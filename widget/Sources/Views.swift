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

    /// Text on the coloured part of the bar.
    var ink: Color { self == .yellow ? Color.black.opacity(0.85) : .white }
}

/// Fill = elapsed time, tick = estimate, lighter band = likely range. The times are written
/// inside the bar: the elapsed (or real) time on the left, the estimate on the right.
struct BarView: View {
    let elapsed: Double
    let estimate: Double?
    let range: (low: Double, high: Double)?
    let pace: Pace
    let leading: String
    let trailing: String
    var height: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let scale = barScale(elapsed: elapsed, estimate: estimate, high: range?.high)
            let x = { (v: Double) -> CGFloat in v.isFinite ? CGFloat(min(max(v, 0) / scale, 1)) * w : 0 }
            let fill = min(w, max(height, x(elapsed)))
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.08))
                if let r = range {
                    Rectangle().fill(Color.primary.opacity(0.10))
                        .frame(width: max(3, x(r.high) - x(r.low)))
                        .offset(x: x(r.low))
                }
                Rectangle().fill(pace.color).frame(width: fill)
                if let est = estimate {
                    Rectangle().fill(Color.primary.opacity(0.7))
                        .frame(width: 2)
                        .offset(x: min(max(0, x(est) - 1), w - 2))
                }
                // The same text twice: dark over the empty track, light over the fill.
                labels.foregroundStyle(Color.primary)
                    .mask(HStack(spacing: 0) { Color.clear.frame(width: fill); Color.black })
                labels.foregroundStyle(pace.ink)
                    .mask(HStack(spacing: 0) { Color.black.frame(width: fill); Color.clear })
            }
            .clipShape(RoundedRectangle(cornerRadius: height / 2))
        }
        .frame(height: height)
    }

    private var labels: some View {
        HStack(spacing: 6) {
            Text(leading).font(.system(size: 10.5, weight: .semibold).monospacedDigit())
            Spacer(minLength: 4)
            Text(trailing).font(.system(size: 10.5, weight: .medium).monospacedDigit())
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StateBadge: View {
    let item: TaskItem

    var body: some View {
        Group {
            switch item.state {
            case .waiting:
                Label("needs you", systemImage: "hand.raised.fill").foregroundStyle(Color.orange)
            case .running:
                Label("running", systemImage: "circle.fill").foregroundStyle(Color.green)
            case .background:
                Label("in background", systemImage: "hourglass").foregroundStyle(Color.secondary)
            case .stale:
                Label("stalled", systemImage: "pause.circle").foregroundStyle(Color.secondary)
            case .done:
                Label("done", systemImage: "checkmark").foregroundStyle(Color.secondary)
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

struct TaskRow: View {
    let item: TaskItem
    let now: Double

    var body: some View {
        let elapsed = item.elapsed(at: now)
        let waiting = item.state == .waiting
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(item.data.prompt.map { "Last prompt: \($0)" } ?? "")
                Spacer(minLength: 4)
                StateBadge(item: item)
            }
            BarView(elapsed: elapsed, estimate: item.estimate, range: item.range,
                    pace: item.pace(at: now), leading: leading(elapsed), trailing: trailing)
            HStack(spacing: 6) {
                Text("\(item.folderText) · \(item.modelText)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.data.modelKnown == false
                          ? "Model guessed: the session had not replied yet" : "")
                Spacer(minLength: 4)
                if let note = note {
                    Text(note)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(waiting ? Color.orange : Color.secondary)
                        .help(note)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(waiting ? 7 : 0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(waiting ? 0.13 : 0))
        )
        .opacity(item.state == .done || item.state == .stale ? 0.8 : 1)
    }

    private func leading(_ elapsed: Double) -> String {
        item.state == .done ? "actual \(clock(elapsed))" : clock(elapsed)
    }

    private var trailing: String {
        guard let est = item.estimateText else { return "no estimate" }
        if item.state != .done, let r = item.rangeText { return "est. \(est) (\(r))" }
        return "est. \(est)"
    }

    private var note: String? {
        switch item.state {
        case .waiting:
            return item.waitingText
        case .background:
            let jobs = item.data.bgJobs ?? []
            guard let first = jobs.first, !first.isEmpty else { return "background jobs" }
            return jobs.count == 1 ? first : "\(jobs.count) jobs: \(first)…"
        case .stale:
            return "quiet for \(clock(item.quiet ?? 0))"
        case .done:
            let end = Date(timeIntervalSince1970: item.data.endTs ?? item.data.startTs)
            return "at " + end.formatted(date: .omitted, time: .shortened)
        case .running:
            return nil
        }
    }
}

/// Frames of the panel's buttons, so that clicks there reach them instead of the drag layer.
struct ClickFramesKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

extension View {
    func reportsClickFrame() -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: ClickFramesKey.self, value: [g.frame(in: .named("panel"))])
        })
    }
}

/// The list of tasks, shared by the desktop panel and the menu bar popover: 5 at a time.
struct TaskList: View {
    @ObservedObject var store: TaskStore

    var body: some View {
        let all = store.visible
        let items = Array(all.prefix(store.pageLimit))
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                Text("Claude Code tasks").font(.system(size: 11, weight: .semibold))
                Spacer()
                if store.waitingCount > 0 {
                    Text("\(store.waitingCount) need\(store.waitingCount == 1 ? "s" : "") you")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.orange)
                }
                if store.runningCount > 0 {
                    Text("\(store.runningCount) running")
                        .font(.system(size: 10))
                }
            }
            .foregroundStyle(.secondary)
            if items.isEmpty {
                Text("No tasks in the last hour")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().opacity(0.5) }
                    TaskRow(item: item, now: store.now)
                }
            }
            if all.count > TaskStore.pageSize || store.hiddenAutomated > 0 {
                HStack(spacing: 12) {
                    if all.count > items.count {
                        TextButton(title: "\(min(TaskStore.pageSize, all.count - items.count)) more") {
                            store.pageLimit += TaskStore.pageSize
                        }
                    }
                    if store.pageLimit > TaskStore.pageSize {
                        TextButton(title: "Show less") { store.pageLimit = TaskStore.pageSize }
                    }
                    Spacer()
                    if store.hiddenAutomated > 0 {
                        Text("\(store.hiddenAutomated) test run\(store.hiddenAutomated == 1 ? "" : "s") hidden")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .help("Automated runs (claude -p). Show them from the menu bar menu.")
                    }
                }
                .font(.system(size: 11, weight: .medium))
            }
        }
    }
}

/// A plain text button: drawn by SwiftUI itself (snapshots show it), clickable in the panel.
struct TextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Text(title)
            .foregroundStyle(Color.accentColor)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .reportsClickFrame()
    }
}

/// Content of the desktop panel: fixed width, as tall as the list.
struct PanelView: View {
    @ObservedObject var store: TaskStore
    var onClickFrames: ([CGRect]) -> Void = { _ in }

    var body: some View {
        TaskList(store: store)
            .padding(14)
            .frame(width: 340, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .coordinateSpace(name: "panel")
            .onPreferenceChange(ClickFramesKey.self) { onClickFrames($0) }
    }
}

/// Content of the popover under the menu bar icon.
struct MenuView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var prefs: Prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TaskList(store: store).padding(14)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Panel on the desktop", isOn: $prefs.panelVisible)
                Toggle("Show automated runs (claude -p)", isOn: $store.showAutomated)
                Toggle("Open at login", isOn: Binding(
                    get: { prefs.loginOn },
                    set: { prefs.setLogin($0) }))
                if let note = prefs.loginNote {
                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Open live folder") { prefs.openLiveFolder(store.dir) }
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 12))
            .padding(14)
        }
        .frame(width: 340)
    }
}
