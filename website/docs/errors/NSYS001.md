---
sidebar_label: NSYS001
title: "NSYS001: heap allocation must be marked alloc"
---

# NSYS001: heap allocation must be marked alloc

In a systems project, every heap allocation is written out loud. Four expression shapes reach the
heap — a `new`, an array literal, an interpolated string and a `with` copy — and each one must
carry the `alloc` keyword or sit inside an `alloc { }` zone. The keyword changes nothing about what
the program does; it makes the allocation greppable, so a reviewer can see the whole allocation
budget of a file by reading it.

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
func BuildHeader(): byte[] {
    header := new byte[16]          // ERROR NSYS001
    return header
}
```

```text
── [NSYS001] ERROR ────────────────────────── Program.nl:2:15 ──

    2 |     header := new byte[16]          // ERROR NSYS001
      |               ^

heap allocation in systems strict must be marked with alloc

Systems policy 'systems:strict' rejected the 'allocation' effect.

Hint: effect path: BuildHeader

Suggestion: Write alloc new/alloc [...]/alloc $"..." or move this work into a [boundary].
```

## Why is this reported?

Allocation is the one cost in a managed program that a reader cannot see from the syntax: `new
byte[16]`, `$"frame {id}"` and a `with` copy all look like ordinary expressions and all of them
reach the GC. Systems N# does not ban them outside `[hot]` — it insists they be *spelled*, so that
"where does this file allocate?" is a text search rather than a code review.

The interpolated string is worth calling out, because it is the one people are surprised by:

```n#
func Label(id: int): string {
    text := $"frame {id}"          // reports NSYS001
    return text
}
```

## How to fix it

Write the keyword:

```n#
func BuildHeader(): byte[] {
    header := alloc new byte[16]
    return header
}
```

Or open an `alloc` zone, when a block of setup code allocates several times and marking each site
adds nothing:

```n#
func BuildHeader(): byte[] {
    alloc {
        return new byte[16]
    }
}
```

## What reports something else instead

The rule has three arms, and which one answers depends on the function, not on the expression:

- a `[hot]` or `[alloc(none)]` function **refuses** the allocation outright — that is
  [NSYS010](./NSYS010.md), and writing `alloc` does not help;
- a `[boundary]` function still reports `NSYS001`, but as a **warning** with its own sentence
  (`boundary allocation reported for systems handoff review`), because a boundary is exactly where
  a systems program is allowed to meet the managed world;
- a project without `profile: systems` is silent.

A block-level `allow(alloc)` does **not** satisfy this arm — it silences the `[hot]` ban, not the
request for the keyword. Use `alloc { }` when you want a zone.

## Related

- [NSYS010](./NSYS010.md) — the same allocation inside a `[hot]` or `[alloc(none)]` function.
- [NSYS130](./NSYS130.md) — renting from a pool instead of allocating, and forgetting to give it back.
- [Systems Programming](../systems.md) — the `alloc` keyword and the systems profile.
