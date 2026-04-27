import SwiftUI

/// Horizontal scrolling row of project chips, shown above the main chart on
/// the Overview tab. The first chip is "All"; the rest are top-N by cost. If
/// more remain, a dashed "+N more" chip jumps to the Projects view.
struct ProjectChipStrip: View {
    let snapshot: ProjectsSnapshot
    let accent: Color
    @Binding var selectedProject: String?
    var onOpenProjectsView: () -> Void

    @ObservedObject private var locale = LocaleStore.shared

    /// chip cap before we hide the long tail behind a "+N more" chip.
    private let visibleCap = 8

    private var visibleProjects: [Project] {
        snapshot.projects.filter { $0.cost > 0 || $0.totalTokens > 0 }
    }

    private var topProjects: [Project] {
        Array(visibleProjects.prefix(visibleCap))
    }

    private var hiddenCount: Int {
        max(0, visibleProjects.count - visibleCap)
    }

    private var hiddenCost: Double {
        visibleProjects.dropFirst(visibleCap).reduce(0) { $0 + $1.cost }
    }

    var body: some View {
        if visibleProjects.count <= 1 {
            // 1 project (or none): chips add no value, hide the strip entirely.
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    allChip
                    ForEach(topProjects) { p in
                        chip(for: p)
                    }
                    if hiddenCount > 0 {
                        moreChip
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }
            .background(Color.white.opacity(0.18))
            .overlay(Rectangle().fill(Palette.ink.opacity(0.08)).frame(height: 1), alignment: .bottom)
        }
    }

    // MARK: - Chips

    private var allChip: some View {
        let isActive = (selectedProject == nil)
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                selectedProject = nil
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .strokeBorder(isActive ? .white : accent, lineWidth: 2)
                        .background(Circle().fill(isActive ? accent.opacity(0.0) : .clear))
                        .frame(width: 12, height: 12)
                    Text(L.t("allProjects", locale: locale.current,
                             params: ["n": "\(visibleProjects.count)"]))
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(Fmt.money(snapshot.totalCost))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isActive ? .white.opacity(0.92) : accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isActive ? .white : Palette.ink)
            .background(chipBackground(active: isActive))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chip(for p: Project) -> some View {
        let isActive = (selectedProject == p.cwd)
        let pct = snapshot.totalCost > 0 ? Int((p.cost / snapshot.totalCost * 100).rounded()) : 0
        return Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                selectedProject = (isActive ? nil : p.cwd)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isActive ? Color.white.opacity(0.3) : accent.opacity(0.6))
                        .frame(width: 12, height: 12)
                    Text(p.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 8) {
                    Text(Fmt.money(p.cost))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isActive ? .white : accent)
                    Text("\(pct)% · \(Fmt.int(p.requests)) req")
                        .font(.system(size: 10.5))
                        .foregroundStyle((isActive ? Color.white : Palette.ink).opacity(0.55))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isActive ? .white : Palette.ink)
            .background(chipBackground(active: isActive))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(p.cwd)
    }

    private var moreChip: some View {
        Button(action: onOpenProjectsView) {
            HStack(spacing: 6) {
                Text("+\(hiddenCount) · \(Fmt.money(hiddenCost))")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(Palette.ink.opacity(0.62))
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Palette.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func chipBackground(active: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(active ? accent : Color.white.opacity(0.55))
            if !active {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
            }
        }
        .shadow(color: active ? accent.opacity(0.30) : .clear, radius: 6, y: 2)
    }
}
