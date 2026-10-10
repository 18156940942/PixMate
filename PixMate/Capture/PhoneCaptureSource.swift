import Foundation
import AVFoundation
import CoreImage
import UIKit
import Combine

// MARK: - 手机模式
//
// 没带相机、或只是想先用手机试构图时走这条。
// 对应像素蛋糕的「相机模式」——非有线联机状态下进入相机就是手机模式。

/// 预览帧的节流闸。CIContext 和节流状态都放在非隔离的容器里，
/// 因为采样回调跑在视频队列上，不能碰主线程的东西。
private enum PhoneVideoPipeline {
    static let context = CIContext(options: [.cacheIntermediates: false])

    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var last: CFTimeInterval = 0
        private let interval: CFTimeInterval

        init(fps: Double) {
            interval = fps > 0 ? 1.0 / fps : 0
        }

        func allow() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let now = CACurrentMediaTime()
            guard now - last >= interval else { return false }
            last = now
            return true
        }
    }

    static let gate = Gate(fps: 8)
}

@MainActor
final class PhoneCaptureSource: NSObject, ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var delegateProxy: PhotoCaptureDelegate?

    /// 预览帧回调，供参谋层做人脸 / 构图分析
    var frameSink: ((UIImage) -> Void)?
    /// 拍完的照片回调
    var onPhoto: ((UIImage) -> Void)?

    private let videoQueue = DispatchQueue(label: "pixmate.phone.video")

    // MARK: 启停

    func start() async {
        guard !isRunning else { return }

        guard await requestAccess() else {
            errorMessage = "没有相机权限，去「设置 → 像素搭档」里打开"
            return
        }

        guard configureSession() else { return }

        let session = self.session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
                DispatchQueue.main.async {
                    self.isRunning = true
                    continuation.resume()
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: 配置

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    private func configureSession() -> Bool {
        if isRunning { return true }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        // 后置广角优先
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            errorMessage = "这台设备上没有可用的摄像头"
            return false
        }

        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .quality
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        return true
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = videoInput?.device else { return }
        let clamped = max(device.minAvailableVideoZoomFactor,
                          min(factor, device.maxAvailableVideoZoomFactor))
        try? device.lockForConfiguration()
        device.videoZoomFactor = clamped
        device.unlockForConfiguration()
    }

    // MARK: 拍摄

    func capturePhoto() {
        guard isRunning else { return }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality

        let proxy = PhotoCaptureDelegate { [weak self] image in
            Task { @MainActor in self?.onPhoto?(image) }
        }
        delegateProxy = proxy
        photoOutput.capturePhoto(with: settings, delegate: proxy)
    }
}

// MARK: - 预览流 → 参谋层

extension PhoneCaptureSource: AVCaptureVideoDataOutputSampleBufferDelegate {

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard PhoneVideoPipeline.gate.allow() else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = PhoneVideoPipeline.context.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }
        // 采集缓冲是横的，这里转正
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .right)

        Task { @MainActor [weak self] in
            self?.frameSink?(image)
        }
    }
}

// MARK: - 单张拍摄回调

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {

    private let onFinish: (UIImage) -> Void
    private var didFinish = false

    init(onFinish: @escaping (UIImage) -> Void) {
        self.onFinish = onFinish
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard !didFinish, error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        didFinish = true
        onFinish(image)
    }
}
