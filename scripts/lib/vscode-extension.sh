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

# Ask VS Code to quit normally first so it can persist window state and hot-exit backups, including
# empty windows and Untitled editors. Force-quit only after the graceful-close deadline.
nsharp_kill_vscode() {
    if [[ "${DRY_RUN:-0}" -ne 0 ]]; then
        echo "+ osascript -e 'tell application \"Visual Studio Code\" to quit'"
        echo '+ wait up to 30s for VS Code to exit'
        echo '+ on timeout: WARNING, then killall "Visual Studio Code" or killall "Code"; wait for exit'
        return 0
    fi

    if ! pgrep -x Code >/dev/null 2>&1; then
        echo "   VS Code is not running."
        return 0
    fi

    if ! command -v osascript >/dev/null 2>&1; then
        echo "Error: osascript is required to request a graceful VS Code quit." >&2
        return 1
    fi

    osascript -e 'tell application "Visual Studio Code" to quit' || true
    local waited
    for waited in $(seq 0 30); do
        pgrep -x Code >/dev/null 2>&1 || { echo "   VS Code exited after ${waited}s."; return 0; }
        if [[ "$waited" -lt 30 ]]; then sleep 1; fi
    done

    echo "WARNING: VS Code did not exit within 30s after the graceful quit request. Force-closing it now; any unsaved work may be lost." >&2
    killall "Visual Studio Code" 2>/dev/null || killall "Code" 2>/dev/null || true
    for waited in $(seq 0 30); do
        pgrep -x Code >/dev/null 2>&1 || { echo "   VS Code exited after force-close."; return 0; }
        if [[ "$waited" -lt 30 ]]; then sleep 1; fi
    done
    echo "Error: VS Code is still running after the force-close timeout." >&2
    return 1
}

nsharp_relaunch_vscode_restoring_windows() {
    local -a launch_args=(
        --disable-updates
        --disable-telemetry
        --skip-welcome
        --skip-release-notes
    )

    if [[ "$(uname -s)" == "Darwin" ]]; then
        launch_args+=(--use-mock-keychain)
        nsharp_run open -a "Visual Studio Code" --args "${launch_args[@]}"
    else
        if [[ "$(uname -s)" == "Linux" ]]; then
            launch_args+=(--password-store=basic)
        fi
        nsharp_run code "${launch_args[@]}"
    fi
}

nsharp_open_vscode_sample_in_new_window() {
    local -a launch_args=(
        --disable-updates
        --disable-telemetry
        --skip-welcome
        --skip-release-notes
    )

    if [[ "$(uname -s)" == "Darwin" ]]; then
        launch_args+=(--use-mock-keychain)
    elif [[ "$(uname -s)" == "Linux" ]]; then
        launch_args+=(--password-store=basic)
    fi

    nsharp_run code "${launch_args[@]}" -n "$1"
}
