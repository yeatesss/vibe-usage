import AppKit
import SwiftUI

// MARK: - SettingsView

struct SettingsView: View {
    @ObservedObject private var locale   = LocaleStore.shared
    @ObservedObject private var settings = SettingsStore.shared

    @State private var section: SettingsSection = .general

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Real macOS Liquid Glass — same material the menu popover uses,
            // so the brightness/sheen matches.
            VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()

            // Subtle white wash + top sheen for extra luminosity.
            ZStack {
                LinearGradient(
                    colors: [.white.opacity(0.30), .white.opacity(0.10), .white.opacity(0.20)],
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(
                    colors: [.white.opacity(0.45), .white.opacity(0)],
                    center: UnitPoint(x: 0.25, y: -0.15),
                    startRadius: 0, endRadius: 360
                )
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 180)
                    .background(Color.white.opacity(0.18))
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Palette.ink.opacity(0.08))
                            .frame(width: 1)
                    }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.top, 28) // room for traffic-light buttons
        }
        .frame(width: 720, height: 540)
        .foregroundStyle(Palette.ink)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsSection.allCases) { s in
                sidebarButton(s)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }

    private func sidebarButton(_ s: SettingsSection) -> some View {
        let on = section == s
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { section = s }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: s.systemImage)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(on ? .white : Palette.ink)
                    .frame(width: 14, height: 14)
                Text(L.t(s.localizationKey, locale: locale.current))
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(on ? Palette.indigo : .clear)
            )
            .foregroundStyle(on ? .white : Palette.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        let t = { (k: String) in L.t(k, locale: locale.current) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PaneTitle(text: t(section.localizationKey))
                    .padding(.bottom, 16)

                switch section {
                case .general:
                    SettingsGroup {
                        SettingsRow(label: t("language"), desc: t("languageDesc")) {
                            SegmentedPicker(
                                selection: $locale.current,
                                options: [
                                    SegmentedOption(id: AppLocale.en, label: "English"),
                                    SegmentedOption(id: AppLocale.zh, label: "中文"),
                                ]
                            )
                        }
                        Hairline()
                        SettingsRow(label: t("refreshInterval")) {
                            DropdownPicker(
                                selection: $settings.refreshInterval,
                                options: RefreshInterval.allCases.map {
                                    ($0, t($0.localizationKey))
                                }
                            )
                        }
                        Hairline()
                        SettingsRow(label: t("startup"), desc: t("startupDesc")) {
                            iOSToggle(isOn: $settings.launchAtLogin)
                        }
                    }

                case .appearance:
                    SettingsGroup {
                        SettingsRow(label: t("menuBarDisplay")) {
                            SegmentedPicker(
                                selection: $settings.menuBarDisplay,
                                options: MenuBarDisplay.allCases.map {
                                    SegmentedOption(id: $0, label: t($0.localizationKey))
                                }
                            )
                        }
                        Hairline()
                        SettingsRow(label: t("theme")) {
                            SegmentedPicker(
                                selection: $settings.theme,
                                options: ThemePreference.allCases.map {
                                    SegmentedOption(id: $0, label: t($0.localizationKey))
                                }
                            )
                        }
                    }

                case .dataSources:
                    DataSourcesPane()

                case .about:
                    AboutPane()
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Sections

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, dataSources, about
    var id: String { rawValue }

    var localizationKey: String { rawValue }

    var systemImage: String {
        switch self {
        case .general:     return "gearshape"
        case .appearance:  return "eye"
        case .dataSources: return "powerplug"
        case .about:       return "info.circle"
        }
    }
}

// MARK: - Atoms

private struct PaneTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
            .tracking(-0.3)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
            )
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.ink.opacity(0.08))
            .frame(height: 1)
    }
}

private struct SettingsRow<Trailing: View>: View {
    let label: String
    var desc: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let desc {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink.opacity(0.55))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Custom controls

private struct SegmentedOption<ID: Hashable>: Identifiable {
    let id: ID
    let label: String
}

private struct SegmentedPicker<ID: Hashable>: View {
    @Binding var selection: ID
    let options: [SegmentedOption<ID>]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { opt in
                let on = selection == opt.id
                Button {
                    selection = opt.id
                } label: {
                    Text(opt.label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(on ? Color.white : .clear)
                                .shadow(color: on ? .black.opacity(0.08) : .clear,
                                        radius: 1, x: 0, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Palette.ink.opacity(0.06))
        )
    }
}

private struct DropdownPicker<ID: Hashable>: View {
    @Binding var selection: ID
    let options: [(id: ID, label: String)]

    var body: some View {
        Menu {
            ForEach(options, id: \.id) { o in
                Button(o.label) { selection = o.id }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentLabel)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.ink.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.15), lineWidth: 1)
            )
            .foregroundStyle(Palette.ink)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var currentLabel: String {
        options.first(where: { $0.id == selection })?.label ?? ""
    }
}

private struct iOSToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isOn ? Palette.green : Palette.ink.opacity(0.18))
                    .frame(width: 38, height: 22)
                Circle()
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 1)
                    .padding(2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Data sources pane (reads real backend connectivity)

private struct DataSourcesPane: View {
    @ObservedObject private var locale = LocaleStore.shared
    @ObservedObject private var store: UsageStore = MenuBarController.shared?.store ?? UsageStore()

    var body: some View {
        let t = { (k: String) in L.t(k, locale: locale.current) }
        SettingsGroup {
            SourceRow(
                tool: .claude,
                name: t("claudeCli"),
                connected: connected(.claude),
                connectedLabel: t("connected"),
                disconnectedLabel: t("notConfigured"),
                configureLabel: t("configure")
            )
            Hairline()
            SourceRow(
                tool: .codex,
                name: t("codexCli"),
                connected: connected(.codex),
                connectedLabel: t("connected"),
                disconnectedLabel: t("notConfigured"),
                configureLabel: t("configure")
            )
        }
    }

    private func connected(_ tool: Tool) -> Bool {
        store.snapshot(tool: tool, range: .today) != nil
    }
}

private struct SourceRow: View {
    let tool: Tool
    let name: String
    let connected: Bool
    let connectedLabel: String
    let disconnectedLabel: String
    let configureLabel: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(connected ? Palette.green : Palette.ink.opacity(0.3))
                .frame(width: 8, height: 8)
                .shadow(color: connected ? Palette.green.opacity(0.6) : .clear,
                        radius: connected ? 4 : 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(connected ? connectedLabel : disconnectedLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
            Button(connected ? "···" : configureLabel) {
                openCliDocs()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.15), lineWidth: 1)
            )
        }
        .padding(.vertical, 10)
    }

    private func openCliDocs() {
        let fm = FileManager.default
        // Mirror the backend's defaults (config.go) so we open the directory
        // it actually scans for this tool.
        let candidates: [String]
        switch tool {
        case .claude: candidates = ["~/.claude/projects", "~/.claude"]
        case .codex:  candidates = ["~/.codex/sessions",  "~/.codex"]
        }
        for raw in candidates {
            let path = NSString(string: raw).expandingTildeInPath
            if fm.fileExists(atPath: path) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                return
            }
        }
        // Nothing exists yet — open the parent so the user can create it.
        let fallback = NSString(string: "~").expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: fallback))
    }
}

// MARK: - About pane

private struct AboutPane: View {
    @ObservedObject private var locale = LocaleStore.shared

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.indigo)
                    .frame(width: 64, height: 64)
                    .shadow(color: Palette.indigo.opacity(0.4), radius: 12, x: 0, y: 8)
                BarMark()
            }
            Text("VibeUsage")
                .font(.system(size: 22, weight: .bold))
            Text("\(L.t("version", locale: locale.current)) \(appVersionString())")
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(0.55))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func appVersionString() -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "dev"
        return "\(short) (build \(build))"
    }
}

private struct BarMark: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 6, height: 14)
            RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 6, height: 24)
            RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 6, height: 32)
        }
    }
}

// MARK: - NSVisualEffectView bridge

private struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}

// MARK: - Palette extension (Preferences-only colors)

private extension Palette {
    static let indigo = Color(red: 0x4E/255, green: 0x6E/255, blue: 0xFB/255)
    static let green  = Color(red: 0x34/255, green: 0xC7/255, blue: 0x59/255)
}
