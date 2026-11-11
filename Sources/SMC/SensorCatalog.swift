import Foundation
import IOKit

// MacTemp 传感器目录
// 把 SMC 原始键映射为「部件分类 + 中文名称 + 角色」。
//
// M4 基础款（本机 MacBook Air M4）使用经实测校准的白名单目录（research/sensor_catalog_m4.json，
// 由 docs/SENSOR_MAP.md 的实验得出）：2148 个 SMC 键里真正独立的温度传感器只有约 50 个，
// 其余是同一物理传感器的不同校准别名（恒定温差 7.1/6.7°C）、占位键或不可解码类型。
// 白名单可以避免界面里出现「同一核心 2-3 个几乎相同的数值」，同时降低刷新开销。
//
// 其他 M 系列芯片回退到「键表 + 前缀兜底」的通用目录，尽力展示可读到的传感器。

/// 传感器在聚合计算中的角色。
enum SensorRole: String {
    case cpuHotspot       // CPU Die 热点（主指标）
    case cpuDieAverage    // CPU Die 平均
    case cpuCoreP         // 性能核
    case cpuCoreE         // 能效核
    case cpuAux           // CPU 其他测点
    case gpuCore          // GPU 核心
    case gpuAux           // GPU 其他测点
    case memory           // 内存
    case memoryVRM        // 内存供电
    case storage          // NAND / SSD
    case battery          // 电池组
    case wireless         // 无线模块
    case package          // SoC 封装
    case vrm              // 供电 VRM
    case display          // 屏幕
    case enclosure        // 机身 / 环境
    case other
}

/// 一条传感器定义（与具体读数无关）。
struct SensorDefinition {
    let key: String
    var name: String
    var category: SensorCategory
    var role: SensorRole
}

/// 芯片与机型信息，用于选择传感器键表。
struct SMCProfile {
    let chipName: String       // "Apple M4"
    let family: String         // "M4"
    let pCores: Int
    let eCores: Int
    let gpuCores: Int
    let modelIdentifier: String  // "Mac16,12"

    static func detect() -> SMCProfile {
        let chip = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        var family = chip
        if family.hasPrefix("Apple ") { family = String(family.dropFirst(6)) }
        if let space = family.firstIndex(of: " ") { family = String(family[..<space]) }
        return SMCProfile(
            chipName: chip,
            family: family.uppercased(),
            pCores: sysctlInt("hw.perflevel0.logicalcpu") ?? 0,
            eCores: sysctlInt("hw.perflevel1.logicalcpu") ?? 0,
            gpuCores: gpuCoreCount(),
            modelIdentifier: sysctlString("hw.model") ?? "Mac"
        )
    }

    // MARK: - sysctl / IOKit 辅助

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size + 1)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    static func gpuCoreCount() -> Int {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(
            service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0
        ) else { return 0 }
        let number = property.takeRetainedValue()
        guard CFGetTypeID(number) == CFNumberGetTypeID() else { return 0 }
        var cores: Int32 = 0
        CFNumberGetValue((number as! CFNumber), .sInt32Type, &cores)
        return Int(cores)
    }
}

enum SensorCatalog {
    /// 是否使用实测校准的白名单目录（本机 M4 基础款）。
    static func usesCuratedCatalog(for profile: SMCProfile) -> Bool {
        profile.family == "M4"
    }

    /// 按分类给出合理的有效温度区间，用于过滤占位值和毛刺（依据 docs/SENSOR_MAP.md §7）。
    static func validRange(for category: SensorCategory) -> ClosedRange<Double> {
        switch category {
        case .cpu: return 10...125
        case .gpu: return 0.5...120      // GPU 键偶发 -4.5 / 0.1 毛刺，必须丢弃
        case .memory: return 0...100
        case .storage: return 0...100
        case .battery: return 0...60
        case .wireless: return 0...110
        case .display: return -10...80
        case .enclosure: return -20...80
        case .package: return 0...115
        case .vrm: return 0...120
        case .other: return 0...110
        }
    }

    /// 已知无效的占位键（用于非白名单的兜底路径）。
    static func isPlaceholderKey(_ key: String) -> Bool {
        if key == "TAOL" { return false }
        if key.hasPrefix("Ta") { return true }   // Ta00/Ta01/.../Ta0S 恒为 0 或 5.0
        if key.hasPrefix("Tz") { return true }   // Tz1* 恒为 0
        return false
    }

    /// 按芯片家族返回有序的传感器定义表（顺序即 UI 顺序）。
    static func build(for profile: SMCProfile) -> [SensorDefinition] {
        if usesCuratedCatalog(for: profile) {
            return curatedM4
        }
        return legacyDefinitions(for: profile)
    }

    // MARK: - M4 基础款：实测校准白名单

    static let curatedM4: [SensorDefinition] = [
        .init(key: "TCMz", name: "CPU 热点（最高核心）", category: .cpu, role: .cpuHotspot),
        .init(key: "TCMb", name: "CPU 芯片平均", category: .cpu, role: .cpuDieAverage),
        .init(key: "Tp01", name: "CPU 性能核心 1", category: .cpu, role: .cpuCoreP),
        .init(key: "Tp05", name: "CPU 性能核心 2", category: .cpu, role: .cpuCoreP),
        .init(key: "Tp09", name: "CPU 性能核心 3", category: .cpu, role: .cpuCoreP),
        .init(key: "Tp0D", name: "CPU 性能核心 4", category: .cpu, role: .cpuCoreP),
        .init(key: "Te05", name: "CPU 能效核心 1", category: .cpu, role: .cpuCoreE),
        .init(key: "Te0S", name: "CPU 能效核心 2", category: .cpu, role: .cpuCoreE),
        .init(key: "Te09", name: "CPU 能效核心 3", category: .cpu, role: .cpuCoreE),
        .init(key: "Te0H", name: "CPU 能效核心 4", category: .cpu, role: .cpuCoreE),
        .init(key: "Te0V", name: "CPU 能效核心 5", category: .cpu, role: .cpuCoreE),
        .init(key: "Te0X", name: "CPU 能效核心 6", category: .cpu, role: .cpuCoreE),
        .init(key: "Tg0C", name: "GPU 核心 1", category: .gpu, role: .gpuCore),
        .init(key: "Tg0D", name: "GPU 核心 2", category: .gpu, role: .gpuCore),
        .init(key: "Tg0H", name: "GPU 核心 3", category: .gpu, role: .gpuCore),
        .init(key: "Tg0L", name: "GPU 核心 4", category: .gpu, role: .gpuCore),
        .init(key: "Tg0P", name: "GPU 核心 5", category: .gpu, role: .gpuCore),
        .init(key: "Tg0V", name: "GPU 核心 6", category: .gpu, role: .gpuCore),
        .init(key: "Tg0Y", name: "GPU 核心 7", category: .gpu, role: .gpuCore),
        .init(key: "Tg0e", name: "GPU 核心 8", category: .gpu, role: .gpuCore),
        .init(key: "Tg0k", name: "GPU 核心 9", category: .gpu, role: .gpuCore),
        .init(key: "Tg0n", name: "GPU 核心 10", category: .gpu, role: .gpuCore),
        .init(key: "Tm0B", name: "内存（LPDDR5X）", category: .memory, role: .memory),
        .init(key: "TH0x", name: "NAND 闪存", category: .storage, role: .storage),
        .init(key: "TB0T", name: "电池 电芯 1", category: .battery, role: .battery),
        .init(key: "TB1T", name: "电池 电芯 2", category: .battery, role: .battery),
        .init(key: "TB2T", name: "电池 电芯 3", category: .battery, role: .battery),
        .init(key: "TW0P", name: "Wi-Fi 模块", category: .wireless, role: .wireless),
        .init(key: "TDBP", name: "显示屏 背光 / 面板 A", category: .display, role: .display),
        .init(key: "TDeL", name: "显示屏 面板 B", category: .display, role: .display),
        .init(key: "TAOL", name: "机身 / 环境", category: .enclosure, role: .enclosure),
        .init(key: "TPMP", name: "SoC 封装", category: .package, role: .package),
        .init(key: "TPSP", name: "SoC 封装表面", category: .package, role: .package),
        .init(key: "TSCD", name: "SoC 芯片测点", category: .package, role: .package),
        .init(key: "TPD0", name: "SoC 封装测点 A", category: .package, role: .package),
        .init(key: "TPDX", name: "SoC 封装测点 B", category: .package, role: .package),
        .init(key: "TVV0", name: "GPU 侧供电", category: .vrm, role: .vrm),
        .init(key: "TVM0", name: "CPU 侧供电", category: .vrm, role: .vrm),
        .init(key: "TVh0", name: "供电 高侧", category: .vrm, role: .vrm),
        .init(key: "TVMm", name: "供电 测点 B", category: .vrm, role: .vrm),
        .init(key: "TVm0", name: "供电 测点 C", category: .vrm, role: .vrm),
        .init(key: "TVS0", name: "供电 S0", category: .vrm, role: .vrm),
        .init(key: "TVS1", name: "供电 S1", category: .vrm, role: .vrm),
        .init(key: "TCHP", name: "充电器 / CPU 邻近", category: .other, role: .other),
        .init(key: "TMVR", name: "内存供电", category: .other, role: .other),
        .init(key: "TIOP", name: "雷电接口控制器", category: .other, role: .other),
        .init(key: "TRD0", name: "供电测点 D0", category: .other, role: .other),
        .init(key: "T5SP", name: "存储控制器", category: .other, role: .other),
        .init(key: "Ts0P", name: "SoC 热区 A", category: .other, role: .other),
        .init(key: "Ts1P", name: "SoC 热区 B", category: .other, role: .other),
    ]

    // MARK: - 其他芯片：键表 + 兜底

    private static func legacyDefinitions(for profile: SMCProfile) -> [SensorDefinition] {
        var defs: [SensorDefinition] = []
        defs.append(.init(key: "TCMz", name: "CPU Die 热点", category: .cpu, role: .cpuHotspot))
        defs.append(.init(key: "TCMb", name: "CPU Die 平均", category: .cpu, role: .cpuDieAverage))
        defs.append(.init(key: "TCHP", name: "CPU 邻近 / 充电器", category: .cpu, role: .cpuAux))

        for (index, key) in cpuPerformanceKeys(for: profile).enumerated() {
            defs.append(.init(key: key, name: "CPU 性能核心 \(index + 1)", category: .cpu, role: .cpuCoreP))
        }
        for (index, key) in cpuEfficiencyKeys(for: profile).enumerated() {
            defs.append(.init(key: key, name: "CPU 能效核心 \(index + 1)", category: .cpu, role: .cpuCoreE))
        }
        for (index, key) in gpuKeys(for: profile).enumerated() {
            defs.append(.init(key: key, name: "GPU 核心 \(index + 1)", category: .gpu, role: .gpuCore))
        }

        defs.append(.init(key: "Tm0B", name: "内存邻近", category: .memory, role: .memory))
        defs.append(.init(key: "TH0x", name: "NAND 闪存", category: .storage, role: .storage))
        defs.append(.init(key: "TH0T", name: "NAND 闪存 2", category: .storage, role: .storage))
        defs.append(.init(key: "T5SP", name: "存储控制器", category: .storage, role: .storage))
        defs.append(.init(key: "TB0T", name: "电池传感器 1", category: .battery, role: .battery))
        defs.append(.init(key: "TB1T", name: "电池传感器 2", category: .battery, role: .battery))
        defs.append(.init(key: "TB2T", name: "电池传感器 3", category: .battery, role: .battery))
        defs.append(.init(key: "TW0P", name: "Wi-Fi / 蓝牙模块", category: .wireless, role: .wireless))
        defs.append(.init(key: "TPMP", name: "SoC 封装", category: .package, role: .package))
        defs.append(.init(key: "TVD0", name: "显示 / SoC 供电", category: .vrm, role: .vrm))
        defs.append(.init(key: "TVM0", name: "内存供电", category: .vrm, role: .vrm))
        defs.append(.init(key: "TDBP", name: "屏幕背光邻近", category: .display, role: .display))
        defs.append(.init(key: "TDeL", name: "屏幕面板", category: .display, role: .display))
        defs.append(.init(key: "TAOL", name: "机身进风 / 环境", category: .enclosure, role: .enclosure))
        defs.append(.init(key: "TIOP", name: "雷电控制器", category: .other, role: .other))
        return defs
    }

    /// 目录外但机器上存在的温度键，按前缀推断分类后生成兜底定义。
    static func fallbackDefinition(for key: String) -> SensorDefinition {
        let category: SensorCategory
        let name: String
        switch key.prefix(1) {
        case "T":
            switch String(key.prefix(2)) {
            case "Tp": category = .cpu; name = "CPU 传感器 \(key)"
            case "Te": category = .cpu; name = "CPU 传感器 \(key)"
            case "Tg": category = .gpu; name = "GPU 传感器 \(key)"
            case "Tm": category = .memory; name = "内存传感器 \(key)"
            case "TH", "T5": category = .storage; name = "存储传感器 \(key)"
            case "TB": category = .battery; name = "电池传感器 \(key)"
            case "TW": category = .wireless; name = "无线传感器 \(key)"
            case "TD": category = .display; name = "显示传感器 \(key)"
            case "TA": category = .enclosure; name = "机身传感器 \(key)"
            case "TP": category = .package; name = "封装传感器 \(key)"
            case "TV", "TR": category = .vrm; name = "供电传感器 \(key)"
            case "TC": category = .cpu; name = "CPU 传感器 \(key)"
            case "Ts": category = .other; name = "SoC 热区 \(key)"
            case "TI": category = .other; name = "接口传感器 \(key)"
            default: category = .other; name = "SMC 传感器 \(key)"
            }
        default:
            category = .other; name = "SMC 传感器 \(key)"
        }
        return SensorDefinition(key: key, name: name, category: category, role: .other)
    }

    // MARK: - 各芯片家族键表（非白名单路径）

    static func cpuPerformanceKeys(for profile: SMCProfile) -> [String] {
        let table: [String]
        switch profile.family {
        case "M1":
            table = ["Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
        case "M2":
            table = ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
        case "M3":
            table = ["Tp01", "Tp09", "Tp0f", "Tp0n", "Tp05", "Tp0D", "Tp0j", "Tp0r"]
        default:
            table = ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        }
        return Array(table.prefix(max(profile.pCores, 1)))
    }

    static func cpuEfficiencyKeys(for profile: SMCProfile) -> [String] {
        let table: [String]
        switch profile.family {
        case "M1":
            table = ["Tp09", "Tp0T"]
        case "M2":
            table = ["Tp1h", "Tp1t", "Tp1p", "Tp1l"]
        case "M3":
            table = ["Te05", "Te0L", "Te0P", "Te0S"]
        default:
            table = ["Te05", "Te0S", "Te09", "Te0H", "Te0V", "Te0X"]
        }
        return Array(table.prefix(max(profile.eCores, 1)))
    }

    static func gpuKeys(for profile: SMCProfile) -> [String] {
        switch profile.family {
        case "M1": return ["Tg05", "Tg0D", "Tg0L", "Tg0T"]
        case "M2": return ["Tg0f", "Tg0j"]
        case "M3": return ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]
        default: return ["Tg0D", "Tg0P", "Tg0X", "Tg0j", "Tg0G", "Tg0H", "Tg0K", "Tg0L"]
        }
    }
}
