import Foundation
import ImageCaptureCore
import Combine
import UIKit

// MARK: - 尼康 PTP 会话
//
// 这就是「像素蛋糕怎么连 Z6II」的技术答案：
// 用 ImageCaptureCore 拿到 ICCameraDevice，然后在它上面直接跑 **PTP 私有命令**。
//
//   ICCameraDevice.requestSendPTPCommand(命令块, outData: 数据块) { 响应, 数据, 错误 }
//
// 标准 PTP 操作码负责「读参数 / 写参数 / 拍 / 下载」，
// 尼康私有操作码（0x92xx）负责「实时取景」这类厂商扩展。

@MainActor
final class NikonPTPSession: NSObject, ObservableObject {

    enum Phase: Equatable {
        case idle
        case searching
        case opening(String)
        case ready(String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .searching, .opening: return true
            default: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var modelName: String = ""
    @Published private(set) var isLiveViewRunning = false
    /// 最近一次 PTP 错误，UI 上直接展示，方便对着相机查
    @Published private(set) var lastError: String?
    /// 协议交互日志（调试面板用）
    @Published private(set) var trace: [String] = []

    /// 相机里出现新文件（联机拍摄时就是刚拍的那张）
    var onNewFile: ((ICCameraFile) -> Void)?
    /// 相机拔线 / 关机
    var onDeviceRemoved: (() -> Void)?
    /// 相机主动上报的 PTP 事件
    var onPTPEvent: ((Data) -> Void)?

    /// 会话建立的时间，用来区分「卡里已有的老照片」和「本次新拍的」
    private(set) var sessionOpenedAt: Date?

    private let browser = ICDeviceBrowser()
    private var device: ICCameraDevice?
    private var transaction: UInt32 = 1
    private let downloader = CameraFileDownloader()
    /// 进行中的下载，按落盘路径索引，避免用无类型指针传上下文
    private var pendingDownloads: [URL: (URL, Error?) -> Void] = [:]

    override init() {
        super.init()
        browser.delegate = self
        // browsedDeviceTypeMask 的类型是 ICDeviceTypeMask?（可空），
        // 用 OptionSet 的 union 组合，避免 ICDeviceTypeMask(rawValue:) 的
        // failable 初始化返回可空值。
        browser.browsedDeviceTypeMask = ICDeviceTypeMask.camera
            .union(ICDeviceTypeMask(rawValue: ICDeviceLocationTypeMask.local.rawValue))
    }

    // MARK: 生命周期

    func startSearching() {
        guard !phase.isBusy else { return }
        phase = .searching
        lastError = nil
        log("开始搜索相机…")
        browser.start()
    }

    func shutDown() {
        isLiveViewRunning = false
        browser.stop()
        device?.requestCloseSession()
        device = nil
        sessionOpenedAt = nil
        phase = .idle
        modelName = ""
        log("已断开")
    }

    // MARK: 命令收发

    /// 发一条 PTP 命令。成功时返回（响应, 数据段）。
    @discardableResult
    func send(_ code: UInt16,
              parameters: [UInt32] = [],
              payload: Data? = nil) async throws -> (PTPResponse, Data) {

        guard let device else { throw PTPError.noDevice }
        transaction &+= 1
        let cmd = PTPCommand(code: code,
                             parameters: parameters,
                             transactionID: transaction,
                             payload: payload)

        log("→ 0x\(String(code, radix: 16, uppercase: true)) \(parameters.map { String($0) }.joined(separator: ","))")

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(PTPResponse, Data), Error>) in
            device.requestSendPTPCommand(cmd.commandBlock, outData: cmd.dataBlock) { responseData, outData, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let response = PTPResponse(data: responseData) else {
                    continuation.resume(throwing: PTPError.badResponse)
                    return
                }
                guard response.isOK else {
                    continuation.resume(throwing: PTPError.device(code: response.code,
                                                                  message: response.readableError))
                    return
                }
                continuation.resume(returning: (response, outData))
            }
        }
    }

    // MARK: 实时取景

    /// 开始实时取景。Z 系列固件对入参的要求不完全一致：
    /// 先按带参数的常见形式发，被拒就退回无参形式。
    func startLiveView() async throws {
        do {
            _ = try await send(NikonOpCode.startLiveView.rawValue, parameters: [0x00000000])
        } catch {
            log("带参 StartLiveView 被拒，改用无参形式")
            _ = try await send(NikonOpCode.startLiveView.rawValue)
        }
        isLiveViewRunning = true
        log("实时取景已开启")
    }

    func stopLiveView() async {
        guard isLiveViewRunning else { return }
        isLiveViewRunning = false
        _ = try? await send(NikonOpCode.endLiveView.rawValue)
        log("实时取景已关闭")
    }

    /// 取一帧。相机没准备好时返回 nil 而不是抛错，避免刷屏。
    func fetchLiveViewFrame() async -> NikonLiveViewFrame.Frame? {
        do {
            let (_, data) = try await send(NikonOpCode.getLiveViewImage.rawValue)
            guard !data.isEmpty else { return nil }
            return NikonLiveViewFrame.parse(data)
        } catch {
            return nil
        }
    }

    // MARK: 拍摄

    /// 触发一次拍摄。
    /// `storeInCamera = true` 时相机同时把原图写进存储卡（推荐，RAW 留在卡里最保险）。
    func triggerCapture(storeInCamera: Bool = true) async throws {
        let storage: UInt32 = storeInCamera ? 0xFFFFFFFF : 0x00000000
        do {
            _ = try await send(NikonOpCode.initiateCapture.rawValue, parameters: [storage, 0x00000000])
            log("快门已触发")
        } catch {
            // 有些固件走标准 InitiateCapture，无参数
            log("私有快门被拒，改用标准 InitiateCapture")
            _ = try await send(PTPOperationCode.initiateCapture.rawValue, parameters: [storage, 0x00000000])
        }
    }

    // MARK: 参数读写

    /// 读一个属性的完整描述（当前值 + 可选档位）
    func propertyDescription(_ property: UInt32) async -> PTPDevicePropDesc? {
        do {
            let (_, data) = try await send(PTPOperationCode.getDevicePropDesc.rawValue, parameters: [property])
            return PTPDevicePropDesc.parse(data)
        } catch {
            return nil
        }
    }

    /// 一次性把主要参数全部读回来
    func readPrimaryProperties() async -> [CameraProperty] {
        var result: [CameraProperty] = []
        for code in NikonValueFormatting.primaryProperties {
            guard let desc = await propertyDescription(code) else { continue }
            result.append(makeProperty(from: desc))
        }
        return result
    }

    /// 读一个属性的取值（轻量，比 GetDevicePropDesc 省一次往返）
    func propertyValue(_ property: UInt32, type: PTPDataType) async -> UInt64? {
        do {
            let (_, data) = try await send(PTPOperationCode.getDevicePropValue.rawValue, parameters: [property])
            var r = ByteReader(PTPPayload.strip(data))
            return r.value(of: type)
        } catch {
            return nil
        }
    }

    func setProperty(_ property: UInt32, value: UInt64, type: PTPDataType) async throws {
        var payload = Data()
        switch type {
        case .int8, .uint8:    payload.append(UInt8(value & 0xFF))
        case .int16, .uint16:  payload.appendLE(UInt16(value & 0xFFFF))
        case .int32, .uint32:  payload.appendLE(UInt32(value & 0xFFFFFFFF))
        case .int64, .uint64:  payload.appendLE(value)
        default:               payload.appendLE(UInt32(value & 0xFFFFFFFF))
        }
        _ = try await send(PTPOperationCode.setDevicePropValue.rawValue,
                           parameters: [property],
                           payload: payload)
    }

    /// 切应用模式（静态 / 视频），部分机型切实时取景前需要先切到静态
    func changeApplicationMode(_ mode: NikonAppMode) async {
        _ = try? await send(NikonOpCode.changeApplicationMode.rawValue, parameters: [mode.rawValue])
    }

    // MARK: 下载

    /// 把相机里的一个文件拉到本地，落盘后回调。
    func download(_ file: ICCameraFile,
                  to url: URL,
                  completion: @escaping (URL, Error?) -> Void) {
        guard let device else {
            completion(url, PTPError.noDevice)
            return
        }
        pendingDownloads[url] = completion
        downloader.onComplete = { [weak self] _, finishedURL, error in
            Task { @MainActor in
                guard let self else { return }
                let handler = self.pendingDownloads.removeValue(forKey: finishedURL)
                handler?(finishedURL, error)
            }
        }
        downloader.request(file: file, to: url, on: device)
    }

    // MARK: 内部

    private func makeProperty(from desc: PTPDevicePropDesc) -> CameraProperty {
        let values = desc.allowedValues
        return CameraProperty(
            id: UInt32(desc.property),
            name: NikonValueFormatting.name(for: UInt32(desc.property)),
            currentValue: desc.currentValue,
            currentLabel: NikonValueFormatting.label(for: UInt32(desc.property), value: desc.currentValue),
            allowedValues: values,
            allowedLabels: values.map { NikonValueFormatting.label(for: UInt32(desc.property), value: $0) },
            isWritable: desc.isWritable,
            isReadOnly: !desc.isWritable
        )
    }

    private func attach(_ device: ICDevice) {
        guard let camera = device as? ICCameraDevice else { return }
        self.device = camera
        camera.delegate = self
        modelName = camera.name ?? "尼康相机"
        phase = .opening(modelName)
        log("发现设备：\(modelName)，打开会话…")
        camera.requestOpenSession()
    }

    private func detach(_ device: ICDevice) {
        guard device === self.device else { return }
        log("设备已移除")
        self.device = nil
        isLiveViewRunning = false
        sessionOpenedAt = nil
        phase = .idle
        onDeviceRemoved?()
    }

    func log(_ line: String) {
        let stamp = Date().shortStamp
        trace.append("[\(stamp)] \(line)")
        if trace.count > 400 { trace.removeFirst(trace.count - 400) }
    }
}

// MARK: - 设备浏览器

extension NikonPTPSession: ICDeviceBrowserDelegate {

    // 这几个委托方法必须是 nonisolated：@objc 协议方法不能带 actor 隔离。
    // 但 ImageCaptureCore 并不保证在哪个线程回调，所以内部再显式跳回主 actor。
    // 反过来若直接写成主 actor 方法，编译器会「隐式隔离一致」静默放行，
    // 而 ObjC 运行时不理会这个推断 —— 后台线程回调时会崩。
    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser,
                                   didAdd device: ICDevice,
                                   moreComing: Bool) {
        Task { @MainActor in self.attach(device) }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser,
                                   didRemove device: ICDevice,
                                   moreGoing: Bool) {
        Task { @MainActor in self.detach(device) }
    }

    /// 本地设备全部枚举完毕。协议里是可选方法，但实现它能让「搜不到相机」
    /// 这种情况有明确落点，不至于一直停在 .searching。
    nonisolated func deviceBrowserDidEnumerateLocalDevices(_ browser: ICDeviceBrowser) {
        Task { @MainActor in
            if case .searching = self.phase {
                self.log("本地设备枚举结束，未发现相机")
            }
        }
    }
}

// MARK: - 设备级代理
//
// ⚠️ 这一组 @objc 可选方法的 Swift 签名在 SDK 版本之间偶有变化。
// 如果编译报「does not conform to protocol」或方法不被调用，
// 打开 Xcode 对着 ICCameraDeviceDelegate / ICDeviceDelegate 的定义核对一次即可，
// 见 README 第六节。

extension NikonPTPSession: ICDeviceDelegate {

    // 注意：deviceDidBecomeReady 的现代签名是
    // deviceDidBecomeReady(withCompleteContentCatalog:)，
    // 属于 ICCameraDeviceDelegate，已在上面的相机代理扩展里实现。

    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        Task { @MainActor in
            if let error {
                self.phase = .failed(error.localizedDescription)
                self.lastError = error.localizedDescription
                self.log("打开会话失败：\(error.localizedDescription)")
            } else {
                self.log("会话已打开")
            }
        }
    }

    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        Task { @MainActor in
            self.log("会话已关闭")
            self.isLiveViewRunning = false
            self.phase = .idle
        }
    }

    nonisolated func device(_ device: ICDevice, didReceiveStatusInformation status: [ICDeviceStatus: Any]) {
        // 电池、卡状态等——留给上层按需读取，这里只记日志
        Task { @MainActor in
            let keys = status.keys.map(\.rawValue).joined(separator: ",")
            if !keys.isEmpty { self.log("状态更新：\(keys)") }
        }
    }

    nonisolated func device(_ device: ICDevice, didEncounterError error: Error?) {
        Task { @MainActor in
            let message = error?.localizedDescription ?? "未知错误"
            self.lastError = message
            self.log("设备错误：\(message)")
        }
    }

    nonisolated func didRemove(_ device: ICDevice) {
        Task { @MainActor in self.detach(device) }
    }
}

// MARK: - 相机级代理

extension NikonPTPSession: ICCameraDeviceDelegate {

    /// 相机里新增了一个文件 —— 联机拍摄时这就是刚拍的那张。
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd item: ICCameraItem) {
        Task { @MainActor in
            guard let file = item as? ICCameraFile else { return }
            self.log("相机上报新文件：\(file.name ?? "?")")
            self.onNewFile?(file)
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove item: ICCameraItem) {
        Task { @MainActor in
            self.log("相机移除文件：\(item.name ?? "?")")
        }
    }

    /// 相机内容编目完成，可以开始下发请求了。
    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        Task { @MainActor in
            self.sessionOpenedAt = Date()
            self.phase = .ready(self.modelName)
            self.log("会话就绪，相机内容已编目")
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
        Task { @MainActor in
            self.log("相机重命名了 \(items.count) 个文件")
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didReceiveThumbnail thumbnail: CGImage?,
                                  for item: ICCameraItem,
                                  error: (any Error)?) {
        // 缩略图不是本项目的主路径（我们用 PTP 实时取景），收到只记一笔
        Task { @MainActor in
            if let error {
                self.log("缩略图失败：\(error.localizedDescription)")
            }
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didReceiveMetadata metadata: [AnyHashable: Any]?,
                                  for item: ICCameraItem,
                                  error: (any Error)?) {
        // 同上，元数据按需在下载链路里读
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice,
                                  didReceivePTPEvent eventData: Data) {
        Task { @MainActor in self.onPTPEvent?(eventData) }
    }

    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {
        Task { @MainActor in self.log("设备能力发生变化") }
    }

    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        Task { @MainActor in self.log("设备进入受限状态（可能是锁屏）") }
    }

    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        Task { @MainActor in self.log("设备已解除受限") }
    }
}

// MARK: - 文件下载

/// 用 ICCameraDeviceDownloadDelegate 把相机文件落到指定路径。
///
/// 注意：ICDownloadOption 没有「指定输出文件名」这一项 ——
/// 它只接受 downloadsDirectoryURL（落盘目录），文件名由相机决定。
/// 所以这里约定：调用方给的 url 只取父目录，最终文件名 = 相机原始文件名。
/// 回调里把真实落盘路径回传给上层。
final class CameraFileDownloader: NSObject, ICCameraDeviceDownloadDelegate {

    /// 下载完成：(文件, 落盘路径, 错误)
    var onComplete: ((ICCameraFile, URL, Error?) -> Void)?
    /// 下载进度：(文件, 已下载字节, 总字节)
    var onProgress: ((ICCameraFile, Int64, Int64) -> Void)?

    /// 落盘目录（由最近一次 request 决定），用于回调时拼真实路径
    private var destinationDirectory: URL?

    func request(file: ICCameraFile, to url: URL, on device: ICCameraDevice) {
        let directory = url.deletingLastPathComponent()
        destinationDirectory = directory

        let options: [ICDownloadOption: Any] = [
            .downloadsDirectoryURL: directory as NSURL,
            .overwrite: NSNumber(value: true)
        ]

        device.requestDownloadFile(file,
                                   options: options,
                                   downloadDelegate: self,
                                   didDownloadSelector: #selector(didDownloadFile(_:error:options:contextInfo:)),
                                   contextInfo: nil)
    }

    @objc func didDownloadFile(_ file: ICCameraFile,
                               error: (any Error)?,
                               options: [String: Any],
                               contextInfo: UnsafeMutableRawPointer?) {
        // 真实文件名来自 options 里的 ICDownloadOptionFilenameKey，
        // 拿不到就退回相机原始文件名。
        var name = file.name ?? "unknown"
        if let saved = options[ICDownloadOption.savedFileNameKey.rawValue] as? String, !saved.isEmpty {
            name = saved
        }
        let directory = destinationDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let landed = directory.appendingPathComponent(name)
        onComplete?(file, landed, error)
    }

    @objc func didReceiveDownloadProgress(for file: ICCameraFile,
                                          downloadedBytes: off_t,
                                          maxBytes: off_t) {
        onProgress?(file, Int64(downloadedBytes), Int64(maxBytes))
    }
}
