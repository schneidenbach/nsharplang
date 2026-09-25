#!/usr/bin/env bash
# Quick reload script for VS Code extension development. Every step is PROVEN rather than assumed:
# the kill waits for VS Code to exit, and the server named at the end is this window's own child.

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
VSIX_FILE="$(nsharp_latest_vscode_vsix)"; echo "   Created: $VSIX_FILE"

echo "3. Installing extension..."
nsharp_run code --install-extension "$VSIX_FILE" --force

echo "4. Opening sample project: $SAMPLE_PROJECT"
nsharp_run code "$SAMPLE_PROJECT"

# THE PROOF LINE. `pgrep -f 'LanguageServer.dll' | head -n 1` proved nothing: `head -n 1` takes the LOWEST pid, which is a stale orphan
# (every orphan has ppid 1), and `-n` alone names the .NET Roslyn server, whose own command line carries the ERE in an
# `--extension .../Microsoft.VisualStudio.Copilot.Roslyn.LanguageServer.dll` argument. The newest plugin host's CHILD cannot be either.
echo "5. Language server under test:"
for _ in $(seq 0 60); do
    HELPER_PID="$(pgrep -n -f 'Code Helper \(Plugin\)' || true)"
    SERVER_PID="$(pgrep -n -P "$HELPER_PID" -f 'server/LanguageServer\.dll --stdio' 2>/dev/null || true)"
    if [[ -n "$SERVER_PID" ]]; then break; fi
    sleep 1
done
if [[ -n "$SERVER_PID" ]]; then
    echo "   LanguageServer.dll pid $SERVER_PID (child of plugin host $HELPER_PID) started $(ps -o lstart= -p "$SERVER_PID" | tr -s ' ')"
elif [[ -z "$HELPER_PID" ]]; then
    echo "   No VS Code plugin host is running — cannot name the server." >&2
else
    echo "   No server under plugin host $HELPER_PID after 60s — open a .nl file to activate the extension." >&2
fi

printf '%s\n' "" "Done. Tips:" "   - Open a .nl file to activate the extension" "   - F1 > 'Developer: Reload Window' reloads it" "   - Output panel > 'N# Language Server' for logs" ""
