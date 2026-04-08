# N# Compiler Architecture

## Overview

N# currently has two compilation backends:
- `transpile` — parse/analyze, emit C#, then leverage the .NET toolchain
- `il` — parse/analyze, emit IL directly to a managed assembly

The product toolchain now supports both backends end to end. Projects can opt into either `backend: transpile` or `backend: il`, and the CLI plus MSBuild SDK honor that selection consistently for build, run, test, benchmark, and publish flows. The transpiler remains useful as an explicit C# export/debug path, but it is no longer the only production execution backend.

```
.nl source file
    ↓
Lexer (Token stream)
    ↓
Parser (AST)
    ↓
Analyzer (Semantic analysis)
    ↓
    ├── Transpiler (C# code) → C# Compiler (via dotnet) → Executable
    └── IL Compiler (managed PE emit) → Managed assembly / executable
```

## Why Transpile to C#?

- **Generated-code inspection**: Useful for debugging code generation and interop issues
- **C# export/debug surface**: `nlc transpile` remains valuable when users need to inspect emitted C#
- **Compatibility escape hatch**: Keeps an alternate backend available while the product completes the IL-default cutover

## Why Emit IL Directly?

- **Backend independence**: Removes C# codegen as a hard product dependency
- **Production backend**: The CLI and SDK can now execute the selected project backend without routing through generated C#
- **Real-backend validation**: `nlc check` can validate the configured executable backend directly

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
  - `transpile` backend → C# source code
  - `il` backend → managed PE assembly
- **Process**:
  - Transpiler uses AST visitation to generate C#
  - IL compiler uses `System.Reflection.Emit` and `ManagedPEBuilder` to emit assemblies directly

### 5. Toolchain Integration
- **Input**: backend output
- **Output**: Executable, DLL, or published artifacts
- **Process**:
  - transpile backend emits C# and uses the SDK/MSBuild path to compile it
  - il backend emits assemblies directly in compiler-driven flows and through SDK build tasks in project/MSBuild flows
  - both backends participate in `nlc check/build/run/test/bench/publish`

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
