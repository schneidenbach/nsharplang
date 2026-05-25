# Task 001: Semantic Authoring And Navigation

Priority: P0.

Make authoring and navigation consume the same semantic model in CLI tooling and VS Code. This combines chained member access and type-use navigation because both depend on stable source spans, receiver/type binding, and code-intelligence queries that must not fall back to string matching.

## User Outcome

Developers can write and navigate code like:

```nsharp
func main(): void
    let message = "hello"
    let upper = message.ToUpper().
    let len = message.ToUpper().Length
    let names: List<Person> = []
```

Completion after the trailing dot should show members of `string`, hover on `Length` should describe the resolved member, and go-to-definition/find-references/hover/rename/query should work from type uses such as `Person`, `List<Person>`, `Person?`, `Person[]`, and `Func<Person, string>`. CLI query behavior and the editor must agree because they are reading the same semantic binding data.

## Scope

- Resolve receiver types after chained method calls and property accesses.
- Add stable source spans to all `TypeReference` shapes.
- Record semantic bindings for member receiver and type-use positions.
- Make CLI definition/references/inspect/type queries and LSP completion/definition/references/hover consume the same semantic source of truth.
- Cover duplicate member and type names in different receiver types, namespaces, and files.
- Unskip and pass `LanguageServerTests.Completion_ChainedMemberAccessAsync`.
- Unskip and pass `LanguageServerTests.Hover_ChainedMemberAccessAsync`.

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
- `tests/LanguageServerTests.cs`
- `tests/QueryIntegrationTests.cs`

## Acceptance

- Chained completion, hover, and query type results agree for representative .NET and N# member chains.
- Type annotations, generic arguments, nullable type references, array element types, and function type references have stable source spans.
- BindingMap and SemanticModel record bindings for those source positions.
- CLI and LSP navigation work for type-use sites and agree with each other.
- Duplicate simple names do not produce false positives.
- The solution avoids parser text heuristics that bypass semantic binding.

## Verification

- Run focused parser, binding, semantic model, query, and language-server tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify chained completion, hover, and type-use navigation in VS Code.
