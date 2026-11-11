#!/bin/bash
# run_experiment.sh — MacTemp 温度传感器实测：单次连续实验（约 4.8 分钟）
# MacTemp 传感器研究工具（不参与 App 构建）
#
# 依赖（见 build_tools.sh）: /tmp/mt_bin/{mt_sampler,cpu_load,cpu_watch,metal_load,mem_load}
# 输出: /tmp/mt_exp/sensors.csv  (0.5s 采样，长表 t,key,value)
#       /tmp/mt_exp/cpu.csv      (1s 每逻辑核占用率)
#       /tmp/mt_exp/phases.log   (PHASE <name> <start_unix> <end_unix>)
#       /tmp/mt_exp/context.log  (smctemp -c/-g 与 loadavg 快照)
# 注意: 只用只读 SMC + 自建 QoS 负载；不加 sudo；结束自建进程全部退出。
set -u
BIN=/tmp/mt_bin
OUT=/tmp/mt_exp
# 可选：外部 smctemp 可执行文件路径（https://github.com/narugit/smctemp），用于交叉验证
SMCTEMP="${SMCTEMP:-smctemp}"
mkdir -p "$OUT"
SAMPLES=600      # 采样轮数（0.5s * 600 = 300s）
INTERVAL_MS=500
: > "$OUT/phases.log"
: > "$OUT/context.log"

now() { python3 -c 'import time;print("%.3f"%time.time())'; }
phase() { echo "PHASE $1 $(now) $(now)" >> "$OUT/phases.log"; }

ctx() {
  local tag="$1" c g l
  c=$("$SMCTEMP" -c 2>/dev/null | tr -d '\n')
  g=$("$SMCTEMP" -g 2>/dev/null | tr -d '\n')
  l=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '\n')
  echo "CTX $tag $(now) smctemp_c=$c smctemp_g=$g loadavg=$l" >> "$OUT/context.log"
}

echo "[exp] start $(date '+%F %T')"
ctx start

"$BIN/mt_sampler" sample 302 "$INTERVAL_MS" "$OUT/sensors.csv" > "$OUT/sampler.log" 2>&1 &
SPID=$!
"$BIN/cpu_watch" 300 1000 "$OUT/cpu.csv" > /dev/null 2>&1 &
WPID=$!
sleep 1

# --- Phase 0: 空载基线（不加自建负载）22s ---
P0=$(now); sleep 22; echo "PHASE baseline $P0 $(now)" >> "$OUT/phases.log"
ctx after_baseline

# --- Phase 1: P 核 / E 核交替 4 轮，各 20s ---
for i in 1 2 3 4; do
  P=$(now); "$BIN/cpu_load" p 4 20 > /dev/null 2>&1; echo "PHASE p$i $P $(now)" >> "$OUT/phases.log"
  [ "$i" = "2" ] && ctx during_p2
  P=$(now); "$BIN/cpu_load" e 6 20 > /dev/null 2>&1; echo "PHASE e$i $P $(now)" >> "$OUT/phases.log"
  [ "$i" = "2" ] && ctx during_e2
done

# --- 冷却 8s ---
P=$(now); sleep 8; echo "PHASE quiet1 $P $(now)" >> "$OUT/phases.log"

# --- Phase 2: GPU 负载 36s ---
P=$(now); "$BIN/metal_load" 36 500 > "$OUT/gpu.log" 2>&1; echo "PHASE gpu $P $(now)" >> "$OUT/phases.log"
ctx during_gpu

# --- 冷却 8s ---
P=$(now); sleep 8; echo "PHASE quiet2 $P $(now)" >> "$OUT/phases.log"

# --- Phase 3: 内存负载 26s（5GB 跨步读写，2 线程） ---
P=$(now); "$BIN/mem_load" 3 26 2 > "$OUT/mem.log" 2>&1; echo "PHASE mem $P $(now)" >> "$OUT/phases.log"

# --- 冷却 7s ---
P=$(now); sleep 7; echo "PHASE quiet3 $P $(now)" >> "$OUT/phases.log"

# --- Phase 4: NAND/SSD 写负载（1GB fsync） ---
P=$(now)
dd if=/dev/zero of=/tmp/mt_nand_test.bin bs=1m count=1024 conv=fsync 2>/dev/null
sync
echo "PHASE nand $P $(now)" >> "$OUT/phases.log"
rm -f /tmp/mt_nand_test.bin

# --- 收尾 8s ---
P=$(now); sleep 8; echo "PHASE tail $P $(now)" >> "$OUT/phases.log"
ctx end

wait $SPID 2>/dev/null
wait $WPID 2>/dev/null
echo "[exp] done $(date '+%F %T')"
wc -l "$OUT/sensors.csv" "$OUT/cpu.csv"
cat "$OUT/phases.log"
