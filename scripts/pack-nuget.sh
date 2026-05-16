#!/bin/bash
set -euo pipefail

echo "================================"
echo "Packing N# Release Artifacts"
echo "================================"

# Create artifacts directories
mkdir -p artifacts/nuget artifacts/vscode

echo ""
echo "Building NSharpLang.Build.Tasks in Release mode..."
dotnet build src/NSharpLang.Build.Tasks/NSharpLang.Build.Tasks.csproj -c Release

pack_project() {
  local label="$1"
  local project="$2"
  echo ""
  echo "Packing $label..."
  dotnet pack "$project" -c Release -o artifacts/nuget
}

pack_project "NSharpLang.Sdk" src/NSharpLang.Sdk/NSharpLang.Sdk.csproj
pack_project "NSharpLang.Templates" templates/NSharpLang.Templates.csproj
pack_project "NSharpLang.Compiler" src/NSharpLang.Compiler/Compiler.csproj
pack_project "nlc (N# CLI tool)" src/NSharpLang.Cli/Cli.csproj
pack_project "NSharpLang.LanguageServer" src/NSharpLang.LanguageServer/LanguageServer.csproj

if [[ "${SKIP_VSCODE_PACKAGE:-0}" != "1" ]]; then
  echo ""
  echo "Packaging VS Code extension..."
  ./scripts/build-vscode-extension.sh
  cp -f editors/vscode/*.vsix artifacts/vscode/ 2>/dev/null || true
else
  echo ""
  echo "Skipping VS Code extension package (SKIP_VSCODE_PACKAGE=1)."
fi

echo ""
echo "================================"
echo "Artifacts created successfully:"
echo "================================"
ls -lh artifacts/nuget/*.nupkg
if compgen -G "artifacts/vscode/*.vsix" >/dev/null; then
  ls -lh artifacts/vscode/*.vsix
fi

echo ""
echo "Release artifact set:"
echo "  - NSharpLang.Sdk - MSBuild SDK restored by projects"
echo "  - NSharpLang.Templates - dotnet new templates"
echo "  - NSharpLang.Compiler - Compiler API library"
echo "  - NSharpLang.Cli - global tool that provides nlc"
echo "  - NSharpLang.LanguageServer - global tool that provides nsharp-lsp"
echo "  - nsharp VSIX - VS Code extension installed by scripts/install.sh when published"
