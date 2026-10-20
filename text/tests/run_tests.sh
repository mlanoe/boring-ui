#!/usr/bin/env bash
# Builds the text-engine test (it calls swash, so `boring run` cannot interpret it) and runs the binary.
# Usage: boring-ui/text/tests/run_tests.sh   (BORING=path/to/boring to pick a compiler)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
BORING="${BORING:-boring}"
"$BORING" build >/dev/null
(cd shape_test_rust && cargo run --quiet 2>&1 | grep -v '^warning\|^ *|\|^ *-->\|^$\|= note\|= help\|^[0-9]* [-+]\|^help' || true)
