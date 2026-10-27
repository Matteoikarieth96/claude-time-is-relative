import AppKit
import SwiftUI

extension Pace {
    var nsColor: NSColor {
        switch self {
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .red: return .systemRed
        case .grey: return .systemGray
        case .neutral: return .controlAccentColor
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// The bar's fill: a lighter tone on the left that deepens towards the elapsed time.
    var gradient: LinearGradient {
        let pair: (Color, Color)
        switch self {
        case .green: pair = (Color(red: 0.37, green: 0.88, blue: 0.77), Color(red: 0.18, green: 0.75, blue: 0.44))
        case .yellow: pair = (Color(red: 1.00, green: 0.84, blue: 0.42), Color(red: 1.00, green: 0.62, blue: 0.11))
        case .red: pair = (Color(red: 1.00, green: 0.54, blue: 0.36), Color(red: 0.94, green: 0.22, blue: 0.42))
        case .grey: pair = (Color(white: 0.66), Color(white: 0.45))
        case .neutral: pair = (Color.accentColor.opacity(0.55), Color.accentColor)
        }
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .leading, endPoint: .trailing)
    }

    /// Text on the coloured part of the bar.
    var ink: Color { self == .yellow ? Color.black.opacity(0.78) : .white }

    /// The pace as text on the glass: yellow is too light to read there.
    var textColor: Color { self == .yellow ? Color(red: 0.95, green: 0.55, blue: 0.05) : color }
}

extension Font {
    /// Times: the rounded face of the system font, digits of equal width so the clock does not jump.
    static func timer(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// Fill = elapsed time, tick = estimate, lighter band = likely range, stripes = the part past the
/// estimate. The times are written inside the bar: elapsed (or real) on the left, estimate on the right.
struct BarView: View {
    let elapsed: Double
    let estimate: Double?
    let range: (low: Double, high: Double)?
    let pace: Pace
    var leading = ""
    var trailing = ""
    var height: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let scale = barScale(elapsed: elapsed, estimate: estimate, high: range?.high)
            let x = { (v: Double) -> CGFloat in v.isFinite ? CGFloat(min(max(v, 0) / scale, 1)) * w : 0 }
            let fill = min(w, max(height, x(elapsed)))
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.07))
                if let r = range {
                    Rectangle().fill(Color.primary.opacity(0.09))
                        .frame(width: max(3, x(r.high) - x(r.low)))
                        .offset(x: x(r.low))
                }
                Rectangle().fill(pace.gradient).frame(width: fill)
                if let est = estimate, x(est) < fill - 1 {
                    Stripes(color: pace.ink.opacity(0.2))
                        .frame(width: fill - x(est))
                        .offset(x: x(est))
                }
                // Light from above, as on glass.
                LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0)],
                               startPoint: .top, endPoint: .center)
                    .frame(width: fill)
                if let est = estimate {
                    // With times in the bar, only notches at the top and bottom: the tick never
                    // crosses the text.
                    let notch = leading.isEmpty && trailing.isEmpty ? height : max(3, height * 0.2)
                    VStack(spacing: 0) {
                        Rectangle().frame(height: notch)
                        Spacer(minLength: 0)
                        Rectangle().frame(height: notch)
                    }
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .frame(width: 1.5)
                    .offset(x: min(max(0, x(est) - 0.75), w - 1.5))
                }
                if !leading.isEmpty || !trailing.isEmpty {
                    // The same text twice: dark over the empty track, light over the fill.
                    labels.foregroundStyle(Color.primary)
                        .mask(HStack(spacing: 0) { Color.clear.frame(width: fill); Color.black })
                    labels.foregroundStyle(pace.ink)
                        .mask(HStack(spacing: 0) { Color.black.frame(width: fill); Color.clear })
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.04)],
                               startPoint: .top, endPoint: .bottom), lineWidth: 0.5))
        }
        .frame(height: height)
    }

    private var labels: some View {
        HStack(spacing: 6) {
            Text(leading).font(.timer(10.5))
            Spacer(minLength: 4)
            Text(trailing).font(.timer(10.5, .medium))
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Diagonal stripes over the part of the bar past the estimate.
struct Stripes: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 6
            }
            ctx.stroke(path, with: .color(color), lineWidth: 2)
        }
        .clipped()
    }
}

struct StateBadge: View {
    let item: TaskItem
    var dotClicks = 0
    var dotRun: Int? = nil
    var onDot: ((Double) -> Void)? = nil
    var onUnlock: (() -> Void)? = nil
    @Environment(\.golf) private var golf

    var body: some View {
        Group {
            switch item.state {
            case .waiting:
                Label(L("needs you", "ti aspetta"), systemImage: "hand.raised.fill").foregroundStyle(Color.orange)
            case .running:
                // The dot is an easter egg (see DotFeedback.swift and TaskStore.tapDot).
                RunningDot(dotClicks: dotClicks, onDot: onDot, golf: golf, onUnlock: onUnlock, run: dotRun)
            case .background:
                Label(L("in background", "in background"), systemImage: "hourglass").foregroundStyle(Color.secondary)
            case .stale:
                Label(L("stalled", "fermo"), systemImage: "pause.circle").foregroundStyle(Color.secondary)
            case .done:
                Label(L("done", "fatto"), systemImage: "checkmark").foregroundStyle(Color.secondary)
            }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .labelStyle(BadgeLabelStyle())
        .fixedSize()
    }
}

struct BadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// "fatto" on a finished section: a click takes the section off the list.
struct DoneButton: View {
    var stale = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: hover ? "xmark" : (stale ? "pause.circle" : "checkmark")).imageScale(.small)
            Text(hover ? L("remove", "togli") : (stale ? L("stalled", "fermo") : L("done", "fatto")))
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(hover ? Color.primary : Color.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(hover ? 0.13 : 0.06)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
        .contentShape(Capsule())
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
        .help(L("Remove from the list", "Togli dalla lista"))
        .accessibilityAddTraits(.isButton)
        .fixedSize()
        .reportsClickFrame()
    }
}

/// The row's title. When the session is one of the Claude app's, a click opens its chat.
struct TitleLink: View {
    let text: String
    let url: URL?
    var help = ""
    @State private var hover = false

    var body: some View {
        let label = HStack(spacing: 3) {
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .underline(hover && url != nil, color: .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if url != nil {
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hover ? .secondary : .tertiary)
            }
        }
        if let url {
            label
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .onTapGesture { openChat(url) }
                .help(help.isEmpty ? L("Open the chat", "Apri la chat") : L("Open the chat\n\(help)", "Apri la chat\n\(help)"))
                .accessibilityAddTraits(.isLink)
                .reportsClickFrame()
        } else {
            label.help(help)
        }
    }
}

struct TaskRow: View {
    let item: TaskItem
    let now: Double
    var hidePrompts = false
    var onClose: (() -> Void)? = nil
    var dotClicks = 0
    var dotRun: Int? = nil
    var onDot: ((Double) -> Void)? = nil
    var onUnlock: (() -> Void)? = nil
    /// The mine's finds on the ground of their rows (Drops.swift).
    @ObservedObject private var drops = DropStore.shared

    var body: some View {
        let elapsed = item.elapsed(at: now)
        let pace = item.pace(at: now)
        let over = item.overrun(at: now) != nil
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TitleLink(text: item.shownName(hidePrompts: hidePrompts), url: item.chatURL,
                          help: hidePrompts ? "" : item.data.prompt.map { L("Last prompt: \($0)", "Ultimo prompt: \($0)") } ?? "")
                Spacer(minLength: 4)
                if let onClose, item.state == .done || item.state == .stale {
                    if let drop = drops.drops[item.key] {
                        DroppedItem(drop: drop) {
                            drops.remove(item.key)
                            onClose()
                        }
                    } else {
                        DoneButton(stale: item.state == .stale, action: onClose)
                    }
                } else {
                    StateBadge(item: item, dotClicks: dotClicks, dotRun: dotRun, onDot: onDot, onUnlock: onUnlock)
                }
            }
            BarView(elapsed: elapsed, estimate: item.estimate, range: item.range, pace: pace,
                    leading: leading(elapsed), trailing: trailing(over: over))
            HStack(spacing: 5) {
                Text(item.folderText)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                Text(item.modelText)
                    .foregroundStyle(.tertiary)
                    .help(item.data.modelKnown == false
                          ? L("Model guessed: the session had not replied yet", "Modello presunto: la sessione non aveva ancora risposto") : "")
                Spacer(minLength: 4)
                if let note = note {
                    let flagged = over && item.state != .stale
                    Text(note)
                        .fontWeight(flagged || item.state == .waiting ? .medium : .regular)
                        .foregroundStyle(noteColor(pace: pace, over: over))
                        .truncationMode(.tail)
                        // The overrun on a light pill: red and orange stay readable on any glass.
                        .padding(.horizontal, flagged ? 6 : 0)
                        .padding(.vertical, flagged ? 1 : 0)
                        .background {
                            if flagged { Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.75)) }
                        }
                        .layoutPriority(1)
                        .help(note)
                }
            }
            .font(.system(size: 10))
            .lineLimit(1)
        }
        .opacity(item.state == .done || item.state == .stale ? 0.82 : 1)
    }

    private func leading(_ elapsed: Double) -> String {
        item.state == .done ? L("actual \(clock(elapsed))", "reale \(clock(elapsed))") : clock(elapsed)
    }

    /// The range only while the task is within its estimate: past it, the stripes tell the story.
    private func trailing(over: Bool) -> String {
        guard let est = item.estimateText else { return L("no estimate", "senza stima") }
        if item.state != .done, !over, let r = item.rangeText { return L("est. \(est) (\(r))", "stima \(est) (\(r))") }
        return L("est. \(est)", "stima \(est)")
    }

    private var note: String? {
        switch item.state {
        case .waiting:
            return item.waitingText(hidePrompts: hidePrompts)
        case .running:
            return item.overrunText(at: now)
        case .background:
            if let over = item.overrunText(at: now) { return over }
            let jobs = item.data.bgJobs ?? []
            guard !hidePrompts, let first = jobs.first, !first.isEmpty else { return L("background jobs", "job in background") }
            return jobs.count == 1 ? first : L("\(jobs.count) jobs: \(first)…", "\(jobs.count) job: \(first)…")
        case .stale:
            return L("stalled for \(clock(item.quiet ?? 0))", "fermo da \(clock(item.quiet ?? 0))")
        case .done:
            let end = Date(timeIntervalSince1970: item.data.endTs ?? item.data.startTs)
            let time = end.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Loc.locale))
            let at = L("at \(time)", "alle \(time)")
            return item.overrunText(at: now, short: true).map { "\($0), \(at)" } ?? at
        }
    }

    private func noteColor(pace: Pace, over: Bool) -> Color {
        if item.state == .waiting { return .orange }
        if over && item.state != .stale { return pace.textColor }
        return .secondary
    }
}

/// An earlier request of the session: its prompt, its times and a thin bar.
struct CompactRow: View {
    let item: TaskItem
    let now: Double
    var hidePrompts = false

    var body: some View {
        let elapsed = item.elapsed(at: now)
        let pace = item.pace(at: now)
        let over = item.overrunText(at: now, short: true)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(hidePrompts ? L("Earlier request", "Richiesta precedente") : (item.data.prompt ?? "…"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(hidePrompts ? "" : item.data.prompt ?? "")
                Spacer(minLength: 4)
                Text(times(elapsed, over: over))
                    .font(.timer(10, .medium))
                    .foregroundStyle(over == nil ? Color.secondary : pace.textColor)
                    .fixedSize()
            }
            BarView(elapsed: elapsed, estimate: item.estimate, range: item.range, pace: pace, height: 5)
        }
    }

    private func times(_ elapsed: Double, over: String?) -> String {
        let base = item.estimateText.map { L("\(clock(elapsed)) of \($0)", "\(clock(elapsed)) su \($0)") } ?? clock(elapsed)
        return over.map { "\(base)  \($0)" } ?? base
    }
}

/// A session: its current (or latest) task, and its earlier requests on demand.
struct GroupView: View {
    @ObservedObject var store: TaskStore
    let group: TaskGroup

    var body: some View {
        let open = store.expanded.contains(group.id)
        let waiting = group.main.state == .waiting
        VStack(alignment: .leading, spacing: 7) {
            TaskRow(item: group.main, now: store.now, hidePrompts: store.hidePrompts,
                    onClose: group.closable ? close : nil, dotClicks: store.dotClicks, dotRun: store.dotRun,
                    onDot: { store.tapDot(held: $0) }, onUnlock: { store.unlockGolf(by: "tasti") })
                .overlay {
                    // In the mine the find drops into the row instead (Drops.swift).
                    if let celebration = store.celebrations[group.main.key], !(GameMood.current == .miniera && celebration.ore != nil) {
                        CelebrationView(celebration: celebration).padding(-6)
                    }
                }
                .onAppear { dropFind() }
                .onChange(of: store.celebrations[group.main.key]?.start) { _, _ in dropFind() }
            if !group.earlier.isEmpty {
                TextButton(title: earlierTitle(open), systemImage: open ? "chevron.down" : "chevron.right",
                           color: .secondary) {
                    withAnimation(.snappy(duration: 0.22)) {
                        if open { store.expanded.remove(group.id) } else { store.expanded.insert(group.id) }
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                if open {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(group.earlier) { item in
                            CompactRow(item: item, now: store.now, hidePrompts: store.hidePrompts)
                        }
                    }
                    .padding(.leading, 10)
                    // A thread line: these requests belong to the session above.
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12)).frame(width: 1.5)
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(waiting ? 9 : 0)
        .background {
            if waiting {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                shape.fill(LinearGradient(colors: [Color.orange.opacity(0.20), Color.orange.opacity(0.07)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(shape.strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.6))
            }
        }
    }

    /// A task just finished, in the mine: its find falls into the row.
    private func dropFind() {
        guard GameMood.current == .miniera, let c = store.celebrations[group.main.key], let ore = c.ore else { return }
        DropStore.shared.add(group.main.key, .init(ore: ore, start: c.start, detail: c.oreDetail))
    }

    /// Off the list with a small sound.
    private func close() {
        NSSound(named: "Pop")?.play()
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { store.dismiss(group) }
    }

    private func earlierTitle(_ open: Bool) -> String {
        if open { return L("Hide the earlier requests", "Nascondi le richieste precedenti") }
        let n = group.earlier.count
        let total = group.earlier.reduce(0) { $0 + $1.elapsed(at: store.now) }
        return n == 1 ? L("1 earlier request, \(clock(total))", "1 richiesta precedente, \(clock(total))")
            : L("\(n) earlier requests, \(clock(total)) in all", "\(n) richieste precedenti, \(clock(total)) in tutto")
    }
}

/// Frames of the panel's buttons, so that clicks there reach them instead of the drag layer.
struct ClickFramesKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

/// Where the list's header is in the panel: a double click there opens the dashboard.
struct HeaderFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// Height of the list, so the popover's scroll view is as tall as its content, up to a limit.
struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    func reportsClickFrame() -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: ClickFramesKey.self, value: [g.frame(in: .named("panel"))])
        })
    }
}

/// The list of tasks, one row per session, shared by the desktop panel (5 at a time) and the menu
/// bar popover (all of them, in a list that scrolls).
struct TaskList: View {
    @ObservedObject var store: TaskStore
    var scrolls = false
    var accessory: AnyView? = nil
    /// Called when the list's height changes (the panel then fits its window to it).
    var onHeightChange: () -> Void = {}
    @State private var contentHeight: CGFloat = 0
    /// Which list this is, for its mini golf game: "panel" or "popover".
    var golfPlace = "popover"
    private var golf: GolfGame { GolfGame.game(golfPlace) }

    static let maxScrollHeight: CGFloat = 470

    var body: some View {
        let groups = store.groups
        let playing = store.golfUnlocked && !groups.isEmpty
        VStack(alignment: .leading, spacing: 12) {
            header
            if playing { GolfBoardSlot(game: golf, slot: "alto") }
            if groups.isEmpty {
                Text(L("No tasks in the last hour: as soon as Claude works, it shows up here.", "Nessun task nell'ultima ora: appena Claude lavora, compare qui."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if scrolls {
                ScrollView(.vertical) {
                    rows(groups)
                        .padding(.trailing, 4)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
                        })
                }
                .frame(height: min(max(contentHeight, 20), TaskList.maxScrollHeight))
                .onPreferenceChange(ContentHeightKey.self) {
                    contentHeight = $0
                    onHeightChange()
                }
            } else {
                rows(Array(groups.prefix(store.pageLimit)))
            }
            if playing { GolfBoardSlot(game: golf, slot: "basso") }
            footer(total: groups.count)
        }
        .overlay {
            if let burst = store.dotBurst { DotBurstView(burst: burst).padding(-8) }
        }
        // No game over an empty list: the hole and the ball would sit on its text.
        .overlay { if playing { GolfLayer(game: golf) } }
        .coordinateSpace(name: "golf")
        .environment(\.golf, store.golfUnlocked ? golf : nil)
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "timer").font(.system(size: 11, weight: .semibold))
                Text(L("Claude Code tasks", "Task di Claude Code")).font(.system(size: 11.5, weight: .semibold))
                Spacer()
            }
            .contentShape(Rectangle())
            // Not count: 2: in a list opened by hovering the first click only wakes the app up, and
            // SwiftUI waited for a third. The system's click count knows the double click.
            .onTapGesture { if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { DashboardController.shared.show() } }
            .help(L("Double click for the dashboard", "Doppio clic per la dashboard"))
            if store.waitingCount > 0 {
                Text(L("\(store.waitingCount) need\(store.waitingCount == 1 ? "s" : "") you", "\(store.waitingCount) ti aspett\(store.waitingCount == 1 ? "a" : "ano")"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.orange)
            }
            if store.runningCount > 0 {
                Text(L("\(store.runningCount) running", "\(store.runningCount) in corso")).font(.system(size: 10.5))
            }
            if let accessory { accessory }
        }
        .foregroundStyle(.secondary)
        .background(GeometryReader { g in
            Color.clear.preference(key: HeaderFrameKey.self, value: g.frame(in: .named("panel")))
        })
    }

    private func rows(_ groups: [TaskGroup]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 { Divider().opacity(0.35) }
                GroupView(store: store, group: group)
                    .transition(.asymmetric(insertion: .opacity,
                                            removal: .scale(scale: 0.92, anchor: .top).combined(with: .opacity)))
            }
        }
    }

    @ViewBuilder
    private func footer(total: Int) -> some View {
        let shown = scrolls ? total : min(total, store.pageLimit)
        if total > shown || (!scrolls && store.pageLimit > TaskStore.pageSize) || store.hiddenAutomated > 0 {
            HStack(spacing: 12) {
                if total > shown {
                    TextButton(title: L("\(min(TaskStore.pageSize, total - shown)) more", "Altri \(min(TaskStore.pageSize, total - shown))")) {
                        store.pageLimit += TaskStore.pageSize
                    }
                }
                if !scrolls && store.pageLimit > TaskStore.pageSize {
                    TextButton(title: L("Show less", "Mostra meno")) { store.pageLimit = TaskStore.pageSize }
                }
                Spacer()
                if store.hiddenAutomated > 0 {
                    Text(store.hiddenAutomated == 1 ? L("1 automated run hidden", "1 run automatica nascosta")
                         : L("\(store.hiddenAutomated) automated runs hidden", "\(store.hiddenAutomated) run automatiche nascoste"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .help(L("Automated runs (claude -p): show them from the settings gear.", "Run automatiche (claude -p): le mostri dalla rotellina delle impostazioni."))
                }
            }
            .font(.system(size: 11, weight: .medium))
        }
    }
}

/// A plain text button: drawn by SwiftUI itself (snapshots show it), clickable in the panel.
struct TextButton: View {
    let title: String
    var systemImage: String? = nil
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 8.5, weight: .bold))
            }
            Text(title)
        }
        .foregroundStyle(color)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .dwellClick(perform: action)
        .accessibilityAddTraits(.isButton)
        .reportsClickFrame()
    }
}

/// Content of the desktop panel: fixed width, as tall as the list.
struct PanelView: View {
    @ObservedObject var store: TaskStore
    var onClickFrames: ([CGRect]) -> Void = { _ in }
    var onHeaderFrame: (CGRect) -> Void = { _ in }
    var onResize: () -> Void = {}
    /// Snapshots draw no scroll view: they show the list 5 at a time instead.
    var scrolls = true

    /// Every session, in a list that scrolls (trackpad or wheel) past the panel's height; or, short,
    /// only the counts.
    var body: some View {
        Group {
            if store.compact {
                CompactPanel(store: store).fixedSize()
            } else {
                TaskList(store: store, scrolls: scrolls, onHeightChange: onResize, golfPlace: "panel")
                    .padding(16)
                    .frame(width: 350, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
            .coordinateSpace(name: "panel")
            .onPreferenceChange(ClickFramesKey.self) { onClickFrames($0) }
            .onPreferenceChange(HeaderFrameKey.self) { onHeaderFrame($0) }
            .followsLanguage()
    }
}

/// The short panel: prompts waiting, running and finished, no times. It blinks when one finishes
/// or starts waiting; a click opens the list again, a double click the dashboard.
struct CompactPanel: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        let done = store.doneCount
        HStack(spacing: 14) {
            if store.waitingCount > 0 {
                stat("hand.raised.fill", store.waitingCount, store.waitingCount == 1 ? L("needs you", "ti aspetta") : L("need you", "ti aspettano"), .orange)
            }
            stat("play.fill", store.runningCount, L("running", "in corso"), Pace.green.color)
            stat("checkmark", done, L("done", done == 1 ? "fatto" : "fatti"), .secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background { if let flash = store.flash { FlashView(flash: flash) } }
        .background(GeometryReader { g in
            Color.clear.preference(key: HeaderFrameKey.self, value: g.frame(in: .named("panel")))
        })
        .help(L("Click for the list, double click for the dashboard", "Clic per la lista, doppio clic per la dashboard"))
    }

    private func stat(_ symbol: String, _ n: Int, _ label: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .heavy)).foregroundStyle(color)
            Text("\(n)").font(.timer(17, .bold))
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

/// Content of the popover under the menu bar icon: the list, with the settings behind the gear.
struct MenuView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var prefs: Prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TaskList(store: store, scrolls: true, accessory: AnyView(SettingsMenu(store: store, prefs: prefs)))
            if let note = prefs.loginNote {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 370)
        .followsLanguage()
    }
}

/// The settings, behind the gear: a native menu with a tick next to what is on.
struct SettingsMenu: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var prefs: Prefs

    var body: some View {
        Menu {
            Button(L("Open the dashboard", "Apri la dashboard")) { DashboardController.shared.show() }
            Button(L("Settings…", "Impostazioni…")) { SettingsController.shared.show() }
            Divider()
            Section(L("Where to see it", "Dove vederli")) {
                Toggle(L("Panel on the desktop", "Pannello sul desktop"), isOn: $prefs.panelVisible)
                Toggle(L("Open the list by resting on the icon", "Apri la lista passando sul simbolo"), isOn: $prefs.hoverOpen)
            }
            Section(L("Notifications", "Avvisi")) {
                Picker(L("Notifications", "Avvisi"), selection: $prefs.notifyMode) {
                    ForEach(NotifyMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Toggle(L("When a task finishes", "Quando un task finisce"), isOn: $prefs.notifyDone)
                    .disabled(prefs.notifyMode == .never)
                Toggle(L("When Claude needs you", "Quando Claude ti aspetta"), isOn: $prefs.notifyWaiting)
                    .disabled(prefs.notifyMode == .never)
            }
            Section(L("Privacy", "Privacy")) {
                Toggle(L("Hide prompts and titles (screen sharing)", "Nascondi prompt e titoli (condivisione schermo)"), isOn: $store.hidePrompts)
                Toggle(L("Show automated runs (claude -p)", "Mostra le run automatiche (claude -p)"), isOn: $store.showAutomated)
            }
            Divider()
            Toggle(L("Open at login", "Apri al login"), isOn: Binding(get: { prefs.loginOn }, set: { prefs.setLogin($0) }))
            Button(L("Show the live files folder", "Mostra la cartella dei file live")) { prefs.openLiveFolder(store.dir) }
            Divider()
            Button(L("Quit TaskETA", "Esci da TaskETA")) { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Settings", "Impostazioni"))
    }
}
