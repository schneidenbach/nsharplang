#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/prepare-playground-wasm-async-tests.sh"
cd "$REPO_ROOT"
exec node --test website/tests/playground-wasm-async.test.mjs
