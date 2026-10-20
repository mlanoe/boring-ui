#!/usr/bin/env bash
# Builds stages.br for `--target wgpu` and prints the per-stage timings of the tiled kernel (release build).
# Usage: render/bench/run_stages.sh   (BORING=/path/to/boring to pick a compiler)
set -euo pipefail

BORING="${BORING:-boring}"
cd "$(dirname "${BASH_SOURCE[0]}")"
rm -rf stages_wgpu
"$BORING" build --target wgpu stages.br >/dev/null
cd stages_wgpu
RUSTFLAGS="-A warnings" cargo run --release -q
