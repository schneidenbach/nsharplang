---
sidebar_label: NSYS180
title: "NSYS180: a function-level allow with no reason"
---

# NSYS180: a function-level allow with no reason

A waiver is a promise that somebody has thought about a cost and accepted it. A function-level
`[allow(...)]` with no `reason` records the acceptance and loses the thinking, so Systems N#
refuses it: the whole value of writing waivers in source is that a reviewer can read why each one
is there.

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
[allow(alloc)]
func makeTable(): int {          // ERROR NSYS180
    return 1
}
```

```text
── [NSYS180] ERROR ─────────────────────────── Program.nl:2:1 ──

    2 | func makeTable(): int {          // ERROR NSYS180
      | ^^^^^^^^^

function-level [allow] requires a reason

Systems policy 'systems:strict' rejected the 'effectPolicy' effect.

Hint: effect path: makeTable

Suggestion: Prefer a narrow block-level allow(...), or add reason: "..." to the function-level policy.
```

## Why is this reported?

A function-level `[allow]` is the widest waiver the language has — it covers everything the
function does, including work added to it later by somebody who never saw the attribute. That is
the reason it must say why. The finding is reported at the **declaration** and underlines the
function's own name, because the thing that needs the justification is the declaration, not the
attribute.

## How to fix it

Write the reason, and — for anything a caller outside this file can reach — the owner:

```n#
[allow(alloc, reason: "one-time lookup table built at startup", owner: "runtime-core")]
func makeTable(): int {
    return 1
}
```

The suggestion offers a second, usually better fix: prefer a narrow **block-level** `allow(...)`
statement around the exact statements that need it. A block-level waiver covers what you wrote
inside it and nothing else, and it is not subject to this rule at all — `allow(alloc) { ... }`
with no reason reports nothing.

## The owner arm, and who counts as public

A **public** function needs an `owner` as well, so a waiver on a surface other code depends on has
a name attached to it:

```n#
[allow(alloc, reason: "one-time lookup table built at startup")]
public func MakeTable(): int {          // reports NSYS180: public function-level [allow] requires
    return 1                            //                an owner
}
```

"Public" here is wider than the `public` modifier: N# treats a PascalCase name as exported, so
`MakeTable` is public API and `makeTable` is not. A function-level `[allow]` missing both fields on
a public function reports **two** findings at the same position, one per missing field, because
they are two separate edits.

Both arms prefer error severity and neither consults an allow set — waiving the rule that makes a
waiver auditable would leave nothing behind. A `[boundary]` still downgrades them to warnings, as
it does every systems finding.

## Related

- [NSYS010](./NSYS010.md) — the allocation ban a `[allow(alloc)]` is usually waiving.
- [NSYS100](./NSYS100.md) — `[trusted]`, the waiver mechanism for `unsafe`, and its own audit fields.
- [Systems Programming](../systems.md) — `allow(...)` and the effect model.
