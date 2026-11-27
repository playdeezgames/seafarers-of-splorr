#!/usr/bin/env bash
# Build, then serve build/web on http://localhost:${PORT:-8000} (wasm will not load from file://).
set -euo pipefail
cd "$(dirname "$0")/.."
tools/build.sh
exec python3 -m http.server -d build/web "${PORT:-8000}"
