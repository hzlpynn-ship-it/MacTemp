// MacTemp / Sources/Collectors/CollectorSelfTest.swift
// 归属：collectors（采集器）——命令行自检入口。
//
// 用法（开发期，不进入 App 正常流程）：
//   在 /tmp 写一个 main.swift 调用 `print(CollectorSelfTest.run())`，
//   与 Sources/Models/Models.swift + Sources/Collectors/*.swift 一起 swiftc 编译执行。
// 自检会真实采集一次静态信息 + 连续 5 帧实时负载，并输出：
//   设备/核心/内存/磁盘/网络/电池/进程等人类可读摘要、5 次 sample() 耗时、首帧行为检查、
//   以及字段合法性检查（网络非负/非 NaN、内存不超过总量、电池温度范围等）。

import Foundation

enum CollectorSelfTest {
    static func run() -> String {
        let overallStart = Date()
        var lines: [String] = []
        lines.append("=== MacTemp 采集器自检 ===")
        lines.append("时间: \(dateText(Date()))")
        lines.append("")

        // MARK: 静态系统信息
        let infoCollector = SystemInfoCollector()
        let infoStart = Date()
        let info = infoCollector.collect()
        let infoCostMilliseconds = Date().timeIntervalSince(infoStart) * 1000

        lines.append("【系统信息 SystemInfoCollector】耗时 \(fixed(infoCostMilliseconds)) ms")
        lines.append("  机型: \(info.modelName)  (\(info.modelIdentifier))")
        lines.append("  芯片: \(info.chipName)   架构: \(info.architecture)")
        lines.append("  核心: \(info.totalCores) 逻辑核（\(info.performanceCores)P + \(info.efficiencyCores)E），GPU \(info.gpuCores) 核")
        lines.append("  内存: \(byteText(info.memoryBytes))（\(info.memoryBytes) 字节）")
        lines.append("  系统: \(info.macOSVersion)  Build \(info.macOSBuild)  内核 \(info.kernelVersion)")
        lines.append("  启动时间: \(dateText(info.bootDate))   已运行: \(durationText(info.uptime))")
        lines.append("  主机名: \(info.hostname)")
        lines.append("  序列号: \(info.serialNumber)   硬件 UUID: \(info.hardwareUUID)")
        lines.append("  供电来源: \(info.powerSource)")
        // 同一进程内再 collect() 一次：用于区分"首次 CoreGraphics/IOKit 连接"与稳定的采集开销。
        let secondCollectStart = Date()
        _ = infoCollector.collect()
        let secondCollectCost = Date().timeIntervalSince(secondCollectStart) * 1000
        lines.append("  重复 collect() 耗时: \(fixed(secondCollectCost)) ms（首次调用含 CG/IOKit 连接初始化开销）")

        if info.displays.isEmpty {
            lines.append("  显示器: 无（CoreGraphics 未返回活动显示器）")
        } else {
            for display in info.displays {
                let rate = display.refreshRate.map { "\(fixed($0)) Hz" } ?? "刷新率未知"
                lines.append("  显示器: \(display.name)  \(display.resolution)  \(rate)\(display.isMain ? "  [主显示器]" : "")")
            }
        }

        if info.disks.isEmpty {
            lines.append("  存储卷: 无")
        } else {
            for disk in info.disks {
                lines.append("  存储卷: \(disk.name)  挂载 \(disk.mountPoint)  文件系统 \(disk.fileSystem)  "
                    + "容量 \(byteText(disk.totalBytes))  可用 \(byteText(disk.freeBytes))"
                    + "  内置:\(disk.isInternal ? "是" : "否")  可移除:\(disk.isRemovable ? "是" : "否")")
            }
        }

        if info.networks.isEmpty {
            lines.append("  网络接口: 无")
        } else {
            for network in info.networks {
                lines.append("  网络接口: \(network.name) [\(network.typeLabel)]  IPv4 \(network.ipv4 ?? "-")"
                    + "  IPv6 \(network.ipv6 ?? "-")  MAC \(network.macAddress ?? "-")  \(network.isUp ? "已启用" : "未启用")")
            }
        }

        lines.append("")
        lines.append("【电池 BatteryCollector】")
        appendBatterySection(&lines)
        lines.append("")

        // MARK: 实时负载：连续 5 帧
        lines.append("【实时负载 LiveStatsCollector】")
        let liveCollector = LiveStatsCollector()
        var frameCosts: [Double] = []
        var frames: [LiveStats] = []

        // 第 1 帧：首帧（建立基线，间隔过短时 CPU/网络应为 0）
        frames.append(liveCollector.sample())
        frameCosts.append(liveCollector.lastSampleDuration * 1000)
        let firstFrame = frames[0]
        lines.append("  第 1 帧（首帧，建立基线）: cpuUsage=\(percent(firstFrame.cpuUsage))  "
            + "网络 下行 \(rateText(firstFrame.networkDownBytesPerSec)) / 上行 \(rateText(firstFrame.networkUpBytesPerSec))"
            + "  耗时 \(fixed(frameCosts[0])) ms")

        // 第 2 帧：间隔 1.0s，等价于 App 的刷新间隔，作为主要读数展示
        Thread.sleep(forTimeInterval: 1.0)
        frames.append(liveCollector.sample())
        frameCosts.append(liveCollector.lastSampleDuration * 1000)

        // 第 3~5 帧：间隔 0.35s，纯粹用于统计 sample() 耗时分布
        for _ in 0..<3 {
            Thread.sleep(forTimeInterval: 0.35)
            frames.append(liveCollector.sample())
            frameCosts.append(liveCollector.lastSampleDuration * 1000)
        }

        let primary = frames[1]
        let corePercent = primary.perCoreUsage.map { fixed($0 * 100) + "%" }.joined(separator: " ")
        let loadText = primary.loadAverage.map { fixed($0, digits: 2) }.joined(separator: " / ")
        lines.append("  第 2 帧（间隔 1.0s）: CPU \(percent(primary.cpuUsage))  "
            + "(user \(percent(primary.cpuUser)) / system \(percent(primary.cpuSystem)) / idle \(percent(primary.cpuIdle)))")
        lines.append("    每核占用: \(corePercent)")
        lines.append("    负载均值(1/5/15): \(loadText.isEmpty ? "-" : loadText)   逻辑核数: \(liveCollector.lastCoreCount)")
        lines.append("    内存: 已用 \(byteText(primary.memoryUsed)) / 共 \(byteText(primary.memoryTotal))"
            + "（\(percent(Double(primary.memoryUsed) / Double(max(1, primary.memoryTotal))))）"
            + "  联动 \(byteText(primary.memoryWired))  压缩 \(byteText(primary.memoryCompressed))"
            + "  缓存 \(byteText(primary.memoryCached))  空闲 \(byteText(primary.memoryFree))")
        if primary.swapTotal > 0 {
            lines.append("    交换区: 已用 \(byteText(primary.swapUsed)) / 共 \(byteText(primary.swapTotal))")
        } else {
            lines.append("    交换区: 未使用")
        }
        lines.append("    网络: 下行 \(rateText(primary.networkDownBytesPerSec))  上行 \(rateText(primary.networkUpBytesPerSec))")
        let diskText: String
        if let read = primary.diskReadBytesPerSec, let write = primary.diskWriteBytesPerSec {
            diskText = "读 \(rateText(read))  写 \(rateText(write))"
        } else {
            diskText = "不可用（nil，UI 显示 --）"
        }
        lines.append("    磁盘: \(diskText)")
        let gpuText = primary.gpuUsage.map { percent($0) } ?? "不可用（nil，UI 显示 --）"
        lines.append("    GPU 利用率: \(gpuText)")
        lines.append("    进程总数: \(primary.processCount)")
        lines.append("    CPU 占用前 5 的进程（第 2 帧，差分 1.0s）:")
        for (index, process) in primary.topProcesses.prefix(5).enumerated() {
            lines.append("      \(index + 1). \(process.name)  PID \(process.pid)  "
                + "CPU \(percent(process.cpuUsage))  内存 \(byteText(process.memoryBytes))")
        }
        if primary.topProcesses.isEmpty {
            lines.append("      （无：proc_pidinfo 权限不足或进程枚举失败）")
        }

        let costText = frameCosts.map { fixed($0) }.joined(separator: " / ")
        let maximumCost = frameCosts.max() ?? 0
        let minimumCost = frameCosts.min() ?? 0
        let averageCost = frameCosts.reduce(0, +) / Double(max(1, frameCosts.count))
        lines.append("  sample() 5 次耗时: \(costText) ms")
        lines.append("  耗时统计: 最小 \(fixed(minimumCost)) ms / 平均 \(fixed(averageCost)) ms / 最大 \(fixed(maximumCost)) ms"
            + "  → \(maximumCost < 30 ? "通过（<30ms）" : "超标（>30ms，需要排查）")")

        // MARK: 校验项
        lines.append("")
        lines.append("【校验项】")
        var checks: [(String, Bool, String)] = []
        checks.append(("CPU 型号非空且核心数 > 0",
                       !info.chipName.isEmpty && info.totalCores > 0,
                       "\(info.chipName) / \(info.totalCores) 核"))
        checks.append(("逻辑核数与 host_processor_info 一致",
                       liveCollector.lastCoreCount == info.totalCores,
                       "采样 \(liveCollector.lastCoreCount) / sysctl \(info.totalCores)"))
        checks.append(("内存总量 > 0 且 已用 ≤ 总量",
                       info.memoryBytes > 0 && primary.memoryTotal > 0 && primary.memoryUsed <= primary.memoryTotal,
                       "已用 \(byteText(primary.memoryUsed)) / 共 \(byteText(primary.memoryTotal))"))
        checks.append(("网络速率有限且非负（无 NaN / 负数）",
                       primary.networkDownBytesPerSec.isFinite && primary.networkDownBytesPerSec >= 0
                           && primary.networkUpBytesPerSec.isFinite && primary.networkUpBytesPerSec >= 0,
                       "下行 \(rateText(primary.networkDownBytesPerSec)) / 上行 \(rateText(primary.networkUpBytesPerSec))"))
        checks.append(("首帧每核数组长度 = 逻辑核数",
                       firstFrame.perCoreUsage.count == info.totalCores,
                       "\(firstFrame.perCoreUsage.count) 个"))
        checks.append(("第 2 帧 CPU 占用在 0...1",
                       primary.cpuUsage >= 0 && primary.cpuUsage <= 1,
                       percent(primary.cpuUsage)))
        checks.append(("进程列表非空（权限足够时）",
                       !primary.topProcesses.isEmpty,
                       "\(primary.topProcesses.count) 个 / 共 \(primary.processCount) 进程"))
        if let battery = info.battery, let temperature = battery.temperatureCelsius {
            checks.append(("电池温度在合理范围（-20...80°C）",
                           temperature > -20 && temperature < 80,
                           "\(fixed(temperature)) °C"))
        }
        for (name, passed, detail) in checks {
            lines.append("  [\(passed ? "通过" : "失败")] \(name)：\(detail)")
        }
        let failedCount = checks.filter { !$0.1 }.count
        lines.append("  全部校验: \(failedCount == 0 ? "通过" : "\(failedCount) 项失败")")

        let totalCost = Date().timeIntervalSince(overallStart)
        lines.append("")
        lines.append("=== 自检完成，总耗时 \(fixed(totalCost, digits: 2)) s ===")
        return lines.joined(separator: "\n")
    }

    // MARK: - 电池

    private static func appendBatterySection(_ lines: inout [String]) {
        guard let battery = BatteryCollector.collect() else {
            lines.append("  无电池（台式机 / 无电池机型 / 读取失败 → SystemInfo.battery = nil）")
            return
        }
        lines.append("  存在: \(battery.isPresent ? "是" : "否")   电量: \(fixed(battery.chargePercent))%"
            + "   充电中: \(battery.isCharging ? "是" : "否")   已接电源: \(battery.isPluggedIn ? "是" : "否")")
        let remaining = battery.timeRemainingMinutes.map { "\($0) 分钟" } ?? "未知"
        lines.append("  预计可用/充满时间: \(remaining)")
        let cycle = battery.cycleCount.map { "\($0) 次" } ?? "-"
        let health = battery.healthPercent.map { "\(fixed($0))%" } ?? "-"
        lines.append("  循环次数: \(cycle)   健康度(最大容量): \(health)   状态: \(battery.condition ?? "-")")
        let design = battery.designCapacitymAh.map { "\($0) mAh" } ?? "-"
        let maximum = battery.maxCapacitymAh.map { "\($0) mAh" } ?? "-"
        let current = battery.currentCapacitymAh.map { "\($0) mAh" } ?? "-"
        lines.append("  容量: 设计 \(design)   实际最大 \(maximum)   当前 \(current)")
        let temperature = battery.temperatureCelsius.map { "\(fixed($0)) °C" } ?? "-"
        lines.append("  电芯温度: \(temperature)   （AppleSmartBattery.Temperature 按 0.1K 换算，"
            + "已用 smctemp TB0T/TB1T 交叉验证）")
    }

    // MARK: - 格式化

    private static func fixed(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value)
    }

    private static func percent(_ value: Double) -> String {
        fixed(value * 100, digits: 1) + "%"
    }

    private static func byteText(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        return fixed(value, digits: unitIndex >= 3 ? 2 : 1) + " " + units[unitIndex]
    }

    private static func rateText(_ bytesPerSecond: Double) -> String {
        byteText(UInt64(max(0, bytesPerSecond))) + "/s"
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时 \(minutes) 分" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分"
    }

    private static func dateText(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
