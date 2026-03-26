# What's Next for N#

**Last updated:** 2026-03-26
**Test count:** 944+ tests, 0 failures, 0 warnings

This document consolidates all open task files, known limitations, and gaps into a single prioritized roadmap. It replaces the individual task files (`031`–`036`) which have been archived or removed.

---

## Completed (Archived)

These tasks are done and no longer tracked here:

| Task | What | Status |
|------|------|--------|
| 031 | Linter false-positive: `PushScope`/`PopScope` copied parent variables, causing "unused variable" on foreach targets | **Fixed** — scopes now only track own declarations |
| 034 | Full test suite hang during xUnit discovery | **Resolved** — `dotnet test` completes normally as of 2026-03-26; `test-all.sh` no longer uses category filters |
| 035 | Production-readiness: lazy test fixtures, 50+ error-handling tests, zero build warnings | **Done** |
| 036 | Zero warnings across Compiler, LanguageServer, CLI, Tests | **Done** |

---

## Open Work — Prioritized

### P0: Semantic Correctness (blocks LLM toolchain accuracy)

These are the foundation. `nlc query` returns wrong answers without them.

#### 1. Type-based overload resolution
- **Current:** Method overloads resolved by argument *count* only, not by type. `Analyzer.cs:2127-2130` picks the first method matching parameter count. `ExpressionTypeResolver.cs:62` returns the first overload unconditionally.
- **Impact:** Any .NET API with same-arity overloads (most of BCL) resolves to the wrong method. `Console.WriteLine(int)` vs `Console.WriteLine(string)` — wrong hover, wrong completions.
- **Files:** `Analyzer.cs` (method resolution ~line 2124), `ExpressionTypeResolver.cs` (~line 56-63)
- **Reference:** Roslyn `OverloadResolution.cs`

#### 2. Generic type inference
- **Current:** Generic type parameters must always be explicit: `Identity<int>(42)`.
- **Impact:** LINQ is nearly unusable without this — every `Select`, `Where`, `GroupBy` requires explicit type args.
- **Files:** `Analyzer.cs`, `ExpressionTypeResolver.cs`
- **Reference:** Roslyn `MethodTypeInference.cs`, C# Spec §7.5.2

#### 3. Lambda parameter type inference from context
- **Current:** Lambda params typed as `Unknown` without explicit annotations. `items.Where(x => x > 5)` has `x` as `Unknown`. Confirmed: `Analyzer.cs` has ~20 fallback sites returning `BuiltInTypes.Unknown`.
- **Impact:** LINQ, callbacks, event handlers — anything taking a lambda — has broken type info.
- **Files:** `Analyzer.cs` (call-site analysis), `ExpressionTypeResolver.cs`
- **Depends on:** #2 for the general case (generic method signatures). However, a **useful subset can ship independently**: inferring types from non-generic delegate parameters (`Action<int>`, `Func<string, bool>` with known type args). Note this in implementation.

### P1: LLM Experience (wrong/missing info shown to LLM consumers)

#### 4. LINQ hover shows element type instead of collection type (was Task 033)
- **Current:** Hovering over `.Select()` shows `int` instead of `IEnumerable<int>`. `.ToList()` shows `int` instead of `List<int>`.
- **Root cause:** `ExpressionTypeResolver.ResolveCallType()` at ~line 120 returns `method.ReturnType` which is the unbound generic return type. Need to detect `IsGenericMethodDefinition`, infer type args from receiver's `IEnumerable<T>`, and call `MakeGenericMethod()`.
- **Implementation sketch:** Add `TryConstructGenericMethod()` that extracts element type via `TryGetEnumerableElementType()` (check `IsArray` → `GetElementType()`, then `IEnumerable<>` interface). For `Select` with 2 type params, infer `TResult` from lambda or default to element type.
- **Files:** `ExpressionTypeResolver.cs`
- **Depends on:** Partially blocked by #2, but a simplified heuristic for common LINQ methods (Select, Where, ToList, ToArray, OrderBy, First, FirstOrDefault, Count) can ship independently.
- **Test cases:** Hover tests for Select → `IEnumerable<int>`, ToList → `List<int>`, Where → `IEnumerable<int>`, ToArray → `int[]`.

#### 5. BindingMap coverage expansion
- **Current:** BindingMap exists and works for basic identifier resolution (`BindingMap.cs`, wired into `Analyzer`, `MultiFileCompiler`, `CodeIntelligenceService`, `DocumentManager`). Cross-file merge is implemented. Integration tests pass (`BindingMap_MultiFile_HasCrossFileBindings`). CLI `nlc query refs` uses it for semantic references.
- **Gap:** BindingMap doesn't cover all expression paths (string interpolation, complex member access chains). LSP `FindAllReferences` still uses text search because of these gaps. Imported types from other files may not be fully recorded.
- **Work remaining:** Expand Analyzer binding recording to cover interpolation expressions, member access chains, type references in declarations, and imported symbol usages. Then switch LSP FindAllReferences from text search to BindingMap.
- **Files:** `Analyzer.cs` (binding recording sites), `BindingMap.cs`, `DocumentManager.cs:219-228`

#### 6. Completions fall back to AST instead of SemanticModel
- **Current:** SemanticModel doesn't record fields/properties. CompletionEngine uses AST fallback.
- **Impact:** Completions are syntactic, not semantic — wrong results after shadowing, scoping, type narrowing.
- **Related:** Position-aware SemanticModel (for scope-correct lookups) is also needed.
- **Files:** `Analyzer.cs` (SemanticModel recording), `CompletionEngine.cs`

#### 7. Circular import detection
- **Current:** No detection. `A imports B, B imports A` causes silent failure or infinite loop.
- **Impact:** Multi-file projects can break silently.
- **Files:** `MultiFileCompiler.cs`

#### 8. Pattern exhaustiveness with guards
- **Current:** Exhaustiveness checking is skipped entirely when guards are present. A match expression with only guarded arms and no wildcard produces no warning.
- **Impact:** `nlc query diagnostics` and `nlc check` emit false negatives — silent correctness bugs in user code.
- **Files:** `Analyzer.cs` (pattern exhaustiveness checking)

### P2: IDE & Developer Experience

#### 9. String interpolation syntax highlighting (was Task 032)
- **Current:** Variables inside `$"Hello, {name}!"` are highlighted as string, not as variables.
- **Fix:** Add nested `meta.interpolation.nsharp` pattern to the TextMate grammar. Structure: `begin: "\\{"`, `end: "\\}"`, with `beginCaptures`/`endCaptures` as `punctuation.definition.interpolation.{begin,end}.nsharp`, and `patterns: [{ "include": "#expressions" }]` inside. Also add escape sequence pattern `\\\\[\\\\\"'nrt]` as sibling.
- **Files:** `editors/vscode/syntaxes/nsharp.tmLanguage.json`
- **Reference:** C# TextMate grammar nested interpolation patterns.
- **Test checklist:** Variables inside `{...}` highlighted as variables; method calls highlighted; string parts remain string-colored; escaped braces `{{` not treated as interpolation.
- **Testing:** Must verify in VS Code visually (not just unit tests).

#### 10. Error recovery — multiple errors per file
- **Current:** Parser stops at first error in some cases.
- **Impact:** For LLMs consuming `nlc query diagnostics`, getting only the first error means multiple round-trips to discover all issues. This is a significant workflow penalty for automated coding loops.
- **Reference:** Roslyn's error recovery and synchronization points.

#### 11. Source maps for N# debugging
- **Current:** Debugging uses generated C#, not N# source.
- **Impact:** Developers can't set breakpoints in `.nl` files.

### P3: Language Gaps

#### 12. Extension methods on literals
- **Current:** `5.Times(...)` doesn't work. Must assign to variable first.
- **Files:** `Analyzer.cs` (member access resolution for literal expressions)

#### 13. Implicit symbol resolution from namespace
- **Current:** Requires explicit file imports (`import "Models/Person"`). No auto-discovery from project namespace.
- **Impact:** Boilerplate for multi-file projects. Go auto-discovers from package; Rust uses `mod`.
- **Files:** `MultiFileCompiler.cs`

#### 14. Parameter attributes
- **Current:** `func Create([FromBody] dto: TaskDto)` not supported.
- **Workaround:** ASP.NET Core infers `[FromBody]` for complex types.
- **Priority:** Low — workaround covers most cases.

#### 15. Null-forgiving operator (`!`)
- **Current:** `name!.Length` not supported. Parser doesn't recognize `!` as postfix operator.
- **Workaround:** `(name ?? "").Length` or explicit null check.
- **Priority:** Low.

#### 16. Nested union pattern matching
- **Current:** Deep matching on `Result<T>` containing `Error` union cases is limited.

### P4: Ecosystem

#### 17. REPL (`nlc repl`)
- **Current:** No interactive shell.

#### 18. API documentation generator
- **Current:** `nlc query` provides structured symbol info, but no standalone doc generator.

---

## Dependency Graph

```
#2 Generic type inference
  ← #3 Lambda context inference (needs generic signatures for full version;
       subset for non-generic delegates can ship independently)
  ← #4 LINQ hover (needs constructed generic methods;
       heuristic for common methods can ship independently)
  ← #6 Semantic completions (needs full type info)

#5 BindingMap coverage expansion
  ← LSP FindAllReferences upgrade (from text search to semantic)
  ← LSP Rename accuracy

#1 Type-based overload resolution
  ← Correct .NET API calls (independent of #2)

#8 Pattern exhaustiveness with guards
  ← (independent — can ship anytime)

#10 Error recovery
  ← (independent — can ship anytime, high LLM workflow impact)
```

---

## Recommended Attack Order

1. **#1 Type-based overload resolution** — independent, high impact, unblocks correct BCL usage
2. **#2 Generic type inference** — unblocks #3, #4, #6
3. **#3 Lambda context inference** — LINQ becomes usable (ship non-generic subset early)
4. **#4 LINQ hover fix** — quick win once #2 lands (or ship heuristic first)
5. **#10 Error recovery** — independent, high LLM workflow value
6. **#5 BindingMap coverage** — completes semantic navigation
7. **#8 Pattern exhaustiveness with guards** — independent correctness fix
8. **#9 String interpolation highlighting** — quick VS Code grammar fix
9. Everything else by priority tier

---

## Housekeeping

- **`memory/limitations.md` is stale** — items 14 (LSP go-to-def/refs/rename), 18 (formatter) are listed as "not yet done" but are fully implemented. Items 3 (property type inference), and the "Done" section at bottom acknowledge some of this. Needs a cleanup pass to match current reality.
- **`docs/GAPS.md`** — all critical gaps resolved. Only parameter attributes and null-forgiving remain, both low priority and tracked here.

---

*This document is the single source of truth for what to work on next. Update it as items are completed.*
