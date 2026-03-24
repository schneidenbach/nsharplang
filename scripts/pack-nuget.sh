#!/bin/bash
set -e

echo "================================"
echo "Packing N# NuGet Packages"
echo "================================"

# Create artifacts directory
mkdir -p artifacts/nuget

# Build the build tasks in Release mode
echo ""
echo "Building NSharpLang.Build.Tasks in Release mode..."
dotnet build src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj -c Release

# Pack the SDK
echo ""
echo "Packing NSharpLang.Sdk..."
dotnet pack src/NSharpLang.Sdk/NSharpLang.Sdk.csproj \
  -c Release \
  -o artifacts/nuget

# Pack the templates
echo ""
echo "Packing NSharpLang.Templates..."
dotnet pack templates/NSharpLang.Templates.csproj \
  -c Release \
  -o artifacts/nuget

# Pack the compiler library
echo ""
echo "Packing NSharpLang.Compiler..."
dotnet pack src/NSharpLang.Compiler/Compiler.csproj \
  -c Release \
  -o artifacts/nuget

# Pack the CLI tool
echo ""
echo "Packing nlc (N# CLI tool)..."
dotnet pack src/NSharpLang.Cli/Cli.csproj \
  -c Release \
  -o artifacts/nuget

# Pack the Language Server
echo ""
echo "Packing NSharpLang.LanguageServer..."
dotnet pack src/NSharpLang.LanguageServer/LanguageServer.csproj \
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
echo "  - NSharpLang.Sdk - MSBuild SDK"
echo "  - NSharpLang.Templates - dotnet new templates"
echo "  - NSharpLang.Compiler - Compiler API library"
echo "  - NSharpLang.Cli - CLI tool (command: nlc)"
echo "  - NSharpLang.LanguageServer - LSP server"
