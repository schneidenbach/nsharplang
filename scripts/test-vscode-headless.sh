#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VSCODE_EXT_DIR="$PROJECT_ROOT/editors/vscode"
SERVER_PATH="${NSHARP_VSCODE_SERVER_PATH:-$PROJECT_ROOT/src/NSharpLang.LanguageServer/bin/Release/net10.0/LanguageServer.dll}"
REPORT_PATH="${NSHARP_VSCODE_REPORT_PATH:-$PROJECT_ROOT/.context/vscode-headless-report.json}"

echo "Running headless VS Code smoke tests"
echo "===================================="
echo ""

cd "$PROJECT_ROOT"
echo "1. Building language server"
dotnet build src/NSharpLang.LanguageServer/LanguageServer.csproj -c Release -v quiet

echo ""
echo "2. Compiling VS Code extension and test harness"
cd "$VSCODE_EXT_DIR"

if [[ ! -d node_modules ]]; then
    npm install
fi

npm run compile

echo ""
echo "3. Executing headless VS Code smoke tests"
NSHARP_VSCODE_SERVER_PATH="$SERVER_PATH" \
NSHARP_VSCODE_REPORT_PATH="$REPORT_PATH" \
npm run test:headless

echo ""
echo "Report: $REPORT_PATH"
