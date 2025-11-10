#!/bin/bash
set -e

echo "🚀 Setting up N# for local development..."
echo

# 1. Create local NuGet feed
echo "📦 Creating local NuGet feed at ~/.nuget/local-feed..."
mkdir -p ~/.nuget/local-feed

# Add the local feed to global NuGet config
echo "📝 Adding local feed to NuGet sources..."
dotnet nuget remove source nsharp-local 2>/dev/null || true
dotnet nuget add source ~/.nuget/local-feed --name nsharp-local

# 2. Build and pack SDK to local feed
echo "🔨 Building and packing SDK..."
# Build the build tasks first
dotnet build src/NSharpLang.Build.Tasks/NSharp.Build.Tasks.csproj -c Release -v q
# Pack the SDK
dotnet pack src/Microsoft.NET.Sdk.NSharp/Microsoft.NET.Sdk.NSharp.csproj -c Release -o ~/.nuget/local-feed -v q

# 3. Install template
echo "📝 Installing dotnet new template..."
dotnet new install templates/nsharp-console/ --force

echo
echo "✅ Setup complete!"
echo
echo "Now you can:"
echo "  dotnet new nsharp-console -o MyApp"
echo "  cd MyApp"
echo "  dotnet build"
echo "  dotnet run"
echo
echo "It just works! 🎉"
