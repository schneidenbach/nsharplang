# Task 008: C# Nullability Interop

Priority: P1.

Make N# understand and emit C# nullable metadata at interop boundaries. This stays separate from nullable language idioms because reflection metadata import/export has its own compatibility surface and backend risks.

## User Outcome

When N# calls annotated C# APIs, it should know which values are nullable. When C# consumes N# output, C# should see accurate nullable annotations for public APIs.

## Scope

- Decode `NullableAttribute`, `NullableContextAttribute`, and common flow attributes such as `MaybeNull`, `NotNull`, and `NotNullWhen`.
- Represent missing metadata as `Oblivious`.
- Map annotated C# APIs to `T` or `T?` accurately in N#.
- Emit nullable metadata or equivalent public C# syntax for N# APIs.
- Surface interop nullability in query and hover where applicable.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/TypeInfo.cs`
- `src/NSharpLang.Compiler/CompilationReferenceResolver.cs`
- `src/NSharpLang.Compiler/Transpiler.cs`
- `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`
- `tests/AnalyzerTests.cs`
- `tests/TranspilerTests.cs`
- `tests/ILCompilerTests.cs`
- `tests/QueryIntegrationTests.cs`

## Acceptance

- Annotated C# APIs map to correct N# nullability.
- Missing nullable metadata maps to an explicit oblivious state.
- Generated public C# preserves N# nullability for C# consumers.
- Query/hover surfaces reflect imported and emitted nullability.
- Fixture assemblies cover representative nullable metadata cases.

## Verification

- Run focused analyzer, interop, transpiler, IL compiler, and query tests while developing.
- Run `./scripts/test-all.sh` before committing.
