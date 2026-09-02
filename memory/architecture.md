# N# Compiler Architecture

## Overview

N# has one supported executable backend:
- `il` - parse/analyze and emit a managed assembly directly.

The product toolchain runs through IL end to end. Projects use `backend: il` or omit the field and
take the default. The CLI and MSBuild SDK honor that path for build, run, test, perf-report, publish,
and package flows.

Compiler core, compiler-service, and CLI/tooling command logic are N#-owned. The parser, AST, syntax
diagnostics, semantic analysis, systems policy, linting, formatting, code intelligence and the `nlc`
command surface each have exactly one N# production owner; see the reviewed allowlist below for the
mechanical C# boundaries that remain and for the two surfaces that are still owning C#.

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

### The reviewed allowlist for `src/NSharpLang.Compiler`

Every tracked file in the compiler assembly, classified by the task-021 terminal audit. "Decisions"
is the product-decision census — `NL` codes / user-facing sentences / ordering sites / non-zero exit
returns — which is what proves *mechanical* rather than the word. Line counts are
`ratchet epoch -> current`; no row in the entire 381-row ratchet has ever exceeded its epoch.

| path | epoch -> current | decisions | N# owner it invokes | class |
|---|---|---|---|---|
| `Analyzer.cs` | 23,451 -> 2,798 | 0/1/0/0 | the `Analyzer*.nl` family (81 production files); `AnalyzerMetadataLoadPolicy` | mechanical shell + **quarantine** |
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

**Read the exceptions literally.** Two rows are *not* mechanical boundaries and are not claimed as
such:

- `ColumnarIlEmitter.cs` carries **144 user-facing sentences**. IL generation therefore does **not**
  yet have exactly one N# production owner. It retires under the four remaining
  `tasks/015-remaining-emitter-decisions.md` sub-tasks (plan-row lambda-body emitter; N#
  preflight/typing-owner port; async-func lowering; planner-driven operand unlocks), and under the
  AOT metadata-writer task that must replace `System.Reflection.Emit` outright.
- **The SIMD auto-vectorizer is C# inside `ColumnarIlEmitter.cs` and has an N# contract owner, not an
  N# implementation owner.** `TryEmitVectorizedReduction{While,For}`, `TryEmitVectorizedRangeCount*`,
  `TryEmitVectorizedMinMax*`, and `TryEmitVectorizedCountTransitions*` (plus the `SimdReductions` helper
  table near the top of the file) lower four loop shapes to calls into
  `src/NSharpLang.Runtime/SimdReductions.cs`. That lowering is what makes systems N# Rust-class on the
  vectorizable kernels (`benchmarks/native-comparison/`), and its C# tests were deleted at a50cb4000.
  Since 2026-09-01 the contracts live in `tests/native/systems-vectorization-facts` (IL shape read from
  the emitted assembly by an N# IL walker, plus scalar-equivalence on fixed and randomised inputs, for
  every accepted shape and every conservative guard), and the throughput is gated by the product gate's
  Step 3c against `benchmarks/native-comparison/runner/SystemsThroughputBaseline.nl`. **Any 015 sub-slice
  that deletes or ports the vectorizer must route through that contract project: the N# owner is done
  only when `systems-vectorization-facts` is green unchanged and Step 3c still passes.** Note also that
  the `NSHARP_VECTORIZE_REDUCTIONS=0` opt-out the docs used to advertise died with the legacy IL compiler
  at 1cef0d16e; the columnar emitter has no opt-out, and the contract project pins that fact.
- `Analyzer.cs`'s remaining decision residue is one internal `InvalidOperationException` inside
  `LoadSystemAssemblies()`, which sits wholly inside the **`MetadataLoadContext` quarantine**
  (17 members plus the nested `NSharpMetadataResolver`). The quarantine retires with the AOT
  external-type-model task: the estate cannot spell `MetadataReader` today, and 83 production `.nl`
  files name the `System.Reflection` object model (its types, or an `import System.Reflection`), so
  replacing it is a task, not a slice.

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
