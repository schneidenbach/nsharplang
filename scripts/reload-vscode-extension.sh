#!/usr/bin/env bash
# Quick reload script for VS Code extension development. Every step is PROVEN rather than assumed:
# the kill waits for VS Code to actually exit, and the new language server's start time is printed
# so a verification record can name the build it looked at.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/vscode-extension.sh"

SAMPLE_PROJECT="${NSHARP_VSCODE_SAMPLE_PROJECT:-$NSHARP_REPO_ROOT/examples/01-hello-world}"

for required in dotnet npm npx code; do nsharp_require_command "$required"; done

printf '%s\n' "N# VS Code Extension Quick Reload" "=================================" ""
echo "1. Killing VS Code and waiting for it to exit..."
nsharp_kill_vscode

echo "2. Building language server and packaging VSIX..."
nsharp_build_vscode_extension_package
VSIX_FILE="$(nsharp_latest_vscode_vsix)"
echo "   Created: $VSIX_FILE"

echo "3. Installing extension..."
nsharp_run code --install-extension "$VSIX_FILE" --force

echo "4. Opening sample project: $SAMPLE_PROJECT"
nsharp_run code "$SAMPLE_PROJECT"

# THE PROOF LINE. A record that says which VSIX is on disk says nothing about which build served the
# window; a server process that started after this install does.
echo "5. Language server under test:"
SERVER_PID=""
for _ in $(seq 0 60); do
    SERVER_PID="$(pgrep -f 'LanguageServer.dll' | head -n 1 || true)"
    if [[ -n "$SERVER_PID" ]]; then break; fi
    sleep 1
done
if [[ -n "$SERVER_PID" ]]; then
    echo "   LanguageServer.dll pid $SERVER_PID started $(ps -o lstart= -p "$SERVER_PID" | tr -s ' ')"
else
    echo "   No LanguageServer.dll process after 60s — open a .nl file to activate the extension." >&2
fi

printf '%s\n' "" "Done. Tips:" "   - Open a .nl file to activate the extension" "   - F1 > 'Developer: Reload Window' reloads it" "   - Output panel > 'N# Language Server' for logs" ""
