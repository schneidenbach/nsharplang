# Current N# Task List

Last audited: 2026-05-25

This is the only active task document. It replaces the old lettered task files, which mixed current work with completed, superseded, or historical plans. An item belongs here only if it names a current product gap that is still true against the source tree.

## P0: Semantic Correctness

### 1. Add source positions to type references

`TypeReference` nodes still do not carry enough source-position information for fully semantic definition, references, rename, hover, and query behavior at type-use sites.

Acceptance:
- Type annotations, generic type arguments, nullable type references, array element types, and function type references have stable source spans.
- BindingMap and SemanticModel record bindings for type-use positions.
- `nlc query definition/references/inspect` and LSP definition/references work for type annotations and generic arguments.
- Tests cover duplicate type names in different namespaces/files so this cannot fall back to simple-name matching.

### 2. Finish overload resolution edge cases

Reflection-backed call binding is materially better, but overload scoring is not complete enough to trust every .NET API call.

Acceptance:
- Candidate scoring handles optional parameters, `params`, numeric conversions, nullable conversions, generic methods, extension methods, and ambiguity diagnostics consistently.
- Wrong overload selection has regression tests using real BCL APIs.
- Hover, signature help, query type, and generated code agree on the selected overload.

### 3. Broaden generic type inference

Generic inference works for common paths, but broader .NET APIs still need more complete binding.

Acceptance:
- Inference uses receiver, argument, lambda parameter, lambda return, return-target, and generic constraint information where applicable.
- Failed inference produces a useful diagnostic instead of silently falling back to `unknown`.
- Tests cover multi-parameter generic methods, chained generic APIs, nested generic collections, and constrained generic calls.

### 4. Broaden lambda contextual typing

Common delegate/lambda calls work, but callback-heavy code and generic delegate flows need stronger coverage.

Acceptance:
- Lambda parameters and return types are inferred from delegate, expression tree, extension method, and generic method contexts.
- Nested lambdas and method-group-like callback positions do not lose semantic type information.
- LINQ, event handlers, task continuations, and BCL callback APIs have regression coverage.

### 5. Make LINQ return types fully trustworthy

Common `Where`/`Select`/`ToList` chains are improved, but LINQ correctness still rides on incomplete overload and generic inference.

Acceptance:
- Query type, hover, completions, and signature help report the same types across representative LINQ chains.
- `IEnumerable<T>`, `IQueryable<T>`, arrays, lists, dictionaries, anonymous-like projections, and nullable element types are covered.
- Incorrect chains produce precise diagnostics at the bad call site.

### 6. Finish semantic reference parity in LSP and CLI

Definition and rename prefer project-semantic snapshots when available, but references and degraded fallbacks still need hardening.

Acceptance:
- LSP references and `nlc query references` use the same semantic project reference engine.
- Open unsaved buffers override disk text in semantic snapshots.
- Duplicate simple names in different scopes/files are not conflated.
- If a semantic snapshot cannot be built, the tool reports an explicit degraded state instead of returning a precise-looking text result.

### 7. Improve SemanticModel scope and lookup completeness

The model records more expression types now, but scope-aware identifier lookup is still too flat for editor-grade tooling.

Acceptance:
- Local variables, parameters, members, imported symbols, shadowed names, and nested scopes can be queried by source position.
- Completion, hover, rename, references, inlay hints, and query commands consume this shared model instead of re-walking ASTs differently.
- Tests cover shadowing, nested functions/lambdas, blocks, pattern bindings, and imported names.

## P1: Parser And Diagnostics

### 8. Harden parser recovery beyond the current baseline

Parser recovery already reports multiple useful errors and returns partial ASTs. The remaining work is a hardening pass, not a from-scratch implementation.

Acceptance:
- Fuzzed and hand-curated malformed files do not crash the parser, analyzer, LSP, formatter, or query commands.
- Recovery resumes at useful declaration and statement boundaries without excessive cascades.
- VS Code Problems shows all high-signal diagnostics for a malformed file.
- Golden or snapshot tests lock down representative recovery behavior.

### 9. Keep diagnostic quality from regressing

Elm-style infrastructure and top diagnostic goldens exist. The live task is ongoing quality control as new diagnostics are added.

Acceptance:
- New common diagnostics include source snippets, explanations, concrete suggestions, stable codes, and docs links.
- The top diagnostic golden suite is refreshed when diagnostics change intentionally.
- LSP/VS Code squiggles and quick fixes are visually verified for IDE-facing diagnostic changes.

## P1: IDE Tooling

### 10. Move N# signature help to full compiler semantics

Signature help is stronger for .NET/reflection calls than for user-authored N# declarations and overloads.

Acceptance:
- Signature help works for N# functions, methods, constructors, overloads, generics, defaults, `params`, `ref`, `out`, and extension methods.
- Active parameter selection is correct for nested calls and named arguments.
- LSP tests and real VS Code visual verification cover representative cases.

### 11. Polish auto-import completion ranking and coverage

Auto-import completion exists, but ranking and symbol coverage need product polish.

Acceptance:
- Completion ranks local/in-scope symbols before importable symbols.
- Auto-import covers project symbols and relevant external symbols without noisy or duplicate suggestions.
- `additionalTextEdits` place imports consistently and do not corrupt existing imports/packages.
- Tests cover duplicate names and same-name symbols from different namespaces.

### 12. Harden workspace diagnostics scheduling and coverage

Project-scope diagnostics exist, but scheduling/update behavior needs confidence.

Acceptance:
- Diagnostics update reliably on open, save, change, create, delete, and watched-file events.
- Open-buffer text participates in diagnostics without waiting for disk writes.
- Large workspaces avoid noisy full rescans and stale diagnostics.
- LSP tests cover cross-file errors and file lifecycle events.

### 13. Finish interpolation syntax highlighting

Interpolation highlighting is still a product-polish risk because grammar-only tests can miss visual editor issues.

Acceptance:
- Nested interpolation expressions highlight as N# expressions, not plain string text.
- Escapes, braces, raw strings, and multiline interpolation render correctly.
- The VS Code extension is rebuilt/reinstalled and verified visually in the editor.

### 14. Keep VS Code debug/task claims gated by real-editor evidence

VS Code tasks now use `nlc` paths and debug build plumbing exists, but public claims around F5/debug/test workflows must stay conservative until freshly verified.

Acceptance:
- Fresh template project can build, run, test, and debug from VS Code using contributed tasks/configuration.
- Debugging uses the generated C# bundle correctly and breakpoint/source mapping behavior is visually verified.
- Docs and launch claims match exactly what was verified in VS Code.

## P1: Nullability

### 15. Add explicit null-state and flow-fact data structures

Nullable compatibility and branch narrowing exist, but there is no complete null-state model for expressions, symbols, and stable member paths.

Acceptance:
- Analyzer distinguishes `Unknown`, `Null`, `MaybeNull`, `NotNull`, and `Oblivious`.
- SemanticModel can expose declared type, flow type, and null state at a source position.
- Facts are tracked for variables and stable member paths without noisy cascades after unrelated errors.

### 16. Complete nullable flow narrowing

Direct null-check branch narrowing exists, but early returns, assignment invalidation, member paths, and richer control-flow facts still need work.

Acceptance:
- `if x == null { return } x.Member` is accepted.
- Assigning to `x` invalidates prior facts.
- `&&`, `||`, `is` patterns, `match`, loops, and nested scopes preserve only sound facts.
- Stable member paths such as `user.Address != null` can narrow inside the guarded region.

### 17. Add possible-null diagnostics

N# should report member/index/call access on maybe-null values and assignment from nullable to non-nullable without proof.

Acceptance:
- Maybe-null dereference produces a stable diagnostic with suggestions for `?.`, `??`, a guard, or explicit assertion.
- Assigning/returning/passing `T?` to `T` without proof is rejected or reported according to the chosen severity policy.
- JSON diagnostics, LSP diagnostics, and terminal output expose the same stable code and suggestion fields.

### 18. Implement `must` explicit unwrap/assertion

The planned `must expr` syntax is still missing.

Acceptance:
- Parser, AST, analyzer, formatter, C# export, and IL backend support `must expr`.
- `must T?` has type `T`; redundant `must` on proven non-null values reports a diagnostic.
- Lowering uses explicit throw behavior, not C# null-forgiving syntax.
- Optional assertion messages are either implemented or explicitly deferred.

### 19. Add nullable value idiom diagnostics and fixes

Migration lints catch blind `.Value` and null-forgiving artifacts syntactically, but semantic nullable-value guidance is incomplete.

Acceptance:
- `Nullable<T>.HasValue` and `.Value` are recognized semantically.
- Guarded `.Value` can suggest an `is T value` pattern.
- Unguarded `.Value` reports an unsafe access diagnostic.
- Fixes are marked safe, review-needed, or suggestion-only and round-trip through parser/formatter.

### 20. Add nullable `match` exhaustiveness and narrowing

Nullable values should be consumable through `match` as a first-class absence pattern.

Acceptance:
- `match name { null => ..., value => ... }` narrows `value` to non-null `T`.
- Missing null coverage in expression contexts produces a helpful exhaustiveness diagnostic.
- Value-type nullable and reference nullable cases are both tested.
- Existing union exhaustiveness remains intact.

### 21. Import and emit C# nullable metadata

C# nullable annotations are not yet fully modeled as semantic facts at interop boundaries.

Acceptance:
- Reflection import decodes `NullableAttribute`, `NullableContextAttribute`, and common flow attributes such as `MaybeNull`, `NotNull`, and `NotNullWhen`.
- Annotated C# APIs map to `T` or `T?` accurately in N#.
- Missing nullable metadata can be represented as `Oblivious`.
- Generated public C# preserves N# nullability for C# consumers.

### 22. Surface nullability through query, fixes, and LSP

Nullability work must be visible to tools, not just analyzer internals.

Acceptance:
- `nlc query type` and `inspect` expose nullable/null-state information under a versioned JSON contract.
- Code actions are available for nullability diagnostics where a safe or review-needed edit exists.
- VS Code distinguishes safe fixes from review-needed migration suggestions.

## P2: CLI And Ecosystem

### 23. Create a current `setup-nsharp` GitHub Action

There is no `actions/setup-nsharp` composite action. The old action spec is stale because the installer no longer supports a `--version` flag.

Acceptance:
- `actions/setup-nsharp/action.yml` installs .NET, installs N# from latest or explicit toolset source, adds `~/.nsharp/bin` to PATH, and verifies `nlc`.
- README documents inputs that match the current installer.
- The repository dogfoods the action in an appropriate workflow without depending on stale `dotnet build` assumptions for csproj-free projects.

### 24. Add formatter repo/example audit and CI gate

`nlc format` exists with check, diff, and stdin support, but examples and CI are not currently gated by formatting.

Acceptance:
- Current examples/templates/representative fixtures have been audited with `nlc format --check`.
- Any ugly or unstable formatter output has focused regression tests.
- CI or `scripts/test-all.sh` includes a formatting gate if the repo is expected to stay formatted.

### 25. Grow `nlc fix` into a broader machine-drivable tool

`nlc fix` exists, but the fix catalog is still narrow.

Acceptance:
- More high-confidence compiler/lint diagnostics provide safe or review-needed fixes.
- Dry-run JSON remains stable and includes enough edit/safety metadata for automation.
- Applied fixes preserve formatting and are covered by parser/formatter round-trip tests.

### 26. Unify install, release, and local toolset ergonomics

Install and deployment scripts have improved, but the public path, local dogfood path, and release artifact path still need to feel like one coherent product.

Acceptance:
- Public install docs, local setup docs, `doctor`, package artifacts, VSIX install, and CI setup all describe the same supported model.
- Version/source selection is explicit and tested.
- Stale or ad hoc deployment scripts are either documented as internal-only or removed.

### 27. Build benchmark corpus and results workflow around `nlc bench`

`nlc bench` exists; the missing work is benchmark content, repeatable results, and regression visibility.

Acceptance:
- A benchmark corpus covers compile/check speed and representative runtime scenarios.
- Benchmarks run locally through documented commands and produce JSON/markdown artifacts.
- CI runs benchmarks on an intentional cadence and publishes artifacts without slowing normal PR validation.
- Docs and website claims cite actual benchmark artifacts, not targets.

### 28. Build a public website playground if still part of launch strategy

The local `nlc tutorial` covers much of the interactive learning experience, but there is no public website playground.

Acceptance:
- Product decision is made: public playground is either in launch scope or explicitly deferred.
- If in scope, the playground reuses current tutorial/compiler infrastructure where practical.
- It supports examples, diagnostics, sharing, and a clear no-install first-run experience.

### 29. Polish NuGet library publishing

Library template and `nlc pack` exist, but a few publishing-story gaps remain.

Acceptance:
- Library template includes a small `.tests.nl` example or a deliberate documented reason not to.
- Dedicated library publishing guide explains package metadata, `nlc pack`, NuGet push, and C# consumption.
- End-to-end test verifies a C# project can consume an actual packed N# NuGet package, not only a project reference.

### 30. Add native test coverage reporting or document its absence clearly

`nlc test --coverage` currently reports that coverage is unavailable.

Acceptance:
- Either implement coverage collection/reporting for the xUnit-backed runner, or keep help/docs explicit that coverage is planned.
- CLI exit codes and JSON output remain clear when coverage is requested before support exists.

### 31. Decide cross-compilation and publish-target scope

Cross-compilation remains future work, and release/publish target evidence is still limited.

Acceptance:
- Product docs state exactly what `nlc build --release`, `nlc publish`, and target-platform workflows support today.
- Unsupported target scenarios fail with clear guidance.
- Any supported cross-target path has scenario tests.

### 32. Add built-in build timing evidence or avoid timing claims

Docs mention timing as a gap. Do not make Go/Rust-speed claims without measurements.

Acceptance:
- Either expose reliable build/check timing output and test it, or keep timing claims out of public docs.
- Benchmark and launch docs cite current measured artifacts.

### 33. Audit dependency tree command and docs parity

The CLI has `nlc tree`, but docs still contain stale future-work wording around dependency tree visualization.

Acceptance:
- `nlc tree` behavior, help, JSON/text output, and docs agree.
- Any missing dependency-tree capability is named precisely instead of saying the whole feature is absent.
- Parity tests catch future drift.

## P2: Docs And Site

### 34. Remove stale launch and maturity claims

Docs and memory files still contain historical counts and launch-readiness claims that can drift from reality.

Acceptance:
- Public docs, website docs, README, memory docs, and talk materials avoid static test counts unless generated from fresh artifacts.
- Marketplace, debug, benchmark, production-ready, and feature-complete claims are tied to current evidence.
- Docs build passes after claim updates.

### 35. Keep CLI JSON contracts authoritative

The CLI JSON contract is central to the LLM-first story and must not drift across docs.

Acceptance:
- `memory/components/cli-toolchain.md` remains the canonical contract reference.
- `docs/guide/cli-reference.md`, website docs, help text, completions, and tests stay in sync.
- Breaking JSON changes increment schema versions and include migration notes.
