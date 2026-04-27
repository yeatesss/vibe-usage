import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

// MARK: - Setting enums

enum RefreshInterval: String, CaseIterable, Identifiable {
    case s30 = "30s"
    case m1  = "1m"
    case m5  = "5m"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .s30: return 30
        case .m1:  return 60
        case .m5:  return 300
        }
    }

    var localizationKey: String {
        switch self {
        case .s30: return "every30s"
        case .m1:  return "every1m"
        case .m5:  return "every5m"
        }
    }
}

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case iconOnly, todayCost, tokens
    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .iconOnly:  return "displayIconOnly"
        case .todayCost: return "displayTodayCost"
        case .tokens:    return "displayTokens"
        }
    }
}

enum ThemePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .system: return "themeSystem"
        case .light:  return "themeLight"
        case .dark:   return "themeDark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - SettingsStore

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private enum Key {
        static let refresh = "settings.refreshInterval"
        static let launch  = "settings.launchAtLogin"
        static let display = "settings.menuBarDisplay"
        static let theme   = "settings.theme"
    }

    @Published var refreshInterval: RefreshInterval { didSet {
        guard refreshInterval != oldValue else { return }
        defaults.set(refreshInterval.rawValue, forKey: Key.refresh)
    }}

    @Published var launchAtLogin: Bool { didSet {
        guard launchAtLogin != oldValue else { return }
        defaults.set(launchAtLogin, forKey: Key.launch)
        applyLaunchAtLogin()
    }}

    @Published var menuBarDisplay: MenuBarDisplay { didSet {
        guard menuBarDisplay != oldValue else { return }
        defaults.set(menuBarDisplay.rawValue, forKey: Key.display)
    }}

    @Published var theme: ThemePreference { didSet {
        guard theme != oldValue else { return }
        defaults.set(theme.rawValue, forKey: Key.theme)
        applyTheme()
    }}

    private let defaults = UserDefaults.standard

    private init() {
        self.refreshInterval = RefreshInterval(
            rawValue: UserDefaults.standard.string(forKey: Key.refresh) ?? ""
        ) ?? .s30
        self.menuBarDisplay = MenuBarDisplay(
            rawValue: UserDefaults.standard.string(forKey: Key.display) ?? ""
        ) ?? .todayCost
        self.theme = ThemePreference(
            rawValue: UserDefaults.standard.string(forKey: Key.theme) ?? ""
        ) ?? .system
        // Default launchAtLogin to the OS truth (avoids drift if user toggled
        // it from System Settings)
        let storedLaunch = UserDefaults.standard.object(forKey: Key.launch) as? Bool
        self.launchAtLogin = storedLaunch ?? (SMAppService.mainApp.status == .enabled)
    }

    /// Apply settings that need OS-side state (theme, login item) on launch.
    func applyOnLaunch() {
        applyTheme()
        // Reconcile the in-memory toggle with reality, in case the user
        // changed it via System Settings since our last run.
        let real = SMAppService.mainApp.status == .enabled
        if real != launchAtLogin { launchAtLogin = real }
    }

    private func applyTheme() {
        NSApp.appearance = theme.nsAppearance
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            FileHandle.standardError.write(
                Data("[SettingsStore] launchAtLogin toggle failed: \(error.localizedDescription)\n".utf8)
            )
        }
    }
}
