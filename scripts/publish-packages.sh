#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"

cd "$NSHARP_REPO_ROOT"

TARGET="nuget"
DRY_RUN=0
NUGET_SOURCE="${NUGET_SOURCE:-https://api.nuget.org/v3/index.json}"
GITHUB_OWNER="${GITHUB_OWNER:-schneidenbach}"
GITHUB_FEED="${GITHUB_FEED:-https://nuget.pkg.github.com/${GITHUB_OWNER}/index.json}"

usage() {
    cat <<EOF
Usage: ./scripts/publish-packages.sh [options]

Publishes the canonical N# NuGet package set from artifacts/nuget/.

Options:
  --target nuget|github  Publish to nuget.org (default) or GitHub Packages
  --dry-run              Validate package paths and print push commands
  --help, -h             Show this help text

Environment:
  NUGET_API_KEY          Required for --target nuget unless --dry-run is set
  NUGET_SOURCE           NuGet source URL (default: $NUGET_SOURCE)
  GITHUB_TOKEN           Required for --target github unless --dry-run is set
  GITHUB_OWNER           GitHub package owner (default: $GITHUB_OWNER)
  GITHUB_FEED            GitHub Packages feed URL (default: $GITHUB_FEED)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --target requires nuget or github" >&2
                exit 1
            fi
            TARGET="$2"
            shift
            ;;
        --target=*)
            TARGET="${1#*=}"
            ;;
        --dry-run)
            DRY_RUN=1
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

case "$TARGET" in
    nuget|github) ;;
    *)
        echo "ERROR: unknown target '$TARGET'. Expected nuget or github." >&2
        exit 1
        ;;
esac

if [[ "$DRY_RUN" -eq 0 ]]; then
    case "$TARGET" in
        nuget)
            if [[ -z "${NUGET_API_KEY:-}" ]]; then
                echo "ERROR: NUGET_API_KEY environment variable is not set." >&2
                echo "Please set it using: export NUGET_API_KEY=your_api_key" >&2
                exit 1
            fi
            ;;
        github)
            if [[ -z "${GITHUB_TOKEN:-}" ]]; then
                echo "ERROR: GITHUB_TOKEN is not set." >&2
                echo "Create a PAT at https://github.com/settings/tokens with write:packages scope." >&2
                exit 1
            fi
            ;;
    esac
fi

PACKAGES=()
while IFS='|' read -r package_id _label project; do
    PACKAGES+=("$(nsharp_package_artifact_path "$package_id" "$project" "artifacts/nuget")")
done < <(nsharp_each_package_spec)

echo "========================================"
echo "Publishing N# Packages"
echo "========================================"
echo "Target:   $TARGET"
if [[ "$TARGET" == "nuget" ]]; then
    echo "Source:   $NUGET_SOURCE"
else
    echo "Source:   $GITHUB_FEED"
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Mode:     dry-run"
fi

echo
echo "Checking packages from project-file version source..."
for pkg in "${PACKAGES[@]}"; do
    if [[ ! -f "$pkg" ]]; then
        echo "ERROR: $pkg not found. Run ./scripts/pack-nuget.sh first." >&2
        exit 1
    fi
    echo "  - $pkg"
done

echo
for pkg in "${PACKAGES[@]}"; do
    name="$(basename "$pkg")"
    echo "Publishing $name..."

    if [[ "$DRY_RUN" -eq 1 ]]; then
        if [[ "$TARGET" == "nuget" ]]; then
            echo "  [dry-run] dotnet nuget push $pkg --source $NUGET_SOURCE --skip-duplicate"
        else
            echo "  [dry-run] dotnet nuget push $pkg --source $GITHUB_FEED --skip-duplicate"
        fi
    elif [[ "$TARGET" == "nuget" ]]; then
        dotnet nuget push "$pkg" --api-key "$NUGET_API_KEY" --source "$NUGET_SOURCE" --skip-duplicate
    else
        dotnet nuget push "$pkg" --api-key "$GITHUB_TOKEN" --source "$GITHUB_FEED" --skip-duplicate
    fi

    echo
done

echo "========================================"
echo "Package publish complete."
echo "========================================"
if [[ "$TARGET" == "nuget" ]]; then
    echo
    echo "Canonical public install command:"
    echo "  curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . \"\$HOME/.nsharp/env\""
    echo
    echo "VS Code extension publishing is separate: publish artifacts/vscode/nsharp.vsix to a GitHub Release or publish nsharp.nsharp to the Marketplace before announcing IDE auto-install as public-green."
fi
