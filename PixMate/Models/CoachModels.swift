import Foundation
import CoreGraphics

// MARK: - 关节

/// 人体骨架的一个关节。坐标**归一化到整帧**（0…1，左上为原点），
/// Vision 的原生坐标系是左下原点，转换在 PersonDetector 里完成。
struct SkeletonJoint: Identifiable, Hashable, Sendable {
    var id: String
    var point: CGPoint
    var confidence: Float

    var isReliable: Bool { confidence >= 0.25 }
}

/// 一帧里检测到的一个人
struct DetectedPerson: Identifiable, Hashable, Sendable {
    var id = UUID()
    /// 归一化的人体外接框（左上原点）
    var boundingBox: CGRect
    /// 归一化的人脸框
    var faceBox: CGRect?
    /// 归一化关键点，键为 JointName
    var joints: [String: SkeletonJoint] = [:]

    /// 像素级骨架（相对整帧），用于叠加层绘制
    func pixelJoints(in size: CGSize) -> [String: CGPoint] {
        joints.mapValues { CGPoint(x: $0.point.x * size.width, y: $0.point.y * size.height) }
    }
}

/// Vision 人体姿态的关节名常量表（与 VNHumanBodyPoseObservation.JointName 对齐）
enum JointName {
    static let nose = "nose"
    static let neck = "neck"
    static let leftShoulder = "left_shoulder"
    static let rightShoulder = "right_shoulder"
    static let leftElbow = "left_elbow"
    static let rightElbow = "right_elbow"
    static let leftWrist = "left_wrist"
    static let rightWrist = "right_wrist"
    static let root = "root"
    static let leftHip = "left_hip"
    static let rightHip = "right_hip"
    static let leftKnee = "left_knee"
    static let rightKnee = "right_knee"
    static let leftAnkle = "left_ankle"
    static let rightAnkle = "right_ankle"

    /// 绘制骨架时的连线关系
    static let connections: [(String, String)] = [
        (nose, neck),
        (neck, leftShoulder), (neck, rightShoulder),
        (leftShoulder, leftElbow), (leftElbow, leftWrist),
        (rightShoulder, rightElbow), (rightElbow, rightWrist),
        (neck, root),
        (root, leftHip), (root, rightHip),
        (leftHip, leftKnee), (leftKnee, leftAnkle),
        (rightHip, rightKnee), (rightKnee, rightAnkle)
    ]
}

// MARK: - 构图诊断

enum AdviceSeverity {
    case good      // 没问题
    case tip       // 可以更好
    case warning   // 建议立刻改

    var symbolName: String {
        switch self {
        case .good:    return "checkmark.circle.fill"
        case .tip:     return "lightbulb.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

/// 一条**可执行**的构图建议。
/// 刻意不做成「打个 78 分」——那个分数没法指导拍摄。
/// 每条都必须能翻译成一句立刻能做的动作。
struct CompositionIssue: Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var detail: String
    var severity: AdviceSeverity
    var action: String
    /// 想在画面上标注的位置（归一化），没有就不标
    var anchor: CGPoint?
}

struct CompositionReport: Equatable, Sendable {
    /// 综合分只作为进度参考，UI 上不作为主信息
    var score: Int = 0
    var issues: [CompositionIssue] = []
    /// 地平线倾角（度），负=左倾，正=右倾
    var horizonAngle: Double?
    /// 主体在画面中的面积占比 0…1
    var subjectCoverage: Double = 0
    /// 头顶留白占画面高度比例
    var headroom: Double = 0
    /// 人物是否落在三分线附近
    var onThirds: Bool = false
    /// 人是否贴边或被裁切
    var subjectClipped: Bool = false

    var topIssues: [CompositionIssue] {
        issues.filter { $0.severity != .good }
    }

    var isEmpty: Bool { issues.isEmpty }
}

// MARK: - 姿势分类

/// 姿势库的六个大类，筛选条直接用。
enum PoseCategory: String, CaseIterable, Hashable, Sendable {
    case standing
    case sitting
    case leaning
    case dynamic
    case closeup
    case duo

    var displayName: String {
        switch self {
        case .standing: return "站姿"
        case .sitting:  return "坐姿"
        case .leaning:  return "靠撑"
        case .dynamic:  return "动态"
        case .closeup:  return "半身特写"
        case .duo:      return "双人"
        }
    }
}

// MARK: - 姿势建议

enum PoseSource: String, Codable, Sendable {
    /// 本地姿势库 —— 零延迟、离线可用
    case library
    /// 多模态模型按画面里实际景色现场生成
    case generated
    /// 引导用的通用线框（只给人体轮廓，不给具体姿势）
    case guide

    var displayName: String {
        switch self {
        case .library:   return "姿势库"
        case .generated: return "AI 现场生成"
        case .guide:     return "引导线框"
        }
    }
}

/// 一条姿势建议。
/// `normalizedJoints` 的坐标是**相对人体外接框**的（0…1），
/// 所以能直接套到画面里检测到的任意一个人身上。
struct PoseSuggestion: Identifiable, Hashable, Sendable {
    var id = UUID()
    var title: String
    /// 给模特听的提示语，一句话
    var hint: String
    /// 适合的场景，如「室内 / 半身 / 坐姿」
    var tags: [String] = []
    var source: PoseSource = .library
    /// 相对人体框的骨架坐标
    var normalizedJoints: [String: CGPoint] = [:]
    /// 由多模态模型生成时，附上它看到的具体景色依据
    var sceneNote: String?
    /// 给模特的距离提示（半身 / 全身 / 特写）
    var framing: String = "半身"
    /// 所属大类，筛选条用
    var category: PoseCategory = .standing

    static func == (lhs: PoseSuggestion, rhs: PoseSuggestion) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 叠加层开关

struct OverlayOptions: Codable, Equatable {
    var showThirds: Bool = true
    var showHorizon: Bool = true
    var showSkeleton: Bool = true
    var showPoseGhost: Bool = true
    var showFaceBoxes: Bool = false
    var showAdvice: Bool = true
}

// MARK: - 一帧分析的结果

/// 后台线程算完、回主线程更新 UI 的载体。
/// 全部由值类型组成，所以可以安全跨 actor 传递（Sendable）。
struct CoachAnalysis: Sendable {
    var people: [DetectedPerson] = []
    var faces: [FaceGeometry] = []
    var report = CompositionReport()
    var brightness: Double = 0.5
}
