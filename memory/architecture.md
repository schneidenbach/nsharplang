# N# Compiler Architecture

## Overview

N# is a transpiler-based language that compiles to C#, then leverages the .NET toolchain for final compilation.

```
.nl source file
    ↓
Lexer (Token stream)
    ↓
Parser (AST)
    ↓
Analyzer (Semantic analysis)
    ↓
Transpiler (C# code)
    ↓
C# Compiler (via dotnet)
    ↓
Executable
```

## Why Transpile to C#?

- **Leverage .NET ecosystem**: Use existing C# compiler, debugger, and tools
- **Simpler implementation**: No IL generation, no runtime needed
- **Easier debugging**: Generated C# can be inspected
- **Full .NET interop**: Works seamlessly with C# libraries

## Components

The compiler is composed of 6 main components:

1. **Lexer** - Tokenizes source code (`src/NSharpLang.Compiler/Lexer.cs`)
2. **Parser** - Builds AST from tokens (`src/NSharpLang.Compiler/Parser.cs`)
3. **Analyzer** - Type checking and semantic analysis (`src/NSharpLang.Compiler/Analyzer.cs`)
4. **Transpiler** - Generates C# code (`src/NSharpLang.Compiler/Transpiler.cs`)
5. **CLI** - Command-line interface (`src/NSharpLang.Cli/Program.cs`)
6. **Error Reporting** - Diagnostics and suggestions (`src/NSharpLang.Compiler/ErrorReporting.cs`)

See `memory/components/` folder for detailed documentation on each component.

## Data Flow

### 1. Tokenization
- **Input**: `.nl` source code (string)
- **Output**: `List<Token>`
- **Process**: Lexer scans characters, produces tokens with line/column info

### 2. Parsing
- **Input**: `List<Token>`
- **Output**: `CompilationUnit` (AST root)
- **Process**: Recursive descent parser builds immutable AST tree

### 3. Analysis
- **Input**: `CompilationUnit` (AST)
- **Output**: `AnalysisResult` (type info, errors, warnings)
- **Process**:
  - Scope management (global, class, function, block scopes)
  - Type inference and checking
  - Name resolution (including .NET types via reflection)
  - Definite assignment checking
  - Pattern exhaustiveness checking

### 4. Transpilation
- **Input**: `CompilationUnit` (AST) + `AnalysisResult`
- **Output**: C# source code (string)
- **Process**: AST visitor pattern, generates formatted C# code

### 5. Compilation
- **Input**: C# source code
- **Output**: Executable or DLL
- **Process**: Invoke `dotnet build` or `dotnet run`

## Project Structure

```text
src/
├── NSharpLang.Compiler/
│   ├── Lexer.cs               - Tokenization
│   ├── Token.cs               - Token types
│   ├── Parser.cs              - Parsing logic
│   ├── Analyzer.cs            - Semantic analysis
│   ├── Transpiler.cs          - C# code generation
│   ├── ErrorReporting.cs      - Error codes and formatting
│   ├── Ast/
│   │   ├── Expressions.cs     - Expression nodes
│   │   ├── Statements.cs      - Statement nodes
│   │   └── Declarations.cs    - Declaration nodes
│   └── TypeSystem/
│       └── TypeInfo.cs        - Type representation
├── NSharpLang.Cli/
│   └── Program.cs             - CLI commands (build, run, transpile)
├── NSharpLang.Build.Tasks/
│   └── NSharpCompile.cs       - MSBuild task wrapper
└── NSharpLang.Sdk/
    └── Sdk/                   - SDK props/targets

tests/
├── LexerTests.cs
├── ParserTests.cs
├── AnalyzerTests.cs
└── TranspilerTests.cs

examples/
└── *.nl files
```

## Key Design Decisions

### Immutable AST
All AST nodes are C# records (immutable by default). This makes the compiler:
- Easier to reason about (no hidden mutations)
- Safer for parallel processing
- Simpler to test

### Convention-Based Visibility
- `PascalCase` identifiers → public
- `camelCase` identifiers → private
- Explicit modifiers (`public`, `private`, etc.) override convention
- Enforced by Analyzer, transpiled with explicit modifiers in C#

### Transpilation Strategies

| N# Feature | C# Translation |
|------------|----------------|
| Union types | Abstract base class with nested record cases |
| Duck interfaces | Internal interface + automatic implementation |
| String enums | Static class with const string fields |
| Int enums | Standard C# enum |
| Top-level functions | Wrapped in internal static class |
| Type aliases | Emitted as comments (C# doesn't support at type level) |

### External Type Resolution
The Analyzer uses .NET reflection to:
- Resolve types from `using` statements (e.g., `System.Console`)
- Look up members on external types (methods, properties, fields)
- Handle method overloading (basic resolution by argument count)

This enables seamless interop with the entire .NET ecosystem.

## Build & Test Commands

```bash
# Build compiler
dotnet build src/NSharpLang.Compiler/Compiler.csproj

# Build CLI
dotnet build src/NSharpLang.Cli/Cli.csproj

# Run tests
dotnet test tests/Tests.csproj

# Transpile a file
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- transpile examples/04-pattern-matching/GuardsSimple.nl

# Build a file
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- build examples/04-pattern-matching/GuardsSimple.nl

# Run a file
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- run examples/04-pattern-matching/GuardsSimple.nl
```

## Performance Characteristics

- **Compilation speed**: Fast (single-pass parser, single-pass analyzer)
- **Memory usage**: Low (streaming lexer, no intermediate files)
- **Generated code quality**: Clean, readable C# with proper indentation
- **Runtime performance**: Same as hand-written C# (no overhead)
