import SwiftUI

// Single-series area sparkline with left-to-right draw animation.
struct SparklineView: View {
    let data: [Double]
    let color: Color
    var fillOpacity: Double = 0.22
    var tooltipLabels: [String] = []
    var valueFormatter: (Double) -> String = { Fmt.tokens($0) }

    @State private var drawProgress: CGFloat = 0

    var body: some View {
        ZStack {
            SparkAreaShape(data: data)
                .fill(color.opacity(fillOpacity))
                .mask(
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: geo.size.width * drawProgress)
                    }
                )
            SparkLineShape(data: data)
                .trim(from: 0, to: drawProgress)
                .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
        .overlay(
            ChartCrosshair(
                data: data,
                color: color,
                labels: tooltipLabels,
                valueFormatter: valueFormatter
            )
            .opacity(drawProgress >= 0.999 ? 1 : 0)
        )
        .onAppear { animateDraw() }
        .onChange(of: data) { _, _ in animateDraw() }
    }

    private func animateDraw() {
        drawProgress = 0
        withAnimation(.easeOut(duration: 0.6)) { drawProgress = 1 }
    }
}

private struct SparkLineShape: Shape {
    let data: [Double]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard data.count > 1 else { return p }
        let maxV = max(data.max() ?? 1, 0.0001)
        let stepX = rect.width / CGFloat(data.count - 1)
        for (i, v) in data.enumerated() {
            let x = CGFloat(i) * stepX
            let y = rect.height - CGFloat(v / maxV) * rect.height
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else      { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

private struct SparkAreaShape: Shape {
    let data: [Double]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard data.count > 1 else { return p }
        let maxV = max(data.max() ?? 1, 0.0001)
        let stepX = rect.width / CGFloat(data.count - 1)
        for (i, v) in data.enumerated() {
            let x = CGFloat(i) * stepX
            let y = rect.height - CGFloat(v / maxV) * rect.height
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else      { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

// Stacked bar chart — N series stacked per X bucket.
// SwiftUI-driven so we can animate bars (grow-from-bottom with stagger) and
// attach a hover crosshair + tooltip showing per-segment + total values.
struct StackedBarChartView: View {
    struct Series: Identifiable, Equatable {
        let id: String
        let color: Color
        let data: [Double]

        static func == (lhs: Series, rhs: Series) -> Bool {
            lhs.id == rhs.id && lhs.data == rhs.data
        }
    }

    let series: [Series]
    let labels: [String]
    var seriesDisplayName: (String) -> String = { $0 }
    var totalLabel: String = "Total"
    var valueFormatter: (Double) -> String = { Fmt.tokens($0) }

    @State private var growProgress: [CGFloat] = []
    @State private var hoverX: CGFloat? = nil

    private var bucketCount: Int { series.first?.data.count ?? 0 }

    private var totals: [Double] {
        (0..<bucketCount).map { i in
            series.reduce(0.0) { $0 + ($1.data.indices.contains(i) ? $1.data[i] : 0) }
        }
    }

    private var maxTotal: Double {
        max(totals.max() ?? 1, 0.0001)
    }

    var body: some View {
        GeometryReader { geo in
            let axisInset: CGFloat = 22
            let plotW = geo.size.width
            let plotH = max(geo.size.height - axisInset, 0.0001)
            let n = bucketCount
            let columnW = n > 0 ? plotW / CGFloat(n) : 0
            let barW = columnW * 0.62
            let focused = focusIndex(columnW: columnW, x: hoverX, count: n)

            ZStack(alignment: .topLeading) {
                // Bars
                ForEach(Array(0..<n), id: \.self) { i in
                    let progress = growProgress.indices.contains(i) ? growProgress[i] : 0
                    let isDimmed = focused != nil && focused != i

                    stackedBar(index: i, plotH: plotH)
                        .frame(width: barW, height: plotH, alignment: .bottom)
                        .scaleEffect(x: 1, y: progress, anchor: .bottom)
                        .opacity(isDimmed ? 0.35 : 1.0)
                        .animation(.easeOut(duration: 0.18), value: focused)
                        .position(
                            x: CGFloat(i) * columnW + columnW / 2,
                            y: plotH / 2
                        )
                }

                // X-axis labels
                ForEach(Array(0..<n), id: \.self) { i in
                    if i < labels.count, !labels[i].isEmpty {
                        Text(labels[i])
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.gray.opacity(0.7))
                            .position(
                                x: CGFloat(i) * columnW + columnW / 2,
                                y: plotH + 11
                            )
                    }
                }

                // Hover crosshair + tooltip
                if let i = focused {
                    let anchorX = CGFloat(i) * columnW + columnW / 2

                    Path { p in
                        p.move(to: CGPoint(x: anchorX, y: 0))
                        p.addLine(to: CGPoint(x: anchorX, y: plotH))
                    }
                    .stroke(Palette.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    barTooltip(index: i)
                        .position(tooltipPositionInChart(
                            plotSize: CGSize(width: plotW, height: plotH),
                            anchorX: anchorX,
                            tooltipW: 210,
                            tooltipH: estimatedTooltipHeight
                        ))
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
            .frame(width: plotW, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hoverX = p.x
                case .ended:         hoverX = nil
                }
            }
            .animation(.easeOut(duration: 0.15), value: hoverX != nil)
            .onAppear { animateGrow() }
            .onChange(of: series) { _, _ in animateGrow() }
        }
    }

    // One stacked column — ZStack of bottom-anchored rectangles.
    // Only the outermost (topmost) segment gets rounded top corners so inter-
    // segment seams stay flat and crisp; inner segments use plain rectangles.
    @ViewBuilder
    private func stackedBar(index: Int, plotH: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            // Draw from the top segment down so lower layers visually sit underneath.
            ForEach(Array(series.enumerated().reversed()), id: \.element.id) { pair in
                let s = pair.element
                let isTopSegment = pair.offset == series.count - 1
                let upToTop = series.prefix(pair.offset + 1).reduce(0.0) { acc, ss in
                    acc + (ss.data.indices.contains(index) ? ss.data[index] : 0)
                }
                let h = CGFloat(upToTop / maxTotal) * plotH
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: isTopSegment ? 3 : 0,
                        bottomLeading: 0,
                        bottomTrailing: 0,
                        topTrailing: isTopSegment ? 3 : 0
                    ),
                    style: .continuous
                )
                .fill(s.color)
                .frame(height: h)
            }
        }
    }

    // MARK: Tooltip

    private var estimatedTooltipHeight: CGFloat {
        let padding: CGFloat = 12
        let rowH: CGFloat = 14
        let spacing: CGFloat = 3
        let hasLabel = !labels.allSatisfy { $0.isEmpty }
        // series rows + divider (~5) + total row + optional label row
        let rows = series.count + 1 + (hasLabel ? 1 : 0)
        return padding + CGFloat(rows) * rowH + CGFloat(max(rows - 1, 0)) * spacing + 6
    }

    @ViewBuilder
    private func barTooltip(index: Int) -> some View {
        let label = index < labels.count ? labels[index] : ""
        let total = series.reduce(0.0) {
            $0 + ($1.data.indices.contains(index) ? $1.data[index] : 0)
        }

        VStack(alignment: .leading, spacing: 3) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            ForEach(series) { s in
                let v = s.data.indices.contains(index) ? s.data[index] : 0
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1.5).fill(s.color).frame(width: 6, height: 6)
                    Text(seriesDisplayName(s.id))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer(minLength: 6)
                    Text(valueFormatter(v))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
            Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5).padding(.vertical, 1)
            HStack(spacing: 5) {
                Text(totalLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 6)
                Text(valueFormatter(total))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.ink.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 3)
        .fixedSize()
    }

    // MARK: Hover math

    private func focusIndex(columnW: CGFloat, x: CGFloat?, count: Int) -> Int? {
        guard let x, count > 0, columnW > 0 else { return nil }
        let raw = Int(floor(x / columnW))
        return max(0, min(count - 1, raw))
    }

    // Place the tooltip at the top of the plot area, clamped horizontally so it
    // never exceeds the chart bounds and never overlaps the legend above.
    private func tooltipPositionInChart(
        plotSize: CGSize,
        anchorX: CGFloat,
        tooltipW: CGFloat,
        tooltipH: CGFloat
    ) -> CGPoint {
        let halfW = tooltipW / 2
        let halfH = tooltipH / 2
        let clampedX = max(halfW, min(plotSize.width - halfW, anchorX))
        let y = halfH + 4
        return CGPoint(x: clampedX, y: y)
    }

    // MARK: Animation

    private func animateGrow() {
        // Resize immediately, without animation, so bar count changes don't
        // cascade into partial animations.
        growProgress = Array(repeating: 0, count: bucketCount)
        // Stagger each column so the chart "waves" up from the left.
        for i in 0..<bucketCount {
            let delay = Double(i) * 0.025
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(delay)) {
                if growProgress.indices.contains(i) {
                    growProgress[i] = 1
                }
            }
        }
    }
}


// Mini stacked-bar / sparkbars used in metric cards.
struct SparkBarsView: View {
    let data: [Double]
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard !data.isEmpty else { return }
            let maxV = max(data.max() ?? 1, 0.0001)
            let stride = size.width / CGFloat(data.count)
            let barW = stride * 0.7
            let gap = (stride - barW) / 2
            for (i, v) in data.enumerated() {
                let h = CGFloat(v / maxV) * size.height
                let rect = CGRect(x: CGFloat(i) * stride + gap, y: size.height - h, width: barW, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
    }
}

// Overlay of N line series, each scaled to its own max so shapes are comparable.
struct MultiLineView: View {
    struct Series: Identifiable, Equatable {
        let id: String
        let color: Color
        let data: [Double]

        static func == (lhs: Series, rhs: Series) -> Bool {
            lhs.id == rhs.id && lhs.data == rhs.data
        }
    }
    let series: [Series]
    var tooltipLabels: [String] = []
    var seriesDisplayName: (String) -> String = { $0 }
    var valueFormatter: (Double) -> String = { Fmt.tokens($0) }

    @State private var drawProgress: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(series) { s in
                SparkLineShape(data: s.data)
                    .trim(from: 0, to: drawProgress)
                    .stroke(s.color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            }
        }
        .overlay(
            MultiLineCrosshair(
                series: series,
                labels: tooltipLabels,
                seriesDisplayName: seriesDisplayName,
                valueFormatter: valueFormatter
            )
            .opacity(drawProgress >= 0.999 ? 1 : 0)
        )
        .onAppear { animateDraw() }
        .onChange(of: series) { _, _ in animateDraw() }
    }

    private func animateDraw() {
        drawProgress = 0
        withAnimation(.easeOut(duration: 0.6)) { drawProgress = 1 }
    }
}

// MARK: - Crosshair overlays

/// Vertical dashed cursor + focus dot + tooltip for a single-series chart.
private struct ChartCrosshair: View {
    let data: [Double]
    let color: Color
    let labels: [String]
    let valueFormatter: (Double) -> String

    @State private var hoverX: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            let n = data.count
            ZStack(alignment: .topLeading) {
                Color.clear
                if n > 1, let i = focusIndex(in: geo.size, x: hoverX) {
                    let stepX = geo.size.width / CGFloat(n - 1)
                    let maxV  = max(data.max() ?? 1, 0.0001)
                    let v     = data[i]
                    let xPos  = CGFloat(i) * stepX
                    let yPos  = geo.size.height - CGFloat(v / maxV) * geo.size.height
                    let label = i < labels.count ? labels[i] : ""

                    Path { p in
                        p.move(to: CGPoint(x: xPos, y: 0))
                        p.addLine(to: CGPoint(x: xPos, y: geo.size.height))
                    }
                    .stroke(Palette.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    Circle()
                        .fill(color)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .frame(width: 7, height: 7)
                        .position(x: xPos, y: yPos)

                    crosshairTooltip(label: label, value: valueFormatter(v))
                        .position(tooltipPosition(
                            in: geo.size,
                            anchorX: xPos,
                            tooltipW: 120,
                            tooltipH: 20
                        ))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hoverX = p.x
                case .ended:         hoverX = nil
                }
            }
        }
    }
}

/// Vertical dashed cursor + dot per series + multi-line tooltip.
private struct MultiLineCrosshair: View {
    let series: [MultiLineView.Series]
    let labels: [String]
    let seriesDisplayName: (String) -> String
    let valueFormatter: (Double) -> String

    @State private var hoverX: CGFloat? = nil

    // Estimate tooltip height from its structure so we can float it above the
    // chart frame without relying on async size measurement (PreferenceKey-based
    // measurement was not settling before first render).
    private var estimatedTooltipHeight: CGFloat {
        let padding: CGFloat = 10
        let rowH: CGFloat = 14
        let spacing: CGFloat = 3
        let hasLabel = labels.contains(where: { !$0.isEmpty })
        let rows = series.count + (hasLabel ? 1 : 0)
        return padding + CGFloat(rows) * rowH + CGFloat(max(rows - 1, 0)) * spacing
    }

    var body: some View {
        GeometryReader { geo in
            let n = series.first?.data.count ?? 0
            ZStack(alignment: .topLeading) {
                Color.clear
                if n > 1, let i = focusIndexFor(count: n, in: geo.size, x: hoverX) {
                    let stepX = geo.size.width / CGFloat(n - 1)
                    let xPos  = CGFloat(i) * stepX
                    let label = i < labels.count ? labels[i] : ""

                    Path { p in
                        p.move(to: CGPoint(x: xPos, y: 0))
                        p.addLine(to: CGPoint(x: xPos, y: geo.size.height))
                    }
                    .stroke(Palette.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    ForEach(series) { s in
                        let v = s.data.indices.contains(i) ? s.data[i] : 0
                        let maxV = max(s.data.max() ?? 1, 0.0001)
                        let yPos = geo.size.height - CGFloat(v / maxV) * geo.size.height
                        Circle()
                            .fill(s.color)
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .frame(width: 6, height: 6)
                            .position(x: xPos, y: yPos)
                    }

                    multiTooltip(label: label, index: i)
                        .position(tooltipPosition(
                            in: geo.size,
                            anchorX: xPos,
                            tooltipW: 180,
                            tooltipH: estimatedTooltipHeight
                        ))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hoverX = p.x
                case .ended:         hoverX = nil
                }
            }
        }
    }

    @ViewBuilder
    private func multiTooltip(label: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            ForEach(series) { s in
                let v = s.data.indices.contains(index) ? s.data[index] : 0
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1.5).fill(s.color).frame(width: 6, height: 6)
                    Text(seriesDisplayName(s.id))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 6)
                    Text(valueFormatter(v))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 5).fill(Palette.ink.opacity(0.88)))
        .fixedSize()
    }
}

// MARK: - Crosshair shared helpers

private extension ChartCrosshair {
    func focusIndex(in size: CGSize, x: CGFloat?) -> Int? {
        guard let x, data.count > 1, size.width > 0 else { return nil }
        let stepX = size.width / CGFloat(data.count - 1)
        let raw = Int((x / stepX).rounded())
        return max(0, min(data.count - 1, raw))
    }

    @ViewBuilder
    func crosshairTooltip(label: String, value: String) -> some View {
        let composed = label.isEmpty ? value : "\(label) · \(value)"
        Text(composed)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Palette.ink.opacity(0.88)))
            .fixedSize()
    }
}

private func focusIndexFor(count: Int, in size: CGSize, x: CGFloat?) -> Int? {
    guard let x, count > 1, size.width > 0 else { return nil }
    let stepX = size.width / CGFloat(count - 1)
    let raw = Int((x / stepX).rounded())
    return max(0, min(count - 1, raw))
}

// Float the tooltip above the chart frame so it never obscures the focus point
// or the trend lines, even when the focus is at the chart's highest y.
// Horizontally clamp within the chart width so the box leans right/left near
// edges instead of overflowing the hero card.
private func tooltipPosition(
    in size: CGSize,
    anchorX: CGFloat,
    tooltipW: CGFloat,
    tooltipH: CGFloat
) -> CGPoint {
    let halfW = tooltipW / 2
    let halfH = tooltipH / 2
    let gap: CGFloat = 8
    let clampedX = max(halfW, min(size.width - halfW, anchorX))
    let y = -halfH - gap
    return CGPoint(x: clampedX, y: y)
}
