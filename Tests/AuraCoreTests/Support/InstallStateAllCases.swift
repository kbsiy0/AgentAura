import AuraCore

/// §6.2／§6.3 反覆用到的定義域：`Reason.allCases × MountOwner.allCases`（`broken`）＋
/// connected 的 `MountOwner × Verification` ＋ 兩個頂層 case（`claudeNotFound`／`notConnected`）。
/// 集合由型別推導、不寫數字（R6）——`InstallStateTests`／`InstallAffordanceTests` 各自
/// inline 了一份同形狀的雙迴圈，這裡抽成共用 helper 供 T06 的新 gate（G8a／G10）沿用，
/// 避免第三份手寫迴圈再度漂移。
enum InstallStateAllCases {
    static func all() -> [InstallState] {
        var states: [InstallState] = [.claudeNotFound, .notConnected]
        for reason in InstallState.Reason.allCases {
            for owner in MountOwner.allCases {
                states.append(.broken(reason, owner: owner))
            }
        }
        for owner in MountOwner.allCases {
            for verified in Verification.allCases {
                states.append(.connected(owner: owner, verified: verified))
            }
        }
        return states
    }
}
