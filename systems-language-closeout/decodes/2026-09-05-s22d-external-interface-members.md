# S2.2(d): external-interface member resolution

Implementation baseline: `2e256ef6f2634b14a984091f5fb2c2036afff953`. This slice moves
external-interface candidate enumeration, signature matching and completeness checking into N#.
Successful candidates now carry an emission-scoped structural external-method binding through
override completion and are validated before any `DefineMethodOverride` attachment.

## Resolution and completion ownership

`ColumnarExternalInterfaceMethodResolver` owns the former host policy. Target discovery still walks
`ExternalInterfaces` in list order and each interface's `GetMethods()` result in reflection order.
Every candidate compares the exact name, then the return through
`ColumnarTypeEquivalenceFacts.TypesEquivalent`, then calls `GetParameters`, checks arity and compares
parameters left to right. Wrong names and returns therefore suppress later malformed parameter
inputs, while a matching name and return still reaches the original raw `GetParameters` exception.
The resolver adds no static, generic, default-body or inherited-interface filter.

Completeness uses the same matcher without constructing structural rows. It reads only the first
`Methods[name]` implementation, preserves the original repeated `MethodInfo.Name` access, returns
false for missing or mismatched members and continues to require external default-body members. It
does not recursively enumerate inherited interfaces. The C# candidate loops, completeness loops and
`ExternalInterfaceMethodMatches` definition are deleted; the two call sites now invoke the N# owner
directly. No C# helper, branch, callback, adapter or fallback was added.

`ColumnarExternalMethodDescriptor` is a neutral external-member identity that later base and iterator
slices can reuse without inheriting interface-selection policy. It is derived from the actual
`GetMethods()` winner rather than accepting caller-supplied open/effective signature pairs. It keeps
the enumerated lookup context, reflected context, actual declaring context and open declaring
definition distinct. The open MethodDef is recovered inside that exact declaring definition by
module MVID plus metadata token; neither a name/signature scan nor a closed-signature guess supplies
identity.

After matching succeeds, the descriptor snapshots the authoritative open and effective return and
ordered parameter types, generic method parameters, calling convention, static flag, name, generic
arity and MethodDef identity. Return and parameter required/optional custom-modifier lists are read
only after success and copied into BCL read-only storage. Every selected key has a separately retained
runtime `Type` companion. Constructed generic `MethodInfo` values are rejected as a descriptor
invariant after matching; candidate matching itself receives no new generic-method filter.

`ColumnarExternalInterfaceMethodBinding` derives its executable target from that descriptor.
`ColumnarMethodOverrideDeclaration` retains binding-backed and bare external targets in the same
existing `HashSet<MethodInfo>` domain, preserving first representation and reflection equality.
External and source dedup domains remain separate. Completion retains the winning representation,
and `Apply` validates every structural row against the consuming emission table before the first
attachment. Foreign tables and forged selected/runtime pairs therefore fail atomically.

## External generic-parameter identity

The structural key schema now has explicit `ExternalType` and `ExternalMethod` generic owners. An
external VAR records its actual open `ExternalNamedDefinition` owner and flattened generic ordinal,
including nested definitions. An external MVAR additionally records the declaring module MVID,
MethodDef token, name, generic arity, calling convention and static flag. Runtime and
`MetadataLoadContext` representations of the same metadata owner intern to the same key; overloads,
type owners, nested positions and method owners remain distinct.

Open metadata signatures use `SelectExternalSignatureType`, which derives VAR/MVAR ownership from the
runtime metadata parameter itself. Effective and context types use ordinary selection so registered
source parameters keep their emission-local owner. Validation dispatches by the key's explicit owner
family: a metadata generic parameter deliberately registered under a source fixture owner yields a
source key through ordinary selection and an external key through the dedicated signature selector,
and both validate only under their respective identity rules. Unregistered builder parameters still
fail instead of being misclassified as external metadata.

All new identity, signature, descriptor and binding fields are `readonly`. Input arrays are copied
forward, and only `List<T>.AsReadOnly()` wrappers are retained. Tests mutate input arrays and attempt
`IList` writes against generic owners, signature children, modifier rows and descriptor parameters;
the captured facts remain unchanged.

## Custom-modifier boundary

The direct estate builds and bakes its own Reflection.Emit interface with known return and parameter
`modreq` and `modopt` markers. The runtime exposes each two-entry modifier list in reverse of the
`SetSignature` input order; the descriptor preserves and validates that authoritative reflected order
independently for required and optional lists. Reflection exposes required and optional arrays
separately, so their original mixed interleaving is not recoverable here. Arbitrary lossless mixed
custom-modifier ordering remains an ECMA-335 writer boundary rather than an overclaimed descriptor
guarantee.

## Measured bootstrap spellings

The accepted N# reflection probe is retained under
`/private/tmp/nsharp-s22d-executor-logs/stage0-external-member-reflection`. It proves runtime and
metadata-context VAR/MVAR ownership, exact module/token recovery, method flags and custom-modifier
access. `Guid ==` was unavailable in the bootstrap surface, so portable MVID identity uses the exact
`Guid.ToString()` value on both capture and validation. The standalone local name `required` parsed as
a keyword, and a property/static helper sharing `ModuleVersionId` was rejected as a member collision;
the final names carry no policy workaround. An exploratory C# reflection probe was discarded before
acceptance and is not evidence for this slice.

The formatter changed only canonical line wrapping in
`ColumnarStructuralTypeReferences.nl` and `ColumnarExternalInterfaceMethodResolver.nl`. Exact pre/post
copies and the unified diff are retained under
`/private/tmp/nsharp-s22d-executor-logs/final-format-1`.

## Focused evidence

| Check | Result | Raw evidence |
|---|---|---|
| Bootstrap-services N# estate on formatted source | **7,736 passed, 0 failed** | `/private/tmp/nsharp-s22d-executor-logs/estate-final-postformat-8.log` |
| `./scripts/dev.sh Columnar` before formatting-only line wraps | CLI build passed; **12 passed, 0 failed** | `/private/tmp/nsharp-s22d-executor-logs/dev-columnar-4.log` |
| Native `columnar-emit-facts` with the exact external controls | **93 passed, 0 failed** | `/private/tmp/nsharp-s22d-executor-logs/native-external-current-9.log` |
| Immutable baseline CLI strict check on final source | **259 existing errors, 0 warnings** across 430 files; stderr empty | `/private/tmp/nsharp-s22d-executor-logs/strict-pre-final-postformat.json` |
| Root formatter check over all changed N# files | Exit 0; all files properly formatted | `/private/tmp/nsharp-s22d-executor-logs/final-format-1/check-after.log` |
| `git diff --check` | Exit 0 | Reproducible on this diff |

`ColumnarIlEmitter.cs` decreases from **19,517 / 18,537 / 1,016,931** total lines, nonblank lines and
bytes to **19,492 / 18,513 / 1,015,879**. Its SHA256 is
`b7b8a4a8f08eb4f06cec30d1750476cdb182546b67c9371679b6875b3bc0ba6c`; the diff adds 9 lines and
deletes 34. The final formatted resolver SHA256 is
`0fcf1871cb185476725afc0bd71eebe2c028e3af0d2135b4d9ef531ec48bce77`, and the structural table
SHA256 is `7f491b2c2e5ed2f8c3f463a4073fd1f02fd85b7b6c8ec088881a37ec5992e94e`.

Base-interface and iterator member resolution remain later S2.2 work. This slice deliberately retains
raw reflection exceptions, `GetMethods()` ordering, first-`Methods` completeness, external default
requirements, the absence of inherited-interface recursion and the separate source/external dedup
domains. Modifier interleaving and the remaining handle-only type-pool consumers remain writer debt.
The coordinator owns the immutable baseline/current corpus replay, final strict-source mapping,
physical `MethodImpl` parity, ownership-ratchet update, fresh integration gate and push. This slice
does not publish an SDK.
