# Task 016: Add Explicit Null-State And Flow-Fact Data Structures

Priority: P1 nullability.

Work in the N# repository and give nullability a real semantic model. Nullable compatibility and branch narrowing exist, but there is no complete null-state model for expressions, symbols, and stable member paths.

## Scope

- Design and implement analyzer data structures for null states: `Unknown`, `Null`, `MaybeNull`, `NotNull`, and `Oblivious`.
- Track facts for variables and stable member paths.
- Expose declared type, flow type, and null state through SemanticModel at source positions.
- Avoid noisy cascades after unrelated parse or type errors.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/SemanticModel.cs`
- `src/NSharpLang.Compiler/TypeInfo.cs`
- `tests/AnalyzerTests.cs`
- `tests/AnalyzerSemanticModelTests.cs`

## Acceptance

- Analyzer distinguishes `Unknown`, `Null`, `MaybeNull`, `NotNull`, and `Oblivious`.
- SemanticModel can expose declared type, flow type, and null state at a source position.
- Facts are tracked for variables and stable member paths without noisy cascades after unrelated errors.
- The model is ready for diagnostics, query output, and LSP features in later nullability tasks.

## Verification

- Run focused analyzer and SemanticModel null-state tests while developing.
- Run `./scripts/test-all.sh` before committing.
