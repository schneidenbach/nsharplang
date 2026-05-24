#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"

cd "$NSHARP_REPO_ROOT"

NUGET_SOURCE="https://api.nuget.org/v3/index.json"

package_path() {
    local id="$1"
    local project="$2"
    nsharp_package_artifact_path "$id" "$project" "artifacts/nuget"
}

PACKAGES=()
while IFS='|' read -r package_id _label project; do
    PACKAGES+=("$(package_path "$package_id" "$project")")
done < <(nsharp_each_package_spec)

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
