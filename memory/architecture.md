# N# Compiler Architecture

## Overview

N# has one supported executable backend:
- `il` - parse/analyze and emit a managed assembly directly.

The product toolchain runs through IL end to end. Projects use `backend: il` or omit the field and
take the default. The CLI and MSBuild SDK honor that path for build, run, test, perf-report, publish,
and package flows.

Compiler core, compiler-service, and CLI/tooling command logic are moving to N# ownership. Current compiler
compiler-core and tooling logic is deletion debt, not architecture.

```text
.nl source
  -> Lexer
  -> Parser
  -> Analyzer / semantic model
  -> IL compiler
  -> managed assembly / executable
```

## Why Emit IL Directly?

- **Backend independence:** CLI and SDK builds route through direct IL emission.
- **Production backend:** the CLI and SDK execute projects through direct IL emission.
- **Real-backend validation:** `nlc check` validates the executable backend directly.

## Main Components

1. **Lexer** - tokenizes source code (`src/NSharpLang.Compiler/Lexer.cs`)
2. **Parser** - builds syntax trees (`src/NSharpLang.Compiler/Parser.cs`)
3. **Analyzer** - type checking and semantic analysis (`src/NSharpLang.Compiler/Analyzer.cs`)
4. **Columnar backend** - emits managed PE assemblies from N# compiler tables (`src/NSharpLang.Compiler/Columnar/`)
5. **CLI** - command-line workflows (`src/NSharpLang.Cli/`)
6. **Error reporting** - diagnostics and suggestions (`src/NSharpLang.Compiler/ErrorReporting.cs`)

## Data Flow

### Tokenization
- Input: `.nl` source text
- Output: tokens with line/column information

### Parsing
- Input: tokens
- Output: compilation unit syntax tree

### Analysis
- Input: compilation unit
- Output: semantic result, diagnostics, type information, nullability, and binding facts

### IL Emission
- Input: syntax plus semantic context
- Output: managed PE assembly
- Process: the N# columnar backend emits metadata and IL directly.

## Current Compiler Debt

If code search finds old parser, binder, analyzer, semantic-model, diagnostics, IL-lowering, codegen,
generated-source backend, or legacy comparison path ownership, treat it as a target for replacement
and deletion. Do not preserve it because an older doc called it an inspection surface.

## Build And Test Commands

```bash
dotnet build src/NSharpLang.Compiler/Compiler.csproj
dotnet build src/NSharpLang.Cli/Cli.csproj
dotnet test tests/Tests.csproj
```

Use `./scripts/dev.sh <pattern>` for focused backend/compiler iteration and the appropriate
`./scripts/test-all.sh --commit` gate at integration checkpoints, as described in `AGENTS.md`.
