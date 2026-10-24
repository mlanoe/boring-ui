#!/usr/bin/env bash
# Runs every *_test.br file in this directory with `boring run` (the kernel test as a sequential CPU
# simulation); run_kernel_tests.sh runs the kernel test on the real `simd` and `wgpu` targets.
#
# Tests listed in NATIVE are too slow under the interpreter (the JPEG decoder takes minutes there: every pixel and
# coefficient is a boxed value): they are built with `boring build` and run as native binaries instead (a fraction of
# a second). Set BORING=path/to/boring to pick a compiler; set INTERPRET_ALL=1 to run everything with `boring run`.
#
# Usage: render/tests/run_tests.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

BORING="${BORING:-boring}"
NATIVE="jpeg_test.br"
SKIP="raster_tile_test.br"

status=0
for f in *_test.br; do
    if [ -z "${INTERPRET_ALL:-}" ] && [[ " $SKIP " == *" $f "* ]]; then
        echo "=== skipped $f (kernel targets only: run_kernel_tests.sh) ==="
        continue
    fi
    if [ -z "${INTERPRET_ALL:-}" ] && [[ " $NATIVE " == *" $f "* ]]; then
        name="${f%.br}"
        echo "=== boring build + native run $f ==="
        rm -rf "${name}_rust"
        if "$BORING" build "$f" >/dev/null 2>&1 \
            && (cd "${name}_rust" && RUSTFLAGS="-A warnings" cargo build --release -q 2>/dev/null) \
            && "./${name}_rust/target/release/${name//_/_}"; then
            :
        else
            echo "FAILED: $f" >&2
            status=1
        fi
        rm -rf "${name}_rust"
        continue
    fi
    echo "=== $BORING run $f ==="
    if ! "$BORING" run "$f"; then
        echo "FAILED: $f" >&2
        status=1
    fi
done

exit "$status"
