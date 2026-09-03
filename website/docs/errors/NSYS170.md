---
sidebar_label: NSYS170
title: "NSYS170: the Result copy shape is too large for a hot path"
---

# NSYS170: the Result copy shape is too large for a hot path

`Result<T,E>` is a struct, so returning one copies it: a tag plus both payloads, by value, at every
`return` and every call site on the path. Systems N# estimates that copy shape from the signature
and reports a return type above the v1 hot-path guidance of 128 bytes, so an error type that grew
by accident does not turn into a memcpy on the success path.

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
struct Frame {
    Lo: long
    Hi: long
}

func decodeInner(frame: Frame): Result<Frame, Frame> {
    return Ok(frame)
}

[boundary]
func Decode(frame: Frame): Result<Result<Frame, Frame>, Result<Frame, Frame>> {          // ERROR NSYS170
    return Ok(decodeInner(frame))
}
```

```text
── [NSYS170] WARNING ──────────────────────── Program.nl:11:1 ──

    11 | func Decode(frame: Frame): Result<Result<Frame, Frame>, Result<Frame, Frame>> {          // ERROR NSYS170
       | ^^^^^^

Result<T,E> copy shape is estimated at 176 bytes, above the v1 hot-path guidance of 128 bytes

Systems policy 'systems:strict' rejected the 'resultAbi' effect.

Hint: effect path: Decode

Suggestion: Return a smaller error/value payload or pass large data through caller-owned storage.
```

## Why is this reported?

The estimate is `16` bytes of tag and padding plus both payloads, and the payload sizes are
deliberate over-estimates of what the analyzer cannot see: a `struct` your project declares counts
as 32, an unrecognised generic as 32, a span or memory as 16, an array or reference as 8. The
number in the message is that arithmetic, and the threshold is `above` 128 — a shape estimated at
exactly 128 bytes is accepted.

This is guidance, not a broken promise, so it is a **warning** even in `[hot]`. It is the one
`NSYS` rule whose severity does not rise with the attribute.

## How to fix it

Shrink the error type. An `enum` is 4 bytes, and it is usually all an error needs — the details
belong in a log at the boundary, not in the value the hot path copies:

```n#
enum DecodeError {
    Short
}

struct Frame {
    Lo: long
    Hi: long
}

[boundary]
func Decode(frame: Frame): Result<Frame, DecodeError> {
    return Ok(frame)
}
```

Where the payload really is large, pass it through caller-owned storage — a `Span<byte>` the
caller supplies — and return a `Result` that carries only how much was written.

## What the rule is asked about, and what it is not

Only `[hot]` and `[boundary]` functions are asked; a cold function may return whatever it likes. The
question is asked of the **return type** alone, so a large `Result` as a parameter reports nothing
here. And the identity check comes first: any generic of arity two would size as `16 + both
payloads`, so the rule confirms the type really is a `Result` before it measures it.

`Result` is transparent to the *shape* rule next door — [NSYS070](./NSYS070.md) judges only its
payloads — so a `Result` return can earn this finding and no other.

## Related

- [NSYS070](./NSYS070.md) — the other question asked of a `[hot]` or `[boundary]` signature.
- [NSYS160](./NSYS160.md) — the must-use rule on the same type.
- [Systems Programming](../systems.md) — `Result<T,E>` and its copy shape.
