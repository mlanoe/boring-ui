#!/usr/bin/env bash
# Builds the Todo window for `--target wgpu` and runs it (Escape quits).
set -euo pipefail

BORING="${BORING:-boring}"
cd "$(dirname "${BASH_SOURCE[0]}")"

rm -rf main_wgpu
"$BORING" build --target wgpu >/dev/null
cd main_wgpu
RUSTFLAGS="-A warnings" cargo run --release -q
