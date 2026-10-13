#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLI_DLL="${1:-$REPO_ROOT/src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll}"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/async-iterator-cancellation"
FIXTURE_DLL="$FIXTURE_DIR/bin/Debug/net10.0/NSharpLang.AsyncIteratorCancellationFixture.dll"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nsharp-async-iterator-cancellation.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

export NLC_NO_DAEMON=1
dotnet "$CLI_DLL" build --project "$FIXTURE_DIR"

INVALID_DIR="$TEMP_DIR/multiple-tokens"
mkdir -p "$INVALID_DIR"
cat > "$INVALID_DIR/project.yml" <<'EOF'
name: NSharpLang.AsyncIteratorCancellationInvalid
version: 1.0.0
backend: il
outputType: library
targetFramework: net10.0
EOF
cat > "$INVALID_DIR/Invalid.nl" <<'EOF'
import System.Collections.Generic
import System.Threading
import System.Threading.Tasks

async func* Invalid(first: CancellationToken, second: CancellationToken): IAsyncEnumerable<int> {
    await Task.Delay(1)
    yield 1
}
EOF
if dotnet "$CLI_DLL" check --text --project "$INVALID_DIR" > "$TEMP_DIR/multiple-tokens.txt" 2>&1; then
  echo "The multiple-token async iterator unexpectedly passed nlc check." >&2
  exit 1
fi
if ! grep -q "NL353" "$TEMP_DIR/multiple-tokens.txt" \
    || ! grep -q "EnumeratorCancellation" "$TEMP_DIR/multiple-tokens.txt"; then
  cat "$TEMP_DIR/multiple-tokens.txt" >&2
  echo "The multiple-token error did not direct users to EnumeratorCancellation." >&2
  exit 1
fi

cat > "$TEMP_DIR/InteropConsumer.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
EOF

cat > "$TEMP_DIR/Program.cs" <<'EOF'
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;

if (args.Length != 1)
    throw new InvalidOperationException("Expected the built N# fixture assembly path.");

var fixture = Assembly.LoadFrom(args[0]);
var iterator = fixture.GetTypes()
    .SelectMany(type => type.GetMethods(BindingFlags.Public | BindingFlags.Static))
    .Single(method => method.Name == "Wait");

if (iterator.ReturnType != typeof(IAsyncEnumerable<int>))
    throw new InvalidOperationException($"Expected IAsyncEnumerable<int>, got {iterator.ReturnType}.");

var parameter = iterator.GetParameters().Single();
if (parameter.GetCustomAttributes<EnumeratorCancellationAttribute>().Count() != 1)
    throw new InvalidOperationException("The N# iterator parameter is missing EnumeratorCancellationAttribute metadata.");

var sequence = (IAsyncEnumerable<int>)iterator.Invoke(null, new object[] { CancellationToken.None })!;
using var consumer = new CancellationTokenSource(TimeSpan.FromMilliseconds(200));
var observedValues = 0;
try
{
    await foreach (var value in sequence.WithCancellation(consumer.Token))
        observedValues++;

    throw new InvalidOperationException("The consumer token did not cancel the N# async iterator.");
}
catch (OperationCanceledException)
{
}

if (observedValues != 0)
    throw new InvalidOperationException("The canceled iterator yielded before stopping.");

Console.WriteLine("C# consumer observed the N# EnumeratorCancellation contract.");
EOF

dotnet run --project "$TEMP_DIR/InteropConsumer.csproj" -- "$FIXTURE_DLL"
