import AppKit
import SwiftUI

@MainActor
final class StatsWindowController {
    static let shared = StatsWindowController()

    private var window: NSWindow?

    private init() {}

    func show(store: UsageStore) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "VibeUsage — Dashboard"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 820, height: 560)
            w.center()
            w.contentView = NSHostingView(rootView: StatsView(store: store))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
