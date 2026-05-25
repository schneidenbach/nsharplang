# What's Next for N#

**Goal:** Go- and Rust-grade tooling for humans in VS Code and for LLMs driving the CLI.

---

## Current State (2026-03-27)

Recently landed:
- reflection-backed call binding is no longer pure arity matching in the main analyzer path
- generic LINQ chains and contextual lambda typing are materially better in common cases
- parser recovery now reports multiple useful errors more often instead of bailing early
- auto-import completion and project-scope diagnostics landed in the language server
- BindingMap now covers more real semantic uses: bare interpolation identifiers, more member-access paths, and imported member declarations
- LSP definition/rename now prefer synchronized project-semantic results instead of dropping to text/name heuristics when a semantic snapshot exists
- SemanticModel now records expression types by source position, not just flat name-to-type maps

Still the key remaining gap:
- `TypeReference` nodes do not carry source positions yet, so semantic definition/reference coverage for type annotations and generic type arguments is still incomplete

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
- Current: the main reflection-backed call path now does real candidate binding, but overload scoring/conversions are not complete enough to call this done.
- Impact: wrong .NET method, wrong hover, wrong completion details, wrong docs.
- Priority: highest. This is the floor for BCL interop.

### 2. Generic type inference
- Current: much better for common LINQ-style calls, still incomplete for broader generic APIs and edge cases.
- Impact: LINQ and normal .NET APIs stay clumsy or semantically wrong.
- Priority: highest. This unblocks most “real code” usability.

### 3. Lambda contextual typing
- Current: contextual delegate typing now works in common call paths, but still needs broader coverage and cleanup.
- Impact: breaks LINQ, delegates, event handlers, callback-heavy code.
- Priority: highest. Ship non-generic delegate inference early if needed.

### 4. LINQ return-type construction
- Current: common `Where/Select/ToList`-style chains are much better, but this still rides on incomplete generic/call semantics.
- Impact: hover, type queries, signature help, and completions are misleading.
- Priority: high, but downstream of generic inference unless a targeted heuristic lands first.

### 5. Pattern exhaustiveness with guards ✅ DONE
- Fixed: guarded arms no longer count toward coverage; unguarded arms and catch-all bindings still do.
- Remaining: guard condition semantic analysis not implemented (e.g., `when x > 0` + `when x <= 0` = full coverage).

### 6. Error recovery / multi-error reporting
- Current: recent parser recovery work improved several no-progress/error-cascade cases, but this still needs another pass.
- Impact: bad LLM loops and worse human iteration.
- Priority: high. This is a workflow multiplier.

---

## P1: Shared Semantic Substrate

These are the engine issues that decide whether CLI and LSP can be truly semantic.

### 7. BindingMap coverage expansion
- Current: BindingMap now covers more interpolation/member/imported-member cases, but not enough to trust it everywhere.
- Missing coverage: complex interpolation expressions, more declaration paths, and especially type-reference paths.
- Impact: references/rename/definition still need fallback paths or stay partially semantic.

### 8. SemanticModel completeness
- Current: SemanticModel now has expression-type-by-position recording, but the core identifier model is still too flat.
- Missing: better shadowing-aware lookup, richer local scope/position queries, and fewer AST fallbacks in completions/query helpers.
- Impact: completions are not yet “editor-trustworthy.”

### 9. Cross-file semantic navigation in LSP
- Current: Definition and Rename now prefer project-semantic results when a synchronized snapshot exists.
- Remaining: References parity is still incomplete, and type-use-site navigation is still limited by missing `TypeReference` positions.

### 10. Circular import detection
- Current: circular imports still fail badly or opaquely.
- Impact: multi-file projects can become brittle and confusing.

---

## P2: VS Code Product Gaps

These are the biggest remaining gaps between “CLI is strong” and “editor is first-class.”

### 11. Auto-import on completion
- Current: first-pass auto-import completion landed with `additionalTextEdits`.
- Remaining: ranking/polish and wider symbol coverage.

### 12. Workspace-wide diagnostics
- Current: first-pass project-scope diagnostics publication landed for synchronized open files.
- Remaining: broaden coverage and harden the scheduling/update behavior.

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
- Local deployment now lives behind `scripts/setup-local.sh`; shared toolset publish/install logic is in `scripts/lib/toolset.sh`.

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

### 29. REPL / doc generation
- Ecosystem-level polish, not near-term blockers.

---

## Recommended Attack Order

1. Finish overload resolution + generic inference + lambda contextual typing edge cases
2. Add source positions to `TypeReference` nodes and record semantic bindings for type-use sites
3. Finish LSP semantic references parity on top of the stronger BindingMap/SemanticModel data
4. Do the next parser error-recovery / multi-error reporting pass
5. Move N# signature help fully onto compiler semantics
6. Polish auto-import completion + workspace diagnostics behavior
7. Document symbols + inlay hints
8. Interpolation highlighting + real VS Code visual verification
9. Formatter/fix/install polish

---

## Source of Truth Rules

- `memory/components/cli-toolchain.md` is the canonical CLI contract document.
- Do not create new session-note task files in `tasks/`.
- If editor behavior changes, verify it in real VS Code before marking it done.

---

## Archived / Done Enough To Stop Tracking Here

- CLI query/doc, inspect, inspect-summary, and batch command landed.
- `nlc check` / `nlc fix` contract hardening landed.
- daemon-backed CLI query reuse landed.
- import validation and import-completion correctness work landed.
- first-pass auto-import completion landed.
- first-pass project-scope workspace diagnostics landed.
- full-test-suite hang work was resolved.

- Source maps / debugging -- complete. Zero-config F5 debugging with `#line` directives and PDB mapping.

Only put something back above if it regresses or turns out not to be product-grade.
