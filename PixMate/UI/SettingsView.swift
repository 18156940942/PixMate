import SwiftUI

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var showingConnection = false
    @State private var keyVisible = false

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                overlaySection
                visionSection
                exportSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Color(white: 0.06))
            .navigationTitle("设置")
            .sheet(isPresented: $showingConnection) {
                ConnectionSheet().environmentObject(env)
            }
            .onDisappear { env.persist() }
        }
    }

    // MARK: 连接

    private var connectionSection: some View {
        Section {
            Button {
                showingConnection = true
            } label: {
                HStack {
                    Label("连接与相机设置", systemImage: "cable.connector")
                    Spacer()
                    Text(env.camera.link.title)
                        .font(.caption)
                        .foregroundStyle(linkColor)
                }
            }

            if env.camera.link.isTethering {
                Button(role: .destructive) {
                    env.camera.disconnect()
                } label: {
                    Label("断开相机", systemImage: "xmark.circle")
                }
            }
        } header: {
            Text("相机")
        } footer: {
            Text("Z6II 走的是 USB + PTP 联机，和像素蛋糕是同一条路。机身端要先设好：USB → MTP/PTP、USB 电力输送 → OFF、插好存储卡。")
        }
    }

    private var linkColor: Color {
        env.camera.link.isTethering ? Color(red: 0.24, green: 0.86, blue: 0.62) : .secondary
    }

    // MARK: 叠加层

    private var overlaySection: some View {
        Section("取景叠加层") {
            Toggle("三分线", isOn: $env.overlay.showThirds)
            Toggle("水平参考线", isOn: $env.overlay.showHorizon)
            Toggle("人体骨架", isOn: $env.overlay.showSkeleton)
            Toggle("姿势幽灵", isOn: $env.overlay.showPoseGhost)
            Toggle("人脸框", isOn: $env.overlay.showFaceBoxes)
            Toggle("建议标记", isOn: $env.overlay.showAdvice)
        }
        .onChange(of: env.overlay) { _, _ in env.persist() }
    }

    // MARK: 多模态

    private var visionSection: some View {
        Section {
            TextField("接口地址", text: $env.visionEndpoint)
                .font(.caption.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            HStack {
                if keyVisible {
                    TextField("API Key", text: $env.visionAPIKey)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField("API Key", text: $env.visionAPIKey)
                        .font(.caption.monospaced())
                }
                Button {
                    keyVisible.toggle()
                } label: {
                    Image(systemName: keyVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextField("模型名", text: $env.visionModel)
                .font(.caption.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button {
                env.applyVisionSettings()
                env.flash(env.isVisionConfigured ? "已启用按景色生成姿势" : "已关闭多模态增强")
            } label: {
                Label(env.isVisionConfigured ? "重新应用" : "启用", systemImage: "sparkles")
            }
        } header: {
            Text("多模态姿势生成（可选）")
        } footer: {
            Text("填了才启用。任何兼容 OpenAI Chat Completions 协议的视觉模型都能用：把取景画面发给它，让它按画面里实际的背景、光线、空间给你摆姿建议。\n不填也完全能用——本地姿势库是离线的，零延迟。")
        }
    }

    // MARK: 导出

    private var exportSection: some View {
        Section {
            Picker("格式", selection: $env.exportSettings.format) {
                ForEach(ExportFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }

            if env.exportSettings.format.isLossy {
                ParameterSlider(title: "压缩质量",
                                value: $env.exportSettings.quality,
                                range: 0.6...1.0,
                                formatter: { String(format: "%.0f%%", $0 * 100) })
            }

            Picker("色彩空间", selection: $env.exportSettings.colorSpace) {
                ForEach(ExportColorSpace.allCases, id: \.self) { space in
                    Text(space.displayName).tag(space)
                }
            }

            Picker("尺寸", selection: Binding(
                get: { env.exportSettings.resizeLongEdge ?? 0 },
                set: { env.exportSettings.resizeLongEdge = $0 == 0 ? nil : $0 }
            )) {
                Text("原始尺寸（不降采样）").tag(0)
                Text("长边 4096 px").tag(4096)
                Text("长边 3000 px").tag(3000)
                Text("长边 2048 px").tag(2048)
            }

            Toggle("RAW 真解码出片", isOn: $env.exportSettings.useRawDevelopment)
            Toggle("同时保留相机原图副本", isOn: $env.exportSettings.includeOriginalCopy)
            Toggle("导出后存入系统相册", isOn: $env.exportSettings.saveToPhotoLibrary)

            TextField("文件名前缀", text: $env.exportSettings.filenamePrefix)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("导出")
        } footer: {
            Text("默认「原始尺寸 + Display P3 + 98% 质量」，就是从 RAW 出片的标准配置。「RAW 真解码」用 CIRAWFilter 对 NEF 做全传感器分辨率显影，画质比机内预览高一档，慢一点但值得；系统不认的机型会自动退回嵌入预览。缩略图会内嵌进文件，方便图库秒加载。")
        }
        .onChange(of: env.exportSettings) { _, _ in env.persist() }
    }

    // MARK: 关于

    private var aboutSection: some View {
        Section {
            LabeledContent("版本", value: "1.1")
            LabeledContent("联机方式", value: "USB / PTP")
            LabeledContent("取景分辨率", value: "1024 × 680（Z6II）")
            LabeledContent("构图与姿势", value: "端上 Vision 推理")
            LabeledContent("姿势库", value: "35 条 · 六大类离线")
            NavigationLink("校准说明") {
                CalibrationNotesView()
            }
        } header: {
            Text("关于")
        } footer: {
            Text("所有推理都在设备上完成，取景画面不会离开手机。只有你主动点「按景色生成姿势」时，那一帧才会发给你配置的模型服务。")
        }
    }
}

// MARK: - 校准说明

struct CalibrationNotesView: View {
    var body: some View {
        List {
            Section {
                Text("这个工程里有几处必须拿真机对一遍，我没法在没有 Z6II 的情况下替你蒙对。跑通联机时对着下面这几条核一下。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            note("1 · 快门命令的入参",
                 "代码里 0x9207 带两个参数（存储卡 ID + 格式），部分固件只认一个参数甚至不带参数。触发快门没反应时，看诊断日志里相机返回的错误码：0x2006 是参数不对。")

            note("2 · 实时取景帧的头部长度",
                 "0x9203 返回的数据前面有一段厂商头。代码没有硬砍固定字节，而是直接在字节流里找 JPEG 的 FFD8FF 和末尾 FFD9，所以固件换版本也不会突然黑屏。若还是只有第一帧能显示，八成是分包问题，看第 3 条。")

            note("3 · 实时取景的分包",
                 "部分固件一帧 JPEG 会分多次返回。现象是「只有第一帧能显示，之后全黑」。解决方式是连着取几次直到字节流以 FFD9 结尾再解码。")

            note("4 · 参数档位的显示值",
                 "ISO / 快门 / 光圈在 PTP 里都是裸数字，格式化和机身菜单上的字未必一一对应。打开任意一个参数选择器，最后一栏「诊断信息」会同时显示原始值和档位数量，对着机身屏幕核一遍即可。")

            note("5 · 代理方法的签名",
                 "ICCameraDeviceDelegate / ICDeviceDelegate 那几个 @objc 可选方法的 Swift 签名在 SDK 版本间偶有变化。若编译报 conformance 错误，或连上但收不到新文件事件，对着 Xcode 里协议定义改一下方法名即可。")

            note("6 · 实时取景的入参形式",
                 "代码先按带参数（[0]）发 StartLiveView，被拒就自动退回无参形式。日志里能看到走了哪条。")
        }
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.06))
        .navigationTitle("校准说明")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func note(_ title: String, _ body: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - 导出选项

struct ExportOptionsSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("当前导出配置") {
                    LabeledContent("格式", value: env.exportSettings.format.displayName)
                    LabeledContent("质量", value: String(format: "%.0f%%", env.exportSettings.quality * 100))
                    LabeledContent("色彩空间", value: env.exportSettings.colorSpace.displayName)
                    LabeledContent("尺寸", value: env.exportSettings.resizeLabel)
                    LabeledContent("保留原图", value: env.exportSettings.includeOriginalCopy ? "是" : "否")
                }

                Section {
                    Text("要改配置，去「设置 → 导出」。这里只是确认一下当前用的是哪套。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("导出设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("好") { dismiss() }
                }
            }
        }
    }
}
