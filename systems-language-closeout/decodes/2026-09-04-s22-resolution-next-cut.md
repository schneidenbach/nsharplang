# S2.2 first ownership cut — read-only review, 2026-09-04

Baseline: **69ad857ba5766ff546f285bf6571731f5dfc192f** in `/Users/spencer/repos/nsharplang`. All source reads used
`git show`/`git grep` against that revision. S2.1(i) was in flight during this
review; the committed reconciliation below identifies what subsequently landed. No repository edits, builds,
SDK publication, test runs, corpus sweeps, or gates were performed for this review.

## Current boundary and census

Task 023 S2.2 names `ColumnarEmitPlan`; the actual owner is
`ColumnarCodePlan.nl`. `AddType(Type)` at line 881 appends a live handle to
`Types: Type[]`; it does not intern or retain structural references. There are
**36 production ColumnarCodePlan.AddType calls in 12 files** under BootstrapServices (tests and
comments excluded). The initial 37/13 name census also counted the unrelated
`ColumnarExtensionMethodResolver.AddType(index, candidateType)` helper. This correction
retains the internal `ColumnarCodePlan.AddType(planLocalMirrorTypes[i])` call that a
qualified-call-only search misses. Preserve append order: repeated types currently occupy
separate pool slots. The executor has 23 `plan.Types[...]` reads, including nine
explicit type-operand emission arms, local declarations, catches, and validation.

Exact C# emitter census, excluding definitions, comments, and string literals:

| name | actual calls | boundary |
|---|---:|---|
| `TryResolveType` | **56** | 34 inside the resolution-helper cluster, 22 outside |
| `TryResolveTypeWithTypeParams` | **30** | 19 inside that cluster, 11 outside |
| `TryResolveMemberType` | 6 | plus one definition with generic/non-generic selection |
| `TryResolveBodyType` | 14 | mechanical instance forwarding to the generic resolver |
| `TryResolveClosedUserGeneric` | 2 | one from each canonical resolver |
| `MakeGenericType` | **95** | whole emitter; many body/member-construction sites remain |
| `TryResolveBuiltin` | 4 | canonical resolution and three cast/type-discovery routes |
| `TryFindInterfaceMethod` | 2 | one production entry, one recursive call |
| `TryFindClosedInterfaceMethod` | 2 | one production entry, one recursive call |
| `ExternalInterfaceMethodMatches` | 2 | method declaration and completeness |
| `ClosedInterfaceMethodMatches` | 2 | target selection and completeness |
| `CloseInterfaceMemberType` | 7 | four external uses, three recursive uses |
| `DefineMethodOverride` | 14 | seven sync iterator, four async iterator, three ordinary |

The task's “57 TryResolveType sites” includes its definition; there are **86 actual
calls across the two canonical resolver names**, not 57 resolution calls total.
The helper-cluster counting interval is emitter lines 2488–3495. Counts are an
immutable baseline, not expected post-i totals.

Existing identity owners already matter:

- `ColumnarSemanticTypeResolutionCatalog` builds shared source indexes and exact
  live-handle mappings once. Its views are scoped by source file, lexical owner,
  and the identity of the supplied type-parameter map. `ColumnarExactTypeResolver`
  caches **Resolved / Claimed / Type**, with runtime-generic validation returned
  separately as null / empty / `*` / canonical text. These are not metadata keys.
- S2.1 declaration names and source ordinals, `ColumnarStructDef.DeclaredTypeName`,
  and catalog exact names are available source identities. Display names, short
  aliases, and a builder's AssemblyQualifiedName are not sufficient replacements.
- `ColumnarTypeEquivalenceFacts` is already N# and deliberately differs from
  reference-conversion/interface identity. It includes module-sensitive builder
  and enum identity plus structural closed-generic/byref/SZ-array comparison.
  Do not replace these distinct predicates globally with new key equality.

## Recommended first cut: canonical resolution produces structural references

Move the **connected canonical resolver group** into a directly invoked N# owner
in the existing semantic type-resolution area. Retire C# bodies for:

1. `TryResolveTypeWithTypeParams` (2503–2752), `TryResolveType` (2867–3436),
   `TryResolveClosedUserGeneric` (2817–2864), and
   `TryResolveDelegateCanonical` (3443–3496): approximately 939 physical lines
   including their adjacent explanations. The two main resolvers call each other
   through generic/delegate resolution; moving just one would leave a callback
   into C# policy or require duplicating shape fences.
2. Their source-ownership decisions: `IsOpenGenericUnionDefinition`,
   `ShouldPreserveSemanticGenericHead`, `UnqualifyGenericHead`,
   `IsCollectionHeadShadowedByUserType`, and `TryResolveMemberType`'s selection.
   Reuse existing N# supported-shape/equivalence owners. Reconcile the existing
   N# builtin/exception leaf maps against literal contracts and delete their C#
   copies; do not call C# helpers from the N# resolver.

This is one resolver slice, not all of S2.2. Keep async return-wrapping policy,
member binding, override target search, ambient locals, and stack work separate.
All callers continue resolving at their current phase. The C# changes are direct
N# call routing/deletion; no new loop, dispatch branch, adapter, helper, or replayer.

**Minimum useful result shape:** an emission-scoped structural reference table
plus a selected reference carrying `Key` and the existing live `RuntimeType`.
Reference rows need distinct kinds for primitive, source definition, external
named definition, constructed generic, SZ-array, byref, type generic parameter,
and method generic parameter. A composite holds child key(s); a parameter holds
its owner identity and ordinal. A source definition uses a declaration identity
within this emission; an external leaf retains exact assembly identity, namespace,
nesting/name, and value/reference classification. Preserve generic argument order.
Do not use the original canonical text as the key, or recursively stringify
AssemblyQualifiedName; constructed source types and unbaked parameters require
structural ownership. Erased string-backed enums and reference `?` annotations
must still select their actual CLR signature identity, retaining source provenance
separately when needed. No process-wide cache. Use known source family/owner/method ordinals when
registering generic parameters; do not recover a source method key by eager
MethodBuilder.GetParameters or a metadata token that does not exist yet.

Produce this reference **during resolution**, including the exact-resolver cache
answer, before its live Type companion reaches declaration consumers. A thin N#
`Try...(..., out Type)` consumption surface may preserve existing host signatures
while obtaining that Type from the selected reference; the resolver must not
continue deciding a Type first in C# and merely decorate it afterward.

In the same slice, give `ColumnarCodePlan.AddType` a structural-reference overload
and route the existing **`ColumnarTypeOfPlanner.TryAppendTypeOf` → AddType →
`ldtoken`** path through it. Preserve the current scope-based selection in
`TryResolveTarget`; use the shared identity owner to capture that selection, not a
new canonical fallback. The pool must retain the selected key alongside its live
companion, and the N# executor must validate/consume the paired entry before its
existing Type emission. This is the concrete production reader that prevents a
write-only key schema from being called progress. Keep per-plan slot append order,
checkpoint rollback, capacity growth, and reset coherent. Explicitly inventory
remaining handle-only AddType callers; converting every body pool is later work.
A plan-only record or just redirecting the primitive getter is not this cut.

## Dependency closure: no host callback is necessary

The four resolver bodies are static and read **no emitter instance fields**. Their
complete semantic input is canonical text; enum/struct/union semantic registries;
and, where present, the supplied type-parameter map. Their dependencies close as
follows (direct-call identifiers were extracted from the immutable method bodies):

| dependency | N# disposition |
|---|---|
| Recursive ordinary/generic/closed-source/delegate calls | Move together; all recursive edges stay in the new owner |
| ExactResolver.TryResolve, RuntimeGenericValidationCanonical, IsSourceDefinition | Existing ColumnarExactTypeResolver; preserve its four-way validation answer and terminal Claimed bit |
| Registry TryGetValue/ContainsKey/Values | Existing ColumnarSemanticRegistry and indexes; do not flatten into short-name dictionaries |
| Enum IsStringBacked/EnumType; struct Builder/GenericParameters; union Base | Existing N# ColumnarDefinitions records; direct reads, no C# projection callback |
| UnqualifyGenericHead, IsOpenGenericUnionDefinition, ShouldPreserveSemanticGenericHead, collection-shadow predicate | Move these C# decisions with the group; their dependencies are only the above registries and N# canonicalizer |
| SplitTopLevelCommas, StripTupleElementNames, UnqualifiedTypeName | Existing ColumnarTypeCanonicalizer |
| SplitTopLevelPipes, tuple definitions, supported/admissible/byref-like/builder-bound/nullable predicates | Existing ColumnarTypeOfPlanner; reuse unchanged, including generic/non-generic differences |
| TypesEquivalent | Invoke ColumnarTypeEquivalenceFacts directly; its C# method is already only a forwarder |
| IsSupportedByRefElementType | Move its exact `!IsByRef && IsSupportedType` predicate into N#; remaining host uses may shorten to direct routing |
| External binding-name map / known external resolution | Existing ColumnarExternalBindingPlans and ColumnarTypeOfPlanner.TryResolveKnownExternalType |
| TryResolveExactRuntimeType | Direct N# Type.GetType operation with the same no-throw-on-miss/null outcome; existing host uses can shorten to that owner |
| Builtin and BCL exception maps | Existing N# leaf maps plus exact reconciliation below, not a new detached resolver |
| MakeGenericType/MakeArrayType/MakeByRefType, GetGenericArguments, AssemblyBuilder check, Array.Copy | Direct CLR interop or existing N# array-copy spelling; no ILGenerator or ModuleBuilder involved |

**Leaf mismatch found:** N# TryResolveBuiltinType has the same 21 accepted spellings
(including IntPtr/nint and UIntPtr/nuint aliases), but a different false-out value.
C# TryResolveBclExceptionType also admits YamlException and its full name;
TryResolveExceptionType does not. The existing N# known-external owner already
contains those Yaml spellings, so ordinary canonical resolution reaches it first.
The C# exception helper's *other* catch/construction callers still require the Yaml
row when that helper is deleted. Reuse that N# runtime identity acquisition;
blindly replacing those calls with TryResolveExceptionType is incorrect.
NSharpLang.Runtime Union/Result generic definitions also already have an N#
resolution spelling in TypeOfPlanner; prove equivalent exact definitions and
failure timing rather than assuming `typeof(OpenGeneric<>)` is admitted by stage-0.

**Contexts that must survive unchanged:** catalog creation at emitter 4148; per-file
interface views (4155); per-struct lexical owner plus declaring generic map (4233);
union base/case maps (4998/5023); free-function method maps (5106/5119); body/initializer
views (5424–5609); and per-file test view (5768). The instance TryResolveBodyType
forwarder supplies only `_typeParameters` and `_typeResolutionEnums/Structs/Unions`.
Those four fields remain host-held inputs, not closure captures by N#.
TryResolveIteratorCanonical is a separate policy owner: machine parameters must
beat method parameters, and its ContainsMethodVarReference guard rejects leaked
MVARs. Preserve its special map handling; do not normalize a supplied map to the
catalog's cached map merely because their names match. ForSynthesizedMethod already
narrows ownership in N# and retains its blocked-name set.

`TryResolveLoadedExternalType`/ASP.NET reference probing, async return-shape policy,
iterator MVAR guards, caller-level IsSupportedParameterType checks, and decline
recording are **not called by the four-method group**. They are remaining owners,
not dependencies to be copied into this cut. Existing N# TypeOf detached shape
resolution remains an explicit separate context; sharing leaf facts/key capture
must not route rejected scoped canonicals to it. Thus the port needs neither a
callback into ColumnarIlEmitter nor a new fallback implementation.

The proposed structural consumer is an existing source route, not an invented
writer API: TypeOfPlanner line 146 currently appends its selected Type, and
CodePlanExecutor line 354 already emits its ldtoken. Only that paired pool entry
and its existing validation/execution read change in this first cut. Its exact
N# selection remains authoritative, and no future metadata writer is assumed.

## Failure, order, and identity controls

- Preserve exact semantic selection **before** retained shape interpretation.
  A claimed failure is terminal. Keep lexical nested names, file imports/aliases,
  ambiguous claims, blocked type parameters, and synthesized-method scope narrowing.
  The detached `ColumnarTypeOfPlanner.TryResolveType` is not a drop-in replacement:
  it has different scope inputs and still a short-name fallback.
- Preserve Func parser sugar versus source Action precedence; BCL collection-head
  shadowing; named tuple erasure; two-arm anonymous unions and unequal-arm rule;
  reference versus value nullable behavior; array/byref element fences; open union
  rejection; source generic arity; and distinct generic/non-generic collection
  key/value restrictions. Keep return-before-parameter delegate resolution.
- Keep all existing false/null/out behavior and exception timing measured. Some
  existing N# leaf helpers leave `typeof(object)` on false whereas the C# maps
  leave null. Do not silently widen success or turn a throwing MakeGenericType
  into a decline (or vice versa). Do not cache failed mutable-builder reflection
  answers beyond the current phase or broaden the existing catalog lifetime.
- No eager whole-declaration signature resolution: fields/base/interface/method
  phases remain ordered. Retain h's actual return → parameter → native-row decline
  → parameter-default failure precedence, and parameter metadata before override
  application. Keys must not reorder builder creation, type-pool slots, metadata
  token allocation, or declaration traversal.
- Source identity must distinguish equal names in different emissions/modules.
  Generic parameters must distinguish type versus method owners, including two
  owners both spelling `T`; equivalent closed builder instances must have the
  same structural shape without relying on reference caching by MakeGenericType.

## Stage-0 and meaningful acceptance evidence

Before substantial migration, compile bounded N# probes for the exact intended
API: generic `ColumnarSemanticRegistry<T>`/dictionary lookup and out parameters;
recursive result records and their arrays; Type/TypeBuilder/GenericTypeParameterBuilder
assignment; MakeGenericType(Type[]), MakeArrayType, MakeByRefType; exact assembly,
nested owner, generic-owner and parameter-position reads used by the descriptor;
and selected-reference AddType/checkpoint storage. Existing N# code demonstrates
many of these individually, but it is not proof for the new combined spelling.
If a required operation is missing, report the exact probe and implement an N#
prerequisite; no temporary C# bridge or SDK republish without coordination.

Required canonical N# tests:

1. Literal structural-kind/ordinal/ordered-child expectations and independent
   CLR-type/signature expectations; aliases converging on one selected identity;
   source names in distinct namespaces/emissions; same-name external types from
   distinct assemblies; type-owned versus method-owned generic parameter 0.
2. Table-driven ordinary/generic resolution over scalar, source, nested source,
   source generic, array/byref, nullable, tuple, Func/Action, union, and modeled
   collection shapes. Independently pin all distinct admission fences above,
   claimed failure versus unclaimed miss, and no source short-name rescue.
3. Production field/return/parameter signatures plus `typeof` in root/nested/body
   positions. Assert the structural pool row and actual emitted ldtoken target;
   malformed key/handle pairs fail before any IL mutation. Pin duplicate AddType
   slot order and reset/rollback, not just descriptor factory getters.
4. Retain the h direct-emitter malformed-input precedence controls and i's final
   override matrix. Add a rejected-key/altered-child control that actually trips
   validation; do not rely on source parser errors as proof of emitter ordering.

Use focused `dev.sh` first, then the estate because this resolver is shared. Compare
baseline CLI and changed CLI strict checks against the **same edited source**, with
mapped source-line shifts versus baseline, to catch stage-0-only success/strict
regressions. Parent owns fresh fixed-corpus pre/pre and pre/post whole-PE parity,
output-set/outcome equality, the live byte mutant, ratchet audit, and integration
gate. No accepted slice without a committed production reader and removed C# owner.

## Other S2.2 boundaries and the i reconciliation

`ColumnarOverrideTargetResolver` is N# but returns only MethodInfo (one production
caller at baseline line 4532). It walks nearest base first, declared method order,
public instance virtual/nonfinal/nongeneric matches; builder reads and base-chain
exceptions are guarded. Its cross-universe fallback is assembly-qualified-name
identity. A later cut must add a declaring-type/signature descriptor beside the
selected handle without broadening protected/source-builder admission. The C#
source/closed/external interface search and substitution helpers listed above
remain separate policy owners; their existing differing equality rules matter.

S2.1(i)'s approved shape retains source method ordinals, base/source/external target
families, separate dedup domains, and iterator member declaration identities beside
runtime handles. These can anchor later member-reference descriptors. They are
not yet structural resolved target keys, and i must not be repeated or credited
as completing S2.2. S2.1(i) subsequently committed at `75fa5a77b`: the production types are
`ColumnarMethodOverrideDeclaration`, `ColumnarMethodOverrideCompletion`,
`ColumnarResolvedMethodOverride` and `ColumnarIteratorOverrideDeclaration`. All fourteen C#
attachment calls are removed; the ordinary/interface resolver bodies and type-resolution pool
remain for this stage. Its admitted direct typed tests pass with runtime-Type fixture helpers;
unsupported typeof operands did not establish a custom-return limitation. Revalidate the current
lines and dependency closure before implementation; do not repeat i.

Ambient operands are already pool indices, but the pool stores LocalBuilder:
`AddAmbientLocal` has three production calls, all in ColumnarBoundIdentifierPlanner.
The executor reads LocalType and passes LocalBuilder to EmitLocal. A later cut must
carry actual method slot + type-key data and keep an execution companion outside
portable identity. Preserve four plan-local-mirror scratch sites: mirrors describe
already assigned vocabulary, are not storage, and cannot execute.

`ValidateMethodBodyStack` at executor line 730 has one caller. It computes a local
heights array to a fixpoint, seeds finally/fault/catch boundaries, adds the catch
exception height, checks merges/reachability, and discards the result. There is no
maxstack plan column. A later cut can retain the measured peak at validation/seal,
with reset/rollback and mutation rules; prove it against actual emitted method
headers, including catch/loops/calls. Do not assume Reflection.Emit header maxima
always equal the minimal dataflow peak, or conflate schema-v3 expression stack
validation with this schema-v4 method calculation.
