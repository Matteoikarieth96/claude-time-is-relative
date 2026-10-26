import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Marks for the dashboard. Every project gets its initials on a colour of its own, worked out
// from its name (the same name, the same colour, every time), or a logo Nick drops on it in edit
// mode, kept in ~/.claude/task-eta/logos/<project>.png. Every model family gets a small glyph:
// shapes made up for the dashboard (a hexagon, quatrains, 5-7-5, a moon), nobody's logo.

/// The logos dropped on projects: read again only when their file changes.
final class LogoStore: ObservableObject {
    static let shared = LogoStore()
    /// Bumped when a logo comes or goes, so every mark draws again.
    @Published private(set) var version = 0
    private var cache: [String: (stamp: String, image: NSImage?)] = [:]

    static var dir: URL {
        TaskStore.defaultDir.deletingLastPathComponent().appendingPathComponent("logos", isDirectory: true)
    }

    /// The file of a project's logo: its name, with nothing that could leave the folder.
    static func fileURL(_ project: String) -> URL {
        var name = String(project.map { "/\\:".contains($0) ? "-" : $0 })
        while name.hasPrefix(".") { name.removeFirst() }
        return dir.appendingPathComponent((name.isEmpty ? "progetto" : String(name.prefix(120))) + ".png")
    }

    func image(_ project: String) -> NSImage? {
        let url = LogoStore.fileURL(project)
        let stamp = fileStamp(url.path)
        if let hit = cache[project], hit.stamp == stamp { return hit.image }
        let image = isRegularFile(url.path) ? NSImage(contentsOf: url) : nil
        cache[project] = (stamp, image)
        return image
    }

    /// An image becomes the project's logo: the middle square of it, 128 pixels, as PNG.
    @discardableResult
    func setLogo(_ project: String, from source: URL) -> Bool {
        guard let src = NSImage(contentsOf: source), src.size.width > 0, src.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let scale = max(128 / src.size.width, 128 / src.size.height)
        let w = src.size.width * scale, h = src.size.height * scale
        src.draw(in: NSRect(x: (128 - w) / 2, y: (128 - h) / 2, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try FileManager.default.createDirectory(at: LogoStore.dir, withIntermediateDirectories: true)
            try png.write(to: LogoStore.fileURL(project), options: .atomic)
        } catch {
            return false
        }
        cache[project] = nil
        version += 1
        return true
    }

    /// Back to the initials: the file goes to the Trash, not away for good.
    func removeLogo(_ project: String) {
        try? FileManager.default.trashItem(at: LogoStore.fileURL(project), resultingItemURL: nil)
        cache[project] = nil
        version += 1
    }
}

/// A project's mark: its logo, or its initials on its colour.
struct ProjectMark: View {
    let project: String
    var size: CGFloat = 16
    @ObservedObject private var logos = LogoStore.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Group {
            if let image = logos.image(project) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                shape.fill(ProjectMark.color(project))
                    .overlay {
                        Text(ProjectMark.initials(project, max: size < 15 ? 1 : 2))
                            .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .minimumScaleFactor(0.5)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    /// "acme-sport-reels" AS, "WebShop" WS, "memory" M.
    static func initials(_ name: String, max count: Int = 2) -> String {
        var words = name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.count == 1, let word = words.first {
            // camelCase: a new word at each capital after a small letter.
            var parts: [String] = []
            var current = ""
            for ch in word {
                if ch.isUppercase, let last = current.last, last.isLowercase { parts.append(current); current = "" }
                current.append(ch)
            }
            parts.append(current)
            words = parts
        }
        let letters = words.prefix(count).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    /// Ten hues that sit well together, one per name: the same name always gets the same.
    static func color(_ name: String) -> Color {
        let hues: [Double] = [0.58, 0.47, 0.36, 0.11, 0.02, 0.93, 0.77, 0.66, 0.52, 0.07]
        var hash: UInt32 = 2_166_136_261
        for byte in name.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return Color(hue: hues[Int(hash % UInt32(hues.count))], saturation: 0.55, brightness: 0.74)
    }
}

/// A model family's glyph: opus a solid hexagon (the big work), sonnet four lines (its
/// quatrains), haiku three of 5-7-5, fable a moon (a bedtime story); anything else a ring.
struct ModelGlyph: View {
    let model: String
    var size: CGFloat = 11

    enum Family { case opus, sonnet, haiku, fable, other }

    static func family(_ model: String) -> Family {
        let m = model.lowercased()
        if m.contains("opus") { return .opus }
        if m.contains("sonnet") { return .sonnet }
        if m.contains("haiku") { return .haiku }
        if m.contains("fable") { return .fable }
        return .other
    }

    static func color(_ family: Family) -> Color {
        switch family {
        case .opus: return Color(red: 0.49, green: 0.39, blue: 0.92)
        case .sonnet: return Color(red: 0.12, green: 0.60, blue: 0.64)
        case .haiku: return Color(red: 0.30, green: 0.62, blue: 0.28)
        case .fable: return Color(red: 0.90, green: 0.57, blue: 0.12)
        case .other: return Color.secondary
        }
    }

    var body: some View {
        let family = ModelGlyph.family(model)
        let color = ModelGlyph.color(family)
        Canvas { ctx, s in
            let w = s.width, h = s.height
            switch family {
            case .opus:
                var p = Path()
                for i in 0..<6 {
                    let a = Double(i) * .pi / 3 - .pi / 2
                    let pt = CGPoint(x: w / 2 + w * 0.48 * cos(a), y: h / 2 + h * 0.48 * sin(a))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                p.closeSubpath()
                ctx.fill(p, with: .color(color))
            case .sonnet:
                for i in 0..<4 {
                    let y = h * (0.14 + 0.24 * Double(i))
                    ctx.fill(Path(roundedRect: CGRect(x: w * 0.08, y: y, width: w * 0.84, height: h * 0.13), cornerRadius: h * 0.06),
                             with: .color(color))
                }
            case .haiku:
                for (i, length) in [0.55, 0.85, 0.55].enumerated() {
                    let y = h * (0.18 + 0.27 * Double(i))
                    ctx.fill(Path(roundedRect: CGRect(x: w * (1 - length) / 2, y: y, width: w * length, height: h * 0.16),
                                  cornerRadius: h * 0.08), with: .color(color))
                }
            case .fable:
                var moon = Path(ellipseIn: CGRect(x: w * 0.06, y: h * 0.06, width: w * 0.88, height: h * 0.88))
                moon = moon.subtracting(Path(ellipseIn: CGRect(x: w * 0.34, y: h * -0.06, width: w * 0.8, height: h * 0.8)))
                ctx.fill(moon, with: .color(color))
            case .other:
                ctx.stroke(Path(ellipseIn: CGRect(x: w * 0.15, y: h * 0.15, width: w * 0.7, height: h * 0.7)),
                           with: .color(color), lineWidth: max(1, w * 0.14))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The logos in edit mode: drop an image on a project, or pick one.
struct ProjectLogosEditor: View {
    let projects: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Project logos", "Loghi dei progetti")).font(.system(size: 13, weight: .semibold))
            Text(L("Drag an image onto a project, or choose one. Without a logo, a project gets its initials on a colour all its own.",
                   "Trascina un'immagine su un progetto, o sceglila. Senza logo, il progetto ha le sue iniziali su un colore tutto suo."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if projects.isEmpty {
                Text(L("No projects yet.", "Ancora nessun progetto.")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(projects, id: \.self) { LogoRow(project: $0) }
        }
        .padding(16)
        .frame(width: 340)
    }
}

private struct LogoRow: View {
    let project: String
    @ObservedObject private var logos = LogoStore.shared
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 10) {
            ProjectMark(project: project, size: 28)
            Text(project).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            if logos.image(project) != nil {
                Button(L("Remove", "Togli")) { logos.removeLogo(project) }
                    .help(L("Back to the initials (the file goes to the Trash)", "Torna alle iniziali (il file va nel Cestino)"))
            }
            Button(L("Choose…", "Scegli…")) { choose() }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(targeted ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            return logos.setLogo(project, from: url)
        } isTargeted: { targeted = $0 }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = L("The logo for \(project)", "Il logo di \(project)")
        if panel.runModal() == .OK, let url = panel.url { logos.setLogo(project, from: url) }
    }
}
