# Task 001: Chained Member Access Authoring

Priority: P0.

Make chained member access feel correct in both CLI tooling and VS Code. Today the suite has skipped language-server tests for completion and hover after chained calls. This is a visible authoring failure, not just an internal semantic-model cleanup.

## User Outcome

In a file like:

```nsharp
func main(): void
    let message = "hello"
    let upper = message.ToUpper().
    let len = message.ToUpper().Length
```

completion after the trailing dot should show members of `string`, hover on `Length` should describe the resolved member, and CLI query behavior should agree with the editor. The implementation must use compiler semantics for the receiver expression; do not add a text-only language-server special case.

## Scope

- Resolve receiver types after chained method calls and property accesses.
- Use the same semantic source of truth for CLI query and LSP completion/hover.
- Unskip and pass `LanguageServerTests.Completion_ChainedMemberAccessAsync`.
- Unskip and pass `LanguageServerTests.Hover_ChainedMemberAccessAsync`.
- Add coverage for at least one chained call whose return type is not `string`.

## Likely Files

- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/SemanticModel.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.LanguageServer/Handlers/CompletionHandler.cs`
- `src/NSharpLang.LanguageServer/Handlers/HoverHandler.cs`
- `tests/LanguageServerTests.cs`
- `tests/QueryIntegrationTests.cs`

## Acceptance

- Chained completion, hover, and query type results agree for representative .NET and N# member chains.
- The two skipped chained-member language-server tests are enabled and passing.
- Duplicate simple member names on different receiver types do not produce false positives.
- The solution avoids parser text heuristics that bypass semantic binding.

## Verification

- Run focused language-server and query tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify chained completion and hover in real VS Code.
