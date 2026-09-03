---
sidebar_label: NSYS160
title: "NSYS160: a Result is ignored"
---

# NSYS160: a Result is ignored

`Result<T,E>` is must-use. A call that returns one and is written as a bare statement has dropped
the error path on the floor — the failure was computed, handed back, and thrown away without
anybody looking at it. Systems N# reports that, because the whole reason to return errors as
values is that the compiler can then tell when one is ignored.

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
enum ParseError {
    Bad
}

func parse(value: int): Result<int, ParseError> {
    return Ok(value)
}

func run(): int {
    parse(1)          // ERROR NSYS160
    return 0
}
```

```text
── [NSYS160] ERROR ───────────────────────── Program.nl:10:10 ──

    10 |     parse(1)          // ERROR NSYS160
       |          ^^^^^

Result returned by 'parse' is ignored

Systems policy 'systems:strict' rejected the 'resultMustUse' effect.

Hint: effect path: run

Suggestion: Bind the Result, return it, or explicitly inspect IsOk/IsErr so the error path is handled.
```

## Why is this reported?

An ignored exception is loud. An ignored `Result` is silent: the program keeps going with a
failure it never read, and the next symptom appears somewhere unrelated. Must-use is what buys back
the one thing exceptions were actually good at.

The rule needs a contract to read, so it is deliberately narrow. It fires only when the call
resolved to a **declared** function whose **written** return type is `Result<T,E>` — a generic
named `Result` with exactly two type arguments. A call with no resolved declaration, or a callee
with no written return type, is silent, because a rule about a discarded error path cannot be
stated about a contract the analyzer never read.

## How to fix it

Bind it and look at it:

```n#
enum ParseError {
    Bad
}

func parse(value: int): Result<int, ParseError> {
    return Ok(value)
}

func run(): int {
    outcome := parse(1)
    if outcome.IsErr {
        return 1
    }
    return outcome.OkValueUnchecked
}
```

Returning the `Result` onward counts too — the obligation moves to your caller, which is usually
the right answer.

## Discarding on purpose

When you really do mean to ignore it, say so with an explicit discard:

```n#
func run(): int {
    _ = parse(1)
    return 0
}
```

That is a deliberate, greppable statement rather than an accident, and it reports nothing.

Severity follows the project: an **error** in a `[hot]` function or anywhere in a systems project,
a **warning** otherwise — so a default-profile program gets a nudge rather than a failure.

## Related

- [NSYS120](./NSYS120.md) — why systems code returns `Result` instead of throwing.
- [NSYS170](./NSYS170.md) — how large a `Result` a hot signature can carry.
- [Systems Programming](../systems.md) — `Result<T,E>`.
