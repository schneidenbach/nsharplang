#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/lib/common.sh"
cd "$NSHARP_REPO_ROOT"
REPO_ROOT="$NSHARP_REPO_ROOT"

echo "======================================="
echo "N# VS Code Integration Tests"
echo "======================================="
echo

# Check prerequisites
if ! command -v code >/dev/null 2>&1; then
    echo -e "${RED}Error: VS Code ('code' command) not found on PATH${NC}"
    echo "Install VS Code and ensure 'code' is available in your shell."
    echo "On macOS: Open VS Code > Cmd+Shift+P > 'Shell Command: Install code command'"
    exit 1
fi

if ! command -v dotnet >/dev/null 2>&1; then
    echo -e "${RED}Error: 'dotnet' not found on PATH${NC}"
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    echo -e "${RED}Error: 'node' not found on PATH${NC}"
    exit 1
fi

# Check if Language Server is already built (e.g., by test-all.sh step 2)
LS_DLL="src/NSharpLang.LanguageServer/bin/Debug/net10.0/LanguageServer.dll"
if [ -f "$LS_DLL" ] && [ "$SKIP_LS_BUILD" = "1" ]; then
    echo -e "${GREEN}✓ Language Server already built (skipping rebuild)${NC}"
else
    echo -e "${YELLOW}Step 1: Building Language Server${NC}"
    dotnet build src/NSharpLang.LanguageServer/LanguageServer.csproj -v q
    echo -e "${GREEN}✓ Language Server built${NC}"
fi

echo
echo -e "${YELLOW}Step 2: Installing npm dependencies${NC}"
cd editors/vscode
npm install --silent 2>/dev/null || npm install
echo -e "${GREEN}✓ Dependencies installed${NC}"

echo
echo -e "${YELLOW}Step 3: Publishing Language Server to extension${NC}"
npm run build-server 2>/dev/null
echo -e "${GREEN}✓ Server published${NC}"

echo
echo -e "${YELLOW}Step 4: Compiling TypeScript${NC}"
npm run compile
echo -e "${GREEN}✓ TypeScript compiled${NC}"

echo
echo -e "${YELLOW}Step 5: Running VS Code Integration Tests${NC}"
if [ -n "$TEST_SUITE" ]; then
    echo "Suite filter: $TEST_SUITE"
fi
echo "(This will download VS Code if needed and may take a minute...)"
echo

# @vscode/test-electron reuses editors/vscode/.vscode-test between runs. If a
# previous download was interrupted, the directory can look installed but miss
# VS Code's packaged node modules; launching then fails before tests start with
# ERR_MODULE_NOT_FOUND (for example @vscode/policy-watcher). Detect that state
# and force a clean re-download instead of letting the release gate fail on a
# corrupt cache.
for vscode_app in .vscode-test/vscode-*/Visual\ Studio\ Code.app; do
    [ -d "$vscode_app" ] || continue
    if [ ! -d "$vscode_app/Contents/Resources/app/node_modules/@vscode/policy-watcher" ]; then
        install_dir="$(dirname "$vscode_app")"
        echo -e "${YELLOW}Removing incomplete VS Code test install: $install_dir${NC}"
        rm -rf "$install_dir"
    fi
done

npm test

echo
echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}VS Code Integration Tests PASSED! ✓${NC}"
echo -e "${GREEN}=======================================${NC}"
