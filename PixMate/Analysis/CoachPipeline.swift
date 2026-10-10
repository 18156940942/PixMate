import Foundation
import UIKit

// MARK: - 参谋流水线
//
// 取景帧进来 → 人体 / 人脸 / 构图 / 亮度全跑一遍 → 出报告和姿势建议。
// 相机控制器已经把帧率压到 8 fps，这里再做一次「上一帧没跑完就丢掉新帧」，
// 保证不会在低端机上雪崩。

@MainActor
final class CoachPipeline: ObservableObject {

    @Published private(set) var people: [DetectedPerson] = []
    @Published private(set) var faces: [FaceGeometry] = []
    @Published private(set) var report = CompositionReport()
    @Published private(set) var scene = SceneContext()
    @Published private(set) var librarySuggestions: [PoseSuggestion] = []
    @Published private(set) var generatedSuggestions: [PoseSuggestion] = []
    @Published private(set) var deviations: [String] = []
    @Published private(set) var matchScore: Double = 0
    @Published private(set) var isGenerating = false
    @Published private(set) var generationError: String?
    @Published private(set) var lastUpdated = Date.distantPast

    /// 当前选中的目标姿势（画骨架幽灵 + 算偏差）
    @Published var selectedPose: PoseSuggestion? {
        didSet { recomputeDeviations() }
    }

    /// 姿势分类筛选。nil = 智能模式（按画面自动选类，双人时混入互动姿势）
    @Published private(set) var poseCategory: PoseCategory?

    /// 切换分类：立刻换一批姿势，并保持有选中的目标
    func setPoseCategory(_ category: PoseCategory?) {
        guard category != poseCategory else { return }
        poseCategory = category
        refreshLibraryPoses()
    }

    private func refreshLibraryPoses() {
        tick += 1
        librarySuggestions = PoseSuggester.fromLibrary(people: people,
                                                       report: report,
                                                       scene: scene,
                                                       tick: tick,
                                                       category: poseCategory)
        if selectedPose == nil
            || !librarySuggestions.contains(where: { $0.id == selectedPose?.id }) {
            selectedPose = librarySuggestions.first
        }
        recomputeDeviations()
    }

    /// 多模态增强。没配就只用本地库，功能不降级。
    var provider: PoseVisionProvider?

    /// 生成结果缓存：场景没大变化就不重复请求
    private var lastGenerationStamp: Date = .distantPast
    private var lastGenerationKey: String = ""
    private var isProcessing = false
    private var tick = 0

    // MARK: 主入口

    func process(_ frame: UIImage) {
        guard !isProcessing else { return }
        isProcessing = true

        // Vision 跑在缩小图上：构图判断不需要 4000 万像素
        let probe = frame.scaled(toMaxDimension: 720)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let people = BodyPoseAnalyzer.detect(probe)
            let faces = FaceAnalyzer.analyze(probe)
            let report = CompositionAdvisor.evaluate(image: probe, people: people, faces: faces)
            let brightness = CompositionAdvisor.averageBrightness(probe) ?? 0.5

            await self.apply(people: people,
                             faces: faces,
                             report: report,
                             brightness: brightness)
        }
    }

    private func apply(people: [DetectedPerson],
                       faces: [FaceGeometry],
                       report: CompositionReport,
                       brightness: Double) {
        self.people = people
        self.faces = faces
        self.report = report

        let newScene = SceneContext(personCount: people.count,
                                    brightness: brightness,
                                    faceCount: faces.count,
                                    subjectCoverage: report.subjectCoverage)

        let personCountChanged = newScene.personCount != scene.personCount
        let framingChanged = newScene.framingHint != scene.framingHint
        self.scene = newScene

        // 人数或画幅变了才换一批姿势，否则画面会一直跳
        if personCountChanged || framingChanged || librarySuggestions.isEmpty {
            tick += 1
            librarySuggestions = PoseSuggester.fromLibrary(people: people,
                                                           report: report,
                                                           scene: newScene,
                                                           tick: tick,
                                                           category: poseCategory)
            // 当前选中的姿势如果已被换掉，重新选第一条
            if selectedPose == nil
                || !librarySuggestions.contains(where: { $0.id == selectedPose?.id }) {
                selectedPose = librarySuggestions.first
            }
        }

        recomputeDeviations()
        lastUpdated = Date()
        isProcessing = false
    }

    // MARK: 偏差

    private func recomputeDeviations() {
        guard let pose = selectedPose,
              let subject = people.max(by: { $0.boundingBox.height < $1.boundingBox.height }),
              !pose.normalizedJoints.isEmpty else {
            deviations = []
            matchScore = 0
            return
        }

        let current = PoseSuggester.toBoxSpace(joints: subject.joints, box: subject.boundingBox)
        deviations = PoseSuggester.deviations(current: current, target: pose.normalizedJoints)
        matchScore = PoseSuggester.matchScore(current: current, target: pose.normalizedJoints)
    }

    // MARK: 多模态生成

    /// 按眼前景色现场生成姿势。同一场景 12 秒内不重复请求。
    func generateScenePoses() async {
        guard let provider, provider.isConfigured else {
            generationError = PoseGenerationError.notConfigured.errorDescription
            return
        }
        guard !isGenerating else { return }

        let key = "\(scene.framingHint)-\(scene.lightHint)-\(scene.personCount)"
        if key == lastGenerationKey, Date().timeIntervalSince(lastGenerationStamp) < 12 { return }

        isGenerating = true
        generationError = nil

        // 用最近一帧做输入
        guard let frame = latestFrame else {
            isGenerating = false
            generationError = "还没有取景画面"
            return
        }

        do {
            let poses = try await provider.generatePoses(frame: frame, scene: scene, count: 3)
            generatedSuggestions = poses
            lastGenerationKey = key
            lastGenerationStamp = Date()
        } catch {
            generationError = error.localizedDescription
        }

        isGenerating = false
    }

    /// 由外部（相机控制器）在每帧写入，供多模态调用取用
    var latestFrame: UIImage?

    // MARK: 清理

    func reset() {
        people = []
        faces = []
        report = CompositionReport()
        librarySuggestions = []
        generatedSuggestions = []
        deviations = []
        matchScore = 0
        generationError = nil
        selectedPose = nil
        lastGenerationKey = ""
        latestFrame = nil
    }

    // MARK: 汇总

    var allSuggestions: [PoseSuggestion] {
        generatedSuggestions.isEmpty ? librarySuggestions : generatedSuggestions + librarySuggestions
    }

    var primaryAdvice: CompositionIssue? {
        report.topIssues.first
    }
}
