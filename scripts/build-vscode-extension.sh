#!/usr/bin/env bash
# Build and package VS Code extension without killing or reopening VS Code.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/vscode-extension.sh"

nsharp_require_command dotnet
nsharp_require_command npm
nsharp_require_command npx

echo "Building N# VS Code Extension"
echo "============================="
echo ""

echo "1. Building language server and packaging VSIX..."
nsharp_build_vscode_extension_package

VSIX_FILE="$(nsharp_latest_vscode_vsix)"
echo ""
echo "Extension built: $VSIX_FILE"
echo ""
echo "To install manually:"
echo "   code --install-extension $VSIX_FILE --force"
echo ""
echo "Or use the full reload script:"
echo "   ./scripts/reload-vscode-extension.sh"
echo ""
