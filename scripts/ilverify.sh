#!/usr/bin/env bash
#
# ilverify.sh - The IL verification gate for N#.
#
# This is the SINGLE SOURCE OF TRUTH for IL verification. It is invoked by
# CI (.github/workflows/build.yml) and by the local full-suite gate
# (tests/scripts/test-all-core.sh). It builds examples, single-file examples,
# and fixtures with `nlc build`, plus the direct-call native tests with `nlc
# test`, then verifies every emitted assembly with BCL/ASP.NET references.
#
# WHY THIS EXISTS: PR #160 shipped GC-unsafe IL that ECMA-335 verification
# would have rejected, but it only crashed at runtime on Linux x64 and CI
# never ran ilverify. This gate makes any new unverifiable IL a deterministic,
# blocking failure on ubuntu-latest, independent of the host CPU/OS.
#
# IMPORTANT: `dotnet ilverify` exits 0 even when it reports verification
# errors (it only returns non-zero on argument/load failures). We therefore
# parse its textual output for errors rather than trusting the exit code, and
# diff the findings against a committed baseline allowlist so the gate fails
# ONLY on NEW errors.
#
# Regenerate the baseline with:   scripts/ilverify.sh --update-baseline
#
# The full local product gate already builds the example/fixture surface before
# invoking this script. It passes exact emitted assemblies through
# `--built-dirs-file <file>` without rebuilding the same projects again.
#
set -euo pipefail

# --------------------------------------------------------------------------
# Colors (suppressed when not a TTY)
# --------------------------------------------------------------------------
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; NC=''
fi

info()  { echo -e "${YELLOW}>>> $1${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
fail()  { echo -e "${RED}✗ $1${NC}"; }

# --------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BASELINE_FILE="$REPO_ROOT/scripts/ilverify-baseline.txt"
CLI_DLL="$REPO_ROOT/src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll"

UPDATE_BASELINE=0
BUILT_DIRS_FILE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --update-baseline)
            UPDATE_BASELINE=1
            shift
            ;;
        --built-dirs-file)
            if [ "$#" -lt 2 ]; then
                fail "--built-dirs-file requires a path argument"
                exit 2
            fi
            BUILT_DIRS_FILE="$2"
            shift 2
            ;;
        --built-dirs-file=*)
            BUILT_DIRS_FILE="${1#--built-dirs-file=}"
            shift
            ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            fail "Unknown argument: $1"
            exit 2
            ;;
    esac
done

# --------------------------------------------------------------------------
# Locate the .NET runtime and ilverify
# --------------------------------------------------------------------------
if ! command -v dotnet >/dev/null 2>&1; then
    fail "The 'dotnet' CLI is not on PATH."
    exit 2
fi

# `dotnet --list-runtimes` is the canonical source for installed shared
# frameworks and their exact paths. Parsing it avoids fragile guesses about
# install layout (Homebrew, apt, manual tarball, and CI images all differ).
# Each line looks like:
#   Microsoft.NETCore.App 10.0.5 [/abs/path/shared/Microsoft.NETCore.App]
# We pick the newest version of each family and derive the per-version dir.
RUNTIMES="$(dotnet --list-runtimes 2>/dev/null || true)"

pick_latest_runtime_dir() {
    # $1 = family name (Microsoft.NETCore.App / Microsoft.AspNetCore.App)
    local family="$1"
    printf '%s\n' "$RUNTIMES" \
        | awk -v fam="$family" '$1 == fam {
            base = $0; sub(/^[^[]*\[/, "", base); sub(/\]$/, "", base);
            print $2 "\t" base "/" $2
          }' \
        | sort -V | tail -1 | cut -f2
}

NETCORE_DIR="$(pick_latest_runtime_dir Microsoft.NETCore.App)"
ASPNET_DIR="$(pick_latest_runtime_dir Microsoft.AspNetCore.App)"

if [ -z "$NETCORE_DIR" ] || [ ! -d "$NETCORE_DIR" ]; then
    fail "No Microsoft.NETCore.App shared framework found via 'dotnet --list-runtimes'."
    echo "    Install the .NET runtime matching global.json."
    exit 2
fi
[ -d "${ASPNET_DIR:-}" ] || ASPNET_DIR=""

# The ilverify apphost needs DOTNET_ROOT to point at the install root (the dir
# containing shared/). Derive it from the resolved NETCore framework dir:
#   <root>/shared/Microsoft.NETCore.App/<ver>  ->  <root>
if [ -z "${DOTNET_ROOT:-}" ]; then
    DOTNET_ROOT="$(cd "$NETCORE_DIR/../../.." && pwd)"
fi
export DOTNET_ROOT

# Resolve the ilverify command: prefer the global tool, fall back to the
# user tools dir which may not be on PATH in minimal shells.
ILVERIFY_BIN=""
if command -v ilverify >/dev/null 2>&1; then
    ILVERIFY_BIN="ilverify"
elif [ -x "$HOME/.dotnet/tools/ilverify" ]; then
    ILVERIFY_BIN="$HOME/.dotnet/tools/ilverify"
else
    fail "dotnet-ilverify is not installed."
    echo "    Install it with: dotnet tool install --global dotnet-ilverify"
    exit 2
fi

info "IL verification gate"
echo "    dotnet root : $DOTNET_ROOT"
echo "    ilverify    : $ILVERIFY_BIN"
echo "    netcore ref : $NETCORE_DIR"
echo "    aspnet ref  : ${ASPNET_DIR:-<none>}"
echo "    baseline    : $BASELINE_FILE"
echo

# --------------------------------------------------------------------------
# Build the CLI compiler if needed
# --------------------------------------------------------------------------
if [ -z "$BUILT_DIRS_FILE" ] && [ ! -f "$CLI_DLL" ]; then
    info "Building N# CLI (compiler)"
    dotnet build "$REPO_ROOT/src/NSharpLang.Cli/Cli.csproj" -v q
fi

# --------------------------------------------------------------------------
# Build the product surface with nlc
# --------------------------------------------------------------------------
# We deliberately build into each project's own bin/ so reference assemblies
# (runtime assets) land next to the output DLL, mirroring `nlc build`'s real
# behavior. Verification then resolves refs from the framework dirs AND from
# the output dir itself.
BUILT_DIRS=()
BUILT_TARGETS=()

build_project() {
    local project_yml="$1"
    local dir
    dir="$(dirname "$project_yml")"
    rm -rf "$dir/bin" "$dir/obj" "$dir/nsharp" 2>/dev/null || true
    if (cd "$dir" && dotnet "$CLI_DLL" build >/dev/null 2>&1); then
        BUILT_DIRS+=("$dir/bin")
        return 0
    fi
    fail "nlc build failed for project: $dir"
    echo "    Reproduce: (cd $dir && dotnet \"$CLI_DLL\" build)"
    return 1
}

build_single_file() {
    local nl_file="$1"
    local dir
    dir="$(dirname "$nl_file")"
    if dotnet "$CLI_DLL" build "$nl_file" >/dev/null 2>&1; then
        BUILT_DIRS+=("$dir/bin")
        return 0
    fi
    fail "nlc build failed for single-file example: $nl_file"
    echo "    Reproduce: dotnet \"$CLI_DLL\" build \"$nl_file\""
    return 1
}

BUILD_FAILED=0

if [ -n "$BUILT_DIRS_FILE" ]; then
    if [ ! -f "$BUILT_DIRS_FILE" ]; then
        fail "Built output manifest not found: $BUILT_DIRS_FILE"
        exit 2
    fi

    info "Using existing example/template/fixture build outputs"
    while IFS= read -r built_output; do
        [ -z "$built_output" ] && continue
        if [ -f "$built_output" ]; then
            BUILT_TARGETS+=("$built_output")
        elif [ -d "$built_output" ]; then
            BUILT_DIRS+=("$built_output")
        else
            fail "Built output not found: $built_output"
            BUILD_FAILED=1
        fi
    done < "$BUILT_DIRS_FILE"

    if [ "$((${#BUILT_TARGETS[@]} + ${#BUILT_DIRS[@]}))" -eq 0 ]; then
        fail "Built output manifest was empty: $BUILT_DIRS_FILE"
        exit 2
    fi

    if [ "$BUILD_FAILED" = "1" ]; then
        fail "One or more expected build outputs were missing; cannot run IL verification."
        exit 1
    fi
else
    info "Building example/template/fixture projects"
    # Include project examples and the canonical end-to-end issue-tracker fixture,
    # which the format/check gates already exercise.
    PROJECT_YMLS="$(
        {
            find examples -name project.yml -type f 2>/dev/null
            find tests/fixtures/issue-tracker -name project.yml -type f 2>/dev/null
        } | sort -u
    )"
    while IFS= read -r project_yml; do
        [ -z "$project_yml" ] && continue
        build_project "$project_yml" || BUILD_FAILED=1
    done <<< "$PROJECT_YMLS"

    info "Building single-file examples"
    # Single .nl files outside project directories (mirrors full-gate Step 9).
    while IFS= read -r nl_file; do
        [ -z "$nl_file" ] && continue
        dir="$(dirname "$nl_file")"
        [ -f "$dir/project.yml" ] && continue
        parent="$(dirname "$dir")"
        [ -f "$parent/project.yml" ] && continue
        build_single_file "$nl_file" || BUILD_FAILED=1
    done < <(find examples -name '*.nl' -type f 2>/dev/null | sort)

    info "Building direct-call native test assembly"
    DIRECT_CALL_TEST_ASSEMBLY="$REPO_ROOT/tests/native/direct-calls/bin/Debug/net10.0/tests/NSharpLang.DirectCalls.Tests.dll"
    if dotnet "$CLI_DLL" test --project "$REPO_ROOT/tests/native/direct-calls" --no-cache --json >/dev/null 2>&1 \
        && [ -f "$DIRECT_CALL_TEST_ASSEMBLY" ]; then
        BUILT_TARGETS+=("$DIRECT_CALL_TEST_ASSEMBLY")
    else
        fail "nlc test failed to emit the direct-call native test assembly"
        BUILD_FAILED=1
    fi
    if [ "$BUILD_FAILED" = "1" ]; then
        fail "One or more nlc builds failed; cannot run IL verification."
        echo "    Fix the build failures above and re-run."
        exit 1
    fi
fi
echo

# --------------------------------------------------------------------------
# Collect every emitted assembly
# --------------------------------------------------------------------------
# Exact product-gate outputs keep copied runtime assets as references, not targets;
# directory discovery remains for standalone/backward-compatible invocation.
TARGETS=()
SEEN=$'\n'     # newline-delimited absolute paths already collected
FRAMEWORK_NAMES=$'\n'  # newline-delimited basenames of framework assemblies
for dll in "$NETCORE_DIR"/*.dll; do FRAMEWORK_NAMES+="$(basename "$dll")"$'\n'; done
if [ -n "$ASPNET_DIR" ]; then
    for dll in "$ASPNET_DIR"/*.dll; do FRAMEWORK_NAMES+="$(basename "$dll")"$'\n'; done
fi
if [ "${#BUILT_TARGETS[@]}" -gt 0 ]; then for built_target in "${BUILT_TARGETS[@]}"; do
    name="$(basename "$built_target")"
    real="$(cd "$(dirname "$built_target")" && pwd)/$name"
    SEEN+="$real"$'\n'
    TARGETS+=("$real")
done; fi

if [ "${#BUILT_DIRS[@]}" -gt 0 ]; then for bin_dir in "${BUILT_DIRS[@]}"; do
    [ -d "$bin_dir" ] || continue
    while IFS= read -r dll; do
        name="$(basename "$dll")"
        # Skip copied framework/runtime reference assemblies (not N# output).
        case "$FRAMEWORK_NAMES" in
            *$'\n'"$name"$'\n'*) continue ;;
        esac
        real="$(cd "$(dirname "$dll")" && pwd)/$name"
        case "$SEEN" in
            *$'\n'"$real"$'\n'*) continue ;;
        esac
        SEEN+="$real"$'\n'
        TARGETS+=("$real")
    done < <(find "$bin_dir" -name '*.dll' -type f 2>/dev/null)
done; fi

if [ "${#TARGETS[@]}" -eq 0 ]; then
    fail "No N# output assemblies found to verify."
    echo "    Expected emitted DLLs under the freshly-built example/fixture bin dirs."
    exit 1
fi

info "Verifying ${#TARGETS[@]} N# assemblies"
echo

# --------------------------------------------------------------------------
# Run ilverify and collect normalized errors
# --------------------------------------------------------------------------
# Normalized error line format (stable, path-independent):
#   <AssemblyName.dll> | <ErrorCode> | <Type::Method-or-detail>
#
# We strip absolute paths and IL offsets so the baseline stays portable
# across machines and CI runners.
RAW_OUTPUT="$(mktemp)"
NORMALIZED="$(mktemp)"
trap 'rm -f "$RAW_OUTPUT" "$NORMALIZED"' EXIT

# Shared reference args (newest NETCore + ASP.NET runtimes).
declare -a FRAMEWORK_REFS=()
for dll in "$NETCORE_DIR"/*.dll; do FRAMEWORK_REFS+=( -r "$dll" ); done
if [ -n "$ASPNET_DIR" ]; then
    for dll in "$ASPNET_DIR"/*.dll; do FRAMEWORK_REFS+=( -r "$dll" ); done
fi

VERIFY_TOOL_ERROR=0
for target in "${TARGETS[@]}"; do
    target_dir="$(dirname "$target")"
    asm_name="$(basename "$target")"

    # Framework/sibling refs plus the `+"..."` guard support bash 3.2 `set -u`.
    local_refs=()
    for sibling in "$target_dir"/*.dll; do
        [ "$sibling" = "$target" ] && continue
        local_refs+=( -r "$sibling" )
    done

    set +e
    "$ILVERIFY_BIN" "$target" \
        -s System.Private.CoreLib \
        "${FRAMEWORK_REFS[@]}" \
        ${local_refs[@]+"${local_refs[@]}"} \
        > "$RAW_OUTPUT" 2>&1
    tool_exit=$?
    set -e
    unset local_refs

    # ilverify outcomes:
    #   * verified clean   -> "... Classes and Methods in <file> Verified."
    #   * verification errs -> "[IL]/[MD]: Error ..." lines + "N Error(s) Verifying"
    #   * INTERNAL CRASH    -> stack trace through ILVerify/Internal.IL with no
    #                          summary (an ilverify bug provoked by unusual but
    #                          loadable IL, e.g. the lock-statement lowering).
    #   * USAGE/LOAD ERROR  -> "Error: No files matching ...", bad system module,
    #                          etc. This is gate MISCONFIGURATION, never IL debt.
    has_summary=0
    if grep -qE '(Error\(s\) Verifying|Classes and Methods in .* Verified\.)' "$RAW_OUTPUT"; then
        has_summary=1
    fi
    if [ "$has_summary" -eq 0 ]; then
        if grep -qE '(at ILVerify\.|at Internal\.IL\.)' "$RAW_OUTPUT"; then
            # ilverify crashed while importing this assembly's IL. Record it as
            # a baseline-able finding so a KNOWN crash does not permanently block
            # the gate, while a NEW crash on a different assembly still fails it.
            # The crash signature itself is evidence of unusual emitted IL.
            crash_kind="$(grep -oE '[A-Za-z.]+Exception' "$RAW_OUTPUT" | head -1)"
            crash_kind="${crash_kind:-UnknownException}"
            fail "ilverify crashed on $asm_name ($crash_kind) — recorded as CRASH finding"
            printf '%s | CRASH | %s\n' "$asm_name" "$crash_kind" >> "$NORMALIZED"
            continue
        fi
        # No summary and no internal stack trace => genuine usage/load failure.
        fail "ilverify could not run on $asm_name (gate misconfiguration)"
        sed 's/^/      /' "$RAW_OUTPUT" | head -8
        VERIFY_TOOL_ERROR=1
        continue
    fi

    # Normalize findings as: <assembly> | <code> | <member-or-detail>.
    # The `|| true` keeps a no-match grep (exit 1) from tripping `set -e`.
    while IFS= read -r line; do
        case "$line" in
            *'[IL]: Error'*)
                code="$(printf '%s' "$line" | sed -E 's/.*\[IL\]: Error \[([^]]*)\].*/\1/')"
                # Member is the second field inside the first [path : member] group.
                member="$(printf '%s' "$line" | sed -E 's/.*\[IL\]: Error \[[^]]*\]: \[[^]]*: ([^]]*)\].*/\1/' | sed -E 's/^ +| +$//g')"
                printf '%s | IL:%s | %s\n' "$asm_name" "$code" "$member"
                ;;
            *'[MD]: Error'*)
                # Metadata errors carry no code/offset; keep the message (minus
                # absolute paths) as the stable detail.
                detail="$(printf '%s' "$line" | sed -E 's/.*\[MD\]: Error: //' | sed -E 's/^ +| +$//g')"
                printf '%s | MD | %s\n' "$asm_name" "$detail"
                ;;
        esac
    done < <(grep -E '\[(IL|MD)\]: Error' "$RAW_OUTPUT" || true) >> "$NORMALIZED"
done

if [ "$VERIFY_TOOL_ERROR" = "1" ]; then
    fail "ilverify failed to run on one or more assemblies (see above)."
    exit 1
fi

# Sort + dedupe for a stable, diffable signature.
sort -u "$NORMALIZED" -o "$NORMALIZED"

# --------------------------------------------------------------------------
# Baseline handling
# --------------------------------------------------------------------------
if [ "$UPDATE_BASELINE" = "1" ]; then
    {
        echo "# ilverify baseline allowlist for N#"
        echo "#"
        echo "# Each non-comment line is a KNOWN/EXPECTED IL verification finding,"
        echo "# normalized as:  <Assembly.dll> | <kind> | <detail>"
        echo "#   kind = IL:<Code>  ECMA-335 verification error (e.g. IL:StackUnexpected)"
        echo "#   kind = MD          metadata error (e.g. missing interface method)"
        echo "#   kind = CRASH       ilverify itself crashed importing this assembly"
        echo "#"
        echo "# The gate (scripts/ilverify.sh) fails only on findings NOT listed here,"
        echo "# so it blocks NEW unverifiable IL (the PR #160 regression class)."
        echo "# Keep this file as close to EMPTY as possible: every entry is real debt."
        echo "# Regenerate with: scripts/ilverify.sh --update-baseline (review the diff!)."
        echo "#"
        echo "# Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "#"
        cat "$NORMALIZED"
    } > "$BASELINE_FILE"
    ok "Baseline updated: $BASELINE_FILE ($(wc -l < "$NORMALIZED" | tr -d ' ') findings)"
    exit 0
fi

# Build the effective baseline (strip comments/blank lines), sorted.
BASELINE_NORMALIZED="$(mktemp)"
trap 'rm -f "$RAW_OUTPUT" "$NORMALIZED" "$BASELINE_NORMALIZED"' EXIT
if [ -f "$BASELINE_FILE" ]; then
    grep -vE '^\s*#|^\s*$' "$BASELINE_FILE" | sort -u > "$BASELINE_NORMALIZED" || true
else
    : > "$BASELINE_NORMALIZED"
fi

# NEW errors  = findings present now but not in the baseline.
# STALE allows = baseline entries no longer reproduced (informational; the
#                gate does not fail on these but reports them so we can prune).
NEW_ERRORS="$(comm -23 "$NORMALIZED" "$BASELINE_NORMALIZED")"
STALE_ALLOWS="$(comm -13 "$NORMALIZED" "$BASELINE_NORMALIZED")"

if [ -n "$STALE_ALLOWS" ]; then
    info "Baseline entries no longer reproduced (consider pruning with --update-baseline):"
    printf '%s\n' "$STALE_ALLOWS" | sed 's/^/    /'
    echo
fi

if [ -n "$NEW_ERRORS" ]; then
    fail "NEW IL verification errors detected (not in baseline):"
    echo
    printf '%s\n' "$NEW_ERRORS" | sed 's/^/    /'
    echo
    echo -e "${RED}These assemblies contain unverifiable IL.${NC} This is the class of bug"
    echo "that crashed on Linux x64 in PR #160. Fix the active N# IL emission path"
    echo "so the assembly verifies, OR — only if"
    echo "the finding is genuinely benign and expected — record it in the baseline:"
    echo
    echo "    scripts/ilverify.sh --update-baseline   # then review the diff carefully"
    echo
    exit 1
fi

ok "All ${#TARGETS[@]} N# assemblies pass IL verification (no new errors vs baseline)."
exit 0
