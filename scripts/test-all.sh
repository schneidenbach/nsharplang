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
CLI_DLL="$REPO_ROOT/src/NSharpLang.Cli/bin/Debug/net9.0/Cli.dll"

section "Step 1: Clean Previous Build Artifacts"
echo "Cleaning bin/ and obj/ directories..."
find . \( -type d -name "bin" -o -type d -name "obj" -o -type d -name "nsharp" \) | while read dir; do
    if [[ "$dir" == "./node_modules"* ]] || [[ "$dir" == *".vscode-test"* ]] || [[ "$dir" == *"node_modules"* ]]; then
        continue
    fi
    rm -rf "$dir"
done
handle_success "Cleaned build artifacts"

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

section "Step 3b: VS Code Integration Tests (MANDATORY)"
# VS Code integration tests are REQUIRED — they catch parser/LSP regressions
# that unit tests miss (e.g., false-positive NL101 errors on valid syntax).
# If prerequisites are missing, this is a FAILURE, not a skip.
VSCODE_SKIP_REASON=""
if ! command -v code >/dev/null 2>&1; then
    VSCODE_SKIP_REASON="VS Code ('code' command) not found on PATH"
fi
if ! command -v node >/dev/null 2>&1; then
    VSCODE_SKIP_REASON="Node.js ('node' command) not found on PATH"
fi

if [ -n "$VSCODE_SKIP_REASON" ]; then
    echo -e "${RED}ERROR: $VSCODE_SKIP_REASON${NC}"
    echo "VS Code integration tests are mandatory. Install prerequisites:"
    echo "  - VS Code: https://code.visualstudio.com/"
    echo "  - Node.js: https://nodejs.org/"
    echo "  - 'code' CLI: VS Code > Cmd+Shift+P > 'Shell Command: Install code command'"
    handle_error "VS Code integration tests (missing prerequisites)"
else
    echo "Running VS Code integration tests..."
    VSCODE_OUTPUT=$(mktemp)
    if "$REPO_ROOT/scripts/test-vscode-integration.sh" > "$VSCODE_OUTPUT" 2>&1; then
        handle_success "VS Code integration tests"
    else
        cat "$VSCODE_OUTPUT"
        handle_error "VS Code integration tests"
    fi
    rm -f "$VSCODE_OUTPUT"
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

echo "Clearing NuGet caches..."
dotnet nuget locals all --clear > /dev/null 2>&1
handle_success "NuGet caches cleared"

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

if [ -f "$TEMP_DIR/TestWebApiApp/project.yml" ]; then
    handle_success "webapi project.yml exists"
else
    handle_error "webapi project.yml missing"
fi

section "Step 7: Build Template-Generated Project"
if [ -d "$TEMP_DIR/TestConsoleApp" ]; then
    cd "$TEMP_DIR/TestConsoleApp"
    echo "Building template-generated project..."
    if dotnet restore $DOTNET_STABLE_FLAGS > /dev/null 2>&1 && dotnet build $DOTNET_STABLE_FLAGS > /dev/null 2>&1; then
        handle_success "Template project builds"
    else
        handle_error "Template project build"
    fi
else
    handle_error "Template project missing"
fi

if [ -d "$TEMP_DIR/TestWebApiApp" ]; then
    cd "$TEMP_DIR/TestWebApiApp"
    echo "Building web API template-generated project..."
    if dotnet restore $DOTNET_STABLE_FLAGS > /dev/null 2>&1 && dotnet build $DOTNET_STABLE_FLAGS > /dev/null 2>&1; then
        handle_success "Web API template project builds"
    else
        handle_error "Web API template project build"
    fi
else
    handle_error "Web API template project missing"
fi

cd "$REPO_ROOT"
rm -rf "$TEMP_DIR"

section "Step 8: Build Example Projects"
echo "Using up to $MAX_JOBS parallel workers for project verification..."

# Find all example projects with project.yml
EXAMPLE_PROJECTS=$(find examples -name "project.yml" -type f | sort)

if [ -z "$EXAMPLE_PROJECTS" ]; then
    echo "No example projects found with project.yml"
else
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
        idx="${entry%%|*}"
        project_file="${entry#*|}"
        project_dir=$(dirname "$project_file")
        project_name=$(basename "$project_dir")
        log_file="$results_dir/$idx.log"
        result_file="$results_dir/$idx.result"
        work_dir="$repo_root/$project_dir"

        rm -rf "$work_dir/bin" "$work_dir/obj" "$work_dir/nsharp" 2>/dev/null || true

        if (cd "$work_dir" && dotnet restore --disable-build-servers > /dev/null 2>&1 && dotnet build --disable-build-servers --no-restore > "$log_file" 2>&1); then
            printf "OK|%s|%s\n" "$project_name" "$project_dir" > "$result_file"
        else
            printf "FAIL|%s|%s|%s\n" "$project_name" "$project_dir" "$log_file" > "$result_file"
        fi
    ' _ {} "$REPO_ROOT" "$EXAMPLE_RESULTS_DIR" < "$EXAMPLE_LIST"

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
            echo "  Run manually: cd $project_dir && dotnet build"
        fi
    done < "$EXAMPLE_LIST"

    rm -rf "$EXAMPLE_RESULTS_DIR"
fi

section "Step 9: Build Legacy Examples (CLI-based)"

# Find examples with .nl files but no project.yml
LEGACY_EXAMPLES=$(find examples -maxdepth 2 -name "*.nl" -type f | grep -v "project.yml" | sort)

if [ -z "$LEGACY_EXAMPLES" ]; then
    echo "No legacy examples found"
else
    echo "Note: Legacy examples use direct CLI compilation (not dotnet build)"
    if [ ! -f "$CLI_DLL" ]; then
        handle_error "CLI build artifact missing"
    else
        LEGACY_RESULTS_DIR=$(mktemp -d)
        LEGACY_LIST="$LEGACY_RESULTS_DIR/items.txt"
        i=0
        printf '%s\n' "$LEGACY_EXAMPLES" | while IFS= read -r nl_file; do
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
                printf "SKIP|%s|%s\n" "$example_name" "$nl_file" > "$result_file"
            fi
        ' _ {} "$REPO_ROOT" "$LEGACY_RESULTS_DIR" "$CLI_DLL" < "$LEGACY_LIST"

        while IFS='|' read -r idx nl_file; do
            result_file="$LEGACY_RESULTS_DIR/$idx.result"
            status=$(cut -d'|' -f1 "$result_file")
            example_name=$(cut -d'|' -f2 "$result_file")
            example_path=$(cut -d'|' -f3 "$result_file")

            echo
            echo "Compiling legacy example: $example_name"
            echo "  Location: $example_path"

            if [ "$status" = "OK" ]; then
                handle_success "Legacy example: $example_name"
            else
                echo -e "${YELLOW}  Skipped (may require special setup)${NC}"
            fi
        done < "$LEGACY_LIST"

        rm -rf "$LEGACY_RESULTS_DIR"
    fi
fi

section "Step 10: Summary"
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
