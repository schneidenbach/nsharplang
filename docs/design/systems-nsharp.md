# Systems N# Proposal

Status: design proposal
Updated: 2026-06-01

Systems N# is an optional product lane for writing CLR code with explicit runtime
costs and systems-oriented guarantees. It must preserve N#'s core identity: a
small, pragmatic .NET language with strong tooling and first-class C# interop.
Systems N# should not turn the whole language into a Rust clone. It should make
the CLR's real costs visible, checkable, and explainable.

This proposal records the current design decisions and the reasoning behind
them. It is intentionally adversarial: many details still need review against
real systems code before implementation.

## Product Position

N# has two product lanes:

1. **Default N#**: pragmatic .NET, C# interop, simple syntax, strong tooling.
2. **Systems N#**: an optional whole-project profile for cost-visible,
   AOT-aware, boundary-policed systems code.

Default projects can still use local systems features such as `[hot]` without
enabling the whole-project systems profile.

Reasoning:

- A whole-language systems pivot would risk corrupting N#'s simplicity and .NET
  practicality.
- A local-only hot-path feature would be useful but too weak to establish a
  systems-language identity.
- Two lanes let ordinary .NET users adopt N# while systems users can opt into a
  stricter product promise.

## Project Configuration

Systems profile is enabled in `project.yml`:

```yaml
language:
  profile: systems
  systems:
    mode: strict # audit | strict
    unknownExternalCalls: warn # allow | warn | error
```

`language.profile: systems` defaults to `strict`.

Reasoning:

- If a user explicitly opts into systems mode, the profile should mean something.
- `audit` remains available for migration and framework-heavy apps.
- Unknown external calls need policy because .NET dependency behavior is often
  opaque.

## CLI Surface

Systems tooling should be automation-first, with human text rendered from
canonical versioned JSON:

```bash
nlc systems check
nlc systems check --strict
nlc systems audit-package Dapper
nlc systems audit-package Dapper --project .
nlc systems freeze-effects --write-lock
nlc systems check --locked-effects
```

`nlc check` integration:

- In default N# projects, `nlc check` enforces local `[hot]` annotations.
- In systems-profile projects, `nlc check` includes systems diagnostics.
- `nlc systems check` provides richer reports, package audits, effect diffs,
  and lockfile workflows.

Reasoning:

- Systems mode should not require a separate command for basic correctness.
- Deep reports and dependency audits need a dedicated command surface.
- N#'s CLI is LLM-first, so versioned JSON must be canonical.

## Diagnostic Model

Systems diagnostics use a separate `NSYS###` code family.

Initial families:

- `NSYS001`: allocation visibility
- `NSYS010`: hot allocation violation
- `NSYS020`: boxing violation
- `NSYS030`: delegate/closure violation
- `NSYS040`: dispatch violation
- `NSYS050`: unknown external call
- `NSYS060`: AOT blocker
- `NSYS070`: boundary leak
- `NSYS080`: lifetime/ref escape
- `NSYS090`: resource disposal
- `NSYS100`: memory safety/trusted wrapper

Audit-mode systems findings are separate report findings, not ordinary compiler
warnings. Strict mode promotes policy violations to build errors.

Reasoning:

- Systems findings are not the same as syntax/type errors.
- Audit mode should not flood editors with warning noise.
- A separate code family gives this feature room to grow.

## Hot Functions

`[hot]` is available in any N# project and opts the function into strict local
systems semantics.

```nsharp
[hot]
func Parse(bytes: ReadOnlySpan<byte>): Result<Packet, ParseError> {
    ...
}
```

`[hot]` is first-call inclusive in v1. It rejects:

- heap allocation
- boxing
- delegate allocation
- closure allocation
- runtime polymorphic dispatch
- reflection
- dynamic code
- throwing exceptions
- unknown external calls
- AOT blockers
- creation/opening of disposable resources

`[hot]` does not imply memory safety. A hot function may contain explicit
restricted `unsafe` blocks if all hot effect rules still pass.

Reasoning:

- `[hot]` must be sharp. It is the strongest user-facing promise in the design.
- First-call inclusive semantics avoid hiding static cache/delegate
  initialization costs.
- Memory safety and performance hotness are separate concerns; combining them
  would make the model less precise.

## Allocation Visibility

Systems strict rejects all unmarked heap allocations:

```nsharp
x := new User()        // error in systems strict if User is a class
x := alloc new User()  // allowed in ordinary systems code
p := new Point()       // ok when Point is a struct
```

Accepted allocation markers in v1:

```nsharp
user := alloc new User(...)
bytes := alloc new byte[4096]
msg := alloc $"id={id}"
items := alloc [1, 2, 3]
```

`alloc` marks selected heap-producing construction forms, not arbitrary method
calls.

`alloc {}` is a construction zone for selected obvious allocation sugar:

```nsharp
alloc {
    msg := $"id={id}"     // allowed and reported as an allocation site
    items := [1, 2, 3]    // allowed and reported as an allocation site
}
```

`alloc {}` does not automatically allow boxing, closure allocation, delegate
allocation, iterator/async state machine allocation, reflection, dynamic code, or
unknown external allocations.

Inside `[hot]` or `[alloc(none)]`, even `alloc new` is rejected unless wrapped in
an explicit allow region:

```nsharp
[hot]
func BuildOnce() {
    allow(alloc, reason: "One-time lookup table construction") {
        table := alloc new LookupTable()
    }
}
```

Reasoning:

- If N# adds `alloc`, it must mean real cost visibility.
- `new` is not always heap allocation on .NET, so the rule must classify the
  operation, not just the keyword.
- Strings and collection literals are common enough to need explicit allocation
  syntax and allocation zones.

## Allows And Escapes

Allow escapes are available at function and block level only in v1:

```nsharp
[hot]
[allow(dispatch: interface, reason: "Strategy selected once per packet type")]
func Parse(...) {
    ...
}

allow(alloc, reason: "One-time cache initialization") {
    cache = alloc new Cache()
}
```

Rules:

- `reason` is required in systems profile.
- Expression-level `allow` is deferred.
- Diagnostics should prefer suggesting the narrowest block-level allow.

Reasoning:

- This mirrors the review posture of `unsafe` without copying Rust's full model.
- A reason string is enough for v1; audit IDs are deferred as process overhead.
- Function-level allows are useful, but block-level allows keep exceptions local.

## Delegates And Closures

Systems strict does not add a delegate allocation marker in v1.

Rules:

- Closure/delegate allocation is rejected in ordinary systems strict code.
- It is allowed inside `[boundary]` and reported.
- It is allowed via `allow(delegate, reason: "...")` or
  `allow(closure, reason: "...")`.
- `[hot]` rejects delegate dispatch unless explicitly allowed.

Delegate-shaped APIs may be allowed outside `[hot]` only when summaries prove no
per-call allocation and dispatch policy permits delegate invocation.

Reasoning:

- Delegates are core .NET interop, but not a good default systems abstraction.
- Non-capturing cached delegates can be allocation-free after initialization,
  but first-call initialization and delegate dispatch still matter.
- Systems N# should distinguish construction allocation, cache initialization,
  and per-call delegate invocation.

## Boundary Functions

`[boundary]` is an adapter contract, not an "anything goes" zone.

```nsharp
[boundary]
func LoadConfig(path: string): Result<Config, ConfigError> {
    ...
}
```

Rules:

- Normal .NET patterns are allowed inside and reported.
- Heap allocation, delegate allocation, closure captures, boxing,
  reflection/dynamic code, throwing/catching, virtual dispatch, and unknown
  external calls are listed in systems reports.
- The exported boundary surface must not leak systems-hostile shapes into
  systems/hot code.
- AOT blockers inside a boundary require explicit `allow(aot: blocked, reason:
  "...")`.

Reasoning:

- .NET frameworks are often allocation-heavy, delegate-heavy, and
  reflection-heavy. Systems N# needs a quarantine/adaptation story rather than a
  fantasy that those costs disappear.
- Boundaries are where normal .NET APIs become systems-safe values, spans,
  results, and explicit errors.

## Boundary Type Surface

Systems uses a two-ring model.

For `[hot]`, accepted surfaces are strict:

- primitives
- enums
- unmanaged structs
- ref structs
- `Span<T>` / `ReadOnlySpan<T>` with lifetime rules
- hot-safe `value union` values

General systems code may accept pragmatic managed surfaces:

- existing strings
- existing arrays
- `ReadOnlyMemory<T>`
- selected immutable or systems-safe types
- selected BCL types with known contracts

Managed crossings are visible in reports.

Reasoning:

- Banning all managed references would make .NET systems code impractical.
- Letting arbitrary managed objects into hot paths would weaken the performance
  promise.
- Strings and arrays must be supported as existing inputs, but spans should be
  the preferred hot API surface.

## Managed Reads In Hot Code

`[hot]` may read existing managed references in v1 when the operation is proven
non-allocating and non-mutating.

Allowed examples include known-safe string/array/span operations such as:

- `string.Length`
- `string[i]`
- array `.Length`
- array indexing
- `Span<T>.Length`

Property getters are allowed only when proven trivial:

- compiler-known N# stored property/direct field read
- known BCL intrinsic
- tiny external IL-proven getter such as `ldarg.0; ldfld; ret`

Unknown getters fail in `[hot]` unless explicitly allowed.

Reasoning:

- On the CLR, a property is a method and may allocate, throw, lock, lazily
  initialize, or dispatch virtually.
- Compiler-owned trivial getters are deterministic to classify.
- External IL proof must be conservative and shape-based.

## Error Model

Hot/systems code should use explicit result values instead of exceptions.

```nsharp
value union Result<T, E> {
    Ok { value: T }
    Err { error: E }
}
```

Rules:

- `[hot]` cannot throw.
- Boundaries catch and translate .NET exceptions into explicit `Result<T, E>`
  or equivalent error values.
- `Result<T, E>` is conceptually a standard `value union`, not a compiler-only
  special case.

Reasoning:

- Exceptions are expensive and hidden control flow.
- A blessed result shape is familiar to Rust users and aligns with N# pattern
  matching.
- Treating `Result` as a value union avoids making a one-off magic type.

## Value Unions

Payload-carrying allocation-free unions require explicit `value union` syntax:

```nsharp
value union Result<T, E> {
    Ok { value: T }
    Err { error: E }
}
```

Rules:

- `value union` emits an allocation-free tagged value layout when eligible.
- Generic payloads are supported.
- Reference-type payloads are allowed generally.
- `[hot]` applies stricter payload-safety rules.
- Ordinary class-backed payload unions are rejected in `[hot]`.

Reasoning:

- Public C#-natural unions and allocation-free systems unions are different ABI
  promises.
- Explicit `value union` avoids hidden representation changes.
- Allowing reference payloads makes value unions useful outside the strictest hot
  paths.

## Effects And Summaries

The compiler tracks separate effect dimensions:

- allocation
- boxing
- delegate construction
- closure capture
- dispatch
- reflection
- dynamic code
- AOT compatibility
- throwing
- lifetime/ref escape
- resource disposal
- memory safety

Hot-callable functions require a known effect summary from one of:

- explicit `[hot]`
- explicit raw contracts such as `[alloc(none)]`
- compiler-inferred internal summary
- builtin intrinsic summary
- tiny-whitelist external IL-proven summary

Unknown summaries fail in `[hot]`.

Reasoning:

- A single `systems-safe` bit would be too blunt.
- Separate dimensions let reports explain the actual failed rule.
- Inference keeps internal helper functions ergonomic, while exported APIs need
  stable summaries.

## Effect Locking

The compiler emits generated effect facts under `.nlc/` by default.

Teams may opt into a committed lockfile:

```bash
nlc systems freeze-effects --write-lock
nlc systems check --locked-effects
```

The committed file is expected to be named `nsharp.effects.lock.json`.

Reasoning:

- Internal effect inference is ergonomic but can create accidental performance
  regressions.
- A lockfile gives CI a way to catch changed allocation/boxing/dispatch facts.
- Making the committed artifact opt-in avoids churn for teams that do not need
  it.

## External Dependency Audit

Systems audit covers the full dependency graph:

- NuGet packages
- project references
- local DLL/assembly references
- transitive dependencies

`audit-package` supports both isolated and project-context modes:

```bash
nlc systems audit-package Dapper --target-framework net10.0 --runtime osx-arm64
nlc systems audit-package Dapper --project .
```

Facts record:

- source: `compiler`, `builtin`, `ilProven`, `trustedUser`, `unknown`
- confidence: `proven`, `likely`, `unknown`, `trusted`
- assembly identity/version/hash
- direct vs transitive dependency attribution

`[hot]` accepts only compiler, builtin, and tiny external IL-proven facts. User
trusted facts do not satisfy `[hot]`.

Reasoning:

- Real .NET projects depend on NuGet and internal libraries.
- Package behavior depends on target framework, runtime, and resolved dependency
  graph.
- Trusted user facts are useful for systems code, but too weak for hot-path
  guarantees.

## External IL Proof

`[hot]` accepts external IL-proven facts only for a tiny conservative whitelist:

- trivial getter: `ldarg.0; ldfld; ret`
- trivial static readonly field/property load
- primitive arithmetic helper with no calls, allocation, boxing, or throw
- readonly struct helper with direct field reads/arithmetic only
- known BCL intrinsics such as string/array/span length/index operations

Reasoning:

- External source is often unavailable.
- IL can prove local shape facts, but not arbitrary semantic behavior.
- A tiny whitelist gives practical interop without letting "probably fine" code
  into `[hot]`.

## NativeAOT

Systems profile requires NativeAOT compatibility by default.

Rules:

- AOT blockers are errors in systems profile unless explicitly allowed.
- `[boundary]` does not automatically waive AOT blockers.
- `allow(aot: blocked, reason: "...")` permits normal check/build to pass but
  records status as blocked with allowed exceptions.
- `nlc publish --aot` fails on any reachable AOT blocker, even if normally
  allowed.

Reports separate status dimensions:

```json
{
  "systems": "pass",
  "aot": "blockedWithAllowedExceptions",
  "hot": "pass",
  "memorySafety": "pass"
}
```

The first real Systems N# milestone requires actual native binary generation:

```bash
nlc publish --aot
```

Initial support targets constrained systems CLI and library/package validation,
not ASP.NET.

Reasoning:

- A systems language on .NET needs a real deployment story, not analysis-only
  marketing.
- AOT blockers must remain visible even when allowed for normal builds.
- ASP.NET and reflection-heavy app frameworks are not the right first target.

## Templates

Systems templates should exist as both dedicated names and flags:

```bash
nlc new systems-cli PacketTool
nlc new systems-lib PacketCore
nlc new console --systems
nlc new lib --systems
```

Templates include:

- `language.profile: systems`
- strict defaults
- AOT-ready config
- a sample `[hot]` function
- a sample `[boundary]` adapter
- systems tests
- `nlc publish --aot` path

ZLinq policy:

- `systems-lib` has no default third-party dependency.
- `systems-cli` may include an optional ZLinq sample/dependency path.
- Docs and diagnostics recommend ZLinq for value pipelines.

Reasoning:

- Dedicated templates give Systems N# product identity.
- Flags avoid template sprawl and support discoverability.
- Libraries should avoid default third-party dependencies.

## Lifetime And Ref Safety

V1 includes CLR-native lifetime/ref safety, not Rust ownership.

Rules:

- `Span<T>`, `ReadOnlySpan<T>`, and ref structs are automatically local-only.
- The compiler rejects invalid escape to heap fields, closures, async state
  machines, iterators, or invalid returns.
- Explicit `scoped` is available for advanced interop/API clarity.
- Diagnostics should explain lifetime violations in N# terms.

Reasoning:

- This maps to the CLR's existing ref-like model.
- Full borrow checking, move-only types, and affine ownership are too much risk
  for v1.
- Span/ref safety is essential for credible systems programming on .NET.

## Resource Management

Systems strict enforces obvious `IDisposable` disposal with existing `using`
patterns. There is no `defer` in v1.

Rules:

- Disposable values created locally must be disposed, returned/transferred, or
  stored into an owning location once ownership semantics exist.
- `[hot]` cannot create/open disposable resources in v1.

Reasoning:

- Resource leaks are a real systems concern.
- Existing .NET `using` is familiar and compiles to standard disposal patterns.
- `defer` is attractive, but the enforcement is more important than a new
  keyword.

## Restricted Unsafe And Memory Safety

Restricted unsafe is available in any N# project when explicit:

```nsharp
unsafe {
    ...
}
```

Initial restricted unsafe scope:

- `stackalloc` / stack buffers
- function pointers where CLR-supported
- fixed/native interop essentials
- tightly checked pointer-like operations later
- no broad arbitrary pointer arithmetic in the first slice

Memory safety is a separate effect dimension:

```nsharp
[memory(safe)]
func Parse(...) { ... }
```

Safe wrappers over unsafe code require trust:

```nsharp
[memory(safe)]
[trusted(reason: "Bounds checked before pointer copy")]
func Copy(dst: Span<byte>, src: ReadOnlySpan<byte>) {
    unsafe {
        ...
    }
}
```

Rules:

- Systems profile does not default to memory safe.
- Exported APIs in systems-profile libraries need explicit or inferred memory
  safety summaries.
- `[trusted]` is valid anywhere when paired with a memory-safety contract.
- `[trusted]` requires a reason string.
- `[trusted]` may justify memory safety, not performance facts.
- `[trusted]` is allowed in `[hot]` functions, but only for memory safety.

Reasoning:

- Real high-performance code sometimes needs unsafe internals.
- Safe abstractions over unsafe code are a normal systems pattern.
- Trust must not be allowed to fake allocation-free or dispatch-free
  performance facts.

## ZLinq And Pipelines

Systems N# blesses ZLinq as the first-class high-performance LINQ path.

Rules:

- `System.Linq` is rejected in `[hot]` unless proven safe.
- ZLinq is recommended for systems pipelines.
- N# ships builtin summaries for pinned supported ZLinq versions.
- `[hot]` can allow ZLinq chains only when the exact chain satisfies hot effects.
- Unsupported ZLinq operators degrade to systems diagnostics.
- System.Linq-to-ZLinq migration is a diagnostic/codefix, never a silent compiler
  rewrite.

Reasoning:

- A blanket LINQ ban is too crude; high-performance value-LINQ libraries exist.
- Silent rewrites would surprise users and complicate dependencies/debugging.
- ZLinq can serve as a pilot for serious package effect summaries.

## SIMD

V1 SIMD support is diagnostics and guidance only.

Rules:

- `System.Numerics.Vector<T>` and hardware intrinsics should type-check cleanly.
- The compiler can recognize simple vectorization opportunities.
- Systems reports can suggest ZLinq/SIMD or explicit `Vector<T>` APIs.
- No auto-vectorization or new vector syntax in v1.

Reasoning:

- .NET already has SIMD APIs and a JIT optimizer.
- New vector syntax and compiler auto-vectorization would require substantial
  benchmark evidence.
- Guidance is valuable without overcommitting the language.

## Deferred From V1

- `[alloc(max: N)]` dynamic allocation budgets
- expression-level `allow`
- broad ownership/move/borrow model
- `defer`
- thread-safety/concurrency effects
- arbitrary pointer arithmetic
- steady-state `[hot(phase: steadyState)]`
- broad user-defined systems-safe class/frozen object model
- compiler-native vector syntax
- built-in benchmark/probe harness

Reasoning:

- These features may be valuable, but each adds significant semantic surface.
- V1 should prove cost visibility, hot-path checking, AOT publish, boundary
  adaptation, and tooling before expanding.

## Major Open Questions

1. What exact type shapes count as boundary leaks?
2. How strict should systems-safe managed type rules be before a full `frozen`
   model exists?
3. How should reports distinguish cold-start, steady-state, and unknown-phase
   costs outside `[hot]`?
4. What exact syntax should attributes use in N# once parser constraints are
   considered?
5. How much interprocedural effect inference is needed before v1 is usable?
6. What is the minimum NativeAOT template surface that makes Systems N# credible?
7. How should ZLinq version support be pinned, updated, and tested?
8. What does the package audit manifest schema look like, and how are trusted
   user facts reviewed?
9. What real systems examples should be used as acceptance tests?
10. Which features should be cut if the first implementation milestone gets too
    large?

## Initial Implementation Task Series

1. Finalize this proposal through adversarial review with real systems examples.
2. Add parser support for attributes/contracts: `[hot]`, `[boundary]`,
   `[alloc(none)]`, `[memory(safe)]`, `[trusted(reason)]`, and `[allow(...)]`.
3. Add syntax for `alloc new`, `alloc $"..."`, `alloc [...]`, and `alloc {}`.
4. Build the effect-summary model.
5. Enforce `[hot]` locally in default projects.
6. Add `language.profile: systems`, strict default, and `NSYS###` findings.
7. Implement `nlc systems check` with canonical versioned JSON.
8. Add boundary leak rules and systems-safe surface classification.
9. Implement tiny external IL-proof whitelist for trivial getters/helpers.
10. Add actual NativeAOT publish for systems CLI templates.
11. Add systems templates.
12. Add dependency graph audit and manifest format.
13. Add ZLinq summaries and System.Linq-to-ZLinq codefix pilot.
14. Add effect lockfile tooling.
15. Add docs, examples, and acceptance tests based on adversarial review output.
