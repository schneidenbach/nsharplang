#!/usr/bin/env bash
set -euo pipefail

resolve_dotnet_root() {
  python3 - "$1" <<'PY'
import os
import sys

dotnet = os.path.realpath(sys.argv[1])
dotnet_dir = os.path.dirname(dotnet)
candidates = (
    dotnet_dir,
    os.path.join(os.path.dirname(dotnet_dir), "libexec"),
    os.path.dirname(dotnet_dir),
)
for candidate in candidates:
    if os.path.isfile(os.path.join(candidate, "dotnet")) and os.path.isdir(os.path.join(candidate, "shared")):
        print(candidate)
        break
PY
}

if command -v dotnet >/dev/null 2>&1; then
  dotnet_root="$(resolve_dotnet_root "$(command -v dotnet)")"
  if [[ -n "${DOTNET_ROOT:-}" || -n "$dotnet_root" ]]; then
    DOTNET_ROOT="${DOTNET_ROOT:-$dotnet_root}"
    export DOTNET_ROOT
    case "$(uname -m)" in
      arm64) export DOTNET_ROOT_ARM64="${DOTNET_ROOT_ARM64:-$DOTNET_ROOT}" ;;
      x86_64) export DOTNET_ROOT_X64="${DOTNET_ROOT_X64:-$DOTNET_ROOT}" ;;
    esac
  fi
fi

if command -v nlc >/dev/null 2>&1; then
  exec nlc "$@"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec dotnet run --project "$ROOT/src/NSharpLang.Cli/Cli.csproj" -- "$@"
