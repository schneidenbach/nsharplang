---
sidebar_label: NSYS150
title: "NSYS150: a sidecar summary that cannot be audited for drift"
---

# NSYS150: a sidecar summary that cannot be audited for drift

A sidecar `HotSummary` is a claim about somebody else's compiled code: "this method does not
allocate, does not box, is trim-safe." N# will act on that claim, but only if it can tell later
whether the code it describes has changed. A sidecar entry keyed to neither a body identity nor a
package version cannot be audited for drift, so the profile refuses it rather than trusting a fact
with no way to expire.

The systems analyzer only runs when the project asks for it, and a sidecar is only read when the
project lists it. Here is the project that produced the diagnostic below:

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
    allowHotSidecars: true
    hotSummaryFiles:
      - hot-summaries.json
```

`hotSummaryFiles` entries are resolved relative to the project root unless they are absolute, so
this one sits beside `project.yml`:

```json title="hot-summaries.json"
{
  "schemaVersion": 1,
  "entries": [
    {
      "schemaVersion": 1,
      "assemblyIdentity": "System.Private.CoreLib",
      "targetFramework": "*",
      "method": "Convert.ToInt32",
      "source": "sidecar",
      "effects": {
        "aotSafe": true,
        "trimSafe": true
      }
    }
  ]
}
```

```n#
import System

[hot]
func Parse(text: string): int {
    return Convert.ToInt32(text)          // ERROR NSYS150
}
```

```text
── [NSYS150] ERROR ────────────────────────── Program.nl:5:27 ──

    5 |     return Convert.ToInt32(text)          // ERROR NSYS150
      |                           ^^^^^^^

sidecar HotSummary for 'Convert.ToInt32' is missing body identity or package version, so per-fact drift cannot be audited

Systems policy '[hot]' rejected the 'effectDrift' effect.

Hint: effect path: Parse

Suggestion: Key sidecar facts by MVID/body hash, source hash, or package version plus metadata identity.
```

## Why is this reported?

The entry says `Convert.ToInt32` is AOT-safe and trim-safe, and the analyzer would happily let a
`[hot]` function call it on that basis. But the entry does not say *which* `Convert.ToInt32` — no
MVID, no body hash, no source hash, no package version. Six months and one dependency bump later,
the method has a different body and the file still says the same thing, and nothing in the build
can notice.

Effect drift is the failure this code exists to prevent: a callee that quietly gains a cost its
hot caller was relying on it not having. A summary you cannot key to a version is a summary that
cannot drift *detectably*, which is worse than no summary at all — the build stays green while the
claim rots.

## How to fix it

Key the entry. Either a body identity or a package version is enough, and both is better:

```json
{
  "schemaVersion": 1,
  "entries": [
    {
      "schemaVersion": 1,
      "assemblyIdentity": "System.Private.CoreLib",
      "targetFramework": "*",
      "method": "Convert.ToInt32",
      "source": "sidecar",
      "packageVersion": "10.0.0",
      "bodyIdentity": "mvid:9f2c1c1e-0b7a-4b16-9a4e-1d2f6c0a55e1",
      "effects": {
        "aotSafe": true,
        "trimSafe": true
      }
    }
  ]
}
```

With those fields present, the call is accepted and the project reports nothing.

The alternative is not to rely on the sidecar: move the call behind a `[boundary]` and hand the
hot path a value. The finding is still raised there, but as a warning for review rather than a
build-blocking error.

## The two gates, in order

A sidecar passes through two checks before any of its effect facts are read, and the first one
answers conclusively:

1. **May a sidecar satisfy `[hot]` at all?** Only if `language.systems.allowHotSidecars` is `true`.
   With it `false` — the default — the same program above reports [NSYS050](./NSYS050.md) instead:
   `sidecar HotSummary for 'Convert.ToInt32' is not allowed to satisfy [hot] by project policy`.
   Turn it on only after auditing the sidecar's identity and body hash.
2. **Can this entry be audited for drift?** That is this rule.

An entry that fails either gate contributes exactly one fact to its caller — that it reached an
unknown external call. None of its other claims travel, because the claims of an entry that failed
a gate are precisely the ones that cannot be trusted.

Neither gate applies to the compiler's own BCL Hot Pack. That is not a sidecar, and it always
passes.

## Related

- [NSYS050](./NSYS050.md) — the first gate's finding, and what happens with no summary at all.
- [NSYS060](./NSYS060.md) — the AOT and trim facts a summary is claiming.
- [Systems Programming](../systems.md) — `HotSummary` sidecars and the effect model.
