#!/usr/bin/env bash
#
# Fast inner-loop for compiler/CLI iteration.
#
# Builds the N# CLI (compiler + nlc) and runs a FOCUSED slice of the test estate.
# This is the loop you run dozens of times while building. It is deliberately
# NOT the product gate: it skips the Systems benchmark gate, VS Code tests,
# example/template builds, ilverify, and interop checks. Those run in the full gate.
#
# Before committing, you still MUST run the full isolated gate:
#     VSCODE_TESTS=skip ./scripts/test-all.sh --commit
#
# THE TWO TEST BODIES. There is no C# unit suite any more — `tests/*.cs` is gone and
# `tests/Tests.csproj` with it. What remains is what the gate's Step 3a runs:
#
#   * the ESTATE — the compiler-service contracts that live beside their owners as
#     `src/NSharpLang.Compiler.Core/*.tests.nl`, run through that project with
#     `-p:NSharpExcludeTests=false`. This is the slow one: it re-restores and rebuilds
#     Compiler Core with its tests included.
#   * the NATIVE PROJECTS — every `tests/native/<dir>` with a `project.yml` and a
#     `*.tests.nl` beside it, each run by the freshly built `nlc test`. These are seconds
#     apiece, and a pattern usually wants only one or two of them.
#
# Usage:
#     ./scripts/dev.sh [pattern]        build CLI, then run the slices matching pattern
#     ./scripts/dev.sh                  build CLI only (fastest: just confirm it compiles)
#     ./scripts/dev.sh Columnar         build, then the columnar slices
#     ./scripts/dev.sh --since          build, then only the slices implicated by your changes
#     ./scripts/dev.sh --since main     build, then the slices implicated by changes since `main`
#     ./scripts/dev.sh --estate         build, then the whole compiler-service estate
#     ./scripts/dev.sh --estate Columnar  build, then the estate rows whose names match
#     ./scripts/dev.sh --list           list every slice name
#     TEST_GREP=Columnar ./scripts/dev.sh                pattern via env
#
# Options:
#     --since [ref]     derive the slice selection from `git diff` (default ref: HEAD, i.e. the
#                       working tree). Changed paths map to slices. FAIL-SAFE: a central or
#                       unmapped change (AST core, runtime/SDK, build config, shared compiler
#                       file) runs EVERYTHING and says why. Never silently narrows.
#     --estate [filter] run the compiler-service estate; with a filter, only the rows whose
#                       fully-qualified name matches it.
#     --no-estate       never run the estate, whatever the selection asked for. For tight loops
#                       on a native project; it narrows coverage, so say so when you report.
#     --list            print the slice names and exit
#     --no-build        skip the CLI build, go straight to tests
#     --build-only      build the CLI, skip tests (same as passing no pattern)
#     -h, --help        show this help
#
# A pattern selects NATIVE PROJECTS by directory name (case- and hyphen-insensitive substring,
# so `LanguageServer` finds `language-server-handlers`) and, unless `--no-estate` is given, the
# ESTATE rows whose fully-qualified name contains the same word. A pattern that matches nothing
# is an error: zero matched tests is not evidence.
#
# Change-aware selection is an inner-loop accelerator ONLY. It is allowed to miss
# tests precisely because the full --commit gate remains the backstop. Never treat
# a green `dev.sh --since` as a substitute for the commit gate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

CLI_PROJECT="src/NSharpLang.Cli/Cli.csproj"
CLI_DLL="src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll"
ESTATE_PROJECT="src/NSharpLang.Compiler.Core/NSharpLang.Compiler.Core.csproj"

# Same build-server stability flags the product gate uses, so the inner loop and
# the gate agree on MSBuild behavior.
DOTNET_STABLE_FLAGS="--disable-build-servers -nr:false"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Match the product gate's Step 3a evidence vocabulary. Both VSTest and N# native
# test output use these counters, but they must appear together on one summary
# line: independent greps could combine unrelated output into a false verdict.
has_nonempty_successful_test_summary() {
    local output="$1" line passed failed total saw_summary=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*Passed![[:space:]]*-[[:space:]]*Failed:[[:space:]]*([0-9]+),[[:space:]]*Passed:[[:space:]]*([0-9]+),[[:space:]]*Skipped:[[:space:]]*([0-9]+),[[:space:]]*Total:[[:space:]]*([0-9]+)([[:space:]]*,|[[:space:]]*$) ]]; then
            failed="${BASH_REMATCH[1]}"
            passed="${BASH_REMATCH[2]}"
            total="${BASH_REMATCH[4]}"
        elif [[ "$line" =~ ^[[:space:]]*Failed![[:space:]]*-[[:space:]]*Failed:[[:space:]]*([0-9]+),[[:space:]]*Passed:[[:space:]]*([0-9]+),[[:space:]]*Skipped:[[:space:]]*([0-9]+),[[:space:]]*Total:[[:space:]]*([0-9]+)([[:space:]]*,|[[:space:]]*$) ]]; then
            return 1
        elif [[ "$line" =~ ^[[:space:]]*Passed:[[:space:]]*([0-9]+),[[:space:]]*Failed:[[:space:]]*([0-9]+),[[:space:]]*Skipped:[[:space:]]*([0-9]+),[[:space:]]*Total:[[:space:]]*([0-9]+)([[:space:]]*,|[[:space:]]*$) ]]; then
            passed="${BASH_REMATCH[1]}"
            failed="${BASH_REMATCH[2]}"
            total="${BASH_REMATCH[4]}"
        else
            continue
        fi

        saw_summary=1
        if [[ ! "$passed" =~ ^[1-9][0-9]*$ ]] || [ "$failed" != "0" ] || [[ ! "$total" =~ ^[1-9][0-9]*$ ]]; then
            return 1
        fi
    done < "$output"

    [ "$saw_summary" = "1" ]
}

report_missing_test_evidence() {
    local label="$1"
    echo -e "${RED}✗ $label did not produce a nonempty successful test summary${NC}"
    echo "    Expected one VSTest or N# native summary line with Passed: > 0, Failed: 0, and Total: > 0."
    echo "    Check the filter; it may have matched no tests."
}

DO_BUILD=1
DO_TESTS=1
RUN_EVERYTHING=0
WANT_ESTATE=0
ALLOW_ESTATE=1
ESTATE_FILTER=""
SINCE_REF=""
USE_SINCE=0
LIST_ONLY=0
FILTER_INPUT="${TEST_GREP:-}"

# Every native slice: a tests/native/<dir> holding a project.yml AND at least one *.tests.nl.
# (The gate's Step 3a discovers them with the same two conditions.)
native_slices() {
    local project dir
    for project in tests/native/*/project.yml; do
        [ -f "$project" ] || continue
        dir="$(dirname "$project")"
        if compgen -G "$dir/*.tests.nl" > /dev/null; then
            printf '%s\n' "$dir"
        fi
    done
}

# Case- and hyphen-insensitive substring match, so `LanguageServer`, `language-server` and
# `languageserver` all select the same projects.
normalize_slice_word() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' -' | tr -d '_'
}

native_slices_matching() {
    local wanted dir
    wanted="$(normalize_slice_word "$1")"
    [ -n "$wanted" ] || return 0
    while IFS= read -r dir; do
        case "$(normalize_slice_word "$(basename "$dir")")" in
            *"$wanted"*) printf '%s\n' "$dir" ;;
        esac
    done < <(native_slices)
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            # Print the leading comment block (skip the shebang, stop at the
            # first non-comment line) with the leading "# " stripped.
            awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
            exit 0
            ;;
        --list)
            LIST_ONLY=1
            shift
            ;;
        --no-build)
            DO_BUILD=0
            shift
            ;;
        --build-only)
            DO_TESTS=0
            shift
            ;;
        --no-estate)
            ALLOW_ESTATE=0
            shift
            ;;
        --estate)
            WANT_ESTATE=1
            # An immediately following bare word is the estate filter; an option is not.
            if [ $# -ge 2 ]; then
                case "$2" in
                    -*) : ;;
                    *) ESTATE_FILTER="$2"; shift ;;
                esac
            fi
            shift
            ;;
        --estate=*)
            WANT_ESTATE=1
            ESTATE_FILTER="${1#--estate=}"
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

if [ "$LIST_ONLY" = "1" ]; then
    echo "estate    src/NSharpLang.Compiler.Core/*.tests.nl (run with --estate)"
    native_slices | sed 's/^tests\/native\//native    /'
    exit 0
fi

# Map the set of changed files (vs a git ref) to a slice selection. Slices are grouped by
# subsystem, not 1:1 with source files, so we map changed PATHS to subsystem keywords that
# name native project directories and appear in estate row names. Emits one of:
#   __NONE__   nothing implicated (e.g. docs-only change)
#   __FULL__   a central/unmapped change → run everything (fail-safe)
#   <words>    a space-separated keyword selection
# Human-readable reasoning goes to stderr; only the result token goes to stdout.
derive_slices_from_diff() {
    local ref="$1"
    local changed untracked
    changed="$(git diff --name-only "$ref" 2>/dev/null || true)"
    untracked="$(git ls-files --others --exclude-standard 2>/dev/null || true)"
    changed="$(printf '%s\n%s\n' "$changed" "$untracked" | sed '/^[[:space:]]*$/d' | sort -u)"

    if [ -z "$changed" ]; then
        echo "__NONE__"
        return 0
    fi

    local terms="" full=0 reasons="" f
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        case "$f" in
            # --- central / cross-cutting → everything (fail-safe) ---
            Directory.Build.*|*/Directory.Build.*|*.sln|*.slnx|global.json|NuGet.config)
                full=1; reasons="$reasons
  - $f (build config)" ;;
            src/NSharpLang.Runtime/*|src/NSharpLang.Build.Tasks/*|src/NSharpLang.Sdk/*)
                full=1; reasons="$reasons
  - $f (runtime/SDK — also run the gate for template/example coverage)" ;;
            # --- the N# compiler: one flat directory, so the FILE NAME names the subsystem ---
            src/NSharpLang.Compiler.Core/Columnar*)        terms="$terms estate Columnar" ;;
            src/NSharpLang.Compiler.Core/Analyzer*)        terms="$terms estate Analyzer" ;;
            src/NSharpLang.Compiler.Core/Formatter*|src/NSharpLang.Compiler.Core/Format*) terms="$terms estate" ;;
            src/NSharpLang.Compiler.Core/CodeIntelligence*|src/NSharpLang.Compiler.Core/Completion*) terms="$terms estate completion query LanguageServer" ;;
            src/NSharpLang.Compiler.Core/DocQuery*|src/NSharpLang.Compiler.Core/Query*) terms="$terms estate query doc" ;;
            src/NSharpLang.Compiler.Core/*Command*)        terms="$terms estate cli daemon" ;;
            src/NSharpLang.Compiler.Core/*)
                full=1; reasons="$reasons
  - $f (shared compiler file)" ;;
            # --- the remaining C# shell around it ---
            src/NSharpLang.Compiler/*)
                full=1; reasons="$reasons
  - $f (shared compiler file)" ;;
            # --- sibling projects ---
            src/NSharpLang.LanguageServer/*)           terms="$terms LanguageServer lsp" ;;
            src/NSharpLang.Cli/*)                      terms="$terms cli daemon compilation-backend parity" ;;
            src/NSharpLang.Playground*/*)              terms="$terms playground" ;;
            # --- a changed native project: run that project ---
            tests/native/*/*)
                terms="$terms $(basename "$(dirname "$f")")" ;;
            # --- inner loop can't meaningfully cover these → fail-safe ---
            tests/scripts/*|tests/fixtures/*)
                full=1; reasons="$reasons
  - $f (test infra/fixtures)" ;;
            # --- nothing implicated ---
            docs/*|*.md|editors/*|*.yml|*.yaml|*.json|.github/*|.gitignore)
                : ;;
            *)
                full=1; reasons="$reasons
  - $f (unmapped path)" ;;
        esac
    done <<< "$changed"

    if [ "$full" = "1" ]; then
        printf 'Change-aware selection: EVERYTHING (fail-safe). Triggers:%s\n' "$reasons" >&2
        echo "__FULL__"
        return 0
    fi

    terms="$(printf '%s\n' $terms | sed '/^$/d' | sort -u | tr '\n' ' ')"
    if [ -z "${terms// /}" ]; then
        echo "__NONE__"
        return 0
    fi

    printf 'Change-aware selection (since %s): %s\n' "$ref" "$terms" >&2
    printf '%s\n' "$terms"
}

SELECTED_NATIVE=""
add_native() {
    local dir
    while IFS= read -r dir; do
        [ -n "$dir" ] || continue
        case " $SELECTED_NATIVE " in
            *" $dir "*) ;;
            *) SELECTED_NATIVE="$SELECTED_NATIVE $dir" ;;
        esac
    done
}

if [ "$USE_SINCE" = "1" ]; then
    DERIVED="$(derive_slices_from_diff "$SINCE_REF")"
    case "$DERIVED" in
        __NONE__)
            echo "Change-aware: nothing implicated by changes since $SINCE_REF — building only."
            DO_TESTS=0
            ;;
        __FULL__)
            RUN_EVERYTHING=1
            ;;
        *)
            for word in $DERIVED; do
                if [ "$word" = "estate" ]; then
                    WANT_ESTATE=1
                    continue
                fi
                add_native < <(native_slices_matching "$word")
                if [ -z "$ESTATE_FILTER" ]; then
                    ESTATE_FILTER="$word"
                fi
            done
            ;;
    esac
elif [ -n "$FILTER_INPUT" ]; then
    add_native < <(native_slices_matching "$FILTER_INPUT")
    if [ -z "$ESTATE_FILTER" ]; then
        ESTATE_FILTER="$FILTER_INPUT"
    fi
    WANT_ESTATE=1
    if [ -z "${SELECTED_NATIVE// /}" ]; then
        echo -e "${YELLOW}No native project name matches '$FILTER_INPUT' — running the estate rows that match instead.${NC}"
        echo "    See every slice name with: ./scripts/dev.sh --list"
    fi
elif [ "$WANT_ESTATE" = "0" ]; then
    DO_TESTS=0
fi

if [ "$ALLOW_ESTATE" = "0" ]; then
    WANT_ESTATE=0
fi

if [ "$RUN_EVERYTHING" = "1" ]; then
    add_native < <(native_slices)
    [ "$ALLOW_ESTATE" = "1" ] && WANT_ESTATE=1
    ESTATE_FILTER=""
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
RAN_ANYTHING=0

if [ "$DO_TESTS" = "1" ] && [ "$WANT_ESTATE" = "1" ]; then
    RAN_ANYTHING=1
    echo
    if [ -n "$ESTATE_FILTER" ]; then
        echo -e "${YELLOW}>>> Compiler-service estate (filter: $ESTATE_FILTER)${NC}"
    else
        echo -e "${YELLOW}>>> Compiler-service estate (all rows)${NC}"
    fi
    # The restore MUST re-run with -p:NSharpExcludeTests=false --force-evaluate after any other
    # build, or `dotnet test` silently exits 0 having discovered zero tests.
    if ! dotnet restore $DOTNET_STABLE_FLAGS "$ESTATE_PROJECT" -p:NSharpExcludeTests=false --force-evaluate -v q; then
        echo -e "${RED}✗ Estate restore failed${NC}"
        TEST_EXIT=1
    else
        ESTATE_OUTPUT=$(mktemp)
        ESTATE_RC=0
        if [ -n "$ESTATE_FILTER" ]; then
            dotnet test $DOTNET_STABLE_FLAGS "$ESTATE_PROJECT" -p:NSharpExcludeTests=false --no-restore \
                --filter "FullyQualifiedName~$ESTATE_FILTER" -v q --nologo > "$ESTATE_OUTPUT" 2>&1 || ESTATE_RC=$?
        else
            dotnet test $DOTNET_STABLE_FLAGS "$ESTATE_PROJECT" -p:NSharpExcludeTests=false --no-restore \
                -v q --nologo > "$ESTATE_OUTPUT" 2>&1 || ESTATE_RC=$?
        fi
        if [ "$ESTATE_RC" != "0" ]; then
            cat "$ESTATE_OUTPUT"
            echo -e "${RED}✗ Estate rows failed${NC}"
            TEST_EXIT=$ESTATE_RC
        elif has_nonempty_successful_test_summary "$ESTATE_OUTPUT"; then
            grep -E "Passed!|Failed!|Passed:|Failed:|error" "$ESTATE_OUTPUT" | head -20 || true
            echo -e "${GREEN}✓ Estate rows passed${NC}"
        else
            cat "$ESTATE_OUTPUT"
            report_missing_test_evidence "Estate rows"
            TEST_EXIT=1
        fi
        rm -f "$ESTATE_OUTPUT"
    fi
fi

if [ "$DO_TESTS" = "1" ] && [ -n "${SELECTED_NATIVE// /}" ]; then
    if [ ! -f "$CLI_DLL" ]; then
        echo -e "${RED}✗ $CLI_DLL is missing — run without --no-build${NC}"
        exit 1
    fi

    for dir in $SELECTED_NATIVE; do
        RAN_ANYTHING=1
        echo
        echo -e "${YELLOW}>>> Native project: $dir${NC}"
        if dotnet "$CLI_DLL" test --project "$dir" --no-cache --text; then
            echo -e "${GREEN}✓ $dir passed${NC}"
        else
            TEST_EXIT=$?
            echo -e "${RED}✗ $dir failed${NC}"
        fi
    done
fi

if [ "$DO_TESTS" = "1" ] && [ "$RAN_ANYTHING" = "0" ]; then
    echo -e "${RED}✗ Nothing matched — zero matched tests is not evidence.${NC}"
    echo "    See every slice name with: ./scripts/dev.sh --list"
    exit 2
fi

if [ "$DO_TESTS" = "0" ] && [ "$DO_BUILD" = "1" ]; then
    echo
    echo "No slice selected — built only. Pass a pattern (or --since) to run tests, e.g.:"
    echo "    ./scripts/dev.sh Columnar"
    echo "    ./scripts/dev.sh --since"
    echo "    ./scripts/dev.sh --estate"
fi

END_TIME=$(date +%s)
echo
printf 'Done in %dm %02ds\n' "$(((END_TIME - START_TIME) / 60))" "$(((END_TIME - START_TIME) % 60))"

if [ "$TEST_EXIT" != "0" ]; then
    exit "$TEST_EXIT"
fi

if [ "$RAN_ANYTHING" = "1" ]; then
    echo
    echo -e "${YELLOW}Reminder:${NC} this is the fast inner loop, not the gate."
    if [ "$WANT_ESTATE" = "0" ]; then
        echo "The compiler-service estate was NOT run. Add it with: ./scripts/dev.sh --estate [filter]"
    fi
    echo "Before committing:  VSCODE_TESTS=skip ./scripts/test-all.sh --commit"
fi
