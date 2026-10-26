// Variables used by Scriptable.
// These must be at the very top of the file. Do not edit.
// icon-color: deep-purple; icon-glyph: stopwatch;

// TaskETA sull'iPhone: le sessioni di Claude Code del Mac, come nel pannello del Mac, lette dal
// Mac stesso sulla stessa Wi-Fi (TaskETA.app > Impostazioni > iPhone). Fuori da quella rete il Mac
// non si raggiunge e il widget mostra gli ultimi dati in grigio. Un solo script per tutte le
// misure: Home piccolo, medio e grande; blocco schermo rotondo, rettangolare e in riga sopra l'ora.
// TaskETA.app scrive qui sotto l'indirizzo e il codice del tuo Mac: non serve toccare altro.

const MAC = "__TASKETA_URL__"       // the Mac's name on the network: follows it when its IP changes
const MAC_IP = "__TASKETA_IP_URL__" // its IP when the script was copied: no name lookup needed
const TOKEN = "__TASKETA_TOKEN__"
// The Mac app's language when it wrote the script ("en" or "it"); English if it was not filled in.
const LANG_SET = "__TASKETA_LANG__"
// The language of the Mac's last answer wins, so a switch on the Mac reaches a script copied by hand too
// (from the next refresh); else the one written here.
const LANG = (() => {
  try {
    const fm = FileManager.local()
    const cache = fm.joinPath(fm.documentsDirectory(), "taskETA-ultimo.json")
    const last = fm.fileExists(cache) ? JSON.parse(fm.readString(cache)).lang : null
    if (last === "it" || last === "en") return last
  } catch (e) {}
  return LANG_SET === "it" ? "it" : "en"
})()
// A text in the script's language: English first, then Italian.
const T = (en, it) => LANG === "it" ? it : en
// The widget gets little time to run: past this the Mac counts as away and the last data shows.
const WAIT_MS = 4000

// The Mac app's bars, light to deep per pace.
const PACE = {
  green: ["#5EE0C4", "#2EBF70"],
  yellow: ["#FFD66B", "#FF9E1C"],
  red: ["#FF8A5C", "#F0386B"],
  grey: ["#A8A8A8", "#737373"],
  neutral: ["#8AB4FF", "#4C7DFF"],
}
// The pace as text: yellow is too light to read on white.
const PACE_TEXT = { green: "#28A745", yellow: "#F28C0D", red: "#F0386B", grey: "#8E8E93", neutral: "#007AFF" }
// Light or dark like the iPhone: every text colour has its dark twin. The bars use colours that
// read on white and on black.
const DARK = {
  "#1D1D1F": "#F5F5F7", "#86868B": "#98989D", "#AEAEB2": "#636366", "#28A745": "#32D74B", "#F28C0D": "#FFB340",
  "#F0386B": "#FF6B81", "#8E8E93": "#98989D", "#007AFF": "#64A0FF", "#FF9500": "#FF9F0A", "#34C759": "#30D158",
}

// The styles: light or dark like the iPhone by default, and three more won with the estimates on
// the Mac (Gems.swift, WidgetTheme). The Mac sends the one picked there with «Usa sull'iPhone» as
// "theme"; a name written in the widget's Parameter field wins over it.
const THEMES = {
  auto: { name: T("Light or dark, like the iPhone", "Chiaro o scuro, come l'iPhone"), mode: "auto" },
  fairway: { name: "Fairway", mode: "dark", bg: ["#1A5E41", "#0F3D2C", "#092A1E"],
    text: ["#F3F7EF", "#A9C7B5", "#6E9583"], running: "#FFD66B" },
  notte: { name: T("Night golf", "Golf di notte"), mode: "dark", bg: ["#18204A", "#0B1026", "#04060E"],
    text: ["#EAF0FF", "#8C96BF", "#545D8C"], running: "#7CF7D4" },
  oro: { name: T("Trophy", "Trofeo"), mode: "light", bg: ["#FFF7D6", "#F4DD8F", "#DDB24C"],
    text: ["#3A2A05", "#77591A", "#A0823C"], running: "#1C8F52" },
}
const THEME_WORDS = { fairway: "fairway", verde: "fairway", green: "fairway", notte: "notte", night: "notte",
  oro: "oro", trofeo: "oro", gold: "oro" }
let THEME = THEMES.auto
let lockedNote = null // a style asked for in the Parameter but not won yet

// A text colour in the style: its dark twin on dark styles, both (by the iPhone's look) on auto.
const tint = (hex, alpha = 1) => THEME.mode === "dark" ? new Color(DARK[hex] || hex, alpha)
  : THEME.mode === "light" ? new Color(hex, alpha)
  : Color.dynamic(new Color(hex, alpha), new Color(DARK[hex] || hex, alpha))
let PRIMARY, SECONDARY, TERTIARY

// The styles won so far, and how to win the others: they come with the data.
const wonOf = (d) => (d && d.themes) || []
const hintsOf = (d) => (d && d.themeHints) || {}

function applyTheme(param, d) {
  const word = String(param || "").trim() || String((d && d.theme) || "")
  const id = THEME_WORDS[word.toLowerCase()]
  const won = wonOf(d)
  const hints = hintsOf(d)
  THEME = id && won.includes(id) ? THEMES[id] : THEMES.auto
  lockedNote = id && !won.includes(id) ? "🔒 " + THEMES[id].name + ": " + (hints[id] || T("not won yet", "ancora da vincere")) : null
  if (THEME.text) [PRIMARY, SECONDARY, TERTIARY] = THEME.text.map((hex) => new Color(hex))
  else [PRIMARY, SECONDARY, TERTIARY] = [tint("#1D1D1F"), tint("#86868B"), tint("#AEAEB2")]
}
applyTheme(null, null)
const GREY = "#8E8E93"
const ORANGE = "#FF9500"
const GREEN = "#34C759"
const WHITE = Color.white()
const dim = (alpha) => new Color("#FFFFFF", alpha)
const ink = (alpha) => new Color("#000000", alpha)

// ---- data

// The Mac turned the token down (a new code): marks the error, whatever else it says.
const WRONG_CODE = T("wrong code", "codice")

// One request to the Mac: the data, or why not.
async function ask(base) {
  const req = new Request(base + "/status")
  req.headers = { Authorization: "Bearer " + TOKEN }
  req.timeoutInterval = WAIT_MS / 1000
  const data = await req.loadJSON()
  const code = req.response && req.response.statusCode
  if (code === 200 && data && data.v === 1) return data
  throw new Error(code === 401 ? WRONG_CODE : T("odd answer (", "risposta strana (") + code + ")")
}

// The IP and the name at once: the first good answer wins, and nothing waits past WAIT_MS.
function firstAnswer(bases) {
  return new Promise((resolve, reject) => {
    if (!bases.length) return reject(new Error(T("the Mac's address is missing: put the script back from Settings",
      "indirizzo del Mac mancante: rimetti lo script dalle impostazioni")))
    let left = bases.length
    const errors = []
    const timer = Timer.schedule(WAIT_MS, false, () => reject(new Error(T("the Mac doesn't answer within ", "il Mac non risponde entro ") + WAIT_MS / 1000 + " s")))
    for (const base of bases) {
      ask(base).then((data) => {
        timer.invalidate()
        resolve(data)
      }, (e) => {
        errors.push(base + ": " + ((e && e.message) || e))
        if (--left === 0) {
          timer.invalidate()
          reject(new Error(errors.join("; ")))
        }
      })
    }
  })
}

// The Mac's token changed: the script must be put back (noData says how).
const CODE_CHANGED = T("Code changed: put the script back", "Codice cambiato: rimetti lo script")

async function load() {
  const fm = FileManager.local()
  const cache = fm.joinPath(fm.documentsDirectory(), "taskETA-ultimo.json")
  let problem = T("Mac offline", "Mac fuori rete")
  let detail = null // the error itself, shown when you run the script in the app
  try {
    const data = await firstAnswer([MAC_IP, MAC].filter((u) => u && !u.includes("__TASKETA")))
    data.at = Date.now()
    fm.writeString(cache, JSON.stringify(data))
    return { data, online: true, problem: null }
  } catch (e) {
    detail = (e && e.message) || String(e)
    if (detail.includes(WRONG_CODE)) problem = CODE_CHANGED
  }
  let old = null
  try {
    old = fm.fileExists(cache) ? JSON.parse(fm.readString(cache)) : null
  } catch (e) {
    old = null
  }
  return { data: old, online: false, problem, detail }
}

// ---- words and numbers, as on the Mac

function clock(seconds) {
  const s = Math.max(0, Math.round(seconds))
  if (s < 60) return s + "s"
  return Math.floor(s / 60) + "m" + String(s % 60).padStart(2, "0") + "s"
}
// A time that does not tick, in the ticking one's look: "4:12", "1:04:12".
function bigClock(seconds) {
  const s = Math.max(0, Math.round(seconds))
  const mm = String(Math.floor((s % 3600) / 60))
  const ss = String(s % 60).padStart(2, "0")
  return s >= 3600 ? Math.floor(s / 3600) + ":" + mm.padStart(2, "0") + ":" + ss : mm + ":" + ss
}
const approx = (seconds) => "~" + Math.max(1, Math.round(seconds / 60)) + " min"
function minuteRange(low, high) {
  const lo = Math.max(1, Math.floor(low / 60))
  const hi = Math.max(lo, Math.ceil(high / 60))
  return lo === hi ? lo + " min" : lo + "-" + hi + " min"
}
const live = (t) => t.state === "running" || t.state === "background"
const over = (t) => !!t.over
// A long title cut before the row does it, so the state on its right always shows whole.
const cut = (s, n) => String(s || "").length > n ? String(s).slice(0, n - 1).trimEnd() + "…" : String(s || "")

function hhmm(ms) {
  const df = new DateFormatter()
  df.useNoDateStyle()
  df.useShortTimeStyle()
  return df.string(new Date(ms))
}

// The bar's right side, as on the Mac: "stima ~2 min (1-3 min)" within the estimate, "stima
// ~2 min" after it; just "~2 min" where room is short.
function estimateText(t, short) {
  if (!t.estimate) return short ? "" : T("no estimate", "senza stima")
  const est = approx(t.estimate)
  if (short) return est
  if (t.state !== "done" && !over(t) && t.low != null && t.high > t.low) return T("est. ", "stima ") + est + " (" + minuteRange(t.low, t.high) + ")"
  return T("est. ", "stima ") + est
}

// The words under the row, as the Mac writes them (none while a task runs within its estimate).
const noteOf = (t) => t.note || null

// The most urgent session first: the one that waits for you, then the ones past their estimate
// (red before yellow), then what runs, what is still, what is done. Same rank, the Mac's order.
const RANK = { waiting: 0, running: 3, background: 4, stale: 5, done: 6 }
const rank = (t) => live(t) && over(t) ? (t.pace === "red" ? 1 : 2) : RANK[t.state] != null ? RANK[t.state] : 6
function urgent(d) {
  return (d.tasks || []).map((t, i) => [t, i]).sort((a, b) => rank(a[0]) - rank(b[0]) || a[1] - b[1]).map((x) => x[0])
}

// "Altre 3: 1 in corso, 2 fatti": what the sessions left out of the widget are doing.
function restText(rest, count = true) {
  const n = (states) => rest.filter((t) => states.includes(t.state)).length
  const parts = []
  if (n(["waiting"])) parts.push(n(["waiting"]) + T(n(["waiting"]) === 1 ? " needs you" : " need you", " ti aspetta"))
  if (n(["running", "background"])) parts.push(n(["running", "background"]) + T(" running", " in corso"))
  if (n(["stale"])) parts.push(n(["stale"]) + T(" stalled", n(["stale"]) === 1 ? " fermo" : " fermi"))
  if (n(["done"])) parts.push(n(["done"]) + T(" done", n(["done"]) === 1 ? " fatto" : " fatti"))
  return (count ? T(rest.length + " more", "Altre " + rest.length) : T("The rest", "Le altre")) + ": " + parts.join(", ")
}

// How many rows fit in `room` points: each row's height, the gap between rows, and the line for
// the others when some stay out. The heights are the rows' on the iPhone (text lines included).
function fitting(list, room, height, gap, footer) {
  let used = 0, n = 0
  for (const t of list) {
    const need = height(t) + (n ? gap : 0)
    const more = n + 1 < list.length ? footer : 0
    if (n && used + need + more > room) break
    used += need
    n++
  }
  return n
}

// The widget's content width on this iPhone, from Apple's widget sizes by screen, so the bars
// reach the edge: 300 (128 on the small) when unsure, since a bar wider than the widget would
// push the layout out.
function contentWidth(family, padding) {
  let size = null
  try {
    if (!Device.isPad()) {
      const s = Device.screenSize()
      const w = Math.min(s.width, s.height), h = Math.max(s.width, s.height)
      size = w > 480 ? null : w >= 428 ? [170, 364] : w >= 414 ? (h >= 890 ? [169, 360] : [159, 348])
        : w >= 390 ? [158, 338] : w >= 375 ? (h >= 800 ? [155, 329] : [148, 321]) : w >= 320 ? [141, 292] : null
    }
  } catch (e) {
    size = null
  }
  if (!size) return family === "small" ? 128 : 300
  return (family === "small" ? size[0] : size[1]) - padding
}

// ---- drawing

function rgb(hex) {
  return [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16))
}
function mix(a, b, t) {
  const [x, y] = [rgb(a), rgb(b)]
  return "#" + x.map((v, i) => Math.round(v + (y[i] - v) * t).toString(16).padStart(2, "0")).join("")
}

function canvas(width, height) {
  const ctx = new DrawContext()
  ctx.size = new Size(width, height)
  ctx.opaque = false
  ctx.respectScreenScale = true
  return ctx
}

// The Mac's bar: grey track, the likely range a shade darker, the elapsed time filled light to
// deep in the pace's colours, stripes past the estimate, light from above, notches at the
// estimate. The capsule comes from the rounded corners of what holds it.
function barImage(t, width, height, mono) {
  const scale = Math.max(t.elapsed * 1.05, (t.high || 0) * 1.15, (t.estimate || 0) * 1.3, 30)
  const x = (s) => Math.min(width, (Math.max(0, s) / scale) * width)
  const fill = Math.min(width, Math.max(height, x(t.elapsed)))
  const ctx = canvas(width, height)
  ctx.setFillColor(mono ? dim(0.18) : new Color(GREY, 0.18))
  ctx.fillRect(new Rect(0, 0, width, height))
  if (t.low != null && t.high != null && t.high > t.low) {
    ctx.setFillColor(mono ? dim(0.12) : new Color(GREY, 0.14))
    ctx.fillRect(new Rect(x(t.low), 0, Math.max(3, x(t.high) - x(t.low)), height))
  }
  const [a, b] = mono ? ["#FFFFFF", "#FFFFFF"] : PACE[t.pace] || PACE.neutral
  // The gradient in bands of 8 points: smooth enough, and few shapes to draw.
  const steps = Math.max(1, Math.ceil(fill / 8))
  for (let i = 0; i < steps; i++) {
    ctx.setFillColor(new Color(mix(a, b, steps === 1 ? 1 : i / (steps - 1)), mono ? 0.45 : 1))
    ctx.fillRect(new Rect((fill / steps) * i, 0, fill / steps + 0.6, height))
  }
  const est = t.estimate ? x(t.estimate) : null
  if (est != null && est < fill - 1) {
    // Diagonal stripes from the estimate to the end of the fill.
    const stripes = new Path()
    for (let x0 = est - height; x0 < fill; x0 += 6) {
      const t0 = Math.max(0, (est - x0) / height)
      const t1 = Math.min(1, (fill - x0) / height)
      if (t1 <= t0) continue
      stripes.move(new Point(x0 + t0 * height, height - t0 * height))
      stripes.addLine(new Point(x0 + t1 * height, height - t1 * height))
    }
    ctx.addPath(stripes)
    ctx.setStrokeColor(t.pace === "yellow" ? ink(0.15) : dim(0.3))
    ctx.setLineWidth(2)
    ctx.strokePath()
  }
  if (!mono) {
    // Light from above, in two bands.
    ctx.setFillColor(dim(0.28))
    ctx.fillRect(new Rect(0, 0, fill, height / 6))
    ctx.setFillColor(dim(0.12))
    ctx.fillRect(new Rect(0, height / 6, fill, height / 6))
  }
  if (est != null) {
    const notch = Math.max(3, height * 0.2)
    const nx = Math.min(width - 1.5, Math.max(0, est - 0.75))
    ctx.setFillColor(mono ? dim(0.9) : new Color(GREY, 0.95))
    ctx.fillRect(new Rect(nx, 0, 1.5, notch))
    ctx.fillRect(new Rect(nx, height - notch, 1.5, notch))
  }
  return { image: ctx.getImage(), fill }
}

// The round lock screen widget's ring: the share of the estimate gone by, full once past it.
function ring(frac, size, line) {
  const ctx = canvas(size, size)
  const c = size / 2
  const rad = c - line / 2
  const circle = new Path()
  circle.addEllipse(new Rect(line / 2, line / 2, size - line, size - line))
  ctx.addPath(circle)
  ctx.setStrokeColor(dim(0.25))
  ctx.setLineWidth(line)
  ctx.strokePath()
  const f = Math.min(Math.max(frac || 0, 0), 1)
  if (f > 0) {
    const n = Math.max(2, Math.ceil(60 * f))
    const points = []
    for (let i = 0; i <= n; i++) {
      const angle = -Math.PI / 2 + 2 * Math.PI * f * (i / n)
      points.push(new Point(c + rad * Math.cos(angle), c + rad * Math.sin(angle)))
    }
    const arc = new Path()
    arc.addLines(points)
    ctx.addPath(arc)
    ctx.setStrokeColor(WHITE)
    ctx.setLineWidth(line)
    ctx.strokePath()
    ctx.setFillColor(WHITE)
    for (const p of [points[0], points[points.length - 1]]) {
      ctx.fillEllipse(new Rect(p.x - line / 2, p.y - line / 2, line, line))
    }
  }
  return ctx.getImage()
}

// ---- building blocks

const FONTS = {
  regular: (s) => Font.regularRoundedSystemFont(s),
  medium: (s) => Font.mediumRoundedSystemFont(s),
  semibold: (s) => Font.semiboldRoundedSystemFont(s),
  bold: (s) => Font.boldRoundedSystemFont(s),
  title: (s) => Font.mediumSystemFont(s),
}

function text(stack, s, size, o = {}) {
  const t = stack.addText(String(s))
  t.font = FONTS[o.weight || "medium"](size)
  t.textColor = o.color || PRIMARY
  if (o.alpha != null) t.textOpacity = o.alpha
  t.lineLimit = o.lines || 1
  t.minimumScaleFactor = o.scale || 0.8
  return t
}

// A horizontal row, its content vertically centred.
function hrow(parent, spacing = 0) {
  const r = parent.addStack()
  r.layoutHorizontally()
  r.centerAlignContent()
  r.spacing = spacing
  return r
}

function symbol(stack, name, size, color) {
  const sym = SFSymbol.named(name)
  sym.applyFont(Font.semiboldSystemFont(size))
  const img = stack.addImage(sym.image)
  img.imageSize = new Size(size, size)
  img.tintColor = tint(color)
  return img
}

const BADGE = {
  running: ["circle.fill", T("running", "in corso"), GREEN],
  waiting: ["hand.raised.fill", T("needs you", "ti aspetta"), ORANGE],
  background: ["hourglass", "in background", GREY],
  stale: ["pause.circle", T("stalled", "fermo"), GREY],
  done: ["checkmark", T("done", "fatto"), GREY],
}

// The state on the right of the title: "● in corso", "✋ ti aspetta"…
function badge(stack, t, size) {
  const [name, label, own] = BADGE[t.state] || BADGE.running
  const color = t.state === "running" && THEME.running ? THEME.running : own
  const b = hrow(stack, 3)
  symbol(b, name, size - 2, color)
  text(b, label, size, { weight: "semibold", color: tint(color) })
}

// The bar with its times inside: the elapsed time on the left (ticking by itself while the task
// runs and the Mac answers), the estimate on the right, each dark over the track and light over
// the fill.
function bar(parent, t, d, online, width, height, o = {}) {
  const { image, fill } = barImage(t, width, height, false)
  const s = parent.addStack()
  s.size = new Size(width, height)
  s.backgroundImage = image
  s.cornerRadius = height / 2
  s.layoutHorizontally()
  s.centerAlignContent()
  s.setPadding(0, 8, 0, 8)
  const size = Math.min(12, Math.max(9.5, height * 0.68))
  const lightInk = t.pace === "yellow" ? ink(0.78) : WHITE
  const color = (x) => (fill >= x ? lightInk : PRIMARY)
  if (online && live(t)) {
    const date = s.addDate(new Date(d.at - t.elapsed * 1000))
    date.applyTimerStyle()
    date.font = Font.semiboldRoundedSystemFont(size)
    date.textColor = color(52)
    date.lineLimit = 1
  } else {
    const lead = t.state === "done" && !o.short ? T("actual ", "reale ") + clock(t.elapsed) : clock(t.elapsed)
    text(s, lead, size, { weight: "semibold", color: color(lead.length * 6.5 + 10) })
    s.addSpacer()
  }
  const right = estimateText(t, o.short)
  if (right) text(s, right, size, { weight: "medium", color: color(width - right.length * 6 - 10) })
}

// The orange card of the session that waits for you; the width left inside it.
function card(parent, t, width, pad) {
  const c = parent.addStack()
  c.layoutVertically()
  c.spacing = 2
  if (t.state !== "waiting") return [c, width]
  c.backgroundColor = new Color(ORANGE, 0.1)
  c.borderColor = new Color(ORANGE, 0.35)
  c.borderWidth = 1
  c.cornerRadius = pad + 4
  c.setPadding(pad - 3, pad, pad - 2, pad)
  return [c, width - 2 * pad]
}

// A session as a row of the Mac's panel: title and state, the bar with the times inside, folder
// and model with the note. The one that waits for you on an orange card.
function row(parent, t, d, online, width) {
  const [c, inner] = card(parent, t, width, 8)
  const top = hrow(c)
  text(top, cut(t.name, t.state === "waiting" ? 32 : 38), 12.5, { weight: "title", alpha: t.state === "done" || t.state === "stale" ? 0.8 : 1 })
  top.addSpacer(6)
  badge(top, t, 10.5)
  bar(c, t, d, online, inner, 14)
  const foot = hrow(c, 5)
  text(foot, t.folder, 10, { color: SECONDARY })
  if (t.model) text(foot, t.model, 10, { color: TERTIARY })
  foot.addSpacer()
  const note = noteOf(t)
  if (!note) return
  const flagged = over(t) && t.state !== "stale" && t.state !== "done"
  const color = t.state === "waiting" ? ORANGE : flagged ? PACE_TEXT[t.pace] || PACE_TEXT.neutral : "#86868B"
  const pill = foot.addStack()
  if (flagged) {
    pill.backgroundColor = tint(color, 0.14)
    pill.cornerRadius = 6
    pill.setPadding(0, 5, 0, 5)
  }
  text(pill, note, 10, { weight: flagged || t.state === "waiting" ? "semibold" : "regular", color: tint(color) })
}

// A session in two lines for the medium: the title with what matters on its right (what it
// waits for, how far past the estimate, else the state), then the bar.
function compactRow(parent, t, d, online, width) {
  const [c, inner] = card(parent, t, width, 7)
  const top = hrow(c)
  text(top, cut(t.name, t.state === "waiting" ? 28 : 36), 12.5, { weight: "title", alpha: t.state === "done" || t.state === "stale" ? 0.8 : 1 })
  top.addSpacer(6)
  if (t.state === "waiting") {
    const r = hrow(top, 3)
    symbol(r, "hand.raised.fill", 9, ORANGE)
    text(r, noteOf(t) || T("needs you", "ti aspetta"), 10.5, { weight: "semibold", color: tint(ORANGE) })
  } else if (live(t) && over(t)) {
    text(top, t.over, 10.5, { weight: "semibold", color: tint(PACE_TEXT[t.pace] || PACE_TEXT.neutral) })
  } else {
    badge(top, t, 10.5)
  }
  bar(c, t, d, online, inner, 15)
}

// "⏱ Claude Code" on the left, the counts on the right, as at the top of the Mac's list.
function header(w, d, online, problem) {
  const h = hrow(w, 5)
  symbol(h, "timer", 12, "#86868B")
  text(h, "Claude Code", 12.5, { weight: "semibold", color: SECONDARY })
  h.addSpacer()
  if (!d) return text(h, problem, 11, { color: SECONDARY })
  if (!online) return text(h, T("offline since ", "fuori rete dalle ") + hhmm(d.at), 11, { weight: "semibold", color: SECONDARY })
  const parts = []
  if (d.waiting) parts.push([d.waiting + T(d.waiting === 1 ? " needs you" : " need you", " ti aspetta"), tint(ORANGE)])
  if (d.running || !d.done) parts.push([d.running + T(" running", " in corso"), SECONDARY])
  if (d.done) parts.push([d.done === 1 ? T("1 done", "1 fatto") : d.done + T(" done", " fatti"), SECONDARY])
  parts.forEach(([label, color], i) => text(h, label + (i < parts.length - 1 ? "," : ""), 11.5, { weight: "semibold", color }))
}

function empty(w, size) {
  w.addSpacer()
  text(w, T("No sessions in the last hour: as soon as Claude works on the Mac, it shows up here.",
    "Nessuna sessione nell'ultima ora: appena Claude lavora sul Mac, compare qui."), size, { color: TERTIARY, lines: 3 })
  w.addSpacer()
}

// Nothing to show yet: what is wrong, and how to put it right.
function noData(w, problem) {
  const code = problem === CODE_CHANGED
  text(w, "TaskETA", 13, { weight: "semibold", color: SECONDARY })
  w.addSpacer(4)
  text(w, problem || T("Mac offline", "Mac fuori rete"), 13, { weight: "semibold", lines: 3 })
  w.addSpacer()
  text(w, code ? T("TaskETA on the Mac puts the script back in iCloud Drive by itself, within a minute.",
    "TaskETA sul Mac rimette lo script in iCloud Drive da solo, entro un minuto.")
    : T("The Mac answers on the same Wi-Fi, with TaskETA > Settings > iPhone on.",
      "Il Mac risponde sulla stessa Wi-Fi, con TaskETA > Impostazioni > iPhone acceso."), 10.5, { color: TERTIARY, lines: 3 })
}

function background(w, online) {
  const g = new LinearGradient()
  if (THEME.bg) {
    g.colors = THEME.bg.map((hex) => new Color(hex, online ? 1 : 0.82))
    g.locations = [0, 0.5, 1]
    g.startPoint = new Point(0, 0)
    g.endPoint = new Point(1, 1)
    w.backgroundGradient = g
    return
  }
  const pair = (light, dark) => Color.dynamic(new Color(light), new Color(dark))
  g.colors = online ? [pair("#FFFFFF", "#1C1C1E"), pair("#F2F2F5", "#121214")]
    : [pair("#F4F4F6", "#19191B"), pair("#E6E6EA", "#0F0F11")]
  g.locations = [0, 1]
  g.startPoint = new Point(0, 0)
  g.endPoint = new Point(0, 1)
  w.backgroundGradient = g
}

// ---- the sizes

const LAYOUT = {
  // The most urgent session, and how many others there are.
  small(w, d, online, problem) {
    w.setPadding(12, 12, 12, 12)
    background(w, online)
    if (!d) return noData(w, problem)
    const list = urgent(d)
    const t = list[0]
    const top = hrow(w, 5)
    if (!online) text(top, T("offline since ", "fuori rete dalle ") + hhmm(d.at), 10.5, { weight: "semibold", color: SECONDARY })
    else if (t) badge(top, t, 11)
    else text(top, "Claude Code", 11, { weight: "semibold", color: SECONDARY })
    top.addSpacer()
    if (list.length > 1) text(top, "+" + (list.length - 1), 11, { weight: "semibold", color: TERTIARY })
    if (!t) return empty(w, 11.5)
    w.addSpacer()
    text(w, t.name, 13, { weight: "title", lines: 2 })
    w.addSpacer(6)
    bar(w, t, d, online, contentWidth("small", 24), 18, { short: true })
    w.addSpacer(5)
    const note = noteOf(t)
    const flagged = t.state === "waiting" || (over(t) && live(t))
    const color = t.state === "waiting" ? tint(ORANGE) : flagged ? tint(PACE_TEXT[t.pace] || PACE_TEXT.neutral) : SECONDARY
    // What matters first: what it waits for, how far past; else the folder, and when it ended.
    const line = flagged && note ? note : t.folder + (note && !live(t) ? ", " + note : "")
    text(w, line, 10.5, { weight: flagged ? "semibold" : "medium", color, lines: 2 })
    if (list.length > 1) text(w, restText(list.slice(1), false), 9.5, { color: TERTIARY, lines: 2 })
  },

  // Up to three sessions as two-line rows: the title and the bar.
  medium(w, d, online, problem) {
    w.setPadding(12, 14, 12, 14)
    background(w, online)
    if (!d) return noData(w, problem)
    const list = d.tasks || []
    if (!list.length) {
      header(w, d, online, problem)
      return empty(w, 12)
    }
    const width = contentWidth("medium", 28)
    // Two or three rows: as many as fit over the line for the others (or for the Mac away).
    const room = fitting(list, 134 - (online ? 0 : 15) - (lockedNote ? 12 : 0),
      (t) => t.state === "waiting" ? 42 : 33, 5, 15)
    list.slice(0, room).forEach((t, i) => {
      if (i) w.addSpacer(5)
      compactRow(w, t, d, online, width)
    })
    w.addSpacer()
    if (!online) text(w, T("Mac offline since ", "Mac fuori rete dalle ") + hhmm(d.at) + T(": data from then", ": dati di allora"), 10.5, { color: TERTIARY })
    else if (list.length > room) text(w, restText(list.slice(room)), 10.5, { color: TERTIARY })
  },

  // As many full rows as fit, as in the Mac's panel, under the counts.
  large(w, d, online, problem) {
    w.setPadding(15, 16, 14, 16)
    background(w, online)
    header(w, d, online, problem)
    if (!d) return
    const list = d.tasks || []
    if (!list.length) return empty(w, 12)
    w.addSpacer(8)
    const width = contentWidth("large", 32)
    // Five or six rows under the counts: as many as fit, the one that waits for you on its card.
    const shown = fitting(list, 302 - (lockedNote ? 14 : 0), (t) => t.state === "waiting" ? 56 : 45, 6, 19)
    list.slice(0, shown).forEach((t, i) => {
      if (i) w.addSpacer(6)
      row(w, t, d, online, width)
    })
    w.addSpacer()
    if (shown < list.length) text(w, restText(list.slice(shown)), 10.5, { color: TERTIARY })
  },

  // Lock screen: iOS draws it in one colour over your wallpaper, and the folder stands in for
  // the prompt, in view of anyone near.
  accessoryCircular(w, d, online) {
    w.addAccessoryWidgetBackground = true
    const t = d && online ? urgent(d)[0] : null
    let frac = 0, big, small
    if (!d || !online) [big, small] = ["–", T("offline", "fuori rete")]
    else if (t && t.state === "waiting") [big, small] = ["✋", T("needs you", "ti aspetta")]
    else if (t && live(t)) {
      frac = t.estimate ? t.elapsed / t.estimate : 0
      big = Math.floor(t.elapsed / 60) + "m"
      small = t.estimate ? T("of ", "su ") + Math.max(1, Math.round(t.estimate / 60)) + "m" : T("running", "in corso")
    } else if (t) [big, small] = [String(d.done || 0), T("done", d.done === 1 ? "fatto" : "fatti")]
    else [big, small] = ["0", T("running", "in corso")]
    w.backgroundImage = ring(frac, 76, 6)
    w.addSpacer()
    text(w, big, 17, { weight: "bold", color: WHITE, scale: 0.6 }).centerAlignText()
    text(w, small, 9, { weight: "semibold", color: WHITE, alpha: 0.8, scale: 0.6 }).centerAlignText()
    w.addSpacer()
  },

  // The time first, big: the most urgent session's clock (ticking by itself while it runs).
  accessoryRectangular(w, d, online, problem) {
    const white = { color: WHITE }
    const t = d && urgent(d)[0]
    if (!d || !t) {
      text(w, "Claude Code", 13, { ...white, weight: "semibold" })
      text(w, !d ? problem : online ? T("No sessions in the last hour", "Nessuna sessione nell'ultima ora") : T("Mac offline", "Mac fuori rete"),
        12, { ...white, alpha: 0.85, lines: 2 })
      return
    }
    const top = w.addStack()
    top.layoutHorizontally()
    top.bottomAlignContent()
    if (online && live(t)) {
      const date = top.addDate(new Date(d.at - t.elapsed * 1000))
      date.applyTimerStyle()
      date.font = Font.boldRoundedSystemFont(24)
      date.textColor = WHITE
      date.lineLimit = 1
      date.minimumScaleFactor = 0.7
    } else {
      text(top, bigClock(t.elapsed), 24, { ...white, weight: "bold", scale: 0.7 })
      top.addSpacer(6)
      if (t.state === "waiting") text(top, "✋", 13, white)
      top.addSpacer()
    }
    // What it is against the estimate first, the folder after: a long folder name gets cut, not that.
    const state = t.state === "waiting" ? T("needs you", "ti aspetta")
      : live(t) ? (t.estimate ? T("est. ", "stima ") + approx(t.estimate) : T("no estimate", "senza stima"))
      : t.state === "done" ? T("done", "fatto") : T("stalled", "fermo")
    const others = (d.tasks || []).length - 1
    text(w, state + ", " + t.folder + (others > 0 ? ", +" + others : ""), 12, { ...white, alpha: 0.85 })
    w.addSpacer(3)
    const note = noteOf(t)
    if (!online) text(w, T("offline, data from ", "fuori rete, dato delle ") + hhmm(d.at), 11, { ...white, alpha: 0.6 })
    else if (note && (t.state === "waiting" || (over(t) && live(t)) || t.state === "done")) {
      text(w, note, 11, { ...white, weight: "semibold", alpha: t.state === "done" ? 0.75 : 1 })
    } else if (t.estimate) {
      const i = w.addImage(barImage(t, 150, 5, true).image)
      i.imageSize = new Size(150, 5)
      i.cornerRadius = 2.5
    }
  },

  accessoryInline(w, d, online, problem) {
    let s
    const t = d && online ? urgent(d)[0] : null
    if (!d) s = "TaskETA, " + String(problem || T("Mac offline", "Mac fuori rete")).toLowerCase()
    else if (!online) s = T("TaskETA, Mac offline", "TaskETA, Mac fuori rete")
    else if (!t) s = T("No sessions in the last hour", "Nessuna sessione nell'ultima ora")
    else if (t.state === "waiting") s = t.folder + T(" needs you", " ti aspetta")
    else if (live(t)) s = clock(t.elapsed) + (t.estimate ? T(" of ", " su ") + approx(t.estimate) : "") + ", " + t.folder
    else s = (t.state === "done" ? T("Done in ", "Fatto in ") : T("Stalled, ", "Fermo, ")) + clock(t.elapsed) + ", " + t.folder
    w.addText(s)
  },
}

function widgetFor(family, d, online, problem, theme) {
  applyTheme(theme !== undefined ? theme : args.widgetParameter, d)
  const w = new ListWidget()
  ;(LAYOUT[family] || LAYOUT.medium)(w, d, online, problem)
  if (lockedNote && !String(family).startsWith("accessory")) {
    w.addSpacer(2)
    text(w, lockedNote, 9.5, { color: SECONDARY })
  }
  // Sooner while something runs or waits; iOS decides in the end (often every 15 minutes or so).
  const minutes = d && online && (d.running || d.waiting) ? 1 : online ? 10 : 15
  w.refreshAfterDate = new Date(Date.now() + minutes * 60 * 1000)
  return w
}

// ---- run

async function main() {

  const { data, online, problem, detail } = await load()

  if (config.runsInWidget || config.runsInAccessoryWidget) {
    Script.setWidget(widgetFor(config.widgetFamily, data, online, problem))
    return
  }
  // In the app: a preview of each size, and whether the Mac answers.
  const sizes = [
    [T("Home small", "Home piccolo"), "small", "presentSmall"],
    [T("Home medium", "Home medio"), "medium", "presentMedium"],
    [T("Home large", "Home grande"), "large", "presentLarge"],
    [T("Lock screen round", "Blocco schermo rotondo"), "accessoryCircular", "presentAccessoryCircular"],
    [T("Lock screen rectangular", "Blocco schermo rettangolare"), "accessoryRectangular", "presentAccessoryRectangular"],
    [T("Lock screen inline", "Blocco schermo in riga"), "accessoryInline", "presentAccessoryInline"],
  ]
  const alert = new Alert()
  alert.title = "TaskETA"
  alert.message = online ? T("Connected to ", "Collegato a ") + data.mac + "."
    : problem + "." + T("\n\nAddress: ", "\n\nIndirizzo: ") + MAC + (detail ? T("\nError: ", "\nErrore: ") + detail : "")
  const won = wonOf(data)
  const hints = hintsOf(data)
  const styles = ["fairway", "notte", "oro"]
  alert.message += T("\n\nStyles: ", "\n\nStili: ") + styles.map((id) => THEMES[id].name + (won.includes(id)
    ? T(" ✓ (pick it on the Mac: Analytics, “iPhone styles”)", " ✓ (sceglilo sul Mac: Analytics, «Stili iPhone»)")
    : " 🔒 " + (hints[id] || ""))).join("; ") + "."
  for (const [label] of sizes) alert.addAction(label)
  for (const id of styles) alert.addAction(T("Style ", "Stile ") + THEMES[id].name + (won.includes(id) ? "" : " 🔒") + T(", Home medium", ", Home medio"))
  alert.addCancelAction(T("Close", "Chiudi"))
  const pick = await alert.presentSheet()
  if (pick >= 0 && pick < sizes.length) {
    const [, family, present] = sizes[pick]
    const w = widgetFor(family, data, online, problem, null)
    await (typeof w[present] === "function" ? w[present]() : w.presentSmall())
  } else if (pick >= sizes.length && pick < sizes.length + styles.length) {
    // A preview of the style even before it is won: the widget itself waits for the unlock.
    const id = styles[pick - sizes.length]
    await widgetFor("medium", data ? { ...data, themes: [...won, id] } : data, online, problem, id).presentMedium()
  }
}

// Anything that goes wrong shows up on the widget (or in an alert in the app) with its line,
// instead of a blank widget.
try {
  await main()
} catch (e) {
  const what = ((e && e.message) || String(e)) + (e && e.line ? T(" (line ", " (riga ") + e.line + ")" : "")
  if (config.runsInWidget || config.runsInAccessoryWidget) {
    const w = new ListWidget()
    w.backgroundColor = Color.dynamic(Color.white(), new Color("#1C1C1E"))
    const title = w.addText(T("TaskETA: script error", "TaskETA: errore nello script"))
    title.font = Font.boldSystemFont(13)
    title.textColor = new Color("#F0386B")
    const detail = w.addText(what)
    detail.font = Font.systemFont(11)
    detail.textColor = Color.dynamic(new Color("#1D1D1F"), new Color("#F5F5F7"))
    detail.minimumScaleFactor = 0.6
    Script.setWidget(w)
  } else {
    const alert = new Alert()
    alert.title = T("TaskETA: script error", "TaskETA: errore nello script")
    alert.message = what
    alert.addAction("OK")
    await alert.present()
  }
}
Script.complete()
