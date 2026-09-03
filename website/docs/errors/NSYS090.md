---
sidebar_label: NSYS090
title: "NSYS090: a disposable resource is never disposed"
---

# NSYS090: a disposable resource is never disposed

A local that opens a file handle, a socket or a stream owns something the runtime will not take
back on its own. Systems N# tracks each such local through the body and reports the ones that
reach the end of the function still open — not as a style note, but because a leaked handle is a
correctness bug at any temperature, which is why this one is an error even in cold code.

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
import System.IO

func Open(path: string): bool {
    stream := alloc new FileStream(path, FileMode.Open)          // ERROR NSYS090
    return stream != null
}
```

```text
── [NSYS090] ERROR ─────────────────────────── Program.nl:4:5 ──

    4 |     stream := alloc new FileStream(path, FileMode.Open)          // ERROR NSYS090
      |     ^^^^^^

disposable resource 'stream' created as FileStream is not disposed on an obvious lexical path

Systems policy 'systems:strict' rejected the 'resource' effect.

Hint: effect path: Open

Suggestion: Use `using`, call Dispose/DisposeAsync in a finally block, or return/transfer through an explicit owner once ownership is modeled.
```

## Why is this reported?

The message names the **kind** — `created as FileStream` — because "is not disposed" is only
actionable once you know which line opened it. The analyzer recognises fourteen disposable types
by simple name (`FileStream`, `StreamReader`, `StreamWriter`, `BinaryReader`, `BinaryWriter`,
`TextReader`, `TextWriter`, `MemoryStream`, `Socket`, `TcpClient`, `UdpClient`, `HttpClient`,
`SemaphoreSlim`, `CancellationTokenSource`) and the four `File` factories (`File.Open`,
`File.OpenRead`, `File.OpenWrite`, `File.Create`).

Note that `alloc` does not change the answer. Spelling the allocation says something about the
heap, not about ownership, so the rule looks straight through the keyword.

## How to fix it

Close it on a path the analyzer can see:

```n#
import System.IO

func Open(path: string) {
    stream := alloc new FileStream(path, FileMode.Open)
    stream.Dispose()
}
```

`using`, or a `Dispose`/`DisposeAsync` in a `finally`, work the same way. Note that `try`/`finally`
is itself exception control flow, which a systems path reports as [NSYS120](./NSYS120.md) — so in
practice resource handling belongs in a `[boundary]`, where that finding is a warning for review.

## "An obvious lexical path" is a deliberate promise

The check is lexical and conservative, and the sentence says so rather than claiming your code is
wrong. A buffer handed to a helper that disposes it *is* reported here, because the analyzer does
not model ownership transfer across function boundaries in this version. That is the reason the
suggestion names the shapes it can see instead of telling you to fix a bug.

A `[hot]` function may not open a resource at all — a `using`, an `await foreach` or a
constructor call reports there whether or not anything is disposed later, alongside the
allocation and readiness findings the same line earns.

## Related

- [NSYS130](./NSYS130.md) — the same ledger for pooled buffers, where the imbalance is a warning.
- [NSYS120](./NSYS120.md) — why `try`/`finally` is itself reported on a systems path.
- [Systems Programming](../systems.md) — pooling and the `[boundary]` seam.
