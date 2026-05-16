#!/usr/bin/env bash
set -euo pipefail

if command -v nlc >/dev/null 2>&1; then
  exec nlc "$@"
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec dotnet run --project "$ROOT/src/NSharpLang.Cli/Cli.csproj" -- "$@"
