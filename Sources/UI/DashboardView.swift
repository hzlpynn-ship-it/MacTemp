import SwiftUI

// 概览页：6 张主部件温度卡（含 60 秒 sparkline）+ 实时负载卡 + 系统状态卡。

struct DashboardView: View {
    @EnvironmentObject private var app: AppState

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if app.isScanning && app.primaryGroups.isEmpty {
                skeletonGrid
            } else if app.primaryGroups.isEmpty {
                GlassCard(padding: 6) {
                    EmptyStateView(
                        symbol: "thermometer.medium.slash",
                        title: "未发现温度传感器",
                        message: "当前没有可用的 SMC 温度测点。请确认机型受支持，或尝试重新扫描。",
                        actionTitle: "重新扫描",
                        action: { app.rescanSensors() }
                    )
                }
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(app.primaryGroups) { group in
                        TemperatureCard(
                            group: group,
                            history: app.historyValues(for: group.id),
                            unit: app.settings.unit
                        )
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    LiveLoadCard()
                        .frame(maxWidth: .infinity)
                    SystemStatusCard()
                        .frame(width: 318)
                }

                dashboardFooter
            }
        }
    }

    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonTemperatureCard()
            }
        }
    }

    private var dashboardFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.accent.opacity(0.8))
            Text("数据来自 AppleSMC 原生传感器 · 每 \(Int(app.refreshInterval)) 秒刷新 · 保留最近 60 个采样")
                .font(Theme.captionFont)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            Text("更新于 \(Fmt.clock(app.lastUpdated))")
                .font(Theme.numberFont(9.5, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }
}

// MARK: - 主部件温度卡

struct TemperatureCard: View {
    let group: TemperatureGroup
    let history: [Double]
    let unit: TemperatureUnit

    private var color: Color { Theme.temperatureColor(group.primary) }
    private var isAvailable: Bool { group.primary != nil }

    var body: some View {
        GlassCard(cornerRadius: 17, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 9) {
                    SymbolChip(symbol: group.symbolName, tint: color, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.title)
                            .font(Theme.cardTitleFont)
                            .lineLimit(1)
                        Text(group.subtitle)
                            .font(Theme.captionFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    StatusPill(
                        text: isAvailable ? Theme.temperatureStatus(group.primary) : "不可用",
                        color: color,
                        showsDot: false
                    )
                    .opacity(isAvailable ? 1 : 0.6)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(Fmt.temperature(group.primary, unit: unit))
                        .font(Theme.heroFont(30))
                        .foregroundStyle(color)
                    Text(unit.shortLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 1)
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("平均 \(Fmt.temperature(group.average, unit: unit))")
                            .font(Theme.captionFont)
                            .foregroundStyle(.secondary)
                        Text("最高 \(Fmt.temperature(group.maximum, unit: unit))")
                            .font(Theme.captionFont)
                            .foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }

                Sparkline(values: history, color: color, lineWidth: 1.6)
                    .frame(height: 31)

                HStack(spacing: 4) {
                    Text("60 秒趋势")
                        .font(Theme.captionFont)
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Text("\(group.sensorCount) 个测点")
                        .font(Theme.captionFont)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - 实时负载卡

struct LiveLoadCard: View {
    @EnvironmentObject private var app: AppState

    private var stats: LiveStats { app.liveStats }
    private var memoryProgress: Double {
        guard stats.memoryTotal > 0 else { return 0 }
        return min(max(Double(stats.memoryUsed) / Double(stats.memoryTotal), 0), 1)
    }

    var body: some View {
        GlassCard(padding: 15) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 9) {
                    SymbolChip(symbol: "speedometer", tint: Theme.accent, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("实时负载")
                            .font(Theme.cardTitleFont)
                        Text("每秒采样 · \(max(app.systemInfo.totalCores, stats.perCoreUsage.count)) 核心")
                            .font(Theme.captionFont)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    loadAverageView
                }

                HStack(spacing: 16) {
                    RingGauge(
                        progress: stats.cpuUsage,
                        color: Theme.loadColor(stats.cpuUsage),
                        lineWidth: 7,
                        size: 74
                    ) {
                        VStack(spacing: 0) {
                            Text(Fmt.percent(stats.cpuUsage))
                                .font(Theme.numberFont(16, weight: .semibold))
                                .foregroundStyle(Theme.loadColor(stats.cpuUsage))
                            Text("CPU")
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            Text("每核心占用")
                                .font(Theme.captionFont)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text(coreSplitText)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        CoreUsageBars(values: stats.perCoreUsage, height: 32)
                        HStack(spacing: 4) {
                            Text("0%")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.tertiary)
                            Spacer(minLength: 0)
                            Text("100%")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 8) {
                    LoadTile(symbol: "memorychip", label: "内存", tint: Theme.accent) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(Fmt.percent(memoryProgress))
                                .font(Theme.numberFont(14, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        MiniBar(progress: memoryProgress, color: Theme.accent, height: 4)
                        Text("\(Fmt.bytes(stats.memoryUsed)) / \(Fmt.bytes(stats.memoryTotal))")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    LoadTile(symbol: "network", label: "网络", tint: Theme.tempGreen) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.tempCool)
                            Text(Fmt.speed(stats.networkDownBytesPerSec))
                                .font(Theme.numberFont(11, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.accentDeep)
                            Text(Fmt.speed(stats.networkUpBytesPerSec))
                                .font(Theme.numberFont(11, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }

                    LoadTile(symbol: "list.bullet", label: "进程", tint: Theme.tempYellow) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(Fmt.count(stats.processCount))
                                .font(Theme.numberFont(14, weight: .semibold))
                            Text("个")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                        }
                        Text(stats.topProcesses.first.map { "最高 \($0.name)" } ?? "暂无进程数据")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                DividerLine()

                HStack(spacing: 14) {
                    loadFooterMetric(
                        icon: "internaldrive",
                        label: "磁盘读",
                        value: stats.diskReadBytesPerSec.map { Fmt.speed($0) } ?? "--"
                    )
                    loadFooterMetric(
                        icon: "internaldrive",
                        label: "磁盘写",
                        value: stats.diskWriteBytesPerSec.map { Fmt.speed($0) } ?? "--"
                    )
                    loadFooterMetric(
                        icon: "arrow.left.arrow.right",
                        label: "交换内存",
                        value: stats.swapTotal > 0
                            ? "\(Fmt.bytes(stats.swapUsed)) / \(Fmt.bytes(stats.swapTotal))"
                            : "未使用"
                    )
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func loadFooterMetric(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(label)
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(Theme.numberFont(9, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var loadAverageView: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("平均负载")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
            Text(loadAverageText)
                .font(Theme.numberFont(11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var loadAverageText: String {
        let values = stats.loadAverage.prefix(3)
        guard !values.isEmpty else { return "--" }
        return values.map { String(format: "%.2f", $0) }.joined(separator: "  ")
    }

    private var coreSplitText: String {
        let info = app.systemInfo
        if info.performanceCores > 0 || info.efficiencyCores > 0 {
            return "\(info.performanceCores)P + \(info.efficiencyCores)E"
        }
        return stats.perCoreUsage.isEmpty ? "" : "\(stats.perCoreUsage.count) 核"
    }
}

/// 负载卡内部的小指标块。
struct LoadTile<Content: View>: View {
    var symbol: String
    var label: String
    var tint: Color = Theme.accent
    private let content: Content

    init(symbol: String, label: String, tint: Color = Theme.accent, @ViewBuilder content: () -> Content) {
        self.symbol = symbol
        self.label = label
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(shape.fill(Theme.track.opacity(0.42)))
        .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - 系统状态卡

struct SystemStatusCard: View {
    @EnvironmentObject private var app: AppState

    private var pressureColor: Color { Theme.thermalColor(app.thermalPressure) }

    var body: some View {
        GlassCard(padding: 15) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 9) {
                    SymbolChip(symbol: "thermometer.variable", tint: pressureColor, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("系统状态")
                            .font(Theme.cardTitleFont)
                        Text("热压力与供电")
                            .font(Theme.captionFont)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    StatusPill(text: app.thermalPressure.title, color: pressureColor)
                }

                Text(app.thermalPressure.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                DividerLine()

                VStack(spacing: 0) {
                    statusRow(
                        symbol: "fanblades",
                        label: "风扇",
                        value: fanText,
                        tint: app.fans.isEmpty ? Theme.tempCool : Theme.accent
                    )
                    statusRow(
                        symbol: "bolt.fill",
                        label: "整机功耗",
                        value: Fmt.watts(app.powerWatts),
                        tint: Theme.tempYellow
                    )
                    statusRow(
                        symbol: "clock",
                        label: "运行时间",
                        value: uptimeText,
                        tint: Theme.accentDeep
                    )
                    statusRow(
                        symbol: "powerplug.fill",
                        label: "供电",
                        value: powerSourceText,
                        tint: Theme.tempGreen
                    )
                    statusRow(
                        symbol: "thermometer.high",
                        label: "最高温度",
                        value: Fmt.temperatureWithUnit(app.maxTemperature, unit: app.settings.unit),
                        tint: Theme.temperatureColor(app.maxTemperature)
                    )
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Text("更新于 \(Fmt.clock(app.lastUpdated))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Text("\(app.sensors.filter { $0.isAvailable }.count) 个测点可用")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func statusRow(symbol: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(label)
                .font(Theme.labelFont)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(Theme.numberFont(11.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(height: 26)
    }

    private var fanText: String {
        if app.fans.isEmpty {
            return "无风扇 · 被动散热"
        }
        let rpms = app.fans.compactMap(\.rpm)
        if rpms.isEmpty { return "转速不可用" }
        return rpms.map { Fmt.rpm($0) }.joined(separator: " / ")
    }

    private var uptimeText: String {
        let info = app.systemInfo
        guard info.totalCores > 0 else { return "--" }
        let byBoot = Date().timeIntervalSince(info.bootDate)
        return Fmt.uptime(max(byBoot, info.uptime))
    }

    private var powerSourceText: String {
        let source = app.systemInfo.powerSource
        return source.isEmpty ? "--" : source
    }
}
