---
sidebar_label: NSYS050
title: "NSYS050: an external call with no systems summary"
---

# NSYS050: an external call with no systems summary

A `[hot]` function promises a cost model, and it can only promise one for code whose costs are
known. When a call leaves the project for a method the analyzer has no summary for, there is
nothing to check — so the profile fails closed and says so, rather than accepting a call whose
allocation, boxing and throwing behaviour nobody has stated.

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
[hot]
func Digits(value: int): string {
    return value.ToString()          // ERROR NSYS050
}
```

```text
── [NSYS050] ERROR ────────────────────────── Program.nl:3:26 ──

    3 |     return value.ToString()          // ERROR NSYS050
      |                          ^^^^^^^^

unknown external call 'value.ToString' is not callable from [hot]

Systems policy '[hot]' rejected the 'unknownExternalCall' effect.

Hint: effect path: Digits

Suggestion: Add a compiler/HotSummary entry, make the callee [hot], or move this call behind a [boundary].
```

## Why is this reported?

`value.ToString()` is a fine call. The problem is that nothing in the project says what it costs:
on most types it allocates a string, on some it also boxes, and the `[hot]` contract is exactly
the promise that neither happens without being written down.

Three sources of knowledge can answer for a call, and this finding means all three came up empty:
the compiler's own BCL Hot Pack (`Span`, `MemoryMarshal`, `BinaryPrimitives`, `BitOperations`,
`Math`, the `Interlocked`/`Volatile` operations, and the pool rent/return pair), a sidecar
`HotSummary` file listed in `language.systems.hotSummaryFiles`, and a callee declared in your own
project — which the analyzer reads directly and summarises itself.

## How to fix it

Hand the hot path a value it can already read. Formatting is boundary work; a length is not:

```n#
[hot]
func Digits(text: string): int {
    return text.Length
}
```

The other two routes are to make the callee something the analyzer can see — a function in your
own project, which needs no summary at all — or to add a sidecar `HotSummary` entry for the
external method, which is an audited claim about someone else's code and carries its own
obligations ([NSYS150](./NSYS150.md)).

## The three arms, and the project setting

Which sentence you get depends on where the call is, and only the third arm consults
configuration:

- in `[hot]`: `unknown external call 'X' is not callable from [hot]` — an **error**, always;
- in `[boundary]`: `boundary external call 'X' reported for systems handoff review` — a
  **warning**, because a boundary is exactly where unknown work is supposed to live;
- anywhere else in a systems project: `unknown external call 'X' has no systems summary`, at the
  severity `language.systems.unknownExternalCalls` names — `error`, `warn` (the default), or
  `allow`, which reports nothing.

Setting `unknownExternalCalls: allow` silences cold code and changes nothing in `[hot]`: the first
arm never reaches the setting.

## Related

- [NSYS150](./NSYS150.md) — a sidecar summary that cannot be audited for drift.
- [NSYS040](./NSYS040.md) — a call the analyzer *did* classify, as runtime dispatch.
- [NSYS140](./NSYS140.md) — a threading primitive with no modelled semantics.
- [Systems Programming](../systems.md) — the BCL Hot Pack and `HotSummary` sidecars.
