#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/local-toolset.sh"

PROJECT_ROOT="$NSHARP_REPO_ROOT"
LOCAL_FEED="${NSHARP_LOCAL_FEED:-$HOME/.nuget/local-feed}"
NUGET_SOURCE_NAME="${NSHARP_LOCAL_SOURCE_NAME:-nsharp-local}"
DOTNET_TOOLS_DIR="${DOTNET_TOOLS_DIR:-$HOME/.dotnet/tools}"
NSHARP_ENV_DIR="${NSHARP_ENV_DIR:-$HOME/.nsharp}"
NSHARP_ENV_FILE="$NSHARP_ENV_DIR/env"
SAMPLE_PROJECT="${NSHARP_VSCODE_SAMPLE_PROJECT:-$PROJECT_ROOT/examples/01-hello-world}"

DRY_RUN=0
WITH_VSCODE=0
RESTART_VSCODE=1
UPDATE_PATH=1

usage() {
    cat <<EOF
Usage: ./scripts/setup-local.sh [options]

Contributor bootstrap for the local N# toolchain. Builds packages from this
checkout, refreshes the local NuGet feed, installs the nlc and nsharp-lsp dotnet
tools from that feed, installs the templates, and makes nlc available on PATH
for future shells.

Options:
  --with-vscode        Also package/install the VS Code extension
  --skip-vscode        Do not package/install the VS Code extension (default)
  --no-restart-vscode  Install VS Code extension without reopening VS Code
  --no-path-update     Do not update shell profile files
  --dry-run            Print the steps without making changes
  --help, -h           Show this help text

Environment overrides:
  NSHARP_LOCAL_FEED          Local NuGet feed path
  NSHARP_LOCAL_SOURCE_NAME   NuGet source name to register
  DOTNET_TOOLS_DIR           Directory expected to contain dotnet global tools
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

ensure_dotnet_tools_path() {
    if ! nsharp_path_contains "$DOTNET_TOOLS_DIR"; then
        export PATH="$DOTNET_TOOLS_DIR:$PATH"
    fi

    local dotnet_root=""
    if command -v dotnet >/dev/null 2>&1; then
        dotnet_root="$(nsharp_resolve_dotnet_root "$(command -v dotnet)")"
        if [[ -n "$dotnet_root" ]]; then
            export DOTNET_ROOT="${DOTNET_ROOT:-$dotnet_root}"
            case "$(uname -m)" in
                arm64) export DOTNET_ROOT_ARM64="${DOTNET_ROOT_ARM64:-$DOTNET_ROOT}" ;;
                x86_64) export DOTNET_ROOT_X64="${DOTNET_ROOT_X64:-$DOTNET_ROOT}" ;;
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
export PATH="$DOTNET_TOOLS_DIR:\$PATH"
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
        echo "Error: nlc was installed but is not on PATH. Source $NSHARP_ENV_FILE or add $DOTNET_TOOLS_DIR to PATH." >&2
        exit 1
    fi

    nlc --version
    if [[ "$WITH_VSCODE" -eq 1 ]]; then
        nlc doctor --require-vscode
    else
        nlc doctor --skip-vscode
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            ;;
        --with-vscode)
            WITH_VSCODE=1
            ;;
        --skip-vscode)
            WITH_VSCODE=0
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
echo "Local feed:        $LOCAL_FEED"
echo "Dotnet tools path: $DOTNET_TOOLS_DIR"
echo "VS Code install:   $([[ "$WITH_VSCODE" -eq 1 ]] && echo yes || echo no)"
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Mode:              dry-run"
fi

nsharp_log "Deploying local packages, templates, CLI, and language server"
if [[ "${#deploy_args[@]}" -gt 0 ]]; then
    echo "Deploy options:    ${deploy_args[*]}"
fi
nsharp_deploy_local_toolset "$LOCAL_FEED" "$NUGET_SOURCE_NAME" "$DOTNET_TOOLS_DIR" "$deploy_skip_vscode" "$RESTART_VSCODE" "$SAMPLE_PROJECT"

ensure_dotnet_tools_path
verify_local_toolchain

echo
echo "Local N# setup complete."
echo "For this terminal, setup has exported: $DOTNET_TOOLS_DIR"
if [[ "$UPDATE_PATH" -eq 1 ]]; then
    echo "For new terminals, restart your shell or run: source $NSHARP_ENV_FILE"
else
    echo "For new terminals, add $DOTNET_TOOLS_DIR to PATH or rerun without --no-path-update."
fi
echo
echo "Try:"
echo "  nlc new MyApp"
echo "  cd MyApp"
echo "  nlc run"
