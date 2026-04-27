import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    /// snapshots[tool][project][range] — empty project key "" = "all projects".
    /// Project-specific data is loaded on demand when selectedProject changes.
    @Published private(set) var snapshots: [Tool: [String: [Range: UsageSnapshot]]] = [:]
    @Published private(set) var heatmaps: [Tool: [Int: HeatmapSnapshot]] = [:]
    @Published private(set) var projectLists: [Tool: [Range: ProjectsSnapshot]] = [:]
    @Published private(set) var lastError: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var loading: Set<String> = []

    /// The currently focused project (cwd). nil = "All". Shared between
    /// the Overview chip strip and the Projects master/detail view; cleared
    /// on tool change.
    @Published var selectedProject: String? = nil

    private let api: UsageAPI

    init(api: UsageAPI = UsageAPI()) {
        self.api = api
    }

    /// Returns the snapshot for the currently-active project filter.
    /// If `project` is nil it falls back to the all-projects snapshot.
    func snapshot(tool: Tool, range: Range, project: String? = nil) -> UsageSnapshot? {
        snapshots[tool]?[project ?? ""]?[range]
    }

    func heatmap(tool: Tool, weeks: Int) -> HeatmapSnapshot? {
        heatmaps[tool]?[weeks]
    }

    func projects(tool: Tool, range: Range) -> ProjectsSnapshot? {
        projectLists[tool]?[range]
    }

    func cost(tool: Tool, range: Range) -> Double {
        snapshot(tool: tool, range: range)?.metrics.cost ?? 0
    }

    /// Reset selection and project caches when the user switches tools, since
    /// each tool has its own project set.
    func clearProjectSelection() {
        selectedProject = nil
    }

    func loadAll(tool: Tool, project: String? = nil) async {
        await withTaskGroup(of: Void.self) { group in
            for r in Range.allCases {
                group.addTask { await self.load(tool: tool, range: r, project: project) }
            }
        }
    }

    func load(tool: Tool, range: Range, project: String? = nil) async {
        let projectKey = project ?? ""
        let key = "\(tool.rawValue)-\(range.rawValue)-\(projectKey)"
        loading.insert(key)
        defer { loading.remove(key) }
        do {
            let snap = try await api.query(tool: tool, range: range, project: projectKey)
            var perTool = snapshots[tool] ?? [:]
            var perProject = perTool[projectKey] ?? [:]
            perProject[range] = snap
            perTool[projectKey] = perProject
            snapshots[tool] = perTool
            lastError = nil
            lastSyncedAt = Date()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = msg
            FileHandle.standardError.write(Data("[UsageStore] \(tool.rawValue)/\(range.rawValue)/\(projectKey): \(msg)\n".utf8))
        }
    }

    func loadProjects(tool: Tool, range: Range) async {
        let key = "projects-\(tool.rawValue)-\(range.rawValue)"
        loading.insert(key)
        defer { loading.remove(key) }
        do {
            let snap = try await api.projects(tool: tool, range: range)
            var perRange = projectLists[tool] ?? [:]
            perRange[range] = snap
            projectLists[tool] = perRange
            lastError = nil
            lastSyncedAt = Date()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = msg
            FileHandle.standardError.write(Data("[UsageStore] projects \(tool.rawValue)/\(range.rawValue): \(msg)\n".utf8))
        }
    }

    /// Push the desired ingest scan interval to the backend. Errors are
    /// logged and swallowed — failures are non-fatal because the next
    /// successful push (next launch / next preference change) recovers.
    func pushBackendTick(seconds: TimeInterval) async {
        do {
            try await api.setBackendTick(seconds: seconds)
            lastError = nil
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("[UsageStore] push tick: \(msg)\n".utf8))
        }
    }

    func loadHeatmap(tool: Tool, weeks: Int) async {
        let key = "heatmap-\(tool.rawValue)-\(weeks)"
        loading.insert(key)
        defer { loading.remove(key) }
        do {
            let snap = try await api.heatmap(tool: tool, weeks: weeks)
            var perWeeks = heatmaps[tool] ?? [:]
            perWeeks[weeks] = snap
            heatmaps[tool] = perWeeks
            lastError = nil
            lastSyncedAt = Date()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = msg
            FileHandle.standardError.write(Data("[UsageStore] heatmap \(tool.rawValue)/\(weeks): \(msg)\n".utf8))
        }
    }
}
