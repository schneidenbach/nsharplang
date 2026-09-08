# N# Compiler Architecture

## Overview

N# has one supported executable backend:
- `il` - parse/analyze and emit a managed assembly directly.

The product toolchain runs through IL end to end. Projects use `backend: il` or omit the field and
take the default. The CLI and MSBuild SDK honor that path for build, run, test, perf-report, publish,
and package flows.

The parser, AST, syntax diagnostics, semantic analysis, systems analysis, columnar input builder,
IL emitter and multi-file compiler are N#-owned. Compiler-wide ownership remains open: recursive
reference resolution, SDK reference-assembly orchestration and remaining canonical compiler
assertions still require migration. CLI/editor policy and broader branch initiatives are tracked
separately. Historical allowlist labels below do not establish current completion.

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
3. **Analyzer** - type checking and semantic analysis (`src/NSharpLang.Compiler.BootstrapServices/Analyzer.nl`, with the N# owners `AnalyzerDeclarationContext.nl`, `TypeInfoIdentityFacts.nl`, `AnalyzerConversionFacts.nl`, `AnalyzerCallableReferenceFacts.nl`, `AnalyzerWellKnownTypes.nl`, `AnalyzerWellKnownTypeFacts.nl`, `AnalyzerClrTypeConversion.nl`, `AnalyzerAssignabilityFacts.nl`, `AnalyzerExternalTypeProbe.nl`, `AnalyzerTypeReferenceFacts.nl`, `AnalyzerScopeStack.nl`, `AnalyzerProjectDiscovery.nl`, `AnalyzerTypeResolver.nl`, `AnalyzerTypeSubstitution.nl`, `AnalyzerStructuralAssignability.nl`, `AnalyzerDiagnosticSink.nl`, `AnalyzerStateModels.nl`, `AnalyzerDiagnostics.nl`, `NullabilityMetadataCore.nl`, `NullabilityMetadataReflection.nl`, `AnalyzerReflectionTypeConversion.nl`, `AnalyzerFunctionTypeFactory.nl`, `AnalyzerAssignability.nl`)
4. **Columnar backend** - emits managed PE assemblies from N# compiler tables (`src/NSharpLang.Compiler.BootstrapServices/ColumnarIlEmitter.nl`)
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

### Historical reviewed inventory for `src/NSharpLang.Compiler`

The table records the task-021 terminal audit, not current ownership acceptance. The current
compiler cursor and ratchet are authoritative. Complete Analyzer, SystemsAnalyzer, input-builder
and ColumnarIlEmitter ownership is accepted. The complete MultiFileCompiler class is also accepted
at `27b1a8a1b`; its old C# file and ten-case recovery test file are deleted.

At that audit, tracked files in the compiler assembly were classified as follows. "Decisions"
is the product-decision census — `NL` codes / user-facing sentences / ordering sites / non-zero exit
returns. That census alone does not prove a boundary mechanical: state, control flow and failure
policy must also be reviewed. Line counts are
`ratchet epoch -> current`; no row in the entire 381-row ratchet has ever exceeded its epoch.

| path | epoch -> current | decisions | N# owner it invokes | class |
|---|---|---|---|---|
| `Analyzer.cs` | 23,451 -> 0 | removed | complete `Analyzer.nl` and existing N# collaborators | deleted; accepted at `a207ee13b` |
| `CodeIntelligence/CodeIntelligenceService.cs` | 1,906 -> 153 | 0/0/0/0 | `ProjectSnapshot.nl`, `CodeIntelligenceQueries.nl` | mechanical |
| `CodeIntelligence/CompletionEngine.cs` | 805 -> 96 | 0/1/0/0 | `CompletionEngineKernels.nl`, `CompletionReceiverFacts.nl` | mechanical |
| `CodeIntelligence/FixApplicator.cs` | 57 -> 54 | 0/0/0/0 | `ColumnarParserRecovery.nl`, `Linter.nl`, `CodeFix.nl` | mechanical |
| `CodeIntelligence/OutputFormatter.cs` | 379 -> 271 | 0/0/0/0 | `OutputFormatterJsonKernels.nl` and siblings | mechanical |
| `Columnar/ColumnarDeclineTrace.cs` | 39 -> 39 | 0/0/0/0 | `ColumnarDeclineReasons.nl` | mechanical |
| `Columnar/ColumnarIlEmitter.cs` | 21,723 -> 21,519 | **0/144/3/2** | the `Columnar*Planner/Resolver/Facts` family (33 production files) | **STILL OWNING — not mechanical** |
| `Columnar/ColumnarProgramInputBuilder.cs` | 1,062 -> 1,051 | 0/0/0/0 | 16 `global::Program.*` parser kernels | mechanical |
| `MultiFileCompiler.cs` | 670 -> 663 | 0/6/0/0 | `ImportGraph*`, `ColumnarEmissionDiagnostics.nl` | mechanical |
| `Performance/SystemsAnalyzer.cs` | 2,390 -> 1,156 | 0/0/0/0 | the twelve `Systems*Policy` types (11 files) | mechanical |
| `Compiler.csproj` | 38 -> 38 | — | — | mechanical |

Eleven further C# files in this assembly are `state:"removed"` — deleted whole, 37,616 epoch lines:
`Parser.cs`, `Formatter.cs`, `Linter.cs`, `DocQuery.cs`, the three `Ast/*.cs`, `NullabilityMetadata.cs`,
`ErrorReporting.cs`, `AstNodeFinder.cs` and `Columnar/ColumnarCompiler.cs`.

**Current ownership must be proved from source.** Historical mechanical labels do not exempt
remaining state/control ownership from the active goal:

- The complete `ColumnarIlEmitter` implementation, including SIMD loop lowering, now lives in
  `src/NSharpLang.Compiler.BootstrapServices/ColumnarIlEmitter.nl`; its C# owner is deleted.
  Checkpoint `8ec52542b`, published with `d533cd51e`, passed the fresh IDE-enabled product gate,
  installed SDK verification and real-editor formatting checks. See
  [the acceptance evidence](../systems-language-closeout/decodes/2026-09-08-complete-columnar-emitter-ownership.md).
- The existing `tests/native/systems-vectorization-facts` assertions and product-gate throughput
  checks remain the vectorizer's regression coverage. Calls into
  `src/NSharpLang.Runtime/SimdReductions.cs` are runtime calls; runtime reimplementation remains
  separate from compiler lowering ownership.
- The complete `MultiFileCompiler.nl` owns pipeline sequencing, state, diagnostics, emission-thread
  lifetime and failure behavior. Its ten recovery cases execute in N#. Fresh product/IDE checks,
  installed SDK self-host and real unsaved-buffer verification pass at `27b1a8a1b`.
  [Acceptance](../systems-language-closeout/decodes/2026-09-08-complete-multifile-compiler-ownership.md).
- `src/NSharpLang.Cli/CompilationReferenceResolver.cs` still controls recursive reference builds,
  package traversal, caching and failure behavior. Existing N# kernels do not make the remaining
  orchestration mechanical. Compiler reference resolution remains in scope despite its CLI path;
  the complete owner and canonical assertions are the selected implementation area in task 021.
- `Build.Tasks/EmitIlAssembly.cs` still owns reference-assembly scanning, traversal, duplicate
  identity reuse, rewrite/write ordering and failure cleanup. Existing SdkEmitTaskKernels predicates
  do not make this connected group mechanical. Move it with its state/helpers, preferably with the
  complete task if actual N# source supports the required MSBuild boundary. Retain the existing
  Cecil behavior; this establishes no dependency on a new metadata writer.
- The former Analyzer metadata quarantine is removed with the complete C# class. Its metadata
  lifecycle and existing reflection operations are owned by N#; no metadata-writer rewrite was
  required to achieve that ownership. NativeAOT and a broader metadata-writer initiative remain
  separate from the compiler-only goal unless a concrete ownership dependency is demonstrated.

Sibling assemblies are classified the same way and carry two `(b)` pins — surfaces that retire *with
their subject* rather than moving, and which are pinned by contract in the meantime:
`Cli/Daemon/DaemonProtocol.cs`'s JSON-RPC wire DTOs, and `Playground/PlaygroundRunner.cs`'s execution
mechanism (a tree-walking interpreter that answers differently from `nlc run` on seven of fourteen
comparable programs; it retires when the playground runs emitted IL in the browser).
`Playground/PlaygroundCompiler.cs` carries the hosted playground's own presentation copy — 24
sentences and 7 ordering sites — and retires with the same Playground task.

The ratchet at `tests/native/ownership-audit/non-nsharp-growth-ratchet.v1.json` enforces this
allowlist mechanically: no listed file may grow past its epoch ceiling (`OWN004`), and a new non-N#
file is refused outright (`OWN003` — *"new unclassified non-N# file; implement this behavior in N#
or remove the file"*). `tasks/README.md` is the ordered vertical ownership queue and
`systems-language-closeout/STATUS.md` is its cursor/evidence ledger.

## Build And Test Commands

```bash
dotnet build src/NSharpLang.Compiler/Compiler.csproj
dotnet build src/NSharpLang.Cli/Cli.csproj
dotnet test tests/Tests.csproj
```

Use `./scripts/dev.sh <pattern>` for focused backend/compiler iteration and the appropriate
`./scripts/test-all.sh --commit` gate at integration checkpoints, as described in `AGENTS.md`.
