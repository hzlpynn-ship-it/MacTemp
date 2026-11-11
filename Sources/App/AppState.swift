import Foundation
import AppKit

// MacTemp 全局状态：SMC 传感器 + 系统信息 + 实时负载 + 设置 + 历史曲线。
// 采样在后台串行队列执行，UI 更新统一切回主线程。

final class AppState: ObservableObject {
    // MARK: - 对外发布的状态

    @Published private(set) var systemInfo: SystemInfo = .placeholder
    @Published private(set) var liveStats: LiveStats = LiveStats()
    @Published private(set) var groups: [TemperatureGroup] = []
    @Published private(set) var sensors: [TemperatureSensor] = []
    @Published private(set) var fans: [FanReading] = []
    @Published private(set) var thermalPressure: ThermalPressure = .nominal
    @Published private(set) var powerWatts: Double?
    @Published private(set) var lastUpdated: Date = .distantPast
    @Published private(set) var isScanning = true
    @Published private(set) var scanError: String?
    @Published private(set) var history: [String: [Double]] = [:]

    @Published var settings: AppSettings = AppSettings() {
        didSet { settingsDidChange(from: oldValue) }
    }

    // MARK: - 内部

    private let monitor = SMCMonitor()
    private let systemCollector = SystemInfoCollector()
    private let liveCollector = LiveStatsCollector()
    private let samplingQueue = DispatchQueue(label: "com.mactemp.sampling", qos: .utility)

    private var timer: Timer?
    private var samplingInFlight = false
    private var tickCount = 0
    private var monitorStarted = false
    private var lastStaticRefresh = Date.distantPast
    private let historyCapacity = 60
    private static let settingsKey = "MacTemp.settings.v1"

    // MARK: - 生命周期

    init() {
        self.settings = Self.loadSettings()
        startMonitoring()
    }

    deinit {
        timer?.invalidate()
    }

    /// 首次启动：后台扫描 SMC + 采集静态信息，然后开始周期采样。
    func startMonitoring() {
        samplingQueue.async { [weak self] in
            guard let self else { return }
            let started = self.monitor.start()
            let info = self.systemCollector.collect()
            DispatchQueue.main.async {
                self.monitorStarted = started
                self.systemInfo = info
                self.isScanning = false
                if !started {
                    self.scanError = self.monitor.lastError ?? "传感器初始化失败"
                }
                self.scheduleTimer()
                self.performSample()
            }
        }
    }

    /// 立即刷新一次（不阻塞 UI）。
    func refreshNow() {
        performSample()
    }

    /// 重新扫描传感器（设置页可调用）。
    func rescanSensors() {
        isScanning = true
        scanError = nil
        samplingQueue.async { [weak self] in
            guard let self else { return }
            let started = self.monitor.start()
            DispatchQueue.main.async {
                self.monitorStarted = started
                self.isScanning = false
                if !started {
                    self.scanError = self.monitor.lastError ?? "没有检测到温度传感器"
                }
                self.performSample()
            }
        }
    }

    // MARK: - 采样

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = max(0.5, settings.refreshInterval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.performSample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func performSample() {
        guard monitorStarted, !samplingInFlight else { return }
        samplingInFlight = true
        let shouldRefreshStatic = Date().timeIntervalSince(lastStaticRefresh) > 30
        samplingQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.monitor.sample()
            let live = self.liveCollector.sample()
            var staticInfo: SystemInfo?
            if shouldRefreshStatic {
                staticInfo = self.systemCollector.collect()
            }
            DispatchQueue.main.async {
                if let staticInfo {
                    self.systemInfo = staticInfo
                    self.lastStaticRefresh = Date()
                }
                self.apply(snapshot: snapshot, live: live)
                self.samplingInFlight = false
            }
        }
    }

    private func apply(snapshot: SMCSnapshot, live: LiveStats) {
        sensors = snapshot.sensors
        groups = snapshot.groups
        fans = snapshot.fans
        powerWatts = snapshot.powerWatts
        liveStats = live
        lastUpdated = Date()
        thermalPressure = ThermalPressure(ProcessInfo.processInfo.thermalState)
        if snapshot.validSensorCount > 0, scanError != nil, monitorStarted {
            scanError = nil
        }
        appendHistory(groups: snapshot.groups)
        tickCount += 1
    }

    private func appendHistory(groups: [TemperatureGroup]) {
        guard settings.recordHistory else {
            if !history.isEmpty { history = [:] }
            return
        }
        for group in groups {
            guard let value = group.primary else { continue }
            var values = history[group.id] ?? []
            values.append(value)
            if values.count > historyCapacity {
                values.removeFirst(values.count - historyCapacity)
            }
            history[group.id] = values
        }
    }

    // MARK: - 设置

    private func settingsDidChange(from oldValue: AppSettings) {
        saveSettings()
        if oldValue.refreshInterval != settings.refreshInterval {
            scheduleTimer()
        }
    }

    private static func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: Self.settingsKey)
    }

    // MARK: - UI 辅助接口

    var primaryGroups: [TemperatureGroup] {
        groups.filter { $0.isPrimaryCard }
    }

    var cpuCoreSensors: [TemperatureSensor] {
        sensors.filter {
            $0.name.hasPrefix("CPU 性能核心") || $0.name.hasPrefix("CPU 能效核心")
        }
    }

    var maxTemperature: Double? {
        sensors.compactMap(\.celsius).max()
    }

    func historyValues(for id: String) -> [Double] {
        history[id] ?? []
    }

    func sensors(in category: SensorCategory?) -> [TemperatureSensor] {
        guard let category else { return sensors }
        return sensors.filter { $0.category == category }
    }

    var refreshInterval: Double {
        max(0.5, settings.refreshInterval)
    }

    /// 菜单栏标题，例如 "CPU 62°"。
    var menuBarLabel: String {
        let unit = settings.unit
        func temp(_ value: Double?) -> String? {
            guard let value else { return nil }
            return "\(Int(unit.convert(fromCelsius: value).rounded()))°"
        }
        switch settings.menuBarMetric {
        case .cpu:
            return temp(groups.first(where: { $0.id == SensorCategory.cpu.rawValue })?.primary).map { "CPU \($0)" } ?? "--"
        case .gpu:
            return temp(groups.first(where: { $0.id == SensorCategory.gpu.rawValue })?.primary).map { "GPU \($0)" } ?? "--"
        case .highest:
            return temp(maxTemperature).map { "\($0)" } ?? "--"
        case .power:
            guard let powerWatts else { return "--" }
            return "\(Int(powerWatts.rounded()))W"
        case .fan:
            if let rpm = fans.first?.rpm {
                return "\(Int(rpm.rounded())) RPM"
            }
            return "无风扇"
        }
    }

    /// 导出传感器列表为 CSV 文本。
    func sensorCSV() -> String {
        var lines = ["名称,分类,SMC键,类型,温度(°C),状态"]
        for sensor in sensors {
            let category = sensor.category.title.replacingOccurrences(of: ",", with: " ")
            let name = sensor.name.replacingOccurrences(of: ",", with: " ")
            let value: String
            let state: String
            if let celsius = sensor.celsius {
                value = String(format: "%.2f", celsius)
                state = "可用"
            } else {
                value = ""
                state = "不可用"
            }
            lines.append("\(name),\(category),\(sensor.key),\(sensor.typeName),\(value),\(state)")
        }
        return lines.joined(separator: "\n")
    }
}
