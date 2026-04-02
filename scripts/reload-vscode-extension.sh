#!/bin/bash
# Quick reload script for VS Code extension development
# Kills VS Code, rebuilds extension, reinstalls it, and reopens sample project

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VSCODE_EXT_DIR="$PROJECT_ROOT/editors/vscode"
SAMPLE_PROJECT="$PROJECT_ROOT/examples/01-hello-world"

echo "🔧 N# VS Code Extension Quick Reload"
echo "===================================="
echo ""

# 1. Kill VS Code
echo "1️⃣  Killing VS Code..."
killall "Visual Studio Code" 2>/dev/null || killall "Code" 2>/dev/null || true
sleep 1

# 2. Build Language Server
echo ""
echo "2️⃣  Building Language Server..."
cd "$PROJECT_ROOT"
dotnet build src/NSharpLang.LanguageServer/LanguageServer.csproj -c Release -v quiet

# 3. Package VSIX
echo ""
echo "3️⃣  Packaging VSIX..."
cd "$VSCODE_EXT_DIR"

# Copy language server to extension
echo "   - Copying language server..."
mkdir -p server
cp -f "$PROJECT_ROOT/src/NSharpLang.LanguageServer/bin/Release/net9.0"/* server/ 2>/dev/null || true

# Install npm dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "   - Installing npm dependencies..."
    npm install
fi

# Compile TypeScript
echo "   - Compiling TypeScript..."
npm run compile || { echo "   ❌ TypeScript compile failed"; exit 1; }

# Package VSIX
echo "   - Creating VSIX package..."
npx vsce package --allow-star-activation > /dev/null 2>&1 || {
    echo "   ⚠️  vsce not found, installing..."
    npm install -g @vscode/vsce > /dev/null 2>&1
    npx vsce package --allow-star-activation > /dev/null 2>&1
}

VSIX_FILE=$(ls -t nsharp-*.vsix | head -1)
echo "   ✅ Created: $VSIX_FILE"

# 4. Install Extension
echo ""
echo "4️⃣  Installing extension..."
code --install-extension "$VSIX_FILE" --force

# 5. Open Sample Project
echo ""
echo "5️⃣  Opening sample project..."
echo "   Project: $SAMPLE_PROJECT"

# Open VS Code with the sample project
code "$SAMPLE_PROJECT"

echo ""
echo "✅ Done! VS Code should open with the sample project."
echo ""
echo "💡 Tips:"
echo "   - Open a .nl file to activate the extension"
echo "   - Press F1 and type 'Developer: Reload Window' to reload extension"
echo "   - Check the Output panel (View → Output) and select 'N# Language Server' to see logs"
echo ""
