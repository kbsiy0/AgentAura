import Foundation

public struct PanelRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let projectName: String
    public let activity: Activity
    public let headline: String
    public let detail: String
    public let meta: String
    public let relativeTime: String
    public let isEnded: Bool

    /// 副行整行（S1-B，persona-ack）。已結束時「已結束」**在行首**——那是這列唯一的存活訊號，
    /// 舊版拼成 `[detail, "已結束 · 2m 前"]` 落在 10pt 灰字中段，夾在活的列之間看不到。
    /// 活著且無 detail → 空字串（view 不畫這行，維持既有行為）。字串在 model 層拼，view 只印。
    public var footer: String {
        let parts = isEnded ? ["已結束", detail, relativeTime] : (detail.isEmpty ? [] : [detail, relativeTime])
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// 面板的呈現邏輯。純函數，所以排序、截斷、時間格式化都可測 ——
/// 這些是最容易在 UI 層被寫成「看起來對」但邊界錯的東西（負數時長、懸空分隔符、
/// 未截斷的長訊息把面板撐爆）。
public enum PanelViewModel {

    public static func rows(from states: [SessionState], now: Date = Date()) -> [PanelRow] {
        states
            .sorted { a, b in
                // 與 D1 一致：優先序高的在前
                if a.activity != b.activity { return a.activity > b.activity }
                // 活著的優先於已結束的
                let aEnded = a.liveness == .ended, bEnded = b.liveness == .ended
                if aEnded != bEnded { return !aEnded }
                // 同組內最近活動優先
                return a.updatedAt > b.updatedAt
            }
            .map { row(for: $0, now: now) }
    }

    static func row(for s: SessionState, now: Date) -> PanelRow {
        PanelRow(id: s.id,
                 projectName: s.projectName,
                 activity: s.activity,
                 headline: headline(for: s),
                 detail: detail(for: s, now: now),
                 meta: meta(for: s),
                 relativeTime: relativeTime(from: s.updatedAt, now: now),
                 isEnded: s.liveness == .ended)
    }

    static func headline(for s: SessionState) -> String {
        switch s.activity {
        case .waiting:
            // **先用 `toolDescription`。** 只有 tool 名的話「等你批准：Bash」
            // 看不出在等什麼，而 waiting 正是最需要資訊的一列。
            // `notificationMessage`（例如「MCP server 在等你輸入」）是第二順位。
            if let what = s.toolDescription ?? s.notificationMessage {
                return "等你批准：\(what)"
            }
            return "等你批准：\(s.currentTool ?? "輸入")"
        case .error:
            return s.toolError ?? s.errorType ?? "執行失敗"
        case .done:
            return summarise(s.lastMessage) ?? "已完成"
        case .working:
            // **主 agent 的 tool 是主行**（spec §2.5 結尾）。subagent 的以
            // `Explore → Grep` 形式**附註**在副行，不是拿來取代主行。
            //
            // 這裡先前寫成 subagent 優先 —— `MergeRules` 費了很大力氣保住
            // `mainTool` 不被 subagent 覆蓋（`mainToolNotOverwritten`），
            // 結果在呈現層又被覆蓋掉了。資料層守住的東西在最後一段丟失。
            return s.currentTool ?? s.subagentTool ?? "執行中"
        case .idle:
            return "等你下指令"
        }
    }

    /// 完成訊息可能很長（實測有數千字），面板不能被它撐爆。
    static func summarise(_ text: String?, limit: Int = 80) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let flat = text.split(whereSeparator: \.isNewline)
            .first?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !flat.isEmpty else { return nil }
        return flat.count <= limit ? flat : String(flat.prefix(limit)) + "…"
    }

    static func detail(for s: SessionState, now: Date) -> String {
        var parts: [String] = []
        if let start = s.turnStartedAt {
            parts.append("本輪 " + duration(now.timeIntervalSince(start)))
        }
        if let sub = s.subagentTool { parts.append(sub) }   // §2.5：subagent 以附註呈現
        if let ms = s.toolDurationMs, ms > 0 { parts.append(duration(Double(ms) / 1000)) }
        let subs = s.subagents.values.reduce(0, +)
        if subs > 0 { parts.append("\(subs) 個子任務") }
        if s.toolFailures > 0 { parts.append("\(s.toolFailures) 次工具失敗") }
        return parts.joined(separator: " · ")
    }

    /// T05（S1-Q5）：套 `Jargon` 把代碼字換成人話。`meta` 曾經直接 join 原始字串——
    /// `Jargon` 可以 100% 正確而面板照樣印 `claude-opus-5[1m] · xhigh · auto`，
    /// 這裡才是真正接線的地方。
    static func meta(for s: SessionState) -> String {
        [s.model.map(Jargon.model), s.effort.map(Jargon.effort), s.permissionMode.map(Jargon.permissionMode)]
            .compactMap { $0 }                 // 缺值就整段省略，不留懸空分隔符
            .joined(separator: " · ")
    }

    public static func duration(_ seconds: Double) -> String {
        let t = Int(max(0, seconds))           // 時鐘倒退 clamp 到 0
        if t < 60 { return "\(t)s" }
        if t < 3_600 { return "\(t / 60)m \(t % 60)s" }
        return "\(t / 3_600)h \((t % 3_600) / 60)m"
    }

    public static func relativeTime(from date: Date, now: Date = Date()) -> String {
        let t = max(0, now.timeIntervalSince(date))
        if t < 5 { return "剛剛" }
        return duration(t) + "前"
    }

    public static func title(for icon: IconState) -> String {
        SessionSummary.text(attention: icon.attentionCount, live: icon.liveCount,
                            done: icon.counts[.done] ?? 0, attentionWord: "在等你")
    }
}
