#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/lib/toolset.sh"
source "$SCRIPT_DIR/lib/vscode-extension.sh"

cd "$NSHARP_REPO_ROOT"

echo "================================"
echo "Packing N# Release Artifacts"
echo "================================"

# Create artifacts directories
mkdir -p artifacts/nuget artifacts/toolset artifacts/vscode

nsharp_pack_package_set artifacts/nuget minimal

echo ""
echo "Publishing package-manager toolset..."
nsharp_publish_toolset "artifacts/toolset/nsharp" "artifacts/nuget"
(
    cd artifacts/toolset
    rm -f nsharp-toolset.tar.gz
    tar -czf nsharp-toolset.tar.gz nsharp
)

if [[ "${SKIP_VSCODE_PACKAGE:-0}" != "1" ]]; then
    echo ""
    echo "Packaging VS Code extension..."
    nsharp_build_vscode_extension_package
    cp -f editors/vscode/*.vsix artifacts/vscode/ 2>/dev/null || true
    if latest_vsix="$(nsharp_latest_vscode_vsix)"; then
        cp -f "$latest_vsix" artifacts/vscode/nsharp.vsix
    fi
else
    echo ""
    echo "Skipping VS Code extension package (SKIP_VSCODE_PACKAGE=1)."
fi

echo ""
echo "================================"
echo "Artifacts created successfully:"
echo "================================"
ls -lh artifacts/nuget/*.nupkg
ls -lh artifacts/toolset/nsharp-toolset.tar.gz
if compgen -G "artifacts/vscode/*.vsix" >/dev/null; then
    ls -lh artifacts/vscode/*.vsix
fi

echo ""
echo "Release artifact set:"
nsharp_print_release_artifact_set
