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

# Keep the shared artifact's contents derived from the build owners here rather than maintaining a
# second hand-written path list in the workflow.
SHARED_BUILD_OUTPUT_PROJECTS=(
    "${NATIVE_PREREQUISITE_PROJECTS[@]}"
    src/NSharpLang.Playground.Wasm/NSharpLang.Playground.Wasm.csproj
    src/NSharpLang.Compiler/*.csproj
    src/NSharpLang.Compiler.*/*.csproj
)

if [[ "${1:-}" == "--archive" ]]; then
    if [[ $# -ne 2 ]]; then
        echo "Usage: $0 --archive <output.tar.gz>" >&2
        exit 2
    fi
    archive_path="$2"
    mkdir -p "$(dirname "$archive_path")"
    output_directories=()
    for project in "${SHARED_BUILD_OUTPUT_PROJECTS[@]}"; do
        project_directory="${project%/*}"
        output_directories+=("$project_directory/bin" "$project_directory/obj")
    done
    tar -czf "$archive_path" -C "$REPO_ROOT" "${output_directories[@]}"
    exit 0
fi

for project in "${NATIVE_PREREQUISITE_PROJECTS[@]}"; do
    dotnet build "$@" "$project" -c Debug -v q
done
