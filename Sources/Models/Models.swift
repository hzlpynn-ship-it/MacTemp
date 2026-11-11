import Foundation

// MARK: - 传感器分类

/// 温度传感器的部件分类，也用于仪表盘卡片分组与传感器列表筛选。
enum SensorCategory: String, CaseIterable, Codable, Identifiable {
    case cpu
    case gpu
    case memory
    case storage
    case battery
    case wireless
    case display
    case enclosure
    case package
    case vrm
    case other

    var id: String { rawValue }

    /// 卡片标题（短）
    var cardTitle: String {
        switch self {
        case .cpu: return "CPU 处理器"
        case .gpu: return "GPU 图形"
        case .memory: return "内存"
        case .storage: return "固态硬盘"
        case .battery: return "电池"
        case .wireless: return "无线模块"
        case .display: return "显示屏"
        case .enclosure: return "机身 / 环境"
        case .package: return "SoC 封装"
        case .vrm: return "供电 VRM"
        case .other: return "其他传感器"
        }
    }

    /// 侧栏/筛选器标题
    var title: String {
        switch self {
        case .cpu: return "处理器"
        case .gpu: return "图形处理器"
        case .memory: return "内存"
        case .storage: return "存储"
        case .battery: return "电池"
        case .wireless: return "无线"
        case .display: return "显示"
        case .enclosure: return "机身"
        case .package: return "SoC 封装"
        case .vrm: return "供电"
        case .other: return "其他"
        }
    }

    /// SF Symbol 名称（macOS 13+ 均可用）
    var symbolName: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "rectangle.3.group"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .battery: return "battery.75"
        case .wireless: return "wifi"
        case .display: return "display"
        case .enclosure: return "laptopcomputer"
        case .package: return "square.stack.3d.up"
        case .vrm: return "bolt.fill"
        case .other: return "thermometer.medium"
        }
    }

    /// 传感器的稳定排序
    var sortIndex: Int {
        switch self {
        case .cpu: return 0
        case .gpu: return 1
        case .memory: return 2
        case .storage: return 3
        case .battery: return 4
        case .wireless: return 5
        case .package: return 6
        case .vrm: return 7
        case .display: return 8
        case .enclosure: return 9
        case .other: return 10
        }
    }

    /// 可作为仪表盘主卡片展示的分类（按顺序）
    static var dashboardCardOrder: [SensorCategory] {
        [.cpu, .gpu, .memory, .storage, .battery, .wireless]
    }
}

// MARK: - 温度读数

/// 单个 SMC 温度传感器。
struct TemperatureSensor: Identifiable, Hashable {
    /// SMC 键名，例如 "Tp01"、"TCMz"，全局唯一。
    let key: String
    /// 中文可读名称，例如 "CPU 性能核心 1"。
    var name: String
    var category: SensorCategory
    /// 摄氏度；nil 表示当前读数不可用（读取失败或超出合理范围）。
    var celsius: Double?
    /// SMC 数据类型，例如 "flt "。
    var typeName: String
    /// 附加说明，例如 "SMC 原始键"。
    var note: String?

    var id: String { key }
    var isAvailable: Bool { celsius != nil }
}

/// 仪表盘上的部件温度汇总卡片。
struct TemperatureGroup: Identifiable, Hashable {
    /// 稳定 ID，历史曲线以它为键，例如 "cpu"、"gpu"。
    let id: String
    var category: SensorCategory
    var title: String
    /// 副标题，例如 "Apple M4 · 4P + 6E"。
    var subtitle: String
    /// 卡片主数值（摄氏度），nil 表示不可用。
    var primary: Double?
    /// 该部件所有有效传感器的平均值。
    var average: Double?
    /// 该部件所有有效传感器的最高值。
    var maximum: Double?
    /// 参与统计的有效传感器数量。
    var sensorCount: Int
    var symbolName: String
    /// 是否展示为主卡片（即"AIDA 风格"的主部件卡片）。
    var isPrimaryCard: Bool
}

// MARK: - 风扇 / 散热压力

struct FanReading: Identifiable, Hashable {
    let id: Int
    var name: String
    /// 当前转速（RPM），nil 表示无风扇或读取不可用。
    var rpm: Double?
    var minRPM: Double?
    var maxRPM: Double?
}

/// macOS 系统热压力等级（来自 ProcessInfo.thermalState）。
enum ThermalPressure: String, Codable, Identifiable, CaseIterable {
    case nominal
    case fair
    case serious
    case critical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nominal: return "正常"
        case .fair: return "偏热"
        case .serious: return "严重"
        case .critical: return "临界"
        }
    }

    var detail: String {
        switch self {
        case .nominal: return "系统热状态正常，无降频"
        case .fair: return "系统温度偏高，可能出现轻微降频"
        case .serious: return "系统温度很高，性能已明显受限"
        case .critical: return "系统温度临界，需立即降温"
        }
    }

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}

// MARK: - 静态系统信息

struct DisplayInfo: Identifiable, Hashable {
    var name: String
    var resolution: String
    var refreshRate: Double?
    var isMain: Bool

    var id: String { "\(name)-\(resolution)-\(isMain)" }
}

struct DiskInfo: Identifiable, Hashable {
    var name: String
    var mountPoint: String
    var fileSystem: String
    var totalBytes: UInt64
    var freeBytes: UInt64
    var isInternal: Bool
    var isRemovable: Bool

    var id: String { mountPoint }
}

struct NetworkInterfaceInfo: Identifiable, Hashable {
    var name: String
    var typeLabel: String
    var ipv4: String?
    var ipv6: String?
    var macAddress: String?
    var isUp: Bool

    var id: String { name }
}

struct BatteryInfo: Hashable {
    var isPresent: Bool
    /// 0...100
    var chargePercent: Double
    var isCharging: Bool
    var isPluggedIn: Bool
    var timeRemainingMinutes: Int?
    var cycleCount: Int?
    /// 0...100，相对设计容量
    var healthPercent: Double?
    var designCapacitymAh: Int?
    var maxCapacitymAh: Int?
    var currentCapacitymAh: Int?
    var temperatureCelsius: Double?
    var condition: String?

    static let empty = BatteryInfo(isPresent: false, chargePercent: 0, isCharging: false, isPluggedIn: false)
}

struct SystemInfo: Hashable {
    var modelName: String
    var modelIdentifier: String
    var chipName: String
    var architecture: String
    var totalCores: Int
    var performanceCores: Int
    var efficiencyCores: Int
    var gpuCores: Int
    var memoryBytes: UInt64
    var macOSVersion: String
    var macOSBuild: String
    var kernelVersion: String
    var uptime: TimeInterval
    var bootDate: Date
    var hostname: String
    var serialNumber: String
    var hardwareUUID: String
    var powerSource: String
    var displays: [DisplayInfo]
    var disks: [DiskInfo]
    var networks: [NetworkInterfaceInfo]
    var battery: BatteryInfo?

    static let placeholder = SystemInfo(
        modelName: "Mac",
        modelIdentifier: "Mac",
        chipName: "Apple Silicon",
        architecture: "arm64",
        totalCores: 0,
        performanceCores: 0,
        efficiencyCores: 0,
        gpuCores: 0,
        memoryBytes: 0,
        macOSVersion: "macOS",
        macOSBuild: "-",
        kernelVersion: "-",
        uptime: 0,
        bootDate: Date(),
        hostname: "-",
        serialNumber: "-",
        hardwareUUID: "-",
        powerSource: "-",
        displays: [],
        disks: [],
        networks: [],
        battery: nil
    )
}

// MARK: - 实时负载

struct ProcessSample: Identifiable, Hashable {
    var pid: Int32
    var name: String
    /// 0...1 之间（单个核心满载 = 1.0，多核可 > 1.0 的读数已做归一化说明见实现）
    var cpuUsage: Double
    var memoryBytes: UInt64

    var id: Int32 { pid }
}

struct LiveStats {
    var timestamp: Date = Date()
    /// 0...1
    var cpuUsage: Double = 0
    var perCoreUsage: [Double] = []
    /// 0...1
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuIdle: Double = 1
    var loadAverage: [Double] = []
    var memoryTotal: UInt64 = 0
    var memoryUsed: UInt64 = 0
    var memoryWired: UInt64 = 0
    var memoryCompressed: UInt64 = 0
    var memoryCached: UInt64 = 0
    var memoryFree: UInt64 = 0
    var swapTotal: UInt64 = 0
    var swapUsed: UInt64 = 0
    var networkDownBytesPerSec: Double = 0
    var networkUpBytesPerSec: Double = 0
    var diskReadBytesPerSec: Double? = nil
    var diskWriteBytesPerSec: Double? = nil
    var processCount: Int = 0
    var topProcesses: [ProcessSample] = []
    /// Apple Silicon 上默认不可用；采集不到时保持 nil。
    var gpuUsage: Double? = nil
}

// MARK: - 设置

enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .celsius: return "摄氏度 °C"
        case .fahrenheit: return "华氏度 °F"
        }
    }

    var shortLabel: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    func convert(fromCelsius value: Double) -> Double {
        switch self {
        case .celsius: return value
        case .fahrenheit: return value * 9.0 / 5.0 + 32.0
        }
    }

    /// 把摄氏温度格式化为带一位小数的字符串（不含单位）。
    func format(fromCelsius value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f", convert(fromCelsius: value))
    }
}

enum MenuBarMetric: String, Codable, CaseIterable, Identifiable {
    case cpu
    case gpu
    case highest
    case power
    case fan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU 温度"
        case .gpu: return "GPU 温度"
        case .highest: return "最高部件温度"
        case .power: return "整机功耗"
        case .fan: return "风扇转速"
        }
    }
}

struct AppSettings: Codable, Equatable {
    /// 传感器刷新间隔（秒）
    var refreshInterval: Double = 1.0
    var unit: TemperatureUnit = .celsius
    var menuBarMetric: MenuBarMetric = .cpu
    var menuBarShowText: Bool = true
    /// 是否记录 60 秒历史曲线
    var recordHistory: Bool = true
    /// 温度告警阈值（摄氏度），nil 表示关闭
    var alertThresholdCelsius: Double? = nil
}

// MARK: - 采集器协议

protocol SystemInfoProviding {
    func collect() -> SystemInfo
}

protocol LiveStatsProviding {
    func sample() -> LiveStats
}

protocol BatteryInfoProviding {
    func collect() -> BatteryInfo?
}
