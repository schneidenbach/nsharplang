# Current Issues & Roadmap

Updated: 2026-03-25

## What Exists Today

### CLI Toolchain (LLM-first)
- `nlc check` — fast type-check without codegen (like `cargo check`)
- `nlc fix` — auto-apply compiler suggestions (like `cargo clippy --fix`)
- `nlc query symbols` — list all symbols in project/file
- `nlc query outline` — file structure with imports and declarations
- `nlc query diagnostics` — Elm-level rich errors (JSON + text)
- `nlc query type` — type info at position
- `nlc query definition` — go-to-def (position-based + name search)
- `nlc query references` — find all references (semantic via BindingMap + text fallback)
- `nlc query completions` — LLM-optimized completions (member access + identifier)
- `nlc daemon` — background analysis server (Unix socket, auto-start, 30min idle timeout)
- `nlc format` — code formatter
- `nlc lint` — static analysis
- All query commands output versioned JSON (schemaVersion: 1) by default

### IDE Tooling (VS Code)
- CompletionHandler — AST-based member completion, namespace completion, trigger character
- HoverHandler — type info on hover
- DefinitionHandler — go-to-definition (F12)
- RenameHandler — rename symbol (F2) with interpolation awareness
- SignatureHelpHandler — parameter info for .NET types
- CodeActionHandler — quick fixes (add import, remove unused var)
- TextDocumentHandler — diagnostics with correct squiggly width/position

### Compiler Infrastructure
- BindingMap — semantic symbol resolution (declaration → usages)
- CodeFixService — 3 providers (NL002 missing import, NL001 unused var, NL003 null check stub)
- CodeIntelligenceService — shared engine for CLI and (eventually) LSP
- CompletionEngine — LLM-optimized completions with AST field resolution
- OutputFormatter — JSON (versioned envelope) + Elm-style text

## Remaining IDE Tooling Tasks

### Tier 1 — Must Have

| # | Task | Status | Notes |
|---|------|--------|-------|
| 10 | Auto-import on completion | pending | Select `Console` without `import System` → auto-add import via `additionalTextEdits` on CompletionItem |
| 11 | Find All References (LSP) | **partially done** | BindingMap exists for semantic resolution. Need ReferencesHandler in LSP to expose via Shift+F12 |
| 12 | Cross-file go-to-definition (LSP) | **partially done** | CLI `nlc query def` works cross-file. LSP DefinitionHandler needs to use CodeIntelligenceService for cross-file |
| 13 | Workspace-wide diagnostics | pending | Analyze all .nl files on workspace open, not just open files |

### Tier 2 — Important

| # | Task | Status | Notes |
|---|------|--------|-------|
| 14 | N# function signature help | pending | SignatureHelpHandler only works for .NET types. Should show hints for user-defined N# functions |
| 15 | Quick fix: add missing import | **done (CLI)** | `nlc fix` handles NL002. LSP CodeActionHandler already wired. |
| 16 | Document symbols / Outline (LSP) | **done (CLI)** | `nlc query outline` works. Need DocumentSymbolHandler in LSP for Outline panel |
| 17 | Inlay hints for type inference | pending | Show `: string` as ghost text after `:=`. Killer feature for inference language |
| 18 | Snippet completions | pending | `func` → template, `if` → if block, `match` → match expression |

### Tier 3 — LLM Toolchain Polish

| # | Task | Status | Notes |
|---|------|--------|-------|
| 19 | `nlc query doc` | pending | API documentation from CLI. `nlc query doc Console.WriteLine` → signature + XML doc. XmlDocReader exists in LSP |
| 20 | Audit `nlc format` | pending | Ensure fully opinionated, zero config. N# should have ONE canonical style like Go |
| 21 | SemanticModel field/property recording | pending | Analyzer doesn't call RecordField/RecordProperty — completions use AST fallback. Fix would improve type queries too |
| 22 | BindingMap for cross-file type references | pending | Import resolution path doesn't record bindings. References falls back to text search for cross-file |

### Bonus
- Add DocumentSelector to ALL LSP handler registration options (hover, definition, rename, etc.)
- Daemon: file watching for automatic cache invalidation
- `nlc fix` additional providers: add missing function return type, fix type mismatches, etc.

## Known Limitations

### Semantic Resolution
- **FindReferences** uses BindingMap for local references but falls back to text search for cross-file type references (imports don't record bindings)
- **SemanticModel** is flat and not position-aware — can't distinguish shadowed variables. Fields/properties not recorded
- **Definition** at a position extracts the name then does a name search across all files — not true semantic resolution for overloads/shadowing
- **Type queries** on member access (`person.Name`) ignore the receiver type — look up `Name` globally

### Completions
- Member access works for .NET types (via reflection) and N# type fields (via AST fallback)
- Doesn't resolve local variable types from `:=` inference — only fields with explicit type annotations
- No extension method completions (LINQ methods on collections)

## Test Status
- **944+ tests passing, 0 failures, 3 skipped**
- Integration tests use real example projects (01-hello-world, 06-classes-and-records, 12-multi-file-projects, 05-unions)
- Tests cover: lexer, parser, analyzer, transpiler, integration, LSP handlers, CodeIntelligence (symbols, outline, diagnostics, definition, references, completions, BindingMap), OutputFormatter, CodeFix
