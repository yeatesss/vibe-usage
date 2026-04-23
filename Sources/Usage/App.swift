import AppKit
import SwiftUI

@main
struct VibeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar?.backend.terminate()
    }
}
