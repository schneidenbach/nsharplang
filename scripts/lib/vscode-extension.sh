#!/usr/bin/env bash

if [[ -z "${NSHARP_REPO_ROOT:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
fi

NSHARP_VSCODE_EXT_DIR="${NSHARP_VSCODE_EXT_DIR:-$NSHARP_REPO_ROOT/editors/vscode}"

nsharp_vscode_package_version() {
    nsharp_read_package_json_version "$NSHARP_VSCODE_EXT_DIR/package.json"
}

nsharp_ensure_vscode_dependencies() {
    local tsc_path="$NSHARP_VSCODE_EXT_DIR/node_modules/.bin/tsc"

    if [[ -d "$NSHARP_VSCODE_EXT_DIR/node_modules" && -x "$tsc_path" ]]; then
        return
    fi

    nsharp_log "Installing VS Code extension dependencies"
    nsharp_run_in_dir "$NSHARP_VSCODE_EXT_DIR" npm install
}

nsharp_latest_vscode_vsix() {
    local latest
    latest="$(ls -t "$NSHARP_VSCODE_EXT_DIR"/nsharp-*.vsix 2>/dev/null | head -n 1 || true)"
    if [[ -z "$latest" ]]; then
        return 1
    fi
    printf '%s\n' "$latest"
}

nsharp_build_vscode_extension_package() {
    nsharp_ensure_vscode_dependencies
    nsharp_run_in_dir "$NSHARP_VSCODE_EXT_DIR" npm run build-server
    nsharp_run_in_dir "$NSHARP_VSCODE_EXT_DIR" npm run compile
    nsharp_run_in_dir "$NSHARP_VSCODE_EXT_DIR" npx vsce package --allow-star-activation
}

nsharp_kill_vscode() {
    if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
        killall "Visual Studio Code" 2>/dev/null || killall "Code" 2>/dev/null || true
    else
        echo '+ killall "Visual Studio Code" || killall "Code" || true'
    fi
}
