/// `IconPalette` ⇄ `UserDefaults` 字串的編解碼。純函式，AuraCore 對抗式測試守正確性，
/// I/O 在 `PaletteStore`（App 層）。spec `2026-09-09-panel-legend-palette-design.md` §2／§3。
public enum PaletteCodec {

    /// round 到 0…255、永遠小寫、恆帶 `#`。
    public static func hex(_ c: RGBA) -> String {
        "#" + hexPair(c.r) + hexPair(c.g) + hexPair(c.b)
    }

    /// **先**驗長度（6 或 7，7 時首字元必須是 `#`）與字元集 `[0-9a-fA-F]`，**再**用
    /// `Array(utf8)` 索引解析——不走 `String.Index` 位移。任何不合格輸入回 nil，不 crash。
    public static func rgba(hex: String) -> RGBA? {
        let bytes = Array(hex.utf8)
        let digits: ArraySlice<UInt8>
        switch bytes.count {
        case 6:
            digits = bytes[0..<6]
        case 7:
            guard bytes[0] == UInt8(ascii: "#") else { return nil }
            digits = bytes[1..<7]
        default:
            return nil
        }
        guard digits.allSatisfy({ hexDigitValue($0) != nil }) else { return nil }
        let d = Array(digits)
        let r = byteValue(d[0], d[1])
        let g = byteValue(d[2], d[3])
        let b = byteValue(d[4], d[5])
        return RGBA(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255, a: 1)
    }

    /// 逐 key 落回預設；只走 `Activity.customizable`，`idle` 永遠忽略（即使值合法）。
    public static func decode(overrides: [Activity: String]) -> IconPalette {
        var palette = IconPalette.default
        for activity in Activity.customizable {
            guard let hex = overrides[activity], let color = rgba(hex: hex) else { continue }
            palette = palette.with(activity, color: color)
        }
        return palette
    }

    /// 只含 customizable 中 ≠ 對應預設色的 key。
    public static func encode(_ p: IconPalette) -> [Activity: String] {
        var result: [Activity: String] = [:]
        for activity in Activity.customizable {
            let color = p[activity]
            if color != IconPalette.default[activity] {
                result[activity] = hex(color)
            }
        }
        return result
    }

    private static let hexAlphabet: [Character] = Array("0123456789abcdef")

    private static func hexPair(_ v: Double) -> String {
        let clamped = v.isFinite ? min(max(v, 0), 1) : 0          // NaN 會讓 Int(nan) trap（review-t0203 Minor 1）
        let byte = Int((clamped * 255).rounded())
        return String([hexAlphabet[byte >> 4], hexAlphabet[byte & 0xF]])
    }

    private static func hexDigitValue(_ b: UInt8) -> Int? {
        switch b {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(b - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(b - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(b - UInt8(ascii: "A")) + 10
        default: return nil
        }
    }

    private static func byteValue(_ hi: UInt8, _ lo: UInt8) -> Int {
        (hexDigitValue(hi) ?? 0) * 16 + (hexDigitValue(lo) ?? 0)
    }
}
