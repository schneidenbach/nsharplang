# What's Next for N#

**Last updated:** 2026-03-26
**Goal:** Go- and Rust-grade tooling for humans in VS Code and for LLMs driving the CLI.

This is the single source of truth for active work. It replaces `tasks/current_issues.md`, `tasks/codex_session_1.md`, and `tasks/codex_session_2.md`.

---

## Product Bar

N# should feel like:
- `go` and `cargo` on the command line: stable, boring, predictable, scriptable
- `gopls` and `rust-analyzer` in the editor: semantic, fast, and trustworthy
- an LLM-first toolchain: one command should return exactly the right semantic answer, in stable JSON, with no guesswork

The highest risk is not missing features. It is **wrong answers**:
- wrong overload selected
- wrong type inferred
- wrong reference set
- wrong completion set
- stale docs claiming features are done when they are not

---

## P0: Semantic Correctness

These block both VS Code and LLM reliability.

### 1. Type-based overload resolution
- Current: overloads are still effectively chosen by arity in key paths.
- Impact: wrong .NET method, wrong hover, wrong completion details, wrong docs.
- Priority: highest. This is the floor for BCL interop.

### 2. Generic type inference
- Current: generic calls still need too many explicit type arguments.
- Impact: LINQ and normal .NET APIs stay clumsy or semantically wrong.
- Priority: highest. This unblocks most “real code” usability.

### 3. Lambda contextual typing
- Current: lambda parameters still degrade to `Unknown` too often.
- Impact: breaks LINQ, delegates, event handlers, callback-heavy code.
- Priority: highest. Ship non-generic delegate inference early if needed.

### 4. LINQ return-type construction
- Current: common LINQ methods can still surface element types or unbound generics instead of the constructed return type.
- Impact: hover, type queries, signature help, and completions are misleading.
- Priority: high, but downstream of generic inference unless a targeted heuristic lands first.

### 5. Pattern exhaustiveness with guards
- Current: guarded match arms can suppress exhaustiveness checking.
- Impact: false negatives in `nlc check` and `nlc query diagnostics`.
- Priority: high correctness fix, independent.

### 6. Error recovery / multi-error reporting
- Current: parser recovery still misses chances to report multiple useful errors in one pass.
- Impact: bad LLM loops and worse human iteration.
- Priority: high. This is a workflow multiplier.

---

## P1: Shared Semantic Substrate

These are the engine issues that decide whether CLI and LSP can be truly semantic.

### 7. BindingMap coverage expansion
- Current: BindingMap works for many cases, but not enough to trust it everywhere.
- Missing coverage: interpolation, more member-access chains, imported-symbol usages, declaration/type-reference paths.
- Impact: references/rename/definition still need fallback paths or stay partially semantic.

### 8. SemanticModel completeness
- Current: completions and some queries still fall back to AST or incomplete semantic recording.
- Missing: fields, properties, better local-variable typing, shadowing-aware lookup, position-aware scope.
- Impact: completions are not yet “editor-trustworthy.”

### 9. Cross-file semantic navigation in LSP
- Current: CLI has moved further than the LSP on true semantic navigation.
- Needed: Definition/References handlers should consume the same semantic engine and stop depending on text-search-style behavior.

### 10. Circular import detection
- Current: circular imports still fail badly or opaquely.
- Impact: multi-file projects can become brittle and confusing.

---

## P2: VS Code Product Gaps

These are the biggest remaining gaps between “CLI is strong” and “editor is first-class.”

### 11. Auto-import on completion
- Current: completion can surface a symbol without making it easy to accept and import it.
- Needed: `additionalTextEdits` on completion items, like good TS/C#/Rust tooling.

### 12. Workspace-wide diagnostics
- Current: diagnostics are still too tied to open documents.
- Needed: project/workspace analysis on open and on change, not just file-local behavior.

### 13. N# signature help
- Current: signature help is much better for .NET/reflection-backed calls than for user-defined N# functions.
- Needed: parity for N# declarations, overloads, and generic signatures.

### 14. Document symbols / outline in LSP
- Current: CLI outline is strong; editor outline support is still lagging.
- Needed: proper `DocumentSymbolHandler` so the VS Code outline panel works like a real language.

### 15. Inlay hints
- Current: no first-class type-inference hints.
- Needed: ghost-text type hints after `:=`, parameter hints where useful, in a minimal style.

### 16. Snippet completions
- Current: completions are semantic-heavy but not yet polished for writing flow.
- Needed: `func`, `if`, `match`, test patterns, etc.

### 17. Interpolation syntax highlighting
- Current: interpolation highlighting is still called out as incomplete.
- Needed: nested interpolation grammar that highlights expressions, not just string bodies.
- Important: must be visually verified in real VS Code, not just grammar-edited.

### 18. Visual verification discipline
- Current: there are active language-server changes in the worktree, but the mandatory reload/reinstall/real-editor verification loop is easy to drift from.
- Rule: no LSP or VS Code work should be considered done until it is visually verified after `./scripts/reload-vscode-extension.sh`.

---

## P3: LLM-First CLI Polish

The CLI is much stronger now, but a few high-value items remain.

### 19. Keep the JSON contract authoritative
- Current: `memory/components/cli-toolchain.md` is the intended contract doc, but other docs drift.
- Needed: treat `cli-toolchain.md` as canonical and update it immediately with every CLI contract change.

### 20. Unify docs and task truth
- Current: docs disagree.
  - `tasks/current_issues.md` had stale claims about CLI feature status.
  - `docs/GAPS.md` understates real semantic/tooling gaps.
  - some task/session files described one-off local work instead of stable roadmap items.
- Needed: one roadmap, one CLI contract doc, less narrative drift.

### 21. `nlc format` audit
- Goal: one opinionated style, no bikeshedding, Go-grade formatting confidence.
- Needed: explicit audit of formatter output over all examples and common code patterns.

### 22. `nlc fix` growth
- Current: useful, but still narrow.
- Next: more fix providers, stronger text/json parity, more machine-drivable edits.

### 23. CLI/install ergonomics
- Current: much better than before, but local tool deployment and editor deployment should feel like one supported path, not a pile of ad hoc scripts.
- Decide what to do with `scripts/deploy-local-toolset.sh`.

---

## P4: Language / Ecosystem Gaps

These matter, but they are not above the tooling foundation.

### 24. Extension methods on literals
- `5.Times(...)` should work.

### 25. Implicit symbol/module discovery
- Reduce import boilerplate in multi-file projects.

### 26. Parameter attributes
- Nice to have; workaround exists.

### 27. Null-forgiving operator
- Low priority; workaround exists.

### 28. Better nested union matching
- Improves expressiveness, but not above tooling correctness.

### 29. Source maps / debugging
- Important long-term, but below semantic correctness and editor trust.

### 30. REPL / doc generation
- Ecosystem-level polish, not near-term blockers.

---

## Immediate Local Housekeeping

These are real, current repository-state issues and should not get lost.

### A. Commit or drop the current `print` sweep + lexer fix cleanly
- Current local state includes:
  - example updates to bare `print ...`
  - lexer fix for interpolated strings with nested string literals, such as `print $"  Tags: {String.Join(", ", task.Tags)}"`
  - regression tests
- Status: verified with full suite passing.
- Action: isolate and commit cleanly.

### B. Resolve the example-tree reshuffle
- Current local state includes deleted `examples/11-advanced-features/*.nl` files and untracked replacement directories.
- Action: decide whether this is the intended new layout, then commit it as its own change.

### C. Resolve unrelated dirty compiler/LSP work before mixing more features
- Dirty compiler files:
  - `src/NSharpLang.Compiler/Analyzer.cs`
  - `src/NSharpLang.Compiler/MultiFileCompiler.cs`
  - `src/NSharpLang.Compiler/Transpiler.cs`
  - `tests/AnalyzerTests.cs`
  - `tests/TranspilerTests.cs`
- Dirty LSP/editor files:
  - `src/NSharpLang.LanguageServer/Handlers/CompletionHandler.cs`
  - `src/NSharpLang.LanguageServer/Handlers/DefinitionHandler.cs`
  - `src/NSharpLang.LanguageServer/Handlers/RenameHandler.cs`
  - `src/NSharpLang.LanguageServer/Services/DocumentManager.cs`
  - `src/NSharpLang.LanguageServer/Services/TypeResolver.cs`
  - `tests/LanguageServerTests.cs`
  - `editors/vscode/BUILD.md`
- Action: sort, review, and avoid letting them silently piggyback on unrelated commits.

### D. Decide what to do with deployment/test scripts
- `scripts/test-all.sh` is locally modified.
- `scripts/deploy-local-toolset.sh` is untracked.
- Action: either promote them intentionally or keep them out of unrelated work.

---

## Recommended Attack Order

1. Type-based overload resolution
2. Generic type inference
3. Lambda contextual typing
4. BindingMap + SemanticModel coverage expansion
5. LSP semantic references/definition parity
6. Error recovery / multi-error reporting
7. Auto-import completion + workspace diagnostics
8. N# signature help + document symbols + inlay hints
9. Interpolation highlighting + real VS Code visual verification
10. Formatter/fix/install polish

---

## Source of Truth Rules

- `tasks/NEXT.md` is the only roadmap file.
- `memory/components/cli-toolchain.md` is the canonical CLI contract document.
- Do not create new session-note task files in `tasks/`.
- If editor behavior changes, verify it in real VS Code before marking it done.

---

## Archived / Done Enough To Stop Tracking Here

- CLI query/doc, inspect, inspect-summary, and batch command landed.
- `nlc check` / `nlc fix` contract hardening landed.
- daemon-backed CLI query reuse landed.
- import validation and import-completion correctness work landed.
- full-test-suite hang work was resolved.

Only put something back above if it regresses or turns out not to be product-grade.
