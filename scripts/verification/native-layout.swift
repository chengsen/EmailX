import AppKit
import SwiftUI

// Production attachment model, strip and wrapping layout are compiled unchanged.
// No system preferences, live account or external UI automation is involved.
@main struct NativeLayoutProbe {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("emailx-layout-\(UUID())")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let attachments = try (0..<40).map { index in
            let url = temporary.appendingPathComponent("\(index)-" + String(repeating: "long-file-附件-", count: 8) + ".txt")
            try Data("synthetic attachment".utf8).write(to: url)
            return try ComposeAttachment(url: url)
        }
        let appearances: [(NSAppearance.Name, ColorScheme)] = [
            (.aqua, .light), (.darkAqua, .dark),
            (.accessibilityHighContrastAqua, .light),
            (.accessibilityHighContrastDarkAqua, .dark)
        ]
        var checks = 0
        for (appearance, scheme) in appearances {
            for width in [CGFloat(560), 900, 1200] {
                for count in [1, 40] {
                    let view = NSHostingView(rootView: ComposeAttachmentsStripView(
                        attachments: Array(attachments.prefix(count)), onRemove: { _ in })
                        .environment(\.colorScheme, scheme)
                        .frame(width: width).fixedSize(horizontal: false, vertical: true))
                    view.appearance = NSAppearance(named: appearance)
                    let size = view.fittingSize
                    precondition(size.width.isFinite && size.height.isFinite && size.width <= width + 1)
                    precondition(size.height > 0 && size.height <= 140.5,
                                 "Attachments displaced editor: \(appearance) \(width) \(count) \(size)")
                    if count == 1 { precondition(size.height < 100, "One attachment wasted viewport height") }
                    checks += 1
                }
            }
        }
        print("PASS \(checks) production attachment layouts: 1/40 long filenames, 560/900/1200pt, Aqua/Dark/high-contrast appearances; no global settings changed")
    }
}
