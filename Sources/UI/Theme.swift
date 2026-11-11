import SwiftUI
import AppKit

// MacTemp 主题层：配色、字体、温度色阶、数值格式化。
// 深色优先；浅色通过动态 NSColor 自适应，不写死黑底。

// MARK: - 十六进制颜色辅助

extension Color {
    /// 用 0xRRGGBB 形式的十六进制值创建 sRGB 颜色。
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

// MARK: - 主题

enum Theme {
    // MARK: 品牌色（青蓝渐变 #36D1DC → #5B86E5）

    static let accent = Color(hex: 0x36D1DC)
    static let accentDeep = Color(hex: 0x5B86E5)

    /// 主品牌渐变（自左上到右下）
    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0x36D1DC), Color(hex: 0x5B86E5)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 横向品牌渐变（用于选中胶囊 / 主按钮，蓝→青，保证左侧文字对比度）
    static let accentGradientHorizontal = LinearGradient(
        colors: [Color(hex: 0x4E7AE0), Color(hex: 0x36D1DC)],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// 卡片顶部高光描边渐变
    static let cardStrokeGradient = LinearGradient(
        colors: [strokeHighlight, strokeSoft],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: 背景 / 材质 / 层级

    private static func dynamic(
        dark: UInt32,
        light: UInt32,
        darkOpacity: Double = 1,
        lightOpacity: Double = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            let isDark = match == .darkAqua
            return isDark
                ? nsColor(hex: dark, alpha: darkOpacity)
                : nsColor(hex: light, alpha: lightOpacity)
        })
    }

    private static func nsColor(hex: UInt32, alpha: Double) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: CGFloat(alpha)
        )
    }

    /// 窗口底色：深色 #0B0F16，浅色为冷调浅灰。
    static let background = dynamic(dark: 0x0B0F16, light: 0xEEF2F8)
    /// 侧栏叠加色（叠在 ultraThinMaterial 之上）。
    static let sidebarTint = dynamic(dark: 0x05070C, light: 0xFFFFFF, darkOpacity: 0.42, lightOpacity: 0.45)
    /// 卡片叠加色：在材质上再压一层深蓝黑，让卡片与背景同色系、有实体感。
    static let cardTint = dynamic(dark: 0x0B1220, light: 0xFFFFFF, darkOpacity: 0.42, lightOpacity: 0.46)
    /// 卡片描边高光 / 收尾。
    static let strokeHighlight = dynamic(dark: 0xFFFFFF, light: 0xFFFFFF, darkOpacity: 0.16, lightOpacity: 0.95)
    static let strokeSoft = dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: 0.035, lightOpacity: 0.05)
    /// 1px 分隔线。
    static let hairline = dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: 0.07, lightOpacity: 0.07)
    /// 进度条 / 环形底槽。
    static let track = dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: 0.075, lightOpacity: 0.06)
    /// 卡片阴影。
    static let cardShadow = dynamic(dark: 0x000000, light: 0x223044, darkOpacity: 0.28, lightOpacity: 0.10)
    /// 深色径向光晕（青）。
    static let glowCyan = dynamic(dark: 0x36D1DC, light: 0x36D1DC, darkOpacity: 0.13, lightOpacity: 0.09)
    /// 深色径向光晕（蓝）。
    static let glowBlue = dynamic(dark: 0x5B86E5, light: 0x5B86E5, darkOpacity: 0.12, lightOpacity: 0.07)
    /// 鼠标悬停背景。
    static let hoverFill = dynamic(dark: 0xFFFFFF, light: 0x000000, darkOpacity: 0.055, lightOpacity: 0.045)

    // MARK: 温度色阶
    // <55 青蓝 / 55–70 绿 / 70–85 黄 / 85–95 橙 / >95 红

    static let tempCool = dynamic(dark: 0x36D1DC, light: 0x0B7F8B)
    static let tempGreen = dynamic(dark: 0x3BD98C, light: 0x0E7F4C)
    static let tempYellow = dynamic(dark: 0xFFD60A, light: 0x946600)
    static let tempOrange = dynamic(dark: 0xFF9F0A, light: 0xB85F00)
    static let tempRed = dynamic(dark: 0xFF5A50, light: 0xC41E1E)
    static let tempUnknown = dynamic(dark: 0x8E97A3, light: 0x6E7885)

    /// 摄氏度 → 色阶颜色。
    static func temperatureColor(_ celsius: Double?) -> Color {
        guard let celsius, celsius.isFinite else { return tempUnknown }
        switch celsius {
        case ..<55: return tempCool
        case ..<70: return tempGreen
        case ..<85: return tempYellow
        case ..<95: return tempOrange
        default: return tempRed
        }
    }

    /// 摄氏度 → 温度状态文案。
    static func temperatureStatus(_ celsius: Double?) -> String {
        guard let celsius, celsius.isFinite else { return "不可用" }
        switch celsius {
        case ..<55: return "凉爽"
        case ..<70: return "正常"
        case ..<85: return "偏高"
        case ..<95: return "高温"
        default: return "过热"
        }
    }

    /// 温度条进度（25–105°C 映射到 0–1，用于传感器列表）。
    static func temperatureProgress(_ celsius: Double?) -> Double {
        guard let celsius, celsius.isFinite else { return 0 }
        return min(max((celsius - 25.0) / 80.0, 0.015), 1.0)
    }

    /// 热压力 → 颜色。
    static func thermalColor(_ pressure: ThermalPressure) -> Color {
        switch pressure {
        case .nominal: return tempGreen
        case .fair: return tempYellow
        case .serious: return tempOrange
        case .critical: return tempRed
        }
    }

    /// 占用率 → 颜色（低负载青蓝、高负载橙红）。
    static func loadColor(_ usage: Double) -> Color {
        switch usage {
        case ..<0.55: return tempCool
        case ..<0.80: return tempGreen
        case ..<0.92: return tempYellow
        default: return tempOrange
        }
    }

    // MARK: 字体

    /// 大号温度数字：圆体 + 等宽数字，避免每秒刷新时抖动。
    static func heroFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }

    /// 普通数字（等宽数字）。
    static func numberFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// SMC 键等专有名词的等宽字体。
    static func monoFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let pageTitleFont = Font.system(size: 25, weight: .bold, design: .rounded)
    static let pageSubtitleFont = Font.system(size: 11.5, weight: .regular)
    static let cardTitleFont = Font.system(size: 13, weight: .semibold)
    static let sectionTitleFont = Font.system(size: 14, weight: .semibold)
    static let captionFont = Font.system(size: 10.5, weight: .regular)
    static let labelFont = Font.system(size: 11.5, weight: .medium)
    static let bodyFont = Font.system(size: 12, weight: .regular)
}

// MARK: - 版本信息

enum AppMetadata {
    /// 从 Bundle 读取版本号；离屏渲染（非 .app 包）时回退到 1.0.0。
    static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        return short ?? "1.0.0"
    }()

    static let build: String = {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleVersion"] as? String) ?? "1"
    }()
}

// MARK: - 数值格式化

enum Fmt {
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    /// 时间（HH:mm:ss）；从未更新时显示占位。
    static func clock(_ date: Date) -> String {
        guard date != .distantPast else { return "--:--:--" }
        return clockFormatter.string(from: date)
    }

    static func day(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    /// 温度数值（按单位换算，不含单位），digits 位小数。
    static func temperature(_ celsius: Double?, unit: TemperatureUnit, digits: Int = 1) -> String {
        guard let celsius, celsius.isFinite else { return "--" }
        return String(format: "%.\(digits)f", unit.convert(fromCelsius: celsius))
    }

    /// 温度数值 + 单位，例如 "62.4 °C"。
    static func temperatureWithUnit(_ celsius: Double?, unit: TemperatureUnit, digits: Int = 1) -> String {
        guard let celsius, celsius.isFinite else { return "--" }
        return "\(temperature(celsius, unit: unit, digits: digits)) \(unit.shortLabel)"
    }

    /// 字节容量（自动选择 GB / MB / KB）。
    static func bytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= 1_073_741_824 {
            return "\(trim(value / 1_073_741_824)) GB"
        }
        if value >= 1_048_576 {
            return "\(trim(value / 1_048_576)) MB"
        }
        if value >= 1024 {
            return "\(trim(value / 1024)) KB"
        }
        return "\(bytes) B"
    }

    /// 网络速率。
    static func speed(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        if value < 1024 { return String(format: "%.0f B/s", value) }
        let kb = value / 1024
        if kb < 1024 { return String(format: kb < 100 ? "%.1f KB/s" : "%.0f KB/s", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: mb < 100 ? "%.1f MB/s" : "%.0f MB/s", mb) }
        return String(format: "%.2f GB/s", mb / 1024)
    }

    /// 运行时间，例如 "3 天 4 小时" / "4 小时 12 分" / "36 秒"。
    static func uptime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--" }
        let total = Int(seconds.rounded())
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        if minutes > 0 { return "\(minutes) 分 \(total % 60) 秒" }
        return "\(total) 秒"
    }

    /// 整机功耗，nil 显示 "--"。
    static func watts(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return value < 10 ? String(format: "%.2f W", value) : String(format: "%.1f W", value)
    }

    static func rpm(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "--" }
        return String(format: "%.0f RPM", value)
    }

    /// 0...1 占用率 → 百分比文本。
    static func percent(_ value: Double, digits: Int = 0) -> String {
        guard value.isFinite else { return "--" }
        return String(format: "%.\(digits)f%%", min(max(value, 0), 1) * 100)
    }

    /// 内存等大数字（避免 Locale 逗号）。
    static func count(_ value: Int) -> String {
        "\(value)"
    }

    /// 一位小数的紧凑数字，整数时省略 ".0"。
    private static func trim(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return String(format: "%.0f", value.rounded())
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - 窗口拖拽

/// 透明拖拽区：包一层 NSView，让 hiddenTitleBar 窗口在空白区域也能拖动。
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

// MARK: - 常见复用修饰符

extension View {
    /// 应用统一的玻璃卡片背景（ultraThinMaterial + 1px 高光描边 + 轻阴影）。
    func glassCard(cornerRadius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GlassCardBackground(cornerRadius: cornerRadius))
    }
}

/// 卡片背景：材质 + 叠加色 + 渐变描边 + 柔阴影。
struct GlassCardBackground: View {
    var cornerRadius: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(Theme.cardTint))
            .overlay(shape.strokeBorder(Theme.cardStrokeGradient, lineWidth: 1))
            .shadow(color: Theme.cardShadow, radius: 12, x: 0, y: 7)
    }
}
