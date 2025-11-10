#!/bin/bash
set -e

VERSION="1.0.0"

echo "================================"
echo "Publishing N# NuGet Packages"
echo "================================"

# Check if NUGET_API_KEY is set
if [ -z "$NUGET_API_KEY" ]; then
  echo "ERROR: NUGET_API_KEY environment variable is not set"
  echo "Please set it using: export NUGET_API_KEY=your_api_key"
  exit 1
fi

# Check if packages exist
PACKAGES=(
  "NSharpLang.Sdk.0.1.0"
  "NSharp.Templates.${VERSION}"
  "NSharp.Compiler.${VERSION}"
  "nlc.0.1.0"
  "NSharp.LanguageServer.${VERSION}"
)

echo ""
echo "Checking packages..."
for pkg in "${PACKAGES[@]}"; do
  if [ ! -f "artifacts/nuget/${pkg}.nupkg" ]; then
    echo "ERROR: ${pkg}.nupkg not found. Run ./pack-nuget.sh first"
    exit 1
  fi
  echo "  ✓ ${pkg}.nupkg"
done

# Publish packages
echo ""
echo "Publishing packages to NuGet.org..."

echo ""
echo "Publishing NSharpLang.Sdk..."
dotnet nuget push artifacts/nuget/NSharpLang.Sdk.0.1.0.nupkg \
  --api-key "$NUGET_API_KEY" \
  --source https://api.nuget.org/v3/index.json

echo ""
echo "Publishing NSharp.Templates..."
dotnet nuget push artifacts/nuget/NSharp.Templates.${VERSION}.nupkg \
  --api-key "$NUGET_API_KEY" \
  --source https://api.nuget.org/v3/index.json

echo ""
echo "Publishing NSharp.Compiler..."
dotnet nuget push artifacts/nuget/NSharp.Compiler.${VERSION}.nupkg \
  --api-key "$NUGET_API_KEY" \
  --source https://api.nuget.org/v3/index.json

echo ""
echo "Publishing nlc (CLI tool)..."
dotnet nuget push artifacts/nuget/nlc.0.1.0.nupkg \
  --api-key "$NUGET_API_KEY" \
  --source https://api.nuget.org/v3/index.json

echo ""
echo "Publishing NSharp.LanguageServer..."
dotnet nuget push artifacts/nuget/NSharp.LanguageServer.${VERSION}.nupkg \
  --api-key "$NUGET_API_KEY" \
  --source https://api.nuget.org/v3/index.json

echo ""
echo "================================"
echo "Packages published successfully!"
echo "================================"
echo ""
echo "Users can now install with:"
echo ""
echo "  # Install templates"
echo "  dotnet new install NSharp.Templates"
echo ""
echo "  # Install CLI tool"
echo "  dotnet tool install -g nlc"
echo ""
echo "  # Install Language Server"
echo "  dotnet tool install -g NSharp.LanguageServer"
echo ""
echo "And create projects with:"
echo "  dotnet new nsharp-console -o MyApp"
echo "  cd MyApp"
echo "  dotnet build"
