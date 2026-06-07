---
sidebar_label: Systems N#
title: Systems N#
---

# Systems N#

Systems N# is an opt-in **performance lane** of the language for writing CLR code with
explicit, checkable runtime costs. It is the same N# you already know — the same syntax,
the same C# interop — with a stricter analyzer and a few extra constructs that make
allocation, dispatch, lifetimes, and memory safety *visible* instead of implicit.

The promise is deliberately not "Rust on the CLR." The promise is that N# makes CLR costs
**visible, checkable, and explainable**: allocation, boxing, virtual dispatch, closure and
delegate construction, reflection, dynamic code, throwing, AOT/trimming hazards, lifetime
and ref escape, resource ownership, memory safety, and hidden first-use work. When you
opt a function into the hot path, the compiler holds you to that contract and tells you —
in plain language — the moment the cost model is violated.

> **Status:** Systems N# is an enforced, tested lane today (the full `NSYS###` effect
> family, `Result<T,E>`, `ref struct`/lifetime checks, `stackalloc`, `[trusted]`
> governance, and SIMD auto-vectorization all ship and are covered by tests). A few items
> are analysis-only or deferred — they are called out explicitly below. The canonical
> design spec is [`docs/design/systems-nsharp.md`](https://github.com/schneidenbach/nsharplang/blob/main/docs/design/systems-nsharp.md); measured
> cross-language numbers live in
> [`docs/design/systems-vs-native.md`](https://github.com/schneidenbach/nsharplang/blob/main/docs/design/systems-vs-native.md).

---

## Turning on the systems profile

Systems N# is a **project profile**, not a separate dialect. Scaffold a systems project, or
add the profile to an existing one:

```bash
# Dedicated systems templates
nlc new systems-cli PacketTool
nlc new systems-lib PacketCore

# Or add the systems profile to a standard template
nlc new PacketTool --template console --systems
nlc new PacketCore --template library --systems
```

The systems templates set the profile in `project.yml`:

```yaml
name: PacketTool
entry: Program.nl
outputType: exe
targetFramework: net10.0
language:
  profile: systems          # turns on the strict effect analyzer
  systems:
    mode: strict            # effect violations are build-blocking errors
    aotTarget: nativeaot    # target-qualifies AOT/trim facts (nativeaot | coreclr | mono-wasm)
    stackBudgetBytes: 4096  # ceiling for stackalloc in this project
```

Under the systems profile, the analyzer is **strict**: effect violations in `[hot]` code are
build-blocking errors, not advisories. Code outside `[hot]`/`[boundary]` still compiles
exactly as ordinary N#.

Inspect the cost model from the CLI:

```bash
nlc check --systems-report          # versioned JSON of every effect site
nlc build --perf-report             # allocation/dispatch/boxing/pool/trusted/AOT report
nlc query perf --file Program.nl --pos 12:8   # explain the cost facts at a position
nlc query trusted                   # list governed [trusted] wrappers
```

---

## Effect attributes

Three attributes describe where a function sits in the cost model:

| Attribute | Meaning |
|-----------|---------|
| `[hot]` | Steady-state hot path. No allocation, boxing, closures/delegates, virtual dispatch, reflection, or throwing unless explicitly allowed. The strictest contract. |
| `[boundary]` | The seam between cold setup and hot code. May allocate and rent pools; the place where you warm caches and hand buffers to `[hot]` callees. |
| *(default)* | Cold code. Ordinary N#; no extra obligations. |

```n#
[hot]
func ReadTaggedByte(bytes: ReadOnlySpan<byte>): Result<byte, ParseError> {
    // every cost in here is checked: no hidden allocation, no boxing, no throw
    if bytes.Length < 2 {
        return Err(new ParseError { Kind: ParseKind.Short, Offset: bytes.Length })
    }
    return Ok(bytes[1])
}
```

When a `[hot]` function calls a cold callee that allocates, the analyzer follows the call
path and reports the violation at the call site, naming the full chain
(`ParseFrame -> DecodePayload -> FormatError`). Cost does not hide behind a function
boundary.

### The `NSYS` cost model

Each kind of hidden cost has its own diagnostic so the message tells you exactly what the
hot path did wrong:

| Code | Caught |
|------|--------|
| `NSYS010` | Heap allocation in `[hot]` (includes `[hot] async`/iterators) |
| `NSYS020` | Boxing a value type |
| `NSYS030` | Closure or delegate construction |
| `NSYS040` | Virtual/interface dispatch that wasn't devirtualized |
| `NSYS050` | Call into an external method with no known cost summary |
| `NSYS060` | AOT/trimming blocker |
| `NSYS070` | A value escaping a `[boundary]` that shouldn't |
| `NSYS080` | Lifetime / ref escape (e.g. returning a `stackalloc` span) |
| `NSYS090` | Resource left undisposed |
| `NSYS100` | Memory-safety violation / ungoverned `unsafe` |
| `NSYS110` | Hot-readiness (`.cctor`, lazy init, JIT/tiering warmup) |
| `NSYS120` | An implicit trap / throw in a no-throw `[hot]` function |
| `NSYS130` | Pool rent/return imbalance |
| `NSYS140` | A concurrency primitive with no memory-ordering summary |
| `NSYS150` | Effect drift — a callee gained a cost a hot caller relied on it not having |
| `NSYS160` | A must-use `Result<T,E>` discarded |
| `NSYS170` | A `Result<T,E>` return value's copy shape exceeds the hot-path size guidance |
| `NSYS180` | Effect policy — a function-level `[allow]` is missing a required `reason`/`owner` |

When a cost is intentional, waive it locally with an `allow(...)` statement that records the
reason and owner — the waiver is part of the source, reviewable in code review:

```n#
allow(alloc, reason: "one-time warmup buffer", owner: "runtime-core")
```

---

## `Result<T,E>` — allocation-free structured errors

Systems code can't pay the cost of exceptions on the success path, so Systems N# ships a
compiler-known, allocation-free `Result<T,E>` (a `readonly struct` with a tag byte and
ok/err payloads). Construct with `Ok(...)`/`Err(...)`; branch with `IsOk`/`IsErr`; read the
payload with `OkValueUnchecked`/`ErrValueUnchecked` after you've checked the tag.

```n#
enum ParseKind { Short, BadTag }

struct ParseError {
    Kind: ParseKind
    Offset: int
}

[hot]
func ReadTaggedByte(bytes: ReadOnlySpan<byte>): Result<byte, ParseError> {
    if bytes.Length < 2 {
        return Err(new ParseError { Kind: ParseKind.Short, Offset: bytes.Length })
    }
    if bytes[0] != 42 {
        return Err(new ParseError { Kind: ParseKind.BadTag, Offset: 0 })
    }
    return Ok(bytes[1])
}

func Main(): int {
    okInput := alloc new byte[2]
    okInput[0] = (byte)42
    okInput[1] = (byte)99
    result := ReadTaggedByte(okInput)
    if result.IsOk == false {
        return 1
    }
    return (int)result.OkValueUnchecked   // 99
}
```

A `Result<T,E>` is **must-use**: dropping one as a bare statement is `NSYS160`. Explicitly
discard with `_ =` when you really mean to ignore it. The whole success path is exception-
free and allocation-free; a CLR exception is only ever paid if you choose to convert an
`Err` into a throw.

> Only `Result<T,E>` is a compiler-known value union today. General arbitrary
> `value union` types are **deferred** from this version.

---

## Explicit allocation: `alloc` and `stackalloc`

In systems code, heap allocation is something you say out loud. The `alloc` keyword marks
an allocation site so it's greppable and reviewable, and `stackalloc` gives you a stack
buffer as a `Span<T>` **without** an `unsafe` block.

```n#
// alloc marks the heap allocation explicitly
input := alloc new byte[7]

// stackalloc gives a Span<byte> on the stack — no unsafe needed
scratch := stackalloc byte[64]
```

`stackalloc` length is bounded by `language.systems.stackBudgetBytes` (default 4096); going
over budget is `NSYS080`. A stack span has `local` lifetime and cannot escape its frame —
returning one is a compile error, not a dangling pointer.

---

## Spans, `ref struct`, and lifetimes

Zero-copy parsing leans on `ref struct` types and spans. Systems N# checks the lifetime
rules at compile time: ref-like fields are only allowed in a `ref struct`, by-ref
parameters use `&T`, and you can annotate parameter and return lifetimes with `scoped` and
`returns 'a`.

```n#
ref struct FrameReader {
    buf: ReadOnlySpan<byte>
    pos: int

    constructor(input: ReadOnlySpan<byte>) {
        buf = input
        pos = 0
    }
}

ref struct FrameResult {
    ok: bool
    frame: ReadOnlySpan<byte>
    error: FrameError
}

// 'a ties the returned frame's lifetime to the reader's buffer
[hot]
func NextFrame<'a>(reader: &FrameReader scoped 'a): FrameResult returns 'a {
    if reader.pos + 4 > reader.buf.Length {
        return new FrameResult { ok: false, frame: reader.buf.Slice(reader.pos, 0), error: FrameError.Eof }
    }

    len := BinaryPrimitives.ReadInt32LittleEndian(reader.buf.Slice(reader.pos, 4))
    reader.pos = reader.pos + 4

    if len < 0 || reader.pos + len > reader.buf.Length {
        return new FrameResult { ok: false, frame: reader.buf.Slice(reader.pos, 0), error: FrameError.Truncated }
    }

    frame := reader.buf.Slice(reader.pos, len)
    reader.pos = reader.pos + len
    return new FrameResult { ok: true, frame: frame, error: FrameError.Eof }
}
```

Call a `&T` parameter with `ref`:

```n#
reader := new FrameReader(input)
frame := NextFrame(ref reader)
```

The compiler returns a **return-lifetime fact** for each function (`local`, `param`,
`heap(owner)`, `static`, or `unknown`). Returning an `unknown` lifetime into a `[hot]`
caller is rejected. This is a CLR ref-safety model focused on the v1 escape shapes — it
catches stack/span escapes; it is **not** a Rust borrow checker (move/affine ownership is
deferred).

---

## Restricted `unsafe` and `[trusted]` governance

`unsafe { }` blocks work in any project. In *systems* code, an `unsafe` block must live
inside a function that is both marked `[memory(safe)]` (you assert the public behavior is
safe) and governed by a `[trusted(...)]` attribute recording **why** it's safe, **who**
owns it, when it was **reviewed**, and when that sign-off **expires**. Without that
governance, the `unsafe` is `NSYS100`.

```n#
[memory(safe)]
[trusted(
    reason: "len is checked against both span lengths before the unsafe copy",
    owner: "runtime-core",
    review: "2026-12-01",
    expires: "2027-06-01"
)]
[hot]
func CopyExact(dst: Span<byte>, src: ReadOnlySpan<byte>, len: int): CopyError {
    if len < 0 || len > dst.Length || len > src.Length {
        return CopyError.OutOfRange
    }

    unsafe {
        Buffer.MemoryCopy(src.ptr, dst.ptr, dst.Length, len)
    }

    return CopyError.Ok
}
```

`nlc query trusted` reports every governed wrapper with its owner, review date, expiry,
body size, and callers, so trusted code is auditable across the codebase.

> Scope is intentionally narrow: governed pointer operations inside trusted wrappers (e.g.
> a span's `.ptr`) and native interop via `LibraryImport`. **Arbitrary pointer arithmetic,
> `fixed`, and function pointers are not in this version.**

---

## Pooling

Renting from `ArrayPool`/`MemoryPool` carries a `poolRent` effect rather than counting as an
unconditional allocation, so `[hot]` code may rent from a hot-ready pool. The analyzer
checks lexical rent/return balance — a rent with no matching return (directly, via `using`,
or via `try/finally`) is `NSYS130`. Warm and return buffers at a `[boundary]`:

```n#
[boundary]
func ReadAndParse(path: string): int {
    buffer := ArrayPool<byte>.Shared.Rent(4096)
    try {
        read := ReadInto(path, buffer)
        return ParseFirstByte(buffer, read)   // [hot] callee
    } finally {
        ArrayPool<byte>.Shared.Return(buffer)
    }
}
```

> Balance checking is lexical and conservative — it does not prove arbitrary ownership
> transfer across function boundaries.

---

## SIMD auto-vectorization (shipped + measured)

This is the part that makes systems N# *fast*, not just *checked*. RyuJIT does not
auto-vectorize counted reduction loops (LLVM does — that was the entire Rust/C gap on those
kernels). So the N# IL backend recognizes two canonical hot-loop shapes and emits unrolled
`System.Numerics.Vector<T>` code directly.

**1. Counted reductions** — `for i < len { acc = acc + a[i] }`:

```n#
[hot]
func checksum(values: int[]): int {
    sum := 0
    len := values.Length
    for i := 0; i < len; i++ {
        sum = sum + values[i]
    }
    return sum
}
```

**2. Range-predicate counts** — `for i < len { if a[i] >= lo && a[i] <= hi { count++ } }`:

```n#
[hot]
func countAscii(values: int[]): int {
    count := 0
    len := values.Length
    for i := 0; i < len; i++ {
        if values[i] >= 32 && values[i] <= 126 {
            count = count + 1
        }
    }
    return count
}
```

Both rewrites are **on by default**; set `NSHARP_VECTORIZE_REDUCTIONS=0` to opt out. They
only fire under conservative guards: an unchecked context, an exact element-type match,
distinct accumulator/array/index names (no aliasing), and a side-effect-free loop bound
(`array.Length` lowers to a pure `ldlen`).

**Measured (Apple M4, .NET 10, BenchmarkDotNet vs the C# scalar baseline, 2026-06-07):**

| Kernel | Size | C# ns | N# ns | N# / C# |
|--------|------|-------|-------|---------|
| checksum (reduction) | 4096 | 994.7 | **222.5** | **0.22× — 4.5× faster** |
| count-ascii (range count) | 4096 | 1172.9 | **296.4** | **0.25× — 4.0× faster** |

This closes the worst-case gap behind native (Rust/C) on these kernels from ~8.8× to ~2×.

> **Honest scope.** Vectorization is narrow on purpose, with a single uniform-stride index
> and exactly the two shapes above. Counted **reductions** cover `int`/`long`/`uint`/`ulong`
> arrays; **range-predicate counts** currently cover `int[]` only. Floating-point reductions
> are deliberately excluded (FP addition isn't associative).
> Loops that don't match — and non-vectorizable kernels generally — correctly stay scalar
> and tie C#. Broader auto-vectorization (more loop shapes and element types) and a structural
> LLVM/NativeAOT-class vectorizing backend were evaluated and deferred; per-pattern `Vector<T>`
> emission already closes the measured gap to within ~2× of native — see
> [Systems N# vs Rust vs C](https://github.com/schneidenbach/nsharplang/blob/main/docs/design/systems-vs-native.md).

---

## Concurrency and atomics

`Volatile.Read`/`Volatile.Write`, the `Interlocked` family
(`Exchange`/`CompareExchange`/`Increment`/`Decrement`/`Add`), and `Thread.MemoryBarrier`
are callable from `[hot]` code through the BCL Hot Pack, which carries their memory-ordering
facts. A concurrency primitive *outside* that summarized set is `NSYS140` — there is no
wildcard accept. (Systems N# surfaces these facts; it does not claim to prove data-race
freedom.)

---

## AOT and trimming

The systems profile produces **target-qualified** AOT/trim facts: with `aotTarget:
nativeaot`, the analyzer reports per-symbol `aotSafe`/`trimSafe` facts and flags blockers as
`NSYS060`. `nlc publish --aot` runs that analysis and annotates
`[RequiresUnreferencedCode]`/`[RequiresDynamicCode]` where appropriate.

> **Analysis-only today.** `nlc publish --aot` verifies AOT-safety and emits the usual
> framework-dependent assembly — it does **not** yet emit a native image (reports always
> set `nativeImageEmitted: false`). Plain `nlc publish` produces framework-dependent
> artifacts. Treat AOT support as a correctness/readiness gate, not as native-image
> production.

---

## What's enforced vs. deferred

| Area | Status |
|------|--------|
| `[hot]`/`[boundary]` effect model + full `NSYS###` family | **Enforced** |
| `Result<T,E>` (allocation-free, must-use) | **Shipped + measured** |
| `alloc` / `stackalloc` (Span, no `unsafe`) | **Shipped** |
| `ref struct`, `&T`, `scoped`, `returns 'a` lifetime checks | **Shipped** (v1 escape shapes; not a borrow checker) |
| `unsafe` + `[trusted]` governance + `nlc query trusted` | **Shipped** (narrow: no arbitrary pointer arithmetic) |
| Pool rent/return balance | **Shipped** (lexical/conservative) |
| SIMD auto-vectorization (reductions, range counts) | **Shipped + measured** (narrow shapes) |
| AOT/trim facts | **Analysis-only** (no native image emission) |
| Atomics via Hot Pack | **Shipped** (fail-closed, no race proof) |
| General `value union`, ownership/move model, `defer`, effect lockfiles | **Deferred** |

---

## Next steps

- **[Language Tour](language-tour.md)** — the core language every systems program builds on
- **[Types](types.md)** — structs, `ref struct`, records, generics
- **[CLI Reference → Systems N# CLI Surface](cli-reference.md#systems-n-cli-surface)** — the full command surface
- **[Systems N# Proposal](https://github.com/schneidenbach/nsharplang/blob/main/docs/design/systems-nsharp.md)** — the canonical design spec
- **[Systems N# vs Rust vs C](https://github.com/schneidenbach/nsharplang/blob/main/docs/design/systems-vs-native.md)** — measured cross-language numbers
