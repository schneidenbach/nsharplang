---
sidebar_label: NSYS020
title: "NSYS020: a value is boxed on a systems path"
---

# NSYS020: a value is boxed on a systems path

Boxing puts a value type on the heap so that something typed `object` can hold it — one
allocation, one indirection, and a copy on the way back out. Systems N# reports every cast to
`object` on a systems path, because the target type is all a compiler can see: it cannot know
from the cast alone whether the operand was an `int` that really boxes or a reference that does
not, so it says *may box* and asks you to keep the value concrete.

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
func Tag(value: int): object {
    return (object)value          // ERROR NSYS020
}
```

```text
── [NSYS020] ERROR ────────────────────────── Program.nl:2:12 ──

    2 |     return (object)value          // ERROR NSYS020
      |            ^

cast to object may box a value on systems paths

Systems policy 'systems:strict' rejected the 'boxing' effect.

Hint: effect path: Tag

Suggestion: Keep values concrete or use a generic/constrained API.
```

## Why is this reported?

A boxing conversion is invisible in the source and expensive at run time: the value is copied onto
the heap, the reference is what travels, and reading it back copies again. On a hot path that is
an allocation per call in a place nothing named `new`.

The rule is deliberately syntactic. It fires on a cast whose target is `object` (or
`System.Object`) and on nothing else, so a reference that is already `object` is reported
alongside the `int` that really boxes:

```n#
func Tag(value: string): object {
    return (object)value          // reports NSYS020
}
```

That is the honest answer rather than a guess. If you know the operand is a reference, the cast is
usually removable anyway.

## How to fix it

Keep the value in a type that holds it without a heap trip:

```n#
func Tag(value: int): long {
    return (long)value
}
```

Where a single function really must accept several shapes, take a generic parameter constrained to
`struct` rather than `object` — a constrained generic is instantiated per value type and boxes
nothing.

## Where the same cast is a warning

`NSYS020` is a policy finding, so its severity depends on where you wrote it:

- in a `[hot]` function or in ordinary systems-profile code it is an **error**;
- in a `[boundary]` function it is a **warning** — a boundary is where a systems program meets
  the managed world, and its findings are for review;
- a narrow `allow(boxing, reason: "...", owner: "...")` around the cast silences it.

A callee that boxes reports against its `[hot]` caller instead, at the call site, as
`callee 'X' boxes a value on a hot path`.

## Related

- [NSYS010](./NSYS010.md) — allocation on a hot path, which a box is a special case of.
- [NSYS040](./NSYS040.md) — dispatch through an interface, the other cost of erasing a value's type.
- [Systems Programming](../systems.md) — the `NSYS` cost model.
