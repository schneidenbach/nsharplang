# Task 015: Build And Test Warning Hygiene

Priority: P2.

Make the ordinary local verification path quiet enough that warnings mean something. A clean `./scripts/test-all.sh` currently passes, but plain `dotnet test tests/Tests.csproj` still emits package-pruning, nullable, and analyzer warning noise before reporting success.

## User Outcome

A contributor can run the normal build and test commands and immediately trust the output. New warnings are visible regressions instead of being buried under known noise.

## Scope

- Audit warnings from `dotnet test tests/Tests.csproj`, `dotnet build`, and `./scripts/test-all.sh`.
- Remove unnecessary package references or explicitly document why they are retained.
- Fix nullable warnings in compiler, language server, and test code where the code is actually unsafe or ambiguous.
- Add targeted suppressions only when the code is intentionally safe and the suppression is documented at the narrowest practical scope.
- Decide whether the release gate should fail on new warnings, and apply that policy consistently.

## Likely Files

- `tests/Tests.csproj`
- `src/NSharpLang.Compiler/Compiler.csproj`
- `src/NSharpLang.LanguageServer/LanguageServer.csproj`
- `tests/ILCompilerTests.cs`
- `tests/LanguageServerTests.cs`
- `tests/ParserTests.cs`
- `scripts/test-all.sh`

## Acceptance

- `dotnet test tests/Tests.csproj` completes without known warning noise.
- Package-pruning warnings are either fixed or justified in project files.
- Nullable and analyzer warnings are fixed or narrowly suppressed with rationale.
- `./scripts/test-all.sh` still passes end to end.
- The warning policy is documented for contributors.

## Verification

- Run `dotnet build`.
- Run `dotnet test tests/Tests.csproj`.
- Run `./scripts/test-all.sh` before committing if code or build configuration changes.
