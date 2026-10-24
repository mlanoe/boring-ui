#!/usr/bin/env bash
# Builds and runs the demo; the PPM goes to stdout (BORING=path/to/boring to pick a compiler).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
"${BORING:-boring}" build >/dev/null 2>&1
(cd bidi_demo_rust && cargo run --quiet 2>/dev/null)
