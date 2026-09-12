import Testing
import AuraCore

/// B2（/simplify 波次1，alt#2／struct#9）：`PanelBanner.error(for: InstallerFailure)` 是
/// `InstallerFailure` 9 種結果 → banner 文案的單一窮盡來源（app 層 `handleConnectFailure`
/// 先前手搓了 11 次，`mustMoveToApplications` 甚至已經漂成兩種措辭）。這裡直接窮盡
/// `InstallerFailure` 的建構空間，釘住每一種結果都給出非空、且與既有共用常數一致的文案；
/// exhaustive-switch 本身已經是「漏一條就編譯錯」的 gate（見 commit 內的 mutation 記錄），
/// 這裡補的是「內容對不對」那一半。
@Suite("PanelBanner.error(for: InstallerFailure) 窮盡文案（B2）")
struct PanelBannerInstallerFailureTests {

    static let allFailures: [InstallerFailure] = {
        var out: [InstallerFailure] = [
            .mustMoveToApplications,
            .cannotConnect(nil),
            .externalMountNeedsChoice,
            .bundleIncomplete,
            .writeTargetOccupied,
            .renameFailed(13),
            .verificationFailed,
            .hookBlockedOrBroken(stamp: "s"),
            .hookUnconfirmed(stamp: "s"),
        ]
        out += InstallState.Reason.allCases.map { InstallerFailure.cannotConnect($0) }
        return out
    }()

    @Test("每一種 InstallerFailure 都有非空 banner 文案，kind 恆為 .error")
    func everyFailureHasNonEmptyErrorBanner() {
        for failure in Self.allFailures {
            let banner = PanelBanner.error(for: failure)
            #expect(banner.kind == .error, "\(failure)")
            #expect(!banner.text.isEmpty, "\(failure)")
        }
    }

    @Test("mustMoveToApplications 用合併後的單一措辭常數")
    func mustMoveToApplicationsUsesMergedMessage() {
        #expect(PanelBanner.error(for: .mustMoveToApplications).text
                == InstallerFailure.mustMoveToApplicationsMessage)
    }

    @Test("hookBlockedOrBroken／hookUnconfirmed 與 explanationDetail 共用同一組 prescription 常數（單一 oracle，S1-1）")
    func hookFailuresShareExplanationDetailPrescriptions() {
        #expect(PanelBanner.error(for: .hookBlockedOrBroken(stamp: "x")).text
                == InstallState.hookBlockedPrescription)
        #expect(PanelBanner.error(for: .hookUnconfirmed(stamp: "x")).text
                == InstallState.hookUnconfirmedPrescription)
    }

    @Test("cannotConnect(nil) 與 cannotConnect(reason) 跟 healthLabel 是同一個 oracle")
    func cannotConnectMatchesHealthLabel() {
        #expect(PanelBanner.error(for: .cannotConnect(nil)).text == InstallState.claudeNotFound.healthLabel)
        for reason in InstallState.Reason.allCases {
            #expect(PanelBanner.error(for: .cannotConnect(reason)).text
                    == InstallState.broken(reason, owner: .unknown).healthLabel, "\(reason)")
        }
    }
}
