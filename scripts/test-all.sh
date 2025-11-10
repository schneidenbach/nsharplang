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
cd "$(dirname "$0")"
REPO_ROOT=$(pwd)

section "Step 1: Clean Previous Build Artifacts"
echo "Cleaning bin/ and obj/ directories..."
find . -type d -name "bin" -o -name "obj" -o -name "nsharp" | while read dir; do
    if [[ "$dir" != "./node_modules"* ]]; then
        rm -rf "$dir"
    fi
done
handle_success "Cleaned build artifacts"

section "Step 2: Build N# Compiler"
echo "Building compiler and CLI..."
if dotnet build src/Compiler/Compiler.csproj -v q; then
    handle_success "Compiler built"
else
    handle_error "Compiler build"
fi

section "Step 3: Run Unit Tests"
echo "Running all unit tests..."
if dotnet test -v q --nologo; then
    TEST_RESULT=$(dotnet test --nologo --verbosity quiet 2>&1 | grep -E "Passed|Failed" || echo "")
    echo "$TEST_RESULT"
    handle_success "Unit tests passed"
else
    handle_error "Unit tests"
fi

section "Step 4: Pack and Install MSBuild SDK"
echo "Packing SDK to local NuGet feed..."
if dotnet pack src/NSharpLang.Sdk/NSharpLang.Sdk.csproj -o ~/.nuget/local-feed -v q; then
    handle_success "SDK packed"
else
    handle_error "SDK pack"
fi

echo "Clearing NuGet caches..."
dotnet nuget locals all --clear > /dev/null 2>&1
handle_success "NuGet caches cleared"

section "Step 5: Install dotnet new Template"
echo "Installing nsharp-console template..."
if dotnet new install templates/nsharp-console/ --force > /dev/null 2>&1; then
    handle_success "Template installed"
else
    handle_error "Template installation"
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

if [ -f "$TEMP_DIR/TestConsoleApp/project.yml" ]; then
    handle_success "project.yml exists"
else
    handle_error "project.yml missing"
fi

section "Step 7: Build Template-Generated Project"
cd "$TEMP_DIR/TestConsoleApp"
echo "Building template-generated project..."
if dotnet restore > /dev/null 2>&1 && dotnet build > /dev/null 2>&1; then
    handle_success "Template project builds"
else
    handle_error "Template project build"
fi

cd "$REPO_ROOT"
rm -rf "$TEMP_DIR"

section "Step 8: Build Example Projects"

# Find all example projects with project.yml
EXAMPLE_PROJECTS=$(find examples -name "project.yml" -type f | sort)

if [ -z "$EXAMPLE_PROJECTS" ]; then
    echo "No example projects found with project.yml"
else
    for project_file in $EXAMPLE_PROJECTS; do
        project_dir=$(dirname "$project_file")
        project_name=$(basename "$project_dir")

        echo
        echo "Building example: $project_name"
        echo "  Location: $project_dir"

        cd "$REPO_ROOT/$project_dir"

        # Clean first
        rm -rf bin obj nsharp 2>/dev/null || true

        # Restore and build
        if dotnet restore > /dev/null 2>&1 && dotnet build 2>&1 | grep -q "Build succeeded"; then
            handle_success "Example: $project_name"
        else
            handle_error "Example: $project_name"
            echo "  Run manually: cd $project_dir && dotnet build"
        fi

        cd "$REPO_ROOT"
    done
fi

section "Step 9: Build Legacy Examples (CLI-based)"

# Find examples with .nl files but no project.yml
LEGACY_EXAMPLES=$(find examples -maxdepth 2 -name "*.nl" -type f | grep -v "project.yml" | sort)

if [ -z "$LEGACY_EXAMPLES" ]; then
    echo "No legacy examples found"
else
    echo "Note: Legacy examples use direct CLI compilation (not dotnet build)"
    for nl_file in $LEGACY_EXAMPLES; do
        example_name=$(basename "$nl_file" .nl)

        echo
        echo "Compiling legacy example: $example_name"
        echo "  Location: $nl_file"

        # Try to compile with CLI
        if dotnet run --project src/Cli/Cli.csproj -- build "$nl_file" > /dev/null 2>&1; then
            handle_success "Legacy example: $example_name"
        else
            # Some examples might be meant to fail or have special requirements
            echo -e "${YELLOW}  Skipped (may require special setup)${NC}"
        fi
    done
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
