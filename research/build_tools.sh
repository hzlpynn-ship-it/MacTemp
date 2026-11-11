#!/bin/bash
# build_tools.sh — 编译 MacTemp 传感器研究工具（无 Xcode，只需 CLT）
# MacTemp 传感器研究工具（不参与 App 构建）
#
# 用法: ./build_tools.sh [输出目录]     # 默认 /tmp/mt_bin
# 依赖: clang、swiftc（Command Line Tools）、macOS SDK（IOKit/Metal）
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
BIN="${1:-/tmp/mt_bin}"
mkdir -p "$BIN"

clang -O2 -o "$BIN/mt_sampler" "$SRC/mt_sampler.c" "$SRC/smc_mt.c" -framework IOKit
clang -O2 -o "$BIN/cpu_load"   "$SRC/cpu_load.c"
clang -O2 -o "$BIN/cpu_watch"  "$SRC/cpu_watch.c"
clang -O2 -o "$BIN/mem_load"   "$SRC/mem_load.c"
clang -O2 -o "$BIN/proc_top"   "$SRC/proc_top.c" -lproc
clang -O2 -o "$BIN/hid_sensors" "$SRC/hid_sensors.c" -framework IOKit -framework CoreFoundation
clang -O2 -o "$BIN/proc_watch" "$SRC/proc_watch.c" -lproc
swiftc -O -target arm64-apple-macosx14.0 \
  -module-cache-path /tmp/mt_swift_mc \
  -Xcc -fmodules-cache-path=/tmp/mt_swift_mc \
  -o "$BIN/metal_load" "$SRC/metal_load.swift"

echo "built: $BIN/{mt_sampler,cpu_load,cpu_watch,mem_load,proc_top,proc_watch,hid_sensors,metal_load}"
echo "下一步: ./run_experiment.sh   (约 5 分钟；结果在 /tmp/mt_exp/)"
echo "     然后: $PWD/analyze_experiment.py   (需要 pandas)"
