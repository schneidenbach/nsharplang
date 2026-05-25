#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/lib/toolset.sh"

OUTPUT_DIR="${NSHARP_TOOLSET_OUTPUT:-$NSHARP_REPO_ROOT/artifacts/toolset/nsharp}"
PACKAGE_DIR="${NSHARP_LOCAL_FEED:-$NSHARP_REPO_ROOT/artifacts/nuget}"
ARCHIVE_PATH="${NSHARP_TOOLSET_ARCHIVE:-$NSHARP_REPO_ROOT/artifacts/toolset/nsharp-toolset.tar.gz}"
SKIP_PACKAGES=0
SKIP_ARCHIVE=0

usage() {
    cat <<EOF
Usage: ./scripts/publish-toolset.sh [options]

Publishes the package-manager-ready N# toolset:
  - framework-dependent nlc app payload
  - framework-dependent nsharp-lsp app payload
  - N# launchers that resolve .NET without dotnet global-tool apphosts
  - NSharpLang SDK/template/compiler packages used by generated projects

Options:
  --output DIR       Toolset directory (default: artifacts/toolset/nsharp)
  --packages DIR     NuGet package directory to bundle (default: artifacts/nuget)
  --archive FILE     tar.gz artifact path (default: artifacts/toolset/nsharp-toolset.tar.gz)
  --skip-packages    Do not pack SDK/template/compiler packages first
  --skip-archive     Do not create the tar.gz artifact
  --help, -h         Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT_DIR="$2"
            shift
            ;;
        --packages)
            PACKAGE_DIR="$2"
            shift
            ;;
        --archive)
            ARCHIVE_PATH="$2"
            shift
            ;;
        --skip-packages)
            SKIP_PACKAGES=1
            ;;
        --skip-archive)
            SKIP_ARCHIVE=1
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

nsharp_require_command dotnet

mkdir -p "$PACKAGE_DIR"

if [[ "$SKIP_PACKAGES" -eq 0 ]]; then
    nsharp_log "Packing SDK, templates, and compiler packages"
    nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet build src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj -c Release -v q
    while IFS='|' read -r _package_id label project; do
        nsharp_log "Packing $label"
        nsharp_run_in_dir "$NSHARP_REPO_ROOT" dotnet pack "$project" -c Release -o "$PACKAGE_DIR" -v q
    done < <(nsharp_each_package_spec)
fi

nsharp_log "Publishing N# toolset"
nsharp_publish_toolset "$OUTPUT_DIR" "$PACKAGE_DIR"

if [[ "$SKIP_ARCHIVE" -eq 0 ]]; then
    nsharp_log "Creating toolset archive"
    mkdir -p "$(dirname "$ARCHIVE_PATH")"
    rm -f "$ARCHIVE_PATH"
    (
        cd "$(dirname "$OUTPUT_DIR")"
        tar -czf "$ARCHIVE_PATH" "$(basename "$OUTPUT_DIR")"
    )
    echo "Archive: $ARCHIVE_PATH"
fi

echo
echo "Toolset published: $OUTPUT_DIR"
echo "Launchers:"
echo "  $OUTPUT_DIR/bin/nlc"
echo "  $OUTPUT_DIR/bin/nsharp-lsp"
