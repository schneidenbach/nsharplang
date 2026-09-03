---
sidebar_label: NSYS110
title: "NSYS110: hot code that needs warmup first"
---

# NSYS110: hot code that needs warmup first

`[hot]` is a promise about the *steady state*, and first-use work is what breaks it: reading a
static member runs that type's class initializer the first time it happens, on whichever call
happens to be first. Systems N# reports the read so that the initialization is moved somewhere it
can be paid deliberately, before the hot path starts.

The systems analyzer only runs when the project asks for it. Without the `language.profile:
systems` block, none of this is reported:

```yaml
# FILE project.yml
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
static class Registry {
    static Limit: int = 4
}

[hot]
func Cap(value: int): int {
    return value + Registry.Limit          // ERROR NSYS110
}
```

```text
── [NSYS110] ERROR ────────────────────────── Program.nl:7:28 ──

    7 |     return value + Registry.Limit          // ERROR NSYS110
      |                            ^

static member access 'Registry.Limit' requires a warmup or HotSummary readiness fact

Systems policy '[hot]' rejected the 'hotReadiness' effect.

Hint: effect path: Cap
```

## Why is this reported?

`Registry.Limit` looks like a field read, and after the first call it is one. On the first call it
is a class-initializer run of unbounded cost, and nothing in the source distinguishes the two. On
a hot path that is a latency spike in a place with no syntax to point at.

The receiver must be an **upper-case identifier**, which is this compiler's own type-name
convention: `buffer.Length` reads a field on a local, `Registry.Limit` reaches a static member, and
nothing else in the expression tells them apart.

## How to fix it

Pass the value in. A parameter has no initializer to run:

```n#
[hot]
func Cap(value: int, limit: int): int {
    if value > limit {
        return limit
    }
    return value
}
```

Or declare the warmup and let the project state that first-use work is paid up front. Naming any
warmup function in `language.systems.warmup` clears the readiness obligation for the project:

```yaml
language:
  profile: systems
  systems:
    mode: strict
    aotTarget: nativeaot
    warmup:
      - Warmup
```

## Four answers clear the read, and any one is enough

- the project declares a `warmup` list at all;
- the receiver is an `enum` your project declares — `Color.Red` is not a warmup obligation;
- the receiver is one of the eight statics the call family knows are hot-ready: `BinaryPrimitives`,
  `MemoryMarshal`, `BitOperations`, `Math`, `MathF`, `Volatile`, `Interlocked`, `Thread`. So
  `Math.Min(value, 16)` in a `[hot]` function reports nothing;
- a target-qualified `HotSummary` carries a readiness fact for that receiver.

The same code also reports a summarized callee that declares `requiresWarmup` — including a pool
rent, which is why renting inside `[hot]` earns both `NSYS110` and [NSYS130](./NSYS130.md).

`NSYS110` is reported **only** inside `[hot]`. Cold code and `[boundary]` code hear nothing at all,
not even a warning: paying first-use work is exactly what a boundary is for.

## Related

- [NSYS130](./NSYS130.md) — a pool rent, which is also first-use work until the pool is warm.
- [NSYS050](./NSYS050.md) — a call with no summary to read a readiness fact from.
- [Systems Programming](../systems.md) — `language.systems.warmup` and the BCL Hot Pack.
