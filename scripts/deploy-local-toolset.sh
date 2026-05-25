#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/lib/toolset.sh"
source "$SCRIPT_DIR/lib/vscode-extension.sh"

PROJECT_ROOT="$NSHARP_REPO_ROOT"
LOCAL_FEED="${NSHARP_LOCAL_FEED:-$HOME/.nsharp/packages}"
INSTALL_DIR="${NSHARP_INSTALL_DIR:-$HOME/.nsharp}"
TOOLSET_DIR="${NSHARP_TOOLSET_OUTPUT:-$PROJECT_ROOT/artifacts/toolset/local}"
VSCODE_EXT_DIR="$NSHARP_VSCODE_EXT_DIR"
SAMPLE_PROJECT="${NSHARP_VSCODE_SAMPLE_PROJECT:-$PROJECT_ROOT/examples/01-hello-world}"

DRY_RUN=0
SKIP_VSCODE=0
RESTART_VSCODE=1

usage() {
    cat <<EOF
Usage: ./scripts/deploy-local-toolset.sh [options]

Builds and deploys the local N# toolset without NuGet tool apphosts:
  - packs SDK/templates/compiler packages into the local N# package cache
  - publishes nlc and nsharp-lsp as framework-dependent apps
  - installs launchers under ~/.nsharp/bin
  - optionally packages and installs the VS Code extension

Options:
  --dry-run            Print the steps without making changes
  --skip-vscode        Skip VS Code packaging/install
  --no-restart-vscode  Install the extension without restarting VS Code
  --help               Show this help text

Environment overrides:
  NSHARP_LOCAL_FEED           Local N# package cache (default: ~/.nsharp/packages)
  NSHARP_INSTALL_DIR          Install directory (default: ~/.nsharp)
  NSHARP_TOOLSET_OUTPUT       Staging directory for the published toolset
  NSHARP_VSCODE_SAMPLE_PROJECT  Workspace to open after extension install
EOF
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

echo "========================================"
echo "Deploying Local N# Toolset"
echo "========================================"
echo "Project root: $PROJECT_ROOT"
echo "Install dir:  $INSTALL_DIR"
echo "Packages:     $LOCAL_FEED"
echo "Toolset:      $TOOLSET_DIR"
if [[ "$SKIP_VSCODE" -eq 0 ]]; then
    echo "VS Code:      yes"
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Mode:         dry-run"
fi

nsharp_log "Packing N# packages"
nsharp_run mkdir -p "$LOCAL_FEED"
while IFS='|' read -r package_id _label _project; do
    normalized_id="$(nsharp_lowercase "$package_id")"
    if [[ "$DRY_RUN" -eq 0 ]]; then
        rm -f "$LOCAL_FEED"/"$package_id".*.nupkg
        rm -rf "$HOME/.nuget/packages/$normalized_id"
    else
        echo "+ rm -f $LOCAL_FEED/$package_id.*.nupkg"
        echo "+ rm -rf $HOME/.nuget/packages/$normalized_id"
    fi
done < <(nsharp_each_package_spec)

nsharp_run_in_dir "$PROJECT_ROOT" dotnet build src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj -c Release -v q
while IFS='|' read -r _package_id label project; do
    nsharp_log "Packing $label"
    nsharp_run_in_dir "$PROJECT_ROOT" dotnet pack "$project" -c Release -o "$LOCAL_FEED" -v q
done < <(nsharp_each_package_spec)

nsharp_log "Publishing and installing local app payloads"
if [[ "$DRY_RUN" -eq 0 ]]; then
    nsharp_publish_toolset "$TOOLSET_DIR" "$LOCAL_FEED"
    nsharp_install_toolset "$TOOLSET_DIR" "$INSTALL_DIR"
    nsharp_install_templates_from_packages "$INSTALL_DIR/packages"
    nsharp_write_shared_nuget_config "$INSTALL_DIR/packages" "$INSTALL_DIR/NuGet.config"
else
    echo "+ publish nlc and nsharp-lsp to $TOOLSET_DIR"
    echo "+ install toolset to $INSTALL_DIR"
    echo "+ dotnet new install $INSTALL_DIR/packages/NSharpLang.Templates.<version>.nupkg --force"
    echo "+ write $INSTALL_DIR/NuGet.config"
fi

if [[ "$SKIP_VSCODE" -eq 0 ]]; then
    nsharp_log "Building and installing the VS Code extension"
    nsharp_build_vscode_extension_package

    if [[ "$RESTART_VSCODE" -eq 1 ]]; then
        nsharp_kill_vscode
    fi

    nsharp_run code --install-extension "$VSCODE_EXT_DIR"/nsharp-*.vsix --force

    if [[ "$RESTART_VSCODE" -eq 1 ]]; then
        nsharp_run code "$SAMPLE_PROJECT"
    fi
fi

echo
echo "Local deploy complete."
echo "Commands:"
echo "  - CLI: $INSTALL_DIR/bin/nlc"
echo "  - LSP: $INSTALL_DIR/bin/nsharp-lsp"
echo "  - Packages: $INSTALL_DIR/packages"
if [[ "$SKIP_VSCODE" -eq 0 ]]; then
    if [[ "$RESTART_VSCODE" -eq 1 ]]; then
        echo "  - VS Code reopened with: $SAMPLE_PROJECT"
    else
        echo "  - VS Code extension installed from: $VSCODE_EXT_DIR"
    fi
fi
echo "Run ./scripts/setup-local.sh to write shell profile integration."
