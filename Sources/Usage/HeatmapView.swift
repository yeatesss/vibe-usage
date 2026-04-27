import SwiftUI

// MARK: - HeatmapView

/// GitHub-style contribution heatmap: 7 rows (Mon → Sun) × N cols (weeks).
/// Cells stretch to fill the available width; color intensity is bucketed
/// against the snapshot max.
struct HeatmapView: View {
    enum Metric {
        case cost
        case tokens
    }

    enum Size {
        case compact
        case regular

        var gap: CGFloat         { self == .compact ? 2 : 3 }
        var corner: CGFloat      { 2.5 }
        var labelWidth: CGFloat  { self == .compact ? 24 : 36 }
        var labelGap: CGFloat    { self == .compact ? 6 : 8 }
        var monthStripH: CGFloat { self == .compact ? 12 : 16 }
        var labelFont: Font      { .system(size: self == .compact ? 9 : 11) }
        var monthFont: Font      { .system(size: self == .compact ? 9.5 : 11.5, weight: .medium) }
        var legendFont: Font     { .system(size: self == .compact ? 9.5 : 11) }
        var topSpacing: CGFloat  { self == .compact ? 4 : 10 }
    }

    let snapshot: HeatmapSnapshot
    let accent: Color
    var metric: Metric = .cost
    var size: Size = .regular
    var showsLegend: Bool = true

    @ObservedObject private var locale = LocaleStore.shared
    @State private var measuredWidth: CGFloat = 0

    var body: some View {
        let cellSide = computedCellSide(width: measuredWidth)
        VStack(alignment: .leading, spacing: size.topSpacing) {
            monthStrip(cellSide: cellSide)
            HStack(alignment: .top, spacing: size.labelGap) {
                weekdayColumn(cellSide: cellSide)
                grid(cellSide: cellSide)
            }
            if showsLegend {
                legend(cellSide: cellSide)
            }
        }
        .background(
            GeometryReader { g in
                Color.clear.preference(key: WidthPreferenceKey.self, value: g.size.width)
            }
        )
        .onPreferenceChange(WidthPreferenceKey.self) { w in
            if abs(w - measuredWidth) > 0.5 {
                measuredWidth = w
            }
        }
    }

    // MARK: Grid

    private func grid(cellSide: CGFloat) -> some View {
        HStack(alignment: .top, spacing: size.gap) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, column in
                VStack(spacing: size.gap) {
                    ForEach(0..<7, id: \.self) { row in
                        cell(for: column[row], side: cellSide)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(for day: HeatmapDay?, side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size.corner, style: .continuous)
            .fill(fill(for: day))
            .overlay(
                RoundedRectangle(cornerRadius: size.corner, style: .continuous)
                    .strokeBorder(borderColor(for: day), lineWidth: 0.5)
            )
            .frame(width: side, height: side)
            .help(day.map(tooltipString) ?? "")
    }

    // MARK: Weekday labels (all 7)

    private var weekdayStrings: [String] {
        locale.current == .zh
            ? ["一", "二", "三", "四", "五", "六", "日"]
            : ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }

    private func weekdayColumn(cellSide: CGFloat) -> some View {
        VStack(spacing: size.gap) {
            ForEach(0..<7, id: \.self) { i in
                Text(weekdayStrings[i])
                    .font(size.labelFont)
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .frame(width: size.labelWidth, height: cellSide, alignment: .trailing)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Month strip (aligned with the grid)

    private func monthStrip(cellSide: CGFloat) -> some View {
        let gridW = cellSide * CGFloat(max(weeks.count, 1))
                    + size.gap * CGFloat(max(weeks.count - 1, 0))
        let visible = visibleMonthMarkers(cellSide: cellSide)
        return HStack(spacing: 0) {
            Spacer().frame(width: size.labelWidth + size.labelGap)
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: gridW, height: size.monthStripH)
                ForEach(visible, id: \.index) { marker in
                    Text(marker.label)
                        .font(size.monthFont)
                        .foregroundStyle(Palette.ink.opacity(0.6))
                        .fixedSize()
                        .offset(x: CGFloat(marker.index) * (cellSide + size.gap))
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Drop markers whose pixel offset would collide with the previous one.
    /// Uses a rough 22pt label-width estimate so "Apr" and "May" don't fuse.
    private func visibleMonthMarkers(cellSide: CGFloat) -> [MonthMarker] {
        let stride = cellSide + size.gap
        let minPx: CGFloat = locale.current == .zh ? 16 : 24
        let minCols = max(Int((minPx / max(stride, 1)).rounded(.up)), 1)
        var out: [MonthMarker] = []
        var lastIdx: Int? = nil
        for m in monthMarkers {
            if let last = lastIdx, m.index - last < minCols { continue }
            out.append(m)
            lastIdx = m.index
        }
        return out
    }

    // MARK: Legend

    private func legend(cellSide: CGFloat) -> some View {
        let swatch = min(max(cellSide, 9), 14)
        return HStack(spacing: 4) {
            Spacer().frame(width: size.labelWidth + size.labelGap)
            Text(L.t("less", locale: locale.current))
                .font(size.legendFont)
                .foregroundStyle(Palette.ink.opacity(0.5))
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: size.corner, style: .continuous)
                    .fill(color(level: level))
                    .frame(width: swatch, height: swatch)
                    .overlay(
                        RoundedRectangle(cornerRadius: size.corner, style: .continuous)
                            .strokeBorder(Palette.ink.opacity(0.06), lineWidth: 0.5)
                    )
            }
            Text(L.t("more", locale: locale.current))
                .font(size.legendFont)
                .foregroundStyle(Palette.ink.opacity(0.5))
            Spacer(minLength: 0)
        }
    }

    // MARK: Responsive cell size

    /// Cell side = (availableWidth - weekdayLabel - gap - inter-col gaps) / weekCount.
    /// Clamped to [3, 40] so the grid still renders during the first measurement frame.
    private func computedCellSide(width: CGFloat) -> CGFloat {
        let weekCount = max(weeks.count, 1)
        let usable = width - size.labelWidth - size.labelGap
        let totalGap = CGFloat(weekCount - 1) * size.gap
        let raw = (usable - totalGap) / CGFloat(weekCount)
        if !raw.isFinite || raw < 3 { return 3 }
        return min(raw, 40)
    }

    // MARK: Weeks shaping

    /// Group days into columns (weeks). Each column is an array of 7 optional
    /// days indexed by weekday (Mon=0..Sun=6).
    private var weeks: [[HeatmapDay?]] {
        guard !snapshot.days.isEmpty else { return [] }
        let weekCount = snapshot.days.count / 7
        var out: [[HeatmapDay?]] = []
        out.reserveCapacity(weekCount)
        for w in 0..<weekCount {
            var col: [HeatmapDay?] = Array(repeating: nil, count: 7)
            for d in 0..<7 {
                let idx = w * 7 + d
                if idx < snapshot.days.count { col[d] = snapshot.days[idx] }
            }
            out.append(col)
        }
        return out
    }

    // MARK: Month markers

    private struct MonthMarker { let index: Int; let label: String }

    private var monthMarkers: [MonthMarker] {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Singapore") ?? .current
        let df = DateFormatter()
        df.calendar = c
        df.locale = Locale(identifier: locale.current == .zh ? "zh_CN" : "en_US")
        df.timeZone = c.timeZone
        df.dateFormat = locale.current == .zh ? "M月" : "MMM"

        var markers: [MonthMarker] = []
        var lastMonth: Int = -1
        for (i, col) in weeks.enumerated() {
            guard let first = col.compactMap({ $0 }).first else { continue }
            let comps = c.dateComponents([.month], from: first.date)
            if let m = comps.month, m != lastMonth {
                markers.append(MonthMarker(index: i, label: df.string(from: first.date)))
                lastMonth = m
            }
        }
        return markers
    }

    // MARK: Coloring

    private var maxValue: Double {
        switch metric {
        case .cost:   return snapshot.maxCost
        case .tokens: return snapshot.maxTokens
        }
    }

    private func value(of day: HeatmapDay) -> Double {
        switch metric {
        case .cost:   return day.cost
        case .tokens: return day.totalTokens
        }
    }

    private func level(for day: HeatmapDay) -> Int {
        guard !day.isFuture else { return -1 }
        let max = maxValue
        let v = value(of: day)
        guard max > 0, v > 0 else { return 0 }
        let r = v / max
        if r > 0.66 { return 4 }
        if r > 0.33 { return 3 }
        if r > 0.10 { return 2 }
        return 1
    }

    private func fill(for day: HeatmapDay?) -> Color {
        guard let day else { return Palette.ink.opacity(0.04) }
        let lv = level(for: day)
        if lv == -1 { return Palette.ink.opacity(0.02) } // future
        return color(level: lv)
    }

    private func borderColor(for day: HeatmapDay?) -> Color {
        guard let day else { return Palette.ink.opacity(0.06) }
        if Calendar.current.isDate(day.date, inSameDayAs: snapshot.today) {
            return Palette.ink.opacity(0.55)
        }
        return Palette.ink.opacity(0.06)
    }

    private func color(level: Int) -> Color {
        switch level {
        case 0:  return Palette.ink.opacity(0.06)
        case 1:  return accent.opacity(0.25)
        case 2:  return accent.opacity(0.45)
        case 3:  return accent.opacity(0.70)
        default: return accent.opacity(0.95)
        }
    }

    // MARK: Tooltip

    private func tooltipString(for day: HeatmapDay) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: locale.current == .zh ? "zh_CN" : "en_US")
        df.dateStyle = .medium
        let date = df.string(from: day.date)
        if day.isFuture {
            return date
        }
        let cost = String(format: "$%.4f", day.cost)
        let tokens = Fmt.tokens(day.totalTokens)
        let reqs = Fmt.int(day.requests)
        if locale.current == .zh {
            return "\(date) · \(cost) · \(tokens) Token · \(reqs) 次请求"
        }
        return "\(date) · \(cost) · \(tokens) tokens · \(reqs) reqs"
    }
}

// MARK: - Preference key

private struct WidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
