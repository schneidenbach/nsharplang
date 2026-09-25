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
# THE LANGUAGE SERVER IS BUILT HERE ON PURPOSE. Three native projects take
# src/NSharpLang.LanguageServer/bin/Debug/net10.0/LanguageServer.dll as a `dll:` dependency, and until
# the C# unit suite was retired that dll arrived as a side effect of the deleted Step 3 building
# tests/Tests.csproj, which project-referenced it. Naming it here is the difference between a
# reproducible gate and one that passes only on a machine that happens to have built it.
echo "Building compiler, CLI, Build.Tasks, the language server three native projects take as a dll: dependency, and the playground a fourth one takes..."
if dotnet build $DOTNET_STABLE_FLAGS src/NSharpLang.Cli/Cli.csproj -v q \
    && dotnet build $DOTNET_STABLE_FLAGS src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj -v q \
    && dotnet build $DOTNET_STABLE_FLAGS src/NSharpLang.LanguageServer/LanguageServer.csproj -v q \
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
    dotnet "$CLI_DLL" format --project src/NSharpLang.Compiler.Model --check || format_rc=1
    dotnet "$CLI_DLL" format --project src/NSharpLang.Compiler.Syntax --check || format_rc=1
    dotnet "$CLI_DLL" format --project src/NSharpLang.Compiler.Core --check || format_rc=1
} > "$FORMAT_OUTPUT" 2>&1
cat "$FORMAT_OUTPUT"
if [ "$format_rc" -eq 0 ]; then
    handle_success "Formatting gate"
else
    handle_error "Formatting gate"
fi
rm -f "$FORMAT_OUTPUT"

# The throughput gate measures its own reference. Each of the twelve cells runs the live kernel and a
# frozen control interleaved in one process, and gates on their ratio, so the verdict no longer
# depends on this host resembling the idle Apple M4 that a stored baseline was taken on -- which it
# repeatedly did not, failing cells at 1.2x-4.0x whenever another build was running. The step still
# runs immediately after build/format, before prolonged self-host/test phases: the gate also prints
# an INFORMATIONAL drift row against those 2026-09-01 numbers, which is only interesting on a
# machine this gate has not yet preconditioned, and an early benchmark failure is cheap.
section "Step 2c: Systems Throughput Gate"
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

section "Step 2d: Self-Host Front Door"
# THE COMPILER'S OWN SOURCE, THROUGH THE COMPILER'S OWN FRONT DOOR.
#
# Everything else in this gate compiles `src/NSharpLang.Compiler.Core` with the PINNED stage-0 seed
# in `bootstrap/`, through the SDK's emit-only path -- which does not run analysis at all. So the
# compiler at tip could stop being able to compile its own source and nothing here would notice. It
# happened: four `while true { ... return ... }` loops carried a dead trailing `return` that the old
# seed accepted and the tip refuses, and the failure surfaced only when the seed was being
# republished by hand.
#
# This step closes that blind spot by running `nlc check` -- the real front door, analysis, lint and
# all -- over the compiler's own projects with the CLI this gate just built, and refusing any
# INCREASE in what it reports.
#
# IT IS A RATCHET, NOT A ZERO. The front door currently reports a large, classified backlog on Core's
# own source (unused and missing imports, nullable arguments passed where non-nullable is declared,
# definite-assignment holes) that the emit-only path never asked about. The ceilings below are that
# backlog, measured; they exist to go DOWN and must never be raised to accommodate new source. A
# change that adds a front-door diagnostic to the compiler's own source fails here, which is exactly
# the event nothing could catch before.
#
# `src/NSharpLang.Build.Tasks` has no N# sources yet (it is MSBuild targets plus C# tasks), so it is
# listed and checked rather than assumed: the day it grows one, this step covers it.
#
# `src/NSharpLang.Compiler.Model` and `src/NSharpLang.Compiler.Syntax`, the slices carved out of Core
# so far, are checked before it, lowest first: Core builds them as project references (Syntax builds
# Model the same way), so each one's own count must stay 0 for the next one's to be readable.
#
# COST: the whole step is dominated by Core, whose front door walks 952 files. It sits inside the
# validated step cache on the UNIT input set, so it runs only when the compiler's own sources move.
if step_cache_hit "self-host-front-door" "$UNIT_INPUTS_HASH"; then
    step_skip_banner "self-host-front-door" "$UNIT_INPUTS_HASH"
    handle_success "Self-host front door (validated step cache)"
else
    echo "Checking the compiler's own projects with the CLI this gate built..."
    SELF_HOST_PROJECTS=(
        "src/NSharpLang.Compiler.Model"
        "src/NSharpLang.Compiler.Syntax"
        "src/NSharpLang.Compiler.Core"
        "src/NSharpLang.Compiler"
        "src/NSharpLang.Playground"
        "src/NSharpLang.Build.Tasks"
    )
    # Measured on the tip CLI; the classification behind each number is in memory/README.md.
    #
    # 2026-09-22, the Compiler.Core compression campaign (PRs 1-4 of the Fable audit): 1,318,
    # carried by 279 of the project's files, down from 1,340. The four PRs ADDED fourteen NL010s -- a
    # deleted duplicate leaves the import that served it unused -- and removing those plus the
    # twenty-two other unused imports already sitting in the same files took the total to 1,318. No
    # other class moved: NL905 424, NL202 352, NL002 239, NL010 165 (was 201 at the peak, 186
    # before), NL012 38, NL011 30, NL304 28.
    #
    # 2026-09-23, PRs 5-7 of the same audit (the emit context, the loop sweep, the node kinds):
    # 1,317, still carried by 279 files. Measured with the tip CLI against BOTH trees -- the base
    # source reports 1,318 through the same front door, so the compiler changed no answer -- the
    # diff is zero additions and one removal: the NL905 on `initCtor` in `ColumnarIlEmitter.nl`,
    # whose `initCtor.Body.SourceFileId` was dereferenced twice by the hand-threaded sibling view
    # and holder slot and is dereferenced once now that `ColumnarEmitContext.ForSourceFile` derives
    # both from one file id. NL905 424 -> 423; no other class moved.
    #
    # 2026-09-23, PRs 8-10 of the same audit (the accessor-to-property sweep, the per-type families,
    # the parser-kernel split): 1,314, carried by 278 of the project's files. Measured with the tip
    # CLI against BOTH trees the way `c751edd7e` established -- the base source (`738996c29`)
    # reports 1,317 through the same front door -- the diff is zero additions and three removals.
    # Two are NL905 in `ColumnarIlEmitter.nl`, on `bclInitializerSetterForOpcode` and
    # `bclMemberInitializerSetterForOpcode`: the source already guards `property.SetMethod == null`
    # above each one, and written `property.get_SetMethod() == null` that guard narrowed nothing,
    # because flow narrowing tracks a member read and cannot track a call. The third is the NL002 on
    # the deleted `ColumnarParserKernels.nl` for a `List` used without the import that provides it --
    # the split gives each of the twelve new files the imports it actually uses. NL905 423 -> 421,
    # NL002 239 -> 238; NL202 352, NL010 165, NL012 38, NL011 30 and NL304 28 are all unmoved.
    #
    # 2026-09-24, before Compiler.Model is carved out of Core: 1,291, carried by 270 of the
    # project's files. Model's product files carried 23 of the 1,314 and are now clean, because once
    # Model is its own project its diagnostics block Core's check (the reference build fails) rather
    # than counting in it. Measured with the same tip CLI against both trees, the diff over
    # diagnostic identities is zero additions and 23 removals: NL011 8, NL010 5, NL002 4, NL012 4 and
    # NL905 2, every one in a Model product file. NL905 421 -> 419, NL002 238 -> 234, NL010 165 ->
    # 160, NL012 38 -> 34, NL011 30 -> 22; NL202 352 and NL304 28 are unmoved.
    #
    # 2026-09-24, name lookup over referenced assemblies (`SimpleNamePrecedence.Select`): 1,283. The
    # eight NL209 ties the compiler's own source carried -- `Version` and `EventInfo` between System
    # and YamlDotNet, `ParameterModifier` between the Ast and System.Reflection -- are spelled in
    # full, because the emitter now refuses a tie the way the analyzer always reported it rather
    # than binding whichever import was written first; `import YamlDotNet.Core`, whose only use was
    # the tie, goes. Identity diff against 1,291: zero additions, eight NL209 removals.
    #
    # 2026-09-24, referenced-assembly operands and constructor arguments (`census/xasm`): 1,281. The
    # external-construction door that replaced the contextual-only one binds its selection to
    # null-checked locals and declares its canonical-name slot as the `string` the builder writes, so
    # the NL202 on `out canonical` and an NL905 on the parameter-type index the old door carried are
    # gone. Identity diff against 1,283: zero additions, two removals (NL202 352 -> 351, NL905 419 -> 418).
    #
    # 2026-09-24, Compiler.Model carved out of Core into its own project (`census/model`): Model 0,
    # checked FIRST, because Core takes it as a `project:` reference and a diagnostic in Model would
    # BLOCK Core's check rather than count in it -- its zero is what keeps Core's number a number.
    # Core 1,281, unchanged, and the identity diff against the base tree through the same tip CLI is
    # zero additions and zero removals. The carve first measured 1,214 -- 68 NL202s gone and one false
    # NL402 added -- because the analyzer judged a REFERENCED class type more loosely than a source
    # one; that was fixed in the analyzer (a maybe-null value of a non-framework referenced class
    # type is refused where the same source type is, and a bare one is not-null), not ratcheted.
    #
    # 2026-09-24, Compiler.Syntax carved out of Core into its own project, rows included
    # (`census/syntax`): Model 0, Syntax 0 and Core 1,261, checked in that order because each takes
    # the one before it as a `project:` reference. Syntax reached zero at the source first -- the
    # NL012 on `ParseTypeBody`'s unread `name`, and its estate's 16 (NL010 9, NL907 4, NL905 2, NL202
    # 1) plus the NL010 splitting the formatter rows off two parser files left -- so the identity diff
    # against the base tree (1,279) through the same tip CLI is zero additions and 18 removals (NL010 10,
    # NL907 4, NL905 2, NL202 1, NL012 1), every one a source fix, and against the pre-carve tree zero
    # and zero. The carve first measured 36,701 -- every Model name unresolved, because `nlc` did not
    # compile against a project reference's own project references and Core now reaches Model only
    # through Syntax -- and then 1,325, the 62 NL002s a SOURCE type's project-wide discovery had
    # answered for `ColumnarParserRecovery`, `ColumnarNodeTable` and `ColumnarExpressionNodeKind`;
    # the first was fixed in the resolver, the second by the imports NL002 asks for.
    #
    # 2026-09-25, before Compiler.Driver is carved out of Core: Core 1,205. Driver's own files carried
    # 56 of the 1,261 (NL002 18, NL905 12, NL011 8, NL010 8, NL202 7, NL012 2, NL907 1) and are now
    # clean, because once Driver is its own project it sits ABOVE Core: its check begins by building
    # Core as a project reference, so its own count cannot be read while Core's is above zero, and
    # it has to start at zero rather than carry debt no step can see. Measured with the same tip CLI
    # against both trees, the identity diff is zero additions and those 56 removals, every one in a
    # Driver file.
    #
    # -1 means BLOCKED, not clean. `check` on a project that REFERENCES Compiler.Core builds that
    # reference first, and that build fails while Core's own front door is not clean -- so those two
    # produce an error envelope instead of a diagnostic list and there is nothing to count yet. The
    # step prints the reason and moves on; the day Core reaches 0 their ceilings become real numbers
    # and their own sources (zero diagnostics today, measured through `--text`) are covered too.
    SELF_HOST_CEILINGS=(
        0
        0
        1205
        -1
        -1
        0
    )
    # The count and the per-code breakdown are read out of the check document here rather than from a
    # helper script: a new Python file is a CODE row in the ownership ratchet and would need a new
    # epoch, not a repin. A crashed check leaves an unreadable document, which prints a reason and
    # fails the step rather than counting as zero.
    SELF_HOST_READ_COUNT='
import collections, json, sys
try:
    document = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as error:
    print(f"unreadable: {type(error).__name__}: {error}")
    raise SystemExit(0)
failure = document.get("error")
if failure is not None:
    print("failed: " + str(failure.get("message", failure)).splitlines()[0])
    raise SystemExit(0)
results = document.get("results") or []
if "--by-code" in sys.argv[2:]:
    counts = collections.Counter(str(entry.get("code", "?")) for entry in results)
    for code, total in sorted(counts.items(), key=lambda pair: (-pair[1], pair[0])):
        print(f"    {total:5} {code}")
else:
    print(len(results))
'
    SELF_HOST_OK=1
    # What the front door measured for Compiler.Core itself, in THIS run. It decides whether a
    # project that REFERENCES Core can produce a diagnostic list at all: `check` resolves references
    # with BuildProjectReferences on, so a referencing project's check first builds Core from source,
    # and that build cannot succeed while Core's own front door is not clean. Empty until Core has
    # been checked -- Core is first in the array above, and if that ever stops being true the
    # referencing projects are checked for real rather than skipped on an unread number.
    SELF_HOST_CORE_COUNT=""
    for ((self_host_index = 0; self_host_index < ${#SELF_HOST_PROJECTS[@]}; self_host_index++)); do
        SELF_HOST_PROJECT="${SELF_HOST_PROJECTS[$self_host_index]}"
        SELF_HOST_CEILING="${SELF_HOST_CEILINGS[$self_host_index]}"
        # STRUCTURALLY UNREACHABLE WORK IS NOT PERFORMED. A BLOCKED project (ceiling -1) whose block
        # is already proven by Core's own nonzero count would spend a full front-end compile of all
        # of Core to arrive at the same BLOCKED line: about 2 minutes each, for a number the step
        # itself records as "not counted yet". The row is printed with the reason it is blocked
        # instead. The day Core reaches 0 diagnostics this guard stops firing on its own and both
        # projects are checked for real, which is exactly when their -1 ceilings become real numbers.
        if [ "$SELF_HOST_CEILING" -lt 0 ] \
            && [[ "$SELF_HOST_CORE_COUNT" =~ ^[0-9]+$ ]] \
            && [ "$SELF_HOST_CORE_COUNT" -gt 0 ]; then
            echo "  $SELF_HOST_PROJECT: BLOCKED behind Compiler.Core's own front door; not counted yet (not attempted: src/NSharpLang.Compiler.Core reported $SELF_HOST_CORE_COUNT diagnostics through this same front door, so the project-reference build this check begins with cannot succeed)."
            continue
        fi
        SELF_HOST_OUTPUT=$(mktemp)
        dotnet "$CLI_DLL" check --project "$SELF_HOST_PROJECT" --json > "$SELF_HOST_OUTPUT" 2>&1 || true
        SELF_HOST_COUNT=$(python3 -c "$SELF_HOST_READ_COUNT" "$SELF_HOST_OUTPUT")
        if [ "$SELF_HOST_PROJECT" = "src/NSharpLang.Compiler.Core" ]; then
            SELF_HOST_CORE_COUNT="$SELF_HOST_COUNT"
        fi
        if [ "$SELF_HOST_CEILING" -lt 0 ]; then
            echo "  $SELF_HOST_PROJECT: BLOCKED behind Compiler.Core's own front door; not counted yet ($SELF_HOST_COUNT)."
        elif [[ ! "$SELF_HOST_COUNT" =~ ^[0-9]+$ ]]; then
            echo "  $SELF_HOST_PROJECT: check produced no readable JSON ($SELF_HOST_COUNT)"
            head -c 2000 "$SELF_HOST_OUTPUT"
            SELF_HOST_OK=0
        elif [ "$SELF_HOST_COUNT" -gt "$SELF_HOST_CEILING" ]; then
            echo "  $SELF_HOST_PROJECT: $SELF_HOST_COUNT diagnostics, ceiling $SELF_HOST_CEILING - the compiler's own source got WORSE through its own front door."
            python3 -c "$SELF_HOST_READ_COUNT" "$SELF_HOST_OUTPUT" --by-code
            SELF_HOST_OK=0
        elif [ "$SELF_HOST_COUNT" -lt "$SELF_HOST_CEILING" ]; then
            echo "  $SELF_HOST_PROJECT: $SELF_HOST_COUNT diagnostics, below the ceiling of $SELF_HOST_CEILING - lower the ceiling in tests/scripts/test-all-core.sh."
        else
            echo "  $SELF_HOST_PROJECT: $SELF_HOST_COUNT diagnostics (at the ceiling)."
        fi
        rm -f "$SELF_HOST_OUTPUT"
    done

    if [ "$SELF_HOST_OK" -eq 1 ]; then
        handle_success "Self-host front door"
        step_cache_store "self-host-front-door" "$UNIT_INPUTS_HASH"
    else
        handle_error "Self-host front door"
    fi
fi

# STEP 3 WAS THE C# UNIT SUITE AND IS RETIRED. `tests/*.cs` and `tests/Tests.csproj` are gone: every
# assertion they carried now lives either in the compiler-service estate or in a tests/native project,
# both of which Step 3a below already runs. Step 3a KEEPS ITS NAME rather than being renumbered —
# a dozen .nl comments and memory/testing.md cite "Step 3a" by name, and renaming a step to close a
# numbering gap would invalidate all of them for nothing.

section "Step 3a: Run Native N# Tests"
if step_cache_hit "native-nsharp-tests" "$UNIT_INPUTS_HASH"; then
    step_skip_banner "native-nsharp-tests" "$UNIT_INPUTS_HASH"
    handle_success "Native N# tests (validated step cache)"
else
    echo "Running the gated compiler-service and product .tests.nl estate..."
    NATIVE_STEP_OK=1
    # Every project whose own directory holds estate rows, lowest slice first: a slice carved out of
    # Compiler.Core whose rows reach only itself and the slices below it carries them into its own
    # project (Compiler.Syntax does); the rest still sit in Core's slice directories. Each is restored
    # and run on its own, and each must show its own nonempty, failure-free summary.
    BOOTSTRAP_TEST_PROJECTS=(
        "src/NSharpLang.Compiler.Syntax/NSharpLang.Compiler.Syntax.csproj"
        "src/NSharpLang.Compiler.Core/NSharpLang.Compiler.Core.csproj"
    )
    for BOOTSTRAP_TEST_PROJECT in "${BOOTSTRAP_TEST_PROJECTS[@]}"; do
        BOOTSTRAP_TEST_NAME="$(basename "$BOOTSTRAP_TEST_PROJECT" .csproj)"
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
            handle_success "Native N# tests: compiler-service contracts ($BOOTSTRAP_TEST_NAME)"
        else
            cat "$BOOTSTRAP_TEST_OUTPUT"
            handle_error "Native N# tests: compiler-service contracts ($BOOTSTRAP_TEST_NAME)"
            NATIVE_STEP_OK=0
        fi
        rm -f "$BOOTSTRAP_TEST_OUTPUT"
    done

    NATIVE_PROJECTS=$(
        while IFS= read -r native_project; do
            native_dir=$(dirname "$native_project")
            if find "$native_dir" -maxdepth 1 -name "*.tests.nl" -type f -print -quit | grep -q .; then
                printf '%s\n' "$native_project"
            fi
        done < <(find examples tests -name "project.yml" -type f 2>/dev/null | sort)
    )
    # THE SWEEP RUNS IN PARALLEL, WITH A PINNED SERIAL GROUP IN FRONT OF IT.
    #
    # 129 projects, one `nlc test` PROCESS each, ran strictly one at a time and cost about 17
    # minutes of a 33-minute gate. Steps 8, 9 and 10 in this same file already run their per-project
    # work under `xargs -P "$MAX_JOBS"` with a numbered results directory, and this block now uses
    # the same pattern: each worker writes its own files, and the PARENT replays every project in
    # discovery order, so the log reads exactly as it did when the loop was sequential.
    #
    # Two things stay serial, both because they read or write state that is NOT per-project:
    #   * a project whose claim is about the MACHINE (`compile-time-bench` reads the one-minute load
    #     average and measures latency against a baseline);
    #   * a project that mutates or depends on state outside its own directory - daemon sockets and
    #     `~/.nsharp`, the shared NuGet cache through a real `dotnet restore`/`dotnet build`, the
    #     installers, or a walk of the whole working tree that concurrent `bin`/`obj` writes would
    #     perturb.
    # The serial group also runs FIRST, which warms the NuGet cache before anything runs in
    # parallel - the same race Step 8 avoids with its single warm-up build at :750.
    #
    # Every `dll:` dependency these projects name is a prebuilt binary under `src/*/bin/Debug/...`
    # produced ONCE, serially, by Step 2 (Cli, Build.Tasks, LanguageServer, Playground; the Cli
    # build carries Compiler, Compiler.Core, TestHost and the Runtime with it). Nothing in this step
    # builds them, so no two workers can race to produce one. The preflight below proves they are
    # all present before the first worker starts, rather than letting 120 parallel processes each
    # discover the same missing file.
    native_requires_serial_run() {
        case "$1" in
            # Reads `sysctl -n vm.loadavg` and judges a median against a baseline measured on an
            # idle machine: it may not run beside seven siblings.
            tests/native/compile-time-bench) return 0 ;;
            # Starts daemons, binds their sockets and writes their state outside the project.
            tests/native/daemon-command) return 0 ;;
            # Runs the installers, the reseed fixtures and `scripts/dev.sh` as PROCESSES.
            tests/native/gate-script-contracts) return 0 ;;
            # Real `dotnet` restores/builds against a package cache: keep them off each other.
            tests/native/compilation-backend) return 0 ;;
            # `dotnet pack` of the in-repo `NSharpLang.Sdk` and `NSharpLang.Runtime` projects. That
            # pack is not confined to its own output directory: the SDK project-references
            # Build.Tasks and the Runtime and MSBuilds Build.Tasks for its `tools/` payload, so it
            # WRITES the shared `src/*/obj` and `src/*/bin`. Run beside its neighbour in discovery
            # order -- `tests/native/sdk-pack-symbol-contract`, which packs the same two projects --
            # it lost one row of 28 to an MSBuild file lock. The project now packs once per process
            # instead of once per row, and this step hands it a feed it packed itself, so under the
            # gate it packs nothing at all - but a run that supplies no feed still packs, so the
            # serial slot stays. With it here, nothing left in the parallel group packs an in-repo
            # project even when the shared feed is unavailable.
            tests/native/sdk-project-reference-boundary) return 0 ;;
            # Builds a two-project MSBuild tree twice over against the same private feed and judges
            # which emits RAN: a sibling writing `src/*/obj` under it would change that answer.
            tests/native/sdk-reference-incrementality) return 0 ;;
            tests/native/nuget-resolution-fidelity) return 0 ;;
            tests/native/reference-resolution) return 0 ;;
            tests/native/sdk-emit-path-parity) return 0 ;;
            tests/native/template-project-smoke) return 0 ;;
            # Packs this whole checkout, runs `scripts/publish-toolset.sh`, then builds a Docker image
            # and drives a container. The packs write the shared `src/*/obj` and `src/*/bin` the same
            # way its neighbours' do, and the container it starts binds a FIXED name.
            tests/native/installed-toolchain-integration) return 0 ;;
            # Walks the whole working tree and counts what it finds there.
            tests/native/ownership-audit) return 0 ;;
            *) return 1 ;;
        esac
    }

    # The validator is the one that guarded the sequential loop, moved into the worker verbatim. It
    # is carried as a string here and written to the throwaway results directory below rather than
    # added to the repository, for the same reason `SELF_HOST_READ_COUNT` is a string: a new Python
    # FILE under version control would be a CODE row in the ownership ratchet.
    NATIVE_READ_SUMMARY='
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
'

    # THE SWEEP'S DURABLE RECORD. The `project=<dir> seconds=<n>` lines are the only per-project cost
    # the log keeps, and a wall-clock second cannot say whether a project spent it compiling or
    # running. `nlc test --timings` splits the two, and this reader - a string for the same reason
    # `NATIVE_READ_SUMMARY` is one - writes the split, the outcome and the row counts of every project to
    # `artifacts/native-sweep/<UTC time>.json`, then prints the totals so the file reconciles
    # against the per-project summary lines above it. `artifacts/` is gitignored and excluded from the
    # isolated copy; `tests/scripts/test-all.sh` carries the record back to the source tree. Best
    # effort by construction: a record that cannot be written is reported, never a failed step.
    NATIVE_RECORD_SWEEP='
import datetime
import json
import os
import sys

results_dir, list_path, artifacts_root = sys.argv[1], sys.argv[2], sys.argv[3]

def read_envelope(path):
    try:
        with open(path, encoding="utf-8") as stream:
            payload = json.load(stream)
        return payload if isinstance(payload, dict) else {}
    except (OSError, ValueError):
        return {}

def non_negative_int(value):
    return value if type(value) is int and value >= 0 else None

projects = []
with open(list_path, encoding="utf-8") as listing:
    for line in listing:
        line = line.strip()
        if not line:
            continue
        index, project = line.split("|", 1)
        status, seconds = "missing", None
        try:
            with open(os.path.join(results_dir, index + ".result"), encoding="utf-8") as result:
                recorded_status, recorded_seconds = result.read().strip().split("|", 1)
            status = "passed" if recorded_status == "OK" else "failed"
            seconds = int(recorded_seconds)
        except (OSError, ValueError):
            pass
        envelope = read_envelope(os.path.join(results_dir, index + ".json"))
        summary = envelope.get("summary") if isinstance(envelope.get("summary"), dict) else {}
        timings = envelope.get("timings") if isinstance(envelope.get("timings"), dict) else {}
        projects.append({
            "project": project,
            "status": status,
            "wallSeconds": seconds,
            "buildMs": non_negative_int(timings.get("buildMs")),
            "runMs": non_negative_int(timings.get("runMs")),
            "totalMs": non_negative_int(timings.get("totalMs")),
            "tests": non_negative_int(summary.get("total")),
            "passed": non_negative_int(summary.get("passed")),
            "failed": non_negative_int(summary.get("failed")),
            "skipped": non_negative_int(summary.get("skipped")),
        })

def total(key):
    return sum(project[key] or 0 for project in projects)

recorded_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
record = {
    "schemaVersion": 1,
    "recordedAtUtc": recorded_at.isoformat().replace("+00:00", "Z"),
    "summary": {
        "projects": len(projects),
        "passedProjects": sum(1 for project in projects if project["status"] == "passed"),
        "failedProjects": sum(1 for project in projects if project["status"] != "passed"),
        "tests": total("tests"),
        "passed": total("passed"),
        "failed": total("failed"),
        "skipped": total("skipped"),
        "buildMs": total("buildMs"),
        "runMs": total("runMs"),
        "wallSeconds": total("wallSeconds"),
    },
    "projects": projects,
}

directory = os.path.join(artifacts_root, "native-sweep")
path = os.path.join(directory, recorded_at.strftime("%Y%m%dT%H%M%SZ") + ".json")
os.makedirs(directory, exist_ok=True)
with open(path, "w", encoding="utf-8") as stream:
    json.dump(record, stream, indent=2)
    stream.write("\n")

totals = record["summary"]
print("Native sweep record: {path} - {projects} projects ({failedProjects} failed), {tests} tests (Passed: {passed}, Failed: {failed}, Skipped: {skipped}), build {buildMs} ms, run {runMs} ms".format(path=os.path.relpath(path), **totals))
'

    NATIVE_WORKER='
entry="$1"
results_dir="$2"
cli_dll="$3"
reader="$4"
idx="${entry%%|*}"
native_dir="${entry#*|}"
native_start=$(date +%s)
native_output="$results_dir/$idx.json"
native_stderr="$results_dir/$idx.err"
native_summary="$results_dir/$idx.summary"
native_status=FAIL
# --json is a stdout contract: warnings and progress go to stderr and must not reach the parser.
# --timings adds the `timings` object (build, run, total) to the envelope; the sweep record reads it.
if dotnet "$cli_dll" test --project "$native_dir" --no-cache --json --timings \
        > "$native_output" 2> "$native_stderr" \
    && python3 "$reader" "$native_output" > "$native_summary" 2>&1; then
    native_status=OK
fi
printf "%s|%s\n" "$native_status" "$(($(date +%s) - native_start))" > "$results_dir/$idx.result"
'

    # ONE PRIVATE SDK FEED FOR THE WHOLE SWEEP, PACKED BEFORE THE FIRST PROJECT RUNS.
    #
    # `tests/native/sdk-project-reference-boundary`, `tests/native/sdk-pack-symbol-contract`,
    # `tests/native/sdk-emit-path-parity` and `tests/native/sdk-reference-incrementality` each need a
    # private feed holding this tree's `NSharpLang.Sdk` and `NSharpLang.Runtime`, and each builds one
    # by running `dotnet pack` over the two in-repo projects. All four read
    # `NSHARP_SDK_PROJECT_REFERENCE_FEED` and
    # `NSHARP_SDK_PROJECT_REFERENCE_VERSION` FIRST, exactly so a runner that already packed one can
    # hand it over - their fixtures say so in as many words.
    #
    # That pack is not confined to its own output directory: `NSharpLang.Sdk.csproj`
    # project-references Build.Tasks and the Runtime and MSBuilds Build.Tasks for its `tools/`
    # payload, so every pack WRITES the shared `src/*/obj` and `src/*/bin`. Two of them overlapping
    # is an MSBuild file lock, and that is not hypothetical: the boundary project lost one row of 28
    # to `System.IO.IOException: The process cannot access the file
    # 'src/NSharpLang.Runtime/bin/Release/net10.0/NSharpLang.Runtime.deps.json' because it is being
    # used by another process`. Packed once HERE - by the parent, before any worker exists - the
    # pack cannot overlap anything, and the three projects stop paying for it three times.
    #
    # A feed supplied from outside is honored untouched; only a feed this step packed is deleted
    # again below.
    if [ -z "${NSHARP_SDK_PROJECT_REFERENCE_FEED:-}" ] || [ -z "${NSHARP_SDK_PROJECT_REFERENCE_VERSION:-}" ]; then
        NATIVE_SDK_FEED=$(mktemp -d)
        NATIVE_SDK_FEED_VERSION="0.1.0-nativesweep$(date +%s)-$$"
        if dotnet pack src/NSharpLang.Runtime/NSharpLang.Runtime.csproj -o "$NATIVE_SDK_FEED" \
                -p:Version=0.1.0 $DOTNET_STABLE_FLAGS -v q \
            && dotnet pack src/NSharpLang.Sdk/NSharpLang.Sdk.csproj -o "$NATIVE_SDK_FEED" \
                -p:Version="$NATIVE_SDK_FEED_VERSION" $DOTNET_STABLE_FLAGS -v q; then
            export NSHARP_SDK_PROJECT_REFERENCE_FEED="$NATIVE_SDK_FEED"
            export NSHARP_SDK_PROJECT_REFERENCE_VERSION="$NATIVE_SDK_FEED_VERSION"
            handle_success "Native N# tests: shared private SDK feed"
        else
            handle_error "Native N# tests: shared private SDK feed"
            NATIVE_STEP_OK=0
        fi
    fi

    if [ -z "$NATIVE_PROJECTS" ]; then
        handle_error "Native N# tests (no projects found)"
        NATIVE_STEP_OK=0
    else
        NATIVE_MAX_JOBS="$MAX_JOBS"
        if [ "$NATIVE_MAX_JOBS" -gt 6 ]; then
            NATIVE_MAX_JOBS=6
        fi

        # PREFLIGHT: every `dll:` dependency named by the projects about to run must already exist.
        NATIVE_MISSING_DLLS=$(
            grep -h -E "^[[:space:]]*-[[:space:]]*dll:" $(printf '%s\n' "$NATIVE_PROJECTS") 2>/dev/null \
                | sed -E "s|^[[:space:]]*-[[:space:]]*dll:[[:space:]]*||" \
                | sed -E "s|^\.\./\.\./\.\./||" \
                | sort -u \
                | while IFS= read -r dll_path; do
                    if [ "${dll_path#src/}" != "$dll_path" ] && [ ! -f "$dll_path" ]; then
                        printf '%s\n' "$dll_path"
                    fi
                done
        )
        if [ -n "$NATIVE_MISSING_DLLS" ]; then
            echo "These shared dependencies are named by a native project but were not built by Step 2:"
            printf '  %s\n' $NATIVE_MISSING_DLLS
            handle_error "Native N# tests (missing shared dependencies)"
            NATIVE_STEP_OK=0
        fi

        NATIVE_RESULTS_DIR=$(mktemp -d)
        NATIVE_READER="$NATIVE_RESULTS_DIR/read-summary.py"
        printf '%s\n' "$NATIVE_READ_SUMMARY" > "$NATIVE_READER"
        NATIVE_LIST="$NATIVE_RESULTS_DIR/items.txt"
        NATIVE_SERIAL_LIST="$NATIVE_RESULTS_DIR/serial.txt"
        NATIVE_PARALLEL_LIST="$NATIVE_RESULTS_DIR/parallel.txt"
        : > "$NATIVE_LIST"
        : > "$NATIVE_SERIAL_LIST"
        : > "$NATIVE_PARALLEL_LIST"
        native_index=0
        while IFS= read -r native_project; do
            [ -n "$native_project" ] || continue
            native_dir=$(dirname "$native_project")
            native_index=$((native_index + 1))
            printf '%04d|%s\n' "$native_index" "$native_dir" >> "$NATIVE_LIST"
            if native_requires_serial_run "$native_dir"; then
                printf '%04d|%s\n' "$native_index" "$native_dir" >> "$NATIVE_SERIAL_LIST"
            else
                printf '%04d|%s\n' "$native_index" "$native_dir" >> "$NATIVE_PARALLEL_LIST"
            fi
        done <<< "$NATIVE_PROJECTS"

        echo "Running $(wc -l < "$NATIVE_SERIAL_LIST" | tr -d ' ') projects serially, then $(wc -l < "$NATIVE_PARALLEL_LIST" | tr -d ' ') with up to $NATIVE_MAX_JOBS parallel workers..."

        xargs -P 1 -I{} bash -lc "$NATIVE_WORKER" _ {} "$NATIVE_RESULTS_DIR" "$CLI_DLL" "$NATIVE_READER" < "$NATIVE_SERIAL_LIST"
        xargs -P "$NATIVE_MAX_JOBS" -I{} bash -lc "$NATIVE_WORKER" _ {} "$NATIVE_RESULTS_DIR" "$CLI_DLL" "$NATIVE_READER" < "$NATIVE_PARALLEL_LIST"

        # Replayed in discovery order, so the log is identical whatever order the workers finished in.
        while IFS='|' read -r native_index native_dir; do
            [ -n "$native_index" ] || continue
            echo
            echo "Testing native project: $native_dir"
            native_result_file="$NATIVE_RESULTS_DIR/$native_index.result"
            if [ ! -f "$native_result_file" ]; then
                echo "No result was recorded for $native_dir - its worker did not finish."
                handle_error "Native N# tests: $native_dir"
                NATIVE_STEP_OK=0
                continue
            fi

            native_status=$(cut -d'|' -f1 "$native_result_file")
            # PER-PROJECT WALL TIME. `nlc test --json` lands in a file this step deletes again, so
            # the only durable record of what each project costs is this line in the gate log.
            # Read it back with: grep '^project=' <gate log>.
            printf 'project=%s seconds=%s\n' "$native_dir" "$(cut -d'|' -f2 "$native_result_file")"
            if [ "$native_status" = "OK" ]; then
                cat "$NATIVE_RESULTS_DIR/$native_index.summary" || true
                handle_success "Native N# tests: $native_dir"
            else
                cat "$NATIVE_RESULTS_DIR/$native_index.json" 2>/dev/null || true
                cat "$NATIVE_RESULTS_DIR/$native_index.summary" 2>/dev/null || true
                cat "$NATIVE_RESULTS_DIR/$native_index.err" >&2 2>/dev/null || true
                handle_error "Native N# tests: $native_dir"
                NATIVE_STEP_OK=0
            fi
        done < "$NATIVE_LIST"

        NATIVE_RECORDER="$NATIVE_RESULTS_DIR/record-sweep.py"
        printf '%s\n' "$NATIVE_RECORD_SWEEP" > "$NATIVE_RECORDER"
        echo
        if ! python3 "$NATIVE_RECORDER" "$NATIVE_RESULTS_DIR" "$NATIVE_LIST" "$REPO_ROOT/artifacts"; then
            echo -e "${YELLOW}The native sweep record could not be written; the sweep's verdict is unaffected.${NC}"
        fi

        rm -rf "$NATIVE_RESULTS_DIR"
    fi

    # Only a feed this step packed itself: a supplied one belongs to the caller.
    if [ -n "${NATIVE_SDK_FEED:-}" ]; then
        rm -rf "$NATIVE_SDK_FEED"
        unset NSHARP_SDK_PROJECT_REFERENCE_FEED NSHARP_SDK_PROJECT_REFERENCE_VERSION NATIVE_SDK_FEED
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
    if dotnet "$CLI_DLL" build; then
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
    if dotnet "$CLI_DLL" build; then
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
