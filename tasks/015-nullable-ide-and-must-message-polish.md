# Task 015: Nullable IDE And Must Message Polish

Priority: P1.

Finish the developer-facing polish around nullable unwraps now that `must`, nullable `.HasValue` / `.Value`, and nullable match semantics exist in the compiler.

## User Outcome

Developers should see `must` as a first-class language feature in the editor and CLI query surfaces, and they should have a designed way to attach a domain-specific failure message when an unwrap is intentionally fatal.

## Scope

- Decide and document the syntax for optional `must` failure messages, or explicitly reject custom messages in favor of `if`/`throw`.
- If accepted, implement parsing, formatting, analyzer typing, C# export, IL lowering, and tests for custom `must` failure messages.
- Add `must` to VS Code TextMate grammar, semantic-token keyword handling, keyword completion, and hover help.
- Add nullable unwrap/match snippets or completion documentation only if they are concise and do not crowd normal editing.
- Ensure `nlc query completions --include-keywords` and any LSP keyword lists stay aligned.

## Likely Files

- `src/NSharpLang.Compiler/Parser.cs`
- `src/NSharpLang.Compiler/Ast/Expressions.cs`
- `src/NSharpLang.Compiler/Analyzer.cs`
- `src/NSharpLang.Compiler/Formatter.cs`
- `src/NSharpLang.Compiler/Transpiler.cs`
- `src/NSharpLang.Compiler/ILCompiler/ILCompiler.cs`
- `src/NSharpLang.LanguageServer/Handlers`
- `editors/vscode`
- `tests`
- `memory/features/type-system.md`

## Acceptance

- The chosen `must` message design is documented with examples and non-examples.
- If custom messages are implemented, both C# and IL backends throw the custom message consistently.
- `must` highlights as a keyword in VS Code and appears in appropriate completion/hover surfaces.
- IDE behavior is visually verified in a real VS Code window after extension reload.
- Query/LSP keyword coverage has tests so the lists do not drift again.

## Verification

- Run focused parser, analyzer, formatter, transpiler, IL compiler, language server, and extension tests while developing.
- Run `./scripts/reload-vscode-extension.sh`, open VS Code, and visually verify keyword highlighting/completion/hover in a sample `.nl` file.
- Run `./scripts/test-all.sh` before committing.
