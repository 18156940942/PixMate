import Foundation

// MARK: - 修图参数

/// 一张照片的全部修图参数。所有值均为归一化的「强度」，
/// 由 RetouchEngine 翻译成 Core Image 的具体滤镜参数。
struct RetouchParams: Codable, Equatable, Hashable {

    // ── 人像 ───────────────────────────────────────────
    /// 磨皮强度。引擎会保留皮肤纹理，不是无脑涂抹。
    var skinSmoothing: Double = 0
    /// 肤色冷暖：负=冷，正=暖
    var skinTone: Double = 0
    /// 肤色提亮
    var skinBrightness: Double = 0
    /// 祛痘 / 瑕疵弱化
    var blemishRemoval: Double = 0
    /// 脸型收窄
    var faceSlim: Double = 0
    /// 眼神光 + 眼白提亮
    var eyeEnhance: Double = 0
    /// 牙齿美白
    var teethWhiten: Double = 0
    /// 唇色增强
    var lipEnhance: Double = 0

    // ── 影调 ───────────────────────────────────────────
    var exposure: Double = 0
    var contrast: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var whites: Double = 0
    var blacks: Double = 0

    // ── 色彩 ───────────────────────────────────────────
    var temperature: Double = 0
    var tint: Double = 0
    var vibrance: Double = 0
    var saturation: Double = 0
    /// 色相偏移，用于做青橙、胶片等风格
    var hueShift: Double = 0

    // ── 细节 ───────────────────────────────────────────
    var clarity: Double = 0
    var sharpen: Double = 0.15
    var denoise: Double = 0
    var vignette: Double = 0
    var grain: Double = 0

    // ── 背景 ───────────────────────────────────────────
    /// 背景虚化（人像模式）
    var backgroundBlur: Double = 0
    /// 背景压暗，突出主体
    var backgroundDarken: Double = 0

    static let neutral = RetouchParams()

    /// 是否任何一项非默认 —— 用于 UI 上显示「已修」标记
    var isEdited: Bool { self != RetouchParams.neutral }

    /// 人像相关项是否启用（决定要不要跑人脸检测，省算力）
    var needsFaceAnalysis: Bool {
        skinSmoothing > 0.001 || skinTone != 0 || skinBrightness != 0 ||
        blemishRemoval > 0.001 || faceSlim > 0.001 || eyeEnhance > 0.001 ||
        teethWhiten > 0.001 || lipEnhance > 0.001
    }

    /// 背景相关项是否启用（决定要不要跑人像分割）
    var needsSubjectMask: Bool {
        backgroundBlur > 0.001 || backgroundDarken > 0.001
    }

    mutating func resetPortrait() {
        skinSmoothing = 0; skinTone = 0; skinBrightness = 0; blemishRemoval = 0
        faceSlim = 0; eyeEnhance = 0; teethWhiten = 0; lipEnhance = 0
    }

    mutating func resetTone() {
        exposure = 0; contrast = 0; highlights = 0; shadows = 0; whites = 0; blacks = 0
    }

    mutating func resetColor() {
        temperature = 0; tint = 0; vibrance = 0; saturation = 0; hueShift = 0
    }

    mutating func resetAll() { self = .neutral }
}

// MARK: - 修图预设

struct RetouchPreset: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// 内置预设不可删除，但可以「另存为」衍生出自己的版本
    var isBuiltIn: Bool = false
    var params: RetouchParams
    var createdAt: Date = .now

    // MARK: 内置预设

    /// 命名刻意避开像素蛋糕的注册商标用语（原肤/无暇/原生感/春桃），
    /// 用功能描述性的名字，气质上对齐「一键出片」。
    static let builtIns: [RetouchPreset] = [
        RetouchPreset(
            name: "通透",
            isBuiltIn: true,
            params: {
                var p = RetouchParams.neutral
                p.skinSmoothing = 0.42
                p.skinBrightness = 0.12
                p.blemishRemoval = 0.30
                p.faceSlim = 0.10
                p.eyeEnhance = 0.22
                p.exposure = 0.06
                p.contrast = 0.10
                p.shadows = 0.16
                p.vibrance = 0.12
                p.clarity = 0.08
                return p
            }()
        ),
        RetouchPreset(
            name: "奶油肤",
            isBuiltIn: true,
            params: {
                var p = RetouchParams.neutral
                p.skinSmoothing = 0.62
                p.skinTone = 0.10
                p.skinBrightness = 0.20
                p.blemishRemoval = 0.45
                p.faceSlim = 0.16
                p.eyeEnhance = 0.30
                p.teethWhiten = 0.28
                p.exposure = 0.10
                p.highlights = -0.08
                p.shadows = 0.22
                p.temperature = 0.06
                p.vibrance = 0.08
                p.clarity = -0.06
                p.backgroundBlur = 0.18
                return p
            }()
        ),
        RetouchPreset(
            name: "胶片",
            isBuiltIn: true,
            params: {
                var p = RetouchParams.neutral
                p.skinSmoothing = 0.22
                p.exposure = -0.04
                p.contrast = 0.16
                p.highlights = -0.14
                p.shadows = 0.30
                p.blacks = -0.18
                p.temperature = 0.08
                p.tint = 0.04
                p.vibrance = -0.06
                p.saturation = -0.10
                p.hueShift = 0.05
                p.clarity = 0.05
                p.grain = 0.22
                p.vignette = 0.16
                return p
            }()
        ),
        RetouchPreset(
            name: "高级灰",
            isBuiltIn: true,
            params: {
                var p = RetouchParams.neutral
                p.skinSmoothing = 0.30
                p.blemishRemoval = 0.22
                p.faceSlim = 0.08
                p.exposure = -0.02
                p.contrast = -0.06
                p.highlights = -0.10
                p.shadows = 0.24
                p.whites = -0.12
                p.saturation = -0.24
                p.vibrance = -0.08
                p.clarity = -0.04
                p.backgroundDarken = 0.12
                return p
            }()
        ),
        RetouchPreset(
            name: "棚拍硬朗",
            isBuiltIn: true,
            params: {
                var p = RetouchParams.neutral
                p.skinSmoothing = 0.34
                p.blemishRemoval = 0.50
                p.faceSlim = 0.06
                p.eyeEnhance = 0.20
                p.exposure = 0.02
                p.contrast = 0.20
                p.highlights = -0.06
                p.shadows = 0.10
                p.blacks = -0.10
                p.clarity = 0.16
                p.sharpen = 0.28
                p.backgroundDarken = 0.18
                return p
            }()
        ),
        RetouchPreset(
            name: "暖阳",
            isBuiltIn: true,
            params: {
                var p = RetouchParams.neutral
                p.skinSmoothing = 0.38
                p.skinTone = 0.16
                p.skinBrightness = 0.14
                p.exposure = 0.08
                p.highlights = -0.06
                p.shadows = 0.20
                p.temperature = 0.20
                p.vibrance = 0.18
                p.saturation = 0.06
                p.clarity = 0.06
                p.vignette = 0.10
                return p
            }()
        )
    ]
}
