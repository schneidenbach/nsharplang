---
sidebar_label: NSYS030
title: "NSYS030: a delegate or closure is constructed here"
---

# NSYS030: a delegate or closure is constructed here

A lambda is two costs at once: a delegate object on the heap, and — if it reads anything from the
enclosing scope — a closure object to carry it. Systems N# reports the construction wherever it
appears on a systems path, not the call through it, because the construction is the part that
allocates and the part you can move.

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
func Adder(): Func<int, int> {
    return (x) => x + 1          // ERROR NSYS030
}
```

```text
── [NSYS030] ERROR ────────────────────────── Program.nl:2:12 ──

    2 |     return (x) => x + 1          // ERROR NSYS030
      |            ^

delegate or closure construction is not allowed here

Systems policy 'systems:strict' rejected the 'delegate' effect.

Hint: effect path: Adder

Suggestion: Move delegate construction behind a [boundary] or use a direct call.
```

## Why is this reported?

The sentence says *not allowed here* rather than naming the profile, and that is the actual shape
of the rule: the same lambda is fine one `[boundary]` away. What a systems path cannot afford is
building it per call — a delegate allocated in a loop is one allocation and one indirect call per
iteration, and neither is visible in the source.

The rule fires on the lambda itself. It does not try to decide whether the lambda captures: a
delegate is constructed either way, so the finding is the same and the effect summary records both
the delegate and the closure bit.

## How to fix it

Call the function directly. A named function called by name is a direct call with nothing on the
heap:

```n#
func addOne(x: int): int {
    return x + 1
}

func Bump(value: int): int {
    return addOne(value)
}
```

When the indirection is the point — a strategy chosen once and used many times — build the
delegate at a `[boundary]` during setup and hand the hot path the result, or waive it narrowly
where it is genuinely one-time:

```n#
func Adder(): Func<int, int> {
    allow(delegate, reason: "startup wiring only", owner: "runtime-core") {
        return (x) => x + 1
    }
}
```

## Severity, and what the boundary changes

`NSYS030` is a policy finding: an **error** in `[hot]` and in ordinary systems-profile code, a
**warning** in a `[boundary]` function, and silent under a matching `allow(delegate, ...)`. A
resolved callee that constructs a delegate is reported against its `[hot]` caller at the call
site instead, as `callee 'X' constructs a delegate or closure on a hot path`.

## Related

- [NSYS010](./NSYS010.md) — the allocation a delegate is.
- [NSYS040](./NSYS040.md) — the indirect call a delegate makes.
- [NSYS180](./NSYS180.md) — what a function-level `allow` has to say for itself.
- [Systems Programming](../systems.md) — the `[hot]`/`[boundary]` split.
