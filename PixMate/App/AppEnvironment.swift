import Foundation
import SwiftUI
import Combine

// MARK: - 全局环境
//
// 所有服务在这里装配一次，视图通过 EnvironmentObject 取用。

@MainActor
final class AppEnvironment: ObservableObject {

    let camera = CameraController()
    let coach = CoachPipeline()
    let projects = ProjectStore()
    let presets = PresetStore()
    let retouch = RetouchEngine()
    let exporter = ExportService()

    // 界面状态
    @Published var activeProjectID: UUID?
    @Published var overlay = OverlayOptions()
    @Published var exportSettings = ExportSettings()
    @Published var toast: String?
    @Published var lastCaptured: PhotoAsset?

    // 多模态设置
    @Published var visionEndpoint: String = "https://api.openai.com/v1/chat/completions"
    @Published var visionAPIKey: String = ""
    @Published var visionModel: String = "gpt-4o-mini"

    private var cancellables = Set<AnyCancellable>()

    init() {
        loadPreferences()
        wireCamera()
        forwardChildChanges()
        applyVisionSettings()
    }

    // MARK: 装配

    private func wireCamera() {
        // 取景帧 → 参谋层
        camera.frameSink = { [weak self] image in
            guard let self else { return }
            self.coach.latestFrame = image
            self.coach.process(image)
        }
    }

    /// 把子对象的变化转发出来，
    /// 这样视图只订阅环境对象一处就能拿到相机、参谋、项目的全部更新。
    private func forwardChildChanges() {
        let publishers: [AnyPublisher<Void, Never>] = [
            camera.objectWillChange.eraseToAnyPublisher(),
            coach.objectWillChange.eraseToAnyPublisher(),
            projects.objectWillChange.eraseToAnyPublisher(),
            presets.objectWillChange.eraseToAnyPublisher(),
            exporter.objectWillChange.eraseToAnyPublisher()
        ]
        for publisher in publishers {
            publisher
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    /// 切换当前项目：同时也决定了照片回传到哪个目录
    func activate(_ projectID: UUID?) {
        activeProjectID = projectID
        coach.reset()

        camera.configure(projectID: projectID) { [weak self] asset in
            guard let self, let pid = self.activeProjectID else { return }
            self.projects.addAsset(asset, to: pid)
            self.lastCaptured = asset
            self.toast = "已回传 1 张 · \(asset.resolutionLabel)"
        }
    }

    /// 当前项目里最近一张照片，进入精修页默认展示它
    var activeProject: ShootProject? {
        guard let id = activeProjectID else { return nil }
        return projects.project(id)
    }

    // MARK: 手机模式

    func startPhoneMode() {
        guard activeProjectID != nil else {
            flash("先建一个项目，手机拍的照片才有地方放")
            return
        }
        camera.startPhoneMode()
    }

    func stopPhoneMode() {
        camera.stopPhoneMode()
    }

    // MARK: 预设

    func applyPreset(_ preset: RetouchPreset, to asset: PhotoAsset) {
        guard let pid = activeProjectID else { return }
        var updated = asset
        updated.retouch = preset.params
        projects.updateAsset(updated, in: pid)
    }

    func applyPresetToProject(_ preset: RetouchPreset) {
        guard let pid = activeProjectID, let project = projects.project(pid) else { return }
        for asset in project.assets {
            var updated = asset
            updated.retouch = preset.params
            projects.updateAsset(updated, in: pid)
        }
        projects.setPreset(preset.id, for: pid)
        toast = "已把「\(preset.name)」套用到 \(project.count) 张"
    }

    // MARK: 多模态

    func applyVisionSettings() {
        let key = visionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            coach.provider = nil
            return
        }
        let url = URL(string: visionEndpoint.trimmingCharacters(in: .whitespaces)) 
            ?? URL(string: "https://api.openai.com/v1/chat/completions")!
        coach.provider = OpenAICompatiblePoseProvider(endpoint: url, apiKey: key, model: visionModel)
        savePreferences()
    }

    var isVisionConfigured: Bool {
        !visionAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: 偏好持久化

    private let preferencesKey = "PixMate.Preferences"

    private struct Preferences: Codable {
        var exportSettings: ExportSettings
        var overlay: OverlayOptions
        var visionEndpoint: String
        var visionAPIKey: String
        var visionModel: String
    }

    private func savePreferences() {
        let prefs = Preferences(exportSettings: exportSettings,
                                overlay: overlay,
                                visionEndpoint: visionEndpoint,
                                visionAPIKey: visionAPIKey,
                                visionModel: visionModel)
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        UserDefaults.standard.set(data, forKey: preferencesKey)
    }

    private func loadPreferences() {
        guard let data = UserDefaults.standard.data(forKey: preferencesKey),
              let prefs = try? JSONDecoder().decode(Preferences.self, from: data) else { return }
        exportSettings = prefs.exportSettings
        overlay = prefs.overlay
        visionEndpoint = prefs.visionEndpoint
        visionAPIKey = prefs.visionAPIKey
        visionModel = prefs.visionModel
    }

    func persist() { savePreferences() }

    // MARK: 提示条

    func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if self.toast == message { self.toast = nil }
        }
    }
}
