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
#     ./scripts/dev.sh --since          build, then only tests implicated by your uncommitted changes
#     ./scripts/dev.sh --since main      build, then only tests implicated by changes since `main`
#     ./scripts/dev.sh 'FullyQualifiedName~Exception&Category=Fast'   raw VSTest filter
#     TEST_GREP=Columnar ./scripts/dev.sh                             pattern via env
#
# Options:
#     --since [ref]     derive the test filter from `git diff` (default ref: HEAD, i.e. the
#                       working tree). Changed paths map to subsystem keywords (Columnar,
#                       ILCompiler, LanguageServer, Cli, ...). FAIL-SAFE: a central or unmapped
#                       change (AST core, runtime/SDK, build config, shared compiler file) runs
#                       the full unit suite instead, and says why. Never silently narrows.
#     --no-build        skip the CLI build, go straight to tests
#     --build-only      build the CLI, skip tests (same as passing no pattern)
#     -h, --help        show this help
#
# A bare word is wrapped as `FullyQualifiedName~<word>`. Anything containing a
# VSTest filter operator (~ = ! ( ) | &) is passed through verbatim.
#
# Change-aware selection is an inner-loop accelerator ONLY. It is allowed to miss
# tests precisely because the full --commit gate remains the backstop. Never treat
# a green `dev.sh --since` as a substitute for the commit gate.

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
FULL_SUITE=0
SINCE_REF=""
USE_SINCE=0
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
        --since)
            USE_SINCE=1
            SINCE_REF="HEAD"
            # Treat the next token as the base ref only if it resolves to a commit;
            # otherwise leave it for normal parsing (and default the ref to HEAD).
            if [ $# -ge 2 ] && git rev-parse --verify --quiet "${2}^{commit}" >/dev/null 2>&1; then
                SINCE_REF="$2"
                shift
            fi
            shift
            ;;
        --since=*)
            USE_SINCE=1
            SINCE_REF="${1#--since=}"
            if ! git rev-parse --verify --quiet "${SINCE_REF}^{commit}" >/dev/null 2>&1; then
                echo "dev.sh: --since ref is not a valid commit: $SINCE_REF" >&2
                exit 2
            fi
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

# Map the set of changed files (vs a git ref) to a VSTest filter. Tests are grouped
# by subsystem, not 1:1 with source files, so we map changed PATHS to subsystem
# keywords that appear in the tests' fully-qualified names. Emits one of:
#   __NONE__   no unit tests implicated (e.g. docs-only change)
#   __FULL__   a central/unmapped change → run the whole unit suite (fail-safe)
#   <filter>   a `FullyQualifiedName~A|FullyQualifiedName~B` selection
# Human-readable reasoning goes to stderr; only the result token goes to stdout.
derive_filter_from_diff() {
    local ref="$1"
    local changed untracked
    changed="$(git diff --name-only "$ref" 2>/dev/null || true)"
    untracked="$(git ls-files --others --exclude-standard 2>/dev/null || true)"
    changed="$(printf '%s\n%s\n' "$changed" "$untracked" | sed '/^[[:space:]]*$/d' | sort -u)"

    if [ -z "$changed" ]; then
        echo "__NONE__"
        return 0
    fi

    local terms="" full=0 reasons="" f stem
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in
            # --- central / cross-cutting → full unit suite (fail-safe) ---
            Directory.Build.*|*/Directory.Build.*|*.sln|*.slnx|global.json|NuGet.config)
                full=1; reasons="$reasons
  - $f (build config)" ;;
            src/NSharpLang.Compiler/Ast/*)
                full=1; reasons="$reasons
  - $f (AST core — broad impact)" ;;
            src/NSharpLang.Runtime/*|src/NSharpLang.Build.Tasks/*|src/NSharpLang.Sdk/*)
                full=1; reasons="$reasons
  - $f (runtime/SDK — also run the gate for template/example coverage)" ;;
            # --- compiler subsystems ---
            src/NSharpLang.Compiler/Columnar/*)        terms="$terms Columnar" ;;
            src/NSharpLang.Compiler/ILCompiler/*)      terms="$terms ILCompiler" ;;
            src/NSharpLang.Compiler/CodeIntelligence/*) terms="$terms LanguageServer CodeIntelligence" ;;
            src/NSharpLang.Compiler/Performance/*)     terms="$terms Systems" ;;
            src/NSharpLang.Compiler/Parser*.cs|src/NSharpLang.Compiler/Lexer*.cs) terms="$terms Parser" ;;
            src/NSharpLang.Compiler/Analyzer*.cs)      terms="$terms Analyzer" ;;
            src/NSharpLang.Compiler/Transpiler*.cs)    terms="$terms Transpiler" ;;
            src/NSharpLang.Compiler/Formatter*.cs)     terms="$terms Formatter" ;;
            src/NSharpLang.Compiler/*)
                full=1; reasons="$reasons
  - $f (shared compiler file)" ;;
            # --- sibling projects ---
            src/NSharpLang.LanguageServer/*)           terms="$terms LanguageServer" ;;
            src/NSharpLang.Cli/*)                      terms="$terms Cli" ;;
            src/NSharpLang.Compiler.Dogfood/*)         terms="$terms Dogfood" ;;
            src/NSharpLang.Playground*/*)              terms="$terms Playground" ;;
            # --- a changed test file: run that file's own tests (class == file stem) ---
            tests/*.cs)
                stem="$(basename "$f" .cs)"; terms="$terms $stem" ;;
            # --- inner loop can't meaningfully cover these → fail-safe ---
            tests/scripts/*|tests/fixtures/*)
                full=1; reasons="$reasons
  - $f (test infra/fixtures)" ;;
            # --- no unit tests implicated ---
            docs/*|*.md|editors/*|*.yml|*.yaml|*.json|.github/*|.gitignore)
                : ;;
            *)
                full=1; reasons="$reasons
  - $f (unmapped path)" ;;
        esac
    done <<< "$changed"

    if [ "$full" = "1" ]; then
        printf 'Change-aware selection: FULL unit suite (fail-safe). Triggers:%s\n' "$reasons" >&2
        echo "__FULL__"
        return 0
    fi

    terms="$(printf '%s\n' $terms | sed '/^$/d' | sort -u)"
    if [ -z "$terms" ]; then
        echo "__NONE__"
        return 0
    fi

    local filter="" t
    while IFS= read -r t; do
        [ -z "$t" ] && continue
        if [ -z "$filter" ]; then
            filter="FullyQualifiedName~$t"
        else
            filter="$filter|FullyQualifiedName~$t"
        fi
    done <<< "$terms"
    printf 'Change-aware selection (since %s): %s\n' "$ref" "$(echo $terms | tr '\n' ' ')" >&2
    echo "$filter"
}

FILTER=""
if [ "$USE_SINCE" = "1" ]; then
    DERIVED="$(derive_filter_from_diff "$SINCE_REF")"
    case "$DERIVED" in
        __NONE__)
            echo "Change-aware: no unit tests implicated by changes since $SINCE_REF — building only."
            DO_TESTS=0
            ;;
        __FULL__)
            FULL_SUITE=1
            ;;
        *)
            FILTER="$DERIVED"
            ;;
    esac
else
    FILTER="$(build_filter "$FILTER_INPUT")"
    [ -z "$FILTER" ] && DO_TESTS=0
fi

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
    echo -e "${YELLOW}>>> Running tests${NC}"
    if [ "$FULL_SUITE" = "1" ]; then
        echo "    Scope: full unit suite (no filter)"
        if dotnet test $DOTNET_STABLE_FLAGS "$TEST_PROJECT" -v q --nologo; then
            echo -e "${GREEN}✓ Full unit suite passed${NC}"
        else
            TEST_EXIT=$?
            echo -e "${RED}✗ Unit suite failed${NC}"
        fi
    else
        echo "    Filter: $FILTER"
        if dotnet test $DOTNET_STABLE_FLAGS "$TEST_PROJECT" --filter "$FILTER" -v q --nologo; then
            echo -e "${GREEN}✓ Focused tests passed${NC}"
        else
            TEST_EXIT=$?
            echo -e "${RED}✗ Focused tests failed${NC}"
        fi
    fi
elif [ "$DO_BUILD" = "1" ]; then
    echo
    echo "No test pattern given — built only. Pass a pattern (or --since) to run tests, e.g.:"
    echo "    ./scripts/dev.sh Columnar"
    echo "    ./scripts/dev.sh --since"
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
