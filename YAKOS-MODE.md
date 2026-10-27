# Yako's Mode

Yako's Mode is a version of task-eta made by Nick at Starcks on top of Dino's original. The estimates are
Dino's: the engine in `task_eta.py` is his, touched only to make it faster. Yako's Mode adds a richer TaskETA
menu bar app, two small games, an iPhone widget and a few extra lines in the hooks. Everything still runs
only on your Mac: no account, no telemetry, nothing sent anywhere.

The app speaks English by default and Italian too (see [Language](#language)). The full changelog, version by
version, is in Italian in [YAKO.md](YAKO.md).

## What it adds

**Menu bar and list**
- A coloured box in the menu bar: prompts running, done in the last hour, and the time of the longest one
  (`▶ 3  ✓ 2  ⏱ 12m04s`). Green on time, orange past the estimate, red past the range, a hand when Claude needs you.
- The list opens when the pointer rests on the icon and closes when it leaves; a double click opens the dashboard.
- One row per session, earlier requests folded under it. The overrun is written out ("+10 min over the
  estimate (×6)") and the bar past the estimate is striped. A click on the title opens that chat in the Claude app.

**Desktop panel**
- The same list in a Liquid Glass panel on the desktop that scrolls, and a short version with only the counts
  that blinks green when a task finishes and orange when Claude needs you.

**End of a task**
- A few seconds of animation in the row, one per outcome: fireworks on the estimate, a rocket under the range,
  confetti within it, flames past it ("This is fine"). The menu bar box shows the outcome too. Only the sticker
  with Reduce Motion.

**Dashboard** (double click, or ⌘D)
- A grid of widgets you can move, resize, add and remove: tasks and hours, how often the estimates were right,
  estimate against real time, where the estimates miss (by kind, model and project), hours per day, a heat map
  of days and hours, the history with a link to each chat, "useless stats" such as "Doomscrolling avoided".
- A weekly analysis written by an outside scheduled task that reads only numbers, never prompts (optional).

**Notifications**
- The app's own glass toasts when a task finishes or Claude needs you (macOS refuses system notifications to
  an app signed ad hoc), with the widget in view, always or never. One per session, a ✕ to close it.

**Touch Bar** (Macs that have one)
- A Control Strip button with the most urgent session, and a full bar with one button per session.
- The button puts itself back when the Control Strip drops it (after sleep, the lock screen, a user switch,
  or with no notice at all): cheap checks every second, a re-add at most every 30 s.

**The Mine** (the estimates game, Minecraft style)
- Every task with Claude's estimate is a pickaxe stroke, and what you find says how good the estimate was:
  Diamond (within 5%), Emerald, Gold Ingot, Iron Ingot, Coal, then Cobweb down to Rotten Flesh.
- 9 diamonds make a Block of Diamond; a week with 80% good finds and at least 20 strokes lights Surry's Beacon.
  The pickaxe is the level (wood to diamond), and Claude rates its own estimates at the end of each reply.
- Minecraft's icons are Mojang's, so they are not in the repo: save them yourself in `~/.claude/task-eta/minerali`
  (the names are in YAKO.md); without them you see coloured squares.

**Mini golf** (an easter egg)
- Click the "running" dot 101 times, or drag it holding ⌘ M G, and the list becomes a mini golf course:
  slingshot shots, cushions, par and streaks, a round of 18 holes a day with obstacles, a different twist every
  day (wind, portals, a shy hole…), achievements, and a heat map of your shots.

**The Course** (the level game, in the dashboard)
- A 9-hole map where each hole is a level with its trials and a power to unlock.

**iPhone widget** (optional, off by default)
- A Scriptable widget that shows your sessions on the Home and Lock Screen. The app runs a small server on your
  local network only (port 8765, answering only with its code) and keeps the script in iCloud Drive up to date.

**Hooks**
- The `elapsed` line ends with what the estimate found in the mine ("· Emerald") and says when the next pickaxe
  is ready; `task_eta.py piccone` (or `pickaxe`) shows it, and `piccone su` takes it only when you ask.
- The `[task-eta]` block gets Claude's own score and how this week's estimates compare with the last ones.
  `task_eta.py score off` and `TASK_ETA_MINE=off` turn these off.
- `task_eta.py language` shows or sets the language (below).

## Language

English is the base language; Italian is the second. Pick **Language / Lingua** at the top of Settings
(⌘,): System, English or Italiano. It applies at once, no relaunch. System follows the Mac's first language and
falls back to English.

The choice is saved in `~/.claude/task-eta/language.json`, shared by the app and the hooks, so the end of the
`elapsed` line follows it too. From a terminal:

```bash
python3 task_eta.py language it      # or en, or system
```

The lines the hooks write for Claude stay in English. Every text in the app is `L("English", "Italiano")`
(`widget/Sources/Loc.swift`); the English side keeps its template (`"{1} running"`), so a third language can be
added as a lookup keyed by the English text (the file explains how).

## Build and install

Needs macOS 14+, Python 3.9+ and the Xcode Command Line Tools (`xcode-select --install`). Install task-eta as
in the [README](README.md) (`python3 install.py`), saying yes to the widget, or build the app by hand:

```bash
./widget/build.sh
./widget/build/TaskETA.app/Contents/MacOS/TaskETA --selftest
python3 -m unittest discover -s tests
```

Then quit a running TaskETA, copy `widget/build/TaskETA.app` to `~/Applications` and open it. To preview without
installing, `TaskETA --snapshot out.png --demo` draws the panel and `--dashboard-snapshot out.png` the dashboard;
`TASKETA_LANG=it` or `TASKETA_LANG=en` draws them in that language.
