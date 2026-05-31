# N# Performance Compiler Refactor

Status: design proposal
Updated: 2026-05-27

This document defines the compiler refactor needed to make N# a performance-by-default CLR language. It is intentionally conservative about public claims: CLR interop remains a first-class product value, and every optimization that weakens interop or changes language behavior must be justified by dated BenchmarkDotNet output, IL-shape evidence, and compatibility tests.

## Product Position

N# should target this performance envelope:

- **Default goal**: C#-class performance for ordinary .NET code without user ceremony.
- **Aspirational goal**: Go-like performance for allocation-light services, CLIs, parsing, data processing, and server hot paths.
- **Bounded non-goal**: Rust/C++/Zig parity for workloads dominated by manual layout, arena ownership, deterministic destruction, whole-program monomorphization, or no-GC latency constraints.

The CLR is not the only bottleneck. Recent function-value work showed that N# emitted delegate-heavy IL in places where direct helper calls were legal. Fixing the emission changed a repeated local-lambda benchmark from allocation-heavy microseconds to allocation-free hundreds of nanoseconds. That is compiler headroom, not runtime inevitability.

The real constraint is sharper: N# must emit IL that the .NET JIT, tiered PGO, NativeAOT, GC, and C# consumers can all understand. When N# emits object-heavy, delegate-heavy, interface-heavy, or reflection-sensitive shapes, it pays those costs. When it emits simple calls, contiguous value data, spans, direct field access, and allocation-free loops, the CLR can be very fast.

## Evidence Baseline

Current dated evidence from the external scratch lab, run on 2026-05-27 with BenchmarkDotNet ShortRun, Apple M4, .NET 10.0.5, `N=1024`:

| Scenario | Current N# Result | Matched C# Result | Interpretation |
| --- | ---: | ---: | --- |
| Direct loop | 500.344 ns / 0 B | 514.132 ns / 0 B | N# is already in the same range. |
| Top-level call loop | 484.405 ns / 0 B | 489.025 ns / 0 B | Direct calls are viable. |
| Local function direct | 489.561 ns / 0 B | 481.785 ns / 0 B | Close enough that long-run validation matters more than micro claims. |
| Lambda local direct | 487.095 ns / 0 B | 492.174 ns / 0 B | Direct lambda-local lowering works. |
| Lambda escaped boundary | 487.124 ns / 0 B | 274.111 ns / 0 B | The delegate-boundary path remains a real target. |
| Lambda captured local-only | 483.615 ns / 0 B | 280.664 ns / 24 B | N# eliminated allocation but still has code-shape/JIT gap. |
| Repeated lambda creation in loop | 263.401 ns / 0 B | 8,402.815 ns / 90,112 B | N# can beat idiomatic delegate allocation when escape analysis proves local-only use. |

Do not publish broad "Go speed", "Rust speed", or "faster than C#" claims from this table. It proves that specific compiler lowering choices matter and that wrapper shape plus IL shape must be reported with benchmarks.

## Runtime Realities

The design must treat these CLR facts as product constraints:

- **Delegates are reference types.** Public or escaping function values must use CLR delegate semantics unless N# intentionally introduces a non-CLR internal ABI.
- **Escaping closure state normally requires heap representation.** The compiler can remove over-capture and avoid lifted boxes for readonly captures, but it cannot keep arbitrary escaping closure state on the caller stack.
- **GC is part of the platform.** Allocation elimination is still the main hot-path lever; GC tuning is secondary.
- **JIT quality is pattern-sensitive.** Simple IL with direct calls, obvious loops, value types, and spans gives the runtime more room than reflection-heavy or virtual-heavy IL.
- **NativeAOT is a deployment mode, not a magic optimizer.** It can improve startup and trim/runtime footprint, but it has reflection/dynamic-code limitations and may not beat tiered JIT plus PGO for every throughput workload.
- **Reference-type generic sharing limits Rust-style specialization.** The compiler can specialize N#-internal paths, but public CLR generic semantics still matter.

## Refactor Architecture

The current backend is effectively `AST + semantic helpers -> IL`. That is too direct for a performance-focused compiler. We need an explicit performance lowering pipeline:

```text
Source
  -> Lexer / Parser
  -> Analyzer
  -> Bound IR
  -> Performance Facts
       escape, capture, mutation, allocation, purity, dispatch, ABI boundary
  -> ABI Classifier
       CLR-public, CLR-private, NSharp-internal, AOT-safe
  -> Lowered IR
       explicit storage, explicit calls, explicit boxes, explicit temporaries
  -> IL Emission
  -> IL Shape + Benchmark Evidence
```

### Decision: Add Bound IR Or Keep Optimizing AST

Recommendation: add a bound IR. Keep it narrow at first, but make it the optimization source of truth.

| Option | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| Continue optimizing the AST emitter | Fastest near-term patches | Hard to reason about scopes, captures, overloads, and lowering correctness | Use only for small tactical fixes. |
| Add a full Roslyn-style bound tree | Clean semantic model | Large refactor and longer runway | Target long-term, but do not block performance work on full parity. |
| Add a minimal Bound IR for functions/expressions/hot constructs | Enough for escape, ABI, value layout, dispatch, and allocation analysis | Requires dual maintenance during transition | Recommended first architecture step. |

Interop tradeoff: none if Bound IR preserves current metadata emission. Language tradeoff: none.

## Performance Facts

Performance facts must be explicit data attached to Bound IR nodes, not implicit local booleans scattered through emitters.

Required facts:

- **Escape**: local-only, returned, stored, passed to unknown call, public ABI, expression tree, reflection boundary.
- **Capture**: captured by value, captured by mutable storage, captures `this`, captures ref-like value, no capture.
- **Allocation**: guaranteed none, delegate allocation, closure allocation, array allocation, iterator/state-machine allocation, boxing allocation, unknown.
- **Dispatch**: direct, constrained value-type, virtual, interface, delegate invoke, reflection/dynamic.
- **Value layout**: primitive, enum, struct, ref struct, nullable, union representation, reference object.
- **AOT/trimming safety**: no reflection dependency, metadata required, dynamic code required, expression-tree required.

### Decision: Conservative Or Aggressive Analysis

Recommendation: conservative by default, aggressive only under proof.

| Option | Language/interop cost | Performance impact | Decision |
| --- | --- | --- | --- |
| Conservative proof-only lowering | No behavior surprises | Misses some wins initially | Default. |
| Speculative lowering with fallback | Requires deopt model CLR does not naturally provide | Complex and fragile | Avoid. |
| User opt-in unsafe/perf mode | Adds language/project complexity | Useful later for narrow domains | Defer until evidence proves need. |

## Function Values And Closures

Current rule: CLR delegates remain the public ABI. N# may erase delegates internally when the value does not cross a boundary.

Required compiler work:

1. Generalize direct-call lowering from lambda locals and local functions into a Bound IR function-value lowering pass.
2. Track exact escape reason: direct local call, argument to known inlineable helper, stored local, returned, field, array, interface, expression tree, `Delegate`, `MulticastDelegate`.
3. Emit direct helper calls for all non-escaping function values, including contextual `Func<>` / `Action<>` locals and method groups.
4. Cache all non-capturing escaped lambdas and method groups in static fields where CLR semantics match.
5. Avoid closure classes when `this` is not referenced.
6. Use normal local storage for readonly captures. Use lifted shared storage only for mutation or lifetime.
7. Add IL-shape diagnostics so `nlc query perf` can explain why a function value allocated.

### Decision: Internal Function ABI

Recommendation: keep public CLR delegates, add an internal function ABI only after the current transparent lowering is exhausted.

| Option | What we sacrifice | What we gain | Decision |
| --- | --- | --- | --- |
| Always CLR delegates | No interop cost | Leaves local hot paths slower/allocation-prone | Rejected for internal code. |
| Transparent internal helper calls | No source or public ABI cost | Removes most non-escaping delegate overhead | Current path; continue. |
| First-class internal function pointer ABI | Harder reflection/debugging; possible interop cliffs if it leaks | Faster higher-order internal code | Consider after evidence shows helper-call lowering is insufficient. |
| Public N# function type distinct from delegates | C# interop cost and language complexity | Stronger performance contract | Not for v1. |

## Value Layout

N# must stop treating every rich language feature as an object shape. The compiler should choose allocation-free value layouts where interop permits.

Required compiler work:

1. Add layout classification for `class`, `record`, `struct`, `readonly struct`, `ref struct`, tuple, newtype, nullable, and union.
2. Emit small immutable domain wrappers as `readonly struct` where semantics permit.
3. Prefer direct fields and init-only properties only when interop requires property shape.
4. Keep public classes and records C#-natural by default.
5. Add explicit layout tests for object header avoidance: no generated display class, no case object, no boxed value.

### Decision: Union Representation

Recommendation: split union representation by boundary.

| Option | Interop cost | Performance impact | Decision |
| --- | --- | --- | --- |
| Always class hierarchy cases | Excellent C# consumption | Allocates per case; virtual/type-test cost | Keep for public/non-small unions. |
| Internal tagged struct for closed small unions | C# sees less natural shape if exposed | Allocation-free matches and better locality | Use internally when not exposed. |
| Public tagged struct union | Less idiomatic C# but still consumable | Allocation-free public data | Consider for `readonly`/small unions behind explicit design. |
| Reuse `System.ValueTuple`-like shapes | Familiar CLR value layout | Weak named-case semantics | Use only for compiler-internal lowering, not source ABI. |

Language tradeoff: if users can observe identity of union cases, allocation-free unions become harder. Recommendation: do not promise reference identity for union cases unless explicitly class-backed.

## String Interpolation

String interpolation is pervasive in idiomatic code, so its lowering directly shapes the allocation profile of typical programs.

Previous lowering built a `string[]`, stored each segment (boxing every value-type hole into `object` and routing through `string.Concat(object)` / `string.Format(string, object)`), then called `string.Concat(string[])`. That path allocated an array per interpolation plus one box per value-type hole.

Current lowering mirrors the C# compiler and targets `System.Runtime.CompilerServices.DefaultInterpolatedStringHandler` (a stackalloc-backed ref struct):

1. Construct the handler with the constant `literalLength` (sum of literal-segment lengths) and `formattedCount` (number of holes), matching the constants C# passes.
2. Emit `AppendLiteral(string)` per literal segment.
3. Emit `AppendFormatted<T>(T)` per hole using the **generic** overload instantiated at the hole's static type, so value-type holes are never boxed. String holes use the dedicated `AppendFormatted(string)` overload. Holes with a format clause use `AppendFormatted<T>(T, string)`.
4. Produce the result with `ToStringAndClear()`.
5. A purely literal interpolation (no holes) folds to a single `ldstr` constant and never allocates a handler.

The handler is a ref struct kept strictly stack-local: it is declared as a local, only ever addressed via `ldloca`, and never stored to a field or captured, so the byref-internal value type stays verifiable and GC-safe (ILVerify-clean, and exercised under `--blame-crash` on linux/amd64 — the platform where unverifiable IL crashes).

Net effect per interpolation with value holes: `box` drops to `0`, the `string[]` allocation (`newarr`) and `string.Concat` call are eliminated. IL-shape regression tests in `ILShapeBaselineTests` pin `box == 0`, `newarr == 0`, no `string.Concat`, exactly one handler ctor + `ToStringAndClear`, and one `AppendFormatted` per hole. Behavioral tests assert exact string parity (including culture-correct `:X` / `:F2` format clauses) against the equivalent C# interpolation.

## Generics And Specialization

The CLR already specializes generic code for value types but shares many reference-type instantiations. N# can still do better for internal code.

Required compiler work:

1. Classify generic functions as public ABI, private/internal, or local.
2. Specialize private/internal generic functions for hot value-type instantiations when benchmark evidence shows a win.
3. Emit `constrained.` calls for value-type interface/generic dispatch to avoid boxing.
4. Avoid generic helper shapes that force `object` or interface boxing.
5. Record generic specialization in IL-shape reports.

### Decision: Monomorphization

Recommendation: selective internal specialization, not global Rust-style monomorphization.

| Option | What we sacrifice | What we gain | Decision |
| --- | --- | --- | --- |
| CLR generic sharing only | Leaves some interface/boxing overhead | Small assemblies, predictable interop | Default public ABI. |
| Selective private specialization | Larger assemblies, more compiler complexity | Better value-type hot paths | Recommended. |
| Whole-program monomorphization | Dynamic loading/reflection interop, build size, AOT complexity | Rust-like codegen potential | Not aligned with CLR product goals. |

### Implementation: Selective Specialization (shipped)

Selective internal specialization is implemented by `Performance/GenericSpecializer.cs`
(policy + registry) and a hook in the IL backend (`ILCompiler.cs`). The design is built
around the lesson from the GC-unsafe IL regression that crashed on x64: **we never rewrite
IL tokens after the fact.** Instead the existing, type-correct body emitter is re-driven
with the generic type parameter names bound to concrete value types through a substitution
map (`_activeGenericSpecialization` in `ResolveType`). Every local, signature, `ldtoken`,
`newobj`, and array element type therefore flows through the same resolution code that
already produces verifiable IL for ordinary non-generic methods. The substitution map is
consulted *after* any live local generic parameters so that a nested generic local function
that shadows the outer type-parameter name resolves to its own open parameter, not the outer
concrete type.

What changes at a specialized call site is only the target method token: a closed generic
instantiation `foo<int32>(...)` becomes a direct call to a concrete non-generic method
`foo$System_Int32(int32)`. The shared-generic dictionary-lookup shape is gone and the body
carries no boxing for the specialized value type.

Gating (deliberately conservative — this is the highest GC-safety-risk pass):

1. **Boundary**: only `ClrInternal` / `FilePrivate` / `Local` generics are eligible
   (`AbiClassifier.ClassifyFunctionBoundary`). Public CLR surface keeps its generic ABI
   untouched for C# interop.
2. **Shape**: only static, top-level functions on the program type are specialized today.
   Instance/extension generics stay shared.
3. **Type arguments**: only closed, finalized value types — reference types (already shared
   via `__Canon`), open generic parameters, pointers, by-ref types, and `void` are excluded.
   Source-declared structs (emitted as `TypeBuilder`s, whose layout may not be baked when the
   specialized signature is built) are also conservatively left shared until proven safe by
   evidence.
4. **Cap**: an internal `DefaultSpecializationCap` (256) bounds the number of specialized
   bodies emitted; once reached, further requests fall back to the shared path. Every skipped
   instantiation is recorded (`GenericSpecializer.Skipped`) with a reason for diagnostics.

Verification: specialized assemblies pass `ilverify` (the make-or-break gate for this pass)
with zero new errors over baseline, IL-shape regression tests assert `box == 0` and the
absence of a generic-instantiation token for specialized call sites (and that public generics
stay shared), and behavioural parity is checked by invoking specialized programs. See
`tests/PerfEvidence/GenericSpecializationTests.cs` and `tests/GenericSpecializerTests.cs`.

## Dispatch And Interfaces

N# should make concrete dispatch the default on hot paths while preserving .NET polymorphism at boundaries.

Required compiler work:

1. Prefer direct calls for local/private functions and sealed/private methods.
2. Devirtualize calls when the receiver type is exact.
3. Emit `call` instead of `callvirt` when null-check semantics are unnecessary or already proven.
4. Lower duck-interface use to compile-time structural calls when the concrete type is known.
5. Avoid interface dispatch in compiler-generated loops unless the source explicitly requires abstraction.

### Decision: Duck Interface Runtime Shape

Recommendation: compile-time structural dispatch internally, CLR interface shape only at interop boundaries.

| Option | Interop cost | Performance impact | Decision |
| --- | --- | --- | --- |
| Always emit runtime interfaces | Easy reflection/C# model | Interface dispatch and possible boxing | Keep for public contracts. |
| Erase duck interfaces internally | No public interop for erased shape | Direct calls, no adapter allocation | Recommended default for internal use. |
| Generate adapters automatically at boundaries | More generated types | Best of both worlds if tested | Add after Bound IR ABI classifier exists. |

## Match And Switch Lowering

`match` expressions and `switch` statements are control-flow hot paths. The naive lowering tests
each arm in source order with an independent compare-and-branch; with N arms a value that hits the
last arm pays N comparisons, and large dispatch tables become O(N) hot loops.

Implemented compiler work (Unit 10):

1. **Dense integer/enum jump tables.** When every selectable arm is a guardless constant
   `int`/`char`/`bool` literal or an int-backed enum-member pattern (e.g. `Color.Red`), and the
   keys are dense enough, the arms lower to a single range-biased `OpCodes.Switch`: the scrutinee
   is shifted by the minimum key (`sub`) and used to index the jump table, with a `br` to the
   default for out-of-range values. Density heuristic: at least four distinct keys and a key span
   `(max - min)` no larger than four times the key count, so the table is never dominated by empty
   default slots.
2. **String hash dispatch.** A string `match`/`switch` with four or more distinct literal keys
   computes a process-stable content hash (FNV-1a) of the scrutinee **once**, switches on
   `hash % bucketCount`, then verifies the candidate(s) in that bucket with ordinal string
   equality. The compile-time bucket assignment and the emitted run-time hash use the identical
   FNV-1a function, so a key always lands in the bucket it was assigned to. A null scrutinee is
   routed to the default before hashing. `String.GetHashCode` is deliberately **not** used because
   it is randomized per process and would make bucket assignment non-deterministic.
3. **Single scrutinee evaluation.** The scrutinee is always spilled to a local exactly once and
   every test (table index, hash input, equality verification, or linear compare) reads that local.
   Side-effecting scrutinees (`match next() { ... }`) run their side effect exactly once.
4. **Cheapest-first / correctness-preserving fallback.** Guards (`when` clauses), non-constant
   patterns, nullable scrutinees, sparse key sets, and short key sets fall back to the existing
   linear chain. First-match-wins, guard fallthrough, variable-binding catch-alls, and
   exhaustiveness/no-match semantics are preserved exactly; the dispatch path declines whenever it
   cannot prove equivalence (e.g. a non-final `default`, multiple defaults, or any guard).

This also fixed a latent correctness bug: enum-member patterns (`Color.Red`) were previously
misread as variable bindings in `match`, so an enum match always selected its first arm. They now
compare the discriminant.

### Decision: Dispatch Shape By Arm Kind And Density

Recommendation: choose the dispatch shape from the arm kinds and key density, never unconditionally.

| Option | Cost | Performance impact | Decision |
| --- | --- | --- | --- |
| Always linear compare chain | Simplest | O(N) per match, O(N) table scans | Keep only as the fallback. |
| Always jump table | Wastes space on sparse keys | Great when dense, pathological when sparse | Gate behind a density heuristic. |
| Always string hash dispatch | Hash cost dominates tiny matches | Wins only past a key-count threshold | Gate behind a ≥4-key threshold. |
| Kind- and density-directed selection | Slightly more compiler logic | Best shape per match, verifiable IL | Recommended (implemented). |

Verifiability gate: every emitted shape (jump table, hash loop, string verification) must pass
ILVerify and run crash-free under amd64, because IL bugs here can be GC-unsafe and crash only on
x64 (see the PR #160 regression). IL-shape tests assert the presence/absence of `OpCodes.Switch`
and single scrutinee evaluation; behavioural tests cover dense, sparse, guarded, enum, string,
null, and variable-binding-catch-all matches.

## Collections, Spans, And Loops

N# cannot be Go-like if idiomatic loops allocate or hide bounds checks behind abstractions.

Required compiler work:

1. Lower `for item in array` to index loops over arrays when mutation/enumerator semantics permit.
2. Lower `for item in Span<T>` / `ReadOnlySpan<T>` to span index loops.
3. Prefer `ReadOnlySpan<T>` for readonly slice parameters and string/array views where lifetime is local.
4. Avoid enumerator allocation for common BCL collections.
5. Preserve exact CLR `foreach` semantics when the source relies on disposal or custom enumerators.
6. Add bounds-check-oriented IL-shape tests for canonical loops.

### Decision: Make Span A First-Class Language Concept

Recommendation: yes, but with honest restrictions.

| Option | Language cost | Interop cost | Decision |
| --- | --- | --- | --- |
| Treat `Span<T>` as ordinary external type | Simple | Misses lifetime diagnostics and optimization | Insufficient. |
| First-class local-only span/slice model | Requires ref-safety diagnostics | Matches CLR span constraints and unlocks performance | Recommended. |
| Invent non-CLR slice type | More runtime/library burden | Could improve ergonomics | Defer until CLR span model proves inadequate. |

Language tradeoff: first-class spans require restrictions: no field storage in normal classes, no async capture, no heap escape, and careful closure rules.

### Stack buffers

A fixed-size local array literal of unmanaged primitive elements that never escapes its
frame is stored as a stack-allocated `[InlineArray]` value-type struct instead of a heap
array. The local stays semantically a `T[]` to the rest of the type system; only its
storage and the IL for its reads/writes change. This removes the heap allocation and the
GC tracking for the common "scratch buffer" pattern.

Mechanism (emitter):

- A synthesized `[InlineArray(N)]` struct with a single element field of type `T` backs the
  buffer; the runtime lays out `N` contiguous copies. The buffer lives in a plain stack slot.
- Element access uses an interior managed pointer
  (`Unsafe.Add<T>(ref Unsafe.As<TBuffer,T>(ref buffer), index)`) followed by an immediate
  `ldind`/`stind`. The byref only ever lives on the evaluation stack for a single load/store,
  so the IL stays verifiable and GC-safe (a stack-local struct is never relocated).
- Index access emits an explicit `(uint)index < (uint)N` bounds check that throws
  `IndexOutOfRangeException`, preserving array element-access semantics. `foreach` lowers to a
  counted index loop with no enumerator.

Eligibility is decided by a deliberately **fail-closed** escape analysis
(`StackBufferPromotionAnalysis`). A local is promoted only when ALL hold:

1. Element type is an unmanaged primitive (`int`/`double`/etc.) — never a managed reference,
   so the stack buffer has no GC references.
2. Size is a known small compile-time constant (`<= 32` elements, no spreads).
3. It is a single declaration at the top level of the function body (promotion storage is
   method-wide and string-keyed; restricting to top-level keeps that model sound).
4. Its name does not collide with a parameter or a current-type member (field/property).
5. Every use is on the small whitelist the emitter can lower: index get/set (including
   compound assignment), `.Length`, and `foreach`. Any other use — bare identifier load,
   return, argument pass, `ref`/`out` of an element, cast, capture in a lambda/local function,
   increment/decrement of an element, use inside a pattern, or any shape the walker does not
   recognise — disqualifies the local, which then stays a heap array.

Because the fallback is a heap array (always valid), no diagnostic is required on escape:
promotion is a transparent optimization, not a checked language feature.

Deferred: buffers declared inside nested blocks (would require scope-restored promotion
state), non-constant sizes, and managed/struct element types.

## Async And Iterators

Async and iterator lowering can dominate allocations. N# should make the cheap path explicit without making async interop weird.

Required compiler work:

1. Prefer `ValueTask<T>` for internal async functions that commonly complete synchronously, but preserve public API compatibility rules.
2. Avoid async state machines when a function returns an existing task/value-task directly and has no `await`.
3. Avoid iterator state machines for simple materialized collections when a loop can fill an array/list more directly.
4. Track async closure captures separately from ordinary closure captures.
5. Emit analyzer diagnostics when a lambda/closure/span crosses an async boundary and forces allocation or is illegal.

### Decision: Default Task Or ValueTask

Recommendation: public APIs should stay explicit; internal compiler-generated async helpers may use `ValueTask` when evidence supports it.

| Option | What we sacrifice | What we gain | Decision |
| --- | --- | --- | --- |
| Always `Task<T>` | Leaves sync-completion allocation opportunities | Simple C# interop | Public default remains acceptable. |
| Always `ValueTask<T>` | More complex consumption rules for C# users | Better sync-completion cases | Too broad for public default. |
| Evidence-based internal `ValueTask<T>` | Minimal interop impact | Wins in known hot paths | Recommended. |

### Implementation Status

The IL backend (`System.Reflection.Emit`) does **not** emit real async state machines today.
`EmitAwaitExpression` lowers `await` to a synchronous `GetAwaiter().GetResult()`, and the whole
`async` body runs synchronously; the result is wrapped into a completed `Task`/`ValueTask` at each
return (`EmitWrapCurrentAsyncReturn`). This means item (2) above — "no state machine for an async
method without `await`" — is already satisfied structurally: no `IAsyncStateMachine`/`MoveNext`
type is generated for any async method, and the await-free path adds no Task allocation beyond the
unavoidable result carrier (`Task.CompletedTask` is cached; `ValueTask` is allocation-free; a
result-typed `Task<T>` uses `Task.FromResult`).

Landed in this workstream (`ILCompiler.Async.cs`):

- **Exception-as-faulted-task parity.** Because the body runs synchronously, a thrown exception
  would otherwise escape the method synchronously. C# instead captures it and returns a *faulted*
  task. Async method bodies are now wrapped in a `try/catch(Exception)` fault guard
  (`BeginAsyncFaultGuard`/`EndAsyncFaultGuard`) that converts a thrown exception into a faulted
  `Task`/`Task<T>`/`ValueTask`/`ValueTask<T>` (`Task.FromException[<T>]`), routed through the
  structured-return mechanism. Side-effect ordering up to the throw is preserved. Verifiable,
  GC-safe IL.
- **Nested-body return-context isolation.** Lambdas and local functions emit into their own IL
  generators. The fault guard sets the protected-region depth, which previously leaked into nested
  bodies and bound their returns to the wrong generator. `SaveAndResetNestedMethodReturnContext` /
  `RestoreNestedMethodReturnContext` now isolate the structured-return + exception-depth context
  around every nested method body (in `LambdaEmitter` and `EmitGenericLocalFunctionBody`). Each
  nested emitter also establishes its *own* structured-return context
  (`InitializeStructuredReturnContext`) and closes it (`TryCloseNestedStructuredReturn`), so a
  `return` inside a `try`/`catch` within a lambda or local function routes through the nested
  generator. Previously this either crashed codegen ("No structured return context") or emitted a
  cross-generator `stloc`/`leave` (invalid IL).
- **Pooled-builder selection plumbing.** `language.pooledAsync` (project.yml) +
  `ResolveAsyncMethodBuilderType` select `PoolingAsyncValueTaskMethodBuilder[<T>]` for
  ValueTask-returning async methods; `ApplyAsyncMethodBuilderAttribute` is the single wiring point
  that would attach `[AsyncMethodBuilder(...)]`.

**DEFERRED (not implemented):**

- Real async state machines (`IAsyncStateMachine`/`MoveNext`, suspension/resumption at `await`,
  builders actually driving the machine). `EmitAwaitExpression` remains synchronous.
- Actually emitting `[AsyncMethodBuilder]`: gated off (`EmitAsyncMethodBuilderAttribute => false`)
  because the attribute is inert without a state machine to drive. Flip it on when state machines
  land. Until then `pooledAsync` is accepted and validated but has no codegen effect.
- The fault guard is applied to top-level functions and type methods only. Async **lambdas** and
  async **local functions** still surface a thrown exception synchronously (pre-existing behavior);
  wrapping them is follow-up work once the shared body-emission paths are unified.
- **`OperationCanceledException` → canceled task.** C#'s async builder reports a thrown
  `OperationCanceledException` by completing the task as *canceled* (via
  `TrySetCanceled(oce.CancellationToken)`), not faulted. The fault guard currently routes *all*
  exceptions through `Task.FromException`, so a thrown OCE becomes a *faulted* task carrying the
  OCE rather than a canceled one. Matching C# exactly requires `TrySetCanceled` semantics —
  `Task.FromCanceled` is stricter (it throws unless the token is already canceled, so it cannot be
  used for a bare `new OperationCanceledException()`). Deferred until the async builder path is
  fleshed out; the common throw-an-exception case is correct today.

## Error Handling And Exceptions

CLR exceptions are expensive when thrown. N# already has Go-inspired result/error patterns; the compiler should make those cheap.

Required compiler work:

1. Keep exceptions for exceptional CLR interop and `throw`.
2. Make result/error sugar lower to direct branches and value carriers, not exception control flow.
3. Consider allocation-free `Result<T, E>` internal layout for non-public hot paths.
4. Add benchmarks for success-path and failure-path result handling.

### Decision: Exceptions As Control Flow

Recommendation: never lower ordinary N# result/error control flow to exceptions.

Interop tradeoff: none. Language tradeoff: users must choose exception interop explicitly when calling exception-based .NET APIs.

## Reflection, Dynamic, And Expression Trees

Reflection and expression trees are important .NET interop paths, but they prevent many optimizations.

Required compiler work:

1. Mark expression-tree boundaries as hard CLR delegate boundaries.
2. Mark reflection/dynamic access as unknown escape and unknown dispatch.
3. Preserve metadata required by public reflection scenarios.
4. Provide diagnostics that explain when reflection/dynamic prevents direct lowering, trimming, or AOT safety.

### Decision: Optimize Across Reflection Boundaries

Recommendation: no. Treat reflection/dynamic/expression trees as optimization fences unless a future linker-style analysis proves safety.

Interop tradeoff: preserving reflection shape keeps .NET compatibility. Performance tradeoff: reflection-heavy code will not be the peak-performance subset.

## NativeAOT, Trimming, And Deployment Modes

N# should be AOT-friendly by construction, but not AOT-only.

Required compiler work:

1. Add an AOT-safety fact to Bound IR and diagnostics.
2. Avoid hidden reflection dependencies in compiler-generated code.
3. Generate source/metadata annotations when a public API requires reflection.
4. Add `nlc publish` evidence for NativeAOT only after template and dependency workflows are tested.
5. Benchmark both tiered JIT+PGO and NativeAOT for any claim.

### Decision: Default Runtime Mode

Recommendation: default to normal .NET JIT for compatibility; offer NativeAOT as an explicit publish mode later.

| Option | Interop cost | Performance impact | Decision |
| --- | --- | --- | --- |
| JIT only | Best dynamic/reflection compatibility | Slower startup, larger runtime footprint | Current default. |
| NativeAOT default | Breaks some reflection/dynamic/plugin patterns | Better startup/deployment profile | Too expensive for v1 default. |
| Explicit AOT mode with diagnostics | User chooses tradeoff | Clear deployment story | Recommended future path. |

### Implemented: AOT-Blocker Analysis, `--aot` Mode, And Annotations

The first slice of the "explicit AOT mode" is shipped. It is analysis-only — N# does **not**
emit a native image yet; `nlc publish --aot` is explicit about that.

**Analysis pass.** `AotBlockerAnalyzer` (in `src/NSharpLang.Compiler/Performance/`) walks every
parsed compilation unit and records each construct that prevents Native AOT or trimming:

| Construct | `AotSafetyKind` | Diagnostic |
| --- | --- | --- |
| Reflection (`GetType`, `GetMethod`, `GetProperty`, `GetCustomAttributes`, …) | `MetadataRequired` | NL960 |
| Dynamic code (`Activator.CreateInstance`, `DynamicInvoke`, `CreateDelegate`) | `DynamicCodeRequired` | NL961 |
| Runtime generic instantiation (`MakeGenericType` / `MakeGenericMethod`) | `DynamicCodeRequired` | NL962 |
| Expression trees (`Expression.*`, `.Compile()`) | `ExpressionTreeRequired` | NL963 |

Detection is shape/name-based over the AST — N# has no dedicated reflection syntax, so the pass
recognizes the well-known BCL entry points. `nameof(...)` is compile-time and is never flagged.
Each blocker is attributed to its enclosing declaration and ABI boundary (via `AbiClassifier`),
and the corresponding `PerformanceFacts` (`AotSafety` + `Escape = ReflectionBoundary`) are recorded
into the shared `PerformanceFactStore`. The pass runs on every analysis (it changes no behavior on
its own), so the facts are always available.

**`--aot` strict gate.** `nlc build --aot` and `nlc check --aot` promote every blocker to a
build-blocking, Elm-quality error: clear title, source caret, a "why this blocks AOT" explanation,
and a concrete fix hint. `nlc publish --aot` runs the same gate (analysis-only) and prints a notice
that no native image is produced this release. Without `--aot`, blockers are not errors.

**Public-API annotations.** Independent of the strict gate, ordinary builds stamp the BCL
attributes `[RequiresUnreferencedCode]` (reflection) and `[RequiresDynamicCode]` (dynamic code /
runtime generics / expression trees) onto **public** methods that contain blockers, so downstream
C#/AOT consumers see the same warnings the .NET libraries emit. Only the public CLR surface is
annotated; file-private/internal/local code is invisible to consumers and is left alone. Attribute
emission is metadata-only — it never changes a method's IL body — so emitted IL stays verifiable
and GC-safe.

**Perf report.** `nlc build --perf-report` now populates the previously-empty `aotBlockers` array
with `{ code, kind, file, line, column, construct, enclosingBoundary, enclosingDeclaration,
onPublicSurface }` for each blocker. The report shape is stable and versioned by the envelope's
`schemaVersion`.

Not yet done (future phases): native image generation, trimming roots/feature switches, and
benchmark evidence comparing JIT+PGO against NativeAOT.

## SIMD And Hardware Intrinsics

N# should not invent a vector model before the basic IL is strong. It should first expose .NET's existing SIMD safely.

Required compiler work:

1. Make `System.Numerics.Vector<T>` and hardware-intrinsic APIs work cleanly through imports.
2. Add analyzer recognition for vector-friendly loops.
3. Add optional auto-vectorization guidance diagnostics before attempting compiler vectorization.
4. Only add N# vector syntax after benchmark evidence shows .NET APIs are too cumbersome.

### Decision: Auto-Vectorization

Recommendation: defer. Let RyuJIT and explicit .NET vector APIs carry this initially.

Language tradeoff: no new syntax. Performance tradeoff: users write explicit vector code for peak SIMD until evidence justifies language support.

### Decision: Arithmetic Overflow Semantics And Bounds-Check-Elision-Friendly Loops

N#'s language-level default overflow semantics are **unchecked** (wraparound), matching C#'s
default. This is fixed by the language spec (`docs/DESIGN.md`) and the
`examples/11-advanced-features/CheckedUnchecked` example: integer arithmetic outside an explicit
`checked(...)` region wraps on overflow and emits the plain CLR opcodes (`add`/`sub`/`mul`), never
the `*.ovf` variants. An explicit `checked(...)` region is honored exactly — it emits the `*.ovf`
opcode and throws `OverflowException` at runtime. `unchecked(...)` is the explicit opt-out and is
the same as the default.

Because the default is already unchecked, the performance-relevant guarantee is narrow but
load-bearing for hot loops:

1. **Compiler-introduced induction arithmetic stays unchecked unconditionally.** The index
   increment (`i++`) emitted by the array and span foreach fast paths is always a plain `add`,
   independent of `_overflowCheckingEnabled`. Even when the loop *body* contains a `checked(...)`
   expression, only that user expression gets `*.ovf`; the induction must not.
   A poisoned induction (`add.ovf`) would defeat RyuJIT's loop optimizations and add a per-iteration
   overflow check that the language never asked for.

2. **Array index loops use the RyuJIT range-check-elimination idiom.** The array foreach fast path
   emits: index initialized to `0`; a loop test that compares the index against the array's *own*
   length via a fresh `ldlen` (deliberately not cached in a local — caching defeats array BCE);
   monotonic `i++`; and `ldelem*` on the same array. This is the canonical
   `for (int i = 0; i < arr.Length; i++) arr[i]` shape that RyuJIT proves `0 <= i < arr.Length` for
   and elides the per-element bounds check. The span fast path caches `Length` once (spans have no
   `ldlen`) and reads elements through `GetReference` + `Unsafe.Add` + `ldind`, the same shape the
   span indexer lowers to.

Note that N#'s `checked`/`unchecked` are **expression-scoped** (`checked(expr)`); there is no
`checked { block }` statement form, so a `for` loop can never be syntactically wrapped in a checked
context. A `checked(...)` expression appearing in a loop body affects only its own arithmetic; the
generated induction and bounds-check shape around it stay unchecked.

All emitted IL stays fully verifiable (ILVerify clean) and GC-safe.

**Status: already correct, now regression-locked.** This unit found no codegen gap. The
default-unchecked arithmetic emission (`ILCompiler.Operators.cs` / `ILCompiler.cs` `EmitBinary`),
the `checked(...)`-only `*.ovf` path (`TryEmitCheckedBinaryOperator`, gated on the `false`-default
`_overflowCheckingEnabled` flag), and the array foreach BCE idiom (`EmitForeachForArray`, with the
induction's plain `add` emitted unconditionally — never under the overflow flag) were already
implemented as described above. The truth was confirmed by disassembling the IL of a compiled
probe (`sumArray`/`checkedAdd`/`plainAdd`): `sumArray` shows `ldc.i4.0`-init,
`ldloc ; ldloc ; ldlen ; conv.i4 ; bge` per-iteration test (exactly one `ldlen`, length not cached),
`ldelem.i4`, plain user `add`, and a plain `ldc.i4.1 ; add` induction with zero `*.ovf`;
`checkedAdd` emits a lone `add.ovf`; `plainAdd` emits a lone `add`. ILVerify reports the probe DLL
clean (zero errors). No `ILCompiler` source change was made — this unit adds only the regression
tests below.

Regression coverage: `tests/PerfEvidence/ArithmeticAndLoopShapeTests.cs` pins both the IL shape and
the behavior:

- **IL shape (contiguous-sequence assertions, not bare opcode counts):** the array loop test reads
  the length fresh per iteration (`ldlen ; conv.i4 ; bge`, with exactly one `ldlen`, proving the
  length is not cached in a local), loads elements via `ldelem.i4 ; stloc`, and increments
  monotonically (`ldc.i4.1 ; add`). Unchecked paths contain zero `*.ovf` opcodes; an explicit
  `checked(x + y)` emits exactly one `add.ovf` (and zero plain `add`); a `checked(...)` expression
  inside a loop body emits exactly one overflow opcode total (the user add) and leaves the induction
  and BCE shape intact.
- **Behavior:** `checked(int.MaxValue + 1)` throws `OverflowException`; the default unchecked
  `int.MaxValue + 1` wraps to `int.MinValue`; array-foreach sums are numerically correct.

Language tradeoff: none — this matches the existing spec. Performance tradeoff: none on the safety
side; the win is keeping hot loops free of spurious overflow checks and bounds checks.
### Status (verified): explicit SIMD works; compiler auto-vectorization deferred

**Part 1 — explicit `System.Numerics` SIMD: done, no code change required.** The compiler's
existing operator-overload resolution (`ILCompiler.Operators.cs`:
`TryEmitBinaryOperator` → `ResolveBinaryOperatorMethod` → `ResolveReflectionStaticMethod`)
already recognizes the static `op_Addition`/`op_Subtraction`/`op_Multiply`/... methods on
`Vector<T>`, `Vector2`, `Vector3`, and `Vector4` (and on `System.Runtime.Intrinsics` vector
types, which expose the same operators). For `a + b` on a vector type it emits a direct
`call op_Addition`, leaving the value types on the evaluation stack — **zero boxing, no virtual
dispatch, ILVerify-clean**. `new Vector<int>(array)` and `vec.CopyTo(array)` likewise bind to
the public ctor/method and emit verifiable IL. This is locked in by
`tests/PerfEvidence/SimdVectorShapeTests.cs` (trait `Category=Simd`), which pins both the IL
shape (direct intrinsic `call`, no `box`/`newobj`/`callvirt`) and behavioral parity
(vectorized `Vector<int>` add/multiply are bit-identical to the scalar wrapping result;
`Vector3` component results match the BCL).

**Part 2 — compiler-driven auto-vectorization of scalar element-wise loops: intentionally
deferred.** Rewriting `while i < n { c[i] = a[i] + b[i]; i = i + 1 }` into a strided
`Vector<T>` loop with a scalar remainder is a real semantic optimization, not a small add-on,
and the marginal value over the JIT is unproven. Even a *verifiable* (no unsafe-memory IL)
implementation built on `new Vector<T>(array, index)` / `op_Addition` / `CopyTo` must still
prove a large set of preconditions to stay correct — and verifiable IL prevents x64 *crashes*
but not wrong *results* or wrong *exception timing*. Given the recent x64-only GC-unsafe-IL
regression, the conservative call is to keep ordinary scalar loops scalar (a fallback pinned by
`ScalarElementWiseLoop_StaysScalar_NoVectorTypesEmitted`) and let RyuJIT + explicit vector APIs
carry SIMD for now. (Note: RyuJIT reliably elides *some* bounds checks and accelerates *some*
fixed-shape memory operations, but does **not** reliably SIMD-lower arbitrary three-array
integer arithmetic loops — so "the JIT already does it" is not a sufficient justification on its
own; the justification is risk/value, below.)

**Reopen criteria for compiler auto-vectorization (all required):**

1. Benchmarks (BenchmarkDotNet on the compiled assembly, on both arm64 and **Linux x64**) show
   the current N# scalar lowering is *not* already handled well by RyuJIT for the target loop
   shapes, i.e. there is a real, measured speedup to capture.
2. A managed `Vector<T>` rewrite shows a meaningful, consistent speedup across supported
   runtimes/architectures (no regression on small/odd `n`).
3. Recognizer rules are specified narrowly (exact loop shape: single induction var mutated only
   by the `i + 1` step; condition exactly `i < n`; single-statement element-wise body with an
   identical index expression on all sides; integer-wrapping op only — float forbidden;
   SZ-array element type supported by `Vector<T>`; induction var not captured or used after the
   loop; `n`/arrays side-effect-free) and tested heavily with **negative** cases.
4. Dedicated tests cover exception timing, aliasing (`c` aliasing `a`/`b`), null arrays,
   bounds, partial-write-then-throw, and the remainder tail.
5. The scalar fallback **reuses the original lowering path** (the guard only selects the vector
   fast path; a failed guard must execute the unmodified scalar loop so partial-write/throw
   semantics are preserved) rather than duplicating loop semantics by hand.
6. Verification gate: ILVerify-clean and a green `--filter Simd` run inside the amd64 Docker
   lane with `--blame-crash`.

## Diagnostics And Tooling

A performance-by-default language still needs explainability. Developers should be able to ask why code allocated or dispatched virtually.

Required tooling:

1. `nlc query perf --file --pos`: explain allocation, dispatch, capture, and ABI facts for a selected expression/function.
2. `nlc build --perf-report`: emit JSON with schema version, allocation sites, delegate sites, boxing sites, virtual/interface dispatch, closure captures, and AOT blockers. The envelope and AOT-blocker facts exist today; the other categories are reserved arrays until their fact sources are wired up.
3. `IlShapeInspector` (in `NSharpLang.Compiler.Performance`): deterministic per-method IL-shape summaries (`newobj`/`box`/`callvirt` vs `call`/delegate ctors), currently used by compiler regression tests and available to wire into future CLI perf facts. (A wall-clock `nlc bench` command was prototyped and removed — see `memory/limitations.md`; use BenchmarkDotNet directly on the compiled assembly for timings.)
4. Stable schema versions for all performance reports.

### Decision: Performance Diagnostics Before Optimizer Completeness

Recommendation: yes. Explainability should land early so optimization work can be validated by users and tests.

Interop/language tradeoff: none. Tooling cost: additional schema discipline.

## Evidence Gates

No performance feature is complete until it has all applicable evidence:

1. **Semantic tests**: behavior preserved, including mutation, lifetime, null, async, and interop cases.
2. **IL-shape tests**: direct calls, delegate allocations, closure allocations, boxing, `callvirt`, cache fields, struct/class layout, and lifted storage are counted where relevant.
3. **BenchmarkDotNet results**: matched-shape N# vs C#, idiomatic C#, allocation counts, environment info, and raw JSON/Markdown.
4. **Regression budget**: if an optimization helps one benchmark but harms ordinary code, the decision must be documented.
5. **Docs**: public docs must state what the evidence proves and what it does not prove.
6. **IL verifiability**: every emitted assembly must pass ECMA-335 IL verification (the IL Verification Gate below). Performance-driven IL changes must stay verifiable and GC-safe.

### IL Verification Gate

PR #160 shipped GC-unsafe IL that the JIT only rejected at runtime on Linux
x64; macOS/Windows happened to tolerate it and CI never ran an x64 leg or any
IL verifier, so the bug shipped. The IL Verification Gate closes that hole by
making unverifiable IL a deterministic, host-independent, **blocking** failure.

- **Single source of truth**: `scripts/ilverify.sh`. It is invoked by both CI
  (`.github/workflows/build.yml`, the blocking `ilverify` job on
  `ubuntu-latest`) and the local full-suite gate
  (`tests/scripts/test-all-core.sh`, Step 10b). There is exactly one place that
  defines what "verifiable" means for N#.
- **What it does**: builds every example project, every single-file example,
  and the `issue-tracker` fixture with `nlc build`, locates each emitted output
  assembly, and runs `dotnet ilverify` against it, resolving the BCL and
  ASP.NET shared frameworks (auto-discovered via `dotnet --list-runtimes`, so it
  works on Homebrew, apt, and CI .NET layouts) plus sibling output DLLs.
- **Exit-code caveat**: `dotnet ilverify` is parsed by output, not exit code —
  a clean run prints `... Verified.`, verification errors print `[IL]:`/`[MD]:
  Error` lines, and an internal ilverify crash prints a stack trace with no
  summary. The script classifies each case explicitly. A genuine usage/load
  failure (bad refs) is a hard error and is never allowlisted.
- **Baseline allowlist**: `scripts/ilverify-baseline.txt` records known,
  pre-existing findings in the normalized form
  `<Assembly.dll> | <kind> | <detail>` (kinds: `IL:<Code>`, `MD`, `CRASH`). The
  gate fails only on findings **not** in the baseline, so it catches NEW
  unverifiable IL — exactly the #160 regression class — while pre-existing debt
  is tracked, not silently ignored. The baseline is intentionally small and
  every entry is debt. Regenerate it deliberately with
  `scripts/ilverify.sh --update-baseline` and review the diff. The current
  baseline captures real, pre-existing emitter bugs (struct `Equals`
  receiver-type confusion, `int`/`double` conversion mismatches, init-only field
  writes outside `.ctor`, an interface-method emission gap, and an ilverify
  crash on the lock-statement lowering); these are tracked for a follow-up
  emitter fix and must not grow.
- **Why blocking from day one**: confirmed by the product owner. A non-blocking
  verifier is how #160 happened.

## Benchmark Corpus And IL-Shape Gate

The performance claims are backed by two coupled artifacts, one per optimized pattern.

### 1. Matched N#-vs-C# benchmark corpus (`benchmarks/`)

`benchmarks/NSharpLang.Benchmarks.csproj` is a BenchmarkDotNet project with one benchmark class per
pattern. Each class binds the N# probe to a typed delegate in `[GlobalSetup]`
(`NSharpCompiledMethod.Bind<TDelegate>`) and pairs it with a hand-written, same-algorithm C#
baseline so the comparison is a fair, matched-shape one.

The project is **deliberately outside** the default `dotnet test` path and is **not** in
`NSharpLang.sln`: it produces manual, wall-clock before/after numbers for a PR, never a CI gate
(wall-clock is non-deterministic). Run it manually:

```bash
# whole corpus (Release is mandatory for real numbers)
dotnet run -c Release --project benchmarks -- --filter '*'
# one family
dotnet run -c Release --project benchmarks -- --filter '*ForeachArray*'
# fast smoke check that it still executes (not for real numbers)
dotnet run -c Release --project benchmarks -- --filter '*' --job Dry
```

Results land in `BenchmarkDotNet.Artifacts/` (git-ignored). `[MemoryDiagnoser]` on every class makes
the allocation column the load-bearing signal: e.g. the array/span/value-union families report
0 B/op, and the static-lambda family allocates only the backing `List<>` (the delegate itself is
cached, so it does not show up per-iteration).

Current families (matched to the PR #160 optimizations):

| Benchmark class                  | Pattern                                   | Probe method |
| -------------------------------- | ----------------------------------------- | ------------ |
| `ForeachArrayBenchmarks`         | `foreach` over `T[]`                       | `sumArray`   |
| `ForeachSpanBenchmarks`          | `foreach` over `ReadOnlySpan<T>`           | `sumSpan`    |
| `ValueUnionBenchmarks`           | payload-free value-struct union            | `classify`   |
| `ConstrainedDispatchBenchmarks`  | constrained generic dispatch (no box)      | `run`        |
| `StaticLambdaBenchmarks`         | cached non-capturing lambda in a loop      | `build`      |
| `ErrorTupleBenchmarks`           | `(result, err)` tuple, no throw on success | `RunSuccess` |

### 2. Deterministic IL-shape regression gate (`tests/PerfEvidence/IlShapeRegressionTests.cs`)

This is the **ratchet**. Unlike `ILShapeBaselineTests` (which documents the *current* shape so the
refactor can show progress), each test here pins the *optimized* shape of a hot path so a later
change cannot silently regress it. The tests are deterministic (decoded IL counts, no wall-clock),
reuse the existing `ILShapeInspector` harness, and ship inside `tests/Tests.csproj`, so CI enforces
them on every change. The pinned invariants:

| Test                                                                  | Pinned invariant                          |
| --------------------------------------------------------------------- | ----------------------------------------- |
| `Gate_ForeachOverArray_AllocatesNoEnumerator_AndDispatchesNothing`    | `newobj == 0`, no `call`/`callvirt`, `ldlen` present |
| `Gate_ForeachOverSpan_AllocatesNoEnumerator`                          | `newobj == 0`                             |
| `Gate_ValueStructUnion_DoesNotBox`                                    | union is a value type, `box == 0`         |
| `Gate_ConstrainedGenericDispatch_UsesConstrainedCallvirt_AndDoesNotBox` | `constrained.` + `callvirt`, `box == 0` |
| `Gate_StaticLambdaInLoop_ConstructsDelegateAtMostOnce`                | delegate-ctor `<= 1`                       |
| `Gate_ErrorTupleSuccessPath_SynthesizesNoThrow`                       | success path has no `throw`/`rethrow`      |

### Adding a new optimized pattern

When a later unit optimizes a new pattern, add **both** artifacts in the same change:

1. **Benchmark**: add `benchmarks/<Pattern>Benchmarks.cs` with a `[MemoryDiagnoser]` class. Put the
   N# probe in a `const string Source`, bind it in `[GlobalSetup]` via
   `NSharpCompiledMethod.Bind<TDelegate>(Source, "<method>")`, and write a matched C# `[Benchmark(Baseline = true)]`.
   For ref-struct parameters (`Span<T>`), declare a custom delegate type — a `Func<>` cannot carry a ref struct.
2. **IL gate**: add a `Gate_<Pattern>_<Invariant>` test to `IlShapeRegressionTests.cs` that compiles
   the same probe with `ILShapeInspector.Compile`/`GetProgramMethod` and asserts the pinned opcode
   counts (`AssertCallCount`, `AssertNoBoxing`, `CountDelegateConstructions`, etc.).
3. **Verify GC-safe IL**: build the probe with `nlc build <probe>.nl` and run
   `dotnet ilverify <dll> -r '<shared-runtime>/*.dll' -r '<outdir>/*.dll'` — it must report zero
   errors. Reference the **shared runtime** dir (it has `System.Private.CoreLib`), not the ref pack.
4. **Cross-platform crash check**: run the gate under amd64 Linux with a crash detector —
   `docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src mcr.microsoft.com/dotnet/sdk:10.0 bash -c "dotnet test tests/Tests.csproj --filter IlShapeRegression --blame-crash"` —
   to catch the GC-unsafe-IL class of bug that only manifested on Linux x64 in PR #160.

## Implementation Roadmap

### Phase 0: Evidence Discipline

- Keep the external scratch benchmark lab outside the repo.
- Add reusable IL-shape inspection helpers in tests.
- Add a performance evidence index under `memory/` once more benchmark families exist.
- Do not publish comparative claims without dated artifacts.

### Phase 1: Bound IR And Facts

- Introduce Bound IR for functions, locals, calls, lambdas, loops, and basic type constructs.
- Attach escape/capture/allocation/dispatch facts.
- Keep IL emission behavior identical where no optimization is enabled.
- Acceptance: all current tests pass; selected IL-shape tests can read facts or emitted shape.

### Phase 2: Function-Value Completion

- Move current direct local-function/lambda logic into the fact-driven lowering pass.
- Add method-group direct lowering where shadowing and overload rules are proven.
- Improve escaped delegate-boundary code shape.
- Acceptance: delegate-boundary benchmark gap is reduced or explicitly explained by IL/JIT shape.

### Phase 3: Value Layout And Union Strategy

- Implement internal tagged-struct unions for non-public small unions.
- Add readonly/newtype struct lowering where semantics permit.
- Add no-boxing generic/value tests.
- Acceptance: union/newtype benchmarks report allocation reductions without public ABI regressions.

### Phase 4: Loop/Span/Collection Lowering

- Add first-class span/ref-safety analysis.
- Lower common array/span/list loops to allocation-free direct loops.
- Emit diagnostics for allocations from enumerators or collection expressions.
- Acceptance: loop benchmarks match C# IL shape for arrays/spans and explain remaining gaps.

### Phase 5: Generic Specialization And Dispatch

- Selectively specialize private/internal generic hot paths.
- Devirtualize exact receivers and duck-interface calls.
- Avoid interface boxing with `constrained.` calls.
- Acceptance: boxing/interface-dispatch IL-shape tests and targeted generic benchmarks.

### Phase 6: AOT And Deployment

- Add AOT-safety diagnostics.
- Add NativeAOT publish mode only when templates, reflection annotations, and dependencies are verified.
- Benchmark JIT+PGO against AOT before recommending either.

## Decision Log Template

Every major optimization should add a short decision record:

```text
Decision:
Scenario:
Chosen lowering:
Rejected alternatives:
Language behavior sacrificed:
Interop sacrificed:
Evidence:
Open risks:
Rollback plan:
```

## References

- .NET runtime compilation configuration, including tiered compilation and PGO: https://learn.microsoft.com/en-us/dotnet/core/runtime-config/compilation
- Native AOT deployment and limitations: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/
- .NET garbage collection fundamentals: https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/fundamentals
- .NET memory and spans overview: https://learn.microsoft.com/en-us/dotnet/standard/memory-and-spans/
- .NET SIMD/hardware acceleration overview: https://learn.microsoft.com/en-us/dotnet/standard/simd
