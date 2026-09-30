#!/usr/bin/env bash

if [[ -z "${NSHARP_REPO_ROOT:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
fi

NSHARP_VSCODE_EXT_DIR="${NSHARP_VSCODE_EXT_DIR:-$NSHARP_REPO_ROOT/editors/vscode}"

nsharp_vscode_package_version() {
    nsharp_read_package_json_version "$NSHARP_VSCODE_EXT_DIR/package.json"
}

nsharp_ensure_vscode_dependencies() {
    if [[ -d "$NSHARP_VSCODE_EXT_DIR/node_modules" && -x "$NSHARP_VSCODE_EXT_DIR/node_modules/.bin/tsc" ]]; then
        return
    fi
    nsharp_log "Installing VS Code extension dependencies"
    nsharp_run_in_dir "$NSHARP_VSCODE_EXT_DIR" npm install
}

nsharp_latest_vscode_vsix() {
    ls -t "$NSHARP_VSCODE_EXT_DIR"/nsharp-*.vsix 2>/dev/null | head -n 1 | grep .
}

nsharp_build_vscode_extension_package() {
    nsharp_ensure_vscode_dependencies
    nsharp_run_in_dir "$NSHARP_VSCODE_EXT_DIR" npm run build-server
    nsharp_run_in_dir "$NSHARP_VSCODE_EXT_DIR" npm run compile
    nsharp_run_in_dir "$NSHARP_VSCODE_EXT_DIR" npx vsce package --allow-star-activation
}

# THE KILL IS WAITED ON: `killall` cannot fail visibly, and on 2026-09-02 three consecutive reloads
# reported success while a self-updating VS Code kept running — the verification measured a stale build.
nsharp_kill_vscode() {
    [[ "${DRY_RUN:-0}" -eq 0 ]] || { echo '+ killall "Visual Studio Code" || killall "Code" || true (then wait for exit)'; return; }
    killall "Visual Studio Code" 2>/dev/null || killall "Code" 2>/dev/null || true
    local waited
    for waited in $(seq 0 30); do
        pgrep -x Code >/dev/null 2>&1 || { echo "   VS Code exited after ${waited}s."; return; }
        sleep 1
    done
    echo "Error: VS Code is still running after 30s — a pending self-update can hold it open. Quit it by hand and re-run." >&2
    return 1
}
