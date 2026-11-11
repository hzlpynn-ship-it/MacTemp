// MacTemp / Sources/Collectors/NetworkSupport.swift
// 归属：collectors（采集器）——网络接口枚举与字节计数（getifaddrs + if_data）。
//
// 静态信息（SystemInfoCollector）与实时速率（LiveStatsCollector）共用这里的结果，
// 避免各自重复实现 getifaddrs。

import Foundation
import Darwin

/// 单个网络接口的快照：地址信息 + 累计收发字节。
struct NetworkInterfaceSnapshot {
    var name: String = ""
    var ipv4: String?
    var ipv6: String?
    /// IPv6 链路本地地址（fe80::），当没有全局地址时作为兜底展示。
    var ipv6LinkLocal: String?
    var macAddress: String?
    var isUp: Bool = false
    /// 累计接收字节（来自 if_data.ifi_ibytes）
    var receivedBytes: UInt64 = 0
    /// 累计发送字节（来自 if_data.ifi_obytes）
    var sentBytes: UInt64 = 0
}

/// 网络接口读取器。
enum NetworkReader {
    /// 一次 getifaddrs 遍历，汇总出所有接口的地址与计数。
    /// 任何底层调用失败都返回空数组（安全降级）。
    static func readInterfaces() -> [NetworkInterfaceSnapshot] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(first) }

        // 接口名 -> 快照；用字典聚合 AF_LINK / AF_INET / AF_INET6 三类 entry。
        var table: [String: NetworkInterfaceSnapshot] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let current = cursor {
            let ifa = current.pointee
            cursor = ifa.ifa_next

            let name = String(cString: ifa.ifa_name)
            guard !name.isEmpty else { continue }

            var snapshot = table[name] ?? NetworkInterfaceSnapshot(name: name)
            // IFF_UP = 0x1
            snapshot.isUp = (ifa.ifa_flags & UInt32(IFF_UP)) != 0

            let family = ifa.ifa_addr.map { Int32($0.pointee.sa_family) } ?? -1

            switch family {
            case AF_LINK:
                // 链路层：MAC 地址 + 收发字节计数
                if let address = ifa.ifa_addr, let data = ifa.ifa_data {
                    let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                    snapshot.receivedBytes = UInt64(ifData.ifi_ibytes)
                    snapshot.sentBytes = UInt64(ifData.ifi_obytes)
                    if snapshot.macAddress == nil {
                        snapshot.macAddress = macAddress(from: address)
                    }
                }
            case AF_INET:
                if let address = ifa.ifa_addr, snapshot.ipv4 == nil {
                    snapshot.ipv4 = ipv4String(from: address)
                }
            case AF_INET6:
                if let address = ifa.ifa_addr {
                    if let text = ipv6String(from: address) {
                        // 优先展示全局地址；fe80:: 链路本地地址仅作兜底。
                        if text.lowercased().hasPrefix("fe80") {
                            if snapshot.ipv6LinkLocal == nil { snapshot.ipv6LinkLocal = text }
                        } else if snapshot.ipv6 == nil {
                            snapshot.ipv6 = text
                        }
                    }
                }
            default:
                break
            }

            table[name] = snapshot
        }

        return Array(table.values)
    }

    /// 实时速率用的累计计数：优先所有已启用的物理接口（en*，Wi-Fi / 以太网）之和；
    /// 若没有 en*（极少数情况），退化为所有已启用且非回环/非 AirDrop 的接口之和。
    ///
    /// 返回的 key 用于检测"参与统计的接口集合"是否变化；集合变化时本帧速率应记为 0，
    /// 否则跨接口的计数差会得到离谱的速率。
    static func aggregateCounters(_ interfaces: [NetworkInterfaceSnapshot]) -> (key: String, received: UInt64, sent: UInt64) {
        let physical = interfaces.filter { $0.isUp && $0.name.hasPrefix("en") }
        if !physical.isEmpty {
            let sorted = physical.sorted { $0.name < $1.name }
            let key = "en:" + sorted.map(\.name).joined(separator: ",")
            var received: UInt64 = 0
            var sent: UInt64 = 0
            for item in sorted {
                received &+= item.receivedBytes
                sent &+= item.sentBytes
            }
            return (key, received, sent)
        }

        // 兜底：排除回环、AirDrop / 低延迟 WLAN、Old-school 隧道等会重复计数的接口。
        let fallback = interfaces.filter { item in
            guard item.isUp else { return false }
            let name = item.name
            let ignored = name.hasPrefix("lo") || name.hasPrefix("awdl") || name.hasPrefix("llw")
                || name.hasPrefix("gif") || name.hasPrefix("stf")
            return !ignored
        }
        let sorted = fallback.sorted { $0.name < $1.name }
        let key = "fallback:" + sorted.map(\.name).joined(separator: ",")
        var received: UInt64 = 0
        var sent: UInt64 = 0
        for item in sorted {
            received &+= item.receivedBytes
            sent &+= item.sentBytes
        }
        return (key, received, sent)
    }

    // MARK: - 地址解析

    private static func ipv4String(from address: UnsafeMutablePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let result: String? = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
            var addr = pointer.pointee.sin_addr
            guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buffer)
        }
        return result
    }

    private static func ipv6String(from address: UnsafeMutablePointer<sockaddr>) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let result: String? = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
            var addr = pointer.pointee.sin6_addr
            guard inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buffer)
        }
        return result
    }

    /// 从 sockaddr_dl 中解析 6 字节 MAC。
    /// sockaddr_dl 布局：sdl_len(0) / sdl_family(1) / sdl_index(2,u16) / sdl_type(4)
    /// / sdl_nlen(5) / sdl_alen(6) / sdl_slen(7) / sdl_data(8...)，LLADDR = sdl_data + sdl_nlen。
    private static func macAddress(from address: UnsafeMutablePointer<sockaddr>) -> String? {
        guard Int32(address.pointee.sa_family) == AF_LINK else { return nil }
        let raw = UnsafeRawPointer(address)
        let addressLength = Int(address.pointee.sa_len)
        guard addressLength >= 8 else { return nil }
        let nameLength = Int(raw.load(fromByteOffset: 5, as: UInt8.self))
        let linkLength = Int(raw.load(fromByteOffset: 6, as: UInt8.self))
        guard linkLength == 6, 8 + nameLength + linkLength <= addressLength else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(6)
        for index in 0..<linkLength {
            bytes.append(raw.load(fromByteOffset: 8 + nameLength + index, as: UInt8.self))
        }
        guard bytes.contains(where: { $0 != 0 }) else { return nil }
        return bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
