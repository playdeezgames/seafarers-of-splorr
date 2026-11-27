#!/usr/bin/env bash
# Build the wasm game into build/web. Pass --size for the shipping build.
set -euo pipefail
cd "$(dirname "$0")/.."
opt=speed
[[ "${1:-}" == "--size" ]] && opt=size
mkdir -p build/web
odin build src/web -collection:sos=. -target:js_wasm32 -out:build/web/game.wasm -o:$opt -vet-shadowing -vet-unused
cp "$(odin root)/core/sys/wasm/js/odin.js" build/web/
cp web/lootlocker.js build/web/
# Stamp a build id into the page's file URLs so browsers and the Pages CDN never mix old and new files.
build_id="$(git rev-parse --short HEAD 2>/dev/null || echo dev)-$(date +%s)"
sed "s/__BUILD__/$build_id/g" web/index.html > build/web/index.html
cp assets/font/m6x11.png build/web/font.png
cp assets/tiles/natural.png build/web/natural.png
echo "built build/web ($opt)"
