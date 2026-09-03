---
sidebar_label: NSYS140
title: "NSYS140: a concurrency primitive with no systems semantics"
---

# NSYS140: a concurrency primitive with no systems semantics

Systems N# models a small, exact set of concurrency operations: `Volatile.Read`/`Write`, the five
`Interlocked` read-modify-writes, and `Thread.MemoryBarrier`. Anything else on those three types is
a primitive whose memory-ordering behaviour the profile cannot state, so it is reported rather than
quietly accepted. There is no wildcard accept.

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
import System.Threading

func Pause() {
    Thread.Sleep(1)          // ERROR NSYS140
}
```

```text
── [NSYS140] ERROR ────────────────────────── Program.nl:4:17 ──

    4 |     Thread.Sleep(1)          // ERROR NSYS140
      |                 ^

concurrency primitive 'Thread.Sleep' has no v1 HotSummary semantics

Systems policy 'systems:strict' rejected the 'concurrency' effect.

Hint: effect path: Pause

Suggestion: Use Volatile.Read/Write, Interlocked.Exchange/CompareExchange/Increment/Decrement/Add, or Thread.MemoryBarrier.
```

## Why is this reported?

The systems profile publishes *facts* about the code it checks, and a fact it cannot derive is not
a fact it will assume. `Thread.Sleep` blocks; other members of these types take locks, wait, or
have ordering semantics that depend on the runtime. Accepting them silently would mean the analyzer
had priced something it never looked at.

The test is by type prefix: any member of `Interlocked.`, `Volatile.` or `Thread.` — in the bare
spelling or the `System.Threading.`-qualified one — that is not in the modelled set. `MyInterlocked.Read`
is not caught; it is an ordinary call, and reports under [NSYS050](./NSYS050.md) instead.

## How to fix it

Use an operation the profile models:

```n#
func Fence() {
    Thread.MemoryBarrier()
}
```

`Volatile.Read`, `Volatile.Write`, `Interlocked.Exchange`, `Interlocked.CompareExchange`,
`Interlocked.Increment`, `Interlocked.Decrement` and `Interlocked.Add` are the rest of the set,
and all of them are callable from `[hot]` code through the BCL Hot Pack, which carries their
ordering facts.

Where a heavier primitive is genuinely the right answer — a cold shutdown drain, a startup
handshake — waive it narrowly and record why:

```n#
func Pause() {
    allow(concurrency, reason: "cold shutdown drain", owner: "runtime-core") {
        Thread.Sleep(1)
    }
}
```

## What this rule does not claim

Systems N# **surfaces** memory-ordering facts; it does not prove data-race freedom. Passing this
check means every concurrency primitive you reached has a stated semantics, not that your
concurrent algorithm is correct.

`NSYS140` is a policy finding: an error in `[hot]` and in ordinary systems-profile code, a warning
in a `[boundary]`, and silent under a matching `allow(concurrency, ...)`.

## Related

- [NSYS050](./NSYS050.md) — a call outside these three types with no summary at all.
- [NSYS110](./NSYS110.md) — why `Thread`, `Volatile` and `Interlocked` need no warmup fact.
- [Systems Programming](../systems.md) — concurrency and atomics.
