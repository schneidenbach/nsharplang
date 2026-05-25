# Task 003: Type-Use Navigation

Priority: P0.

Make type annotations and generic type arguments navigable everywhere a developer expects. This is a vertical slice through parser spans, semantic binding, CLI query, and VS Code navigation.

## User Outcome

From a type use such as `person: Person`, `List<Person>`, `Person?`, `Person[]`, or `Func<Person, string>`, a developer should be able to use go-to-definition, find references, hover, rename where safe, and `nlc query` commands without simple-name confusion.

## Scope

- Add stable source spans to all `TypeReference` shapes.
- Record semantic bindings for type-use positions.
- Make CLI definition/references/inspect and LSP definition/references/hover consume the same semantic binding data.
- Cover duplicate type names in different namespaces or files.

## Likely Files

- `src/NSharpLang.Compiler/Ast.cs`
- `src/NSharpLang.Compiler/Parser.cs`
- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/BindingMap.cs`
- `src/NSharpLang.Compiler/SemanticModel.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.LanguageServer`
- `tests/BindingMapTests.cs`
- `tests/AnalyzerSemanticModelTests.cs`
- `tests/QueryIntegrationTests.cs`
- `tests/LanguageServerTests.cs`

## Acceptance

- Type annotations, generic arguments, nullable type references, array element types, and function type references have stable source spans.
- BindingMap and SemanticModel record bindings for those source positions.
- CLI and LSP navigation work for type-use sites and agree with each other.
- Duplicate type-name fixtures prove the feature is semantic, not string matching.

## Verification

- Run focused parser, binding, semantic model, query, and language-server tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify type-use navigation in VS Code.
