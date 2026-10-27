import AppKit
import CoreText
import SwiftUI

// The look of "Il campo" for the game's cards in the dashboard (the gems and the mini golf): the
// map's colours and fonts. Dark is "golf di notte".
// Barlow Semi Condensed for titles and numbers, Barlow for the text: the map's own files in
// Resources/campo/fonts, registered for this process the first time a card is drawn; without them,
// the system font. Nothing here moves.

struct CampoStyle {
    let dark: Bool

    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    private func pick(_ light: UInt32, _ night: UInt32) -> Color { rgb(dark ? night : light) }

    var bg: Color { pick(0xeef2ea, 0x0d1714) }
    /// The paper of the map's cards.
    var plate: Color { pick(0xfbfcf8, 0x15241e) }
    var line: Color { pick(0xcbd6c4, 0x2b3d34) }
    /// The lawn: the plate of the game's widgets.
    var grass: Color { pick(0xcfe3bd, 0x1c3223) }
    var lane: Color { rgb(0x3f8a4f) }
    var laneEdge: Color { pick(0xf1f6e6, 0x2d4a34) }
    var laneOff: Color { pick(0xa8b8a4, 0x3d4b41) }
    var ice: [Color] { [rgb(0xeef7fc), rgb(0xc4e1f0)] }
    var felt: Color { rgb(0x1d6a48) }
    var rail: Color { rgb(0x7a5232) }
    var pocket: Color { rgb(0x111614) }
    var wood: Color { pick(0xa77a4f, 0x8a6440) }
    var woodDeep: Color { pick(0x8c6340, 0x6c4c30) }
    /// The flag: the accent, "you are here".
    var flag: Color { pick(0xd1452e, 0xf06a50) }
    var done: Color { pick(0x2f7140, 0x82d191) }
    var ink: Color { pick(0x16241b, 0xe4ede5) }
    var muted: Color { pick(0x56665b, 0x9bb0a2) }
    var todo: Color { pick(0x93a296, 0x63746a) }
    var ball: Color { pick(0xffffff, 0xf7f7f2) }
    /// The letters carved in a wooden plaque.
    var carved: Color { rgb(0xfbf3e4) }
    /// Text on the lane's green (the score card's header).
    var onLane: Color { rgb(0xf1f6e6) }
}

private func rgb(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
}

enum CampoFont {
    /// The six Barlow faces, registered once; false when the files are missing.
    static let ready: Bool = {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("campo/fonts") else { return false }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: "BarlowSemiCondensed-Bold", size: 12) != nil && NSFont(name: "Barlow-Regular", size: 12) != nil
    }()

    /// Titles and numbers, digits of equal width.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        guard ready else { return .system(size: size, weight: weight).width(.condensed).monospacedDigit() }
        let face = weight == .regular ? "Regular" : weight == .semibold ? "SemiBold" : "Bold"
        return .custom("BarlowSemiCondensed-\(face)", size: size).monospacedDigit()
    }

    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard ready else { return .system(size: size, weight: weight) }
        let face = weight == .regular ? "Regular" : weight == .semibold ? "SemiBold" : "Bold"
        return .custom("Barlow-\(face)", size: size)
    }
}

// MARK: - the plate

/// The game's widgets: the lawn of the park as the plate, a small green with its flag and the title
/// in the map's face. What does not fit is cut, as in every widget.
struct CampoPlate<Content: View>: View {
    let title: String
    var subtitle: String?
    var compact = false
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        VStack(alignment: .leading, spacing: compact ? 6 : 14) {
            HStack(alignment: .center, spacing: compact ? 8 : 11) {
                CampoGreen().frame(width: compact ? 34 : 46, height: compact ? 21 : 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(CampoFont.display(compact ? 17 : 21)).foregroundStyle(s.ink).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(CampoFont.text(compact ? 11.5 : 12.5)).foregroundStyle(s.muted).lineLimit(1)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
            }
            content.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(compact ? 12 : 16)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: DashMetrics.radius, style: .continuous).fill(s.grass))
        .clipShape(RoundedRectangle(cornerRadius: DashMetrics.radius, style: .continuous))
    }
}

/// A small green seen from above, as on the map: the lawn, the cup with its flag, the ball.
struct CampoGreen: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let oval = CGRect(x: 1.5, y: h * 0.34, width: w - 3, height: h * 0.62)
            ctx.fill(Path(ellipseIn: oval), with: .color(s.lane))
            ctx.stroke(Path(ellipseIn: oval), with: .color(s.laneEdge), lineWidth: 2)
            let cup = CGPoint(x: w * 0.66, y: oval.midY - 1)
            ctx.fill(Path(ellipseIn: CGRect(x: cup.x - 3, y: cup.y - 2, width: 6, height: 4)), with: .color(s.pocket))
            var pole = Path()
            pole.move(to: cup)
            pole.addLine(to: CGPoint(x: cup.x, y: 1))
            ctx.stroke(pole, with: .color(s.ink), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            var pennant = Path()
            pennant.move(to: CGPoint(x: cup.x, y: 1))
            pennant.addLine(to: CGPoint(x: cup.x + w * 0.26, y: 1 + h * 0.13))
            pennant.addLine(to: CGPoint(x: cup.x, y: 1 + h * 0.26))
            pennant.closeSubpath()
            ctx.fill(pennant, with: .color(s.flag))
            let ball = CGRect(x: w * 0.22, y: oval.midY, width: 5, height: 5)
            ctx.fill(Path(ellipseIn: ball), with: .color(s.ball))
            ctx.stroke(Path(ellipseIn: ball), with: .color(s.ink), lineWidth: 0.8)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - numbers and bars

/// A number of the game with its why underneath, on the paper of the map's cards.
struct CampoFigure: View {
    let label: String
    let value: String
    let why: String
    var accent: Color?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(CampoFont.display(11, .semibold)).kerning(0.8).foregroundStyle(s.muted).lineLimit(1)
            Text(value).font(CampoFont.display(24)).foregroundStyle(accent ?? s.ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(why).font(CampoFont.text(11)).foregroundStyle(s.muted).lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .campoPaper(s)
    }
}

/// The map's bar: a thin track, the part done in the "done" green.
struct CampoBar: View {
    let share: Double
    var color: Color?
    /// A mark at this share: the goal.
    var mark: Double?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(s.ink.opacity(0.1))
                Capsule().fill(color ?? s.done).frame(width: max(7, geo.size.width * min(1, max(0, share))))
                if let mark {
                    Rectangle().fill(s.ink.opacity(0.6)).frame(width: 2, height: geo.size.height + 4)
                        .offset(x: geo.size.width * mark - 1)
                }
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

/// A label in a thin capsule, as the map's state of a hole: "aperto", "chiuso", "vinta".
struct CampoState: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased()).font(CampoFont.display(11)).kerning(0.7)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .foregroundStyle(color)
            .overlay(Capsule().strokeBorder(color, lineWidth: 1))
            .lineLimit(1).fixedSize()
    }
}

/// The map's padlock. On a drawing (the ice, the felt) always in the light colours, to be seen.
struct CampoLock: View {
    var size: CGFloat = 18
    var onDrawing = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(onDrawing ? .light : scheme)
        Canvas { ctx, box in
            let k = box.width / 18
            var shackle = Path()
            shackle.move(to: CGPoint(x: 3 * k, y: 8 * k))
            shackle.addLine(to: CGPoint(x: 3 * k, y: 5.5 * k))
            shackle.addArc(center: CGPoint(x: 9 * k, y: 5.5 * k), radius: 6 * k, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            shackle.addLine(to: CGPoint(x: 15 * k, y: 8 * k))
            ctx.stroke(shackle, with: .color(s.ink), lineWidth: 1.6)
            let body = Path(roundedRect: CGRect(x: 0.8, y: 8 * k, width: box.width - 1.6, height: 12 * k), cornerRadius: 2.5 * k)
            ctx.fill(body, with: .color(s.plate))
            ctx.stroke(body, with: .color(s.ink), lineWidth: 1.6)
        }
        .frame(width: size, height: size * 21 / 18)
        .accessibilityLabel(L("locked", "chiuso"))
    }
}

extension View {
    /// On the paper of the map's cards: the plate colour, a thin line round it.
    func campoPaper(_ s: CampoStyle, radius: CGFloat = 10) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(s.plate))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(s.line, lineWidth: 1))
    }

    /// A small title over a part of a card, in the map's face.
    func campoEyebrow(_ s: CampoStyle) -> some View {
        font(CampoFont.display(12, .semibold)).kerning(0.8).foregroundStyle(s.muted)
    }
}

// MARK: - the mini golf's three courses

enum CampoMinigolf: CaseIterable {
    case prato, ghiaccio, biliardo

    var name: String {
        switch self {
        case .prato: return L("Lawn", "Prato")
        case .ghiaccio: return L("Ice course", "Campo ghiacciato")
        case .biliardo: return L("Billiards", "Biliardo")
        }
    }

    /// The holes played that open it: every task with an estimate, a bogey too.
    var need: Int {
        switch self {
        case .prato: return 0
        case .ghiaccio: return CampoCourse.ice
        case .biliardo: return CampoCourse.pool
        }
    }

    var what: String {
        switch self {
        case .prato: return L("The mini golf behind the dot: par 3, cushions worth 50 points.",
                              "Il minigolf dietro il pallino: par 3, sponde da 50 punti.")
        case .ghiaccio: return L("The ball slides: it barely slows down, bounces more, stops late.",
                                 "La pallina scivola: rallenta poco, rimbalza di più, si ferma tardi.")
        case .biliardo: return L("Six holes, in the corners and halfway along the long sides: only bank shots count.",
                                 "Sei buche, agli angoli e a metà dei lati lunghi: conta solo di sponda.")
        }
    }
}

/// A course of the mini golf drawn as on the map: the lawn, the ice rink or the billiards table,
/// behind a dashed frame and the padlock until it opens.
struct CampoCourseDrawing: View {
    let course: CampoMinigolf
    let open: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        ZStack {
            drawing(s)
            if !open {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(s.ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(width: 118, height: 62)
                CampoLock(size: 17, onDrawing: true)
            }
        }
        .frame(width: 118, height: 64)
        .accessibilityElement()
        .accessibilityLabel(open ? L("\(course.name), open", "\(course.name), aperto") : L("\(course.name), locked", "\(course.name), chiuso"))
    }

    private func drawing(_ s: CampoStyle) -> some View {
        Canvas { ctx, size in
            let r = CGRect(x: (size.width - 102) / 2, y: (size.height - 52) / 2, width: 102, height: 52)
            switch course {
            case .prato:
                let oval = r.insetBy(dx: 0, dy: 4)
                ctx.fill(Path(ellipseIn: oval), with: .color(s.lane))
                ctx.stroke(Path(ellipseIn: oval), with: .color(s.laneEdge), lineWidth: 4)
                let cup = CGPoint(x: oval.midX + 19, y: oval.midY - 2)
                ctx.fill(Path(ellipseIn: CGRect(x: cup.x - 5, y: cup.y - 3.5, width: 10, height: 7)), with: .color(s.pocket))
                var pole = Path()
                pole.move(to: cup)
                pole.addLine(to: CGPoint(x: cup.x, y: cup.y - 24))
                ctx.stroke(pole, with: .color(s.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                var pennant = Path()
                pennant.move(to: CGPoint(x: cup.x, y: cup.y - 24))
                pennant.addLine(to: CGPoint(x: cup.x + 16, y: cup.y - 20))
                pennant.addLine(to: CGPoint(x: cup.x, y: cup.y - 16))
                pennant.closeSubpath()
                ctx.fill(pennant, with: .color(s.flag))
                let ball = CGRect(x: oval.midX - 27, y: oval.midY, width: 9, height: 9)
                ctx.fill(Path(ellipseIn: ball), with: .color(s.ball))
                ctx.stroke(Path(ellipseIn: ball), with: .color(s.ink), lineWidth: 1.2)
            case .ghiaccio:
                let rink = Path(roundedRect: r, cornerRadius: 14)
                ctx.fill(rink, with: .linearGradient(Gradient(colors: s.ice), startPoint: CGPoint(x: r.minX, y: r.minY),
                                                     endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                ctx.stroke(rink, with: .color(s.line), lineWidth: 2)
                for (x0, x1) in [(16.0, 40.0), (44.0, 66.0), (70.0, 88.0)] {
                    var streak = Path()
                    streak.move(to: CGPoint(x: r.minX + x0, y: r.maxY - 10))
                    streak.addLine(to: CGPoint(x: r.minX + x1, y: r.minY + 12))
                    ctx.stroke(streak, with: .color(.white.opacity(0.85)), lineWidth: 2)
                }
            case .biliardo:
                let table = Path(roundedRect: r, cornerRadius: 5)
                ctx.fill(table, with: .color(s.felt))
                ctx.stroke(table, with: .color(s.rail), lineWidth: 7)
                for p in [CGPoint(x: r.minX + 4, y: r.minY + 4), CGPoint(x: r.maxX - 4, y: r.minY + 4),
                          CGPoint(x: r.minX + 4, y: r.maxY - 4), CGPoint(x: r.maxX - 4, y: r.maxY - 4),
                          CGPoint(x: r.midX, y: r.minY + 2), CGPoint(x: r.midX, y: r.maxY - 2)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(s.pocket))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - score cards and plaques

/// A score card's frame: a header band in the lane's green, rows on paper with thin lines between.
struct CampoScoreCard<Header: View, Rows: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let rows: Rows
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        VStack(spacing: 0) {
            header
                .font(CampoFont.display(11.5)).kerning(0.7).foregroundStyle(s.onLane)
                .frame(height: 24)
                .frame(maxWidth: .infinity)
                .background(s.lane)
            rows
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .campoPaper(s, radius: 8)
    }
}

/// The shots of a hole as written on a golf score card: a circle under par (two for an ace), a
/// square over it (two for a double bogey), nothing at par.
struct CampoShots: View {
    let shots: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        Text("\(shots)").font(CampoFont.display(14)).foregroundStyle(s.ink)
            .frame(width: 24, height: 24)
            .overlay {
                switch shots {
                case 1:
                    ZStack { Circle().strokeBorder(s.ink, lineWidth: 1.1); Circle().strokeBorder(s.ink, lineWidth: 1).padding(3) }
                case 2:
                    Circle().strokeBorder(s.ink, lineWidth: 1.1).padding(1.5)
                case 3:
                    EmptyView()
                case 4:
                    Rectangle().strokeBorder(s.ink, lineWidth: 1.1).padding(2)
                default:
                    ZStack { Rectangle().strokeBorder(s.ink, lineWidth: 1.1); Rectangle().strokeBorder(s.ink, lineWidth: 1).padding(3) }
                }
            }
            .accessibilityLabel(L(shots == 1 ? "1 shot" : "\(shots) shots", "\(shots) \(shots == 1 ? "tiro" : "tiri")"))
    }
}

/// The map's hole badge: a number in a disc.
struct CampoBadge: View {
    let number: Int
    var color: Color?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        Text("\(number)").font(CampoFont.display(12.5)).foregroundStyle(s.bg)
            .frame(width: 21, height: 21)
            .background(Circle().fill(color ?? s.done))
    }
}

/// An achievement as a wooden plaque by the course: carved when won, only its outline until then.
struct CampoPlaque: View {
    let title: String
    let how: String
    let earned: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        VStack(spacing: 1) {
            Text(title).font(CampoFont.display(14)).lineLimit(1)
            Text(how).font(CampoFont.text(10.5, earned ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.85)
        }
        .foregroundStyle(earned ? s.carved : s.muted)
        .shadow(color: earned ? s.rail.opacity(0.9) : .clear, radius: 0, x: 0, y: 0.8)
        .padding(.horizontal, 18).padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background {
            if earned {
                ZStack {
                    shape.fill(LinearGradient(colors: [s.wood, s.woodDeep], startPoint: .top, endPoint: .bottom))
                    // The grain: two thin lighter lines across.
                    VStack(spacing: 9) {
                        Rectangle().fill(s.carved.opacity(0.10)).frame(height: 1)
                        Rectangle().fill(s.carved.opacity(0.07)).frame(height: 1)
                    }
                    .padding(.horizontal, 14)
                    shape.strokeBorder(s.rail, lineWidth: 1.5)
                    HStack {
                        Circle().fill(s.rail).frame(width: 4, height: 4)
                        Spacer()
                        Circle().fill(s.rail).frame(width: 4, height: 4)
                    }
                    .padding(.horizontal, 6)
                }
            } else {
                shape.strokeBorder(s.todo, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(earned ? L("\(title), won: \(how)", "\(title), vinto: \(how)") : L("\(title), not won yet: \(how)", "\(title), da vincere: \(how)"))
    }
}

/// The way to the next level as a fairway: the ball where the points are, the flag at the green.
struct CampoFairway: View {
    let share: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let s = CampoStyle(scheme)
        Canvas { ctx, size in
            let w = size.width, mid = size.height - 9
            let lane = CGRect(x: 0, y: mid - 8, width: w - 4, height: 16)
            ctx.fill(Path(roundedRect: lane, cornerRadius: 8), with: .color(s.laneEdge))
            let inner = lane.insetBy(dx: 3, dy: 3)
            ctx.fill(Path(roundedRect: inner, cornerRadius: 5), with: .color(s.laneOff))
            let x = inner.minX + max(10, inner.width * min(1, max(0, share)))
            ctx.fill(Path(roundedRect: CGRect(x: inner.minX, y: inner.minY, width: x - inner.minX, height: inner.height), cornerRadius: 5),
                     with: .color(s.lane))
            // The flag at the green, the ball where you are.
            let cup = CGPoint(x: inner.maxX - 7, y: mid)
            ctx.fill(Path(ellipseIn: CGRect(x: cup.x - 3.5, y: cup.y - 2.5, width: 7, height: 5)), with: .color(s.pocket))
            var pole = Path()
            pole.move(to: cup)
            pole.addLine(to: CGPoint(x: cup.x, y: 1))
            ctx.stroke(pole, with: .color(s.ink), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            var pennant = Path()
            pennant.move(to: CGPoint(x: cup.x, y: 1))
            pennant.addLine(to: CGPoint(x: cup.x - 13, y: 4.5))
            pennant.addLine(to: CGPoint(x: cup.x, y: 8))
            pennant.closeSubpath()
            ctx.fill(pennant, with: .color(s.flag))
            let ball = CGRect(x: min(x, inner.maxX - 18) - 5, y: mid - 5, width: 10, height: 10)
            ctx.fill(Path(ellipseIn: ball), with: .color(s.ball))
            ctx.stroke(Path(ellipseIn: ball), with: .color(s.ink), lineWidth: 1.2)
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }
}
