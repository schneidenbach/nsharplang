#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/artifacts/smoke-turnkey}"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$LOG_DIR/$STAMP"
FEED="$PROJECT_ROOT/artifacts/nuget"
APP_DIR="$RUN_DIR/work/MyApp"

mkdir -p "$RUN_DIR"
LOG_FILE="$RUN_DIR/smoke.log"

exec > >(tee "$LOG_FILE") 2>&1

echo "N# turnkey installer smoke"
echo "repo: $PROJECT_ROOT"
echo "run:  $RUN_DIR"
echo "log:  $LOG_FILE"
echo ""

cd "$PROJECT_ROOT"
SKIP_VSCODE_PACKAGE=1 ./scripts/pack-nuget.sh

TMP_HOME="$RUN_DIR/home"
mkdir -p "$TMP_HOME"
export HOME="$TMP_HOME"
export PATH="$HOME/.dotnet/tools:$PATH"
export DOTNET_CLI_HOME="$HOME"
export DOTNET_ROOT="${DOTNET_ROOT:-$(python3 - <<'PY'
import os, shutil
real=os.path.realpath(shutil.which('dotnet'))
bin_dir=os.path.dirname(real)
for candidate in (os.path.join(os.path.dirname(bin_dir), 'libexec'), os.path.dirname(bin_dir), bin_dir):
    if os.path.isdir(candidate):
        print(candidate)
        break
PY
)}"
export NUGET_PACKAGES="$RUN_DIR/nuget-packages"

mkdir -p "$HOME/.nuget/NuGet"
cat > "$HOME/.nuget/NuGet/NuGet.Config" <<NUGETCONFIG
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nsharp-local" value="$FEED" />
  </packageSources>
</configuration>
NUGETCONFIG

echo "==> Verifying unsupported public version pin is rejected"
set +e
PIN_OUTPUT=$(./scripts/install.sh --source "$FEED" --version 0.1.0 --skip-vscode --dry-run 2>&1)
PIN_STATUS=$?
set -e
printf '%s\n' "$PIN_OUTPUT"
if [[ "$PIN_STATUS" -ne 2 ]] || ! printf '%s\n' "$PIN_OUTPUT" | grep -q 'does not support --version'; then
  echo "ERROR: installer accepted --version or did not explain why public version pinning is disabled." >&2
  exit 1
fi

set +e
PIN_EQUALS_OUTPUT=$(./scripts/install.sh --source "$FEED" --version=0.1.0 --skip-vscode --dry-run 2>&1)
PIN_EQUALS_STATUS=$?
set -e
printf '%s\n' "$PIN_EQUALS_OUTPUT"
if [[ "$PIN_EQUALS_STATUS" -ne 2 ]] || ! printf '%s\n' "$PIN_EQUALS_OUTPUT" | grep -q 'does not support --version'; then
  echo "ERROR: installer accepted --version=VALUE or did not explain why public version pinning is disabled." >&2
  exit 1
fi

echo "==> Running installer against local package feed"
./scripts/install.sh --source "$FEED" --skip-vscode

echo "==> Verifying CLI"
nlc --version
nlc doctor --skip-vscode

echo "==> Creating fresh N# console project"
mkdir -p "$RUN_DIR/work"
cd "$RUN_DIR/work"
nlc new MyApp
cd "$APP_DIR"

# nlc-generated projects include NuGet.config; point NSharp packages at the isolated local feed.
python3 - <<PY
from pathlib import Path
p=Path('NuGet.config')
s=p.read_text()
s=s.replace('%HOME%/.nuget/local-feed', '$FEED')
s=s.replace('$HOME/.nuget/local-feed', '$FEED')
p.write_text(s)
PY

nlc build
nlc run

echo "==> VS Code extension check"
if command -v code >/dev/null 2>&1; then
  if compgen -G "$PROJECT_ROOT/editors/vscode/nsharp-*.vsix" >/dev/null; then
    code --install-extension "$PROJECT_ROOT"/editors/vscode/nsharp-*.vsix --force
  else
    echo "No local VSIX found; run ./scripts/build-vscode-extension.sh before requiring local VS Code extension smoke."
  fi
  code --list-extensions | grep -i '^nsharp\.nsharp$' || echo "N# VS Code extension is not installed in this smoke environment."
else
  echo "VS Code 'code' CLI not present in smoke environment; installer path was exercised with --skip-vscode."
fi

echo ""
echo "Smoke complete: $LOG_FILE"
