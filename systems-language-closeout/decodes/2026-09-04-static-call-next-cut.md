# Static-call ownership: next cut at 5ac4faa79

Read-only source decode for task 022/2f-b2. No implementation, build, or deletion verdict is claimed.

The inherited assertion that the static-call chain is not routed through N# is false at this base.
`ColumnarIlEmitter.TryEmitStaticCall` (lines 13591–14455) already invokes
`TryEmitPlannedExternalCall` at 13625. Its 865 lines include source-static dispatch, which is not part
of an external-call-only deletion. The external fallback at 13629–14450 contains 63 top-level
conditions. `ColumnarDirectCallPlanner` (814–860) separately tries `GetStaticCallPlan` and then scoped
ordinary runtime selection. The former is a closed contract table; the latter is the general resolver.

## Candidate: trailing null-reference optional parameters

Reuse `ColumnarOrdinaryRuntimeDirectCallResolver.ResolveOptionalFill` (528) with `expectedStatic=true`
and `ColumnarDirectCallPlanner.AppendOptionalFillRuntimeSelection` (1075). The latter already emits
static calls, but their production pairing is currently reached only for instance calls (980).
Keep exact-arity selection first and terminal `OwnedRejected` terminal.

This capability targets two C# branches at 14191–14210:

| Overload | Existing lowering |
|---|---|
| `ArgumentNullException.ThrowIfNull(Object, String): Void` | explicit argument, optional boxing, `ldnull`, `call` |
| `ArgumentException.ThrowIfNullOrWhiteSpace(String, String): Void` | explicit argument, `ldnull`, `call` |

Do not synthesize CallerArgumentExpression text in an ownership move; the existing emitted default
is null. `Directory.CreateTempSubdirectory()` is an independent catalog-backed positive case with
an existing resolver-only contract in `ColumnarExtensionMethodResolver.tests.nl` (231).

`ColumnarExtensionMethodResolver.DefaultIsNullReference` (574) reads `DefaultValue` and catches
failure. The task-022 capability-floor evidence identifies that getter as unavailable on MLC
parameters; use and contract the raw metadata default. Preserve guards for optional reference
parameters and exclusions of byref, pointer, value-type and generic-parameter defaults. Current
product selection returns runtime types; this is preparation of the shared owner for the metadata
universe, not a claim that current emitted calls already use MLC MethodInfos.

## Required evidence before deleting either branch

- Both helpers execute successfully and throw as expected; emitted signatures, null defaults,
  boxing and one-time argument evaluation are pinned independently.
- An ordinary static optional-null call executes through the product; temporary directories are
  cleaned up. Deterministic fixtures cover exact-arity precedence, ambiguity, required arguments,
  non-null reference defaults and value-type defaults.
- Runtime and MLC parameter metadata agree on the admitted raw-null-default shape.
- Source types with the same names win over external types, including a source owner with a missing
  member; aliases and lexical shadows keep their current behavior.
- Contextual-lambda frames and unplannable nested arguments remain supported where they are supported
  today. The frame escape at `ColumnarDirectCallPlanner:155` can yield the whole subtree. A green
  direct-call probe does not prove these contexts, so the 20-line deletion remains conditional.
- Control-first emitted-byte comparison and focused native execution precede integration gating.

## Remaining dependencies in the larger fallback

Generic/byref calls include Interlocked, generic JSON serialization and Array operations.
Argument expansion and non-null defaults include asynchronous File APIs, JsonDocument and Task
calls. Buffer.MemoryCopy delegates to span-pointer syntax rewriting at 13541–13589; replacing that
with a reflected pointer call would change behavior. Source TypeBuilder identities, generic closures,
numeric/reference/boxing conversions and source-name precedence must remain intact throughout.

The writer has exclusive emitter ownership during S2.1(g). This decode does not authorize concurrent
edits to that file or claim the optional-argument candidate has passed its contextual tests.
