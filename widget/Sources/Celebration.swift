import SwiftUI

/// How a finished task went against its estimate.
enum Outcome: CaseIterable {
    case exact    // within 8% of the estimate
    case faster   // under the likely range
    case onTime   // within the likely range
    case slower   // past the likely range

    /// The sticker: one meme per outcome.
    var stamp: String {
        switch self {
        case .exact: return L("🤌 Chef's kiss", "🤌 Dai che ci siamo")
        case .faster: return L("🦵 Speedrun!", "🦵 C'hai quella gamba lì")
        case .onTime: return "🎉 GG"
        case .slower: return "🔥 This is fine"
        }
    }

    var emoji: String { String(stamp.prefix(1)) }

    /// A smaller sticker on the side, a moment later: a comment, not the headline.
    var aside: String? { self == .slower ? L("🐢 Slow and steady", "🐢 Piano piano") : nil }

    /// The colours of the particles and of the glow; the first is the main one.
    var palette: [Color] {
        switch self {
        case .exact: return [Color(red: 1.00, green: 0.74, blue: 0.20), Color(red: 1.00, green: 0.42, blue: 0.60),
                             Color(red: 0.20, green: 0.80, blue: 0.68), Color(red: 0.48, green: 0.38, blue: 1.00)]
        case .faster: return [Color(red: 0.20, green: 0.70, blue: 0.94), Color(red: 0.48, green: 0.38, blue: 1.00),
                              Color(red: 0.20, green: 0.80, blue: 0.68)]
        case .onTime: return [Color(red: 0.37, green: 0.88, blue: 0.77), Color(red: 1.00, green: 0.82, blue: 0.40),
                              Color(red: 1.00, green: 0.42, blue: 0.60), Color(red: 0.48, green: 0.38, blue: 1.00)]
        case .slower: return [Color(red: 1.00, green: 0.54, blue: 0.24), Color(red: 0.94, green: 0.22, blue: 0.42),
                              Color(red: 1.00, green: 0.82, blue: 0.40)]
        }
    }
}

/// How a real time went against an estimate and its likely range (seconds): the one rule for the
/// celebrations and the dashboard. Within 8% is hit, with no floor since v2.8 (on a 24 second
/// estimate 10 seconds were 40%); Claude's score passes the hook's floor of 10 seconds.
func outcomeOf(real: Double, estimate est: Double, range: (low: Double, high: Double)?, floor: Double = 0) -> Outcome {
    if abs(real - est) <= max(floor, est * 0.08) { return .exact }
    let r = range ?? (est * 0.7, est * 1.5)
    if real < r.low { return .faster }
    if real > r.high { return .slower }
    return .onTime
}

extension TaskItem {
    /// How the task went, once finished, and by how much (seconds, positive when late).
    func outcome(at now: Double) -> (outcome: Outcome, delta: Double)? {
        guard let est = estimate, est > 0 else { return nil }
        let real = elapsed(at: now)
        return (outcomeOf(real: real, estimate: est, range: range), real - est)
    }
}

/// A fixed pseudo-random number in 0..<1 for item i: the same i and salt always give the same.
func pseudoRandom(_ i: Int, _ salt: Double) -> Double {
    let x = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
    return x - x.rounded(.down)
}

/// A position bouncing between 0 and length: the path of something that moves straight and
/// bounces off two walls.
func bounce(_ p: Double, _ length: Double) -> Double {
    guard length > 0 else { return 0 }
    var m = p.truncatingRemainder(dividingBy: 2 * length)
    if m < 0 { m += 2 * length }
    return m <= length ? m : 2 * length - m
}

/// A blink of the short panel: green when a task finishes, orange when Claude waits for you.
struct Flash: Equatable {
    let waiting: Bool
    let start: Double
    static let duration: Double = 3.5
}

struct FlashView: View {
    let flash: Flash

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince1970 - flash.start
            if t >= 0 && t < Flash.duration {
                let color = flash.waiting ? Color.orange : Pace.green.color
                let pulse = 0.5 + 0.5 * cos(t * 2 * .pi * 1.6)   // about 5 blinks
                let fade = min(1, (Flash.duration - t) / 0.8)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(color.opacity(0.42 * pulse * fade))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(color.opacity(0.9 * pulse * fade), lineWidth: 2))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The easter egg of the dot next to "in corso": at the 10th click it shoots off, at the 69th
/// come 69 dots, all bouncing around the list.
struct DotBurst: Equatable {
    let count: Int
    let start: Double
    /// The single dot of the 8th click flies a while longer.
    var duration: Double { count == 1 ? 8 : 5 }
}

struct DotBurstView: View {
    let burst: DotBurst

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince1970 - burst.start
            if t >= 0 && t < burst.duration {
                Canvas { ctx, size in drawDots(&ctx, size: size, t: t) }
                    .opacity(min(1, (burst.duration - t) / 0.6))
            }
        }
        .allowsHitTesting(false)
    }

    private func drawDots(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let colors = Outcome.allCases.flatMap { $0.palette } + [Pace.green.color]
        let single = burst.count == 1
        for i in 0..<burst.count {
            let r = single ? 6 : 3.5 + pseudoRandom(i, 1) * 3.5
            let angle = single ? 2.4 : pseudoRandom(i, 2) * 2 * .pi
            let speed = single ? 430 : 170 + pseudoRandom(i, 3) * 230
            let x0 = single ? size.width - 40 : r + pseudoRandom(i, 4) * (size.width - 2 * r)
            let y0 = single ? 22 : r + pseudoRandom(i, 5) * (size.height - 2 * r)
            func at(_ time: Double) -> CGPoint {
                CGPoint(x: r + bounce(x0 - r + cos(angle) * speed * time, size.width - 2 * r),
                        y: r + bounce(y0 - r + sin(angle) * speed * time, size.height - 2 * r))
            }
            let color = single ? Pace.green.color : colors[i % colors.count]
            if single { // a trail behind the dot that shot off
                for k in stride(from: 8, through: 1, by: -1) {
                    let p = at(max(0, t - Double(k) * 0.018))
                    let tr = r * (1 - Double(k) / 10)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - tr, y: p.y - tr, width: 2 * tr, height: 2 * tr)),
                             with: .color(color.opacity(0.5 * (1 - Double(k) / 9))))
                }
            }
            let p = at(t)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.45, y: p.y - r * 0.6, width: r * 0.6, height: r * 0.5)),
                     with: .color(.white.opacity(0.55)))
        }
    }
}

/// A row's celebration: what to show and since when.
struct Celebration {
    let outcome: Outcome
    let start: Double
    /// Real time minus the estimate, seconds.
    let delta: Double
    /// The estimate, for "×6" past it.
    var estimate: Double = 0
    /// The likely range, for the ore the mine finds.
    var range: (low: Double, high: Double)? = nil

    static let duration: Double = 3.5

    /// What the pickaxe found (Miniera.swift), nil without an estimate.
    var ore: Ore? { estimate > 0 ? Ore(real: estimate + delta, estimate: estimate, range: range) : nil }

    /// "36s of 30s": the real time on the estimate.
    var oreDetail: String { L("\(clock(estimate + delta)) of \(clock(estimate))", "\(clock(estimate + delta)) su \(clock(estimate))") }

    /// Under the sticker: how far from the estimate.
    var detail: String {
        switch outcome {
        case .exact: return L("spot on", "stima centrata")
        case .onTime: return L("on time", "nei tempi")
        case .faster: return "−" + clock(-delta)
        case .slower:
            let ratio = estimate > 0 ? (estimate + delta) / estimate : 0
            return overText(delta) + (ratio >= 2 ? " (\(timesText(ratio)))" : "")
        }
    }
}

/// A few seconds over a row that has just finished, different for each outcome: fireworks right on
/// the estimate, a rocket under the range, confetti within it, "this is fine" flames past it, each
/// with its sticker. Only the sticker when the Mac asks for reduced motion.
struct CelebrationView: View {
    let celebration: Celebration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince1970 - celebration.start
            if t >= 0 && t < Celebration.duration {
                let fade = envelope(t)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(RadialGradient(colors: [celebration.outcome.palette[0].opacity(0.30), .clear],
                                             center: .center, startRadius: 4, endRadius: 190))
                        .opacity(fade)
                    if !reduceMotion {
                        Canvas { ctx, size in
                            Particles(outcome: celebration.outcome, t: t, size: size).draw(in: &ctx)
                        }
                    }
                    sticker(t: t).opacity(fade)
                    if let aside = celebration.outcome.aside {
                        asideSticker(aside, t: t)
                            .opacity(fade)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(.top, 6)
                            .padding(.trailing, 12)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .allowsHitTesting(false)
    }

    /// Fades in fast, holds, fades out over the last half second.
    private func envelope(_ t: Double) -> Double {
        min(1, t / 0.15, (Celebration.duration - t) / 0.5)
    }

    /// Pops in 0.7 seconds after the main sticker, small and tilted the other way.
    private func asideSticker(_ text: String, t: Double) -> some View {
        let p = min(1, max(0, (t - 0.7) / 0.35))
        let back = 1 + 2.70158 * pow(p - 1, 3) + 1.70158 * pow(p - 1, 2)
        return Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.9)))
            .overlay(Capsule().strokeBorder(Color(red: 0.37, green: 0.80, blue: 0.45), lineWidth: 1.5))
            .rotationEffect(.degrees(8))
            .scaleEffect(p == 0 ? 0.01 : 0.3 + 0.7 * back)
            .opacity(p == 0 ? 0 : 1)
    }

    /// The meme sticker: pops in with an overshoot, slightly tilted.
    private func sticker(t: Double) -> some View {
        let p = min(1, max(0, t / 0.45))
        let c1 = 1.70158, c3 = c1 + 1
        let back = 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)  // ease out with overshoot
        let ore = GameMood.current == .miniera ? celebration.ore : nil
        let main = ore.map { Color(nsColor: $0.tones.light) } ?? celebration.outcome.palette[0]
        return HStack(spacing: 6) {
            if let ore { OreIcon(ore: ore, size: 20) }
            VStack(spacing: 0) {
                Text(ore?.name ?? celebration.outcome.stamp)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                Text(ore != nil ? celebration.oreDetail : celebration.detail)
                    .font(.timer(10, .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.92)))
        .overlay(Capsule().strokeBorder(main, lineWidth: 2))
        .shadow(color: main.opacity(0.55), radius: 8)
        .rotationEffect(.degrees(-6))
        .scaleEffect(0.3 + 0.7 * back)
    }
}

/// The particles of one frame, drawn from the time alone: the same t always gives the same picture.
struct Particles {
    let outcome: Outcome
    let t: Double
    let size: CGSize

    private var w: Double { size.width }
    private var h: Double { size.height }

    /// A fixed pseudo-random number in 0..<1 for particle i.
    private func rnd(_ i: Int, _ salt: Double) -> Double {
        let x = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }

    private func color(_ i: Int) -> Color { outcome.palette[i % outcome.palette.count] }

    func draw(in ctx: inout GraphicsContext) {
        switch outcome {
        case .exact: fireworks(&ctx)
        case .faster: rocket(&ctx)
        case .onTime: confetti(&ctx)
        case .slower: flames(&ctx)
        }
    }

    /// Three bursts of sparks, one after the other, falling a little as they fade.
    private func fireworks(_ ctx: inout GraphicsContext) {
        let bursts: [(x: Double, y: Double, at: Double)] = [(0.2, 0.38, 0.05), (0.8, 0.32, 0.45), (0.5, 0.26, 0.85),
                                                            (0.33, 0.3, 1.5), (0.68, 0.4, 1.9)]
        for (b, burst) in bursts.enumerated() {
            let tau = t - burst.at
            guard tau > 0, tau < 1.3 else { continue }
            let center = CGPoint(x: burst.x * w, y: burst.y * h)
            if tau < 0.18 { // the flash of the burst
                let r = 3 + tau * 60
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(color(b).opacity(0.5 * (1 - tau / 0.18))))
            }
            for i in 0..<26 {
                let angle = Double(i) / 26 * 2 * .pi + rnd(i, Double(b)) * 0.3
                let speed = 60 + rnd(i, Double(b) + 9) * 40
                let dist = speed * tau * (1 - 0.35 * tau)
                let p = CGPoint(x: center.x + cos(angle) * dist, y: center.y + sin(angle) * dist + 22 * tau * tau)
                let back = max(0, tau - 0.07)
                let d0 = speed * back * (1 - 0.35 * back)
                let q = CGPoint(x: center.x + cos(angle) * d0, y: center.y + sin(angle) * d0 + 22 * back * back)
                var path = Path()
                path.move(to: q)
                path.addLine(to: p)
                let alpha = 1 - tau / 1.3
                ctx.stroke(path, with: .color(color(i + b).opacity(alpha)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.8, y: p.y - 1.8, width: 3.6, height: 3.6)),
                         with: .color(color(i + b + 1).opacity(alpha)))
            }
        }
    }

    /// A rocket across the row, sparks behind it and speed lines.
    private func rocket(_ ctx: inout GraphicsContext) {
        func position(_ time: Double) -> CGPoint {
            let p = min(1, max(0, (time - 0.15) / 1.2))
            let eased = p * p * (3 - 2 * p)
            return CGPoint(x: -24 + eased * (w + 48), y: h * 0.55 + sin(time * 9) * 4)
        }
        for i in 0..<7 {
            let y = (0.15 + rnd(i, 3) * 0.7) * h
            let x = w - ((t * (340 + rnd(i, 4) * 160) + rnd(i, 5) * w).truncatingRemainder(dividingBy: w + 80))
            var line = Path()
            line.move(to: CGPoint(x: x, y: y))
            line.addLine(to: CGPoint(x: x + 26 + rnd(i, 6) * 30, y: y))
            ctx.stroke(line, with: .color(color(i).opacity(0.45 * min(1, (2.6 - t) / 0.6))), lineWidth: 1.5)
        }
        for i in 0..<46 {
            let born = 0.15 + Double(i) * 0.026
            let age = t - born
            guard age > 0, age < 0.8 else { continue }
            let origin = position(born)
            let p = CGPoint(x: origin.x - 14 - age * (30 + rnd(i, 1) * 40),
                            y: origin.y + 3 + (rnd(i, 2) - 0.5) * 22 * age + 14 * age * age)
            let r = 2.4 * (1 - age / 0.8)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(color(i).opacity(1 - age / 0.8)))
        }
        guard t < 1.45 else { return }
        var layer = ctx
        let here = position(t)
        layer.translateBy(x: here.x, y: here.y)
        layer.rotate(by: .degrees(45)) // the emoji points up and to the right
        layer.draw(Text("🚀").font(.system(size: 22)), at: .zero)
    }

    /// Confetti falling and swaying, each piece turning.
    private func confetti(_ ctx: inout GraphicsContext) {
        for i in 0..<48 {
            let born = rnd(i, 1) * 0.6
            let age = t - born
            guard age > 0 else { continue }
            let x = rnd(i, 2) * w + sin(age * (3 + rnd(i, 3) * 3) + rnd(i, 4) * 6) * 9
            let y = -8 + age * (34 + rnd(i, 5) * 34)
            guard y < h + 8 else { continue }
            var piece = ctx
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .radians(age * (4 + rnd(i, 6) * 6)))
            piece.scaleBy(x: 1, y: abs(cos(age * 5 + rnd(i, 7) * 3)) * 0.8 + 0.2) // a flat piece flipping
            piece.fill(Path(CGRect(x: -2, y: -3.5, width: 4, height: 7)), with: .color(color(i)))
        }
    }

    /// Flames along the bottom of the row, flickering, and a little smoke.
    private func flames(_ ctx: inout GraphicsContext) {
        let rise = min(1, t / 0.6)
        for i in 0..<12 {
            let puff = (t * 0.9 + rnd(i, 1)).truncatingRemainder(dividingBy: 1)
            let x = rnd(i, 2) * w + sin(t * 2 + Double(i)) * 6
            let y = h - 10 - puff * h * 0.9
            let r = 2 + puff * 5
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                     with: .color(Color.gray.opacity(0.12 * (1 - puff) * rise)))
        }
        let count = 11
        for i in 0..<count {
            let flicker = 0.85 + 0.22 * sin(t * 13 + Double(i) * 1.7) + 0.08 * sin(t * 29 + Double(i))
            let x = (Double(i) + 0.5) / Double(count) * w + (rnd(i, 3) - 0.5) * 8
            let y = h + 6 - rise * (10 + rnd(i, 4) * 8)
            var flame = ctx
            flame.translateBy(x: x, y: y)
            flame.scaleBy(x: flicker, y: flicker * (1 + 0.1 * sin(t * 17 + Double(i))))
            flame.draw(Text("🔥").font(.system(size: 17)), at: .zero)
        }
    }
}
