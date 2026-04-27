import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    static private(set) var shared: MenuBarController?

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    let store: UsageStore
    let backend: BackendProcess
    private var cancellables: Set<AnyCancellable> = []
    private var refreshTimer: Timer?

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        self.store = UsageStore()
        self.backend = BackendProcess()
        super.init()
        backend.ensureRunning()
        configurePopover()
        configureStatusItem()
        Self.shared = self
        SettingsStore.shared.applyOnLaunch()
        bindStatusItem()
        bindSettings()
        startInitialLoad()
        startRefreshTimer()
    }

    func closePopover() {
        if popover.isShown { popover.performClose(nil) }
    }

    private func configurePopover() {
        popover.contentSize = NSSize(width: 360, height: 720)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuPanelView(store: store))
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = barChartIcon()
        button.imagePosition = .imageLeading
        button.title = " $—"
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.target = self
        button.action = #selector(togglePopover(_:))
    }

    private func bindStatusItem() {
        store.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusTitle() }
            .store(in: &cancellables)
    }

    private func bindSettings() {
        SettingsStore.shared.$refreshInterval
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.startRefreshTimer()
                Task { @MainActor [weak self] in
                    await self?.syncTickToBackend()
                }
            }
            .store(in: &cancellables)

        SettingsStore.shared.$menuBarDisplay
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusTitle() }
            .store(in: &cancellables)
    }

    private func refreshStatusTitle() {
        guard let button = statusItem.button else { return }
        switch SettingsStore.shared.menuBarDisplay {
        case .iconOnly:
            button.title = ""
        case .todayCost:
            let total = store.cost(tool: .claude, range: .today)
                      + store.cost(tool: .codex,  range: .today)
            button.title = String(format: " $%.2f", total)
        case .tokens:
            let total = (store.snapshot(tool: .claude, range: .today)?.metrics.total ?? 0)
                      + (store.snapshot(tool: .codex,  range: .today)?.metrics.total ?? 0)
            button.title = " " + Fmt.tokens(total)
        }
    }

    private func startInitialLoad() {
        Task { @MainActor in
            // backend was just spawned; runtime.json may not exist for ~100-300ms.
            // Retry until either a snapshot lands or we give up after ~3s.
            for attempt in 0..<10 {
                await store.loadAll(tool: .claude)
                await store.loadAll(tool: .codex)
                if store.snapshot(tool: .claude, range: .today) != nil {
                    await syncTickToBackend()
                    return
                }
                if attempt < 9 { try? await Task.sleep(nanoseconds: 300_000_000) }
            }
            // Even if no snapshot landed (e.g. cold install with no usage),
            // still push the preferred tick so the backend uses it next scan.
            await syncTickToBackend()
        }
    }

    private func syncTickToBackend() async {
        await store.pushBackendTick(seconds: SettingsStore.shared.refreshInterval.seconds)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = SettingsStore.shared.refreshInterval.seconds
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.store.load(tool: .claude, range: .today)
                await self.store.load(tool: .codex,  range: .today)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func barChartIcon() -> NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let bars: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = [
                (1.5, 1.5, 2, 5),
                (5,   1.5, 2, 8.5),
                (8.5, 1.5, 2, 11),
            ]
            NSColor.labelColor.setFill()
            for b in bars {
                let path = NSBezierPath(roundedRect: NSRect(x: b.x, y: b.y, width: b.w, height: b.h),
                                        xRadius: 0.6, yRadius: 0.6)
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
