#!/bin/bash
set -eo pipefail

# Verify debugging support works end-to-end
# Tests that #line directives are emitted correctly in generated C# files
# and that PDB files contain references to .nl source files

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

FAILURES=0

pass() { echo -e "${GREEN}PASS${NC}: $1"; }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILURES=$((FAILURES + 1)); }

echo "========================================="
echo "N# Debugging Verification"
echo "========================================="
echo

# Use an existing example project
PROJECT_DIR="examples/01-hello-world"

echo "Step 1: Build example project..."
dotnet clean "$PROJECT_DIR" -v q 2>&1 > /dev/null
if dotnet build "$PROJECT_DIR" -v q 2>&1 | tail -3; then
    pass "Project builds"
else
    fail "Project build"
    exit 1
fi

echo
echo "Step 2: Check generated C# for #line directives..."
GEN_DIR="$PROJECT_DIR/obj/Debug/net9.0/nsharp"
if [ -d "$GEN_DIR" ]; then
    GEN_FILES=$(find "$GEN_DIR" -name "*.g.cs" 2>/dev/null)
    if [ -z "$GEN_FILES" ]; then
        fail "No .g.cs files found in $GEN_DIR"
    else
        HAS_LINE_DIRECTIVE=false
        HAS_LINE_HIDDEN=false
        HAS_LINE_DEFAULT=false
        HAS_NL_REF=false

        for f in $GEN_FILES; do
            if grep -q '#line [0-9]' "$f"; then HAS_LINE_DIRECTIVE=true; fi
            if grep -q '#line hidden' "$f"; then HAS_LINE_HIDDEN=true; fi
            if grep -q '#line default' "$f"; then HAS_LINE_DEFAULT=true; fi
            if grep -q '\.nl"' "$f"; then HAS_NL_REF=true; fi
        done

        if $HAS_LINE_DIRECTIVE; then pass "#line directives present"; else fail "#line directives missing"; fi
        if $HAS_LINE_HIDDEN; then pass "#line hidden present"; else fail "#line hidden missing"; fi
        if $HAS_LINE_DEFAULT; then pass "#line default present"; else fail "#line default missing"; fi
        if $HAS_NL_REF; then pass ".nl file references in #line directives"; else fail ".nl file references missing"; fi
    fi
else
    fail "Generated C# directory not found: $GEN_DIR"
fi

echo
echo "Step 3: Check PDB exists..."
PDB_DIR="$PROJECT_DIR/bin/Debug"
PDB_FILES=$(find "$PDB_DIR" -name "*.pdb" 2>/dev/null)
if [ -n "$PDB_FILES" ]; then
    pass "PDB file(s) found"
    for pdb in $PDB_FILES; do
        if strings "$pdb" 2>/dev/null | grep -q '\.nl'; then
            pass "PDB references .nl files: $(basename $pdb)"
        else
            fail "PDB does not reference .nl files: $(basename $pdb)"
        fi
    done
else
    fail "No PDB files found in $PDB_DIR"
fi

echo
echo "Step 4: Verify template includes .vscode files..."
for tmpl in templates/nsharp-console templates/nsharp-webapi templates/console; do
    if [ -f "$tmpl/.vscode/launch.json" ] && [ -f "$tmpl/.vscode/tasks.json" ]; then
        pass "Template $tmpl has .vscode files"
    else
        fail "Template $tmpl missing .vscode files"
    fi
done

echo
echo "========================================="
if [ $FAILURES -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
else
    echo -e "${RED}$FAILURES check(s) failed${NC}"
fi
exit $FAILURES
