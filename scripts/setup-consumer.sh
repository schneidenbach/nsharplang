#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat <<'EOF'
setup-consumer.sh has been replaced by the package-manager toolset installer.

Use one of:
  brew install nsharp
  ./scripts/install.sh --source <nsharp-toolset.tar.gz>
  ./scripts/setup-local.sh
EOF

exec "$SCRIPT_DIR/install.sh" "$@"
