import AppKit
import SwiftUI

// The analysis of the week: written every Monday by an analyst outside the project (a scheduled
// Claude task that reads only the figures in insights-input.json, made by widget/insights/export.py),
// shown in the dashboard. See widget/insights/README.md.

struct WeeklyInsights: Codable, Equatable {
    struct Item: Codable, Equatable {
        var title: String
        var body: String
        var kind: String?   // trend, record, tip, warning
    }

    var v: Int?
    var generated: String?  // ISO 8601
    var period: String?     // "19-25 ottobre"
    var headline: String
    var items: [Item]

    static var url: URL {
        TaskStore.defaultDir.deletingLastPathComponent().appendingPathComponent("insights.json")
    }

    private static var cache: (stamp: String, value: WeeklyInsights?)?

    /// The last analysis, read again only when the file changes.
    static func load(from url: URL = WeeklyInsights.url) -> WeeklyInsights? {
        let stamp = fileStamp(url.path)
        if let cache, cache.stamp == stamp { return cache.value }
        var value: WeeklyInsights?
        if isRegularFile(url.path), let data = try? Data(contentsOf: url) {
            value = try? JSONDecoder().decode(WeeklyInsights.self, from: data)
            if let v = value, v.headline.isEmpty || v.items.isEmpty { value = nil }
        }
        cache = (stamp, value)
        return value
    }
}

extension WeeklyInsights.Item {
    var emoji: String {
        switch kind {
        case "trend": return "📈"
        case "record": return "🏆"
        case "warning": return "⚠️"
        default: return "💡"
        }
    }
}

/// The dashboard's widget: the headline, the points' titles when there is room, and the whole
/// analysis a click away.
struct InsightsWidget: View {
    let insights: WeeklyInsights?
    let size: WidgetSize
    @State private var open = false
    /// The pointer is on the icon and the hand cursor is pushed: popped once, on leaving or on disappearing.
    @State private var hand = false

    var body: some View {
        WidgetChrome(role: .plate, title: L("Weekly analysis", "Analisi della settimana"),
                     subtitle: insights.map { ins -> String in
                         let n = ins.items.count
                         return [ins.period, L("\(n) point\(n == 1 ? "" : "s"), from an analyst who sees only the numbers",
                                               "\(n) punti, da un analista che vede solo i numeri")]
                             .compactMap { $0 }.joined(separator: ", ")
                     } ?? L("every Monday morning", "ogni lunedì mattina")) {
            if let ins = insights {
                // An icon, not a button: the pointer on it opens the analysis at once (a click too).
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(open ? Color.accentColor : .secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(open ? 0.1 : 0.05)))
                    .contentShape(Circle())
                    .onHover { inside in
                        if inside { open = true }
                        if inside != hand {
                            inside ? NSCursor.pointingHand.push() : NSCursor.pop()
                            hand = inside
                        }
                    }
                    .onDisappear {
                        if hand { NSCursor.pop() }
                        hand = false
                    }
                    .onTapGesture { open = true }
                    .help(L("Read the analysis", "Leggi l'analisi"))
                    .accessibilityLabel(L("Read the analysis", "Leggi l'analisi"))
                    .accessibilityAddTraits(.isButton)
                    .popover(isPresented: $open, arrowEdge: .bottom) { InsightsDetail(insights: ins) }
            }
        } content: {
            if let ins = insights {
                VStack(alignment: .leading, spacing: 8) {
                    Text(ins.headline).font(.system(size: size.width >= 4 ? 17 : 14, weight: .semibold))
                        .lineLimit(size.height >= 2 ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if size.height >= 2 {
                        // By position: two points may share a title.
                        ForEach(Array(ins.items.prefix(4).enumerated()), id: \.offset) { _, item in
                            Label(item.title, systemImage: item.symbol)
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                    }
                }
            } else {
                Text(L("The first analysis arrives on Monday morning: an outside agent reads only the week's numbers (no prompts, no files) and writes what it sees.",
                       "La prima analisi arriva lunedì mattina: un agente esterno legge solo i numeri della settimana (niente prompt, niente file) e scrive cosa vede."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

extension WeeklyInsights.Item {
    /// The kind as a symbol, for the widget's list.
    var symbol: String {
        switch kind {
        case "trend": return "chart.line.uptrend.xyaxis"
        case "record": return "trophy"
        case "warning": return "exclamationmark.triangle"
        default: return "lightbulb"
        }
    }
}

struct InsightsDetail: View {
    let insights: WeeklyInsights

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(insights.headline).font(.system(size: 15, weight: .bold))
                if let period = insights.period {
                    Text(period).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(Array(insights.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text(item.emoji).font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Text(item.body).font(.system(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 440, height: 420)
    }
}
