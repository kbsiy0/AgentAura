import Testing
import AuraCore

/// spec `2026-09-09-panel-legend-palette-design.md` §6：`hexRoundTrip`、
/// `hexRejectsGarbage`、`decodeFallsBackPerKey`、`encodeOnlyNonDefault`。
@Suite("PaletteCodec")
struct PaletteCodecTests {

    /// 兩個 `RGBA` 的最大分量差（0…1）——本檔獨立定義，`AgentAuraAppTests` 那份
    /// 是不同 test target，跨不過來（`Package.swift` 沒有讓兩個 test target 互相依賴）。
    static func delta(_ a: RGBA, _ b: RGBA) -> Double {
        max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b), abs(a.a - b.a))
    }

    /// customizable 四色的實際色——不透過 `Activity.customizable`（那條本身待測，
    /// 具體列舉才不會循環依賴一條還沒紅過的 gate）。
    static let baseColors: [RGBA] = [
        IconPalette.default.error, IconPalette.default.waiting,
        IconPalette.default.working, IconPalette.default.done,
    ]

    /// 每通道 0…255 step 17 的決定性掃描：R/G/B 各自變動、其餘固定 128，a 固定 1。
    static let sweepColors: [RGBA] = stride(from: 0, through: 255, by: 17).flatMap { v -> [RGBA] in
        let f = Double(v) / 255
        let mid = 128.0 / 255
        return [
            RGBA(r: f, g: mid, b: mid, a: 1),
            RGBA(r: mid, g: f, b: mid, a: 1),
            RGBA(r: mid, g: mid, b: f, a: 1),
        ]
    }

    @Test("hex/rgba 往返：customizable 四色＋每通道 0…255 step 17 決定性掃描，分量差 ≤ 1/255；大小寫與無 # 正向")
    func hexRoundTrip() throws {
        for c in Self.baseColors + Self.sweepColors {
            let hex = PaletteCodec.hex(c)
            let back = try #require(PaletteCodec.rgba(hex: hex), "hex(\(c)) = \"\(hex)\" 應該能被 rgba(hex:) 解回來")
            #expect(Self.delta(back, c) <= 1.0 / 255, """
                往返失真：\(c) -> "\(hex)" -> \(back)，分量差 \(Self.delta(back, c)) > 1/255
                """)
        }
        #expect(PaletteCodec.rgba(hex: "#FF9F0A") == PaletteCodec.rgba(hex: "#ff9f0a"), "大小寫應視為相同色")
        #expect(PaletteCodec.rgba(hex: "ff9f0a") != nil, "省略 # 應仍能解析")
    }

    @Test("垃圾輸入一律回 nil、不 crash（對抗式）")
    func hexRejectsGarbage() throws {
        let garbage = [
            "", "#", "#12345", "#1234567", "#ff9f0a80", "#GGGGGG",
            "rgb(1,2,3)", "0a84ff ", "#ff9få", String(repeating: "f", count: 10_240),
        ]
        for g in garbage {
            #expect(PaletteCodec.rgba(hex: g) == nil, """
                垃圾輸入 "\(g.prefix(20))..." 應回 nil，實際 \(String(describing: PaletteCodec.rgba(hex: g)))
                """)
        }
    }

    @Test("decode 逐 key 落回預設；idle 永遠忽略（對抗式）")
    func decodeFallsBackPerKey() throws {
        let legitHex = "#123456"
        let expectedErrorColor = try #require(PaletteCodec.rgba(hex: legitHex),
            "前提：legitHex 自己要能被 rgba(hex:) 解出來")

        let overrides: [Activity: String] = [
            .error: legitHex,
            .waiting: "not-a-hex-at-all",
            .idle: legitHex,
        ]
        let palette = PaletteCodec.decode(overrides: overrides)

        #expect(palette.error == expectedErrorColor, "error 應套用合法覆寫色，實際 \(palette.error)")
        #expect(palette.waiting == IconPalette.default.waiting, "waiting 收到垃圾應落回預設，實際 \(palette.waiting)")
        #expect(palette.idle == IconPalette.default.idle, "idle 永遠忽略覆寫（即使值合法），實際 \(palette.idle)")
        #expect(palette.working == IconPalette.default.working, "未覆寫的 working 應維持預設")
        #expect(palette.done == IconPalette.default.done, "未覆寫的 done 應維持預設")
    }

    @Test("encode 只含非預設 key；decode(encode(p)) 還原 p")
    func encodeOnlyNonDefault() throws {
        #expect(PaletteCodec.encode(.default).isEmpty, "encode(.default) 應為空")

        let legitHex = "#123456"
        let customColor = try #require(PaletteCodec.rgba(hex: legitHex))
        let changed = IconPalette(idle: IconPalette.default.idle, working: customColor,
                                  done: IconPalette.default.done, waiting: IconPalette.default.waiting,
                                  error: IconPalette.default.error)

        let encoded = PaletteCodec.encode(changed)
        #expect(encoded.count == 1, "只改 working 應該只有一個 key，實際 \(encoded.count) 個：\(encoded)")
        #expect(encoded[.working] != nil, "應包含 .working 這個 key，實際 keys \(encoded.keys)")

        let decoded = PaletteCodec.decode(overrides: encoded)
        #expect(decoded == changed, "decode(encode(p)) 應該還原 p，實際 \(decoded)")
    }
}
