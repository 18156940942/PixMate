import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - 蒙版渲染
//
// 修图的所有「局部」效果都靠蒙版控制作用范围。
// 这里用 Core Graphics 把关键点画成带羽化的灰度图：
// 白 = 生效，黑 = 不生效，灰边 = 过渡。

enum MaskRenderer {

    /// 把一个归一化多边形画成蒙版
    static func polygon(_ points: [CGPoint],
                        size: CGSize,
                        feather: CGFloat,
                        scale: CGFloat = 1.0,
                        expand: CGFloat = 0) -> CIImage? {
        guard points.count >= 3, size.width > 0, size.height > 0 else { return nil }

        let gray = renderGray(size: size) { ctx in
            let path = CGMutablePath()
            let scaled = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            path.addLines(between: scaled)
            path.closeSubpath()

            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addPath(path)
            ctx.fillPath()
        }

        return soften(gray, size: size, feather: feather, expand: expand)
    }

    /// 椭圆蒙版（用于脸颊、痣点这类圆形区域）
    static func ellipse(center: CGPoint,
                        radiusX: CGFloat,
                        radiusY: CGFloat,
                        size: CGSize,
                        feather: CGFloat) -> CIImage? {
        let gray = renderGray(size: size) { ctx in
            let rect = CGRect(x: (center.x - radiusX) * size.width,
                              y: (center.y - radiusY) * size.height,
                              width: radiusX * 2 * size.width,
                              height: radiusY * 2 * size.height)
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fillEllipse(in: rect)
        }
        return soften(gray, size: size, feather: feather)
    }

    /// 两个椭圆合并（眼睛、嘴唇这类成对区域）
    static func pairedEllipses(centers: [CGPoint],
                               radiusX: CGFloat,
                               radiusY: CGFloat,
                               size: CGSize,
                               feather: CGFloat) -> CIImage? {
        guard !centers.isEmpty else { return nil }
        let gray = renderGray(size: size) { ctx in
            ctx.setFillColor(gray: 1, alpha: 1)
            for center in centers {
                let rect = CGRect(x: (center.x - radiusX) * size.width,
                                  y: (center.y - radiusY) * size.height,
                                  width: radiusX * 2 * size.width,
                                  height: radiusY * 2 * size.height)
                ctx.fillEllipse(in: rect)
            }
        }
        return soften(gray, size: size, feather: feather)
    }

    // MARK: 内部

    private static func renderGray(size: CGSize, draw: (CGContext) -> Void) -> CIImage {
        let width = Int(max(1, size.width.rounded()))
        let height = Int(max(1, size.height.rounded()))
        let colorSpace = CGColorSpaceCreateDeviceGray()

        guard let ctx = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        draw(ctx)

        guard let cg = ctx.makeImage() else {
            return CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        }
        return CIImage(cgImage: cg)
    }

    /// 羽化 + 可选的膨胀（expand > 0 时把蒙版往外扩一圈）
    private static func soften(_ image: CIImage,
                               size: CGSize,
                               feather: CGFloat,
                               expand: CGFloat = 0) -> CIImage {
        var result = image

        if expand > 0 {
            // 用「先模糊再提对比」实现膨胀，避免自己写形态学核
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = result
            blur.radius = Float(expand)
            if let expanded = blur.outputImage {
                let threshold = CIFilter.colorMatrix()
                threshold.inputImage = expanded
                threshold.rVector = CIVector(x: 6, y: 0, z: 0, w: -2.5)
                threshold.gVector = CIVector(x: 6, y: 0, z: 0, w: -2.5)
                threshold.bVector = CIVector(x: 6, y: 0, z: 0, w: -2.5)
                result = (threshold.outputImage ?? expanded).cropped(to: CGRect(origin: .zero, size: size))
            }
        }

        if feather > 0 {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = result
            blur.radius = Float(feather)
            result = (blur.outputImage ?? result).cropped(to: CGRect(origin: .zero, size: size))
        }

        return result.cropped(to: CGRect(origin: .zero, size: size))
    }
}
