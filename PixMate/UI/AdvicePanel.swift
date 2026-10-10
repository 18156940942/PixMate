import SwiftUI

// MARK: - 参谋面板
//
// 上：构图诊断（可执行的建议）
// 下：姿势建议（本地库 / AI 现场生成）+ 与目标姿势的差距

struct AdvicePanel: View {
    @EnvironmentObject private var env: AppEnvironment
    @ObservedObject var coach: CoachPipeline
    @Binding var selectedPose: PoseSuggestion?

    @State private var showingAllAdvice = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                compositionSection
                poseSection
            }
            .padding(14)
        }
        .background(Color(white: 0.09))
    }

    // MARK: 构图

    private var compositionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "构图诊断", systemImage: "viewfinder")
                if !coach.report.isEmpty {
                    Text("\(coach.report.score)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(scoreColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(scoreColor.opacity(0.16), in: Capsule())
                }
            }

            if coach.people.isEmpty && coach.faces.isEmpty {
                EmptyHint(icon: "person.crop.rectangle.badge.plus",
                          title: "画面里还没检测到人",
                          message: "把相机对准拍摄对象，诊断会自动出现")
            } else if coach.report.topIssues.isEmpty {
                AdviceRow(icon: "checkmark.seal.fill",
                          color: Color(red: 0.24, green: 0.86, blue: 0.62),
                          title: "构图没问题",
                          detail: "可以直接按快门",
                          action: nil)
            } else {
                ForEach(visibleIssues) { issue in
                    AdviceRow(icon: issue.severity.symbolName,
                              color: issue.severity == .warning
                                ? Color(red: 1.0, green: 0.62, blue: 0.20)
                                : Color(red: 0.98, green: 0.86, blue: 0.42),
                              title: issue.title,
                              detail: issue.detail,
                              action: issue.action)
                }

                if coach.report.topIssues.count > 2 {
                    Button {
                        showingAllAdvice.toggle()
                    } label: {
                        Text(showingAllAdvice ? "收起" : "还有 \(coach.report.topIssues.count - 2) 条")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var visibleIssues: [CompositionIssue] {
        showingAllAdvice ? coach.report.topIssues : Array(coach.report.topIssues.prefix(2))
    }

    private var scoreColor: Color {
        switch coach.report.score {
        case 85...:    return Color(red: 0.24, green: 0.86, blue: 0.62)
        case 65..<85:  return Color(red: 0.98, green: 0.86, blue: 0.42)
        default:       return Color(red: 1.0, green: 0.55, blue: 0.35)
        }
    }

    // MARK: 姿势

    private var poseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "姿势建议", systemImage: "figure.stand")
                Spacer()
                Button {
                    Task { await coach.generateScenePoses() }
                } label: {
                    HStack(spacing: 4) {
                        if coach.isGenerating {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(env.isVisionConfigured ? "按景色生成" : "去设置里配模型")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(env.isVisionConfigured
                                 ? Color(red: 0.55, green: 0.78, blue: 1.0)
                                 : Color.secondary)
                .disabled(!env.isVisionConfigured || coach.isGenerating)
            }

            if let error = coach.generationError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.20))
            }

            if coach.allSuggestions.isEmpty {
                EmptyHint(icon: "figure.wave",
                          title: "还没有姿势建议",
                          message: "检测到人之后会自动推荐")
            } else {
                categoryChips

                if !coach.generatedSuggestions.isEmpty {
                    Text("AI 按当前景色生成")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(coach.allSuggestions) { pose in
                            PoseCard(pose: pose,
                                     isSelected: selectedPose?.id == pose.id)
                                .onTapGesture { selectedPose = pose }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let pose = selectedPose {
                selectedPoseDetail(pose)
            }
        }
    }

    /// 分类筛选条：智能 + 六大类。双人互动姿势在智能模式下自动混入。
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "智能", category: nil)
                ForEach(PoseCategory.allCases, id: \.self) { category in
                    chip(title: category.displayName, category: category)
                }
            }
        }
    }

    private func chip(title: String, category: PoseCategory?) -> some View {
        let isActive = coach.poseCategory == category
        return Button {
            coach.setPoseCategory(category)
        } label: {
            Text(title)
                .font(.caption2.weight(isActive ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive ? Color(red: 0.24, green: 0.86, blue: 0.62).opacity(0.2)
                                     : Color.white.opacity(0.06),
                            in: Capsule())
                .overlay(
                    Capsule().strokeBorder(isActive ? Color(red: 0.24, green: 0.86, blue: 0.62).opacity(0.7)
                                                    : Color.white.opacity(0.08),
                                           lineWidth: 1)
                )
                .foregroundStyle(isActive ? Color(red: 0.24, green: 0.86, blue: 0.62) : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func selectedPoseDetail(_ pose: PoseSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(pose.title)
                    .font(.subheadline.weight(.semibold))
                Text(pose.source.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: Capsule())
                Spacer()
                Text(String(format: "匹配 %.0f%%", coach.matchScore * 100))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(coach.matchScore > 0.7
                                     ? Color(red: 0.24, green: 0.86, blue: 0.62)
                                     : .secondary)
            }

            Text(pose.hint)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.9))

            if let note = pose.sceneNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !coach.deviations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("现在就可以喊的话")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ForEach(coach.deviations, id: \.self) { hint in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption2)
                            Text(hint).font(.caption)
                        }
                        .foregroundStyle(Color(red: 0.98, green: 0.86, blue: 0.42))
                    }
                }
                .padding(.top, 2)
            } else if coach.matchScore > 0.7 {
                Text("姿态已经很接近了，再按几张挑一张")
                    .font(.caption2)
                    .foregroundStyle(Color(red: 0.24, green: 0.86, blue: 0.62))
            }
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 单条建议

struct AdviceRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let action: String?

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let action {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                        Text(action)
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: - 姿势卡片

struct PoseCard: View {
    let pose: PoseSuggestion
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 用迷你骨架当缩略图，不依赖任何图片资源
            MiniSkeleton(joints: pose.normalizedJoints,
                         color: isSelected ? Color(red: 0.24, green: 0.86, blue: 0.62) : .white.opacity(0.72))
                .frame(width: 62, height: 76)

            Text(pose.title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)

            Text(pose.framing)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .frame(width: 84)
        .background(isSelected ? Color(red: 0.24, green: 0.86, blue: 0.62).opacity(0.16)
                               : Color.white.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color(red: 0.24, green: 0.86, blue: 0.62).opacity(0.8)
                                         : .white.opacity(0.08),
                              lineWidth: 1)
        )
    }
}

/// 姿势缩略骨架
struct MiniSkeleton: View {
    let joints: [String: CGPoint]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let projected = joints.mapValues {
                CGPoint(x: $0.x * size.width, y: $0.y * size.height)
            }
            for (a, b) in JointName.connections {
                guard let pa = projected[a], let pb = projected[b] else { continue }
                var path = Path()
                path.move(to: pa)
                path.addLine(to: pb)
                context.stroke(path, with: .color(color), lineWidth: 1.8)
            }
            for (_, point) in projected {
                let r: CGFloat = 1.8
                let dot = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: dot), with: .color(color))
            }
        }
    }
}
