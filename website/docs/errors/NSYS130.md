---
sidebar_label: NSYS130
title: "NSYS130: a pooled buffer is rented and not returned"
---

# NSYS130: a pooled buffer is rented and not returned

Renting from a pool is not an allocation, which is why `[hot]` code is allowed to do it at all —
but a rental is a debt. Systems N# tracks every buffer a function rents and reports the ones that
reach the end of the body without being returned, because a pool that leaks its buffers is a pool
that allocates.

The systems analyzer only runs when the project asks for it. Without the `language.profile:
systems` block, none of this is reported:

```yaml title="project.yml"
name: PacketCore
version: 1.0.0
outputType: library
targetFramework: net10.0
entry: Program.nl
language:
  profile: systems
  systems:
    mode: strict
    aotTarget: nativeaot
    stackBudgetBytes: 4096
```

```n#
import System.Buffers

type ByteArrayPool = ArrayPool<byte>

func Lease(): int {
    buffer := ByteArrayPool.Shared.Rent(4096)          // ERROR NSYS130
    return buffer.Length
}
```

```text
── [NSYS130] WARNING ───────────────────────── Program.nl:6:5 ──

    6 |     buffer := ByteArrayPool.Shared.Rent(4096)          // ERROR NSYS130
      |     ^^^^^^

pooled buffer 'buffer' rented here is not returned on an obvious lexical path

Systems policy 'systems:strict' rejected the 'pool' effect.

Hint: effect path: Lease

Suggestion: Return the buffer in a finally block, use a recognized owner/disposable pattern, or keep pooling inside a [boundary].
```

## Why is this reported?

A lost rental does not crash anything. It quietly turns the pool into a slower allocator: the next
`Rent` finds nothing to hand back, allocates a fresh array, and the array you dropped becomes GC
work. Nothing in the source says so, which is why the analyzer keeps the ledger for you.

The classification is deliberately wide. Any target containing `ArrayPool` or `MemoryPool` is a
pool call, and so is any target whose name ends in `.Rent` or `.Return` — so a custom pool that
spells the pair the same way gets the balance rule for free.

Note the type alias in the example. `ArrayPool<byte>.Shared` cannot be written directly today;
`type ByteArrayPool = ArrayPool<byte>` is how a generic pool is named, and it is what the shipped
systems samples use.

## How to fix it

Return it on the same lexical path, at a `[boundary]` where the pooling belongs:

```n#
import System.Buffers

type ByteArrayPool = ArrayPool<byte>

[boundary]
func Lease(): int {
    buffer := ByteArrayPool.Shared.Rent(4096)
    length := buffer.Length
    ByteArrayPool.Shared.Return(buffer)
    return length
}
```

A `finally` block or a recognised owner/disposable pattern discharges it just as well. The rule is
lexical and conservative — it does not model ownership transfer across function boundaries — which
is why the suggestion names the shapes it can see rather than telling you the code is wrong.

## Severity, and renting inside `[hot]`

An unreturned rental prefers **error** in `[hot]` and **warning** everywhere else: losing a rental
costs throughput rather than correctness. That is the opposite of [NSYS090](./NSYS090.md), where an
undisposed handle is an error at any temperature.

Renting *inside* `[hot]` is a separate, hot-only finding — `[hot] pool rent requires a hot-ready
pool precondition or allow(pool)` — because the first rent from a cold pool is a first-use stall.
Expect it alongside [NSYS110](./NSYS110.md) for the same line until the project declares a warmup.
A narrow `allow(pool, ...)` waives it.

## Related

- [NSYS090](./NSYS090.md) — the same ledger for disposable resources.
- [NSYS110](./NSYS110.md) — why a cold pool is also a readiness problem.
- [NSYS010](./NSYS010.md) — what pooling exists to avoid.
- [Systems Programming](../systems.md) — pooling and the `[boundary]` seam.
