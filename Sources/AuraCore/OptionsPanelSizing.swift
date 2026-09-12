/// C2（team-lead 收尾）：Options 展開後的面板高度上限**由列數推導**，不是魔術數字——
/// team-lead 原本的意見：把門檻從 400pt 手動調到 460pt（因為多了一列）方向不對，
/// 下次再加一列又要再手動調一次，而門檻真正該擋的是「某一列自己變胖」（padding 被改壞），
/// 不是「列數變多」這種合理成長。
///
/// **T15（V1 落地）重新校準**：列高從「~3pt 垂直內距、無固定 frame」改成 V1 token 的
/// `.frame(minHeight: 28)`（＋20pt 左側圖示欄），舊常數（`perRowCeiling=30`／
/// `chromeCeiling=160`）是照 22pt 列高反推的，換了列高之後 worst-case 直接紅
/// （量到 473pt > 舊門檻 460pt）——這裡照 T15 之後的版面重新量，不是把門檻機械式往上調。
///
/// **實測分解**（`StatusItemController` 直接量 `preferredContentSize.height`，8→10 列
/// 逐項加開關，`ZZZScratchSizingMeasure`，量完即刪）：純列基準 chrome（8 列、無 subtitle、
/// 無 external 行）＝392pt；每多一列（純文字或純開關列）＋28pt（8→9→10 列驗證：
/// 392→420→448，完全線性，與 `.frame(minHeight: 28)` 直接對上）；純列基準 chrome 本身
/// （扣掉列數貢獻）＝392 − 8×28 ＝168pt（9／10 列反推同樣得到 168pt，三點一致）；
/// 「減少動態」的 subtitle 額外 ＋3pt（10 列：448→451，遠小於舊系統的 +14pt——舊列高本來
/// 就矮，subtitle 撐開的幅度大；新列高已經被 `minHeight: 28` 撐到位，subtitle 只需再擠出
/// 3pt）；`externalTargetPath` 那行（連同它的分隔線）額外 ＋22pt（451→473，這行沒有跟著
/// T15 改，數字與 T15 之前一致）。worst-case（10 列＋subtitle＋external 行）實測 473pt，
/// 與 168＋10×28＋3＋22 完全吻合。
///
/// 不逐項建模（那樣會變成跟列數一樣要手動同步的另一種魔術數字），改成**每列都用最壞情境
/// 的保守上界**：`perRowCeiling = 30pt`（實測純列 28pt，留 2pt margin）；
/// `chromeCeiling = 205pt` 一次涵蓋固定 chrome（實測 168pt）＋「最多一列有 subtitle（+3pt）、
/// 最多一行 external 目標（+22pt）」這類不隨列數線性成長的變異，外加約 12pt margin。
/// 10 列時 `ceiling = 10×30+205 = 505pt`，對實測 worst-case 473pt 留 32pt margin（≈6.8%）。
public enum OptionsPanelSizing {
    public static let perRowCeiling: Double = 30
    public static let chromeCeiling: Double = 205

    /// `rowCount` 一律從 `OptionsMenuModel.rows(...).count` 現場算，不得寫死——
    /// 這樣加一列時門檻自動跟著長，只有「列自己變胖」才會讓量到的高度超過它。
    public static func heightCeiling(forRowCount rowCount: Int) -> Double {
        Double(rowCount) * perRowCeiling + chromeCeiling
    }
}
