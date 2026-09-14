# S2.2(g0): exact generic enumerator protocol storage

Implementation baseline: `70a84bc7270c98bbbbd2f33a56b2af1c464242ec`. This prerequisite admits
one builder-bound protocol handle needed by the source-definition discovery owner: the exact BCL
`IEnumerator<T>` closed over an element already accepted by the collection element policy.

## Boundary and implementation

`ColumnarTypeOfPlanner.IsSupportedType` now checks `IsSupportedEnumeratorType` only inside its
existing builder-bound branch and only after the existing collection, task, result and anonymous
union checks. The new predicate requires a constructed generic whose definition has the exact BCL
`IEnumerator<>` assembly-qualified identity, has one argument, and whose argument satisfies the
existing `IsAdmissibleCollectionElement` rule. `IsSupportedCollectionType` is unchanged, so this does
not make an enumerator a collection expression or a `for` source.

The canonical contract admits source class and source value-type elements, rejects a closed source
generic element already outside the collection-element policy, rejects the open definition, and
rejects a baked foreign type with the same full name from another assembly. Existing successful
type-family checks keep their prior short-circuit and reflection order.

The pinned compiler cannot lower `typeof(IEnumerator<int>)` as a local initializer in this kernel;
both chained and split spellings declined. The implementation therefore follows the existing
required-definition kernel pattern with `Type.GetType`, then verifies the returned definition through
`ExternalAssemblyScan.HasExactTypeIdentity`. This adds one narrow runtime type lookup. Removing such
lookups across runtime and metadata universes remains part of the already-open metadata-universe
closeout rather than this storage prerequisite.

## Consumed proof and focused evidence

The external `ProtocolRow` differential uses the same source with the immutable pre compiler and the
fresh compiler built from this change. The pre compiler declines the inferred local as unsupported
`IEnumerator<ProtocolRow>` storage. The fresh compiler passes the test, and its emitted IL stores
`IEnumerator<ProtocolRow>` and calls that exact constructed interface's `get_Current`; it does not
widen `Current` to `object`. The same shape is retained as
`EnumeratorProtocolStorage.tests.nl` for rebuilt-compiler gates.

| Check | Result | Raw evidence |
|---|---|---|
| `./scripts/dev.sh Columnar` on final formatted source | **12 passed, 0 failed** | `/private/tmp/nsharp-s22g-executor-logs/seed-postformat/dev.stdout` |
| BootstrapServices estate with tests forced on | **7,757 passed, 0 failed** | `/private/tmp/nsharp-s22g-executor-logs/seed-postformat/test.stdout` |
| Immutable-pre `ProtocolRow` source loop | **declined before execution** at `emit.local.unsupported-type` | `/private/tmp/nsharp-s22g-executor-logs/seed-protocol-loop-1/pre-traced.stderr` |
| Fresh-compiler identical `ProtocolRow` source loop | **1 passed, 0 failed** | `/private/tmp/nsharp-s22g-executor-logs/seed-protocol-loop-1/post-postformat.stdout` |
| Fresh-compiler durable native contract | **1 passed, 0 failed** | `/private/tmp/nsharp-s22g-executor-logs/seed-native/test.stdout` |
| N# formatter over the three owned N# files | Exit 0 | `/private/tmp/nsharp-s22g-executor-logs/seed-format/check-final.stdout` |
| `git diff --check` | Exit 0 | Reproducible on this diff |

The frozen differential source is SHA-256 `6929fb095e5487af21da226ba3d71249e13fc69500a476a7a7dc5e1e0965ec79`.
The immutable pre CLI is `978b6d90a2b19179337613632d48549eede0450d165a7557edf60cdd1a83673b`;
the final worker CLI is `91528724f81f6d217ac4e99b060fbfee6e21bc3c7aa3a83b8c1207ca2515aaee`.
The emitted proof DLL is `a891aa86af0ffef854f0c7e83055a172d24f94158985e6407c703c1fdcb80e07`,
and its IL text is `202eb39353ca0702ffe5a26987e1a45b94385cfc15ce3731ed9cccd51d26c164`.

The coordinator owns the fresh prerequisite gate, local compiler seed provenance, and continuation of
S2.2(g) from that accepted compiler. The worker evidence ends before the coordinator gate and seed repin; the
[integration proof](2026-09-05-s22g0-parity-proof.md) identifies their actual receipts. Discovery routing
remains at the next cursor.
