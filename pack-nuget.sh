#!/bin/bash
set -e

echo "================================"
echo "Packing N# NuGet Packages"
echo "================================"

# Create artifacts directory
mkdir -p artifacts/nuget

# Build the build tasks in Release mode
echo ""
echo "Building NSharp.Build.Tasks in Release mode..."
dotnet build src/Build/NSharp.Build.Tasks/NSharp.Build.Tasks.csproj -c Release

# Pack the SDK
echo ""
echo "Packing Microsoft.NET.Sdk.NSharp..."
dotnet pack sdk/Microsoft.NET.Sdk.NSharp/Sdk/Microsoft.NET.Sdk.NSharp/Microsoft.NET.Sdk.NSharp.csproj \
  -c Release \
  -o artifacts/nuget

# Pack the templates
echo ""
echo "Packing NSharp.Templates..."
dotnet pack templates/NSharp.Templates.csproj \
  -c Release \
  -o artifacts/nuget

# List the created packages
echo ""
echo "================================"
echo "Packages created successfully:"
echo "================================"
ls -lh artifacts/nuget/*.nupkg

echo ""
echo "Packages are ready in artifacts/nuget/"
