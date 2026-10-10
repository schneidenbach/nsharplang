#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Native project.yml files reference these Debug output directories directly through `dll:`.
# Keep this list as the single owner shared by the product gate and CI.
NATIVE_PREREQUISITE_PROJECTS=(
    src/NSharpLang.Cli/Cli.csproj
    src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj
    src/NSharpLang.LanguageServer/LanguageServer.csproj
    src/NSharpLang.Playground/NSharpLang.Playground.csproj
)

for project in "${NATIVE_PREREQUISITE_PROJECTS[@]}"; do
    dotnet build "$@" "$project" -c Debug -v q
done
