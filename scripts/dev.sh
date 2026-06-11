#!/usr/bin/env bash
#
# Fast inner-loop for compiler/CLI iteration.
#
# Builds the N# CLI (compiler + nlc) and runs a FOCUSED slice of unit tests.
# This is the loop you run dozens of times while building. It is deliberately
# NOT the product gate: it skips the Systems benchmark gate, VS Code tests,
# example/template builds, ilverify, and C# interop. Those run in the full gate.
#
# Before committing, you still MUST run the full isolated gate:
#     VSCODE_TESTS=skip ./scripts/test-all.sh --commit
#
# Usage:
#     ./scripts/dev.sh [pattern]        build CLI, then run tests matching pattern
#     ./scripts/dev.sh                  build CLI only (fastest: just confirm it compiles)
#     ./scripts/dev.sh Columnar         build, then tests whose name contains "Columnar"
#     ./scripts/dev.sh 'FullyQualifiedName~Exception&Category=Fast'   raw VSTest filter
#     TEST_GREP=Columnar ./scripts/dev.sh                             pattern via env
#
# Options:
#     --no-build        skip the CLI build, go straight to tests
#     --build-only      build the CLI, skip tests (same as passing no pattern)
#     -h, --help        show this help
#
# A bare word is wrapped as `FullyQualifiedName~<word>`. Anything containing a
# VSTest filter operator (~ = ! ( ) | &) is passed through verbatim.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

CLI_PROJECT="src/NSharpLang.Cli/Cli.csproj"
TEST_PROJECT="tests/Tests.csproj"

# Same build-server stability flags the product gate uses, so the inner loop and
# the gate agree on MSBuild behavior.
DOTNET_STABLE_FLAGS="--disable-build-servers -nr:false"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

DO_BUILD=1
DO_TESTS=1
FILTER_INPUT="${TEST_GREP:-}"

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            # Print the leading comment block (skip the shebang, stop at the
            # first non-comment line) with the leading "# " stripped.
            awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
            exit 0
            ;;
        --no-build)
            DO_BUILD=0
            shift
            ;;
        --build-only)
            DO_TESTS=0
            shift
            ;;
        --)
            shift
            ;;
        *)
            FILTER_INPUT="$1"
            shift
            ;;
    esac
done

# A bare identifier is a convenience shorthand for a name-substring match. If the
# user already wrote a VSTest filter expression, respect it verbatim.
build_filter() {
    local input="$1"
    [ -z "$input" ] && return 0
    case "$input" in
        *[~=!\(\)\|\&]*) printf '%s' "$input" ;;
        *) printf 'FullyQualifiedName~%s' "$input" ;;
    esac
}

FILTER="$(build_filter "$FILTER_INPUT")"
[ -z "$FILTER" ] && DO_TESTS=0

START_TIME=$(date +%s)

if [ "$DO_BUILD" = "1" ]; then
    echo -e "${YELLOW}>>> Building N# CLI (compiler + nlc)${NC}"
    if dotnet build $DOTNET_STABLE_FLAGS "$CLI_PROJECT" -v q; then
        echo -e "${GREEN}✓ CLI built${NC}"
    else
        echo -e "${RED}✗ CLI build failed${NC}"
        exit 1
    fi
fi

TEST_EXIT=0
if [ "$DO_TESTS" = "1" ]; then
    echo
    echo -e "${YELLOW}>>> Running focused tests${NC}"
    echo "    Filter: $FILTER"
    if dotnet test $DOTNET_STABLE_FLAGS "$TEST_PROJECT" --filter "$FILTER" -v q --nologo; then
        echo -e "${GREEN}✓ Focused tests passed${NC}"
    else
        TEST_EXIT=$?
        echo -e "${RED}✗ Focused tests failed${NC}"
    fi
elif [ "$DO_BUILD" = "1" ]; then
    echo
    echo "No test pattern given — built only. Pass a pattern to run tests, e.g.:"
    echo "    ./scripts/dev.sh Columnar"
fi

END_TIME=$(date +%s)
echo
printf 'Done in %dm %02ds\n' "$(((END_TIME - START_TIME) / 60))" "$(((END_TIME - START_TIME) % 60))"

if [ "$TEST_EXIT" != "0" ]; then
    exit "$TEST_EXIT"
fi

if [ "$DO_TESTS" = "1" ]; then
    echo
    echo -e "${YELLOW}Reminder:${NC} this is the fast inner loop, not the gate."
    echo "Before committing:  VSCODE_TESTS=skip ./scripts/test-all.sh --commit"
fi
