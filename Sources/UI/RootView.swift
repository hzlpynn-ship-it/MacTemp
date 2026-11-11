import SwiftUI
import AppKit

// 主窗口根视图：自定义侧栏（App 标识 + 5 个导航项 + 底部状态）+ 内容区。
// 不使用 NavigationSplitView（hiddenTitleBar 下易出问题）；左上角 78×28 区域留给红绿灯。

// MARK: - 导航项

enum RootTab: String, CaseIterable, Identifiable {
    case dashboard
    case sensors
    case system
    case processes
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "概览"
        case .sensors: return "传感器"
        case .system: return "系统信息"
        case .processes: return "进程"
        case .settings: return "设置"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: return "各部件温度、60 秒趋势、实时负载一目了然"
        case .sensors: return "全部 SMC 温度测点，按部件分类浏览"
        case .system: return "设备、芯片、内存、存储与网络概况"
        case .processes: return "CPU 占用最高的进程，每秒采样"
        case .settings: return "刷新频率、温度单位与菜单栏显示"
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .sensors: return "thermometer.medium"
        case .system: return "desktopcomputer"
        case .processes: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - 根视图

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @State private var selectedTab: RootTab
    @State private var hoveredTab: RootTab?
    @State private var refreshSpin: Double = 0

    /// 可选初始页，方便离屏渲染 / 未来截图工具直接打开指定页面。
    init(initialTab: RootTab = .dashboard) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            contentArea
        }
        .background(AppBackground())
        .frame(minWidth: 1020, minHeight: 700)
        .ignoresSafeArea()
    }

    // MARK: 侧栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 红绿灯预留区（hiddenTitleBar）
            Color.clear
                .frame(height: 38)

            brand
                .padding(.horizontal, 18)
                .padding(.bottom, 24)

            Text("监控面板")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 22)
                .padding(.bottom, 7)

            VStack(spacing: 3) {
                ForEach(RootTab.allCases) { tab in
                    navItem(tab)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 16)

            sidebarStatus
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
        }
        .frame(width: 212)
        .background {
            ZStack {
                SidebarBackground()
                WindowDragArea()
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.hairline)
                .frame(width: 1)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            AppLogoMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("MacTemp")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("温度监控 · v\(AppMetadata.version)")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private func navItem(_ tab: RootTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 18)
                Text(tab.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
                if tab == .sensors, !app.sensors.isEmpty {
                    Text("\(app.sensors.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .opacity(isSelected ? 0.85 : 0.55)
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.62))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                shape.fill(
                    isSelected
                        ? AnyShapeStyle(Theme.accentGradientHorizontal)
                        : AnyShapeStyle(isHovered ? Theme.hoverFill : Color.clear)
                )
            )
            .overlay {
                if isSelected {
                    shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                }
            }
            .shadow(color: isSelected ? Theme.accentDeep.opacity(0.35) : Color.clear, radius: 8, y: 3)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredTab = tab
            } else if hoveredTab == tab {
                hoveredTab = nil
            }
        }
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }

    private var sidebarStatus: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let statusColor: Color = app.scanError != nil && !app.isScanning
            ? Theme.tempRed
            : (app.isScanning ? Theme.tempYellow : Theme.tempGreen)
        let statusText: String = app.scanError != nil && !app.isScanning
            ? "传感器异常"
            : (app.isScanning ? "正在扫描…" : "实时监控中")
        let availableCount = app.sensors.filter { $0.isAvailable }.count

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusDot(color: statusColor, size: 6.5)
                Text(statusText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                Text("最近更新")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(Fmt.clock(app.lastUpdated))
                    .font(Theme.numberFont(9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text("\(availableCount) / \(app.sensors.count) 个传感器在线")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.track.opacity(0.4)))
        .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: 内容区

    private var contentArea: some View {
        VStack(spacing: 0) {
            contentHeader

            if app.isScanning {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(height: 2.5)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 2)
            }

            if let error = app.scanError, !app.isScanning {
                ErrorBanner(message: error, onRetry: { app.rescanSensors() })
                    .padding(.horizontal, 26)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
            }

            ScrollView {
                pageContent
                    .frame(maxWidth: 1100, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.top, 2)
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTab.title)
                    .font(Theme.pageTitleFont)
                    .foregroundStyle(.primary)
                Text(selectedTab.subtitle)
                    .font(Theme.pageSubtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            headerStatus
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .background(alignment: .top) {
            WindowDragArea()
                .frame(height: 34)
        }
    }

    private var headerStatus: some View {
        HStack(spacing: 9) {
            StatusPill(
                text: "热压力 \(app.thermalPressure.title)",
                color: Theme.thermalColor(app.thermalPressure)
            )

            powerPill

            unitToggle

            GlassIconButton(
                symbol: "arrow.clockwise",
                helpText: "立即刷新（⌘R）",
                tint: Theme.accent
            ) {
                refreshSpin += 360
                app.refreshNow()
            }
            .rotationEffect(.degrees(refreshSpin))
            .animation(.easeInOut(duration: 0.5), value: refreshSpin)
        }
    }

    private var powerPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("功耗")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)
            Text(Fmt.watts(app.powerWatts))
                .font(Theme.numberFont(11, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.track.opacity(0.45)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var unitToggle: some View {
        HStack(spacing: 0) {
            ForEach(TemperatureUnit.allCases) { unit in
                let isSelected = app.settings.unit == unit
                Button {
                    app.settings.unit = unit
                } label: {
                    Text(unit.shortLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            if isSelected {
                                Capsule().fill(Theme.accentGradientHorizontal)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.track.opacity(0.45)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    // MARK: 页面分发

    @ViewBuilder
    private var pageContent: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView()
        case .sensors:
            SensorsView()
        case .system:
            SystemInfoView()
        case .processes:
            ProcessesView()
        case .settings:
            SettingsView(embedded: true)
        }
    }
}

// MARK: - 背景

/// 窗口背景：深色底 + 极淡青/蓝径向光晕（静态绘制，不参与逐帧重绘）。
struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [Theme.glowCyan, Color.clear],
                center: UnitPoint(x: 0.95, y: 0.0),
                startRadius: 20,
                endRadius: 620
            )
            RadialGradient(
                colors: [Theme.glowBlue, Color.clear],
                center: UnitPoint(x: 0.05, y: 1.05),
                startRadius: 20,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

/// 侧栏背景：材质 + 深色叠加，让侧栏比内容区更沉。
struct SidebarBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Theme.sidebarTint)
        }
    }
}

/// App 图标（自绘渐变圆角方块 + 温度计符号），各处复用。
struct AppLogoMark: View {
    var size: CGFloat = 34

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
        ZStack {
            shape.fill(Theme.accentGradient)
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.28), Color.clear],
                    startPoint: .topLeading,
                    endPoint: .center
                )
            )
            Image(systemName: "thermometer.medium")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.22), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(Color.white.opacity(0.32), lineWidth: 1))
        .shadow(color: Theme.accentDeep.opacity(0.45), radius: 8, y: 3)
    }
}
