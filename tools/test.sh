#!/usr/bin/env bash
# Native tests for the rules, then a wasm type check of the web layer.
set -euo pipefail
cd "$(dirname "$0")/.."
odin test game -define:ODIN_TEST_THREADS=1 -o:speed -vet-shadowing -vet-unused
odin check src/web -collection:sos=. -target:js_wasm32 -vet-shadowing -vet-unused
