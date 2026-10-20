#!/usr/bin/env bash
# Runs the kernel rasterizer test (raster_gpu_test.br: kernel vs CPU reference) on the real kernel targets,
# `--target simd` and `--target wgpu`, and fails on the first target that does not print "raster gpu ok".
# (`boring run tests/raster_gpu_test.br` runs the same file as a sequential CPU simulation.)
#
# Usage: render/tests/run_kernel_tests.sh            # simd and wgpu
#        TARGETS=simd render/tests/run_kernel_tests.sh
#        BORING=/path/to/boring render/tests/run_kernel_tests.sh
set -euo pipefail

BORING="${BORING:-boring}"
TARGETS="${TARGETS:-simd wgpu}"
cd "$(dirname "${BASH_SOURCE[0]}")"

status=0
for target in $TARGETS; do
    echo "=== boring build --target $target raster_gpu_test.br ==="
    rm -rf "raster_gpu_test_$target"
    "$BORING" build --target "$target" raster_gpu_test.br >/dev/null
    (
        cd "raster_gpu_test_$target"
        if [ "$target" = simd ]; then
            RUSTFLAGS="-A warnings" cargo run --release -q
        else
            RUSTFLAGS="-A warnings" cargo run -q
        fi
    ) | tee "raster_gpu_test_$target.log"
    if ! grep -q "raster gpu ok" "raster_gpu_test_$target.log"; then
        echo "FAILED: $target" >&2
        status=1
    fi
    rm -f "raster_gpu_test_$target.log"
done
exit "$status"
