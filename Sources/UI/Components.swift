import SwiftUI

// 通用 UI 组件：玻璃卡片、环形仪表、sparkline、进度条、状态胶囊、
// 骨架屏、错误条、空态、筛选 chip、流式布局等。全部为纯视图，不依赖 AppState。

// MARK: - 玻璃卡片

/// 统一的玻璃卡片容器（材质 + 1px 高光描边 + 柔阴影）。
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 18
    var padding: CGFloat = 16
    private let content: Content

    init(cornerRadius: CGFloat = 18, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassCardBackground(cornerRadius: cornerRadius))
    }
}

/// 1px 分隔线（自适应深浅色）。
struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}

// MARK: - 图标 / 徽标

/// 柔和的圆角图标底座（低饱和底色 + 同色描边），用于卡片与列表标题。
struct SymbolChip: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 32

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(shape.fill(tint.opacity(0.13)))
            .overlay(shape.strokeBorder(tint.opacity(0.30), lineWidth: 1))
    }
}

/// SMC key 等专有名词的等宽小徽标。
struct KeyBadge: View {
    let text: String
    var tint: Color = Color.secondary

    var body: some View {
        Text(text)
            .font(Theme.monoFont(9.5, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.track)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

// MARK: - 状态胶囊 / 圆点

/// 带柔光的小圆点。
struct StatusDot: View {
    var color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.8), radius: 3)
    }
}

/// 状态胶囊，例如「热压力 正常」「无风扇」。
struct StatusPill: View {
    let text: String
    var color: Color = Theme.accent
    var showsDot: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            if showsDot {
                Circle()
                    .fill(color)
                    .frame(width: 5.5, height: 5.5)
            }
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(color.opacity(0.13)))
        .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
    }
}

// MARK: - 环形仪表

/// 圆环进度仪表，中间可放自定义内容（百分比、数值等）。
struct RingGauge<Center: View>: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 8
    var size: CGFloat = 88
    private let center: Center

    init(
        progress: Double,
        color: Color,
        lineWidth: CGFloat = 8,
        size: CGFloat = 88,
        @ViewBuilder center: () -> Center
    ) {
        self.progress = progress
        self.color = color
        self.lineWidth = lineWidth
        self.size = size
        self.center = center()
    }

    var body: some View {
        let clamped = min(max(progress.isFinite ? progress : 0, 0), 1)
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(clamped, 0.001))
                .stroke(
                    LinearGradient(
                        colors: [color, color.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 5)
                .animation(.easeOut(duration: 0.35), value: clamped)
            center
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 进度条

/// 细圆角进度条（渐变填充 + 柔光）。
struct MiniBar: View {
    var progress: Double
    var color: Color = Theme.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(progress.isFinite ? progress : 0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.85), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, geo.size.width * clamped))
                    .shadow(color: color.opacity(0.35), radius: 3)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: progress)
    }
}

/// 传感器列表里的温度条（按 25–105°C 映射）。
struct TemperatureBar: View {
    var celsius: Double?
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let progress = Theme.temperatureProgress(celsius)
            let color = Theme.temperatureColor(celsius)
            let width = celsius == nil ? 0 : max(height, geo.size.width * progress)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.5), color],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Sparkline（60 秒历史）

/// 轻量 Canvas 折线图：60 个采样点，带渐变填充与末端光点。
struct Sparkline: View {
    var values: [Double]
    var color: Color = Theme.accent
    var lineWidth: CGFloat = 1.7
    var showsFill: Bool = true
    var showsLastPoint: Bool = true

    var body: some View {
        Canvas { context, size in
            let points = self.points(in: size)
            guard points.count >= 2 else {
                var baseline = Path()
                let y = size.height * 0.58
                baseline.move(to: CGPoint(x: 0, y: y))
                baseline.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    baseline,
                    with: .color(color.opacity(0.18)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
                return
            }

            var line = Path()
            line.move(to: points[0])
            for point in points.dropFirst() {
                line.addLine(to: point)
            }

            if showsFill {
                var fill = line
                fill.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
                fill.addLine(to: CGPoint(x: points[0].x, y: size.height))
                fill.closeSubpath()
                context.fill(
                    fill,
                    with: .linearGradient(
                        Gradient(colors: [color.opacity(0.28), color.opacity(0.0)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }

            context.stroke(
                line,
                with: .color(color.opacity(0.92)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )

            if showsLastPoint, let last = points.last {
                let ring = Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8))
                context.stroke(ring, with: .color(color.opacity(0.28)), lineWidth: 1)
                let dot = Path(ellipseIn: CGRect(x: last.x - 2.2, y: last.y - 2.2, width: 4.4, height: 4.4))
                context.fill(dot, with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2, size.width > 1, size.height > 1 else { return [] }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let isFlat = (maximum - minimum) < 0.6
        let range = max(maximum - minimum, 0.6)
        let inset: CGFloat = 3
        let usableHeight = max(size.height - inset * 2, 1)
        let usableWidth = max(size.width - inset * 2, 1)
        let stepX = usableWidth / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let normalized = isFlat ? 0.5 : (value - minimum) / range
            let y = size.height - inset - CGFloat(normalized) * usableHeight
            return CGPoint(x: inset + CGFloat(index) * stepX, y: y)
        }
    }
}

// MARK: - 每核占用柱

/// 每核心占用的小柱状图（底部对齐，带底槽）。
struct CoreUsageBars: View {
    var values: [Double]
    var height: CGFloat = 34

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                let clamped = min(max(value.isFinite ? value : 0, 0), 1)
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                        .fill(Theme.track.opacity(0.6))
                    RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.accentDeep, Theme.accent],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: max(3, height * CGFloat(clamped)))
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

// MARK: - 信息行 / 指标块

/// 左标签 + 右数值的信息行。
struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color? = nil
    var mono: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(Theme.labelFont)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(mono ? Theme.numberFont(12, weight: .medium) : Theme.bodyFont)
                .foregroundStyle(valueColor ?? Color.primary)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minHeight: 20)
    }
}

/// 小号指标块（图标 + 标签 + 数值），用于负载 / 系统状态卡片内部。
struct MetricTile: View {
    var symbol: String
    var label: String
    var value: String
    var tint: Color = Theme.accent
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(Theme.numberFont(14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let detail {
                Text(detail)
                    .font(Theme.captionFont)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.track.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
    }
}

/// 图例圆点 + 文案。
struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5.5, height: 5.5)
            Text(label).font(Theme.captionFont).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 按钮

/// 胶囊主按钮（品牌渐变）。
struct GradientButton: View {
    let title: String
    var symbol: String? = nil
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.accentGradientHorizontal))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .shadow(color: Theme.accentDeep.opacity(hovered ? 0.55 : 0.3), radius: hovered ? 10 : 6, y: 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// 胶囊次按钮（柔和底色）。
struct SoftButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = Color.secondary
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(tint.opacity(hovered ? 0.16 : 0.10)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }
}

/// 圆形玻璃图标按钮（刷新等）。
struct GlassIconButton: View {
    let symbol: String
    var helpText: String = ""
    var size: CGFloat = 28
    var tint: Color = Color.secondary
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(hovered ? Color.primary : tint)
                .frame(width: size, height: size)
                .background(Circle().fill(hovered ? Theme.hoverFill : Color.clear))
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(helpText)
    }
}

/// 过滤器 chip（分类筛选、分段选择）。
struct FilterChip: View {
    let title: String
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .monospacedDigit()
                        .opacity(0.72)
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(Theme.accentGradientHorizontal)
                        : AnyShapeStyle(hovered ? Theme.hoverFill : Color.clear)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.white.opacity(0.18) : Theme.hairline,
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

/// 自绘开关：品牌渐变开启态，避免系统 Toggle 在深色/离屏渲染下的显示失真。
struct AccentSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                Capsule()
                    .fill(
                        isOn
                            ? AnyShapeStyle(Theme.accentGradientHorizontal)
                            : AnyShapeStyle(Theme.track)
                    )
                    .frame(width: 36, height: 21)
                Circle()
                    .fill(Color.white)
                    .frame(width: 17, height: 17)
                    .offset(x: isOn ? 7.5 : -7.5)
                    .shadow(color: Color.black.opacity(0.25), radius: 1.5, y: 0.5)
            }
            .frame(width: 36, height: 21)
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.16), value: isOn)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - 错误 / 空态

/// 顶部错误提示条。
struct ErrorBanner: View {
    let message: String
    var retryTitle: String = "重新扫描"
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.tempOrange)
            VStack(alignment: .leading, spacing: 1) {
                Text("传感器读取异常")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(message)
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let onRetry {
                Button(action: onRetry) {
                    Text(retryTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.tempOrange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.tempOrange.opacity(0.16)))
                        .overlay(Capsule().strokeBorder(Theme.tempOrange.opacity(0.35), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.tempOrange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.tempOrange.opacity(0.28), lineWidth: 1)
        )
    }
}

/// 空态占位。
struct EmptyStateView: View {
    var symbol: String = "thermometer.slash"
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
            Text(message)
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                SoftButton(title: actionTitle, symbol: "arrow.clockwise", tint: Theme.accent, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
    }
}

// MARK: - 骨架屏

/// 呼吸占位块（仅在扫描期间出现，动画生命周期短）。
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 6

    @State private var dimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.track)
            .frame(width: width, height: height)
            .opacity(dimmed ? 0.5 : 1)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: dimmed)
            .onAppear { dimmed = true }
    }
}

/// 概览页加载时的卡片骨架。
struct SkeletonTemperatureCard: View {
    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SkeletonBlock(width: 32, height: 32, cornerRadius: 9)
                    VStack(alignment: .leading, spacing: 5) {
                        SkeletonBlock(width: 80, height: 11)
                        SkeletonBlock(width: 54, height: 8)
                    }
                    Spacer()
                }
                SkeletonBlock(width: 120, height: 30, cornerRadius: 7)
                SkeletonBlock(height: 34, cornerRadius: 8)
            }
        }
    }
}

/// 通用列表行骨架。
struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 10) {
            SkeletonBlock(width: 24, height: 24, cornerRadius: 7)
            SkeletonBlock(height: 11)
            SkeletonBlock(width: 52, height: 11)
        }
        .padding(.vertical, 7)
    }
}

// MARK: - 流式布局

/// 简单流式布局：chips 自动换行。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var lastLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lastLineWidth = x - spacing
            lineHeight = max(lineHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : lastLineWidth
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
