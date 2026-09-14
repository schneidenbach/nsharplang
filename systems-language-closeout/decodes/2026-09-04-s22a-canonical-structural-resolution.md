# S2.2(a): canonical resolution and a consumed structural type reference

Subsequent correction (S2.2(b), `4b592311`): this slice's input-snapshot tests did not establish
emitted backing-storage immutability. Getter-only rows still exposed mutable fields and arrays.
The [S2.2(b) implementation](2026-09-05-s22b-source-interface-member-resolution.md) adds readonly
fields, copied BCL read-only storage and three controls that fail on the earlier representation.
The original S2.2(a) parity and execution receipts below remain historical evidence for that revision.

Implementation baseline: `665b1068ad6905b4de3fc98efdf6f404e454c525`. This first S2.2 cut moves
the connected ordinary, generic-aware, closed-source-generic and delegate canonical resolver into
N#. Resolution now produces an emission-scoped structural reference beside its exact runtime `Type`,
and the existing `typeof` plan path carries that pair through `AddType` to the executor's `ldtoken`
operation.

## Canonical resolution ownership

`ColumnarCanonicalTypeResolver` owns the former host policy and its recursive dependency closure.
The public ordinary, generic-aware and member entry points return their existing boolean and `Type`
contracts, but successful paths obtain the runtime handle from an N# selected structural reference.
The exact resolver cache likewise stores the selected reference rather than a detached `Type`.

The port preserves the original order and distinctions rather than normalizing similar shapes:

- exact semantic selection still precedes manual shape interpretation, and `Claimed` remains
  terminal;
- the supplied generic map is consulted only after exact scope selection;
- ordinary and generic-aware collection predicates remain different, including their source-builder
  restrictions;
- named tuples retain their original unchecked construction result while explicit `ValueTuple` uses
  the existing support predicate;
- source generic arity is checked at the original phase, delegate returns resolve before parameters,
  and array, byref, nullable, union and shadowing fences retain their old order;
- the two false outcomes that intentionally retain a non-null runtime `Type` use
  `RejectedWithRuntime`. They do not acquire an admissible key and are not normalized to null; and
- exact runtime-name resolution remains a direct `Type.GetType` operation. The separate existing
  `TryResolveLoadedExternalType` assembly scan remains in C# for its ASP.NET caller.

The host now calls the N# owner directly. Thirteen C# method definitions are deleted:
`TryResolveTypeWithTypeParams`, `TryResolveType`, `TryResolveClosedUserGeneric`,
`TryResolveDelegateCanonical`, `TryResolveMemberType`, `TryResolveExactRuntimeType`,
`TryResolveBuiltin`, `TryResolveBclExceptionType`, `UnqualifyGenericHead`,
`IsCollectionHeadShadowedByUserType`, `IsSupportedByRefElementType`,
`IsOpenGenericUnionDefinition` and `ShouldPreserveSemanticGenericHead`. No replacement C# method,
policy branch, callback, adapter or replayer was added.

## Structural identity and lifetime

Each `ColumnarSemanticTypeResolutionCatalog` constructs a fresh
`ColumnarStructuralTypeReferenceTable`. Re-emitting the same parsed `ColumnarProgramInput` therefore
gets a different reference-identity token; an old selection and an old code-plan pool entry remain
bound to the first table after the second catalog exists. Per-file and per-owner catalog views share
the one table for their emission through explicit constructor and binding arguments. There is no
ambient or process-wide `Type` lookup.

Immutable keys distinguish signature primitives, source definitions, external named definitions,
constructed generics, SZ arrays, byrefs, type generic parameters, method generic parameters and
synthesized definitions. Composite children retain declaration/argument order. External identity
contains the exact assembly name, namespace, ordered containing/nested names and value/reference
shape. Primitive identity requires the exact core-library assembly; `decimal`, `DateTime`, `Index`
and `Range` remain external named value types rather than signature primitives.

Source keys use exact declared names plus the emission token. Generic parameters also retain source
file, owner family, declared type or member identity, member ordinal and parameter ordinal.
Registration occurs where the declaration is created: catalog source definitions, source methods,
union cases, iterator machines and other synthesized types. Persisted Reflection.Emit method
parameters are classified with `IsGenericMethodParameter`/`IsGenericTypeParameter`; their
`DeclaringMethod` is null on the measured runtime implementation. No unbaked method signature,
metadata token or assembly-qualified builder name is used to recover ownership.

String-backed source enums intentionally select the CLR `string` primitive key. Their source name
and emission token remain separate provenance, so two erased enums share signature identity without
becoming the same declaration. Supplied provenance validates only when both token and name are
present, the token is the selected table, and the registered source name maps to the same runtime
handle. Synthesized stable names cannot be forged as source provenance. Constructors copy child and
nested-name arrays, reject null identity parts, and recursive validation rejects malformed kind,
shape, owner, child and runtime pairs.

## Consumed `typeof` pair and pool lifecycle

`ColumnarTypeOfPlanner` keeps its original binding-scope resolver and its actual supplied bindings;
the canonical resolver is not substituted for that scope. Once the scope selects its runtime type,
the planner captures the matching structural key and source provenance through the same catalog
table, then calls the keyed `ColumnarCodePlan.AddType` overload. The executor calls
`ValidatedTypeAt` before emitting the existing `ldtoken`, so the structural key is a required input
to this production operation rather than a write-only description.

Keyed and legacy additions both overwrite the structural companion columns. Capacity growth copies
all three columns, while checkpoint rollback and reset retain the existing count-only semantics
without allowing a later legacy append to reuse stale metadata. Both v3 and v4 execution validate
the complete type pool before an opcode or local is emitted. Duplicate runtime handles still append
duplicate slots. The code-plan pool has 36 production calls across 12 files: this slice keys the one
`typeof` call, while the other **35** `AddType(Type)` calls remain explicitly handle-only. Of those,
34 are external planner calls and one is the plan-local mirror copy inside `ColumnarCodePlan`.
Converting those consumers is later S2.2 work.

## Measured bootstrap and fixture spellings

Before the product port, a package-SDK stage-0 program exercised the combined surface: generic
registry lookup with `out`, recursive result/key arrays, runtime and Reflection.Emit types,
`MakeGenericType`, array and byref construction, assembly/nesting identity, type and method generic
owners and ordinals, keyed and legacy pool rows, rollback, reused slots, capacity growth and pair
validation. It ran with exit 0 and printed
`True:True:2:4:5:90:11:6:Owner:7:Map:4`. The observed DLL SHA256 is
`ff979a8ad4fbd18476fc70eb7e3fbc9efde89ee1d576c3901aa7072cd411558c`; the SDK and compiler
package hashes, source, emitted IL and receipt are retained under
`/private/tmp/nsharp-s22a-executor-logs/stage0`.

A second isolated probe measured persisted generic-parameter ownership. It printed distinct public
VAR/MVAR flags while both persisted declaring-owner properties were null. Its source SHA256 is
`3719aad701f98fcef1a04b14b9061775418e167275ee7b4c6443d44ef59bea31` and its complete evidence is
under `/private/tmp/nsharp-s22a-executor-logs/gp-owner-probe`.

Fixture-only declines were narrowed without expanding product surface. Existing static fixture calls
now spell the new trailing nullable table as explicit `null`; object-array writes use the established
`ExecutorSetObject` helper; the admitted decimal spelling is `typeof(decimal)`; and nested selection,
key extraction and `Type` operands use named locals at the static-call boundary. The exact declined
expressions remain in `estate-structural-1.log`, `-2.log` and
`estate-structural-final-4.log` through `-8.log`. Those logs prove only the rejected expressions they
name; they do not establish a general void-helper or custom-return limitation.

## Focused contracts and evidence

The N# estate adds structural identity, canonical policy, source-provenance, generic-owner,
cross-emission lifetime, pool lifecycle and pre-IL validation contracts. Runtime and
MetadataLoadContext primitive handles converge; spoofed primitives, altered children, foreign or
partial provenance and foreign tables decline. Same-named external types from two assemblies stay
distinct, separately constructed source closures have equal structural shape, and runtime plus
persisted VAR/MVAR owners remain distinct. A reused-program contract stores the first selected row in
a code plan, creates a second catalog, then proves the first pool entry still validates only against
its original table.

Three source-level controls in the existing `columnar-emit-facts` project independently pin field,
return and parameter signatures; root, nested and body `typeof` loads; source aliases, arrays and
closed source generics; and type versus method generic owners. Both the immutable baseline CLI and
the changed CLI pass the exact 79-test project. A separate existing-project control pins collection
head shadowing against an imported BCL type. Iterator controls cover the new synthesized-owner and
replacement-VAR registration route.

| Check | Result | Raw evidence |
|---|---|---|
| Bootstrap-services N# estate | **7,703 passed, 0 failed** | `/private/tmp/nsharp-s22a-executor-logs/estate-structural-postformat-2.log` |
| `./scripts/dev.sh Columnar` | CLI build passed; **12 passed, 0 failed** | `/private/tmp/nsharp-s22a-executor-logs/dev-columnar-postformat-1.log` |
| Native columnar emit facts, baseline CLI | **79 passed, 0 failed** | `/private/tmp/nsharp-s22a-executor-logs/native-production-baseline-final.log` |
| Native columnar emit facts, changed CLI | **79 passed, 0 failed** | `/private/tmp/nsharp-s22a-executor-logs/native-production-postformat-1.log` |
| Native collection-shadow control | **1 passed, 0 failed** | `/private/tmp/nsharp-s22a-executor-logs/native-canonical-shadow-postformat-1.log` |
| Native iterators | **25 passed, 0 failed** | `/private/tmp/nsharp-s22a-executor-logs/native-iterators-postformat-1.log` |
| Unchanged canonical/leaf probes on early immutable candidate | **81 expected cases passed** | `/private/tmp/nsharp-023-s22a-proof-20260904/early-candidate-1` |

The final strict walk uses the immutable baseline CLI and the changed CLI against the same edited
`src/NSharpLang.Compiler.BootstrapServices` tree. Both report **427 checked files, 259 errors and 0
warnings** with expected exit 1; stdout JSON is byte-identical at SHA256
`ed9b29010436aab6fb59b04f41930eaee386fed09117c791dc0907c582cecfe8`, and stderr is empty.
Baseline source to edited source retains the same 259 sites. The final mapping has 26 line shifts:
12 in BindingScope, seven in CodePlanExecutor, six in SemanticTypeRegistry and one in TypeOfPlanner.
Three BindingScope NL412 explanations also contain the shifted line number; two RangeIndexPlanner
NL402 snippets/hints show the explicit added table argument and corresponding arities. The final
raw files are `/private/tmp/nsharp-s22a-executor-logs/strict-postformat-{pre,post}.json`; the complete
baseline-to-edited mapping is
`/private/tmp/nsharp-023-s22a-proof-20260904/final-controls-77686382de9e/strict-comparison.json`.

`ColumnarIlEmitter.cs` decreases from **20,688 / 19,677 / 1,074,830** total lines, nonblank lines and
bytes to **19,629 / 18,637 / 1,021,506**. Its final SHA256 is
`1fa0b1b50bca2964f955cf038ac82605ee508a3cdd49ec46b1ed13f000d0493c`. Root formatter and diff
checks pass; the formatter receipt is `/private/tmp/nsharp-s22a-executor-logs/root-format-final-2.log`.

The coordinator owns the committed fixed-corpus parity replay, final 81-case differential replay,
ownership-ratchet repin, fresh backend gate and push. This slice does not publish an SDK. The 35
handle-only type-pool callers, loaded external-reference probing, remaining signature/member
descriptors, metadata writer work and the rest of S2.2 remain open.
