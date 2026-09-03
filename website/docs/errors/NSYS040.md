---
sidebar_label: NSYS040
title: "NSYS040: the call goes through runtime dispatch"
---

# NSYS040: the call goes through runtime dispatch

Runtime dispatch is a call whose target is chosen while the program is running: an interface
method, an enumerator step, a delegate invoked reflectively. Systems N# reports it because the
cost is not one indirection — it is the inlining, the constant folding and the bounds-check
elimination that the JIT cannot do once it stops knowing what it is calling.

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
import System.Collections.Generic

func FirstOrZero(items: List<int>): int {
    walker := items.GetEnumerator()          // ERROR NSYS040
    return walker.Current
}
```

```text
── [NSYS040] ERROR ────────────────────────── Program.nl:4:34 ──

    4 |     walker := items.GetEnumerator()          // ERROR NSYS040
      |                                  ^

call to 'items.GetEnumerator' uses runtime dispatch or an unsummarized interface-shaped API

Systems policy 'systems:strict' rejected the 'dispatch' effect.

Hint: effect path: FirstOrZero

Suggestion: Use a concrete receiver, constrained generic call, or HotSummary-covered wrapper.
```

## Why is this reported?

`GetEnumerator` is the honest example. It looks like a method call on a list, and it is really a
handoff to whatever implementation the runtime finds: from that point the loop body is opaque, and
so is everything the enumerator does per step.

The analyzer recognises the shape by name, and the two halves of the test are deliberately
different. A target that **names** an enumerable surface — anything containing `System.Linq`,
`IEnumerable` or `IQueryable`, in any position — is dispatch. A target that **steps** one is
matched by suffix: `.GetEnumerator`, `.MoveNext`, `.DynamicInvoke`. A function of your own called
`MoveNext` is not caught by the second rule; any receiver's `.MoveNext` is.

## How to fix it

Read the elements through a concrete type. An array — or a span over one — has a length the JIT
can see and an element type it can specialise for:

```n#
func FirstOrZero(items: int[]): int {
    if items.Length == 0 {
        return 0
    }
    return items[0]
}
```

Where the abstraction is genuinely needed, take a generic parameter constrained to `struct` plus
your own interface. A constrained generic call over a value type is resolved at JIT time, per
instantiation, with no interface dispatch left in the code.

## Iterating is not the same as calling

A `for ... in` loop over a `List<int>` reports nothing:

```n#
import System.Collections.Generic

func Sum(items: List<int>): int {
    total := 0
    for value in items {
        total = total + value
    }
    return total
}
```

The rule is about the **call** you wrote, not about iteration in general. That is a deliberate
limit rather than a claim that the loop is free — write the enumerator step yourself and it is
reported.

`NSYS040` is a policy finding: an error in `[hot]` and in ordinary systems-profile code, a warning
in a `[boundary]`, and silent under a narrow `allow(dispatch, ...)`.

## Related

- [NSYS030](./NSYS030.md) — the delegate whose invocation is the other kind of indirect call.
- [NSYS050](./NSYS050.md) — a call the analyzer could not classify at all.
- [NSYS070](./NSYS070.md) — an `IEnumerable` on the signature, reported before the body is read.
- [Systems Programming](../systems.md) — the `NSYS` cost model.
