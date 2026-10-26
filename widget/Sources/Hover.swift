import AppKit
import SwiftUI

/// Hover to click (Settings > Dove vederli, on by default): the pointer on a control acts as a
/// click at once (Nick: "istantaneo, non mezzo secondo"). Once per visit: move away to arm it
/// again. A delay above zero brings back the line filling under it. Over it the pointer turns into a hand. Used only on actions that open or
/// show something (an analysis, the dashboard, a folder, more rows), never on ones that remove,
/// send or change something.
struct DwellClick: ViewModifier {
    let action: () -> Void
    var delay: Double = 0
    @AppStorage("dwellClick") private var enabled = true
    @State private var progress: CGFloat = 0
    @State private var pending: DispatchWorkItem?
    @State private var fired = false
    @State private var inside = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: geo.size.width * progress, height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(y: 3)
                }
                .allowsHitTesting(false)
            }
            .onHover { hovering in
                if hovering != inside {
                    hovering ? NSCursor.pointingHand.push() : NSCursor.pop()
                    inside = hovering
                }
                pending?.cancel()
                pending = nil
                if hovering, enabled, !fired, delay <= 0 {
                    fired = true
                    action()
                } else if hovering, enabled, !fired {
                    withAnimation(.linear(duration: delay)) { progress = 1 }
                    let work = DispatchWorkItem {
                        fired = true
                        reset()
                        action()
                    }
                    pending = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                } else {
                    reset()
                    if !hovering { fired = false }
                }
            }
            .onDisappear {
                pending?.cancel()
                if inside { NSCursor.pop() }
                inside = false
            }
    }

    private func reset() {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { progress = 0 }
    }
}

extension View {
    /// See DwellClick.
    func dwellClick(perform action: @escaping () -> Void) -> some View {
        modifier(DwellClick(action: action))
    }
}
