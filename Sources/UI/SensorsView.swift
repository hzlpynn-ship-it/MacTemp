import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

// 传感器页：搜索 + 分类过滤 + 按分类分组的全部温度测点 + CSV 导出。

struct SensorsView: View {
    @EnvironmentObject private var app: AppState

    @State private var searchText: String = ""
    @State private var selectedCategory: SensorCategory?
    @State private var onlyAvailable: Bool = true
    @State private var exportFeedback: Bool = false

    // MARK: 过滤

    private var filteredSensors: [TemperatureSensor] {
        var list = app.sensors
        if let selectedCategory {
            list = list.filter { $0.category == selectedCategory }
        }
        if onlyAvailable {
            list = list.filter { $0.isAvailable }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || $0.key.localizedCaseInsensitiveContains(query)
            }
        }
        return list
    }

    private var groupedSensors: [SensorGroup] {
        let byCategory = Dictionary(grouping: filteredSensors, by: \.category)
        return SensorCategory.allCases
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { category in
                guard let list = byCategory[category], !list.isEmpty else { return nil }
                return SensorGroup(category: category, sensors: list)
            }
    }

    // MARK: 视图

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar

            if app.isScanning && app.sensors.isEmpty {
                GlassCard(padding: 16) {
                    VStack(spacing: 8) {
                        ForEach(0..<8, id: \.self) { _ in
                            SkeletonRow()
                        }
                    }
                }
            } else if app.sensors.isEmpty {
                GlassCard(padding: 6) {
                    EmptyStateView(
                        symbol: "thermometer.medium.slash",
                        title: "未发现温度传感器",
                        message: "当前没有读取到任何 SMC 温度测点，请尝试重新扫描，或确认设备是否受支持。",
                        actionTitle: "重新扫描",
                        action: { app.rescanSensors() }
                    )
                }
            } else {
                categoryChips
                summaryLine

                if groupedSensors.isEmpty {
                    GlassCard(padding: 6) {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "没有匹配的传感器",
                            message: "试试更换关键词、切换分类，或关闭「仅显示可用」。"
                        )
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(groupedSensors) { group in
                            SensorGroupCard(group: group, unit: app.settings.unit)
                        }
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            searchField

            HStack(spacing: 6) {
                Text("仅显示可用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                AccentSwitch(isOn: $onlyAvailable)
            }
            .fixedSize()

            Spacer(minLength: 0)

            SoftButton(
                title: exportFeedback ? "已导出" : "导出 CSV",
                symbol: exportFeedback ? "checkmark" : "square.and.arrow.up",
                tint: Theme.accent
            ) {
                exportCSV()
            }
            .disabled(app.sensors.isEmpty)
            .opacity(app.sensors.isEmpty ? 0.5 : 1)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索名称或 SMC 键…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 244, height: 27)
        .background(Capsule().fill(Theme.track.opacity(0.45)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var categoryChips: some View {
        FlowLayout(spacing: 7, lineSpacing: 7) {
            FilterChip(
                title: "全部",
                count: app.sensors.count,
                isSelected: selectedCategory == nil
            ) {
                selectedCategory = nil
            }

            ForEach(SensorCategory.allCases.sorted { $0.sortIndex < $1.sortIndex }) { category in
                let count = app.sensors.filter { $0.category == category }.count
                FilterChip(
                    title: category.title,
                    count: count,
                    isSelected: selectedCategory == category
                ) {
                    selectedCategory = selectedCategory == category ? nil : category
                }
                .opacity(count == 0 ? 0.45 : 1)
            }
        }
    }

    private var summaryLine: some View {
        let list = filteredSensors
        let availableCount = list.filter { $0.isAvailable }.count
        let maximum = list.compactMap(\.celsius).max()

        return HStack(spacing: 8) {
            summaryPill(icon: "dot.radiowaves.left.and.right", text: "\(list.count) 个测点")
            summaryPill(icon: "checkmark.circle.fill", text: "\(availableCount) 个可用", color: Theme.tempGreen)
            if let maximum {
                summaryPill(
                    icon: "thermometer.high",
                    text: "最高 \(Fmt.temperatureWithUnit(maximum, unit: app.settings.unit))",
                    color: Theme.temperatureColor(maximum)
                )
            }
            Spacer(minLength: 0)
            Text("温度条按 25–105 °C 映射 · 采样间隔 \(Int(app.refreshInterval)) 秒")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func summaryPill(icon: String, text: String, color: Color = Color.secondary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.track.opacity(0.4)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: CSV 导出

    private func exportCSV() {
        let csv = "\u{FEFF}" + app.sensorCSV()
        let stamp = Fmt.day(Date()).replacingOccurrences(of: "/", with: "-")

        let panel = NSSavePanel()
        panel.title = "导出传感器数据"
        panel.message = "CSV 文件可直接用 Excel 或 Numbers 打开"
        panel.nameFieldStringValue = "MacTemp-传感器-\(stamp).csv"
        panel.canCreateDirectories = true
        if let csvType = UTType(filenameExtension: "csv") {
            panel.allowedContentTypes = [csvType]
        }

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try csv.data(using: .utf8)?.write(to: url, options: .atomic)
                withAnimation(.easeOut(duration: 0.2)) { exportFeedback = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.2)) { exportFeedback = false }
                }
            } catch {
                NSLog("MacTemp CSV 导出失败: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - 分组模型与分组卡片

private struct SensorGroup: Identifiable {
    let category: SensorCategory
    let sensors: [TemperatureSensor]
    var id: String { category.rawValue }
}

private struct SensorGroupCard: View {
    let group: SensorGroup
    let unit: TemperatureUnit

    private var maximum: Double? { group.sensors.compactMap(\.celsius).max() }
    private var average: Double? {
        let values = group.sensors.compactMap(\.celsius)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var body: some View {
        GlassCard(cornerRadius: 16, padding: 0) {
            VStack(spacing: 0) {
                header
                DividerLine()
                ForEach(Array(group.sensors.enumerated()), id: \.element.id) { index, sensor in
                    SensorRow(sensor: sensor, unit: unit)
                        .padding(.horizontal, 6)
                    if index < group.sensors.count - 1 {
                        DividerLine()
                            .padding(.leading, 30)
                            .padding(.trailing, 6)
                    }
                }
            }
        }
    }

    private var header: some View {
        let color = Theme.temperatureColor(maximum)
        return HStack(spacing: 9) {
            SymbolChip(symbol: group.category.symbolName, tint: color, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.category.cardTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                Text("\(group.sensors.count) 个测点")
                    .font(Theme.captionFont)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            if let average {
                Text("平均 \(Fmt.temperatureWithUnit(average, unit: unit))")
                    .font(Theme.numberFont(10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let maximum {
                Text("最高 \(Fmt.temperatureWithUnit(maximum, unit: unit))")
                    .font(Theme.numberFont(10, weight: .medium))
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - 单行传感器

private struct SensorRow: View {
    let sensor: TemperatureSensor
    let unit: TemperatureUnit

    @State private var hovered = false

    var body: some View {
        let color = Theme.temperatureColor(sensor.celsius)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        HStack(spacing: 10) {
            StatusDot(
                color: color.opacity(sensor.isAvailable ? 1 : 0.35),
                size: 6
            )

            Text(sensor.name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(sensor.isAvailable ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            KeyBadge(text: sensor.key)

            Spacer(minLength: 10)

            TemperatureBar(celsius: sensor.celsius, height: 5)
                .frame(width: 108)

            Text(Fmt.temperature(sensor.celsius, unit: unit))
                .font(Theme.numberFont(11.5, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 52, alignment: .trailing)

            Text(unit.shortLabel)
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
                .frame(width: 17, alignment: .leading)

            Text(sensor.typeName.trimmingCharacters(in: .whitespaces))
                .font(Theme.monoFont(9))
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)

            Text(statusText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(sensor.isAvailable ? color.opacity(0.95) : Color.secondary)
                .frame(width: 38, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(shape.fill(hovered ? Theme.hoverFill : Color.clear))
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private var statusText: String {
        if sensor.isAvailable {
            return sensor.note ?? "正常"
        }
        return "不可用"
    }
}
