---
sidebar_label: NSYS120
title: "NSYS120: an unguarded trap on a systems path"
---

# NSYS120: an unguarded trap on a systems path

Systems N# asks a program to carry its failures as values. An exception is control flow the type
system cannot see, with a cost — stack walk, handler search, allocation — that is paid exactly
when the program is already in trouble. So `throw` and `try` are reported on any systems path, and
in `[hot]` they are refused outright, together with the implicit traps a bounds check or a division
can raise.

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
func Fail() {
    throw alloc new Exception("frame too short")          // ERROR NSYS120
}
```

```text
── [NSYS120] ERROR ─────────────────────────── Program.nl:2:5 ──

    2 |     throw alloc new Exception("frame too short")          // ERROR NSYS120
      |     ^

systems code must translate exception control flow into explicit Result/error values

Systems policy 'systems:strict' rejected the 'throw' effect.

Hint: effect path: Fail

Suggestion: Catch exceptions at a [boundary] and return Result<T,E> or another explicit error value.
```

## Why is this reported?

A function that throws has a second, unwritten return type. Callers cannot see it, the compiler
cannot check that anybody handles it, and the systems profile cannot price it. `Result<T,E>` is
the alternative the language ships for exactly this: a `readonly struct` with a tag and two
payloads, allocation-free on both the success and the failure path.

## How to fix it

Return the failure:

```n#
enum FrameError {
    Short
}

func Read(bytes: byte[]): Result<int, FrameError> {
    if bytes.Length < 4 {
        return Err(FrameError.Short)
    }
    return Ok(bytes.Length)
}
```

Catching is how a boundary is written, so `try`/`catch` belongs in a `[boundary]` function that
translates what it caught into an explicit error value. There the finding is a warning for review
rather than an error.

## The four sentences under one code

Which one you get says which promise was broken:

- **cold systems code, `throw`** — `systems code must translate exception control flow into
  explicit Result/error values`;
- **cold systems code, `try`** — `exception control flow is reported on systems paths`, a
  deliberately weaker sentence, because catching is what a boundary does;
- **`[hot]`** — a flat refusal: `[hot] cannot throw exceptions` and `[hot] cannot use exception
  control flow`. These come through the hot-only door, which **no** `allow(throw)` waives;
- **`[hot]`, implicit traps** — an unguarded index, a division with no proven non-zero divisor, or
  checked arithmetic with no overflow proof:

```n#
[hot]
func First(bytes: byte[]): byte {
    return bytes[0]          // reports NSYS120: index access in [hot] requires a proven
}                            //                bounds guard or allow(trap)
```

Guard it — `if bytes.Length < 1 { return 0 }` before the read — and the finding goes away, because
the analyzer tracks the guard, not the syntax. The cold arms are policy findings, so a narrow
`allow(throw, ...)` or `allow(trap, ...)` silences them and a `[boundary]` downgrades them.

## Related

- [NSYS160](./NSYS160.md) — the `Result` you returned instead, and what happens when a caller drops it.
- [NSYS170](./NSYS170.md) — how large a `Result` a hot signature can carry.
- [NSYS090](./NSYS090.md) — resource cleanup, which is why `try`/`finally` shows up here.
- [Systems Programming](../systems.md) — `Result<T,E>`.
