import SwiftUI

// MARK: - 尺寸工具

extension CGSize {
    /// 等比缩放，完整放进容器（aspect-fit）
    func fitted(in container: CGSize) -> CGSize {
        guard width > 0, height > 0, container.width > 0, container.height > 0 else { return container }
        let scale = min(container.width / width, container.height / height)
        return CGSize(width: width * scale, height: height * scale)
    }
}

// MARK: - 根视图

struct RootView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var tab: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                MonitorView()
                    .tabItem { Label("拍摄", systemImage: "camera.viewfinder") }
                    .tag(0)

                ProjectsView()
                    .tabItem { Label("项目", systemImage: "square.stack.3d.up") }
                    .tag(1)

                SettingsView()
                    .tabItem { Label("设置", systemImage: "slider.horizontal.3") }
                    .tag(2)
            }
            .tint(Color(red: 0.24, green: 0.86, blue: 0.62))

            if let toast = env.toast {
                ToastBanner(text: toast)
                    .padding(.bottom, 78)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: env.toast)
    }
}

struct ToastBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(red: 0.24, green: 0.86, blue: 0.62))
            Text(text)
                .font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}

// MARK: - 通用小控件

/// 带数值显示的参数滑块
struct ParameterSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -1...1
    var formatter: (Double) -> String = { String(format: "%+.2f", $0) }
    var onCommit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatter(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isActive ? Color(red: 0.24, green: 0.86, blue: 0.62) : .secondary)
            }
            Slider(value: $value, in: range) { editing in
                if !editing { onCommit?() }
            }
            .tint(Color(red: 0.24, green: 0.86, blue: 0.62))
        }
    }

    private var isActive: Bool { abs(value) > 0.001 }
}

/// 0…1 的强度滑块
struct StrengthSlider: View {
    let title: String
    @Binding var value: Double
    var onCommit: (() -> Void)?

    var body: some View {
        ParameterSlider(title: title,
                        value: $value,
                        range: 0...1,
                        formatter: { String(format: "%.0f%%", $0 * 100) },
                        onCommit: onCommit)
    }
}

/// 分区标题
struct SectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
            }
            Text(title)
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.top, 6)
    }
}

/// 空状态
struct EmptyHint: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.subheadline.weight(.medium))
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
