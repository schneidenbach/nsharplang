#!/bin/bash
# Build and package VS Code extension (without killing/reopening VS Code)
# Use this if you want to manually reload the extension

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VSCODE_EXT_DIR="$PROJECT_ROOT/editors/vscode"

echo "🔧 Building N# VS Code Extension"
echo "================================"
echo ""

# 1. Build Language Server
echo "1️⃣  Building Language Server..."
cd "$PROJECT_ROOT"
dotnet build src/NSharpLang.LanguageServer/LanguageServer.csproj -c Release -v quiet

# 2. Package VSIX
echo ""
echo "2️⃣  Packaging VSIX..."
cd "$VSCODE_EXT_DIR"

# Copy language server to extension
echo "   - Copying language server..."
mkdir -p server
cp -f "$PROJECT_ROOT/src/NSharpLang.LanguageServer/bin/Release/net10.0"/* server/ 2>/dev/null || true

# Compile TypeScript
echo "   - Compiling TypeScript..."
npm run compile

# Package VSIX
echo "   - Creating VSIX package..."
npx vsce package --allow-star-activation

VSIX_FILE=$(ls -t nsharp-*.vsix | head -1)
echo ""
echo "✅ Extension built: $VSCODE_EXT_DIR/$VSIX_FILE"
echo ""
echo "To install manually:"
echo "   code --install-extension $VSCODE_EXT_DIR/$VSIX_FILE --force"
echo ""
echo "Or use the full reload script:"
echo "   ./scripts/reload-vscode-extension.sh"
echo ""
