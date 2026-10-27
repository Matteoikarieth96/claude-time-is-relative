import AppKit
import SwiftUI

// The dashboard as a grid of widgets, like the iPhone's home screen: 4 columns, rows of one fixed
// height, each widget 1×1 to 4×4 cells, packed in order where it first fits. "Modifica" (⌘E)
// lets you drag them around, change their size, hide them and bring them back; the layout is kept
// as JSON in UserDefaults, under "dashboardLayout".
//
// To check the drawing without clicking, TASKETA_DEBUG_DASH (comma separated) with
// `TaskETA --dashboard-snapshot FILE`: edit = in edit mode, all = the hidden widgets too,
// min / max = every widget at its smallest / largest size, demo = "Adesso" with the demo tasks,
// halfway = the opening's draw-in stopped halfway, editors = the edit-mode popovers drawn under
// the grid, cards = the game's cards (gems, mini golf) whole under the grid. Nothing of these is
// saved. The map of "Il campo" is a web view: the snapshot draws it first, off screen (Campo.swift).

// MARK: - sizes and widgets

enum WidgetSize: String, CaseIterable, Codable, Identifiable {
    case s1x1 = "1x1", s1x2 = "1x2", s2x1 = "2x1", s2x2 = "2x2", s3x2 = "3x2", s3x3 = "3x3"
    case s4x1 = "4x1", s4x2 = "4x2", s4x3 = "4x3", s4x4 = "4x4", s4x5 = "4x5"

    var id: String { rawValue }
    var width: Int { Int(String(rawValue.prefix(1))) ?? 1 }
    var height: Int { Int(String(rawValue.suffix(1))) ?? 1 }
    var label: String { "\(width)×\(height)" }
}

enum DashWidget: String, CaseIterable, Codable, Identifiable {
    case today, hours, hitRate, tasks, streak, now, days, projects, models, outcomes, misses
    case insights, scatter, heat, history, funStats, gems, minigolf, campo

    var id: String { rawValue }

    /// The name in the "Aggiungi" menu and on the drag.
    var title: String {
        switch self {
        case .today: return L("Today", "Oggi")
        case .hours: return L("Hours worked", "Ore di lavoro")
        case .hitRate: return L("Estimates in range", "Stime nella forchetta")
        case .tasks: return L("Tasks", "Task")
        case .streak: return L("Best streak", "Serie migliore")
        case .now: return L("Now", "Adesso")
        case .days: return L("Hours per day", "Ore al giorno")
        case .projects: return L("Projects", "Progetti")
        case .models: return L("Models", "Modelli")
        case .outcomes: return L("How the estimates went", "Gli esiti delle stime")
        case .misses: return L("Where the estimates miss", "Dove sbagliano le stime")
        case .insights: return L("Weekly analysis", "Analisi della settimana")
        case .scatter: return L("Estimate vs actual time", "Stima e tempo reale")
        case .heat: return L("When you work", "Quando lavori")
        case .history: return L("History", "Storico")
        case .funStats: return L("Useless stats", "Statistiche inutili")
        case .gems: return GameMood.current.cardTitle
        case .minigolf: return L("Mini golf", "Minigolf")
        case .campo: return L("The Course", "Il campo")
        }
    }

    /// The sizes that read well: each widget has its own compact and full forms.
    var sizes: [WidgetSize] {
        switch self {
        case .today, .hours, .hitRate, .tasks, .streak: return [.s1x1, .s2x1]
        case .now: return [.s1x1, .s2x1, .s2x2, .s3x2, .s4x2]
        case .days: return [.s2x1, .s2x2, .s3x2, .s4x1, .s4x2]
        case .projects, .models: return [.s1x1, .s1x2, .s2x1, .s2x2]
        case .outcomes: return [.s2x1, .s4x1]
        case .misses: return [.s2x2, .s3x2, .s4x2, .s4x3]
        case .insights: return [.s2x1, .s2x2, .s4x1]
        case .scatter: return [.s2x2, .s3x2, .s3x3, .s4x2]
        case .heat: return [.s1x1, .s2x2, .s3x2, .s4x2]
        case .history: return [.s2x2, .s3x2, .s3x3, .s4x2, .s4x3, .s4x4]
        case .funStats: return [.s2x2, .s3x2, .s4x2]
        // The whole mine or mini golf card is about 700 points high: 5 rows show it without scrolling.
        case .gems, .minigolf: return [.s2x1, .s4x4, .s4x5]
        // The map is 1200 × 720: the whole width, and 5 rows to show it nearly whole.
        case .campo: return [.s4x4, .s4x5]
        }
    }

    /// Widgets with something of their own to set in edit mode (a popover).
    var hasSettings: Bool { self == .funStats || self == .projects }
}

// MARK: - the layout and where it is kept

struct DashLayout: Equatable {
    struct Entry: Codable, Equatable {
        var widget: DashWidget
        var size: WidgetSize
        var hidden = false
    }

    var entries: [Entry]

    /// The first layout: what Nick asks first (today, the period, the estimates), then where the
    /// time goes and where the estimates miss, the history last. The game's map before the history;
    /// the gems and the mini golf wait in "Aggiungi".
    static let standard = DashLayout(entries: [
        Entry(widget: .today, size: .s1x1), Entry(widget: .hours, size: .s1x1),
        Entry(widget: .hitRate, size: .s1x1), Entry(widget: .tasks, size: .s1x1),
        Entry(widget: .now, size: .s2x2), Entry(widget: .days, size: .s2x2),
        Entry(widget: .outcomes, size: .s4x1),
        Entry(widget: .misses, size: .s4x2),
        Entry(widget: .projects, size: .s2x2), Entry(widget: .models, size: .s2x2),
        Entry(widget: .funStats, size: .s4x2),
        Entry(widget: .insights, size: .s4x1),
        Entry(widget: .scatter, size: .s2x2), Entry(widget: .heat, size: .s2x2),
        Entry(widget: .campo, size: .s4x5),
        Entry(widget: .history, size: .s4x3),
        Entry(widget: .streak, size: .s1x1, hidden: true),
        Entry(widget: .gems, size: .s4x4, hidden: true),
        Entry(widget: .minigolf, size: .s4x4, hidden: true),
    ])

    /// The saved form: {"v":1,"widgets":[{"id":"today","size":"1x1","hidden":false},…]}.
    private struct Saved: Codable {
        struct Item: Codable { var id: String; var size: String?; var hidden: Bool? }
        var v: Int
        var widgets: [Item]
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(Saved(v: 1, widgets: entries.map {
            Saved.Item(id: $0.widget.rawValue, size: $0.size.rawValue, hidden: $0.hidden)
        }))
    }

    /// Read leniently: widgets this version does not know are left out, a size a widget no longer
    /// has falls back to its first one, and widgets added since come in at the end, as in `standard`.
    static func decoded(_ data: Data) -> DashLayout? {
        guard let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        var seen = Set<DashWidget>()
        var entries: [Entry] = []
        for item in saved.widgets {
            guard let widget = DashWidget(rawValue: item.id), !seen.contains(widget) else { continue }
            seen.insert(widget)
            let size = item.size.flatMap(WidgetSize.init(rawValue:)).flatMap { widget.sizes.contains($0) ? $0 : nil }
                ?? widget.sizes[0]
            entries.append(Entry(widget: widget, size: size, hidden: item.hidden ?? false))
        }
        entries += standard.entries.filter { !seen.contains($0.widget) }
        return entries.isEmpty ? nil : DashLayout(entries: entries)
    }
}

/// The debug flags of TASKETA_DEBUG_DASH (see the top of the file).
enum DashDebug {
    static let flags = Set((ProcessInfo.processInfo.environment["TASKETA_DEBUG_DASH"] ?? "")
        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    /// The snapshot draws no scroll views (they come out as placeholders): lists show what fits.
    static let snapshot = CommandLine.arguments.contains("--dashboard-snapshot")
    /// TASKETA_DEBUG_GOLF: the mini golf unlocked (not saved) and sample games in the dashboard.
    static let golf = ProcessInfo.processInfo.environment["TASKETA_DEBUG_GOLF"] != nil
    /// TASKETA_DEBUG_GEMS: a sample day of gems in the dashboard.
    static let gems = ProcessInfo.processInfo.environment["TASKETA_DEBUG_GEMS"] != nil
}

final class DashGridModel: ObservableObject {
    static let defaultsKey = "dashboardLayout"

    @Published private(set) var layout: DashLayout
    @Published var editing = DashDebug.flags.contains("edit")
    /// The widget just brought back from "Aggiungi": the page scrolls to it.
    @Published var added: DashWidget?
    private let defaults: UserDefaults
    /// False while a debug flag draws a layout of its own: that one is never saved.
    private let saves: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var layout = defaults.data(forKey: DashGridModel.defaultsKey).flatMap(DashLayout.decoded) ?? .standard
        let flags = DashDebug.flags
        saves = flags.isDisjoint(with: ["all", "min", "max"])
        if !saves {
            layout.entries = layout.entries.map { entry in
                var e = entry
                if flags.contains("all") || flags.contains("min") || flags.contains("max") { e.hidden = false }
                if flags.contains("min") { e.size = e.widget.sizes.first ?? e.size }
                if flags.contains("max") { e.size = e.widget.sizes.last ?? e.size }
                return e
            }
        }
        self.layout = layout
    }

    var visible: [DashLayout.Entry] { layout.entries.filter { !$0.hidden } }
    var hidden: [DashLayout.Entry] { layout.entries.filter(\.hidden) }
    var isStandard: Bool { layout == .standard }

    /// Drops `widget` where `target` is: before it when it comes from further down, after it when
    /// it comes from above (as in a list).
    func move(_ widget: DashWidget, to target: DashWidget) {
        change { entries in
            guard widget != target, let from = entries.firstIndex(where: { $0.widget == widget }),
                  let to = entries.firstIndex(where: { $0.widget == target }) else { return }
            let entry = entries.remove(at: from)
            entries.insert(entry, at: to)
        }
    }

    func resize(_ widget: DashWidget, to size: WidgetSize) {
        change { entries in
            guard let i = entries.firstIndex(where: { $0.widget == widget }), widget.sizes.contains(size) else { return }
            entries[i].size = size
        }
    }

    func hide(_ widget: DashWidget) {
        change { entries in
            guard let i = entries.firstIndex(where: { $0.widget == widget }) else { return }
            entries[i].hidden = true
        }
    }

    /// Back from "Aggiungi": after the last visible widget, where the page then scrolls.
    func show(_ widget: DashWidget) {
        change { entries in
            guard let i = entries.firstIndex(where: { $0.widget == widget }) else { return }
            var entry = entries.remove(at: i)
            entry.hidden = false
            let end = (entries.lastIndex(where: { !$0.hidden }) ?? -1) + 1
            entries.insert(entry, at: end)
        }
        added = widget
    }

    func reset() {
        layout = .standard
        if saves { defaults.removeObject(forKey: DashGridModel.defaultsKey) }
    }

    private func change(_ edit: (inout [DashLayout.Entry]) -> Void) {
        var entries = layout.entries
        edit(&entries)
        guard entries != layout.entries else { return }
        layout.entries = entries
        if saves, let data = layout.encoded() { defaults.set(data, forKey: DashGridModel.defaultsKey) }
    }
}

// MARK: - the grid

enum DashMetrics {
    static let columns = 4
    static let row: CGFloat = 112
    static let gap: CGFloat = 14
    static let radius: CGFloat = 12
}

struct WidgetSpanKey: LayoutValueKey {
    static let defaultValue = WidgetSize.s1x1
}

/// Columns of equal width and rows of a fixed height; each widget goes, in order, to the first
/// place from the top left where it fits, so a small one can fill a gap left above.
struct WidgetGridLayout: Layout {
    var columns = DashMetrics.columns
    var row = DashMetrics.row
    var gap = DashMetrics.gap

    /// The cell (column, row) of each span, top left first.
    static func pack(_ spans: [WidgetSize], columns: Int) -> [(column: Int, row: Int)] {
        var taken: [[Bool]] = []
        func fits(_ c: Int, _ r: Int, _ w: Int, _ h: Int) -> Bool {
            for y in r..<(r + h) where y < taken.count {
                for x in c..<(c + w) where taken[y][x] { return false }
            }
            return true
        }
        var cells: [(column: Int, row: Int)] = []
        for span in spans {
            let w = min(max(1, span.width), columns), h = max(1, span.height)
            var r = 0
            var placed: (column: Int, row: Int)?
            while placed == nil {
                for c in 0...(columns - w) where fits(c, r, w, h) {
                    placed = (c, r)
                    break
                }
                if placed == nil { r += 1 }
            }
            let cell = placed ?? (0, r)
            while taken.count < cell.row + h { taken.append(Array(repeating: false, count: columns)) }
            for y in cell.row..<(cell.row + h) {
                for x in cell.column..<(cell.column + w) { taken[y][x] = true }
            }
            cells.append(cell)
        }
        return cells
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let spans = subviews.map { $0[WidgetSpanKey.self] }
        let cells = WidgetGridLayout.pack(spans, columns: columns)
        let rows = zip(cells, spans).map { $0.row + $1.height }.max() ?? 0
        let height = rows == 0 ? 0 : CGFloat(rows) * row + CGFloat(rows - 1) * gap
        return CGSize(width: proposal.width ?? 940, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let spans = subviews.map { $0[WidgetSpanKey.self] }
        let cells = WidgetGridLayout.pack(spans, columns: columns)
        let column = (bounds.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        for (i, subview) in subviews.enumerated() {
            let span = spans[i], cell = cells[i]
            let w = min(span.width, columns)
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(cell.column) * (column + gap),
                                      y: bounds.minY + CGFloat(cell.row) * (row + gap)),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: CGFloat(w) * column + CGFloat(w - 1) * gap,
                                                     height: CGFloat(span.height) * row + CGFloat(span.height - 1) * gap))
        }
    }
}

struct DashboardGrid: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var grid: DashGridModel
    /// The opening, once each time the dashboard opens (the grid comes back with the data): the
    /// figures run up and the charts grow from 0 to 1, together. Never again until the next
    /// opening, never with Reduce Motion, and already at 1 in a snapshot.
    @State private var intro: Double = DashDebug.flags.contains("halfway") ? 0.45 : DashDebug.snapshot ? 1 : 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WidgetGridLayout {
            ForEach(grid.visible, id: \.widget) { entry in
                DashWidgetView(widget: entry.widget, size: entry.size, model: model)
                    // Exactly its cells: a widget never grows into the one below; what does not fit is cut.
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .modifier(EditableWidget(entry: entry, grid: grid, model: model))
                    .layoutValue(key: WidgetSpanKey.self, value: entry.size)
                    .id(entry.widget)
            }
        }
        // Only the user's own changes move things: a size, a drop, a widget hidden or back.
        .animation(.snappy(duration: 0.3), value: grid.layout)
        .environment(\.dashIntro, intro)
        .onAppear {
            guard intro == 0 else { return }
            if reduceMotion {
                intro = 1
            } else {
                withAnimation(.easeOut(duration: 1.1).delay(0.05)) { intro = 1 }
            }
        }
    }
}

private struct DashIntroKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

extension EnvironmentValues {
    /// How far the opening is, 0 to 1 (see DashboardGrid): figures and bars are drawn times this.
    var dashIntro: Double {
        get { self[DashIntroKey.self] }
        set { self[DashIntroKey.self] = newValue }
    }
}

/// A number that runs up to its value with the opening: SwiftUI draws every step in between.
struct CountingText: View, Animatable {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

/// In edit mode: a dashed outline, the size on top right (a menu), a button to hide it on top
/// left, and the whole widget can be dragged onto another one to take its place. The content
/// takes no clicks meanwhile, so a drag never starts a chart's or a link's own gesture.
struct EditableWidget: ViewModifier {
    let entry: DashLayout.Entry
    @ObservedObject var grid: DashGridModel
    /// For the editors: the projects to give a logo to.
    let model: DashboardModel
    @State private var targeted = false
    @State private var settingsOpen = false

    func body(content: Content) -> some View {
        if grid.editing {
            content
                .allowsHitTesting(false)
                .overlay {
                    RoundedRectangle(cornerRadius: DashMetrics.radius + 3, style: .continuous)
                        .strokeBorder(targeted ? Color.accentColor : Color.primary.opacity(0.32),
                                      style: StrokeStyle(lineWidth: targeted ? 2 : 1, dash: targeted ? [] : [5, 4]))
                        .padding(-5)
                        .allowsHitTesting(false)
                }
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .draggable(entry.widget.rawValue) {
                            Text(entry.widget.title)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
                        }
                }
                .overlay(alignment: .topLeading) {
                    Button { grid.hide(entry.widget) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 18))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color(white: 0.42))
                    }
                    .buttonStyle(.plain)
                    .help(L("Hide “\(entry.widget.title)”: bring it back from Add", "Nascondi «\(entry.widget.title)»: torna da Aggiungi"))
                    .accessibilityLabel(L("Hide \(entry.widget.title)", "Nascondi \(entry.widget.title)"))
                    .offset(x: -12, y: -12)
                }
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 6) {
                        if entry.widget.hasSettings {
                            Button { settingsOpen = true } label: {
                                Label(entry.widget == .projects ? L("Logos", "Loghi") : L("Customize", "Personalizza"), systemImage: "slider.horizontal.3")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .help(entry.widget == .projects ? L("The projects' logos", "I loghi dei progetti")
                                  : L("Which stats, the ×4, the words to count", "Quali statistiche, il ×4, le parole da contare"))
                            .chip()
                            .popover(isPresented: $settingsOpen, arrowEdge: .bottom) {
                                if entry.widget == .projects {
                                    ProjectLogosEditor(projects: model.projectNames)
                                } else {
                                    FunStatsEditor()
                                }
                            }
                        }
                        Menu {
                            Picker(L("Size", "Dimensione"), selection: Binding(get: { entry.size },
                                                                               set: { grid.resize(entry.widget, to: $0) })) {
                                ForEach(entry.widget.sizes) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        } label: {
                            Text(entry.size.label).font(.timer(11, .semibold))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help(L("Size of “\(entry.widget.title)”", "Dimensione di «\(entry.widget.title)»"))
                        .chip()
                    }
                    .offset(x: 6, y: -11)
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first, let widget = DashWidget(rawValue: raw), widget != entry.widget else { return false }
                    grid.move(widget, to: entry.widget)
                    return true
                } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}

private extension View {
    /// The small capsule of the edit-mode controls.
    func chip() -> some View {
        padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

// MARK: - widget chrome

/// What a widget is, which decides how it sits on the page: a figure is a number under a rule,
/// with no box; a chart or a list sits on a plate; the hero (the outcomes' bar) has neither, the
/// bar is enough.
enum WidgetRole { case figure, hero, plate }

/// The dashboard's few colours: ink from the system, one blue for hours and counts, green and
/// orange only for a change that is good or bad, the outcomes' own colours where an outcome is.
enum DashColor {
    static let data = Color(red: 0.20, green: 0.52, blue: 0.88)
    static let good = Color(red: 0.13, green: 0.62, blue: 0.36)
    static let bad = Color(red: 0.91, green: 0.42, blue: 0.08)
    static let plate = Color.primary.opacity(0.045)
    static let track = Color.primary.opacity(0.08)
}

struct WidgetChrome<Trailing: View, Content: View>: View {
    let role: WidgetRole
    let title: String
    var subtitle: String?
    let trailing: Trailing
    let content: Content

    init(role: WidgetRole, title: String, subtitle: String? = nil,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.role = role
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        switch role {
        case .figure:
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Color.primary.opacity(0.78)).frame(height: 2)
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).padding(.top, 9)
                content.padding(.top, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .hero:
            // One line of header: the room goes to the bar.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer(minLength: 8)
                    trailing
                }
                content.frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .plate:
            // minHeight 0: the plate is its cells, never taller; a list longer than that is cut inside it.
            VStack(alignment: .leading, spacing: 12) {
                header
                content.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(16)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: DashMetrics.radius, style: .continuous).fill(DashColor.plate))
            .clipShape(RoundedRectangle(cornerRadius: DashMetrics.radius, style: .continuous))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension WidgetChrome where Trailing == EmptyView {
    init(role: WidgetRole, title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(role: role, title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

/// A figure: the number large in the rounded face, its unit small, and one line that says what
/// it is against (the period before, yesterday). An accessory on the right shows its shape.
struct FigureView<Accessory: View>: View {
    let value: String
    /// A number to count up with the opening, written by `format` (then `value` is not used).
    var number: Double?
    var format: (Double) -> String = { "\(safeInt($0.rounded()))" }
    var unit: String?
    let caption: Text
    /// A name instead of a number (the top project): smaller, in the text face.
    var isName = false
    let accessory: Accessory
    @Environment(\.dashIntro) private var intro

    init(value: String, unit: String? = nil, caption: Text, isName: Bool = false,
         @ViewBuilder accessory: () -> Accessory) {
        self.value = value
        self.unit = unit
        self.caption = caption
        self.isName = isName
        self.accessory = accessory()
    }

    init(number: Double, format: @escaping (Double) -> String, unit: String? = nil, caption: Text,
         @ViewBuilder accessory: () -> Accessory) {
        self.init(value: format(number), unit: unit, caption: caption, accessory: accessory)
        self.number = number
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                HStack(alignment: .lastTextBaseline, spacing: unit == "%" ? 1 : 4) {
                    Group {
                        if let number {
                            CountingText(value: number * intro, format: format)
                        } else {
                            Text(value)
                        }
                    }
                    .font(isName ? .system(size: 22, weight: .semibold) : .timer(34, .semibold))
                    if let unit {
                        Text(unit).font(.timer(15, .medium)).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.55).layoutPriority(1)
                Spacer(minLength: 0)
                accessory
            }
            .frame(height: 42, alignment: .bottom)
            caption.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension FigureView where Accessory == EmptyView {
    init(value: String, unit: String? = nil, caption: Text, isName: Bool = false) {
        self.init(value: value, unit: unit, caption: caption, isName: isName, accessory: { EmptyView() })
    }

    init(number: Double, format: @escaping (Double) -> String, unit: String? = nil, caption: Text) {
        self.init(number: number, format: format, unit: unit, caption: caption, accessory: { EmptyView() })
    }
}

/// Small bars side by side, the tallest at full height: the shape of a series, no axes.
struct MiniBars: View {
    let values: [Double]
    var colors: [Color]?
    var color = DashColor.data
    @Environment(\.dashIntro) private var intro

    var body: some View {
        GeometryReader { geo in
            let top = max(values.max() ?? 0, 0.000_1)
            let n = max(values.count, 1)
            let gap: CGFloat = n > 20 ? 1 : 2
            let w = max(1, (geo.size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(values.indices, id: \.self) { i in
                    let v = values[i]
                    RoundedRectangle(cornerRadius: min(1.5, w / 2))
                        .fill(v > 0 ? (colors.map { $0[i % $0.count] } ?? color) : Color.primary.opacity(0.14))
                        .frame(width: w, height: v > 0 ? max(2, geo.size.height * v / top * intro) : 1)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
        .frame(maxWidth: 104)
        .frame(height: 26)
        .accessibilityHidden(true)
    }
}

// MARK: - which view is which widget

struct DashWidgetView: View {
    let widget: DashWidget
    let size: WidgetSize
    @ObservedObject var model: DashboardModel

    var body: some View {
        switch widget {
        case .today: TodayWidget(model: model, size: size)
        case .hours: HoursWidget(model: model, size: size)
        case .hitRate: HitRateWidget(model: model, size: size)
        case .tasks: TasksWidget(model: model, size: size)
        case .streak: StreakWidget(stats: model.stats, size: size)
        case .now:
            if let store = DashboardController.shared.store ?? (DashDebug.flags.contains("demo") ? TaskStore.demo() : nil) {
                NowWidget(store: store, size: size)
            } else {
                WidgetChrome(role: size == .s1x1 ? .figure : .plate, title: L("Now", "Adesso")) {
                    Text(L("Running tasks show up here.", "I task in corso compaiono qui.")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        case .days: DaysWidget(model: model, size: size)
        case .projects: HoursListWidget(projects: true, model: model, size: size)
        case .models: HoursListWidget(projects: false, model: model, size: size)
        case .outcomes: OutcomesWidget(stats: model.stats, size: size)
        case .misses: MissesWidget(stats: model.stats, period: model.periodText, size: size)
        case .insights: InsightsWidget(insights: WeeklyInsights.load(), size: size)
        case .scatter: ScatterWidget(stats: model.stats, size: size)
        case .heat: HeatWidget(stats: model.stats, size: size)
        case .history: HistoryWidget(model: model, size: size)
        case .funStats: FunStatsWidget(model: model, size: size)
        case .gems:
            GemsWidget(stats: DashDebug.gems ? GemStats.sample() : GemStats(model.all),
                       mine: DashDebug.gems ? MineStats.sample() : MineStats(model.all), size: size,
                       onFind: { ore, week in
                           model.mineFilter = .init(ore: ore, week: week)
                           model.jump = .history
                       })
        case .minigolf:
            MinigolfWidget(store: DashboardController.shared.store, played: model.all.filter { $0.estimate != nil }.count, size: size)
        case .campo: CampoWidget(model: model, size: size)
        }
    }
}
