#!/usr/bin/env bash

if [[ -z "${NSHARP_REPO_ROOT:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
fi

NSHARP_PACKAGE_SPECS=(
    "NSharpLang.Sdk|NSharpLang.Sdk|src/NSharpLang.Sdk/NSharpLang.Sdk.csproj"
    "NSharpLang.Runtime|NSharpLang.Runtime|src/NSharpLang.Runtime/NSharpLang.Runtime.csproj"
    "NSharpLang.Templates|NSharpLang.Templates|templates/NSharpLang.Templates.csproj"
    "NSharpLang.Compiler.Model|NSharpLang.Compiler.Model|src/NSharpLang.Compiler.Model/NSharpLang.Compiler.Model.csproj"
    "NSharpLang.Compiler.Syntax|NSharpLang.Compiler.Syntax|src/NSharpLang.Compiler.Syntax/NSharpLang.Compiler.Syntax.csproj"
    "NSharpLang.Compiler.Core|NSharpLang.Compiler.Core|src/NSharpLang.Compiler.Core/NSharpLang.Compiler.Core.csproj"
    "NSharpLang.Compiler.Tooling|NSharpLang.Compiler.Tooling|src/NSharpLang.Compiler.Tooling/NSharpLang.Compiler.Tooling.csproj"
    "NSharpLang.Compiler.Driver|NSharpLang.Compiler.Driver|src/NSharpLang.Compiler.Driver/NSharpLang.Compiler.Driver.csproj"
    "NSharpLang.Compiler|NSharpLang.Compiler|src/NSharpLang.Compiler/Compiler.csproj"
)

nsharp_each_package_spec() {
    printf '%s\n' "${NSHARP_PACKAGE_SPECS[@]}"
}

# An N# project (its directory holds project.yml) is written by the N# IL emitter, which has no
# symbol writer, so every compiler slice carved out of Core gets the repair without naming it.
nsharp_package_emits_no_symbols() {
    [[ -f "$NSHARP_REPO_ROOT/$(dirname "$1")/project.yml" ]]
}

nsharp_package_version() {
    local project="$1"
    local version
    version="$(nsharp_read_xml_value "$NSHARP_REPO_ROOT/$project" Version)"
    if [[ -z "$version" ]]; then
        version="$(dotnet msbuild "$NSHARP_REPO_ROOT/$project" -getProperty:PackageVersion -nologo)"
    fi
    printf '%s\n' "$version"
}

nsharp_package_artifact_path() {
    local package_id="$1"
    local project="$2"
    local artifacts_dir="${3:-$NSHARP_REPO_ROOT/artifacts/nuget}"
    local version
    version="$(nsharp_package_version "$project")"
    printf '%s/%s.%s.nupkg\n' "$artifacts_dir" "$package_id" "$version"
}

nsharp_msbuild_single_node_enabled() {
    local value="${NLC_MSBUILD_SINGLE_NODE:-}"
    if [[ -z "$value" ]]; then
        if [[ -n "${CODEX_SANDBOX:-}" ]]; then
            value=1
        else
            value=0
        fi
    fi

    case "$value" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

nsharp_configure_stable_dotnet_build_flags() {
    NSHARP_DOTNET_STABLE_BUILD_FLAGS=(--disable-build-servers -nr:false)

    if nsharp_msbuild_single_node_enabled; then
        NSHARP_DOTNET_STABLE_BUILD_FLAGS+=(-m:1 -p:BuildInParallel=false)
        export DOTNET_CLI_USE_MSBUILD_SERVER=0
        export DOTNET_CLI_RUN_MSBUILD_OUTOFPROC=0
        export DOTNET_CLI_USE_MSBUILDNOINPROCNODE=0
        export MSBUILDDISABLENODEREUSE=1
        unset MSBUILDNOINPROCNODE
    fi
}

nsharp_prepare_stage0_sdk_for_pack() {
    local verbosity="${1:-q}"
    local sdk_project="src/NSharpLang.Sdk/NSharpLang.Sdk.csproj"
    local compiler_core_project="src/NSharpLang.Compiler.Core/NSharpLang.Compiler.Core.csproj"
    local sdk_version sdk_cache_dir

    sdk_version="$(nsharp_package_version "$sdk_project")"
    sdk_cache_dir="${NUGET_PACKAGES:-$HOME/.nuget/packages}/nsharplang.sdk/$sdk_version/Sdk"

    echo
    echo "Preparing stage-0 NSharpLang.Sdk cache..."
    nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet restore "${NSHARP_DOTNET_STABLE_BUILD_FLAGS[@]}" "$compiler_core_project" --force-evaluate -v "$verbosity"

    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        echo "+ cp $NSHARP_REPO_ROOT/src/NSharpLang.Sdk/Sdk/Sdk.props $sdk_cache_dir/Sdk.props"
        return 0
    fi

    if [[ ! -d "$sdk_cache_dir" ]]; then
        echo "Error: expected restored NSharpLang.Sdk cache at $sdk_cache_dir" >&2
        exit 1
    fi

    cp "$NSHARP_REPO_ROOT/src/NSharpLang.Sdk/Sdk/Sdk.props" "$sdk_cache_dir/Sdk.props"
}

nsharp_pack_package_set() {
    local output_dir="$1"
    local verbosity="${2:-q}"
    local package_spec
    local runtime_project="src/NSharpLang.Runtime/NSharpLang.Runtime.csproj"

    nsharp_configure_stable_dotnet_build_flags

    echo
    echo "Packing NSharpLang.Runtime bootstrap package..."
    nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet pack "${NSHARP_DOTNET_STABLE_BUILD_FLAGS[@]}" "$runtime_project" -c Release -o "$output_dir" -v "$verbosity"

    nsharp_prepare_stage0_sdk_for_pack "$verbosity"

    echo
    echo "Building NSharpLang.Build.Tasks in Release mode..."
    nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet build "${NSHARP_DOTNET_STABLE_BUILD_FLAGS[@]}" src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj -c Release -v "$verbosity"

    # A synchronous array walk avoids Bash 3.2 SIGCHLD interrupting pipe writes from an async
    # producer. The incident cause is inferred from that reproduction, not claimed as proven.
    for package_spec in "${NSHARP_PACKAGE_SPECS[@]}"; do
        IFS='|' read -r _package_id label project <<<"$package_spec"
        if [[ "$project" == "$runtime_project" ]]; then
            continue
        fi

        echo
        echo "Packing $label..."
        if nsharp_package_emits_no_symbols "$project"; then
            # Direct N# IL emits no PDB. Tell NuGet the actual output shape for the compiler assemblies.
            nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet pack "${NSHARP_DOTNET_STABLE_BUILD_FLAGS[@]}" "$project" -c Release -o "$output_dir" -p:DebugSymbols=false -p:DebugType=None -v "$verbosity"
        else
            nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet pack "${NSHARP_DOTNET_STABLE_BUILD_FLAGS[@]}" "$project" -c Release -o "$output_dir" -v "$verbosity"
        fi
    done
}

nsharp_print_release_artifact_set() {
    echo "  - NSharpLang.Sdk - MSBuild SDK restored by projects"
    echo "  - NSharpLang.Runtime - runtime support library for N# language features"
    echo "  - NSharpLang.Templates - dotnet new templates"
    echo "  - NSharpLang.Compiler.Model - N# compiler model (AST, types, diagnostics, project config)"
    echo "  - NSharpLang.Compiler.Syntax - N# compiler syntax (lexer, preprocessor, parser, node table)"
    echo "  - NSharpLang.Compiler.Core - N# compiler implementation dependency"
    echo "  - NSharpLang.Compiler.Tooling - N# compiler tooling (formatter, JSON output models)"
    echo "  - NSharpLang.Compiler.Driver - N# compiler driver (CLI command kernels, multi-file compiler, MSBuild tasks)"
    echo "  - NSharpLang.Compiler - Compiler API library"
    echo "  - nsharp-toolset.tar.gz - package-manager-ready nlc and nsharp-lsp payloads"
    echo "  - nsharp.vsix - stable VS Code extension release asset used by scripts/install.sh fallback"
}
