# N# (NewLang Sharp)

**C# with discriminated unions, structural typing, and Go-inspired syntax**

A pragmatic language targeting .NET/CLI with perfect C# interoperability.

## Philosophy

- **Expressive types**: Discriminated unions and structural typing that C# lacks
- **Pragmatism**: Embraces .NET realities (including null)
- **Perfect C# interop**: C# consumers can't tell they're using N#-compiled code
- **Clean syntax**: Go-inspired conveniences (`:=`, no semicolons, convention-based visibility)

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

## Documentation

- **DESIGN.md** - Complete language specification
- **memory/** - Implementation notes and architecture
- **CLAUDE.md** - Instructions for AI agents
- **STATUS.md** - Current status and features

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
