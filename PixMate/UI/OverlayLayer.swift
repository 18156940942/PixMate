import SwiftUI

// MARK: - 取景叠加层
//
// 画在实时画面之上。所有坐标都是归一化的（0…1，左上原点），
// 乘上 Canvas 的尺寸就落到屏幕上——因为这里的尺寸和底层画面完全一致。

struct OverlayLayer: View {
    var options: OverlayOptions
    var report: CompositionReport
    var people: [DetectedPerson]
    var faces: [FaceGeometry]
    var targetPose: PoseSuggestion?

    private let accent = Color(red: 0.24, green: 0.86, blue: 0.62)
    private let warn = Color(red: 1.0, green: 0.62, blue: 0.20)
    private let ghost = Color(red: 1.0, green: 0.85, blue: 0.35)

    var body: some View {
        Canvas { context, size in
            if options.showThirds {
                drawThirds(context: context, size: size)
            }
            if options.showHorizon {
                drawHorizon(context: context, size: size)
            }
            if options.showFaceBoxes {
                drawFaceBoxes(context: context, size: size)
            }
            if options.showSkeleton {
                drawSkeletons(context: context, size: size)
            }
            if options.showPoseGhost {
                drawPoseGhost(context: context, size: size)
            }
            if options.showAdvice {
                drawAdviceAnchors(context: context, size: size)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 三分线

    private func drawThirds(context: GraphicsContext, size: CGSize) {
        var path = Path()
        for i in 1...2 {
            let x = size.width * CGFloat(i) / 3
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))

            let y = size.height * CGFloat(i) / 3
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(path, with: .color(.white.opacity(0.22)), lineWidth: 1)
    }

    // MARK: 水平参考线

    private func drawHorizon(context: GraphicsContext, size: CGSize) {
        let tilted = (report.horizonAngle.map { abs($0) >= 1.0 }) ?? false
        let color = tilted ? warn : accent

        var path = Path()
        let y = size.height / 2
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(path,
                       with: .color(color.opacity(tilted ? 0.95 : 0.5)),
                       style: StrokeStyle(lineWidth: tilted ? 2 : 1, dash: [7, 6]))

        if tilted, let angle = report.horizonAngle {
            // 在右侧画出「该回正多少」的提示
            let text = Text(String(format: "%+.1f°", angle))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            context.draw(text, at: CGPoint(x: size.width - 34, y: y - 16))
        }
    }

    // MARK: 人脸框

    private func drawFaceBoxes(context: GraphicsContext, size: CGSize) {
        for face in faces {
            let rect = CGRect(x: face.faceBox.minX * size.width,
                              y: face.faceBox.minY * size.height,
                              width: face.faceBox.width * size.width,
                              height: face.faceBox.height * size.height)
            context.stroke(Path(roundedRect: rect, cornerRadius: 6),
                           with: .color(accent.opacity(0.8)),
                           lineWidth: 1.4)
        }
    }

    // MARK: 骨架

    private func drawSkeletons(context: GraphicsContext, size: CGSize) {
        for person in people {
            let points = person.joints.mapValues {
                CGPoint(x: $0.point.x * size.width, y: $0.point.y * size.height)
            }

            for (a, b) in JointName.connections {
                guard let pa = points[a], let pb = points[b] else { continue }
                var path = Path()
                path.move(to: pa)
                path.addLine(to: pb)
                context.stroke(path, with: .color(accent.opacity(0.85)), lineWidth: 2.2)
            }

            for (_, point) in points {
                let r: CGFloat = 3.2
                let dot = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: dot), with: .color(accent))
            }
        }
    }

    // MARK: 姿势幽灵

    private func drawPoseGhost(context: GraphicsContext, size: CGSize) {
        guard let pose = targetPose, !pose.normalizedJoints.isEmpty else { return }
        // 套在画面里最大的那个人身上
        guard let subject = people.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) else { return }

        let box = subject.boundingBox
        func project(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (box.minX + p.x * box.width) * size.width,
                    y: (box.minY + p.y * box.height) * size.height)
        }

        let joints = pose.normalizedJoints.mapValues(project)

        for (a, b) in JointName.connections {
            guard let pa = joints[a], let pb = joints[b] else { continue }
            var path = Path()
            path.move(to: pa)
            path.addLine(to: pb)
            context.stroke(path,
                           with: .color(ghost.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 2.6, dash: [6, 4]))
        }

        for (_, point) in joints {
            let r: CGFloat = 3.6
            let dot = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: dot), with: .color(ghost), lineWidth: 1.6)
        }
    }

    // MARK: 建议锚点

    private func drawAdviceAnchors(context: GraphicsContext, size: CGSize) {
        for issue in report.topIssues {
            guard let anchor = issue.anchor else { continue }
            let center = CGPoint(x: anchor.x * size.width, y: anchor.y * size.height)
            let color = issue.severity == .warning ? warn : ghost

            let r: CGFloat = 14
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.9)), lineWidth: 1.8)

            // 呼吸环
            let outer = rect.insetBy(dx: -6, dy: -6)
            context.stroke(Path(ellipseIn: outer), with: .color(color.opacity(0.28)), lineWidth: 1.2)
        }
    }
}
