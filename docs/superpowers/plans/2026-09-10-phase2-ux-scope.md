# Phase 2 範圍（UI/UX 完整化）

目標（使用者 2026-09-10 22:45）：底層／機器面暫時不動；把 UI/UX 以及「兩個成熟 app 該有的功能」全部做完＋測完，尤其是 UX。

## A. persona NO-GO 的 8 條（T11）
| # | 級別 | 項目 | 檔案 |
|---|---|---|---|
| A1 | **S0** | 主 CTA「接上」不像按鈕（#7f7f7f／4.00:1、與說明句同色）；`.banner` 版狀態文字與按鈕同為 112 | `NotConnectedView.swift:36`、CTA 窄條 |
| A2 | **S0** | tooltip 說謊：D-e 的「還沒接上 Claude Code」repo 0 命中；面板標題同時出現「沒有活著的 session」與「還沒接上」 | `StatusItemController.swift:185`、`PanelViewModel.title` |
| A3 | S1 | `explainOnly` 三格沒有 spec 承諾的說明文字 | `NotConnectedView` |
| A4 | S1 | Options accordion 展開後「開機自動啟動」開關落在指標下（13×16pt 重疊） | `PanelView`／`OptionsSectionView` |
| A5 | S1 | `.banner` CTA 缺副標；「改指向這個 App」無確認框（「移除掛載」有）；成功 banner 不說掛載被換 | CTA 窄條、`AppDelegate+Connect` |
| A6 | S1 | 同一件事三個名字：help「捷徑」／UI「掛載」／對話框「連結」 | `help.html`、views、`AppEnvironment` |
| A7 | S1 | banner 無生命週期（「下一個 session 起生效」永久留著、佔 40pt）；✕ 只有 10×10pt | `BannerView`、`AppDelegate` |
| A8 | S1 | **「重設」在圖例列與 Options 重複**（D-a 要它搬走，舊的沒拿掉，沒有 gate 守） | `LegendRowView.swift:52` |

## B. 成熟 app 該有、我們還缺的（T12）
| # | 項目 | 對應 | 做/不做 |
|---|---|---|---|
| B1 | 右鍵直接開 Options | 兩個 app 都有快速路徑 | **做**（主入口仍看得見） |
| B2 | 「回報問題」入口 | Amphetamine 的 Feedback & Support | **做**（開 GitHub issues） |
| B3 | 快捷鍵字樣（⌘Q／⌘,）顯示在列上 | 兩個 app 都印 | **做**（純顯示） |
| B4 | 「關於」內容：版本＋專案連結＋授權 | Amphetamine 的 About | **做**（目前只是 standard panel） |
| B5 | 「減少動態」開關 | Amphetamine 的 Reduce motion | **做**——它就是 R4 注意力預算的使用者控制 |
| B6 | 「重設全部設定」 | Amphetamine 的 Reset all settings | **不做**：我們的設定只有顏色＋登入項目，已有「重設顏色」，重複 |
| B7 | 統計／歷史／成本 | OpenUsage | **不做**：刻意不存歷史（產品 scope） |
| B8 | 系統通知 | Amphetamine | **不做**：改變產品性質（餘光→主動打擾），撞 R4，需自己的 brainstorm |
| B9 | 熱鍵 | Amphetamine | **不做**：我們是唯讀，沒有可觸發的動作 |

## C. 驗證
1. 每個面板狀態渲一輪圖，**我自己肉眼看**（persona 的 13 張證明這招有效）
2. persona 重測（只測改動處）
3. DoD 帳本更新 ＋ brainstorm HTML 的功能對照表更新
4. 既有 flake `CompositionRootTests.acknowledgeDeletesFiles`（3/20，Change 2 就在待辦）
   —— 屬底層 FSEvents，依「底層暫時不動」保持 known gap
