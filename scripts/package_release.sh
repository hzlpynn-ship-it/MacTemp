#!/bin/bash
# 打包分发：生成可分发的 zip（GitHub Release 附件用）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/MacTemp.app"
ZIP="$ROOT/dist/MacTemp-1.0.0.zip"

if [ ! -d "$APP" ]; then
  echo "未找到 $APP，请先运行 scripts/build.sh" >&2
  exit 1
fi

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "打包完成：$ZIP"
ls -lh "$ZIP"
