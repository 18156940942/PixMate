import SwiftUI
import UIKit

// MARK: - 连接向导
//
// 像素蛋糕在 Z6II 上走的那条路，机身侧要设的东西一模一样。
// 这里把四步做成可对着做的清单，连不上时还有诊断日志。

struct ConnectionSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var showTrace = false
    @State private var traceExport: TraceExport?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: env.camera.link.symbolName)
                            .font(.title3)
                            .foregroundStyle(statusColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(env.camera.link.title)
                                .font(.subheadline.weight(.semibold))
                            if let detail = env.camera.link.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if env.camera.link.isTethering {
                            Text(String(format: "%.1f fps", env.camera.liveViewFPS))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        env.camera.connectWired()
                    } label: {
                        Label("开始搜索相机", systemImage: "magnifyingglass")
                    }
                    .disabled(env.camera.link.isTethering)

                    if env.camera.link.isTethering {
                        Button {
                            env.camera.startLiveView()
                        } label: {
                            Label("开启实时取景", systemImage: "play.rectangle")
                        }
                        .disabled(env.camera.session.isLiveViewRunning)

                        Button(role: .destructive) {
                            env.camera.disconnect()
                        } label: {
                            Label("断开连接", systemImage: "xmark.circle")
                        }
                    }
                }

                Section {
                    if env.camera.link == .phone {
                        Button(role: .destructive) {
                            env.stopPhoneMode()
                        } label: {
                            Label("退出手机模式", systemImage: "iphone.slash")
                        }
                    } else {
                        Button {
                            env.startPhoneMode()
                        } label: {
                            Label("改用手机模式拍摄", systemImage: "iphone")
                        }
                        .disabled(env.camera.link.isTethering)
                    }
                } header: {
                    Text("手机模式")
                } footer: {
                    Text("不联机时，直接用手机镜头取景拍摄。构图诊断、姿势建议、精修导出一样都在——只是画质取决于手机。")
                }

                Section("第一步 · 相机端设置（Z6II）") {
                    StepRow(index: 1,
                            title: "机身内插好存储卡",
                            detail: "没有卡，相机不会把拍到的原图交给手机")
                    StepRow(index: 2,
                            title: "设定菜单 → USB → MTP/PTP",
                            detail: "固件 1.50 以上才有这个菜单项。千万别选「iPhone」——那是给尼康自家 NX MobileAir 用的，会把相机的网络功能全关掉")
                    StepRow(index: 3,
                            title: "设定菜单 → USB 电力输送 → OFF",
                            detail: "手机不是电脑，边给相机供电边传数据会掉线")
                    StepRow(index: 4,
                            title: "关闭飞行模式，模式转盘拨到 M / A / S",
                            detail: "机身在播放模式或视频模式下，实时取景命令会被拒")
                }

                Section("第二步 · 连手机") {
                    StepRow(index: 1,
                            title: "用 USB-C 数据线直连",
                            detail: "线长不超过 2 米。有些线只供电不传数据，必须用带数据传输的线（尼康原装 UC-E24 / UC-E25 一类）")
                    StepRow(index: 2,
                            title: "插上后选「允许」访问相机",
                            detail: "系统会弹「要允许此 App 访问相机吗」；如果误点了不允许，去 设置 → 隐私与安全性 → 文件与文件夹 里重新打开")
                    StepRow(index: 3,
                            title: "回来看取景画面",
                            detail: "连上后 App 会自动开启实时取景；要拍就按下面那个大圆钮")
                }

                Section("如果连不上") {
                    BulletRow(text: "换一根数据线重试——这是最常见的原因")
                    BulletRow(text: "确认相机没被其他软件占用（Lightroom、Captur One 等先退出）")
                    BulletRow(text: "iPhone / iPad 的「文件与文件夹」权限是否给了本 App")
                    BulletRow(text: "相机重启一次，再重新插线")
                    BulletRow(text: "Z6II 的实时取景分辨率为 1024×680，画面不清晰是正常的，它只是取景预览")
                }

                Section {
                    DisclosureGroup("协议交互日志", isExpanded: $showTrace) {
                        if env.camera.session.trace.isEmpty {
                            Text("暂无记录")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 3) {
                                    ForEach(Array(env.camera.session.trace.suffix(120).enumerated()), id: \.offset) { _, line in
                                        Text(line)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(maxHeight: 220)

                            Button {
                                traceExport = exportTrace()
                            } label: {
                                Label("导出诊断日志", systemImage: "square.and.arrow.up")
                                    .font(.footnote)
                            }
                        }
                    }
                } header: {
                    Text("诊断")
                } footer: {
                    Text("连不上相机时把这段日志发我，就能定位是卡在哪一步。导出会带上设备与连接状态信息，方便对照。")
                }
                .sheet(item: $traceExport) { export in
                    ShareSheet(items: [export.url])
                        .ignoresSafeArea()
                }
            }
            .navigationTitle("连接相机")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var statusColor: Color {
        switch env.camera.link {
        case .wired, .wireless: return Color(red: 0.24, green: 0.86, blue: 0.62)
        case .phone:            return Color(red: 0.55, green: 0.78, blue: 1.0)
        case .failed:           return Color(red: 1.0, green: 0.55, blue: 0.35)
        case .connecting:       return Color(red: 0.98, green: 0.86, blue: 0.42)
        case .disconnected:     return .secondary
        }
    }

    // MARK: 日志导出

    /// 把协议日志连同设备信息写成临时 txt，走系统分享面板发出去
    private func exportTrace() -> TraceExport? {
        let device = UIDevice.current
        var lines: [String] = []
        lines.append("PixMate 联机诊断日志")
        lines.append("================================")
        lines.append("导出时间：\(Date().formatted(date: .abbreviated, time: .standard))")
        lines.append("设备：\(device.model) · iOS \(device.systemVersion)")
        lines.append("连接状态：\(env.camera.link.title)")
        if let detail = env.camera.link.detail {
            lines.append("状态详情：\(detail)")
        }
        lines.append("相机型号：\(env.camera.session.modelName.isEmpty ? "（未识别）" : env.camera.session.modelName)")
        lines.append("实时取景：\(env.camera.session.isLiveViewRunning ? "运行中" : "未开启")")
        lines.append(String(format: "取景帧率：%.1f fps", env.camera.liveViewFPS))
        lines.append("================================")
        lines.append(contentsOf: env.camera.session.trace)
        let text = lines.joined(separator: "\n")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PixMate诊断-\(formatter.string(from: Date())).txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return TraceExport(url: url)
        } catch {
            return nil
        }
    }
}

/// sheet(item:) 需要的包装
private struct TraceExport: Identifiable {
    let id = UUID()
    let url: URL
}

/// 系统分享面板
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct StepRow: View {
    let index: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.black)
                .frame(width: 18, height: 18)
                .background(Color(red: 0.24, green: 0.86, blue: 0.62), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
