import Foundation
import UIKit

// MARK: - 实时取景帧解析

/// 尼康实时取景（GetLiveViewImage 0x9203）返回的不是干净的 JPEG：
/// 前面有一段厂商头（Z 系列实测约 128 字节），尾部还可能带填充。
///
/// 最稳的剥法不是「砍掉前 N 字节」——固件一变 N 就变了——
/// 而是直接在字节流里找 JPEG 的 SOI（FF D8 FF）和 EOI（FF D9）。
enum NikonLiveViewFrame {

    struct Frame {
        var jpeg: Data
        var width: CGFloat
        var height: CGFloat
        /// 整帧 JPEG 的字节数，用于估算码率
        var byteCount: Int
    }

    /// 从原始返回数据里剥出可用的一帧
    static func parse(_ raw: Data) -> Frame? {
        let bytes = [UInt8](PTPPayload.strip(raw))
        guard let soi = findSOI(bytes) else { return nil }
        let eoi = findEOI(bytes, from: soi) ?? (bytes.count - 1)
        guard eoi > soi + 4 else { return nil }

        let jpeg = Data(bytes[soi...eoi])
        let size = imageSize(of: jpeg) ?? CGSize(width: LiveViewDefaults.assumedWidth,
                                                 height: LiveViewDefaults.assumedHeight)
        return Frame(jpeg: jpeg, width: size.width, height: size.height, byteCount: jpeg.count)
    }

    /// 找 SOI：FF D8 FF
    private static func findSOI(_ b: [UInt8]) -> Int? {
        guard b.count > 3 else { return nil }
        for i in 0..<(b.count - 2) where b[i] == 0xFF && b[i + 1] == 0xD8 && b[i + 2] == 0xFF {
            return i
        }
        return nil
    }

    /// 从后往前找 EOI：FF D9
    private static func findEOI(_ b: [UInt8], from start: Int) -> Int? {
        guard b.count > 2, start < b.count - 1 else { return nil }
        var i = b.count - 2
        while i > start {
            if b[i] == 0xFF && b[i + 1] == 0xD9 { return i + 1 }
            i -= 1
        }
        return nil
    }

    /// 只读 JPEG 头拿到真实像素尺寸，不必解码整张图
    private static func imageSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
              w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }
}

// MARK: - 取景帧节流

/// 实时取景的节流器：相机出帧比屏幕刷新快，
/// 全部解码会白烧电，所以按目标帧率丢帧。
final class FrameThrottle {
    private let minInterval: TimeInterval
    private var lastEmit: TimeInterval = 0

    init(fps: Double) {
        minInterval = fps > 0 ? 1.0 / fps : 0
    }

    func shouldEmit(now: TimeInterval = CFAbsoluteTimeGetCurrent()) -> Bool {
        guard now - lastEmit >= minInterval else { return false }
        lastEmit = now
        return true
    }

    func reset() { lastEmit = 0 }
}
