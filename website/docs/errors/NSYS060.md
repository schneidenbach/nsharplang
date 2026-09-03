---
sidebar_label: NSYS060
title: "NSYS060: the call blocks AOT and trimming facts"
---

# NSYS060: the call blocks AOT and trimming facts

With `aotTarget` set, a systems project is making a claim about publishing: that every symbol it
reaches survives trimming and needs no code generated at run time. `typeof`, reflection and
runtime code generation break that claim — they reach metadata a trimmer would otherwise remove —
so the analyzer reports them under the AOT policy, and an `NSYS060` left at error severity is what
turns the report's AOT analysis from `pass` to `fail`.

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
func NameOfInt(): string {
    marker := typeof(int)          // ERROR NSYS060
    return marker.Name
}
```

```text
── [NSYS060] ERROR ────────────────────────── Program.nl:2:15 ──

    2 |     marker := typeof(int)          // ERROR NSYS060
      |               ^

typeof requires metadata and may block trimming/AOT facts

Systems policy 'systems:strict' rejected the 'aot' effect.

Hint: effect path: NameOfInt

Suggestion: Move reflection to a [boundary] or add an audited target-qualified summary.
```

## Why is this reported?

`typeof(int)` looks free, and at run time it nearly is. The cost is at publish time: the type's
metadata must be kept, and a trimmer that cannot see the use must keep more than that. The finding
wears the `aot` effect rather than a "reflection" one for exactly this reason — what it costs is
the target-qualified AOT fact, not a cycle count.

The same policy covers calls that construct types or instantiate generics at run time, and any
`HotSummary` that declares itself not AOT- or trim-safe for the `aotTarget` you configured. The
target is part of the question: a summary can be safe for `coreclr` and not for `nativeaot`.

## How to fix it

Reflection at startup is ordinary. Say so, narrowly, with a reason and an owner that survive code
review:

```n#
func NameOfInt(): string {
    allow(aot, reason: "startup diagnostics only", owner: "runtime-core") {
        marker := typeof(int)
        return marker.Name
    }
}
```

The alternative is to move the metadata work behind a `[boundary]` and hand the systems code a
plain value — a name, an index, an enum — that carries no metadata dependency at all.

## Severity, and what publishing does with it

`NSYS060` is a policy finding: an error in `[hot]` and in ordinary systems-profile code, a warning
in a `[boundary]`, and silent under a matching `allow(aot, ...)`. `nlc publish --aot` runs the same
analysis and annotates `[RequiresUnreferencedCode]`/`[RequiresDynamicCode]` where appropriate.

AOT support in this version is a **readiness gate, not a native-image producer**: `nlc publish
--aot` verifies the facts and still emits a framework-dependent assembly.

## Related

- [NSYS050](./NSYS050.md) — a call with no cost summary at all.
- [NSYS150](./NSYS150.md) — auditing the sidecar summaries these facts come from.
- [Systems Programming](../systems.md) — AOT and trimming.
