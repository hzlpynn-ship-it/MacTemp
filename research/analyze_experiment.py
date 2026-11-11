#!/usr/bin/env python3
# analyze_experiment.py — MacTemp 温度传感器实测数据分析
# MacTemp 传感器研究工具（不参与 App 构建）
#
# 输入: /tmp/mt_exp/{sensors.csv,cpu.csv,phases.log,context.log}
# 输出:
#   /tmp/mt_exp/report_phase_medians.csv   各键在各阶段的 中位温度
#   /tmp/mt_exp/report_deltas.csv          各键 ΔT(P/E/GPU/MEM/NAND vs baseline) + P-E 对比度
#   /tmp/mt_exp/report_groups.csv          数值完全相同的键分组（同传感器别名）
#   /tmp/mt_exp/report_cpu_clusters.csv    P/E 负载阶段各逻辑核占用率均值（判断核序号分组）
#   stdout: 关键摘要
import sys
import pandas as pd
import numpy as np

OUT = "/tmp/mt_exp"


def load():
    ph = pd.read_csv(f"{OUT}/phases.log", sep=r"\s+", header=None,
                     names=["tag", "phase", "start", "end"])
    ph = ph[ph["tag"] == "PHASE"][["phase", "start", "end"]].astype({"start": float, "end": float})
    ph["dur"] = ph["end"] - ph["start"]
    ph = ph.reset_index(drop=True)
    s = pd.read_csv(f"{OUT}/sensors.csv")
    s = s.drop_duplicates(subset=["t_unix", "key"], keep="last")
    wide = s.pivot(index="t_unix", columns="key", values="value").sort_index()
    return ph, wide


def label_phase(t, ph):
    for _, r in ph.iterrows():
        if r["start"] <= t < r["end"]:
            return r["phase"]
    return "none"


def main():
    ph, wide = load()
    print(f"[input] {len(wide)} samples, {wide.shape[1]} keys, span {wide.index.max()-wide.index.min():.1f}s")
    print(ph[["phase", "dur"]].to_string(index=False))

    # 每个键在各阶段的中位数
    labels = np.array([label_phase(t, ph) for t in wide.index])
    wide = wide.assign(_phase=labels)
    group_map = {"p1": "p", "p2": "p", "p3": "p", "p4": "p",
                 "e1": "e", "e2": "e", "e3": "e", "e4": "e"}
    wide["_phase2"] = wide["_phase"].map(lambda x: group_map.get(x, x))
    num = wide.drop(columns=[c for c in ["_phase", "_phase2"] if c in wide.columns])
    med = num.groupby(wide["_phase2"]).median()
    med.to_csv(f"{OUT}/report_phase_medians.csv")

    base = med.loc["baseline"] if "baseline" in med.index else med.iloc[0]
    rec = {}
    for key in [c for c in med.columns]:
        rec[key] = {
            "idle": base[key],
            "p": med.loc["p", key] if "p" in med.index else np.nan,
            "e": med.loc["e", key] if "e" in med.index else np.nan,
            "gpu": med.loc["gpu", key] if "gpu" in med.index else np.nan,
            "mem": med.loc["mem", key] if "mem" in med.index else np.nan,
            "nand": med.loc["nand", key] if "nand" in med.index else np.nan,
            "quiet1": med.loc["quiet1", key] if "quiet1" in med.index else np.nan,
            "quiet2": med.loc["quiet2", key] if "quiet2" in med.index else np.nan,
            "quiet3": med.loc["quiet3", key] if "quiet3" in med.index else np.nan,
        }
    r = pd.DataFrame(rec).T
    r["dP"] = r["p"] - r["idle"]
    r["dE"] = r["e"] - r["idle"]
    r["dPmE"] = r["p"] - r["e"]
    r["dGPU"] = r["gpu"] - r["quiet1"]
    r["dMem"] = r["mem"] - r["quiet2"]
    r["dNand"] = r["nand"] - r["quiet3"]
    r["spread"] = r[["p", "e", "gpu", "mem", "nand"]].max(axis=1) - r[["p", "e", "gpu", "mem", "nand"]].min(axis=1)
    # 归一化对比度：谁更像 P / E / GPU
    r["scoreP"] = r["dPmE"] / (r["spread"].abs() + 0.05)
    r["scoreGPU"] = r["dGPU"] / (r["spread"].abs() + 0.05)
    r["scoreMem"] = r["dMem"] / (r["spread"].abs() + 0.05)
    r["scoreNand"] = r["dNand"] / (r["spread"].abs() + 0.05)
    r = r.sort_values("dPmE", ascending=False)
    r.round(3).to_csv(f"{OUT}/report_deltas.csv")

    print("\n=== Top 20 by dPmE (更像 P 核) ===")
    print(r.head(20)[["idle", "p", "e", "gpu", "mem", "nand", "dP", "dE", "dPmE", "dGPU", "dMem", "dNand"]].round(2).to_string())
    print("\n=== Bottom 20 by dPmE (更像 E 核) ===")
    print(r.tail(20)[["idle", "p", "e", "gpu", "mem", "nand", "dP", "dE", "dPmE", "dGPU", "dMem", "dNand"]].round(2).to_string())
    print("\n=== Top 15 by dGPU ===")
    print(r.sort_values("dGPU", ascending=False).head(15)[["idle", "p", "e", "gpu", "quiet1", "dP", "dE", "dGPU"]].round(2).to_string())
    print("\n=== Top 15 by dMem ===")
    print(r.sort_values("dMem", ascending=False).head(15)[["idle", "p", "e", "mem", "quiet2", "dMem"]].round(2).to_string())
    print("\n=== Top 15 by dNand ===")
    print(r.sort_values("dNand", ascending=False).head(15)[["idle", "p", "e", "nand", "quiet3", "dNand"]].round(2).to_string())

    # ---- 相同数值的键分组（同一物理传感器的别名） ----
    cols = list(wide.columns)
    cols = [c for c in cols if not c.startswith("_")]
    sub = wide[cols].dropna(how="all")
    groups = {}
    used = set()
    for i, a in enumerate(cols):
        if a in used:
            continue
        members = [a]
        va = sub[a].values.astype(float)
        for b in cols[i + 1:]:
            if b in used:
                continue
            vb = sub[b].values.astype(float)
            m = ~np.isnan(va) & ~np.isnan(vb)
            if m.sum() < 30:
                continue
            if np.max(np.abs(va[m] - vb[m])) < 0.02:
                members.append(b)
                used.add(b)
        used.add(a)
        groups[a] = members
    g = pd.DataFrame([{"key": k, "n": len(v), "members": " ".join(v)} for k, v in groups.items() if len(v) > 1])
    g.sort_values("n", ascending=False).to_csv(f"{OUT}/report_groups.csv", index=False)
    print(f"\n=== 完全相同数值的键组（{len(g)} 组，共 {int(g['n'].sum()) if len(g) else 0} 个键）===")
    if len(g):
        print(g.sort_values("n", ascending=False).to_string(index=False))

    # ---- CPU 占用率：各阶段每逻辑核均值 ----
    try:
        cpu = pd.read_csv(f"{OUT}/cpu.csv")
        cpu["_phase"] = [label_phase(t, ph) for t in cpu["t_unix"]]
        cpu["_phase2"] = cpu["_phase"].map(lambda x: group_map.get(x, x))
        core_cols = [c for c in cpu.columns if c.startswith("cpu")]
        cm = cpu.groupby("_phase2")[core_cols].mean()
        cm.round(1).to_csv(f"{OUT}/report_cpu_clusters.csv")
        print("\n=== 各阶段每逻辑核平均占用率 (%) ===")
        print(cm.round(1).to_string())
        if "p" in cm.index and "e" in cm.index:
            dp = (cm.loc["p"] - cm.loc["baseline"]).round(1)
            de = (cm.loc["e"] - cm.loc["baseline"]).round(1)
            print("\nP 负载相对空载各核 Δ占用:", dp.to_dict())
            print("E 负载相对空载各核 Δ占用:", de.to_dict())
    except Exception as e:  # noqa: BLE001
        print(f"[warn] cpu cluster analysis failed: {e}")


if __name__ == "__main__":
    main()
