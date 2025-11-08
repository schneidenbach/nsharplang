#!/bin/bash

# Build script for Task Management API
# Compiles N# files and builds the .NET project

set -e

echo "Building Task Management API..."
echo

# Find the N# compiler
COMPILER="../../../src/Cli/Cli.csproj"

if [ ! -f "$COMPILER" ]; then
    echo "Error: Compiler not found at $COMPILER"
    exit 1
fi

echo "Step 1: Compiling N# files to C#..."
dotnet run --project "$COMPILER" -- transpile Program.nl -o Program.g.cs
dotnet run --project "$COMPILER" -- transpile Database.nl -o Database.g.cs
dotnet run --project "$COMPILER" -- transpile Tasks.nl -o Tasks.g.cs

echo
echo "Step 2: Restoring NuGet packages..."
dotnet restore

echo
echo "Step 3: Building .NET project..."
dotnet build

echo
echo "Build complete!"
echo
echo "To run the API:"
echo "  dotnet run"
echo
echo "Then visit https://localhost:5001/swagger"
