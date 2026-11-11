// MacTemp / Sources/Collectors/LiveStatsCollector.swift
// 归属：collectors（采集器）——实时负载采样（CPU / 内存 / 网络 / 磁盘 / GPU / 进程）。
//
// 性能目标：单次 sample() < 30ms（刷新间隔约 1 秒，常驻运行）。
// 实测（M4, -O 编译）：CPU ≈ 0.1ms、内存 ≈ 0.1ms、网络 ≈ 0.6ms、进程 ≈ 2~5ms、
// IOKit（GPU/磁盘）≈ 0.2ms，总计通常在 5ms 以内。为避免卡顿：
//   * 所有 C API 都在当前线程同步调用，没有网络/文件 IO 阻塞；
//   * IOKit 服务句柄在 init 时选好并持有，每帧只读单个属性；
//   * 进程枚举只对全部 pid 做一次 proc_pidinfo，进程名只对 top N 获取。
//
// ---- 关键计算口径（与"活动监视器"对齐的说明）----
// 1) CPU 占用：host_processor_info(PROCESSOR_CPU_LOAD_INFO) 返回每个逻辑核的累计 tick 计数
//    （user/system/idle/nice，单位 1/100 秒，uint32 会回绕）。本实现保存上一帧计数做差分：
//      cpuUsage  = (Δuser + Δsystem + Δnice) / Δtotal
//      cpuUser   = Δuser / Δtotal，cpuSystem = Δsystem / Δtotal，cpuIdle = Δidle / Δtotal
//      perCoreUsage[i] = (Δtotal_i - Δidle_i) / Δtotal_i
//    首帧没有差分时返回 0（cpuIdle = 1），不崩溃。
// 2) 内存：host_statistics64(HOST_VM_INFO64) 的页计数 × 页大小（本机 16KB）。口径：
//      空闲   = (free_count + speculative_count) × pageSize
//      文件缓存 = (external_page_count + purgeable_count) × pageSize   // 文件页 + 可回收页
//      已用   = 物理内存总量 - 空闲 - 文件缓存（clamp >= 0）
//    即"used ≈ total - free - cached"。活动监视器的"已使用内存"= 应用内存 + 联动内存(wired)
//    + 已压缩，与本站口径的差异主要来自 purgeable/speculative 的归类；同一台机器实测两者
//    相差约 2~3%（24GB 机器上 0.5GB 量级），本实现优先保证 used + cached + free ≈ total
//    的自洽性，便于 UI 画占用条。
// 3) 网络：getifaddrs 取 if_data.ifi_ibytes / ifi_obytes 累计值，与上一帧差分 ÷ 实际间隔。
//    统计范围 = 所有已启用的物理接口（en*，本机即 en0 Wi-Fi）之和；没有 en* 时退化为
//    所有非回环/非 AirDrop 接口之和。接口集合变化时本帧记 0，避免跨接口出现异常速率。
// 4) 进程 CPU%：proc_pidinfo(PROC_PIDTASKINFO) 的 pti_total_user/system 单位是 mach absolute
//    time tick（M4 实测 24MHz，不是纳秒），用 MachTime.timebase 换算成秒后 ÷ 实际间隔。
//    单核满载 = 1.0，多线程进程可 > 1.0（与活动监视器 400% 的语义一致）。
// 5) 磁盘：IOBlockStorageDriver.Statistics 的累计字节差分；GPU：IOAccelerator PerformanceStatistics
//    的 Device Utilization %。两者都是可选字段，采集不到保持 nil。
// 6) GPU 利用率仅在 IORegistry 提供 PerformanceStatistics 时可用；Apple Silicon 上通常可用。

import Foundation
import Darwin

final class LiveStatsCollector: LiveStatsProviding {
    /// 单个逻辑核的累计 tick（uint32，1/100 秒，会回绕，差分时按 UInt32 模运算）。
    private struct CPUTicks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    /// 一次内存采样的结果。
    private struct MemorySnapshot {
        var total: UInt64
        var used: UInt64
        var wired: UInt64
        var compressed: UInt64
        var cached: UInt64
        var free: UInt64
        var swapTotal: UInt64
        var swapUsed: UInt64
    }

    /// 与 sysctl "vm.swapusage" 对应的结构体（struct xsw_usage）。
    private struct SwapUsage {
        var total: UInt64 = 0
        var available: UInt64 = 0
        var used: UInt64 = 0
        var pageSize: UInt32 = 0
        var encrypted: Int32 = 0
    }

    private let processCollector = ProcessCollector()
    private let gpuReader = GPUReader()
    private let diskReader = DiskIOReader()

    private let pageSize: UInt64
    private let physicalMemory: UInt64

    private var previousCPUTicks: [CPUTicks] = []
    private var previousCPUTime: UInt64 = 0

    private var previousNetworkKey: String = ""
    private var previousNetworkReceived: UInt64 = 0
    private var previousNetworkSent: UInt64 = 0
    private var previousNetworkTime: UInt64 = 0

    /// 最近一次 sample() 的耗时（秒）；供 CollectorSelfTest 输出性能证据。
    private(set) var lastSampleDuration: TimeInterval = 0
    /// 最近一次采样到的逻辑核数。
    private(set) var lastCoreCount: Int = 0

    init() {
        // 页大小：Apple Silicon 为 16KB；host_page_size 失败时回退 16KB（本机实测值）。
        var size: vm_size_t = 0
        if host_page_size(mach_host_self(), &size) == KERN_SUCCESS, size > 0 {
            pageSize = UInt64(size)
        } else {
            pageSize = 16384
        }
        physicalMemory = SysctlReader.uint64("hw.memsize") ?? ProcessInfo.processInfo.physicalMemory

        // 预热基线：AppState 通常在 init 后立刻首次 sample，随后 1 秒一次；
        // 预热后第二次 sample 就有真实的 CPU/网络差分（首次仍会因间隔过短按首帧返回 0）。
        previousCPUTicks = Self.readCPUSnapshot() ?? []
        lastCoreCount = previousCPUTicks.count
        previousCPUTime = MachTime.nowNanoseconds()

        let interfaces = NetworkReader.readInterfaces()
        let counters = NetworkReader.aggregateCounters(interfaces)
        previousNetworkKey = counters.key
        previousNetworkReceived = counters.received
        previousNetworkSent = counters.sent
        previousNetworkTime = MachTime.nowNanoseconds()
    }

    func sample() -> LiveStats {
        let sampleStart = MachTime.nowNanoseconds()
        var stats = LiveStats()
        stats.timestamp = Date()

        // ---- CPU ----
        let cpuSnapshot = Self.readCPUSnapshot() ?? []
        let now = MachTime.nowNanoseconds()
        let cpuElapsed = previousCPUTime > 0 && now > previousCPUTime
            ? Double(now - previousCPUTime) / 1_000_000_000.0
            : 0
        // 间隔 < 200ms 时 tick 差噪声大，按首帧返回 0；但仍更新基线，下一帧即可给出真实值。
        let hasCPUBaseline = cpuElapsed >= 0.2 && cpuSnapshot.count == previousCPUTicks.count

        if hasCPUBaseline {
            var userDelta = 0.0
            var systemDelta = 0.0
            var idleDelta = 0.0
            var niceDelta = 0.0
            var perCore: [Double] = []
            perCore.reserveCapacity(cpuSnapshot.count)

            for index in cpuSnapshot.indices {
                let current = cpuSnapshot[index]
                let previous = previousCPUTicks[index]
                // UInt32 模运算差分，正确处理计数回绕。
                let user = Double(current.user &- previous.user)
                let system = Double(current.system &- previous.system)
                let idle = Double(current.idle &- previous.idle)
                let nice = Double(current.nice &- previous.nice)
                let total = user + system + idle + nice
                userDelta += user
                systemDelta += system
                idleDelta += idle
                niceDelta += nice
                perCore.append(total > 0 ? max(0, min(1, (total - idle) / total)) : 0)
            }

            let totalDelta = userDelta + systemDelta + idleDelta + niceDelta
            stats.perCoreUsage = perCore
            if totalDelta > 0 {
                stats.cpuUsage = max(0, min(1, (userDelta + systemDelta + niceDelta) / totalDelta))
                stats.cpuUser = userDelta / totalDelta
                stats.cpuSystem = systemDelta / totalDelta
                stats.cpuIdle = idleDelta / totalDelta
            } else {
                stats.cpuIdle = 1
            }
        } else {
            // 首帧：返回与原核数等长的 0 数组，UI 可以正常画每核小条。
            stats.perCoreUsage = [Double](repeating: 0, count: cpuSnapshot.count)
            stats.cpuUsage = 0
            stats.cpuIdle = 1
        }

        previousCPUTicks = cpuSnapshot
        previousCPUTime = now
        lastCoreCount = cpuSnapshot.count

        // ---- 内存 ----
        if let memory = Self.readMemory(pageSize: pageSize, physicalMemory: physicalMemory) {
            stats.memoryTotal = memory.total
            stats.memoryUsed = memory.used
            stats.memoryWired = memory.wired
            stats.memoryCompressed = memory.compressed
            stats.memoryCached = memory.cached
            stats.memoryFree = memory.free
            stats.swapTotal = memory.swapTotal
            stats.swapUsed = memory.swapUsed
        } else {
            stats.memoryTotal = physicalMemory
        }

        // ---- 负载均值 ----
        var loadAverage = [Double](repeating: 0, count: 3)
        let loadCount = getloadavg(&loadAverage, 3)
        if loadCount > 0 {
            stats.loadAverage = Array(loadAverage.prefix(Int(loadCount)))
        }

        // ---- 网络（字节/秒）----
        let interfaces = NetworkReader.readInterfaces()
        let counters = NetworkReader.aggregateCounters(interfaces)
        let networkNow = MachTime.nowNanoseconds()
        if previousNetworkTime > 0, networkNow > previousNetworkTime, counters.key == previousNetworkKey {
            let elapsed = Double(networkNow - previousNetworkTime) / 1_000_000_000.0
            if elapsed >= 0.1 {
                stats.networkDownBytesPerSec = counters.received >= previousNetworkReceived
                    ? Double(counters.received - previousNetworkReceived) / elapsed
                    : 0
                stats.networkUpBytesPerSec = counters.sent >= previousNetworkSent
                    ? Double(counters.sent - previousNetworkSent) / elapsed
                    : 0
            }
        }
        previousNetworkKey = counters.key
        previousNetworkReceived = counters.received
        previousNetworkSent = counters.sent
        previousNetworkTime = networkNow

        // ---- 磁盘（可选）----
        let disk = diskReader.sample()
        stats.diskReadBytesPerSec = disk.read
        stats.diskWriteBytesPerSec = disk.write

        // ---- GPU（可选）----
        stats.gpuUsage = gpuReader.utilization()

        // ---- 进程 ----
        let processResult = processCollector.sample()
        stats.processCount = processResult.count
        stats.topProcesses = processResult.processes

        lastSampleDuration = Double(MachTime.nowNanoseconds() - sampleStart) / 1_000_000_000.0
        return stats
    }

    // MARK: - CPU 快照

    /// 读取每个逻辑核的累计 tick。调用方负责释放 host_processor_info 分配的内存（见 defer）。
    /// 失败时返回 nil（例如内核拒绝 host_processor_info）。
    private static func readCPUSnapshot() -> [CPUTicks]? {
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuCount: natural_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &cpuInfo,
            &cpuInfoCount
        )
        guard result == KERN_SUCCESS, let info = cpuInfo, cpuCount > 0 else { return nil }
        defer {
            // host_processor_info 用 vm_allocate 分配，必须 vm_deallocate，否则每秒泄漏内存。
            let bytes = vm_size_t(Int(cpuInfoCount) * MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), bytes)
        }

        let stride = Int(CPU_STATE_MAX)
        var ticks: [CPUTicks] = []
        ticks.reserveCapacity(Int(cpuCount))
        for index in 0..<Int(cpuCount) {
            let base = index * stride
            guard base + stride <= Int(cpuInfoCount) else { break }
            let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            ticks.append(CPUTicks(user: user, system: system, idle: idle, nice: nice))
        }
        return ticks
    }

    // MARK: - 内存快照

    /// 读取 vm_statistics64 并按 "used ≈ total - free - cached" 口径换算（详见文件头注释）。
    private static func readMemory(pageSize: UInt64, physicalMemory: UInt64) -> MemorySnapshot? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let total = physicalMemory
        let page = pageSize
        let freeBytes = (UInt64(statistics.free_count) &+ UInt64(statistics.speculative_count)) &* page
        let cachedBytes = (UInt64(statistics.external_page_count) &+ UInt64(statistics.purgeable_count)) &* page
        let wiredBytes = UInt64(statistics.wire_count) &* page
        let compressedBytes = UInt64(statistics.compressor_page_count) &* page
        // clamp：极端情况下 cached/free 之和可能超过 total（计数口径差异），保证 used >= 0。
        let usedBytes = (freeBytes &+ cachedBytes) < total ? total - freeBytes - cachedBytes : 0

        let swap = readSwapUsage()
        return MemorySnapshot(
            total: total,
            used: usedBytes,
            wired: wiredBytes,
            compressed: compressedBytes,
            cached: cachedBytes,
            free: freeBytes,
            swapTotal: swap.total,
            swapUsed: swap.used
        )
    }

    /// sysctl vm.swapusage：交换区总量 / 已用字节数。
    private static func readSwapUsage() -> (total: UInt64, used: UInt64) {
        var usage = SwapUsage()
        var size = MemoryLayout<SwapUsage>.size
        let result = withUnsafeMutablePointer(to: &usage) { pointer -> Int32 in
            sysctlbyname("vm.swapusage", pointer, &size, nil, 0)
        }
        guard result == 0 else { return (0, 0) }
        return (usage.total, usage.used)
    }
}
