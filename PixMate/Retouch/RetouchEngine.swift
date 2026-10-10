import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - 分析结果
//
// Vision 很贵，滑块拖动时绝不能每帧重跑。
// 所以「分析」和「渲染」拆开：一张照片分析一次，参数怎么调都只是重渲染。

final class RetouchAnalysis {
    let baseImage: CIImage
    let extent: CGRect
    let imageSize: CGSize
    let faces: [FaceGeometry]
    let personMask: CIImage?
    let personBox: CGRect?

    init(baseImage: CIImage,
         extent: CGRect,
         imageSize: CGSize,
         faces: [FaceGeometry],
         personMask: CIImage?,
         personBox: CGRect?) {
        self.baseImage = baseImage
        self.extent = extent
        self.imageSize = imageSize
        self.faces = faces
        self.personMask = personMask
        self.personBox = personBox
    }

    var faceCount: Int { faces.count }
    var hasPersonMask: Bool { personMask != nil }
}

// MARK: - 修图引擎

final class RetouchEngine {

    let context: CIContext
    private let displayP3 = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    /// Vision 跑在缩小图上——脸还是那张脸，但快好几倍
    private let analysisMaxDimension: CGFloat = 1600

    init(context: CIContext? = nil) {
        if let context {
            self.context = context
        } else {
            // 线性工作空间，高光/阴影与肤色运算才不会发灰
            let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()
            self.context = CIContext(options: [
                .workingColorSpace: linear,
                .outputColorSpace: displayP3,
                .cacheIntermediates: false
            ])
        }
    }

    // MARK: 分析

    func analyze(_ image: UIImage, detectPerson: Bool = true) -> RetouchAnalysis {
        let base: CIImage
        if let cg = image.normalizedCGImage() {
            base = CIImage(cgImage: cg)
        } else {
            base = CIImage.empty()
        }
        let extent = base.extent

        let probe = image.scaled(toMaxDimension: analysisMaxDimension)
        let faces = FaceAnalyzer.analyze(probe)

        var personMask: CIImage?
        var personBox: CGRect?
        if detectPerson, let result = PersonMasker.mask(probe, context: context) {
            let sx = extent.width / max(1, probe.size.width)
            let sy = extent.height / max(1, probe.size.height)
            personMask = result.personMask
                .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                .cropped(to: extent)
            personBox = result.boundingBox
        }

        return RetouchAnalysis(baseImage: base,
                               extent: extent,
                               imageSize: CGSize(width: extent.width, height: extent.height),
                               faces: faces,
                               personMask: personMask,
                               personBox: personBox)
    }

    // MARK: 渲染

    func render(_ analysis: RetouchAnalysis, params: RetouchParams) -> UIImage? {
        let ci = compose(analysis, params: params)
        guard let cg = context.createCGImage(ci, from: analysis.extent, format: .RGBA8, colorSpace: displayP3) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    /// 一步到位：分析 + 渲染（适合单张导出）
    func render(_ image: UIImage, params: RetouchParams) -> UIImage? {
        let analysis = analyze(image, detectPerson: params.needsSubjectMask)
        return render(analysis, params: params)
    }

    /// 只要像素，不转 UIImage —— 导出链路用
    func renderCIImage(_ analysis: RetouchAnalysis, params: RetouchParams) -> CIImage {
        compose(analysis, params: params)
    }

    // MARK: 管线

    private func compose(_ analysis: RetouchAnalysis, params: RetouchParams) -> CIImage {
        var ci = analysis.baseImage
        let extent = analysis.extent

        ci = applyTone(ci, params: params, extent: extent)
        ci = applyColor(ci, params: params, extent: extent)
        ci = applyDetail(ci, params: params, extent: extent)
        ci = applyBackground(ci, analysis: analysis, params: params)
        ci = applyPortrait(ci, analysis: analysis, params: params)
        ci = applyFinish(ci, params: params, extent: extent)

        return ci.cropped(to: extent)
    }

    // ── 影调 ──────────────────────────────────────────

    private func applyTone(_ image: CIImage, params: RetouchParams, extent: CGRect) -> CIImage {
        var ci = image

        if abs(params.exposure) > 0.001 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = ci.clampedToExtent()
            filter.ev = Float(params.exposure * 2.0)
            ci = crop(filter.outputImage ?? ci, to: extent)
        }

        if abs(params.contrast) > 0.001 || abs(params.whites) > 0.001 || abs(params.blacks) > 0.001 {
            let filter = CIFilter.colorControls()
            filter.inputImage = ci.clampedToExtent()
            filter.contrast = Float(1 + params.contrast * 0.6)
            filter.brightness = Float(params.whites * 0.10 + params.blacks * -0.06)
            filter.saturation = 1
            ci = crop(filter.outputImage ?? ci, to: extent)
        }

        if abs(params.highlights) > 0.001 || abs(params.shadows) > 0.001 {
            let filter = CIFilter.highlightShadowAdjust()
            filter.inputImage = ci.clampedToExtent()
            filter.shadowAmount = Float(params.shadows)
            filter.highlightAmount = Float(1 + params.highlights * 0.5)
            filter.radius = 12
            if let out = filter.outputImage {
                ci = crop(out, to: extent)
            }
        }

        return ci
    }

    // ── 色彩 ──────────────────────────────────────────

    private func applyColor(_ image: CIImage, params: RetouchParams, extent: CGRect) -> CIImage {
        var ci = image

        if abs(params.temperature) > 0.001 || abs(params.tint) > 0.001 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = ci.clampedToExtent()
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 6500 + params.temperature * 2200,
                                            y: params.tint * 45)
            ci = crop(filter.outputImage ?? ci, to: extent)
        }

        if abs(params.vibrance) > 0.001 {
            let filter = CIFilter.vibrance()
            filter.inputImage = ci.clampedToExtent()
            filter.amount = Float(params.vibrance * 1.2)
            ci = crop(filter.outputImage ?? ci, to: extent)
        }

        if abs(params.saturation) > 0.001 {
            let filter = CIFilter.colorControls()
            filter.inputImage = ci.clampedToExtent()
            filter.saturation = Float(max(0, 1 + params.saturation))
            filter.contrast = 1
            filter.brightness = 0
            ci = crop(filter.outputImage ?? ci, to: extent)
        }

        if abs(params.hueShift) > 0.001 {
            let filter = CIFilter.hueAdjust()
            filter.inputImage = ci.clampedToExtent()
            filter.angle = Float(params.hueShift * .pi)
            ci = crop(filter.outputImage ?? ci, to: extent)
        }

        return ci
    }

    // ── 细节 ──────────────────────────────────────────

    private func applyDetail(_ image: CIImage, params: RetouchParams, extent: CGRect) -> CIImage {
        var ci = image

        if params.denoise > 0.001 {
            let filter = CIFilter.noiseReduction()
            filter.inputImage = ci.clampedToExtent()
            filter.noiseLevel = Float(params.denoise * 0.05)
            filter.sharpness = 0.35
            ci = crop(filter.outputImage ?? ci, to: extent)
        }

        if abs(params.clarity) > 0.001 {
            let filter = CIFilter.unsharpMask()
            filter.inputImage = ci.clampedToExtent()
            filter.radius = 12
            filter.intensity = Float(params.clarity * 1.2)
            ci = crop(filter.outputImage ?? ci, to: extent)
        }

        if params.sharpen > 0.001 {
            let filter = CIFilter.sharpenLuminance()
            filter.inputImage = ci.clampedToExtent()
            filter.sharpness = Float(params.sharpen * 1.5)
            filter.radius = 1.4
            ci = crop(filter.outputImage ?? ci, to: extent)
        }

        return ci
    }

    // ── 背景 ──────────────────────────────────────────

    private func applyBackground(_ image: CIImage,
                                 analysis: RetouchAnalysis,
                                 params: RetouchParams) -> CIImage {
        guard params.needsSubjectMask, let personMask = analysis.personMask else { return image }
        let extent = analysis.extent
        var ci = image

        // 背景 = 人像蒙版取反
        let backgroundMask = invert(personMask, extent: extent)

        if params.backgroundBlur > 0.001 {
            let filter = CIFilter.maskedVariableBlur()
            filter.inputImage = ci.clampedToExtent()
            filter.mask = backgroundMask      // 白 = 要模糊的地方
            filter.radius = Float(params.backgroundBlur * 24)
            ci = crop(filter.outputImage ?? ci, to: extent)
        }

        if params.backgroundDarken > 0.001 {
            let darken = CIFilter.exposureAdjust()
            darken.inputImage = ci.clampedToExtent()
            darken.ev = Float(-params.backgroundDarken * 1.8)

            if let dark = darken.outputImage {
                let blend = CIFilter.blendWithMask()
                blend.inputImage = dark
                blend.backgroundImage = ci
                blend.maskImage = scaleMask(backgroundMask, to: 0.85)
                ci = crop(blend.outputImage ?? ci, to: extent)
            }
        }

        return ci
    }

    // ── 人像 ──────────────────────────────────────────

    private func applyPortrait(_ image: CIImage,
                               analysis: RetouchAnalysis,
                               params: RetouchParams) -> CIImage {
        guard params.needsFaceAnalysis, !analysis.faces.isEmpty else { return image }
        let size = analysis.imageSize
        var ci = image

        for face in analysis.faces {
            ci = applySkin(to: ci, face: face, size: size, params: params)
            ci = applyBlemish(to: ci, face: face, size: size, params: params)
            ci = applyEyes(to: ci, face: face, size: size, params: params)
            ci = applyMouth(to: ci, face: face, size: size, params: params)
        }

        // 脸型放在最后：它改的是几何，先做会被后续模糊糊掉边界
        if params.faceSlim > 0.001 {
            for face in analysis.faces {
                ci = applyFaceSlim(to: ci, face: face, size: size, params: params)
            }
        }

        return ci
    }

    /// 磨皮 + 肤色
    private func applySkin(to image: CIImage,
                           face: FaceGeometry,
                           size: CGSize,
                           params: RetouchParams) -> CIImage {
        guard let skinMask = faceMask(face, size: size) else { return image }
        var ci = image
        let extent = image.extent

        if params.skinSmoothing > 0.001 {
            let sigma = 4.0 + params.skinSmoothing * 10.0

            let blur = CIFilter.gaussianBlur()
            blur.inputImage = ci.clampedToExtent()
            blur.radius = Float(sigma)

            if let blurred = blur.outputImage {
                let feathered = soften(skinMask, radius: sigma * 0.5)

                let blend = CIFilter.blendWithMask()
                blend.inputImage = blurred
                blend.backgroundImage = ci
                blend.maskImage = scaleMask(feathered, to: params.skinSmoothing * 0.85)
                ci = crop(blend.outputImage ?? ci, to: extent)

                // 补回高频：把细节找回来一点，避免一眼假
                let sharpen = CIFilter.unsharpMask()
                sharpen.inputImage = ci.clampedToExtent()
                sharpen.radius = 2.2
                sharpen.intensity = Float(0.45 + params.skinSmoothing * 0.3)

                if let sharpened = sharpen.outputImage {
                    let restore = CIFilter.blendWithMask()
                    restore.inputImage = sharpened
                    restore.backgroundImage = ci
                    restore.maskImage = scaleMask(feathered, to: 0.7)
                    ci = crop(restore.outputImage ?? ci, to: extent)
                }
            }
        }

        if abs(params.skinBrightness) > 0.001 || abs(params.skinTone) > 0.001 {
            var adjusted = ci

            if abs(params.skinBrightness) > 0.001 {
                let f = CIFilter.colorControls()
                f.inputImage = adjusted.clampedToExtent()
                f.brightness = Float(params.skinBrightness * 0.25)
                f.contrast = 1
                f.saturation = 1
                adjusted = f.outputImage ?? adjusted
            }

            if abs(params.skinTone) > 0.001 {
                let f = CIFilter.temperatureAndTint()
                f.inputImage = adjusted.clampedToExtent()
                f.neutral = CIVector(x: 6500, y: 0)
                f.targetNeutral = CIVector(x: 6500 + params.skinTone * 1200, y: 0)
                adjusted = f.outputImage ?? adjusted
            }

            let blend = CIFilter.blendWithMask()
            blend.inputImage = adjusted
            blend.backgroundImage = ci
            blend.maskImage = scaleMask(skinMask, to: 0.9)
            ci = crop(blend.outputImage ?? ci, to: extent)
        }

        return ci
    }

    /// 祛痘 / 瑕疵：中值滤波对孤立小点最有效，且不糊整片皮肤
    private func applyBlemish(to image: CIImage,
                              face: FaceGeometry,
                              size: CGSize,
                              params: RetouchParams) -> CIImage {
        guard params.blemishRemoval > 0.001,
              let skinMask = faceMask(face, size: size) else { return image }

        // CIMedian 是固定的 3×3 核，没有 radius 参数。
        // 想控制「力度」就调蒙版强度（下面 scaleMask 的那一项），
        // 这样效果可调，又不会糊掉整片皮肤。
        let filter = CIFilter.median()
        filter.inputImage = image.clampedToExtent()

        guard let median = filter.outputImage else { return image }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = median
        blend.backgroundImage = image
        blend.maskImage = scaleMask(skinMask, to: params.blemishRemoval * 0.8)
        return crop(blend.outputImage ?? image, to: image.extent)
    }

    /// 眼神光 + 眼白
    private func applyEyes(to image: CIImage,
                           face: FaceGeometry,
                           size: CGSize,
                           params: RetouchParams) -> CIImage {
        guard params.eyeEnhance > 0.001 else { return image }
        let centers = [face.leftEyeCenter, face.rightEyeCenter].compactMap { $0 }
        guard !centers.isEmpty else { return image }

        let rx = max(0.012, face.eyeDistance * 0.30)
        let ry = rx * 0.60
        guard let mask = MaskRenderer.pairedEllipses(centers: centers,
                                                     radiusX: rx,
                                                     radiusY: ry,
                                                     size: size,
                                                     feather: 4) else { return image }

        let filter = CIFilter.colorControls()
        filter.inputImage = image.clampedToExtent()
        filter.brightness = Float(params.eyeEnhance * 0.10)
        filter.contrast = Float(1 + params.eyeEnhance * 0.18)
        filter.saturation = Float(max(0, 1 - params.eyeEnhance * 0.25))

        guard let adjusted = filter.outputImage else { return image }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = adjusted
        blend.backgroundImage = image
        blend.maskImage = scaleMask(mask, to: params.eyeEnhance * 0.85)
        return crop(blend.outputImage ?? image, to: image.extent)
    }

    /// 唇色 + 牙齿
    private func applyMouth(to image: CIImage,
                            face: FaceGeometry,
                            size: CGSize,
                            params: RetouchParams) -> CIImage {
        var ci = image

        if params.lipEnhance > 0.001, let center = face.lipCenter {
            let rx = max(0.02, face.faceBox.width * 0.30)
            let ry = rx * 0.55
            if let mask = MaskRenderer.ellipse(center: center,
                                               radiusX: rx, radiusY: ry,
                                               size: size, feather: 5) {
                let f = CIFilter.colorControls()
                f.inputImage = ci.clampedToExtent()
                f.saturation = Float(1 + params.lipEnhance * 0.45)
                f.brightness = Float(params.lipEnhance * 0.02)
                f.contrast = 1
                if let adjusted = f.outputImage {
                    let blend = CIFilter.blendWithMask()
                    blend.inputImage = adjusted
                    blend.backgroundImage = ci
                    blend.maskImage = scaleMask(mask, to: params.lipEnhance * 0.8)
                    ci = crop(blend.outputImage ?? ci, to: ci.extent)
                }
            }
        }

        if params.teethWhiten > 0.001, let inner = face.mouthInnerCenter {
            let rx = max(0.014, face.faceBox.width * 0.16)
            let ry = rx * 0.45
            if let mask = MaskRenderer.ellipse(center: inner,
                                               radiusX: rx, radiusY: ry,
                                               size: size, feather: 3) {
                let f = CIFilter.colorControls()
                f.inputImage = ci.clampedToExtent()
                f.saturation = Float(max(0, 1 - params.teethWhiten * 0.7))
                f.brightness = Float(params.teethWhiten * 0.08)
                f.contrast = 1
                if let adjusted = f.outputImage {
                    let blend = CIFilter.blendWithMask()
                    blend.inputImage = adjusted
                    blend.backgroundImage = ci
                    blend.maskImage = scaleMask(mask, to: params.teethWhiten * 0.85)
                    ci = crop(blend.outputImage ?? ci, to: ci.extent)
                }
            }
        }

        return ci
    }

    /// 脸型收窄
    ///
    /// 做法：把整图以脸部中心为轴横向压缩一点点，
    /// 再用羽化椭圆蒙版只把这个变形贴回脸部区域。
    /// 纯公开滤镜实现，不需要自定义 Metal kernel。
    private func applyFaceSlim(to image: CIImage,
                               face: FaceGeometry,
                               size: CGSize,
                               params: RetouchParams) -> CIImage {
        let box = CGRect(x: face.faceBox.minX * size.width,
                         y: face.faceBox.minY * size.height,
                         width: face.faceBox.width * size.width,
                         height: face.faceBox.height * size.height)
        guard box.width > 4, box.height > 4 else { return image }

        let center = CGPoint(x: box.midX, y: box.midY)
        let scaleX = 1 - params.faceSlim * 0.10

        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: scaleX, y: 1)
            .translatedBy(x: -center.x, y: -center.y)

        let narrowed = image.clampedToExtent()
            .transformed(by: transform)
            .cropped(to: image.extent)

        let rx = (box.width / 2) / size.width * 1.05
        let ry = (box.height / 2) / size.height * 1.05
        guard let mask = MaskRenderer.ellipse(center: CGPoint(x: face.faceBox.midX, y: face.faceBox.midY),
                                              radiusX: rx,
                                              radiusY: ry,
                                              size: size,
                                              feather: max(3, box.width * 0.06)) else { return image }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = narrowed
        blend.backgroundImage = image
        blend.maskImage = scaleMask(mask, to: 0.95)
        return crop(blend.outputImage ?? image, to: image.extent)
    }

    // ── 收尾 ──────────────────────────────────────────

    private func applyFinish(_ image: CIImage, params: RetouchParams, extent: CGRect) -> CIImage {
        var ci = image

        if params.vignette > 0.001 {
            let filter = CIFilter.vignette()
            filter.inputImage = ci.clampedToExtent()
            filter.intensity = Float(params.vignette * 1.4)
            filter.radius = Float(max(extent.width, extent.height) * 0.55)
            ci = crop(filter.outputImage ?? ci, to: extent)
        }

        if params.grain > 0.001 {
            ci = addGrain(ci, amount: params.grain)
        }

        return ci
    }

    private func addGrain(_ image: CIImage, amount: Double) -> CIImage {
        let extent = image.extent
        guard let noise = CIFilter.randomGenerator().outputImage?.cropped(to: extent) else { return image }

        let mono = CIFilter.colorMatrix()
        mono.inputImage = noise
        mono.rVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
        mono.gVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
        mono.bVector = CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0)
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount) * 0.5)

        guard let grain = mono.outputImage else { return image }

        let overlay = CIFilter.overlayBlendMode()
        overlay.inputImage = grain
        overlay.backgroundImage = image
        return crop(overlay.outputImage ?? image, to: extent)
    }

    // MARK: 蒙版工具

    /// 人脸皮肤区蒙版。有轮廓点用轮廓，没有就退回外接椭圆。
    private func faceMask(_ face: FaceGeometry, size: CGSize) -> CIImage? {
        if face.faceContour.count >= 6 {
            return MaskRenderer.polygon(face.faceContour, size: size, feather: 7)
        }
        return MaskRenderer.ellipse(center: CGPoint(x: face.faceBox.midX, y: face.faceBox.midY),
                                    radiusX: face.faceBox.width / 2,
                                    radiusY: face.faceBox.height / 2,
                                    size: size,
                                    feather: 8)
    }

    private func soften(_ mask: CIImage, radius: Double) -> CIImage {
        guard radius > 0 else { return mask }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = mask.clampedToExtent()
        filter.radius = Float(radius)
        return crop(filter.outputImage ?? mask, to: mask.extent)
    }

    private func invert(_ mask: CIImage, extent: CGRect) -> CIImage {
        let filter = CIFilter.colorInvert()
        filter.inputImage = mask.cropped(to: extent)
        return crop(filter.outputImage ?? mask, to: extent)
    }

    /// 把蒙版整体乘一个系数 —— 用来表达「效果强度」
    private func scaleMask(_ mask: CIImage, to value: Double) -> CIImage {
        let v = CGFloat(min(1, max(0, value)))
        let filter = CIFilter.colorMatrix()
        filter.inputImage = mask
        filter.rVector = CIVector(x: v, y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: v, y: 0, z: 0, w: 0)
        filter.bVector = CIVector(x: v, y: 0, z: 0, w: 0)
        filter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return filter.outputImage ?? mask
    }

    private func crop(_ image: CIImage, to extent: CGRect) -> CIImage {
        image.cropped(to: extent)
    }
}
