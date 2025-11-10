# N# (NewLang Sharp)

**Go for .NET - A pragmatic language for .NET developers sick of XML bullshit**

## Quick Start

### 1. One-Time Setup

```bash
git clone <repo-url>
cd NewCLILang
./scripts/setup-local.sh
```

### 2. Create Project

```bash
dotnet new nsharp-console -o MyApp
cd MyApp
```

**Files created:**
- `project.yml` - YOUR config (edit this)
- `Program.nl` - YOUR code
- `MyApp.csproj` - 4 lines (never touch)
- `global.json` - SDK config
- `NuGet.config` - Package sources (auto-configured)

### 3. Build and Run

```bash
dotnet build
dotnet run
```

**Output:** `Hello, N#!`

**That's it. No manual config editing. It just works.**

---

## Philosophy

- **Expressive types**: Discriminated unions and structural typing that C# lacks
- **Pragmatism**: Embraces .NET realities (including null)
- **Perfect C# interop**: C# consumers can't tell they're using N#-compiled code
- **Clean syntax**: Go-inspired conveniences (`:=`, no semicolons, convention-based visibility)
- **No XML**: YAML for config, minimal `.csproj` you never edit

## Why N#?

Unlike F# which has poor C# interop, N# is designed for perfect .NET ecosystem integration:

| Feature | N# | F# |
|---------|----|----|
| **Unions** | C# class hierarchies | Opaque to C# |
| **Records** | C# records | Weird constructors |
| **Async** | Task/ValueTask | Different type |
| **Nullability** | C# nullable types | F# Option |

## Quick Example

```n#
// Variables with type inference
name := "Alice"
items := [1, 2, 3, 4, 5]

// Discriminated unions with pattern matching
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

message := result match {
    Result.Success { value: x } => $"Got {x}",
    Result.Failure { error: e } => $"Error: {e}"
}

// Duck interfaces (structural typing)
duck interface IReader {
    func Read(): string
}

class FileReader {
    func Read(): string => "file contents"
}

func Process(r: IReader) {
    print r.Read()
}

Process(new FileReader())  // Works via structural typing!
```

## Installation

### From NuGet (Recommended)

```bash
# Install templates
dotnet new install NSharp.Templates

# Create a new console app
dotnet new nsharp-console -o MyApp
cd MyApp

# Build and run
dotnet build
dotnet run
```

The SDK (`Microsoft.NET.Sdk.NSharp`) is automatically downloaded when you build.

### Build from Source

```bash
git clone https://github.com/anthropics/NewCLILang.git
cd NewCLILang
dotnet build
dotnet test  # 568 tests passing
```

### CLI Usage

```bash
# Transpile to C# (stdout)
dotnet run --project src/Cli/Cli.csproj -- transpile Program.nl

# Build single file (auto-cleanup)
dotnet run --project src/Cli/Cli.csproj -- build Program.nl

# Build all .nl files in project (auto-cleanup)
dotnet run --project src/Cli/Cli.csproj -- build

# Build and run
dotnet run --project src/Cli/Cli.csproj -- run Program.nl

# Keep generated .cs files for debugging
dotnet run --project src/Cli/Cli.csproj -- build --keep-generated
```

**Note:** Generated `.cs` files are automatically cleaned up after build. Use `--keep-generated` for debugging.

## Key Features

### Modern Syntax
- Type inference with `:=`
- No semicolons required
- String interpolation
- Pattern matching with exhaustiveness checking
- Collection expressions (C# 12)
- List patterns (C# 11)

### Advanced Types
- Discriminated unions (transpile to C# class hierarchies)
- Duck interfaces (structural typing)
- Records with `with` expressions
- Primary constructors (C# 12)
- Required and init-only properties

### .NET Interop
- Seamless C# interop (generated code is idiomatic C#)
- Ref/out parameters
- Params arrays/collections
- Operator overloading
- Extension methods
- Async/await

## Examples

See `examples/` directory:
- **hello.nl** - Basic syntax
- **WeatherDemo/** - Multi-file project (10+ features)
- **unions_and_match.nl** - Discriminated unions
- **duck_interfaces.nl** - Structural typing
- **list_patterns.nl** - Pattern matching
- **error_handling.nl** - Exception handling

## Status

**Version:** v1.71
**Tests:** 568 passing (100%)
**Features:** All from DESIGN.md implemented + Assembly resolution + Override support

## CI/CD

N# projects work seamlessly with standard .NET CI/CD tools. Ready-to-use templates available:

### Quick Setup

**GitHub Actions:**
```bash
mkdir -p .github/workflows
cp ci/templates/github-actions/build.yml .github/workflows/
```

**Docker:**
```bash
cp ci/templates/docker/Dockerfile.webapi Dockerfile
docker build -t myapp . && docker run -p 8080:8080 myapp
```

**Templates include:**
- GitHub Actions (build, release, format-check, lint)
- Azure Pipelines (complete multi-stage pipeline)
- Docker (SDK, runtime, web API with multi-stage builds)
- Docker Compose (local development with dependencies)

**Complete examples:**
- `ci/examples/console-app/` - Console app with automated NuGet publishing
- `ci/examples/web-api/` - Web API with Docker deployment
- `ci/examples/library/` - Library publishing with pre-release support

See [CI/CD Guide](docs/guide/ci-cd.md) for full documentation.

## Documentation

- **docs/DESIGN.md** - Complete language specification
- **memory/** - Implementation notes and architecture
- **CLAUDE.md** - Instructions for AI agents
- **docs/** - User guides and references
- **docs/guide/ci-cd.md** - CI/CD setup and best practices

## Architecture

```
.nl source → Lexer → Parser → Analyzer → Transpiler → C# → IL
```

**Why transpile to C#?**
- Perfect interop with C# ecosystem
- Leverage existing .NET toolchain
- Simpler implementation
- Can inspect generated C# code

## C# Interop Example

N# code:
```n#
class Calculator {
    func Add(x: int, y: int): int => x + y
}
```

C# consumer:
```csharp
var calc = new Calculator();
var result = calc.Add(2, 3);  // Works perfectly!
```

## Who Should Use N#?

- .NET developers wanting simpler syntax
- Teams building libraries for C# consumption
- Developers who love Go's simplicity but need .NET
- Projects needing discriminated unions with C# interop

## License

MIT
