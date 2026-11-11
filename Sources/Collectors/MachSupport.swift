// MacTemp / Sources/Collectors/MachSupport.swift
// 归属：collectors（采集器）——系统底层 C API 的安全 Swift 封装。
//
// 设计原则：
// 1. 所有 C API 调用都检查返回值；失败返回 nil，绝不强制解包；
// 2. 不 spawn 任何外部进程（禁止 Process 调 ps / top / ioreg / system_profiler）；
// 3. 尽量复用/缓存 IOKit 服务句柄，避免每秒刷新时反复遍历 IORegistry；
// 4. 采样路径上的函数都保持轻量（微秒~毫秒级），满足 sample() < 30ms 的要求。

import Foundation
import Darwin
import IOKit
import IOKit.ps

// MARK: - sysctl 读取

/// `sysctlbyname` 的类型安全封装。
/// 每次调用只做一次系统调用，适合静态信息；采样热点路径不要反复调用。
enum SysctlReader {
    /// 读取任意 sysctl 的原始数据。
    static func data(_ name: String) -> Data? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        if buffer.count > size { buffer.removeLast(buffer.count - size) }
        return Data(buffer)
    }

    /// 读取 C 字符串型 sysctl（如 hw.model、kern.osversion）。
    static func string(_ name: String) -> String? {
        guard let data = data(name) else { return nil }
        // sysctl 返回的字符串以 \0 结尾；去掉尾部空字节再做 UTF-8 解码。
        let trimmed = data.prefix { $0 != 0 }
        guard !trimmed.isEmpty else { return nil }
        return String(decoding: trimmed, as: UTF8.self)
    }

    /// 读取整型 sysctl（如 hw.memsize、hw.logicalcpu）。自动适配 4/8 字节宽度。
    static func uint64(_ name: String) -> UInt64? {
        guard let data = data(name) else { return nil }
        switch data.count {
        case 8:
            return data.withUnsafeBytes { $0.load(as: UInt64.self) }
        case 4:
            return UInt64(data.withUnsafeBytes { $0.load(as: UInt32.self) })
        default:
            return nil
        }
    }

    static func int(_ name: String) -> Int? {
        guard let value = uint64(name) else { return nil }
        return Int(value)
    }

    /// 读取 `struct timeval` 型 sysctl（如 kern.boottime）。
    /// 注意：函数名不能叫 timeval，否则会和 Darwin.timeval 类型同名遮蔽。
    static func timevalValue(_ name: String) -> Darwin.timeval? {
        guard let data = data(name), data.count >= MemoryLayout<Darwin.timeval>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: Darwin.timeval.self) }
    }
}

// MARK: - mach 时间基

/// mach 绝对时间与秒之间的换算。
///
/// 说明：`proc_taskinfo.pti_total_user/pti_total_system` 的单位不是纳秒，而是
/// mach absolute time 的 tick（本机 M4 实测 timebase = 125/3，即 24MHz；
/// 用 rusage 交叉验证 6551534 ticks ≈ 0.27298s）。因此进程 CPU 时间必须用
/// 这里的 timebase 换算，直接除以 1e9 会得到错误的百分比。
enum MachTime {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        // mach_timebase_info 在 macOS 上不会失败；仍做默认值兜底。
        if mach_timebase_info(&info) != KERN_SUCCESS {
            info.numer = 1
            info.denom = 1
        }
        return info
    }()

    /// 当前单调时钟（纳秒），用于计算采样间隔。
    static func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    /// 把 mach absolute time tick 换算成秒。
    static func seconds(fromTicks ticks: UInt64) -> Double {
        guard timebase.denom != 0 else { return Double(ticks) / 1_000_000_000.0 }
        return Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000.0
    }
}

// MARK: - 任意类型（CF/NSNumber/NSString）的取值转换

/// IORegistry / IOPS 返回的属性字典里混有 NSNumber / String / Bool，
/// 这里统一做宽松转换，缺失或类型不符时返回 nil。
enum AnyValue {
    static func int(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let int = value as? Int { return int }
        if let int64 = value as? Int64 { return Int(int64) }
        if let uint64 = value as? UInt64 { return Int(clamping: uint64) }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    static func uint64(_ value: Any?) -> UInt64? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return number.uint64Value }
        if let uint64 = value as? UInt64 { return uint64 }
        if let int64 = value as? Int64 { return int64 >= 0 ? UInt64(int64) : nil }
        if let int = value as? Int { return int >= 0 ? UInt64(int) : nil }
        if let string = value as? String { return UInt64(string) }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return number.boolValue }
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let string = value as? String {
            switch string.lowercased() {
            case "yes", "true", "1": return true
            case "no", "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

// MARK: - IOKit 辅助

/// IOKit 服务/属性的读取封装。所有 io_service_t / io_iterator_t 都会正确释放。
enum IOKitHelper {
    /// 按类名取第一个匹配服务，在闭包内使用；闭包返回后自动 IOObjectRelease。
    static func withFirstService<T>(_ className: String, _ body: (io_service_t) -> T?) -> T? {
        guard let matching = IOServiceMatching(className) else { return nil }
        // IOServiceGetMatchingService 会消费 matching 字典的引用。
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return body(service)
    }

    /// 按类名遍历所有匹配服务（用于 AGXAccelerator / IOBlockStorageDriver 这类可能有多个实例的类）。
    static func forEachService(_ className: String, _ body: (io_service_t) -> Void) {
        guard let matching = IOServiceMatching(className) else { return }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            body(entry)
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
    }

    /// 读取某个 IORegistry 节点的全部属性（CFDictionary → [String: Any]）。
    static func properties(of service: io_service_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let dictionary = unmanaged?.takeRetainedValue() else { return nil }
        return dictionary as? [String: Any]
    }

    /// 读取某个 IORegistry 节点的单个属性。
    static func property(of service: io_service_t, key: String) -> Any? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return unmanaged.takeRetainedValue()
    }

    /// 按类名取第一个匹配服务的属性字典（如 AppleSmartBattery、IOPlatformExpertDevice）。
    static func firstProperties(_ className: String) -> [String: Any]? {
        withFirstService(className) { properties(of: $0) }
    }

    /// 读取节点的 IOClass 名称（调试/识别用）。
    static func className(of service: io_service_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(service, &buffer) == KERN_SUCCESS else { return "" }
        return String(cString: buffer)
    }
}
