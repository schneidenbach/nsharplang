# S2.2(g): source-definition discovery

Implementation baseline: `1e3d8cbfc130cad4528d98609e97492122f94d4c`. This slice makes N#
the sole owner of the first-hit source-definition discovery family used by declaration attachment,
generic constraints, closed receivers and constrained source calls.

## Discovery ownership and phase order

`ColumnarSourceDefinitionResolver` compares each live registry row's `Builder` with the requested
handle through CLR `Type` equality and returns the first match in enumeration order. It keeps the
three bool/out contracts distinct. Struct discovery forwards its caller's out slot and leaves the
direct TypeBuilder scan outside the reflection catches. Interface discovery uses a local candidate,
then checks the first winner's `IsInterface` flag. Closed-receiver discovery clears both outputs,
performs the existing closed-source guard and second generic-definition read, assigns the winning
definition, and only then reads and assigns the receiver's generic arguments.

Enumeration uses the exact inferred `IEnumerator<ColumnarStructDef>` for `Current`, the inherited
nongeneric `IEnumerator` for movement, and `IDisposable` in an explicit `finally`. Enumerator
acquisition remains before the protected region. A hit writes the caller's out slot before disposal;
a completed miss clears it only after successful disposal. The closed receiver keeps its definition
and argument writes inside iteration before disposal.

The direct-type and closed-receiver entry points accept the existing
`IReadOnlyDictionary<string, ColumnarStructDef>` registry. They read `Values` only after the original
TypeBuilder or closed-source guards, output initialization, and generic-head reads. This preserves
the host's property-access and exception order even for malformed registry implementations.

## Bootstrap prerequisites and measured limits

The accepted g0 checkpoint admitted only the exact BCL `IEnumerator<T>` protocol closed over an
already-admissible builder-bound element. This lets the resolver retain the generic
`IEnumerator<ColumnarStructDef>.Current` slot without widening it to `object`; it did not change
collection or `for` admission.

The pinned compiler could not resolve `System.Array.Empty<System.Type>()`, and both direct and typed
`System.Type.EmptyTypes` field reads initially declined. The connected g1 prerequisite added the
exact external static field plan for `Type.EmptyTypes`. The closed receiver now stores that BCL field
value before its guard, preserving the same shared array object returned by `Array.Empty<Type>()`.
No private singleton or runtime reflection substitute remains.

A bare N# `for` loop is not used: its current lowering does not place disposal in a protected
finally. A test-only iterator with `yield` inside `try/finally` also declined at the measured
unsupported iterator-body shape, so the post-hit disposal-failure contract uses a bounded
Reflection.Emit fixture instead. Its generic `Current` returns the real definition, its nongeneric
`Current` returns a deliberately different object, and its `Dispose` throws. This independently
pins exact slot selection and the difference between the struct resolver's forwarded out slot and
the interface resolver's local candidate.

The first generator-state draft inspected the enumerable object returned by the iterator factory.
The generated `GetEnumerator` clone contract means that object is not the machine the resolver
consumed. The final fixture emits a small enumerable wrapper that returns a pre-captured exact
`IEnumerator<ColumnarStructDef>`; hit, miss and throwing `MoveNext` tests therefore inspect the
actual disposed machine. A typed static test runner, invoked through the existing reflection test
helper, crosses the baked fixture's `object` boundary while keeping every resolver call and `out`
argument direct inside the runner. A false-`MoveNext`, throwing-`Dispose` case separately proves
that a disposal failure on a miss preserves the caller's sentinel before the post-loop null write.

## Host reduction and remaining boundary

The C# host deletes `TryResolveUserInterfaceDef`, `TryResolveUserStructDef` and
`TryFindDefByBuilder`. The three retained private adapters are one-expression forwards, the four
interface sites call N# directly at their existing phases, and the duplicate inline field lookup
uses the same first-hit owner. No callback, fallback, catch or new C# branch was added.

The general-call loop that combines registry iteration with per-row member selection remains. It can
continue after an earlier duplicate definition fails member selection, so replacing it with this
pure first-hit finder would change policy. Closed-interface call argument admission also remains
with that connected later slice.

## Focused evidence

The final source passed:

- `./scripts/dev.sh Columnar`: 12/12 focused host tests.
- forced test-enabled restore, then the source-definition filter: 7/7 (six new timing/phase
  contracts and one existing source-identity contract).
- the complete BootstrapServices estate: 7,765/7,765.
- `tests/native/columnar-emit-facts`: 105/105 with the rebuilt worker CLI.
- N# formatter check and `git diff --check`.

The host change is eight added and 115 deleted lines: 107 fewer total lines, 98 fewer nonblank
lines, and 2,646 fewer bytes in `ColumnarIlEmitter.cs`. Exact command output, source hashes and the
handoff receipt are under `/private/tmp/nsharp-s22g-executor-logs`. The coordinator owns immutable
exact-source corpus replay, strict diagnostic mapping, physical metadata parity, ownership
ratchets, the final backend gate and push.

## Integration strict correction

Root's initial immutable replay at `de83c4197` matched the entire emitted corpus, but strict checking
reported two new NL011 errors for empty generic-definition catch bodies. Both compilers agreed on
those findings. Correction `096968ae7` (worker `bafce7640`) makes each caught NotSupportedException or
NotImplementedException explicitly clear the output and return false, the same result previously
reached at the common tail after cleanup. No catch boundary or direct-scan behavior changes.
Focused 7/7 and dev Columnar 12/12 pass. The corrected source SHA256 is
`2b569fdaa21d11594f5a41182901b869340a8a7170e543cdb284848d40ea57a9`.
Final immutable strict checking returns to 259 inherited errors, zero warnings, across 433 files;
identical final-source pre/final JSON and unchanged-line mapping are retained. See the integration
proof for the separate combined-source gate, independent controls, mutation and final review.
