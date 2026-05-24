#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"

PROJECT_ROOT="$NSHARP_REPO_ROOT"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts/nuget"
PACKAGE_ID="NSharpLang.Cli"
PACKAGE_CACHE_DIR="$HOME/.nuget/packages/nsharplang.cli"
TOOL_STORE_DIR="$HOME/.dotnet/tools/.store/nsharplang.cli"
TOOL_PATH="$HOME/.dotnet/tools/nlc"

read_version() {
    nsharp_package_version "src/NSharpLang.Cli/Cli.csproj"
}

require_command() {
    nsharp_require_command "$1"
}

resolve_dotnet_root() {
    nsharp_resolve_dotnet_root "$1"
}

require_command dotnet
require_command python3

VERSION="$(read_version)"
if [[ -z "$VERSION" ]]; then
    echo "Error: failed to read CLI version from Cli.csproj" >&2
    exit 1
fi

DOTNET_ROOT="$(resolve_dotnet_root "$(command -v dotnet)")"
export DOTNET_ROOT

echo "==> Building and packing $PACKAGE_ID $VERSION"
mkdir -p "$ARTIFACTS_DIR"
dotnet build "$PROJECT_ROOT/src/NSharpLang.Cli/Cli.csproj" -c Release -v q
dotnet pack "$PROJECT_ROOT/src/NSharpLang.Cli/Cli.csproj" -c Release -o "$ARTIFACTS_DIR" -v q

echo "==> Clearing cached tool copies"
dotnet tool uninstall --global "$PACKAGE_ID" >/dev/null 2>&1 || true
rm -rf "$PACKAGE_CACHE_DIR" "$TOOL_STORE_DIR"

echo "==> Installing global nlc from local package"
dotnet tool install --global --source "$ARTIFACTS_DIR" "$PACKAGE_ID" --version "$VERSION" --no-http-cache

echo "==> Verifying installation"
if [[ -x "$TOOL_PATH" ]]; then
    "$TOOL_PATH" --help >/dev/null
else
    echo "Error: expected tool at $TOOL_PATH" >&2
    exit 1
fi

if zsh -lc 'command -v nlc >/dev/null 2>&1'; then
    zsh -lc 'nlc --help >/dev/null'
    echo "Installed: $(zsh -lc 'command -v nlc')"
else
    echo "Installed: $TOOL_PATH"
    echo "Note: add $HOME/.dotnet/tools to PATH for fresh shells."
fi

echo "Local nlc install complete."
