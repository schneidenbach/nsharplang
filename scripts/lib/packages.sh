#!/usr/bin/env bash

if [[ -z "${NSHARP_REPO_ROOT:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
fi

NSHARP_PACKAGE_SPECS=(
    "NSharpLang.Sdk|NSharpLang.Sdk|src/NSharpLang.Sdk/NSharpLang.Sdk.csproj"
    "NSharpLang.Templates|NSharpLang.Templates|templates/NSharpLang.Templates.csproj"
    "NSharpLang.Compiler|NSharpLang.Compiler|src/NSharpLang.Compiler/Compiler.csproj"
    "NSharpLang.Cli|nlc (N# CLI tool)|src/NSharpLang.Cli/Cli.csproj"
    "NSharpLang.LanguageServer|NSharpLang.LanguageServer|src/NSharpLang.LanguageServer/LanguageServer.csproj"
)

nsharp_each_package_spec() {
    printf '%s\n' "${NSHARP_PACKAGE_SPECS[@]}"
}

nsharp_package_version() {
    local project="$1"
    nsharp_read_xml_value "$NSHARP_REPO_ROOT/$project" Version
}

nsharp_package_artifact_path() {
    local package_id="$1"
    local project="$2"
    local artifacts_dir="${3:-$NSHARP_REPO_ROOT/artifacts/nuget}"
    local version
    version="$(nsharp_package_version "$project")"
    printf '%s/%s.%s.nupkg\n' "$artifacts_dir" "$package_id" "$version"
}

nsharp_print_release_artifact_set() {
    echo "  - NSharpLang.Sdk - MSBuild SDK restored by projects"
    echo "  - NSharpLang.Templates - dotnet new templates"
    echo "  - NSharpLang.Compiler - Compiler API library"
    echo "  - NSharpLang.Cli - global tool that provides nlc"
    echo "  - NSharpLang.LanguageServer - global tool that provides nsharp-lsp"
    echo "  - nsharp.vsix - stable VS Code extension release asset used by scripts/install.sh fallback"
}
