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
dotnet build src/NSharpLang.Build.Tasks/NSharp.Build.Tasks.csproj -c Release

# Pack the SDK
echo ""
echo "Packing Microsoft.NET.Sdk.NSharp..."
dotnet pack src/Microsoft.NET.Sdk.NSharp/Microsoft.NET.Sdk.NSharp.csproj \
  -c Release \
  -o artifacts/nuget

# Pack the templates
echo ""
echo "Packing NSharp.Templates..."
dotnet pack templates/NSharp.Templates.csproj \
  -c Release \
  -o artifacts/nuget

# Pack the compiler library
echo ""
echo "Packing NSharp.Compiler..."
dotnet pack src/Compiler/Compiler.csproj \
  -c Release \
  -o artifacts/nuget

# Pack the CLI tool
echo ""
echo "Packing nlc (N# CLI tool)..."
dotnet pack src/Cli/Cli.csproj \
  -c Release \
  -o artifacts/nuget

# Pack the Language Server
echo ""
echo "Packing NSharp.LanguageServer..."
dotnet pack src/LanguageServer/LanguageServer.csproj \
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
echo ""
echo "Core packages:"
echo "  - Microsoft.NET.Sdk.NSharp - MSBuild SDK"
echo "  - NSharp.Templates - dotnet new templates"
echo "  - NSharp.Compiler - Compiler API library"
echo "  - nlc - CLI tool (dotnet tool install -g nlc)"
echo "  - NSharp.LanguageServer - LSP server"
