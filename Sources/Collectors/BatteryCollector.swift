// MacTemp / Sources/Collectors/BatteryCollector.swift
// 归属：collectors（采集器）——电池信息采集（IOPS + AppleSmartBattery IORegistry）。
//
// 数据来源：
//   1. IOKit.ps：IOPSCopyPowerSourcesInfo / IOPSCopyPowerSourcesList → 电量、充放电状态、剩余时间；
//   2. IORegistry "AppleSmartBattery"：循环次数、设计容量、实际最大容量、电芯温度、充电状态等。
// 所有字段都可能缺失（老机器 / 无电池机型 / 权限受限），一律返回 nil 降级，绝不强制解包。
//
// 电池温度单位校准（重要）：
//   AppleSmartBattery 的 "Temperature" 原始值不是摄氏度，也不是开尔文，而是 **0.1 开尔文（deci-Kelvin）**。
//   本机实测（Mac16,12, macOS 15.6.1）：原始值 3001~3014 → 300.1~301.4 K → 26.95~28.25 °C；
//   同时用 smctemp 读取电池 SMC 温度键交叉验证：
//     TB0T = 27.2°C、TB1T = 26.3°C、TB2T = 27.2°C、ftB0 = 26.8°C
//   两者吻合（误差 < 1.5°C），确认原始值单位是 0.1 K，换算公式：°C = raw / 10 - 273.15。
//   为兼容其他机型，按量级自适应：raw > 1000 按 0.1K；> 200 按 K；> 0 按已是 °C。
//   换算后超出 -20...80°C 视为无效返回 nil（防止单位识别错误时显示离谱温度）。

import Foundation
import IOKit
import IOKit.ps

struct BatteryCollector {
    /// 采集当前电池信息；无电池机型（Mac mini / Mac Studio 等）返回 nil。
    static func collect() -> BatteryInfo? {
        let powerSourceDescription = readPowerSourceDescription()
        let smartBattery = IOKitHelper.firstProperties("AppleSmartBattery") ?? [:]

        let isPresent: Bool = {
            if let present = AnyValue.bool(powerSourceDescription?["Is Present"]) { return present }
            if let installed = AnyValue.int(smartBattery["BatteryInstalled"]) { return installed != 0 }
            return !smartBattery.isEmpty
        }()
        guard isPresent || !smartBattery.isEmpty else { return nil }

        let charging = AnyValue.bool(smartBattery["IsCharging"])
            ?? AnyValue.bool(powerSourceDescription?["Is Charging"])
            ?? false
        // 注意：右侧表达式本身非可选，所以不需要再补 ?? false。
        let pluggedIn = AnyValue.bool(smartBattery["ExternalConnected"])
            ?? (AnyValue.string(powerSourceDescription?["Power Source State"]) == "AC Power")

        // 电量：优先 AppleSmartBattery 顶层的 CurrentCapacity（已经是 0...100 百分比），
        // 其次用 IOPS 的 Current/Max 比例。
        var chargePercent: Double?
        if let percent = AnyValue.double(smartBattery["CurrentCapacity"]), percent >= 0, percent <= 100 {
            chargePercent = percent
        } else if let current = AnyValue.double(powerSourceDescription?["Current Capacity"]),
                  let maximum = AnyValue.double(powerSourceDescription?["Max Capacity"]),
                  maximum > 0 {
            chargePercent = min(100, max(0, current / maximum * 100))
        }

        // 剩余时间：充电中显示"充满还需"，放电时显示"剩余使用"；未知值（0 / -1 / 65535）返回 nil。
        var timeRemainingMinutes: Int?
        let maximumValidMinutes = 7 * 24 * 60
        if charging {
            if let minutes = AnyValue.int(powerSourceDescription?["Time to Full Charge"]),
               minutes > 0, minutes < maximumValidMinutes {
                timeRemainingMinutes = minutes
            }
        } else if let minutes = AnyValue.int(powerSourceDescription?["Time to Empty"]),
                  minutes > 0, minutes < maximumValidMinutes {
            timeRemainingMinutes = minutes
        }

        let designCapacity = AnyValue.int(smartBattery["DesignCapacity"])
        let nominalCapacity = AnyValue.int(smartBattery["NominalChargeCapacity"])
        let rawMaxCapacity = AnyValue.int(smartBattery["AppleRawMaxCapacity"])
        let rawCurrentCapacity = AnyValue.int(smartBattery["AppleRawCurrentCapacity"])

        // 健康度口径：对齐系统设置 / 系统信息里的"最大容量"。
        // 实测本机 system_profiler 显示 Maximum Capacity = 100%，而
        // NominalChargeCapacity(4646) / DesignCapacity(4629) = 100.4%，
        // AppleRawMaxCapacity(4519) / DesignCapacity = 97.6%；
        // 可见系统用的是 NominalChargeCapacity 并封顶到 100%。
        // 部分机型没有 NominalChargeCapacity，则退回 AppleRawMaxCapacity。
        var healthPercent: Double?
        if let design = designCapacity, design > 0 {
            if let basis = nominalCapacity ?? rawMaxCapacity, basis > 0 {
                healthPercent = min(100, max(0, Double(basis) / Double(design) * 100))
            }
        }

        let condition = localizedCondition(
            rawCondition: AnyValue.string(powerSourceDescription?["BatteryHealthCondition"])
                ?? AnyValue.string(powerSourceDescription?["BatteryHealth"]),
            permanentFailureStatus: AnyValue.int(smartBattery["PermanentFailureStatus"]) ?? 0
        )

        return BatteryInfo(
            isPresent: isPresent,
            chargePercent: chargePercent ?? 0,
            isCharging: charging,
            isPluggedIn: pluggedIn,
            timeRemainingMinutes: timeRemainingMinutes,
            cycleCount: AnyValue.int(smartBattery["CycleCount"]),
            healthPercent: healthPercent,
            designCapacitymAh: designCapacity,
            maxCapacitymAh: rawMaxCapacity ?? nominalCapacity,
            currentCapacitymAh: rawCurrentCapacity,
            temperatureCelsius: batteryTemperature(from: smartBattery),
            condition: condition
        )
    }

    // MARK: - 内部实现

    /// 从 IOPS 取内置电池的描述字典。
    private static func readPowerSourceDescription() -> [String: Any]? {
        guard let blobUnmanaged = IOPSCopyPowerSourcesInfo() else { return nil }
        let blob = blobUnmanaged.takeRetainedValue()
        guard let listUnmanaged = IOPSCopyPowerSourcesList(blob) else { return nil }
        // IOPSCopyPowerSourcesList 返回 CFArray，元素为各电源的 IOPowerSource 引用（数组持有，不额外 retain）。
        let sourcesArray = listUnmanaged.takeRetainedValue()
        let sourceCount = CFArrayGetCount(sourcesArray)
        var fallback: [String: Any]?
        for index in 0..<sourceCount {
            guard let rawSource = CFArrayGetValueAtIndex(sourcesArray, index) else { continue }
            let source = Unmanaged<CFTypeRef>.fromOpaque(rawSource).takeUnretainedValue()
            guard let descriptionUnmanaged = IOPSGetPowerSourceDescription(blob, source) else { continue }
            let description = descriptionUnmanaged.takeUnretainedValue() as? [String: Any] ?? [:]
            // 优先内置电池；外接 UPS 等电源作为兜底。
            if AnyValue.string(description["Type"]) == "InternalBattery" {
                return description
            }
            if fallback == nil { fallback = description }
        }
        return fallback
    }

    /// AppleSmartBattery.Temperature（0.1 K）→ 摄氏度。
    /// 详见文件头注释里的实测校准记录。
    private static func batteryTemperature(from properties: [String: Any]) -> Double? {
        guard let raw = AnyValue.double(properties["Temperature"]), raw > 0 else { return nil }
        let celsius: Double
        if raw > 1000 {
            celsius = raw / 10.0 - 273.15   // 0.1 K（本机实测路径）
        } else if raw > 200 {
            celsius = raw - 273.15          // K
        } else {
            celsius = raw                   // 已经是 °C
        }
        guard celsius > -20, celsius < 80 else { return nil }
        return celsius
    }

    /// 电池健康状态本地化。
    /// 本机实测：IOPS 的 BatteryHealthCondition 是空字符串，BatteryHealth = "Check Battery"
    /// （旧版兼容字段，并不可靠），而 system_profiler 显示 Condition: Normal、最大容量 100%。
    /// 因此：空字符串忽略；只有明确的 Service/Replace/Poor/Fail 或 PermanentFailureStatus != 0
    /// 才提示"建议维修"；其余情况返回"正常"（与系统信息/系统设置一致）。
    private static func localizedCondition(rawCondition: String?, permanentFailureStatus: Int) -> String? {
        if let raw = rawCondition?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty {
            if raw.contains("normal") || raw.contains("good") { return "正常" }
            if raw.contains("service") || raw.contains("replace") || raw.contains("poor")
                || raw.contains("fail") {
                return "建议维修"
            }
        }
        if permanentFailureStatus != 0 { return "建议维修" }
        return "正常"
    }
}
