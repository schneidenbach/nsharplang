#!/usr/bin/env bash

# Shared helpers for building and installing the repository-local N# toolset.

if [[ -z "${NSHARP_REPO_ROOT:-}" ]]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
fi
if ! declare -F nsharp_each_package_spec >/dev/null 2>&1; then
    source "$NSHARP_SCRIPTS_DIR/lib/packages.sh"
fi
if ! declare -F nsharp_vscode_package_version >/dev/null 2>&1; then
    source "$NSHARP_SCRIPTS_DIR/lib/vscode-extension.sh"
fi

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

nsharp_ensure_local_nuget_source() {
    local local_feed="$1"
    local source_name="$2"

    if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
        dotnet nuget remove source "$source_name" >/dev/null 2>&1 || true
    else
        echo "+ dotnet nuget remove source $source_name || true"
    fi

    nsharp_run dotnet nuget add source "$local_feed" --name "$source_name"
}

nsharp_clear_tool_cache() {
    local tools_dir="$1"
    local package_id="$2"
    local normalized_id
    normalized_id="$(nsharp_lowercase "$package_id")"
    local package_cache_dir="$HOME/.nuget/packages/$normalized_id"
    local tool_store_dir="$tools_dir/.store/$normalized_id"

    if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
        rm -rf "$package_cache_dir" "$tool_store_dir"
    else
        echo "+ rm -rf $package_cache_dir $tool_store_dir"
    fi
}

nsharp_reinstall_tool() {
    local local_feed="$1"
    local tools_dir="$2"
    local package_id="$3"
    local version="$4"

    if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
        dotnet tool uninstall -g "$package_id" >/dev/null 2>&1 || true
    else
        echo "+ dotnet tool uninstall -g $package_id || true"
    fi

    nsharp_clear_tool_cache "$tools_dir" "$package_id"
    nsharp_run dotnet tool install -g "$package_id" --version "$version" --add-source "$local_feed" --no-http-cache
}

nsharp_verify_tool_file() {
    local tools_dir="$1"
    local command_name="$2"
    local tool_path="$tools_dir/$command_name"

    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        echo "+ test -x $tool_path"
        return 0
    fi

    if [[ ! -x "$tool_path" ]]; then
        echo "Error: expected tool at $tool_path" >&2
        exit 1
    fi
}

nsharp_remove_local_package() {
    local local_feed="$1"
    local package_id="$2"
    local normalized_id
    normalized_id="$(nsharp_lowercase "$package_id")"

    if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
        rm -f "$local_feed"/"$package_id".*.nupkg
        rm -rf "$HOME/.nuget/packages/$normalized_id"
    else
        echo "+ rm -f $local_feed/$package_id.*.nupkg"
        echo "+ rm -rf $HOME/.nuget/packages/$normalized_id"
    fi
}

nsharp_pack_package_set() {
    local output_dir="$1"
    local verbosity="${2:-q}"

    nsharp_configure_stable_dotnet_build_flags

    echo
    echo "Building NSharpLang.Build.Tasks in Release mode..."
    nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet build "${NSHARP_DOTNET_STABLE_BUILD_FLAGS[@]}" src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj -c Release -v "$verbosity"

    while IFS='|' read -r _package_id label project; do
        echo
        echo "Packing $label..."
        nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet pack "${NSHARP_DOTNET_STABLE_BUILD_FLAGS[@]}" "$project" -c Release -o "$output_dir" -v "$verbosity"
    done < <(nsharp_each_package_spec)
}

nsharp_deploy_local_toolset() {
    local local_feed="$1"
    local source_name="$2"
    local tools_dir="$3"
    local skip_vscode="$4"
    local restart_vscode="$5"
    local sample_project="$6"

    nsharp_require_command dotnet

    if [[ "$skip_vscode" -eq 0 ]]; then
        nsharp_require_command npm
        nsharp_require_command npx
        nsharp_require_command code
    fi

    local cli_version
    local lsp_version
    local vscode_version=""
    local vsix_file=""
    cli_version="$(nsharp_package_version "src/NSharpLang.Cli/Cli.csproj")"
    lsp_version="$(nsharp_package_version "src/NSharpLang.LanguageServer/LanguageServer.csproj")"
    if [[ "$skip_vscode" -eq 0 ]]; then
        vscode_version="$(nsharp_vscode_package_version)"
        vsix_file="$NSHARP_VSCODE_EXT_DIR/nsharp-$vscode_version.vsix"
    fi

    if [[ -z "$cli_version" || -z "$lsp_version" ]]; then
        echo "Error: failed to read one or more package versions." >&2
        exit 1
    fi
    if [[ "$skip_vscode" -eq 0 && -z "$vscode_version" ]]; then
        echo "Error: failed to read VS Code extension version." >&2
        exit 1
    fi

    echo "========================================"
    echo "Deploying Local N# Toolset"
    echo "========================================"
    echo "Project root: $NSHARP_REPO_ROOT"
    echo "Local feed:   $local_feed"
    echo "Tool path:    $tools_dir"
    echo "CLI version:  $cli_version"
    echo "LSP version:  $lsp_version"
    if [[ "$skip_vscode" -eq 0 ]]; then
        echo "VSIX:         $vsix_file"
    fi
    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        echo "Mode:         dry-run"
    fi

    nsharp_log "Preparing local feed"
    nsharp_run mkdir -p "$local_feed"
    nsharp_ensure_local_nuget_source "$local_feed" "$source_name"

    nsharp_log "Packing published artifacts into the local feed"
    while IFS='|' read -r package_id _label _project; do
        nsharp_remove_local_package "$local_feed" "$package_id"
    done < <(nsharp_each_package_spec)
    nsharp_pack_package_set "$local_feed" q

    nsharp_log "Refreshing templates and global dotnet tools"
    if [[ "${DRY_RUN:-0}" -eq 0 ]]; then
        dotnet new uninstall NSharpLang.Templates >/dev/null 2>&1 || true
    else
        echo "+ dotnet new uninstall NSharpLang.Templates || true"
    fi
    nsharp_run dotnet new install NSharpLang.Templates --add-source "$local_feed" --force
    nsharp_reinstall_tool "$local_feed" "$tools_dir" NSharpLang.Cli "$cli_version"
    nsharp_reinstall_tool "$local_feed" "$tools_dir" NSharpLang.LanguageServer "$lsp_version"
    nsharp_verify_tool_file "$tools_dir" nlc
    nsharp_verify_tool_file "$tools_dir" nsharp-lsp

    if [[ "$skip_vscode" -eq 0 ]]; then
        nsharp_log "Building and installing the VS Code extension"
        nsharp_build_vscode_extension_package

        if [[ "$restart_vscode" -eq 1 ]]; then
            nsharp_kill_vscode
        fi

        nsharp_run code --install-extension "$vsix_file" --force

        if [[ "$restart_vscode" -eq 1 ]]; then
            nsharp_run code "$sample_project"
        fi
    fi

    echo
    echo "Local deploy complete."
    echo "Commands:"
    echo "  - CLI: nlc"
    echo "  - LSP: nsharp-lsp"
    if ! nsharp_path_contains "$tools_dir"; then
        echo "  - PATH: add $tools_dir, or run ./scripts/setup-local.sh to install the shell bootstrap"
    fi
    if [[ "$skip_vscode" -eq 0 ]]; then
        if [[ "$restart_vscode" -eq 1 ]]; then
            echo "  - VS Code reopened with: $sample_project"
        else
            echo "  - VS Code extension installed: $vsix_file"
        fi
    fi
}
