import Foundation
import CoreGraphics

// MARK: - 姿势库
//
// 每条姿势的骨架坐标是**相对人体外接框**的：
//   (0,0) = 人体框左上，(1,1) = 人体框右下
// 所以同一条姿势能直接套到画面里检测到的任意一个人身上，
// 横向压扁 / 纵向拉长都会自动跟着人走。
//
// 全部离线，零延迟，不依赖网络。
// 六大类：站姿 / 坐姿 / 靠撑 / 动态 / 半身特写 / 双人。

enum PoseLibrary {

    // MARK: 智能挑选

    /// 按画幅、光线、人数挑合适的姿势，并轮换，避免每次都是同一条。
    /// `category` 为 nil 时走智能模式：按当前画面自动选类，双人时混入互动姿势。
    static func pick(framing: String,
                     light: String,
                     personCount: Int,
                     seed: Int,
                     category: PoseCategory? = nil,
                     limit: Int = 4) -> [PoseSuggestion] {

        var pool: [PoseSuggestion]
        var duoBonus: [PoseSuggestion] = []

        if let category {
            // 显式选了类：以类为主，画幅不合适的不硬塞
            pool = all.filter { $0.category == category }
            if framing == "特写" || framing == "半身" {
                let upper = pool.filter { $0.framing == "半身" || $0.framing == "特写" }
                if !upper.isEmpty { pool = upper }
            }
        } else {
            pool = all.filter { $0.category != .duo }

            // 特写和半身优先上半身姿势
            if framing == "特写" || framing == "半身" {
                let upper = pool.filter { $0.framing == "半身" || $0.framing == "特写" }
                if !upper.isEmpty { pool = upper }
            }
            // 两个人时，混入双人互动姿势
            if personCount == 2 {
                duoBonus = all.filter { $0.category == .duo }
            }
        }

        // 人多时推荐互动感弱一点的独立姿势
        if personCount >= 3 {
            let solo = pool.filter { !$0.tags.contains("双人") }
            if !solo.isEmpty { pool = solo }
        }
        // 暗光下推荐静态姿势，减少糊片概率
        if light == "暗光" {
            let steady = pool.filter { !$0.tags.contains("动态") }
            if !steady.isEmpty { pool = steady }
        }

        guard !pool.isEmpty || !duoBonus.isEmpty else { return [] }

        let offset = abs(seed) % max(1, pool.count)
        var result: [PoseSuggestion] = []

        // 双人时：先给 1 条互动姿势，再给单人姿势
        if !duoBonus.isEmpty {
            let duoOffset = abs(seed) % duoBonus.count
            result.append(duoBonus[duoOffset])
        }

        for i in 0..<min(limit - result.count, pool.count) {
            result.append(pool[(offset + i) % pool.count])
        }
        return result
    }

    // MARK: 全量列表

    static let all: [PoseSuggestion] = [
        // 站姿
        standingNeutral, threeQuarterTurn, handInPocket, legsCrossedStand,
        handsBehindBack, sideProfileStand, jacketPull, handShading, fullBodyStretch,
        // 坐姿
        seatedLean, crossLeggedSit, floorCrossSit, hugKnees, chairSideSit,
        // 靠撑
        leaningWall, railingLean, tableLean, wallSquat,
        // 动态
        walking, dressSpin, hairFlip, bigStride, lightJump,
        // 半身特写
        armsCrossed, handOnHip, handInHair, lookBack, headTilt,
        chinRest, handOnShoulder, handFramingFace, eyesClosed,
        // 双人
        backToBack, handInHand, shoulderLean
    ]

    // MARK: 构造

    private static func make(_ title: String,
                             _ hint: String,
                             tags: [String],
                             framing: String,
                             category: PoseCategory,
                             _ points: [(String, CGFloat, CGFloat)]) -> PoseSuggestion {
        var joints: [String: CGPoint] = [:]
        for (name, x, y) in points {
            joints[name] = CGPoint(x: x, y: y)
        }
        return PoseSuggestion(title: title,
                              hint: hint,
                              tags: tags,
                              source: .library,
                              normalizedJoints: joints,
                              framing: framing,
                              category: category)
    }

    // MARK: 站姿

    static let standingNeutral = make(
        "正面自然站",
        "重心放一条腿上，另一条腿轻轻点地，肩膀往下沉",
        tags: ["单人", "静态", "万能"], framing: "全身", category: .standing,
        [(JointName.nose, 0.50, 0.07),
         (JointName.neck, 0.50, 0.15),
         (JointName.leftShoulder, 0.36, 0.20), (JointName.rightShoulder, 0.64, 0.20),
         (JointName.leftElbow, 0.30, 0.35),   (JointName.rightElbow, 0.70, 0.35),
         (JointName.leftWrist, 0.28, 0.49),   (JointName.rightWrist, 0.72, 0.49),
         (JointName.root, 0.50, 0.50),
         (JointName.leftHip, 0.41, 0.52),     (JointName.rightHip, 0.59, 0.52),
         (JointName.leftKnee, 0.42, 0.74),    (JointName.rightKnee, 0.58, 0.72),
         (JointName.leftAnkle, 0.42, 0.96),   (JointName.rightAnkle, 0.58, 0.95)]
    )

    static let threeQuarterTurn = make(
        "侧身三分之二",
        "身体转开 45° 只留四分之三侧脸，前肩往前送一点",
        tags: ["单人", "静态", "显瘦", "万能"], framing: "全身", category: .standing,
        [(JointName.nose, 0.55, 0.07),
         (JointName.neck, 0.52, 0.15),
         (JointName.leftShoulder, 0.40, 0.20), (JointName.rightShoulder, 0.66, 0.22),
         (JointName.leftElbow, 0.36, 0.35),   (JointName.rightElbow, 0.72, 0.37),
         (JointName.leftWrist, 0.34, 0.49),   (JointName.rightWrist, 0.70, 0.51),
         (JointName.root, 0.52, 0.50),
         (JointName.leftHip, 0.45, 0.52),     (JointName.rightHip, 0.60, 0.51),
         (JointName.leftKnee, 0.46, 0.74),    (JointName.rightKnee, 0.59, 0.72),
         (JointName.leftAnkle, 0.47, 0.96),   (JointName.rightAnkle, 0.58, 0.95)]
    )

    static let handInPocket = make(
        "插兜回眸",
        "一只手插兜，身体先转走再回头，下巴别抬",
        tags: ["单人", "静态", "街拍"], framing: "全身", category: .standing,
        [(JointName.nose, 0.58, 0.08),
         (JointName.neck, 0.53, 0.16),
         (JointName.leftShoulder, 0.41, 0.21), (JointName.rightShoulder, 0.65, 0.21),
         (JointName.leftElbow, 0.39, 0.36),   (JointName.rightElbow, 0.62, 0.37),
         (JointName.leftWrist, 0.38, 0.48),   (JointName.rightWrist, 0.54, 0.50),
         (JointName.root, 0.52, 0.51),
         (JointName.leftHip, 0.45, 0.53),     (JointName.rightHip, 0.59, 0.53),
         (JointName.leftKnee, 0.46, 0.75),    (JointName.rightKnee, 0.58, 0.73),
         (JointName.leftAnkle, 0.47, 0.96),   (JointName.rightAnkle, 0.58, 0.95)]
    )

    static let legsCrossedStand = make(
        "双腿交叉站",
        "前腿从膝盖处轻轻搭过后腿，膝盖别锁死，胯往后收",
        tags: ["单人", "静态", "显瘦"], framing: "全身", category: .standing,
        [(JointName.nose, 0.52, 0.07),
         (JointName.neck, 0.51, 0.15),
         (JointName.leftShoulder, 0.38, 0.20), (JointName.rightShoulder, 0.64, 0.20),
         (JointName.leftElbow, 0.33, 0.35),   (JointName.rightElbow, 0.68, 0.36),
         (JointName.leftWrist, 0.32, 0.49),   (JointName.rightWrist, 0.66, 0.50),
         (JointName.root, 0.51, 0.51),
         (JointName.leftHip, 0.42, 0.53),     (JointName.rightHip, 0.58, 0.53),
         (JointName.leftKnee, 0.50, 0.74),    (JointName.rightKnee, 0.58, 0.73),
         (JointName.leftAnkle, 0.56, 0.95),   (JointName.rightAnkle, 0.60, 0.94)]
    )

    static let handsBehindBack = make(
        "背手而立",
        "两手在身后轻轻交叠，胸口自然会挺起来，下巴微收",
        tags: ["单人", "静态", "气场"], framing: "全身", category: .standing,
        [(JointName.nose, 0.50, 0.07),
         (JointName.neck, 0.50, 0.15),
         (JointName.leftShoulder, 0.36, 0.20), (JointName.rightShoulder, 0.64, 0.20),
         (JointName.leftElbow, 0.30, 0.34),   (JointName.rightElbow, 0.70, 0.34),
         (JointName.leftWrist, 0.44, 0.45),   (JointName.rightWrist, 0.56, 0.45),
         (JointName.root, 0.50, 0.51),
         (JointName.leftHip, 0.41, 0.53),     (JointName.rightHip, 0.59, 0.53),
         (JointName.leftKnee, 0.42, 0.74),    (JointName.rightKnee, 0.58, 0.74),
         (JointName.leftAnkle, 0.42, 0.95),   (JointName.rightAnkle, 0.58, 0.95)]
    )

    static let sideProfileStand = make(
        "侧身远望",
        "整个人转成侧面，眼睛看向远处不看镜头，脖子拉长",
        tags: ["单人", "静态", "故事感"], framing: "全身", category: .standing,
        [(JointName.nose, 0.62, 0.08),
         (JointName.neck, 0.56, 0.16),
         (JointName.leftShoulder, 0.46, 0.22), (JointName.rightShoulder, 0.62, 0.21),
         (JointName.leftElbow, 0.42, 0.36),   (JointName.rightElbow, 0.58, 0.35),
         (JointName.leftWrist, 0.44, 0.48),   (JointName.rightWrist, 0.56, 0.47),
         (JointName.root, 0.52, 0.51),
         (JointName.leftHip, 0.47, 0.53),     (JointName.rightHip, 0.57, 0.53),
         (JointName.leftKnee, 0.50, 0.74),    (JointName.rightKnee, 0.55, 0.74),
         (JointName.leftAnkle, 0.52, 0.95),   (JointName.rightAnkle, 0.56, 0.95)]
    )

    static let jacketPull = make(
        "拽着衣角",
        "一只手轻轻拽住外套下摆往一侧拉，另一只手自然放松",
        tags: ["单人", "静态", "街拍"], framing: "全身", category: .standing,
        [(JointName.nose, 0.48, 0.08),
         (JointName.neck, 0.49, 0.16),
         (JointName.leftShoulder, 0.35, 0.21), (JointName.rightShoulder, 0.63, 0.21),
         (JointName.leftElbow, 0.28, 0.36),   (JointName.rightElbow, 0.72, 0.36),
         (JointName.leftWrist, 0.30, 0.49),   (JointName.rightWrist, 0.62, 0.50),
         (JointName.root, 0.50, 0.51),
         (JointName.leftHip, 0.41, 0.53),     (JointName.rightHip, 0.59, 0.53),
         (JointName.leftKnee, 0.42, 0.74),    (JointName.rightKnee, 0.58, 0.74),
         (JointName.leftAnkle, 0.42, 0.95),   (JointName.rightAnkle, 0.58, 0.95)]
    )

    static let handShading = make(
        "搭凉棚远眺",
        "一只手抬到眉骨遮光，像在找远处的什么，眼睛眯一点",
        tags: ["单人", "静态", "旅行"], framing: "全身", category: .standing,
        [(JointName.nose, 0.50, 0.09),
         (JointName.neck, 0.50, 0.17),
         (JointName.leftShoulder, 0.36, 0.22), (JointName.rightShoulder, 0.64, 0.22),
         (JointName.leftElbow, 0.29, 0.37),   (JointName.rightElbow, 0.74, 0.32),
         (JointName.leftWrist, 0.32, 0.52),   (JointName.rightWrist, 0.60, 0.10),
         (JointName.root, 0.50, 0.52),
         (JointName.leftHip, 0.41, 0.54),     (JointName.rightHip, 0.59, 0.54),
         (JointName.leftKnee, 0.43, 0.75),    (JointName.rightKnee, 0.57, 0.75),
         (JointName.leftAnkle, 0.43, 0.96),   (JointName.rightAnkle, 0.57, 0.96)]
    )

    static let fullBodyStretch = make(
        "舒展站立",
        "双臂往上拉开，指尖用力往上够，把身形拉长",
        tags: ["单人", "静态", "姿态"], framing: "全身", category: .standing,
        [(JointName.nose, 0.50, 0.10),
         (JointName.neck, 0.50, 0.18),
         (JointName.leftShoulder, 0.37, 0.23), (JointName.rightShoulder, 0.63, 0.23),
         (JointName.leftElbow, 0.32, 0.14),   (JointName.rightElbow, 0.68, 0.14),
         (JointName.leftWrist, 0.30, 0.04),   (JointName.rightWrist, 0.70, 0.04),
         (JointName.root, 0.50, 0.52),
         (JointName.leftHip, 0.42, 0.54),     (JointName.rightHip, 0.58, 0.54),
         (JointName.leftKnee, 0.43, 0.75),    (JointName.rightKnee, 0.57, 0.75),
         (JointName.leftAnkle, 0.43, 0.96),   (JointName.rightAnkle, 0.57, 0.96)]
    )

    // MARK: 坐姿

    static let seatedLean = make(
        "坐姿前倾",
        "坐椅子前三分之一，身体往膝盖方向前倾，手肘搭在腿上",
        tags: ["单人", "静态", "室内"], framing: "半身", category: .sitting,
        [(JointName.nose, 0.52, 0.14),
         (JointName.neck, 0.51, 0.25),
         (JointName.leftShoulder, 0.38, 0.32), (JointName.rightShoulder, 0.64, 0.32),
         (JointName.leftElbow, 0.33, 0.50),   (JointName.rightElbow, 0.69, 0.50),
         (JointName.leftWrist, 0.42, 0.64),   (JointName.rightWrist, 0.62, 0.64),
         (JointName.root, 0.51, 0.66),
         (JointName.leftHip, 0.43, 0.74),     (JointName.rightHip, 0.59, 0.74),
         (JointName.leftKnee, 0.38, 0.90),    (JointName.rightKnee, 0.62, 0.90)]
    )

    static let crossLeggedSit = make(
        "翘腿坐",
        "一条腿搭到另一条腿上，背挺直别塌腰，手搭在膝盖上",
        tags: ["单人", "静态", "室内", "气场"], framing: "全身", category: .sitting,
        [(JointName.nose, 0.49, 0.12),
         (JointName.neck, 0.49, 0.22),
         (JointName.leftShoulder, 0.36, 0.28), (JointName.rightShoulder, 0.63, 0.28),
         (JointName.leftElbow, 0.31, 0.43),   (JointName.rightElbow, 0.68, 0.43),
         (JointName.leftWrist, 0.42, 0.55),   (JointName.rightWrist, 0.69, 0.46),
         (JointName.root, 0.50, 0.56),
         (JointName.leftHip, 0.42, 0.62),     (JointName.rightHip, 0.58, 0.62),
         (JointName.leftKnee, 0.60, 0.72),    (JointName.rightKnee, 0.62, 0.74),
         (JointName.leftAnkle, 0.66, 0.90),   (JointName.rightAnkle, 0.60, 0.95)]
    )

    static let floorCrossSit = make(
        "席地盘腿坐",
        "盘腿坐在地上，手自然搭在膝盖上，背立直",
        tags: ["单人", "静态", "生活感"], framing: "全身", category: .sitting,
        [(JointName.nose, 0.50, 0.16),
         (JointName.neck, 0.50, 0.28),
         (JointName.leftShoulder, 0.34, 0.35), (JointName.rightShoulder, 0.66, 0.35),
         (JointName.leftElbow, 0.27, 0.50),   (JointName.rightElbow, 0.73, 0.50),
         (JointName.leftWrist, 0.30, 0.64),   (JointName.rightWrist, 0.70, 0.64),
         (JointName.root, 0.50, 0.60),
         (JointName.leftHip, 0.40, 0.66),     (JointName.rightHip, 0.60, 0.66),
         (JointName.leftKnee, 0.28, 0.74),    (JointName.rightKnee, 0.72, 0.74),
         (JointName.leftAnkle, 0.46, 0.95),   (JointName.rightAnkle, 0.54, 0.95)]
    )

    static let hugKnees = make(
        "抱膝坐",
        "膝盖收向胸口，双臂环住小腿，下巴可以轻搁在膝盖上",
        tags: ["单人", "静态", "情绪"], framing: "全身", category: .sitting,
        [(JointName.nose, 0.50, 0.24),
         (JointName.neck, 0.50, 0.34),
         (JointName.leftShoulder, 0.37, 0.40), (JointName.rightShoulder, 0.63, 0.40),
         (JointName.leftElbow, 0.33, 0.52),   (JointName.rightElbow, 0.67, 0.52),
         (JointName.leftWrist, 0.42, 0.66),   (JointName.rightWrist, 0.58, 0.66),
         (JointName.root, 0.50, 0.58),
         (JointName.leftHip, 0.42, 0.64),     (JointName.rightHip, 0.58, 0.64),
         (JointName.leftKnee, 0.38, 0.68),    (JointName.rightKnee, 0.62, 0.68),
         (JointName.leftAnkle, 0.40, 0.94),   (JointName.rightAnkle, 0.60, 0.94)]
    )

    static let chairSideSit = make(
        "侧身坐",
        "侧对着椅子坐，双腿并拢倒向一侧，一手搭在椅背上",
        tags: ["单人", "静态", "室内", "柔美"], framing: "全身", category: .sitting,
        [(JointName.nose, 0.58, 0.13),
         (JointName.neck, 0.55, 0.23),
         (JointName.leftShoulder, 0.42, 0.29), (JointName.rightShoulder, 0.66, 0.29),
         (JointName.leftElbow, 0.36, 0.44),   (JointName.rightElbow, 0.72, 0.42),
         (JointName.leftWrist, 0.38, 0.55),   (JointName.rightWrist, 0.74, 0.50),
         (JointName.root, 0.54, 0.58),
         (JointName.leftHip, 0.46, 0.64),     (JointName.rightHip, 0.62, 0.64),
         (JointName.leftKnee, 0.36, 0.80),    (JointName.rightKnee, 0.42, 0.80),
         (JointName.leftAnkle, 0.34, 0.95),   (JointName.rightAnkle, 0.40, 0.96)]
    )

    // MARK: 靠撑

    static let leaningWall = make(
        "靠墙倚立",
        "后背和肩胛贴墙，一条腿屈起来踩墙，下巴略收",
        tags: ["单人", "静态", "街拍"], framing: "全身", category: .leaning,
        [(JointName.nose, 0.46, 0.08),
         (JointName.neck, 0.48, 0.16),
         (JointName.leftShoulder, 0.35, 0.21), (JointName.rightShoulder, 0.62, 0.21),
         (JointName.leftElbow, 0.30, 0.37),   (JointName.rightElbow, 0.68, 0.36),
         (JointName.leftWrist, 0.29, 0.51),   (JointName.rightWrist, 0.66, 0.50),
         (JointName.root, 0.49, 0.51),
         (JointName.leftHip, 0.42, 0.53),     (JointName.rightHip, 0.58, 0.53),
         (JointName.leftKnee, 0.44, 0.74),    (JointName.rightKnee, 0.64, 0.70),
         (JointName.leftAnkle, 0.45, 0.96),   (JointName.rightAnkle, 0.68, 0.82)]
    )

    static let railingLean = make(
        "倚栏杆",
        "双手或单手搭在栏杆上，上半身微微前倾送出去",
        tags: ["单人", "静态", "旅行"], framing: "全身", category: .leaning,
        [(JointName.nose, 0.56, 0.09),
         (JointName.neck, 0.54, 0.17),
         (JointName.leftShoulder, 0.40, 0.22), (JointName.rightShoulder, 0.66, 0.22),
         (JointName.leftElbow, 0.34, 0.34),   (JointName.rightElbow, 0.72, 0.30),
         (JointName.leftWrist, 0.38, 0.50),   (JointName.rightWrist, 0.68, 0.36),
         (JointName.root, 0.52, 0.51),
         (JointName.leftHip, 0.44, 0.53),     (JointName.rightHip, 0.60, 0.53),
         (JointName.leftKnee, 0.44, 0.74),    (JointName.rightKnee, 0.60, 0.74),
         (JointName.leftAnkle, 0.44, 0.95),   (JointName.rightAnkle, 0.60, 0.95)]
    )

    static let tableLean = make(
        "撑桌面",
        "双手撑在桌上，肩往下压，身体重心前倾，眼神从手臂间投出来",
        tags: ["单人", "静态", "室内", "气场"], framing: "半身", category: .leaning,
        [(JointName.nose, 0.50, 0.20),
         (JointName.neck, 0.50, 0.30),
         (JointName.leftShoulder, 0.35, 0.35), (JointName.rightShoulder, 0.65, 0.35),
         (JointName.leftElbow, 0.30, 0.48),   (JointName.rightElbow, 0.70, 0.48),
         (JointName.leftWrist, 0.42, 0.50),   (JointName.rightWrist, 0.58, 0.50),
         (JointName.root, 0.50, 0.58),
         (JointName.leftHip, 0.41, 0.62),     (JointName.rightHip, 0.59, 0.62),
         (JointName.leftKnee, 0.42, 0.80),    (JointName.rightKnee, 0.58, 0.80),
         (JointName.leftAnkle, 0.43, 0.96),   (JointName.rightAnkle, 0.57, 0.96)]
    )

    static let wallSquat = make(
        "贴墙蹲",
        "背贴墙蹲低一点，手肘搭在膝盖上，重心稳住别晃",
        tags: ["单人", "静态", "街拍"], framing: "全身", category: .leaning,
        [(JointName.nose, 0.48, 0.22),
         (JointName.neck, 0.48, 0.32),
         (JointName.leftShoulder, 0.34, 0.38), (JointName.rightShoulder, 0.62, 0.38),
         (JointName.leftElbow, 0.29, 0.50),   (JointName.rightElbow, 0.67, 0.50),
         (JointName.leftWrist, 0.34, 0.62),   (JointName.rightWrist, 0.62, 0.60),
         (JointName.root, 0.48, 0.62),
         (JointName.leftHip, 0.40, 0.66),     (JointName.rightHip, 0.56, 0.66),
         (JointName.leftKnee, 0.30, 0.70),    (JointName.rightKnee, 0.62, 0.72),
         (JointName.leftAnkle, 0.34, 0.94),   (JointName.rightAnkle, 0.66, 0.90)]
    )

    // MARK: 动态

    static let walking = make(
        "走动抓拍",
        "自然往前走，别停下来看镜头，手脚甩开",
        tags: ["单人", "动态", "生活感"], framing: "全身", category: .dynamic,
        [(JointName.nose, 0.52, 0.07),
         (JointName.neck, 0.50, 0.15),
         (JointName.leftShoulder, 0.37, 0.20), (JointName.rightShoulder, 0.63, 0.20),
         (JointName.leftElbow, 0.30, 0.34),   (JointName.rightElbow, 0.70, 0.33),
         (JointName.leftWrist, 0.26, 0.46),   (JointName.rightWrist, 0.72, 0.44),
         (JointName.root, 0.50, 0.50),
         (JointName.leftHip, 0.41, 0.52),     (JointName.rightHip, 0.59, 0.52),
         (JointName.leftKnee, 0.34, 0.72),    (JointName.rightKnee, 0.62, 0.74),
         (JointName.leftAnkle, 0.30, 0.94),   (JointName.rightAnkle, 0.64, 0.96)]
    )

    static let dressSpin = make(
        "转动裙摆",
        "用腰带动转身，裙摆甩起来那一刻按快门，脸保持朝镜头",
        tags: ["单人", "动态", "裙装"], framing: "全身", category: .dynamic,
        [(JointName.nose, 0.50, 0.08),
         (JointName.neck, 0.50, 0.16),
         (JointName.leftShoulder, 0.34, 0.21), (JointName.rightShoulder, 0.66, 0.21),
         (JointName.leftElbow, 0.22, 0.28),   (JointName.rightElbow, 0.78, 0.32),
         (JointName.leftWrist, 0.12, 0.20),   (JointName.rightWrist, 0.88, 0.42),
         (JointName.root, 0.50, 0.51),
         (JointName.leftHip, 0.40, 0.53),     (JointName.rightHip, 0.60, 0.53),
         (JointName.leftKnee, 0.40, 0.74),    (JointName.rightKnee, 0.60, 0.74),
         (JointName.leftAnkle, 0.38, 0.95),   (JointName.rightAnkle, 0.62, 0.95)]
    )

    static let hairFlip = make(
        "甩发瞬间",
        "头往一侧甩，手指穿过头发带过去，连续做让摄影师抓",
        tags: ["单人", "动态", "长发"], framing: "半身", category: .dynamic,
        [(JointName.nose, 0.44, 0.06),
         (JointName.neck, 0.50, 0.16),
         (JointName.leftShoulder, 0.36, 0.22), (JointName.rightShoulder, 0.64, 0.22),
         (JointName.leftElbow, 0.30, 0.36),   (JointName.rightElbow, 0.72, 0.30),
         (JointName.leftWrist, 0.36, 0.50),   (JointName.rightWrist, 0.58, 0.08),
         (JointName.root, 0.50, 0.51),
         (JointName.leftHip, 0.41, 0.53),     (JointName.rightHip, 0.59, 0.53),
         (JointName.leftKnee, 0.42, 0.74),    (JointName.rightKnee, 0.58, 0.74),
         (JointName.leftAnkle, 0.42, 0.95),   (JointName.rightAnkle, 0.58, 0.95)]
    )

    static let bigStride = make(
        "大步流星",
        "迈开大步往前跨，手臂前后甩开，下巴抬起看前方",
        tags: ["单人", "动态", "气场"], framing: "全身", category: .dynamic,
        [(JointName.nose, 0.54, 0.07),
         (JointName.neck, 0.52, 0.15),
         (JointName.leftShoulder, 0.39, 0.20), (JointName.rightShoulder, 0.65, 0.20),
         (JointName.leftElbow, 0.32, 0.32),   (JointName.rightElbow, 0.72, 0.33),
         (JointName.leftWrist, 0.26, 0.42),   (JointName.rightWrist, 0.76, 0.44),
         (JointName.root, 0.52, 0.50),
         (JointName.leftHip, 0.43, 0.52),     (JointName.rightHip, 0.61, 0.52),
         (JointName.leftKnee, 0.36, 0.68),    (JointName.rightKnee, 0.64, 0.70),
         (JointName.leftAnkle, 0.30, 0.88),   (JointName.rightAnkle, 0.66, 0.96)]
    )

    static let lightJump = make(
        "轻盈跳起",
        "踮脚小跳，膝盖收一点，手臂上扬，落地前那一刻最好看",
        tags: ["单人", "动态", "旅行"], framing: "全身", category: .dynamic,
        [(JointName.nose, 0.50, 0.09),
         (JointName.neck, 0.50, 0.17),
         (JointName.leftShoulder, 0.35, 0.22), (JointName.rightShoulder, 0.65, 0.22),
         (JointName.leftElbow, 0.28, 0.18),   (JointName.rightElbow, 0.72, 0.18),
         (JointName.leftWrist, 0.24, 0.06),   (JointName.rightWrist, 0.76, 0.06),
         (JointName.root, 0.50, 0.52),
         (JointName.leftHip, 0.41, 0.54),     (JointName.rightHip, 0.59, 0.54),
         (JointName.leftKnee, 0.38, 0.70),    (JointName.rightKnee, 0.62, 0.70),
         (JointName.leftAnkle, 0.40, 0.84),   (JointName.rightAnkle, 0.60, 0.84)]
    )

    // MARK: 半身 / 特写

    static let armsCrossed = make(
        "抱臂",
        "双臂轻搭不要绷紧，手指放松，肩膀下沉别耸肩",
        tags: ["单人", "静态", "气场"], framing: "半身", category: .closeup,
        [(JointName.nose, 0.50, 0.10),
         (JointName.neck, 0.50, 0.20),
         (JointName.leftShoulder, 0.34, 0.26), (JointName.rightShoulder, 0.66, 0.26),
         (JointName.leftElbow, 0.28, 0.44),   (JointName.rightElbow, 0.72, 0.44),
         (JointName.leftWrist, 0.56, 0.46),   (JointName.rightWrist, 0.44, 0.48),
         (JointName.root, 0.50, 0.60),
         (JointName.leftHip, 0.40, 0.68),     (JointName.rightHip, 0.60, 0.68)]
    )

    static let handOnHip = make(
        "单手扶腰",
        "手肘往外撑出三角形，另一只手自然垂下",
        tags: ["单人", "静态", "显瘦"], framing: "半身", category: .closeup,
        [(JointName.nose, 0.50, 0.08),
         (JointName.neck, 0.50, 0.17),
         (JointName.leftShoulder, 0.36, 0.23), (JointName.rightShoulder, 0.64, 0.23),
         (JointName.leftElbow, 0.26, 0.40),   (JointName.rightElbow, 0.68, 0.40),
         (JointName.leftWrist, 0.42, 0.52),   (JointName.rightWrist, 0.70, 0.56),
         (JointName.root, 0.50, 0.55),
         (JointName.leftHip, 0.42, 0.62),     (JointName.rightHip, 0.58, 0.62),
         (JointName.leftKnee, 0.43, 0.82),    (JointName.rightKnee, 0.57, 0.82)]
    )

    static let handInHair = make(
        "手扶发丝",
        "手指插进头发往上撩一点，手腕别挡脸",
        tags: ["单人", "静态", "柔美", "半身"], framing: "半身", category: .closeup,
        [(JointName.nose, 0.48, 0.12),
         (JointName.neck, 0.50, 0.22),
         (JointName.leftShoulder, 0.35, 0.28), (JointName.rightShoulder, 0.65, 0.28),
         (JointName.leftElbow, 0.30, 0.46),   (JointName.rightElbow, 0.74, 0.42),
         (JointName.leftWrist, 0.34, 0.60),   (JointName.rightWrist, 0.60, 0.10),
         (JointName.root, 0.50, 0.62),
         (JointName.leftHip, 0.41, 0.70),     (JointName.rightHip, 0.59, 0.70)]
    )

    static let lookBack = make(
        "转身回望",
        "背对镜头，肩线先转，再回过头来，手可以往后搭",
        tags: ["单人", "静态", "故事感"], framing: "半身", category: .closeup,
        [(JointName.nose, 0.62, 0.09),
         (JointName.neck, 0.55, 0.19),
         (JointName.leftShoulder, 0.42, 0.25), (JointName.rightShoulder, 0.68, 0.25),
         (JointName.leftElbow, 0.38, 0.42),   (JointName.rightElbow, 0.72, 0.42),
         (JointName.leftWrist, 0.36, 0.56),   (JointName.rightWrist, 0.70, 0.56),
         (JointName.root, 0.53, 0.58),
         (JointName.leftHip, 0.46, 0.66),     (JointName.rightHip, 0.62, 0.66)]
    )

    static let headTilt = make(
        "歪头浅笑",
        "头轻轻往一侧倒，视线看向镜头外侧一点",
        tags: ["单人", "静态", "柔美", "特写"], framing: "特写", category: .closeup,
        [(JointName.nose, 0.54, 0.20),
         (JointName.neck, 0.49, 0.32),
         (JointName.leftShoulder, 0.34, 0.42), (JointName.rightShoulder, 0.64, 0.42),
         (JointName.leftElbow, 0.30, 0.62),   (JointName.rightElbow, 0.70, 0.62),
         (JointName.leftWrist, 0.32, 0.78),   (JointName.rightWrist, 0.68, 0.78),
         (JointName.root, 0.50, 0.78),
         (JointName.leftHip, 0.42, 0.90),     (JointName.rightHip, 0.58, 0.90)]
    )

    static let chinRest = make(
        "托腮凝视",
        "手背托住下巴，手肘撑稳，眼神放松看向镜头",
        tags: ["单人", "静态", "柔美", "室内"], framing: "半身", category: .closeup,
        [(JointName.nose, 0.46, 0.14),
         (JointName.neck, 0.48, 0.24),
         (JointName.leftShoulder, 0.34, 0.30), (JointName.rightShoulder, 0.64, 0.30),
         (JointName.leftElbow, 0.26, 0.48),   (JointName.rightElbow, 0.70, 0.46),
         (JointName.leftWrist, 0.42, 0.20),   (JointName.rightWrist, 0.66, 0.34),
         (JointName.root, 0.50, 0.55),
         (JointName.leftHip, 0.41, 0.64),     (JointName.rightHip, 0.59, 0.64)]
    )

    static let handOnShoulder = make(
        "手搭肩",
        "一只手搭在自己另一边肩膀上，头往反方向轻靠",
        tags: ["单人", "静态", "柔美"], framing: "半身", category: .closeup,
        [(JointName.nose, 0.52, 0.10),
         (JointName.neck, 0.51, 0.20),
         (JointName.leftShoulder, 0.35, 0.26), (JointName.rightShoulder, 0.65, 0.26),
         (JointName.leftElbow, 0.28, 0.42),   (JointName.rightElbow, 0.76, 0.36),
         (JointName.leftWrist, 0.30, 0.56),   (JointName.rightWrist, 0.64, 0.22),
         (JointName.root, 0.51, 0.55),
         (JointName.leftHip, 0.42, 0.64),     (JointName.rightHip, 0.60, 0.64)]
    )

    static let handFramingFace = make(
        "手背贴脸",
        "手背轻轻贴在脸颊一侧，手指自然弯着别僵",
        tags: ["单人", "静态", "柔美", "特写"], framing: "特写", category: .closeup,
        [(JointName.nose, 0.47, 0.16),
         (JointName.neck, 0.49, 0.28),
         (JointName.leftShoulder, 0.35, 0.34), (JointName.rightShoulder, 0.65, 0.34),
         (JointName.leftElbow, 0.26, 0.52),   (JointName.rightElbow, 0.74, 0.44),
         (JointName.leftWrist, 0.32, 0.64),   (JointName.rightWrist, 0.55, 0.16),
         (JointName.root, 0.50, 0.58),
         (JointName.leftHip, 0.42, 0.68),     (JointName.rightHip, 0.58, 0.68)]
    )

    static let eyesClosed = make(
        "闭眼仰头",
        "闭上眼睛，头微微仰起，感受光打在脸上",
        tags: ["单人", "静态", "情绪", "特写"], framing: "特写", category: .closeup,
        [(JointName.nose, 0.48, 0.13),
         (JointName.neck, 0.49, 0.24),
         (JointName.leftShoulder, 0.35, 0.31), (JointName.rightShoulder, 0.65, 0.31),
         (JointName.leftElbow, 0.29, 0.47),   (JointName.rightElbow, 0.71, 0.47),
         (JointName.leftWrist, 0.35, 0.58),   (JointName.rightWrist, 0.65, 0.58),
         (JointName.root, 0.50, 0.56),
         (JointName.leftHip, 0.42, 0.66),     (JointName.rightHip, 0.58, 0.66)]
    )

    // MARK: 双人

    static let backToBack = make(
        "背靠背",
        "两人背贴背站定，各自把重量轻轻交给对方，看向前方",
        tags: ["双人", "静态"], framing: "全身", category: .duo,
        [(JointName.nose, 0.46, 0.08),
         (JointName.neck, 0.48, 0.16),
         (JointName.leftShoulder, 0.34, 0.21), (JointName.rightShoulder, 0.62, 0.21),
         (JointName.leftElbow, 0.28, 0.35),   (JointName.rightElbow, 0.68, 0.35),
         (JointName.leftWrist, 0.30, 0.48),   (JointName.rightWrist, 0.66, 0.48),
         (JointName.root, 0.49, 0.51),
         (JointName.leftHip, 0.41, 0.53),     (JointName.rightHip, 0.57, 0.53),
         (JointName.leftKnee, 0.43, 0.74),    (JointName.rightKnee, 0.57, 0.74),
         (JointName.leftAnkle, 0.44, 0.95),   (JointName.rightAnkle, 0.58, 0.95)]
    )

    static let handInHand = make(
        "牵手对望",
        "两人隔开一步牵手，身体微微相向，互相看着笑",
        tags: ["双人", "静态", "情绪"], framing: "全身", category: .duo,
        [(JointName.nose, 0.42, 0.08),
         (JointName.neck, 0.45, 0.16),
         (JointName.leftShoulder, 0.33, 0.21), (JointName.rightShoulder, 0.61, 0.21),
         (JointName.leftElbow, 0.26, 0.33),   (JointName.rightElbow, 0.70, 0.30),
         (JointName.leftWrist, 0.22, 0.44),   (JointName.rightWrist, 0.84, 0.36),
         (JointName.root, 0.48, 0.51),
         (JointName.leftHip, 0.40, 0.53),     (JointName.rightHip, 0.58, 0.53),
         (JointName.leftKnee, 0.42, 0.74),    (JointName.rightKnee, 0.56, 0.74),
         (JointName.leftAnkle, 0.42, 0.95),   (JointName.rightAnkle, 0.56, 0.95)]
    )

    static let shoulderLean = make(
        "依靠肩膀",
        "头轻靠在对方肩上，一条手臂自然环过去",
        tags: ["双人", "静态", "情绪"], framing: "半身", category: .duo,
        [(JointName.nose, 0.58, 0.09),
         (JointName.neck, 0.55, 0.17),
         (JointName.leftShoulder, 0.42, 0.22), (JointName.rightShoulder, 0.68, 0.22),
         (JointName.leftElbow, 0.35, 0.36),   (JointName.rightElbow, 0.76, 0.32),
         (JointName.leftWrist, 0.36, 0.50),   (JointName.rightWrist, 0.80, 0.44),
         (JointName.root, 0.55, 0.52),
         (JointName.leftHip, 0.47, 0.54),     (JointName.rightHip, 0.63, 0.54),
         (JointName.leftKnee, 0.48, 0.75),    (JointName.rightKnee, 0.62, 0.75),
         (JointName.leftAnkle, 0.48, 0.96),   (JointName.rightAnkle, 0.62, 0.96)]
    )
}
