import SwiftUI
import Foundation

// 系统信息页：设备 / 芯片 / 内存 / 系统 / 电池 / 显示 / 存储 / 网络 卡片网格。

struct SystemInfoView: View {
    @EnvironmentObject private var app: AppState

    private var info: SystemInfo { app.systemInfo }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                deviceCard
                    .frame(maxWidth: .infinity)
                chipCard
                    .frame(maxWidth: .infinity)
            }

            HStack(alignment: .top, spacing: 14) {
                memoryCard
                    .frame(maxWidth: .infinity)
                systemCard
                    .frame(maxWidth: .infinity)
            }

            HStack(alignment: .top, spacing: 14) {
                batteryCard
                    .frame(maxWidth: .infinity)
                displayCard
                    .frame(maxWidth: .infinity)
            }

            HStack(alignment: .top, spacing: 14) {
                storageCard
                    .frame(maxWidth: .infinity)
                networkCard
                    .frame(maxWidth: .infinity)
            }

            footer
        }
    }

    // MARK: 设备

    private var deviceCard: some View {
        InfoCard(
            title: "设备",
            symbol: "laptopcomputer",
            tint: Theme.accent
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(textOrDash(info.modelName))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    KeyBadge(text: textOrDash(info.modelIdentifier))
                    StatusPill(text: info.architecture, color: Theme.accentDeep, showsDot: false)
                }
                DividerLine()
                InfoRow(label: "主机名", value: textOrDash(info.hostname), mono: false)
                InfoRow(label: "序列号", value: textOrDash(info.serialNumber))
                InfoRow(label: "硬件 UUID", value: textOrDash(info.hardwareUUID))
                InfoRow(label: "启动时间", value: Fmt.day(info.bootDate) + " " + Fmt.clock(info.bootDate))
            }
        }
    }

    // MARK: 芯片

    private var chipCard: some View {
        InfoCard(
            title: "芯片",
            symbol: "cpu",
            tint: Theme.tempCool
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(textOrDash(info.chipName))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("\(textOrDash(info.architecture)) · \(info.totalCores) 核心")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                DividerLine()
                InfoRow(label: "总核心", value: "\(info.totalCores) 核")
                InfoRow(label: "性能核心", value: "\(info.performanceCores) 核", valueColor: Theme.accentDeep)
                InfoRow(label: "能效核心", value: "\(info.efficiencyCores) 核", valueColor: Theme.tempCool)
                InfoRow(label: "GPU 核心", value: info.gpuCores > 0 ? "\(info.gpuCores) 核" : "--")
                if info.performanceCores + info.efficiencyCores > 0 {
                    coreCompositionBar
                }
            }
        }
    }

    private var coreCompositionBar: some View {
        HStack(spacing: 2) {
            ForEach(0..<max(info.performanceCores, 0), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Theme.accentDeep)
                    .frame(height: 5)
            }
            ForEach(0..<max(info.efficiencyCores, 0), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Theme.accent.opacity(0.75))
                    .frame(height: 5)
            }
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    // MARK: 内存

    private var memoryCard: some View {
        let stats = app.liveStats
        let total = info.memoryBytes > 0 ? info.memoryBytes : stats.memoryTotal
        let used = stats.memoryUsed
        let fraction = total > 0 ? min(max(Double(used) / Double(total), 0), 1) : 0

        return InfoCard(
            title: "内存",
            symbol: "memorychip",
            tint: Theme.tempGreen,
            trailing: "统一内存"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.bytes(total))
                        .font(Theme.heroFont(23))
                    Spacer()
                    Text(Fmt.percent(fraction))
                        .font(Theme.numberFont(13, weight: .semibold))
                        .foregroundStyle(Theme.tempGreen)
                }
                MiniBar(progress: fraction, color: Theme.tempGreen, height: 6)
                HStack(spacing: 4) {
                    Text("已用 \(Fmt.bytes(used))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Text("可用 \(Fmt.bytes(max(total, used) - used))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                DividerLine()
                InfoRow(label: "物理内存", value: Fmt.bytes(info.memoryBytes))
                InfoRow(label: "联动内存", value: stats.memoryWired > 0 ? Fmt.bytes(stats.memoryWired) : "--")
                InfoRow(label: "已压缩", value: stats.memoryCompressed > 0 ? Fmt.bytes(stats.memoryCompressed) : "--")
                InfoRow(label: "文件缓存", value: stats.memoryCached > 0 ? Fmt.bytes(stats.memoryCached) : "--")
            }
        }
    }

    // MARK: 系统

    private var systemCard: some View {
        InfoCard(
            title: "系统",
            symbol: "gear",
            tint: Theme.tempYellow
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(macOSDisplay)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("构建 \(textOrDash(info.macOSBuild)) · \(kernelDisplay)")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                DividerLine()
                InfoRow(label: "系统版本", value: macOSDisplay)
                InfoRow(label: "构建版本", value: textOrDash(info.macOSBuild))
                InfoRow(label: "内核版本", value: kernelDisplay)
                InfoRow(label: "运行时间", value: Fmt.uptime(uptimeSeconds))
                InfoRow(label: "系统架构", value: textOrDash(info.architecture))
            }
        }
    }

    private var uptimeSeconds: TimeInterval {
        let byBoot = Date().timeIntervalSince(info.bootDate)
        return max(byBoot, info.uptime, 0)
    }

    /// collector 返回的版本号可能已带 "macOS " 前缀，避免重复拼接。
    private var macOSDisplay: String {
        let raw = info.macOSVersion
        return raw.lowercased().hasPrefix("macos") ? raw : "macOS \(raw)"
    }

    /// 内核版本同理：可能已带 "Darwin " 前缀。
    private var kernelDisplay: String {
        let raw = info.kernelVersion
        return raw.lowercased().hasPrefix("darwin") ? raw : "Darwin \(raw)"
    }

    // MARK: 电池

    private var batteryCard: some View {
        let battery = info.battery
        return InfoCard(
            title: "电池",
            symbol: "battery.75",
            tint: Theme.tempGreen,
            trailing: battery?.condition
        ) {
            if let battery, battery.isPresent {
                HStack(spacing: 18) {
                    RingGauge(
                        progress: (battery.healthPercent ?? battery.chargePercent) / 100.0,
                        color: healthColor(battery.healthPercent ?? battery.chargePercent),
                        lineWidth: 8,
                        size: 92
                    ) {
                        VStack(spacing: 1) {
                            Text(battery.healthPercent.map { "\(Int($0.rounded()))%" } ?? "--")
                                .font(Theme.heroFont(19))
                                .foregroundStyle(healthColor(battery.healthPercent ?? battery.chargePercent))
                            Text("健康度")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    VStack(spacing: 0) {
                        InfoRow(label: "当前电量", value: String(format: "%.0f%%", battery.chargePercent))
                        InfoRow(label: "充电状态", value: chargeStateText(battery))
                        InfoRow(label: "循环次数", value: battery.cycleCount.map { "\($0) 次" } ?? "--")
                        InfoRow(
                            label: "电池温度",
                            value: Fmt.temperatureWithUnit(battery.temperatureCelsius, unit: app.settings.unit)
                        )
                    }
                    .frame(maxWidth: .infinity)
                }

                DividerLine()

                HStack(spacing: 8) {
                    batteryPill(
                        icon: battery.isCharging ? "bolt.fill" : "powerplug.fill",
                        label: battery.isCharging ? "充电中" : (battery.isPluggedIn ? "已接通电源" : "电池供电"),
                        color: battery.isCharging ? Theme.tempGreen : Theme.accent
                    )
                    if let minutes = battery.timeRemainingMinutes, minutes > 0 {
                        batteryPill(icon: "clock", label: "剩余 \(minutes / 60) 小时 \(minutes % 60) 分", color: Theme.accentDeep)
                    }
                    Spacer(minLength: 0)
                }

                InfoRow(
                    label: "设计容量 / 最大容量",
                    value: capacityText(battery)
                )
            } else {
                EmptyStateView(
                    symbol: "battery.0",
                    title: "未检测到电池",
                    message: "当前设备没有内置电池，或系统未能读取电池信息。"
                )
            }
        }
    }

    private func healthColor(_ percent: Double) -> Color {
        switch percent {
        case ..<55: return Theme.tempRed
        case ..<70: return Theme.tempOrange
        case ..<85: return Theme.tempYellow
        default: return Theme.tempGreen
        }
    }

    private func chargeStateText(_ battery: BatteryInfo) -> String {
        if battery.isCharging { return "充电中" }
        if battery.isPluggedIn { return "已接通电源" }
        return "电池供电"
    }

    private func capacityText(_ battery: BatteryInfo) -> String {
        let design = battery.designCapacitymAh.map { "\($0) mAh" } ?? "--"
        let maximum = battery.maxCapacitymAh.map { "\($0) mAh" } ?? "--"
        return "\(design) / \(maximum)"
    }

    private func batteryPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.track.opacity(0.4)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: 显示

    private var displayCard: some View {
        InfoCard(
            title: "显示",
            symbol: "display",
            tint: Theme.accent,
            trailing: "\(info.displays.count) 台显示器"
        ) {
            if info.displays.isEmpty {
                EmptyStateView(symbol: "display", title: "未检测到显示器", message: "系统未返回显示设备信息。")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(info.displays.enumerated()), id: \.element.id) { index, display in
                        displayRow(display)
                        if index < info.displays.count - 1 {
                            DividerLine()
                        }
                    }
                }
            }
        }
    }

    private func displayRow(_ display: DisplayInfo) -> some View {
        HStack(spacing: 10) {
            SymbolChip(symbol: "display", tint: Theme.accent, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(display.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if display.isMain {
                        StatusPill(text: "主显示器", color: Theme.accent, showsDot: false)
                    }
                }
                HStack(spacing: 8) {
                    Text(display.resolution)
                        .font(Theme.numberFont(10, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let refresh = display.refreshRate {
                        Text("\(Int(refresh.rounded())) Hz")
                            .font(Theme.numberFont(10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    // MARK: 存储

    private var storageCard: some View {
        InfoCard(
            title: "存储",
            symbol: "internaldrive",
            tint: Theme.tempOrange,
            trailing: "\(info.disks.count) 个卷"
        ) {
            if info.disks.isEmpty {
                EmptyStateView(symbol: "internaldrive", title: "未检测到存储卷", message: "系统未返回磁盘容量信息。")
            } else {
                VStack(spacing: 10) {
                    ForEach(info.disks) { disk in
                        diskRow(disk)
                    }
                }
            }
        }
    }

    private func diskRow(_ disk: DiskInfo) -> some View {
        let total = disk.totalBytes
        let used = total >= disk.freeBytes ? total - disk.freeBytes : 0
        let fraction = total > 0 ? min(max(Double(used) / Double(total), 0), 1) : 0
        let color: Color = fraction > 0.9 ? Theme.tempRed : (fraction > 0.75 ? Theme.tempOrange : Theme.accent)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(disk.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                if disk.isInternal {
                    StatusPill(text: "内置", color: Theme.accent, showsDot: false)
                }
                if disk.isRemovable {
                    StatusPill(text: "可移除", color: Theme.tempYellow, showsDot: false)
                }
                Spacer(minLength: 0)
                Text("\(Fmt.bytes(used)) / \(Fmt.bytes(total))")
                    .font(Theme.numberFont(10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            MiniBar(progress: fraction, color: color, height: 6)
            HStack(spacing: 6) {
                Text(disk.mountPoint)
                    .font(Theme.monoFont(9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(disk.fileSystem)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Text("可用 \(Fmt.bytes(disk.freeBytes))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 网络

    private var networkCard: some View {
        InfoCard(
            title: "网络",
            symbol: "network",
            tint: Theme.accentDeep,
            trailing: "\(info.networks.filter { $0.isUp }.count) 个接口在线"
        ) {
            if info.networks.isEmpty {
                EmptyStateView(symbol: "network", title: "未检测到网络接口", message: "系统未返回网络信息。")
            } else {
                VStack(spacing: 10) {
                    ForEach(info.networks) { interface in
                        networkRow(interface)
                    }
                }
            }
        }
    }

    private func networkRow(_ interface: NetworkInterfaceInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(interface.isUp ? Theme.tempGreen : Color.secondary)
                Text(interface.name)
                    .font(.system(size: 11.5, weight: .medium))
                Text(interface.typeLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                StatusPill(
                    text: interface.isUp ? "在线" : "离线",
                    color: interface.isUp ? Theme.tempGreen : Color.secondary
                )
            }
            networkDetailRow(label: "IPv4", value: interface.ipv4)
            networkDetailRow(label: "IPv6", value: interface.ipv6)
            networkDetailRow(label: "MAC", value: interface.macAddress)
        }
    }

    private func networkDetailRow(label: String, value: String?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .leading)
            Text(textOrDash(value))
                .font(Theme.monoFont(9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    // MARK: 页脚

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 9))
                .foregroundStyle(Theme.tempGreen.opacity(0.8))
            Text("系统信息来自 sysctl / IOKit / FileManager 等系统公开接口 · 完全本地采集")
                .font(Theme.captionFont)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private func textOrDash(_ value: String?) -> String {
        guard let value, !value.isEmpty, value != "-" else { return "--" }
        return value
    }
}

// MARK: - 通用信息卡片

/// 带标题行的玻璃卡片容器。
struct InfoCard<Content: View>: View {
    let title: String
    let symbol: String
    var tint: Color = Theme.accent
    var trailing: String? = nil
    private let content: Content

    init(
        title: String,
        symbol: String,
        tint: Color = Theme.accent,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 9) {
                    SymbolChip(symbol: symbol, tint: tint, size: 28)
                    Text(title)
                        .font(Theme.cardTitleFont)
                    Spacer(minLength: 6)
                    if let trailing {
                        Text(trailing)
                            .font(Theme.captionFont)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                content
            }
        }
    }
}
