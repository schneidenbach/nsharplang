# Current Issues & IDE Tooling Roadmap

Updated: 2026-03-24 after major IDE tooling session.

## What Was Done This Session (10 commits)

### Commits (oldest to newest)
1. **LSP improvements: rename, completions, diagnostics** — RenameHandler (F2), parameter tracking for go-to-def, squiggly width fix, array/nullable type resolution, semantic model variables in completions
2. **Fix squiggly width for linter diagnostics, detect undeclared vars in interpolation** — Linter squiggly uses actual symbol length; analyzer catches `$"Hello, {me}!"` when `me` is undeclared (NL301)
3. **Fix linter squiggly position by finding symbol in source line** — Searches source text for actual identifier position instead of trusting linter's column offset
4. **AST-based member completion with static/instance filtering and N# type support** — Rewrote CompletionHandler to use AstNodeFinder + ExpressionTypeResolver (like HoverHandler); handles .NET types via reflection AND N# types via SymbolsInfo; adds MemberAccessMode enum
5. **Remove temporary debug logging**
6. **Add namespace completion (System. -> Console, Math, Collections, etc.)** — GetTypesInNamespace, GetSubNamespaces, IsKnownNamespace with WellKnownNamespaces hashset
7. **Add mandatory IDE verification and Codex review requirements to CLAUDE.md**
8. **Fix completion race condition: use trigger character instead of text scanning** — `request.Context?.TriggerCharacter == "."` as primary signal; fallback handles missing dot in buffer
9. **Fix namespace completion: dedup generics, use well-known namespace list** — Dedup on cleaned name (Action`1 -> Action before seen.Add); WellKnownNamespaces for fast namespace detection
10. **Fix Codex review issues: symbol priority, namespace gating, type caching** — Moved namespace after symbol resolution; gated with IsKnownNamespace; added GetOrCacheExportedTypes; added DocumentSelector for completion registration

### Key Architecture Decisions
- **Trigger character over text scanning**: The dot trigger character (`request.Context?.TriggerCharacter`) is the reliable signal for member completion. Document text may not have the dot yet due to race condition between `didChange` and `completion` requests.
- **DocumentSelector required**: `CompletionRegistrationOptions` MUST set `DocumentSelector = new TextDocumentSelector(new TextDocumentFilter { Language = "nsharp" })` or VS Code won't forward completion requests. Other handlers (hover, definition, etc.) should also set this — currently they don't but work via fallback behavior.
- **AST-based completion (primary) + text fallback**: Primary path uses AstNodeFinder + ExpressionTypeResolver like HoverHandler. Falls back to text-based identifier extraction when AST is broken.
- **Symbol priority > namespace**: Real symbols in scope (variables, types) checked before namespace completion. Codex review identified this as a correctness issue.

### Skills Created
- **`~/.claude/skills/computer-use/`** — macOS GUI automation via screencapture + osascript. Includes VS Code shortcuts reference. Used for mandatory IDE verification.

## Remaining IDE Tooling Tasks

### Tier 1 — Must Have

| # | Task | Status | Notes |
|---|------|--------|-------|
| 10 | Auto-import on completion | pending | Select `Console` without `import System` -> auto-add import. Needs `additionalTextEdits` on CompletionItem |
| 11 | Find All References | pending | Implement ReferencesHandler. Reuse FindAllReferences from DocumentManager, extend across open documents. Shift+F12 |
| 12 | Cross-file go-to-definition | pending | F12 on type defined in another file should jump there. Need to track symbols across all open documents |
| 13 | Workspace-wide diagnostics | pending | Analyze all .nl files on workspace open, not just open files |

### Tier 2 — Important

| # | Task | Status | Notes |
|---|------|--------|-------|
| 14 | N# function signature help | pending | SignatureHelpHandler only works for .NET types. Should show hints for user-defined functions from SymbolsInfo |
| 15 | Quick fix: add missing import | pending | Lightbulb on undeclared identifier -> "Add import System" |
| 16 | Document symbols / Outline | pending | Implement DocumentSymbolHandler to populate Outline panel and breadcrumbs. Walk AST. Easy win |
| 17 | Inlay hints for type inference | pending | Show `: string` as ghost text after `:=`. Killer feature for inference language |
| 18 | Snippet completions | pending | `func` -> template, `if` -> if block, `match` -> match expression |

### Bonus (not yet tracked)
- Add DocumentSelector to ALL handler registration options (hover, definition, rename, etc.) — currently only CompletionHandler has it
- Fix duplicate comment block in CompletionHandler.cs line 57-62 (two comment blocks about trigger character)
- Consider caching namespace completion results (currently regenerated each request)

## Known Bugs

### 1. Completion works inconsistently in VS Code
**Root cause**: Mostly resolved. Was caused by:
- Restricted Mode blocking extension activation (fixed: disabled workspace trust globally)
- Race condition between didChange and completion (fixed: use trigger character)
- Missing DocumentSelector in CompletionRegistrationOptions (fixed: added Language="nsharp")
- Cursor positioning issues with osascript automation (not a real bug, just testing artifact)

**Still may occur if**: workspace is opened as single file (not folder), or extension hasn't fully initialized yet.

### 2. Namespace completion fallback shows wrong items
**Root cause**: Fixed. Was caused by `IsKnownNamespace` only checking `_exportedTypesCache` which didn't include CoreLib. Added WellKnownNamespaces hashset for instant lookup.

### 3. Generic type duplicates in namespace completion
**Root cause**: Fixed. `Action`1`, `Action`2` etc. were deduplicated by raw name (with backtick) instead of cleaned name. Now deduplicates AFTER stripping backtick+arity.

## Codex Review Findings (Addressed)

All three warnings from Codex adversarial code review were fixed:
1. **Symbol priority over namespace** — namespace completion moved after semantic model/type resolution
2. **Namespace probing gated** — AST path checks `IsKnownNamespace()` before `GetTypesInNamespace()`
3. **Exported types cached** — `GetOrCacheExportedTypes()` stores results in `_exportedTypesCache`

## Files Modified This Session

### Language Server
- `src/NSharpLang.LanguageServer/Handlers/CompletionHandler.cs` — Major rewrite: AST-based member completion, namespace completion, trigger character fix, DocumentSelector
- `src/NSharpLang.LanguageServer/Handlers/TextDocumentHandler.cs` — Squiggly width fix (token length), linter position fix (source search)
- `src/NSharpLang.LanguageServer/Handlers/RenameHandler.cs` — **New file**: F2 rename with interpolation-aware FindAllReferences
- `src/NSharpLang.LanguageServer/Services/DocumentManager.cs` — FindAllReferences, IsInsideStringOrComment (interpolation), parameter/catch var tracking
- `src/NSharpLang.LanguageServer/Services/TypeResolver.cs` — Array/nullable type resolution, MemberAccessMode, GetTypesInNamespace, IsKnownNamespace, GetOrCacheExportedTypes
- `src/NSharpLang.LanguageServer/Program.cs` — Registered RenameHandler

### Compiler
- `src/NSharpLang.Compiler/Analyzer.cs` — Undeclared identifier detection in string interpolation expressions

### Tests
- `tests/LanguageServerTests.cs` — FindAllReferences tests (interpolation, regular strings), member completion tests (string, Console, N# class), namespace completion test

### Config
- `CLAUDE.md` — Added Codex review requirements, IDE verification requirements
- `~/.claude/skills/computer-use/SKILL.md` — Computer use skill for GUI automation

## Test Status
- **882 tests passing, 0 failures, 3 skipped**
- Tests cover: lexer, parser, analyzer, transpiler, integration, LSP handlers, FindAllReferences, member completion, namespace completion
