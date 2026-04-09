# N# Compiler Architecture

## Overview

N# has one supported executable backend:
- `il` — parse/analyze, emit IL directly to a managed assembly

The product toolchain now runs through IL end to end. Projects use `backend: il` (or omit the field and take the default), and the CLI plus MSBuild SDK honor that path consistently for build, run, test, benchmark, and publish flows. Generated-C# export is retired from the supported CLI and SDK surface.

```
.nl source file
    ↓
Lexer (Token stream)
    ↓
Parser (AST)
    ↓
Analyzer (Semantic analysis)
    ↓
    ├── Transpiler (internal compatibility/testing component)
    └── IL Compiler (managed PE emit) → Managed assembly / executable
```

## Why Emit IL Directly?

- **Backend independence**: Removes C# codegen as a hard product dependency
- **Production backend**: The CLI and SDK execute projects without routing through generated C#
- **Real-backend validation**: `nlc check` validates the executable backend directly

## Components

The compiler is composed of 7 main components:

1. **Lexer** - Tokenizes source code (`src/NSharpLang.Compiler/Lexer.cs`)
2. **Parser** - Builds AST from tokens (`src/NSharpLang.Compiler/Parser.cs`)
3. **Analyzer** - Type checking and semantic analysis (`src/NSharpLang.Compiler/Analyzer.cs`)
4. **Transpiler** - Generates C# code (`src/NSharpLang.Compiler/Transpiler.cs`)
5. **IL Compiler** - Emits managed PE assemblies directly (`src/NSharpLang.Compiler/ILCompiler/`)
6. **CLI** - Command-line interface (`src/NSharpLang.Cli/Program.cs`)
7. **Error Reporting** - Diagnostics and suggestions (`src/NSharpLang.Compiler/ErrorReporting.cs`)

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

### 4. Backend Emission
- **Input**: `CompilationUnit` (AST) + semantic context
- **Output**:
  - `il` backend → managed PE assembly
- **Process**:
  - IL compiler uses `System.Reflection.Emit` and `ManagedPEBuilder` to emit assemblies directly

### 5. Toolchain Integration
- **Input**: backend output
- **Output**: Executable, DLL, or published artifacts
- **Process**:
  - il backend emits assemblies directly in compiler-driven flows and through SDK build tasks in project/MSBuild flows
  - IL participates in `nlc check/build/run/test/bench/publish`

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
│   └── Program.cs             - CLI commands (build, run, check, test, publish, etc.)
├── NSharpLang.Build.Tasks/
│   └── EmitIlAssembly.cs      - MSBuild IL emission task
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
