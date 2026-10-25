#!/usr/bin/env bash
# Frame cost of a 10 / 100 / 1000 row tree, stage by stage (bench_tree.br), on the wgpu kernel target.
set -euo pipefail
BORING="${BORING:-boring}"
cd "$(dirname "${BASH_SOURCE[0]}")"
rm -rf bench_tree_wgpu
"$BORING" build --target wgpu bench_tree.br >/dev/null
cd bench_tree_wgpu
RUSTFLAGS="-A warnings" cargo run --release -q
