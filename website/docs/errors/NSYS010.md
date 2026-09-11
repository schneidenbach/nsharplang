---
sidebar_label: NSYS010
title: "NSYS010: allocation on a hot path"
---

# NSYS010: allocation on a hot path

A `[hot]` function promises that its steady state costs nothing it did not declare, and heap
allocation is the first thing that promise covers. Inside `[hot]` — and inside any function marked
`[alloc(none)]` — allocation is refused outright: spelling `alloc` does not buy it, because the
keyword makes an allocation *visible*, not *free*.

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
[hot]
func BuildHeader(): byte[] {
    return alloc new byte[16]          // ERROR NSYS010
}
```

```text
── [NSYS010] ERROR ────────────────────────── Program.nl:3:18 ──

    3 |     return alloc new byte[16]          // ERROR NSYS010
      |                  ^

allocation not allowed in [hot] function

Systems policy '[hot]' rejected the 'allocation' effect.

Hint: effect path: BuildHeader

Suggestion: Move allocation behind a [boundary], return caller-provided storage, or use a narrow allow(alloc) only for a cold path.
```

## Why is this reported?

A hot path that allocates hands its latency to the garbage collector: the cost is not the `new`,
it is the collection that happens later, on a thread and at a moment the function has no say over.
`[hot]` is the place where you have declared that not to be acceptable, so the analyzer holds you
to it at the allocation site.

The rule follows calls. A `[hot]` function that calls a cold helper that allocates is reported at
the **call**, and the message names the callee:

```n#
[hot]
func Caller(): int {
    return cold()          // reports NSYS010: callee 'cold' allocates on a hot/alloc(none) path
}

func cold(): int {
    table := alloc new int[4]
    return table.Length
}
```

## How to fix it

Take the storage from the caller. A `[hot]` function that writes into a span the caller already
owns allocates nothing:

```n#
import System

[hot]
func WriteHeader(header: Span<byte>): int {
    if header.Length < 16 {
        return 0
    }
    header[0] = (byte)1
    return 16
}
```

The other two shapes of fix are to move the allocation to a `[boundary]` and hand the hot function
the result, or — when the allocation is genuinely one-time — to waive it narrowly and say why:

```n#
[hot]
func BuildHeader(): byte[] {
    allow(alloc, reason: "one-time warmup buffer", owner: "runtime-core") {
        return alloc new byte[16]
    }
}
```

## Declarations that allocate before the body is read

Two `[hot]` signatures are refused on the signature alone, because both compile to a
heap-allocated state machine: a `[hot] async` function reports `NSYS010` at its declaration with
`[hot] async functions allocate or require async machinery in Systems N# v1`, and a `[hot] func*`
iterator reports one at its declaration and a second at each `yield`.

`stackalloc` is not an allocation for this rule — it is a stack buffer bounded by
`language.systems.stackBudgetBytes`, and going over that budget is [NSYS080](./NSYS080.md)
instead. Renting from a pool is not one either; that is [NSYS130](./NSYS130.md).

## Related

- [NSYS001](./NSYS001.md) — the same allocation in cold systems code, where the fix is the `alloc` keyword.
- [NSYS130](./NSYS130.md) — pool rent and return balance.
- [NSYS180](./NSYS180.md) — what a function-level `allow` has to say for itself.
- [Systems Programming](../systems.md) — the `[hot]` contract and the `NSYS` cost model.
