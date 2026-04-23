import SwiftUI

// MARK: - Hero view mode

private enum HeroView { case cost, tokens }

// MARK: - MenuPanelView

struct MenuPanelView: View {
    @State private var tool: Tool = .claude
    @State private var range: Range = .today
    @State private var heroView: HeroView = .cost
    @ObservedObject private var locale = LocaleStore.shared
    @ObservedObject var store: UsageStore
    @Namespace private var animationNS

    private var snapshot: UsageSnapshot { store.snapshot(tool: tool, range: range) ?? .empty }
    private var metrics: UsageMetrics { snapshot.metrics }
    private var tabAnim: Animation { .spring(response: 0.38, dampingFraction: 0.85) }
    private var numAnim: Animation { .smooth(duration: 0.45) }

    var body: some View {
        VStack(spacing: 0) {
            toolTabs
            VStack(spacing: 0) {
                header.padding(.horizontal, 16).padding(.top, 6)
                rangeGrid.padding(.horizontal, 16).padding(.top, 4)
                heroCard.padding(.horizontal, 16).padding(.top, 8)
                hairline.padding(.horizontal, 16).padding(.top, 14)

                breakdown.padding(.horizontal, 16).padding(.top, 4)
                hairline.padding(.horizontal, 16).padding(.top, 14)

                actions.padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 8)
            }
        }
        .frame(width: 360)
        .foregroundStyle(Palette.ink)
        .background(liquidGlassSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
        )
        .task(id: tool.id) {
            await store.loadAll(tool: tool)
        }
    }

    // MARK: Surface (macOS 26 Liquid Glass)

    private var liquidGlassSurface: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [.white.opacity(0.55), .white.opacity(0.25), .white.opacity(0.40)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [.white.opacity(0.55), .white.opacity(0)],
                center: UnitPoint(x: 0.3, y: -0.2),
                startRadius: 0, endRadius: 240
            )
            .allowsHitTesting(false)
        }
    }

    // MARK: Tool tabs

    private var toolTabs: some View {
        HStack(spacing: 4) {
            ForEach(Tool.allCases) { t in
                ToolTabButton(
                    tool: t,
                    label: L.t(t.displayKey, locale: locale.current),
                    active: tool == t,
                    namespace: animationNS
                ) {
                    withAnimation(tabAnim) { tool = t }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: Header — title + (synced/sessions stacked)

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(L.t(tool.displayKey, locale: locale.current))
                .font(.system(size: 21, weight: .semibold))
                .tracking(-0.4)
                .lineLimit(1)
                .fixedSize()
            VStack(alignment: .leading, spacing: 1) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(L.t("syncedAgo", locale: locale.current, params: ["time": syncedAgoLabel(now: context.date)]))
                }
                Text(L.t("sessions",  locale: locale.current, params: ["n": "\(snapshot.sessions)"]))
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.ink.opacity(0.5))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
    }

    // MARK: Range grid — Today $X / Week $X / Month $X / Year $X

    private var rangeGrid: some View {
        HStack(spacing: 6) {
            ForEach(Range.allCases) { r in
                RangeCard(
                    label: L.t(r.rawValue, locale: locale.current),
                    cost: store.cost(tool: tool, range: r),
                    accent: tool.accent,
                    active: r == range,
                    namespace: animationNS
                ) {
                    withAnimation(tabAnim) { range = r }
                }
            }
        }
    }

    // MARK: Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                heroTab("estCost", value: .cost)
                heroTab("tokens",  value: .tokens)
            }
            Text(tool.pricing)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.ink.opacity(0.45))
                .lineLimit(1)

            if heroView == .cost { costHero } else { tokensHero }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var costHero: some View {
        let avg = metrics.cost / Double(max(metrics.requests, 1))
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text(String(format: "$%.2f", metrics.cost))
                    .font(.system(size: 32, weight: .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(tool.accent)
                    .monospacedDigit()
                    .fixedSize()
                    .contentTransition(.numericText(value: metrics.cost))
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Fmt.tokens(metrics.total)) tokens")
                        .contentTransition(.numericText(value: metrics.total))
                    Text(L.t("requestsLine", locale: locale.current, params: ["req": Fmt.int(metrics.requests)]))
                        .contentTransition(.numericText(value: Double(metrics.requests)))
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(0.6))
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
            }
            Text(L.t("avgPerReq", locale: locale.current, params: ["v": String(format: "$%.4f", avg)]))
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink.opacity(0.5))
                .monospacedDigit()
                .contentTransition(.numericText(value: avg))
            sparklineWithLabels.padding(.top, 6)
        }
        .animation(numAnim, value: metrics.cost)
        .animation(numAnim, value: metrics.total)
        .animation(numAnim, value: metrics.requests)
    }

    @ViewBuilder
    private var tokensHero: some View {
        let series = metricSeries
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text(Fmt.tokens(metrics.total))
                    .font(.system(size: 32, weight: .semibold))
                    .tracking(-0.8)
                    .monospacedDigit()
                    .fixedSize()
                    .contentTransition(.numericText(value: metrics.total))
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(String(format: "$%.2f", metrics.cost)) cost")
                        .contentTransition(.numericText(value: metrics.cost))
                    Text(L.t("requestsLine", locale: locale.current, params: ["req": Fmt.int(metrics.requests)]))
                        .contentTransition(.numericText(value: Double(metrics.requests)))
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(0.6))
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
            }
            HStack(spacing: 10) {
                ForEach(series) { s in
                    HStack(spacing: 4) {
                        Rectangle().fill(s.color).frame(width: 8, height: 2).cornerRadius(1)
                        Text(L.t(s.id, locale: locale.current))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.ink.opacity(0.62))
                    }
                }
            }
            .padding(.top, 4)
            MultiLineView(
                series: series,
                tooltipLabels: tooltipLabels,
                seriesDisplayName: { L.t($0, locale: locale.current) }
            )
            .frame(height: 54)
            .padding(.top, 4)
            seriesLabelsRow
        }
        .animation(numAnim, value: metrics.cost)
        .animation(numAnim, value: metrics.total)
        .animation(numAnim, value: metrics.requests)
    }

    private var sparklineWithLabels: some View {
        VStack(spacing: 2) {
            SparklineView(
                data: costSeries,
                color: tool.accent,
                tooltipLabels: tooltipLabels,
                valueFormatter: { String(format: "$%.4f", $0) }
            )
            .frame(height: 44)
            seriesLabelsRow
        }
    }

    // Proportionally distribute total cost across the token-shaped series so the
    // sparkline keeps its visual shape while tooltips surface per-bucket cost.
    private var costSeries: [Double] {
        let tokens = snapshot.series
        let total = tokens.reduce(0, +)
        guard total > 0 else { return Array(repeating: 0, count: tokens.count) }
        let scale = metrics.cost / total
        return tokens.map { $0 * scale }
    }

    private var seriesLabelsRow: some View {
        let labels = snapshot.labels.filter { !$0.isEmpty }
        return HStack {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.ink.opacity(0.45))
                if i < labels.count - 1 { Spacer() }
            }
        }
    }

    private var tooltipLabels: [String] {
        let n = snapshot.series.count
        guard n > 0 else { return [] }
        switch range {
        case .today:
            return (0..<n).map { i in
                i == n - 1 ? L.t("now", locale: locale.current) : String(format: "%02d:00", i)
            }
        case .week:
            let zh = ["周一","周二","周三","周四","周五","周六","周日"]
            let en = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
            let arr = locale.current == .zh ? zh : en
            return (0..<n).map { i in i < arr.count ? arr[i] : "#\(i + 1)" }
        case .month:
            let dayKey = locale.current == .zh ? "第%d天" : "Day %d"
            return (0..<n).map { i in String(format: dayKey, i + 1) }
        case .year:
            let raw = (0..<n).map { i in i < snapshot.labels.count ? snapshot.labels[i] : "" }
            return raw.enumerated().map { i, s in s.isEmpty ? "M\(i + 1)" : s }
        }
    }

    private func syncedAgoLabel(now: Date) -> String {
        guard let t = store.lastSyncedAt else { return "—" }
        let secs = max(Int(now.timeIntervalSince(t)), 0)
        if secs < 60 { return "\(secs)s" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h"
    }

    private var metricSeries: [MultiLineView.Series] {
        let base = snapshot.series
        let baseSum = max(base.reduce(0, +), 0.0001)
        func scale(_ value: Double) -> [Double] { base.map { $0 * value / baseSum } }
        return [
            MultiLineView.Series(id: "cacheRead",  color: Palette.cacheRead,  data: scale(metrics.cacheRead)),
            MultiLineView.Series(id: "input",      color: Palette.input,      data: scale(metrics.input)),
            MultiLineView.Series(id: "output",     color: Palette.output,     data: scale(metrics.output)),
            MultiLineView.Series(id: "cacheWrite", color: Palette.cacheWrite, data: scale(metrics.cacheWrite)),
        ]
    }

    private func heroTab(_ key: String, value: HeroView) -> some View {
        Button {
            withAnimation(tabAnim) { heroView = value }
        } label: {
            Text(L.t(key, locale: locale.current).uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(heroView == value ? Color.white : Palette.ink.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background {
                    if heroView == value {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Palette.ink)
                            .matchedGeometryEffect(id: "heroTabBg", in: animationNS)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Breakdown

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("tokenBreakdown", locale: locale.current))
                .font(.system(size: 15, weight: .semibold))
            StackedBar(segments: stackSegments).frame(height: 8)
            VStack(spacing: 6) {
                MetricRow(color: Palette.input,      label: L.t("input",      locale: locale.current), value: metrics.input,      total: metrics.total)
                MetricRow(color: Palette.output,     label: L.t("output",     locale: locale.current), value: metrics.output,     total: metrics.total)
                MetricRow(color: Palette.cacheRead,  label: L.t("cacheRead",  locale: locale.current), value: metrics.cacheRead,  total: metrics.total)
                MetricRow(color: Palette.cacheWrite, label: L.t("cacheWrite", locale: locale.current), value: metrics.cacheWrite, total: metrics.total)
            }
        }
    }

    private var stackSegments: [StackedBar.Segment] {
        [
            .init(value: metrics.cacheRead,  color: Palette.cacheRead),
            .init(value: metrics.input,      color: Palette.input),
            .init(value: metrics.output,     color: Palette.output),
            .init(value: metrics.cacheWrite, color: Palette.cacheWrite),
        ]
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 0) {
            Button {
                MenuBarController.shared?.closePopover()
                StatsWindowController.shared.show(store: store)
            } label: {
                ActionRow(icon: "chart.bar.fill", label: L.t("openDashboard", locale: locale.current), kbd: "⌘⇧U")
            }
            .buttonStyle(.plain)
            // TODO: 暂未实现，先屏蔽
            // ActionRow(icon: "square.and.arrow.up", label: L.t("exportCsv", locale: locale.current))
            // ActionRow(icon: "bell",                label: L.t("budgets",   locale: locale.current))
            insetHairline
            Button {
                MenuBarController.shared?.closePopover()
                SettingsWindowController.shared.show()
            } label: {
                ActionRow(label: L.t("preferences", locale: locale.current), kbd: "⌘,", plain: true)
            }
            .buttonStyle(.plain)
            Button {
                NSApp.terminate(nil)
            } label: {
                ActionRow(label: L.t("quit", locale: locale.current), kbd: "⌘Q", plain: true)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Hairlines

    private var hairline: some View {
        Rectangle().fill(Palette.ink.opacity(0.10)).frame(height: 1)
    }
    private var insetHairline: some View {
        Rectangle().fill(Palette.ink.opacity(0.10)).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 6)
    }
}

// MARK: - Subviews

private struct ToolTabButton: View {
    let tool: Tool
    let label: String
    let active: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                glyph
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .foregroundStyle(active ? Color.white : Palette.ink)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tool.accent)
                        .matchedGeometryEffect(id: "toolTabBg", in: namespace)
                } else if hover {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    @ViewBuilder
    private var glyph: some View {
        switch tool {
        case .claude:
            Image(systemName: "sparkle").font(.system(size: 13, weight: .semibold))
        case .codex:
            Image(systemName: "atom").font(.system(size: 13, weight: .semibold))
        }
    }
}

// New: rich range card with gradient + accent fill when active
private struct RangeCard: View {
    let label: String
    let cost: Double
    let accent: Color
    let active: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(active ? Color.white.opacity(0.9) : Palette.ink.opacity(0.55))
                    .lineLimit(1)
                Text(String(format: "$%.2f", cost))
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.2)
                    .monospacedDigit()
                    .foregroundStyle(active ? Color.white : Palette.ink)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: cost))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.8), .white.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        ))
                    if active {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accent)
                            .matchedGeometryEffect(id: "rangeCardBg", in: namespace)
                            .shadow(color: accent.opacity(0.25), radius: 6, x: 0, y: 3)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(active ? accent : Color.white.opacity(0.9), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StackedBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let value: Double
        let color: Color
    }
    let segments: [Segment]

    var body: some View {
        GeometryReader { geo in
            let total = max(segments.reduce(0) { $0 + $1.value }, 0.0001)
            HStack(spacing: 0) {
                ForEach(segments) { s in
                    Rectangle().fill(s.color)
                        .frame(width: geo.size.width * CGFloat(s.value / total))
                }
            }
            .clipShape(Capsule())
        }
        .background(Capsule().fill(Palette.ink.opacity(0.08)))
    }
}

private struct MetricRow: View {
    let color: Color
    let label: String
    let value: Double
    let total: Double

    var body: some View {
        let pct = value / max(total, 0.0001) * 100
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(0.8))
                .frame(width: 90, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.ink.opacity(0.08)).frame(height: 4)
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(pct/100), height: 4)
                }
            }
            .frame(height: 4)
            Text(Fmt.tokens(value))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)
                .contentTransition(.numericText(value: value))
            Text(pct < 10 ? String(format: "%.1f%%", pct) : String(format: "%.0f%%", pct))
                .font(.system(size: 11))
                .foregroundStyle(Palette.ink.opacity(0.5))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
                .contentTransition(.numericText(value: pct))
        }
        .animation(.smooth(duration: 0.45), value: value)
    }
}

private struct ActionRow: View {
    var icon: String? = nil
    let label: String
    var kbd: String? = nil
    var plain: Bool = false
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 18)
            } else {
                Spacer().frame(width: plain ? 0 : 18)
            }
            Text(label).font(.system(size: plain ? 13 : 13.5, weight: .regular))
            Spacer(minLength: 0)
            if let kbd {
                Text(kbd)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(hover ? Color.white.opacity(0.8) : Palette.ink.opacity(0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, plain ? 4 : 6)
        .foregroundStyle(hover ? Color.white : Palette.ink)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hover ? Color(red: 0x4E/255, green: 0x6E/255, blue: 0xFB/255) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
