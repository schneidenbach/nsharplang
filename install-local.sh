#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NSHARP_SETUP_LOCAL_INVOCATION="./install-local.sh" \
    NSHARP_SETUP_LOCAL_DEFAULT_WITH_VSCODE="${NSHARP_SETUP_LOCAL_DEFAULT_WITH_VSCODE:-1}" \
    exec "$SCRIPT_DIR/scripts/setup-local.sh" "$@"
