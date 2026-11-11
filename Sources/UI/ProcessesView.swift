import SwiftUI
import Foundation

// 进程页：进程总数 / CPU / 内存 / 负载概览 + CPU 占用排行表格。

struct ProcessesView: View {
    @EnvironmentObject private var app: AppState

    private var stats: LiveStats { app.liveStats }
    private var processes: [ProcessSample] { stats.topProcesses }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryCard
            processTable
            footer
        }
    }

    // MARK: 概览

    private var summaryCard: some View {
        GlassCard(padding: 0) {
            HStack(spacing: 0) {
                summaryTile(
                    symbol: "app.connected.to.app.below.fill",
                    title: "进程总数",
                    value: Fmt.count(stats.processCount) + " 个",
                    detail: "系统当前运行中",
                    tint: Theme.tempCool
                )
                verticalDivider
                summaryTile(
                    symbol: "cpu",
                    title: "CPU 总占用",
                    value: Fmt.percent(stats.cpuUsage),
                    detail: "用户 \(Fmt.percent(stats.cpuUser)) · 系统 \(Fmt.percent(stats.cpuSystem))",
                    tint: Theme.loadColor(stats.cpuUsage),
                    progress: stats.cpuUsage
                )
                verticalDivider
                summaryTile(
                    symbol: "memorychip",
                    title: "内存占用",
                    value: Fmt.percent(memoryFraction),
                    detail: "\(Fmt.bytes(stats.memoryUsed)) / \(Fmt.bytes(stats.memoryTotal))",
                    tint: Theme.tempGreen,
                    progress: memoryFraction
                )
                verticalDivider
                summaryTile(
                    symbol: "speedometer",
                    title: "平均负载",
                    value: loadAverageShort,
                    detail: "1 / 5 / 15 分钟",
                    tint: Theme.tempYellow
                )
            }
        }
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1)
            .padding(.vertical, 14)
    }

    private func summaryTile(
        symbol: String,
        title: String,
        value: String,
        detail: String,
        tint: Color,
        progress: Double? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(Theme.numberFont(19, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let progress {
                MiniBar(progress: progress, color: tint, height: 4)
            }
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var memoryFraction: Double {
        guard stats.memoryTotal > 0 else { return 0 }
        return min(max(Double(stats.memoryUsed) / Double(stats.memoryTotal), 0), 1)
    }

    private var loadAverageShort: String {
        let values = stats.loadAverage.prefix(2)
        guard !values.isEmpty else { return "--" }
        return values.map { String(format: "%.2f", $0) }.joined(separator: " / ")
    }

    // MARK: 进程表格

    private var processTable: some View {
        GlassCard(cornerRadius: 18, padding: 0) {
            VStack(spacing: 0) {
                tableHeader
                DividerLine()
                columnHeader
                DividerLine()

                if processes.isEmpty {
                    EmptyStateView(
                        symbol: "list.bullet.rectangle",
                        title: "暂无进程数据",
                        message: "进程采样尚未完成，或当前没有可读取的进程信息。"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                            ProcessRow(rank: index + 1, process: process)
                            if index < processes.count - 1 {
                                DividerLine()
                                    .padding(.leading, 14)
                                    .padding(.trailing, 14)
                            }
                        }
                    }
                }

                DividerLine()
                tableFooter
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 9) {
            SymbolChip(symbol: "list.number", tint: Theme.accent, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("CPU 占用排行")
                    .font(Theme.cardTitleFont)
                Text("按 CPU 占用从高到低排序")
                    .font(Theme.captionFont)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            StatusPill(text: "Top \(max(processes.count, 8))", color: Theme.accent, showsDot: false)
            StatusPill(text: "采样间隔 \(Int(app.refreshInterval)) 秒", color: Theme.tempGreen)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var columnHeader: some View {
        HStack(spacing: 10) {
            Text("#")
                .frame(width: 20, alignment: .center)
            Text("进程名称")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("CPU 占用")
                .frame(width: 148, alignment: .trailing)
            Text("内存")
                .frame(width: 72, alignment: .trailing)
            Text("PID")
                .frame(width: 58, alignment: .trailing)
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Theme.track.opacity(0.25))
    }

    private var tableFooter: some View {
        HStack(spacing: 5) {
            Image(systemName: "info.circle")
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
            Text("CPU 百分比按单核满载 = 100% 归一化；数据来自 libproc，每秒采样一次。")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Text("共 \(Fmt.count(stats.processCount)) 个进程 · 仅显示占用最高的 \(processes.count) 个")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 9))
                .foregroundStyle(Theme.accent.opacity(0.8))
            Text("进程数据完全在本机采集，不会上传任何信息")
                .font(Theme.captionFont)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Text("更新于 \(Fmt.clock(app.lastUpdated))")
                .font(Theme.numberFont(9.5, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - 进程行

private struct ProcessRow: View {
    let rank: Int
    let process: ProcessSample

    @State private var hovered = false

    private static let avatarPalette: [Color] = [
        Theme.accent, Theme.accentDeep, Theme.tempGreen, Theme.tempYellow,
        Theme.tempOrange, Theme.tempCool
    ]

    private var displayCPU: Double {
        max(process.cpuUsage, 0)
    }

    private var cpuColor: Color {
        Theme.loadColor(min(displayCPU, 1))
    }

    private var avatarColor: Color {
        Self.avatarPalette[abs(Int(process.pid)) % Self.avatarPalette.count]
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

        HStack(spacing: 10) {
            rankView
                .frame(width: 20, alignment: .center)

            Text(initialLetter)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(avatarColor)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(avatarColor.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(avatarColor.opacity(0.25), lineWidth: 1)
                )

            Text(process.name)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                MiniBar(progress: min(displayCPU, 1), color: cpuColor, height: 5)
                    .frame(width: 82)
                Text(String(format: "%.0f%%", displayCPU * 100))
                    .font(Theme.numberFont(10.5, weight: .semibold))
                    .foregroundStyle(cpuColor)
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(width: 148, alignment: .trailing)

            Text(Fmt.bytes(process.memoryBytes))
                .font(Theme.numberFont(10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            Text(String(process.pid))
                .font(Theme.monoFont(9.5))
                .foregroundStyle(.tertiary)
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(shape.fill(hovered ? Theme.hoverFill : Color.clear))
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var initialLetter: String {
        let trimmed = process.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    @ViewBuilder
    private var rankView: some View {
        if rank <= 3 {
            Text("\(rank)")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(rank == 1 ? Color.black.opacity(0.75) : Color.white)
                .frame(width: 17, height: 17)
                .background(
                    Circle().fill(
                        rank == 1
                            ? Theme.tempYellow
                            : (rank == 2 ? Color.secondary.opacity(0.55) : Theme.tempOrange)
                    )
                )
        } else {
            Text("\(rank)")
                .font(Theme.numberFont(10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 17, height: 17)
        }
    }
}
