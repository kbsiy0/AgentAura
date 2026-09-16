import AuraCore

/// T32：選單列 icon 造型偏好——搬出獨立檔案避免 `AppDelegate+PanelActions.swift` 撞
/// 200 行上限（同 `AppDelegate+Connect.swift`／`AppDelegate+Verification.swift` 的既有
/// 拆檔慣例：一個功能區塊一個檔案）。
extension AppDelegate {
    /// `UserDefaults` 鍵，走既有的 `defaults` 注入點（比照 `languageKey`）。
    static let iconShapeKey = "AgentAuraIconShape"
    /// **預設 `.ledStrip`**（design doc D-3：不驚動既有使用者）。
    ///
    /// `legacyAliases`：`nyanCat`／`rainbowCat` 是 T36 加入、2026-09-15 移除的彩虹貓造型
    /// 留在磁碟上的舊字面。已經選過它的使用者要**明確**降級到預設，不是掉進
    /// 「讀不懂就算了」那條兜底路徑——結果一樣，但列在這裡代表我們知道有這個舊值。
    /// 這不是通用的猜測式相容機制：新增一筆必須是明確的一行。
    static let iconShapePreference = RawValuePreference(
        key: iconShapeKey,
        defaultValue: IconShape.ledStrip,
        legacyAliases: ["nyanCat": .ledStrip, "rainbowCat": .ledStrip])

    /// 啟動時讀回持久化值（D-3：未設定過時 `IconShapePreference.load` 回 `.ledStrip`）。
    func loadIconShape() {
        iconShape = Self.iconShapePreference.load(from: defaults)
        status.setIconShape(iconShape)
    }

    /// 落盤、轉發給 `status`、重畫面板三件事綁在一起——同 `performSetIconPlate` 的理由，
    /// 沒有第二個地方可以只做其中一件。
    func performSetIconShape(_ shape: IconShape) {
        // 選了跟現在一樣的造型就什麼都不做——`setIconShape` 會把整個 drawing view
        // 拆掉重建、重設 status item 寬度（efficiency#E）。沒有必要為「沒有變化」付這個代價。
        guard shape != iconShape else { return }
        iconShape = shape
        Self.iconShapePreference.persist(shape, to: defaults)
        status.setIconShape(shape)
        refreshPanel()
    }
}
