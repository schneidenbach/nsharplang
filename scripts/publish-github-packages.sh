#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACTS_DIR="$PROJECT_ROOT/artifacts/nuget"

GITHUB_OWNER="schneidenbach"
GITHUB_FEED="https://nuget.pkg.github.com/${GITHUB_OWNER}/index.json"

usage() {
    cat <<EOF
Usage: ./scripts/publish-github-packages.sh [options]

Publishes all N# NuGet packages to GitHub Packages.

Prerequisites:
  1. Run ./scripts/pack-nuget.sh first to create packages in artifacts/nuget/
  2. Set GITHUB_TOKEN (a PAT with write:packages scope)

Options:
  --dry-run    Show what would be pushed without pushing
  --help       Show this help text

Environment:
  GITHUB_TOKEN    GitHub personal access token with write:packages scope
EOF
}

DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "ERROR: GITHUB_TOKEN is not set."
    echo "Create a PAT at https://github.com/settings/tokens with write:packages scope."
    echo "Then: export GITHUB_TOKEN=ghp_..."
    exit 1
fi

if [[ ! -d "$ARTIFACTS_DIR" ]]; then
    echo "ERROR: $ARTIFACTS_DIR does not exist."
    echo "Run ./scripts/pack-nuget.sh first."
    exit 1
fi

shopt -s nullglob
PACKAGES=("$ARTIFACTS_DIR"/*.nupkg)
shopt -u nullglob

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
    echo "ERROR: No .nupkg files found in $ARTIFACTS_DIR"
    echo "Run ./scripts/pack-nuget.sh first."
    exit 1
fi

echo "========================================"
echo "Publishing to GitHub Packages"
echo "========================================"
echo "Feed:     $GITHUB_FEED"
echo "Packages: ${#PACKAGES[@]} found"
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Mode:     dry-run"
fi
echo ""

for pkg in "${PACKAGES[@]}"; do
    name="$(basename "$pkg")"
    echo "Publishing $name..."

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "  [dry-run] dotnet nuget push $name --source $GITHUB_FEED --skip-duplicate"
    else
        dotnet nuget push "$pkg" \
            --api-key "$GITHUB_TOKEN" \
            --source "$GITHUB_FEED" \
            --skip-duplicate
    fi
    echo ""
done

echo "========================================"
echo "Done."
echo "========================================"
echo ""
echo "To consume from another machine, run:"
echo "  ./scripts/setup-consumer.sh"
