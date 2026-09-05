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

vscode_last_summary_count() {
    local output="$1"
    local label="$2"
    local summary

    summary="$(grep -Eo "[0-9]+ $label" "$output" 2>/dev/null | tail -1 || true)"
    if [ -z "$summary" ]; then
        echo 0
        return
    fi

    echo "${summary%% *}"
}

vscode_passing_count_from_file() {
    vscode_last_summary_count "$1" "passing"
}

vscode_failing_count_from_file() {
    vscode_last_summary_count "$1" "failing"
}

vscode_output_has_failures() {
    local output="$1"
    local failing_count

    failing_count="$(vscode_failing_count_from_file "$output")"
    [ "$failing_count" -gt 0 ] || grep -Eq '✗' "$output"
}

run_vscode_harness_self_test() {
    local output
    output="$(mktemp)"

    printf '  0 passing (3ms)\n' > "$output"
    if [ "$(vscode_passing_count_from_file "$output")" -ne 0 ]; then
        echo "Expected 0 passing to parse as zero tests"
        rm -f "$output"
        return 1
    fi

    printf '  12 passing (3s)\n' > "$output"
    if [ "$(vscode_passing_count_from_file "$output")" -ne 12 ]; then
        echo "Expected positive passing count to parse correctly"
        rm -f "$output"
        return 1
    fi

    printf '  1 failing\n' > "$output"
    if ! vscode_output_has_failures "$output"; then
        echo "Expected positive failing count to be treated as a failure"
        rm -f "$output"
        return 1
    fi

    printf '  0 failing\n' > "$output"
    if vscode_output_has_failures "$output"; then
        echo "Expected zero failing count not to be treated as a failure"
        rm -f "$output"
        return 1
    fi

    rm -f "$output"
    echo "VS Code integration harness self-test passed"
}

if [ "${NSHARP_VSCODE_HARNESS_SELF_TEST:-}" = "1" ]; then
    run_vscode_harness_self_test
    exit $?
fi

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
DEPENDENCY_HASH="$(node - <<'NODE'
const fs = require('fs');
const crypto = require('crypto');
const hash = crypto.createHash('sha256');
for (const file of ['package.json', 'package-lock.json']) {
  if (fs.existsSync(file)) {
    hash.update(file);
    hash.update('\0');
    hash.update(fs.readFileSync(file));
    hash.update('\0');
  }
}
process.stdout.write(hash.digest('hex'));
NODE
)"
DEPENDENCY_MARKER="node_modules/.nsharp-dependencies.sha256"
if [ -f "$DEPENDENCY_MARKER" ] \
    && [ -f "node_modules/typescript/lib/tsc.js" ] \
    && [ -d "node_modules/@vscode/test-electron" ] \
    && [ "$(cat "$DEPENDENCY_MARKER")" = "$DEPENDENCY_HASH" ]; then
    echo -e "${GREEN}✓ Dependencies already installed${NC}"
else
    npm install --silent 2>/dev/null || npm install
    printf '%s\n' "$DEPENDENCY_HASH" > "$DEPENDENCY_MARKER"
    echo -e "${GREEN}✓ Dependencies installed${NC}"
fi

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

VSCODE_TEST_CACHE="${NSHARP_VSCODE_TEST_CACHE:-.vscode-test}"

preseed_vscode_test_cache_from_machine_install() {
    local code_path
    code_path="$(command -v code 2>/dev/null || true)"
    [ -n "$code_path" ] || return 0

    local resolved_code_path
    resolved_code_path="$(python3 - "$code_path" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
)"

    local app_path=""
    case "$resolved_code_path" in
        */Visual\ Studio\ Code.app/Contents/Resources/app/bin/code)
            app_path="${resolved_code_path%/Contents/Resources/app/bin/code}"
            ;;
    esac

    [ -n "$app_path" ] && [ -d "$app_path" ] || return 0

    local version
    version="$(code --version 2>/dev/null | head -1 || true)"
    [ -n "$version" ] || return 0

    local arch
    arch="$(uname -m)"
    case "$arch" in
        arm64|aarch64) arch="arm64" ;;
        x86_64|amd64) arch="x64" ;;
        *) return 0 ;;
    esac

    local platform
    case "$(uname -s)" in
        Darwin) platform="darwin-$arch" ;;
        *) return 0 ;;
    esac

    local install_dir="$VSCODE_TEST_CACHE/vscode-$platform-$version"
    local cached_app="$install_dir/Visual Studio Code.app"
    local complete_file="$install_dir/is-complete"

    if [ -f "$complete_file" ] && [ -d "$cached_app" ]; then
        return 0
    fi

    rm -rf "$install_dir"
    mkdir -p "$install_dir"
    if ! cp -cR "$app_path" "$cached_app" 2>/dev/null; then
        cp -R "$app_path" "$cached_app"
    fi
    touch "$complete_file"
    echo -e "${GREEN}✓ Seeded machine VS Code $version into test-electron cache${NC}"
}

preseed_vscode_test_cache_from_machine_install

if [ -z "${NSHARP_VSCODE_TEST_VERSION:-}" ]; then
    NSHARP_VSCODE_TEST_VERSION="$(code --version 2>/dev/null | head -1 || true)"
fi
if [ -n "${NSHARP_VSCODE_TEST_VERSION:-}" ]; then
    export NSHARP_VSCODE_TEST_VERSION
    echo -e "${GREEN}✓ Using VS Code $NSHARP_VSCODE_TEST_VERSION for test-electron${NC}"
fi

# @vscode/test-electron reuses editors/vscode/.vscode-test between runs. If a
# previous download was interrupted, the directory can look installed but miss
# VS Code's packaged node modules; launching then fails before tests start with
# ERR_MODULE_NOT_FOUND (for example @vscode/policy-watcher). Detect that state
# and force a clean re-download instead of letting the release gate fail on a
# corrupt cache.
for vscode_app in "$VSCODE_TEST_CACHE"/vscode-*/Visual\ Studio\ Code.app; do
    [ -d "$vscode_app" ] || continue
    if [ ! -d "$vscode_app/Contents/Resources/app/node_modules/@vscode/policy-watcher" ]; then
        install_dir="$(dirname "$vscode_app")"
        echo -e "${YELLOW}Removing incomplete VS Code test install: $install_dir${NC}"
        rm -rf "$install_dir"
    fi
done

terminate_process_tree() {
    local pid="$1"
    local signal="${2:-TERM}"
    local child

    for child in $(pgrep -P "$pid" 2>/dev/null || true); do
        terminate_process_tree "$child" "$signal"
    done

    kill "-$signal" "$pid" 2>/dev/null || true
}

run_vscode_tests() {
    local output
    output="$(mktemp)"
    node ./out/test/runTest.js > "$output" 2>&1 &
    local node_pid=$!
    local passed_seen=0
    local host_exit_seen=0
    local passed_at=0
    local passing_count=0

    while kill -0 "$node_pid" 2>/dev/null; do
        passing_count="$(vscode_passing_count_from_file "$output")"
        if [ "$passed_seen" = "0" ] && [ "$passing_count" -gt 0 ]; then
            passed_seen=1
            passed_at="$(date +%s)"
        fi

        if [ "$host_exit_seen" = "0" ] && grep -Eq 'Extension host with pid [0-9]+ exited with code: 0' "$output"; then
            host_exit_seen=1
        fi

        # NEVER take the success early-return if mocha reported any failures (H9). A run can print
        # both "N passing" and "M failing"; without this guard the early-return reported success and
        # bypassed mocha's non-zero exit code. On any failing line, fall through to the real
        # wait/status below so the failure propagates.
        if vscode_output_has_failures "$output"; then
            passed_seen=0
        fi

        if [ "$passed_seen" = "1" ] && [ "$host_exit_seen" = "1" ]; then
            local now
            now="$(date +%s)"
            if [ $((now - passed_at)) -ge 10 ]; then
                cat "$output"
                echo "VS Code tests passed (no failures detected); closing lingering Electron process tree."
                terminate_process_tree "$node_pid" TERM
                sleep 2
                if kill -0 "$node_pid" 2>/dev/null; then
                    terminate_process_tree "$node_pid" KILL
                fi
                wait "$node_pid" 2>/dev/null || true
                rm -f "$output"
                return 0
            fi
        fi

        sleep 1
    done

    local status
    if wait "$node_pid"; then
        status=0
    else
        status=$?
    fi
    passing_count="$(vscode_passing_count_from_file "$output")"
    cat "$output"
    if [ "$status" = "0" ] && [ "$passing_count" -eq 0 ]; then
        echo -e "${RED}Error: VS Code integration harness ran 0 tests${NC}"
        status=1
    fi
    rm -f "$output"
    return "$status"
}

run_vscode_tests

echo
echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}VS Code Integration Tests PASSED! ✓${NC}"
echo -e "${GREEN}=======================================${NC}"
