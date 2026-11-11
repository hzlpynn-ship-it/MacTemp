import Foundation

// MacTemp 命令行自测：不启动 GUI，验证 SMC、采集器与数据聚合是否正常。
// 用法：MacTemp.app/Contents/MacOS/MacTemp --selftest

enum SelfTest {
    static func runAndExit() -> Never {
        print("========== MacTemp 自测 ==========")
        let monitor = SMCMonitor()
        let started = monitor.start()
        print("[SMC] 启动: \(started ? "成功" : "失败") | \(monitor.scanSummary)")
        if let error = monitor.lastError {
            print("[SMC] 错误: \(error)")
        }
        if let profile = monitor.profile {
            print("[芯片] \(profile.chipName) family=\(profile.family) model=\(profile.modelIdentifier) P=\(profile.pCores) E=\(profile.eCores) GPU=\(profile.gpuCores)")
        }

        let snapshot = monitor.sample()
        print("[采样] 有效温度传感器: \(snapshot.validSensorCount)/\(snapshot.sensors.count) | 风扇: \(snapshot.fans.count) | 功耗: "
            + (snapshot.powerWatts.map { String(format: "%.2f W", $0) } ?? "--"))
        print("[分组]")
        for group in snapshot.groups {
            let primary = group.primary.map { String(format: "%.1f°C", $0) } ?? "--"
            let average = group.average.map { String(format: "%.1f°C", $0) } ?? "--"
            let maximum = group.maximum.map { String(format: "%.1f°C", $0) } ?? "--"
            print("  - \(group.title) [\(group.id)] primary=\(primary) avg=\(average) max=\(maximum) n=\(group.sensorCount)")
        }
        print("[CPU 核心] " + snapshot.cpuCores.map {
            "\($0.name)=\($0.celsius.map { String(format: "%.1f", $0) } ?? "--")"
        }.joined(separator: " | "))
        print("[全部可用温度传感器]")
        for sensor in snapshot.sensors where sensor.celsius != nil {
            let value = sensor.celsius.map { String(format: "%.1f", $0) } ?? "--"
            print("  \(sensor.key)  \(sensor.name)  \(value)°C  \(sensor.category.rawValue)")
        }

        print("[系统信息]")
        let info = SystemInfoCollector().collect()
        print("  机型: \(info.modelName) (\(info.modelIdentifier)) 芯片: \(info.chipName)")
        print("  核心: \(info.totalCores) (\(info.performanceCores)P+\(info.efficiencyCores)E) GPU: \(info.gpuCores) 核")
        print("  内存: \(ByteCountFormatter.string(fromByteCount: Int64(info.memoryBytes), countStyle: .memory))")
        print("  系统: \(info.macOSVersion) build=\(info.macOSBuild) kernel=\(info.kernelVersion)")
        print("  运行时间: \(Int(info.uptime / 3600)) 小时 | 主机名: \(info.hostname)")
        print("  电池: " + (info.battery.map { "\(Int($0.chargePercent))% charging=\($0.isCharging) cycle=\($0.cycleCount.map(String.init) ?? "-") health=\($0.healthPercent.map { String(format: "%.0f%%", $0) } ?? "-")" } ?? "无"))
        print("  显示器: " + info.displays.map { "\($0.name) \($0.resolution) @\($0.refreshRate.map { String(format: "%.0f", $0) } ?? "-")Hz" }.joined(separator: ", "))
        print("  磁盘: " + info.disks.map { "\($0.name) \(ByteCountFormatter.string(fromByteCount: Int64($0.totalBytes), countStyle: .file)) 可用 \(ByteCountFormatter.string(fromByteCount: Int64($0.freeBytes), countStyle: .file))" }.joined(separator: " | "))
        print("  网络: " + info.networks.prefix(6).map { "\($0.name)=\($0.ipv4 ?? "-")" }.joined(separator: ", "))

        print("[实时负载]")
        let collector = LiveStatsCollector()
        _ = collector.sample()
        Thread.sleep(forTimeInterval: 1.2)
        let live = collector.sample()
        print(String(format: "  CPU: %.1f%% (user %.1f%% sys %.1f%%) | 每核: %@",
                      live.cpuUsage * 100, live.cpuUser * 100, live.cpuSystem * 100,
                      live.perCoreUsage.map { String(format: "%.0f%%", $0 * 100) }.joined(separator: " ")))
        print("  内存: 已用 \(ByteCountFormatter.string(fromByteCount: Int64(live.memoryUsed), countStyle: .memory)) / \(ByteCountFormatter.string(fromByteCount: Int64(live.memoryTotal), countStyle: .memory)) | swap: \(ByteCountFormatter.string(fromByteCount: Int64(live.swapUsed), countStyle: .memory))")
        print(String(format: "  网络: ↓ %.1f KB/s ↑ %.1f KB/s", live.networkDownBytesPerSec / 1024, live.networkUpBytesPerSec / 1024))
        print("  进程数: \(live.processCount) | Top: " + live.topProcesses.prefix(5).map {
            "\($0.name)(\(String(format: "%.1f%%", $0.cpuUsage * 100)))"
        }.joined(separator: ", "))
        print("========== 自测结束 ==========")
        exit(0)
    }
}
