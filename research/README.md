# research/ — M4 MacBook Air 温度传感器实测

本目录记录了 MacTemp 传感器目录的实测校准过程（M4 MacBook Air，4P+6E / 10 核 GPU，
macOS 15.6.1）。结论与证据表见 [`../docs/SENSOR_MAP.md`](../docs/SENSOR_MAP.md)，
生成的应用侧目录在 `../Sources/SMC/SensorCatalog.swift`。

## 产物

- `sensor_catalog_m4.json` — 50 个独立传感器的目录（key / type / category / displayName /
  confidence / typicalIdle / typicalLoad / evidence），应用侧白名单即由此而来
- 8 个只读测量工具 + 3 个脚本（见下表）

## 复现（约 5 分钟负载，无 sudo、不写 SMC）

```bash
./build_tools.sh                  # 编译 C/Swift 工具到 /tmp/mt_bin（需要 CLT）
./run_experiment.sh               # baseline / P核 / E核 / GPU / 内存 / NAND 六阶段采样
python3 analyze_experiment.py     # 依赖 pandas，生成阶段中位值 / ΔT / 同源分组
python3 build_catalog.py          # 生成 sensor_catalog_m4.json
```

`run_experiment.sh` 可选使用外部的 [smctemp](https://github.com/narugit/smctemp) 做交叉验证：

```bash
SMCTEMP=/path/to/smctemp ./run_experiment.sh
```

## 工具清单

| 文件 | 说明 |
|---|---|
| `smc_mt.{h,c}` | 只读 AppleSMC 访问层（**flt = 小端 float**，其余定点类型大端） |
| `mt_sampler.c` | 枚举全部 SMC 键，筛选 T* 温度键并周期采样 |
| `cpu_load.c` | 用 pthread QoS 分别制造 P 核 / E 核负载 |
| `cpu_watch.c` | 通过 host_processor_info 记录每逻辑核占用率 |
| `metal_load.swift` | 运行时编译 MSL kernel 制造 GPU 负载 |
| `mem_load.c` | 匿名内存跨步读写，制造内存带宽负载 |
| `hid_sensors.c` | 读取 IOHID 温度传感器（PMU tdie / NAND / 电池）作为独立 ground truth |
| `proc_top.c` / `proc_watch.c` | 进程 CPU 采样（可替代被沙盒限制的 ps/top） |
| `analyze_experiment.py` | 阶段中位值、ΔT、同源分组分析（需要 pandas） |
| `build_catalog.py` | 结合实测与人工判定生成传感器目录 JSON |

## 说明

- 所有工具只读硬件 / 自建负载，不使用 sudo、不写 SMC、不修改系统设置
- 实验环境无法制造真正空载窗口，结论以相对温差为主，详见 SENSOR_MAP 的不确定性章节
- 这些脚本不参与 App 构建，仅在需要新增机型/传感器时使用

## 免责声明

这些工具仅用于本机硬件传感器的只读研究：其中 `hid_sensors.c` 使用了未公开文档化的 IOHID 接口，
负载工具会短暂占满 CPU/GPU。它们不参与 MacTemp App 构建，也不应放入日常使用的脚本中。
