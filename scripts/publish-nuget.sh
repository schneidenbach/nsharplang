#!/bin/bash
set -e

SDK_VERSION="0.1.0"
TEMPLATES_VERSION="1.0.0"
COMPILER_VERSION="1.0.0"
CLI_VERSION="0.1.0"
LANGUAGE_SERVER_VERSION="1.0.0"

PACKAGES=(
  "NSharpLang.Sdk.${SDK_VERSION}"
  "NSharpLang.Templates.${TEMPLATES_VERSION}"
  "NSharpLang.Compiler.${COMPILER_VERSION}"
  "NSharpLang.Cli.${CLI_VERSION}"
  "NSharpLang.LanguageServer.${LANGUAGE_SERVER_VERSION}"
)

echo "================================"
echo "Publishing N# NuGet Packages"
echo "================================"

if [ -z "$NUGET_API_KEY" ]; then
  echo "ERROR: NUGET_API_KEY environment variable is not set"
  echo "Please set it using: export NUGET_API_KEY=your_api_key"
  exit 1
fi

echo ""
echo "Checking packages..."
for pkg in "${PACKAGES[@]}"; do
  if [ ! -f "artifacts/nuget/${pkg}.nupkg" ]; then
    echo "ERROR: ${pkg}.nupkg not found. Run ./scripts/pack-nuget.sh first"
    exit 1
  fi
  echo "  - ${pkg}.nupkg"
done

echo ""
echo "Publishing packages to NuGet.org..."

echo ""
echo "Publishing NSharpLang.Sdk..."
dotnet nuget push "artifacts/nuget/NSharpLang.Sdk.${SDK_VERSION}.nupkg" \
  --api-key "$NUGET_API_KEY" \
  --source https://api.nuget.org/v3/index.json

echo ""
echo "Publishing NSharpLang.Templates..."
dotnet nuget push "artifacts/nuget/NSharpLang.Templates.${TEMPLATES_VERSION}.nupkg" \
  --api-key "$NUGET_API_KEY" \
  --source https://api.nuget.org/v3/index.json

echo ""
echo "Publishing NSharpLang.Compiler..."
dotnet nuget push "artifacts/nuget/NSharpLang.Compiler.${COMPILER_VERSION}.nupkg" \
  --api-key "$NUGET_API_KEY" \
  --source https://api.nuget.org/v3/index.json

echo ""
echo "Publishing NSharpLang.Cli..."
dotnet nuget push "artifacts/nuget/NSharpLang.Cli.${CLI_VERSION}.nupkg" \
  --api-key "$NUGET_API_KEY" \
  --source https://api.nuget.org/v3/index.json

echo ""
echo "Publishing NSharpLang.LanguageServer..."
dotnet nuget push "artifacts/nuget/NSharpLang.LanguageServer.${LANGUAGE_SERVER_VERSION}.nupkg" \
  --api-key "$NUGET_API_KEY" \
  --source https://api.nuget.org/v3/index.json

echo ""
echo "================================"
echo "Packages published successfully!"
echo "================================"
echo ""
echo "Users can now install with:"
echo "  dotnet new install NSharpLang.Templates"
echo "  dotnet tool install -g NSharpLang.Cli"
echo "  dotnet tool install -g NSharpLang.LanguageServer"
