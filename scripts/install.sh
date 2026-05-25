#!/usr/bin/env bash
set -euo pipefail

DEFAULT_TOOLSET_URL="https://github.com/schneidenbach/nsharplang/releases/latest/download/nsharp-toolset.tar.gz"
DEFAULT_VSIX_URL="https://github.com/schneidenbach/nsharplang/releases/latest/download/nsharp.vsix"

TOOLSET_SOURCE="${NSHARP_TOOLSET_URL:-$DEFAULT_TOOLSET_URL}"
VSCODE_VSIX_URL="${NSHARP_VSIX_URL:-$DEFAULT_VSIX_URL}"
INSTALL_DIR="${NSHARP_INSTALL_DIR:-$HOME/.nsharp}"
ENV_FILE="${NSHARP_ENV_FILE:-$INSTALL_DIR/env}"
VSCODE_EXTENSION_ID="nsharp.nsharp"
DRY_RUN=0
SKIP_VSCODE=0
UNINSTALL=0
UPDATE_PATH=1

usage() {
  cat <<EOF
Usage: install.sh [options]

Turnkey installer for the public N# toolchain. Installs the package-manager
toolset layout: nlc, nsharp-lsp, the N# SDK/template/compiler packages, and the
VS Code extension when the 'code' CLI is available.

Canonical one-liner:
  curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . "\$HOME/.nsharp/env"

Options:
  --source SOURCE       Toolset directory, .tar.gz archive, or URL
                        (default: latest GitHub release toolset)
  --install-dir DIR     Install directory (default: ~/.nsharp)
  --vsix-url URL        VSIX fallback URL when Marketplace install fails
  --no-vsix-fallback    Do not try a VSIX fallback after Marketplace install
  --skip-vscode         Do not install/probe the VS Code extension
  --no-path-update      Do not update shell profile files
  --uninstall           Remove N# installed payloads instead
  --dry-run             Print commands without running them
  --help, -h            Show this help text

Version pinning:
  Use your package manager for version selection. This script installs the
  provided toolset source as-is.

Environment:
  NSHARP_TOOLSET_URL    Default toolset URL
  NSHARP_VSIX_URL       VSIX fallback URL when Marketplace install fails
  NSHARP_INSTALL_DIR    Install directory (default: ~/.nsharp)
  NSHARP_ENV_FILE       Shell env file (default: <install-dir>/env)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "ERROR: --source requires a value." >&2
        exit 2
      fi
      TOOLSET_SOURCE="$2"
      shift
      ;;
    --install-dir)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "ERROR: --install-dir requires a value." >&2
        exit 2
      fi
      INSTALL_DIR="$2"
      ENV_FILE="${NSHARP_ENV_FILE:-$INSTALL_DIR/env}"
      shift
      ;;
    --version|--version=*)
      echo "ERROR: scripts/install.sh does not support --version." >&2
      echo "Use Homebrew/winget/apt/rpm for version selection, or pass an exact --source toolset archive." >&2
      exit 2
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

require_safe_install_dir() {
  if [[ -z "$INSTALL_DIR" || "$INSTALL_DIR" == "/" || "$INSTALL_DIR" == "$HOME" ]]; then
    echo "ERROR: refusing unsafe N# install directory: ${INSTALL_DIR:-<empty>}" >&2
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

  for candidate in "$bin_dir" "$parent/libexec" "$parent" "$HOME/.dotnet" "/opt/homebrew/opt/dotnet/libexec" "/usr/local/opt/dotnet/libexec" "/usr/local/share/dotnet" "/usr/share/dotnet"; do
    if [[ -x "$candidate/dotnet" && -d "$candidate/shared/Microsoft.NETCore.App" ]] &&
      compgen -G "$candidate/shared/Microsoft.NETCore.App/10.*" >/dev/null; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
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
    zsh) profiles+=("$HOME/.zshrc") ;;
    bash)
      profiles+=("$HOME/.bashrc")
      if [[ "$(uname -s)" == "Darwin" ]]; then
        profiles+=("$HOME/.bash_profile")
      fi
      ;;
  esac

  for candidate in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [[ -f "$candidate" ]]; then
      local listed=0
      for profile in "${profiles[@]}"; do
        [[ "$profile" == "$candidate" ]] && listed=1 && break
      done
      [[ "$listed" -eq 0 ]] && profiles+=("$candidate")
    fi
  done

  [[ "${#profiles[@]}" -eq 0 ]] && profiles+=("$HOME/.profile")
  printf '%s\n' "${profiles[@]}"
}

ensure_profile_sources_env() {
  local profile="$1"
  local source_line
  if [[ "$ENV_FILE" == "$HOME/.nsharp/env" ]]; then
    source_line='[ -f "$HOME/.nsharp/env" ] && . "$HOME/.nsharp/env"'
  else
    source_line="[ -f \"$ENV_FILE\" ] && . \"$ENV_FILE\""
  fi

  if [[ -f "$profile" ]] && grep -Fq "$source_line" "$profile"; then
    echo "Profile already sources N# env: $profile"
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ append N# env source to $profile"
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

write_env_file() {
  local dotnet_root=""
  if command -v dotnet >/dev/null 2>&1; then
    dotnet_root="$(resolve_dotnet_root "$(command -v dotnet)" || true)"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ mkdir -p $(dirname "$ENV_FILE")"
    echo "+ write $ENV_FILE"
    return 0
  fi

  mkdir -p "$(dirname "$ENV_FILE")"
  cat > "$ENV_FILE" <<EOF
# Added by N# installer.
export PATH="$INSTALL_DIR/bin:\$PATH"
EOF
  if [[ -n "$dotnet_root" ]]; then
    {
      printf 'export DOTNET_ROOT=%q\n' "$dotnet_root"
      case "$(uname -m)" in
        arm64|aarch64) echo 'export DOTNET_ROOT_ARM64="${DOTNET_ROOT_ARM64:-$DOTNET_ROOT}"' ;;
        x86_64|amd64) echo 'export DOTNET_ROOT_X64="${DOTNET_ROOT_X64:-$DOTNET_ROOT}"' ;;
        i386|i686) echo 'export DOTNET_ROOT_X86="${DOTNET_ROOT_X86:-$DOTNET_ROOT}"' ;;
      esac
    } >> "$ENV_FILE"
  fi
  echo "Wrote: $ENV_FILE"
}

write_shared_config() {
  local config_file="$INSTALL_DIR/NuGet.config"
  local packages_dir="$INSTALL_DIR/packages"

  echo "==> Writing shared NuGet.config: $config_file"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ mkdir -p $INSTALL_DIR && write $config_file"
    return 0
  fi

  mkdir -p "$INSTALL_DIR"
  cat > "$config_file" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="nsharp-local" value="$packages_dir" />
  </packageSources>
  <packageSourceMapping>
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
    <packageSource key="nsharp-local">
      <package pattern="NSharpLang.*" />
    </packageSource>
  </packageSourceMapping>
</configuration>
EOF
}

toolset_dir_from_root() {
  local root="$1"
  if [[ -d "$root/bin" && -d "$root/lib" ]]; then
    echo "$root"
    return 0
  fi

  local child
  while IFS= read -r child; do
    if [[ -d "$child/bin" && -d "$child/lib" ]]; then
      echo "$child"
      return 0
    fi
  done < <(find "$root" -mindepth 1 -maxdepth 2 -type d 2>/dev/null)

  return 1
}

extract_toolset_archive() {
  local archive="$1"
  local destination="$2"
  mkdir -p "$destination"
  tar -xzf "$archive" -C "$destination"
  toolset_dir_from_root "$destination"
}

prepare_toolset_source() {
  local source="$1"
  local work_dir="$2"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ resolve toolset source $source"
    return 0
  fi

  if [[ -d "$source" ]]; then
    if [[ -f "$source/nsharp-toolset.tar.gz" ]]; then
      extract_toolset_archive "$source/nsharp-toolset.tar.gz" "$work_dir/extracted"
      return 0
    fi
    toolset_dir_from_root "$source"
    return 0
  fi

  if [[ -f "$source" ]]; then
    extract_toolset_archive "$source" "$work_dir/extracted"
    return 0
  fi

  require_command curl
  local archive="$work_dir/nsharp-toolset.tar.gz"
  echo "+ curl -fsSL $source -o $archive" >&2
  curl -fsSL "$source" -o "$archive"
  extract_toolset_archive "$archive" "$work_dir/extracted"
}

install_toolset() {
  local source_dir="$1"
  require_safe_install_dir

  echo "==> Installing N# toolset to $INSTALL_DIR"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ mkdir -p $INSTALL_DIR"
    echo "+ copy bin/lib/packages from $source_dir to $INSTALL_DIR"
    return 0
  fi

  if [[ ! -d "$source_dir/bin" || ! -d "$source_dir/lib" ]]; then
    echo "ERROR: $source_dir is not an N# toolset directory." >&2
    exit 1
  fi

  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" "$INSTALL_DIR/packages"
  cp -R "$source_dir/bin" "$INSTALL_DIR/bin"
  cp -R "$source_dir/lib" "$INSTALL_DIR/lib"
  if [[ -d "$source_dir/packages" ]]; then
    cp -R "$source_dir/packages" "$INSTALL_DIR/packages"
  else
    mkdir -p "$INSTALL_DIR/packages"
  fi
  if [[ -f "$source_dir/VERSION" ]]; then
    cp -f "$source_dir/VERSION" "$INSTALL_DIR/VERSION"
  fi
}

install_templates() {
  echo "==> Installing N# templates"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ dotnet new uninstall NSharpLang.Templates || true"
    echo "+ dotnet new install $INSTALL_DIR/packages/NSharpLang.Templates.<version>.nupkg --force"
    return 0
  fi

  local template_package
  template_package="$(find "$INSTALL_DIR/packages" -maxdepth 1 -name 'NSharpLang.Templates.*.nupkg' -type f | sort | tail -n 1)"
  if [[ -z "$template_package" ]]; then
    echo "ERROR: no NSharpLang.Templates package found in $INSTALL_DIR/packages" >&2
    exit 1
  fi

  dotnet new uninstall NSharpLang.Templates >/dev/null 2>&1 || true
  run dotnet new install "$template_package" --force
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
    return 1
  else
    echo "+ code --install-extension $VSCODE_EXTENSION_ID --force"
    if [[ -n "$VSCODE_VSIX_URL" ]]; then
      echo "+ curl -fsSL $VSCODE_VSIX_URL -o <temp-vsix>  # fallback if Marketplace install fails"
      echo "+ code --install-extension <temp-vsix> --force"
    fi
  fi
}

uninstall_nsharp() {
  require_safe_install_dir
  echo "==> Removing N# installed payloads"
  run rm -rf "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" "$INSTALL_DIR/packages" "$INSTALL_DIR/VERSION"
  if command -v dotnet >/dev/null 2>&1; then
    run dotnet new uninstall NSharpLang.Templates || true
  fi
  if [[ "$SKIP_VSCODE" -eq 0 ]] && command -v code >/dev/null 2>&1; then
    run code --uninstall-extension "$VSCODE_EXTENSION_ID" || true
  fi
  echo "N# uninstall complete. Shell profile entries and $ENV_FILE are left for auditability."
}

require_safe_install_dir

if [[ "$UNINSTALL" -eq 1 ]]; then
  uninstall_nsharp
  exit 0
fi

require_command dotnet

echo "========================================"
echo "Installing N# toolchain"
echo "========================================"
echo "Source:  $TOOLSET_SOURCE"
echo "Install: $INSTALL_DIR"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Mode:    dry-run"
fi
echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
  TOOLSET_DIR="<resolved-toolset>"
  prepare_toolset_source "$TOOLSET_SOURCE" ""
else
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  TOOLSET_DIR="$(prepare_toolset_source "$TOOLSET_SOURCE" "$WORK_DIR")"
fi

install_toolset "$TOOLSET_DIR"
install_templates
write_shared_config

echo "==> Ensuring nlc is on PATH for future shells"
if ! path_contains "$INSTALL_DIR/bin"; then
  export PATH="$INSTALL_DIR/bin:$PATH"
fi
write_env_file
if [[ "$UPDATE_PATH" -eq 1 ]]; then
  while IFS= read -r profile; do
    [[ -n "$profile" ]] || continue
    ensure_profile_sources_env "$profile"
  done < <(profile_candidates)
else
  echo "Skipping shell profile PATH update (--no-path-update)."
fi

install_vscode_extension

if [[ "$DRY_RUN" -eq 0 ]]; then
  echo "==> Verifying install"
  if command -v code >/dev/null 2>&1 && [[ "$SKIP_VSCODE" -eq 0 ]]; then
    "$INSTALL_DIR/bin/nlc" doctor --require-vscode
  else
    "$INSTALL_DIR/bin/nlc" doctor --skip-vscode
  fi
fi

echo ""
echo "N# install complete. Try:"
echo "  nlc new MyApp && cd MyApp && nlc run"
echo ""
echo "For this shell, run:"
echo "  . \"$ENV_FILE\""
