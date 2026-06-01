# Systems N# — Adversarial Design Review

Status: adversarial review (v2 — debated)
Reviews: `docs/design/systems-nsharp.md`
Date: 2026-05-31
Posture: hostile. Assume the team is fooling itself until a claim survives.
Method: two adversarial passes. Pass 1 = Claude review of the proposal against the
real compiler. Pass 2 = Codex adversarially attacking Claude's review. This
document is the synthesis; the changes Pass 2 forced are logged in the appendix.

> Grounding (verified in `src/`, not assumed):
> - A real `PerformanceFacts` framework already exists (escape/capture/allocation/
>   dispatch/value-layout/AOT-safety enums). **This proposal is not vapor — it has
>   bones**, and that materially changes the verdict.
> - Unions exist with **dual layout** (class-hierarchy default; value-struct only
>   for ≤16 cases **with no payloads**). **Generic unions do not exist.**
> - AOT is **analysis-only** (`nlc publish --aot` fails on blockers and stamps
>   APIs, but emits **no native image**).
> - There is **no `unsafe` / `stackalloc` / `ref struct` declaration syntax**.
> - There is **no `nlc systems` command**.

---

## 1. Short verdict

**Needs major surgery — strong bones, three unstated lies, and a missing memory
story.**

The core idea — make CLR costs *visible and checkable* through a multi-dimension
effect model, on infrastructure that already exists — is good and genuinely
N#-appropriate. The whole-project profile, the boundary concept, the
memory-safety/trust split, and even a blessed `Result<T,E>` are all defensible.

But three things must change before this ships:

1. **It oversells local properties as system guarantees** in three places, and
   says so nowhere: "`[hot]` cannot throw" (the CLR throws implicitly), "AOT-safe"
   (nothing is AOT-compiled yet), and the implied latency story (zero local alloc
   ≠ no GC pause). Systems engineers catch all three in five minutes.
2. **It has no memory-*creation* story.** With no `stackalloc`, no `ref struct`
   syntax, and no pooling model, `[hot]` can only *consume* caller-provided
   buffers — it cannot make temporaries. That is a real, narrow, *honest* v1, but
   the spec implies Rust/Zig-class capability it does not have.
3. **It funds the wrong thing.** The actual product is a versioned effect-summary
   *system* seeded with a BCL pack so hot code can call `BinaryPrimitives`,
   `MemoryMarshal`, `BitOperations`, `Interlocked`. The spec spends its words on a
   package-IL-prover and a `freeze-effects` lockfile that real hot code can barely
   use, while the summary system that makes `[hot]` usable is a parenthetical.

Fix those and the surviving design is uniquely N# (cost-visible effects + ref
safety + honest boundaries) rather than a Rust/D tribute act. It is not doomed;
it is over-promised and mis-prioritized.

---

## 2. Top 10 ways this fails in the real systems world

1. **Hidden CLR first-use work is the deepest hole — bigger than any source
   construct.** Source-level "no alloc / no throw" is not enough on the CLR. Type
   initializers (`.cctor`), generic-dictionary lookups for shared generics, first
   JIT + tiered recompilation, lazy BCL caches, globalization tables, and runtime
   helper stubs all allocate and/or throw *outside* anything visible in source.
   The proposal's "first-call inclusive" phrase gestures at this but does not
   define a *hot-readiness model*. Without one, a "zero-alloc `[hot]`" still
   allocates on first reach. **This, not array indexing, is the strongest reason
   to be skeptical of the whole promise.**

2. **No stack-memory-creation story → `[hot]` is "compute over caller buffers"
   only.** No `stackalloc` (and it's gated behind a not-yet-existing `unsafe`), no
   `ref struct` declaration syntax, no arena. So a hot function can read/write
   spans handed to it but cannot create scratch memory. That's a coherent v1 — but
   it's *much* narrower than "systems language," and the spec doesn't admit it.

3. **"`[hot]` cannot throw" is underspecified and, as written, implies the
   impossible.** The CLR emits implicit throws on indexing, divide, null-deref,
   and `checked` overflow — yet the spec *allows* `string[i]` and array indexing
   in hot code. As literally written ("rejects throwing") this is contradictory.
   It is salvageable, but only by *choosing* a precise meaning (see §2-resolution
   box below); the doc currently chooses none.

4. **No BCL primitive catalog = `[hot]` cannot call the functions hot code is made
   of.** `BinaryPrimitives.ReadUInt32LittleEndian`, `MemoryMarshal.Cast`,
   `Unsafe.Add`, `BitOperations.PopCount`, `Vector256.LoadUnsafe` are JIT
   intrinsics lowered to one instruction, but their IL is **not** `ldarg.0; ldfld;
   ret`. The "tiny IL-proven whitelist" rejects every one. A packet parser, codec,
   or UTF-8 reader that can't call `BinaryPrimitives` is a toy.

5. **No pooling story.** `ArrayPool<T>.Rent/Return` and `MemoryPool<T>` are how
   .NET avoids GC. `Rent` returns a *reused* array — not an allocation — but the
   analysis sees an unknown call returning a heap array and flags it. There is no
   way to say "pooled, not allocated," and the pool's own warmup can allocate on
   first use (ties back to §2.1).

6. **No GC-pause story, so the latency pitch is local-only.** Zero allocation in a
   `[hot]` frame prevents *self-induced* collection pressure; it does not stop
   another thread's allocation from triggering a stop-the-world GC. D's `@nogc`
   docs make exactly this distinction. "Zero alloc here" is true and useful; "low
   latency" is a *system* property the spec hasn't earned.

7. **No concurrency/atomics, while targeting concurrent domains.** Order books,
   ECS, ring buffers, and high-throughput services need `Interlocked`, `Volatile`,
   memory barriers, and a memory-ordering story. Thread-safety effects are
   deferred *and* `Interlocked`/`Volatile` aren't even hot-callable. You cannot
   write a lock-free ring buffer in `[hot]` as specified.

8. **Effect inference over generics is real and unaddressed in the spec.** `Foo<T>`'s
   effects depend on `T` (does `T`'s ctor allocate? does `IComparer<T>.Compare`
   dispatch virtually?). Summaries must be *conditional on constraints and called
   members*, not per-method. The `PerformanceFacts` framework makes this tractable
   — but the proposal never commits to parametric summaries, and without them
   inference is either unsound or uselessly conservative for generic hot code.

9. **Effect-fact drift is spooky-action-at-a-distance.** A one-line change in a
   leaf helper can flip an inferred allocation fact and break a `[hot]` caller
   three files away. The lockfile catches *that* it changed; the experience is
   only acceptable if CI emits a *precise per-fact diff* ("`Parse` gained
   allocation via `Helper.Format`"), which the spec does not promise.

10. **Systems culture is measure-first; this ships analysis-only.** The benchmark/
    probe harness is *cut from v1*. Telling a latency engineer "trust our static
    allocation analysis" without a way to verify at runtime inverts the audience's
    value system. The cut probe harness is the one deferral worth reconsidering.

> **Resolution box — what "`[hot]` cannot throw" must be redefined as.** Two viable
> meanings; pick one and write it down:
> (a) **No exception escapes the frame** — explicit `throw` and throwing-summarized
>     calls are banned; implicit checks (bounds/null/overflow) are *out of scope*
>     and documented as such. Honest, weak, shippable.
> (b) **Proof-obligation indexing** — indexing is allowed only when receiver
>     non-null, index in range, and arithmetic non-overflow are *proven*; otherwise
>     a diagnostic. Stronger, more work, genuinely differentiating.
> What is *not* acceptable is the current implied meaning ("no throw-capable IL"),
> which forbids array indexing the spec simultaneously allows.

---

## 3. Top 10 ways this fails in the .NET ecosystem

1. **AOT is the milestone gate but doesn't emit images yet, and "AOT-safe" is
   ambiguous.** `aotSafe` should be *target-qualified* — `aotSafe(nativeaot)`,
   `aotSafe(coreclr)`, `trimSafe` — because reflection/trimming/codegen rules
   differ across NativeAOT, CoreCLR, Mono/WASM. A single "AOT pass" badge over an
   analysis-only pipeline reads as marketing.

2. **`value union` C# interop is unspecified — and it's the blessed type.** How
   does a C# caller consume `Result<T,E>`? As a struct with a tag enum and
   `TryGetOk`? The interop story frays exactly at the type every API returns.

3. **Source generators are the AOT-correct interop path and aren't addressed.**
   `System.Text.Json` source-gen, `LibraryImport`, `[GeneratedRegex]` are how you
   do AOT-safe JSON/interop. A NativeAOT CLI that parses JSON args needs them, yet
   `[boundary]` never mentions source-gen.

4. **Effect facts are a TFM × RID × version matrix.** Multi-targeted packages ship
   different IL per TFM and behave differently per runtime; the resolved transitive
   graph differs per RID. `audit-package --target-framework --runtime` acknowledges
   one axis; the combinatorial caching/identity story is hand-waved. The summary
   key must include {assembly identity, TFM, RID assumptions, body hash/MVID}.

5. **`stackalloc` gated behind `unsafe` is *more* restrictive than C#.** Modern C#
   writes `Span<byte> b = stackalloc byte[256];` with no `unsafe`. Forcing it into
   `unsafe {}` reads as N# being behind C#, not ahead — and it's the only
   in-language way to make a hot temporary (§2.2).

6. **Interface dispatch ban rejects patterns the JIT devirtualizes.** Constrained
   generic calls on value types (the spec's `ConstrainedValueType` kind — good)
   are fine, but PGO/guarded devirtualization often removes interface dispatch on
   reference types too. A blanket ban is cruder than the runtime.

7. **No `IAsyncDisposable`/`ValueTask` story for the IO boundary.** Systems IO is
   increasingly async, yet "file IO boundary feeding a hot parser" is an explicit
   target and there is no async story anywhere.

8. **`alloc new` must not change the runtime meaning of `new` by profile.** It is
   fine for `profile: systems` to make plain heap-allocating `new` a *diagnostic*
   (with a fix-it to `alloc new` or to a `[boundary]`). It is *not* fine for the
   same source to mean different things; `alloc new` should be **always legal,
   everywhere**, meaning "intentional heap allocation," so code is portable across
   profiles. (See §6 — this is a refinement, not a cut.)

9. **Blessing ZLinq couples the compiler to a third party's cadence.** Pinning
   versions and gating hot-acceptance on exact operator chains means one breaking
   ZLinq release strands users. Bless a *contract* ("hot-compatible LINQ profile"),
   not a package; let ZLinq qualify by satisfying the profile.

10. **`Dictionary`/BCL collections silently fail hot rules.** Indexer-set can
    resize (allocate); indexer-get throws `KeyNotFound`. The spec gives no
    capacity/preallocation guidance, so the obvious BCL collection is just rejected
    with no suggested path.

---

## 4. Top 10 ways this corrupts N# simplicity/purity

1. **The annotation budget is Rust-sized.** `[hot]`, `[boundary]`, `[alloc(none)]`,
   `[memory(safe)]`, `[trusted]`, `[allow(dispatch:…)]`, `[allow(aot:…)]`, plus
   `alloc`, `alloc {}`, `allow(){}`, `scoped`, `value union`, `unsafe`. Go has
   none of these. A reader of systems libraries must learn all of them.

2. **`value union` vs `union` is a second union concept** with different ABI,
   payload rules, and hot-eligibility — a representation-aware split that leaks
   into public API design.

3. **Two mechanisms for one concept (allocation):** `new` needs `alloc`, but a
   factory like `ImmutableArray.Create()` that also allocates is *not* markable —
   it's handled by call analysis instead. Inconsistent mental model.

4. **Mandatory `reason:` strings become ceremony.** You will get `reason: "needed"`
   everywhere. Rust's `unsafe` and clippy's `#[allow]` don't demand prose.

5. **The `[hot]` × `[memory(safe)]` × `[boundary]` × strict/audit matrix** is a
   combinatorial "which rules apply here?" space. Each axis is defensible alone;
   together they're heavy.

6. **`allow(...)` is `unsafe`-with-extra-steps, once per effect dimension.**
   Cognitive load scales with the number of effect dimensions.

7. **"First-call inclusive" is muddy** (static vs temporal) and now must be
   replaced by an explicit hot-readiness model (§2.1) — muddy core concepts are
   the opposite of tight.

8. **The CLI grows a whole `nlc systems …` sub-world** plus templates and flags —
   permanent surface the "reliable as Go/Rust" CLI promise must keep stable.

9. **`[trusted]` rots without governance.** A reason string is not enough. Without
   owner metadata, small-body linting, review/expiry dates, and a `nlc query
   trusted` report, it becomes the escape hatch everyone reaches for. (D's docs
   explicitly warn to keep `@trusted` bodies tiny.)

10. **Profile-conditional language semantics are the single sharpest purity risk.**
    If `profile: systems` ever changes what valid source *means* (not just which
    diagnostics fire), N# stops being one language. The profile must be a *policy*,
    never a dialect. (See §6.)

---

## 5. Twelve+ stress examples (pseudo-N#, need not compile)

### Ex 1 — Packet parser over a span (headline use case)
```nsharp
[hot]
func ParseHeader(buf: ReadOnlySpan<byte>): Result<Header, ParseError> {
    if buf.Length < 8 { return Err(ParseError.Short) }
    version := BinaryPrimitives.ReadUInt16LittleEndian(buf)
    length  := BinaryPrimitives.ReadUInt32LittleEndian(buf[2..])
    return Ok(Header { version, length })
}
```
**POORLY.** `BinaryPrimitives.*` is not on the trivial IL whitelist → flagged as
unknown external calls. The flagship example fails its own rules unless the
effect-summary system ships a BCL pack covering these.

### Ex 2 — Binary codec writing to a span
```nsharp
[hot]
func WriteFrame(dst: Span<byte>, f: Frame): Result<int, EncodeError> {
    if dst.Length < f.Size { return Err(EncodeError.NoSpace) }
    dst[0] = f.Tag                  // indexer: implicit IndexOutOfRange
    BinaryPrimitives.WriteUInt32LittleEndian(dst[1..], f.Len)
    return Ok(f.Size)
}
```
**POORLY/UNDERSPECIFIED.** `dst[0]=…` can throw — collides with no-throw *as
written*. Under resolution (a) it's fine (implicit checks out of scope); under (b)
it needs the preceding length check to discharge the bounds obligation. The spec
picks neither, so the example's legality is undefined.

### Ex 3 — Lock-free SPSC ring buffer
```nsharp
[hot]
func TryEnqueue(self: &RingBuffer, item: int): bool {
    head := Volatile.Read(self.head)
    if head - Volatile.Read(self.tail) >= self.cap { return false }
    self.slots[head & self.mask] = item
    Volatile.Write(self.head, head + 1)             // release
    return true
}
```
**POORLY.** No concurrency effects; `Volatile`/`Interlocked` not hot-callable. The
most iconic systems structure can't be written. (Trivially fixable by adding a
concurrency intrinsic pack — see §7.)

### Ex 4 — Arena / bump allocator
```nsharp
func MakeArena(bytes: int): Arena {
    allow(alloc, reason: "single backing buffer for arena lifetime") {
        return Arena { backing: alloc new byte[bytes], offset: 0 }
    }
}
[hot]
func Alloc(self: &Arena, n: int): Span<byte> {
    s := self.backing.AsSpan(self.offset, n)        // span into heap array
    self.offset += n
    return s                                         // escapes the call
}
```
**AMBIGUOUS.** The "one allowed allocation" pattern is expressible (good), but
`Alloc` returns a span into a *heap* array — legal on CLR — while the spec's "spans
are automatically local-only" rule is too blunt to distinguish that from a span
into stack memory. Return-lifetime rules are exactly the unsolved part.

### Ex 5 — Zero-copy length-prefixed frame reader (ref struct)
```nsharp
ref struct FrameReader { buf: ReadOnlySpan<byte>; pos: int }
[hot]
func Next(self: &FrameReader): Result<ReadOnlySpan<byte>, ParseError> {
    if self.pos + 4 > self.buf.Length { return Err(ParseError.Eof) }
    len := BinaryPrimitives.ReadInt32LittleEndian(self.buf[self.pos..])
    self.pos += 4
    frame := self.buf.Slice(self.pos, len)
    self.pos += len
    return Ok(frame)
}
```
**POORLY (today).** No `ref struct` declaration syntax exists; the returned span
borrows the input span and needs *return-lifetime* tracking the spec gestures at
but doesn't define; and the BCL-intrinsic problem recurs.

### Ex 6 — Logging hot path
```nsharp
[hot]
func LogTrade(price: long, qty: int) {
    if !log.Enabled(Level.Debug) { return }
    allow(alloc, reason: "diagnostic path only, gated by level") {
        log.Debug(alloc $"trade px={price} qty={qty}")
    }
}
```
**WELL (the design at its best).** `alloc $"..."` makes the interpolation cost
visible and scopes it to the cold, gated path. Caveat: bless the cached
`LoggerMessage.Define` delegate pattern too.

### Ex 7 — UTF-8 / JSON parser
```nsharp
[hot]
func ParseValue(reader: &Utf8JsonReader): Result<JsonValue, JsonError> {
    if !reader.Read() { return Err(JsonError.Eof) }   // complex IL, can throw
    match reader.TokenType { ... }
}
```
**POORLY.** `Utf8JsonReader.Read()` is non-trivial IL and throws on malformed
input — fails both whitelist and no-throw. A JSON parser (explicit target) can't
sit in `[hot]` without wrapping the whole reader in `allow`, defeating the point.

### Ex 8 — Order book update loop
```nsharp
[hot]
func ApplyUpdate(book: &OrderBook, u: Update): Result<unit, BookError> {
    level := book.bids.GetValueOrDefault(u.price)   // hashing; maybe resize
    book.bids[u.price] = level + u.qty              // set: may allocate on resize
    return Ok(unit)
}
```
**POORLY.** `Dictionary` set can resize (allocate) and get can throw. No
preallocation/capacity story; the obvious BCL collection is silently rejected.

### Ex 9 — Game ECS system update
```nsharp
[hot]
func IntegratePositions(pos: Span<Vector3>, vel: ReadOnlySpan<Vector3>, dt: float) {
    for i in 0..pos.Length { pos[i] = pos[i] + vel[i] * dt }
}
```
**AMBIGUOUS→WELL.** Tight span loop over unmanaged structs is the sweet spot *if*
`Vector3` operators are in the summary pack. Parallelism and SoA are out of scope.
Single-thread case is the strongest realistic example.

### Ex 10 — Native interop wrapper
```nsharp
[boundary]
func OpenDevice(path: string): Result<DeviceHandle, IoError> {
    h := NativeMethods.open(path, O_RDWR)   // LibraryImport source-gen; marshals string (alloc)
    if h < 0 { return Err(IoError.FromErrno(Marshal.GetLastPInvokeError())) }
    return Ok(DeviceHandle { fd: h })
}
```
**WELL.** Marshalling cost + errno translation belong at a reporting boundary that
yields a `Result`. Open Q: require `LibraryImport` (AOT-safe) over `DllImport`?

### Ex 11 — File IO feeding a hot parser via pooled buffer
```nsharp
[boundary]
func ReadAndParse(stream: Stream): Result<Records, IoError> {
    buf := ArrayPool<byte>.Shared.Rent(64 * 1024)   // pooled, NOT allocation
    using defer { ArrayPool<byte>.Shared.Return(buf) }
    n := stream.Read(buf)
    return ParseRecords(buf.AsSpan(0, n))
}
```
**POORLY (pooling gap + no `defer`).** `Rent` reads as allocation; no rent/return
modeling; `defer` is cut so return-on-exit needs `try/finally` the spec doesn't
address. The single most common real .NET IO pattern.

### Ex 12 — Safe wrapper over unsafe memcpy
```nsharp
[memory(safe)]
[trusted(reason: "len <= min(dst,src) lengths checked above", owner: "core", review: "2026-12")]
func CopyExact(dst: Span<byte>, src: ReadOnlySpan<byte>, len: int) {
    if len > dst.Length || len > src.Length { return }
    unsafe { Buffer.MemoryCopy(src.ptr, dst.ptr, dst.Length, len) }
}
```
**WELL — the design's clearest win.** Separating memory-safety (`[trusted]` +
reason) from performance facts is exactly right. Add governance metadata
(owner/review) so `[trusted]` is an auditable artifact, not a comment.

### Ex 13 — ZLinq value pipeline
```nsharp
[hot]
func SumPositive(xs: ReadOnlySpan<int>): long {
    return xs.AsValueEnumerable().Where(x => x > 0).Select(x => (long)x).Sum()
}
```
**AMBIGUOUS.** `x => x > 0` is a closure — banned in `[hot]` unless the blessed
summary proves the chain fully inlines. Brittle per-operator/per-version. Bless a
*hot-LINQ contract* that ZLinq qualifies for, not ZLinq by name.

### Ex 14 — NativeAOT CLI tool
```nsharp
func Main(args: string[]): int {
    opts := ParseArgs(args)
    json := JsonSerializer.Serialize(opts, MyCtx.Default)  // source-gen, AOT-safe
    Console.Out.Write(json)
    return 0
}
```
**AMBIGUOUS (blocked on real AOT).** Plausible *if* `nlc publish --aot` emits a
native image (it doesn't) and source-gen JSON is recognized as AOT-safe
(unaddressed). Today it would only stamp APIs.

### Ex 15 — Package boundary adapter (Dapper/EF)
```nsharp
[boundary]
func LoadUsers(db: IDbConnection): Result<List<User>, DbError> {
    rows := db.Query<User>("select * from users")   // reflection, alloc, dynamic
    return Ok(rows.ToList())
}
```
**WELL.** Exactly the quarantine `[boundary]` exists for: reflection-heavy ORM in,
`Result` of plain values out, costs reported.

**Scorecard:** Strong: 4 (Ex6, 10, 12, 15). Ambiguous: 4 (Ex4, 9, 13, 14).
Poorly: 7 (Ex1, 2, 3, 5, 7, 8, 11). The *boundary* and *trusted-memory* ideas win
consistently; the `[hot]` alloc/no-throw/BCL/memory-creation core loses to CLR
reality until the summary pack, atomics, and a memory story land.

---

## 6. Features to cut / re-scope for v1

1. **Cut: package IL-proof audit over the transitive NuGet graph.** `trustedUser`/
   `ilProven` across all deps is a research project. v1 = a versioned **effect-
   summary system** seeded with a curated **BCL pack** + your-own-source inference
   + opt-in sidecar summaries. Nothing else.
2. **Cut: effect lockfile (`freeze-effects`/`--locked-effects`) from v1.** Premature
   until someone has a regression worth locking. Ship inference + *precise per-fact
   diffs* in `nlc check` first.
3. **Cut: general generic `value union` with arbitrary reference payloads.** Keep a
   **compiler-known allocation-free `Result<T,E>`** as a generic `readonly struct
   {tag, ok, err}` (works for reference *and* value payloads — no field overlap
   needed), with: inactive-field clearing, a `must-use` rule, and a **size
   diagnostic** for large `T`/`E` (the by-value copy cost). Defer space-optimized
   arbitrary unions.
4. **Cut: ZLinq-by-name from the spec.** Ship a *hot-LINQ contract*; ZLinq qualifies
   by satisfying it.
5. **Cut: `allow(aot: blocked)` bookkeeping** until native-image emission exists.
   Until then, report `aotSafe(target)` facts only.
6. **Re-scope (do NOT cut): the whole-project `profile: systems` lane.** *Keep it*
   — default-deny + transitive signaling is genuinely valuable and has precedent
   (`#![no_std]`, `#![deny(unsafe_code)]`, `-betterC`, C++ freestanding). **But it
   must be a policy, never a dialect:** it changes which *diagnostics* fire, never
   what valid source *means*.
7. **Re-scope (do NOT cut): `alloc new`.** Keep it, and make it **always legal
   everywhere**, meaning "intentional heap allocation." Systems profile turns plain
   heap-allocating `new` into a diagnostic with a fix-it. `new`'s runtime meaning
   never changes by profile → copy-paste/codegen portability preserved.
8. **Re-scope: `[memory(safe)]`/`[trusted]`.** Keep the concept (clearest win), add
   **governance** (owner, review/expiry, small-body lint, `nlc query trusted`).
   Defer making `[memory(safe)]` a fully enforced second lane.

---

## 7. Missing features real systems engineers expect

1. **A hot-readiness model** for hidden first-use work: no `.cctor` on the hot path
   unless proven already-run or trivial; defined behavior under tiered JIT /
   ReadyToRun / NativeAOT; report runtime obligations in `nlc query`. *(The single
   most important addition.)*
2. **A versioned effect-summary system** (HotSummary): `{assembly identity, TFM, RID
   assumptions, signature, body hash/MVID} → effects + preconditions`. BCL pack as
   bootstrap data, not language spec. Covers `BinaryPrimitives`, `MemoryMarshal`,
   `Unsafe`, `BitOperations`, `Math`, `System.Numerics`, span slice/index. *Without
   this `[hot]` is unusable.*
3. **A concurrency intrinsic pack** — `Volatile.Read/Write`, `Interlocked.*`,
   barriers, with explicit acquire/release/seq-cst semantics. No new syntax needed;
   just include them in the external-call policy.
4. **A memory-creation story** — `stackalloc` without `unsafe`; a safe arena/owned-
   span model; or an explicit v1 scope statement of "hot compute over caller-
   provided buffers only."
5. **A pooling model** — recognize `ArrayPool`/`MemoryPool` Rent/Return as
   non-allocating (with warmup caveat), plus a rent/return-balance lint.
6. **Honest GC framing** — market `[hot]` as "no self-induced allocation/collection
   pressure," and add `NoGCRegion`/pinning/LOH guidance for the system level.
7. **Measurement integration** — a profiler/benchmark hook; reconsider the cut probe
   harness. A "zero-alloc" badge the user can't verify won't be trusted.
8. **Codegen visibility** — `AggressiveInlining` control and a "show me the IL/asm"
   path. Systems engineers want to see generated code.
9. **`ref struct` / `ref field` declaration syntax + return-lifetime rules** — needed
   for Ex3/Ex5.
10. **Source-generator interop** — `System.Text.Json` source-gen, `LibraryImport`,
    `[GeneratedRegex]` recognized as the AOT-safe paths.
11. **`value union` → C# ABI definition** — how consumers see `Result<T,E>`.

---

## 8. Proposed tighter v1 spec

**Theme: ship the honest core; keep the policy lane; fund the summary system; admit
the memory scope.**

1. **Keep the lane as policy.** `profile: systems` = default-deny + transitive
   signaling, changing diagnostics only, never source meaning. Local `[hot]` /
   `[alloc(none)]` available everywhere prove islands inside non-systems projects.

2. **Redefine `[hot]` honestly.** Forbids: explicit allocation forms, boxing,
   delegate/closure *creation*, virtual/interface dispatch on reference types,
   reflection, dynamic code, *explicit* `throw`, and calls *summarized as*
   allocating/throwing/dispatching. **Choose a no-throw meaning** (§2 box) and
   document that implicit CLR checks are out of scope (or proof-obligated). **Add
   the hot-readiness model** in place of vague "first-call inclusive."

3. **The headline deliverable is the effect-summary system + BCL pack** (§7.2).
   This is the moat and the credibility.

4. **`alloc new` always legal**; systems profile makes plain heap `new` a
   diagnostic with a fix-it. No language-wide change to `new`'s meaning.

5. **Span/ref safety: ship it.** Add `ref struct`/`ref field` syntax + `scoped`
   with explicit *return-lifetime* rules (covers arenas/readers). The genuinely
   N#-coherent core.

6. **Memory + concurrency:** `stackalloc` without `unsafe`; pooling recognized;
   concurrency intrinsic pack hot-callable. Defer broad thread-safety effects.

7. **`Result<T,E>` as a compiler-known allocation-free generic struct** (ref + value
   payloads), with inactive-field clearing, must-use, size diagnostic, and a defined
   C# ABI. Defer general generic value unions.

8. **`[boundary]` = simple report-only adapter.** Keep the concept; drop AOT-allow
   bookkeeping until native images emit. Require `LibraryImport` over `DllImport`.

9. **Keep `unsafe {}` + escape analysis + `[trusted(reason, owner, review)]`** for
   safe-wrapper patterns, with governance. Defer `[memory(safe)]` as a full lane.

10. **AOT: be honest.** Ship target-qualified `aotSafe(...)` analysis (already real),
    labeled as analysis. The native-image milestone remains the gate to calling N#
    a systems language — keep that gate.

11. **Add a measurement hook** (or don't market "zero alloc" without runtime
    verification).

12. **Cut** the package IL-proof audit, the effect lockfile, ZLinq-by-name, and
    general generic value unions from v1.

Net: roughly half the surface, none of the unstated lies, a real memory/concurrency
story, and the survivors are the *uniquely N#* parts.

---

## 9. Unresolved questions the team must answer first

1. **What does "`[hot]` cannot throw" mean?** Pick (a) no-escape or (b)
   proof-obligation indexing — the doc currently implies the impossible third
   option.
2. **What is the hot-readiness model** for `.cctor`/JIT/lazy-cache first-use work?
   (Likely the hardest and most important question.)
3. **What is the effect-summary key and ABI**, and how is the BCL pack versioned
   against runtime/JIT updates? Are N# 1.0 summaries valid for N# 1.1?
4. **How are generic effects expressed** — conditional-on-constraints summaries? How
   does that compose with the `Reflection.Emit` IL backend's monomorphization?
5. **How is pooling modeled** — is `Rent` allocation? What proves rent/return
   balance, and how is pool warmup handled vs hot-readiness?
6. **Is `[hot]` zero-alloc local or system**, and will docs say so honestly?
7. **How does a C# consumer see a `value union` / `Result<T,E>`?** Concrete ABI.
8. **Concurrency:** is *any* lock-free structure writable in `[hot]` in v1? If not,
   say so loudly.
9. **Memory creation:** does v1 include `stackalloc`-without-unsafe and `ref struct`
   syntax, or is v1 explicitly "compute over caller buffers only"?
10. **Async IO boundary:** `IAsyncDisposable`/`ValueTask` story for the file-IO →
    hot-parser scenario.
11. **Governance for `[trusted]`** — owner/review/expiry/lint, or does it rot?
12. **Named acceptance gauntlet.** This review nominates **Ex1 (packet parser),
    Ex3 (ring buffer), Ex5 (frame reader), Ex8 (order book), Ex11 (pooled IO),
    Ex12 (safe memcpy)** as must-pass. If v1 can't do a packet parser, a ring
    buffer, and pooled IO, it is not yet a systems language.

---

## Appendix — debate log (what Pass 2 changed)

Pass 2 (Codex adversarially attacking Pass 1) forced these revisions; recording them
so the reasoning is auditable:

- **No-throw "contradiction" → "underspecification."** Codex was right that the
  contradiction only holds under the "no throw-capable IL" reading. Reframed to
  demand the team *pick* a precise meaning, and supplied the two viable ones
  (no-escape / proof-obligation). The finding survives, sharpened.
- **Cutting the whole-project lane → keep it as policy.** Codex cited `#![no_std]`,
  `#![deny(unsafe_code)]`, `-betterC`, and C++ freestanding. Pass 1's "cut the lane"
  was wrong; the real fix is "policy, not dialect" + "`alloc new` always legal."
- **Cutting `Result<T,E>` → keep it.** Codex showed a generic `readonly struct
  {tag, ok, err}` is allocation-free and fine for reference payloads (no overlap
  needed). Pass 1 conflated this with general generic unions. Only the *general*
  feature is cut; `Result<T,E>` stays with size diagnostics.
- **"BCL catalog is the product" → "effect-summary *system* with a BCL seed pack."**
  Codex's HotSummary framing (extensible sidecars) is more scalable than a static
  hand-maintained list.
- **"Effects+generics unaddressed from scratch" → softened.** `PerformanceFacts`
  exists; reframed as "needs conditional/parametric summaries — commit to them."
- **Added (Pass 1 missed entirely):** hidden CLR first-use work / hot-readiness
  model (now the #1 systems critique); the no-memory-creation scope problem;
  `[trusted]` governance; target-qualified `aotSafe`.

Points where both reviewers converged with no change needed: the BCL-whitelist
gap, the GC-pause/latency overselling, mandatory atomics, no pooling story, and the
Rust-sized annotation budget threatening purity.
