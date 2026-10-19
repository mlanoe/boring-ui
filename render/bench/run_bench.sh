#!/usr/bin/env bash
# Builds bench_raster.br for the real kernel targets and prints its timings.
# (Same stopgap as tests/run_kernel_tests.sh: the unicode crates are added to the generated crate by hand.)
#
# Usage: render/bench/run_bench.sh            # simd and wgpu
#        TARGETS=wgpu render/bench/run_bench.sh
#        BORING=/path/to/boring render/bench/run_bench.sh
set -euo pipefail

BORING="${BORING:-boring}"
TARGETS="${TARGETS:-simd wgpu}"
cd "$(dirname "${BASH_SOURCE[0]}")"
echo "boring.toml" >/dev/null
[ -f boring.toml ] || cp ../tests/boring.toml boring.toml

for target in $TARGETS; do
    echo "=== $target ==="
    rm -rf "bench_raster_$target"
    "$BORING" build --target "$target" bench_raster.br >/dev/null
    (
        cd "bench_raster_$target"
        cargo add unicode-segmentation unicode-width --quiet
        # the generated crate runs in release mode: timings are meaningless in a debug build
        RUSTFLAGS="-A warnings" cargo run --release -q
    )
done
