import Foundation
import UIKit

// MARK: - 姿势建议器

enum PoseSuggester {

    /// 本地姿势库的路子：零延迟、离线、随时可用。
    /// `category` 为 nil 时走智能模式（含双人互动混排）。
    static func fromLibrary(people: [DetectedPerson],
                            report: CompositionReport,
                            scene: SceneContext,
                            tick: Int,
                            category: PoseCategory? = nil) -> [PoseSuggestion] {
        PoseLibrary.pick(framing: scene.framingHint,
                         light: scene.lightHint,
                         personCount: scene.personCount,
                         seed: tick,
                         category: category,
                         limit: 4)
    }

    /// 把检测到的骨架换算到「人体框」坐标系，
    /// 和姿势库里那套坐标对齐，才能做逐关节比对。
    static func toBoxSpace(joints: [String: SkeletonJoint], box: CGRect) -> [String: CGPoint] {
        guard box.width > 0.001, box.height > 0.001 else { return [:] }
        var result: [String: CGPoint] = [:]
        for (name, joint) in joints where joint.isReliable {
            result[name] = CGPoint(x: (joint.point.x - box.minX) / box.width,
                                   y: (joint.point.y - box.minY) / box.height)
        }
        return result
    }

    /// 当前姿态与目标姿势的差距 → 能直接喊给模特听的话。
    /// 这是「姿势引导」真正有用的部分：不是给张图让她自己猜。
    static func deviations(current: [String: CGPoint],
                           target: [String: CGPoint]) -> [String] {
        guard !current.isEmpty, !target.isEmpty else { return [] }

        let joints: [(String, String, String)] = [
            (JointName.leftWrist,  "左手", "抬高"),
            (JointName.rightWrist, "右手", "抬高"),
            (JointName.leftElbow,  "左肘", "往外打开"),
            (JointName.rightElbow, "右肘", "往外打开"),
            (JointName.nose,       "头部", "摆正"),
            (JointName.leftKnee,   "左膝", "调整"),
            (JointName.rightKnee,  "右膝", "调整")
        ]

        var hints: [String] = []
        let threshold: CGFloat = 0.14

        for (key, label, verb) in joints {
            guard let c = current[key], let t = target[key] else { continue }
            let dx = t.x - c.x
            let dy = t.y - c.y
            let distance = hypot(dx, dy)
            guard distance > threshold else { continue }

            // 竖直方向变化更显著时，说「抬高/放低」；否则说水平方向
            if abs(dy) > abs(dx) {
                let level = Int(min(9, max(2, abs(dy) * 20)))
                hints.append("\(label)再\(dy < 0 ? "往上" : "往下")\(level)分")
            } else {
                let side = dx > 0 ? "往画面右" : "往画面左"
                hints.append("\(label)\(verb)，\(side)一点")
            }

            if hints.count >= 3 { break }
        }

        return hints
    }

    /// 综合匹配度 0…1，用来画「你已经很接近了」的提示
    static func matchScore(current: [String: CGPoint], target: [String: CGPoint]) -> Double {
        guard !current.isEmpty, !target.isEmpty else { return 0 }
        var total: Double = 0
        var count = 0
        for (key, t) in target {
            guard let c = current[key] else { continue }
            let distance = hypot(t.x - c.x, t.y - c.y)
            total += max(0, 1 - Double(distance) / 0.6)
            count += 1
        }
        guard count > 0 else { return 0 }
        return min(1, max(0, total / Double(count)))
    }
}

// MARK: - 姿势原型
//
// 多模态模型不擅长吐骨架坐标（吐出来的多半是瞎编的），
// 但非常擅长「看图说人话」。
// 所以分工：模型负责**选原型 + 写贴合眼前景色的文案**，
// 骨架由本地库提供，既准确又稳定。

enum PoseArchetype: String, CaseIterable {
    case standing
    case threeQuarter
    case handInPocket
    case legsCrossed
    case handsBehindBack
    case sideProfile
    case jacketPull
    case handShading
    case stretch
    case seated
    case crossLeggedSit
    case floorSit
    case hugKnees
    case chairSideSit
    case leaning
    case railingLean
    case tableLean
    case wallSquat
    case walking
    case dressSpin
    case hairFlip
    case bigStride
    case jump
    case armsCrossed
    case handOnHip
    case handInHair
    case lookBack
    case headTilt
    case chinRest
    case handOnShoulder
    case handFramingFace
    case eyesClosed
    case backToBack
    case handInHand
    case shoulderLean

    var skeleton: PoseSuggestion? {
        switch self {
        case .standing:         return PoseLibrary.standingNeutral
        case .threeQuarter:     return PoseLibrary.threeQuarterTurn
        case .handInPocket:     return PoseLibrary.handInPocket
        case .legsCrossed:      return PoseLibrary.legsCrossedStand
        case .handsBehindBack:  return PoseLibrary.handsBehindBack
        case .sideProfile:      return PoseLibrary.sideProfileStand
        case .jacketPull:       return PoseLibrary.jacketPull
        case .handShading:      return PoseLibrary.handShading
        case .stretch:          return PoseLibrary.fullBodyStretch
        case .seated:           return PoseLibrary.seatedLean
        case .crossLeggedSit:   return PoseLibrary.crossLeggedSit
        case .floorSit:         return PoseLibrary.floorCrossSit
        case .hugKnees:         return PoseLibrary.hugKnees
        case .chairSideSit:     return PoseLibrary.chairSideSit
        case .leaning:          return PoseLibrary.leaningWall
        case .railingLean:      return PoseLibrary.railingLean
        case .tableLean:        return PoseLibrary.tableLean
        case .wallSquat:        return PoseLibrary.wallSquat
        case .walking:          return PoseLibrary.walking
        case .dressSpin:        return PoseLibrary.dressSpin
        case .hairFlip:         return PoseLibrary.hairFlip
        case .bigStride:        return PoseLibrary.bigStride
        case .jump:             return PoseLibrary.lightJump
        case .armsCrossed:      return PoseLibrary.armsCrossed
        case .handOnHip:        return PoseLibrary.handOnHip
        case .handInHair:       return PoseLibrary.handInHair
        case .lookBack:         return PoseLibrary.lookBack
        case .headTilt:         return PoseLibrary.headTilt
        case .chinRest:         return PoseLibrary.chinRest
        case .handOnShoulder:   return PoseLibrary.handOnShoulder
        case .handFramingFace:  return PoseLibrary.handFramingFace
        case .eyesClosed:       return PoseLibrary.eyesClosed
        case .backToBack:       return PoseLibrary.backToBack
        case .handInHand:       return PoseLibrary.handInHand
        case .shoulderLean:     return PoseLibrary.shoulderLean
        }
    }

    static func from(_ raw: String) -> PoseArchetype? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let direct = PoseArchetype(rawValue: key) { return direct }
        // 容忍模型写成 three_quarter / armcrossed 之类
        let compact = key.replacingOccurrences(of: "_", with: "")
        return allCases.first { $0.rawValue.lowercased() == compact }
    }
}

// MARK: - 多模态姿势生成（可选增强）

/// 把当前取景帧发给视觉模型，让它**照着画面里实际的景色**
/// 给出贴合的姿势建议和提示语。
protocol PoseVisionProvider: AnyObject {
    var isConfigured: Bool { get }
    func generatePoses(frame: UIImage, scene: SceneContext, count: Int) async throws -> [PoseSuggestion]
}

/// 兼容 OpenAI Chat Completions 协议的实现。
/// 任何提供该协议的网关（自建、Azure、各家兼容端点）都能直接用。
final class OpenAICompatiblePoseProvider: PoseVisionProvider {

    var endpoint: URL
    var apiKey: String
    var model: String

    init(endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
         apiKey: String = "",
         model: String = "gpt-4o-mini") {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
    }

    var isConfigured: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    func generatePoses(frame: UIImage,
                       scene: SceneContext,
                       count: Int) async throws -> [PoseSuggestion] {

        guard isConfigured else { throw PoseGenerationError.notConfigured }
        guard let jpeg = frame.scaled(toMaxDimension: 768).jpegData(compressionQuality: 0.7) else {
            throw PoseGenerationError.badImage
        }

        let archetypes = PoseArchetype.allCases.map(\.rawValue).joined(separator: ", ")
        let prompt = """
        你在给一位人像摄影师做现场参谋。图片是相机取景器的实时画面。
        请根据画面里**实际可见的背景、光线方向、空间大小、人物当前姿态**，
        给出 \(count) 条适合当前场景的摆姿建议。

        每条建议必须包含：
        - title：4–8 个字的姿势名
        - hint：一句话，直接说给模特听（口吻自然，不要术语）
        - scene_note：说明为什么这条适合眼前的画面（提到具体看到的元素，如背景、光线、空间）
        - framing：全身 / 半身 / 特写 三者之一
        - base：从下面这个固定列表里选最接近的一个原型
          [\(archetypes)]

        只输出 JSON，不要任何解释文字，格式：
        {"poses":[{"title":"","hint":"","scene_note":"","framing":"","base":""}]}
        """

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 40

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.8,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url",
                         "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw PoseGenerationError.server(text.isEmpty ? "服务端返回异常" : text)
        }

        let content = try extractContent(from: data)
        return try parse(content)
    }

    // MARK: 解析

    private func extractContent(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PoseGenerationError.badResponse
        }
        return content
    }

    private func parse(_ content: String) throws -> [PoseSuggestion] {
        // 模型偶尔会包一层 ```json，先剥掉
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            throw PoseGenerationError.badResponse
        }
        let json = String(cleaned[start...end])

        guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let items = root["poses"] as? [[String: Any]] else {
            throw PoseGenerationError.badResponse
        }

        return items.compactMap { item in
            guard let title = item["title"] as? String,
                  let hint = item["hint"] as? String else { return nil }

            let base = PoseArchetype.from(item["base"] as? String ?? "") ?? .standing
            let skeleton = base.skeleton

            return PoseSuggestion(
                title: title,
                hint: hint,
                tags: [scene.framingHint, scene.lightHint],
                source: .generated,
                normalizedJoints: skeleton?.normalizedJoints ?? [:],
                sceneNote: item["scene_note"] as? String,
                framing: item["framing"] as? String ?? scene.framingHint,
                category: skeleton?.category ?? .standing
            )
        }
    }
}

enum PoseGenerationError: LocalizedError {
    case notConfigured
    case badImage
    case badResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "还没有配置视觉模型的接口地址和密钥"
        case .badImage:      return "取景画面无法编码"
        case .badResponse:   return "模型返回的内容无法解析"
        case .server(let m): return "模型服务出错：\(m)"
        }
    }
}
