import Foundation
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers

// MARK: - RAW 显影
//
// 出片质量的关键升级：
//
//   之前：NEF → 抽嵌入 JPEG 预览 → 修图 → 导出
//          上限被机内预览的画质锁死（通常是压缩过的小尺寸 JPEG）
//   现在：NEF → CIRAWFilter 真显影 → 修图 → 导出
//          全传感器分辨率、线性光下的去马赛克，色彩由系统 RAW 配置文件管
//
// 系统对尼康机型的 RAW 支持跟着 iOS 版本走（Z6 II 早就在列表里）。
// 万一某台机器不被当前系统认，自动退回嵌入预览——功能不降级，只是画质退回。
//
// 注意分工：
//   拍摄瞬间的工作副本仍走 RawPreviewExtractor（快）；
//   只有**导出**和**全屏精修**才用这里（慢一点，但值得）。

enum RawDeveloper {

    /// 系统是否有 CIRAWFilter 可用（iOS 10+ 恒为 true，留着做防御）
    static var isFilterAvailable: Bool {
        CIFilter(name: "CIRAWFilter") != nil
    }

    /// 这个文件系统认不认得是 RAW。认得 ≠ 一定显影成功，但可以提前给出准确提示。
    static func isSystemRaw(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let typeID = CGImageSourceGetType(source) as String?,
              let type = UTType(typeID) else { return false }
        return type.conforms(to: .rawImage)
    }

    // MARK: 显影

    /// 真显影：NEF → CIImage（全传感器分辨率，默认显影参数）。
    /// CIRAWFilter 默认已按 RAW 内嵌方向摆正，不要再补 .oriented()。
    static func developCIImage(from url: URL) -> CIImage? {
        guard let rawInput = CIImage(contentsOf: url) else { return nil }
        guard let filter = CIFilter(name: "CIRAWFilter") else { return nil }
        filter.setValue(rawInput, forKey: kCIInputImageKey)
        guard let output = filter.outputImage,
              output.extent.width > 1, output.extent.height > 1 else { return nil }
        return output
    }

    /// 显影并渲染成 UIImage。
    /// - Parameter maxDimension: 长边上限。6048×4024 的 RGBA8 约 97 MB，
    ///   老设备上可以压一压；导出走修图引擎的上下文，色彩空间随引擎。
    static func developUIImage(from url: URL,
                               context: CIContext,
                               maxDimension: CGFloat = 8192) -> UIImage? {
        // 真 RAW 显影；系统不认这台机器的 RAW 时退回嵌入预览，
        // 让色彩和尺寸处理路径保持一致
        let ci: CIImage
        if let developed = developCIImage(from: url) {
            ci = developed
        } else if let preview = RawPreviewExtractor.preview(from: url),
                  let cg = preview.normalizedCGImage() {
            ci = CIImage(cgImage: cg)
        } else {
            return nil
        }

        var image = ci
        let longEdge = max(image.extent.width, image.extent.height)
        if longEdge > maxDimension, longEdge > 0 {
            let scale = maxDimension / longEdge
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: nil) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    /// 只为诊断：显影耗时。校准日志里用它判断设备是否扛得住全尺寸流程。
    static func measureDevelopmentTime(of url: URL, context: CIContext) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        _ = developUIImage(from: url, context: context)
        return CFAbsoluteTimeGetCurrent() - start
    }
}
