import SwiftUI
import AppKit
import Foundation

// 设置页：刷新间隔 / 温度单位 / 菜单栏显示 / 历史曲线 / 传感器维护 / 关于。
// 同时作为独立 Settings 场景内容（embedded == false 时带自己的滚动与固定尺寸）。

struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    /// 内嵌在主窗口内容区时为 true；作为独立 Settings 窗口时为 false。
    var embedded: Bool = false

    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    var body: some View {
        if embedded {
            content
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ScrollView {
                content
                    .frame(maxWidth: 600, alignment: .leading)
                    .padding(22)
            }
            .frame(width: 640, height: 690)
            .background(AppBackground())
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 13) {
            generalCard
            menuBarCard
            historyCard
            maintenanceCard
            aboutCard
        }
    }

    // MARK: 通用

    private var generalCard: some View {
        settingsCard(title: "通用", symbol: "slider.horizontal.3", tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 0) {
                settingRow(
                    title: "刷新间隔",
                    detail: "温度与负载的采样频率，越快越实时、开销略高"
                ) {
                    Picker("", selection: $app.settings.refreshInterval) {
                        Text("1 秒").tag(1.0)
                        Text("2 秒").tag(2.0)
                        Text("5 秒").tag(5.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }

                DividerLine().padding(.vertical, 8)

                settingRow(
                    title: "温度单位",
                    detail: "所有界面与菜单栏立即生效"
                ) {
                    Picker("", selection: $app.settings.unit) {
                        Text("摄氏度 °C").tag(TemperatureUnit.celsius)
                        Text("华氏度 °F").tag(TemperatureUnit.fahrenheit)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }
            }
        }
    }

    // MARK: 菜单栏

    private var menuBarCard: some View {
        settingsCard(title: "菜单栏", symbol: "menubar.rectangle", tint: Theme.accentDeep) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("预览")
                        .font(Theme.captionFont)
                        .foregroundStyle(.secondary)
                    menuBarPreview
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 9)

                DividerLine().padding(.bottom, 8)

                settingRow(
                    title: "菜单栏显示内容",
                    detail: "选择菜单栏常驻文本展示的指标"
                ) {
                    Picker("", selection: $app.settings.menuBarMetric) {
                        ForEach(MenuBarMetric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 160)
                }

                DividerLine().padding(.vertical, 8)

                settingRow(
                    title: "显示文字标签",
                    detail: "关闭后菜单栏只显示温度计图标"
                ) {
                    AccentSwitch(isOn: $app.settings.menuBarShowText)
                }
            }
        }
    }

    private var menuBarPreview: some View {
        HStack(spacing: 5) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 10, weight: .medium))
            if app.settings.menuBarShowText {
                Text(app.menuBarLabel)
                    .font(Theme.numberFont(10.5, weight: .medium))
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.track.opacity(0.55)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: 历史曲线

    private var historyCard: some View {
        settingsCard(title: "历史曲线", symbol: "chart.line.uptrend.xyaxis", tint: Theme.tempGreen) {
            VStack(alignment: .leading, spacing: 0) {
                settingRow(
                    title: "记录最近 60 秒温度曲线",
                    detail: "关闭后概览卡片将不再显示 sparkline，可略微降低开销"
                ) {
                    AccentSwitch(isOn: $app.settings.recordHistory)
                }

                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Theme.tempGreen)
                    Text("当前 CPU 曲线已记录 \(app.historyValues(for: SensorCategory.cpu.rawValue).count) / 60 个采样点")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: 传感器维护

    private var maintenanceCard: some View {
        settingsCard(title: "传感器", symbol: "thermometer.medium", tint: Theme.tempYellow) {
            VStack(alignment: .leading, spacing: 0) {
                InfoRow(label: "SMC 状态", value: smcStatusText, valueColor: smcStatusColor)
                InfoRow(label: "温度传感器", value: "\(availableSensorCount) / \(app.sensors.count) 可用")
                InfoRow(label: "风扇", value: app.fans.isEmpty ? "无风扇（被动散热）" : "\(app.fans.count) 个")
                InfoRow(label: "整机功耗", value: Fmt.watts(app.powerWatts))
                InfoRow(label: "最后更新", value: Fmt.clock(app.lastUpdated))

                HStack(spacing: 8) {
                    if let error = app.scanError {
                        Text(error)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.tempOrange)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    SoftButton(
                        title: app.isScanning ? "正在扫描…" : "重新扫描传感器",
                        symbol: "arrow.triangle.2.circlepath",
                        tint: Theme.accent
                    ) {
                        app.rescanSensors()
                    }
                    .disabled(app.isScanning)
                    .opacity(app.isScanning ? 0.6 : 1)
                }
                .padding(.top, 10)
            }
        }
    }

    private var availableSensorCount: Int {
        app.sensors.filter { $0.isAvailable }.count
    }

    private var smcStatusText: String {
        if app.isScanning { return "扫描中" }
        if app.scanError != nil { return "异常" }
        return app.sensors.isEmpty ? "无数据" : "正常"
    }

    private var smcStatusColor: Color {
        if app.isScanning { return Theme.tempYellow }
        if app.scanError != nil { return Theme.tempOrange }
        return app.sensors.isEmpty ? Color.secondary : Theme.tempGreen
    }

    // MARK: 关于

    private var aboutCard: some View {
        settingsCard(title: "关于", symbol: "info.circle", tint: Theme.tempCool) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 12) {
                    AppLogoMark(size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MacTemp")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("版本 \(AppMetadata.version) · 构建 \(AppMetadata.build)")
                            .font(Theme.captionFont)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    StatusPill(text: "原生 SwiftUI", color: Theme.accent, showsDot: false)
                }

                Text("MacTemp 是一款原生 macOS 温度监控工具：直接通过 AppleSMC 读取 Apple Silicon 温度传感器，每秒呈现各部件温度、风扇转速与整机功耗，并提供进程排行与系统信息。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                DividerLine()

                aboutRow(label: "数据来源", value: "AppleSMC（IOKit）")
                aboutRow(label: "界面技术", value: "SwiftUI · 无第三方依赖")
                aboutRow(label: "隐私", value: "完全本地运行，无任何网络请求")
                aboutRow(label: "作者", value: "MacTemp Team")

                HStack(spacing: 4) {
                    Text("© 2026 MacTemp · 仅供本机硬件监控使用")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(Theme.labelFont)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5))
                .foregroundStyle(.primary.opacity(0.85))
            Spacer(minLength: 0)
        }
    }

    // MARK: 通用布局

    private func settingsCard<Content: View>(
        title: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SymbolChip(symbol: symbol, tint: tint, size: 25)
                    Text(title)
                        .font(Theme.sectionTitleFont)
                    Spacer(minLength: 0)
                }
                DividerLine()
                content()
            }
        }
    }

    private func settingRow<Control: View>(
        title: String,
        detail: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(Theme.captionFont)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 2)
    }
}
