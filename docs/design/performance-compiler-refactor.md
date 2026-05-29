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

## Diagnostics And Tooling

A performance-by-default language still needs explainability. Developers should be able to ask why code allocated or dispatched virtually.

Required tooling:

1. `nlc query perf --file --pos`: explain allocation, dispatch, capture, and ABI facts for a selected expression/function.
2. `nlc build --perf-report`: emit JSON with schema version, allocation sites, delegate sites, boxing sites, virtual/interface dispatch, closure captures, and AOT blockers.
3. `nlc bench --explain`: attach IL-shape summaries to benchmark output.
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
