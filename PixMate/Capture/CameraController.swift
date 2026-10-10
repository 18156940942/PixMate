import Foundation
import UIKit
import Combine
import ImageCaptureCore

// MARK: - 联机总调度
//
// 把 PTP 会话包装成 App 能直接用的东西：
//   · 一个持续跑的实时取景循环
//   · 一次拍摄 → 等相机上报新文件 → 拉回本地 → 建资产
//   · 参数读写
// 并把每一帧顺手丢给分析层（构图 / 姿势参谋）。

@MainActor
final class CameraController: ObservableObject {

    // 对外状态
    @Published private(set) var link: CameraLink = .disconnected
    @Published private(set) var frame: UIImage?
    @Published private(set) var frameSize: CGSize = CGSize(width: LiveViewDefaults.assumedWidth,
                                                          height: LiveViewDefaults.assumedHeight)
    @Published private(set) var properties: [CameraProperty] = []
    @Published private(set) var liveViewFPS: Double = 0
    @Published private(set) var isReleasing = false
    @Published private(set) var isDownloading = false
    @Published private(set) var lastError: String?
    /// 最近一次成功回传的原图路径，UI 上用来闪一下确认
    @Published private(set) var lastIngestedAt: Date?

    let session = NikonPTPSession()
    let phone = PhoneCaptureSource()

    /// 每帧回调（已节流到分析帧率），供构图 / 姿势参谋消费
    var frameSink: ((UIImage) -> Void)?

    // 内部
    private var liveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var activeProjectID: UUID?
    private var ingestHandler: ((PhotoAsset) -> Void)?
    private let analysisThrottle = FrameThrottle(fps: 8)

    /// 用于标定「卡里已有的老照片」和「本次刚拍的」
    private var captureRequestedAt: Date?

    init() {
        bindSession()
    }

    // MARK: 绑定会话状态

    private func bindSession() {
        session.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self else { return }
                switch phase {
                case .idle:
                    self.link = .disconnected
                case .searching:
                    self.link = .connecting("正在搜索相机…")
                case .opening(let model):
                    self.link = .connecting("正在与 \(model) 建立 PTP 会话…")
                case .ready(let model):
                    self.link = .wired(model: model)
                    Task { await self.refreshProperties() }
                case .failed(let message):
                    self.link = .failed(message)
                }
            }
            .store(in: &cancellables)

        session.onNewFile = { [weak self] file in
            self?.handleNewFile(file)
        }

        session.onDeviceRemoved = { [weak self] in
            guard let self else { return }
            self.stopLiveView()
            self.link = .disconnected
        }
    }

    /// 告诉调度器：回传的照片放进哪个项目、通过什么回调交回上层
    func configure(projectID: UUID?, onIngest: @escaping (PhotoAsset) -> Void) {
        activeProjectID = projectID
        ingestHandler = onIngest
    }

    // MARK: 连接

    func connectWired() {
        lastError = nil
        session.startSearching()
    }

    func disconnect() {
        stopLiveView()
        phone.stop()
        session.shutDown()
        link = .disconnected
        frame = nil
    }

    // MARK: 手机模式

    /// 不联机时，把本机镜头当取景源。帧走和相机完全相同的那条显示通道，
    /// 所以参谋层、叠加层、精修全都照常工作。
    func startPhoneMode() {
        phone.frameSink = { [weak self] image in
            self?.pushPhoneFrame(image)
        }
        phone.onPhoto = { [weak self] image in
            self?.ingestPhonePhoto(image)
        }
        link = .phone
        Task { await phone.start() }
    }

    func stopPhoneMode() {
        phone.stop()
        if link == .phone { link = .disconnected }
        frame = nil
    }

    private func pushPhoneFrame(_ image: UIImage) {
        frame = image
        frameSize = image.size
        frameSink?(image)
    }

    private func ingestPhonePhoto(_ image: UIImage) {
        guard let projectID = activeProjectID else {
            lastError = "还没有选择项目，手机拍的照片没地方放"
            return
        }
        guard let data = image.jpegData(compressionQuality: 0.95) else { return }

        let stamp = Date().fileStamp
        let workingName = "\(stamp)_phone_w.jpg"
        let originalName = "\(stamp)_phone.jpg"

        let workingURL = PixMatePaths.ensure(PixMatePaths.workingDir(projectID))
            .appendingPathComponent(workingName)
        let originalURL = PixMatePaths.ensure(PixMatePaths.originalDir(projectID))
            .appendingPathComponent(originalName)

        try? data.write(to: workingURL, options: .atomic)
        try? data.write(to: originalURL, options: .atomic)

        var asset = PhotoAsset(
            workingFileName: workingName,
            originalFileName: originalName,
            isRaw: false,
            pixelWidth: Int(image.size.width * image.scale),
            pixelHeight: Int(image.size.height * image.scale),
            fileSizeBytes: data.count,
            source: .phone,
            cameraModel: "本机镜头"
        )
        asset.capturedAt = Date()

        lastIngestedAt = Date()
        ingestHandler?(asset)
    }

    // MARK: 实时取景

    func startLiveView() {
        guard link.isTethering else {
            lastError = "还没有连上相机"
            return
        }
        guard liveTask == nil else { return }

        liveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.session.startLiveView()
            } catch {
                self.lastError = "开启实时取景失败：\(error.localizedDescription)"
                self.session.log("StartLiveView 失败：\(error.localizedDescription)")
                self.liveTask = nil
                return
            }
            await self.runLiveViewLoop()
        }
    }

    func stopLiveView() {
        liveTask?.cancel()
        liveTask = nil
        liveViewFPS = 0
        analysisThrottle.reset()
        Task { await session.stopLiveView() }
    }

    /// 实时取景循环。
    /// 每次取帧都是一次 USB 往返，所以节奏由相机决定：
    /// 相机给得快就按目标帧率节流，给得慢就不额外等。
    private func runLiveViewLoop() async {
        let targetInterval: TimeInterval = 1.0 / 20.0
        var framesInWindow = 0
        var windowStart = Date()

        while !Task.isCancelled, session.isLiveViewRunning {
            if link == .phone { break }

            let began = Date()
            if let raw = await session.fetchLiveViewFrame(),
               let image = UIImage(data: raw.jpeg) {
                frame = image
                frameSize = CGSize(width: raw.width, height: raw.height)
                if analysisThrottle.shouldEmit() {
                    frameSink?(image)
                }
                framesInWindow += 1
            }

            let elapsed = Date().timeIntervalSince(began)
            let windowElapsed = Date().timeIntervalSince(windowStart)
            if windowElapsed >= 1.0 {
                liveViewFPS = Double(framesInWindow) / windowElapsed
                framesInWindow = 0
                windowStart = Date()
            }

            let wait = max(0.004, targetInterval - elapsed)
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    // MARK: 拍摄

    /// 按下快门。原图会同时写进相机存储卡（RAW 留卡最保险），
    /// 然后经 PTP 回传到当前项目。
    func release(storeInCamera: Bool = true) async {
        // 手机模式直接走 AVFoundation
        if link == .phone {
            phone.capturePhoto()
            return
        }

        guard link.isTethering else {
            lastError = "还没有连上相机"
            return
        }
        guard !isReleasing else { return }

        isReleasing = true
        captureRequestedAt = Date()
        defer { isReleasing = false }

        do {
            try await session.triggerCapture(storeInCamera: storeInCamera)
        } catch {
            lastError = "快门触发失败：\(error.localizedDescription)"
            session.log("快门失败：\(error.localizedDescription)")
        }
    }

    // MARK: 回传处理

    private func handleNewFile(_ file: ICCameraFile) {
        guard let projectID = activeProjectID else { return }

        // 相机刚开会话时会一次性上报整张卡的内容，
        // 用「文件时间是否晚于本次快门」把老照片挡掉。
        if let requested = captureRequestedAt, let created = file.creationDate {
            if created < requested.addingTimeInterval(-8) { return }
        }

        let originalName = file.name ?? "capture.\(Self.fallbackExtension(for: file))"
        let destination = PixMatePaths.ensure(PixMatePaths.originalDir(projectID))
            .appendingPathComponent("\(Date().fileStamp)_\(originalName)")

        isDownloading = true
        session.download(file, to: destination) { [weak self] url, error in
            guard let self else { return }
            self.isDownloading = false
            if let error {
                self.lastError = "回传失败：\(error.localizedDescription)"
                return
            }
            self.ingest(originalURL: url, projectID: projectID)
        }
    }

    /// 把落盘的原图变成项目里的一张资产：生成工作副本 + 记录元数据
    private func ingest(originalURL: URL, projectID: UUID) {
        let ext = originalURL.pathExtension.lowercased()
        let isRaw = Self.rawExtensions.contains(ext)

        // 工作副本：用于秒开预览与实时修图。
        // JPEG 直接拿来用；RAW 用嵌入预览（iOS 无法直接解码 NEF）。
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let workingName = "\(baseName)_w.jpg"
        let workingURL = PixMatePaths.ensure(PixMatePaths.workingDir(projectID))
            .appendingPathComponent(workingName)

        let preview: UIImage? = isRaw
            ? RawPreviewExtractor.preview(from: originalURL)
            : UIImage(contentsOfFile: originalURL.path)

        guard let image = preview else {
            lastError = isRaw
                ? "无法从 RAW 里取出预览图（\(ext.uppercased())），请改用 JPEG 拍摄"
                : "无法读取回传的照片"
            return
        }

        if let data = image.jpegData(compressionQuality: 0.92) {
            try? data.write(to: workingURL, options: .atomic)
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: originalURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0

        var asset = PhotoAsset(
            workingFileName: workingName,
            originalFileName: originalURL.lastPathComponent,
            isRaw: isRaw,
            pixelWidth: Int(image.size.width * image.scale),
            pixelHeight: Int(image.size.height * image.scale),
            fileSizeBytes: fileSize,
            source: .tethered,
            cameraModel: session.modelName
        )
        asset.capturedAt = Date()

        lastIngestedAt = Date()
        ingestHandler?(asset)
    }

    // MARK: 参数

    func refreshProperties() async {
        guard link.isTethering else { return }
        let list = await session.readPrimaryProperties()
        if !list.isEmpty { properties = list }
    }

    func setProperty(_ property: CameraProperty, toValue value: UInt64) async {
        guard let desc = await session.propertyDescription(property.id) else {
            lastError = "相机没有回报 \(property.name) 的可选值"
            return
        }
        do {
            try await session.setProperty(property.id, value: value, type: desc.dataType)
            await refreshProperties()
        } catch {
            lastError = "\(property.name) 设置失败：\(error.localizedDescription)"
        }
    }

    var primaryProperties: [CameraProperty] {
        let order = NikonValueFormatting.primaryProperties
        return properties.sorted { a, b in
            (order.firstIndex(of: a.id) ?? 99) < (order.firstIndex(of: b.id) ?? 99)
        }
    }

    // MARK: 常量

    static let rawExtensions: Set<String> = ["nef", "nrw", "cr2", "cr3", "arw", "raf", "orf", "rw2", "dng"]

    private static func fallbackExtension(for file: ICCameraFile) -> String {
        let uti = file.uti ?? ""
        if uti.contains("raw") { return "NEF" }
        return "JPG"
    }
}
