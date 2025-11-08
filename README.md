# NewCLILang

A tight, pragmatic language targeting .NET/CLI. Think "Go for .NET" - minimal constructs, practical design, excellent C# interop.

## Features

- **Go-level simplicity** with C-esque syntax
- **Functional-first** paradigm
- **First-class .NET interop** - transpiles to clean C#
- **Convention-based visibility** (PascalCase = public, camelCase = private)
- **Discriminated unions** built into the language
- **No semicolons** required (Go-style)
- **Null-aware by design** with explicit nullable types

## Quick Start

```bash
# Build the compiler
dotnet build src/Compiler/Compiler.csproj
dotnet build src/Cli/Cli.csproj

# Run the example
dotnet run --project src/Cli/Cli.csproj run examples/hello.nl
```

## Example Code

```
using System
using System.Linq

class Program {
    static func Main() {
        name := "World"
        greeting := $"Hello, {name}!"
        Console.WriteLine(greeting)

        numbers := [1, 2, 3, 4, 5]
        doubled := numbers.Select(x => x * 2).ToList()

        Console.WriteLine("Doubled numbers:")
        foreach num in doubled {
            Console.WriteLine(num)
        }
    }
}
```

This transpiles to clean, readable C#:

```csharp
using System;
using System.Linq;

class Program
{
    static void Main()
    {
        var name = "World";
        var greeting = $"Hello, {name}!";
        Console.WriteLine(greeting);
        var numbers = new[] { 1, 2, 3, 4, 5 };
        var doubled = numbers.Select(x => (x * 2)).ToList();
        Console.WriteLine("Doubled numbers:");
        foreach (var num in doubled)
        {
            Console.WriteLine(num);
        }
    }
}
```

## CLI Usage

```bash
# Transpile to C# (prints to stdout)
dotnet run --project src/Cli/Cli.csproj transpile <file.nl>

# Build (generates .g.cs file)
dotnet run --project src/Cli/Cli.csproj build <file.nl>

# Compile and run
dotnet run --project src/Cli/Cli.csproj run <file.nl>
```

## Language Features

### Variables & Types

```
// Type inference
name := "John"
age := 30

// Explicit types
let count: int = 0
const MaxSize: int = 100
```

### Functions

```
func Add(x: int, y: int): int {
    return x + y
}

// Lambdas
double := x => x * 2
sum := (x, y) => x + y
```

### Classes & Records

```
class Person {
    Name: string        // public (PascalCase)
    age: int            // private (camelCase)

    constructor(name: string) {
        Name = name
    }

    func GetAge(): int {
        return age
    }
}

record Point {
    X: int
    Y: int
}

p2 := p1 with { X: 10 }
```

### Discriminated Unions

```
union Result {
    Success { value: int }
    Failure { error: string, code: int }
}

result := match someResult {
    Success { value } => value * 2
    Failure { error, code } => 0
}
```

### Pattern Matching

```
result := match value {
    1 => "one"
    2 => "two"
    _ => "other"
}
```

### Null Safety

```
name: string? = null
value := name ?? "default"
length := name?.Length
```

## Project Structure

```
NewCLILang/
├── src/
│   ├── Compiler/          # Lexer, Parser, Transpiler, AST
│   └── Cli/               # Command-line tool
├── tests/                 # Unit tests (47 passing)
├── examples/              # Sample .nl files
├── memory/                # Implementation notes
├── DESIGN.md             # Language specification
└── tasks.md              # Development roadmap
```

## Development Status

**Current:** MVP complete! Lexer, Parser, and Transpiler working end-to-end.

**Working:**
- ✅ Full lexical analysis
- ✅ Complete AST parsing
- ✅ C# code generation
- ✅ CLI tool (build/transpile/run)
- ✅ 47 unit tests passing

**Not Yet Implemented:**
- ⏳ Semantic analysis (Analyzer)
- ⏳ Type checking
- ⏳ Multi-file compilation
- ⏳ project.yml support
- ⏳ Better error messages

See `tasks.md` for detailed roadmap.

## Design Philosophy

1. **Simplicity over features** - Go-level minimalism
2. **Pragmatism over purity** - Embraces .NET realities (including null)
3. **Interop first** - Clean C# emission for excellent library compatibility
4. **Explicit when it matters** - Convention-based defaults, explicit modifiers when needed

## Running Tests

```bash
dotnet test tests/Tests.csproj
```

All 47 tests currently passing:
- 27 Lexer tests
- 20 Parser tests

## Contributing

This is a demonstration project showing how to build a language for the CLR. The core pipeline (Lexer → Parser → Transpiler → C#) is complete and functional.

Areas for contribution:
- Semantic analyzer implementation
- More comprehensive tests
- Better error messages
- Multi-file compilation
- IDE integration (LSP)

## License

MIT
