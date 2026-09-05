# S2.2(e): iterator declaration member bindings

Implementation baseline: `05d184c8335c0d6bee9d77d5d5ec83a3d01c8774`. This slice moves all
eleven iterator declaration target lookups into N#. Each declaration row now derives and consumes an
emission-scoped structural member binding at the row's existing override-attachment phase.

## Ownership and execution order

`ColumnarIteratorOverrideDeclaration` now owns the target kind as well as its ordinal, declaration
identity and mutable lookup name. Its `Apply` method constructs the binding from that row and the
exact host-created interface context, validates it against the consuming structural table, retains
`ResolvedBinding` and `ResolvedTarget`, and then calls `DefineMethodOverride`.

The C# host forwards one handle-only context for the synchronous machine and one for the asynchronous
machine. It no longer performs the five direct method lookups, two property/getter lookups or five
generic member rebindings. Each of the eleven calls remains immediately after its original
`DefineMethod`; its body plan still runs immediately after attachment. The async core body still runs
before the first async override. Factory-side and body-side iterator member resolution remain
unchanged, including the generic factory's distinct method-MVAR context.

`ColumnarIteratorMemberBinding` derives its target from its target kind, mutable lookup name and exact
context. It performs the original method or property/getter lookup, then performs the single shared
`ColumnarClosedGenericMemberResolver.ResolveMethod` rebind where required. Only after those operations
succeed does it read the authoritative open member signature and select structural facts. No caller
can provide an independent target or effective-signature certificate, and the rebound target is
never inspected for its return, parameters or return-parameter metadata.

The binding retains the exact target and open member; open declaring definition and effective
declaring context; MethodDef MVID/token/name/arity/calling/static facts; and open/effective return and
ordered parameter signature nodes. Open metadata types use `SelectExternalSignatureType`; effective
types use `SelectRuntimeType`, so a registered synthesized machine VAR remains distinct from both the
external interface VAR and the factory method MVAR. Every selected type has an independent runtime
`Type` companion. All retained fields are `readonly`, and parameter rows use an unaliased
`List<T>.AsReadOnly()` wrapper.

The owner-qualified structural substitution rules formerly nested in
`ColumnarExternalMethodDescriptor` now live in `ColumnarExternalMethodSignatureRelation`. The existing
external-interface descriptor calls that same owner without changing its reflected-winner discovery,
capture timing or validation policy.

## Measured phase boundaries

The frozen N# stage-0 probe is under
`/private/tmp/nsharp-s22e-executor-logs/stage0-known-open-member`. It proves method and
property/getter lookup plus `TypeBuilder.GetMethod` rebinding on runtime and persisted builders. On a
rebound builder method, `GetParameters` and `ReturnType` are readable, but the returned generic
parameter has a different owner from the exact machine VAR; `ReturnParameter` throws
`NotSupportedException`. The final binding therefore derives identity from the known open member and
exact context rather than reflecting a signature from the rebound target. The frozen source, DLL and
IL hashes are reviewed at `/private/tmp/nsharp-s22e-review/stage0-boundary/README.md`.

Direct contracts measure the malformed lookup phases. A missing direct method reaches the retained
`InvalidOperationException`; a missing property fails while dereferencing the getter; null lookup
names retain `ArgumentNullException`; and missing runtime or builder rebound methods retain the raw
`NullReferenceException` from the shared rebinder. None of those paths selects a structural row.
Changing a row's lookup name to an existing member with an incompatible signature now reaches
structural relation validation and is rejected before attachment. This is an explicit malformed-row
invariant boundary, rather than a claim that it has the old attachment failure. A valid binding is
still retained before `DefineMethodOverride`, proven with a body owned by a different builder.

## Focused evidence

| Check | Result | Raw evidence |
|---|---|---|
| Bootstrap-services N# estate on formatted source | **7,742 passed, 0 failed** | `/private/tmp/nsharp-s22e-executor-logs/estate-final-postformat-6.log` |
| `./scripts/dev.sh Columnar` | CLI build passed; **12 passed, 0 failed** | `/private/tmp/nsharp-s22e-executor-logs/dev-initial-5.log` |
| Frozen known-open-member N# stage-0 probe | Passed with consumed lookup/rebind/reflection assertions | `/private/tmp/nsharp-s22e-executor-logs/stage0-known-open-member/frozen-run.log` |
| Formatter check over all changed N# files | Exit 0; all files properly formatted | `/private/tmp/nsharp-s22e-executor-logs/final-format-2/check-after.log` |
| `git diff --check` | Exit 0 | Reproducible on this diff |

`ColumnarIlEmitter.cs` decreases from **19,492 / 18,513 / 1,015,879** total lines, nonblank lines and
bytes to **19,485 / 18,506 / 1,014,696**. Its SHA256 is
`e719f880830907953a7852debbb7448eb841ccc8d8999c0b95fe002c6620ff08`; the diff adds 15 lines and
deletes 22. The formatter changed only the new direct test file; pre/post hashes and output are under
`/private/tmp/nsharp-s22e-executor-logs/final-format-2`.

Base-method descriptors, body-side iterator member pools and the remaining handle-only type-pool
consumers remain later ownership work. This slice does not change source/external member selection or
publish an SDK. The coordinator owns immutable final-source corpus replay, strict-source mapping,
physical `MethodImpl` parity, ownership ratchets, the fresh integration gate and push.
