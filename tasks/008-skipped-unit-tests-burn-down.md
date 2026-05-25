# Task 008: Burn Down Skipped Unit Tests

Priority: P0 correctness and release hygiene.

Work in the N# repository and remove the current intentional skips in the core unit suite. These are product gaps, not acceptable permanent skips.

## Current Skips

- `LanguageServerTests.Completion_ChainedMemberAccessAsync`
- `LanguageServerTests.Hover_ChainedMemberAccessAsync`
- `ILCompiler_CanExecuteNullLiteralsForReferenceAndNullableTypes`

## Scope

- Fix chained member access completion and hover so the language server resolves the semantic receiver type after calls such as `message.ToUpper().`.
- Use the shared compiler semantic model for chained receiver typing. Do not add a text-only LSP special case.
- Fix IL null equality under .NET 10 for CLR reference types, emitted N# class types, nullable value types, and both `value == null` / `null == value` operand orders.
- Unskip the tests only when the underlying behavior is fixed and covered.

## Likely Files

- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.Compiler/SemanticModel.cs`
- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`
- `src/NSharpLang.LanguageServer/Handlers/CompletionHandler.cs`
- `src/NSharpLang.LanguageServer/Handlers/HoverHandler.cs`
- `tests/LanguageServerTests.cs`
- `tests/ILCompilerCoverageTests.cs`
- `tests/ILCompilerTests.cs`

## Acceptance

- `LanguageServerTests.Completion_ChainedMemberAccessAsync` is unskipped and passes.
- `LanguageServerTests.Hover_ChainedMemberAccessAsync` is unskipped and passes.
- `ILCompiler_CanExecuteNullLiteralsForReferenceAndNullableTypes` is unskipped and passes.
- Add focused coverage for both null operand orders on emitted class types.
- `rg -n "Fact\\(Skip|Theory\\(Skip" tests` returns no remaining skipped unit tests, or each remaining skip has its own task file.
- `dotnet test tests/Tests.csproj` reports `Skipped: 0`.

## Verification

- Run focused LanguageServer and IL compiler tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Because this changes language server behavior, run `./scripts/reload-vscode-extension.sh` and visually verify chained completion and hover in VS Code.
