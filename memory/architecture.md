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

1. **Lexer** - tokenizes source code (`src/NSharpLang.Compiler.BootstrapServices/Lexer.nl`)
2. **Parser** - builds syntax trees (`src/NSharpLang.Compiler.BootstrapServices/ColumnarParserRecovery.nl`, N#)
3. **Analyzer** - type checking and semantic analysis (`src/NSharpLang.Compiler/Analyzer.cs`, with the N# owners `AnalyzerDeclarationContext.nl`, `TypeInfoIdentityFacts.nl`, `AnalyzerConversionFacts.nl`, `AnalyzerCallableReferenceFacts.nl`, `AnalyzerWellKnownTypes.nl`, `AnalyzerWellKnownTypeFacts.nl`, `AnalyzerClrTypeConversion.nl`, `AnalyzerAssignabilityFacts.nl`, `AnalyzerExternalTypeProbe.nl`, `AnalyzerTypeReferenceFacts.nl`, `AnalyzerScopeStack.nl`, `AnalyzerProjectDiscovery.nl`, `AnalyzerTypeResolver.nl`, `AnalyzerTypeSubstitution.nl`, `AnalyzerStructuralAssignability.nl`, `AnalyzerDiagnosticSink.nl`, `AnalyzerStateModels.nl`, `AnalyzerDiagnostics.nl`, `NullabilityMetadataCore.nl`, `NullabilityMetadataReflection.nl`, `AnalyzerReflectionTypeConversion.nl`, `AnalyzerFunctionTypeFactory.nl`, `AnalyzerAssignability.nl`)
4. **Columnar backend** - emits managed PE assemblies from N# compiler tables (`src/NSharpLang.Compiler/Columnar/`)
5. **CLI** - command-line workflows (`src/NSharpLang.Cli/`)
6. **Error reporting** - diagnostics and suggestions (`src/NSharpLang.Compiler.BootstrapServices/CompilerError.nl`, `ErrorCode.nl`, `ErrorMessageBuilder.nl`, `ErrorSuggestions.nl`, N#)

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

<a id="non-nsharp-survivors"></a>

## Non-N# survivors

This is the durable location for the final closeout allowlist. During the migration, absence from
this section does not make a non-N# file acceptable; it remains product-ownership debt until its
N# replacement is in the product path or the final audit proves it is mechanical integration.

The completed inventory will list each surviving path, the ecosystem boundary it adapts to, the
N# owner it invokes, responsibilities it is forbidden to own, and a removal or re-evaluation
trigger. Candidate boundary categories include MSBuild/LSP protocol objects, process/socket/file
IO, PE/Reflection.Emit replay, metadata loading, ALC loading, NuGet/Zip/HTTP mechanics, and editor
UI wiring. Classification is path-specific: a file does not qualify merely because it uses one
of those APIs or is small.

`tasks/README.md` is the ordered vertical ownership queue and
`systems-language-closeout/STATUS.md` is its temporary cursor/evidence ledger. The final queue task
replaces this paragraph with the exact reviewed allowlist and enforces it with the committed
ownership audit.

## Build And Test Commands

```bash
dotnet build src/NSharpLang.Compiler/Compiler.csproj
dotnet build src/NSharpLang.Cli/Cli.csproj
dotnet test tests/Tests.csproj
```

Use `./scripts/dev.sh <pattern>` for focused backend/compiler iteration and the appropriate
`./scripts/test-all.sh --commit` gate at integration checkpoints, as described in `AGENTS.md`.
