#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE_SCRIPT="$SCRIPT_DIR/test-all-core.sh"

if [ ! -x "$CORE_SCRIPT" ]; then
    echo "ERROR: missing executable core test gate: $CORE_SCRIPT" >&2
    exit 1
fi

FORCE_RUN="${NSHARP_TEST_ALL_FORCE:-0}"
KEEP_RUN="${NSHARP_TEST_KEEP_RUN:-0}"
STEP_CACHE_OFF="${NSHARP_TEST_STEP_CACHE_OFF:-0}"
FRESH_REASON=""
CORE_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            cat <<'EOF'
Usage: ./scripts/test-all.sh [options]

Runs the full N# product gate from an isolated temporary workspace.

Options:
  --commit, --pre-commit
      Fresh isolated run required before committing. Cached results are not accepted.
  --release
      Fresh isolated run required for release verification. Cached results are not accepted.
  --fresh, --no-cache, --rebuild-cache
      Force a fresh isolated run and refresh the validated cache record on success.
  --clean
      Force a fresh isolated run and pass --clean through to the core gate.
  -h, --help
      Show this help.

Plain ./scripts/test-all.sh may return a validated cache hit for fast local
development. Do not use a cached hit as a pre-commit or release verification.

Within a plain fresh isolated development run, individual gate steps may be
skipped when their ENTIRE input set is byte-identical to inputs that previously
passed that step on the same toolchain (validated per-step cache). --commit,
--release, --fresh, --no-cache, and --clean disable per-step skipping and run
everything.
EOF
            exit 0
            ;;
        --commit|--pre-commit)
            FORCE_RUN=1
            FRESH_REASON="pre-commit verification"
            STEP_CACHE_OFF=1
            ;;
        --release)
            FORCE_RUN=1
            FRESH_REASON="release verification"
            STEP_CACHE_OFF=1
            ;;
        --fresh)
            FORCE_RUN=1
            FRESH_REASON="explicit fresh verification"
            STEP_CACHE_OFF=1
            ;;
        --no-cache|--rebuild-cache)
            FORCE_RUN=1
            FRESH_REASON="cache bypass requested"
            STEP_CACHE_OFF=1
            ;;
        --clean)
            FORCE_RUN=1
            FRESH_REASON="clean verification"
            STEP_CACHE_OFF=1
            CORE_ARGS+=("$arg")
            ;;
        *)
            CORE_ARGS+=("$arg")
            ;;
    esac
done

is_enabled() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

cache_root() {
    if [ -n "${NSHARP_TEST_CACHE_ROOT:-}" ]; then
        printf '%s\n' "$NSHARP_TEST_CACHE_ROOT"
        return
    fi

    case "$(uname -s)" in
        Darwin)
            printf '%s\n' "$HOME/Library/Caches/NSharpLang/test-all"
            ;;
        *)
            printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/nsharplang/test-all"
            ;;
    esac
}

CACHE_ROOT="$(cache_root)"
RESULTS_ROOT="$CACHE_ROOT/results"
LOCKS_ROOT="$CACHE_ROOT/locks"
SIGNATURE_FILE="$(mktemp "${TMPDIR:-/tmp}/nsharp-test-signature.XXXXXX")"
DEPENDENCY_SIGNATURE_FILE="$(mktemp "${TMPDIR:-/tmp}/nsharp-test-dependencies.XXXXXX")"
LOCK_STALE_SECONDS="${NSHARP_TEST_LOCK_STALE_SECONDS:-7200}"
if ! [[ "$LOCK_STALE_SECONDS" =~ ^[0-9]+$ ]]; then
    LOCK_STALE_SECONDS=7200
fi

cleanup_signature() {
    rm -f "$SIGNATURE_FILE" "$DEPENDENCY_SIGNATURE_FILE"
}
trap cleanup_signature EXIT

CACHE_KEY="$(
    python3 - "$SOURCE_ROOT" "$SIGNATURE_FILE" "$DEPENDENCY_SIGNATURE_FILE" ${CORE_ARGS[@]+"${CORE_ARGS[@]}"} <<'PY'
import hashlib
import json
import os
import platform
import subprocess
import sys

root = os.path.realpath(sys.argv[1])
signature_path = sys.argv[2]
dependency_signature_path = sys.argv[3]
args = sys.argv[4:]


def run_text(command):
    try:
        completed = subprocess.run(
            command,
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return None
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def source_files():
    git = subprocess.run(
        ["git", "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if git.returncode == 0:
        for raw in git.stdout.split(b"\0"):
            if raw:
                yield raw.decode("utf-8", "surrogateescape")
        return

    skipped_dirs = {
        ".git", "bin", "obj", "node_modules", ".vscode-test", ".context",
        "artifacts", "server", "out", "nsharp"
    }
    for current, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in skipped_dirs]
        for name in files:
            yield os.path.relpath(os.path.join(current, name), root)

def is_dependency_input(relative):
    normalized = relative.replace(os.sep, "/")
    name = os.path.basename(normalized).lower()
    if name in {
        "global.json",
        "nuget.config",
        "packages.lock.json",
        "package.json",
        "package-lock.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        "project.yml",
    }:
        return True
    return normalized.endswith((
        ".csproj",
        ".fsproj",
        ".vbproj",
        ".props",
        ".targets",
        ".sln",
        ".slnx",
    ))

content_hash = hashlib.sha256()
source_file_list = sorted(set(source_files()))
for relative in source_file_list:
    path = os.path.join(root, relative)
    if not os.path.isfile(path):
        continue
    normalized = relative.replace(os.sep, "/")
    content_hash.update(normalized.encode("utf-8", "surrogateescape"))
    content_hash.update(b"\0")
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            content_hash.update(chunk)
    content_hash.update(b"\0")

tool_versions = {
    "dotnet": run_text(["dotnet", "--version"]),
    "node": run_text(["node", "--version"]),
    "npm": run_text(["npm", "--version"]),
    "code": (run_text(["code", "--version"]) or "").splitlines()[:2],
}

# Behavior-changing environment for the gate. Keep in sync with ENV_NAMES in
# the per-step salt in tests/scripts/test-all-core.sh
# (GateStepInputSetGuardTests enforces it).
env_names = [
    "VSCODE_TESTS", "SYSTEMS_BENCH",
    "TEST_SUITE",
    "TEST_GREP",
    "TEST_ALL_JOBS",
    "NLC_MSBUILD_SINGLE_NODE",
    "DOTNET_ROOT",
    "NSHARP_EXPERIMENTAL_SOA",
]

signature = {
    "schemaVersion": 1,
    "sourceHash": content_hash.hexdigest(),
    "args": args,
    "environment": {name: os.environ.get(name) for name in env_names if os.environ.get(name) is not None},
    "tools": tool_versions,
    "platform": {
        "system": platform.system(),
        "machine": platform.machine(),
        "release": platform.release(),
    },
}

encoded = json.dumps(signature, sort_keys=True, separators=(",", ":")).encode("utf-8")
key = hashlib.sha256(encoded).hexdigest()
with open(signature_path, "w", encoding="utf-8") as handle:
    json.dump(signature, handle, indent=2, sort_keys=True)
    handle.write("\n")

dependency_hash = hashlib.sha256()
for relative in source_file_list:
    if not is_dependency_input(relative):
        continue
    path = os.path.join(root, relative)
    if not os.path.isfile(path):
        continue
    normalized = relative.replace(os.sep, "/")
    dependency_hash.update(normalized.encode("utf-8", "surrogateescape"))
    dependency_hash.update(b"\0")
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            dependency_hash.update(chunk)
    dependency_hash.update(b"\0")

dependency_signature = {
    "schemaVersion": 1,
    "sourceHash": dependency_hash.hexdigest(),
    "tools": tool_versions,
    "platform": {
        "system": platform.system(),
        "machine": platform.machine(),
        "release": platform.release(),
    },
    "salt": os.environ.get("NSHARP_TEST_DEPENDENCY_CACHE_SALT"),
}
dependency_encoded = json.dumps(dependency_signature, sort_keys=True, separators=(",", ":")).encode("utf-8")
dependency_key = hashlib.sha256(dependency_encoded).hexdigest()
with open(dependency_signature_path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "key": dependency_key,
            "signature": dependency_signature,
        },
        handle,
        indent=2,
        sort_keys=True,
    )
    handle.write("\n")

print(key)
PY
)"

DEPENDENCY_KEY="$(
    python3 - "$DEPENDENCY_SIGNATURE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["key"])
PY
)"

CACHE_DIR="$RESULTS_ROOT/$CACHE_KEY"
MANIFEST_FILE="$CACHE_DIR/manifest.json"

validate_manifest() {
    [ -f "$MANIFEST_FILE" ] || return 1
    python3 - "$SIGNATURE_FILE" "$MANIFEST_FILE" "$CACHE_KEY" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    signature = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    manifest = json.load(handle)

ok = (
    manifest.get("schemaVersion") == 1
    and manifest.get("key") == sys.argv[3]
    and manifest.get("coreExitCode") == 0
    and manifest.get("signature") == signature
)
raise SystemExit(0 if ok else 1)
PY
}

print_cache_hit() {
    python3 - "$MANIFEST_FILE" "$CACHE_KEY" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    manifest = json.load(handle)

print("=========================================")
print("N# Comprehensive Test Suite")
print("=========================================")
print()
print("Validated isolated test cache hit (development fast path)")
print(f"Cache key: {sys.argv[2][:16]}")
print(f"Full isolated pass: {manifest.get('completedAtUtc')}")
print(f"Recorded duration: {manifest.get('durationSeconds')}s")
print("Fresh run required for commit/release: ./scripts/test-all.sh --commit")
print()
print("Validation:")
print("  - source, test scripts, docs, examples, and templates match")
print("  - test arguments and selected environment match")
print("  - tool versions match")
print("  - cache manifest schema and success marker are valid")
print()
print("LAST ISOLATED FULL TEST RUN PASSED (cached validated result)")
PY
}

mkdir -p "$RESULTS_ROOT" "$LOCKS_ROOT"

if is_enabled "$FORCE_RUN"; then
    if [ -z "$FRESH_REASON" ]; then
        FRESH_REASON="NSHARP_TEST_ALL_FORCE requested"
    fi
    echo "Fresh isolated test run required: $FRESH_REASON"
    echo "Existing cache entries will not satisfy this invocation."
    echo
fi

if ! is_enabled "$FORCE_RUN" && validate_manifest; then
    print_cache_hit
    exit 0
fi

LOCK_DIR="$LOCKS_ROOT/$CACHE_KEY.lock"
LOCK_ACQUIRED=0

release_lock() {
    if [ "$LOCK_ACQUIRED" = "1" ]; then
        rm -rf "$LOCK_DIR"
    fi
}
trap 'cleanup_signature; release_lock' EXIT

lock_mtime_seconds() {
    stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo 0
}

remove_stale_lock_if_needed() {
    if [ -f "$LOCK_DIR/pid" ]; then
        lock_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
        if [[ "$lock_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            echo "Removing stale isolated test cache lock for key ${CACHE_KEY:0:16} (pid $lock_pid is gone)."
            rm -rf "$LOCK_DIR"
            return
        fi
    fi

    lock_mtime="$(lock_mtime_seconds)"
    if [[ "$lock_mtime" =~ ^[0-9]+$ ]] && [ "$lock_mtime" -gt 0 ]; then
        lock_age=$(($(date +%s) - lock_mtime))
        if [ "$lock_age" -gt "$LOCK_STALE_SECONDS" ]; then
            echo "Removing stale isolated test cache lock for key ${CACHE_KEY:0:16} (${lock_age}s old)."
            rm -rf "$LOCK_DIR"
        fi
    fi
}

while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if ! is_enabled "$FORCE_RUN" && validate_manifest; then
        print_cache_hit
        exit 0
    fi
    remove_stale_lock_if_needed
    echo "Waiting for isolated test cache warm-up for key ${CACHE_KEY:0:16}..."
    sleep 5
done
LOCK_ACQUIRED=1
printf '%s\n' "$$" > "$LOCK_DIR/pid"

if ! is_enabled "$FORCE_RUN" && validate_manifest; then
    print_cache_hit
    exit 0
fi

RUN_PARENT="${NSHARP_TEST_RUN_PARENT:-/tmp}"
mkdir -p "$RUN_PARENT"
RUN_ROOT="$(mktemp -d "$RUN_PARENT/nsharp-test-all.${CACHE_KEY:0:12}.XXXXXX")"
RUN_REPO="$RUN_ROOT/repo"
RUN_HOME="$RUN_ROOT/home"
RUN_TMP="$RUN_ROOT/tmp"
RUN_DEPS="$CACHE_ROOT/dependencies/$DEPENDENCY_KEY"

# ONE PACKAGES FOLDER PER RUN, OVER A SHARED STORE THAT IS NEVER WRITTEN IN PLACE.
#
# Every run restores into its OWN `NUGET_PACKAGES`, because a run mutates that folder: its first
# restore extracts the tree's stage-0 seed there, Step 4b deletes the NSharpLang packages and the
# steps after it restore the SDK this tree just packed under the SAME version, and the release pack
# path rewrites the restored SDK's `Sdk.props`. When that folder was shared per dependency key, a
# gate at one commit deleted or replaced the SDK another gate at a different commit was reading
# (MSB3030 on `nsharplang.runtime/0.1.0/.../NSharpLang.Runtime.dll`), and a run could compile with
# a seed that was not its own.
#
# What runs share is `NUGET_STORE`: immutable entries `<id>/<version>/<sha512 of the .nupkg>/`,
# one per nuget.org package a run restored. An entry is written once -- cloned into a staging
# directory inside the store, verified there, then published with a single `rename` that fails if
# the entry already exists, so the loser of a race discards its copy -- and never modified after.
# A reader therefore sees an entry whole or not at all. The NSharpLang packages are never shared:
# the tree under test owns every version of them. `nlc` reads `NUGET_PACKAGES` directly rather than
# NuGet's fallback folders, so a run starts from a copy-on-write clone of the entries its dependency
# key used last time (`NUGET_STORE_INDEX`), which costs a fraction of a second on APFS.
RUN_PACKAGES="$RUN_ROOT/nuget/packages"
NUGET_STORE="$CACHE_ROOT/nuget-store/v1"
NUGET_STORE_INDEX="$RUN_DEPS/nuget-store-index.txt"

# nuget_store materialize|promote <store> <index> <packages-folder>
nuget_store() {
    python3 - "$@" <<'PY'
import base64
import binascii
import hashlib
import json
import os
import shutil
import sys
import time
import uuid

NUGET_ORG = "https://api.nuget.org/v3/index.json"
TREE_OWNED_PREFIX = "nsharplang."
STALE_STAGING_SECONDS = 24 * 60 * 60


def recorded_digest(package_dir, package_id, version):
    """Hex SHA-512 the entry's `.nupkg.sha512` records, or None when it is absent or malformed."""
    path = os.path.join(package_dir, f"{package_id}.{version}.nupkg.sha512")
    try:
        with open(path, encoding="ascii") as handle:
            return binascii.hexlify(base64.b64decode(handle.read().strip(), validate=True)).decode("ascii")
    except (OSError, ValueError):
        return None


def verified_digest(package_dir, package_id, version):
    """The recorded digest, only when the `.nupkg` bytes beside it actually hash to it."""
    recorded = recorded_digest(package_dir, package_id, version)
    if recorded is None:
        return None
    digest = hashlib.sha512()
    try:
        with open(os.path.join(package_dir, f"{package_id}.{version}.nupkg"), "rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError:
        return None
    return recorded if digest.hexdigest() == recorded else None


def shareable(package_dir, package_id):
    # The tree under test owns every NSharpLang identity: seeds, local-feed packs, same-version
    # replacements. Anything else must have come from nuget.org, whose packages never change under
    # an id and version. `nlc`'s own resolver downloads from nuget.org only and writes no
    # `.nupkg.metadata`; NuGet's restore writes one naming the source it extracted from, and one
    # with no source at all when it adopts a package `nlc` already installed.
    if package_id.startswith(TREE_OWNED_PREFIX):
        return False
    metadata = os.path.join(package_dir, ".nupkg.metadata")
    if not os.path.exists(metadata):
        return True
    try:
        with open(metadata, encoding="utf-8") as handle:
            return json.load(handle).get("source", NUGET_ORG) == NUGET_ORG
    except (OSError, ValueError):
        return False


def clone_tree(source, destination):
    # Copy-on-write where the filesystem has it (one `clonefile` per package on APFS), else a copy.
    if sys.platform == "darwin":
        import ctypes
        libc = ctypes.CDLL("libc.dylib", use_errno=True)
        if libc.clonefile(os.fsencode(source), os.fsencode(destination), 0) == 0:
            return
    shutil.copytree(source, destination, symlinks=True)


def safe_name(name):
    return bool(name) and name not in (".", "..") and "/" not in name and "\\" not in name


def read_index(index):
    entries = set()
    try:
        with open(index, encoding="utf-8") as handle:
            for line in handle:
                parts = line.split()
                if len(parts) == 3 and all(safe_name(part) for part in parts):
                    entries.add(tuple(parts))
    except OSError:
        pass
    return entries


def write_index(index, entries):
    os.makedirs(os.path.dirname(index), exist_ok=True)
    temporary = f"{index}.{uuid.uuid4().hex}.tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        for entry in sorted(entries):
            handle.write(" ".join(entry) + "\n")
    os.replace(temporary, index)


def materialize(store, index, packages):
    identities = {}
    for package_id, version, digest in read_index(index):
        identities.setdefault((package_id, version), set()).add(digest)
    cloned = 0
    for (package_id, version), digests in sorted(identities.items()):
        if len(digests) != 1:
            continue
        digest = next(iter(digests))
        entry = os.path.join(store, package_id, version, digest)
        destination = os.path.join(packages, package_id, version)
        if os.path.exists(destination) or verified_digest(entry, package_id, version) != digest:
            continue
        os.makedirs(os.path.dirname(destination), exist_ok=True)
        clone_tree(entry, destination)
        cloned += 1
    print(f"NuGet store: {cloned} packages cloned into this run's packages folder from {store}")


def publish(package_dir, entry, staging_root, package_id, version, digest):
    os.makedirs(staging_root, exist_ok=True)
    staging = os.path.join(staging_root, uuid.uuid4().hex)
    os.mkdir(staging)
    try:
        candidate = os.path.join(staging, "entry")
        clone_tree(package_dir, candidate)
        if verified_digest(candidate, package_id, version) != digest:
            return False
        os.makedirs(os.path.dirname(entry), exist_ok=True)
        try:
            os.rename(candidate, entry)
        except OSError:
            # Another run published this content first. Its entry stands; this copy is discarded.
            return False
        return True
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def promote(store, index, packages):
    staging_root = os.path.join(store, ".staging")
    now = time.time()
    try:
        for name in os.listdir(staging_root):
            path = os.path.join(staging_root, name)
            if now - os.path.getmtime(path) > STALE_STAGING_SECONDS:
                shutil.rmtree(path, ignore_errors=True)
    except OSError:
        pass

    known = set()
    published = 0
    for package_id in sorted(os.listdir(packages)) if os.path.isdir(packages) else []:
        id_dir = os.path.join(packages, package_id)
        if not safe_name(package_id) or not os.path.isdir(id_dir):
            continue
        for version in sorted(os.listdir(id_dir)):
            package_dir = os.path.join(id_dir, version)
            if not safe_name(version) or not os.path.isdir(package_dir) or not shareable(package_dir, package_id):
                continue
            digest = recorded_digest(package_dir, package_id, version)
            if digest is None:
                continue
            entry = os.path.join(store, package_id, version, digest)
            if not os.path.isdir(entry):
                if verified_digest(package_dir, package_id, version) != digest:
                    continue
                if publish(package_dir, entry, staging_root, package_id, version, digest):
                    published += 1
            if os.path.isdir(entry):
                known.add((package_id, version, digest))
    write_index(index, read_index(index) | known)
    print(f"NuGet store: {published} new packages published, {len(known)} recorded for this dependency key")


command, store, index, packages = sys.argv[1:5]
{"materialize": materialize, "promote": promote}[command](store, index, packages)
PY
}

cleanup_run() {
    if ! is_enabled "$KEEP_RUN"; then
        rm -rf "$RUN_ROOT"
    else
        echo "Keeping isolated test run directory: $RUN_ROOT"
    fi
}
trap 'cleanup_signature; cleanup_run; release_lock' EXIT

copy_source_tree() {
    mkdir -p "$RUN_REPO"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete \
            --exclude='.git/' \
            --exclude='**/bin/' \
            --exclude='**/obj/' \
            --exclude='**/node_modules/' \
            --exclude='**/.vscode-test/' \
            --exclude='**/out/' \
            --exclude='**/server/' \
            --exclude='**/nsharp/' \
            --exclude='.context/' --exclude='.claude/' \
            --exclude='artifacts/' \
            --include='/bootstrap/*.nupkg' \
            --exclude='*.nupkg' \
            --exclude='*.vsix' \
            "$SOURCE_ROOT/" "$RUN_REPO/"
    else
        (
            cd "$SOURCE_ROOT"
            tar --exclude='.git' \
                --exclude='*/bin' \
                --exclude='*/obj' \
                --exclude='*/node_modules' \
                --exclude='*/.vscode-test' \
                --exclude='*/out' \
                --exclude='*/server' \
                --exclude='.context' --exclude='.claude' \
                --exclude='artifacts' \
                -cf - .
        ) | (
            cd "$RUN_REPO"
            tar -xf -
        )
    fi
}

echo "Preparing isolated test run"
echo "  Source: $SOURCE_ROOT"
echo "  Run:    $RUN_ROOT"
echo "  Cache:  $CACHE_ROOT"
echo "  Deps:   $RUN_DEPS"
echo "  Key:    ${CACHE_KEY:0:16}"
echo "  DepKey: ${DEPENDENCY_KEY:0:16}"

python3 "$SOURCE_ROOT/tests/scripts/test-release-workflows.py"
copy_source_tree
# THE SEED IS THE TREE'S OWN. The run's packages folder starts with no NSharpLang package at all, so
# the first restore extracts the stage-0 SDK/runtime from the COPIED tree's `bootstrap/` (the root
# NuGet.config source), and these are the bytes checked against its SHA256SUMS -- never whatever
# seed the user's global cache or another gate happens to hold under the same version.
python3 "$RUN_REPO/scripts/verify-bootstrap.py"
mkdir -p "$RUN_HOME" "$RUN_TMP" "$RUN_PACKAGES" "$RUN_DEPS/npm-cache"
nuget_store materialize "$NUGET_STORE" "$NUGET_STORE_INDEX" "$RUN_PACKAGES" \
    || echo "Could not materialize cached NuGet packages; this run restores them itself." >&2

START_TIME="$(date +%s)"

set +e
(
    cd "$RUN_REPO"
    export HOME="$RUN_HOME"
    export DOTNET_CLI_HOME="$RUN_HOME"
    export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
    export DOTNET_CLI_TELEMETRY_OPTOUT=1
    export DOTNET_NOLOGO=1
    export NUGET_PACKAGES="$RUN_PACKAGES"
    export NPM_CONFIG_CACHE="$RUN_DEPS/npm-cache"
    export NSHARP_VSCODE_TEST_CACHE="$RUN_DEPS/vscode-test"
    export NSHARP_VSCODE_PROFILE_ROOT="$RUN_TMP/vscode-profiles"
    export TMPDIR="$RUN_TMP"
    export TMP="$RUN_TMP"
    export TEMP="$RUN_TMP"
    export NSHARP_TEST_ALL_ISOLATED=1
    export NSHARP_TEST_STEP_CACHE_ROOT="$CACHE_ROOT/steps"
    export NSHARP_TEST_STEP_CACHE_OFF="$STEP_CACHE_OFF"
    # Golden regeneration must never leak into the gate: the isolated copy is
    # discarded, and NSHARP_UPDATE_DIAGNOSTIC_GOLDENS=1 makes golden tests
    # self-satisfying (rewrite, then compare against the rewrite). Regenerate
    # goldens with plain `dotnet test` in the working tree instead.
    unset NSHARP_UPDATE_DIAGNOSTIC_GOLDENS
    "$RUN_REPO/tests/scripts/test-all-core.sh" ${CORE_ARGS[@]+"${CORE_ARGS[@]}"}
)
CORE_EXIT=$?
set -e

# Carried out on a failing run too: what a nuget.org package holds does not depend on the verdict.
nuget_store promote "$NUGET_STORE" "$NUGET_STORE_INDEX" "$RUN_PACKAGES" \
    || echo "Could not promote this run's NuGet packages into the shared store; the gate's verdict is unaffected." >&2

# THE RECORDS THE GATE LEAVES BEHIND, CARRIED OUT OF THE COPY IT DELETES. Step 3a writes
# `artifacts/native-sweep/<UTC time>.json` and the compile-time bench writes
# `artifacts/compile-time/last-gate-run.txt`, both under the ISOLATED copy's root, which
# `cleanup_run` removes on exit. Carried back on a failing run too: what a red sweep cost is the
# record most worth keeping. `artifacts/` is gitignored and never part of any input set.
for gate_record in native-sweep compile-time; do
    if [ -d "$RUN_REPO/artifacts/$gate_record" ]; then
        mkdir -p "$SOURCE_ROOT/artifacts/$gate_record" \
            && cp -R "$RUN_REPO/artifacts/$gate_record/." "$SOURCE_ROOT/artifacts/$gate_record/" \
            || echo "Could not carry artifacts/$gate_record back to $SOURCE_ROOT; the gate's verdict is unaffected." >&2
    fi
done

END_TIME="$(date +%s)"
DURATION=$((END_TIME - START_TIME))

if [ "$CORE_EXIT" -ne 0 ]; then
    echo "Isolated test run failed after ${DURATION}s; cache was not updated." >&2
    exit "$CORE_EXIT"
fi

mkdir -p "$CACHE_DIR"
MANIFEST_TMP="$CACHE_DIR/manifest.json.tmp"
python3 - "$SIGNATURE_FILE" "$MANIFEST_TMP" "$CACHE_KEY" "$DURATION" <<'PY'
import datetime as dt
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    signature = json.load(handle)

manifest = {
    "schemaVersion": 1,
    "key": sys.argv[3],
    "coreExitCode": 0,
    "durationSeconds": int(sys.argv[4]),
    "completedAtUtc": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
    "signature": signature,
}

with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
mv "$MANIFEST_TMP" "$MANIFEST_FILE"

echo "Stored validated isolated test cache result: ${CACHE_KEY:0:16} (${DURATION}s)"
