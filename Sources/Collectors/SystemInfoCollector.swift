// MacTemp / Sources/Collectors/SystemInfoCollector.swift
// 归属：collectors（采集器）——静态系统信息采集。
//
// 全部来自系统公开/半公开 API，不 spawn 外部进程：
//   sysctl（hw.model / machdep.cpu.brand_string / hw.memsize / hw.perflevel*.logicalcpu /
//           kern.osversion / kern.osrelease / kern.boottime）、
//   ProcessInfo、FileManager（挂载卷）、CoreGraphics（活动显示器与刷新率）、
//   IOKit IORegistry（IOPlatformExpertDevice 序列号/UUID、AGXAccelerator 的 gpu-core-count）、
//   getifaddrs（网络接口/IP/MAC）、IOKit.ps（当前供电来源）。
//
// 注意：显示器信息只用 CoreGraphics，不用 NSScreen —— AppState 可能在后台线程调用本采集器，
// NSScreen 只能在主线程使用。所有字段缺失时安全降级（nil/0/"-"）。

import Foundation
import CoreGraphics
import IOKit
import IOKit.ps

final class SystemInfoCollector: SystemInfoProviding {
    init() {}

    func collect() -> SystemInfo {
        let uptime = ProcessInfo.processInfo.systemUptime
        let modelIdentifier = SysctlReader.string("hw.model") ?? "-"
        let battery = BatteryCollector.collect()

        var info = SystemInfo.placeholder
        info.modelName = Self.modelName(for: modelIdentifier, chipName: Self.chipName())
        info.modelIdentifier = modelIdentifier
        info.chipName = Self.chipName()
        info.architecture = Self.architecture
        info.performanceCores = SysctlReader.int("hw.perflevel0.logicalcpu") ?? 0
        info.efficiencyCores = SysctlReader.int("hw.perflevel1.logicalcpu") ?? 0
        info.totalCores = SysctlReader.int("hw.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount
        info.gpuCores = Self.cachedGPUCoreCount
        info.memoryBytes = SysctlReader.uint64("hw.memsize") ?? ProcessInfo.processInfo.physicalMemory
        info.macOSVersion = Self.macOSVersionText()
        info.macOSBuild = SysctlReader.string("kern.osversion") ?? "-"
        if let release = SysctlReader.string("kern.osrelease") {
            info.kernelVersion = "Darwin \(release)"
        }
        info.uptime = uptime
        info.bootDate = Self.bootDate(uptime: uptime)
        info.hostname = Self.hostname()
        info.powerSource = Self.powerSourceText(battery: battery)
        info.displays = Self.collectDisplays()
        info.disks = Self.collectDisks()
        info.networks = Self.collectNetworks(hasBattery: battery != nil)
        info.battery = battery

        let identity = Self.hardwareIdentity()
        info.serialNumber = identity.serial ?? "-"
        info.hardwareUUID = identity.uuid ?? "-"

        return info
    }

    // MARK: - 芯片 / 机型

    /// 芯片名称：IORegistry 里没有更友好的名字，sysctl machdep.cpu.brand_string = "Apple M4"。
    private static func chipName() -> String {
        SysctlReader.string("machdep.cpu.brand_string") ?? "Apple Silicon"
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    /// 机型标识（Mac16,12）→ 人类可读名称。
    /// 表内是本项目目标机型及常见 Apple Silicon 机型；未知机型回退为 "Mac（芯片名）"。
    private static func modelName(for identifier: String, chipName: String) -> String {
        if let known = modelNameTable[identifier] { return known }
        if identifier.hasPrefix("MacBookAir") { return "MacBook Air" }
        if identifier.hasPrefix("MacBookPro") { return "MacBook Pro" }
        if identifier.hasPrefix("Macmini") { return "Mac mini" }
        if identifier.hasPrefix("iMac") { return "iMac" }
        if identifier.hasPrefix("MacStudio") || identifier.hasPrefix("Mac13") || identifier.hasPrefix("Mac14,8") {
            return "Mac Studio"
        }
        if identifier.hasPrefix("MacPro") { return "Mac Pro" }
        return chipName.isEmpty ? "Mac" : "Mac（\(chipName)）"
    }

    private static let modelNameTable: [String: String] = [
        // M1 世代
        "MacBookAir10,1": "MacBook Air (M1, 2020)",
        "MacBookPro17,1": "MacBook Pro (13 英寸, M1, 2020)",
        "MacBookPro18,1": "MacBook Pro (14 英寸, M1 Pro, 2021)",
        "MacBookPro18,2": "MacBook Pro (16 英寸, M1 Max, 2021)",
        "Macmini9,1": "Mac mini (M1, 2020)",
        "iMac21,1": "iMac (24 英寸, M1, 2021)",
        "Mac13,1": "Mac Studio (M1 Max, 2022)",
        "Mac13,2": "Mac Studio (M1 Ultra, 2022)",
        // M2 世代
        "Mac14,2": "MacBook Air (13 英寸, M2, 2022)",
        "Mac14,15": "MacBook Air (15 英寸, M2, 2023)",
        "Mac14,5": "MacBook Pro (14 英寸, M2 Pro/Max, 2023)",
        "Mac14,6": "MacBook Pro (16 英寸, M2 Pro/Max, 2023)",
        "Mac14,13": "Mac mini (M2, 2023)",
        "Mac14,14": "Mac mini (M2 Pro, 2023)",
        "Mac14,8": "Mac Studio (M2 Ultra, 2023)",
        // M3 世代
        "Mac15,12": "MacBook Air (13 英寸, M3, 2024)",
        "Mac15,13": "MacBook Air (15 英寸, M3, 2024)",
        "Mac15,3": "MacBook Pro (14 英寸, M3, 2023)",
        "Mac15,6": "MacBook Pro (14 英寸, M3 Pro/Max, 2023)",
        "Mac15,8": "MacBook Pro (16 英寸, M3 Pro/Max, 2023)",
        "Mac15,4": "iMac (24 英寸, M3, 2023)",
        "Mac15,5": "iMac (24 英寸, M3, 2023)",
        // M4 世代（本项目目标机型 Mac16,12 为 13 英寸 MacBook Air M4）
        "Mac16,12": "MacBook Air (13 英寸, M4, 2025)",
        "Mac16,13": "MacBook Air (15 英寸, M4, 2025)",
        "Mac16,1": "MacBook Pro (14 英寸, M4, 2024)",
        "Mac16,6": "MacBook Pro (14 英寸, M4 Pro/Max, 2024)",
        "Mac16,5": "MacBook Pro (16 英寸, M4 Pro/Max, 2024)",
        "Mac16,2": "iMac (24 英寸, M4, 2024)",
        "Mac16,3": "iMac (24 英寸, M4, 2024)",
        "Mac16,10": "Mac mini (M4, 2024)",
        "Mac16,11": "Mac mini (M4 Pro, 2024)"
    ]

    /// AGXAccelerator 的 "gpu-core-count"（例如 M4 = 10）。
    /// 性能注意：只读单个属性，不拉取整个属性字典（AGXAccelerator 的完整属性里含 SchedulerState
    /// 等大对象，首次读取要 10ms+）；同时缓存结果 —— GPU 核数是静态值，collect() 可能被反复调用。
    private static let cachedGPUCoreCount: Int = {
        var cores = 0
        IOKitHelper.forEachService("IOAccelerator") { service in
            guard cores == 0,
                  let value = IOKitHelper.property(of: service, key: "gpu-core-count"),
                  let count = AnyValue.int(value), count > 0 else { return }
            cores = count
        }
        return cores
    }()

    // MARK: - 系统版本 / 时间 / 主机名

    private static func macOSVersionText() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.patchVersion == 0 {
            return "macOS \(version.majorVersion).\(version.minorVersion)"
        }
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func bootDate(uptime: TimeInterval) -> Date {
        if let bootTime = SysctlReader.timevalValue("kern.boottime"), bootTime.tv_sec > 0 {
            return Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec))
        }
        return Date().addingTimeInterval(-uptime)
    }

    private static func hostname() -> String {
        var name = ProcessInfo.processInfo.hostName
        if name.isEmpty {
            name = SysctlReader.string("kern.hostname") ?? "-"
        }
        // 去掉局域网后缀，界面展示更干净。
        if name.hasSuffix(".local") { name.removeLast(".local".count) }
        return name.isEmpty ? "-" : name
    }

    /// IOPlatformExpertDevice 里的序列号与硬件 UUID（无需 root 即可读取）。
    private static func hardwareIdentity() -> (serial: String?, uuid: String?) {
        guard let properties = IOKitHelper.firstProperties("IOPlatformExpertDevice") else {
            return (nil, nil)
        }
        return (
            AnyValue.string(properties["IOPlatformSerialNumber"]),
            AnyValue.string(properties["IOPlatformUUID"])
        )
    }

    // MARK: - 供电来源

    private static func powerSourceText(battery: BatteryInfo?) -> String {
        if let unmanaged = IOPSGetProvidingPowerSourceType(nil) {
            let type = unmanaged.takeUnretainedValue() as String
            if type == "AC Power" { return "电源适配器" }
            if type == "Battery Power" { return "电池供电" }
        }
        if let battery {
            return battery.isPluggedIn ? "电源适配器" : "电池供电"
        }
        return "-"
    }

    // MARK: - 显示器（CoreGraphics，后台线程安全）

    private static func collectDisplays() -> [DisplayInfo] {
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(displayIDs.count), &displayIDs, &count) == .success else {
            return []
        }

        var displays: [DisplayInfo] = []
        for index in 0..<Int(count) {
            let displayID = displayIDs[index]
            let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
            let isMain = CGDisplayIsMain(displayID) != 0

            var resolution = "-"
            var refreshRate: Double?
            if let mode = CGDisplayCopyDisplayMode(displayID) {
                resolution = "\(mode.pixelWidth) × \(mode.pixelHeight)"
                let rate = mode.refreshRate
                if rate.isFinite, rate > 1, rate < 1000 { refreshRate = rate }
            }

            let name: String
            if isBuiltin {
                name = "内置显示器"
            } else {
                name = "外接显示器 \(index + 1)"
            }
            displays.append(DisplayInfo(name: name, resolution: resolution, refreshRate: refreshRate, isMain: isMain))
        }

        // 主显示器排在最前，其余保持枚举顺序。
        displays.sort { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            return lhs.name < rhs.name
        }
        return displays
    }

    // MARK: - 存储卷

    private static func collectDisks() -> [DiskInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeIsBrowsableKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else { return [] }

        var disks: [DiskInfo] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.volumeIsBrowsable != false else { continue }
            let totalBytes = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            guard totalBytes > 0 else { continue }
            let freeBytes = UInt64(max(0, values.volumeAvailableCapacity ?? 0))
            disks.append(DiskInfo(
                name: values.volumeName ?? url.lastPathComponent,
                mountPoint: url.path,
                fileSystem: values.volumeLocalizedFormatDescription ?? "-",
                totalBytes: totalBytes,
                freeBytes: freeBytes,
                isInternal: values.volumeIsInternal ?? false,
                isRemovable: values.volumeIsRemovable ?? false
            ))
        }

        // 内置盘在前；同类型按挂载点排序，保证界面顺序稳定。
        disks.sort { lhs, rhs in
            if lhs.isInternal != rhs.isInternal { return lhs.isInternal }
            return lhs.mountPoint < rhs.mountPoint
        }
        return disks
    }

    // MARK: - 网络接口

    private static func collectNetworks(hasBattery: Bool) -> [NetworkInterfaceInfo] {
        let snapshots = NetworkReader.readInterfaces()
        // 过滤回环、AirDrop / 低延迟 WLAN、虚拟调试接口、虚拟机桥接等，这些接口对普通用户没有展示价值。
        let skippedPrefixes = ["lo", "awdl", "llw", "gif", "stf", "anpi", "vmenet", "bridge", "ap"]

        var interfaces: [NetworkInterfaceInfo] = []
        for snapshot in snapshots {
            guard snapshot.isUp else { continue }
            if skippedPrefixes.contains(where: { snapshot.name.hasPrefix($0) }) { continue }
            // 只展示"真正承载地址"的接口：
            //   * en0 是主力网卡，始终保留（Wi-Fi 重连没有地址时也能看到接口状态）；
            //   * 其他接口必须有 IPv4 或全局 IPv6 才展示；
            //   * 纯链路本地 IPv6（fe80::）的 utun 等隧道不展示，避免刷屏。
            let hasUsableAddress = snapshot.ipv4 != nil || snapshot.ipv6 != nil
            guard snapshot.name == "en0" || hasUsableAddress else { continue }
            interfaces.append(NetworkInterfaceInfo(
                name: snapshot.name,
                typeLabel: typeLabel(for: snapshot.name, hasBattery: hasBattery),
                ipv4: snapshot.ipv4,
                ipv6: snapshot.ipv6 ?? snapshot.ipv6LinkLocal,
                macAddress: snapshot.macAddress,
                isUp: snapshot.isUp
            ))
        }

        interfaces.sort { lhs, rhs in
            let leftRank = sortRank(lhs.name)
            let rightRank = sortRank(rhs.name)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.name < rhs.name
        }
        return interfaces
    }

    /// 接口排序权重：en0（主力网卡）最前，其次其他物理网卡，再到 VPN / 网桥等。
    private static func sortRank(_ name: String) -> Int {
        if name == "en0" { return 0 }
        if name.hasPrefix("en") { return 1 }
        if name.hasPrefix("utun") { return 2 }
        if name.hasPrefix("bridge") { return 3 }
        return 4
    }

    /// 接口类型的中文标签。
    /// 说明：sysctl/if_data 无法区分 Wi-Fi 与有线以太网；对带电池的笔记本（含本机 MacBook Air）
    /// en0 就是 Wi-Fi，其余 en* 视为以太网（USB 网卡 / 扩展坞）。
    private static func typeLabel(for name: String, hasBattery: Bool) -> String {
        if name.hasPrefix("en") {
            if name == "en0" && hasBattery { return "Wi-Fi" }
            return "以太网"
        }
        if name.hasPrefix("utun") { return "VPN 隧道" }
        if name.hasPrefix("bridge") { return "桥接网络" }
        if name.hasPrefix("p2p") { return "直连网络" }
        if name.hasPrefix("ap") { return "个人热点" }
        return "网络接口"
    }
}
