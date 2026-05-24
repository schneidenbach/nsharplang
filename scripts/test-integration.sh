#!/bin/bash
set -e

echo "========================================="
echo "N# Integration Tests (Docker required)"
echo "========================================="
echo

# Change to repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
cd "$NSHARP_REPO_ROOT"

if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker is not running. Integration tests require Docker."
    echo "Please start Docker Desktop and try again."
    exit 1
fi

dotnet test tests/NSharpLang.IntegrationTests/IntegrationTests.csproj -v n --nologo
