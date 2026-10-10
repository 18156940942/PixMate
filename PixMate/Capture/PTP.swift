import Foundation

// MARK: - PTP 容器
//
// 与相机通信的全部数据都是 PTP 容器。三种容器结构（ISO 15740）：
//
//   命令块 Command : Length(4) Type(2)=1 Code(2) TransactionID(4) Params(4×n)
//   数据块 Data    : Length(4) Type(2)=2 Code(2) Data(...)      ← 头只有 8 字节
//   响应块 Response: Length(4) Type(2)=3 Code(2) TransactionID(4) Params(4×n)
//
// 字节序统一为小端。

enum PTPContainerType: UInt16 {
    case command  = 0x0001
    case data     = 0x0002
    case response = 0x0003
    case event    = 0x0004
}

// MARK: - 标准操作码

enum PTPOperationCode: UInt16 {
    case getDeviceInfo      = 0x1001
    case openSession        = 0x1002
    case closeSession       = 0x1003
    case getStorageIDs      = 0x1004
    case getObjectHandles   = 0x1007
    case getObjectInfo      = 0x1008
    case getObject          = 0x1009
    case getDeviceStatus    = 0x1017
    case initiateCapture    = 0x100E
    case getDevicePropDesc  = 0x1014
    case getDevicePropValue = 0x1015
    case setDevicePropValue = 0x1016
    case getPartialObject   = 0x101B
}

// MARK: - PTP 数据类型

enum PTPDataType: UInt16 {
    case int8    = 0x0001
    case uint8   = 0x0002
    case int16   = 0x0003
    case uint16  = 0x0004
    case int32   = 0x0005
    case uint32  = 0x0006
    case int64   = 0x0007
    case uint64  = 0x0008
    case int128  = 0x0009
    case uint128 = 0x000A
    case string  = 0xFFFF

    var byteWidth: Int? {
        switch self {
        case .int8, .uint8:     return 1
        case .int16, .uint16:   return 2
        case .int32, .uint32:   return 4
        case .int64, .uint64:   return 8
        case .int128, .uint128: return 16
        case .string:           return nil
        }
    }
}

// MARK: - 响应码

enum PTPResponseCode: UInt16 {
    case ok                  = 0x2001
    case generalError        = 0x2002
    case sessionNotOpen      = 0x2003
    case invalidTransactionID = 0x2004
    case operationNotSupported = 0x2005
    case parameterNotSupported = 0x2006
    case incompleteTransfer  = 0x2007
    case deviceBusy          = 0x2019
    case invalidParameter    = 0x201E
    case accessDenied        = 0x200F
    case devicePropNotSupported = 0x200A

    var text: String {
        switch self {
        case .ok:                     return "OK"
        case .generalError:           return "相机返回一般错误"
        case .sessionNotOpen:         return "PTP 会话未打开"
        case .invalidTransactionID:   return "事务号无效"
        case .operationNotSupported:  return "相机不支持该操作"
        case .parameterNotSupported:  return "参数不被支持"
        case .incompleteTransfer:     return "数据传输不完整"
        case .deviceBusy:             return "相机忙（可能正在对焦/写卡）"
        case .invalidParameter:       return "参数非法"
        case .accessDenied:           return "访问被拒绝"
        case .devicePropNotSupported: return "相机不支持该属性"
        }
    }
}

// MARK: - 字节读取器

/// 所有解析都走这个，避免直接玩裸指针。
struct ByteReader {
    private(set) var bytes: [UInt8]
    private(set) var offset: Int = 0

    init(_ data: Data) { bytes = [UInt8](data) }
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var remaining: Int { bytes.count - offset }
    var isAtEnd: Bool { offset >= bytes.count }

    mutating func u8() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func u16() -> UInt16? {
        guard remaining >= 2 else { return nil }
        let v = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        offset += 2
        return v
    }

    mutating func u32() -> UInt32? {
        guard remaining >= 4 else { return nil }
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(bytes[offset + i]) << (8 * i) }
        offset += 4
        return v
    }

    mutating func u64() -> UInt64? {
        guard remaining >= 8 else { return nil }
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(bytes[offset + i]) << (8 * i) }
        offset += 8
        return v
    }

    /// 按 PTP 数据类型读一个值，统一提升成 UInt64
    mutating func value(of type: PTPDataType) -> UInt64? {
        switch type {
        case .int8, .uint8:
            guard let b = u8() else { return nil }
            return UInt64(b)
        case .int16, .uint16:
            guard let v = u16() else { return nil }
            return UInt64(v)
        case .int32, .uint32:
            guard let v = u32() else { return nil }
            return UInt64(v)
        case .int64, .uint64:
            return u64()
        case .int128, .uint128:
            guard remaining >= 16 else { return nil }
            offset += 16
            return 0
        case .string:
            return nil
        }
    }

    mutating func skip(_ n: Int) {
        offset = min(bytes.count, offset + max(0, n))
    }

    mutating func take(_ n: Int) -> [UInt8]? {
        guard remaining >= n, n >= 0 else { return nil }
        let slice = Array(bytes[offset..<(offset + n)])
        offset += n
        return slice
    }

    var rest: [UInt8] { offset < bytes.count ? Array(bytes[offset...]) : [] }
}

// MARK: - 构造

extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        for i in 0..<4 { append(UInt8((value >> (8 * UInt32(i))) & 0xFF)) }
    }

    mutating func appendLE(_ value: UInt64) {
        for i in 0..<8 { append(UInt8((value >> (8 * UInt64(i))) & 0xFF)) }
    }
}

// MARK: - PTP 命令

struct PTPCommand {
    var code: UInt16
    var parameters: [UInt32] = []
    var transactionID: UInt32 = 1
    /// 数据阶段要发给相机的载荷（data-out 操作，如 SetDevicePropValue）
    var payload: Data?

    /// 命令块（Type = 1）
    var commandBlock: Data {
        var d = Data()
        d.appendLE(UInt32(12 + parameters.count * 4))
        d.appendLE(UInt16(PTPContainerType.command.rawValue))
        d.appendLE(code)
        d.appendLE(transactionID)
        for p in parameters.prefix(5) { d.appendLE(p) }
        return d
    }

    /// 数据块（Type = 2，头 8 字节：Length + Type + Code）
    var dataBlock: Data? {
        guard let payload else { return nil }
        var d = Data()
        d.appendLE(UInt32(8 + payload.count))
        d.appendLE(UInt16(PTPContainerType.data.rawValue))
        d.appendLE(code)
        d.append(payload)
        return d
    }

    /// 只发裸数据、不带容器头（少数 SDK 版本要求这种形式）
    var rawPayload: Data? { payload }
}

// MARK: - PTP 响应

struct PTPResponse {
    var code: UInt16
    var transactionID: UInt32
    var parameters: [UInt32]

    init?(data: Data) {
        var r = ByteReader(data)
        guard let _ = r.u32(),
              let type = r.u16(),
              type == PTPContainerType.response.rawValue,
              let code = r.u16(),
              let tid = r.u32() else { return nil }
        self.code = code
        self.transactionID = tid
        var params: [UInt32] = []
        while let p = r.u32() { params.append(p) }
        self.parameters = params
    }

    var isOK: Bool { code == PTPResponseCode.ok.rawValue }

    var responseCode: PTPResponseCode? { PTPResponseCode(rawValue: code) }

    var readableError: String {
        if let c = responseCode { return "\(c.text)（0x\(String(code, radix: 16, uppercase: true))）" }
        return "未知错误（0x\(String(code, radix: 16, uppercase: true))）"
    }
}

// MARK: - 数据段剥离

enum PTPPayload {
    /// ImageCaptureCore 不同版本对 `outData` 的处理不一致：
    /// 有的返回完整 Data Block（8 字节头），有的直接给裸数据。
    /// 这里统一剥成裸数据 —— 靠 Length 是否与实际长度吻合来判断。
    static func strip(_ data: Data) -> Data {
        guard data.count > 8 else { return data }
        var r = ByteReader(data)
        guard let length = r.u32(),
              let type = r.u16(),
              type == PTPContainerType.data.rawValue,
              Int(length) == data.count else {
            return data
        }
        _ = r.u16() // OperationCode 回显
        return Data(r.rest)
    }
}

// MARK: - DevicePropDesc

/// 一个相机属性的完整描述（由 GetDevicePropDesc 0x1014 返回）。
/// 有了它才知道某个参数当前是第几档、一共有哪些档。
struct PTPDevicePropDesc {
    var property: UInt16
    var dataType: PTPDataType
    var isWritable: Bool
    var defaultValue: UInt64
    var currentValue: UInt64
    var form: Form

    enum Form {
        case none
        case range(min: UInt64, max: UInt64, step: UInt64)
        case enumeration([UInt64])
    }

    var allowedValues: [UInt64] {
        switch form {
        case .none:                 return [currentValue]
        case .range(let lo, let hi, let step):
            guard step > 0, hi >= lo else { return [currentValue] }
            var out: [UInt64] = []
            var v = lo
            while v <= hi {
                out.append(v)
                let next = v &+ step
                if next <= v { break }   // 防溢出死循环
                v = next
            }
            return out
        case .enumeration(let list): return list
        }
    }

    static func parse(_ raw: Data) -> PTPDevicePropDesc? {
        var r = ByteReader(PTPPayload.strip(raw))
        guard let prop = r.u16(),
              let rawType = r.u16(),
              let type = PTPDataType(rawValue: rawType),
              let getSet = r.u8(),
              let def = r.value(of: type),
              let cur = r.value(of: type) else { return nil }

        var form: Form = .none
        if let formFlag = r.u8() {
            switch formFlag {
            case 0x01:
                if let lo = r.value(of: type),
                   let hi = r.value(of: type),
                   let step = r.value(of: type) {
                    form = .range(min: lo, max: hi, step: step)
                }
            case 0x02:
                if let count = r.u16() {
                    var list: [UInt64] = []
                    for _ in 0..<count {
                        guard let v = r.value(of: type) else { break }
                        list.append(v)
                    }
                    form = .enumeration(list)
                }
            default:
                form = .none
            }
        }

        return PTPDevicePropDesc(
            property: prop,
            dataType: type,
            isWritable: getSet == 0x01,
            defaultValue: def,
            currentValue: cur,
            form: form
        )
    }
}

// MARK: - 错误

enum PTPError: LocalizedError {
    case noDevice
    case sessionNotOpen
    case badResponse
    case device(code: UInt16, message: String)
    case timeout(String)
    case notSupported(String)

    var errorDescription: String? {
        switch self {
        case .noDevice:          return "没有找到相机"
        case .sessionNotOpen:    return "相机会话未打开"
        case .badResponse:       return "相机返回了无法解析的数据"
        case .device(_, let m):  return m
        case .timeout(let what): return "\(what) 超时"
        case .notSupported(let what): return "当前相机不支持\(what)"
        }
    }
}

// MARK: - 数值格式化
//
// PTP 里所有参数都是裸数字，要显示成人话得查表。
// 尼康各固件的编码在细节上有差异，所以这里的原则是：
// **表里有的就翻译，没见过的就老实显示原始数值**，不猜。
// 真机上跑一次「参数校准」就能把表补全，见 README 第六节。

enum NikonValueFormatting {

    /// ISO：尼康把 ISO 值直接放在 UInt32 里（高字节用于标识自动档）
    static func iso(_ value: UInt64) -> String {
        let low = UInt32(value & 0xFFFF)
        switch value >> 16 {
        case 0x0000: return "ISO \(low)"
        case 0x0001: return "自动 ISO"
        case 0x0002: return "ISO \(low)（固定）"
        default:
            if low > 0 { return "ISO \(low)" }
            return "ISO —"
        }
    }

    /// 快门：尼康用分子/分母的定点表示，常见编码是 10000/x
    static func exposureTime(_ value: UInt64) -> String {
        guard value > 0 else { return "—" }
        let v = Double(value)
        if v >= 10_000 {
            let seconds = v / 10_000.0
            if seconds >= 1 {
                return String(format: "%.1f s", seconds)
            }
            return String(format: "1/%.0f", 1.0 / seconds)
        }
        // 小于 10000 的当作 1/x 处理
        if v >= 1 && v <= 8000 { return String(format: "1/%.0f", v) }
        return String(format: "%.4g", v)
    }

    /// 光圈：尼康用 f 值 ×100 的整数
    static func fNumber(_ value: UInt64) -> String {
        let f = Double(value) / 100.0
        guard f > 0 else { return "—" }
        return String(format: "f/%.1f", f)
    }

    /// 曝光补偿：以 1/6 EV 为步长的定点数
    static func exposureBias(_ value: UInt64) -> String {
        let signed = Int32(bitPattern: UInt32(truncatingIfNeeded: value))
        let ev = Double(signed) / 6.0
        return String(format: "%+.1f EV", ev)
    }

    /// 光圈优先等曝光模式枚举
    static func exposureProgram(_ value: UInt64) -> String {
        switch value {
        case 0x0001: return "M 手动"
        case 0x0002: return "Auto 自动"
        case 0x0003: return "A 光圈优先"
        case 0x0004: return "S 快门优先"
        case 0x0005: return "P 程序自动"
        default:     return "模式 \(value)"
        }
    }

    /// 白平衡
    static func whiteBalance(_ value: UInt64) -> String {
        switch value {
        case 0x0001: return "自动"
        case 0x0002: return "白炽灯"
        case 0x0003: return "荧光灯"
        case 0x0004: return "日光"
        case 0x0005: return "闪光灯"
        case 0x0006: return "阴天"
        case 0x0007: return "阴影"
        case 0x0008: return "色温"
        case 0x8010: return "预设 1"
        case 0x8011: return "预设 2"
        case 0x8012: return "预设 3"
        default:     return "白平衡 \(value)"
        }
    }

    /// 驱动 / 连拍模式
    static func stillCaptureMode(_ value: UInt64) -> String {
        switch value {
        case 0x0001: return "单张"
        case 0x0002: return "连拍"
        case 0x0003: return "延时"
        case 0x8010: return "静音"
        default:     return "驱动 \(value)"
        }
    }

    /// 对焦模式
    static func focusMode(_ value: UInt64) -> String {
        switch value {
        case 0x0001: return "MF 手动"
        case 0x0002: return "AF-S"
        case 0x0003: return "AF-C"
        case 0x0004: return "AF-A"
        default:     return "对焦 \(value)"
        }
    }

    /// 电池电量百分比
    static func battery(_ value: UInt64) -> String {
        "\(min(value, 100))%"
    }

    /// 兜底：按属性码挑一个格式化函数
    static func label(for property: UInt32, value: UInt64) -> String {
        switch property {
        case CameraPropertyCode.exposureIndex.rawValue:  return iso(value)
        case CameraPropertyCode.exposureTime.rawValue:   return exposureTime(value)
        case CameraPropertyCode.fNumber.rawValue:        return fNumber(value)
        case CameraPropertyCode.exposureBiasComp.rawValue: return exposureBias(value)
        case CameraPropertyCode.exposureProgramMode.rawValue: return exposureProgram(value)
        case CameraPropertyCode.whiteBalance.rawValue:   return whiteBalance(value)
        case CameraPropertyCode.stillCaptureMode.rawValue: return stillCaptureMode(value)
        case CameraPropertyCode.focusMode.rawValue:      return focusMode(value)
        case CameraPropertyCode.batteryLevel.rawValue:   return battery(value)
        default:                                          return "\(value)"
        }
    }

    /// 属性码 → 中文名
    static func name(for property: UInt32) -> String {
        switch property {
        case CameraPropertyCode.exposureIndex.rawValue:      return "ISO"
        case CameraPropertyCode.exposureTime.rawValue:       return "快门"
        case CameraPropertyCode.fNumber.rawValue:            return "光圈"
        case CameraPropertyCode.exposureBiasComp.rawValue:   return "曝光补偿"
        case CameraPropertyCode.exposureProgramMode.rawValue: return "曝光模式"
        case CameraPropertyCode.whiteBalance.rawValue:       return "白平衡"
        case CameraPropertyCode.stillCaptureMode.rawValue:   return "驱动模式"
        case CameraPropertyCode.focusMode.rawValue:          return "对焦模式"
        case CameraPropertyCode.meteringMode.rawValue:       return "测光模式"
        case CameraPropertyCode.imageSize.rawValue:          return "画幅尺寸"
        case CameraPropertyCode.batteryLevel.rawValue:       return "电池"
        case CameraPropertyCode.remainingShots.rawValue:     return "剩余张数"
        default:                                             return "0x\(String(property, radix: 16, uppercase: true))"
        }
    }

    /// 界面上重点展示的几项，顺序即显示顺序
    static let primaryProperties: [UInt32] = [
        CameraPropertyCode.exposureTime.rawValue,
        CameraPropertyCode.fNumber.rawValue,
        CameraPropertyCode.exposureIndex.rawValue,
        CameraPropertyCode.exposureBiasComp.rawValue
    ]
}
