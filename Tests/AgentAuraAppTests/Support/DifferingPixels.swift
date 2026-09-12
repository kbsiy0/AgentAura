import Foundation

/// T01 helper（項目 4）：差異渲染——數兩張點陣圖有幾個像素不同。**同尺寸才可比**，
/// 尺寸不同一律 throw，不安靜回一個沒有意義的數字。
enum DifferingPixels {
    struct SizeMismatch: Error, CustomStringConvertible {
        let description: String
    }

    static func count(_ a: OffscreenRender.Bitmap, _ b: OffscreenRender.Bitmap) throws -> Int {
        guard a.context.width == b.context.width, a.context.height == b.context.height else {
            throw SizeMismatch(description: """
                尺寸不同：\(a.context.width)x\(a.context.height) vs \(b.context.width)x\(b.context.height) \
                —— 兩張圖必須同尺寸才可逐像素相減
                """)
        }
        guard let da = a.context.data, let db = b.context.data else { return 0 }
        let width = a.context.width, height = a.context.height
        let bprA = a.context.bytesPerRow, bprB = b.context.bytesPerRow
        let bufA = da.bindMemory(to: UInt8.self, capacity: bprA * height)
        let bufB = db.bindMemory(to: UInt8.self, capacity: bprB * height)
        var diff = 0
        for y in 0..<height {
            let rowA = y * bprA, rowB = y * bprB
            for x in 0..<width {
                let offA = rowA + x * 4, offB = rowB + x * 4
                if bufA[offA] != bufB[offB] || bufA[offA + 1] != bufB[offB + 1]
                    || bufA[offA + 2] != bufB[offB + 2] || bufA[offA + 3] != bufB[offB + 3] {
                    diff += 1
                }
            }
        }
        return diff
    }
}
