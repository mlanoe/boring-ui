#!/usr/bin/env bash
# Runs every *_test.br file through the TRANSPILER: `boring build` -> `cargo run`, and fails
# (nonzero exit) if any file fails to transpile, fails to compile as Rust, or exits nonzero.
# Counterpart of run_tests.sh (which uses the interpreter, `boring run`). The generated Cargo
# projects land in tests/*_rust/ (gitignored).
#
# Usage: tests/run_tests_transpiled.sh            # all tests
#        BORING=/path/to/boring tests/run_tests_transpiled.sh   # a specific compiler build
set -euo pipefail

BORING="${BORING:-boring}"
cd "$(dirname "${BASH_SOURCE[0]}")"

status=0
for f in *_test.br; do
    name="${f%.br}"
    echo "=== boring build $f ==="
    if ! "$BORING" build "$f" >/dev/null 2>"$name.build.log"; then
        echo "FAILED (transpile): $f — see tests/$name.build.log" >&2
        status=1
        continue
    fi
    rm -f "$name.build.log"
    if ! (cd "${name}_rust" && RUSTFLAGS="-A warnings" cargo run -q); then
        echo "FAILED (compile/run): $f" >&2
        status=1
    fi
done

exit "$status"
