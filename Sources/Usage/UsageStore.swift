import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshots: [Tool: [Range: UsageSnapshot]] = [:]
    @Published private(set) var heatmaps: [Tool: [Int: HeatmapSnapshot]] = [:]
    @Published private(set) var lastError: String?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var loading: Set<String> = []

    private let api: UsageAPI

    init(api: UsageAPI = UsageAPI()) {
        self.api = api
    }

    func snapshot(tool: Tool, range: Range) -> UsageSnapshot? {
        snapshots[tool]?[range]
    }

    func heatmap(tool: Tool, weeks: Int) -> HeatmapSnapshot? {
        heatmaps[tool]?[weeks]
    }

    func cost(tool: Tool, range: Range) -> Double {
        snapshot(tool: tool, range: range)?.metrics.cost ?? 0
    }

    func loadAll(tool: Tool) async {
        await withTaskGroup(of: Void.self) { group in
            for r in Range.allCases {
                group.addTask { await self.load(tool: tool, range: r) }
            }
        }
    }

    func load(tool: Tool, range: Range) async {
        let key = "\(tool.rawValue)-\(range.rawValue)"
        loading.insert(key)
        defer { loading.remove(key) }
        do {
            let snap = try await api.query(tool: tool, range: range)
            var perRange = snapshots[tool] ?? [:]
            perRange[range] = snap
            snapshots[tool] = perRange
            lastError = nil
            lastSyncedAt = Date()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastError = msg
            FileHandle.standardError.write(Data("[UsageStore] \(tool.rawValue)/\(range.rawValue): \(msg)\n".utf8))
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
