// MacTemp / Sources/Collectors/HardwareIOReader.swift
// 归属：collectors（采集器）——GPU 利用率 / 磁盘读写速率的 IOKit 读取器。
//
// 这两个指标在 LiveStats 里都是可选字段（采集不到保持 nil），因此实现上以"不拖慢 sample()"为第一优先：
//   * init 时各遍历一次 IORegistry，选好要长期观察的服务句柄（IOObjectRetain 持有）；
//   * 每帧只读取该服务的一个属性（IORegistryEntryCreateCFProperty），耗时约几十微秒；
//   * 任何失败都返回 nil，绝不崩溃。
//
// GPU：匹配 IOAccelerator（Apple Silicon 上实际类是 AGXAcceleratorG16G 等）的
//      PerformanceStatistics → "Device Utilization %"（0...100）。
// 磁盘：匹配 IOBlockStorageDriver，取"累计读写字节数最大"的实例作为系统内置 SSD（disk0），
//      用 Statistics 字典的 "Bytes (Read)" / "Bytes (Write)" 差分得到 Bytes/s。
//      说明：APFS 卷/外接盘/磁盘镜像也会注册 IOBlockStorageDriver，累计量最大的通常就是系统盘；
//      用累计量而不是名字判断，避免不同机型命名差异。

import Foundation
import IOKit

/// GPU 利用率读取器（Apple Silicon 上用 IORegistry 的 PerformanceStatistics，无需 Metal）。
final class GPUReader {
    private var service: io_service_t = 0

    init() {
        // 找到第一个带 PerformanceStatistics 的 IOAccelerator 服务并持有它。
        // 只读单个属性：IOAccelerator 完整属性字典很大（SchedulerState 等），拉全量要 10ms+。
        IOKitHelper.forEachService("IOAccelerator") { candidate in
            guard service == 0 else { return }
            guard IOKitHelper.property(of: candidate, key: "PerformanceStatistics") is [String: Any] else { return }
            service = candidate
            IOObjectRetain(service)
        }
    }

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    /// 当前 GPU 利用率 0...1；不可用时 nil。
    func utilization() -> Double? {
        guard service != 0,
              let statistics = IOKitHelper.property(of: service, key: "PerformanceStatistics") as? [String: Any],
              let percent = AnyValue.double(statistics["Device Utilization %"]) else {
            return nil
        }
        let usage = percent / 100.0
        guard usage.isFinite else { return nil }
        return min(1, max(0, usage))
    }
}

/// 磁盘读写速率读取器（系统内置 SSD，Bytes/s）。
final class DiskIOReader {
    private var service: io_service_t = 0
    private var previousReadBytes: UInt64 = 0
    private var previousWriteBytes: UInt64 = 0
    private var previousSampleTime: UInt64 = 0

    init() {
        // 选取累计读写字节数最大的 IOBlockStorageDriver 实例作为系统盘。
        var bestService: io_service_t = 0
        var bestTotal: UInt64 = 0
        IOKitHelper.forEachService("IOBlockStorageDriver") { candidate in
            guard let counters = Self.readCounters(service: candidate) else { return }
            let total = counters.read &+ counters.write
            if total > bestTotal {
                if bestService != 0 { IOObjectRelease(bestService) }
                IOObjectRetain(candidate)
                bestService = candidate
                bestTotal = total
            }
        }
        service = bestService
    }

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    /// 返回 (读 Bytes/s, 写 Bytes/s)；首帧或不可用时返回 nil。
    func sample() -> (read: Double?, write: Double?) {
        guard service != 0, let counters = Self.readCounters(service: service) else {
            return (nil, nil)
        }
        let now = MachTime.nowNanoseconds()
        defer {
            previousReadBytes = counters.read
            previousWriteBytes = counters.write
            previousSampleTime = now
        }
        guard previousSampleTime > 0, now > previousSampleTime else { return (nil, nil) }
        let elapsed = Double(now - previousSampleTime) / 1_000_000_000.0
        // 间隔太短时计数差没有统计意义（也避免首帧噪声）。
        guard elapsed >= 0.2 else { return (nil, nil) }

        let readRate = counters.read >= previousReadBytes
            ? Double(counters.read - previousReadBytes) / elapsed
            : 0
        let writeRate = counters.write >= previousWriteBytes
            ? Double(counters.write - previousWriteBytes) / elapsed
            : 0
        return (readRate, writeRate)
    }

    // MARK: - 内部实现

    private static func readCounters(service: io_service_t) -> (read: UInt64, write: UInt64)? {
        guard let statistics = IOKitHelper.property(of: service, key: "Statistics") as? [String: Any] else {
            return nil
        }
        guard let read = AnyValue.uint64(statistics["Bytes (Read)"]),
              let write = AnyValue.uint64(statistics["Bytes (Write)"]) else {
            return nil
        }
        return (read, write)
    }
}
