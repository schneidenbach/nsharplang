#!/usr/bin/env bash

# Shared Bash helpers for repository-local scripts.

NSHARP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NSHARP_SCRIPTS_DIR="$(cd "$NSHARP_LIB_DIR/.." && pwd)"
NSHARP_REPO_ROOT="$(cd "$NSHARP_SCRIPTS_DIR/.." && pwd)"

nsharp_log() {
    echo
    echo "==> $1"
}

nsharp_print_command() {
    printf '+'
    for arg in "$@"; do
        printf ' %q' "$arg"
    done
    printf '\n'
}

nsharp_run() {
    nsharp_print_command "$@"
    if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
        "$@"
    fi
}

nsharp_run_in_dir() {
    local dir="$1"
    shift

    printf '+ (cd %q &&' "$dir"
    for arg in "$@"; do
        printf ' %q' "$arg"
    done
    printf ')\n'

    if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
        (
            cd "$dir"
            "$@"
        )
    fi
}

nsharp_require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command not found: $cmd" >&2
        exit 1
    fi
}

nsharp_read_xml_value() {
    local file="$1"
    local tag="$2"
    sed -n "s:.*<$tag>\\(.*\\)</$tag>.*:\\1:p" "$file" | head -n 1
}

nsharp_read_package_json_version() {
    local file="$1"
    sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n 1
}

nsharp_lowercase() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

nsharp_path_contains() {
    case ":$PATH:" in
        *":$1:"*) return 0 ;;
        *) return 1 ;;
    esac
}

nsharp_resolve_dotnet_root() {
    python3 - "$1" <<'PY'
import os
import sys

dotnet = os.path.realpath(sys.argv[1])
dotnet_dir = os.path.dirname(dotnet)
parent = os.path.dirname(dotnet_dir)
candidates = (
    dotnet_dir,
    os.path.join(parent, "libexec"),
    parent,
    "/usr/local/share/dotnet",
    "/opt/homebrew/share/dotnet",
)
seen = set()
for candidate in candidates:
    if candidate in seen:
        continue
    seen.add(candidate)
    if (
        os.path.isfile(os.path.join(candidate, "dotnet"))
        and (
            os.path.isdir(os.path.join(candidate, "sdk"))
            or os.path.isdir(os.path.join(candidate, "host", "fxr"))
        )
    ):
        print(candidate)
        break
else:
    print(dotnet_dir)
PY
}
