#!/bin/bash
set -euo pipefail

NUGET_SOURCE="https://api.nuget.org/v3/index.json"

read_version() {
  python3 - "$1" <<'PY'
import re, sys
text=open(sys.argv[1], encoding='utf-8').read()
match=re.search(r'<Version>([^<]+)</Version>', text)
if not match:
    raise SystemExit(f'No <Version> in {sys.argv[1]}')
print(match.group(1))
PY
}

package_path() {
  local id="$1"
  local project="$2"
  local version
  version="$(read_version "$project")"
  echo "artifacts/nuget/${id}.${version}.nupkg"
}

PACKAGES=(
  "$(package_path NSharpLang.Sdk src/NSharpLang.Sdk/NSharpLang.Sdk.csproj)"
  "$(package_path NSharpLang.Templates templates/NSharpLang.Templates.csproj)"
  "$(package_path NSharpLang.Compiler src/NSharpLang.Compiler/Compiler.csproj)"
  "$(package_path NSharpLang.Cli src/NSharpLang.Cli/Cli.csproj)"
  "$(package_path NSharpLang.LanguageServer src/NSharpLang.LanguageServer/LanguageServer.csproj)"
)

echo "================================"
echo "Publishing N# NuGet Packages"
echo "================================"

if [[ -z "${NUGET_API_KEY:-}" ]]; then
  echo "ERROR: NUGET_API_KEY environment variable is not set"
  echo "Please set it using: export NUGET_API_KEY=your_api_key"
  exit 1
fi

echo ""
echo "Checking packages from project-file version source..."
for pkg in "${PACKAGES[@]}"; do
  if [[ ! -f "$pkg" ]]; then
    echo "ERROR: $pkg not found. Run ./scripts/pack-nuget.sh first"
    exit 1
  fi
  echo "  - $pkg"
done

echo ""
echo "Publishing packages to $NUGET_SOURCE..."
for pkg in "${PACKAGES[@]}"; do
  echo ""
  echo "Publishing $(basename "$pkg")..."
  dotnet nuget push "$pkg" --api-key "$NUGET_API_KEY" --source "$NUGET_SOURCE" --skip-duplicate
done

echo ""
echo "================================"
echo "NuGet packages published successfully!"
echo "================================"
echo ""
echo "Canonical public install command:"
echo "  curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash"
echo ""
echo "VS Code extension publishing is separate: publish artifacts/vscode/*.vsix to the Marketplace/Open VSX or a GitHub release before announcing IDE auto-install as public-green."
