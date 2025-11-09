#!/bin/bash
set -e

echo "🚀 Setting up N# for local development..."
echo

# 1. Create local NuGet feed
echo "📦 Creating local NuGet feed at ~/.nuget/local-feed..."
mkdir -p ~/.nuget/local-feed

# 2. Pack SDK to local feed
echo "🔨 Building and packing SDK..."
dotnet pack src/Build/Microsoft.NET.Sdk.NSharp/Microsoft.NET.Sdk.NSharp.csproj -o ~/.nuget/local-feed -v q

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
