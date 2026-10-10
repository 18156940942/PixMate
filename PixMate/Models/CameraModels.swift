import Foundation

// MARK: - 连接状态

/// 相机与手机的连接形态。
/// 尼康 Z6II 没有原生 UVC 输出，所以除了手机模式以外，
/// 联机只可能是有线 PTP 或无线 PTP/IP（像素蛋糕这两条都支持）。
enum CameraLink: Equatable {
    case disconnected
    case connecting(String)
    case wired(model: String)
    case wireless(model: String)
    case phone
    case failed(String)

    var isConnected: Bool {
        switch self {
        case .wired, .wireless, .phone: return true
        default: return false
        }
    }

    var isTethering: Bool {
        switch self {
        case .wired, .wireless: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .disconnected:      return "未连接"
        case .connecting:        return "连接中…"
        case .wired(let m):      return "\(m) · 有线"
        case .wireless(let m):   return "\(m) · 无线"
        case .phone:             return "手机模式"
        case .failed:            return "连接失败"
        }
    }

    var detail: String? {
        switch self {
        case .connecting(let s): return s
        case .failed(let s):     return s
        default: return nil
        }
    }

    var symbolName: String {
        switch self {
        case .disconnected: return "cable.connector.slash"
        case .connecting:   return "arrow.triangle.2.circlepath"
        case .wired:        return "cable.connector"
        case .wireless:     return "wifi"
        case .phone:        return "iphone"
        case .failed:       return "exclamationmark.triangle"
        }
    }
}

// MARK: - 相机可调参数

/// 相机上的一个可调项，直接映射到一个 PTP DeviceProp。
/// 名称与取值都由相机在会话建立时回报，App 不硬编码档位。
struct CameraProperty: Identifiable, Equatable {
    /// PTP 属性码，如 0x500F = ISO
    let id: UInt32
    var name: String
    var currentValue: UInt64
    var currentLabel: String
    var allowedValues: [UInt64]
    var allowedLabels: [String]
    var isWritable: Bool
    /// 是否只读（如电池电量、剩余张数）
    var isReadOnly: Bool

    var isEnumeration: Bool { allowedLabels.count > 1 }

    var index: Int? {
        allowedValues.firstIndex(of: currentValue)
    }

    var progress: Double {
        guard isEnumeration, allowedValues.count > 1, let i = index else { return 0 }
        return Double(i) / Double(allowedValues.count - 1)
    }
}

// MARK: - 标准 PTP 属性码

enum CameraPropertyCode: UInt32 {
    case batteryLevel          = 0x5001
    case imageSize            = 0x5003
    case compressionSetting   = 0x5004
    case whiteBalance         = 0x5005
    case fNumber              = 0x5007
    case focusMode            = 0x500A
    case meteringMode         = 0x500B
    case exposureTime         = 0x500D
    case exposureProgramMode  = 0x500E
    case exposureIndex        = 0x500F
    case exposureBiasComp     = 0x5010
    case stillCaptureMode     = 0x5013
    case remainingShots       = 0x5017
    case dateTime             = 0x5011
}

// MARK: - 尼康私有操作码

/// 尼康 PTP 私有操作码。Z 系列（含 Z6II）与 D 系列共用这套编号。
/// 参考开源实现（libgphoto2 的 nikon 后端）——但**入参格式必须真机校准**，
/// 不同固件版本对同一操作码的参数解释可能不同，见 README 第六节。
enum NikonOpCode: UInt16 {
    /// 进入 / 退出实时取景
    case startLiveView       = 0x9201
    case endLiveView         = 0x9202
    /// 取一帧实时取景画面（返回 JPEG，前置一段厂商头）
    case getLiveViewImage    = 0x9203
    /// 手动对焦驱动
    case mfDrive             = 0x9204
    /// 机身内开始录制（视频）
    case startMovieRecInCard = 0x9205
    case endMovieRec         = 0x9206
    /// 触发一次静态拍摄，可指定是否写入机身存储卡
    case initiateCapture     = 0x9207
    /// 切换应用模式（静态 / 视频）
    case changeApplicationMode = 0x9435
    /// 取厂商自定义属性码表
    case getVendorPropCodes  = 0x9438
    /// 取 PTP/IP 信息（无线联机时需要）
    case getPTPIPInfo        = 0x943C
    /// 自动对焦驱动
    case afDrive             = 0x92C1
    /// 取事件（新文件、参数变更）
    case getEvent            = 0x90C7
    /// 会话就绪问答
    case deviceReady         = 0x90C8
}

/// 尼康应用模式
enum NikonAppMode: UInt32 {
    case still  = 0x0001
    case movie  = 0x0002
}

/// Z6II 实时取景帧的已知尺寸（Dragonframe 官方对 Z6II 的记录为 1024×680）。
/// 仅用于 UI 预布局，实际以每帧 JPEG 头部为准。
enum LiveViewDefaults {
    static let assumedWidth: CGFloat = 1024
    static let assumedHeight: CGFloat = 680
}
