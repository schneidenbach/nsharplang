#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/vscode-extension.sh"

usage() {
    cat <<'USAGE'
Usage: scripts/vscode-visual-scenario.sh <scenario> [--hold-seconds N] [--workspace DIR]

Scenarios: rename, hover, definition, references, diagnostics, completion, code-action

The test VS Code window stays open until N seconds elapse or its printed sentinel file is touched.
The workspace is copied to a disposable temporary directory before a scenario can edit it.
USAGE
}

if [[ $# -lt 1 || "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit $([[ $# -lt 1 ]] && echo 2 || echo 0)
fi

scenario="$1"
shift
hold_seconds=30
workspace_source="$NSHARP_REPO_ROOT/examples/17-issue-tracker"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hold-seconds)
            [[ $# -ge 2 ]] || { echo "Error: --hold-seconds requires a value." >&2; usage >&2; exit 2; }
            hold_seconds="$2"
            shift 2
            ;;
        --workspace)
            [[ $# -ge 2 ]] || { echo "Error: --workspace requires a directory." >&2; usage >&2; exit 2; }
            workspace_source="$2"
            shift 2
            ;;
        *)
            echo "Error: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$scenario" in
    rename|hover|definition|references|diagnostics|completion|code-action) ;;
    *) echo "Error: unknown visual scenario '$scenario'." >&2; usage >&2; exit 2 ;;
esac

if [[ ! "$hold_seconds" =~ ^[0-9]+$ ]]; then
    echo "Error: --hold-seconds must be a non-negative integer." >&2
    exit 2
fi
if [[ ! -d "$workspace_source" ]]; then
    echo "Error: workspace directory does not exist: $workspace_source" >&2
    exit 2
fi

workspace_source="$(cd "$workspace_source" && pwd)"
nsharp_require_command node
nsharp_require_command unzip
nsharp_require_command dotnet

cli_dll="$NSHARP_REPO_ROOT/src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll"
oracle_script="$NSHARP_REPO_ROOT/scripts/lib/vscode-visual-oracle.sh"
echo "Building the worktree CLI for independent scenario checks."
dotnet build --disable-build-servers -nr:false "$NSHARP_REPO_ROOT/src/NSharpLang.Cli/Cli.csproj" -c Debug -v q
if [[ ! -f "$cli_dll" ]]; then
    echo "Error: fresh CLI build did not produce $cli_dll." >&2
    exit 1
fi

task_tmp="$(mktemp -d "${TMPDIR:-/tmp}/nsharp-vscode-visual.XXXXXX")"
sentinel_path=""
cleanup() {
    if [[ -n "$sentinel_path" ]]; then rm -f "$sentinel_path"; fi
    rm -rf "$task_tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

workspace_copy="$task_tmp/workspace"
package_root="$task_tmp/extension-package"
mkdir -p "$workspace_copy" "$package_root"

echo "Copying scenario workspace into an isolated temporary directory."
node - "$workspace_source" "$workspace_copy" <<'NODE'
const fs = require('fs');
const path = require('path');
const source = path.resolve(process.argv[2]);
const destination = path.resolve(process.argv[3]);
const ignored = new Set(['.git', 'node_modules', 'bin', 'obj', '.vscode-test']);
fs.cpSync(source, destination, {
  recursive: true,
  filter(candidate) {
    const relative = path.relative(source, candidate);
    if (!relative) return true;
    return !relative.split(path.sep).some(part => ignored.has(part));
  }
});
NODE

echo "Building and packaging the N# VS Code extension from this worktree."
nsharp_build_vscode_extension_package
vsix_path="$(nsharp_latest_vscode_vsix)"
if [[ -z "$vsix_path" || ! -f "$vsix_path" ]]; then
    echo "Error: extension packaging did not produce an N# VSIX." >&2
    exit 1
fi
unzip -q "$vsix_path" -d "$package_root"
packaged_extension_path="$package_root/extension"
if [[ ! -f "$packaged_extension_path/package.json" ]]; then
    echo "Error: packaged VSIX did not contain extension/package.json." >&2
    exit 1
fi

report_dir="$NSHARP_REPO_ROOT/.context/vscode-visual-scenarios"
mkdir -p "$report_dir"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
report_path="$report_dir/$scenario-$run_id.json"
sentinel_path="$report_dir/hold-$scenario-$run_id.sentinel"
rm -f "$sentinel_path"

echo "Opening isolated test VS Code; its title and PID will be printed when the scenario passes."
echo "If you want to close it earlier, run: touch $sentinel_path"

cd "$NSHARP_VSCODE_EXT_DIR"
NSHARP_VSCODE_VISUAL_SCENARIO="$scenario" \
NSHARP_VSCODE_VISUAL_WORKSPACE="$workspace_copy" \
NSHARP_VSCODE_VISUAL_EXTENSION_PATH="$packaged_extension_path" \
NSHARP_VSCODE_VISUAL_REPORT_PATH="$report_path" \
NSHARP_VSCODE_VISUAL_SENTINEL="$sentinel_path" \
NSHARP_VSCODE_VISUAL_HOLD_SECONDS="$hold_seconds" \
NSHARP_VSCODE_VISUAL_CLI_DLL="$cli_dll" \
NSHARP_VSCODE_VISUAL_ORACLE="$oracle_script" \
node ./out/test/visual/runVisualScenario.js

echo "Visual scenario report: $report_path"
