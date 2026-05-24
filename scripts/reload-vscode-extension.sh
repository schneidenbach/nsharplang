#!/usr/bin/env bash
# Quick reload script for VS Code extension development.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/vscode-extension.sh"

SAMPLE_PROJECT="${NSHARP_VSCODE_SAMPLE_PROJECT:-$NSHARP_REPO_ROOT/examples/01-hello-world}"

nsharp_require_command dotnet
nsharp_require_command npm
nsharp_require_command npx
nsharp_require_command code

echo "N# VS Code Extension Quick Reload"
echo "================================="
echo ""

echo "1. Killing VS Code..."
nsharp_kill_vscode
sleep 1

echo ""
echo "2. Building language server and packaging VSIX..."
nsharp_build_vscode_extension_package
VSIX_FILE="$(nsharp_latest_vscode_vsix)"
echo "   Created: $VSIX_FILE"

echo ""
echo "3. Installing extension..."
nsharp_run code --install-extension "$VSIX_FILE" --force

echo ""
echo "4. Opening sample project..."
echo "   Project: $SAMPLE_PROJECT"
nsharp_run code "$SAMPLE_PROJECT"

echo ""
echo "Done. VS Code should open with the sample project."
echo ""
echo "Tips:"
echo "   - Open a .nl file to activate the extension"
echo "   - Press F1 and type 'Developer: Reload Window' to reload extension"
echo "   - Check the Output panel and select 'N# Language Server' to see logs"
echo ""
