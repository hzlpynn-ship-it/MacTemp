# 第三方声明与参考

本仓库不包含任何第三方源代码，构建时也不依赖第三方库（仅使用 macOS 系统框架）。
以下项目/资料对「AppleSMC 协议理解」与「传感器键名语义」提供了参考，特此致谢：

| 项目 / 资料 | 许可证 | 用途 |
|---|---|---|
| [Stats](https://github.com/exelban/stats) | MIT | Apple Silicon 传感器键名与分组的社区映射参考 |
| [smctemp](https://github.com/narugit/smctemp) | GPL-2.0 | AppleSMC 读取协议与数据类型解码规则的外部参考，用于交叉验证 |
| AppleSMC 协议早期公开实现（devnull / smcFanControl 系列） | GPL | IOKit AppleSMC 用户客户端协议的历史参考 |
| [MacMonitor SENSORS.md](https://github.com/ryyansafar/MacMonitor) | 未声明 | 传感器语义的社区整理资料（仅作线索，均经过本机实测验证） |

说明：

- 本项目的 SMC 访问层（`Sources/SMC/smc_bridge.c`）与全部应用代码均为独立实现，
  未复制、链接或再分发上述项目的代码；`vendor/`、`research/` 中也不包含第三方源码副本。
- 上述项目仅作为外部参考链接，构建 MacTemp 不需要下载它们。
- Apple、macOS、Mac、Apple Silicon 是 Apple Inc. 的商标；AIDA64 是其各自权利人的商标。
  本项目与 Apple、AIDA64 官方均无关联。
- AppleSMC 用户客户端属于 Apple 未公开文档化的 IOKit 接口。本项目仅以只读方式访问，
  用于本机硬件监控；这类接口不适合 Mac App Store 分发，可能随 macOS 版本变化。
