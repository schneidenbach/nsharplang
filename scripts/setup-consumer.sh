#!/usr/bin/env bash
set -euo pipefail

GITHUB_OWNER="schneidenbach"
GITHUB_FEED="https://nuget.pkg.github.com/${GITHUB_OWNER}/index.json"
SOURCE_NAME="nsharp-github"

usage() {
    cat <<EOF
Usage: setup-consumer.sh [options]

Sets up a machine to consume N# packages from the private GitHub Packages feed.
Automatically uses 'gh auth token' if GITHUB_TOKEN is not set.

This script:
  1. Registers the GitHub Packages NuGet source (with authentication)
  2. Installs dotnet new templates
  3. Installs the nlc CLI tool
  4. Installs the N# language server

One-liner (requires gh CLI):
  bash <(gh api repos/schneidenbach/nsharplang/contents/scripts/setup-consumer.sh -H "Accept: application/vnd.github.raw")

Options:
  --token TOKEN   Use this token instead of auto-detection
  --dry-run       Show what would be done without doing it
  --help          Show this help text
EOF
}

DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --token)
            GITHUB_TOKEN="$2"
            shift
            ;;
        --dry-run) DRY_RUN=1 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
    shift
done

# Auto-detect token from gh CLI if not provided
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    if command -v gh >/dev/null 2>&1; then
        GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
    fi
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "ERROR: No GitHub token found."
    echo ""
    echo "Option 1: Install gh CLI and run 'gh auth login'"
    echo "Option 2: export GITHUB_TOKEN=ghp_... (PAT with read:packages scope)"
    echo "Option 3: ./scripts/setup-consumer.sh --token ghp_..."
    exit 1
fi

run() {
    # Mask passwords/tokens in log output
    local display=""
    local mask_next=0
    for arg in "$@"; do
        if [[ "$mask_next" -eq 1 ]]; then
            display="$display ***"
            mask_next=0
        else
            display="$display $arg"
        fi
        if [[ "$arg" == "--password" || "$arg" == "--api-key" ]]; then
            mask_next=1
        fi
    done
    echo "+$display"
    if [[ "$DRY_RUN" -eq 0 ]]; then
        "$@"
    fi
}

echo "========================================"
echo "Setting up N# toolchain"
echo "========================================"
if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "Mode: dry-run"
fi
echo ""

# Step 1: Register the NuGet source
echo "==> Registering NuGet source: $SOURCE_NAME"
if [[ "$DRY_RUN" -eq 0 ]]; then
    dotnet nuget remove source "$SOURCE_NAME" 2>/dev/null || true
else
    echo "+ dotnet nuget remove source $SOURCE_NAME || true"
fi

run dotnet nuget add source "$GITHUB_FEED" \
    --name "$SOURCE_NAME" \
    --username "$GITHUB_OWNER" \
    --password "$GITHUB_TOKEN" \
    --store-password-in-clear-text
echo ""

# Step 2: Install templates
echo "==> Installing N# templates"
if [[ "$DRY_RUN" -eq 0 ]]; then
    dotnet new uninstall NSharpLang.Templates 2>/dev/null || true
else
    echo "+ dotnet new uninstall NSharpLang.Templates || true"
fi
run dotnet new install NSharpLang.Templates --add-source "$GITHUB_FEED"
echo ""

# Step 3: Install global tools
echo "==> Installing nlc CLI tool"
if [[ "$DRY_RUN" -eq 0 ]]; then
    dotnet tool uninstall -g NSharpLang.Cli 2>/dev/null || true
else
    echo "+ dotnet tool uninstall -g NSharpLang.Cli || true"
fi
run dotnet tool install -g NSharpLang.Cli --add-source "$GITHUB_FEED"
echo ""

echo "==> Installing N# language server"
if [[ "$DRY_RUN" -eq 0 ]]; then
    dotnet tool uninstall -g NSharpLang.LanguageServer 2>/dev/null || true
else
    echo "+ dotnet tool uninstall -g NSharpLang.LanguageServer || true"
fi
run dotnet tool install -g NSharpLang.LanguageServer --add-source "$GITHUB_FEED"
echo ""

# Step 4: Write a reusable NuGet.config for N# projects
NSHARP_CONFIG_DIR="$HOME/.nsharp"
NSHARP_NUGET_CONFIG="$NSHARP_CONFIG_DIR/NuGet.config"

echo "==> Writing shared NuGet.config to $NSHARP_NUGET_CONFIG"
if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$NSHARP_CONFIG_DIR"
    cat > "$NSHARP_NUGET_CONFIG" <<NUGETCONFIG
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="nsharp-github" value="https://nuget.pkg.github.com/schneidenbach/index.json" />
  </packageSources>
  <packageSourceMapping>
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
    <packageSource key="nsharp-github">
      <package pattern="NSharpLang.*" />
    </packageSource>
  </packageSourceMapping>
  <packageSourceCredentials>
    <nsharp-github>
      <add key="Username" value="schneidenbach" />
      <add key="ClearTextPassword" value="${GITHUB_TOKEN}" />
    </nsharp-github>
  </packageSourceCredentials>
</configuration>
NUGETCONFIG
else
    echo "+ mkdir -p $NSHARP_CONFIG_DIR"
    echo "+ write NuGet.config to $NSHARP_NUGET_CONFIG"
fi
echo ""

echo "========================================"
echo "Setup complete!"
echo "========================================"
echo ""
echo "Commands:"
echo "  nlc                        - N# compiler CLI"
echo "  nsharp-lsp                 - N# language server"
echo "  nlc new MyApp              - Create a console project"
echo "  nlc new MyApi --template webapi"
echo ""
echo "Quick start:"
echo "  nlc new MyApp"
echo "  cd MyApp"
echo "  cp $NSHARP_NUGET_CONFIG ./NuGet.config"
echo "  nlc run"
