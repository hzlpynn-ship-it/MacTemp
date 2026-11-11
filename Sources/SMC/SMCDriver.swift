import Foundation

// MacTemp SMC 驱动（Swift 侧）
// 负责打开 AppleSMC、枚举键、读取原始值，并把 SMC 数据类型解码成 Double。
// 注意：Apple Silicon 上 "flt " 类型按小端浮点存储；带 sp/fp 前缀的定点类型为大端。
// 该解码规则与开源工具 smctemp 一致，并已在 MacBook Air M4 (macOS 15.6.1) 上实测验证。

/// 一次原始 SMC 读取结果。
struct SMCRawValue {
    let key: String
    let type: String
    let dataSize: UInt32
    let bytes: [UInt8]
}

/// SMC 键元数据（扫描阶段缓存，刷新时避免重复查询）。
struct SMCKeyMeta {
    let key: String
    let type: String
    let dataSize: UInt32
}

final class SMCDriver {
    static let shared = SMCDriver()

    private var opened = false

    private init() {}

    var isOpen: Bool { opened }

    /// 打开 AppleSMC。返回是否成功。
    func open() -> Bool {
        if opened { return true }
        let rc = mt_smc_open()
        opened = (rc == 0)
        return opened
    }

    func close() {
        if opened {
            mt_smc_close()
            opened = false
        }
    }

    /// SMC 键总数。
    func keyCount() -> Int {
        guard opened else { return 0 }
        return Int(mt_smc_key_count())
    }

    /// 枚举第 index 个键名。
    func key(at index: Int) -> String? {
        guard opened, index >= 0, index < 0xFFFF else { return nil }
        var buffer = [CChar](repeating: 0, count: 5)
        let rc = mt_smc_key_at(UInt32(index), &buffer)
        guard rc == 0 else { return nil }
        let key = Self.string(fromCChars: buffer)
        guard key.count == 4 else { return nil }
        return key
    }

    /// 查询键的元数据（类型 + 长度）。
    func keyInfo(_ key: String) -> (type: String, dataSize: UInt32)? {
        guard opened else { return nil }
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        let rc = key.withCString { cs in
            mt_smc_key_info(cs, &dataSize, &dataType)
        }
        guard rc == 0, dataSize <= 32 else { return nil }
        let bytes = [
            UInt8((dataType >> 24) & 0xff),
            UInt8((dataType >> 16) & 0xff),
            UInt8((dataType >> 8) & 0xff),
            UInt8(dataType & 0xff),
        ]
        let type = String(bytes: bytes, encoding: .ascii) ?? ""
        return (type, dataSize)
    }

    /// 使用已知长度读取键内容（刷新阶段使用，每次仅一次 IPC）。
    func read(key: String, dataSize: UInt32) -> SMCRawValue? {
        guard opened, dataSize > 0, dataSize <= 32 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        let rc = key.withCString { cs in
            mt_smc_read_simple(cs, dataSize, &bytes)
        }
        guard rc == 0 else { return nil }
        return SMCRawValue(key: key, type: "", dataSize: dataSize, bytes: bytes)
    }

    /// 查询元数据后读取（扫描阶段使用）。
    func readAuto(key: String) -> SMCRawValue? {
        guard opened else { return nil }
        var size: UInt32 = 0
        var typeBuffer = [CChar](repeating: 0, count: 5)
        var bytes = [UInt8](repeating: 0, count: 32)
        let rc = key.withCString { cs in
            mt_smc_read_auto_simple(cs, &size, &typeBuffer, &bytes)
        }
        guard rc == 0, size > 0, size <= 32 else { return nil }
        let type = Self.string(fromCChars: typeBuffer)
        return SMCRawValue(key: key, type: type, dataSize: size, bytes: bytes)
    }

    // MARK: - 解码

    /// 把原始字节解码为数值。规则与 smctemp 保持一致。
    static func decode(type: String, bytes: [UInt8], dataSize: UInt32) -> Double? {
        guard dataSize > 0 else { return nil }
        func be16(_ offset: Int = 0) -> UInt16? {
            guard bytes.count >= offset + 2 else { return nil }
            return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
        }
        func be32(_ offset: Int = 0) -> UInt32? {
            guard bytes.count >= offset + 4 else { return nil }
            return (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) |
                (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
        }

        switch type {
        case "flt ":
            // Apple Silicon 上为小端 float（直接按内存序拷贝）
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) |
                (UInt32(bytes[3]) << 24)
            let value = Float(bitPattern: raw)
            guard value.isFinite else { return nil }
            return Double(value)
        case "ioft":
            // 8 字节 I/O 定点数：低 8 位小数（本应用用作温度时不可靠，直接不用）
            return nil
        case "sp78":
            guard let v = be16() else { return nil }
            return Double(Int16(bitPattern: v)) / 256.0
        case "sp87":
            guard let v = be16() else { return nil }
            return Double(Int16(bitPattern: v)) / 128.0
        case "sp5a":
            guard let v = be16() else { return nil }
            return Double(Int16(bitPattern: v)) / 1024.0
        case "sp69":
            guard let v = be16() else { return nil }
            return Double(Int16(bitPattern: v)) / 512.0
        case "sp96":
            guard let v = be16() else { return nil }
            return Double(Int16(bitPattern: v)) / 64.0
        case "spb4":
            guard let v = be16() else { return nil }
            return Double(Int16(bitPattern: v)) / 16.0
        case "spf0":
            guard let v = be16() else { return nil }
            return Double(Int16(bitPattern: v))
        case "sp1e":
            guard let v = be16() else { return nil }
            return Double(Int16(bitPattern: v)) / 16384.0
        case "sp3c":
            guard let v = be16() else { return nil }
            return Double(Int16(bitPattern: v)) / 4096.0
        case "sp4b":
            guard let v = be16() else { return nil }
            return Double(Int16(bitPattern: v)) / 2048.0
        case "fpe2":
            guard let v = be16() else { return nil }
            return Double(v) / 4.0
        case "fp1f":
            guard let v = be16() else { return nil }
            return Double(v) / 32768.0
        case "fp4c":
            guard let v = be16() else { return nil }
            return Double(v) / 4096.0
        case "fp5b":
            guard let v = be16() else { return nil }
            return Double(v) / 2048.0
        case "fp6a":
            guard let v = be16() else { return nil }
            return Double(v) / 1024.0
        case "fp79":
            guard let v = be16() else { return nil }
            return Double(v) / 512.0
        case "fp88":
            guard let v = be16() else { return nil }
            return Double(v) / 256.0
        case "fpa6":
            guard let v = be16() else { return nil }
            return Double(v) / 64.0
        case "fpc4":
            guard let v = be16() else { return nil }
            return Double(v) / 16.0
        case "si8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(Int8(bitPattern: bytes[0]))
        case "si16":
            guard let v = be16() else { return nil }
            return Double(Int16(bitPattern: v))
        case "si32":
            guard let v = be32() else { return nil }
            return Double(Int32(bitPattern: v))
        case "ui8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        case "ui16":
            guard let v = be16() else { return nil }
            return Double(v)
        case "ui32":
            guard let v = be32() else { return nil }
            return Double(v)
        case "ui64":
            guard bytes.count >= 8 else { return nil }
            var value: UInt64 = 0
            for i in 0..<8 { value = (value << 8) | UInt64(bytes[i]) }
            return Double(value)
        case "pwm ":
            guard let v = be16() else { return nil }
            return Double(v) * 100.0 / 65536.0
        default:
            return nil
        }
    }

    private static func string(fromCChars chars: [CChar]) -> String {
        var bytes: [UInt8] = []
        for c in chars {
            if c == 0 { break }
            bytes.append(UInt8(bitPattern: c))
        }
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }
}

/// SMC 温度/风扇/功率相关键的通用判定工具。
enum SMCKeyClassifier {
    /// 可作为温度值解码的 SMC 数据类型。
    static let temperatureTypes: Set<String> = [
        "flt ", "sp78", "sp87", "sp5a", "sp69", "sp96", "spb4", "spf0",
        "sp1e", "sp3c", "sp4b", "fpe2", "fp1f", "fp4c", "fp5b", "fp6a",
        "fp79", "fp88", "fpa6", "fpc4",
    ]

    /// 可作为数值解码（风扇/功率等）的类型。
    static let numericTypes: Set<String> = temperatureTypes.union([
        "ui8 ", "ui16", "ui32", "ui64", "si8 ", "si16", "si32", "pwm ",
    ])

    static func isTemperatureKey(_ key: String) -> Bool {
        key.hasPrefix("T")
    }
}
