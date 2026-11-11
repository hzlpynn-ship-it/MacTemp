import SwiftUI
import AppKit
import Foundation

// 菜单栏弹出面板：4 个主部件迷你行 + 热压力 / 风扇 / 功耗 + 打开主窗口 / 退出。
// 宽度 340pt，与 MenuBarExtra(.window) 配合。

struct MenuBarPanelView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var refreshSpin: Double = 0

    private var groups: [TemperatureGroup] {
        Array(app.primaryGroups.prefix(4))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            DividerLine()

            if app.isScanning && groups.isEmpty {
                scanningPlaceholder
            } else if groups.isEmpty {
                emptyPlaceholder
            } else {
                miniRows
                trendSection
            }

            DividerLine()
            statusStrip

            Spacer(minLength: 6)

            actions
            footer
        }
        .frame(width: 340)
        .background(.ultraThinMaterial)
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 9) {
            AppLogoMark(size: 27)
            VStack(alignment: .leading, spacing: 0) {
                Text("MacTemp")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                Text("最近更新 \(Fmt.clock(app.lastUpdated))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            StatusPill(text: stateText, color: stateColor)
            GlassIconButton(
                symbol: "arrow.clockwise",
                helpText: "立即刷新",
                size: 24,
                tint: Theme.accent
            ) {
                refreshSpin += 360
                app.refreshNow()
            }
            .rotationEffect(.degrees(refreshSpin))
            .animation(.easeInOut(duration: 0.5), value: refreshSpin)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var stateColor: Color {
        if app.isScanning { return Theme.tempYellow }
        if app.scanError != nil { return Theme.tempOrange }
        return Theme.tempGreen
    }

    private var stateText: String {
        if app.isScanning { return "扫描中" }
        if app.scanError != nil { return "读取异常" }
        return "实时"
    }

    // MARK: 迷你行

    private var miniRows: some View {
        VStack(spacing: 1) {
            ForEach(groups) { group in
                miniRow(group)
            }
        }
        .padding(.vertical, 4)
    }

    private func miniRow(_ group: TemperatureGroup) -> some View {
        let color = Theme.temperatureColor(group.primary)
        return HStack(spacing: 9) {
            SymbolChip(symbol: group.symbolName, tint: color, size: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text(group.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Text(group.subtitle)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 2)

            Sparkline(
                values: app.historyValues(for: group.id),
                color: color,
                lineWidth: 1.1,
                showsFill: false,
                showsLastPoint: false
            )
            .frame(width: 46, height: 15)

            Text(Fmt.temperature(group.primary, unit: app.settings.unit))
                .font(Theme.numberFont(14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, alignment: .trailing)

            Text(app.settings.unit.shortLabel)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: 60 秒趋势

    private var cpuGroup: TemperatureGroup? {
        app.primaryGroups.first { $0.category == .cpu }
    }

    private var cpuHistory: [Double] {
        app.historyValues(for: SensorCategory.cpu.rawValue)
    }

    private var trendSection: some View {
        let color = Theme.temperatureColor(cpuGroup?.primary)
        let values = cpuHistory
        let minimum = values.min()
        let maximum = values.max()
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                Text("CPU 温度趋势")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let minimum, let maximum {
                    Text("\(Fmt.temperature(minimum, unit: app.settings.unit))° — \(Fmt.temperature(maximum, unit: app.settings.unit))°")
                        .font(Theme.numberFont(9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Text("60 秒")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
            }
            Sparkline(values: values, color: color, lineWidth: 1.3)
                .frame(height: 56)
        }
        .padding(10)
        .background(shape.fill(Theme.track.opacity(0.32)))
        .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.top, 3)
        .padding(.bottom, 9)
    }

    // MARK: 状态条

    private var statusStrip: some View {
        HStack(spacing: 0) {
            miniStat(
                symbol: "thermometer.variable",
                label: "热压力",
                value: app.thermalPressure.title,
                tint: Theme.thermalColor(app.thermalPressure)
            )
            statDivider
            miniStat(
                symbol: "fanblades",
                label: "风扇",
                value: fanText,
                tint: app.fans.isEmpty ? Theme.tempCool : Theme.accent
            )
            statDivider
            miniStat(
                symbol: "bolt.fill",
                label: "整机功耗",
                value: Fmt.watts(app.powerWatts),
                tint: Theme.tempYellow
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 24)
    }

    private func miniStat(symbol: String, label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(Theme.numberFont(11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var fanText: String {
        if app.fans.isEmpty { return "被动散热" }
        let rpms = app.fans.compactMap(\.rpm)
        guard let first = rpms.first else { return "不可用" }
        return Fmt.rpm(first)
    }

    // MARK: 占位

    private var scanningPlaceholder: some View {
        VStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 9) {
                    SkeletonBlock(width: 24, height: 24, cornerRadius: 7)
                    VStack(alignment: .leading, spacing: 4) {
                        SkeletonBlock(width: 72, height: 9)
                        SkeletonBlock(width: 44, height: 7)
                    }
                    Spacer(minLength: 0)
                    SkeletonBlock(width: 60, height: 14, cornerRadius: 6)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 5) {
            Image(systemName: "thermometer.medium.slash")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)
            Text(app.scanError ?? "暂无温度数据")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: 操作

    private var actions: some View {
        VStack(spacing: 7) {
            Button(action: openMainWindow) {
                HStack(spacing: 6) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11, weight: .semibold))
                    Text("打开主窗口")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.accentGradientHorizontal))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("退出 MacTemp")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.track.opacity(0.4)))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text("MacTemp v\(AppMetadata.version) · AppleSMC 原生监控")
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Text("\(app.sensors.filter { $0.isAvailable }.count) 测点")
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.top, 7)
        .padding(.bottom, 10)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
