# S2.2(f): base-method bindings and ordinary declaration realization

Implementation baseline: `18d112ce39205298327292e7d5bf05161d9e756e`. This slice carries a
successful base override lookup as an emission-scoped structural binding and moves the ordinary
method's final `DefineMethod` call into its N# completion row.

## Deriving lookup and binding ownership

`ColumnarBaseMethodMatch` is the single owner of the established base policy. It preserves the null
base fallback to `System.Object`, the derived-to-ancestor walk, `DeclaredOnly` enumeration, the
TypeBuilder skip and reflection catches, the public virtual/non-final/non-generic filter, and the
signature read order of arity before return and parameters left to right. Type identity remains
reference equality followed by two assembly-qualified-name reads. The existing bool/out resolver and
its two public policy probes are thin forwards to this owner.

A successful match retains the actual ancestor that supplied the winner, its exact `MethodInfo`, the
observed return `Type`, and copied ordered `ParameterInfo`/`Type` pairs. Losing attempts select no
structural identity. `ColumnarBaseMethodBinding` accepts only that derived match and the consuming
table; it cannot certify a caller-supplied target or signature.

The neutral `ColumnarExternalMethodDescriptor` has a base-specific deriving constructor. It recovers
the authoritative open MethodDef from the winning declaring definition by module MVID and metadata
token, then captures open/effective signature and modifier identities with independent runtime
companions. When the recovered open method is the exact winner, it reuses the match's observed return
and parameter snapshots rather than repeating those signature reads. Closed generic ancestors retain
their open VAR-bearing signature and exact closed declaring context. All new fields are `readonly`,
and ordered rows use copied `List<T>.AsReadOnly()` storage.

`ColumnarResolvedMethodOverride` now carries the base binding through the same completion domain as
the source and external bindings. `Apply` validates every binding against the caller's emission table
before the first `DefineMethodOverride`. Bare-handle rows remain for the existing direct/source/base
compatibility surfaces; the production base route always supplies the structural binding.

## Declaration realization and phase order

The product completion now receives both names that already existed at different phases: the row's
`MemberName` still selects and diagnoses the base slot, while the current host declaration's `m.Name`
is captured for realization. It copies the already-resolved return and ordered parameter handles and
exposes `DefineMethod(owner)`. An ordinary nonoverride completion does not select those handles into
the structural table.

The C# host still performs return/parameter resolution and interface matching first, calls Complete,
checks the located decline, asks the completion to define the method, emits existing parameter and
default metadata, applies overrides, and only then registers jobs. No callback, fallback, catch or new
C# helper was added. The old three-argument Complete surface still produces handle-only rows and does
not perform the later modifier/open-definition reads.

The new structural production path can reject malformed successfully matched reflection facts while
constructing the binding, before method declaration. This is a descriptor-integrity boundary; no
claim is made that arbitrary hostile `MethodInfo` implementations retain their earlier downstream
failure. The legacy lookup path retains its original short-circuit and catch behavior.

## Measured bootstrap boundary and focused evidence

The consumed all-N# probe at
`/private/tmp/nsharp-s22f-executor-logs/stage0-base-capture-1` covers runtime and
`MetadataLoadContext` closed `Comparer<int>` winners, MethodDef recovery, return/parameter modifier
access, and the MethodBuilder returned by `DefineMethod`. The compiled probe does not inspect an
unbaked MethodBuilder signature; that unrelated getter still throws before its owner is baked.

Direct contracts cover the runtime and metadata closed-base forms, an actual ancestor winner, the
TypeBuilder skip, foreign tables, independently corrupted runtime companions, readonly storage,
base/source/external target order, and all-target validation before attachment. A runtime dispatch
witness proves a corrupt later base binding leaves an earlier raw target unattached, with a valid
structural base binding as the positive twin. Completion contracts retain a host name distinct from
the selected row name, a wrapped return handle, heterogeneous ordered parameters, copied input arrays,
all four attribute outcomes, exact missing-base decline data and ordinary no-selection behavior.

| Check | Result | Raw evidence |
|---|---|---|
| `./scripts/dev.sh Columnar` on final product source | **12 passed, 0 failed** | `/private/tmp/nsharp-s22f-executor-logs/dev-final-stable.log` |
| BootstrapServices estate on final formatted owned source | **7,749 passed, 0 failed** | `/private/tmp/nsharp-s22f-executor-logs/estate-final-stable.log` |
| Immutable baseline CLI check during implementation | **259 existing errors, no new findings** | `/private/tmp/nsharp-s22f-executor-logs/check-binding-initial.json` |
| N# formatter over all five owned N# files | Exit 0; formatted 0 files | `/private/tmp/nsharp-s22f-executor-logs/final-format/check-after.log` |
| `git diff --check` | Exit 0 | Reproducible on this diff |

`ColumnarIlEmitter.cs` decreases from **19,485 / 18,506 / 1,014,696** total lines,
nonblank lines and bytes to **19,484 / 18,505 / 1,014,658**. The exact delta is one line, one
nonblank line and 38 bytes. `DefineMethodParameterMetadata` and the remaining body/default policy stay
in their existing owners.

The coordinator owns immutable exact-source corpus replay, final strict-source mapping, physical
`MethodImpl` parity, ownership-ratchet and task/status documentation, the fresh backend gate and push.
This slice does not publish an SDK or run a product gate.
