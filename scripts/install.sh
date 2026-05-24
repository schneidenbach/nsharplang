#!/usr/bin/env bash
set -euo pipefail

DEFAULT_NUGET_SOURCE="https://api.nuget.org/v3/index.json"
DEFAULT_VSIX_URL="https://github.com/schneidenbach/nsharplang/releases/latest/download/nsharp.vsix"
NUGET_SOURCE="$DEFAULT_NUGET_SOURCE"
DOTNET_TOOLS_DIR="${DOTNET_TOOLS_DIR:-$HOME/.dotnet/tools}"
NSHARP_ENV_DIR="${NSHARP_ENV_DIR:-$HOME/.nsharp}"
NSHARP_ENV_FILE="$NSHARP_ENV_DIR/env"
DRY_RUN=0
SKIP_VSCODE=0
UNINSTALL=0
UPDATE_PATH=1
VSCODE_EXTENSION_ID="nsharp.nsharp"
VSCODE_VSIX_URL="${NSHARP_VSIX_URL:-$DEFAULT_VSIX_URL}"

usage() {
  cat <<EOF
Usage: install.sh [options]

Turnkey installer for the public N# toolchain. Installs the user-facing NSharpLang
surface: nlc CLI, dotnet new templates, SDK restore support, language server, and
VS Code extension when the 'code' CLI is available.

Canonical one-liner:
  curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . "\$HOME/.nsharp/env"

Options:
  --source SOURCE       NuGet source or local feed directory (default: NuGet.org)
  --vsix-url URL        VSIX fallback URL when Marketplace install fails
  --no-vsix-fallback    Do not try a VSIX fallback after Marketplace install
  --skip-vscode         Do not install/probe the VS Code extension
  --no-path-update      Do not update shell profile files
  --uninstall           Remove N# tools/templates/VS Code extension instead
  --dry-run             Print commands without running them
  --help, -h            Show this help text

Version pinning:
  --version is intentionally unsupported until all public NSharpLang packages
  ship with one unified release version. Use the default latest install for now.

Environment:
  NSHARP_VSIX_URL       VSIX fallback URL when Marketplace install fails
  DOTNET_TOOLS_DIR      Dotnet global-tool directory (default: ~/.dotnet/tools)
  NSHARP_ENV_DIR        Directory for the N# shell env file (default: ~/.nsharp)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|--version=*)
      echo "ERROR: scripts/install.sh does not support --version yet." >&2
      echo "NSharpLang packages currently ship with mixed package versions, so one public version cannot safely pin the full toolchain." >&2
      echo "Use the default latest install, or publish a unified release version across CLI, SDK, templates, compiler, and language server first." >&2
      exit 2
      ;;
    --source)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "ERROR: --source requires a value." >&2
        exit 2
      fi
      NUGET_SOURCE="$2"
      shift
      ;;
    --vsix-url)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "ERROR: --vsix-url requires a value." >&2
        exit 2
      fi
      VSCODE_VSIX_URL="$2"
      shift
      ;;
    --no-vsix-fallback) VSCODE_VSIX_URL="" ;;
    --skip-vscode) SKIP_VSCODE=1 ;;
    --no-path-update) UPDATE_PATH=0 ;;
    --uninstall) UNINSTALL=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

run() {
  echo "+ $*"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$@"
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

resolve_dotnet_root() {
  local dotnet_path="$1"
  local target="$dotnet_path"
  local dir link bin_dir parent candidate

  while [[ -L "$target" ]]; do
    dir="$(cd -P "$(dirname "$target")" && pwd)"
    link="$(readlink "$target")"
    if [[ "$link" == /* ]]; then
      target="$link"
    else
      target="$dir/$link"
    fi
  done

  bin_dir="$(cd -P "$(dirname "$target")" && pwd)"
  parent="$(dirname "$bin_dir")"

  for candidate in "$bin_dir" "$parent/libexec" "$parent" "/usr/local/share/dotnet" "/opt/homebrew/share/dotnet"; do
    if [[ -x "$candidate/dotnet" && ( -d "$candidate/sdk" || -d "$candidate/host/fxr" ) ]]; then
      echo "$candidate"
      return 0
    fi
  done

  echo "$bin_dir"
}

is_dotnet_root() {
  local candidate="${1:-}"
  [[ -n "$candidate" && -x "$candidate/dotnet" && ( -d "$candidate/sdk" || -d "$candidate/host/fxr" ) ]]
}

path_contains() {
  case ":$PATH:" in
    *":$1:"*) return 0 ;;
    *) return 1 ;;
  esac
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
  if ! path_contains "$DOTNET_TOOLS_DIR"; then
    export PATH="$DOTNET_TOOLS_DIR:$PATH"
  fi

  if [[ "$UPDATE_PATH" -eq 0 ]]; then
    echo "==> Skipping shell profile PATH update (--no-path-update)"
    return 0
  fi

  echo "==> Ensuring nlc is on PATH for future shells"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ mkdir -p $NSHARP_ENV_DIR"
    echo "+ write $NSHARP_ENV_FILE"
  else
    mkdir -p "$NSHARP_ENV_DIR"
    cat > "$NSHARP_ENV_FILE" <<EOF
# Added by N# installer.
export PATH="$DOTNET_TOOLS_DIR:\$PATH"
EOF
    if [[ -n "${DOTNET_ROOT:-}" ]]; then
      printf 'export DOTNET_ROOT=%q\n' "$DOTNET_ROOT" >> "$NSHARP_ENV_FILE"
    fi
    if [[ -n "${DOTNET_ROOT_ARM64:-}" ]]; then
      printf 'export DOTNET_ROOT_ARM64=%q\n' "$DOTNET_ROOT_ARM64" >> "$NSHARP_ENV_FILE"
    fi
    if [[ -n "${DOTNET_ROOT_X64:-}" ]]; then
      printf 'export DOTNET_ROOT_X64=%q\n' "$DOTNET_ROOT_X64" >> "$NSHARP_ENV_FILE"
    fi
    echo "Wrote: $NSHARP_ENV_FILE"
  fi

  while IFS= read -r profile; do
    [[ -n "$profile" ]] || continue
    ensure_profile_sources_env "$profile"
  done < <(profile_candidates)
}

source_args=()
if [[ -n "$NUGET_SOURCE" ]]; then
  source_args=(--add-source "$NUGET_SOURCE")
fi

install_or_update_tool() {
  local package_id="$1"
  local action="install"
  if dotnet tool list -g | grep -qi "^$package_id[[:space:]]"; then
    action="update"
  fi

  local cmd=(dotnet tool "$action" -g "$package_id")
  if [[ ${#source_args[@]} -gt 0 ]]; then
    cmd+=("${source_args[@]}")
  fi
  run "${cmd[@]}"
}

install_templates() {
  run dotnet new uninstall NSharpLang.Templates || true
  local package="NSharpLang.Templates"
  local cmd=(dotnet new install "$package")
  if [[ ${#source_args[@]} -gt 0 ]]; then
    cmd+=("${source_args[@]}")
  fi
  run "${cmd[@]}"
}

install_vscode_extension() {
  if [[ "$SKIP_VSCODE" -eq 1 ]]; then
    echo "==> Skipping VS Code extension (--skip-vscode)"
    return 0
  fi

  if ! command -v code >/dev/null 2>&1; then
    echo "==> VS Code 'code' CLI not found; skipping extension install. Run 'code --install-extension $VSCODE_EXTENSION_ID' after installing VS Code."
    return 0
  fi

  echo "==> Installing VS Code extension: $VSCODE_EXTENSION_ID"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    if code --install-extension "$VSCODE_EXTENSION_ID" --force; then
      return 0
    fi
    if [[ -n "$VSCODE_VSIX_URL" ]]; then
      local tmp
      tmp="$(mktemp -t nsharp-vscode.XXXXXX.vsix)"
      require_command curl
      echo "==> Marketplace install failed; trying VSIX fallback: $VSCODE_VSIX_URL"
      curl -fsSL "$VSCODE_VSIX_URL" -o "$tmp"
      code --install-extension "$tmp" --force
      rm -f "$tmp"
      return 0
    fi
    echo "ERROR: failed to install $VSCODE_EXTENSION_ID from the Marketplace and VSIX fallback is disabled." >&2
    echo "Publish the VS Code extension or provide --vsix-url/NSHARP_VSIX_URL to a release VSIX." >&2
    return 1
  else
    echo "+ code --install-extension $VSCODE_EXTENSION_ID --force"
    if [[ -n "$VSCODE_VSIX_URL" ]]; then
      echo "+ curl -fsSL $VSCODE_VSIX_URL -o <temp-vsix>  # fallback if Marketplace install fails"
      echo "+ code --install-extension <temp-vsix> --force"
    fi
  fi
}

write_shared_config() {
  local config_dir="$HOME/.nsharp"
  local config_file="$config_dir/NuGet.config"
  echo "==> Writing shared NuGet.config: $config_file"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$config_dir"
    if [[ "$NUGET_SOURCE" == "$DEFAULT_NUGET_SOURCE" ]]; then
      cat > "$config_file" <<NUGETCONFIG
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="$DEFAULT_NUGET_SOURCE" />
  </packageSources>
</configuration>
NUGETCONFIG
    else
      cat > "$config_file" <<NUGETCONFIG
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="nsharp" value="$NUGET_SOURCE" />
  </packageSources>
  <packageSourceMapping>
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
    <packageSource key="nsharp">
      <package pattern="NSharpLang.*" />
    </packageSource>
  </packageSourceMapping>
</configuration>
NUGETCONFIG
    fi
  else
    echo "+ mkdir -p $config_dir && write $config_file"
  fi
}

uninstall_nsharp() {
  echo "==> Removing N# toolchain"
  run dotnet tool uninstall -g NSharpLang.Cli || true
  run dotnet tool uninstall -g NSharpLang.LanguageServer || true
  run dotnet new uninstall NSharpLang.Templates || true
  if [[ "$SKIP_VSCODE" -eq 0 ]] && command -v code >/dev/null 2>&1; then
    run code --uninstall-extension "$VSCODE_EXTENSION_ID" || true
  fi
  echo "N# uninstall complete. Shared config under ~/.nsharp is left in place for auditability; remove it manually if desired."
}

require_command dotnet
resolved_dotnet_root="$(resolve_dotnet_root "$(command -v dotnet)")"
if ! is_dotnet_root "${DOTNET_ROOT:-}" && is_dotnet_root "$resolved_dotnet_root"; then
  export DOTNET_ROOT="$resolved_dotnet_root"
fi
if [[ -n "${DOTNET_ROOT:-}" ]]; then
  case "$(uname -m)" in
    arm64|aarch64)
      if ! is_dotnet_root "${DOTNET_ROOT_ARM64:-}"; then
        export DOTNET_ROOT_ARM64="$DOTNET_ROOT"
      fi
      ;;
    x86_64|amd64)
      if ! is_dotnet_root "${DOTNET_ROOT_X64:-}"; then
        export DOTNET_ROOT_X64="$DOTNET_ROOT"
      fi
      ;;
  esac
fi

if [[ "$UNINSTALL" -eq 1 ]]; then
  uninstall_nsharp
  exit 0
fi

echo "========================================"
echo "Installing N# toolchain"
echo "========================================"
echo "Source:  $NUGET_SOURCE"
echo "Version: latest available"
echo "Tools:   $DOTNET_TOOLS_DIR"
echo ""

install_templates
install_or_update_tool NSharpLang.Cli
install_or_update_tool NSharpLang.LanguageServer
ensure_dotnet_tools_path
write_shared_config
install_vscode_extension

if [[ "$DRY_RUN" -eq 0 ]]; then
  echo "==> Verifying install"
  if command -v code >/dev/null 2>&1 && [[ "$SKIP_VSCODE" -eq 0 ]]; then
    nlc doctor --require-vscode
  else
    nlc doctor --skip-vscode
  fi
fi

echo ""
echo "N# install complete. Try:"
echo "  nlc new MyApp && cd MyApp && nlc run"
echo ""
echo "If this shell still cannot find nlc, run:"
echo "  . \"\$HOME/.nsharp/env\""
