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
CORE_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --no-cache|--rebuild-cache)
            FORCE_RUN=1
            ;;
        --clean)
            FORCE_RUN=1
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
LOCK_STALE_SECONDS="${NSHARP_TEST_LOCK_STALE_SECONDS:-7200}"
if ! [[ "$LOCK_STALE_SECONDS" =~ ^[0-9]+$ ]]; then
    LOCK_STALE_SECONDS=7200
fi

cleanup_signature() {
    rm -f "$SIGNATURE_FILE"
}
trap cleanup_signature EXIT

CACHE_KEY="$(
    python3 - "$SOURCE_ROOT" "$SIGNATURE_FILE" ${CORE_ARGS[@]+"${CORE_ARGS[@]}"} <<'PY'
import hashlib
import json
import os
import platform
import subprocess
import sys

root = os.path.realpath(sys.argv[1])
signature_path = sys.argv[2]
args = sys.argv[3:]


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


content_hash = hashlib.sha256()
for relative in sorted(set(source_files())):
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

env_names = [
    "VSCODE_TESTS",
    "TEST_SUITE",
    "TEST_GREP",
    "TEST_ALL_JOBS",
    "NLC_MSBUILD_SINGLE_NODE",
    "DOTNET_ROOT",
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
print(key)
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
print("Validated isolated test cache hit")
print(f"Cache key: {sys.argv[2][:16]}")
print(f"Full isolated pass: {manifest.get('completedAtUtc')}")
print(f"Recorded duration: {manifest.get('durationSeconds')}s")
print()
print("Validation:")
print("  - source, test scripts, docs, examples, and templates match")
print("  - test arguments and selected environment match")
print("  - tool versions match")
print("  - cache manifest schema and success marker are valid")
print()
print("ALL TESTS PASSED! (cached isolated result)")
PY
}

mkdir -p "$RESULTS_ROOT" "$LOCKS_ROOT"

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
RUN_DEPS="$CACHE_ROOT/dependencies/$CACHE_KEY"

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
            --exclude='.context/' \
            --exclude='artifacts/' \
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
                --exclude='.context' \
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

copy_source_tree
mkdir -p "$RUN_HOME" "$RUN_TMP" "$RUN_DEPS/nuget/packages" "$RUN_DEPS/npm-cache"

START_TIME="$(date +%s)"

set +e
(
    cd "$RUN_REPO"
    export HOME="$RUN_HOME"
    export DOTNET_CLI_HOME="$RUN_HOME"
    export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
    export DOTNET_CLI_TELEMETRY_OPTOUT=1
    export DOTNET_NOLOGO=1
    export NUGET_PACKAGES="$RUN_DEPS/nuget/packages"
    export NPM_CONFIG_CACHE="$RUN_DEPS/npm-cache"
    export TMPDIR="$RUN_TMP"
    export TMP="$RUN_TMP"
    export TEMP="$RUN_TMP"
    export NSHARP_TEST_ALL_ISOLATED=1
    "$RUN_REPO/tests/scripts/test-all-core.sh" ${CORE_ARGS[@]+"${CORE_ARGS[@]}"}
)
CORE_EXIT=$?
set -e

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
