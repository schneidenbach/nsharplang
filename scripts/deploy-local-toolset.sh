#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/lib/vscode-extension.sh"

PROJECT_ROOT="$NSHARP_REPO_ROOT"
LOCAL_FEED="${NSHARP_LOCAL_FEED:-$HOME/.nuget/local-feed}"
NUGET_SOURCE_NAME="${NSHARP_LOCAL_SOURCE_NAME:-nsharp-local}"
DOTNET_TOOLS_DIR="${DOTNET_TOOLS_DIR:-$HOME/.dotnet/tools}"
VSCODE_EXT_DIR="$NSHARP_VSCODE_EXT_DIR"
SAMPLE_PROJECT="${NSHARP_VSCODE_SAMPLE_PROJECT:-$PROJECT_ROOT/examples/01-hello-world}"

DRY_RUN=0
SKIP_VSCODE=0
RESTART_VSCODE=1

usage() {
    cat <<EOF
Usage: ./scripts/deploy-local-toolset.sh [options]

Builds and deploys the full local N# toolset:
  - refreshes the local NuGet feed
  - packs the SDK, templates, compiler, CLI, and language server
  - reinstalls the global dotnet tools (nlc and nsharp-lsp)
  - packages and installs the VS Code extension

Options:
  --dry-run           Print the steps without making changes
  --skip-vscode       Skip VS Code packaging/install
  --no-restart-vscode Install the extension without restarting VS Code
  --help              Show this help text

Environment overrides:
  NSHARP_LOCAL_FEED           Local NuGet feed path
  NSHARP_LOCAL_SOURCE_NAME    NuGet source name to register
  DOTNET_TOOLS_DIR            Directory expected to contain dotnet global tools
  NSHARP_VSCODE_SAMPLE_PROJECT  Workspace to open after extension install
EOF
}

ensure_nuget_source() {
    if [[ "$DRY_RUN" -eq 0 ]]; then
        dotnet nuget remove source "$NUGET_SOURCE_NAME" >/dev/null 2>&1 || true
    else
        echo "+ dotnet nuget remove source $NUGET_SOURCE_NAME || true"
    fi

    nsharp_run dotnet nuget add source "$LOCAL_FEED" --name "$NUGET_SOURCE_NAME"
}

clear_tool_cache() {
    local package_id="$1"
    local normalized_id
    normalized_id="$(nsharp_lowercase "$package_id")"
    local package_cache_dir="$HOME/.nuget/packages/$normalized_id"
    local tool_store_dir="$DOTNET_TOOLS_DIR/.store/$normalized_id"

    if [[ "$DRY_RUN" -eq 0 ]]; then
        rm -rf "$package_cache_dir" "$tool_store_dir"
    else
        echo "+ rm -rf $package_cache_dir $tool_store_dir"
    fi
}

reinstall_tool() {
    local package_id="$1"
    local version="$2"

    if [[ "$DRY_RUN" -eq 0 ]]; then
        dotnet tool uninstall -g "$package_id" >/dev/null 2>&1 || true
    else
        echo "+ dotnet tool uninstall -g $package_id || true"
    fi

    clear_tool_cache "$package_id"
    nsharp_run dotnet tool install -g "$package_id" --version "$version" --add-source "$LOCAL_FEED" --no-http-cache
}

verify_tool_file() {
    local command_name="$1"
    local tool_path="$DOTNET_TOOLS_DIR/$command_name"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "+ test -x $tool_path"
        return 0
    fi

    if [[ ! -x "$tool_path" ]]; then
        echo "Error: expected tool at $tool_path" >&2
        exit 1
    fi
}

remove_local_package() {
    local package_id="$1"
    local normalized_id
    normalized_id="$(nsharp_lowercase "$package_id")"

    if [[ "$DRY_RUN" -eq 0 ]]; then
        rm -f "$LOCAL_FEED"/"$package_id".*.nupkg
        rm -rf "$HOME/.nuget/packages/$normalized_id"
    else
        echo "+ rm -f $LOCAL_FEED/$package_id.*.nupkg"
        echo "+ rm -rf $HOME/.nuget/packages/$normalized_id"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --skip-vscode)
            SKIP_VSCODE=1
            ;;
        --no-restart-vscode)
            RESTART_VSCODE=0
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

nsharp_require_command dotnet

if [[ "$SKIP_VSCODE" -eq 0 ]]; then
    nsharp_require_command npm
    nsharp_require_command npx
    nsharp_require_command code
fi

CLI_VERSION="$(nsharp_package_version "src/NSharpLang.Cli/Cli.csproj")"
LSP_VERSION="$(nsharp_package_version "src/NSharpLang.LanguageServer/LanguageServer.csproj")"
VSCODE_VERSION="$(nsharp_vscode_package_version)"
VSIX_FILE="$VSCODE_EXT_DIR/nsharp-$VSCODE_VERSION.vsix"

if [[ -z "$CLI_VERSION" || -z "$LSP_VERSION" || -z "$VSCODE_VERSION" ]]; then
    echo "Error: failed to read one or more package versions." >&2
    exit 1
fi

echo "========================================"
echo "Deploying Local N# Toolset"
echo "========================================"
echo "Project root: $PROJECT_ROOT"
echo "Local feed:   $LOCAL_FEED"
echo "Tool path:    $DOTNET_TOOLS_DIR"
echo "CLI version:  $CLI_VERSION"
echo "LSP version:  $LSP_VERSION"
if [[ "$SKIP_VSCODE" -eq 0 ]]; then
    echo "VSIX:         $VSIX_FILE"
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Mode:         dry-run"
fi

nsharp_log "Preparing local feed"
nsharp_run mkdir -p "$LOCAL_FEED"
ensure_nuget_source

nsharp_log "Packing published artifacts into the local feed"
while IFS='|' read -r package_id _label _project; do
    remove_local_package "$package_id"
done < <(nsharp_each_package_spec)
nsharp_run_in_dir "$PROJECT_ROOT" dotnet build src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj -c Release -v q
while IFS='|' read -r _package_id _label project; do
    nsharp_run_in_dir "$PROJECT_ROOT" dotnet pack "$project" -c Release -o "$LOCAL_FEED" -v q
done < <(nsharp_each_package_spec)

nsharp_log "Refreshing templates and global dotnet tools"
if [[ "$DRY_RUN" -eq 0 ]]; then
    dotnet new uninstall NSharpLang.Templates >/dev/null 2>&1 || true
else
    echo "+ dotnet new uninstall NSharpLang.Templates || true"
fi
nsharp_run dotnet new install NSharpLang.Templates --add-source "$LOCAL_FEED" --force
reinstall_tool NSharpLang.Cli "$CLI_VERSION"
reinstall_tool NSharpLang.LanguageServer "$LSP_VERSION"
verify_tool_file nlc
verify_tool_file nsharp-lsp

if [[ "$SKIP_VSCODE" -eq 0 ]]; then
    nsharp_log "Building and installing the VS Code extension"
    nsharp_build_vscode_extension_package

    if [[ "$RESTART_VSCODE" -eq 1 ]]; then
        nsharp_kill_vscode
    fi

    nsharp_run code --install-extension "$VSIX_FILE" --force

    if [[ "$RESTART_VSCODE" -eq 1 ]]; then
        nsharp_run code "$SAMPLE_PROJECT"
    fi
fi

echo
echo "Local deploy complete."
echo "Commands:"
echo "  - CLI: nlc"
echo "  - LSP: nsharp-lsp"
if ! nsharp_path_contains "$DOTNET_TOOLS_DIR"; then
    echo "  - PATH: add $DOTNET_TOOLS_DIR, or run ./scripts/setup-local.sh to install the shell bootstrap"
fi
if [[ "$SKIP_VSCODE" -eq 0 ]]; then
    if [[ "$RESTART_VSCODE" -eq 1 ]]; then
        echo "  - VS Code reopened with: $SAMPLE_PROJECT"
    else
        echo "  - VS Code extension installed: $VSIX_FILE"
    fi
fi
