import Foundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - 构图参谋
//
// 刻意不做成「打个 78 分」。
// 分数本身不能指导拍摄，能指导的是「把手机向左回正 3°」这种句子。
// 所以每一判据都输出：问题 → 依据 → 动作。

enum CompositionAdvisor {

    static func evaluate(image: UIImage,
                         people: [DetectedPerson],
                         faces: [FaceGeometry]) -> CompositionReport {
        var report = CompositionReport()
        var issues: [CompositionIssue] = []

        // ── 水平线 ────────────────────────────────────
        if let angle = detectHorizon(image) {
            report.horizonAngle = angle
            let magnitude = abs(angle)
            if magnitude >= 1.0 {
                let dir = angle > 0 ? "向右下" : "向左下"
                issues.append(CompositionIssue(
                    title: "水平线歪了",
                    detail: String(format: "地平线%@倾斜 %.1f°", dir, magnitude),
                    severity: magnitude >= 3 ? .warning : .tip,
                    action: String(format: "把手机%@回正 %.0f°", angle > 0 ? "向左" : "向右", max(1, magnitude)),
                    anchor: nil))
            }
        }

        // ── 主体 ──────────────────────────────────────
        if people.isEmpty {
            issues.append(CompositionIssue(
                title: "画面里没有人",
                detail: "当前构图还没装进主体",
                severity: .tip,
                action: "让人进入画面；若拍的是空镜就直接按快门",
                anchor: nil))
            report.score = 70
        } else {
            // 取画面里最大的那个人当主角
            let subject = people.max { a, b in
                a.boundingBox.width * a.boundingBox.height < b.boundingBox.width * b.boundingBox.height
            }!
            let box = subject.boundingBox
            report.subjectCoverage = Double(box.width * box.height)
            report.headroom = Double(box.minY)

            // 头顶留白
            if box.minY < 0.02 {
                issues.append(CompositionIssue(
                    title: "头顶被切了",
                    detail: String(format: "头顶距上边缘只有 %.0f%% 画面高", box.minY * 100),
                    severity: .warning,
                    action: "镜头往上抬一点，或让人往画面中下部站",
                    anchor: CGPoint(x: box.midX, y: box.minY)))
            } else if box.minY > 0.28 {
                issues.append(CompositionIssue(
                    title: "头顶留白太多",
                    detail: String(format: "上方空了 %.0f%% 画面高", box.minY * 100),
                    severity: .tip,
                    action: "镜头往下压一点，或走近一步把人物拍满些",
                    anchor: CGPoint(x: box.midX, y: box.minY)))
            }

            // 主体占比
            if report.subjectCoverage < 0.12 {
                issues.append(CompositionIssue(
                    title: "人物太小",
                    detail: String(format: "主体只占画面 %.0f%%", report.subjectCoverage * 100),
                    severity: .tip,
                    action: "往前走两步，或换长一点焦距",
                    anchor: CGPoint(x: box.midX, y: box.midY)))
            } else if report.subjectCoverage > 0.62 {
                issues.append(CompositionIssue(
                    title: "人物太满",
                    detail: String(format: "主体占了画面 %.0f%%", report.subjectCoverage * 100),
                    severity: .tip,
                    action: "退后一点给肢体留空间，尤其是手和脚",
                    anchor: CGPoint(x: box.midX, y: box.midY)))
            }

            // 贴边
            let margin: CGFloat = 0.012
            let clipped = box.minX < margin || box.maxX > 1 - margin || box.minY < margin || box.maxY > 1 - margin
            report.subjectClipped = clipped
            if clipped {
                issues.append(CompositionIssue(
                    title: "人物被画面切到",
                    detail: "身体或头部碰到了画面边缘",
                    severity: .warning,
                    action: "退后一点或调整取景，让主体四周都留出空隙",
                    anchor: CGPoint(x: box.midX, y: box.midY)))
            }

            // 三分线
            let anchorPoint = subject.joints[JointName.nose]?.point
                ?? subject.joints[JointName.neck]?.point
                ?? CGPoint(x: box.midX, y: box.minY)
            let thirds = [CGPoint(x: 1.0/3, y: 1.0/3),
                          CGPoint(x: 2.0/3, y: 1.0/3),
                          CGPoint(x: 1.0/3, y: 2.0/3),
                          CGPoint(x: 2.0/3, y: 2.0/3)]
            let nearest = thirds.map { hypot($0.x - anchorPoint.x, $0.y - anchorPoint.y) }.min() ?? 1
            report.onThirds = nearest < 0.12
            if !report.onThirds, report.subjectCoverage > 0.10 {
                issues.append(CompositionIssue(
                    title: "主体不在三分线",
                    detail: "面部落在画面中央，构图偏平",
                    severity: .tip,
                    action: "把面部挪到三分交点附近，画面会更有呼吸感",
                    anchor: anchorPoint))
            }

            // 脸的方向
            if faces.isEmpty, report.subjectCoverage > 0.15 {
                issues.append(CompositionIssue(
                    title: "看不到正脸",
                    detail: "检测到人体但没检出五官",
                    severity: .tip,
                    action: "让人稍微转向镜头；若是刻意拍侧脸 / 背影，忽略这条",
                    anchor: CGPoint(x: box.midX, y: box.minY + box.height * 0.12)))
            }
        }

        // ── 现场亮度 ──────────────────────────────────
        if let brightness = averageBrightness(image) {
            if brightness < 0.20 {
                issues.append(CompositionIssue(
                    title: "现场偏暗",
                    detail: String(format: "画面平均亮度只有 %.0f%%", brightness * 100),
                    severity: .tip,
                    action: "提高 ISO 或放慢快门；不然回传的图噪点会偏多",
                    anchor: nil))
            } else if brightness > 0.86 {
                issues.append(CompositionIssue(
                    title: "现场偏亮",
                    detail: String(format: "画面平均亮度达 %.0f%%", brightness * 100),
                    severity: .tip,
                    action: "降低曝光补偿，保住高光细节",
                    anchor: nil))
            }
        }

        // 警告在前，提示在后
        issues.sort { lhs, rhs in
            rank(lhs.severity) < rank(rhs.severity)
        }
        report.issues = issues
        report.score = score(from: issues)
        return report
    }

    // MARK: 分数

    private static func rank(_ severity: AdviceSeverity) -> Int {
        switch severity {
        case .warning: return 0
        case .tip:     return 1
        case .good:    return 2
        }
    }

    private static func score(from issues: [CompositionIssue]) -> Int {
        var value = 100
        for issue in issues {
            switch issue.severity {
            case .warning: value -= 18
            case .tip:     value -= 7
            case .good:    break
            }
        }
        return max(35, min(100, value))
    }

    // MARK: 水平线

    static func detectHorizon(_ image: UIImage) -> Double? {
        guard let cg = image.normalizedCGImage() else { return nil }
        let request = VNDetectHorizonRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first as? VNHorizonObservation else { return nil }
        let degrees = Double(observation.angle) * 180.0 / .pi
        // 角度太小等同于没有地平线，直接不报
        return abs(degrees) < 0.4 ? nil : degrees
    }

    // MARK: 平均亮度

    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func averageBrightness(_ image: UIImage) -> Double? {
        guard let cg = image.scaled(toMaxDimension: 120).normalizedCGImage() else { return nil }
        let input = CIImage(cgImage: cg)

        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent

        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output,
                       toBitmap: &pixel,
                       rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8,
                       colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = Double(pixel[0]) / 255.0
        let g = Double(pixel[1]) / 255.0
        let b = Double(pixel[2]) / 255.0
        // Rec.709 亮度
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

// MARK: - 场景线索

/// 从一帧画面里能可靠得到的场景信息。
/// 注意：不猜「室内还是室外」——那是猜不准的，交给多模态模型去做。
struct SceneContext {
    var personCount: Int = 0
    var brightness: Double = 0.5
    var faceCount: Int = 0
    /// 主体在画面里占多大 —— 决定推荐半身还是全身
    var subjectCoverage: Double = 0

    var framingHint: String {
        if subjectCoverage > 0.45 { return "特写" }
        if subjectCoverage > 0.20 { return "半身" }
        return "全身"
    }

    var lightHint: String {
        if brightness < 0.25 { return "暗光" }
        if brightness > 0.8 { return "强光" }
        return "常规光"
    }
}
