import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Photos

// MARK: - 导出设置

enum ExportFormat: String, CaseIterable, Codable {
    case jpeg
    case heic
    case png
    case tiff

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .png:  return "PNG"
        case .tiff: return "TIFF"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .png:  return "png"
        case .tiff: return "tif"
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .png:  return .png
        case .tiff: return .tiff
        }
    }

    /// 是否支持有损压缩质量参数
    var isLossy: Bool {
        self == .jpeg || self == .heic
    }
}

enum ExportColorSpace: String, CaseIterable, Codable {
    case displayP3
    case sRGB
    case adobeRGB
    case proPhoto

    var displayName: String {
        switch self {
        case .displayP3: return "Display P3"
        case .sRGB:      return "sRGB"
        case .adobeRGB:  return "Adobe RGB"
        case .proPhoto:  return "ProPhoto RGB"
        }
    }

    var cgColorSpace: CGColorSpace {
        let name: CFString
        switch self {
        case .displayP3: name = CGColorSpace.displayP3
        case .sRGB:      name = CGColorSpace.sRGB
        case .adobeRGB:  name = CGColorSpace.adobeRGB1998
        case .proPhoto:  name = CGColorSpace.extendedLinearSRGB
        }
        return CGColorSpace(name: name) ?? CGColorSpaceCreateDeviceRGB()
    }
}

struct ExportSettings: Codable, Equatable {
    var format: ExportFormat = .jpeg
    /// 默认 0.98 —— 二次压缩几乎不可见
    var quality: Double = 0.98
    var colorSpace: ExportColorSpace = .displayP3
    /// nil = 保持原始尺寸，绝不降采样
    var resizeLongEdge: Int? = nil
    /// 是否把相机原图（RAW）一并复制到导出目录
    var includeOriginalCopy: Bool = true
    var saveToPhotoLibrary: Bool = false
    var filenamePrefix: String = "PixMate"
    /// RAW 出片是否走真显影（CIRAWFilter 全传感器分辨率），
    /// 失败自动退回嵌入预览。老设备嫌慢可以关掉。
    var useRawDevelopment: Bool = true

    var resizeLabel: String {
        guard let edge = resizeLongEdge else { return "原始尺寸（不降采样）" }
        return "长边 \(edge) px"
    }

    // MARK: Codable —— 新字段用 decodeIfPresent，旧存档不会解码失败

    enum CodingKeys: String, CodingKey {
        case format, quality, colorSpace, resizeLongEdge
        case includeOriginalCopy, saveToPhotoLibrary, filenamePrefix
        case useRawDevelopment
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(ExportFormat.self, forKey: .format) ?? .jpeg
        quality = try c.decodeIfPresent(Double.self, forKey: .quality) ?? 0.98
        colorSpace = try c.decodeIfPresent(ExportColorSpace.self, forKey: .colorSpace) ?? .displayP3
        resizeLongEdge = try c.decodeIfPresent(Int.self, forKey: .resizeLongEdge)
        includeOriginalCopy = try c.decodeIfPresent(Bool.self, forKey: .includeOriginalCopy) ?? true
        saveToPhotoLibrary = try c.decodeIfPresent(Bool.self, forKey: .saveToPhotoLibrary) ?? false
        filenamePrefix = try c.decodeIfPresent(String.self, forKey: .filenamePrefix) ?? "PixMate"
        useRawDevelopment = try c.decodeIfPresent(Bool.self, forKey: .useRawDevelopment) ?? true
    }
}

// MARK: - 导出服务

@MainActor
final class ExportService: ObservableObject {

    @Published private(set) var isExporting = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastMessage: String?

    /// 导出并返回落盘的文件路径
    func export(assets: [PhotoAsset],
                project: ShootProject,
                settings: ExportSettings,
                engine: RetouchEngine,
                store: ProjectStore) async -> [URL] {

        guard !assets.isEmpty, !isExporting else { return [] }

        isExporting = true
        progress = 0
        lastMessage = nil

        let directory = PixMatePaths.ensure(PixMatePaths.exportDir(project.id))
        let colorSpace = settings.colorSpace.cgColorSpace
        var written: [URL] = []

        for (index, asset) in assets.enumerated() {
            // 1. 取源图：优先原图（RAW 真显影拿全量数据），否则工作副本
            guard let source = loadSource(for: asset, project: project, store: store,
                                          engine: engine, settings: settings) else {
                lastMessage = "跳过 \(asset.workingFileName)：源文件读不到"
                progress = Double(index + 1) / Double(assets.count)
                continue
            }

            // 2. 全分辨率跑一遍修图（不是拿预览图凑数）
            var params = asset.retouch
            let analysis = engine.analyze(source, detectPerson: params.needsSubjectMask || params.needsFaceAnalysis)
            let ci = engine.renderCIImage(analysis, params: params)

            // 3. 需要缩放才缩放；默认原样
            var finalImage = ci
            if let longEdge = settings.resizeLongEdge, longEdge > 0 {
                let current = max(ci.extent.width, ci.extent.height)
                if current > CGFloat(longEdge) {
                    let scale = CGFloat(longEdge) / current
                    finalImage = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                }
            }

            let extent = finalImage.extent
            guard let cgImage = engine.context.createCGImage(finalImage,
                                                             from: extent,
                                                             format: .RGBA8,
                                                             colorSpace: colorSpace) else {
                lastMessage = "跳过 \(asset.workingFileName)：渲染失败"
                progress = Double(index + 1) / Double(assets.count)
                continue
            }

            // 4. 写文件
            let name = fileName(prefix: settings.filenamePrefix,
                                project: project.name,
                                index: index + 1,
                                asset: asset,
                                settings: settings)
            let url = directory.appendingPathComponent(name)

            if encode(cgImage, format: settings.format, quality: settings.quality, to: url) {
                written.append(url)
            } else {
                lastMessage = "写入失败：\(name)"
            }

            // 5. 原图另存一份，方便日后返修
            if settings.includeOriginalCopy, let original = store.originalURL(for: asset, in: project.id) {
                let copyName = "\(settings.filenamePrefix)_原始_\(asset.capturedAt.fileStamp).\(original.pathExtension)"
                let copyURL = directory.appendingPathComponent(copyName)
                if !FileManager.default.fileExists(atPath: copyURL.path) {
                    try? FileManager.default.copyItem(at: original, to: copyURL)
                }
            }

            progress = Double(index + 1) / Double(assets.count)
            // 让 UI 有机会刷新进度
            await Task.yield()
        }

        if settings.saveToPhotoLibrary, !written.isEmpty {
            await saveToLibrary(written)
        }

        lastMessage = "已导出 \(written.count) 张到 \(settings.format.displayName) · \(settings.colorSpace.displayName)"
        isExporting = false
        return written
    }

    // MARK: 源图

    private func loadSource(for asset: PhotoAsset,
                            project: ShootProject,
                            store: ProjectStore,
                            engine: RetouchEngine,
                            settings: ExportSettings) -> UIImage? {
        // 原图优先。RAW 走真显影（全传感器分辨率），失败退回嵌入预览
        if let originalURL = store.originalURL(for: asset, in: project.id),
           FileManager.default.fileExists(atPath: originalURL.path) {
            if asset.isRaw {
                if settings.useRawDevelopment {
                    if let developed = RawDeveloper.developUIImage(from: originalURL,
                                                                   context: engine.context) {
                        return developed
                    }
                }
                if let preview = RawPreviewExtractor.preview(from: originalURL) { return preview }
            } else if let image = UIImage(contentsOfFile: originalURL.path) {
                return image
            }
        }
        // 退回工作副本
        let workingURL = store.workingURL(for: asset, in: project.id)
        return UIImage(contentsOfFile: workingURL.path)
    }

    // MARK: 编码

    private func encode(_ image: CGImage,
                        format: ExportFormat,
                        quality: Double,
                        to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                format.utType.identifier as CFString,
                                                                1,
                                                                nil) else {
            return false
        }

        var options: [CFString: Any] = [:]
        if format.isLossy {
            options[kCGImageDestinationLossyCompressionQuality] = max(0.0, min(1.0, quality))
        }
        // 缩略图内嵌，方便在图库和访达里秒加载
        options[kCGImageDestinationEmbedThumbnail] = true

        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    // MARK: 文件名

    private func fileName(prefix: String,
                          project: String,
                          index: Int,
                          asset: PhotoAsset,
                          settings: ExportSettings) -> String {
        let safeProject = project.replacingOccurrences(of: " ", with: "-")
        let stamp = asset.capturedAt.fileStamp
        return "\(prefix)_\(safeProject)_\(String(format: "%03d", index))_\(stamp).\(settings.format.fileExtension)"
    }

    // MARK: 相册

    private func saveToLibrary(_ urls: [URL]) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            lastMessage = "没有相册写入权限，文件已存在 App 的导出目录里"
            return
        }
        for url in urls {
            try? await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, fileURL: url, options: nil)
            }
        }
    }
}
