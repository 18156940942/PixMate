import Foundation
import CoreGraphics

// MARK: - 照片来源

enum AssetSource: String, Codable, CaseIterable {
    /// 联机拍摄：由相机拍下、经 PTP 回传到手机
    case tethered
    /// 手机模式：不联机时用本机镜头拍
    case phone
    /// 从相机存储卡批量读取的历史照片
    case imported

    var displayName: String {
        switch self {
        case .tethered: return "联机拍摄"
        case .phone:    return "手机模式"
        case .imported: return "相机导入"
        }
    }

    var symbolName: String {
        switch self {
        case .tethered: return "cable.connector"
        case .phone:    return "iphone"
        case .imported: return "square.and.arrow.down"
        }
    }
}

// MARK: - 拍摄项目

/// 一个拍摄项目 = 一次拍摄任务的全部照片。
/// 对应像素蛋糕的「项目」，是所有联机拍摄与修图操作的容器。
struct ShootProject: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var assets: [PhotoAsset] = []
    var activePresetID: UUID?

    var count: Int { assets.count }

    /// 封面取最新一张
    var coverAsset: PhotoAsset? { assets.last }

    var pickedCount: Int { assets.filter(\.isPicked).count }
}

// MARK: - 照片资产

struct PhotoAsset: Identifiable, Codable, Hashable {
    var id = UUID()

    /// 工作副本文件名（JPEG，用于秒开预览与实时修图）
    var workingFileName: String

    /// 原始文件文件名。联机拍摄时是相机回传的原图；
    /// 若相机同时存卡，这里可能是 NEF/RAW，用于最终高质量导出。
    var originalFileName: String?

    /// 是否为 RAW（NEF/CR3/ARW…），决定导出走不走 RAW 引擎
    var isRaw: Bool = false

    var capturedAt: Date = .now
    var pixelWidth: Int
    var pixelHeight: Int
    var fileSizeBytes: Int = 0

    var source: AssetSource = .tethered
    var cameraModel: String?

    /// 这张图的修图参数（每张独立可调，也可由预设批量套用）
    var retouch: RetouchParams = .neutral

    /// 标记（对应像素蛋糕的「标记」、LR 的 Pick 旗标）
    var isPicked: Bool = false

    /// 0–5 星
    var rating: Int = 0

    var exportedAt: Date?

    var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }

    var aspectRatio: CGFloat {
        guard pixelHeight > 0 else { return 1 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }

    var megapixels: Double {
        Double(pixelWidth * pixelHeight) / 1_000_000
    }

    var resolutionLabel: String {
        "\(pixelWidth) × \(pixelHeight)"
    }
}

// MARK: - 磁盘路径

enum PixMatePaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var root: URL {
        documents.appendingPathComponent("PixMate", isDirectory: true)
    }

    static var projectsRoot: URL {
        root.appendingPathComponent("Projects", isDirectory: true)
    }

    static var presetsFile: URL {
        root.appendingPathComponent("presets.json")
    }

    static var projectsIndexFile: URL {
        root.appendingPathComponent("projects.json")
    }

    static func projectDir(_ id: UUID) -> URL {
        projectsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func originalDir(_ id: UUID) -> URL {
        projectDir(id).appendingPathComponent("originals", isDirectory: true)
    }

    static func workingDir(_ id: UUID) -> URL {
        projectDir(id).appendingPathComponent("working", isDirectory: true)
    }

    static func exportDir(_ id: UUID) -> URL {
        projectDir(id).appendingPathComponent("export", isDirectory: true)
    }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func ensureProjectScaffold(_ id: UUID) {
        ensure(projectsRoot)
        ensure(projectDir(id))
        ensure(originalDir(id))
        ensure(workingDir(id))
        ensure(exportDir(id))
    }
}

// MARK: - 小工具

extension Double {
    /// 0…1 的安全钳制
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
    /// -1…1 的安全钳制
    var clampedSigned: Double { Swift.min(1, Swift.max(-1, self)) }
}

extension Date {
    var shortStamp: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: self)
    }

    var fileStamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: self)
    }
}
