#!/usr/bin/env bash
# 操作シナリオ→描画結果ギャラリーをローカル生成（CI・実機不要）。
# Swift(Linux)が描画命令をJSON化 → Python(PIL)がPNG＋HTMLに起こす。
#   使い方: tools/gallery.sh [出力ディレクトリ]   (既定: ./gallery)
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/share/swiftly/bin:$PATH"
OUT="${1:-gallery}"
JSON="$(mktemp)"
GALLERY_OUT="$JSON" swift test --package-path Packages/PhotoLayoutCore --filter generateGallery >/dev/null 2>&1
python3 tools/render_gallery.py "$JSON" "$OUT"
rm -f "$JSON"
echo "open $OUT/index.html  (または $OUT/gallery.png)"
