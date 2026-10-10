import SwiftUI
import UIKit

// MARK: - 项目库

struct ProjectsView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var showingCreate = false
    @State private var newName = ""
    @State private var pendingDelete: ShootProject?

    var body: some View {
        NavigationStack {
            Group {
                if env.projects.projects.isEmpty {
                    EmptyHint(icon: "square.stack.3d.up.slash",
                              title: "还没有拍摄项目",
                              message: "建一个项目，联机拍到的照片会自动回传到里面")
                } else {
                    List {
                        ForEach(env.projects.projects) { project in
                            NavigationLink {
                                ProjectDetailView(projectID: project.id)
                                    .environmentObject(env)
                            } label: {
                                projectRow(project)
                            }
                            .listRowBackground(Color(white: 0.1))
                            .swipeActions {
                                Button(role: .destructive) {
                                    pendingDelete = project
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(white: 0.06))
            .navigationTitle("项目")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newName = "拍摄 \(Date().shortStamp)"
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .alert("新建项目", isPresented: $showingCreate) {
                TextField("项目名称", text: $newName)
                Button("取消", role: .cancel) {}
                Button("创建") {
                    let project = env.projects.createProject(name: newName)
                    env.activate(project.id)
                    env.flash("已创建「\(project.name)」并设为当前项目")
                }
            } message: {
                Text("创建后会立刻成为当前项目，联机拍摄的照片都进这里。")
            }
            .alert("删除项目？", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )) {
                Button("取消", role: .cancel) { pendingDelete = nil }
                Button("删除", role: .destructive) {
                    if let project = pendingDelete {
                        if env.activeProjectID == project.id { env.activate(nil) }
                        env.projects.delete(project.id)
                    }
                    pendingDelete = nil
                }
            } message: {
                Text("项目里的照片和原图会一并从磁盘删除，这一步不可撤销。")
            }
        }
    }

    private func projectRow(_ project: ShootProject) -> some View {
        HStack(spacing: 12) {
            coverThumb(project)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if env.activeProjectID == project.id {
                        Text("当前")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.24, green: 0.86, blue: 0.62), in: Capsule())
                    }
                }
                Text("\(project.count) 张 · \(project.createdAt.shortStamp)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if project.pickedCount > 0 {
                    Text("已标记 \(project.pickedCount) 张")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.24, green: 0.86, blue: 0.62))
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func coverThumb(_ project: ShootProject) -> some View {
        if let cover = project.coverAsset {
            LocalImage(url: env.projects.workingURL(for: cover, in: project.id))
        } else {
            ZStack {
                Color.white.opacity(0.06)
                Image(systemName: "photo.on.rectangle.angled")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 项目详情

struct ProjectDetailView: View {
    let projectID: UUID

    @EnvironmentObject private var env: AppEnvironment
    @State private var selection: Set<UUID> = []
    @State private var isSelecting = false
    @State private var showingExportOptions = false

    private var project: ShootProject? { env.projects.project(projectID) }

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 6)]

    var body: some View {
        Group {
            if let project {
                VStack(spacing: 0) {
                    summaryBar(project)
                    Divider().overlay(Color.white.opacity(0.08))

                    if project.assets.isEmpty {
                        Spacer()
                        EmptyHint(icon: "camera.metering.unknown",
                                  title: "这个项目还没有照片",
                                  message: "把它设为当前项目，然后回到拍摄页联机拍摄")
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(project.assets) { asset in
                                    AssetCell(asset: asset,
                                              projectID: project.id,
                                              isSelected: selection.contains(asset.id),
                                              isSelecting: isSelecting)
                                        .onTapGesture {
                                            if isSelecting {
                                                toggle(asset.id)
                                            }
                                        }
                                }
                            }
                            .padding(6)
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.08))
                    actionBar(project)
                }
            } else {
                EmptyHint(icon: "questionmark.folder", title: "项目不存在")
            }
        }
        .background(Color(white: 0.06))
        .navigationTitle(project?.name ?? "项目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isSelecting ? "完成" : "选择") {
                    isSelecting.toggle()
                    if !isSelecting { selection.removeAll() }
                }
                .disabled((project?.assets.isEmpty ?? true))
            }
        }
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsSheet()
                .environmentObject(env)
        }
    }

    // MARK: 顶部概况

    private func summaryBar(_ project: ShootProject) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(project.count) 张照片")
                    .font(.subheadline.weight(.medium))
                let rawCount = project.assets.filter(\.isRaw).count
                Text(rawCount > 0 ? "其中 \(rawCount) 张 RAW" : "全部为 JPEG")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if env.activeProjectID != project.id {
                Button {
                    env.activate(project.id)
                    env.flash("已切换到「\(project.name)」")
                } label: {
                    Text("设为当前")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.24, green: 0.86, blue: 0.62))
            } else {
                Label("当前项目", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.24, green: 0.86, blue: 0.62))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 底部操作

    private func actionBar(_ project: ShootProject) -> some View {
        HStack(spacing: 10) {
            if isSelecting {
                Button("全选") { selection = Set(project.assets.map(\.id)) }
                    .font(.caption)
                Button("清空") { selection.removeAll() }
                    .font(.caption)
                Spacer()
                Text("已选 \(selection.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    Section("批量套用预设") {
                        ForEach(env.presets.presets) { preset in
                            Button(preset.name) {
                                applyPreset(preset, in: project)
                            }
                        }
                    }
                } label: {
                    Label("批量预设", systemImage: "wand.and.stars")
                        .font(.caption)
                }
                Spacer()
            }

            Button {
                export(project)
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(red: 0.24, green: 0.86, blue: 0.62), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(env.exporter.isExporting)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 动作

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func applyPreset(_ preset: RetouchPreset, in project: ShootProject) {
        let targets = isSelecting && !selection.isEmpty
            ? project.assets.filter { selection.contains($0.id) }
            : project.assets
        for asset in targets {
            var updated = asset
            updated.retouch = preset.params
            env.projects.updateAsset(updated, in: project.id)
        }
        env.flash("已把「\(preset.name)」套用到 \(targets.count) 张")
    }

    private func export(_ project: ShootProject) {
        let targets = isSelecting && !selection.isEmpty
            ? project.assets.filter { selection.contains($0.id) }
            : project.assets
        guard !targets.isEmpty else { return }
        Task {
            _ = await env.exporter.export(assets: targets,
                                          project: project,
                                          settings: env.exportSettings,
                                          engine: env.retouch,
                                          store: env.projects)
            env.flash(env.exporter.lastMessage ?? "导出完成")
        }
    }
}

// MARK: - 照片格

struct AssetCell: View {
    let asset: PhotoAsset
    let projectID: UUID
    let isSelected: Bool
    let isSelecting: Bool

    @EnvironmentObject private var env: AppEnvironment
    @State private var showingDetail = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LocalImage(url: env.projects.workingURL(for: asset, in: projectID))
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isSelected ? Color(red: 0.24, green: 0.86, blue: 0.62)
                                                 : Color.white.opacity(0.06),
                                      lineWidth: isSelected ? 2.5 : 1)
                )
                .onTapGesture {
                    if !isSelecting { showingDetail = true }
                }

            HStack(spacing: 4) {
                if asset.isRaw {
                    Text("RAW")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                }
                if asset.retouch.isEdited {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 9))
                        .padding(3)
                        .background(.black.opacity(0.6), in: Circle())
                        .foregroundStyle(Color(red: 0.24, green: 0.86, blue: 0.62))
                }
            }
            .padding(5)

            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? Color(red: 0.24, green: 0.86, blue: 0.62) : .white.opacity(0.7))
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .sheet(isPresented: $showingDetail) {
            NavigationStack {
                RetouchView(asset: asset)
                    .environmentObject(env)
            }
        }
    }
}

// MARK: - 本地图片（异步加载，不卡列表）

struct LocalImage: View {
    let url: URL
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Color.white.opacity(0.05)
                    ProgressView().controlSize(.mini)
                }
            }
        }
        .task(id: url) {
            let loaded = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: url.path)
            }.value
            await MainActor.run { self.image = loaded }
        }
    }
}
