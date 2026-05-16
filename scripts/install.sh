#!/usr/bin/env bash
set -euo pipefail

NUGET_SOURCE="https://api.nuget.org/v3/index.json"
VERSION=""
DRY_RUN=0
SKIP_VSCODE=0
UNINSTALL=0
VSCODE_EXTENSION_ID="nsharp.nsharp"

usage() {
  cat <<EOF
Usage: install.sh [options]

Turnkey installer for the public N# toolchain. Installs the user-facing NSharpLang
surface: nlc CLI, dotnet new templates, SDK restore support, language server, and
VS Code extension when the 'code' CLI is available.

Canonical one-liner:
  curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash

Options:
  --version VERSION     Install an exact NSharpLang package version
  --source SOURCE       NuGet source or local feed directory (default: NuGet.org)
  --skip-vscode         Do not install/probe the VS Code extension
  --uninstall           Remove N# tools/templates/VS Code extension instead
  --dry-run             Print commands without running them
  --help, -h            Show this help text

Environment:
  NSHARP_VSIX_URL       Optional VSIX fallback URL when marketplace install fails
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift ;;
    --source) NUGET_SOURCE="$2"; shift ;;
    --skip-vscode) SKIP_VSCODE=1 ;;
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
  python3 - "$1" <<'PY'
import os, sys
real = os.path.realpath(sys.argv[1])
bin_dir = os.path.dirname(real)
for candidate in (os.path.join(os.path.dirname(bin_dir), 'libexec'), os.path.dirname(bin_dir), bin_dir):
    if os.path.isdir(candidate):
        print(candidate)
        break
PY
}

tool_version_args=()
template_version_args=()
if [[ -n "$VERSION" ]]; then
  tool_version_args=(--version "$VERSION")
  template_version_args=("::$VERSION")
fi

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
  if [[ ${#tool_version_args[@]} -gt 0 ]]; then
    cmd+=("${tool_version_args[@]}")
  fi
  if [[ ${#source_args[@]} -gt 0 ]]; then
    cmd+=("${source_args[@]}")
  fi
  run "${cmd[@]}"
}

install_templates() {
  run dotnet new uninstall NSharpLang.Templates || true
  local package="NSharpLang.Templates"
  if [[ ${#template_version_args[@]} -gt 0 ]]; then
    package="NSharpLang.Templates${template_version_args[0]}"
  fi
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
    if [[ -n "${NSHARP_VSIX_URL:-}" ]]; then
      local tmp
      tmp="$(mktemp -t nsharp-vscode.XXXXXX.vsix)"
      curl -fsSL "$NSHARP_VSIX_URL" -o "$tmp"
      code --install-extension "$tmp" --force
      rm -f "$tmp"
      return 0
    fi
    echo "ERROR: failed to install $VSCODE_EXTENSION_ID from the marketplace and NSHARP_VSIX_URL was not set." >&2
    echo "Publish the VS Code extension or provide NSHARP_VSIX_URL to a release VSIX." >&2
    return 1
  else
    echo "+ code --install-extension $VSCODE_EXTENSION_ID --force"
  fi
}

write_shared_config() {
  local config_dir="$HOME/.nsharp"
  local config_file="$config_dir/NuGet.config"
  echo "==> Writing shared NuGet.config: $config_file"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$config_dir"
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
require_command python3
export DOTNET_ROOT="${DOTNET_ROOT:-$(resolve_dotnet_root "$(command -v dotnet)")}"

if [[ "$UNINSTALL" -eq 1 ]]; then
  uninstall_nsharp
  exit 0
fi

echo "========================================"
echo "Installing N# toolchain"
echo "========================================"
echo "Source:  $NUGET_SOURCE"
echo "Version: ${VERSION:-latest available}"
echo ""

install_templates
install_or_update_tool NSharpLang.Cli
install_or_update_tool NSharpLang.LanguageServer
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
