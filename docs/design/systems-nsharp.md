# Systems N# Proposal

Status: design proposal, adversarially revised
Updated: 2026-06-01
Primary review input: `docs/audits/systems-nsharp-adversarial-review.md`

Systems N# is an optional product lane for writing CLR code with explicit runtime
costs and systems-oriented checks. It must preserve N#'s core identity: a small,
pragmatic .NET language with strong tooling and first-class C# interop.

The central promise is not "Rust on the CLR." The central promise is that N#
makes CLR costs visible, checkable, and explainable: allocation, boxing,
dispatch, closure/delegate construction, reflection, dynamic code, throwing,
AOT/trimming hazards, lifetime/ref escape, resource ownership, memory safety,
and hidden first-use work.

This document is the canonical Systems N# proposal. Some audits and prompts may
refer to it as `systems-proposal.md`; the repository path is
`docs/design/systems-nsharp.md`.

## Revision History

| Revision | Date | Summary |
| --- | --- | --- |
| Initial proposal | 2026-06-01 | Defined Systems N# as an optional profile with `[hot]`, `[boundary]`, allocation visibility, AOT analysis, effect locking, package audit, value unions, and restricted unsafe. |
| Adversarial revision | 2026-06-01 | Re-scoped the proposal after `systems-nsharp-adversarial-review.md`: made the systems profile a policy rather than a dialect; replaced package-IL proof and effect lockfiles with a HotSummary system plus BCL seed pack; added a hot-readiness model for `.cctor`, JIT, tiering, lazy runtime work, and pool warmup; defined `[hot]` no-throw as explicit exception ban plus proof obligations for common implicit traps; added `stackalloc` without `unsafe`, `ref struct`, return-lifetime rules, pooling, and atomics; made `Result<T,E>` a compiler-known allocation-free struct with a C# ABI; target-qualified AOT facts; added source-generator interop, `[trusted]` governance, precise effect diffs, and the use-case appendix. |

## Product Position

N# has two product lanes:

1. **Default N#**: pragmatic .NET, C# interop, simple syntax, strong tooling.
2. **Systems N#**: an optional policy profile for cost-visible,
   AOT-aware, boundary-policed systems code.

Default projects can still use local systems features such as `[hot]` without
enabling the whole-project systems profile.

The systems profile is a policy, never a dialect:

- It changes which diagnostics are emitted and which facts must be proven.
- It does not change the runtime meaning of valid source.
- Syntax such as `alloc new` is legal everywhere and always means
  "intentional heap allocation."
- Plain heap-allocating `new` always means the normal CLR allocation. Systems
  strict diagnoses it and offers a fix-it to `alloc new` or to move the work
  behind a boundary.

Reasoning:

- A whole-language systems pivot would corrupt N#'s simplicity and .NET
  practicality.
- A local-only hot-path feature is useful but too weak to establish a product
  lane.
- Policy-only systems mode gives strict teams real enforcement without making
  N# source profile-dependent.

## Honest Scope

Systems N# v1 is intentionally bounded.

It promises:

- local self-allocation control for checked hot paths
- explicit adaptation boundaries for normal .NET APIs
- deterministic static effect facts with precise diagnostics
- span/ref safety that matches CLR constraints
- checked use of known BCL hot primitives
- target-qualified AOT/trimming analysis
- safe-wrapper governance for restricted unsafe code

It does not promise:

- process-wide no-GC latency
- Rust/C++/Zig parity for manual ownership, deterministic destruction, or
  no-runtime deployment
- proof that other threads cannot trigger a GC pause
- broad transitive proof of every NuGet package
- a native image until `nlc publish --aot` actually emits one
- arbitrary unsafe pointer programming in v1

The public language claim should be:

> Systems N# can prove that a checked hot path does not itself allocate, box,
> create delegates/closures, dispatch through unknown runtime polymorphism, call
> unknown code, or rely on hidden first-use work. It cannot by itself make the
> whole CLR process pause-free.

## Project Configuration

Systems profile is enabled in `project.yml`:

```yaml
language:
  profile: systems
  systems:
    mode: strict # audit | strict
    unknownExternalCalls: warn # allow | warn | error
    aotTarget: nativeaot # nativeaot | coreclr | mono-wasm
    stackBudgetBytes: 4096
    hotSummaryFiles:
      - summaries/vendor.hotsummary.json
    allowHotSidecars: false
```

`language.profile: systems` defaults to `strict`.

Rules:

- `audit` reports systems facts without blocking normal development.
- `strict` promotes policy violations to build errors.
- Target-qualified AOT facts are evaluated against `aotTarget`.
- Configuration belongs in `project.yml`; `.csproj` remains the minimal SDK
  reference.

Reasoning:

- If a user opts into systems mode, the profile must mean something.
- `audit` remains necessary for migration and framework-heavy applications.
- AOT and trimming hazards differ by target, so the target must be explicit.

## CLI Surface

V1 uses existing CLI surfaces before adding a new command family:

```bash
nlc check
nlc check --systems-report
nlc build --perf-report
nlc query perf --file Program.nl --pos 12:8
nlc query trusted
```

`nlc check` integration:

- In default N# projects, `nlc check` enforces local `[hot]` annotations.
- In systems-profile projects, `nlc check` includes systems diagnostics.
- `--systems-report` emits the canonical versioned JSON systems report.
- `nlc build --perf-report` remains the deterministic IL-shape and effect
  signal.
- `nlc query perf` exposes position-based effect facts for humans, LLMs, and
  IDE tooling.
- `nlc query trusted` reports all `[trusted]` blocks and functions with owner,
  review, expiry, size, and call-chain context.

Deferred CLI:

- `nlc systems ...` is deferred until the existing `check`, `build
  --perf-report`, and `query` surfaces prove insufficient.
- `audit-package`, `freeze-effects`, and `--locked-effects` are cut from v1.

Reasoning:

- The repository already has `nlc check`, `nlc build --perf-report`, and
  `nlc query` as product surfaces.
- Adding a new CLI sub-world before the model is stable creates permanent
  compatibility burden.
- N#'s LLM-first CLI requirement is served by stable JSON envelopes, not by a
  particular command name.

## Diagnostic Model

Systems diagnostics use the `NSYS###` family.

Initial families:

- `NSYS001`: allocation visibility
- `NSYS010`: hot allocation violation
- `NSYS020`: boxing violation
- `NSYS030`: delegate/closure violation
- `NSYS040`: dispatch violation
- `NSYS050`: unknown external call
- `NSYS060`: AOT/trimming blocker
- `NSYS070`: boundary leak
- `NSYS080`: lifetime/ref escape
- `NSYS090`: resource disposal
- `NSYS100`: memory safety/trusted wrapper
- `NSYS110`: hot-readiness blocker
- `NSYS120`: implicit trap proof failure
- `NSYS130`: pool rent/return imbalance
- `NSYS140`: concurrency primitive summary failure
- `NSYS150`: effect fact drift
- `NSYS160`: result ABI / must-use violation

Strict mode errors must include:

- the exact effect dimension that failed
- the local operation or call that introduced the fact
- the summary source used for the decision
- the nearest caller where the fact became policy-relevant
- a suggested fix when one exists

Example diagnostic shape:

```text
NSYS010 error: allocation not allowed in [hot] function
  Program.nl:42:18
  ParseFrame -> DecodePayload -> FormatError
  FormatError allocates a string interpolation here.
  Fix: return an error code from DecodePayload, or wrap the cold diagnostic path
  in allow(alloc) after proving it cannot run on the hot success path.
```

Reasoning:

- Systems findings are not ordinary syntax/type errors.
- Users need the path from policy to cause, not just a local complaint.
- Precise per-fact diffs replace v1 lockfiles as the first regression tool.

## Effect Model

The compiler tracks separate effect dimensions:

- allocation
- boxing
- delegate construction
- closure capture
- dispatch
- reflection
- dynamic code
- AOT/trimming compatibility
- explicit throwing
- implicit trap obligations
- lifetime/ref escape
- resource ownership/disposal
- memory safety
- pool rent/return balance
- hot-readiness
- concurrency primitive semantics

Hot-callable functions require a known effect summary from one of:

- explicit `[hot]`
- explicit raw contracts such as `[alloc(none)]`
- compiler-inferred internal summary
- compiler intrinsic summary
- BCL HotSummary pack entry
- sidecar HotSummary file

Unknown summaries fail in `[hot]`.

Effects are not a single "systems-safe" bit. Each dimension is separately
reported because the fix for "allocates an array" is different from the fix for
"calls a virtual interface method" or "has an unproven bounds check."

## HotSummary System

The HotSummary system is the v1 foundation. It replaces the earlier broad
package-IL proof proposal.

A HotSummary entry records:

- summary schema version
- assembly identity and public key token when present
- package id/version when resolved from NuGet
- target framework
- runtime identifier assumptions, when RID-sensitive
- method signature and generic arity
- body identity: MVID, metadata token, body hash, or source hash
- effect facts by dimension
- generic/constraint conditions
- preconditions needed for the facts
- hot-readiness requirements
- owner/source of the summary: `compiler`, `bclPack`, `sourceInferred`,
  `sidecar`, or `trustedMemoryOnly`

Summary source rules:

- Compiler-owned N# source can be inferred.
- The BCL seed pack is versioned with the N# toolchain and target runtime.
- Sidecar summaries are accepted for ordinary systems code but must be explicit
  and versioned.
- Sidecar summaries do not by themselves satisfy `[hot]` unless the project
  policy explicitly allows them.
- `[trusted]` may justify memory safety only; it never fakes allocation,
  dispatch, throwing, AOT, or hot-readiness facts.

Parametric generic summaries:

- Generic effects may depend on constraints and called members.
- A summary for `Foo<T>` must say which facts hold for all `T`, which require
  `T: unmanaged`, which require a constrained value-type call, and which depend
  on a summarized callback/comparer/operator.
- A summary cannot collapse all instantiations into one optimistic fact.

Reasoning:

- Hot code needs `BinaryPrimitives`, `MemoryMarshal`, `BitOperations`, span
  helpers, `Interlocked`, and `Volatile`. A tiny arbitrary IL whitelist rejects
  the code systems users actually write.
- The product is the effect-summary system plus trustworthy seed data, not a
  speculative transitive package prover.
- Generic hot code is either parametric or uselessly conservative.

## BCL Hot Pack

The v1 BCL HotSummary pack must cover the primitives that make real hot code
possible:

- `System.Buffers.Binary.BinaryPrimitives`
- `System.MemoryExtensions` span helpers used by parsers/codecs
- `System.Runtime.InteropServices.MemoryMarshal`
- `System.Runtime.CompilerServices.Unsafe` for approved wrappers only
- `System.Numerics.BitOperations`
- `System.Numerics.Vector<T>` and selected hardware intrinsic wrappers
- `System.Math` and `System.MathF`
- `Span<T>` and `ReadOnlySpan<T>` length, index, slice, copy, clear, fill
- string length and indexing, with trap obligations
- array length and indexing, with trap obligations
- `System.Threading.Volatile`
- `System.Threading.Interlocked`
- `ArrayPool<T>` and `MemoryPool<T>` rent/return effects
- source-generated interop shapes for `LibraryImport`
- source-generated serialization shapes for `System.Text.Json`
- `[GeneratedRegex]` where generated code is visible and summarized

The pack is fail-closed:

- Unsupported overloads are unknown.
- Runtime-version-sensitive summaries include target runtime identity.
- Intrinsic summaries must state whether the operation can throw, allocate,
  box, dispatch, or trigger first-use work.

Reasoning:

- A packet parser that cannot call `BinaryPrimitives` is not a credible systems
  example.
- A lock-free ring buffer that cannot call `Volatile` or `Interlocked` is not a
  credible systems example.
- Source generators are the AOT-correct path for JSON, P/Invoke, and regex in
  modern .NET.

## Hot-Readiness Model

`[hot]` is checked for local effects and for hidden first-use work.

Hot-readiness covers work that can occur before or during the first call even
when source appears allocation-free:

- type initializers (`.cctor`)
- static field initialization
- lazy BCL caches
- generic dictionary setup for shared generics
- first JIT and tiered recompilation effects
- helper stub creation
- source-generator static caches
- pool initialization/warmup
- globalization tables and culture-sensitive helpers

V1 defines three phases:

1. **Build-ready**: the code is statically summarized, but runtime warmup may
   still be required.
2. **Warm-ready**: the application has executed a generated or user-authored
   warmup plan that touches hot call paths, static initializers, pools, and
   generic instantiations.
3. **AOT-ready**: for a target that emits a native image, the reachable hot path
   has no dynamic-code or trimming blockers for that target.

`[hot]` requires one of:

- no hidden first-use work reachable from the hot path
- a HotSummary precondition stating the required warmup
- an explicit warmup function referenced from project configuration

Example:

```yaml
language:
  profile: systems
  systems:
    warmup:
      - PacketCore.Warmup
```

Reports must distinguish "local hot facts pass" from "hot-readiness requires
warmup."

Reasoning:

- First-call inclusive cannot be a vague phrase. The CLR has real first-use
  behavior outside source-level constructs.
- Systems users will not trust a zero-alloc claim that allocates the first time
  production traffic hits it.

## Hot Functions

`[hot]` is available in any N# project and opts a function into strict local
systems semantics.

```nsharp
[hot]
func Parse(bytes: ReadOnlySpan<byte>): Result<Packet, ParseError> {
    ...
}
```

`[hot]` rejects:

- heap allocation, including `alloc new`
- boxing
- delegate construction
- closure allocation
- runtime polymorphic dispatch that is not summarized as direct or constrained
- reflection
- dynamic code
- explicit `throw`
- calls summarized as throwing
- unknown external calls
- AOT/trimming blockers for the configured target
- disposable resource creation/opening
- pool rent unless the pool precondition is satisfied
- unproven implicit trap obligations unless explicitly allowed
- hidden first-use work unless hot-readiness is satisfied

`[hot]` does not imply memory safety. A hot function may contain restricted
`unsafe` blocks if performance facts still pass and memory safety is either not
claimed or justified through `[trusted]`.

Reasoning:

- `[hot]` must be sharp, but it must be truthful about CLR behavior.
- Local self-allocation control and system-level latency are different claims.
- Memory safety and performance hotness are separate concerns.

## Explicit Throwing And Implicit Traps

The phrase "`[hot]` cannot throw" means two different things in v1:

1. **Explicit exception escape is banned.** A hot function cannot contain
   `throw`, call a function summarized as throwing, or rely on exception-based
   control flow.
2. **Common implicit CLR traps are proof obligations.** Indexing, slicing,
   null-dereference, divide/modulo by zero, and checked arithmetic must be
   proven safe by local flow facts, summarized preconditions, or an explicit
   `allow(trap)`.

Examples:

```nsharp
[hot]
func ReadTag(buf: ReadOnlySpan<byte>): Result<byte, ParseError> {
    if buf.Length < 1 { return Err(ParseError.Short) }
    return Ok(buf[0]) // bounds obligation discharged
}

[hot]
func Divide(n: int, d: int): Result<int, MathError> {
    if d == 0 { return Err(MathError.DivideByZero) }
    return Ok(n / d) // divide-by-zero obligation discharged
}
```

`allow(trap)` is reserved for narrow low-level code where the trap is an
intentional fail-fast condition:

```nsharp
allow(trap, reason: "internal invariant: generated table index is always valid") {
    value := table[index]
}
```

Rules:

- `allow(trap)` is not suggested for normal parser or boundary code.
- Bounds proofs cover canonical guards such as `i < span.Length`,
  `i + n <= span.Length`, and loop ranges derived from `.Length`.
- Null proofs use N# null-flow facts and explicit guards.
- Overflow proofs are required only in checked arithmetic contexts. Hot loop
  increments use the language's normal unchecked lowering when specified by the
  surrounding arithmetic semantics.

Reasoning:

- Saying no hot function can throw while allowing array indexing is dishonest
  unless the indexing obligation is defined.
- Proof obligations keep the strong product promise without banning normal span
  code.

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
    msg := $"id={id}"
    items := [1, 2, 3]
}
```

`alloc {}` does not automatically allow boxing, closure allocation, delegate
allocation, iterator/async state machine allocation, reflection, dynamic code,
or unknown external allocations.

Inside `[hot]` or `[alloc(none)]`, even `alloc new` is rejected unless wrapped in
a narrow allow region:

```nsharp
[hot]
func BuildOnce() {
    allow(alloc, reason: "one-time lookup table construction outside steady path") {
        table := alloc new LookupTable()
    }
}
```

Rules:

- `alloc new` is always legal in the language.
- Systems strict diagnoses plain heap `new`.
- `[hot]` rejects heap allocation even when marked.
- Factory methods that allocate are represented by call summaries, not by the
  `alloc` keyword.

Reasoning:

- `new` is not always heap allocation on .NET.
- The systems profile must not change what `new` means.
- Allocation markers create reviewable intent without pretending method calls
  are syntactically markable.

## Allows And Escapes

Allow escapes are available at function and block level in v1:

```nsharp
[hot]
[allow(dispatch: interface, reason: "strategy selected once per packet family")]
func Parse(...) {
    ...
}

allow(alloc, reason: "diagnostic path only after parse failure") {
    msg := alloc $"bad frame at {offset}"
}
```

Rules:

- Block-level allows are preferred.
- Function-level allows require `reason`.
- Public API allows require `reason` and `owner`.
- Expression-level `allow` is deferred.
- Diagnostics should suggest the narrowest block-level allow.
- `allow(...)` cannot justify memory safety. Use `[trusted]` for that.
- `allow(...)` cannot invent facts for unknown external code; it only waives a
  project policy after the effect is known and reported.

Reasoning:

- Mandatory prose on every tiny local allow becomes ceremony. Requiring reasons
  at function/public scope is the useful governance point.
- A local allow is a policy waiver, not a proof mechanism.

## Delegates And Closures

Systems strict does not add a delegate allocation marker in v1.

Rules:

- Closure/delegate allocation is rejected in ordinary systems strict code unless
  allowed.
- It is allowed inside `[boundary]` and reported.
- It is allowed via `allow(delegate, reason: "...")` or
  `allow(closure, reason: "...")`.
- `[hot]` rejects delegate dispatch unless the target is summarized as direct,
  cached, and hot-ready, or the call is explicitly allowed.
- Non-capturing cached delegates require hot-readiness facts for the static
  cache initialization.

Delegate-shaped APIs may be allowed outside `[hot]` only when summaries prove no
per-call allocation and dispatch policy permits invocation.

Reasoning:

- Delegates are core .NET interop, but not a good default systems abstraction.
- Construction allocation, cache initialization, and per-call delegate dispatch
  are separate facts.

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
  reflection/dynamic code, throwing/catching, virtual dispatch, unknown external
  calls, and AOT blockers are listed in systems reports.
- Boundaries catch and translate .NET exceptions into explicit result or error
  values when crossing into systems code.
- The exported boundary surface must not leak systems-hostile shapes into
  `[hot]` code.
- Source-generated paths are preferred for AOT-sensitive work:
  `LibraryImport` over `DllImport`, `System.Text.Json` source-generation over
  reflection serialization, and `[GeneratedRegex]` over runtime regex
  compilation when possible.
- AOT blockers inside a boundary are reported as `aotSafe(target): false`.
  `allow(aot: blocked)` bookkeeping is cut from v1.

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
- readonly structs that satisfy layout and summary rules
- ref structs
- `Span<T>` / `ReadOnlySpan<T>` with lifetime rules
- compiler-known `Result<T,E>`
- selected BCL types with HotSummary coverage

General systems code may accept pragmatic managed surfaces:

- existing strings
- existing arrays
- `ReadOnlyMemory<T>` / `Memory<T>`
- selected immutable or systems-safe types
- selected BCL types with known contracts
- handles/owners that have disposal summaries

Managed crossings are visible in reports.

Boundary leaks include:

- returning `IEnumerable<T>`, `IQueryable<T>`, `object`, `dynamic`, or
  reflection-heavy framework types into `[hot]` code
- exposing unsummarized interfaces to hot callers
- returning mutable BCL collections where resizing/allocation is possible
  inside the subsequent hot path
- returning `Task<T>`/async state machines into hot paths instead of adapting at
  the boundary

Reasoning:

- Banning all managed references would make .NET systems code impractical.
- Letting arbitrary managed objects into hot paths would weaken the performance
  promise.
- Strings and arrays must be supported as existing inputs, but spans should be
  the preferred hot API surface.

## Managed Reads In Hot Code

`[hot]` may read existing managed references in v1 when the operation is proven
non-allocating and non-mutating and its implicit traps are discharged.

Allowed examples include known-safe string/array/span operations such as:

- `string.Length`
- `string[i]`, with bounds and null obligations
- array `.Length`
- array indexing, with bounds and null obligations
- `Span<T>.Length`
- span indexing/slicing, with bounds obligations

Property getters are allowed only when proven trivial:

- compiler-known N# stored property/direct field read
- known BCL intrinsic
- HotSummary-covered getter
- tiny external IL-proven getter such as `ldarg.0; ldfld; ret`

Unknown getters fail in `[hot]` unless explicitly allowed.

Reasoning:

- On the CLR, a property is a method and may allocate, throw, lock, lazily
  initialize, or dispatch virtually.
- External proof must be conservative and versioned.

## Memory Creation

V1 includes a real memory-creation story.

Safe stack allocation:

```nsharp
[hot]
func ParseSmall(buf: ReadOnlySpan<byte>): Result<Header, ParseError> {
    scratch := stackalloc byte[64]
    ...
}
```

Rules:

- `stackalloc` is legal without `unsafe` when assigned to `Span<T>` or
  `ReadOnlySpan<T>` and `T` is unmanaged.
- The length must be statically bounded by a project-configurable stack budget
  or guarded by a compiler-recognized maximum.
- The initial implementation reads that budget from
  `language.systems.stackBudgetBytes` and defaults it to 4096 bytes.
- Stack-allocated spans are `local` lifetime and cannot be returned, captured,
  stored in heap fields, used across `await`, or used across iterator yield.
- Arbitrary pointer access still requires restricted `unsafe`.

Heap-backed arenas:

```nsharp
struct Arena {
    backing: byte[]
    offset: int
}

func MakeArena(bytes: int): Arena {
    return Arena { backing: alloc new byte[bytes], offset: 0 }
}

[hot]
func Alloc(self: &Arena, n: int): Result<Span<byte>, ArenaError> {
    if self.offset + n > self.backing.Length { return Err(ArenaError.Full) }
    s := self.backing.AsSpan(self.offset, n)
    self.offset += n
    return Ok(s)
}
```

Rules:

- Returning a span into a heap-backed buffer is legal when the return lifetime is
  `heap(owner)` or `param(self)`, not `local`.
- Returning a span into stack memory is illegal.
- Arena APIs must state or infer the returned lifetime.

Reasoning:

- A systems language that can only consume caller buffers is too narrow.
- C# permits safe `Span<T> b = stackalloc byte[256]`; N# cannot be more
  restrictive without a strong reason.
- CLR spans require lifetime precision, not blanket "spans are local-only."

## Lifetime And Ref Safety

V1 includes CLR-native lifetime/ref safety, not Rust ownership.

Source features:

```nsharp
ref struct FrameReader {
    buf: ReadOnlySpan<byte>
    pos: int
}

func Slice<'a>(buf: ReadOnlySpan<byte> scoped 'a, start: int, len: int): ReadOnlySpan<byte> returns 'a {
    return buf.Slice(start, len)
}
```

Rules:

- `ref struct` declarations are supported.
- Ref-like fields are allowed only in `ref struct`.
- `Span<T>`, `ReadOnlySpan<T>`, and ref structs cannot escape to heap fields,
  closures, async state machines, iterators, boxing, or interface storage.
- Explicit `scoped` is available for advanced interop/API clarity.
- Return-lifetime facts distinguish `local`, `param(name)`, `heap(owner)`,
  `static`, and `unknown`.
- Returning `unknown` lifetime into `[hot]` fails.
- Diagnostics explain lifetime violations in N# terms and include the escape
  path.

Reasoning:

- This maps to the CLR's existing ref-like model.
- Full borrow checking, move-only types, and affine ownership are out of v1.
- Return-lifetime rules are required for arenas and zero-copy readers.

## Pooling

Pooling is modeled separately from allocation.

Recognized v1 APIs:

- `ArrayPool<T>.Shared.Rent`
- `ArrayPool<T>.Return`
- selected `MemoryPool<T>` rent/dispose patterns

Effects:

- `Rent` has a `poolRent` effect, not an unconditional `allocation` effect.
- `Rent` may allocate during pool growth or warmup unless a HotSummary
  precondition says the pool is warm-ready for the requested size.
- `Return` satisfies a rent/return balance obligation.
- Missing `Return` is `NSYS130`.

Rules:

- `[hot]` may call `Rent` only when the pool and bucket are hot-ready, or inside
  a cold branch with an explicit allow.
- Boundary code may rent and return buffers and pass spans into hot parsers.
- The analyzer tracks obvious lexical balance and `using`/`try/finally` patterns.
- It does not promise full linear ownership in v1.

Reasoning:

- `ArrayPool<T>` is a standard .NET zero-GC tool.
- Treating `Rent` as always allocating rejects real systems patterns.
- Treating `Rent` as free hides pool warmup and leak risks.

## Concurrency And Atomics

V1 does not introduce broad thread-safety effects.

It does make core concurrency primitives hot-callable through the BCL Hot Pack:

- `Volatile.Read`
- `Volatile.Write`
- `Interlocked.Exchange`
- `Interlocked.CompareExchange`
- `Interlocked.Increment`
- `Interlocked.Decrement`
- `Interlocked.Add`
- `Thread.MemoryBarrier`

Semantics:

- `Volatile.Read` is acquire.
- `Volatile.Write` is release.
- `Interlocked.*` operations are atomic read-modify-write operations with the
  CLR's full-fence semantics.
- The summary records allocation/throw/dispatch facts and memory-ordering facts.

Rules:

- Lock-free structures remain responsible for their own algorithmic correctness.
- Systems reports can show concurrency primitives used by a hot path.
- A future thread-safety effect lane may reason about data races, but v1 does
  not claim that.

Reasoning:

- A systems profile that cannot express a ring buffer, counter, or work queue is
  not credible.
- The CLR already provides the primitives; N# needs summaries and diagnostics,
  not new syntax.

## Error Model And Result ABI

Hot/systems code should use explicit result values instead of exceptions.

V1 defines a compiler-known allocation-free `Result<T,E>`:

```nsharp
result Result<T, E> {
    Ok(T)
    Err(E)
}
```

Conceptual CLR ABI:

```csharp
public readonly struct Result<T, E>
{
    public bool IsOk { get; }
    public bool IsErr { get; }
    public bool TryGetOk(out T value);
    public bool TryGetErr(out E error);
}
```

Compiler layout requirements:

- allocation-free readonly struct
- tag field
- ok payload field
- err payload field
- inactive reference fields are cleared to avoid retaining objects
- no reference identity for cases
- `must-use` diagnostic when ignored
- size diagnostic when `sizeof(Result<T,E>)` or copy shape is too large

Rules:

- `[hot]` cannot use exception control flow.
- Boundaries catch and translate .NET exceptions into `Result<T,E>` or equivalent
  error values.
- `Result<T,E>` supports reference and value payloads.
- General generic `value union` is deferred from v1.

Reasoning:

- A blessed result shape is needed because every hot API otherwise invents its
  own error ABI.
- The C# consumer story must be concrete.
- Keeping `Result<T,E>` compiler-known avoids overcommitting to arbitrary generic
  value unions before the representation is proven.

## Value Unions

V1 does not ship general arbitrary generic `value union`.

Rules:

- Existing union representation remains available where already supported.
- Non-payload or small closed value unions may be optimized under existing
  layout rules.
- `Result<T,E>` is the special v1 allocation-free generic result shape.
- Payload-carrying public arbitrary value unions are deferred until their C# ABI,
  size behavior, and pattern-matching lowering are proven.

Reasoning:

- Public C#-natural unions and allocation-free systems unions are different ABI
  promises.
- The adversarial review correctly separated `Result<T,E>` from arbitrary value
  unions.

## External Dependencies

V1 cuts broad transitive package IL proof.

Supported v1 inputs:

- compiler-inferred facts for source in the current project
- facts from referenced N# projects that emit versioned summaries
- BCL Hot Pack facts
- explicit sidecar HotSummary files for selected external APIs
- tiny IL-proven facts for trivial getters and helpers

Tiny IL proof covers only:

- trivial getter: `ldarg.0; ldfld; ret`
- trivial static readonly field/property load
- primitive arithmetic helper with no calls, allocation, boxing, or throw
- readonly struct helper with direct field reads/arithmetic only

Sidecar summaries are keyed by:

- assembly identity
- target framework
- RID assumptions
- method signature
- MVID/body hash or package version plus metadata identity

Reasoning:

- Real .NET packages are multi-targeted and RID-sensitive.
- A full package prover is a research project and should not block v1.
- Stable sidecar summaries give teams a practical bridge without lying about
  proof strength.

## NativeAOT And Trimming

Systems profile reports target-qualified deployment facts:

- `aotSafe(nativeaot)`
- `aotSafe(coreclr)`
- `aotSafe(mono-wasm)`
- `trimSafe`

Current repository reality:

- `nlc publish --aot` is analysis-only today: it fails on blockers and annotates
  APIs, but does not emit a native image.
- Systems N# must not market native-image support until native image emission is
  implemented and verified.

Rules:

- AOT blockers are errors in systems strict for the configured target.
- `[boundary]` does not automatically waive AOT blockers.
- Source-generated interop/serialization/regex paths are the preferred way to
  satisfy NativeAOT and trimming.
- Reports distinguish analysis status from emitted artifact status.

Example report fragment:

```json
{
  "schemaVersion": 1,
  "systems": "pass",
  "aot": {
    "target": "nativeaot",
    "analysis": "pass",
    "nativeImageEmitted": false
  },
  "hot": "pass",
  "memorySafety": "notClaimed"
}
```

The first real Systems N# deployment milestone requires actual native binary
generation:

```bash
nlc publish --aot
```

Reasoning:

- A systems language on .NET needs a deployment story, but analysis-only AOT is
  not native compilation.
- Reflection/trimming/codegen rules differ across NativeAOT, CoreCLR, and
  Mono/WASM.

## Resource Management And Async Boundaries

Systems strict enforces obvious `IDisposable` and `IAsyncDisposable` ownership.

Rules:

- Disposable values created locally must be disposed, returned/transferred, or
  stored into an owning location once ownership semantics exist.
- `using` and `await using` are recognized.
- `try/finally` is recognized for pool return and disposal.
- `[hot]` cannot create/open disposable resources in v1.
- `[hot]` cannot be an async function or iterator in v1.
- Async IO belongs at `[boundary]` functions that adapt results into spans,
  buffers, or explicit result values.
- `ValueTask<T>` is supported at boundaries where it is part of the .NET API
  contract, but no "zero allocation async" claim is made without effect facts.

Reasoning:

- Systems IO is often async, but async state machines and disposal patterns are
  boundary concerns in v1.
- Existing .NET `using`/`await using` patterns are familiar and map to standard
  IL.
- `defer` is deferred; enforcement matters more than a new keyword.

## Restricted Unsafe And Memory Safety

Restricted unsafe is available in any N# project when explicit:

```nsharp
unsafe {
    ...
}
```

Initial restricted unsafe scope:

- function pointers where CLR-supported
- fixed/native interop essentials
- tightly checked pointer-like operations behind trusted wrappers
- no broad arbitrary pointer arithmetic in the first slice

Safe `stackalloc` to `Span<T>` does not require `unsafe`; pointer access still
does.

Memory safety is a separate effect dimension:

```nsharp
[memory(safe)]
func Parse(...) { ... }
```

Safe wrappers over unsafe code require trust:

```nsharp
[memory(safe)]
[trusted(
    reason: "len <= min(dst.Length, src.Length) checked before copy",
    owner: "runtime-core",
    review: "2026-12-01",
    expires: "2027-06-01"
)]
func Copy(dst: Span<byte>, src: ReadOnlySpan<byte>, len: int) {
    unsafe {
        ...
    }
}
```

Rules:

- Systems profile does not default to memory safe.
- Exported APIs in systems-profile libraries need explicit or inferred memory
  safety summaries.
- `[trusted]` is valid only when paired with a memory-safety contract.
- `[trusted]` requires `reason`, `owner`, and `review`.
- `expires` is recommended and may become required for public packages.
- `[trusted]` may justify memory safety, not performance facts.
- `[trusted]` bodies are linted for size and complexity.
- `nlc query trusted` reports owner, review, expiry, body size, unsafe use, and
  callers.

Reasoning:

- Safe abstractions over unsafe code are a normal systems pattern.
- Trust without governance rots into a blanket escape hatch.
- Memory-safety trust must not fake allocation-free or dispatch-free facts.

## Hot LINQ Contract

V1 does not bless ZLinq by name in the language spec.

Instead, N# defines a hot-LINQ contract:

- no per-element allocation
- no hidden boxing
- no closure allocation after hot-readiness
- direct or constrained dispatch only
- summarized operators and terminal operations
- target-runtime identity in the summary
- clear fallback diagnostics when an operator is unsupported

Rules:

- `System.Linq` is rejected in `[hot]` unless proven safe by summaries.
- Any library, including ZLinq, may qualify by shipping or being covered by
  HotSummary facts that satisfy the contract.
- Migration from `System.Linq` to a hot-compatible profile is a diagnostic or
  codefix, never a silent compiler rewrite.

Reasoning:

- A blanket LINQ ban is too crude.
- Coupling the compiler to one third-party package's cadence is not a stable
  language design.

## SIMD And Codegen Visibility

V1 SIMD support is diagnostics and guidance plus HotSummary coverage for known
BCL APIs.

Rules:

- `System.Numerics.Vector<T>` and hardware intrinsics should type-check cleanly.
- The compiler can recognize simple vectorization opportunities and report
  suggestions.
- No auto-vectorization or new vector syntax in v1.
- Reports expose IL-shape facts relevant to systems code: `newobj`, `newarr`,
  `box`, `callvirt`, delegate construction, constrained calls, and known
  intrinsic calls.
- Runtime benchmarking is done with BenchmarkDotNet against compiled N#
  assemblies; N# does not add a fragile wall-clock benchmark runner in v1.
- The repository benchmark corpus includes a Systems BenchmarkDotNet gate with
  124 required rows, matched C# baselines, `MemoryDiagnoser`, zero-allocation
  enforcement, and a 1.25 throughput-ratio gate. It covers hot loops over
  caller-owned memory at small and large sizes, span handoff and array-to-span
  coercion, caller write buffers, direct `Result<T,E>` ABI use, pooled boundary
  handoff, and hot+result combination paths. Small-workload rows normalize the
  C# side through delegates where the N# side is delegate-bound so wrapper
  overhead is charged symmetrically.
- `Result<T,E>` hot code uses direct `TryGet*`/`Is*` tag inspection. The
  delegate-based `Match` helper remains a C# interop convenience, not the
  systems-hot path, because delegate dispatch cannot match direct tagged-struct
  dispatch.

Reasoning:

- Systems engineers need codegen visibility.
- The repository already documents IL shape as N#'s deterministic performance
  signal; wall-clock numbers should use mature .NET tooling.

## Templates

Systems templates should exist as both dedicated names and flags after the
core checks are implemented:

```bash
nlc new systems-cli PacketTool
nlc new systems-lib PacketCore
nlc new console --systems
nlc new lib --systems
```

Templates include:

- `language.profile: systems`
- strict defaults
- target-qualified AOT analysis config
- sample `[hot]` parser
- sample `[boundary]` adapter
- sample warmup function
- sample `Result<T,E>` API
- systems tests
- `nlc check --systems-report`
- `nlc build --perf-report`

Reasoning:

- Dedicated templates give Systems N# product identity.
- Flags avoid template sprawl and support discoverability.
- Libraries should avoid default third-party dependencies.

## Deferred From V1

- standalone `nlc systems ...` command family
- `audit-package` over the full transitive NuGet graph
- effect lockfile and `freeze-effects`
- expression-level `allow`
- broad ownership/move/borrow model
- `defer`
- full thread-safety/data-race effects
- arbitrary pointer arithmetic
- steady-state-only `[hot(phase: steadyState)]`
- broad user-defined systems-safe class/frozen object model
- compiler-native vector syntax
- built-in wall-clock benchmark/probe runner
- general arbitrary generic `value union`
- package-wide trusted user facts satisfying `[hot]`

Reasoning:

- These features may be valuable, but each adds significant semantic surface.
- V1 should prove HotSummary, BCL coverage, hot-readiness, `[hot]` checking,
  memory creation, ref safety, pooling, atomics, AOT analysis, boundary
  adaptation, and tooling before expanding.

## Acceptance Gauntlet

V1 is not credible until these examples pass as designed:

1. Packet parser over `ReadOnlySpan<byte>` using `BinaryPrimitives`.
2. Binary frame writer into `Span<byte>` with discharged bounds obligations.
3. Lock-free SPSC ring buffer using `Volatile` and `Interlocked`.
4. Heap-backed arena returning spans with correct return lifetimes.
5. `ref struct` zero-copy frame reader.
6. Pooled file IO boundary feeding a hot parser with balanced rent/return.
7. Safe wrapper over unsafe copy using `[memory(safe)]` and governed
   `[trusted]`.
8. Order-book update loop with preallocated storage or clear diagnostics for
   resizing collections.
9. Native interop boundary using `LibraryImport`.
10. Source-generated JSON CLI path reported as target-qualified AOT-safe.

Each example must have:

- source sample
- `nlc check --systems-report` golden JSON
- human diagnostic golden text for at least one failure case
- `nlc build --perf-report` evidence
- C# interop evidence where the API is public

## Major Open Questions

1. What exact syntax should lifetime names and `returns 'a` use in N# once parser
   constraints are considered?
2. What is the minimum BCL Hot Pack needed for the first public preview?
3. How should HotSummary sidecars be distributed and versioned for packages?
4. How strict should systems-safe managed type rules be before a full `frozen`
   model exists?
5. How much interprocedural effect inference is needed before v1 is usable?
6. What is the minimum NativeAOT template surface that makes Systems N# credible
   after native image emission exists?
7. Which source-generated APIs should be recognized first?
8. What exact schema should `nlc check --systems-report` use?
9. How should warmup functions be verified in tests?
10. Which acceptance-gauntlet examples are required before a public preview?

## Initial Implementation Task Series

1. Finalize this proposal through review with real systems examples.
2. Build HotSummary data model and schema.
3. Add BCL Hot Pack seed summaries for spans, arrays, strings,
   `BinaryPrimitives`, `BitOperations`, `MemoryMarshal`, `Math`, `Volatile`,
   `Interlocked`, and pool APIs.
4. Add parser/analyzer support for `[hot]`, `[boundary]`, `[alloc(none)]`,
   `[memory(safe)]`, `[trusted(...)]`, and `[allow(...)]`.
5. Add syntax for `alloc new`, `alloc $"..."`, `alloc [...]`, and `alloc {}`.
6. Add `stackalloc` to safe span syntax.
7. Add `ref struct`, ref-like fields, `scoped`, and return-lifetime analysis.
8. Enforce `[hot]` locally in default projects.
9. Add explicit throw and implicit trap proof obligations for `[hot]`.
10. Add hot-readiness facts and warmup reporting.
11. Add `language.profile: systems`, strict default, and `NSYS###` findings.
12. Add `nlc check --systems-report` with canonical versioned JSON.
13. Add precise per-fact drift output to `nlc check`.
14. Add boundary leak rules and systems-safe surface classification.
15. Add target-qualified AOT/trimming facts.
16. Add pooling rent/return balance checks.
17. Add `Result<T,E>` compiler-known struct ABI, must-use, and size diagnostics.
18. Add `[trusted]` governance lint and `nlc query trusted`.
19. Add systems templates after the checks produce useful reports.
20. Add docs, examples, and acceptance tests based on the gauntlet.

## Appendix A: Use Cases And How Systems Features Address Them

The first 23 use cases are small enough to challenge inline as one-file samples
in Appendix B. Use cases 24-48 are complex proof projects under
`docs/design/systems-samples/proofs/`.

Implementation note: Appendix B and the proof projects are proposal pressure
tests. The current executable implementation evidence is the ten-case acceptance
gauntlet under `tests/fixtures/systems-gauntlet/`, executable proof projects
31, 32, 36, 44, and 45 under `docs/design/systems-samples/proofs/`, the Systems
N# unit/CLI tests, and the 124-row Systems BenchmarkDotNet gate. The remaining
24-48 proof projects are design-only until migrated and audited in
`docs/audits/systems-proof-project-audit.md`.

| # | Use case | Systems features that address it | V1 posture | Sample |
| ---: | --- | --- | --- | --- |
| 1 | Parse a binary packet header from a socket buffer. | `[hot]`, `ReadOnlySpan<byte>`, `BinaryPrimitives` BCL Hot Pack, bounds trap proofs, `Result<T,E>`. | Must pass. | [B01](#b01-packet-header-read-use-case-1) |
| 2 | Write a binary frame into caller-provided memory. | `[hot]`, `Span<byte>`, slice/index proofs, `BinaryPrimitives.Write*`, explicit result errors. | Must pass. | [B02](#b02-frame-writer-use-case-2) |
| 3 | Decode variable-length integers without allocation. | `[hot]`, span loops, unchecked loop arithmetic where appropriate, trap obligations for indexing. | Must pass. | [B03](#b03-varint-decoder-use-case-3) |
| 4 | Compute CRC/checksum over a span. | `[hot]`, direct loops, `BitOperations`, no allocation/boxing facts, IL-shape report. | Must pass. | [B04](#b04-checksum-use-case-4) |
| 5 | Validate UTF-8 in a buffer. | `[hot]`, span reads, BCL summaries for safe primitives, explicit error values instead of exceptions. | Must pass for parser-owned loops; BCL helpers need summaries. | [B05](#b05-utf-8-validation-use-case-5) |
| 6 | Scan JSON tokens before materializing objects. | `[hot]` scanner over spans, `Result<T,E>`, boundary materialization for allocated DOM objects. | Hot scanner in scope; full `Utf8JsonReader` requires summaries or boundary adaptation. | [B06](#b06-json-token-scan-use-case-6) |
| 7 | Parse CSV rows from pooled file buffers. | `[boundary]` file IO, `ArrayPool<T>` rent/return, hot parser over `ReadOnlySpan<byte>`. | Must pass. | [B07](#b07-pooled-csv-count-use-case-7) |
| 8 | Parse FIX/order-entry messages. | `[hot]`, stack scratch buffers, span slicing, `Result<T,E>`, hot-readiness for lookup tables. | Must pass. | [B08](#b08-fix-message-tag-scan-use-case-8) |
| 9 | Decode telemetry frames in an agent. | Systems strict profile, BCL Hot Pack, warmup plan, AOT/trimming facts. | In scope. | [B09](#b09-telemetry-frame-use-case-9) |
| 10 | Serialize a protocol response without allocations. | `[hot]` writer, caller-provided `Span<byte>`, `BinaryPrimitives`, explicit no-space errors. | In scope. | [B10](#b10-protocol-response-writer-use-case-10) |
| 11 | Implement an SPSC ring buffer. | `Volatile`, `Interlocked`, explicit acquire/release facts, array index proofs. | Must pass algorithmically; no data-race proof claimed. | [B11](#b11-spsc-ring-buffer-use-case-11) |
| 12 | Maintain a lock-free metrics counter. | `Interlocked.Increment/Add`, `[hot]`, no allocation facts. | In scope. | [B12](#b12-metrics-counter-use-case-12) |
| 13 | Adapt a framework work queue to hot workers. | `[boundary]` for framework queue, systems-safe handoff type, `[hot]` worker. | In scope. | [B13](#b13-work-queue-adapter-use-case-13) |
| 14 | Apply order-book updates with predictable allocation. | Preallocated storage, `[hot]` loops, diagnostics for `Dictionary` resize/throw paths. | In scope with preallocated/custom storage; ordinary `Dictionary` mutation gets diagnostics. | [B14](#b14-order-book-update-use-case-14) |
| 15 | Update game ECS component arrays. | `Span<T>`, direct loops, `System.Numerics`, no boxing/dispatch, IL-shape report. | In scope. | [B15](#b15-ecs-update-use-case-15) |
| 16 | Run audio DSP over sample buffers. | `[hot]`, spans, `MathF`, SIMD guidance, no allocation/boxing. | In scope. | [B16](#b16-audio-dsp-use-case-16) |
| 17 | Transform image pixels in-place. | `Span<T>`, unmanaged structs, vector summaries, bounds proof in counted loops. | In scope. | [B17](#b17-image-pixel-transform-use-case-17) |
| 18 | Implement a compression block codec. | stackalloc scratch, spans, `BitOperations`, hot-readiness for tables. | In scope. | [B18](#b18-rle-block-codec-use-case-18) |
| 19 | Process game network packets. | `[boundary]` socket IO, `[hot]` packet decode, `Result<T,E>`, pooled buffers. | In scope. | [B19](#b19-game-network-packet-use-case-19) |
| 20 | Search a memory-mapped binary index. | Boundary mapping/opening, hot span reader over existing memory, lifetime rules. | In scope if memory owner lifetime is modeled. | [B20](#b20-memory-mapped-index-search-use-case-20) |
| 21 | Use a precomputed lookup table in hot code. | hot-readiness, warmup functions, static initializer diagnostics. | In scope. | [B21](#b21-precomputed-lookup-use-case-21) |
| 22 | Use a heap-backed arena for per-request temporaries. | `alloc new` at setup, arena return-lifetime rules, hot allocation from backing span. | In scope. | [B22](#b22-heap-backed-arena-use-case-22) |
| 23 | Use `stackalloc` for small scratch space. | Safe `stackalloc` to span, stack budget diagnostics, local lifetime rules. | Must pass. | [B23](#b23-stackalloc-scratch-use-case-23) |
| 24 | Build a zero-copy frame reader. | `ref struct`, ref-like fields, return-lifetime facts, `BinaryPrimitives`. | Must pass. | [Project](systems-samples/proofs/24-zero-copy-frame-reader/) |
| 25 | Wrap unsafe memory copy safely. | restricted `unsafe`, `[memory(safe)]`, `[trusted(reason, owner, review)]`, small-body lint. | Must pass. | [Project](systems-samples/proofs/25-trusted-memory-copy/) |
| 26 | Open a native device handle. | `[boundary]`, `LibraryImport`, explicit handle owner/disposal, `Result<T,E>`. | In scope. | [Project](systems-samples/proofs/26-native-device-handle/) |
| 27 | Call a C library from a systems CLI. | source-generated P/Invoke, AOT facts, boundary adaptation. | In scope. | [Project](systems-samples/proofs/27-c-library-cli/) |
| 28 | Parse command-line options and emit JSON in NativeAOT. | Boundary allocation, `System.Text.Json` source-gen, target-qualified AOT facts. | Analysis in scope now; native image waits for publish implementation. | [Project](systems-samples/proofs/28-nativeaot-json-cli/) |
| 29 | Use generated regex in a boundary parser. | `[GeneratedRegex]` summary, boundary allocation report, AOT/trimming facts. | In scope with generated-code summary. | [Project](systems-samples/proofs/29-generated-regex-boundary/) |
| 30 | Log diagnostic details only on cold failures. | `[hot]` success path, narrow `allow(alloc)` in cold branch, allocation report. | In scope. | [Project](systems-samples/proofs/30-cold-failure-logging/) |
| 31 | Emit metrics from hot code. | `Interlocked`, no string formatting in hot path, boundary exporter. | In scope. | [Project](systems-samples/proofs/31-hot-metrics/) |
| 32 | Prewarm caches before accepting traffic. | hot-readiness model, warmup config, `.cctor` and pool warmup reports. | In scope. | [Project](systems-samples/proofs/32-cache-prewarm/) |
| 33 | Use `ArrayPool<byte>` for file IO. | `poolRent` effect, rent/return balance, warm-ready precondition. | Must pass. | [Project](systems-samples/proofs/33-arraypool-file-io/) |
| 34 | Use `MemoryPool<byte>` with disposal. | resource ownership, `IAsyncDisposable`/`IDisposable`, pool summaries. | In scope for selected patterns. | [Project](systems-samples/proofs/34-memorypool-disposal/) |
| 35 | Build an async file reader feeding a hot parser. | `[boundary]` async IO, `ValueTask<T>` where API requires it, hot span parser. | Boundary in scope; `[hot] async` deferred. | [Project](systems-samples/proofs/35-async-file-hot-parser/) |
| 36 | Use `Dictionary` in setup then read in hot code. | boundary/setup allocation, hot-readiness, diagnostics for resize/throwing mutations. | Reads only if summarized and trap/throw risks handled. | [Project](systems-samples/proofs/36-dictionary-setup-hot-read/) |
| 37 | Implement a custom fixed-capacity map. | structs, arrays/spans, index proofs, no allocation after construction. | In scope. | [Project](systems-samples/proofs/37-fixed-capacity-map/) |
| 38 | Sort unmanaged records with a comparer. | generic parametric summaries, constrained value-type dispatch, no boxing. | In scope after generic summaries. | [Project](systems-samples/proofs/38-unmanaged-sort-comparer/) |
| 39 | Run a hot-compatible LINQ-style pipeline. | hot-LINQ contract, library HotSummary, closure/delegate facts, hot-readiness. | In scope by contract, not by ZLinq name. | [Project](systems-samples/proofs/39-hot-linq-pipeline/) |
| 40 | Expose a hot parser to C# callers. | C#-natural public ABI, `Result<T,E>` struct ABI, `ReadOnlySpan<byte>` parameters. | In scope. | [Project](systems-samples/proofs/40-csharp-hot-parser-api/) |
| 41 | Return structured errors without exceptions. | `Result<T,E>`, must-use, pattern matching, boundary exception translation. | Must pass. | [Project](systems-samples/proofs/41-structured-errors/) |
| 42 | Keep public APIs AOT/trimming friendly. | `aotSafe(target)`, `trimSafe`, source-generator guidance, boundary reports. | In scope as analysis; native image later. | [Project](systems-samples/proofs/42-aot-friendly-public-api/) |
| 43 | Build a plugin that runs on Mono/WASM. | target-qualified AOT facts, no dynamic-code summaries, boundary restrictions. | In scope as target analysis. | [Project](systems-samples/proofs/43-mono-wasm-plugin/) |
| 44 | Validate no unexpected allocation in CI. | `nlc check --systems-report`, `nlc build --perf-report`, precise per-fact diffs. | In scope; lockfile deferred. | [Project](systems-samples/proofs/44-ci-allocation-gate/) |
| 45 | Audit unsafe wrappers before release. | `[trusted]` governance, owner/review/expiry metadata, `nlc query trusted`. | In scope. | [Project](systems-samples/proofs/45-trusted-audit/) |
| 46 | Adapt Dapper/EF/database calls. | `[boundary]`, allocation/reflection reports, explicit DTO/result handoff. | Boundary in scope; hot ORM calls out of scope. | [Project](systems-samples/proofs/46-dapper-boundary/) |
| 47 | Keep a CLI startup path honest. | hot-readiness, AOT/trimming facts, IL-shape report, source-generated JSON/regex. | In scope; actual native image later. | [Project](systems-samples/proofs/47-cli-startup-honesty/) |
| 48 | Diagnose a dependency helper that became allocation-heavy. | HotSummary body identity, source-inferred facts, `NSYS150` per-fact drift. | In scope for source/referenced N# projects; broad NuGet proof deferred. | [Project](systems-samples/proofs/48-effect-drift/) |

## Appendix B: Basic One-File Samples

These inline samples intentionally use proposed Systems N# syntax. They are
design proof inputs, not current compiler fixtures.

### B01 Packet Header Read (Use Case 1)

```nsharp
namespace SystemsSamples.Basic01

import System
import System.Buffers.Binary

struct Header {
    Version: ushort
    Length: uint
}

enum HeaderError {
    Short
}

[hot]
func ParseHeader(buf: ReadOnlySpan<byte>): Result<Header, HeaderError> {
    if buf.Length < 6 {
        return Err(HeaderError.Short)
    }

    return Ok(Header {
        Version: BinaryPrimitives.ReadUInt16LittleEndian(buf.Slice(0, 2)),
        Length: BinaryPrimitives.ReadUInt32LittleEndian(buf.Slice(2, 4))
    })
}
```

### B02 Frame Writer (Use Case 2)

```nsharp
namespace SystemsSamples.Basic02

import System
import System.Buffers.Binary

enum WriteError {
    NoSpace
}

[hot]
func WriteFrame(dst: Span<byte>, tag: byte, length: uint): Result<int, WriteError> {
    if dst.Length < 5 {
        return Err(WriteError.NoSpace)
    }

    dst[0] = tag
    BinaryPrimitives.WriteUInt32LittleEndian(dst.Slice(1, 4), length)
    return Ok(5)
}
```

### B03 Varint Decoder (Use Case 3)

```nsharp
namespace SystemsSamples.Basic03

import System

enum VarintError {
    Truncated
    TooLarge
}

[hot]
func ReadVarint(buf: ReadOnlySpan<byte>): Result<int, VarintError> {
    value := 0
    shift := 0

    for i := 0; i < buf.Length; i++ {
        b := buf[i]
        value = value | ((b & 0x7F) << shift)
        if (b & 0x80) == 0 {
            return Ok(value)
        }
        shift = shift + 7
        if shift > 28 {
            return Err(VarintError.TooLarge)
        }
    }

    return Err(VarintError.Truncated)
}
```

### B04 Checksum (Use Case 4)

```nsharp
namespace SystemsSamples.Basic04

import System
import System.Numerics

[hot]
func Checksum32(buf: ReadOnlySpan<byte>): uint {
    crc := 0xFFFF_FFFFu
    for i := 0; i < buf.Length; i++ {
        crc = BitOperations.RotateRight(crc ^ buf[i], 3)
    }
    return crc
}
```

### B05 UTF-8 Validation (Use Case 5)

```nsharp
namespace SystemsSamples.Basic05

import System

enum Utf8Error {
    BadLead
    Truncated
}

[hot]
func ValidateAsciiOrTwoByteUtf8(buf: ReadOnlySpan<byte>): Result<int, Utf8Error> {
    i := 0
    while i < buf.Length {
        b := buf[i]
        if b < 0x80 {
            i = i + 1
        } else if b >= 0xC2 && b <= 0xDF {
            if i + 1 >= buf.Length {
                return Err(Utf8Error.Truncated)
            }
            cont := buf[i + 1]
            if (cont & 0xC0) != 0x80 {
                return Err(Utf8Error.BadLead)
            }
            i = i + 2
        } else {
            return Err(Utf8Error.BadLead)
        }
    }
    return Ok(i)
}
```

### B06 JSON Token Scan (Use Case 6)

```nsharp
namespace SystemsSamples.Basic06

import System

enum JsonScanError {
    Empty
    Unsupported
}

enum JsonToken {
    ObjectStart
    ArrayStart
    StringStart
    NumberStart
}

[hot]
func ScanFirstToken(buf: ReadOnlySpan<byte>): Result<JsonToken, JsonScanError> {
    i := 0
    while i < buf.Length && buf[i] <= 32 {
        i = i + 1
    }
    if i >= buf.Length {
        return Err(JsonScanError.Empty)
    }

    b := buf[i]
    if b == 123 { return Ok(JsonToken.ObjectStart) }
    if b == 91 { return Ok(JsonToken.ArrayStart) }
    if b == 34 { return Ok(JsonToken.StringStart) }
    if b >= 48 && b <= 57 { return Ok(JsonToken.NumberStart) }
    return Err(JsonScanError.Unsupported)
}
```

### B07 Pooled CSV Count (Use Case 7)

```nsharp
namespace SystemsSamples.Basic07

import System
import System.Buffers
import System.IO

[hot]
func CountCsvRows(buf: ReadOnlySpan<byte>): int {
    rows := 0
    for i := 0; i < buf.Length; i++ {
        if buf[i] == 10 {
            rows = rows + 1
        }
    }
    return rows
}

[boundary]
func ReadAndCountRows(path: string): int {
    bytes := ArrayPool<byte>.Shared.Rent(65536)
    try {
        n := File.OpenRead(path).Read(bytes)
        return CountCsvRows(bytes.AsSpan(0, n))
    } finally {
        ArrayPool<byte>.Shared.Return(bytes)
    }
}
```

### B08 FIX Message Tag Scan (Use Case 8)

```nsharp
namespace SystemsSamples.Basic08

import System

enum FixError {
    MissingEquals
}

[hot]
func FindTagValue(msg: ReadOnlySpan<byte>, tag: int): Result<ReadOnlySpan<byte>, FixError> {
    i := 0
    while i < msg.Length {
        current := 0
        while i < msg.Length && msg[i] >= 48 && msg[i] <= 57 {
            current = current * 10 + (msg[i] - 48)
            i = i + 1
        }
        if i >= msg.Length || msg[i] != 61 {
            return Err(FixError.MissingEquals)
        }
        i = i + 1
        start := i
        while i < msg.Length && msg[i] != 1 {
            i = i + 1
        }
        if current == tag {
            return Ok(msg.Slice(start, i - start))
        }
        i = i + 1
    }
    return Err(FixError.MissingEquals)
}
```

### B09 Telemetry Frame (Use Case 9)

```nsharp
namespace SystemsSamples.Basic09

import System
import System.Buffers.Binary

struct Telemetry {
    Kind: ushort
    Timestamp: ulong
}

enum TelemetryError {
    Short
}

[hot]
func DecodeTelemetry(buf: ReadOnlySpan<byte>): Result<Telemetry, TelemetryError> {
    if buf.Length < 10 {
        return Err(TelemetryError.Short)
    }
    return Ok(Telemetry {
        Kind: BinaryPrimitives.ReadUInt16LittleEndian(buf.Slice(0, 2)),
        Timestamp: BinaryPrimitives.ReadUInt64LittleEndian(buf.Slice(2, 8))
    })
}
```

### B10 Protocol Response Writer (Use Case 10)

```nsharp
namespace SystemsSamples.Basic10

import System
import System.Buffers.Binary

enum ResponseError {
    NoSpace
}

[hot]
func WriteResponse(dst: Span<byte>, requestId: uint, status: ushort): Result<int, ResponseError> {
    if dst.Length < 6 {
        return Err(ResponseError.NoSpace)
    }
    BinaryPrimitives.WriteUInt32LittleEndian(dst.Slice(0, 4), requestId)
    BinaryPrimitives.WriteUInt16LittleEndian(dst.Slice(4, 2), status)
    return Ok(6)
}
```

### B11 SPSC Ring Buffer (Use Case 11)

```nsharp
namespace SystemsSamples.Basic11

import System
import System.Threading

struct Ring {
    slots: int[]
    mask: int
    head: int
    tail: int
}

[hot]
func TryEnqueue(ring: &Ring, item: int): bool {
    head := Volatile.Read(ref ring.head)
    tail := Volatile.Read(ref ring.tail)
    if head - tail >= ring.slots.Length {
        return false
    }
    ring.slots[head & ring.mask] = item
    Volatile.Write(ref ring.head, head + 1)
    return true
}
```

### B12 Metrics Counter (Use Case 12)

```nsharp
namespace SystemsSamples.Basic12

import System.Threading

struct Counters {
    Packets: long
    Errors: long
}

[hot]
func RecordOk(counters: &Counters) {
    Interlocked.Increment(ref counters.Packets)
}

[hot]
func RecordError(counters: &Counters) {
    Interlocked.Increment(ref counters.Errors)
}
```

### B13 Work Queue Adapter (Use Case 13)

```nsharp
namespace SystemsSamples.Basic13

import System.Collections.Concurrent

struct WorkItem {
    Id: int
    Value: int
}

[hot]
func Process(item: WorkItem): int {
    return item.Id ^ item.Value
}

[boundary]
func Drain(queue: ConcurrentQueue<WorkItem>): int {
    total := 0
    item := WorkItem {}
    while queue.TryDequeue(out item) {
        total = total + Process(item)
    }
    return total
}
```

### B14 Order Book Update (Use Case 14)

```nsharp
namespace SystemsSamples.Basic14

import System

struct Level {
    Price: long
    Quantity: int
}

[hot]
func ApplyUpdate(levels: Span<Level>, price: long, delta: int): bool {
    for i := 0; i < levels.Length; i++ {
        if levels[i].Price == price {
            levels[i] = Level { Price: price, Quantity: levels[i].Quantity + delta }
            return true
        }
    }
    return false
}
```

### B15 ECS Update (Use Case 15)

```nsharp
namespace SystemsSamples.Basic15

import System
import System.Numerics

[hot]
func Integrate(pos: Span<Vector3>, vel: ReadOnlySpan<Vector3>, dt: float) {
    for i := 0; i < pos.Length; i++ {
        pos[i] = pos[i] + vel[i] * dt
    }
}
```

### B16 Audio DSP (Use Case 16)

```nsharp
namespace SystemsSamples.Basic16

import System

[hot]
func ApplyGain(samples: Span<float>, gain: float) {
    for i := 0; i < samples.Length; i++ {
        samples[i] = samples[i] * gain
    }
}
```

### B17 Image Pixel Transform (Use Case 17)

```nsharp
namespace SystemsSamples.Basic17

import System

struct Rgba {
    R: byte
    G: byte
    B: byte
    A: byte
}

[hot]
func PremultiplyAlpha(pixels: Span<Rgba>) {
    for i := 0; i < pixels.Length; i++ {
        p := pixels[i]
        pixels[i] = Rgba {
            R: (p.R * p.A) / 255,
            G: (p.G * p.A) / 255,
            B: (p.B * p.A) / 255,
            A: p.A
        }
    }
}
```

### B18 RLE Block Codec (Use Case 18)

```nsharp
namespace SystemsSamples.Basic18

import System

enum CodecError {
    NoSpace
}

[hot]
func EncodeRuns(src: ReadOnlySpan<byte>, dst: Span<byte>): Result<int, CodecError> {
    outPos := 0
    i := 0
    while i < src.Length {
        run := 1
        while i + run < src.Length && src[i + run] == src[i] && run < 255 {
            run = run + 1
        }
        if outPos + 2 > dst.Length {
            return Err(CodecError.NoSpace)
        }
        dst[outPos] = run
        dst[outPos + 1] = src[i]
        outPos = outPos + 2
        i = i + run
    }
    return Ok(outPos)
}
```

### B19 Game Network Packet (Use Case 19)

```nsharp
namespace SystemsSamples.Basic19

import System
import System.Buffers

enum PacketError {
    Empty
}

[hot]
func DecodeOpcode(packet: ReadOnlySpan<byte>): Result<byte, PacketError> {
    if packet.Length == 0 {
        return Err(PacketError.Empty)
    }
    return Ok(packet[0])
}

[boundary]
func ReceiveAndDecode(socketBytes: byte[]): Result<byte, PacketError> {
    rented := ArrayPool<byte>.Shared.Rent(socketBytes.Length)
    try {
        socketBytes.CopyTo(rented)
        return DecodeOpcode(rented.AsSpan(0, socketBytes.Length))
    } finally {
        ArrayPool<byte>.Shared.Return(rented)
    }
}
```

### B20 Memory-Mapped Index Search (Use Case 20)

```nsharp
namespace SystemsSamples.Basic20

import System
import System.Buffers.Binary

[hot]
func BinarySearchIndex(indexBytes: ReadOnlySpan<byte>, key: int): Result<int, string> {
    count := indexBytes.Length / 8
    lo := 0
    hi := count - 1
    while lo <= hi {
        mid := lo + ((hi - lo) / 2)
        offset := mid * 8
        found := BinaryPrimitives.ReadInt32LittleEndian(indexBytes.Slice(offset, 4))
        value := BinaryPrimitives.ReadInt32LittleEndian(indexBytes.Slice(offset + 4, 4))
        if found == key { return Ok(value) }
        if found < key { lo = mid + 1 } else { hi = mid - 1 }
    }
    return Err("missing")
}
```

### B21 Precomputed Lookup (Use Case 21)

```nsharp
namespace SystemsSamples.Basic21

static class HexTable {
    static Values: int[] = Build()

    static func Build(): int[] {
        values := alloc new int[256]
        for i := 0; i < values.Length; i++ {
            values[i] = -1
        }
        values[48] = 0
        values[49] = 1
        values[65] = 10
        return values
    }
}

[boundary]
func Warmup() {
    _ = HexTable.Values[0]
}

[hot]
func HexValue(b: byte): int {
    return HexTable.Values[b]
}
```

### B22 Heap-Backed Arena (Use Case 22)

```nsharp
namespace SystemsSamples.Basic22

import System

enum ArenaError {
    Full
}

struct Arena {
    backing: byte[]
    offset: int
}

[boundary]
func NewArena(size: int): Arena {
    return Arena { backing: alloc new byte[size], offset: 0 }
}

[hot]
func Alloc(arena: &Arena, len: int): Result<Span<byte>, ArenaError> returns heap(arena) {
    if len < 0 || arena.offset + len > arena.backing.Length {
        return Err(ArenaError.Full)
    }
    start := arena.offset
    arena.offset = arena.offset + len
    return Ok(arena.backing.AsSpan(start, len))
}
```

### B23 Stackalloc Scratch (Use Case 23)

```nsharp
namespace SystemsSamples.Basic23

import System

[hot]
func ReverseSmall(src: ReadOnlySpan<byte>, dst: Span<byte>): Result<int, string> {
    if src.Length > 64 || dst.Length < src.Length {
        return Err("bad size")
    }

    scratch := stackalloc byte[64]
    for i := 0; i < src.Length; i++ {
        scratch[i] = src[i]
    }
    for i := 0; i < src.Length; i++ {
        dst[i] = scratch[src.Length - 1 - i]
    }
    return Ok(src.Length)
}
```
