#!/bin/bash
set -e

echo "================================"
echo "Publishing N# NuGet Packages"
echo "================================"

# Check if NUGET_API_KEY is set
if [ -z "$NUGET_API_KEY" ]; then
  echo "ERROR: NUGET_API_KEY environment variable is not set"
  echo "Please set it using: export NUGET_API_KEY=your_api_key"
  exit 1
fi

# Ensure packages exist
if [ ! -f "artifacts/nuget/Microsoft.NET.Sdk.NSharp.1.0.0.nupkg" ]; then
  echo "ERROR: SDK package not found. Run ./pack-nuget.sh first"
  exit 1
fi

if [ ! -f "artifacts/nuget/NSharp.Templates.1.0.0.nupkg" ]; then
  echo "ERROR: Templates package not found. Run ./pack-nuget.sh first"
  exit 1
fi

# Publish SDK
echo ""
echo "Publishing Microsoft.NET.Sdk.NSharp..."
dotnet nuget push artifacts/nuget/Microsoft.NET.Sdk.NSharp.1.0.0.nupkg \
  --api-key "$NUGET_API_KEY" \
  --source https://api.nuget.org/v3/index.json

# Publish Templates
echo ""
echo "Publishing NSharp.Templates..."
dotnet nuget push artifacts/nuget/NSharp.Templates.1.0.0.nupkg \
  --api-key "$NUGET_API_KEY" \
  --source https://api.nuget.org/v3/index.json

echo ""
echo "================================"
echo "Packages published successfully!"
echo "================================"
echo ""
echo "Users can now install with:"
echo "  dotnet new install NSharp.Templates"
echo ""
echo "And create projects with:"
echo "  dotnet new nsharp-console -o MyApp"
