# Task 001: Add Source Positions To Type References

Priority: P0 semantic correctness.

Work in the N# repository and make type-use sites first-class semantic locations. `TypeReference` nodes still do not carry enough source-position information for fully semantic definition, references, rename, hover, and query behavior at type annotations and generic type arguments. This creates text/name fallback risk in both CLI tools and VS Code.

## Scope

- Audit parser construction of every `TypeReference` shape: simple names, qualified names, nullable types, array types, generic arguments, and function types.
- Add stable source spans to type references without breaking existing parser or formatter behavior.
- Record semantic bindings for type-use positions in `BindingMap` and `SemanticModel`.
- Update CLI query paths and LSP handlers that answer definition, references, hover, rename, and inspect at type-use sites.
- Prefer shared compiler semantics over per-command AST walking.

## Likely Files

- `src/NSharpLang.Compiler/Parser.cs`
- `src/NSharpLang.Compiler/Ast.cs`
- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/BindingMap.cs`
- `src/NSharpLang.Compiler/SemanticModel.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.LanguageServer`
- `tests/*BindingMap*`, `tests/*SemanticModel*`, `tests/QueryIntegrationTests.cs`, `tests/LanguageServerTests.cs`

## Acceptance

- Type annotations, generic type arguments, nullable type references, array element types, and function type references have stable source spans.
- BindingMap and SemanticModel record bindings for type-use positions.
- `nlc query definition`, `nlc query references`, `nlc query inspect`, and LSP definition/references work for type annotations and generic arguments.
- Tests cover duplicate type names in different namespaces/files so the implementation cannot fall back to simple-name matching.
- Existing parser, formatter, and valid-code behavior remain stable.

## Verification

- Run focused parser, binding, query, and language server tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Because this affects IDE behavior, run `./scripts/reload-vscode-extension.sh` and visually verify type-use navigation in VS Code.
