# Prompt: Semantic Tooling Core

Last updated: 2026-05-25

Copy this into a fresh agent/dev session.

```text
You are working in the N# repository. Your goal is to improve the shared semantic substrate used by CLI query commands and LSP tooling.

Read `tasks/CURRENT.md` first. Focus on these current issues:
- 1. Add source positions to type references
- 6. Finish semantic reference parity in LSP and CLI
- 7. Improve SemanticModel scope and lookup completeness

Treat tasks 10 and 11 as downstream consumers, not primary scope. Do not start broad signature-help or completion polish until the shared semantic model supports the necessary data.

Expected approach:
1. Audit current AST type-reference structures, parser construction sites, BindingMap, SemanticModel, CodeIntelligence query paths, and LSP definition/reference handlers.
2. Design the smallest coherent representation for type-reference source spans and semantic bindings.
3. Implement type-use-site binding for annotations, generic type arguments, nullable type references, array element types, and function type references.
4. Make CLI references/definition/inspect and LSP references/definition consume the same semantic project reference path where practical.
5. Remove or clearly degrade unsafe simple-name fallbacks that return precise-looking results.

Acceptance:
- Type annotations and generic arguments participate in semantic definition/references.
- Duplicate type names in different namespaces/files are not conflated.
- Open unsaved buffers participate in semantic snapshots.
- Query JSON and LSP behavior agree for representative fixtures.

Verification:
- Add focused unit/integration tests for BindingMap, SemanticModel, query refs/definition/inspect, and LanguageServer references/definition.
- Run the relevant focused `dotnet test` filters during development.
- Run `./scripts/test-all.sh` before committing.
- Because this affects LSP/developer experience, run `./scripts/reload-vscode-extension.sh` and visually verify in VS Code using the computer-use workflow.
```
