#!/bin/bash
set -e

echo "========================================="
echo "N# Comprehensive Test Suite"
echo "========================================="
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track failures
FAILURES=0

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
if [ "$DEFAULT_JOBS" -gt 4 ]; then
    DEFAULT_JOBS=4
fi
MAX_JOBS=${TEST_ALL_JOBS:-$DEFAULT_JOBS}
if ! [[ "$MAX_JOBS" =~ ^[0-9]+$ ]] || [ "$MAX_JOBS" -lt 1 ]; then
    MAX_JOBS=1
fi
DOTNET_STABLE_FLAGS="--disable-build-servers"

# Parse arguments
CLEAN_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN_BUILD=1 ;;
    esac
done

# Function to print section headers
section() {
    echo
    echo -e "${YELLOW}>>> $1${NC}"
    echo "========================================="
}

# Function to handle errors
handle_error() {
    echo -e "${RED}✗ FAILED: $1${NC}"
    FAILURES=$((FAILURES + 1))
}

# Function to handle success
handle_success() {
    echo -e "${GREEN}✓ PASSED: $1${NC}"
}

# Change to repo root
cd "$(dirname "$0")/.."
REPO_ROOT=$(pwd)
CLI_DLL="$REPO_ROOT/src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll"

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
echo "Building compiler and CLI..."
if dotnet build $DOTNET_STABLE_FLAGS src/NSharpLang.Cli/Cli.csproj -v q; then
    handle_success "Compiler built"
else
    handle_error "Compiler build"
fi

section "Step 3: Run Unit Tests"
echo "Running all unit tests..."
TEST_OUTPUT=$(mktemp)
if dotnet test $DOTNET_STABLE_FLAGS tests/Tests.csproj -v q --nologo --no-restore > "$TEST_OUTPUT" 2>&1; then
    TEST_RESULT=$(grep -E "Passed!|Failed!" "$TEST_OUTPUT" || echo "")
    if [ -n "$TEST_RESULT" ]; then
        echo "$TEST_RESULT"
    fi
    handle_success "Unit tests passed"
else
    cat "$TEST_OUTPUT"
    handle_error "Unit tests"
fi
rm -f "$TEST_OUTPUT"

section "Step 3b: VS Code Integration Tests"
# Determine whether to run full VS Code tests or just the smoke suite.
# Full tests run when:
#   - VSCODE_TESTS=full is explicitly set
#   - Changes touch editors/vscode/** or src/NSharpLang.LanguageServer/**
# Otherwise, run the smoke suite (extension, diagnostics, hover, completion).
VSCODE_TEST_MODE="${VSCODE_TESTS:-auto}"

if [ "$VSCODE_TEST_MODE" = "auto" ]; then
    # Check what changed relative to main. Default to full if diff can't be computed
    # (on main itself, shallow clones, detached HEAD, etc.) — fail-safe, not fail-open.
    CHANGED_FILES=$(git diff --name-only main...HEAD 2>/dev/null) || CHANGED_FILES=""
    if [ -z "$CHANGED_FILES" ]; then
        VSCODE_TEST_MODE="full"
        echo "On main or cannot determine changed files — running full VS Code test suite"
    elif echo "$CHANGED_FILES" | grep -qE '^(editors/vscode/|src/NSharpLang\.LanguageServer/)'; then
        VSCODE_TEST_MODE="full"
        echo "LSP or extension changes detected — running full VS Code test suite"
    else
        VSCODE_TEST_MODE="smoke"
        echo "No LSP/extension changes — running smoke tests only"
        echo "  (set VSCODE_TESTS=full to force full suite)"
    fi
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
                "$REPO_ROOT/scripts/test-vscode-integration.sh" > "$VSCODE_OUTPUT" 2>&1 && VSCODE_OK=1 || VSCODE_OK=0
        else
            echo "Running full VS Code integration tests..."
            SKIP_LS_BUILD=1 "$REPO_ROOT/scripts/test-vscode-integration.sh" > "$VSCODE_OUTPUT" 2>&1 && VSCODE_OK=1 || VSCODE_OK=0
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

section "Step 4: Pack and Install MSBuild SDK"
echo "Packing SDK to local NuGet feed..."
if dotnet pack $DOTNET_STABLE_FLAGS src/NSharpLang.Sdk/NSharpLang.Sdk.csproj -o ~/.nuget/local-feed -v q; then
    handle_success "SDK packed"
else
    handle_error "SDK pack"
fi

section "Step 4b: Pack N# Templates"
echo "Packing templates to local NuGet feed..."
if dotnet pack $DOTNET_STABLE_FLAGS templates/NSharpLang.Templates.csproj -o ~/.nuget/local-feed -v q; then
    handle_success "Templates packed"
else
    handle_error "Templates pack"
fi

echo "Clearing NuGet global-packages cache..."
dotnet nuget locals global-packages --clear > /dev/null 2>&1
handle_success "NuGet global-packages cache cleared"

section "Step 4c: C# Interop Tests"
echo "Running C# interop tests..."
INTEROP_DIR="$REPO_ROOT/tests/NSharpLang.CSharpInteropTests"

INTEROP_OUTPUT=$(mktemp)
if dotnet test $DOTNET_STABLE_FLAGS "$INTEROP_DIR/CSharpInteropTests.csproj" -v q --nologo > "$INTEROP_OUTPUT" 2>&1; then
    TEST_RESULT=$(grep -E "Passed!|Failed!" "$INTEROP_OUTPUT" || echo "")
    if [ -n "$TEST_RESULT" ]; then
        echo "$TEST_RESULT"
    fi
    handle_success "C# interop tests passed"
else
    cat "$INTEROP_OUTPUT"
    handle_error "C# interop tests"
fi
rm -f "$INTEROP_OUTPUT"

section "Step 5: Install dotnet new Template"
echo "Installing NSharpLang.Templates from local feed..."
if dotnet new install NSharpLang.Templates --add-source ~/.nuget/local-feed --force > /dev/null 2>&1; then
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
cd "$TEMP_DIR"
if dotnet new nsharp-console -o TestConsoleApp > /dev/null 2>&1; then
    handle_success "Template created test project"
else
    handle_error "Template creation"
    cd "$REPO_ROOT"
fi

if dotnet new nsharp-webapi -o TestWebApiApp > /dev/null 2>&1; then
    handle_success "Web API template created test project"
else
    handle_error "Web API template creation"
    cd "$REPO_ROOT"
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

# Find all example projects and test fixture projects with project.yml
EXAMPLE_PROJECTS=$(find examples tests/fixtures -name "project.yml" -type f 2>/dev/null | sort)

if [ -z "$EXAMPLE_PROJECTS" ]; then
    echo "No example projects found with project.yml"
else
    # Pre-build one example to populate the NuGet cache, avoiding parallel restore races
    FIRST_PROJECT=$(echo "$EXAMPLE_PROJECTS" | head -1)
    FIRST_DIR=$(dirname "$FIRST_PROJECT")
    echo "Warming NuGet cache with $FIRST_DIR..."
    rm -rf "$FIRST_DIR/bin" "$FIRST_DIR/obj" "$FIRST_DIR/nsharp" 2>/dev/null || true
    rm -f "$FIRST_DIR"/*.g.csproj 2>/dev/null || true
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
        # Remove any stale generated .g.csproj files
        rm -f "$work_dir"/*.g.csproj 2>/dev/null || true

        if (cd "$work_dir" && dotnet "$cli_dll" build > "$log_file" 2>&1); then
            printf "OK|%s|%s\n" "$project_name" "$project_dir" > "$result_file"
        else
            printf "FAIL|%s|%s|%s\n" "$project_name" "$project_dir" "$log_file" > "$result_file"
        fi
    ' _ {} "$REPO_ROOT" "$EXAMPLE_RESULTS_DIR" "$CLI_DLL" < "$EXAMPLE_LIST"

    while IFS='|' read -r idx project_file; do
        result_file="$EXAMPLE_RESULTS_DIR/$idx.result"
        status=$(cut -d'|' -f1 "$result_file")
        project_name=$(cut -d'|' -f2 "$result_file")
        project_dir=$(cut -d'|' -f3 "$result_file")

        echo
        echo "Building example: $project_name"
        echo "  Location: $project_dir"

        if [ "$status" = "OK" ]; then
            handle_success "Example: $project_name"
        else
            handle_error "Example: $project_name"
            echo "  Run manually: cd $project_dir && dotnet \"$CLI_DLL\" build"
        fi
    done < "$EXAMPLE_LIST"

    rm -rf "$EXAMPLE_RESULTS_DIR"
fi

section "Step 9: Build Single-File Examples (CLI-based)"

# Known failures that are NOT example bugs:
#   PrintNameofTypeof.nl       - compiler bug: nameof(instance.Property) transpiles incorrectly
#   ConstructorChaining.nl     - compiler bug: interface accessibility in transpiled C#
# Multi-file examples that cannot be built as single files:
#   12-multi-file-projects/imports/  - requires multi-file compilation
KNOWN_FAILURES="PrintNameofTypeof.nl|ConstructorChaining.nl|12-multi-file-projects/imports/"

# Find single .nl files outside of project.yml directories.
# Skip files inside project-based directories (they're tested in Step 8).
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

            if dotnet "$cli_dll" build "$nl_file" > "$log_file" 2>&1; then
                printf "OK|%s|%s\n" "$example_name" "$nl_file" > "$result_file"
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

            echo
            echo "Building single-file example: $example_name"
            echo "  Location: $example_path"

            if [ "$status" = "OK" ]; then
                handle_success "Single-file example: $example_name"
            elif echo "$example_path" | grep -qE "$KNOWN_FAILURES"; then
                echo -e "${YELLOW}  Known failure (compiler bug or intentional): $example_name${NC}"
            else
                handle_error "Single-file example: $example_name"
                echo "  Run manually: dotnet \"$CLI_DLL\" build \"$example_path\""
            fi
        done < "$LEGACY_LIST"

        rm -rf "$LEGACY_RESULTS_DIR"
    fi
fi

section "Step 10: Check Examples (nlc check)"
echo "Running nlc check on all example directories..."
echo "This verifies the Language Server won't report false errors."

# Directories to check individually (each is a self-contained project scope)
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

# Known check failures:
#   12-multi-file-projects  - parent dir has cross-project symbol conflicts (sub-dirs pass individually)
#   17-issue-tracker        - parent dir has no project.yml (backend/ is the actual project)
CHECK_KNOWN_FAILURES="12-multi-file-projects$|17-issue-tracker$"

echo "Using up to $MAX_JOBS parallel workers for nlc check..."
CHECK_RESULTS_DIR=$(mktemp -d)
CHECK_LIST="$CHECK_RESULTS_DIR/items.txt"
i=0
while IFS= read -r check_dir; do
    [ -z "$check_dir" ] && continue
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

    result=$(dotnet "$cli_dll" check "$check_dir/" 2>&1 || true)
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
    elif echo "$dir_name" | grep -qE "$CHECK_KNOWN_FAILURES"; then
        echo -e "  ${YELLOW}⚠${NC} $dir_name (known: $errors errors)"
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

section "Step 11: Summary"
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
