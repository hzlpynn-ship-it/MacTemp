#!/usr/bin/env python3
# build_catalog.py — 由实测数据表生成 research/sensor_catalog_m4.json
# MacTemp 传感器研究工具
#
# 数据来源: /tmp/mt_exp/{sensors.csv,report_master.csv}（2026-11-11 08:52-08:57 实验）
# 本脚本把"人工判定的命名/分类/置信度"与"实测 idle/load 数值"合成最终 JSON。
# 实测数值在此内嵌（来自 report_master.csv），保证在 /tmp 数据丢失后仍可复现 JSON。
import json
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sensor_catalog_m4.json")

# ---- 实测中位值（来自 /tmp/mt_exp/report_master.csv，08:52-08:57 实验）----
# key: (idle=baseline中位, load=max(p,e,gpu)中位, 实测min, 实测max)
M = {
    # CPU 核心 / 聚合
    "TCMz": (91.5, 95.5, 89.2, 96.4),
    "TCMb": (86.8, 89.3, 83.8, 90.0),
    "Tp01": (82.2, 87.2, 79.5, 87.6),
    "Tp05": (81.1, 86.2, 78.6, 86.8),
    "Tp09": (83.8, 87.7, 81.4, 88.2),
    "Tp0D": (82.3, 85.3, 80.1, 86.4),
    "Te05": (84.0, 86.3, 81.4, 86.6),
    "Te0S": (83.4, 84.9, 80.3, 85.2),
    "Te09": (83.9, 86.2, 81.2, 86.6),
    "Te0H": (82.3, 84.0, 79.4, 84.4),
    "Te0V": (87.8, 90.4, 85.5, 90.6),
    "Te0X": (88.7, 90.3, 85.9, 90.8),
    # GPU
    "Tg0C": (80.6, 79.7, 74.6, 84.3),
    "Tg0D": (85.2, 84.3, 79.2, 86.5),
    "Tg0H": (86.5, 85.8, 0.1, 88.1),
    "Tg0L": (86.7, 86.3, 80.7, 88.2),
    "Tg0P": (84.8, 84.2, 78.8, 86.2),
    "Tg0V": (83.2, 84.5, 0.1, 85.1),
    "Tg0Y": (85.6, 86.4, 0.1, 87.3),
    "Tg0e": (85.7, 85.9, 80.7, 87.0),
    "Tg0k": (86.8, 86.8, 81.2, 88.0),
    "Tg0n": (86.4, 85.8, 0.1, 88.1),
    # 内存 / 存储 / 电池 / 无线 / 显示 / 机身
    "Tm0B": (58.0, 58.1, 56.7, 58.5),
    "TH0x": (55.1, 55.1, 54.1, 55.6),
    "TB0T": (29.3, 30.0, 29.2, 30.3),
    "TB1T": (28.2, 29.0, 28.1, 29.3),
    "TB2T": (29.3, 30.0, 29.2, 30.3),
    "TW0P": (58.1, 57.8, 56.5, 58.3),
    "TDBP": (34.3, 34.6, 34.2, 34.8),
    "TDeL": (33.7, 34.1, 33.6, 34.5),
    "TAOL": (25.0, 25.7, 25.0, 26.0),
    # 封装 / 供电 / 其他
    "TPMP": (58.8, 59.3, 57.6, 59.9),
    "TPSP": (58.7, 58.7, 57.2, 59.3),
    "TSCD": (64.9, 64.6, 62.7, 65.5),
    "TPD0": (66.4, 69.6, 64.0, 70.4),
    "TPD5": (70.0, 73.2, 67.0, 74.0),
    "TPDX": (70.5, 73.2, 67.7, 73.8),
    "TVM0": (80.2, 78.3, 76.8, 80.8),
    "TVMh": (80.2, 78.3, 76.8, 80.8),
    "TVh0": (83.6, 81.8, 80.3, 84.1),
    "TVMm": (82.2, 79.4, 78.4, 83.4),
    "TVm0": (77.4, 75.4, 73.5, 78.0),
    "TVm1": (82.2, 79.4, 78.4, 83.4),
    "TVV0": (70.4, 73.2, 67.7, 73.8),
    "TVS0": (44.1, 44.2, 43.7, 44.6),
    "TVS1": (45.1, 45.2, 44.6, 45.6),
    "TCHP": (51.6, 51.9, 50.6, 52.9),
    "TMVR": (54.7, 54.9, 53.3, 55.3),
    "TIOP": (44.9, 45.0, 44.6, 45.5),
    "TRD0": (57.9, 58.0, 56.3, 58.5),
    "TRD2": (56.8, 56.8, 55.2, 57.5),
    "T5SP": (48.1, 48.2, 47.6, 48.4),
    "Ts0P": (25.9, 27.0, 25.9, 27.1),
    "Ts1P": (25.1, 26.1, 24.9, 26.3),
}

# (key, type, category, displayName, confidence, evidence)
E = [
    # ================= CPU =================
    ("TCMz", "flt ", "cpu", "CPU 热点（最高核心测点）", "high",
     "全实验 89.2–96.4°C，为 CPU 家族最高；与 Tp1C/Tp3T 差值恒 0.0°C（同传感器别名）；P 核负载 +2.6°C、P 核空闲的 MEM 阶段 -4.0°C，响应最强 → 适合作 CPU 主指标/热点"),
    ("TCMb", "flt ", "cpu", "CPU 芯片平均（封装测点）", "medium",
     "与 TVD0 差值恒 0.01°C（别名）；全实验 83.8–90.0°C，居 CPU 家族中位；+0.8/+1.2°C 随 P 负载上升，MEM 阶段 -3.3°C；推断为 CPU die 平均口径，未见公开键表佐证"),
    ("Tp01", "flt ", "cpu", "CPU 性能核心 1", "medium",
     "Stats M4 键表第一个 P 核；与 Tp00 恒差 7.1°C（同传感器双校准），与 Tp0Y 同值（别名）；P 核负载 +2.2°C，MEM（P 核空闲）-5.3°C；4 个 P 核之一"),
    ("Tp05", "flt ", "cpu", "CPU 性能核心 2", "medium",
     "Stats M4 'performance core 2'；与 Tp04 恒差 7.1°C；P 核负载 +2.0°C，MEM -4.6°C；4 个 P 核之一"),
    ("Tp09", "flt ", "cpu", "CPU 性能核心 3", "medium",
     "Stats M4 'performance core 3'；与 Tp08 恒差 7.1°C；P 核负载 +1.9°C，MEM -4.5°C；4 个 P 核之一"),
    ("Tp0D", "flt ", "cpu", "CPU 性能核心 4", "medium",
     "Stats M4 'performance core 4'；与 Tp0C 恒差 7.1°C；P 核负载 +1.7°C，MEM -3.5°C；4 个 P 核之一"),
    ("Te05", "flt ", "cpu", "CPU 能效核心 1", "medium",
     "Stats M4 'efficiency core 1'；与 Te04 恒差 6.7°C；全体 81.4–86.6°C；E 家族对 P 核负载敏感度仅为 Tp 家族 ~43%（符合 E 簇已被后台负载压满）；6 个 E 核之一"),
    ("Te0S", "flt ", "cpu", "CPU 能效核心 2", "medium",
     "Stats M4 'efficiency core 2'；与 Te0R 恒差 6.7°C；E 家族响应 0.6°C（P 负载）；6 个 E 核之一，序号按 Stats 原顺序"),
    ("Te09", "flt ", "cpu", "CPU 能效核心 3", "medium",
     "Stats M4 'efficiency core 3'；与 Te08 恒差 6.7°C；E 家族响应 1.2°C；6 个 E 核之一"),
    ("Te0H", "flt ", "cpu", "CPU 能效核心 4", "medium",
     "Stats M4 'efficiency core 4'；与 Te0G 恒差 6.7°C；E 家族响应 0.8°C；6 个 E 核之一"),
    ("Te0V", "flt ", "cpu", "CPU 能效核心 5", "low",
     "Stats M4 只列出 4 个 E 核；本机 M4 为 4P+6E，第 5、6 核按 Te 键块顺序 + 实测独立信号（Te0V 与 Te06 同值、Te0X 与 Te0T 同值）挑选，序号属推断"),
    ("Te0X", "flt ", "cpu", "CPU 能效核心 6", "low",
     "同上：M4 基础款 6 个 E 核的扩展推断，Te0X 与 Te0T 为同一传感器（恒差），未见外部键表可对照，序号可能调换"),
    # ================= GPU =================
    ("Tg0C", "flt ", "gpu", "GPU 核心 1", "low",
     "GPU 家族 18 键可按恒定温差归为 10 个独立信号（=M4 10 核 GPU）；序号按 key 顺序推断，未与物理核编号对照；实测 74.6–84.3°C"),
    ("Tg0D", "flt ", "gpu", "GPU 核心 2", "medium",
     "smctemp -g（M4 口径=均值(Tg0D,Tg0P,Tg0X,Tg0j)）在 GPU 阶段得 83.2°C，本组四键均值 83.1°C，交叉验证一致；本键全程 79.2–86.5°C 无毛刺，适合作为 GPU 主指标"),
    ("Tg0H", "flt ", "gpu", "GPU 核心 3", "low",
     "Stats M4 'GPU 2'；与 Tg0G 恒差 4.6°C；GPU 阶段 +1.35°C；偶发 0.1°C 毛刺需过滤"),
    ("Tg0L", "flt ", "gpu", "GPU 核心 4", "low",
     "Stats M4 GPU 家族键；与 Tg0K 恒差 4.6°C；GPU 阶段 +1.49°C"),
    ("Tg0P", "flt ", "gpu", "GPU 核心 5", "low",
     "Stats M4 GPU 家族键；与 Tg0O 恒差 4.6°C；GPU 阶段 +1.23°C"),
    ("Tg0V", "flt ", "gpu", "GPU 核心 6", "low",
     "与 Tg0U 恒差 4.6°C；GPU 阶段 +1.70°C；偶发 0.1°C 毛刺"),
    ("Tg0Y", "flt ", "gpu", "GPU 核心 7", "low",
     "与 Tg0X 恒差 4.6°C；GPU 阶段 +1.99°C（GPU 家族最大）；偶发 0.1°C 毛刺"),
    ("Tg0e", "flt ", "gpu", "GPU 核心 8", "low",
     "与 Tg0d 恒差 4.6°C；GPU 阶段 +1.72°C"),
    ("Tg0k", "flt ", "gpu", "GPU 核心 9", "low",
     "与 Tg0j 恒差 4.6°C；GPU 阶段 +1.66°C；实测中位最高（86.4°C）"),
    ("Tg0n", "flt ", "gpu", "GPU 核心 10", "low",
     "与 Tg0m 恒差 4.6°C；GPU 阶段 +1.05°C；偶发 0.1°C 毛刺"),
    # ================= 内存 =================
    ("Tm0B", "flt ", "memory", "内存温度（LPDDR5X）", "medium",
     "Stats M4 有 Tm0p/Tm1p/Tm2p 三个 'Memory Proximity' 键，本机只有 Tm0B；实测 56.7–58.5°C、对 CPU/GPU/内存阶段几乎不敏感（±0.2°C），符合封装内内存慢热特征"),
    # ================= 存储 =================
    ("TH0x", "flt ", "storage", "NAND 闪存", "high",
     "Stats 键表 TH0x=NAND；与 HID 传感器 'NAND CH0 temp'（52.0°C，整数量化）同刻对照差 1.9°C；与 TH0T 恒等（别名）；实测 54.1–55.6°C，1GB 写入后未明显抬升（0.9s 完成，NAND 热容大）"),
    # ================= 电池 =================
    ("TB0T", "flt ", "battery", "电池 电芯 1", "high",
     "与 HID 'gas gauge battery' 同刻对照完全一致（31.3/30.2/31.3 vs 31.3/30.2/31.3）；IOKit AppleSmartBattery 的 Temperature 为 0.1K 单位（3023→29.08°C）与本组 29–30°C 吻合；实测 29.2–30.3°C"),
    ("TB1T", "flt ", "battery", "电池 电芯 2", "high",
     "同上（HID gas gauge battery 第二/第三路）；与 TB0T 恒差 1.1°C"),
    ("TB2T", "flt ", "battery", "电池 电芯 3", "high",
     "与 TB0T 恒等（别名）；HID 对照一致"),
    # ================= 无线 =================
    ("TW0P", "flt ", "wireless", "Wi-Fi 模块", "high",
     "Stats 键表 TW0P=Airport；实测 56.5–58.3°C，负载不敏感（Wi-Fi 有其他电源域）；与 Wi-Fi 常开状态一致"),
    # ================= 显示 =================
    ("TDBP", "flt ", "display", "显示屏 背光/面板 A", "medium",
     "实测 34.2–34.8°C，随环境缓慢漂移；键名与 TDeL 成对，项目早期探测判定为屏幕相关；无公开键表佐证"),
    ("TDeL", "flt ", "display", "显示屏 面板 B", "medium",
     "实测 33.6–34.5°C，与 TDBP 恒差 0.6°C；同 TDBP 的判据"),
    # ================= 机身 =================
    ("TAOL", "flt ", "enclosure", "机身 / 环境温度", "medium",
     "实测 25.0–26.0°C，全程几乎恒定、与电池/机身传感器同步（与 TB0T/TB1T/TB2T、Ts0P、TVA0 差值恒定）→ 典型的机身/环境慢变量；注意 Ta0* 多为 0/5 占位键，不要用"),
    # ================= 封装 =================
    ("TPMP", "flt ", "package", "SoC 封装 / PMU 测点 A", "low",
     "实测 57.6–59.9°C，随 CPU 功率轻微变化（+0.2°C）；键名 MP 疑为 Memory/PMU Proximity，无公开键表佐证"),
    ("TPSP", "flt ", "package", "SoC 封装 / PMU 测点 B", "low",
     "实测 57.2–59.3°C，比 TPMP 低 ~0.5°C、同步漂移；推断为封装另一测点"),
    ("TSCD", "flt ", "package", "SoC 芯片测点（SCD）", "low",
     "实测 62.7–65.5°C，与 GPU 阶段 +0.4°C；键名含义未确认，疑为 SoC die 类测点"),
    ("TPD0", "flt ", "package", "SoC 封装测点 TPD0", "low",
     "TPD0..TPDF/TPDX 共 17 个 64–70°C 测点，与 HID 'PMU tdie1..14'（62–70°C）量级相符；TPD5/TPDX 在 GPU 阶段 +2.9°C（供电域发热）；具体含义未确认"),
    ("TPDX", "flt ", "package", "SoC 封装测点 TPDX", "low",
     "与 TPD5、TVV0 恒等（同一传感器 3 个别名）；GPU 阶段 +2.9°C，疑为 GPU 供电域附近 PMU die 测点"),
    # ================= 供电 VRM =================
    ("TVV0", "flt ", "vrm", "供电域温度（GPU 侧）", "low",
     "与 TPD5/TPDX 同值别名；GPU 阶段 +2.9°C 为全家族最大 → 判断为 GPU 供电域测点"),
    ("TVM0", "flt ", "vrm", "供电域温度（最大 A）", "low",
     "与 TVMh/TVh1/TVmS 恒等；~79°C，GPU 阶段 -0.7°C（与 CPU 侧耦合更强）；TV 家族疑为 voltage-domain 温度，无公开键表佐证"),
    ("TVh0", "flt ", "vrm", "供电域温度（高侧）", "low",
     "与 TVM0 家族恒差 3.4°C；~82.8°C"),
    ("TVMm", "flt", "vrm", "供电域温度（最大 B）", "low", "与 TVm1 恒等；~80.9°C") if False else ("TVMm", "flt ", "vrm", "供电域温度（最大 B）", "low", "与 TVm1 恒等；~80.9°C"),
    ("TVm0", "flt ", "vrm", "供电域温度（最小 A）", "low",
     "~76.5°C；与 TVm2/TVM0 同族但独立；TVm* 疑为 memory rail 温度"),
    ("TVS0", "flt ", "vrm", "供电域温度（S0）", "low",
     "实测 43.7–44.6°C，几乎恒定（±0.1）；另一路供电/传感器轨"),
    ("TVS1", "flt ", "vrm", "供电域温度（S1）", "low",
     "实测 44.6–45.6°C，与 TVS0 恒差 1.0°C"),
    # ================= 其他 =================
    ("TCHP", "flt ", "other", "未分类测点 TCHP", "low",
     "实测 50.6–52.9°C，全程基本恒定（对 CPU/GPU/内存负载均无响应，GPU 阶段 +0.8°C 为噪声）；疑为充电/机壳类慢变量"),
    ("TMVR", "flt ", "other", "未分类测点 TMVR", "low",
     "实测 53.3–55.3°C，几乎不随负载变化"),
    ("TIOP", "flt ", "other", "I/O / 雷电接口", "low",
     "实测 44.6–45.5°C 恒定；键名 IO 前缀，项目早期探测归为雷电；无公开键表佐证"),
    ("TRD0", "flt ", "other", "未分类测点 TRD0", "low",
     "TRD0..TRD8/TRDX 共 10 个 55–58°C 测点，对负载几乎不敏感（±0.3°C）；含义未确认"),
    ("T5SP", "flt ", "other", "未分类测点 T5SP", "low",
     "实测 47.6–48.4°C 恒定；疑为固定参考/校准值"),
    ("Ts0P", "flt ", "other", "未分类测点 Ts0P", "low",
     "实测 25.9–27.1°C，与电池/机身组同漂移（差值恒定）；早前误判为 NAND，已由 HID NAND CH0=52°C 排除，改为低置信度未分类"),
    ("Ts1P", "flt ", "other", "未分类测点 Ts1P", "low",
     "实测 24.9–26.3°C，与 Ts0P 恒差 0.9°C；同为低速变量"),
]

def main():
    rows = []
    for key, typ, cat, name, conf, ev in E:
        idle, load, mn, mx = M[key]
        rows.append({
            "key": key,
            "type": typ,
            "category": cat,
            "displayName": name,
            "confidence": conf,
            "typicalIdle": round(float(idle), 1),
            "typicalLoad": round(float(load), 1),
            "evidence": ev,
        })
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"wrote {OUT}: {len(rows)} entries")
    from collections import Counter
    print("categories:", dict(Counter(r["category"] for r in rows)))
    print("confidence:", dict(Counter(r["confidence"] for r in rows)))

if __name__ == "__main__":
    main()
