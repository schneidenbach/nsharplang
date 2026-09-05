# S2.2(c): closed source-interface member resolution

Implementation baseline: `aff32a9e1a1a0df3d75cc3805223af5c235b12fb`. This slice moves closed
source-interface lookup, signature substitution, completeness checking and generic method rebinding
into N#. A successful lookup now produces an emission-scoped structural binding that remains attached
to the override row through completion and execution.

## Resolution and binding ownership

`ColumnarClosedGenericMemberResolver` owns the former host policy. Closed source lookup still reads
only the first `Methods[memberName]` row, tries the current declaration before a depth-first walk of
`InterfaceBases`, and retains the original closed mapping context while recording the actual ancestor
that declared a winning member. Matching substitutes the return before inspecting parameter count,
then substitutes parameters left to right and stops on the first mismatch. It continues to use
`ColumnarTypeEquivalenceFacts.TypesEquivalent`, distinct from the ordinary source resolver's CLR
`Type ==` rule.

The same N# owner now supplies the signature substitution used by the constrained source-interface
selector. Its C# argument selection, ambiguity and contextual-expression policy remains in place.
The existing `ResolveClosedGenericMethod` C# entry is a direct call to the shared N# rebinder, so its
collection, iterator, await and source callers retain the original builder-bound
`TypeBuilder.GetMethod` branch and runtime `MethodBase.GetMethodFromHandle` branch without a copied
policy implementation.

`ColumnarClosedSourceInterfaceMethodMatch` is the successful relation between the authoritative open
source row, the original mapping context and the exact effective return and parameter handles produced
by that one match. It snapshots the open return before substitution and each open/effective parameter
as comparison proceeds; builder and modifier facts are captured only after the whole signature
matches. Failed matches perform no structural capture or binding. Descriptor construction proves that
the same `Methods[name]` row still owns those snapshots; a caller cannot combine an independently
supplied effective signature or target with an otherwise valid source declaration.

`ColumnarClosedSourceInterfaceMethodDescriptor` reuses the ordinary source member descriptor for the
actual found owner and open signature. It separately retains structural selections plus independent
runtime companions for the mapping open definition, original closed context and effective signature.
Constructed contexts validate that child zero is the mapping definition; nongeneric and open generic
contexts validate the same source-definition key. All scalar fields are `readonly`, and ordered facts
are copied into fresh lists retained only through BCL read-only wrappers.

The binding derives its target from the captured builder after a successful match and performs no
`MethodBuilder.GetParameters`, return-type reflection, metadata-token lookup or second generic closure.
`ColumnarMethodOverrideDeclaration` keeps closed bindings in the existing source target and default
`HashSet<MethodInfo>` domain, so ordinary, closed and bare source rows preserve the first representation
seen under the old equality rule. Completion retains that representation. `Apply` validates every
structural target against the consuming emission table before the first `DefineMethodOverride`; a
foreign table or malformed selected/runtime pair therefore cannot partially attach an earlier row.

The C# host now forwards lookup to this N# binding and the existing emission table. The definitions of
`TryFindClosedInterfaceMethod`, `ClosedInterfaceMethodMatches`, `ClosedInterfaceMembersSatisfied` and
`CloseInterfaceMemberType` are deleted completely. The constrained selector's two substitution calls
route to N#. No C# helper, branch, callback, adapter or fallback was added.

## Preserved edge behavior

Direct contracts pin nongeneric, open generic-definition and constructed contexts; same-owner,
different-owner and method-generic ordinal substitution; out-of-range retention; SZ-array, byref and
nested generic recursion; terminal closed, pointer and non-SZ-array shapes; runtime and builder-bound
method rebinding; and the raw incompatible-owner `ArgumentException`. Completeness retains default-body
skips, first-row selection and structural type equivalence.

Malformed matching controls prove the original short circuit precisely: a wrong return suppresses a
null later parameter, matching return plus wrong arity still suppresses it, and a first-parameter
mismatch suppresses a malformed second parameter. Matching every preceding value reaches the original
raw `NullReferenceException`. Failed candidates and completeness checks do not perform structural
capture or method rebinding.

The descriptor contracts also mutate the source parameter, return and builder independently after a
successful match. A new descriptor rejects each altered row, while an already captured descriptor and
target retain their immutable facts. Reflection verifies every field on the new match, parameter,
descriptor and binding rows is emitted `initonly`; attempted `IList` writes to retained signature
storage throw `NotSupportedException`.

## Measured bootstrap spellings

The first direct runtime-branch casts declined at `emit.return.expression` and
`emit.typed-local.initializer`. The admitted form preserves the explicit `MethodInfo` cast through a
named `object?` local; it does not add an `as` fallback or a replacement exception. Chained nullable
`GetElementType` casts likewise declined at `emit.local.initializer`, while a named object local followed
by the same explicit `Type` cast compiled. The standalone identifier `match` parsed as the N# `match`
keyword; the retained AST shows its value as a recovered match expression, and the final source uses
`comparison`.

Fixture-only `TypeBuilder.MakeGenericType` receiver calls declined until the builder was first widened
to `Type`. A current-runtime probe also found that Reflection.Emit `SymbolType` reports `IsSZArray=true`
for builder-parameter byrefs and pointers; the historical helper checks `IsSZArray` before `IsByRef`, so
branch-discrimination tests use runtime generic parameters instead. The exact probe establishes the
current behavior only; immutable-baseline equivalence is inferred from the unchanged branch order, not
claimed as an executed differential result.

Rejected and admitted evidence is retained under `/private/tmp/nsharp-s22c-executor-logs`, including
`dev-initial*.log`, `ast-revised-candidate.json`, `dev-snapshots-1.log`,
`substitution-debug-2/run.log` and the successful focused logs below.

## Focused evidence

| Check | Result | Raw evidence |
|---|---|---|
| Bootstrap-services N# estate | **7,726 passed, 0 failed** | `/private/tmp/nsharp-s22c-executor-logs/estate-final-postformat.log` |
| `./scripts/dev.sh Columnar` | CLI build passed; **12 passed, 0 failed** | `/private/tmp/nsharp-s22c-executor-logs/dev-final-preformat.log` |
| Root formatter check over the changed N# files | Exit 0; all files properly formatted | `/private/tmp/nsharp-s22c-executor-logs/final-format/check-after.log` |
| `git diff --check` | Exit 0 | Reproducible on this diff |

The formatter removed one blank line from the new resolver and made no semantic or token change. Its
exact pre/post sources, hashes and unified diff are under
`/private/tmp/nsharp-s22c-executor-logs/final-format`; the final source manifest is
`/private/tmp/nsharp-s22c-executor-logs/final-source/final-source-manifest.txt`.

The exact assembly produced by the final post-format estate is retained under
`/private/tmp/nsharp-s22c-executor-logs/final-linked`. Its SHA256 is
`4340915f25e6de948984ef56ec680a0d3af35889dbcedec60c0c6789ed15d2e0`; the IL SHA256 is
`ecb9267699f22dcf0ce28706e92ea9eb74105c75f94e5cbc0390241e292f3eba`. The IL census records the
builder/runtime rebinding calls, BCL `AsReadOnly` calls, 28 new `initonly` fields and the existing
all-target validation pass before `DefineMethodOverride`.

`ColumnarIlEmitter.cs` decreases from **19,613 / 18,622 / 1,020,953** total lines, nonblank lines and
bytes to **19,517 / 18,537 / 1,016,931**. Its SHA256 is
`cad6a79b7c6f9f2310ed149cad33e8b05a94d4d43160ba4edb6ef660a8ce7368`; the diff adds 11 lines and
deletes 107. The new resolver SHA256 is
`918fb166f5630b3b9f7a8de38698e4d56854e5eb9a51f206f19dac683652edca`.

Closed ancestor generic-argument remapping, source-definition discovery, constrained-call argument
admission, external/base/iterator member descriptors and constructor resolution remain later S2.2
work. This slice preserves the first-`Methods` limitation, owner-blind ordinal substitution, raw
reflection exceptions and the constrained selector's existing ambiguity outputs. The coordinator owns
the immutable baseline/current production replay, strict-source comparison, physical `MethodImpl`
parity, ownership-ratchet update, fresh integration gate and push. This slice does not publish an SDK.
