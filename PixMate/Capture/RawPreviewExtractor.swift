import Foundation
import UIKit
import ImageIO

// MARK: - RAW 预览提取
//
// iOS 无法直接解码尼康 NEF，但两张牌可以打：
//
//  1. ImageIO 内置 RAW 支持 —— 若当前系统认这台相机的 RAW，直接出缩略图；
//  2. 嵌入预览 —— 几乎所有 RAW 内部都塞了一张完整 JPEG 预览，
//     按 SOI/EOI 扫一遍把最大那张取出来。
//
// 所以「用 RAW 拍」在本 App 里是可行的：
// 修图与预览走嵌入 JPEG，RAW 原文件原样留着，等接 RAW 引擎时再深加工。

enum RawPreviewExtractor {

    /// 尝试从 RAW 里取一张能用的预览图
    static func preview(from url: URL) -> UIImage? {
        if let fast = thumbnailViaImageIO(url) { return fast }
        if let embedded = largestEmbeddedJPEG(url) { return embedded }
        return nil
    }

    // MARK: 路线一：ImageIO

    private static func thumbnailViaImageIO(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2400
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) {
            return UIImage(cgImage: cg)
        }
        if let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return UIImage(cgImage: cg)
        }
        return nil
    }

    // MARK: 路线二：扫嵌入 JPEG

    private static func largestEmbeddedJPEG(_ url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let bytes = [UInt8](data)

        var best: Data?
        var index = 0
        let count = bytes.count

        while index < count - 3 {
            // 找 SOI：FF D8 FF
            guard bytes[index] == 0xFF, bytes[index + 1] == 0xD8, bytes[index + 2] == 0xFF else {
                index += 1
                continue
            }
            let start = index
            // 从该处向后找 EOI：FF D9
            var cursor = start + 2
            var end: Int?
            while cursor < count - 1 {
                if bytes[cursor] == 0xFF, bytes[cursor + 1] == 0xD9 {
                    end = cursor + 1
                    break
                }
                cursor += 1
            }
            guard let stop = end else { break }

            let candidate = Data(bytes[start...stop])
            // 太小的多半是缩略图，跳过；选最大的那张（通常是全尺寸预览）
            if candidate.count > (best?.count ?? 0), candidate.count > 20_000 {
                best = candidate
            }
            index = stop + 1
        }

        guard let jpeg = best else { return nil }
        return UIImage(data: jpeg)
    }
}
