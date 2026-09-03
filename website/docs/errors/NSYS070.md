---
sidebar_label: NSYS070
title: "NSYS070: a systems-hostile type on a hot surface"
---

# NSYS070: a systems-hostile type on a hot surface

`[hot]` and `[boundary]` are promises about a *signature*, so they are checked before the body is
read. A parameter or return type that drags the managed world across the seam — a `Stream`, an
`object`, a `List`, an `IEnumerable`, a `Task` — is reported at the declaration, because no
amount of care inside the function can undo what the signature already exposed.

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
import System.IO

[hot]
func CanSeek(input: Stream): bool {          // ERROR NSYS070
    return input.CanSeek
}
```

```text
── [NSYS070] ERROR ────────────────────────── Program.nl:4:14 ──

    4 | func CanSeek(input: Stream): bool {          // ERROR NSYS070
      |              ^^^^^

[hot] parameter 'input' exposes a systems-hostile type: Stream

Systems policy '[hot]' rejected the 'boundaryLeak' effect.

Hint: effect path: CanSeek

Suggestion: Use primitives, spans, readonly/ref structs, Result<T,E>, or an explicit boundary adapter type.
```

## Why is this reported?

The message names the type, and the name *is* the reason: fourteen collection, sequence and
delegate constructors (`IEnumerable`, `IQueryable`, `IEnumerator`, `IAsyncEnumerable`, `Task`,
`ValueTask`, `Func`, `Action`, `List`, `Dictionary`, `IList`, `ICollection`, `IReadOnlyList`,
`IReadOnlyCollection`) and five simple ones (`object`, `dynamic`, `Type`, `Stream`, `Delegate`)
are hostile wherever they appear on a systems surface. Each one hands the function something whose
cost the caller decides.

Every parameter is asked separately and reports at its own position, so a signature with three
hostile parameters produces three findings rather than one about the function.

## How to fix it

Take the bytes, not the source of the bytes. A span has a known length, a known element type and
no ownership question:

```n#
import System

[hot]
func HasHeader(bytes: ReadOnlySpan<byte>): bool {
    return bytes.Length >= 16
}
```

Reading the `Stream` is then `[boundary]` work: open it, fill a buffer, and call the hot function
with a span over that buffer. That is the shape the two attributes exist to describe — the
boundary meets the managed world, the hot path sees only values.

`Result<T,E>` is transparent to this rule: only its payloads are judged, so returning
`Result<int, ParseError>` from a `[hot]` function is fine.

## `[hot]` asks one more question than `[boundary]`

A `[boundary]` refuses only the named hostile shapes. A `[hot]` signature also refuses anything it
has **no summary rule for** — an unrecognised generic is `generic type 'X' has no HotSummary
surface rule`, and an unrecognised simple name is `managed or unsummarized type 'X'`:

```n#
[hot]
func Wrap(box: Holder<int>): int {          // reports NSYS070
    return 0
}

class Holder<T> {
}
```

The same declaration on a `[boundary]` reports nothing. Two things rescue a name from the strict
arm: a `struct` or `enum` your project declares, and a generic parameter constrained to `struct`.
An array's *element* is not the exposed surface, so the strict arm is switched off for one hop
inside an array type.

Severity follows the attribute: an error in `[hot]`, a warning at a `[boundary]`.

## Related

- [NSYS080](./NSYS080.md) — the other signature rule, about lifetimes rather than shapes.
- [NSYS170](./NSYS170.md) — a `Result` return whose copy shape is too large.
- [NSYS040](./NSYS040.md) — what actually happens when the hostile type is used.
- [Systems Programming](../systems.md) — `[hot]`, `[boundary]` and spans.
