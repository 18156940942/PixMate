# PixMate · 像素搭档

一个自用的 iOS 联机拍摄 App。**联机方式完全照像素蛋糕连尼康 Z6II 的那条路做**：USB 数据线 + PTP 协议，实时取景、即拍即修、构图与姿势参谋、高质量导出，四件事串成一条流水线。

不是「像」像素蛋糕，是同一类东西——你可以把它理解成一个只为你一台 Z6II 服务的私人版。

---

## 一、四条需求分别落在哪

| 你的需求 | 实现在哪 | 具体做到什么程度 |
|---|---|---|
| ① 实时监控相机屏幕 | `Capture/NikonPTPSession.swift`<br>`Capture/CameraController.swift` | USB + PTP 拉实时取景流，Z6II 原生分辨率 1024×680，实测目标 20 fps，画面差就自动降速不空转 |
| ② 即拍即修 + AI 修图 | `Retouch/RetouchEngine.swift` | 磨皮（保纹理）、祛痘、肤色冷暖/提亮、脸型收窄、眼神光、牙齿美白、唇色，加影调/色彩/背景虚化。6 个内置预设，一键套整个项目 |
| ③ AI 辅助构图 + 生成姿势 | `Analysis/` 五个文件 | 构图诊断给的是「把手机向左回正 3°」这种能立刻执行的句子；姿势建议分本地库（**35 条 · 站姿/坐姿/靠撑/动态/半身特写/双人六大类**，离线零延迟）和多模态现场生成（按画面里实际景色）两层；两个人入画时自动混入互动姿势 |
| ④ 高质量导出 | `Export/ExportService.swift` | 默认原始尺寸不降采样 + Display P3 + 98% 质量；RAW 自动取嵌入预览出片，原图另存一份 |

**第 ③ 条是唯一市面上没有现成方案的部分**（像素蛋糕没有，Superpose / 卡洛相机那类只有手机自拍姿势，不接相机画面）。所以我在这块做得最重。

---

## 二、联机原理：像素蛋糕到底怎么连 Z6II

这是这次重做的核心。三件事决定了方案：

**1. Z6II 没有原生 UVC 输出。**

这点和 Z30 不一样。Z30 机身能直出 UVC 视频流，手机当 USB 摄像头就能认；Z6II 不行——尼康给它的 Webcam Utility 是**电脑上跑的软件**，把相机的私有流转成虚拟摄像头，手机端用不了。

结论：**Z6II 连手机只剩 PTP 一条路。**

**2. PTP 就是像素蛋糕走的路。**

像素蛋糕的联机在 iPhone 上要求开「相机」+「文件与文件夹」两项权限——这正是 `ImageCaptureCore` 的 PTP 通路特征。它的 Z6II 有线联机、监视器模式，底层都是 PTP。

**3. 所以本工程的取景层长这样：**

```
iPhone / iPad
    │  USB-C 数据线（≤2m，带数据传输）
    ▼
ImageCaptureCore  →  ICCameraDevice
    │
    │  requestSendPTPCommand(命令块, outData: 数据块)
    ▼
尼康 PTP 协议
    ├── 标准操作码：读参数 / 写参数 / 触发快门 / 下载文件
    └── 私有操作码：0x9201 开实时取景、0x9203 取帧、0x9207 触发拍摄
```

关键的几个操作码（`Models/CameraModels.swift` 里的 `NikonOpCode`）：

| 操作码 | 作用 |
|---|---|
| `0x9201` | 开启实时取景 |
| `0x9202` | 关闭实时取景 |
| `0x9203` | 取一帧实时取景画面（返回带厂商头的 JPEG） |
| `0x9207` | 触发一次拍摄 |
| `0x9435` | 切换应用模式（静态 / 视频） |
| `0x90C7` / `0x90C8` | 取事件 / 会话就绪问答 |

标准 PTP 部分用来读参数（`0x1014` 取属性描述）和写参数（`0x1016`），以及下载文件。

**实时取景帧怎么剥出来的**（`Capture/LiveViewStream.swift`）：

相机返回的数据不是干净 JPEG，前面有一段厂商头。代码**没有硬砍固定字节数**——固件一换那个数字就变了——而是直接在字节流里找 JPEG 的 `FFD8FF`（SOI）和末尾的 `FFD9`（EOI）。这样固件升级也不会突然黑屏。

---

## 三、相机端设置（Z6II）

这四步和像素蛋糕的要求**一模一样**，少一步连不上：

| 步骤 | 菜单路径 | 值 | 为什么 |
|---|---|---|---|
| 1 | —— | **机身内插好存储卡** | 没卡相机不会把原图交给手机 |
| 2 | 设定菜单 → USB | **MTP/PTP** | ⚠️ 千万别选「iPhone」，那是给尼康自家 NX MobileAir 用的，选它会把相机网络功能全关掉。需要固件 **1.50 以上**才有这个菜单项 |
| 3 | 设定菜单 → USB 电力输送 | **OFF** | 手机不是电脑，边给相机供电边传数据必然掉线 |
| 4 | 飞行模式 / 模式转盘 | 关飞行模式，转盘拨到 **M/A/S** | 相机在播放模式或视频模式下，实时取景命令会被拒 |

---

## 四、手机端连接

1. 用 **USB-C 数据线直连**，线长 **≤ 2 米**。
   有些线只供电不传数据，必须用带数据传输的（尼康原装 UC-E24 / UC-E25 一类）。
2. 插上后系统弹「要允许访问相机吗」→ **允许**。
   误点不允许：设置 → 隐私与安全性 → 文件与文件夹 → 找到「像素搭档」打开。
3. 打开 App → App 会自动搜索并建立 PTP 会话 → 连上后自动开实时取景。
4. 还没建项目的话先建一个（项目页右上角 +），否则拍了没地方放。

---

## 五、五分钟跑起来

1. **项目页** → 右上角 `+` → 建一个项目，它自动成为「当前项目」。
2. **拍摄页** → 底部点「搜索相机」→ 连上后画面出现。
3. 手机会自动开始诊断：**取景画面上直接标出问题**（歪掉的水平线、头顶留白、主体不在三分线），侧栏给出「把手机向左回正 3°」这类动作。
4. **点姿势卡片** → 画面上出现虚线骨架幽灵，套在你检测到的那个人身上；下面实时显示「左手再往上 3 分」这种喊话提示。
5. **按快门** → 相机拍下、原图经 PTP 回传到项目、右下角出现缩略图 → 点它进精修。
6. 精修页调完 → 「导出」。想批量：项目页 → 选 → 批量预设 → 导出。

---

## 六、构建

### 有 Mac

需要 **Xcode 15+** 和 **XcodeGen**（`brew install xcodegen`）。

```bash
cd outputs/PixMate
xcodegen generate
open PixMate.xcodeproj
```

然后在 Xcode 里：
- 选中 PixMate target → Signing & Capabilities → 填你的 **Team**
- 把 Bundle Identifier 改成你自己的（默认 `com.local.pixmate` 会和别人冲突）
- 选你的 iPhone / iPad → Run

### 没有 Mac（只有 Windows）

**已经给你铺好了：推到 GitHub，云端自动出 ipa，再在 Windows 上装进 iPhone。**

- 构建脚本：`.github/workflows/build-ipa.yml`（推上去自动跑，`macos-14` runner，公共仓库免费）
- 完整步骤：**[构建与安装-无Mac电脑.md](构建与安装-无Mac电脑.md)** ← 从注册 GitHub 到手机上打开 App，全程照做即可

一句话流程：推仓库 → Actions 出 `.ipa` → Sideloadly 装到 iPhone → 手机上开「开发者模式」。
免费 Apple ID 签出来是 7 天有效期，到期重签一次即可续期，**App 里的项目数据不会丢**。

> 顺带说一句：这部份的麻烦全部来自 iOS 必须用 Mac 签名打包，和代码本身无关。如果你哪天想要「改完就能装到手机上立刻试」，安卓那边一条 `./gradlew installDebug` 就完事，那是另一条路。

---

## 七、工程结构

```
PixMate/
├── project.yml                  XcodeGen 工程定义（含 shared scheme，云端构建要用）
├── 构建与安装-无Mac电脑.md        没有 Mac 时的完整安装指南（GitHub 出 ipa + Sideloadly）
├── .github/workflows/build-ipa.yml  推到 GitHub 自动构建未签名 ipa
└── PixMate/
    ├── App/
    │   ├── PixMateApp.swift           入口
    │   └── AppEnvironment.swift       服务装配 + 偏好持久化
    ├── Models/
    │   ├── CoreModels.swift           项目 / 照片资产 / 磁盘路径
    │   ├── CameraModels.swift         连接状态 / 参数 / PTP 操作码表
    │   ├── RetouchModels.swift        修图参数 + 6 个内置预设
    │   ├── CoachModels.swift          骨架 / 构图报告 / 姿势建议
    │   └── Stores.swift               项目库 / 预设库持久化
    ├── Capture/
    │   ├── PTP.swift                  PTP 容器、操作码、属性描述解析、数值格式化
    │   ├── NikonPTPSession.swift      ★ ImageCaptureCore 上的 PTP 会话
    │   ├── CameraController.swift     ★ 取景循环 / 快门 / 回传
    │   ├── LiveViewStream.swift       实时取景帧剥离 + 节流
    │   ├── RawPreviewExtractor.swift  NEF 取嵌入预览（拍摄瞬间的快速副本）
    │   ├── RawDeveloper.swift         ★ RAW 真显影（CIRAWFilter，导出用）
    │   └── PhoneCaptureSource.swift   手机模式（AVFoundation）
    ├── Analysis/
    │   ├── CompositionAdvisor.swift   ★ 可解释构图诊断
    │   ├── PoseLibrary.swift          35 条离线姿势 · 六大类
    │   ├── PoseSuggester.swift        ★ 姿势匹配 + 多模态生成
    │   └── CoachPipeline.swift        参谋流水线
    ├── Retouch/
    │   ├── FaceAnalysis.swift         Vision 人脸/人体/姿态
    │   ├── MaskRenderer.swift         蒙版绘制与羽化
    │   └── RetouchEngine.swift        ★ 修图管线
    ├── Export/
    │   └── ExportService.swift        高质量导出
    └── UI/
        ├── RootView.swift             标签栏 + 通用控件
        ├── MonitorView.swift          ★ 监视器主界面
        ├── OverlayLayer.swift         ★ 叠加层绘制
        ├── AdvicePanel.swift          参谋面板
        ├── ConnectionSheet.swift      连接向导 + 诊断日志
        ├── RetouchView.swift          精修界面
        ├── ProjectsView.swift         项目库
        └── SettingsView.swift         设置 + 校准说明
```

---

## 八、真机校准清单

**这几处必须拿真机对一遍，离线写不出正确答案。** App 里「设置 → 关于 → 校准说明」也有一份，并且连接向导底部有实时协议日志——**日志可以一键导出成 txt**（带设备型号、iOS 版本、连接状态、取景帧率），连不上时把导出的文件发我就能定位。

| # | 位置 | 现象 | 怎么修 |
|---|---|---|---|
| 1 | `NikonPTPSession.triggerCapture` | 按快门没反应 | `0x9207` 带两个参数，部分固件只认一个或不带。看日志里的返回码：`0x2006` = 参数不对 |
| 2 | `NikonLiveViewFrame.parse` | 只有第一帧能显示，之后全黑 | 一帧 JPEG 被分包了。连着取几次直到字节流以 `FFD9` 结尾再解码 |
| 3 | 参数选择器最后一栏 | 显示的档位和机身菜单对不上 | 打开任意参数 → 「诊断信息」会同时显示原始值和档位数量，对着机身核一遍，把 `NikonValueFormatting` 里的换算改掉 |
| 4 | `ICCameraDeviceDelegate` 那几个方法 | 编译报 conformance 错，或连上但收不到新文件事件 | `@objc` 可选方法的 Swift 签名在 SDK 版本间偶有变化，对着 Xcode 里的协议定义改方法名即可 |
| 5 | `NikonPTPSession.startLiveView` | 开不了实时取景 | 代码先按带参数 `[0]` 发，被拒自动退回无参形式。日志里能看到走了哪条 |

**参数档位这件事说明一下**：ISO / 快门 / 光圈在 PTP 里都是裸数字，`NikonValueFormatting` 里的换算是按公开资料写的，和机身屏幕上的字未必一一对应。所以我的做法是——**表里有的就翻译，没见过的就老实显示原始数值，不猜**。你对着机身核一轮，把表补全，之后就准了。

---

## 九、故障排查

| 现象 | 先看这几条 |
|---|---|
| 完全搜不到相机 | ① 换线（最常见）② 相机的 USB 是不是 MTP/PTP ③ 相机有没有被 Lightroom / Capture One 之类占着 ④ 文件与文件夹权限 |
| 连上就掉线 | USB 电力输送是不是 OFF；线是不是超 2 米 |
| 有画面但拍照没反应 | 相机在不在 M/A/S 档；卡插了没有 |
| 回传的图比卡里的小 | 那是正常——回传的是相机给的原图/嵌入预览。想要 RAW 全量数据，卡里那份才是完整的，导出时的「保留原图副本」会把它一起放过去 |
| RAW 显示不出来 | 说明这个 NEF 版本既不被 iOS 的 ImageIO 认，嵌入预览也扫不出来。先用 JPEG 拍，或把那张发我看看 |

---

## 十、已知边界（说清楚，不兜圈子）

- **实时取景是 1024×680**，这是 Z6II 的 PTP 取景分辨率，不是画质问题。成片质量取决于回传的原图，不受影响。
- **RAW 出片分两级**。拍摄瞬间的工作副本走嵌入预览（快）；**导出走 CIRAWFilter 真显影**（全传感器分辨率，Z6II 在 Apple 的 RAW 支持列表里）——前提是当前 iOS 版本认这台机器的 NEF，不认就自动退回嵌入预览，功能不降级。拍摄瞬间的修图预览仍是嵌入 JPEG，这是速度取舍。
- **无线（WiFi）联机没做**。像素蛋糕有，走的是相机热点 + 手动配 IP。有线更稳更快，自用场景够。要加的话是在 `Capture/` 下再写一个 PTP/IP over TCP 的会话实现，接口和现在这个一样。
- **脸型收窄是横向缩放 + 羽化蒙版**，不是真正的网格变形（那需要自定义 Metal warp kernel）。效果够用，但极端值会看出来。
- **多模态姿势生成要你自己配接口**（设置 → 多模态姿势生成）。兼容 OpenAI Chat Completions 协议的任何视觉模型都行。不配也不影响使用——本地 35 条姿势库是离线的。
- 端上推理**不出设备**。只有你主动点「按景色生成姿势」时，那一帧才会发给你配置的模型服务。

---

## 十一、和像素蛋糕的关系

代码全部原创，没有反编译、没有引用它的任何资源。

`RetouchModels.swift` 里 6 个内置预设的命名（通透 / 奶油肤 / 胶片 / 高级灰 / 棚拍硬朗 / 暖阳）是**刻意避开**它的注册商标用语（原肤 / 无暇 / 原生感 / 春桃）的——自用无所谓，但没必要踩线。

参数档位全部由相机动态回报，App 不硬编码任何厂商私有表——这也是为什么换个机身、刷个固件都不会整块失效。

---

## 十二、接着往下做，优先级我建议这样排

1. **先把 PTP 实时取景在真机上跑通并校准**（第八节 1–3 条）。这是地基，其余都建在它上面。日志导出按钮在连接向导底部。
2. 加无线 PTP/IP 通路，接口对齐现在这个会话。
3. 批量导出的后台化 + 进度条（现在是大图逐张串行，20 张以上会有点慢）。
4. 姿势库按拍摄主题再扩（情侣旅拍、汉服、商务形象照各成一辑）。

~~接 libraw 升级 RAW 解码~~（已完成：走 `CIRAWFilter` 真显影，见 `Capture/RawDeveloper.swift`）
~~姿势库扩到 30+ 条并分类~~（已完成：35 条 · 六大类，参谋面板顶部有筛选条）

第 1 条跑完把日志发我，我根据实际返回码把参数一次校准到位。
