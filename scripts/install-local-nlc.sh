#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "install-local-nlc.sh is retained as a compatibility wrapper."
echo "Installing the local N# toolset with launchers under ~/.nsharp/bin."
exec "$SCRIPT_DIR/setup-local.sh" --skip-vscode "$@"
