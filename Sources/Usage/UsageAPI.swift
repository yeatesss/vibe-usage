import Foundation

// MARK: - Errors

enum UsageAPIError: Error, LocalizedError {
    case backendNotRunning
    case invalidURL
    case http(Int)
    case decode(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .backendNotRunning: return "backend not running (runtime.json missing or invalid)"
        case .invalidURL:        return "invalid backend URL"
        case .http(let code):    return "HTTP \(code)"
        case .decode(let err):   return "decode: \(err.localizedDescription)"
        case .transport(let err): return "transport: \(err.localizedDescription)"
        }
    }
}

// MARK: - Runtime info

struct BackendRuntimeInfo: Decodable {
    let port: Int
    let pid: Int
    let startedAt: String
    let version: String
    let dataDir: String

    enum CodingKeys: String, CodingKey {
        case port, pid
        case startedAt = "started_at"
        case version
        case dataDir = "data_dir"
    }
}

// MARK: - API client

final class UsageAPI: @unchecked Sendable {
    private let session: URLSession
    private let runtimePath: URL
    private let decoder: JSONDecoder

    init(dataDir: URL? = nil, session: URLSession = .shared) {
        self.session = session
        let dir = dataDir ?? Self.defaultDataDir
        self.runtimePath = dir.appendingPathComponent("runtime.json")
        self.decoder = JSONDecoder()
    }

    static var defaultDataDir: URL {
        if let override = ProcessInfo.processInfo.environment["VIBEUSAGE_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VibeUsage", isDirectory: true)
    }

    func runtime() throws -> BackendRuntimeInfo {
        guard let data = try? Data(contentsOf: runtimePath) else {
            throw UsageAPIError.backendNotRunning
        }
        do {
            return try decoder.decode(BackendRuntimeInfo.self, from: data)
        } catch {
            throw UsageAPIError.backendNotRunning
        }
    }

    func query(tool: Tool, range: Range) async throws -> UsageSnapshot {
        let info = try runtime()
        var c = URLComponents()
        c.scheme = "http"
        c.host = "127.0.0.1"
        c.port = info.port
        c.path = "/usage"
        c.queryItems = [
            URLQueryItem(name: "tool",  value: tool.rawValue),
            URLQueryItem(name: "range", value: range.rawValue),
        ]
        guard let url = c.url else { throw UsageAPIError.invalidURL }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw UsageAPIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.http(-1)
        }
        guard http.statusCode == 200 else {
            throw UsageAPIError.http(http.statusCode)
        }
        do {
            let payload = try decoder.decode(BackendQueryResult.self, from: data)
            return payload.toSnapshot()
        } catch {
            throw UsageAPIError.decode(error)
        }
    }

    /// PUTs the desired ingest scan interval to the backend so file scanning
    /// stays in sync with the user's "Refresh interval" preference.
    func setBackendTick(seconds: TimeInterval) async throws {
        let info = try runtime()
        var c = URLComponents()
        c.scheme = "http"
        c.host = "127.0.0.1"
        c.port = info.port
        c.path = "/config/tick"
        guard let url = c.url else { throw UsageAPIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Go duration format ("30s", "60s", "300s") — matches time.ParseDuration.
        let body = try JSONSerialization.data(withJSONObject: ["tick": "\(Int(seconds))s"])
        req.httpBody = body

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: req)
        } catch {
            throw UsageAPIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.http(-1)
        }
        guard http.statusCode == 200 else {
            throw UsageAPIError.http(http.statusCode)
        }
    }

    func heatmap(tool: Tool, weeks: Int) async throws -> HeatmapSnapshot {
        let info = try runtime()
        var c = URLComponents()
        c.scheme = "http"
        c.host = "127.0.0.1"
        c.port = info.port
        c.path = "/usage/heatmap"
        c.queryItems = [
            URLQueryItem(name: "tool",  value: tool.rawValue),
            URLQueryItem(name: "weeks", value: String(weeks)),
        ]
        guard let url = c.url else { throw UsageAPIError.invalidURL }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw UsageAPIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.http(-1)
        }
        guard http.statusCode == 200 else {
            throw UsageAPIError.http(http.statusCode)
        }
        do {
            let payload = try decoder.decode(BackendHeatmapResult.self, from: data)
            return payload.toSnapshot()
        } catch {
            throw UsageAPIError.decode(error)
        }
    }
}

// MARK: - Backend payload (matches Go usage.QueryResult)

private struct BackendQueryResult: Decodable {
    struct Metrics: Decodable {
        let inputTokens: Int64
        let outputTokens: Int64
        let cacheReadTokens: Int64
        let cacheWriteTokens: Int64
        let totalTokens: Int64
        let reasoningOutputTokens: Int64
        let costUSD: String
        let requests: Int64

        enum CodingKeys: String, CodingKey {
            case inputTokens          = "input_tokens"
            case outputTokens         = "output_tokens"
            case cacheReadTokens      = "cache_read_tokens"
            case cacheWriteTokens     = "cache_write_tokens"
            case totalTokens          = "total_tokens"
            case reasoningOutputTokens = "reasoning_output_tokens"
            case costUSD              = "cost_usd"
            case requests
        }
    }
    struct Series: Decodable {
        let values: [Int64]
        let labels: [String]
    }
    let metrics: Metrics
    let sessions: Int
    let series: Series

    func toSnapshot() -> UsageSnapshot {
        let m = UsageMetrics(
            input:      Double(metrics.inputTokens),
            output:     Double(metrics.outputTokens),
            cacheRead:  Double(metrics.cacheReadTokens),
            cacheWrite: Double(metrics.cacheWriteTokens),
            cost:       Double(metrics.costUSD) ?? 0,
            requests:   Int(metrics.requests)
        )
        return UsageSnapshot(
            metrics:  m,
            series:   series.values.map(Double.init),
            labels:   series.labels,
            sessions: sessions
        )
    }
}

// MARK: - Backend heatmap payload (matches Go usage.HeatmapResult)

private struct BackendHeatmapResult: Decodable {
    struct Day: Decodable {
        let date: String
        let weekday: Int
        let totalTokens: Int64
        let costUSD: String
        let requests: Int64
        let isFuture: Bool

        enum CodingKeys: String, CodingKey {
            case date, weekday
            case totalTokens = "total_tokens"
            case costUSD     = "cost_usd"
            case requests
            case isFuture    = "is_future"
        }
    }
    let tool: String
    let weeks: Int
    let startDate: String
    let endDate: String
    let today: String
    let days: [Day]

    enum CodingKeys: String, CodingKey {
        case tool, weeks
        case startDate = "start_date"
        case endDate   = "end_date"
        case today
        case days
    }

    func toSnapshot() -> HeatmapSnapshot {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "Asia/Singapore")
        df.dateFormat = "yyyy-MM-dd"

        let mapped: [HeatmapDay] = days.map { d in
            HeatmapDay(
                id: d.date,
                date: df.date(from: d.date) ?? .distantPast,
                weekday: d.weekday,
                totalTokens: Double(d.totalTokens),
                cost: Double(d.costUSD) ?? 0,
                requests: Int(d.requests),
                isFuture: d.isFuture
            )
        }
        return HeatmapSnapshot(
            weeks: weeks,
            startDate: df.date(from: startDate) ?? .distantPast,
            endDate:   df.date(from: endDate)   ?? .distantPast,
            today:     df.date(from: today)     ?? .distantPast,
            days: mapped
        )
    }
}
