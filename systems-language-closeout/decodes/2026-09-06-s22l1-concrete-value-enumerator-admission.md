# S2.2(l1): concrete dictionary value enumerator admission

The entry-point discovery owner retains the concrete struct returned by
`Dictionary<string, ColumnarStructDef>.Values.GetEnumerator()`. The accepted l0 compiler rejected
that local at `emit.local.unsupported-type`, before any entry-point test executed. The direct
Values/GetEnumerator source, command, output and hashes are frozen under
`/private/tmp/nsharp-s22l-executor-logs/resume-20260906/attempt-02-direct-values-enumerator/`.

An instrumented replay of the same local initializer established the storage handle before its
source type was baked. It is a value-type `TypeBuilderInstantiation` of the exact BCL
`Dictionary<TKey, TValue>.ValueCollection.Enumerator` definition. Its key is runtime `string`; its
value is the live `ColumnarStructDef` `TypeBuilderImpl`; and `ContainsBuilderBoundType` is true. The
final observation and independent review are retained at
`/private/tmp/nsharp-s22l-executor-logs/resume-20260906/exact-init-type-diagnostic/final-observation.json`
and `/private/tmp/nsharp-s22l1-review/actual-handle/review.json`. This evidence records the live
builder shape through its full name and runtime implementation class; it does not claim equality to
the later baked type or observe `IsCreated`.

`ColumnarTypeOfPlanner` now admits only that exact nested BCL definition in the existing
builder-bound storage arm. The helper rejects open shapes recursively, requires the key itself to be
a supported type, retains Dictionary's non-enum builder-bound key rejection, and applies the existing
collection-element rule to the value. This preserves the original canonical Dictionary key/value
boundaries and does not admit `ValueCollection`, arbitrary nested value types, or a name-compatible
foreign definition.

The existing enumerator protocol contract constructs the genuine nested definition over runtime
`string` and a live source builder. It proves the new exact helper and full storage owner accept that
handle while the ordinary collection and enumerator protocol predicates remain false. The final
`./scripts/dev.sh TypeOf` build succeeds, and a forced test-enabled focused run executes and passes
1/1 with no skips. The exact candidate payload and generating receipt are frozen at
`/private/tmp/nsharp-s22l1-executor-logs/candidate-payload-02/`; the focused receipt is
`/private/tmp/nsharp-s22l1-executor-logs/forced-enumerator-final-02/receipt.json`.

No C# owner, entry-point policy or ownership ratchet changes in the product commit. Root accepted
this capability at tested `6687505e4` through independent controls, immutable comparisons, a fresh
backend gate and same-source SDK verification 3/3. [Acceptance proof](2026-09-06-s22l1-parity-proof.md).
The complete [S2.2(l) entry-point owner](2026-09-06-s22l-entrypoint-next-cut.md) remains the next cut.
