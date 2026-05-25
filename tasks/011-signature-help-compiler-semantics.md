# Task 011: Move N# Signature Help To Full Compiler Semantics

Priority: P1 IDE tooling.

Work in the N# repository and make signature help use compiler semantics for N# declarations with the same rigor as reflection-backed calls. Signature help is stronger for .NET calls than for user-authored N# functions and methods.

## Scope

- Audit `SignatureHelpHandler` and any helper code that builds signatures from AST or partial semantic data.
- Support N# functions, methods, constructors, overloads, generics, defaults, `params`, `ref`, `out`, and extension methods.
- Ensure active parameter selection is correct for nested calls, named arguments, generic type arguments, and defaulted arguments.
- Keep signature help results aligned with analyzer overload resolution.

## Likely Files

- `src/NSharpLang.LanguageServer/Handlers/SignatureHelpHandler.cs`
- `src/NSharpLang.Compiler/CodeIntelligence`
- `src/NSharpLang.Compiler/Analyzer.cs`
- `tests/LanguageServerTests.cs`
- `tests/AnalyzerTests.cs`

## Acceptance

- Signature help works for N# functions, methods, constructors, overloads, generics, defaults, `params`, `ref`, `out`, and extension methods.
- Active parameter selection is correct for nested calls and named arguments.
- LSP tests cover representative N# and .NET calls.
- Signature help agrees with analyzer-selected overloads.

## Verification

- Run focused LanguageServer signature help tests while developing.
- Run `./scripts/test-all.sh` before committing.
- Run `./scripts/reload-vscode-extension.sh` and visually verify signature help in real VS Code.
