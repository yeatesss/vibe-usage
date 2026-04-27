import SwiftUI

/// The Projects view: master list on the left, detail on the right. Lives
/// inside the Stats window; takes ownership of search & sort state.
struct ProjectsMasterDetail: View {
    let tool: Tool
    let range: Range
    let snapshot: ProjectsSnapshot
    @Binding var selectedProject: String?
    @ObservedObject var store: UsageStore

    @ObservedObject private var locale = LocaleStore.shared

    enum SortKey: String, CaseIterable, Identifiable {
        case cost, tokens, requests, recent, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .cost:     return "byCost"
            case .tokens:   return "byTokens"
            case .requests: return "byRequests"
            case .recent:   return "byRecent"
            case .name:     return "byName"
            }
        }
    }

    @State private var query: String = ""
    @State private var sortKey: SortKey = .cost
    @FocusState private var searchFocused: Bool

    private var filtered: [Project] {
        var list = snapshot.projects
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.displayName.lowercased().contains(q)
                || $0.cwd.lowercased().contains(q)
            }
        }
        switch sortKey {
        case .cost:     list.sort { $0.cost > $1.cost }
        case .tokens:   list.sort { $0.totalTokens > $1.totalTokens }
        case .requests: list.sort { $0.requests > $1.requests }
        case .name:     list.sort { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        case .recent:
            list.sort { (a, b) in
                (a.lastActiveAt ?? .distantPast) > (b.lastActiveAt ?? .distantPast)
            }
        }
        return list
    }

    var body: some View {
        HStack(spacing: 0) {
            master
                .frame(width: 320)
                .background(Color.white.opacity(0.18))
            Divider()
            detail
        }
    }

    // MARK: - Master list

    private var master: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { p in
                            row(for: p)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                                        selectedProject = p.cwd
                                    }
                                    Task { await store.load(tool: tool, range: range, project: p.cwd) }
                                }
                        }
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                TextField(L.t("searchProjects", locale: locale.current), text: $query)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.08), lineWidth: 1)
            )

            Picker("", selection: $sortKey) {
                ForEach(SortKey.allCases) { k in
                    Text(L.t(k.label, locale: locale.current)).tag(k)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 90)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("—")
                .font(.system(size: 18))
                .foregroundStyle(Palette.ink.opacity(0.45))
            Text(L.t(query.isEmpty ? "noProjectsInRange" : "noMatchingProjects",
                     locale: locale.current))
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(0.55))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func row(for p: Project) -> some View {
        let isActive = (selectedProject == p.cwd)
        let isInactive = (p.cost <= 0 && p.totalTokens <= 0)
        return HStack(spacing: 0) {
            // accent stripe on active
            Rectangle()
                .fill(isActive ? tool.accent : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(p.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(isInactive ? Palette.ink.opacity(0.6) : Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(isInactive ? "—" : Fmt.money(p.cost))
                        .font(.system(size: 12.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isInactive ? Palette.ink.opacity(0.4) : tool.accent)
                }

                Text(p.cwd.isEmpty ? L.t("unknownProject", locale: locale.current) : truncatedPath(p.cwd))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.head)

                breakdownBar(for: p, dim: isInactive)
                    .frame(height: 4)

                HStack(spacing: 8) {
                    Text(isInactive
                         ? L.t("inactive", locale: locale.current)
                         : "\(Fmt.int(p.requests)) req")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.ink.opacity(0.5))
                    if let last = p.lastActiveAt {
                        Text("·")
                            .foregroundStyle(Palette.ink.opacity(0.3))
                        Text(relativeAgo(last))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.ink.opacity(0.5))
                    }
                }
            }
            .padding(.leading, 11)
            .padding(.trailing, 14)
            .padding(.vertical, 9)
        }
        .background(
            isActive
            ? tool.accent.opacity(0.10)
            : Color.clear
        )
        .contentShape(Rectangle())
        .overlay(Rectangle().fill(Palette.ink.opacity(0.05)).frame(height: 1), alignment: .bottom)
    }

    private func breakdownBar(for p: Project, dim: Bool) -> some View {
        let total = max(p.totalTokens, 1)
        let inputW   = p.inputTokens / total
        let outputW  = p.outputTokens / total
        let cReadW   = p.cacheReadTokens / total
        let cWriteW  = p.cacheWriteTokens / total
        return GeometryReader { g in
            HStack(spacing: 0) {
                Rectangle().fill(Palette.cacheRead).frame(width: g.size.width * cReadW)
                Rectangle().fill(Palette.input).frame(width: g.size.width * inputW)
                Rectangle().fill(Palette.output).frame(width: g.size.width * outputW)
                Rectangle().fill(Palette.cacheWrite).frame(width: g.size.width * cWriteW)
            }
            .opacity(dim ? 0.35 : 1)
            .clipShape(Capsule())
            .background(Capsule().fill(Palette.ink.opacity(0.05)))
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let cwd = selectedProject,
           let p = snapshot.projects.first(where: { $0.cwd == cwd }) {
            ProjectDetailView(
                tool: tool, range: range,
                project: p, store: store
            )
        } else {
            allProjectsDetail
        }
    }

    private var allProjectsDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(L.t("allProjectsTitle", locale: locale.current))
                    .font(.system(size: 20, weight: .semibold))
                Text("\(snapshot.projects.count) · \(Fmt.money(snapshot.totalCost))")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink.opacity(0.55))
            }

            statsCards(
                cost: snapshot.totalCost,
                tokens: snapshot.totalTokens,
                requests: snapshot.totalRequests,
                sessions: snapshot.projects.reduce(0) { $0 + $1.sessions }
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("pickAProject", locale: locale.current))
                    .font(.system(size: 13, weight: .semibold))
                Text(L.t("pickAProjectHint", locale: locale.current))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink.opacity(0.55))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
            )
            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private func statsCards(cost: Double, tokens: Double, requests: Int, sessions: Int) -> some View {
        HStack(spacing: 10) {
            statCard(L.t("estCost", locale: locale.current), Fmt.money(cost), accent: tool.accent)
            statCard(L.t("tokens", locale: locale.current), Fmt.tokens(tokens), accent: nil)
            statCard(L.t("requests", locale: locale.current), Fmt.int(requests), accent: nil)
            statCard(L.t("sessionsLabel", locale: locale.current), Fmt.int(sessions), accent: nil)
        }
    }

    private func statCard(_ label: String, _ value: String, accent: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Palette.ink.opacity(0.55))
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .monospacedDigit()
                .foregroundStyle(accent ?? Palette.ink)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    /// Trim very long absolute paths to "…/parent/leaf" so the row stays
    /// single-line without losing the meaningful tail.
    private func truncatedPath(_ p: String) -> String {
        let parts = p.split(separator: "/")
        if parts.count <= 3 { return p }
        return "/" + parts.suffix(3).joined(separator: "/")
    }

    private func relativeAgo(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: locale.current == .zh ? "zh_CN" : "en_US")
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

/// Right pane of ProjectsMasterDetail when a project is selected.
struct ProjectDetailView: View {
    let tool: Tool
    let range: Range
    let project: Project
    @ObservedObject var store: UsageStore

    @ObservedObject private var locale = LocaleStore.shared
    @State private var copied = false

    /// Full per-project usage (chart + breakdown). Loaded by the parent
    /// when selectedProject changes; we just read whatever the store has.
    private var projectSnapshot: UsageSnapshot {
        store.snapshot(tool: tool, range: range, project: project.cwd) ?? .empty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                stats
                tokenChart
                breakdownAndBranches
                Spacer(minLength: 4)
            }
            .padding(20)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(project.displayName)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.3)
                pathPill
                Spacer(minLength: 0)
                if let last = project.lastActiveAt {
                    Text(L.t("lastActive", locale: locale.current,
                             params: ["t": relativeAgo(last)]))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink.opacity(0.5))
                }
            }
            if !project.gitBranches.isEmpty {
                HStack(spacing: 6) {
                    ForEach(project.gitBranches, id: \.self) { b in
                        branchPill(b)
                    }
                }
            }
        }
    }

    private var pathPill: some View {
        Button {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.cwd, forType: .string)
            #endif
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { copied = false }
            }
        } label: {
            HStack(spacing: 6) {
                Text(project.cwd.isEmpty ? "—" : project.cwd)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Palette.ink.opacity(copied ? 0.85 : 0.45))
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(
                Capsule().fill(Palette.ink.opacity(0.05))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(project.cwd.isEmpty)
    }

    private func branchPill(_ name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9, weight: .medium))
            Text(name)
                .font(.system(size: 11))
        }
        .foregroundStyle(Palette.ink.opacity(0.7))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(Palette.ink.opacity(0.06)))
    }

    // MARK: - Stats

    private var stats: some View {
        HStack(spacing: 10) {
            stat(L.t("estCost", locale: locale.current), Fmt.money(project.cost), accent: tool.accent)
            stat(L.t("tokens", locale: locale.current),  Fmt.tokens(project.totalTokens), accent: nil)
            stat(L.t("requests", locale: locale.current), Fmt.int(project.requests), accent: nil)
            stat(L.t("sessionsLabel", locale: locale.current), Fmt.int(project.sessions), accent: nil)
        }
    }

    private func stat(_ label: String, _ value: String, accent: Color?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Palette.ink.opacity(0.55))
            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .monospacedDigit()
                .foregroundStyle(accent ?? Palette.ink)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
        )
    }

    // MARK: - Token chart

    private var tokenChart: some View {
        let snap = projectSnapshot
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L.t("tokenUsageStacked", locale: locale.current))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            if snap.series.isEmpty {
                placeholderBox(L.t("loadingChart", locale: locale.current), height: 160)
            } else {
                StackedBarChartView(
                    series: stackedSeries(from: snap),
                    labels: snap.labels,
                    seriesDisplayName: { id in L.t(id, locale: locale.current) },
                    totalLabel: L.t("total", locale: locale.current)
                )
                .frame(height: 180)
                .padding(.horizontal, 12).padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                )
            }
        }
    }

    private func stackedSeries(from snap: UsageSnapshot) -> [StackedBarChartView.Series] {
        let m = snap.metrics
        return [
            .init(id: "cacheRead",  color: Palette.cacheRead,  data: scaled(snap.series, share: m.cacheRead)),
            .init(id: "input",      color: Palette.input,      data: scaled(snap.series, share: m.input)),
            .init(id: "output",     color: Palette.output,     data: scaled(snap.series, share: m.output)),
            .init(id: "cacheWrite", color: Palette.cacheWrite, data: scaled(snap.series, share: m.cacheWrite)),
        ]
    }

    private func scaled(_ series: [Double], share: Double) -> [Double] {
        let baseSum = max(series.reduce(0, +), 0.0001)
        return series.map { $0 * share / baseSum }
    }

    private func placeholderBox(_ msg: String, height: CGFloat) -> some View {
        VStack {
            Text(msg)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.ink.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
        )
    }

    // MARK: - Token breakdown + branches

    private var breakdownAndBranches: some View {
        HStack(alignment: .top, spacing: 12) {
            tokenBreakdown
                .frame(maxWidth: .infinity, alignment: .topLeading)
            if !project.gitBranches.isEmpty {
                branchSummary
                    .frame(width: 240)
            }
        }
    }

    private var tokenBreakdown: some View {
        let total = max(project.totalTokens, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L.t("tokenBreakdown", locale: locale.current))
                .font(.system(size: 13, weight: .semibold))
            VStack(spacing: 6) {
                breakdownRow(L.t("cacheRead",  locale: locale.current), value: project.cacheReadTokens,  total: total, color: Palette.cacheRead)
                breakdownRow(L.t("input",      locale: locale.current), value: project.inputTokens,      total: total, color: Palette.input)
                breakdownRow(L.t("output",     locale: locale.current), value: project.outputTokens,     total: total, color: Palette.output)
                breakdownRow(L.t("cacheWrite", locale: locale.current), value: project.cacheWriteTokens, total: total, color: Palette.cacheWrite)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
            )
        }
    }

    private func breakdownRow(_ label: String, value: Double, total: Double, color: Color) -> some View {
        let pct = value / total
        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink.opacity(0.7))
                    .frame(width: 80, alignment: .leading)
            }
            GeometryReader { g in
                Capsule()
                    .fill(Palette.ink.opacity(0.05))
                    .overlay(
                        HStack {
                            Capsule().fill(color)
                                .frame(width: max(g.size.width * pct, 1))
                            Spacer(minLength: 0)
                        }
                    )
                    .clipShape(Capsule())
            }
            .frame(height: 6)
            Text(String(format: "%.1f%%", pct * 100))
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.ink.opacity(0.55))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
            Text(Fmt.tokens(value))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Palette.ink.opacity(0.7))
                .frame(width: 60, alignment: .trailing)
        }
    }

    private var branchSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("branches", locale: locale.current))
                .font(.system(size: 13, weight: .semibold))
            VStack(spacing: 8) {
                ForEach(project.gitBranches, id: \.self) { b in
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Palette.ink.opacity(0.55))
                        Text(b)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
            )
        }
    }

    // MARK: - Helpers

    private func relativeAgo(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: locale.current == .zh ? "zh_CN" : "en_US")
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}
