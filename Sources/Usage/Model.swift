import SwiftUI

// MARK: - Tool

enum Tool: String, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }

    var accent: Color {
        switch self {
        case .claude: return Color(red: 0xC9/255, green: 0x64/255, blue: 0x42/255)
        case .codex:  return Color(red: 0x4E/255, green: 0x6E/255, blue: 0xFB/255)
        }
    }

    var displayKey: String {
        switch self {
        case .claude: return "claudeCode"
        case .codex:  return "codex"
        }
    }

    var pricing: String {
        switch self {
        case .claude: return "$3 / $15 / 1M · 90% cache discount"
        case .codex:  return "$1.25 / $10 / 1M · cached $0.125"
        }
    }
}

// MARK: - Range

enum Range: String, CaseIterable, Identifiable {
    case today, week, month, year
    var id: String { rawValue }
}

// MARK: - UsageMetrics

struct UsageMetrics {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
    let cost: Double
    let requests: Int

    var total: Double { input + output + cacheRead + cacheWrite }
}

// MARK: - UsageSnapshot

struct UsageSnapshot {
    let metrics: UsageMetrics
    let series: [Double]
    let labels: [String]
    let sessions: Int

    static let empty = UsageSnapshot(
        metrics: UsageMetrics(input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, requests: 0),
        series: [],
        labels: [],
        sessions: 0
    )
}

// MARK: - Number formatting

enum Fmt {
    static func tokens(_ n: Double) -> String {
        if n >= 1_000_000 {
            let v = n / 1_000_000
            return String(format: v >= 10 ? "%.1fM" : "%.2fM", v)
        }
        if n >= 1_000 {
            let v = n / 1_000
            return String(format: v >= 100 ? "%.0fK" : "%.1fK", v)
        }
        return String(Int(n))
    }

    static func money(_ n: Double, decimals: Int = 2) -> String {
        return String(format: "$%.\(decimals)f", n)
    }

    static func int(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Localization

enum AppLocale: String, CaseIterable {
    case en, zh
}

@MainActor
final class LocaleStore: ObservableObject {
    static let shared = LocaleStore()
    @Published var current: AppLocale = .en
    private init() {}
}

enum L {
    static func t(_ key: String, locale: AppLocale, params: [String: String] = [:]) -> String {
        let dict = locale == .zh ? zh : en
        guard var v = dict[key] else { return key }
        for (k, value) in params {
            v = v.replacingOccurrences(of: "{\(k)}", with: value)
        }
        return v
    }

    static let en: [String: String] = [
        "claudeCode": "Claude Code",
        "codex": "Codex",
        "syncedAgo": "Synced {time} ago",
        "sessions": "{n} sessions",
        "estCost": "Cost",
        "tokens": "Tokens",
        "requestsLine": "{req} requests",
        "avgPerReq": "avg {v} / request",
        "tokenBreakdown": "Token breakdown",
        "input": "Input",
        "output": "Output",
        "cacheRead": "Cache read",
        "cacheWrite": "Cache write",
        "otherPeriods": "Other periods",
        "today": "Today",
        "week": "Week",
        "month": "Month",
        "year": "Year",
        "openDashboard": "Open full dashboard",
        "exportCsv": "Export CSV…",
        "budgets": "Budgets & alerts",
        "preferences": "Preferences…",
        "quit": "Quit VibeUsage",
        "language": "Language",
        "now": "Now",
        "dashboard": "Dashboard",
        "tokensRequestsLine": "{tokens} tokens · {req} requests",
        "rangeSubToday": "Hourly · last 24h",
        "rangeSubWeek": "Last 7 days",
        "rangeSubMonth": "Last 30 days",
        "rangeSubYear": "Monthly · last 12 months",
        "tokenUsageStacked": "Token usage — stacked by type",
        "estimatedCost": "Estimated cost",
        "allPeriods": "All periods",
        "requestStats": "Request stats",
        "requests": "Requests",
        "avgTokensPerReq": "Avg tokens / req",
        "avgCostPerReq": "Avg cost / req",
        "total": "Total",
    ]

    static let zh: [String: String] = [
        "claudeCode": "Claude Code",
        "codex": "Codex",
        "syncedAgo": "{time} 前同步",
        "sessions": "{n} 个会话",
        "estCost": "花费",
        "tokens": "Token",
        "requestsLine": "{req} 次请求",
        "avgPerReq": "平均 {v} / 次请求",
        "tokenBreakdown": "Token 分布",
        "input": "输入",
        "output": "输出",
        "cacheRead": "缓存读取",
        "cacheWrite": "缓存写入",
        "otherPeriods": "其他时间段",
        "today": "今日",
        "week": "本周",
        "month": "本月",
        "year": "本年",
        "openDashboard": "打开完整面板",
        "exportCsv": "导出 CSV…",
        "budgets": "预算与提醒",
        "preferences": "偏好设置…",
        "quit": "退出 VibeUsage",
        "language": "语言",
        "now": "现在",
        "dashboard": "仪表盘",
        "tokensRequestsLine": "{tokens} Token · {req} 次请求",
        "rangeSubToday": "每小时 · 过去 24 小时",
        "rangeSubWeek": "过去 7 天",
        "rangeSubMonth": "过去 30 天",
        "rangeSubYear": "每月 · 过去 12 个月",
        "tokenUsageStacked": "Token 使用量 · 按类型堆叠",
        "estimatedCost": "预计花费",
        "allPeriods": "所有周期",
        "requestStats": "请求统计",
        "requests": "请求数",
        "avgTokensPerReq": "平均 Token / 次请求",
        "avgCostPerReq": "平均花费 / 次请求",
        "total": "合计",
    ]
}

// MARK: - Palette

enum Palette {
    static let input      = Color(red: 0x5B/255, green: 0x8D/255, blue: 0xEF/255)
    static let output     = Color(red: 0xC9/255, green: 0x64/255, blue: 0x42/255)
    static let cacheRead  = Color(red: 0x7D/255, green: 0xB4/255, blue: 0x6C/255)
    static let cacheWrite = Color(red: 0xB5/255, green: 0x8B/255, blue: 0xE0/255)
    static let ink        = Color(red: 0x1A/255, green: 0x16/255, blue: 0x25/255)
}
