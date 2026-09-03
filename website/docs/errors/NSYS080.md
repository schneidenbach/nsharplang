---
sidebar_label: NSYS080
title: "NSYS080: a lifetime that cannot be proven"
---

# NSYS080: a lifetime that cannot be proven

A span borrows a frame it does not own. Systems N# checks at compile time that no borrowed view
outlives the storage behind it: a ref-like field may only live in a `ref struct`, a `[hot]`
function may only return a ref-like value with a written lifetime, and a `stackalloc` must fit the
project's stack budget. All three are the same guarantee, so they share one code.

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
import System

struct Holder {
    buf: ReadOnlySpan<byte>          // ERROR NSYS080
}
```

```text
── [NSYS080] ERROR ─────────────────────────── Program.nl:4:5 ──

    4 |     buf: ReadOnlySpan<byte>          // ERROR NSYS080
      |     ^^^

ref-like field 'buf' is only allowed inside a ref struct

Systems policy 'systems:strict' rejected the 'lifetime' effect.

Hint: effect path: Holder

Suggestion: Declare the containing type as `ref struct`, or store a heap-safe owner such as Memory<T>/ReadOnlyMemory<T>.
```

## Why is this reported?

`Holder` is an ordinary struct, so a `Holder` can be boxed, stored in a field of a class, captured
by a closure or put in an array — and every one of those outlives the stack frame whose bytes the
`ReadOnlySpan` points at. A `ref struct` is the type-system marker that says none of that is
allowed, which is why the field is legal there and nowhere else.

## How to fix it

Declare the containing type as a `ref struct`, and the CLR's own rules keep it on the stack:

```n#
import System

ref struct Holder {
    buf: ReadOnlySpan<byte>
}
```

If the value genuinely must be stored — put in a field, held across an `await`, kept in a
collection — the answer is a heap-safe owner instead: `Memory<byte>` or `ReadOnlyMemory<byte>`
carry the same bytes with no frame to outlive.

## The other two shapes that report NSYS080

**A `[hot]` function returning a borrowed view with no lifetime.** The compiler computes a return
lifetime for every function — `local`, `param`, `heap(owner)`, `static` or `unknown` — and
`unknown` is not admissible in `[hot]`:

```n#
import System

[hot]
func Head(buf: ReadOnlySpan<byte>): ReadOnlySpan<byte> {          // reports NSYS080
    return buf.Slice(0, 1)
}
```

Tie the result to the input with `returns 'a`, or return an owned value instead.

**A `stackalloc` over the budget.** `language.systems.stackBudgetBytes` (4096 above) is a hard
ceiling, and the message names both numbers — `stackalloc reserves 8192 bytes, above the
configured systems stack budget of 4096 bytes`. Raise the budget deliberately, or take the buffer
from the caller.

This is a CLR ref-safety model aimed at the escape shapes, and it is **not** a borrow checker:
move and affine ownership are not modelled in this version.

## Related

- [NSYS070](./NSYS070.md) — the other signature rule, about which types may cross a systems surface.
- [NSYS010](./NSYS010.md) — why `stackalloc` exists: it is not a heap allocation.
- [Systems Programming](../systems.md) — `ref struct`, `scoped` and `returns 'a`.
