#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_DLL="$REPO_ROOT/src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll"
ARTIFACT_ROOT="$REPO_ROOT/artifacts/playground-wasm"

if [ ! -f "$CLI_DLL" ]; then
    echo "error: build the playground WASM host before preparing its async fixtures." >&2
    exit 1
fi

ASYNC_PATTERN_FIXTURE="$REPO_ROOT/tests/fixtures/async-awaitable-patterns"
dotnet "$CLI_DLL" build --project "$ASYNC_PATTERN_FIXTURE" --release --emit-reference-assembly
ASYNC_PATTERN_FIXTURE_DLL="$ASYNC_PATTERN_FIXTURE/bin/Release/net10.0/NSharpLang.AsyncAwaitablePatternFixtures.dll"
ASYNC_PATTERN_RUNTIME_DLL="$ASYNC_PATTERN_FIXTURE/bin/Release/net10.0/NSharpLang.Runtime.dll"

ASYNC_CONSTRUCTOR_FIXTURE="$REPO_ROOT/tests/fixtures/async-constructor-reflection"
dotnet build "$ASYNC_CONSTRUCTOR_FIXTURE/AsyncConstructorReflectionFixtures.csproj" -c Release -v q -p:TargetFramework=net10.0 -p:TargetFrameworks=net10.0 -p:Nullable=enable
ASYNC_CONSTRUCTOR_FIXTURE_DLL="$ASYNC_CONSTRUCTOR_FIXTURE/bin/Release/net10.0/AsyncConstructorReflectionFixtures.dll"

SDK_BASE="$(dotnet --info | sed -n 's/^ Base Path:[[:space:]]*//p' | head -n 1)"
DOTNET_ROOT="${SDK_BASE%/sdk/*}"
RUNTIME_CORELIB="$(find "$DOTNET_ROOT/shared/Microsoft.NETCore.App" -name System.Private.CoreLib.dll -type f | sort -V | tail -n 1)"
RUNTIME_SYSTEM_RUNTIME="$(find "$DOTNET_ROOT/shared/Microsoft.NETCore.App" -name System.Runtime.dll -type f | sort -V | tail -n 1)"
if [ ! -f "$ASYNC_PATTERN_FIXTURE_DLL" ] || [ ! -f "$ASYNC_PATTERN_RUNTIME_DLL" ] || [ ! -f "$ASYNC_CONSTRUCTOR_FIXTURE_DLL" ] || [ ! -f "$RUNTIME_CORELIB" ] || [ ! -f "$RUNTIME_SYSTEM_RUNTIME" ]; then
    echo "error: async playground fixture or runtime assembly was not produced." >&2
    exit 1
fi

mkdir -p "$ARTIFACT_ROOT"
ASYNC_PATTERN_FIXTURE_ARCHIVE="$ARTIFACT_ROOT/async-awaitable-pattern-fixture.zip"
rm -f "$ASYNC_PATTERN_FIXTURE_ARCHIVE"
zip -q -9 -j -X "$ASYNC_PATTERN_FIXTURE_ARCHIVE" "$ASYNC_PATTERN_FIXTURE_DLL" "$ASYNC_CONSTRUCTOR_FIXTURE_DLL" "$ASYNC_PATTERN_RUNTIME_DLL" "$RUNTIME_CORELIB" "$RUNTIME_SYSTEM_RUNTIME"

echo "Async playground fixtures prepared at $ASYNC_PATTERN_FIXTURE_ARCHIVE"
