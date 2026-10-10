import SwiftUI
import UIKit

// MARK: - 精修界面

struct RetouchView: View {
    let asset: PhotoAsset

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var params: RetouchParams
    @State private var tab: EditTab = .portrait
    @State private var original: UIImage?
    @State private var preview: UIImage?
    @State private var analysis: RetouchAnalysis?
    @State private var showingOriginal = false
    @State private var isRendering = false
    @State private var renderTask: Task<Void, Never>?
    @State private var showingSavePreset = false
    @State private var presetName = ""
    @State private var didExport = false

    init(asset: PhotoAsset) {
        self.asset = asset
        _params = State(initialValue: asset.retouch)
    }

    /// 预览用中等分辨率——改参数要跟手，导出时才跑全分辨率
    private let previewMaxDimension: CGFloat = 1500

    var body: some View {
        VStack(spacing: 0) {
            imageArea
            Divider().overlay(Color.white.opacity(0.08))
            presetStrip
            Divider().overlay(Color.white.opacity(0.08))
            editor
            Divider().overlay(Color.white.opacity(0.08))
            toolbar
        }
        .background(Color(white: 0.06))
        .navigationTitle(asset.isRaw ? "精修 · RAW" : "精修")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") {
                    renderTask?.cancel()
                    dismiss()
                }
            }
        }
        .onAppear(perform: prepare)
        .onDisappear { renderTask?.cancel() }
        .onChange(of: params) { _, _ in scheduleRender() }
        .alert("保存为预设", isPresented: $showingSavePreset) {
            TextField("预设名称", text: $presetName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                env.presets.addUserPreset(name: name, params: params)
                presetName = ""
                env.flash("已保存预设「\(name)」")
            }
        }
    }

    // MARK: 画面

    private var imageArea: some View {
        ZStack {
            Color.black

            if let image = showingOriginal ? original : preview {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }

            if isRendering {
                VStack {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("渲染中").font(.caption2)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(10)
            }

            VStack {
                Spacer()
                HStack {
                    if showingOriginal {
                        Text("原图")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
                    Spacer()
                    if let analysis, analysis.faceCount > 0 {
                        Label("\(analysis.faceCount) 张脸", systemImage: "face.smiling")
                            .font(.caption2)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                }
                .padding(10)
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        // 按住看原图 —— 修图软件最基本的手势
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in showingOriginal = true }
                .onEnded { _ in showingOriginal = false }
        )
    }

    // MARK: 预设条

    private var presetStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(env.presets.presets) { preset in
                    Button {
                        params = preset.params
                    } label: {
                        VStack(spacing: 2) {
                            Text(preset.name)
                                .font(.caption.weight(.medium))
                            if !preset.isBuiltIn {
                                Text("自建")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !preset.isBuiltIn {
                            Button(role: .destructive) {
                                env.presets.delete(preset.id)
                            } label: {
                                Label("删除预设", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: 编辑区

    @ViewBuilder
    private var editor: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(EditTab.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(tab.controls, id: \.title) { control in
                        ParameterSlider(title: control.title,
                                        value: binding(control.keyPath),
                                        range: control.range,
                                        formatter: control.formatter)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(height: 232)
    }

    private func binding(_ keyPath: WritableKeyPath<RetouchParams, Double>) -> Binding<Double> {
        Binding(
            get: { params[keyPath: keyPath] },
            set: { params[keyPath: keyPath] = $0 }
        )
    }

    // MARK: 底部工具条

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                params.resetAll()
                env.flash("已重置全部调整")
            } label: {
                Label("重置", systemImage: "arrow.uturn.backward")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                showingSavePreset = true
            } label: {
                Label("存为预设", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                save()
            } label: {
                Text("保存")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                save()
                Task { await exportCurrent() }
            } label: {
                Text(didExport ? "已导出" : "导出")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.24, green: 0.86, blue: 0.62), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 逻辑

    private func prepare() {
        guard let projectID = env.activeProjectID else { return }
        let url = env.projects.workingURL(for: asset, in: projectID)
        guard let image = UIImage(contentsOfFile: url.path) else { return }

        let small = image.scaled(toMaxDimension: previewMaxDimension)
        original = small

        let analysis = env.retouch.analyze(small, detectPerson: params.needsSubjectMask)
        self.analysis = analysis
        preview = env.retouch.render(analysis, params: params)
    }

    /// 滑块连续变化时去抖，只渲染最后一帧
    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled, let analysis else { return }

            isRendering = true
            let result = env.retouch.render(analysis, params: params)
            if !Task.isCancelled {
                preview = result
            }
            isRendering = false
        }
    }

    private func save() {
        guard let projectID = env.activeProjectID else { return }
        var updated = asset
        updated.retouch = params
        env.projects.updateAsset(updated, in: projectID)
    }

    private func exportCurrent() async {
        guard let project = env.activeProject else { return }
        var updated = asset
        updated.retouch = params
        let urls = await env.exporter.export(assets: [updated],
                                             project: project,
                                             settings: env.exportSettings,
                                             engine: env.retouch,
                                             store: env.projects)
        if !urls.isEmpty {
            didExport = true
            env.flash(env.exporter.lastMessage ?? "导出完成")
        }
    }
}

// MARK: - 编辑分组

enum EditTab: String, CaseIterable, Identifiable {
    case portrait, tone, color, detail, background

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portrait:   return "人像"
        case .tone:       return "影调"
        case .color:      return "色彩"
        case .detail:     return "细节"
        case .background: return "背景"
        }
    }

    struct Control {
        let title: String
        let keyPath: WritableKeyPath<RetouchParams, Double>
        let range: ClosedRange<Double>
        let formatter: (Double) -> String

        init(_ title: String,
             _ keyPath: WritableKeyPath<RetouchParams, Double>,
             range: ClosedRange<Double> = -1...1,
             formatter: ((Double) -> String)? = nil) {
            self.title = title
            self.keyPath = keyPath
            self.range = range
            self.formatter = formatter ?? {
                abs($0) < 0.005 ? "0" : String(format: "%+.0f", $0 * 100)
            }
        }
    }

    var controls: [Control] {
        switch self {
        case .portrait:
            return [
                Control("磨皮", \RetouchParams.skinSmoothing, range: 0...1),
                Control("祛痘 / 瑕疵", \RetouchParams.blemishRemoval, range: 0...1),
                Control("肤色冷暖", \RetouchParams.skinTone),
                Control("肤色提亮", \RetouchParams.skinBrightness),
                Control("脸型收窄", \RetouchParams.faceSlim, range: 0...1),
                Control("眼神光", \RetouchParams.eyeEnhance, range: 0...1),
                Control("牙齿美白", \RetouchParams.teethWhiten, range: 0...1),
                Control("唇色", \RetouchParams.lipEnhance, range: 0...1)
            ]
        case .tone:
            return [
                Control("曝光", \RetouchParams.exposure),
                Control("对比度", \RetouchParams.contrast),
                Control("高光", \RetouchParams.highlights),
                Control("阴影", \RetouchParams.shadows),
                Control("白色", \RetouchParams.whites),
                Control("黑色", \RetouchParams.blacks)
            ]
        case .color:
            return [
                Control("色温", \RetouchParams.temperature),
                Control("色调", \RetouchParams.tint),
                Control("自然饱和度", \RetouchParams.vibrance),
                Control("饱和度", \RetouchParams.saturation),
                Control("色相", \RetouchParams.hueShift)
            ]
        case .detail:
            return [
                Control("清晰度", \RetouchParams.clarity),
                Control("锐化", \RetouchParams.sharpen, range: 0...1),
                Control("降噪", \RetouchParams.denoise, range: 0...1),
                Control("暗角", \RetouchParams.vignette, range: 0...1),
                Control("颗粒", \RetouchParams.grain, range: 0...1)
            ]
        case .background:
            return [
                Control("背景虚化", \RetouchParams.backgroundBlur, range: 0...1),
                Control("背景压暗", \RetouchParams.backgroundDarken, range: 0...1)
            ]
        }
    }
}
