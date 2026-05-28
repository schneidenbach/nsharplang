#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/lib/toolset.sh"
source "$SCRIPT_DIR/lib/vscode-extension.sh"

PROJECT_ROOT="$NSHARP_REPO_ROOT"
SETUP_LOCAL_INVOCATION="${NSHARP_SETUP_LOCAL_INVOCATION:-./scripts/setup-local.sh}"
NSHARP_INSTALL_DIR="${NSHARP_INSTALL_DIR:-$HOME/.nsharp}"
NSHARP_BIN_DIR="$NSHARP_INSTALL_DIR/bin"
LOCAL_FEED="${NSHARP_LOCAL_FEED:-$NSHARP_INSTALL_DIR/packages}"
TOOLSET_DIR="${NSHARP_TOOLSET_OUTPUT:-$PROJECT_ROOT/artifacts/toolset/local}"
NSHARP_ENV_DIR="${NSHARP_ENV_DIR:-$HOME/.nsharp}"
NSHARP_ENV_FILE="$NSHARP_ENV_DIR/env"
SAMPLE_PROJECT="${NSHARP_VSCODE_SAMPLE_PROJECT:-$PROJECT_ROOT/examples/01-hello-world}"
VSCODE_EXT_DIR="$NSHARP_VSCODE_EXT_DIR"

DRY_RUN=0
WITH_VSCODE=0
VSCODE_REQUEST_EXPLICIT=0
RESTART_VSCODE=1
UPDATE_PATH=1

case "${NSHARP_SETUP_LOCAL_DEFAULT_WITH_VSCODE:-0}" in
    1|true|TRUE|yes|YES|on|ON)
        WITH_VSCODE=1
        ;;
    0|false|FALSE|no|NO|off|OFF|"")
        WITH_VSCODE=0
        ;;
    *)
        echo "Error: NSHARP_SETUP_LOCAL_DEFAULT_WITH_VSCODE must be 0 or 1." >&2
        exit 2
        ;;
esac

usage() {
    cat <<EOF
Usage: $SETUP_LOCAL_INVOCATION [options]

Contributor bootstrap for the local N# toolchain. Builds packages from this
checkout, refreshes the local N# package cache, installs the nlc and nsharp-lsp
launchers, installs the templates, and makes nlc available on PATH
for future shells.

Options:
  --with-vscode        Also package/install the VS Code extension$([[ "$WITH_VSCODE" -eq 1 ]] && echo " (default)")
  --skip-vscode        Do not package/install the VS Code extension$([[ "$WITH_VSCODE" -eq 0 ]] && echo " (default)")
  --no-restart-vscode  Install VS Code extension without reopening VS Code
  --no-path-update     Do not update shell profile files
  --dry-run            Print the steps without making changes
  --help, -h           Show this help text

Environment overrides:
  NSHARP_LOCAL_FEED          Local NuGet feed path
  NSHARP_INSTALL_DIR         N# install directory (default: ~/.nsharp)
  NSHARP_ENV_DIR             Directory for the N# shell env file
EOF
}

profile_candidates() {
    local shell_name
    shell_name="$(basename "${SHELL:-}")"
    local profiles=()

    case "$shell_name" in
        zsh)
            profiles+=("$HOME/.zshrc")
            ;;
        bash)
            profiles+=("$HOME/.bashrc")
            if [[ "$(uname -s)" == "Darwin" ]]; then
                profiles+=("$HOME/.bash_profile")
            fi
            ;;
    esac

    for candidate in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
        if [[ -f "$candidate" ]]; then
            local already_listed=0
            for profile in "${profiles[@]}"; do
                if [[ "$profile" == "$candidate" ]]; then
                    already_listed=1
                    break
                fi
            done
            if [[ "$already_listed" -eq 0 ]]; then
                profiles+=("$candidate")
            fi
        fi
    done

    if [[ "${#profiles[@]}" -eq 0 ]]; then
        profiles+=("$HOME/.profile")
    fi

    printf '%s\n' "${profiles[@]}"
}

ensure_profile_sources_env() {
    local profile="$1"
    local source_line
    if [[ "$NSHARP_ENV_FILE" == "$HOME/.nsharp/env" ]]; then
        source_line='[ -f "$HOME/.nsharp/env" ] && . "$HOME/.nsharp/env"'
    else
        source_line="[ -f \"$NSHARP_ENV_FILE\" ] && . \"$NSHARP_ENV_FILE\""
    fi

    if [[ -f "$profile" ]] && grep -Fq "$source_line" "$profile"; then
        echo "Profile already sources N# env: $profile"
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "+ append N# PATH bootstrap to $profile"
        return 0
    fi

    mkdir -p "$(dirname "$profile")"
    {
        echo
        echo "# N# toolchain"
        echo "$source_line"
    } >> "$profile"

    echo "Updated shell profile: $profile"
}

ensure_nsharp_path() {
    if ! nsharp_path_contains "$NSHARP_BIN_DIR"; then
        export PATH="$NSHARP_BIN_DIR:$PATH"
    fi

    local dotnet_root=""
    if command -v dotnet >/dev/null 2>&1; then
        dotnet_root="$(nsharp_resolve_dotnet_root "$(command -v dotnet)")"
        if [[ -n "$dotnet_root" ]]; then
            export DOTNET_ROOT="$dotnet_root"
            case "$(uname -m)" in
                arm64) export DOTNET_ROOT_ARM64="$DOTNET_ROOT" ;;
                x86_64) export DOTNET_ROOT_X64="$DOTNET_ROOT" ;;
            esac
        fi
    fi

    if [[ "$UPDATE_PATH" -eq 0 ]]; then
        echo "Skipping shell profile PATH update (--no-path-update)."
        return 0
    fi

    nsharp_log "Ensuring nlc is on PATH for future shells"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "+ mkdir -p $NSHARP_ENV_DIR"
        echo "+ write $NSHARP_ENV_FILE"
        if [[ -n "$dotnet_root" ]]; then
            echo "+ write DOTNET_ROOT=$DOTNET_ROOT to $NSHARP_ENV_FILE"
        fi
    else
        mkdir -p "$NSHARP_ENV_DIR"
        cat > "$NSHARP_ENV_FILE" <<EOF
# Added by N# local setup.
export PATH="$NSHARP_BIN_DIR:\$PATH"
EOF
        if [[ -n "$dotnet_root" ]]; then
            {
                echo "export DOTNET_ROOT=\"${DOTNET_ROOT}\""
                case "$(uname -m)" in
                    arm64) echo "export DOTNET_ROOT_ARM64=\"\${DOTNET_ROOT_ARM64:-\$DOTNET_ROOT}\"" ;;
                    x86_64) echo "export DOTNET_ROOT_X64=\"\${DOTNET_ROOT_X64:-\$DOTNET_ROOT}\"" ;;
                esac
            } >> "$NSHARP_ENV_FILE"
        fi
        echo "Wrote: $NSHARP_ENV_FILE"
    fi

    while IFS= read -r profile; do
        [[ -n "$profile" ]] || continue
        ensure_profile_sources_env "$profile"
    done < <(profile_candidates)
}

verify_local_toolchain() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        if [[ "$WITH_VSCODE" -eq 1 ]]; then
            echo "+ nlc doctor --require-vscode"
        else
            echo "+ nlc doctor --skip-vscode"
        fi
        return 0
    fi

    nsharp_log "Verifying local N# toolchain"
    if ! command -v nlc >/dev/null 2>&1; then
        echo "Error: nlc was installed but is not on PATH. Source $NSHARP_ENV_FILE or add $NSHARP_BIN_DIR to PATH." >&2
        exit 1
    fi

    nlc --version
    if [[ "$WITH_VSCODE" -eq 1 ]]; then
        nlc doctor --require-vscode
    else
        nlc doctor --skip-vscode
    fi
}

deploy_local_toolset() {
    local skip_vscode="$1"
    local vscode_vsix=""

    nsharp_require_command dotnet

    echo "========================================"
    echo "Deploying Local N# Toolset"
    echo "========================================"
    echo "Project root: $PROJECT_ROOT"
    echo "Install dir:  $NSHARP_INSTALL_DIR"
    echo "Packages:     $LOCAL_FEED"
    echo "Toolset:      $TOOLSET_DIR"
    if [[ "$skip_vscode" -eq 0 ]]; then
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
    nsharp_pack_package_set "$LOCAL_FEED" q

    nsharp_log "Publishing and installing local app payloads"
    if [[ "$DRY_RUN" -eq 0 ]]; then
        nsharp_publish_toolset "$TOOLSET_DIR" "$LOCAL_FEED"
        nsharp_install_toolset "$TOOLSET_DIR" "$NSHARP_INSTALL_DIR"
        nsharp_install_templates_from_packages "$NSHARP_INSTALL_DIR/packages"
        nsharp_write_shared_nuget_config "$NSHARP_INSTALL_DIR/packages" "$NSHARP_INSTALL_DIR/NuGet.config"
    else
        echo "+ publish nlc and nsharp-lsp to $TOOLSET_DIR"
        echo "+ install toolset to $NSHARP_INSTALL_DIR"
        echo "+ dotnet new install $NSHARP_INSTALL_DIR/packages/NSharpLang.Templates.<version>.nupkg --force"
        echo "+ write $NSHARP_INSTALL_DIR/NuGet.config"
    fi

    if [[ "$skip_vscode" -eq 0 ]]; then
        nsharp_log "Building and installing the VS Code extension"
        nsharp_build_vscode_extension_package
        if [[ "$DRY_RUN" -eq 1 ]]; then
            vscode_vsix="$VSCODE_EXT_DIR/nsharp-$(nsharp_vscode_package_version).vsix"
        else
            vscode_vsix="$(nsharp_latest_vscode_vsix)"
        fi

        if [[ "$RESTART_VSCODE" -eq 1 ]]; then
            nsharp_kill_vscode
        fi

        nsharp_run code --install-extension "$vscode_vsix" --force

        if [[ "$RESTART_VSCODE" -eq 1 ]]; then
            nsharp_run code "$SAMPLE_PROJECT"
        fi
    fi

    echo
    echo "Local deploy complete."
    echo "Commands:"
    echo "  - CLI: $NSHARP_INSTALL_DIR/bin/nlc"
    echo "  - LSP: $NSHARP_INSTALL_DIR/bin/nsharp-lsp"
    echo "  - Packages: $NSHARP_INSTALL_DIR/packages"
    if [[ "$skip_vscode" -eq 0 ]]; then
        if [[ "$RESTART_VSCODE" -eq 1 ]]; then
            echo "  - VS Code reopened with: $SAMPLE_PROJECT"
        else
            echo "  - VS Code extension installed from: $vscode_vsix"
        fi
    fi
}

maybe_disable_default_vscode_install() {
    if [[ "$WITH_VSCODE" -eq 0 || "$DRY_RUN" -eq 1 ]]; then
        return 0
    fi

    local missing=()
    for cmd in npm npx code; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        return 0
    fi

    if [[ "$VSCODE_REQUEST_EXPLICIT" -eq 1 ]]; then
        echo "Error: VS Code extension install requested, but missing required command(s): ${missing[*]}" >&2
        exit 1
    fi

    echo "VS Code extension install skipped because required command(s) were not found: ${missing[*]}"
    echo "Install the missing command(s), or run '$SETUP_LOCAL_INVOCATION --with-vscode' to require the editor reinstall."
    WITH_VSCODE=0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --with-vscode)
            WITH_VSCODE=1
            VSCODE_REQUEST_EXPLICIT=1
            ;;
        --skip-vscode)
            WITH_VSCODE=0
            VSCODE_REQUEST_EXPLICIT=1
            ;;
        --no-restart-vscode)
            RESTART_VSCODE=0
            ;;
        --no-path-update)
            UPDATE_PATH=0
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

maybe_disable_default_vscode_install

deploy_args=()
deploy_skip_vscode=0
if [[ "$DRY_RUN" -eq 1 ]]; then
    deploy_args+=(--dry-run)
fi
if [[ "$WITH_VSCODE" -eq 0 ]]; then
    deploy_args+=(--skip-vscode)
    deploy_skip_vscode=1
fi
if [[ "$RESTART_VSCODE" -eq 0 ]]; then
    deploy_args+=(--no-restart-vscode)
fi

echo "========================================"
echo "Setting up local N# toolchain"
echo "========================================"
echo "Project root:      $PROJECT_ROOT"
echo "Install dir:       $NSHARP_INSTALL_DIR"
echo "Command path:      $NSHARP_BIN_DIR"
echo "VS Code install:   $([[ "$WITH_VSCODE" -eq 1 ]] && echo yes || echo no)"
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Mode:              dry-run"
fi

nsharp_log "Deploying local packages, templates, CLI, and language server launchers"
if [[ "${#deploy_args[@]}" -gt 0 ]]; then
    echo "Deploy options:    ${deploy_args[*]}"
fi
deploy_local_toolset "$deploy_skip_vscode"

ensure_nsharp_path
verify_local_toolchain

echo
echo "Local N# setup complete."
echo "For this terminal, setup has exported: $NSHARP_BIN_DIR"
if [[ "$UPDATE_PATH" -eq 1 ]]; then
    echo "For new terminals, restart your shell or run: source $NSHARP_ENV_FILE"
else
    echo "For new terminals, add $NSHARP_BIN_DIR to PATH or rerun without --no-path-update."
fi
echo
echo "Try:"
echo "  nlc new MyApp"
echo "  cd MyApp"
echo "  nlc run"
