import SwiftUI
import UIKit

// MARK: - 监视器主界面

struct MonitorView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var editingProperty: CameraProperty?
    @State private var showingConnection = false
    @State private var retouchTarget: PhotoAsset?
    @State private var showingAdviceSheet = false

    private var isWide: Bool { sizeClass == .regular }

    /// env.coach 是 let 常量（CoachPipeline 是引用类型），
    /// 不能直接对它取 $env.coach.selectedPose —— 那要求 coach 可被替换。
    /// 这里手工构造一个指向其内部属性的绑定。
    private var selectedPoseBinding: Binding<PoseSuggestion?> {
        Binding(
            get: { env.coach.selectedPose },
            set: { env.coach.selectedPose = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusStrip(showingConnection: $showingConnection)

            HStack(spacing: 0) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isWide {
                    Divider().overlay(Color.white.opacity(0.08))
                    AdvicePanel(coach: env.coach, selectedPose: selectedPoseBinding)
                        .frame(width: 320)
                }
            }

            CaptureBar(editingProperty: $editingProperty,
                       showingAdvice: $showingAdviceSheet,
                       retouchTarget: $retouchTarget)
        }
        .background(Color.black.ignoresSafeArea(edges: .top))
        .onChange(of: env.camera.link) { _, newValue in
            if newValue.isTethering, !env.camera.session.isLiveViewRunning {
                env.camera.startLiveView()
            }
        }
        .sheet(item: $editingProperty) { property in
            PropertyPickerSheet(property: property) { newValue in
                Task {
                    if let current = env.camera.properties.first(where: { $0.id == property.id }) {
                        await env.camera.setProperty(current, toValue: newValue)
                    }
                }
            }
        }
        .sheet(isPresented: $showingConnection) {
            ConnectionSheet()
                .environmentObject(env)
        }
        .sheet(isPresented: $showingAdviceSheet) {
            NavigationStack {
                AdvicePanel(coach: env.coach, selectedPose: selectedPoseBinding)
                    .environmentObject(env)
                    .navigationTitle("实时参谋")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $retouchTarget) { asset in
            NavigationStack {
                RetouchView(asset: asset)
                    .environmentObject(env)
            }
        }
    }

    // MARK: 取景画面

    private var preview: some View {
        GeometryReader { geo in
            let fitted = env.camera.frameSize.fitted(in: geo.size)

            ZStack {
                Color.black

                if let frame = env.camera.frame {
                    Image(uiImage: frame)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                } else {
                    idlePlaceholder
                }

                // 叠加层尺寸和画面完全一致，所以归一化坐标可以直接用
                OverlayLayer(options: env.overlay,
                             report: env.coach.report,
                             people: env.coach.people,
                             faces: env.coach.faces,
                             targetPose: env.coach.selectedPose)
                    .frame(width: fitted.width, height: fitted.height)

                if env.camera.isReleasing || env.camera.isDownloading {
                    busyOverlay
                }

                VStack {
                    HStack {
                        Spacer()
                        lastCapturedBadge
                    }
                    Spacer()
                }
                .padding(12)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var idlePlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "cable.connector.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("还没有画面")
                .font(.headline)
            Text(connectionHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showingConnection = true
            } label: {
                Label("连接尼康相机", systemImage: "link")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.24, green: 0.86, blue: 0.62))
        }
    }

    private var connectionHint: String {
        switch env.camera.link {
        case .disconnected:
            return "先用 USB-C 数据线把 Z6II 接到 iPhone / iPad 上"
        case .connecting(let text):
            return text
        case .failed(let text):
            return text
        default:
            return ""
        }
    }

    private var busyOverlay: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(env.camera.isDownloading ? "正在回传原图…" : "正在拍摄…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var lastCapturedBadge: some View {
        Group {
            if let asset = env.lastCaptured,
               let project = env.activeProject,
               let image = UIImage(contentsOfFile: env.projects.workingURL(for: asset, in: project.id).path) {
                Button {
                    retouchTarget = asset
                } label: {
                    VStack(spacing: 4) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.white.opacity(0.25), lineWidth: 1))
                        Text("精修")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 54, height: 54)
            }
        }
    }
}

// MARK: - 状态条

struct StatusStrip: View {
    @EnvironmentObject private var env: AppEnvironment
    @Binding var showingConnection: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                showingConnection = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: env.camera.link.symbolName)
                        .font(.caption)
                    Text(env.camera.link.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                .foregroundStyle(linkColor)
            }
            .buttonStyle(.plain)

            if env.camera.link.isTethering {
                Label(String(format: "%.1f fps", env.camera.liveViewFPS),
                      systemImage: "speedometer")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let project = env.activeProject {
                Text(project.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(project.count) 张")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            } else {
                Text("未选择项目")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(white: 0.08))
    }

    private var linkColor: Color {
        switch env.camera.link {
        case .wired, .wireless: return Color(red: 0.24, green: 0.86, blue: 0.62)
        case .phone:            return Color(red: 0.55, green: 0.78, blue: 1.0)
        case .failed:           return Color(red: 1.0, green: 0.55, blue: 0.35)
        case .connecting:       return Color(red: 0.98, green: 0.86, blue: 0.42)
        case .disconnected:     return .secondary
        }
    }
}

// MARK: - 拍摄控制条

struct CaptureBar: View {
    @EnvironmentObject private var env: AppEnvironment
    @Binding var editingProperty: CameraProperty?
    @Binding var showingAdvice: Bool
    @Binding var retouchTarget: PhotoAsset?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var presetsExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if env.camera.link.isTethering, !env.camera.primaryProperties.isEmpty {
                propertyChips
            }
            if !env.camera.link.isTethering {
                quickConnectRow
            }
            Divider().overlay(Color.white.opacity(0.08))
            controls
        }
        .background(Color(white: 0.07))
    }

    // MARK: 参数快捷条

    private var propertyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(env.camera.primaryProperties) { property in
                    Button {
                        editingProperty = property
                    } label: {
                        VStack(spacing: 1) {
                            Text(property.name)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text(property.currentLabel)
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(property.isWritable ? .primary : .secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: 未连接时的快捷入口

    private var quickConnectRow: some View {
        HStack(spacing: 10) {
            switch env.camera.link {
            case .disconnected, .failed:
                Button {
                    env.camera.connectWired()
                } label: {
                    Label("搜索相机", systemImage: "magnifyingglass")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.24, green: 0.86, blue: 0.62))

                Button {
                    env.startPhoneMode()
                } label: {
                    Label("手机模式", systemImage: "iphone")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
            case .connecting(let text):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(text).font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            case .phone:
                Label("手机模式取景中", systemImage: "iphone")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
                Spacer()
                Button("退出") { env.stopPhoneMode() }
                    .font(.caption)
            default:
                EmptyView()
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: 主控制

    private var controls: some View {
        HStack(alignment: .center, spacing: 14) {
            // 左：预设
            Menu {
                Section("套用到整个项目") {
                    ForEach(env.presets.presets) { preset in
                        Button(preset.name) {
                            env.applyPresetToProject(preset)
                        }
                    }
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 17))
                    Text("预设")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
                .frame(width: 52)
            }

            Spacer()

            // 中：快门
            shutterButton

            Spacer()

            // 右：叠加层 + 参谋
            VStack(spacing: 3) {
                Menu {
                    Toggle("三分线", isOn: $env.overlay.showThirds)
                    Toggle("水平参考线", isOn: $env.overlay.showHorizon)
                    Toggle("人体骨架", isOn: $env.overlay.showSkeleton)
                    Toggle("姿势幽灵", isOn: $env.overlay.showPoseGhost)
                    Toggle("人脸框", isOn: $env.overlay.showFaceBoxes)
                    Toggle("建议标记", isOn: $env.overlay.showAdvice)
                } label: {
                    Image(systemName: "square.on.square.dashed")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .frame(width: 52)
                }

                if sizeClass == .compact {
                    Button {
                        showingAdvice = true
                    } label: {
                        Text("参谋")
                            .font(.system(size: 9))
                            .foregroundStyle(env.coach.report.topIssues.isEmpty ? .secondary
                                             : Color(red: 0.98, green: 0.86, blue: 0.42))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("叠加")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var shutterButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await env.camera.release() }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                    .frame(width: 68, height: 68)
                Circle()
                    .fill(canShoot ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 56, height: 56)
                if env.camera.isReleasing {
                    ProgressView().tint(.black)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canShoot)
        .opacity(canShoot ? 1 : 0.5)
    }

    private var canShoot: Bool {
        (env.camera.link.isTethering || env.camera.link == .phone)
            && !env.camera.isReleasing
            && env.activeProjectID != nil
    }
}

// MARK: - 参数选择
//
// 档位全部由相机回报，App 不硬编码 —— 换个机身、刷个固件都不会失效。

struct PropertyPickerSheet: View {
    let property: CameraProperty
    let onSelect: (UInt64) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !property.isWritable {
                    Section {
                        Text("这一项在机身上调整，App 只读取")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("可选档位（由相机回报）") {
                    ForEach(Array(zip(property.allowedValues, property.allowedLabels)), id: \.0) { value, label in
                        Button {
                            onSelect(value)
                            dismiss()
                        } label: {
                            HStack {
                                Text(label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if value == property.currentValue {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color(red: 0.24, green: 0.86, blue: 0.62))
                                }
                            }
                        }
                        .disabled(!property.isWritable)
                    }
                }

                Section("诊断信息") {
                    LabeledContent("属性码", value: "0x\(String(property.id, radix: 16, uppercase: true))")
                    LabeledContent("原始当前值", value: "\(property.currentValue)")
                    LabeledContent("档位数量", value: "\(property.allowedValues.count)")
                }
            }
            .navigationTitle(property.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
