import SwiftUI

struct StatsView: View {
    @State private var tool: Tool = .claude
    @State private var range: Range = .week
    @ObservedObject private var locale = LocaleStore.shared
    @ObservedObject var store: UsageStore
    @Namespace private var animationNS

    private var snapshot: UsageSnapshot { store.snapshot(tool: tool, range: range) ?? .empty }
    private var metrics: UsageMetrics { snapshot.metrics }
    private var tabAnim: Animation { .spring(response: 0.38, dampingFraction: 0.85) }
    private var numAnim: Animation { .smooth(duration: 0.45) }

    private let dashboardHeatmapWeeks = 52

    var body: some View {
        VStack(spacing: 0) {
            topBar
            subHeader
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        main
                        Divider()
                        sidebar
                    }
                    heatmapSection
                }
            }
        }
        .background(statsBackground)
        .foregroundStyle(Palette.ink)
        .task(id: tool.id) {
            await store.loadAll(tool: tool)
            await store.loadHeatmap(tool: tool, weeks: dashboardHeatmapWeeks)
        }
    }

    // MARK: Heatmap section (full width, below main + sidebar)

    private var heatmapSection: some View {
        let snap = store.heatmap(tool: tool, weeks: dashboardHeatmapWeeks) ?? .empty
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("activity", locale: locale.current))
                    .font(.system(size: 14, weight: .semibold))
                Text(L.t("activitySub", locale: locale.current, params: ["weeks": "\(dashboardHeatmapWeeks)"]))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink.opacity(0.55))
            }
            HeatmapView(snapshot: snap, accent: tool.accent, metric: .cost, size: .regular)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
        )
        .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 22)
    }

    // MARK: Background — same liquid-glass family

    private var statsBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [.white.opacity(0.55), .white.opacity(0.30), .white.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.white)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(red: 0x4E/255, green: 0x6E/255, blue: 0xFB/255)))
            Text("VibeUsage").font(.system(size: 13, weight: .semibold))
            Text("— " + L.t("dashboard", locale: locale.current))
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink.opacity(0.55))
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(Tool.allCases) { t in
                    Button {
                        withAnimation(tabAnim) { tool = t }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: t == .claude ? "sparkle" : "atom")
                                .font(.system(size: 11))
                            Text(L.t(t.displayKey, locale: locale.current))
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .foregroundStyle(tool == t ? .white : Palette.ink)
                        .background {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.white.opacity(0.5))
                                if tool == t {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(t.accent)
                                        .matchedGeometryEffect(id: "topToolBg", in: animationNS)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.white.opacity(0.3))
        .overlay(Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1), alignment: .bottom)
    }

    // MARK: Subheader — big number + range tabs

    private var subHeader: some View {
        HStack(alignment: .lastTextBaseline, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rangeSubtitle.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.ink.opacity(0.55))
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(String(format: "$%.2f", metrics.cost))
                        .font(.system(size: 32, weight: .semibold))
                        .tracking(-0.8)
                        .monospacedDigit()
                        .foregroundStyle(tool.accent)
                        .contentTransition(.numericText(value: metrics.cost))
                    Text(L.t(
                        "tokensRequestsLine",
                        locale: locale.current,
                        params: ["tokens": Fmt.tokens(metrics.total), "req": Fmt.int(metrics.requests)]
                    ))
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.ink.opacity(0.62))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: metrics.total))
                }
                .animation(numAnim, value: metrics.cost)
                .animation(numAnim, value: metrics.total)
                .animation(numAnim, value: metrics.requests)
            }
            Spacer(minLength: 0)
            rangePicker
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .overlay(Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1), alignment: .bottom)
    }

    private var rangePicker: some View {
        HStack(spacing: 0) {
            ForEach(Range.allCases) { r in
                Button {
                    withAnimation(tabAnim) { range = r }
                } label: {
                    Text(L.t(r.rawValue, locale: locale.current))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(range == r ? Color.white : Palette.ink.opacity(0.65))
                        .frame(minWidth: 56)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background {
                            if range == r {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Palette.ink)
                                    .matchedGeometryEffect(id: "rangePickerBg", in: animationNS)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
        )
    }

    private var rangeSubtitle: String {
        let key: String
        switch range {
        case .today: key = "rangeSubToday"
        case .week:  key = "rangeSubWeek"
        case .month: key = "rangeSubMonth"
        case .year:  key = "rangeSubYear"
        }
        return L.t(key, locale: locale.current)
    }

    // MARK: Main column (chart + metric cards)

    private var main: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L.t("tokenUsageStacked", locale: locale.current))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 12) {
                    legendDot(Palette.cacheRead,  L.t("cacheRead",  locale: locale.current))
                    legendDot(Palette.input,      L.t("input",      locale: locale.current))
                    legendDot(Palette.output,     L.t("output",     locale: locale.current))
                    legendDot(Palette.cacheWrite, L.t("cacheWrite", locale: locale.current))
                }
            }

            StackedBarChartView(
                series: stackedSeries,
                labels: snapshot.labels,
                seriesDisplayName: { id in L.t(id, locale: locale.current) },
                totalLabel: L.t("total", locale: locale.current)
            )
                .frame(height: 230)
                .padding(.horizontal, 12).padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
                )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricCard(label: L.t("input",      locale: locale.current), value: metrics.input,      color: Palette.input,      series: scaledSeries(metrics.input))
                metricCard(label: L.t("output",     locale: locale.current), value: metrics.output,     color: Palette.output,     series: scaledSeries(metrics.output))
                metricCard(label: L.t("cacheRead",  locale: locale.current), value: metrics.cacheRead,  color: Palette.cacheRead,  series: scaledSeries(metrics.cacheRead))
                metricCard(label: L.t("cacheWrite", locale: locale.current), value: metrics.cacheWrite, color: Palette.cacheWrite, series: scaledSeries(metrics.cacheWrite))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var stackedSeries: [StackedBarChartView.Series] {
        [
            .init(id: "cacheRead",  color: Palette.cacheRead,  data: scaledSeries(metrics.cacheRead)),
            .init(id: "input",      color: Palette.input,      data: scaledSeries(metrics.input)),
            .init(id: "output",     color: Palette.output,     data: scaledSeries(metrics.output)),
            .init(id: "cacheWrite", color: Palette.cacheWrite, data: scaledSeries(metrics.cacheWrite)),
        ]
    }

    private func scaledSeries(_ totalValue: Double) -> [Double] {
        let base = snapshot.series
        let baseSum = max(base.reduce(0, +), 0.0001)
        return base.map { $0 * totalValue / baseSum }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.ink.opacity(0.62))
        }
    }

    private func metricCard(label: String, value: Double, color: Color, series: [Double]) -> some View {
        let pct = value / max(metrics.total, 0.0001)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
                Text(label.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Palette.ink.opacity(0.55))
                Spacer()
                Text(String(format: "%.1f%%", pct * 100))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.ink.opacity(0.45))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: pct))
            }
            HStack(alignment: .center, spacing: 10) {
                Text(Fmt.tokens(value))
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.4)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
                Spacer()
                SparkBarsView(data: series, color: color)
                    .frame(width: 80, height: 24)
            }
        }
        .animation(numAnim, value: value)
        .padding(.horizontal, 13).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
        )
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            sideSection(title: L.t("estimatedCost", locale: locale.current)) {
                Text(String(format: "$%.2f", metrics.cost))
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.6)
                    .monospacedDigit()
                    .foregroundStyle(tool.accent)
                    .contentTransition(.numericText(value: metrics.cost))
                Text(tool.pricing)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                Text(L.t(
                    "avgPerReq",
                    locale: locale.current,
                    params: ["v": String(format: "$%.4f", metrics.cost / Double(max(metrics.requests, 1)))]
                ))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: metrics.cost / Double(max(metrics.requests, 1))))
            }
            .animation(numAnim, value: metrics.cost)
            sideDivider
            sideSection(title: L.t("allPeriods", locale: locale.current)) {
                ForEach(Range.allCases) { r in
                    let snap = store.snapshot(tool: tool, range: r) ?? .empty
                    Button {
                        withAnimation(tabAnim) { range = r }
                    } label: {
                        HStack {
                            Text(L.t(r.rawValue, locale: locale.current).uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(r == range ? Palette.ink : Palette.ink.opacity(0.55))
                                .frame(width: 60, alignment: .leading)
                            Text(Fmt.tokens(snap.metrics.total))
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.ink.opacity(0.55))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: snap.metrics.total))
                            Spacer()
                            Text(String(format: "$%.2f", snap.metrics.cost))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(tool.accent)
                                .monospacedDigit()
                                .contentTransition(.numericText(value: snap.metrics.cost))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background {
                            if r == range {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Palette.ink.opacity(0.08))
                                    .matchedGeometryEffect(id: "allPeriodsBg", in: animationNS)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .animation(numAnim, value: snap.metrics.cost)
                }
            }
            sideDivider
            sideSection(title: L.t("requestStats", locale: locale.current)) {
                kv(L.t("requests",        locale: locale.current), Fmt.int(metrics.requests),                                                  numericAnchor: Double(metrics.requests))
                kv(L.t("avgTokensPerReq", locale: locale.current), Fmt.tokens(metrics.total / Double(max(metrics.requests, 1))),               numericAnchor: metrics.total / Double(max(metrics.requests, 1)))
                kv(L.t("avgCostPerReq",   locale: locale.current), String(format: "$%.4f", metrics.cost / Double(max(metrics.requests, 1))),   numericAnchor: metrics.cost / Double(max(metrics.requests, 1)))
            }
            .animation(numAnim, value: metrics.requests)
            .animation(numAnim, value: metrics.total)
            .animation(numAnim, value: metrics.cost)
            Spacer()
        }
        .padding(18)
        .frame(width: 260, alignment: .topLeading)
        .background(Color.white.opacity(0.22))
    }

    @ViewBuilder
    private func sideSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Palette.ink.opacity(0.5))
                .padding(.bottom, 2)
            content()
        }
    }
    private var sideDivider: some View {
        Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1)
    }
    private func kv(_ k: String, _ v: String, numericAnchor: Double) -> some View {
        HStack {
            Text(k).font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.6))
            Spacer()
            Text(v).font(.system(size: 12, weight: .medium)).monospacedDigit()
                .contentTransition(.numericText(value: numericAnchor))
        }
        .padding(.vertical, 3)
    }
}
