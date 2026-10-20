#!/usr/bin/env bash
# Runs the kernel rasterizer tests on the real kernel targets, `--target simd` and `--target wgpu`:
#   raster_gpu_test.br   per-pixel kernel vs the CPU reference        (prints "raster gpu ok")
#   raster_tile_test.br  tiled kernel vs the per-pixel kernel, exact  (prints "raster tile ok")
# and fails on the first one that does not print its line.
# (`boring run tests/<file>.br` runs the same files as a sequential CPU simulation.)
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
    for test in "raster_gpu_test:raster gpu ok" "raster_tile_test:raster tile ok"; do
        name="${test%%:*}"
        expected="${test#*:}"
        echo "=== boring build --target $target $name.br ==="
        rm -rf "${name}_$target"
        "$BORING" build --target "$target" "$name.br" >/dev/null
        (
            cd "${name}_$target"
            if [ "$target" = simd ]; then
                RUSTFLAGS="-A warnings" cargo run --release -q
            else
                RUSTFLAGS="-A warnings" cargo run -q
            fi
        ) | tee "${name}_$target.log"
        if ! grep -q "$expected" "${name}_$target.log"; then
            echo "FAILED: $name on $target" >&2
            status=1
        fi
        rm -f "${name}_$target.log"
    done
done
exit "$status"
