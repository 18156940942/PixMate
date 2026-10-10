import Foundation
import Vision
import CoreImage
import UIKit

// MARK: - 人脸几何
//
// Vision 的所有坐标都是「归一化 + 左下原点」。
// 这里统一转成「归一化 + 左上原点」，因为 Core Graphics 和 UI 都是这个习惯，
// 转换只在这一个地方做，后面所有人都不用再操心坐标系。

struct FaceGeometry: Sendable {
    /// 人脸外接框（归一化，左上原点）
    var faceBox: CGRect
    /// 以下都是归一化到整图的点序列（左上原点）
    var faceContour: [CGPoint] = []
    var leftEye: [CGPoint] = []
    var rightEye: [CGPoint] = []
    var leftEyebrow: [CGPoint] = []
    var rightEyebrow: [CGPoint] = []
    var outerLips: [CGPoint] = []
    var innerLips: [CGPoint] = []
    var nose: [CGPoint] = []

    var leftEyeCenter: CGPoint? { centroid(leftEye) }
    var rightEyeCenter: CGPoint? { centroid(rightEye) }
    var lipCenter: CGPoint? { centroid(outerLips) }
    var mouthInnerCenter: CGPoint? { centroid(innerLips) }

    var eyeDistance: CGFloat {
        guard let l = leftEyeCenter, let r = rightEyeCenter else { return faceBox.width * 0.4 }
        return hypot(r.x - l.x, r.y - l.y)
    }

    private func centroid(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}

// MARK: - 人脸分析

enum FaceAnalyzer {

    /// 检出画面里所有人脸的关键点
    static func analyze(_ image: UIImage, maxFaces: Int = 6) -> [FaceGeometry] {
        guard let cgImage = image.normalizedCGImage() else { return [] }

        let request = VNDetectFaceLandmarksRequest()
        request.revision = VNDetectFaceLandmarksRequestRevision3

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }
        return observations.prefix(maxFaces).compactMap { convert($0) }
    }

    private static func convert(_ observation: VNFaceObservation) -> FaceGeometry {
        let box = flip(observation.boundingBox)
        var geometry = FaceGeometry(faceBox: box)

        guard let landmarks = observation.landmarks else { return geometry }

        geometry.faceContour   = points(landmarks.faceContour, in: observation.boundingBox)
        geometry.leftEye        = points(landmarks.leftEye, in: observation.boundingBox)
        geometry.rightEye       = points(landmarks.rightEye, in: observation.boundingBox)
        geometry.leftEyebrow    = points(landmarks.leftEyebrow, in: observation.boundingBox)
        geometry.rightEyebrow   = points(landmarks.rightEyebrow, in: observation.boundingBox)
        geometry.outerLips      = points(landmarks.outerLips, in: observation.boundingBox)
        geometry.innerLips      = points(landmarks.innerLips, in: observation.boundingBox)
        geometry.nose           = points(landmarks.nose, in: observation.boundingBox)

        return geometry
    }

    private static func points(_ region: VNFaceLandmarkRegion2D?, in faceBox: CGRect) -> [CGPoint] {
        guard let region else { return [] }
        return region.normalizedPoints.map { point in
            // 先在「人脸框」坐标系里还原，再翻转到左上原点
            let x = faceBox.minX + point.x * faceBox.width
            let y = faceBox.minY + point.y * faceBox.height
            return CGPoint(x: x, y: 1 - y)
        }
    }

    private static func flip(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX,
               y: 1 - rect.maxY,
               width: rect.width,
               height: rect.height)
    }
}

// MARK: - 人体分割（主体蒙版）
//
// 用于背景虚化 / 背景压暗。返回的蒙版里「人 = 亮」，和 CIBlendWithMask 的约定一致。

enum PersonMasker {

    struct Result {
        /// 人的蒙版（CIImage，单通道）
        var personMask: CIImage
        /// 归一化的人体外接框（左上原点）
        var boundingBox: CGRect?
    }

    static func mask(_ image: UIImage, context: CIContext) -> Result? {
        guard let cgImage = image.normalizedCGImage() else { return nil }

        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observation = request.results?.first else { return nil }
        let buffer = observation.pixelBuffer

        var mask = CIImage(cvPixelBuffer: buffer)
        let extent = CGRect(x: 0, y: 0,
                            width: CVPixelBufferGetWidth(buffer),
                            height: CVPixelBufferGetHeight(buffer))

        // 蒙版分辨率通常比原图小，放大回原尺寸
        let target = CGRect(origin: .zero, size: image.size)
        mask = mask.transformed(by: CGAffineTransform(scaleX: target.width / extent.width,
                                                      y: target.height / extent.height))

        // VNPixelBufferObservation 不提供 boundingBox（那是 VNDetectedObjectObservation
        // 才有的），所以直接从蒙版本身求人体外接框 —— 反而更贴合真实轮廓。
        let normalizedBox = boundingBox(ofMask: mask,
                                        extent: extent,
                                        context: context)

        return Result(personMask: mask.cropped(to: target), boundingBox: normalizedBox)
    }

    /// 扫描蒙版像素，找出亮度 > 阈值 的范围，返回归一化矩形（左上原点）。
    private static func boundingBox(ofMask mask: CIImage,
                                    extent: CGRect,
                                    context: CIContext) -> CGRect? {
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height)
        context.render(mask,
                       toBitmap: &pixels,
                       rowBytes: width,
                       bounds: extent,
                       format: .L8,
                       colorSpace: nil)

        // 阈值取 0.5 左右：分割输出是概率图，>127 视为「是人」
        let threshold: UInt8 = 127
        var minX = width, minY = height, maxX = -1, maxY = -1

        for y in 0..<height {
            let row = y * width
            for x in 0..<width where pixels[row + x] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }

        // CI 的 y 轴向上，转成「左上原点」需要翻转
        let x0 = CGFloat(minX) / CGFloat(width)
        let x1 = CGFloat(maxX + 1) / CGFloat(width)
        let y0 = CGFloat(height - 1 - maxY) / CGFloat(height)
        let y1 = CGFloat(height - minY) / CGFloat(height)

        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

// MARK: - 人体姿态
//
// 姿势参谋的基础：拿到骨架关键点。

enum BodyPoseAnalyzer {

    static func detect(_ image: UIImage) -> [DetectedPerson] {
        guard let cgImage = image.normalizedCGImage() else { return [] }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        return observations.compactMap { observation -> DetectedPerson? in
            guard let recognized = try? observation.recognizedPoints(.all) else { return nil }

            var joints: [String: SkeletonJoint] = [:]
            var minX: CGFloat = 1, minY: CGFloat = 1, maxX: CGFloat = 0, maxY: CGFloat = 0

            for (key, point) in recognized {
                guard point.confidence > 0.05 else { continue }
                let name = mapName(key)
                // Vision 是左下原点，翻到左上
                let normalized = CGPoint(x: point.location.x, y: 1 - point.location.y)
                joints[name] = SkeletonJoint(id: name, point: normalized, confidence: point.confidence)
                minX = min(minX, normalized.x); maxX = max(maxX, normalized.x)
                minY = min(minY, normalized.y); maxY = max(maxY, normalized.y)
            }

            guard !joints.isEmpty else { return nil }
            let box = CGRect(x: minX, y: minY,
                             width: max(0.02, maxX - minX),
                             height: max(0.02, maxY - minY))

            return DetectedPerson(boundingBox: box, faceBox: nil, joints: joints)
        }
    }

    private static func mapName(_ key: VNHumanBodyPoseObservation.JointName) -> String {
        switch key {
        case .nose:            return JointName.nose
        case .neck:            return JointName.neck
        case .leftShoulder:    return JointName.leftShoulder
        case .rightShoulder:   return JointName.rightShoulder
        case .leftElbow:       return JointName.leftElbow
        case .rightElbow:      return JointName.rightElbow
        case .leftWrist:       return JointName.leftWrist
        case .rightWrist:      return JointName.rightWrist
        case .root:            return JointName.root
        case .leftHip:         return JointName.leftHip
        case .rightHip:        return JointName.rightHip
        case .leftKnee:        return JointName.leftKnee
        case .rightKnee:       return JointName.rightKnee
        case .leftAnkle:       return JointName.leftAnkle
        case .rightAnkle:      return JointName.rightAnkle
        default:               return key.rawValue.rawValue
        }
    }
}

// MARK: - UIImage 归一化

extension UIImage {

    /// 统一转成「正立、无方向标记」的 CGImage，
    /// 否则 Vision 拿到的坐标会和屏幕上看到的对不上。
    func normalizedCGImage() -> CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let redrawn = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return redrawn.cgImage
    }

    func scaled(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let ratio = maxDimension / longest
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
