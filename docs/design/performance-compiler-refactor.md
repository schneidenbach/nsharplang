# N# Performance Compiler Refactor

Status: superseded as a pipeline plan — retained for optimization principles, per-section status, and evidence discipline
Updated: 2026-06-10 (substance originally 2026-05-27)

> **Read alongside [`columnar-pipeline.md`](columnar-pipeline.md) (decided 2026-06-06; standalone-pipeline
> routing decision 2026-06-08).** The self-host endgame makes flat **columnar node tables** the single
> intermediate representation end-to-end (parse→bind→analyze→codegen, no internal C# AST). As of
> 2026-06-09, Phase S Stages 3b/4/5 are DONE — the standalone columnar pipeline owns parse→emit for the
> modeled surface (32/32 dogfood corpus), routed by default with `NSHARP_COLUMNAR_BACKEND=0` as the
> explicit C#-backend opt-out; live work is the Phase D rich-language emit arc
> ([`self-host-progress.md`](self-host-progress.md) is the cursor). The
> tree-based "Analyzer → Bound IR" pipeline proposed below will NOT be built: the C# `ILCompiler/` and
> `Analyzer.cs` it would refactor are slated for deletion at Stage 6
> ([`roadmap-to-done.md`](roadmap-to-done.md)). The optimization *principles* in this doc —
> escape/capture analysis, allocation-fact tracking, dispatch classification, value layout — remain
> valid, and many shipped directly in the existing emitter (dated statuses below, per section). Where
> this doc and the columnar plan conflict, the columnar pipeline is authoritative.

This document defined the compiler refactor proposed in May 2026 to make N# a performance-by-default CLR language. The performance outcome was instead delivered in the existing emitter (most recently Phase P auto-vectorization, complete 2026-06-07 — see [`systems-vs-native.md`](systems-vs-native.md)), and the columnar pipeline supersedes the Bound-IR plan. The doc remains intentionally conservative about public claims: CLR interop remains a first-class product value, and every optimization that weakens interop or changes language behavior must be justified by dated BenchmarkDotNet output, IL-shape evidence, and compatibility tests.

## Product Position

N# should target this performance envelope:

- **Default goal**: C#-class performance for ordinary .NET code without user ceremony.
- **Aspirational goal**: Go-like performance for allocation-light services, CLIs, parsing, data processing, and server hot paths.
- **Bounded non-goal**: Rust/C++/Zig parity for workloads dominated by manual layout, arena ownership, deterministic destruction, whole-program monomorphization, or no-GC latency constraints.

**Measured update (2026-06-07):** with Phase P per-pattern auto-vectorization (default-on), systems-N# beats C#/RyuJIT ~2–6× on vectorizable kernels and is ≤2.02× of best Rust/C at `N=4096` (worst small-input cell 2.49×) — see [`systems-vs-native.md`](systems-vs-native.md). [`roadmap-to-done.md`](roadmap-to-done.md) now codifies "Rust-class perf" (within ~2× of Rust/C on the vectorizable hot kernels) in its Definition of DONE. The bounded non-goal above still holds for workloads dominated by manual layout, arena ownership, deterministic destruction, whole-program monomorphization, or no-GC latency — do not generalize the six-kernel result.

The CLR is not the only bottleneck. Recent function-value work showed that N# emitted delegate-heavy IL in places where direct helper calls were legal. Fixing the emission changed a repeated local-lambda benchmark from allocation-heavy microseconds to allocation-free hundreds of nanoseconds. That is compiler headroom, not runtime inevitability.

The real constraint is sharper: N# must emit IL that the .NET JIT, tiered PGO, NativeAOT, GC, and C# consumers can all understand. When N# emits object-heavy, delegate-heavy, interface-heavy, or reflection-sensitive shapes, it pays those costs. When it emits simple calls, contiguous value data, spans, direct field access, and allocation-free loops, the CLR can be very fast.

## Evidence Baseline

Dated evidence from the external scratch lab, run on 2026-05-27 with BenchmarkDotNet ShortRun, Apple M4, .NET 10.0.5, `N=1024`. As of 2026-06-10 these are still the latest function-value numbers, but they predate the 2026-05-30 closure-lowering batch (`361c2fdc`, `72eec29a`, both touching `ILCompiler/LambdaEmitter.cs`) — re-measure with the in-repo `benchmarks/StaticLambdaBenchmarks.cs` (added 2026-05-30) before relying on the lambda rows. The lowering shapes themselves are pinned by `tests/PerfEvidence/ClosureCaptureILShapeTests.cs` and `StructClosureILShapeTests.cs`; newer dated evidence for the systems kernels lives in [`systems-vs-native.md`](systems-vs-native.md) (2026-06-07).

| Scenario | Current N# Result | Matched C# Result | Interpretation |
| --- | ---: | ---: | --- |
| Direct loop | 500.344 ns / 0 B | 514.132 ns / 0 B | N# is already in the same range. |
| Top-level call loop | 484.405 ns / 0 B | 489.025 ns / 0 B | Direct calls are viable. |
| Local function direct | 489.561 ns / 0 B | 481.785 ns / 0 B | Close enough that long-run validation matters more than micro claims. |
| Lambda local direct | 487.095 ns / 0 B | 492.174 ns / 0 B | Direct lambda-local lowering works. |
| Lambda escaped boundary | 487.124 ns / 0 B | 274.111 ns / 0 B | Real gap as of 2026-05-27; unmeasured since. Diagnosed 2026-06-10 — see Function Values below. |
| Lambda captured local-only | 483.615 ns / 0 B | 280.664 ns / 24 B | N# eliminated allocation but still has code-shape/JIT gap. |
| Repeated lambda creation in loop | 263.401 ns / 0 B | 8,402.815 ns / 90,112 B | N# can beat idiomatic delegate allocation when escape analysis proves local-only use. |

Do not publish broad "Go speed", "Rust speed", or "faster than C#" claims from this table. It proves that specific compiler lowering choices matter and that wrapper shape plus IL shape must be reported with benchmarks.

## Runtime Realities

The design must treat these CLR facts as product constraints:

- **Delegates are reference types.** Public or escaping function values must use CLR delegate semantics unless N# intentionally introduces a non-CLR internal ABI.
- **Escaping closure state normally requires heap representation.** The compiler can remove over-capture and avoid lifted boxes for readonly captures, but it cannot keep arbitrary escaping closure state on the caller stack.
- **GC is part of the platform.** Allocation elimination is still the main hot-path lever; GC tuning is secondary.
- **JIT quality is pattern-sensitive.** Simple IL with direct calls, obvious loops, value types, and spans gives the runtime more room than reflection-heavy or virtual-heavy IL.
- **RyuJIT does not auto-vectorize loops.** Clean scalar IL stays scalar. N# therefore emits `System.Numerics.Vector<T>` IL directly for the canonical hot-loop shapes (counted reductions, range-predicate counts, min/max, count-transitions) — shipped 2026-06-06/07, default-on with `NSHARP_VECTORIZE_REDUCTIONS=0` opt-out; see [`systems-vs-native.md`](systems-vs-native.md).
- **NativeAOT is a deployment mode, not a magic optimizer.** It can improve startup and trim/runtime footprint, but it has reflection/dynamic-code limitations and may not beat tiered JIT plus PGO for every throughput workload.
- **Reference-type generic sharing limits Rust-style specialization.** The compiler specializes N#-internal paths (shipped 2026-05-30: `Performance/GenericSpecializer.cs` — selective monomorphization of private/file-private generics over value types, public CLR generic ABI untouched for C# interop), but public CLR generic semantics still matter.

## Refactor Architecture

**SUPERSEDED (2026-06-08).** The explicit-IR pipeline below was never built as drawn. The self-host decision ([`roadmap-to-done.md`](roadmap-to-done.md) Stage 4j; [`columnar-pipeline.md`](columnar-pipeline.md)) makes the standalone columnar pipeline's flat node tables the single IR end-to-end, and the C# `Analyzer`/`ILCompiler` this diagram would have refactored are slated for deletion at Stage 6 once columnar coverage completes. The non-IR stages DID ship inside the C# pipeline: Performance Facts (`Performance/PerformanceFacts.cs` + `PerformanceFactStore`, position-keyed, 2026-05-29), the ABI Classifier (`Performance/AbiClassifier.cs` — shipped taxonomy `ClrPublic`/`ClrInternal`/`FilePrivate`/`Local`; AOT/trimming safety is classified separately via `AotSafetyKind` + `AotRequirements`, not as an ABI boundary), AOT-safety analysis (`AotBlockerAnalyzer`), and the IL-shape + benchmark evidence gates (`tests/PerfEvidence`, the ILVerify gate, the Systems BDN gate). Any future IR-level facts attach to the columnar tables, not a tree-based Bound IR.

The original (historical) framing: the backend is effectively `AST + semantic helpers -> IL`, judged too direct for a performance-focused compiler, motivating an explicit performance lowering pipeline:

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

**DECISION OVERTAKEN (2026-06-08).** No Bound IR was added. The performance program (the 2026-05-30 13-unit batch and the 2026-06-06/07 Phase P auto-vectorization — Rust-class results, default-on) shipped directly in the existing AST emitter — the option the table below relegated to "small tactical fixes" — and the optimization source of truth going forward is the standalone columnar pipeline: its flat node tables ARE the IR. Do not invest in a tree-based Bound IR inside the C# `ILCompiler`/`Analyzer`; those components retire at Stage 6, and until then the C# pipeline serves as the parity oracle. The original recommendation ("add a bound IR, keep it narrow, make it the optimization source of truth") and its option table are retained for the record:

| Option | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| Continue optimizing the AST emitter | Fastest near-term patches | Hard to reason about scopes, captures, overloads, and lowering correctness | Use only for small tactical fixes. |
| Add a full Roslyn-style bound tree | Clean semantic model | Large refactor and longer runway | Target long-term, but do not block performance work on full parity. |
| Add a minimal Bound IR for functions/expressions/hot constructs | Enough for escape, ABI, value layout, dispatch, and allocation analysis | Requires dual maintenance during transition | Recommended first architecture step. |

Interop tradeoff: none if Bound IR preserves current metadata emission. Language tradeoff: none.

## Performance Facts

Shipped (2026-05-29): performance facts are explicit data, not implicit local booleans scattered through emitters — `Performance/PerformanceFacts.cs` records all six fact categories in a `PerformanceFactStore` keyed by source position, populated during `MultiFileCompiler` analysis and consumed by the systems analyzer, `nlc query`, and code intelligence. (They are not attached to Bound IR nodes — none exist; when the columnar pipeline takes over analysis, facts attach to columnar table rows / symbol IDs.)

The fact categories:

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
| User opt-in unsafe/perf mode | Adds language/project complexity | Useful for narrow domains | SHIPPED 2026-06-01 as Systems N# — an optional per-project lane (project.yml `language.systems.*`) with systems-oriented checks and cost visibility, not an "unsafe" switch; see [`systems-nsharp.md`](systems-nsharp.md). |

## Function Values And Closures

Current rule: CLR delegates remain the public ABI. N# may erase delegates internally when the value does not cross a boundary.

Compiler work (status 2026-06-10):

1. Direct-call lowering for lambda locals and local functions — SHIPPED in the C# ILCompiler (`ILCompiler.LocalFunctions.cs`), not as a Bound IR pass. The generalization target is now the columnar pipeline's lambdas/closures arc (in flight as of 2026-06-10 — L1a delegate-type plumbing and L1b non-capturing call-argument lambda literals have landed; [`self-host-progress.md`](self-host-progress.md) is the live cursor), which must carry this lowering forward when columnar takes ownership of function-value emission.
2. Track exact escape reason: direct local call, argument to known inlineable helper, stored local, returned, field, array, interface, expression tree, `Delegate`, `MulticastDelegate` — OPEN (no such taxonomy in code beyond the coarse `EscapeKind` facts).
3. Emit direct helper calls for all non-escaping function values, including contextual `Func<>` / `Action<>` locals and method groups — PARTIAL (lambda locals and local functions, see item 1; method-group direct lowering not built).
4. Cache non-capturing escaped lambdas and method groups in static fields — SHIPPED 2026-05-29 (`TryEmitCachedStaticDelegate`, `ILCompiler.Delegates.cs`), covering lambdas, local functions, and method groups. Known gaps (diagnosed 2026-06-10): the cached delegate is static-target (`ldnull`/`ldftn`), the cache field keys per call site rather than per lambda, and caching is disabled method-wide when any generic local function is present (`ILCompiler.Delegates.cs:187`).
5. Avoid closure classes when `this` is not referenced — SHIPPED 2026-05-29/30: no-capture lambdas emit as static methods; this-only captures bind as instance lambdas without a display class; non-escaping mutating local-function captures use struct closures (pinned by `ClosureCaptureILShapeTests` and `StructClosureILShapeTests`).
6. Use normal local storage for readonly captures. Use lifted shared storage only for mutation or lifetime — OPEN (no readonly/mutable capture split found in `LambdaEmitter.cs`).
7. IL-shape diagnostics for function-value allocation — SHIPPED 2026-05-29: `nlc query perf --file <path> --pos <line>:<col>` reports allocation/dispatch/capture/ABI facts, including delegate-allocation and delegate-invoke classifications.

**Delegate-boundary diagnosis (2026-06-10, IL-shape level — benchmark-unconfirmed).** The escaped-boundary gap in the 2026-05-27 baseline (487 ns vs 274 ns) is attributed to delegate shape, not allocation. N# emits non-capturing escaped lambdas as static-target delegates (`ldnull`/`ldftn`/`newobj`, `ILCompiler.Delegates.cs:156-171`), which pay a per-`Invoke` shuffle thunk and resist PGO guarded-devirtualization inlining; Roslyn instead emits closed-instance delegates over a `<>c` singleton display class. Closing the gap requires Roslyn-style instance-lambda emission plus per-lambda delegate caching (fixing the item-4 gaps above) — and a dated `StaticLambdaBenchmarks` re-run must confirm before the gap is claimed closed.

### Decision: Internal Function ABI

Recommendation: keep public CLR delegates, add an internal function ABI only after the current transparent lowering is exhausted.

| Option | What we sacrifice | What we gain | Decision |
| --- | --- | --- | --- |
| Always CLR delegates | No interop cost | Leaves local hot paths slower/allocation-prone | Rejected for internal code. |
| Transparent internal helper calls | No source or public ABI cost | Removes most non-escaping delegate overhead | Current path; continue. |
| First-class internal function pointer ABI | Harder reflection/debugging; possible interop cliffs if it leaks | Faster higher-order internal code | Consider after evidence shows helper-call lowering is insufficient. |
| Public N# function type distinct from delegates | C# interop cost and language complexity | Stronger performance contract | Not for v1. |

Note (2026-06-10): "continue" now means continuing this lowering strategy in the columnar pipeline. The existing transparent lowering lives in the C# ILCompiler, which is scheduled for deletion at Stage 6; the columnar lambdas/closures arc (in flight — opened 2026-06-10, L1a landed) must re-implement direct-call lowering and capture classification natively rather than extending `ILCompiler`.

## Value Layout

N# must stop treating every rich language feature as an object shape. The compiler should choose allocation-free value layouts where interop permits.

Compiler work (status 2026-06-10):

1. Add layout classification for `class`, `record`, `struct`, `readonly struct`, `ref struct`, tuple, newtype, nullable, and union — PARTIAL as of 2026-05-29: ABI-boundary classification (`AbiClassifier`) and union layout classification (`UnionValueLayout`) shipped; a unified layout classifier across the remaining kinds has not been built.
2. Emit small immutable domain wrappers as `readonly struct` where semantics permit — SHIPPED: newtypes and readonly record structs emit as readonly structs (`ApplyIsReadOnlyAttribute`, `ILCompiler.cs`), eliminating defensive copies through `in`/readonly references.
3. Prefer direct fields and init-only properties only when interop requires property shape.
4. Keep public classes and records C#-natural by default.
5. Add explicit layout tests for object header avoidance — SHIPPED 2026-05-29/30: pinned by `ClosureCaptureILShapeTests` (no display class), `StructClosureILShapeTests` (no heap closure box), `IlShapeRegressionTests.Gate_ValueStructUnion_DoesNotBox` (no case object, no box), and `UnionPayloadILShapeTests` (no stray box).

### Decision: Union Representation

Recommendation: split union representation by boundary.

| Option | Interop cost | Performance impact | Decision |
| --- | --- | --- | --- |
| Always class hierarchy cases | Excellent C# consumption | Allocates per case; virtual/type-test cost | Keep for public/non-small unions. |
| Internal tagged struct for closed small unions | C# sees less natural shape if exposed | Allocation-free matches and better locality | Use internally when not exposed. |
| Public tagged struct union | Less idiomatic C# but still consumable | Allocation-free public data | Consider for `readonly`/small unions behind explicit design. |
| Reuse `System.ValueTuple`-like shapes | Familiar CLR value layout | Weak named-case semantics | Use only for compiler-internal lowering, not source ABI. |

Status (shipped 2026-05-29): small (≤16 cases), closed, value-friendly, payload-free, non-generic unions emit as a public readonly tag struct (`Performance/UnionValueLayout.cs` + `DeclareValueStructUnion`) — gating is by shape, not by visibility; the struct IS the union's public, C#-consumable form, which goes further than the table's "behind explicit design" row anticipated. Everything else (payload-carrying, generic, >16 cases) keeps the class hierarchy (pinned by `Gate_ValueStructUnion_DoesNotBox` and `UnionPayloadILShapeTests`; benchmarked by `ValueUnionBenchmarks`). Open: extending value-struct lowering to payload-carrying cases (the Unit 15 scope note in `UnionValueLayout.cs`).

Backend caveat (2026-06-10) — RESOLVED (2026-06-19, columnar now OWNS the layout): the value-struct lowering used to exist only in the C# ILCompiler (`IsValueStructEmittable` → `DeclareValueStructUnion`). Previously the columnar pipeline emitted every union as a class hierarchy, so a columnar-routed build silently swapped the allocation-free public tag struct for heap case objects, and the behavioral parity oracle could not catch the layout difference. `ColumnarIlEmitter` now EMITS the value-struct layout directly for any value-struct-emittable union (small, closed, payload-free, non-generic): a sealed readonly tag struct over `ValueType` with a private `int _tag`, a private `U(int)` ctor, a public `Tag` getter, a nested sealed-abstract marker type per case (`public const int Tag`), and a public static `Create_<Case>()` factory — mirroring `DeclareValueStructUnion`. Construction is the allocation-free factory call; a bare `Union.Case` match is a tag compare; `is`-to-case, `==`, and default-init-field uses that columnar does not yet model decline cleanly to the oracle, which compiles them correctly. (An `is`/`as` whose source is a value-struct union — `c as U.Case`, `c as object`, `c is IFoo`, including aliased/nullable spellings — declines from columnar to the C# oracle, which now BOXES the value before the reference `isinst`, matching C#'s value-type `as`/`is` semantics. This fixed a pre-existing SYSTEMIC segfault: the value-struct work surfaced that the backends isinst'd an unboxed struct because the analyzer models all unions as reference types. `c as U.Case` is null, `c as object` boxes, `c is U.Case` is the tag test, a hard `(U.Case)c` throws a clean InvalidCastException.) The eligibility decision is owned by N# (`ColumnarUnionIsValueStructEmittable` in `ParserColumnarUnions.nl`, mirroring `IsValueStructEmittable`); the columnar-routed value-struct ABI is pinned by `ColumnarCodegen_EmitsValueStructUnion` (IsValueType==true + construct/match parity + the 16/17-case boundary), the oracle's by `ILCompiler_PayloadFreeUnion_IsEmittedAsValueStruct`. So the columnar backend now owns the public value-struct union form rather than declining it.

Language tradeoff: if users can observe identity of union cases, allocation-free unions become harder. Recommendation: do not promise reference identity for union cases unless explicitly class-backed.

Generic unions (shipped 2026-06-10): `union Result<T>` emits as a generic class hierarchy — each nested case redeclares the union's type parameters and derives from the base closed over them (`` Result`1+Success<T> : Result<T> ``). Generic unions are excluded from value-struct layout; a per-instantiation tag representation remains future work.

## String Interpolation

String interpolation is pervasive in idiomatic code, so its lowering directly shapes the allocation profile of typical programs.

Previous lowering built a `string[]`, stored each segment (boxing every value-type hole into `object` and routing through `string.Concat(object)` / `string.Format(string, object)`), then called `string.Concat(string[])`. That path allocated an array per interpolation plus one box per value-type hole.

Current lowering mirrors the C# compiler and targets `System.Runtime.CompilerServices.DefaultInterpolatedStringHandler` (a stackalloc-backed ref struct):

1. Construct the handler with the constant `literalLength` (sum of literal-segment lengths) and `formattedCount` (number of holes), matching the constants C# passes.
2. Emit `AppendLiteral(string)` per literal segment.
3. Emit `AppendFormatted<T>(T)` per hole using the **generic** overload instantiated at the hole's static type, so value-type holes are never boxed. String holes use the dedicated `AppendFormatted(string)` overload. Holes with a format clause use `AppendFormatted<T>(T, string)`.
4. Produce the result with `ToStringAndClear()`.
5. A purely literal interpolation (no holes) folds to a single `ldstr` constant and never allocates a handler.

Two exceptions to the never-box rule (shipped 2026-05-30 in the same batch): `ReadOnlySpan<char>`/`Span<char>` holes route through the dedicated `AppendFormatted(ReadOnlySpan<char>[, int, string])` overloads (a byref-like ref struct can never satisfy a generic type argument), and holes whose type is declared in the current compilation (TypeBuilder/EnumBuilder-backed enums and structs) box through the non-generic `AppendFormatted(object, int, string)` overload — instantiating the generic over a builder type emits an unresolvable MethodSpec token (caught by ilverify). BCL value types keep the zero-alloc generic path; the builder-type boxing shape is pinned by its own IL-shape test.

The handler is a ref struct kept strictly stack-local: it is declared as a local, only ever addressed via `ldloca`, and never stored to a field or captured, so the byref-internal value type stays verifiable and GC-safe (ILVerify-clean; since 2026-05-30 the product-wide unverifiable-IL baseline is empty — pinned by `IlVerifyBaselineEmptyTests` and enforced continuously by the linux/amd64 CI ilverify job over `scripts/ilverify.sh`).

Net effect per interpolation with BCL value-type holes: `box` drops to `0`, the `string[]` allocation (`newarr`) and `string.Concat` call are eliminated (source-declared enum/struct holes deliberately box through the `AppendFormatted(object, ...)` fallback above, and that shape is pinned by its own test). IL-shape regression tests in `ILShapeBaselineTests` pin `box == 0`, `newarr == 0`, no `string.Concat`, exactly one handler ctor + `ToStringAndClear`, and one `AppendFormatted` per hole. Behavioral tests assert exact string parity (including culture-correct `:X` / `:F2` format clauses) against the equivalent C# interpolation.

## String Concatenation

Binary `+` string concatenation is flattened before IL emission. The old lowering emitted every
string addition as a pairwise `string.Concat(object, object)` call, which boxed value-type operands
and materialized intermediate strings for longer chains.

Current lowering keeps pure two-to-four operand string chains on the typed `string.Concat(string, …)`
overloads, folds all-literal chains to one `ldstr`, and routes mixed string/value chains through the
same `DefaultInterpolatedStringHandler` machinery used for interpolation. That preserves left-to-right
evaluation while avoiding `box`, `newarr`, and nested `string.Concat` calls for hot CLI-style command
construction such as `"--pos " + line + ":" + column`.

## Generics And Specialization

The CLR already specializes generic code for value types but shares many reference-type instantiations. N# can still do better for internal code.

Compiler work (status 2026-06-10):

1. Classify generic functions as public ABI, private/internal, or local — SHIPPED 2026-05-30 (`AbiClassifier.ClassifyFunctionBoundary`).
2. Specialize private/internal/local generic functions for all eligible closed value-type instantiations, bounded by a 256-body cap and conservative structural gating (see below) — SHIPPED 2026-05-30; per-instantiation benchmark gating was dropped in favor of the structural gates.
3. Emit `constrained.` calls for value-type interface/generic dispatch to avoid boxing — SHIPPED 2026-05-30.
4. Avoid generic helper shapes that force `object` or interface boxing.
5. Record generic specialization in IL-shape reports — SHIPPED 2026-05-30 (`GenericSpecializer.Skipped` registry + `GenericSpecializationTests`).

### Decision: Monomorphization

Recommendation: selective internal specialization, not global Rust-style monomorphization.

| Option | What we sacrifice | What we gain | Decision |
| --- | --- | --- | --- |
| CLR generic sharing only | Leaves some interface/boxing overhead | Small assemblies, predictable interop | Default public ABI. |
| Selective private specialization | Larger assemblies, more compiler complexity | Better value-type hot paths | Recommended. |
| Whole-program monomorphization | Dynamic loading/reflection interop, build size, AOT complexity | Rust-like codegen potential | Not aligned with CLR product goals. |

### Implementation: Selective Specialization (shipped)

Scope (2026-06-10): everything in this section — and the two string sections above — is implemented in the C# `ILCompiler` backend only. The standalone columnar pipeline (authoritative per the banner, and the planned replacement for `ILCompiler` at Stage 6) does not yet carry these lowerings: it declines interpolated strings at parse, lowers string `+` as pairwise typed `string.Concat(string, string)` with no chain flattening or handler routing, and emits generic functions/types (including `where`-constrained ones, Phases D-15a/b, D-16, D-17b) as ordinary shared CLR generics with no specialization pass. These optimizations must be ported to `ColumnarIlEmitter` (or explicitly re-justified) before `ILCompiler/` is deleted.

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
5. **Constraints**: a generic whose type parameters carry interface/base-type/`class` constraints
   is never specialized — an arbitrary value type may not satisfy the constraint, so a
   monomorphic body could fail to resolve constrained member calls. Only `struct`/`new()`-constrained
   (or unconstrained) generics are eligible (`HasOnlySpecializationSafeConstraints`); pinned by
   `ConstrainedGeneric_StaysShared_NotSpecialized`.

Verification: specialized assemblies pass `ilverify` (the make-or-break gate for this pass)
with zero errors — since 2026-05-30 the product-wide unverifiable-IL baseline is empty
(`IlVerifyBaselineEmptyTests`), so specialization must introduce none. IL-shape regression tests assert `box == 0` and the
absence of a generic-instantiation token for specialized call sites (and that public generics
stay shared), and behavioural parity is checked by invoking specialized programs. See
`tests/PerfEvidence/GenericSpecializationTests.cs` and `tests/GenericSpecializerTests.cs`.

## Dispatch And Interfaces

N# should make concrete dispatch the default on hot paths while preserving .NET polymorphism at boundaries.

Compiler work (items 1–3 shipped conservatively in PR #160, 2026-05-29):

1. Prefer direct calls for local/private functions and sealed/private methods — DONE (top-level functions are static `call`; non-virtual instance methods emit `call`).
2. Devirtualize calls when the receiver type is exact — SHIPPED in conservative form via `CanDevirtualizeInstanceCall` (exactly-typed, provably non-null receivers only: `new T()` and string-producing literals); broader receiver proofs (locals never reassigned to a derived type, sealed receivers) remain open. A catalog performance diagnostic (NL952 "Virtual dispatch not devirtualized", Info) is defined for the misses but is not yet emitted by any pass — wiring it to the recorded dispatch facts remains open.
3. Emit `call` instead of `callvirt` when null-check semantics are unnecessary or already proven — SHIPPED for the same conservative receiver set.
4. Lower duck-interface use to compile-time structural calls when the concrete type is known — NOT IMPLEMENTED.
5. Avoid interface dispatch in compiler-generated loops unless the source explicitly requires abstraction — array/Span foreach lower to enumerator-free index loops (`ldlen` since 2026-06-05); `List<T>`-style collections still dispatch through `IEnumerable<T>`.

### Decision: Duck Interface Runtime Shape

Recommendation: compile-time structural dispatch internally, CLR interface shape only at interop boundaries.

| Option | Interop cost | Performance impact | Decision |
| --- | --- | --- | --- |
| Always emit runtime interfaces | Easy reflection/C# model | Interface dispatch and possible boxing | Keep for public contracts. |
| Erase duck interfaces internally | No public interop for erased shape | Direct calls, no adapter allocation | Recommended default for internal use. |
| Generate adapters automatically at boundaries | More generated types | Best of both worlds if tested | Add after the ABI classifier gains adapter generation — the classifier itself shipped 2026-05-29 (`Performance/AbiClassifier.cs`) as a self-contained component, no Bound IR required; adapter work now belongs in the columnar pipeline. |

Status (2026-06-10): the shipped shape is a hybrid the table doesn't name — duck interfaces always emit as real CLR interfaces, structurally matched at compile time, but are demoted to internal visibility unless a public implementor exists (`GetInterfaceTypeVisibilityAttributes`, `ILCompiler.cs`; same policy in the transpiler). Internal erasure (the recommended default above) is not implemented; internal duck-typed call sites still pay interface dispatch unless the receiver is concrete.

## Match And Switch Lowering

`match` expressions and `switch` statements are control-flow hot paths. The naive lowering tests
each arm in source order with an independent compare-and-branch; with N arms a value that hits the
last arm pays N comparisons, and large dispatch tables become O(N) hot loops.

Implemented compiler work (Unit 10, shipped 2026-05-30 in PR #172):

1. **Dense integer/enum jump tables.** When every selectable arm is a guardless constant
   integer literal (`int` and the smaller int-backed integrals `short`/`sbyte`/`byte`/`ushort`),
   `char` literal, or an int-backed enum-member pattern (e.g. `Color.Red`), and the
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

Backend caveat (2026-06-10): these dispatch shapes exist only in the C# ILCompiler, which Stage 6
deletes. The columnar pipeline's own match lowering (Phases D-6/D-6b–e, D-7b, D-10b/c, 2026-06-09)
currently emits a linear compare chain for every match — including ≥4-key integer/string matches —
with no `OpCodes.Switch` emission anywhere under `Columnar/`. Before Stage 6 routes all programs
through the columnar backend, the jump-table and string-hash shapes must be ported to
`ColumnarIlEmitter` (and re-pinned by `MatchDispatchLoweringTests`-equivalent shape tests), or dense
matches must keep declining to the C# path; otherwise Unit 10's dispatch win silently regresses.

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

Pipeline note (2026-06-10): everything below is implemented in the C# `ILCompiler`, which is slated for deletion at Stage 6 of the self-host roadmap. The standalone columnar pipeline currently reproduces the foreach-over-arrays index-loop lowering (Phase D-4, 2026-06-08), and its assignment statements are already statement-context-native (direct stores, no value reload, no `pop`; compound `+=` and span element stores still decline to C#). Stack-buffer promotion and span foreach must be re-established in `ColumnarIlEmitter` (and their IL-shape pins re-pointed) before Stage 6 retires the C# backend.

Compiler work (status 2026-06-10 — items 1, 2, 5, 6 SHIPPED 2026-05-29/30):

1. Lower `for item in array` to index loops over arrays — SHIPPED: SZ-array foreach lowers to an allocation-free `ldlen`+index loop, with the enumerator fallback retained for multi-dimensional/non-zero-based arrays.
2. Lower `for item in Span<T>` / `ReadOnlySpan<T>` to span index loops — SHIPPED, pinned by `SpanForeachILShapeTests` (no box, no enumerator, no virtual dispatch).
3. Prefer `ReadOnlySpan<T>` for readonly slice parameters and string/array views where lifetime is local — covered by the systems span model below.
4. Avoid enumerator allocation for common BCL collections — OPEN: foreach over `List<T>` still resolves `GetEnumerator` through `IEnumerable<T>` interface dispatch (allocating).
5. Preserve exact CLR `foreach` semantics when the source relies on disposal or custom enumerators — SHIPPED (enumerator+dispose fallback preserved).
6. Add bounds-check-oriented IL-shape tests for canonical loops — SHIPPED (`SpanForeachILShapeTests` 2026-05-30; `ldlen` + fused-branch loop-shape pins 2026-06-05).

### Decision: Make Span A First-Class Language Concept

Recommendation: yes, but with honest restrictions.

| Option | Language cost | Interop cost | Decision |
| --- | --- | --- | --- |
| Treat `Span<T>` as ordinary external type | Simple | Misses lifetime diagnostics and optimization | Insufficient. |
| First-class local-only span/slice model | Requires ref-safety diagnostics | Matches CLR span constraints and unlocks performance | Recommended. |
| Invent non-CLR slice type | More runtime/library burden | Could improve ergonomics | Defer until CLR span model proves inadequate. |

Language tradeoff: first-class spans require restrictions: no field storage in normal classes, no async capture, no heap escape, and careful closure rules.

Status (2026-06-10): adopted and shipped for the systems track. `stackalloc` into `Span<T>`/`ReadOnlySpan<T>` is in the language (lexer/parser support), and `SystemsAnalyzer` enforces the lifetime restrictions as NSYS080 errors (stackalloc spans cannot escape via return; ref-like returns require explicit lifetimes; stackalloc lengths must be statically bounded within the systems stack budget). Span foreach lowers to allocation-free index loops, pinned by `SpanForeachILShapeTests`.

### Stack buffers (shipped 2026-05-30, Performance Unit 7; pinned by `tests/PerfEvidence/StackallocPromotionTests.cs`)

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
4. Its name does not collide with a parameter (checked in the analysis), nor with a
   current-type member (field/property) or a lifted/captured local (both checked at the emitter
   seam, which has the semantic member table).
5. Every use is on the small whitelist the emitter can lower: index get/set (including
   compound assignment), `.Length`, and `foreach`. Any other use — bare identifier load,
   return, argument pass, `ref`/`out` of an element, cast, capture in a lambda/local function,
   increment/decrement of an element, use inside a pattern, or any shape the walker does not
   recognise — disqualifies the local, which then stays a heap array.

Because the fallback is a heap array (always valid), no diagnostic is required on escape:
promotion is a transparent optimization, not a checked language feature.

Deferred: buffers declared inside nested blocks (would require scope-restored promotion
state), non-constant sizes, and managed/struct element types.

### Statement-context assignment

Assignment is both an expression and a statement in N#. Expression-valued assignment is required for
shapes such as `x = y = 5`, so the ordinary expression lowerer must leave the assigned value on the
evaluation stack. Hot compiler-service code, however, is dominated by bare assignment statements:
loop induction (`position = position + 1`), counters (`count = count + 1`), and compact token-buffer
writes (`kinds[count] = kind`). Reloading the assigned value only for the expression-statement
emitter to `pop` it adds unnecessary IL and can inhibit the JIT from seeing the tightest loop shape.

Implemented compiler work (2026-06-03; mechanism revised 2026-06-05):

1. `EmitExpressionStatement` routes assignment statements through a dedicated statement-context
   emitter (`TryEmitExpressionDiscardingResult` → `TryEmitAssignmentStatement`) that emits the
   store directly with no value reload and no `pop`.
2. Covered shapes: identifier assignment (simple and compound) and simple indexed assignment into
   arrays and writable `Span<T>`. Static-member and instance-member assignment statements
   currently fall back to the expression path (value produced, then popped) — re-covering them is
   open, low-priority work since the hot dogfood scanners are identifier/indexed-dominated.
   (`EmitAssignment`'s `leaveValueOnStack: false` mode from the original 2026-06-03
   implementation no longer has callers.)
3. `AssignmentStatementIlShapeTests` pins zero `pop` opcodes for local/indexed assignment
   statements and verifies nested assignment expressions still return the assigned value.

## Async And Iterators

Async and iterator lowering can dominate allocations. N# should make the cheap path explicit without making async interop weird.

Compiler work (status 2026-06-10; items 4–5 remain unimplemented — per the self-host roadmap they would land in the columnar diagnostics pass, not in `Analyzer.cs`, which is slated for Stage-6 retirement):

1. `ValueTask<T>` preference — SHIPPED, broader than proposed: the IL backend wraps every async function without an explicit task-like annotation in `ValueTask`/`ValueTask<T>` (`WrapAsyncReturnType`, `ILCompiler.cs`); only the `main` entry point defaults to `Task`. There is no evidence-gated internal-only preference; the default is ValueTask across the board.
2. Avoid async state machines when a function returns an existing task/value-task directly and has no `await`.
3. Avoid iterator state machines for simple materialized collections when a loop can fill an array/list more directly.
4. Track async closure captures separately from ordinary closure captures.
5. Emit analyzer diagnostics when a lambda/closure/span crosses an async boundary and forces allocation or is illegal.

### Decision: Default Task Or ValueTask

**Shipped behavior differs from the original recommendation (verified 2026-06-10):** the default async return wrapper is `ValueTask`/`ValueTask<T>` for every async function except the `main` entry point (`Task`); an explicit task-like annotation (`: Task<int>` etc.) is honored as written. project.yml `language.asyncDefaultType` (default `ValueTask`) is honored by the legacy transpiler only — the IL backend hardcodes the ValueTask default in `WrapAsyncReturnType` and ignores the setting (a known backend/config disconnect). The "evidence-based internal ValueTask" recommendation was never implemented; the shipped default is broader (always-ValueTask-unless-annotated). The original option table, for the record:

| Option | What we sacrifice | What we gain | Decision |
| --- | --- | --- | --- |
| Always `Task<T>` | Leaves sync-completion allocation opportunities | Simple C# interop | Rejected by shipped behavior. |
| Always `ValueTask<T>` | More complex consumption rules for C# users | Better sync-completion cases | This is what shipped (except `main`). |
| Evidence-based internal `ValueTask<T>` | Minimal interop impact | Wins in known hot paths | Original recommendation; never implemented. |

### Implementation Status

Strategic note (2026-06-10): `ILCompiler.Async.cs` belongs to the C# ILCompiler, slated for deletion at Stage 6 once columnar coverage lands. The standalone columnar pipeline does not yet model async/await at all (async programs decline to the C# backend). Real async state machines, if built, land in the columnar backend; the lowering described here is transition-era behavior of the parity oracle, not a future investment target.

The IL backend (`System.Reflection.Emit`) does **not** emit real async state machines today.
`EmitAwaitExpression` lowers `await` to a synchronous `GetAwaiter().GetResult()`, and the whole
`async` body runs synchronously; the result is wrapped into a completed `Task`/`ValueTask` at each
return (`EmitWrapCurrentAsyncReturn`). This means item (2) above — "no state machine for an async
method without `await`" — is already satisfied structurally: no `IAsyncStateMachine`/`MoveNext`
type is generated for any async method, and the await-free path adds no Task allocation beyond the
unavoidable result carrier (`Task.CompletedTask` is cached; `ValueTask` is allocation-free; a
result-typed `Task<T>` uses `Task.FromResult`).

Iterators (verified 2026-06-10): the IL backend likewise emits no iterator state machines. `yield`
generator bodies are lowered eagerly into a `List<T>` that is returned directly (or wrapped in
synthesized `IAsyncEnumerable`/`IAsyncEnumerator` adapters), so item (3) is structurally satisfied —
but the lowering is eager, not lazy: the full sequence is materialized before the caller sees the
first element. Lazy/streaming iterator semantics are deferred alongside async state machines.

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

Compiler work (status 2026-06-10 — items 2–4 shipped, see below):

1. Keep exceptions for exceptional CLR interop and `throw`.
2. Make result/error sugar lower to direct branches and value carriers, not exception control flow.
3. Allocation-free `Result<T, E>` layout — DONE, but scoped differently than proposed: Systems v1 (2026-06-01) made it a compiler-known allocation-free struct with a *public, stable C# ABI* (`docs/design/systems-nsharp.md`, "Error Model And Result ABI") rather than a non-public internal layout, so C# callers consume the same tagged struct.
4. Add benchmarks for success-path and failure-path result handling.

Implemented (2026-05-30/2026-06-01): items 2–4 have shipped. `Result<T, E>` is a compiler-known allocation-free `public readonly struct` (`src/NSharpLang.Runtime/Result.cs`) inspected via direct tag branches (`IsOk`/`TryGetOk`/`TryGetErr`), with NSYS160 (must-use) and NSYS170 (copy-shape size) diagnostics. Success- and failure-path result benchmarks exist (`ErrorTupleBenchmarks`, `SystemsResultBenchmarks`), and the Result ABI is enforced in the CI Systems benchmark gate (`SystemsFastGateBenchmarks`: ResultAbi, HotResultCombinations). The success path of `result, err :=` is pinned to synthesize no throw/rethrow IL (`Gate_ErrorTupleSuccessPath_SynthesizesNoThrow`, 2026-05-30).

### Decision: Exceptions As Control Flow

Recommendation: never lower ordinary N# result/error control flow to exceptions.

Interop tradeoff: none. Language tradeoff: users must choose exception interop explicitly when calling exception-based .NET APIs.

Implemented: the `result, err :=` sugar IS that explicit exception-interop hatch — it wraps the call in try/catch and stores the caught exception into `err`, while the success path is IL-ratcheted to synthesize no throw. Scope note (2026-06-10): this remains a lowering policy only — the planned opt-in strict mode (`language.strict`, NL970s, declaration-side bans; design-only, nothing implemented yet) will never restrict `throw` or exception declarations, since exceptions are CLR-native; `result, err :=` stays an idiom, not a mandate.

## Reflection, Dynamic, And Expression Trees

Reflection and expression trees are important .NET interop paths, but they prevent many optimizations.

Compiler work (status 2026-06-10 — largely shipped, see the status note below):

1. Mark expression-tree boundaries as hard CLR delegate boundaries.
2. Mark reflection/dynamic access as unknown escape and unknown dispatch.
3. Preserve metadata required by public reflection scenarios.
4. Provide diagnostics that explain when reflection/dynamic prevents direct lowering, trimming, or AOT safety.

Status (2026-05-30, see "Implemented: AOT-Blocker Analysis" below): items 1–2's escape marking is shipped — `AotBlockerAnalyzer` records `Escape = ReflectionBoundary` (and `ExpressionTree`-kind) facts into the `PerformanceFactStore`; item 3's annotation half is shipped via public-API `[RequiresUnreferencedCode]`/`[RequiresDynamicCode]` stamping; item 4 is shipped for AOT/trimming as NL960–NL963 plus the `nlc build/check --aot` gate. Remaining: dispatch-fact recording (`DispatchKind.ReflectionDynamic` is defined but never recorded) and "prevents direct lowering" diagnostics — per the banner, any further fact-marking work lands in the columnar pipeline, not a tree-based Bound IR.

### Decision: Optimize Across Reflection Boundaries

Recommendation: no. Treat reflection/dynamic/expression trees as optimization fences unless a future linker-style analysis proves safety.

Interop tradeoff: preserving reflection shape keeps .NET compatibility. Performance tradeoff: reflection-heavy code will not be the peak-performance subset.

Self-host note (2026-06-08): N# currently has no reflection language surface (no `typeof`, no reflection API), and the compiler's own IL emitters are built on `System.Reflection.Emit` — so the planned C#-to-N# port of the columnar emitter is blocked until an N# reflection/interop story exists (see the C#-retirement sequencing in [`roadmap-to-done.md`](roadmap-to-done.md)).

## NativeAOT, Trimming, And Deployment Modes

N# should be AOT-friendly by construction, but not AOT-only.

Compiler work (status 2026-06-10 — items 1–3 done, 4 analysis-only, 5 resolved by P4):

1. AOT-safety fact — DONE (2026-05-30): recorded as `PerformanceFacts.AotSafety` in the shared `PerformanceFactStore` (no Bound IR was built; see the banner).
2. Avoid hidden reflection dependencies in compiler-generated code — DONE (verified by `AotAttributeEmissionTests` and the ILVerify gate).
3. Generate source/metadata annotations when a public API requires reflection — DONE (2026-05-30, see "Implemented" below).
4. Add `nlc publish` evidence for NativeAOT only after template and dependency workflows are tested — `nlc publish --aot` exists but is analysis-only; native-image evidence remains open.
5. Benchmark both tiered JIT+PGO and NativeAOT for any claim — resolved analytically by the P4 decision (2026-06-07): NativeAOT shares RyuJIT codegen, so image emission changes startup/deployment, not throughput.

### Decision: Default Runtime Mode

Recommendation: default to normal .NET JIT for compatibility; offer NativeAOT as an explicit publish mode later.

| Option | Interop cost | Performance impact | Decision |
| --- | --- | --- | --- |
| JIT only | Best dynamic/reflection compatibility | Slower startup, larger runtime footprint | Current default. |
| NativeAOT default | Breaks some reflection/dynamic/plugin patterns | Better startup/deployment profile | Too expensive for v1 default. |
| Explicit AOT mode with diagnostics | User chooses tradeoff | Clear deployment story | Diagnostics gate SHIPPED (`--aot`, analysis-only, 2026-05-30); native image emission endorsed as a separate startup/size track by the P4 decision (2026-06-07) — see [`p4-llvm-nativeaot-backend-evaluation.md`](p4-llvm-nativeaot-backend-evaluation.md). |

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

Detection is semantic-first (since 2026-05-31): when the semantic model resolves a call, the pass
keys on the resolved CLR method and its declaring type (e.g. `CreateInstance` is flagged only on
`System.Activator`, `MakeGenericType` only on `System.Type`-like receivers), eliminating false
positives from domain APIs that merely share a name. A name-based AST fallback remains for callers
without semantic binding. `nameof(...)` is compile-time and is never flagged.
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

Not yet done (future phases): native image generation and trimming roots/feature switches. (The
JIT-vs-AOT throughput benchmark originally listed here was resolved analytically by the P4
decision — NativeAOT shares RyuJIT codegen, so image emission changes startup/deployment, not
throughput.)

The shape of those future phases was decided 2026-06-07 in
[`p4-llvm-nativeaot-backend-evaluation.md`](p4-llvm-nativeaot-backend-evaluation.md): NativeAOT
image emission is a separate, independently-justified startup/size track (RyuJIT codegen — no
throughput change), explicitly decoupled from any LLVM/structural-backend bet, which stays
deferred behind evidence gates G1–G4. NativeAOT-LLVM (runtimelab) was evaluated and is not viable
for a desktop/CLI compiler.

## SIMD And Hardware Intrinsics

N# should not invent a vector model before the basic IL is strong. It should first expose .NET's existing SIMD safely.

Compiler work (resolved 2026-06-07, Phase P — see the parenthetical below):

1. Make `System.Numerics.Vector<T>` and hardware-intrinsic APIs work cleanly through imports.
2. Add analyzer recognition for vector-friendly loops.
3. Add optional auto-vectorization guidance diagnostics before attempting compiler vectorization.
4. Only add N# vector syntax after benchmark evidence shows .NET APIs are too cumbersome.

(Resolved 2026-06-07, Phase P: item 1 shipped as-is; items 2–3 were overtaken — recognition landed not in the Analyzer but as conservative loop-shape detectors inside the IL emitter (`ReductionLoopShape`, `RangePredicateCountShape`, `MinMaxReductionLoopShape`, `CountTransitionsShape`, driven by `ILCompiler.Vectorization.cs`), and the compiler vectorizes matched loops directly with no guidance-diagnostic intermediate step; item 4 holds — no N# vector syntax was added.)

### Decision: Auto-Vectorization

Recommendation (original, 2026-05): defer; let RyuJIT and explicit .NET vector APIs carry this initially. **SUPERSEDED 2026-06-07** — Phase P shipped per-pattern auto-vectorization for four conservative loop shapes (counted integer sum reductions over `int`/`long`/`uint`/`ulong` arrays; `int[]` range-predicate counts; `int[]` min/max conditional reductions including a fused single-pass MinMax; `int[]` adjacent count-transitions), in both while- and for-forms, ON by default (`NSHARP_VECTORIZE_REDUCTIONS=0` opts out).

Language tradeoff: the "no new syntax" half held — vectorization is a lowering of ordinary scalar loops, with no language surface added.

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
   overflow check that the language never asked for. (Since 2026-06-07 this contract also governs
   Phase P auto-vectorization: every vectorized loop shape declines to fire inside a `checked(...)`
   context, because the SIMD helpers wrap where a checked scalar reduction must throw.)

2. **Array index loops use the RyuJIT range-check-elimination idiom.** The array foreach fast path
   emits: index initialized to `0`; a loop test that compares the index against the array's *own*
   length via a fresh `ldlen` (deliberately not cached in a local — caching defeats array BCE);
   monotonic `i++`; and `ldelem*` on the same array. This is the canonical
   `for (int i = 0; i < arr.Length; i++) arr[i]` shape that RyuJIT proves `0 <= i < arr.Length` for
   and elides the per-element bounds check. The span fast path caches `Length` once (spans have no
   `ldlen`) and reads elements through `GetReference` + `Unsafe.Add` + `ldind`, the same shape the
   span indexer lowers to. Since 2026-06-05, explicit counted for-loops over `arr.Length` get the
   same treatment: `array.Length` lowers to `ldlen` for SZ arrays with a fused compare-branch,
   pinned by `ExplicitForArrayLengthLoop_UsesLdlenAndFusedBranch` in `ArithmeticAndLoopShapeTests`.

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

### Status (updated 2026-06-10): explicit SIMD works; per-pattern auto-vectorization SHIPPED (Phase P, 2026-06-07); element-wise store loops remain scalar

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

**Part 2 — compiler auto-vectorization: SHIPPED for reduction/count shapes (Phase P, 2026-06-07);
element-wise stores intentionally still scalar.** The compiler recognizes four conservative loop
shapes in both while- and for-forms and lowers them to verifiable `Vector<T>` helper calls in
`NSharpLang.Runtime.SimdReductions`, ON by default (`NSHARP_VECTORIZE_REDUCTIONS=0` opts out):

1. Counted sum reductions `acc = acc + a[i]` over `int`/`long`/`uint`/`ulong` arrays (integer
   wrapping add is associative, so the rewrite is value-identical; float/double deliberately
   excluded — FP add is not associative).
2. `int[]` range-predicate counts `if a[i] >= lo && a[i] <= hi { count = count + 1 }` via masked SIMD.
3. `int[]` min/max conditional reductions, fused into a single-pass `MinMaxInt32` when both appear
   in one body.
4. `int[]` adjacent count-transitions (`if a[i] != previous { ... }; previous = a[i]`) via seeded
   shifted compare.

Every shape requires an int index and a side-effect-free bound, declines inside a `checked(...)`
context (the vectorized helpers wrap where a checked reduction must throw), and on any
shape/type mismatch falls back to the unmodified scalar lowering (`TryEmitVectorized*` returns
false; the caller emits the normal loop). Pinned by the `*VectorizationTests` and `*ShapeTests`
families in `tests/PerfEvidence`. Measured (2026-06-07, single M4 machine,
[`systems-vs-native.md`](systems-vs-native.md)): every vectorizable kernel is ≤2.02× best-native
at `N=4096` (was 8.8–10.5× pre-Phase-P) and ~2–6× **faster** than C#/RyuJIT, which runs these
loops scalar.

Element-wise store loops (`c[i] = a[i] + b[i]`) remain scalar by design — the original risk
analysis still governs that shape (a strided rewrite must prove aliasing, exception-timing, and
partial-write semantics; verifiable IL prevents crashes but not wrong results), pinned by
`ScalarElementWiseLoop_StaysScalar_NoVectorTypesEmitted`.

Backend caveat (2026-06-10): the four-shape vectorizer lives entirely in the C# ILCompiler path
(`ILCompiler.Vectorization.cs` + the `*Shape` detectors); the standalone columnar pipeline has no
vectorization yet. Before Stage 6 retires `ILCompiler/`, the shape detectors and `SimdReductions`
lowering must be ported to (or re-implemented in) the columnar emitter, or the Rust-class numbers
regress for columnar-routed builds.

**Reopen criteria (HISTORICAL — auto-vectorization was reopened and shipped 2026-06-07 as Phase P,
for reduction/count shapes rather than the element-wise rewrite these criteria anticipated). The
shipped work satisfied the substance of criteria 1, 3, and 5 — measured speedup RyuJIT does not
capture; narrowly specified, negative-tested shape recognizers; a scalar fallback that reuses the
unmodified original lowering — and replaced criteria 2/4/6 with value-identity parity tests
(including SIMD tails and seed/carry restoration), adversarial review, and the ILVerify product
gate, measured on a single M4 machine only (x64 ratios may differ). These criteria remain the bar
for any FUTURE element-wise vectorization, which is still unshipped:**

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

Tooling (status 2026-06-10 — items 1–3 shipped):

1. `nlc query perf --file --pos`: explain allocation, dispatch, capture, and ABI facts for a selected expression/function (shipped: returns the versioned position-based facts envelope — allocation, capture, dispatch, escape, value layout, AOT safety — enriched with Systems N# effect findings; JSON output only).
2. `nlc build --perf-report`: emit JSON with schema version, allocation sites, delegate sites, boxing sites, virtual/interface dispatch, closure captures, and AOT blockers. Shipped (2026-06-01): the versioned envelope reports AOT blockers plus allocation, delegate, boxing, dispatch, and closure-capture sites sourced from the Systems N# effect analyzer, and has since grown pool/resource/boundary-leak/hot-readiness/implicit-trap/trusted-site categories. Per-method `ilShape` counts are the remaining unwired fact source.
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

As of 2026-06-08 these gates are mechanically enforced, not just policy: the full-suite gate runs a blocking Systems BenchmarkDotNet stage (Step 3a, `scripts/benchmark-systems.sh` — matched-shape N#-vs-C# `SystemsFastGateBenchmarks` rows must stay within a 1.05 ratio tolerance), and the columnar backend adds its own never-slower compile-time benchmark plus a columnar↔C# parity oracle (which caught two production codegen bugs on its first day, 2026-06-08, and has driven a steady stream of oracle fixes since — see [`self-host-progress.md`](self-host-progress.md)).

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
  unverifiable IL — exactly the #160 regression class. Regenerate it
  deliberately with `scripts/ilverify.sh --update-baseline` and review the
  diff. The baseline has been EMPTY since the IL-validity coverage sweep
  (2026-05-30, PR #186) fixed every pre-existing finding — struct `Equals`
  receiver-type confusion, `int`/`double` conversion mismatches, init-only
  field writes outside `.ctor`, the interface-method emission gap, and the
  ilverify crash on the lock-statement lowering.
  `tests/PerfEvidence/IlVerifyBaselineEmptyTests.cs` pins the baseline at zero
  entries, so any new allowlisted finding fails the unit-test suite as well as
  the gate.
- **Why blocking from day one**: confirmed by the product owner. A non-blocking
  verifier is how #160 happened.

## Benchmark Corpus And IL-Shape Gate

The performance claims are backed by two coupled artifacts, one per optimized pattern.

This section covers benchmarks for N#-emitted runtime code. Compiler/tooling dogfood benchmark
NUMBERS are tracked in [compiler-benchmark-metrics.md](compiler-benchmark-metrics.md) (the living
roll-up), with per-slice accept/reject narrative in
[compiler-dogfood-rewrite.md](compiler-dogfood-rewrite.md) — a superseded-strategy archive as of
2026-06-07; columnar-pipeline benchmarks are logged in [self-host-progress.md](self-host-progress.md).

### 1. Matched N#-vs-C# benchmark corpus (`benchmarks/`)

`benchmarks/NSharpLang.Benchmarks.csproj` is a BenchmarkDotNet project with one benchmark class per
pattern. Each class binds the N# probe to a typed delegate in `[GlobalSetup]`
(`NSharpCompiledMethod.Bind<TDelegate>`) and pairs it with a hand-written, same-algorithm C#
baseline so the comparison is a fair, matched-shape one.

The project is **deliberately outside** the default `dotnet test` path and is **not** in
`NSharpLang.sln`. The original six-pattern corpus produces manual, wall-clock before/after numbers
for a PR. Since 2026-06-01 the project ALSO hosts `SystemsFastGateBenchmarks`, which IS a blocking
product gate: `scripts/test-all.sh` Step 3a runs `scripts/benchmark-systems.sh` (BDN gate mode, 6
matched N#-vs-C# scenarios, median-ratio limit 1.05 — each N# median ≤ 1.05× its C# baseline
median; ratios are load-robust even though absolute wall-clock is not). Run the corpus manually:

```bash
# whole corpus (Release is mandatory for real numbers)
dotnet run -c Release --project benchmarks -- --filter '*'
# one family
dotnet run -c Release --project benchmarks -- --filter '*ForeachArray*'
# fast smoke check that it still executes (not for real numbers)
dotnet run -c Release --project benchmarks -- --filter '*' --job Dry
```

Gotcha (2026-06-09): run benchmarks from a clean checkout or a `/tmp` worktree. A nested git
worktree under the repo root with a duplicate `NSharpLang.Benchmarks.csproj` makes BenchmarkDotNet
execute 0 benchmarks and fails the Systems gate's expected-count check ("expected 6, got 0").

Results land in `BenchmarkDotNet.Artifacts/` (git-ignored). `[MemoryDiagnoser]` on every class makes
the allocation column the load-bearing signal: e.g. the array/span/value-union families report
0 B/op, and the static-lambda family allocates only the backing `List<>` (the delegate itself is
cached, so it does not show up per-iteration).

Original families (matched to the PR #160 optimizations):

| Benchmark class                  | Pattern                                   | Probe method |
| -------------------------------- | ----------------------------------------- | ------------ |
| `ForeachArrayBenchmarks`         | `foreach` over `T[]`                       | `sumArray`   |
| `ForeachSpanBenchmarks`          | `foreach` over `ReadOnlySpan<T>`           | `sumSpan`    |
| `ValueUnionBenchmarks`           | payload-free value-struct union            | `classify`   |
| `ConstrainedDispatchBenchmarks`  | constrained generic dispatch (no box)      | `run`        |
| `StaticLambdaBenchmarks`         | cached non-capturing lambda in a loop      | `build`      |
| `ErrorTupleBenchmarks`           | `(result, err)` tuple, no throw on success | `RunSuccess` |

As of 2026-06-10 the corpus has grown well beyond these six: the `Systems*` family (including
`SystemsFastGateBenchmarks`, the blocking product-gate set, plus the `SystemsHotPathBenchmarks`
matrix measured against Rust/C in `native-comparison/`), the columnar-pipeline family
(`ColumnarBackendEmitBenchmarks`, `ColumnarSemanticPassBenchmarks`), `DogfoodBoundaryOverheadBenchmarks`,
and ~28 `CompilerService*` + ~26 `Cli*` dogfood families.

Dogfood compiler-service baselines live in `benchmarks/` with the `CompilerService` prefix.
`CompilerServiceLexerBenchmarks` was the first such family (C# `Lexer.Tokenize()` baseline). The
matched N# benchmarks have since landed in the same file (scanner count, token-kind sequence,
reusable-buffer, metadata, and comment-trivia families, each with `[GlobalSetup]` parity
verification), and the 5x dogfood bar was measured and cleared for the N# parser front-end on
2026-06-06 (~5–6x over the C# Parser); the authoritative ratio roll-up is
[compiler-benchmark-metrics.md](compiler-benchmark-metrics.md).

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
   Note (2026-05-30 onward): this is also enforced automatically — `scripts/ilverify.sh` runs as a
   blocking gate (Step 10b of `scripts/test-all.sh`) over all emitted assemblies, and the
   unverifiable-IL baseline is empty (pinned by `IlVerifyBaselineEmptyTests`). The manual
   `dotnet ilverify` run is a fast local probe, not the enforcement mechanism.
4. **Cross-platform crash check**: run the gate under amd64 Linux with a crash detector —
   `docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src mcr.microsoft.com/dotnet/sdk:10.0 bash -c "dotnet test tests/Tests.csproj --filter IlShapeRegression --blame-crash"` —
   to catch the GC-unsafe-IL class of bug that only manifested on Linux x64 in PR #160.

## Implementation Roadmap

Status (2026-06-10): this roadmap is retained as a record. What survives of it executed mostly in
the 2026-05-29/30 performance batches and Phase P — directly in the emitter, without the Bound IR
the phases assumed — and the forward-looking work now lives in
[`roadmap-to-done.md`](roadmap-to-done.md) (Phase D columnar coverage → Stage 6 C# retirement).

### Phase 0: Evidence Discipline — DONE (2026-05-29/2026-06-06)

IL-shape inspection helpers shipped (`tests/PerfEvidence/ILShapeInspector.cs` +
`Performance/IlShapeInspector.cs`; the PerfEvidence suite is now ~35 files). The comparison lab
moved in-repo as `benchmarks/native-comparison/` plus the in-repo BDN Systems gate in
`test-all.sh`. The evidence index lives in `docs/design/` (`systems-vs-native.md`,
`compiler-benchmark-metrics.md`, `self-host-progress.md`), not `memory/`. Dated-artifact
discipline remains in force.

### Phase 1: Bound IR And Facts — SUPERSEDED (2026-06-08)

The Bound IR was never built; the standalone columnar pipeline (flat node tables,
parse→bind→analyze→codegen with no C# AST — see [`columnar-pipeline.md`](columnar-pipeline.md) and
[`roadmap-to-done.md`](roadmap-to-done.md) Stage 4j) is the single IR going forward. The
escape/capture/allocation/dispatch facts survive as `Performance/PerformanceFacts.cs` +
`PerformanceFactStore.cs` attached to the existing emitter, and must be re-homed onto columnar
tables as Phase D coverage grows.

### Phase 2: Function-Value Completion — PARTIALLY LANDED / SUPERSEDED

Closure-capture classification shipped 2026-05-30 directly in `LambdaEmitter.cs`
(no-capture→static, this-only→instance, display class otherwise) without a Bound-IR fact pass.
Method-group direct lowering was not built. The escaped delegate-boundary gap (487 vs 274 ns,
2026-05-27) remains unmeasured since then and is still a target — see the dated diagnosis in
Function Values And Closures above. Remaining function-value work lands in the columnar pipeline:
the lambdas/closures arc is the live Phase D slice (opened 2026-06-10; L1a/L1b landed — see
[`self-host-progress.md`](self-host-progress.md)).

### Phase 3: Value Layout And Union Strategy — DONE (2026-05-29/30, oracle path)

Value-struct tagged unions shipped via `Performance/UnionValueLayout.cs` (integer-tag readonly
struct, allocation-free construction), pinned by `Gate_ValueStructUnion_DoesNotBox` +
`UnionPayloadILShapeTests`. Newtype lowering shipped (synthetic records; call-style construction
2026-06-07). The columnar pipeline gained value-struct user constructors 2026-06-10 (D-17a);
columnar union coverage continues under Phase D.

### Phase 4: Loop/Span/Collection Lowering — LARGELY DONE AND EXCEEDED (2026-06-05/07)

Loop lowering matches or beats C#: `ldlen`, short-circuit branches, span-foreach pins, and Phase P
auto-vectorization (counted reductions, range-predicate counts, fused min/max, count-transitions —
default-on) put N# 2–6× ahead of C# on vectorizable kernels and ≤2.02× of native
([`systems-vs-native.md`](systems-vs-native.md), 2026-06-07). Open: a dedicated span/ref-safety
pass was not built (`StructCopyAnalysis` covers in-param borrows only); enumerator-allocation
diagnostics exist only in systems mode (NSYS010); the vectorizer must be ported to the columnar
backend before `ILCompiler` is deleted (Stage 6).

### Phase 5: Generic Specialization And Dispatch — DONE (2026-05-30, oracle path)

Selective specialization shipped (`Performance/GenericSpecializer.cs` — see the Selective
Specialization section above), conservative exact-receiver devirtualization shipped
(`CanDevirtualizeInstanceCall`; the NL952 catalog diagnostic for un-devirtualized calls is defined
but not yet emitted), and `constrained.` value-type
dispatch shipped (no interface boxing; `ConstrainedDispatchBenchmarks`). Duck-interface erasure
remains unimplemented. Columnar parity for generics is in flight: D-15/16/17 landed generic
functions, generic types, and `where`-constraints (2026-06-09/10).

### Phase 6: AOT And Deployment — DIAGNOSTICS DONE; REMAINDER RESOLVED BY DECISION

AOT-blocker diagnostics NL960–963 shipped 2026-05-30 (`AotBlockerAnalyzer` — see the Implemented
section above). The rest was decided 2026-06-07 in
[`p4-llvm-nativeaot-backend-evaluation.md`](p4-llvm-nativeaot-backend-evaluation.md): NativeAOT
image emission is a separate startup/size track (`nlc publish --aot` remains analysis-only); the
JIT-vs-AOT throughput comparison is moot because NativeAOT shares RyuJIT codegen — it changes
startup/deployment, not throughput.

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

In practice (as of 2026-06-10) decision records live elsewhere, not in this format: per-decision
design docs ([`p4-llvm-nativeaot-backend-evaluation.md`](p4-llvm-nativeaot-backend-evaluation.md),
2026-06-07 — defer the structural backend behind gates G1–G4, NativeAOT as a separate startup/size
track), dated user-decision entries in [`roadmap-to-done.md`](roadmap-to-done.md) (Stage 4j
standalone columnar pipeline, 2026-06-08), and the measured per-slice entries in
[`self-host-progress.md`](self-host-progress.md). New optimization decisions should land in
`roadmap-to-done.md` or a dedicated decision doc; this template is retained as the minimum field
set.

## References

Internal:

- Authoritative pipeline and self-host plan: [columnar-pipeline.md](columnar-pipeline.md), [roadmap-to-done.md](roadmap-to-done.md) (status cursor; supersedes the Bound IR pipeline in this doc as of 2026-06-08)
- Live measured performance evidence: [systems-vs-native.md](systems-vs-native.md) (2026-06-07 single-machine re-run), [compiler-benchmark-metrics.md](compiler-benchmark-metrics.md)
- AOT/backend decision record: [p4-llvm-nativeaot-backend-evaluation.md](p4-llvm-nativeaot-backend-evaluation.md) (2026-06-07)

External:

- .NET runtime compilation configuration, including tiered compilation and PGO: https://learn.microsoft.com/en-us/dotnet/core/runtime-config/compilation
- Native AOT deployment and limitations: https://learn.microsoft.com/en-us/dotnet/core/deploying/native-aot/
- .NET garbage collection fundamentals: https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/fundamentals
- .NET memory and spans overview: https://learn.microsoft.com/en-us/dotnet/standard/memory-and-spans/
- .NET SIMD/hardware acceleration overview: https://learn.microsoft.com/en-us/dotnet/standard/simd
