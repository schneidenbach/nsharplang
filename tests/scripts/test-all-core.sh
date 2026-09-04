#!/bin/bash
set -e

echo "========================================="
echo "N# Comprehensive Test Suite"
echo "========================================="
echo

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

FAILURES=0
TIMING_PRINTED=0
TOTAL_START_TIME=$(date +%s)
CURRENT_SECTION_NAME=""
CURRENT_SECTION_START_TIME=0
STAGE_NAMES=()
STAGE_SECONDS=()

get_cpu_count() {
    if command -v getconf >/dev/null 2>&1; then
        getconf _NPROCESSORS_ONLN 2>/dev/null && return
    fi
    if command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu 2>/dev/null && return
    fi
    echo 4
}

DEFAULT_JOBS=$(get_cpu_count)
if ! [[ "$DEFAULT_JOBS" =~ ^[0-9]+$ ]] || [ "$DEFAULT_JOBS" -lt 1 ]; then
    DEFAULT_JOBS=4
fi
if [ "$DEFAULT_JOBS" -gt 8 ]; then
    DEFAULT_JOBS=8
fi
MAX_JOBS=${TEST_ALL_JOBS:-$DEFAULT_JOBS}
if ! [[ "$MAX_JOBS" =~ ^[0-9]+$ ]] || [ "$MAX_JOBS" -lt 1 ]; then
    MAX_JOBS=1
fi

is_enabled() {
    case "$1" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

if [ -z "${NLC_MSBUILD_SINGLE_NODE+x}" ]; then
    if [ -n "${CODEX_SANDBOX:-}" ]; then
        NLC_MSBUILD_SINGLE_NODE=1
    else
        NLC_MSBUILD_SINGLE_NODE=0
    fi
fi

DOTNET_STABLE_FLAGS="--disable-build-servers -nr:false"
if is_enabled "$NLC_MSBUILD_SINGLE_NODE"; then
    # Some sandboxes allow file writes but deny IPC socket binds; force the in-process MSBuild path.
    DOTNET_STABLE_FLAGS="$DOTNET_STABLE_FLAGS -m:1 -p:BuildInParallel=false"
    export DOTNET_CLI_USE_MSBUILD_SERVER=0
    export DOTNET_CLI_RUN_MSBUILD_OUTOFPROC=0
    export DOTNET_CLI_USE_MSBUILDNOINPROCNODE=0
    export MSBUILDDISABLENODEREUSE=1
    unset MSBUILDNOINPROCNODE
fi

CLEAN_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN_BUILD=1 ;;
    esac
done

section() {
    record_section_duration
    CURRENT_SECTION_NAME="$1"
    CURRENT_SECTION_START_TIME=$(date +%s)
    echo -e "\n${YELLOW}>>> $1${NC}\n========================================="
}

record_section_duration() {
    if [ -z "$CURRENT_SECTION_NAME" ]; then
        return
    fi

    local section_end
    section_end=$(date +%s)
    STAGE_NAMES+=("$CURRENT_SECTION_NAME")
    STAGE_SECONDS+=("$((section_end - CURRENT_SECTION_START_TIME))")
    CURRENT_SECTION_NAME=""
    CURRENT_SECTION_START_TIME=0
}

format_duration() {
    local seconds="$1"
    printf '%dm %02ds' "$((seconds / 60))" "$((seconds % 60))"
}

print_timing_summary() {
    if [ "$TIMING_PRINTED" = "1" ]; then
        return
    fi

    record_section_duration
    TIMING_PRINTED=1

    local total_end
    total_end=$(date +%s)
    local total_seconds=$((total_end - TOTAL_START_TIME))

    echo -e "\n${YELLOW}>>> Timing Summary${NC}\n========================================="
    local i
    for ((i = 0; i < ${#STAGE_NAMES[@]}; i++)); do
        printf '  %-46s %s\n' "${STAGE_NAMES[$i]}" "$(format_duration "${STAGE_SECONDS[$i]}")"
    done
    printf '  %-46s %s\n' "Total" "$(format_duration "$total_seconds")"
}

trap print_timing_summary EXIT

handle_error() {
    echo -e "${RED}✗ FAILED: $1${NC}"
    FAILURES=$((FAILURES + 1))
}

handle_success() {
    echo -e "${GREEN}✓ PASSED: $1${NC}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
REPO_ROOT=$(pwd)
CLI_DLL="$REPO_ROOT/src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll"
LOCAL_FEED="$HOME/.nsharp/packages"
NUGET_PACKAGE_CACHE="${NUGET_PACKAGES:-$HOME/.nuget/packages}"

# ---- Validated per-step input caching --------------------------------------
# A step may be skipped only when its ENTIRE input set is byte-identical to a set that previously PASSED it on this
# toolchain/platform (markers written only on success, keyed by content hash). This is what lets docs- or tests-only
# commits skip identical-input example steps. The wrapper and its fresh/clean flags control skipping; direct core runs never skip.
STEP_CACHE_ROOT="${NSHARP_TEST_STEP_CACHE_ROOT:-}"

step_cache_enabled() {
    [ -n "$STEP_CACHE_ROOT" ] && ! is_enabled "${NSHARP_TEST_STEP_CACHE_OFF:-0}"
}

step_cache_hit() {
    step_cache_enabled || return 1
    [ -n "$2" ] && [ -f "$STEP_CACHE_ROOT/$1/$2.json" ]
}

step_cache_store() {
    step_cache_enabled || return 0
    [ -n "$2" ] || return 0
    mkdir -p "$STEP_CACHE_ROOT/$1"
    printf '{"schemaVersion":1,"step":"%s","inputsHash":"%s","completedAtUtc":"%s"}\n' \
        "$1" "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STEP_CACHE_ROOT/$1/$2.json"
}

step_skip_banner() {
    printf 'SKIPPED: validated step cache hit (key %s).\nThis exact input set previously passed this step on this toolchain.\nForce every step with ./scripts/test-all.sh --fresh (or --release).\n' "${2:0:16}"
}

UNIT_INPUTS_HASH=""
EXAMPLES_INPUTS_HASH=""
BENCH_INPUTS_HASH=""
if step_cache_enabled; then
    STEP_HASH_OUTPUT="$(python3 - "$REPO_ROOT" <<'PY'
import hashlib, json, os, platform, shutil, subprocess, sys

root = os.path.realpath(sys.argv[1])
SKIP_DIRS = {".git", "bin", "obj", "node_modules", ".vscode-test", ".context",
             "artifacts", "server", "out", "nsharp", "TestResults"}

# Path prefixes per input set ('/'-normalized, relative to repo root). Sets are deliberately over-inclusive:
# the gate scripts and shared build files are in every set, and src/ (the compiler itself) invalidates
# everything. UNIT must cover docs/ and website/docs/ wholesale because unit tests golden-compare and
# parity-check repo documentation (cli-reference.md, diagnostic-clusters sample, systems audit, ...);
# GateStepInputSetGuardTests enforces this. BENCH is the systems throughput gate: the runner and kernels.
COMMON = ("scripts/", "tests/scripts/", "global.json", "Directory.Build.props",
          "Directory.Build.targets", "NuGet.config", "NSharpLang.sln")
SETS = {
    "UNIT": COMMON + ("src/", "tests/", "examples/", "templates/",
                       "docs/", "website/docs/",
                       "editors/vscode/test/suite/"),
    "EXAMPLES": COMMON + ("src/", "examples/", "templates/", "tests/fixtures/",
                           "tests/native/", "tests/scripts/"),
    "BENCH": COMMON + ("src/", "benchmarks/native-comparison/"),
}

# Behavior-changing environment must be part of every step key, mirroring env_names in the whole-gate
# signature in tests/scripts/test-all.sh (keep the two lists in sync; GateStepInputSetGuardTests
# enforces it). A marker stored under one environment must never satisfy a run under another.
ENV_NAMES = ("VSCODE_TESTS", "TEST_SUITE", "TEST_GREP", "TEST_ALL_JOBS", "SYSTEMS_BENCH",
             "NLC_MSBUILD_SINGLE_NODE", "DOTNET_ROOT", "NSHARP_EXPERIMENTAL_SOA")

def run_text(command):
    try:
        completed = subprocess.run(command, stdout=subprocess.PIPE,
                                   stderr=subprocess.DEVNULL, text=True, check=False)
    except FileNotFoundError:
        return None
    return completed.stdout.strip() if completed.returncode == 0 else None

def ilverify_versions():
    # The templates-examples-ilverify step promises a same-toolchain skip, so the installed dotnet-ilverify version
    # salts every step key. Resolve the apphost shim like scripts/ilverify.sh does (PATH first, then the default tool
    # dir) and read version names from the tool store; invoking ilverify --version would need DOTNET_ROOT wiring we avoid.
    exe = shutil.which("ilverify")
    if exe is None:
        fallback = os.path.expanduser("~/.dotnet/tools/ilverify")
        exe = fallback if os.access(fallback, os.X_OK) else None
    if exe is None:
        return None
    store = os.path.join(os.path.dirname(os.path.realpath(exe)),
                         ".store", "dotnet-ilverify")
    try:
        versions = sorted(entry for entry in os.listdir(store)
                          if os.path.isdir(os.path.join(store, entry)))
    except OSError:
        return None
    return versions or None

hashes = {name: hashlib.sha256() for name in SETS}
for current, dirs, files in os.walk(root):
    dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
    for name in sorted(files):
        path = os.path.join(current, name)
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        matched = [s for s, prefixes in SETS.items()
                   if any(rel == p or rel.startswith(p) for p in prefixes)]
        if not matched:
            continue
        try:
            with open(path, "rb") as handle:
                content = handle.read()
        except OSError:
            continue
        for s in matched:
            hashes[s].update(rel.encode("utf-8", "surrogateescape"))
            hashes[s].update(b"\0")
            hashes[s].update(content)
            hashes[s].update(b"\0")

salt = json.dumps({
    "schemaVersion": 2,
    "dotnet": run_text(["dotnet", "--version"]),
    "ilverify": ilverify_versions(),
    "environment": {name: os.environ.get(name) for name in ENV_NAMES
                    if os.environ.get(name) is not None},
    "platform": [platform.system(), platform.machine()],
}, sort_keys=True)
for name, digest in hashes.items():
    digest.update(salt.encode("utf-8"))
    print(f"{name}={digest.hexdigest()}")
PY
)" || STEP_HASH_OUTPUT=""
    UNIT_INPUTS_HASH="$(printf '%s\n' "$STEP_HASH_OUTPUT" | sed -n 's/^UNIT=//p')"
    EXAMPLES_INPUTS_HASH="$(printf '%s\n' "$STEP_HASH_OUTPUT" | sed -n 's/^EXAMPLES=//p')"
    BENCH_INPUTS_HASH="$(printf '%s\n' "$STEP_HASH_OUTPUT" | sed -n 's/^BENCH=//p')"
fi
# -----------------------------------------------------------------------------

remove_nuget_package_cache() {
    local package_id="$1"
    local normalized_id
    normalized_id=$(printf '%s' "$package_id" | tr '[:upper:]' '[:lower:]')
    rm -rf "$NUGET_PACKAGE_CACHE/$normalized_id"
}

section "Step 1: Clean Previous Build Artifacts"
if [ "$CLEAN_BUILD" = "1" ]; then
    echo "Cleaning bin/ and obj/ directories..."
    find . \( -type d -name "bin" -o -type d -name "obj" -o -type d -name "nsharp" \) | while read dir; do
        if [[ "$dir" == "./node_modules"* ]] || [[ "$dir" == *".vscode-test"* ]] || [[ "$dir" == *"node_modules"* ]]; then
            continue
        fi
        rm -rf "$dir"
    done
    handle_success "Cleaned build artifacts"
else
    echo "Incremental build (use --clean for full clean)"
    handle_success "Skipped clean (incremental)"
fi

section "Step 2: Build N# Compiler"
echo "Building compiler, CLI, and the playground a native test project takes as a dll: dependency..."
if dotnet build $DOTNET_STABLE_FLAGS src/NSharpLang.Cli/Cli.csproj -v q \
    && dotnet build $DOTNET_STABLE_FLAGS src/NSharpLang.Playground/NSharpLang.Playground.csproj -v q; then
    handle_success "Compiler built"
else
    handle_error "Compiler build"
fi

section "Step 2b: Format Contract Gate"
echo "Checking canonical formatting for examples, templates, fixtures, and the compiler's own N# sources..."
FORMAT_OUTPUT=$(mktemp)
# A brace group's exit status is only its LAST command's: accumulate every exit code instead, so ANY non-zero check fails the gate.
format_rc=0
{
    dotnet "$CLI_DLL" format --project examples --check || format_rc=1
    dotnet "$CLI_DLL" format --project templates --check || format_rc=1
    dotnet "$CLI_DLL" format --project tests/fixtures/issue-tracker --check || format_rc=1
    dotnet "$CLI_DLL" format --project src/NSharpLang.Compiler.BootstrapServices --check || format_rc=1
} > "$FORMAT_OUTPUT" 2>&1
cat "$FORMAT_OUTPUT"
if [ "$format_rc" -eq 0 ]; then
    handle_success "Formatting gate"
else
    handle_error "Formatting gate"
fi
rm -f "$FORMAT_OUTPUT"

section "Step 3: Run Unit Tests"
if step_cache_hit "unit-tests" "$UNIT_INPUTS_HASH"; then
    step_skip_banner "unit-tests" "$UNIT_INPUTS_HASH"
    handle_success "Unit tests (validated step cache)"
else
    echo "Running all unit tests..."
    dotnet restore $DOTNET_STABLE_FLAGS tests/Tests.csproj --force-evaluate -v q
    TEST_OUTPUT=$(mktemp)
    if dotnet test $DOTNET_STABLE_FLAGS tests/Tests.csproj -v q --logger 'console;verbosity=minimal' --nologo --no-restore > "$TEST_OUTPUT" 2>&1; then
        TEST_RESULT=$(grep -E "Passed!|Failed!" "$TEST_OUTPUT" || echo "")
        if [ -n "$TEST_RESULT" ]; then
            echo "$TEST_RESULT"
        fi
        handle_success "Unit tests passed"
        step_cache_store "unit-tests" "$UNIT_INPUTS_HASH"
    else
        cat "$TEST_OUTPUT"
        handle_error "Unit tests"
    fi
    rm -f "$TEST_OUTPUT"
fi

section "Step 3a: Run Native N# Tests"
if step_cache_hit "native-nsharp-tests" "$UNIT_INPUTS_HASH"; then
    step_skip_banner "native-nsharp-tests" "$UNIT_INPUTS_HASH"
    handle_success "Native N# tests (validated step cache)"
else
    echo "Running the gated compiler-service and product .tests.nl estate..."
    NATIVE_STEP_OK=1
    BOOTSTRAP_TEST_PROJECT="src/NSharpLang.Compiler.BootstrapServices/NSharpLang.Compiler.BootstrapServices.csproj"
    BOOTSTRAP_TEST_OUTPUT=$(mktemp)
    if dotnet restore $DOTNET_STABLE_FLAGS "$BOOTSTRAP_TEST_PROJECT" \
            -p:NSharpExcludeTests=false --force-evaluate -v q \
        && dotnet test $DOTNET_STABLE_FLAGS "$BOOTSTRAP_TEST_PROJECT" \
            -p:NSharpExcludeTests=false --no-restore -v q --nologo \
            > "$BOOTSTRAP_TEST_OUTPUT" 2>&1 \
        && grep -Eq 'Passed:[[:space:]]*[1-9][0-9]*' "$BOOTSTRAP_TEST_OUTPUT" \
        && grep -Eq 'Failed:[[:space:]]*0([^0-9]|$)' "$BOOTSTRAP_TEST_OUTPUT" \
        && grep -Eq 'Total:[[:space:]]*[1-9][0-9]*' "$BOOTSTRAP_TEST_OUTPUT"; then
        grep -E "Passed!|Failed!" "$BOOTSTRAP_TEST_OUTPUT" || true
        handle_success "Native N# tests: compiler-service contracts"
    else
        cat "$BOOTSTRAP_TEST_OUTPUT"
        handle_error "Native N# tests: compiler-service contracts"
        NATIVE_STEP_OK=0
    fi
    rm -f "$BOOTSTRAP_TEST_OUTPUT"

    NATIVE_PROJECTS=$(
        while IFS= read -r native_project; do
            native_dir=$(dirname "$native_project")
            if find "$native_dir" -maxdepth 1 -name "*.tests.nl" -type f -print -quit | grep -q .; then
                printf '%s\n' "$native_project"
            fi
        done < <(find examples tests -name "project.yml" -type f 2>/dev/null | sort)
    )
    if [ -z "$NATIVE_PROJECTS" ]; then
        handle_error "Native N# tests (no projects found)"
        NATIVE_STEP_OK=0
    else
        while IFS= read -r native_project; do
            [ -n "$native_project" ] || continue
            native_dir=$(dirname "$native_project")
            echo
            echo "Testing native project: $native_dir"
            NATIVE_OUTPUT=$(mktemp)
            if dotnet "$CLI_DLL" test --project "$native_dir" --no-cache --json \
                    > "$NATIVE_OUTPUT" 2>&1 \
                && python3 - "$NATIVE_OUTPUT" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    payload = json.load(stream)

summary = payload.get("summary", {})
results = payload.get("results", [])
total = summary.get("total")
passed = summary.get("passed")
failed = summary.get("failed")
skipped = summary.get("skipped")

outcome_counts = {"passed": 0, "failed": 0, "skipped": 0}
results_are_valid = True
for result in (results if isinstance(results, list) else []):
    if not isinstance(result, dict) or result.get("outcome") not in outcome_counts:
        results_are_valid = False
        break
    outcome_counts[result["outcome"]] += 1

valid = (
    payload.get("schemaVersion") == 1
    and payload.get("command") == "test"
    and payload.get("ok") is True
    and type(total) is int
    and total > 0
    and isinstance(results, list)
    and len(results) == total
    and all(type(value) is int and value >= 0 for value in (passed, failed, skipped))
    and passed > 0
    and failed == 0
    and passed + failed + skipped == total
    and results_are_valid
    and outcome_counts["passed"] == passed
    and outcome_counts["failed"] == failed
    and outcome_counts["skipped"] == skipped
)
if not valid:
    raise SystemExit("native N# test JSON did not prove a nonempty successful run")

print(f"Passed: {passed}, Failed: {failed}, Skipped: {skipped}, Total: {total}")
PY
            then
                handle_success "Native N# tests: $native_dir"
            else
                cat "$NATIVE_OUTPUT"
                handle_error "Native N# tests: $native_dir"
                NATIVE_STEP_OK=0
            fi
            rm -f "$NATIVE_OUTPUT"
        done <<< "$NATIVE_PROJECTS"
    fi

    if [ "$NATIVE_STEP_OK" = "1" ]; then
        step_cache_store "native-nsharp-tests" "$UNIT_INPUTS_HASH"
    fi
fi

section "Step 3b: VS Code Integration Tests"
# Determine whether to run full VS Code tests or the bounded smoke suite. The full suite is
# intentionally opt-in: exhaustive, can exceed launch rehearsal budgets, and currently includes
# repo-wide/demonstration coverage tracked separately from this fast release gate. The default gate
# still verifies the extension loads and core LSP UX works; VSCODE_TESTS=full asks for the rest.
VSCODE_TEST_MODE="${VSCODE_TESTS:-auto}"

if [ "$VSCODE_TEST_MODE" = "auto" ]; then
    VSCODE_TEST_MODE="smoke"
    echo "Running bounded VS Code smoke tests for the release gate"
    echo "  (set VSCODE_TESTS=full to run the exhaustive VS Code suite)"
fi

if [ "$VSCODE_TEST_MODE" = "skip" ]; then
    echo -e "${YELLOW}Skipping VS Code tests (VSCODE_TESTS=skip)${NC}"
else
    # Check prerequisites
    VSCODE_SKIP_REASON=""
    if ! command -v code >/dev/null 2>&1; then
        VSCODE_SKIP_REASON="VS Code ('code' command) not found on PATH"
    fi
    if ! command -v node >/dev/null 2>&1; then
        VSCODE_SKIP_REASON="Node.js ('node' command) not found on PATH"
    fi

    if [ -n "$VSCODE_SKIP_REASON" ]; then
        echo -e "${RED}ERROR: $VSCODE_SKIP_REASON${NC}"
        echo "VS Code integration tests require:"
        echo "  - VS Code: https://code.visualstudio.com/"
        echo "  - Node.js: https://nodejs.org/"
        echo "  - 'code' CLI: VS Code > Cmd+Shift+P > 'Shell Command: Install code command'"
        handle_error "VS Code integration tests (missing prerequisites)"
    else
        VSCODE_OUTPUT=$(mktemp)
        if [ "$VSCODE_TEST_MODE" = "smoke" ]; then
            echo "Running VS Code smoke tests (extension, diagnostics, hover, completion)..."
            SKIP_LS_BUILD=1 TEST_SUITE="extension,diagnostics,hover,completion" \
                "$REPO_ROOT/tests/scripts/test-vscode-integration.sh" > "$VSCODE_OUTPUT" 2>&1 && VSCODE_OK=1 || VSCODE_OK=0
        else
            echo "Running full VS Code integration tests..."
            SKIP_LS_BUILD=1 "$REPO_ROOT/tests/scripts/test-vscode-integration.sh" > "$VSCODE_OUTPUT" 2>&1 && VSCODE_OK=1 || VSCODE_OK=0
        fi

        if [ "$VSCODE_OK" = "1" ]; then
            PASS_COUNT=$(grep -c '✔' "$VSCODE_OUTPUT" 2>/dev/null || echo "0")
            SKIP_COUNT=$(grep -c 'pending' "$VSCODE_OUTPUT" 2>/dev/null || echo "0")
            SUMMARY_LINE=$(grep -E '[0-9]+ passing' "$VSCODE_OUTPUT" || echo "")
            if [ -n "$SUMMARY_LINE" ]; then
                echo "  $SUMMARY_LINE"
            fi
            if [ "$SKIP_COUNT" != "0" ]; then
                echo "  ($SKIP_COUNT pending/skipped)"
            fi
            handle_success "VS Code integration tests ($VSCODE_TEST_MODE)"
        else
            cat "$VSCODE_OUTPUT"
            handle_error "VS Code integration tests ($VSCODE_TEST_MODE)"
        fi
        rm -f "$VSCODE_OUTPUT"
    fi
fi

section "Step 3c: Systems Throughput Gate"
if [ "${SYSTEMS_BENCH:-}" = "skip" ]; then
    echo -e "${YELLOW}Skipping systems throughput gate (SYSTEMS_BENCH=skip)${NC}"
elif step_cache_hit "systems-throughput" "$BENCH_INPUTS_HASH"; then
    step_skip_banner "systems-throughput" "$BENCH_INPUTS_HASH"
    handle_success "Systems throughput gate (validated step cache)"
elif dotnet "$CLI_DLL" build --project benchmarks/native-comparison/runner \
        && dotnet benchmarks/native-comparison/runner/bin/Debug/net10.0/NSharpLang.NativeComparisonRunner.dll gate --cli "$CLI_DLL" --repo "$REPO_ROOT"; then
    handle_success "Systems throughput gate"
    step_cache_store "systems-throughput" "$BENCH_INPUTS_HASH"
else
    handle_error "Systems throughput gate"
fi

section "Step 4: Pack and Install MSBuild SDK"
echo "Packing runtime to local NuGet feed..."
mkdir -p "$LOCAL_FEED"
rm -f "$LOCAL_FEED"/NSharpLang.Runtime.*.nupkg
if dotnet pack $DOTNET_STABLE_FLAGS src/NSharpLang.Runtime/NSharpLang.Runtime.csproj -o "$LOCAL_FEED" -v q; then
    handle_success "Runtime packed"
else
    handle_error "Runtime pack"
fi

echo "Packing SDK to local NuGet feed..."
mkdir -p "$LOCAL_FEED"
rm -f "$LOCAL_FEED"/NSharpLang.Sdk.*.nupkg
dotnet restore $DOTNET_STABLE_FLAGS src/NSharpLang.Sdk/NSharpLang.Sdk.csproj --force-evaluate -v q
dotnet build $DOTNET_STABLE_FLAGS src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj -v q
if dotnet pack $DOTNET_STABLE_FLAGS src/NSharpLang.Sdk/NSharpLang.Sdk.csproj -o "$LOCAL_FEED" -v q; then
    handle_success "SDK packed"
else
    handle_error "SDK pack"
fi

section "Step 4b: Pack N# Templates"
echo "Packing templates to local NuGet feed..."
rm -f "$LOCAL_FEED"/NSharpLang.Templates.*.nupkg
remove_nuget_package_cache NSharpLang.Templates
if dotnet pack $DOTNET_STABLE_FLAGS templates/NSharpLang.Templates.csproj -o "$LOCAL_FEED" -v q; then
    handle_success "Templates packed"
else
    handle_error "Templates pack"
fi

echo "Clearing N# NuGet package cache entries..."
remove_nuget_package_cache NSharpLang.Runtime
remove_nuget_package_cache NSharpLang.Sdk
remove_nuget_package_cache NSharpLang.Templates
handle_success "N# NuGet package cache entries cleared"

run_template_and_examples_steps() {
ILVERIFY_BUILT_DIRS_FILE=$(mktemp)
ILVERIFY_TEMP_DIRS=()
section "Step 5: Install dotnet new Template"
echo "Installing NSharpLang.Templates from local N# package cache..."
if dotnet new install NSharpLang.Templates --add-source "$LOCAL_FEED" --force > /dev/null 2>&1; then
    handle_success "Template package installed"
else
    handle_error "Template installation"
fi

TEMPLATE_LIST=$(dotnet new list nsharp 2>/dev/null || true)
if echo "$TEMPLATE_LIST" | grep -q "nsharp-console" && echo "$TEMPLATE_LIST" | grep -q "nsharp-webapi"; then
    handle_success "Console and Web API templates are listed"
else
    handle_error "Template listing"
fi

section "Step 6: Test Template Creation"
TEMP_DIR=$(mktemp -d)
echo "Creating test project in $TEMP_DIR..."
if dotnet new nsharp-console -o "$TEMP_DIR/TestConsoleApp" > /dev/null 2>&1; then
    handle_success "Template created test project"
else
    handle_error "Template creation"
fi

if dotnet new nsharp-webapi -o "$TEMP_DIR/TestWebApiApp" > /dev/null 2>&1; then
    handle_success "Web API template created test project"
else
    handle_error "Web API template creation"
fi

if [ -f "$TEMP_DIR/TestConsoleApp/project.yml" ]; then
    handle_success "project.yml exists"
else
    handle_error "project.yml missing"
fi

# Verify NO .csproj was created by template (csproj-free workflow)
CSPROJ_COUNT=$(find "$TEMP_DIR/TestConsoleApp" -name "*.csproj" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$CSPROJ_COUNT" = "0" ]; then
    handle_success "No .csproj in template output (csproj-free)"
else
    handle_error "Template should not create .csproj files"
fi

if [ -f "$TEMP_DIR/TestWebApiApp/project.yml" ]; then
    handle_success "webapi project.yml exists"
else
    handle_error "webapi project.yml missing"
fi

section "Step 7: Build Template-Generated Project (via nlc build)"
if [ -d "$TEMP_DIR/TestConsoleApp" ]; then
    cd "$TEMP_DIR/TestConsoleApp"
    echo "Building template-generated project with nlc build..."
    if dotnet "$CLI_DLL" build > /dev/null 2>&1; then
        handle_success "Template project builds (nlc build)"
    else
        handle_error "Template project build (nlc build)"
    fi
else
    handle_error "Template project missing"
fi

if [ -d "$TEMP_DIR/TestWebApiApp" ]; then
    cd "$TEMP_DIR/TestWebApiApp"
    echo "Building web API template-generated project with nlc build..."
    if dotnet "$CLI_DLL" build > /dev/null 2>&1; then
        handle_success "Web API template project builds (nlc build)"
    else
        handle_error "Web API template project build (nlc build)"
    fi
else
    handle_error "Web API template project missing"
fi

cd "$REPO_ROOT"
rm -rf "$TEMP_DIR"

section "Step 8: Build Example Projects (via nlc build)"
echo "Using up to $MAX_JOBS parallel workers for project verification..."

EXAMPLE_PROJECTS=$(find examples tests/fixtures -name "project.yml" -type f 2>/dev/null | sort)

if [ -z "$EXAMPLE_PROJECTS" ]; then
    echo "No example projects found with project.yml"
else
    # Pre-build one example to populate the NuGet cache, avoiding parallel restore races
    FIRST_PROJECT=$(echo "$EXAMPLE_PROJECTS" | head -1)
    FIRST_DIR=$(dirname "$FIRST_PROJECT")
    echo "Warming NuGet cache with $FIRST_DIR..."
    rm -rf "$FIRST_DIR/bin" "$FIRST_DIR/obj" "$FIRST_DIR/nsharp" 2>/dev/null || true
    (cd "$REPO_ROOT/$FIRST_DIR" && dotnet "$CLI_DLL" build > /dev/null 2>&1) || true

    EXAMPLE_RESULTS_DIR=$(mktemp -d)
    EXAMPLE_LIST="$EXAMPLE_RESULTS_DIR/items.txt"
    i=0
    printf '%s\n' "$EXAMPLE_PROJECTS" | while IFS= read -r project_file; do
        i=$((i + 1))
        printf '%04d|%s\n' "$i" "$project_file"
    done > "$EXAMPLE_LIST"

    xargs -P "$MAX_JOBS" -I{} bash -lc '
        entry="$1"
        repo_root="$2"
        results_dir="$3"
        cli_dll="$4"
        idx="${entry%%|*}"
        project_file="${entry#*|}"
        project_dir=$(dirname "$project_file")
        project_name=$(basename "$project_dir")
        log_file="$results_dir/$idx.log"
        result_file="$results_dir/$idx.result"
        work_dir="$repo_root/$project_dir"

        rm -rf "$work_dir/bin" "$work_dir/obj" "$work_dir/nsharp" 2>/dev/null || true

        if (cd "$work_dir" && dotnet "$cli_dll" build > "$log_file" 2>&1); then
            output_path=$(sed -n "s/^Output: //p" "$log_file" | tail -1)
            if [ -f "$output_path" ]; then
                printf "OK|%s|%s|%s\n" "$project_name" "$project_dir" "$output_path" > "$result_file"
            else
                printf "FAIL|%s|%s|%s\n" "$project_name" "$project_dir" "$log_file" > "$result_file"
            fi
        else
            printf "FAIL|%s|%s|%s\n" "$project_name" "$project_dir" "$log_file" > "$result_file"
        fi
    ' _ {} "$REPO_ROOT" "$EXAMPLE_RESULTS_DIR" "$CLI_DLL" < "$EXAMPLE_LIST"

    while IFS='|' read -r idx project_file; do
        result_file="$EXAMPLE_RESULTS_DIR/$idx.result"
        status=$(cut -d'|' -f1 "$result_file")
        project_name=$(cut -d'|' -f2 "$result_file")
        project_dir=$(cut -d'|' -f3 "$result_file")
        output_path=$(cut -d'|' -f4 "$result_file")

        echo
        echo "Building example: $project_name"
        echo "  Location: $project_dir"

        if [ "$status" = "OK" ]; then
            handle_success "Example: $project_name"
            printf '%s\n' "$output_path" >> "$ILVERIFY_BUILT_DIRS_FILE"
        else
            handle_error "Example: $project_name"
            echo "  Run manually: cd $project_dir && dotnet \"$CLI_DLL\" build"
        fi
    done < "$EXAMPLE_LIST"

    rm -rf "$EXAMPLE_RESULTS_DIR"
fi

section "Step 9: Build Single-File Examples (CLI-based)"

# Single files outside project directories are product surface; no failure allowlist.
LEGACY_EXAMPLES=""
while IFS= read -r nl_file; do
    dir=$(dirname "$nl_file")
    # Skip if this file or its parent dir has a project.yml
    [ -f "$dir/project.yml" ] && continue
    parent=$(dirname "$dir")
    [ -f "$parent/project.yml" ] && continue
    LEGACY_EXAMPLES="${LEGACY_EXAMPLES}${nl_file}
"
done < <(find examples -name "*.nl" -type f | sort)

if [ -z "$LEGACY_EXAMPLES" ]; then
    echo "No single-file examples found"
else
    echo "Building single-file examples with nlc build..."
    if [ ! -f "$CLI_DLL" ]; then
        handle_error "CLI build artifact missing"
    else
        LEGACY_RESULTS_DIR=$(mktemp -d)
        ILVERIFY_TEMP_DIRS+=("$LEGACY_RESULTS_DIR")
        LEGACY_LIST="$LEGACY_RESULTS_DIR/items.txt"
        i=0
        printf '%s' "$LEGACY_EXAMPLES" | while IFS= read -r nl_file; do
            [ -z "$nl_file" ] && continue
            i=$((i + 1))
            printf '%04d|%s\n' "$i" "$nl_file"
        done > "$LEGACY_LIST"

        xargs -P "$MAX_JOBS" -I{} bash -lc '
            entry="$1"
            repo_root="$2"
            results_dir="$3"
            cli_dll="$4"
            idx="${entry%%|*}"
            nl_file="${entry#*|}"
            example_name=$(basename "$nl_file" .nl)
            log_file="$results_dir/$idx.log"
            result_file="$results_dir/$idx.result"
            output_dir="$results_dir/$idx.out"
            mkdir -p "$output_dir"

            if dotnet "$cli_dll" build "$nl_file" --output "$output_dir" > "$log_file" 2>&1; then
                output_path=$(sed -n "s/^Output: //p" "$log_file" | tail -1)
                if [ -f "$output_path" ]; then
                    printf "OK|%s|%s|%s|%s\n" "$example_name" "$nl_file" "$output_dir" "$output_path" > "$result_file"
                else
                    printf "FAIL|%s|%s\n" "$example_name" "$nl_file" > "$result_file"
                fi
            else
                printf "FAIL|%s|%s\n" "$example_name" "$nl_file" > "$result_file"
            fi
        ' _ {} "$REPO_ROOT" "$LEGACY_RESULTS_DIR" "$CLI_DLL" < "$LEGACY_LIST"

        while IFS='|' read -r idx nl_file; do
            result_file="$LEGACY_RESULTS_DIR/$idx.result"
            [ ! -f "$result_file" ] && continue
            status=$(cut -d'|' -f1 "$result_file")
            example_name=$(cut -d'|' -f2 "$result_file")
            example_path=$(cut -d'|' -f3 "$result_file")
            output_dir=$(cut -d'|' -f4 "$result_file")
            output_path=$(cut -d'|' -f5 "$result_file")

            echo
            echo "Building single-file example: $example_name"
            echo "  Location: $example_path"

            if [ "$status" = "OK" ]; then
                handle_success "Single-file example: $example_name"
                printf '%s\n' "$output_path" >> "$ILVERIFY_BUILT_DIRS_FILE"
            else
                handle_error "Single-file example: $example_name"
                echo "  Run manually: dotnet \"$CLI_DLL\" build \"$example_path\""
            fi
        done < "$LEGACY_LIST"
    fi
fi

section "Step 10: Check Examples (nlc check)"
echo "Running nlc check on all example directories..."
echo "This verifies the Language Server won't report false errors."

# Check each self-contained project; skip umbrella folders with no direct .nl files or project.yml —
# their child projects are checked separately, without allowlists that would mask bad import roots.
CHECK_DIRS=$(find examples -mindepth 1 -maxdepth 1 -type d | sort)
# Sub-projects in 12-multi-file-projects need individual checking
CHECK_DIRS="$CHECK_DIRS
$(find examples/12-multi-file-projects -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)"
# Sub-projects in 17-issue-tracker (backend has its own project.yml)
CHECK_DIRS="$CHECK_DIRS
$(find examples/17-issue-tracker -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)"
# Test fixture projects
CHECK_DIRS="$CHECK_DIRS
$(find tests/fixtures -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -v '\.golden' | sort)"

filter_check_dir() {
    local check_dir="$1"
    [ -z "$check_dir" ] && return 1
    [ -f "$check_dir/project.yml" ] && return 0
    find "$check_dir" -maxdepth 1 -name "*.nl" -type f 2>/dev/null | grep -q .
}

echo "Using up to $MAX_JOBS parallel workers for nlc check..."
CHECK_RESULTS_DIR=$(mktemp -d)
CHECK_LIST="$CHECK_RESULTS_DIR/items.txt"
i=0
while IFS= read -r check_dir; do
    filter_check_dir "$check_dir" || continue
    i=$((i + 1))
    printf '%04d|%s\n' "$i" "$check_dir"
done <<< "$CHECK_DIRS" > "$CHECK_LIST"

xargs -P "$MAX_JOBS" -I{} bash -lc '
    entry="$1"
    repo_root="$2"
    results_dir="$3"
    cli_dll="$4"
    idx="${entry%%|*}"
    check_dir="${entry#*|}"
    result_file="$results_dir/$idx.result"

    result=$(dotnet "$cli_dll" check "$check_dir/" 2>/dev/null || true)
    errors=$(echo "$result" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['\''summary'\'']['\''errors'\''])" 2>/dev/null || echo "?")
    dir_name=$(echo "$check_dir" | sed "s|examples/||")
    printf "%s|%s|%s\n" "$errors" "$dir_name" "$check_dir" > "$result_file"
' _ {} "$REPO_ROOT" "$CHECK_RESULTS_DIR" "$CLI_DLL" < "$CHECK_LIST"

CHECK_FAIL=0
while IFS='|' read -r idx check_dir_unused; do
    result_file="$CHECK_RESULTS_DIR/$idx.result"
    [ ! -f "$result_file" ] && continue
    errors=$(cut -d'|' -f1 "$result_file")
    dir_name=$(cut -d'|' -f2 "$result_file")

    if [ "$errors" = "0" ]; then
        echo -e "  ${GREEN}✓${NC} $dir_name"
    else
        echo -e "  ${RED}✗${NC} $dir_name ($errors errors)"
        CHECK_FAIL=1
    fi
done < "$CHECK_LIST"

rm -rf "$CHECK_RESULTS_DIR"

if [ "$CHECK_FAIL" = "0" ]; then
    handle_success "nlc check on examples"
else
    handle_error "nlc check on examples (unexpected errors found)"
fi

section "Step 10b: IL Verification Gate"
echo "Running ECMA-335 IL verification over emitted example/fixture and selected native assemblies..."
echo "(scripts/ilverify.sh is the single source of truth, shared with CI.)"
if command -v ilverify >/dev/null 2>&1 || [ -x "$HOME/.dotnet/tools/ilverify" ]; then
    ILVERIFY_OUTPUT=$(mktemp)
    if "$REPO_ROOT/scripts/ilverify.sh" --built-dirs-file "$ILVERIFY_BUILT_DIRS_FILE" --build-native-tests > "$ILVERIFY_OUTPUT" 2>&1; then
        tail -1 "$ILVERIFY_OUTPUT"
        handle_success "IL verification gate"
    else
        cat "$ILVERIFY_OUTPUT"
        handle_error "IL verification gate"
    fi
    rm -f "$ILVERIFY_OUTPUT"
else
    echo -e "${RED}ERROR: dotnet-ilverify is not installed.${NC}"
    echo "Install it with: dotnet tool install --global dotnet-ilverify"
    handle_error "IL verification gate (dotnet-ilverify not installed)"
fi

rm -f "$ILVERIFY_BUILT_DIRS_FILE"
for temp_dir in "${ILVERIFY_TEMP_DIRS[@]}"; do
    rm -rf "$temp_dir"
done

}

EXAMPLES_FAILURES_BEFORE=$FAILURES
if step_cache_hit "templates-examples-ilverify" "$EXAMPLES_INPUTS_HASH"; then
    section "Steps 5-10b: Templates, Examples, IL Verification"
    step_skip_banner "templates-examples-ilverify" "$EXAMPLES_INPUTS_HASH"
    handle_success "Templates + examples + IL verification (validated step cache)"
else
    run_template_and_examples_steps
    if [ "$FAILURES" -eq "$EXAMPLES_FAILURES_BEFORE" ]; then
        step_cache_store "templates-examples-ilverify" "$EXAMPLES_INPUTS_HASH"
    fi
fi

section "Step 11: Summary"
echo
print_timing_summary
echo
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}ALL TESTS PASSED! ✓${NC}"
    echo -e "${GREEN}=========================================${NC}"
    exit 0
else
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}FAILURES: $FAILURES${NC}"
    echo -e "${RED}=========================================${NC}"
    exit 1
fi
