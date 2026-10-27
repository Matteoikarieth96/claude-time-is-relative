import AppKit
import SwiftUI

// La miniera at the end of a task (Nick: «lanciamo direttamente l'oggetto come in Minecraft, come
// quando rompi un blocco e cade»): instead of the sticker, the find drops into the session's row,
// falls, bounces and rests where «fatto» was, still: nothing moves at rest. A click picks it up,
// with Minecraft's pop, and the row goes off the list as with «fatto». The drops live in memory,
// for as long as their rows are in the list.

final class DropStore: ObservableObject {
    static let shared = DropStore()

    struct Drop: Equatable {
        let ore: Ore
        /// When it fell: only a fresh drop falls, an old one is drawn already on the ground.
        let start: Double
        /// "36s su 30s": the real time on the estimate.
        let detail: String
    }

    /// By the task's key, the row's main task.
    @Published private(set) var drops: [String: Drop] = [:]

    func add(_ key: String, _ drop: Drop) {
        guard drops[key] == nil else { return }
        let cutoff = Date().timeIntervalSince1970 - 2 * 3600   // a finished row stays at most an hour
        drops = drops.filter { $0.value.start > cutoff || $0.value.start == 0 }
        drops[key] = drop
    }

    func remove(_ key: String) { drops[key] = nil }
}

/// The find on the ground of its row: Minecraft's icon (or its square), with a small shadow. The
/// pointer on it lifts it a little; a click collects it.
struct DroppedItem: View {
    let drop: DropStore.Drop
    let onCollect: () -> Void
    @State private var landed = false
    @State private var picked = false
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OreIcon(ore: drop.ore, size: 22)
            .shadow(color: .black.opacity(0.28), radius: 1.2, y: 1.5)
            .scaleEffect(picked ? 1.7 : hover ? 1.15 : 1)
            .opacity(picked ? 0 : 1)
            .offset(y: landed ? (hover ? -2 : 0) : -44)
            .rotationEffect(.degrees(landed ? 0 : -30))
            .frame(width: 26, height: 22)
            .contentShape(Rectangle())
            .onAppear {
                let fresh = drop.start > 0 && Date().timeIntervalSince1970 - drop.start < 2.5
                if fresh && !reduceMotion {
                    // Falls and bounces, then still: a spring that settles in about a second.
                    withAnimation(.interpolatingSpring(stiffness: 240, damping: 9)) { landed = true }
                } else {
                    landed = true
                }
            }
            .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hover = inside } }
            .onTapGesture(perform: collect)
            .help(L("\(drop.ore.name) (\(drop.ore.sign.lowercased())): \(drop.detail). Click to pick it up: the row leaves the list",
                    "\(drop.ore.name) (\(drop.ore.sign.lowercased())): \(drop.detail). Un clic per raccoglierlo: la riga esce dalla lista"))
            .accessibilityLabel(L("\(drop.ore.name), to pick up", "\(drop.ore.name), da raccogliere"))
            .accessibilityAddTraits(.isButton)
            .reportsClickFrame()
    }

    private func collect() {
        guard !picked else { return }
        NSSound(named: "Pop")?.play()
        withAnimation(.easeOut(duration: 0.16)) { picked = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { onCollect() }
    }
}
