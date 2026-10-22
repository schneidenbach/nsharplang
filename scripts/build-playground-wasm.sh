#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$REPO_ROOT/src/NSharpLang.Playground.Wasm/NSharpLang.Playground.Wasm.csproj"
CLI_PROJECT="$REPO_ROOT/src/NSharpLang.Cli/Cli.csproj"
CLI_DLL="$REPO_ROOT/src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll"
PLAYGROUND_PROJECT="$REPO_ROOT/src/NSharpLang.Playground"
ARTIFACT_ROOT="$REPO_ROOT/artifacts/playground-wasm"
PUBLISH_DIR="$ARTIFACT_ROOT/publish"
STATIC_DIR="$REPO_ROOT/website/static/playground/wasm"

if dotnet workload list | grep -Eq '^wasm-tools[[:space:]]'; then
    echo "WebAssembly workload is already installed."
else
    echo "Restoring .NET WebAssembly workload for the playground..."
    dotnet workload restore "$PROJECT"
fi

echo "Publishing N# playground WASM host..."
dotnet build "$CLI_PROJECT" -c Debug -v q
dotnet "$CLI_DLL" build --project "$PLAYGROUND_PROJECT" --release --emit-reference-assembly
ASYNC_PATTERN_FIXTURE="$REPO_ROOT/tests/fixtures/async-awaitable-patterns"
dotnet "$CLI_DLL" build --project "$ASYNC_PATTERN_FIXTURE" --release --emit-reference-assembly
ASYNC_PATTERN_FIXTURE_DLL="$ASYNC_PATTERN_FIXTURE/bin/Release/net10.0/NSharpLang.AsyncAwaitablePatternFixtures.dll"
ASYNC_PATTERN_RUNTIME_DLL="$ASYNC_PATTERN_FIXTURE/bin/Release/net10.0/NSharpLang.Runtime.dll"
SDK_BASE="$(dotnet --info | sed -n 's/^ Base Path:[[:space:]]*//p' | head -n 1)"
DOTNET_ROOT="${SDK_BASE%/sdk/*}"
RUNTIME_CORELIB="$(find "$DOTNET_ROOT/shared/Microsoft.NETCore.App" -name System.Private.CoreLib.dll -type f | sort -V | tail -n 1)"
if [ ! -f "$ASYNC_PATTERN_FIXTURE_DLL" ] || [ ! -f "$ASYNC_PATTERN_RUNTIME_DLL" ] || [ ! -f "$RUNTIME_CORELIB" ]; then
    echo "error: async awaitable pattern fixture assembly was not produced." >&2
    exit 1
fi
mkdir -p "$ARTIFACT_ROOT"
ASYNC_PATTERN_FIXTURE_ARCHIVE="$ARTIFACT_ROOT/async-awaitable-pattern-fixture.zip"
rm -f "$ASYNC_PATTERN_FIXTURE_ARCHIVE"
zip -q -9 -j -X "$ASYNC_PATTERN_FIXTURE_ARCHIVE" "$ASYNC_PATTERN_FIXTURE_DLL" "$ASYNC_PATTERN_RUNTIME_DLL" "$RUNTIME_CORELIB"
cp "$PLAYGROUND_PROJECT/bin/Release/net10.0/NSharpLang.Playground.dll" "$PLAYGROUND_PROJECT/obj/Release/net10.0/NSharpLang.Playground.dll"
for reference_directory in "$REPO_ROOT"/src/*/bin/Release/net10.0/nsharpref; do
    if [ ! -d "$reference_directory" ]; then
        continue
    fi
    project_directory="${reference_directory%/bin/Release/net10.0/nsharpref}"
    target_reference_directory="$project_directory/obj/Release/net10.0/ref"
    mkdir -p "$target_reference_directory"
    cp "$reference_directory"/*.dll "$target_reference_directory/"
done
dotnet publish "$PROJECT" -c Release -o "$PUBLISH_DIR" -p:BuildProjectReferences=false -v q

DOTNET_JS_PATH="$(find "$PUBLISH_DIR" "$REPO_ROOT/src/NSharpLang.Playground.Wasm/bin/Release/net10.0" -path '*/_framework/dotnet.js' -type f 2>/dev/null | head -n 1 || true)"
if [ -z "$DOTNET_JS_PATH" ]; then
    echo "error: dotnet publish did not produce _framework/dotnet.js for the playground WASM host." >&2
    exit 1
fi

BUNDLE_ROOT="$(cd "$(dirname "$DOTNET_JS_PATH")/.." && pwd)"

SDK_BASE="$(dotnet --info | sed -n 's/^ Base Path:[[:space:]]*//p' | head -n 1)"
DOTNET_ROOT="${SDK_BASE%/sdk/*}"
REFERENCE_PACK_ROOT="$DOTNET_ROOT/packs/Microsoft.NETCore.App.Ref"
REFERENCE_PACK="$(find "$REFERENCE_PACK_ROOT" -path '*/ref/net10.0' -type d | sort -V | tail -n 1)"
if [ -z "$REFERENCE_PACK" ]; then
    echo "error: no .NET 10 reference pack was found below $REFERENCE_PACK_ROOT." >&2
    exit 1
fi

rm -rf "$STATIC_DIR"
mkdir -p "$(dirname "$STATIC_DIR")"
cp -R "$BUNDLE_ROOT" "$STATIC_DIR"
# The ownership snapshot covers this generated archive. Omit host-specific extended attributes
# (including access times and UID/GID) so identical reference assemblies produce identical bytes.
zip -q -9 -j -X "$STATIC_DIR/references.zip" "$REFERENCE_PACK"/*.dll

echo "Playground WASM assets copied to website/static/playground/wasm"
