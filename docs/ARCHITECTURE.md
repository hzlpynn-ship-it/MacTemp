# MacTemp 架构说明

本文档说明 MacTemp 的模块划分、数据流与关键实现细节，方便二次开发。

## 1. 总体结构

```
Sources/
├── App/            应用入口、AppState（全局状态与采样调度）、菜单栏、自测、离屏截图
├── Models/         Models.swift：数据模型契约（传感器、分组、系统信息、实时负载、设置）
├── SMC/            AppleSMC 访问层与传感器目录
│   ├── smc_bridge.{h,c}   C 语言 IOKit 桥接（打开 AppleSMC、枚举键、读字节）
│   ├── SMCDriver.swift    Swift 封装 + SMC 数据类型解码
│   ├── SensorCatalog.swift 机型 -> 传感器白名单（键名/中文名/分类/角色）
│   └── SMCMonitor.swift   扫描、周期采样、按部件聚合、风扇与功耗读取
├── Collectors/     系统信息 / 实时负载 / 电池 / 进程采集（纯系统 API）
└── UI/             SwiftUI 界面：主题、组件、5 个页面、菜单栏面板
```

构建产物为 `dist/MacTemp.app`，不进入 git；`scripts/build.sh` 负责编译 + 组装 Bundle + ad-hoc 签名。

## 2. 采样与线程模型

- `AppState` 持有 `SMCMonitor`、`SystemInfoCollector`、`LiveStatsCollector`，使用一个串行
  `DispatchQueue` 做后台采样；结果统一回到主线程更新 `@Published` 属性。
- 默认 1 秒采样一次：读取约 50 个白名单传感器的 SMC 值（每个键一次 IOKit IPC），
  同时采集 CPU/内存/网络/进程等实时负载；静态系统信息每 30 秒刷新一次。
- 历史曲线只保留内存中的最近 60 个采样点，用于界面 sparkline；不做持久化。
- 界面发现采样出错（例如 SMC 不可用）时显示错误条，不崩溃、不伪造数据。

## 3. AppleSMC 访问层

AppleSMC 通过 IOKit 用户客户端访问（`IOServiceOpen("AppleSMC")`），使用 selector 2 上的经典命令：

| 命令 | 值 | 用途 |
|---|---|---|
| `READ_BYTES` | 5 | 读取键的原始字节 |
| `READ_INDEX` | 8 | 按序号枚举键名 |
| `READ_KEYINFO` | 9 | 查询键的数据类型与长度 |

`SMCKeyData` 结构体布局固定为 80 字节。启动扫描时：

1. 读 `#KEY` 得到键总数（本机 M4 MacBook Air 为 2148）；
2. 逐序号枚举键名，只对 `T*`（温度）、`F*`（风扇）、`PSTR`（整机功耗）等候选查询 `READ_KEYINFO`；
3. 按数据类型白名单（`flt` / `sp78` / `fpe2` / ...）筛选可解码的温度候选；
4. 用 `SensorCatalog` 白名单匹配出真正独立的传感器，缓存每个键的 `dataSize` 与类型；
5. 周期采样时只读这些键，每个键仅一次 IPC。

**字节序（实测结论，容易踩坑）**：Apple Silicon 上 `flt ` 类型为**小端 IEEE-754 浮点**；
`sp78`/`fpe2` 等带定点前缀的类型为**大端**；`ioft` 类型语义未确认，直接排除。

## 4. 传感器目录与白名单

`SensorCatalog` 以机型（`hw.model` + `machdep.cpu.brand_string` + `hw.perflevel*`）选择目录：

- **M4 基础款**（本机）使用实测校准后的 50 个传感器白名单。SMC 中同一物理传感器常以多个
  键出现（恒定 7.1°C / 6.7°C 温差或完全同值），若全部展示会出现「同一颗核心 3 个几乎一样的温度」；
  白名单同时排除 `Ta0*`/`Tz*` 等占位键与无法解码的 `ioft` 键。
- 其他 M 系列芯片回退到「键表 + 前缀兜底」的通用目录，尽量展示可读到的传感器。

每类部件的主指标（如 CPU 热点 `TCMz`、GPU `Tg0D`、内存 `Tm0B`、NAND `TH0x`）与有效温度范围
定义在 `SensorCatalog` 和 `SMCMonitor` 中，依据见 `docs/SENSOR_MAP.md`。

## 5. 系统信息与实时负载

全部使用公开/半公开系统 API，不调用外部命令、不需要 root：

- CPU：`host_processor_info` 差分；内存：`host_statistics64`；负载：`getloadavg`
- 网络：`getifaddrs` + `if_data` 计数差分
- 进程：`libproc` 的 `proc_listpids` / `proc_pidinfo` / `proc_pid_rusage` 思路（实现中避开
  了本机 Swift 调用 `proc_pid_rusage` 会崩溃的路径，改用 `PROC_PIDTASKINFO` 的累计 CPU 时间差分）
- 电池：`IOPSCopyPowerSourcesInfo` + `AppleSmartBattery`（注意 `Temperature` 字段单位是 0.1K）
- 磁盘 / GPU 核数 / 显示器：`FileManager`、`IORegistry`、`CoreGraphics`

## 6. 界面

- SwiftUI，部署目标 macOS 14；自定义侧栏（非 `NavigationSplitView`），窗口使用 `.hiddenTitleBar`
- `AppState` 通过 `@EnvironmentObject` 注入；五个页面只读展示，设置写回 `AppState.settings`
- `MenuBarExtra(.window)` 提供常驻面板，显示 4 个主部件温度 + CPU 趋势 + 状态信息
- 离屏渲染：`MacTemp --render <dir>` 用 `NSHostingView` 渲染全部页面，便于截图与视觉回归
- 命令行自测：`MacTemp --selftest` 输出 SMC 扫描、分组、系统信息、实时负载摘要

## 7. 构建与发布

```bash
bash scripts/build.sh           # 编译 + 生成 dist/MacTemp.app
bash scripts/package_release.sh # 生成 dist/MacTemp-1.0.0.zip（Release 附件）
```

只依赖 Command Line Tools（`swiftc` + `clang` + macOS SDK），不需要完整 Xcode / SwiftPM。
App 使用 ad-hoc 签名，首次打开需在系统设置中允许；不适合 Mac App Store。

## 8. 新增机型 / 传感器

1. 运行 `research/build_tools.sh` 与 `research/run_experiment.sh` 采集本机数据；
2. 用 `research/analyze_experiment.py` 分析同源分组与各阶段温升；
3. 更新 `research/sensor_catalog_m4.json` 与 `docs/SENSOR_MAP.md`；
4. 在 `SensorCatalog.swift` 中新增/调整对应机型的白名单与主指标；
5. 用 `--selftest` 与 `--render` 验证，并对比 `smctemp` 等外部工具做交叉检查。
