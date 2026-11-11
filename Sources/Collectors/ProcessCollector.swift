// MacTemp / Sources/Collectors/ProcessCollector.swift
// 归属：collectors（采集器）——基于 libproc 的进程列表与 CPU/内存占用采样。
//
// 采集路径（每帧一次，约 1~4ms）：
//   proc_listpids(PROC_ALL_PIDS) 拿全部 pid
//   → 对每个 pid 调一次 proc_pidinfo(PROC_PIDTASKINFO)，同时拿到：
//       * pti_total_user / pti_total_system：累计 CPU tick（mach absolute time 单位）
//       * pti_resident_size：常驻内存字节数
//   → 与上一帧的 CPU tick 差分，除以真实经过时间得到 CPU 占用。
//
// 口径说明（cpuUsage）：
//   cpuUsage = ΔCPU时间 / Δ实际时间，单核满载 = 1.0；多线程进程可 > 1.0
//   （例如 4 线程跑满 4 个核约为 4.0），与"活动监视器"%CPU 语义一致（活动监视器显示 400%）。
//   LiveStats.topProcesses 只是列表展示，UI 可用 cpuUsage / 逻辑核数 归一成 0...1 的比例条。
//
// 权限：非本用户的进程 proc_pidinfo 会返回 EPERM，直接跳过（不崩溃、不报错）；
//       进程总数仍按 proc_listpids 返回的全部 pid 统计（与活动监视器"进程数"一致）。

import Foundation
import Darwin

final class ProcessCollector {
    /// 上一帧每个 pid 的累计 CPU tick（user + system）。
    private var previousCPUTicks: [pid_t: UInt64] = [:]
    /// 上一帧的采样时刻（mach 单调时钟纳秒）。
    private var previousSampleTime: UInt64 = 0
    /// 列表最多返回多少个进程。
    private let maxProcessCount = 10
    /// 最近一次 sample 的耗时（秒），自检用。
    private(set) var lastDuration: TimeInterval = 0

    /// 采样一帧进程数据。
    /// - Returns: `count` 为系统全部进程数；`processes` 为按 CPU 降序的前 N 个可访问进程。
    func sample() -> (count: Int, processes: [ProcessSample]) {
        let startTime = MachTime.nowNanoseconds()

        // 1. 拿全部 pid。先问所需缓冲区大小，再一次性读入。
        var pids: [pid_t] = []
        var processCount = 0
        let neededBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        if neededBytes > 0 {
            // 留一点余量，避免两次调用之间进程数增长导致截断。
            let capacity = Int(neededBytes) / MemoryLayout<pid_t>.size + 32
            pids = [pid_t](repeating: 0, count: capacity)
            let filledBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size))
            if filledBytes > 0 {
                let count = Int(filledBytes) / MemoryLayout<pid_t>.size
                processCount = count
                if count < pids.count { pids.removeLast(pids.count - count) }
            } else {
                pids.removeAll()
            }
        }

        // 2. 计算本次采样的经过时间；首帧没有上一帧数据时只建立基线。
        let now = MachTime.nowNanoseconds()
        let elapsedSeconds = previousSampleTime > 0 && now > previousSampleTime
            ? Double(now - previousSampleTime) / 1_000_000_000.0
            : 0
        // 间隔太短（< 200ms）时 tick 差噪声极大，按"首帧"处理，避免 UI 出现忽高忽低的假读数。
        let hasBaseline = elapsedSeconds >= 0.2

        var currentTicks: [pid_t: UInt64] = [:]
        currentTicks.reserveCapacity(pids.count)
        var candidates: [(pid: pid_t, cpuUsage: Double, memoryBytes: UInt64)] = []
        candidates.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            var info = proc_taskinfo()
            let infoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let result = proc_pidinfo(pid, Int32(PROC_PIDTASKINFO), 0, &info, infoSize)
            // 权限不足或进程已退出时 result 不为结构体大小，跳过。
            guard result == infoSize else { continue }

            let cpuTicks = info.pti_total_user &+ info.pti_total_system
            currentTicks[pid] = cpuTicks

            var cpuUsage = 0.0
            if hasBaseline, let previous = previousCPUTicks[pid], cpuTicks >= previous {
                let deltaSeconds = MachTime.seconds(fromTicks: cpuTicks - previous)
                cpuUsage = deltaSeconds / elapsedSeconds
                // 防御：极端情况下（时钟异常/计数回绕）给出合理上限，避免 UI 显示离谱数字。
                if !cpuUsage.isFinite || cpuUsage < 0 { cpuUsage = 0 }
                if cpuUsage > 64 { cpuUsage = 64 }
            }

            candidates.append((pid, cpuUsage, UInt64(info.pti_resident_size)))
        }

        previousCPUTicks = currentTicks
        previousSampleTime = now

        // 3. 排序：有差分时按 CPU 降序；首帧按内存降序（此时 CPU 全为 0，按内存排更有信息量）。
        if hasBaseline {
            candidates.sort { lhs, rhs in
                if lhs.cpuUsage != rhs.cpuUsage { return lhs.cpuUsage > rhs.cpuUsage }
                if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
                return lhs.pid < rhs.pid
            }
        } else {
            candidates.sort { lhs, rhs in
                if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
                return lhs.pid < rhs.pid
            }
        }

        // 4. 只为 top N 取进程名（proc_name 是额外系统调用，不值得对全部 pid 调用）。
        let top = candidates.prefix(maxProcessCount)
        var processes: [ProcessSample] = []
        processes.reserveCapacity(top.count)
        for item in top {
            processes.append(ProcessSample(
                pid: item.pid,
                name: processName(pid: item.pid),
                cpuUsage: item.cpuUsage,
                memoryBytes: item.memoryBytes
            ))
        }

        let duration = Double(MachTime.nowNanoseconds() - startTime) / 1_000_000_000.0
        lastDuration = duration
        return (processCount, processes)
    }

    /// 读取进程名；失败时用 "pid N" 兜底。
    private func processName(pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        if length > 0 {
            let name = String(cString: buffer)
            if !name.isEmpty { return name }
        }
        return "pid \(pid)"
    }
}
