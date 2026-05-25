# Task 022: Import And Emit C# Nullable Metadata

Priority: P1 nullability and C# interop.

Work in the N# repository and model C# nullable metadata at interop boundaries. C# nullable annotations are not yet fully decoded as semantic facts, and generated public C# must preserve N# nullability for C# consumers.

## Scope

- Decode `NullableAttribute`, `NullableContextAttribute`, and common flow attributes such as `MaybeNull`, `NotNull`, and `NotNullWhen`.
- Represent missing metadata as `Oblivious`.
- Map annotated C# APIs to `T` or `T?` accurately in N#.
- Emit nullable metadata or C# syntax from generated public C# so C# consumers see correct nullability.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/TypeInfo.cs`
- `src/NSharpLang.Compiler/CompilationReferenceResolver.cs`
- `src/NSharpLang.Compiler/Transpiler.cs`
- `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`
- `tests/AnalyzerTests.cs`
- `tests/TranspilerTests.cs`
- `tests/ILCompilerTests.cs`

## Acceptance

- Reflection import decodes `NullableAttribute`, `NullableContextAttribute`, and common flow attributes such as `MaybeNull`, `NotNull`, and `NotNullWhen`.
- Annotated C# APIs map to `T` or `T?` accurately in N#.
- Missing nullable metadata can be represented as `Oblivious`.
- Generated public C# preserves N# nullability for C# consumers.

## Verification

- Run focused analyzer, interop, transpiler, and IL compiler tests while developing.
- Add small C# fixture assemblies if needed to cover nullable metadata cases.
- Run `./scripts/test-all.sh` before committing.
