#!/usr/bin/env bash
# Runs every *_test.br file in this directory with `boring run`, from the repo root, and fails
# (nonzero exit) on the first one that doesn't pass.
#
# Usage: tests/run_tests.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0
for f in tests/*_test.br; do
    echo "=== boring run $f ==="
    if ! boring run "$f"; then
        echo "FAILED: $f" >&2
        status=1
    fi
done

exit "$status"
