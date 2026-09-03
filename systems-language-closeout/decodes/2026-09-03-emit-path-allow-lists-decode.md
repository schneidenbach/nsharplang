# 022 slice 2f — the closed allow-lists on the emit path (Phase-1 decode)

Measured at `51fa6592b` in `/private/tmp/nsharp-agent-wt/022-s3b2`, with the CLI built from that tree.
Two probe projects outside the repository under `/private/tmp/nsharp-agent-wt/022-probes/`. No product
file was changed.

---

## 1. THE BRIEF'S PROPOSED MEASUREMENT DOES NOT WORK, AND THAT IS THE FIRST FINDING

The brief asks for "a decline census with the list widened" over the corpus. **The corpus cannot
measure this defect class at all.** The pinned corpus (`9b0dd2388`, 74 targets) builds 53 and fails 21,
and not one of the 21 fails because of a type allow-list:

| failing targets | 21 |
|---|---|
| `.tests.nl`-only projects that `nlc build` under-measures (a SITELESS `-- ERROR ---- code`) | 17 |
| lint findings in the two big source trees (`NL001`/`NL002`/`NL010`/`NL011`/`NL012`) | 2 |
| `NL405` native-import marshalling (`ReadOnlySpan<byte>` through a P/Invoke) | 1 |
| `NL001` unused variable | 1 |
| **attributable to a closed type list** | **0** |

Widening the lists and re-running that census would produce 21 → 21 and prove nothing. The corpus's
role in this slice is the IL differential — nothing may move — not the measurement.

**The instrument that does work is a per-shape probe matrix**, the method 022/3a and 023/1 used. §3 is
that matrix, run through the real CLI.

## 2. The census of closed lists

### The two the brief names

| owner | what it gates | shape |
|---|---|---|
| `ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName` (`:193`) | whether an external type may be DECLARED/held at all | one `||` chain of 32 full-name literals plus `IsWriterMetadataTypeName` (6 classes), `IsWriterMetadataHandleName` (31 handle structs), `IsCustomAttributeSequenceName`, `IsXmlLinqTypeName` (7) |
| `ColumnarTypeOfPlanner.IsSupportedType` (`:1088`) | whether `typeof(X)` may be emitted | a dispatcher over ~20 arms |

`IsSupportedType`'s arms are NOT all the same kind of thing, and the slice must not treat them as one:

- **Lowering facts that STAY.** The `typeof(int)/bool/long/ulong/string/char/…` head is the set of
  scalars this backend actually bakes; `IsEnumType`, `valueType is TypeBuilder`,
  `get_IsGenericParameter()`, `IsClosedSourceGeneric`, the `!IsPointer && !IsByRef && IsSZArray`
  element recursion and `IsSupportedNullable` are structural questions with real answers.
- **A rule already, not a list.** `typeof(Exception).IsAssignableFrom(valueType)` is an open rule over
  a base type, and `IsSupportedExternalType` is a half-rule: YamlDotNet by ASSEMBLY IDENTITY, then
  `Microsoft.AspNetCore.` / `Microsoft.Extensions.Hosting` by NAMESPACE PREFIX. Those two are what the
  whole dispatcher should look like.
- **Closed name lists that are the defect.** `IsSupportedRuntimeTypeName`, `IsSupportedJsonType` (8
  names), `IsSupportedSpanLikeType`, `IsSupportedArrayPoolType`, `IsSupportedMemoryPoolType`,
  `IsSupportedMemoryOwnerType`, `IsSupportedMemoryType`, `IsSupportedResultType`,
  `IsSupportedAnonymousUnionType`, `IsSupportedValueTuple`, `IsSupportedDelegateType`,
  `IsSupportedCollectionType`, `IsSupportedTaskType`, plus
  `ColumnarRuntimeTypeFacts.IsSupportedProcessInteropType` / `IsSupportedDirectCallInteropType`, plus
  the `RequiredTextWriterType()` seed whose own comment says it exists only because
  `typeof(TextWriter)` declines under the pinned toolset.

### The siblings

`ColumnarRuntimeInstanceMemberResolver` carries a near-DUPLICATE family of the same predicates —
`IsSupportedJsonType`, `IsSupportedSpanLikeReceiver`, `IsSupportedArrayPoolType`,
`IsSupportedMemoryPoolType`, `IsSupportedCollectionType`, `IsSupportedDelegateType`,
`IsSupportedExternalType`, `IsSupportedAnonymousUnionType`, `IsSupportedTaskValueType`,
`IsSupportedElementType` (24 `IsSupported*` functions in that file alone). Two spellings of one
question is the drift `AnalyzerMetadataLoadPolicy`'s header warns about, and 2f should collapse them
rather than widen both.

The remaining `IsSupported*` in the estate are NOT type admission and are out of scope: opcode-name
tables (`IsSupportedOpCodeMemberName` and its three siblings), token kinds, operator sets, test arity,
SoA column types, `nameof` targets.

## 3. THE MATRIX — 38 `typeof` shapes through the real CLI

Every shape compiled as `typeof(X)` bound to a local in a library project built by the branch CLI.

**PASS (13):** `object`, `string`, `int`, `int[]`, `DateTime`, `Version`, `Exception`, `Type`,
`StringComparer`, `List<int>`, `IEnumerable<int>`, `HashSet<int>`, `StringBuilder`, `Stream`, `Task`,
`Process`.

**DECLINE (22):** `Uri`, `Guid`, `StringComparison`, `ConsoleColor`, `Delegate`, `void`,
`Nullable<int>`, `Queue<int>`, `SortedSet<int>`, `ICollection<int>`, `IList<int>`, `IEnumerable`
(non-generic), `MemoryStream`, `FileStream`, `TextWriter`, `StreamWriter`, `Regex`, `HttpClient`,
`JsonSerializer`, `Path`, `File`, `Environment`, `Math`.

### THE MEASUREMENT: 22 OF 22 DECLINING SHAPES ARE CATALOG-RESOLVABLE

A second probe opened a `MetadataLoadContext` over the common-assembly table and asked it for every
declining type by full name. **All 22 resolve.** Not one decline is a lowering limitation; every one is
a hand list refusing a type the compiler's own catalog already holds. That is the whole measurement the
brief wanted, and it is unanimous.

The catalog also answers the sub-classification the walls guessed at: `Path`, `File`, `Environment`,
`Math` and `JsonSerializer` come back `abstract=True` (a static class is `abstract sealed`), while
`Delegate` and `TextWriter` are ordinary abstract classes and `ICollection<1>`/`IList<1>`/`IEnumerable`
are interfaces. §2.1 records the static-class case as "the SHAPE, not the assembly" — but a static
class's `typeof` is perfectly emittable, so that is one more list rather than a constraint.

### Three recorded walls are STALE and the decode overturns them

§2.1 lists `HashSet<int>`, `StringBuilder` (unless fully qualified) and `Stream` among the `typeof`
declines. **All three PASS today.** Any slice pricing work off that list would be pricing work already
done.

### EVERY DECLINE IS SITELESS, WHICH IS A PRODUCT DEFECT IN ITS OWN RIGHT

All 22 report the headerless `-- ERROR ---- code` with no site, no file and no reason — the exact shape
022/3b-1 fixed for `override` targets. A user who writes `typeof(Uri)` is told nothing at all. 2f
should land a LOCATED `emit.typeof.unsupported-type` decline naming the type, independently of how much
the admission widens, because that is the difference between a wall and a mystery.

## 4. THE TWO-STAGE QUESTION: the widening itself is republish-free

`ColumnarTypeOfPlanner.nl` and `ColumnarExternalBindingPlans.nl` live in `BootstrapServices`, which the
PACKAGED SDK compiles — but the CLI links `BootstrapServices` built FROM SOURCE, so a widened rule is
live for everything that CLI compiles (corpus, probes, native projects) the moment it is built.

The boundary is only crossed if `BootstrapServices`' OWN sources start SPELLING a newly admitted type.
A widening admits more and requires nothing, so the estate compiles unchanged: **no republish for the
widening**. A later sub-slice that rewrites estate code to use a newly admitted `typeof` — for example
deleting `RequiredTextWriterType()` by writing `typeof(TextWriter)` in the estate — IS gated, and that
step stops and reports.

## 5. Sub-slice order

1. **2f-a — the located decline.** `emit.typeof.unsupported-type` naming the type and its site. No
   admission change; the before/after is 22 siteless declines becoming 22 located ones. This is
   separable, is worth landing alone, and gives every later sub-slice a readable failure.
2. **2f-b — `IsSupportedType`'s external arms become one catalog question.** The lowering head and the
   structural arms stay; the closed name lists collapse into "the catalog resolves it". The matrix is
   the before/after: 22 declines → 0, with the 13 passes unmoved.
3. **2f-c — `IsSupportedRuntimeTypeName`'s 32 rows.** Same rule, the declaration gate.
4. **2f-d — collapse the `ColumnarRuntimeInstanceMemberResolver` duplicates onto the same owner.**
5. **2f-e — the estate-side deletions** (`RequiredTextWriterType`, any list function left callerless).
   **This is the republish-gated step; it stops and reports if the estate must spell a new type.**

Each sub-slice: IL differential over the corpus (nothing may move — every admitted shape is one the
corpus never used), estate, 103-project `check --json` differential, the MATRIX before/after in place
of a corpus decline census, format, repin last.

## 6. Coordination note

`ColumnarIlEmitter.cs` is being edited continuously by the 023-s2 stream. Everything in §2 and §5 is in
the N# planners; the only C# this slice needs is deletions at the call sites of the list functions, and
§2's census found the admission logic is already entirely N#-side. Rebase often.
