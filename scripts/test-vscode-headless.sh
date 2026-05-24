#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/vscode-extension.sh"

PROJECT_ROOT="$NSHARP_REPO_ROOT"
VSCODE_EXT_DIR="$NSHARP_VSCODE_EXT_DIR"
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

nsharp_ensure_vscode_dependencies

npm run compile

echo ""
echo "3. Executing headless VS Code smoke tests"
NSHARP_VSCODE_SERVER_PATH="$SERVER_PATH" \
NSHARP_VSCODE_REPORT_PATH="$REPORT_PATH" \
npm run test:headless

echo ""
echo "Report: $REPORT_PATH"
