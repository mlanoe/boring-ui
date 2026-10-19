#!/usr/bin/env bash
# Runs every *_test.br file in this directory with `boring run` (the kernel test as a sequential CPU
# simulation); run_kernel_tests.sh runs the kernel test on the real `simd` and `wgpu` targets.
#
# Usage: render/tests/run_tests.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

status=0
for f in *_test.br; do
    echo "=== boring run $f ==="
    if ! boring run "$f"; then
        echo "FAILED: $f" >&2
        status=1
    fi
done

exit "$status"
