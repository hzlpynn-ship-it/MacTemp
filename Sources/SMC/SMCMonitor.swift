import Foundation

// MacTemp SMC 采样编排
// 负责：启动时扫描全部 SMC 键、建立温度传感器列表、按分类聚合，并周期性读取有效键。

/// 内部跟踪器：缓存键的元数据，刷新时只做一次 IPC 读取。
struct SensorTracker {
    let key: String
    let type: String
    let dataSize: UInt32
    let name: String
    let category: SensorCategory
    let role: SensorRole
    let isPlaceholder: Bool
}

/// 风扇通道（Apple Silicon 无风扇机型没有 F* 键，此数组为空）。
struct FanTracker {
    let index: Int
    let rpmKey: String
    let rpmType: String
    let rpmSize: UInt32
    let minKey: String?
    let minType: String?
    let minSize: UInt32
    let maxKey: String?
    let maxType: String?
    let maxSize: UInt32
}

/// 一次采样得到的完整传感器快照。
struct SMCSnapshot {
    var sensors: [TemperatureSensor] = []
    var groups: [TemperatureGroup] = []
    var fans: [FanReading] = []
    var powerWatts: Double?
    var cpuCores: [TemperatureSensor] = []
    var validSensorCount: Int = 0
}

final class SMCMonitor {
    /// 低于 0.5°C 或高于 125°C 的读数视为不可用（SMC 占位值、读取失败或异常）。
    static let validTemperatureRange: ClosedRange<Double> = 0.5...125.0

    private let driver = SMCDriver.shared
    private(set) var profile: SMCProfile?
    private(set) var trackers: [SensorTracker] = []
    private(set) var fanTrackers: [FanTracker] = []
    private(set) var powerTracker: SensorTracker?
    private(set) var lastError: String?
    private(set) var scanSummary = "尚未扫描"

    /// key -> role 映射，分组聚合时用来挑出 CPU 核心传感器。
    private var roleByKey: [String: SensorRole] = [:]

    var isReady: Bool { !trackers.isEmpty }

    /// 打开 SMC 并扫描全部键。返回是否成功。
    func start() -> Bool {
        lastError = nil
        guard driver.open() else {
            lastError = "无法连接 AppleSMC（当前设备可能不受支持）"
            scanSummary = "SMC 打开失败"
            return false
        }
        let totalKeys = driver.keyCount()
        guard totalKeys > 0 else {
            lastError = "SMC 未返回传感器键（可能需要重启或设备不支持）"
            scanSummary = "SMC 键数量为 0"
            return false
        }

        let profile = SMCProfile.detect()
        self.profile = profile

        var tempMetas: [String: SMCKeyMeta] = [:]
        var fanMetas: [String: SMCKeyMeta] = [:]
        var powerMeta: SMCKeyMeta?

        for index in 0..<totalKeys {
            guard let key = driver.key(at: index) else { continue }
            guard key.utf8.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) else { continue }

            if key.hasPrefix("T") {
                guard let info = driver.keyInfo(key),
                      SMCKeyClassifier.temperatureTypes.contains(info.type)
                else { continue }
                tempMetas[key] = SMCKeyMeta(key: key, type: info.type, dataSize: info.dataSize)
            } else if key.hasPrefix("F"), key.count == 4 {
                guard let info = driver.keyInfo(key),
                      SMCKeyClassifier.numericTypes.contains(info.type)
                else { continue }
                fanMetas[key] = SMCKeyMeta(key: key, type: info.type, dataSize: info.dataSize)
            } else if key == "PSTR" {
                guard let info = driver.keyInfo(key),
                      ["flt ", "fp88", "sp78", "ui16"].contains(info.type)
                else { continue }
                powerMeta = SMCKeyMeta(key: key, type: info.type, dataSize: info.dataSize)
            }
        }

        // 传感器定义：
        // - M4 基础款使用实测校准的白名单（只保留约 50 个独立传感器，剔除别名/占位键）
        // - 其他芯片退回「目录 + 前缀兜底」模式，尽量多展示
        let definitions = SensorCatalog.build(for: profile)
        let curated = SensorCatalog.usesCuratedCatalog(for: profile)
        var ordered: [SensorDefinition] = []
        var known = Set<String>()
        for definition in definitions {
            guard tempMetas[definition.key] != nil, !known.contains(definition.key) else { continue }
            ordered.append(definition)
            known.insert(definition.key)
        }
        if !curated {
            let extras = tempMetas.keys
                .filter { !known.contains($0) }
                .sorted()
                .map { SensorCatalog.fallbackDefinition(for: $0) }
            ordered.append(contentsOf: extras)
        }

        trackers = ordered.compactMap { definition in
            guard let meta = tempMetas[definition.key] else { return nil }
            let placeholder = !curated && SensorCatalog.isPlaceholderKey(meta.key)
            return SensorTracker(
                key: meta.key,
                type: meta.type,
                dataSize: meta.dataSize,
                name: definition.name,
                category: definition.category,
                role: definition.role,
                isPlaceholder: placeholder
            )
        }
        roleByKey = Dictionary(uniqueKeysWithValues: trackers.map { ($0.key, $0.role) })

        // 风扇通道：F0Ac/F0Mn/F0Mx、F1Ac/...（无风扇机型没有任何 F*Ac 键）
        var fanSets: [Int: FanMetaSet] = [:]
        for (key, meta) in fanMetas {
            let chars = Array(key)
            guard chars.count == 4, chars[0] == "F", let fanIndex = Int(String(chars[1])) else { continue }
            switch String(chars[2...3]) {
            case "Ac":
                fanSets[fanIndex, default: FanMetaSet()].rpm = meta
            case "Mn":
                fanSets[fanIndex, default: FanMetaSet()].min = meta
            case "Mx":
                fanSets[fanIndex, default: FanMetaSet()].max = meta
            default:
                break
            }
        }
        fanTrackers = fanSets.keys.sorted().compactMap { fanIndex in
            guard let entry = fanSets[fanIndex], let rpmMeta = entry.rpm else { return nil }
            return FanTracker(
                index: fanIndex,
                rpmKey: rpmMeta.key,
                rpmType: rpmMeta.type,
                rpmSize: rpmMeta.dataSize,
                minKey: entry.min?.key,
                minType: entry.min?.type,
                minSize: entry.min?.dataSize ?? 0,
                maxKey: entry.max?.key,
                maxType: entry.max?.type,
                maxSize: entry.max?.dataSize ?? 0
            )
        }

        if let powerMeta {
            powerTracker = SensorTracker(
                key: powerMeta.key,
                type: powerMeta.type,
                dataSize: powerMeta.dataSize,
                name: "整机功耗",
                category: .other,
                role: .other,
                isPlaceholder: false
            )
        } else {
            powerTracker = nil
        }

        let mode = curated ? "实测校准目录" : "通用目录"
        scanSummary = "SMC 键 \(totalKeys) 个 · 温度候选 \(tempMetas.count) 个 · 跟踪 \(trackers.count) 个（\(mode)）"
        if trackers.isEmpty {
            lastError = "未发现可用的温度传感器"
            return false
        }
        return true
    }

    /// 执行一次采样。
    func sample() -> SMCSnapshot {
        var snapshot = SMCSnapshot()
        guard driver.isOpen, !trackers.isEmpty else { return snapshot }

        var buckets: [SensorCategory: [(key: String, value: Double)]] = [:]

        for tracker in trackers {
            var celsius: Double?
            if let raw = driver.read(key: tracker.key, dataSize: tracker.dataSize),
               let decoded = SMCDriver.decode(type: tracker.type, bytes: raw.bytes, dataSize: raw.dataSize) {
                celsius = validateTemperature(decoded, tracker: tracker)
            }
            let sensor = TemperatureSensor(
                key: tracker.key,
                name: tracker.name,
                category: tracker.category,
                celsius: celsius,
                typeName: tracker.type,
                note: tracker.isPlaceholder ? "占位键" : nil
            )
            snapshot.sensors.append(sensor)
            if let value = celsius {
                buckets[tracker.category, default: []].append((tracker.key, value))
                snapshot.validSensorCount += 1
            }
            if tracker.role == .cpuCoreP || tracker.role == .cpuCoreE {
                snapshot.cpuCores.append(sensor)
            }
        }

        snapshot.fans = fanTrackers.map { tracker in
            let rpm = readNumeric(key: tracker.rpmKey, type: tracker.rpmType, size: tracker.rpmSize)
            let minRPM = tracker.minKey.flatMap { key in
                readNumeric(key: key, type: tracker.minType ?? "", size: tracker.minSize)
            }
            let maxRPM = tracker.maxKey.flatMap { key in
                readNumeric(key: key, type: tracker.maxType ?? "", size: tracker.maxSize)
            }
            return FanReading(
                id: tracker.index,
                name: "风扇 \(tracker.index + 1)",
                rpm: rpm,
                minRPM: minRPM,
                maxRPM: maxRPM
            )
        }

        if let powerTracker,
           let raw = driver.read(key: powerTracker.key, dataSize: powerTracker.dataSize),
           let value = SMCDriver.decode(type: powerTracker.type, bytes: raw.bytes, dataSize: raw.dataSize),
           value > 0.05, value < 500 {
            snapshot.powerWatts = value
        }

        snapshot.groups = buildGroups(from: buckets)
        return snapshot
    }

    // MARK: - 内部

    private func validateTemperature(_ value: Double, tracker: SensorTracker) -> Double? {
        guard !tracker.isPlaceholder, value.isFinite else { return nil }
        // 不同部件的合理温度区间不同：GPU 键会偶发 -4.5 / 0.1 的毛刺，电池传感器上限也只有 60°C。
        let range = SensorCatalog.validRange(for: tracker.category)
        guard value > range.lowerBound, value < range.upperBound else { return nil }
        return value
    }

    private func readNumeric(key: String, type: String, size: UInt32) -> Double? {
        guard size > 0,
              let raw = driver.read(key: key, dataSize: size),
              let value = SMCDriver.decode(type: type, bytes: raw.bytes, dataSize: raw.dataSize),
              value.isFinite
        else { return nil }
        return value
    }

    private func buildGroups(from buckets: [SensorCategory: [(key: String, value: Double)]]) -> [TemperatureGroup] {
        var groups: [TemperatureGroup] = []
        let profile = profile ?? SMCProfile.detect()

        for category in SensorCategory.dashboardCardOrder {
            groups.append(makeGroup(category: category, entries: buckets[category] ?? [], profile: profile))
        }
        for category in [SensorCategory.package, .vrm, .display, .enclosure, .other] {
            let entries = buckets[category] ?? []
            if entries.isEmpty { continue }
            groups.append(makeGroup(category: category, entries: entries, profile: profile))
        }
        return groups
    }

    /// 各部件实测推荐的主指标键（docs/SENSOR_MAP.md §4），按优先级排列。
    private static let primaryKeyOverrides: [SensorCategory: [String]] = [
        .cpu: ["TCMz"],
        .gpu: ["Tg0D"],
        .memory: ["Tm0B"],
        .storage: ["TH0x"],
        .battery: ["TB0T"],
        .wireless: ["TW0P"],
        .package: ["TPMP"],
        .vrm: ["TVV0", "TVM0"],
        .display: ["TDBP"],
        .enclosure: ["TAOL"],
    ]

    private func makeGroup(
        category: SensorCategory,
        entries: [(key: String, value: Double)],
        profile: SMCProfile
    ) -> TemperatureGroup {
        let values = entries.map { $0.value }
        var average = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        var maximum = values.max()

        // CPU 卡片使用「每核心传感器」的口径：热点 TCMz 为主指标，平均/最高只统计 10 个物理核。
        if category == .cpu {
            let coreValues = entries.compactMap { entry -> Double? in
                guard let role = roleByKey[entry.key] else { return nil }
                return (role == .cpuCoreP || role == .cpuCoreE) ? entry.value : nil
            }
            if !coreValues.isEmpty {
                average = coreValues.reduce(0, +) / Double(coreValues.count)
                maximum = coreValues.max()
            }
        }

        // 主指标：优先使用实测推荐键，取不到再按部件类型回退。
        var primary: Double?
        if let candidates = Self.primaryKeyOverrides[category] {
            for key in candidates {
                if let value = entries.first(where: { $0.key == key })?.value {
                    primary = value
                    break
                }
            }
        }
        if primary == nil {
            switch category {
            case .cpu, .gpu, .storage: primary = maximum
            default: primary = average
            }
        }

        return TemperatureGroup(
            id: category.rawValue,
            category: category,
            title: category.cardTitle,
            subtitle: subtitle(for: category, profile: profile),
            primary: primary,
            average: average,
            maximum: maximum,
            sensorCount: entries.count,
            symbolName: category.symbolName,
            isPrimaryCard: SensorCategory.dashboardCardOrder.contains(category)
        )
    }

    private func subtitle(for category: SensorCategory, profile: SMCProfile) -> String {
        switch category {
        case .cpu:
            let p = profile.pCores > 0 ? "\(profile.pCores)P" : "P"
            let e = profile.eCores > 0 ? "\(profile.eCores)E" : "E"
            return "\(profile.chipName) · \(p) + \(e)"
        case .gpu:
            return profile.gpuCores > 0 ? "\(profile.gpuCores) 核 GPU" : "统一 GPU"
        case .memory:
            return "统一内存 LPDDR5X"
        case .storage:
            return "NAND 闪存"
        case .battery:
            return "内置电池组"
        case .wireless:
            return "Wi-Fi / 蓝牙模块"
        case .package:
            return "SoC 封装基板"
        case .vrm:
            return "供电 VRM 阵列"
        case .display:
            return "显示屏"
        case .enclosure:
            return "机身 / 环境"
        case .other:
            return "其他测点"
        }
    }
}

/// 扫描阶段收集的一台风扇的元数据。
private struct FanMetaSet {
    var rpm: SMCKeyMeta?
    var min: SMCKeyMeta?
    var max: SMCKeyMeta?
}
