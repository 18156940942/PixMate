import Foundation

// MARK: - 项目库

/// 项目与照片的持久化。自用工具，数据量可控，
/// 所以索引走单个 JSON，图片本体走磁盘目录。
@MainActor
final class ProjectStore: ObservableObject {

    @Published private(set) var projects: [ShootProject] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        load()
    }

    // MARK: 读写

    func load() {
        PixMatePaths.ensure(PixMatePaths.root)
        guard let data = try? Data(contentsOf: PixMatePaths.projectsIndexFile),
              let list = try? decoder.decode([ShootProject].self, from: data) else {
            projects = []
            return
        }
        projects = list.sorted { $0.createdAt > $1.createdAt }
    }

    func save() {
        PixMatePaths.ensure(PixMatePaths.root)
        guard let data = try? encoder.encode(projects) else { return }
        try? data.write(to: PixMatePaths.projectsIndexFile, options: .atomic)
    }

    // MARK: 项目

    @discardableResult
    func createProject(name: String) -> ShootProject {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = ShootProject(name: trimmed.isEmpty ? "未命名项目" : trimmed)
        PixMatePaths.ensureProjectScaffold(project.id)
        projects.insert(project, at: 0)
        save()
        return project
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].name = name
        projects[i].updatedAt = .now
        save()
    }

    func delete(_ id: UUID) {
        projects.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: PixMatePaths.projectDir(id))
        save()
    }

    func project(_ id: UUID) -> ShootProject? {
        projects.first { $0.id == id }
    }

    func index(of id: UUID) -> Int? {
        projects.firstIndex { $0.id == id }
    }

    // MARK: 照片

    func addAsset(_ asset: PhotoAsset, to projectID: UUID) {
        guard let i = index(of: projectID) else { return }
        projects[i].assets.append(asset)
        projects[i].updatedAt = .now
        save()
    }

    func updateAsset(_ asset: PhotoAsset, in projectID: UUID) {
        guard let pi = index(of: projectID),
              let ai = projects[pi].assets.firstIndex(where: { $0.id == asset.id }) else { return }
        projects[pi].assets[ai] = asset
        projects[pi].updatedAt = .now
        save()
    }

    func removeAsset(_ assetID: UUID, from projectID: UUID) {
        guard let pi = index(of: projectID) else { return }
        guard let ai = projects[pi].assets.firstIndex(where: { $0.id == assetID }) else { return }
        let asset = projects[pi].assets.remove(at: ai)
        try? FileManager.default.removeItem(at: PixMatePaths.workingDir(projectID).appendingPathComponent(asset.workingFileName))
        if let original = asset.originalFileName {
            try? FileManager.default.removeItem(at: PixMatePaths.originalDir(projectID).appendingPathComponent(original))
        }
        projects[pi].updatedAt = .now
        save()
    }

    func setPreset(_ presetID: UUID?, for projectID: UUID) {
        guard let i = index(of: projectID) else { return }
        projects[i].activePresetID = presetID
        save()
    }

    // MARK: 路径解析

    func workingURL(for asset: PhotoAsset, in projectID: UUID) -> URL {
        PixMatePaths.workingDir(projectID).appendingPathComponent(asset.workingFileName)
    }

    func originalURL(for asset: PhotoAsset, in projectID: UUID) -> URL? {
        guard let name = asset.originalFileName else { return nil }
        return PixMatePaths.originalDir(projectID).appendingPathComponent(name)
    }
}

// MARK: - 预设库

@MainActor
final class PresetStore: ObservableObject {

    @Published private(set) var presets: [RetouchPreset] = RetouchPreset.builtIns

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        load()
    }

    func load() {
        PixMatePaths.ensure(PixMatePaths.root)
        guard let data = try? Data(contentsOf: PixMatePaths.presetsFile),
              let list = try? decoder.decode([RetouchPreset].self, from: data) else {
            presets = RetouchPreset.builtIns
            return
        }
        // 内置预设始终以代码为准，用户预设从磁盘恢复
        let user = list.filter { !$0.isBuiltIn }
        presets = RetouchPreset.builtIns + user
    }

    func save() {
        PixMatePaths.ensure(PixMatePaths.root)
        let user = presets.filter { !$0.isBuiltIn }
        guard let data = try? encoder.encode(user) else { return }
        try? data.write(to: PixMatePaths.presetsFile, options: .atomic)
    }

    @discardableResult
    func addUserPreset(name: String, params: RetouchParams) -> RetouchPreset {
        let preset = RetouchPreset(name: name, isBuiltIn: false, params: params)
        presets.append(preset)
        save()
        return preset
    }

    func delete(_ id: UUID) {
        presets.removeAll { $0.id == id && !$0.isBuiltIn }
        save()
    }

    func preset(_ id: UUID) -> RetouchPreset? {
        presets.first { $0.id == id }
    }

    var userPresets: [RetouchPreset] { presets.filter { !$0.isBuiltIn } }
    var builtInPresets: [RetouchPreset] { presets.filter(\.isBuiltIn) }
}
