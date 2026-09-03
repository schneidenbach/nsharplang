---
sidebar_label: NSYS100
title: "NSYS100: unsafe code with no trusted wrapper"
---

# NSYS100: unsafe code with no trusted wrapper

`unsafe` blocks work in any N# project. In a *systems* project they must be governed: the block
has to sit inside a function that both asserts its public behaviour is safe, with `[memory(safe)]`,
and records why — with `[trusted(reason, owner, review)]`. The point is not to make `unsafe` hard;
it is to make every unsafe block in the codebase answerable to `nlc query trusted`.

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
import System

func copyFirst(dst: Span<byte>, src: ReadOnlySpan<byte>): int {
    unsafe {          // ERROR NSYS100
        Buffer.MemoryCopy(src.ptr, dst.ptr, dst.Length, 1)
    }
    return 1
}
```

```text
── [NSYS100] ERROR ─────────────────────────── Program.nl:4:5 ──

    4 |     unsafe {          // ERROR NSYS100
      |     ^

unsafe block requires a [trusted] memory-safe wrapper in systems code

Systems policy 'systems:strict' rejected the 'memorySafety' effect.

Hint: effect path: copyFirst

Suggestion: Wrap unsafe code in a small [trusted(reason, owner, review)] function with [memory(safe)].
```

## Why is this reported?

An `unsafe` block reads and writes memory with no bounds check of any kind, so the proof that it
is correct lives in someone's head. `[trusted]` is where that proof gets written down: what makes
it safe, who owns it, and when it was last reviewed. Without those, the block is not an audited
exception — it is just unchecked memory access with a keyword in front of it.

`Buffer.MemoryCopy` gets the same treatment from the other direction. It is the one call the
profile insists on seeing inside a syntactic cage, and calling it outside an `unsafe` block reports
`NSYS100` with its own sentence: `Buffer.MemoryCopy must be isolated inside an unsafe block`.

## How to fix it

Wrap it in a small governed function, with the bounds proof stated in the body and the review
metadata stated in the attribute:

```n#
import System

[memory(safe)]
[trusted(
    reason: "both spans are length-checked before the copy",
    owner: "runtime-core",
    review: "2026-12-01"
)]
func copyFirst(dst: Span<byte>, src: ReadOnlySpan<byte>): int {
    if dst.Length < 1 || src.Length < 1 {
        return 0
    }

    unsafe {
        Buffer.MemoryCopy(src.ptr, dst.ptr, dst.Length, 1)
    }

    return 1
}
```

`nlc query trusted` then lists this wrapper with its owner, review date, expiry, body size and
callers, so trusted code is auditable across the codebase without grep.

## An incomplete `[trusted]` is one finding that names what is missing

A wrapper that declares `[trusted]` but has not finished the proof reports a single `NSYS100`, and
the sentence lists exactly the absent parts:

```n#
[trusted(reason: "wraps a checked native copy")]
func copyFirst(): int {          // reports NSYS100: [trusted] is missing the owner and review
    return 1                     //                metadata and [memory(safe)]
}
```

One unfinished proof is one underline and one edit — not one finding per missing field. `expires`
is deliberately not part of the rule: it travels on the trusted-site record for the report to
show, and a wrapper with no expiry is still audited.

The block-form rule is a policy finding, so a narrow `allow(memorySafety, ...)` around the block
silences it and a `[boundary]` downgrades it. The declaration-form rule above is not: `[trusted]`
*is* the waiver mechanism, so waiving the rules that make a waiver auditable would leave nothing
behind.

Scope here is intentionally narrow — governed pointer operations inside trusted wrappers and
native interop via `LibraryImport`. Arbitrary pointer arithmetic, `fixed` and function pointers are
not in this version.

## Related

- `NL405` — what a `[LibraryImport]` signature may spell, and why a span may not appear in one.
- [NSYS060](./NSYS060.md) — the other publish-time promise a systems project makes.
- [Systems Programming](../systems.md) — restricted `unsafe` and `[trusted]` governance.
