import Foundation

/// B2／B4：GitHub repo 相關網址，只在這裡寫一次（`git remote -v` 讀到的實際位址，
/// 不是瞎掰的佔位網址）——`reportIssue`（B2）與「關於」的 credits（B4）共用同一個來源，
/// repo 搬家只需要改這裡。
enum ProjectLinks {
    static let repository = URL(string: "https://github.com/kbsiy0/AgentAura")!
    static let newIssue = URL(string: "https://github.com/kbsiy0/AgentAura/issues/new")!
}
