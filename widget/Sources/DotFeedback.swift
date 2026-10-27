import AppKit
import AVFoundation
import SwiftUI

// The "in corso" dot when clicked: it squashes while pressed, jolts at every click (harder and
// harder towards the 101st), shows the count above it and makes a sound that depends on the press:
// a short plop for a tap, a boing for a long press, higher with every click.

struct Jolt {
    var scale = 1.0
    var angle = 0.0
    var dx = 0.0
    var dy = 0.0
}

struct CountPop {
    var opacity = 0.0
    var y = 0.0
    var scale = 0.6
}

/// The green dot and "in corso", the easter egg's button.
struct RunningDot: View {
    /// Every click ever: it always grows, so it triggers the jolt and the number's pop.
    let dotClicks: Int
    let onDot: ((Double) -> Void)?
    let golf: GolfGame?
    /// The other way to the mini golf: drag the dot while holding ⌘, M and G.
    var onUnlock: (() -> Void)? = nil
    /// The clicks of this run (TaskStore.dotRun): the number shown, the jolt's strength.
    var run: Int? = nil
    @State private var pressedAt: Date?
    /// While the mini golf is locked the dot follows the pointer when dragged.
    @State private var drag: CGSize = .zero
    @State private var unlockedNow = false
    /// The dot pulses while the clicks go on and stops once they stop (TaskStore.runGap), not for good.
    @State private var pulsing = false
    @State private var lastPulseClick = 0

    var body: some View {
        let badge = HStack(spacing: 3) {
            dot.offset(drag)
            Text(L("running", "in corso"))
        }
        .foregroundStyle(Color.green)
        if let onDot {
            badge
                .contentShape(Rectangle())
                .gesture(press(onDot))
                .reportsClickFrame()
                .help(golf != nil ? L("Hold me down and pull, like a slingshot", "Tienimi premuto e tira, come una fionda") : "")
        } else {
            badge
        }
    }

    private var dot: some View {
        let shown = run ?? dotClicks
        let amp = 1.2 + Double(min(shown, 101)) / 22  // the jolt grows towards the 101st click of the run
        return Image(systemName: "circle.fill")
            .imageScale(.small)
            .symbolEffect(.pulse, options: .repeating.speed(min(6, 1 + Double(shown) / 3)), isActive: pulsing)
            .onChange(of: dotClicks) { _, clicks in
                pulsing = true
                lastPulseClick = clicks
                DispatchQueue.main.asyncAfter(deadline: .now() + TaskStore.runGap) {
                    if lastPulseClick == clicks { pulsing = false }
                }
            }
            .scaleEffect(pressedAt == nil ? 1 : 0.65)
            .animation(.spring(duration: 0.14), value: pressedAt == nil)
            .keyframeAnimator(initialValue: Jolt(), trigger: dotClicks) { content, v in
                content
                    .scaleEffect(v.scale)
                    .rotationEffect(.degrees(v.angle))
                    .offset(x: v.dx, y: v.dy)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.75, duration: 0.07)
                    CubicKeyframe(0.8, duration: 0.09)
                    SpringKeyframe(1, duration: 0.25)
                }
                KeyframeTrack(\.dx) {
                    LinearKeyframe(amp, duration: 0.035)
                    LinearKeyframe(-amp, duration: 0.035)
                    LinearKeyframe(amp * 0.8, duration: 0.035)
                    LinearKeyframe(-amp * 0.8, duration: 0.035)
                    LinearKeyframe(amp * 0.5, duration: 0.035)
                    LinearKeyframe(0, duration: 0.04)
                }
                KeyframeTrack(\.dy) {
                    LinearKeyframe(-amp * 0.6, duration: 0.04)
                    LinearKeyframe(amp * 0.6, duration: 0.04)
                    LinearKeyframe(-amp * 0.3, duration: 0.04)
                    LinearKeyframe(0, duration: 0.05)
                }
                KeyframeTrack(\.angle) {
                    LinearKeyframe(amp * 6, duration: 0.04)
                    LinearKeyframe(-amp * 6, duration: 0.05)
                    LinearKeyframe(0, duration: 0.06)
                }
            }
            .overlay(alignment: .top) { counter }
    }

    /// The click's number, popping above the dot and fading.
    private var counter: some View {
        Text("\(run ?? dotClicks)")
            .font(.timer(10, .heavy))
            .foregroundStyle(Color.green)
            .fixedSize()
            .keyframeAnimator(initialValue: CountPop(), trigger: dotClicks) { content, v in
                content.opacity(v.opacity).scaleEffect(v.scale).offset(y: v.y)
            } keyframes: { _ in
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(1, duration: 0.02)
                    LinearKeyframe(1, duration: 0.5)
                    LinearKeyframe(0, duration: 0.35)
                }
                KeyframeTrack(\.y) {
                    LinearKeyframe(-6, duration: 0.02)
                    SpringKeyframe(-17, duration: 0.45)
                    LinearKeyframe(-23, duration: 0.4)
                }
                KeyframeTrack(\.scale) {
                    LinearKeyframe(0.7, duration: 0.02)
                    SpringKeyframe(1.15, duration: 0.2)
                    SpringKeyframe(1, duration: 0.3)
                }
            }
            .allowsHitTesting(false)
    }

    /// Every press counts, however fast (macOS turns quick clicks into double and triple clicks);
    /// with the mini golf unlocked a pull is a shot instead.
    private func press(_ onDot: @escaping (Double) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("golf"))
            .onChanged { v in
                if pressedAt == nil {
                    pressedAt = Date()
                    unlockedNow = false
                    // Locked: the app comes in front, so that ⌘M and the letters come to it and not
                    // to the app in front (⌘M would shrink its window, M and G would be typed there).
                    if golf == nil, onUnlock != nil { NSApp.activate(ignoringOtherApps: true) }
                }
                let moved = hypot(v.translation.width, v.translation.height) > 4
                if let golf, moved {
                    golf.pull(from: v.startLocation, to: v.location)
                } else if golf == nil, let onUnlock, moved {
                    drag = CGSize(width: max(-60, min(60, v.translation.width)), height: max(-30, min(30, v.translation.height)))
                    if !unlockedNow, GolfKeys.held() {
                        unlockedNow = true
                        onUnlock()
                    }
                }
            }
            .onEnded { v in
                let held = Date().timeIntervalSince(pressedAt ?? Date())
                pressedAt = nil
                let moved = hypot(v.translation.width, v.translation.height) > 4
                if let golf, moved {
                    golf.release()
                } else if !moved {
                    onDot(held)
                }
                withAnimation(.spring(duration: 0.35, bounce: 0.4)) { drag = .zero }
            }
    }
}

/// ⌘, M and G held together, read from the system's key state (no permission needed, and it works
/// whichever app is in front).
enum GolfKeys {
    static func held() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
            && CGEventSource.keyState(.combinedSessionState, key: 0x2E) // M
            && CGEventSource.keyState(.combinedSessionState, key: 0x05) // G
    }
}

/// The dot's sound: a short plop for a tap, a boing for a long press; the note rises with the
/// clicks, about two octaves up to the 101st. The audio engine stops when the clicking does.
final class DotSound {
    static let shared = DotSound()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var idle: DispatchWorkItem?
    private let rate = 44100.0
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)

    func click(count: Int, held: Double) {
        guard let format, let buffer = sound(count: count, held: held, format: format) else { return }
        if engine == nil {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            guard (try? engine.start()) != nil else { return }
            self.engine = engine
            self.player = player
        }
        player?.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if player?.isPlaying == false { player?.play() }
        idle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.player?.stop()
            self?.engine?.stop()
            self?.engine = nil
            self?.player = nil
        }
        idle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func sound(count: Int, held: Double, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let base = 330 * pow(2, Double(min(count, 101)) / 48)
        let long = held >= 0.2
        let length = long ? 0.34 : 0.09
        let frames = AVAudioFrameCount(length * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var phase = 0.0
        for i in 0..<Int(frames) {
            let t = Double(i) / rate
            let f: Double
            let env: Double
            if long { // boing: up from low, wobbling, slow to die
                f = base * 0.5 * (1 + 0.6 * (1 - exp(-t * 28))) * (1 + 0.07 * sin(2 * .pi * 11 * t))
                env = min(1, t / 0.004) * exp(-t * 7)
            } else { // plop: a quick drop in pitch, gone in a blink
                f = base * (1.6 - 0.6 * min(1, t / 0.05))
                env = min(1, t / 0.002) * exp(-t * 42)
            }
            phase += f / rate
            let sample = sin(2 * .pi * phase) + 0.25 * sin(4 * .pi * phase)
            data[i] = Float(0.22 * env * sample)
        }
        return buffer
    }
}
