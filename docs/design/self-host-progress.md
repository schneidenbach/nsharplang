# Self-Host Progress Log

**Status:** Living log for the N# compiler self-hosting / dogfood migration. Newest entries on top.
See [`compiler-dogfood-rewrite.md`](compiler-dogfood-rewrite.md) for per-slice methodology and
evidence, [`compiler-benchmark-metrics.md`](compiler-benchmark-metrics.md) for the numbers, and
[`compiler-dogfood-boundary-profiling.md`](compiler-dogfood-boundary-profiling.md) for the
delegate-boundary cost analysis (the key perf finding driving the endgame).

This log records: what migrated, benchmark deltas, adapters removed, bootstrap coverage %, and every
language/runtime/compiler limitation found plus the principled change made to resolve it.

---

## 2026-06-14 — SoA add guards length overflow

`table.add()` now rejects a wrapped table whose current `length` is already `int.MaxValue` before
computing `length + 1` for growth and the new length store. Zero-column wrappers make this boundary
reachable without huge backing arrays, and the generated method now reports `length for Table.add is
too large` instead of flowing an overflowed negative capacity into `ensureCapacity`.

## 2026-06-14 — SoA copyRow guards target overflow

`table.copyRow(from, to)` now rejects a dynamic `to == int.MaxValue` before computing `to + 1`
for capacity growth and length updates. The generated wrapper reports a SoA-specific
`ArgumentException` instead of allowing unchecked integer wraparound to steer capacity or indexing.

## 2026-06-14 — SoA copyRow rejects source rows outside length

`table.copyRow(from, to)` now validates the dynamic source row against the table length before reading
column arrays. Negative source/target rows and source rows at or beyond `length` report SoA-specific
`ArgumentException` messages instead of copying default backing-array slots or surfacing raw CLR index
exceptions. Valid copy-to-extension behavior is unchanged.

## 2026-06-14 — SoA generated operations validate dynamic negative bounds

Generated SoA wrapper methods now reject dynamic negative values before they reach CLR array allocation
or indexing paths: `new Table(capacity)`, `table.ensureCapacity(capacity)`, and `table.copyRow(from, to)`
throw SoA-specific `ArgumentException` messages when runtime values are negative. Literal negatives
remain analyzer diagnostics, so known-bad calls still fail before emission.

## 2026-06-14 — SoA wrap rejects statically null columns

`Table.wrap` now reports analyzer diagnostics for column arguments that are literally `null` or
target-typed `default`, including reordered named calls. Dynamic null column variables still flow to
the emitted wrapper guard so runtime validation continues to catch values the analyzer cannot know.

## 2026-06-14 — SoA named arguments drive expected-type inference

Synthetic generated signatures now bind named arguments before argument expression analysis, not only
during final validation. Reordered `Table.wrap` calls with target-typed `new()` column arguments now
infer from the named column parameter instead of the raw argument position, keeping
semantic-model facts aligned with the generated wrapper signature before IL lowering sees the call.

## 2026-06-14 — SoA wrap names and negative lengths validate before emission

`Table.wrap` now participates in the same generated-signature validation as table operations:
column names plus `length` bind semantically for named arguments, and negative literal lengths report
`SoA table wrap length must not be negative` during analysis. Runtime validation still owns null
columns, mismatched column lengths, and dynamic length bounds.

## 2026-06-14 — SoA ensureCapacity uses a source-spellable parameter name

The generated SoA `ensureCapacity` signature now exposes `capacity` as its parameter name in both
semantic analysis and emitted wrapper metadata. Named calls such as `table.ensureCapacity(capacity: n)`
now bind and execute through the same generated method path as positional calls, while wrong-typed and
negative named capacities fail during analysis before wrapper lowering.

## 2026-06-14 — SoA generated operation names bind semantically

Generated SoA operation signatures now carry analyzer-visible parameter names, matching the synthetic
methods emitted for the wrapper. Named calls such as `copyRow(to: dst, from: src)` bind by parameter
before type and literal validation, so unknown names, duplicates, and named negative row ids fail
during analysis with the same source-level contract the backend will emit.

## 2026-06-14 — SoA generated operations reject negative literals

Generated SoA table operations now carry synthetic operation identity through semantic analysis, so
`ensureCapacity(-1)`, `copyRow(-1, to)`, and `copyRow(from, -1)` report source diagnostics before
generated wrapper lowering. The validation is scoped to concrete `int` arguments and preserves the
existing primary diagnostics for wrong counts, wrong types, unknown values, and row-view escapes.

## 2026-06-14 — SoA row projection and copy-row IL shape is pinned

The experimental SoA wrapper tests now inspect emitted opcodes for row-column helper code and the
generated `copyRow` method. Both proofs require direct field plus array element traffic and reject row
object construction, inline array allocation, boxing, delegate construction, and virtual dispatch in the
accepted row/table operation paths, while preserving the explicit `ensureCapacity` call inside `copyRow`.

## 2026-06-14 — Synthetic function signatures validate generated SoA calls

Declaration-less function signatures now enforce argument count and assignability during analysis instead
of only flowing expected types into arguments. This closes generated SoA operation calls such as
`table.add(1)`, `table.ensureCapacity("4")`, and `table.copyRow(0)` before they reach IL emission, while
leaving valid `add`, `clear`, `ensureCapacity(int)`, and `copyRow(int, int)` calls unchanged.

## 2026-06-14 — SoA capacity constructors validate before wrapper lowering

Experimental SoA construction now validates the only supported wrapper constructor shape during
analysis: `new Table(capacity)` with exactly one non-negative `int` capacity argument. Missing, extra,
wrongly named, non-int, and negative literal capacities now report source diagnostics instead of falling
through to generated constructor lookup or array allocation behavior in the IL backend.

## 2026-06-14 — SoA column range reads reject hidden array allocation

Direct SoA column range reads such as `table.column[0..1]` and `table.column[range]` now fail during
analysis with a hidden-allocation diagnostic. Ordinary array range reads remain accepted, but SoA column
slices are blocked until the language owns an allocation-free span/view lowering with pinned IL-shape
evidence. This keeps explicit systems kernels on element indexing instead of accidentally routing compiler
table code through `RuntimeHelpers.GetSubArray`.

## 2026-06-14 — Built-in index diagnostics cover SoA column access

Direct SoA column element access now inherits analyzer-side built-in array index validation, so
`table.column["0"]` fails with a source diagnostic before IL lowering. Array slice writes such as
`table.column[0..1] = values` now also fail during analysis instead of reaching the direct IL backend's
unsupported range-assignment path. Valid `int`, `System.Index`/`^n`, and read-only range indexing for
ordinary arrays remain unchanged.

## 2026-06-14 — SoA column names are validated before wrapper emission

Experimental SoA declarations now reject duplicate column names and column names that collide with
generated wrapper members (`length`, `capacity`, `add`, `clear`, `ensureCapacity`, `copyRow`, and
`wrap`) during analysis. Invalid table shapes now produce source diagnostics instead of reaching
Reflection.Emit field or method definition failures.

## 2026-06-14 — SoA table member mutation fails before emission

The analyzer now rejects direct writes to experimental SoA wrapper members such as `table.column = arr`,
`table.length = n`, and `table.length++`. Row-column writes and explicit column-element writes remain
accepted, but table shape changes must go through construction, `wrap`, `add`, `clear`, `ensureCapacity`,
or `copyRow` so length, capacity, and backing columns stay consistent before IL lowering sees the code.

## 2026-06-14 — SoA row-column null-coalescing reads have IL-shape proof

Plain `table[row].column ?? fallback` over nullable/reference SoA columns now has runtime and
IL-shape evidence beside the existing `??=` proof. The pinned helpers cover both missing and
already-stored column values while keeping the read as direct backing-column array traffic with no
row object, boxing, hidden array allocation, delegate construction, or virtual dispatch.

## 2026-06-14 — SoA table indexes reject non-int and range operands before emission

The analyzer now enforces the row-index contract for experimental SoA tables: `table[index]` must use
an `int` row id. Non-int indexes such as strings and range/slice indexes now produce a SoA-specific
diagnostic pointing back to `table[index].column` instead of being treated as row views or drifting
into generic index/member behavior before IL emission.

## 2026-06-14 — Null-coalescing rejects non-nullable value operands before emission

The analyzer now rejects plain `??` when its left operand cannot be null, including SoA row-column value
reads such as `table[row].intColumn ?? fallback`. This closes the same silent-emission path already
closed for `??=`: non-nullable value columns now produce source diagnostics instead of reaching the IL
backend path that would treat the fallback as unreachable.

## 2026-06-14 — Raw lexer parity wrappers leave product dogfood

`LexerTokenKindScanner.nl` now keeps the compiler-routed composed lexer entry
`TokenizeMetadataWithIndentationInto` in the shipped dogfood source while moving raw parity entry points
(`TokenizeKinds`, `TokenizeKindsInto`, `TokenizeKindsCore`, `TokenizeMetadataInto`, `CommentsInto`,
`CommentsCore`, `TokenizeCount`, and `CopyKindsCore`) into the parity corpus. Product-only coverage pins
those probes absent from emission, and product+parity coverage keeps the lexer parity tests alive without
counting them as shipped compiler routing evidence.

## 2026-06-14 — Null-coalescing assignment rejects non-nullable value targets before emission

The analyzer now rejects `??=` when the assignment target cannot be null, including SoA row-column
value targets such as `table[row].intColumn ??= fallback`. This closes the path where the IL backend
could silently treat a non-nullable value column as already present instead of reporting a useful
source diagnostic.

## 2026-06-14 — SoA default row-column assignment expressions preserve default values

The SoA IL-shape evidence now covers `value := table[row].column = default` for scalar and nullable
reference columns. The expression returns the assigned default while the store goes straight through
the backing column arrays with no row object, boxing, hidden array allocation, delegate construction,
or virtual dispatch.

## 2026-06-14 — SoA null-coalescing row-column assignment expressions preserve values

The SoA IL-shape evidence now covers `value := table[row].column ??= fallback` in both null and
already-set cases. The expression returns the stored/current column value while keeping direct
column-array traffic and avoiding row objects, boxing, hidden array allocation, delegates, and
virtual dispatch.

## 2026-06-14 — SoA prefix row-column increment/decrement has IL-shape proof

The SoA IL-shape evidence now covers prefix row-column increment and decrement expressions. `++table[row].column`
and `--table[row].column` return the updated value, store through the backing column array, and stay free of row
objects, boxing, array allocation, delegate construction, and virtual dispatch.

## 2026-06-14 — Query-position parser leaves product dogfood

The `CliQueryParsing.nl` query-position probe cluster now lives entirely in the parity corpus:
`CliTryParsePositionInto`, the shared result/int tables, parser cores, whitespace helper, and min helper
all moved beside `CliQueryPositionsInto` and `CliQueryPositionChecksumInto`. The shipped product file
keeps the adapter-routed duplicate-rank and packed-result kernels, and coverage now pins the
query-position names absent from product-only emission but present in product+parity emission.

## 2026-06-14 — Semantic-scope scalar wrappers leave product dogfood

`SemanticScopes.nl` no longer emits the raw-array `SemanticScopeIdStartsBefore` and
`SemanticScopeClearTouched` helpers. The live product route keeps `SemanticScopeIdStartsBeforeCore`
inside the iterative sort and `SemanticScopeClearTouchedCore` inside name-set cleanup, while the
raw wrappers now live in the parity corpus and are pinned absent from product coverage.

## 2026-06-14 — Linter parity wrapper leaves product dogfood

`LinterImports.nl` no longer emits the raw-array `LinterImportsClearAllUsedFlags` helper. The shipped
unused-import kernel still exercises discarded non-void sibling calls through the table-shaped
`LinterImportsClearAllUsedFlagsCore` cleanup path, while the raw-array wrapper now lives in the parity
corpus beside the checksum oracle and is pinned absent from product coverage.

## 2026-06-14 — CLI lint project-value wrapper leaves product dogfood

`CliArguments.nl` no longer emits the raw-array `CliLintIsProjectOptionValue` wrapper. The live
`CliLintFileArgIndicesInto` product route still records `--project` value indices once and calls the
table-shaped `CliLintIsProjectOptionValueCore` helper directly, while the CLI adapter and benchmark
surface remain unchanged.

## 2026-06-14 — SoA row-column assignment expressions preserve assigned values

The SoA IL-shape evidence now covers row-column assignment expressions whose assigned value is consumed
by an enclosing initializer. Both `nodes[row].column += value` and `nodes[row].column = value` store
through the backing column arrays, leave the assigned value available, and still avoid row objects,
boxing, array allocation, delegate construction, and virtual dispatch.

## 2026-06-14 — SoA row-column compound assignment has IL-shape proof

The SoA IL-shape evidence now pins accepted compound assignment on row columns (`nodes[row].column +=`
and `*=`). The lowering reads and stores through the backing column arrays, preserves runtime semantics,
and stays free of row objects, boxing, array allocation, delegate construction, and virtual dispatch.

## 2026-06-14 — Stage 1-3b parity probes leave the compiler dogfood adapter

The declared-symbol, name-resolution, type-inference, definite-return/unreachable, and unused-local
columnar parity probes no longer live as private methods on `NSharpCompilerDogfoodAdapter`. The
focused tests now own a test-only `ColumnarDogfoodParityProbe` that loads the dogfood parser kernels
directly, preserving the same C#-AST mirror coverage while removing another non-product surface from
the compiler adapter. The production adapter keeps the default-on columnar emit route and live
compiler-service kernels only.

## 2026-06-14 — SoA default row-column stores have IL-shape proof

The SoA IL-shape evidence now covers `nodes[row].column = default` for both scalar and nullable
reference columns. The pinned helper stores directly into the backing column arrays, does not read
the old element value, and stays free of row objects, boxing, array allocation, delegate construction,
and virtual dispatch.

## 2026-06-14 — Parity-only probes leave the product dogfood directory

`CompilerDogfoodProjectTests` now reads product compiler-service files without their parity-corpus
twins when asserting shipped product coverage. `FormatterSafetyScan.nl`, `PathMatching.nl`, and
`ErrorSuggestions.nl` have been deleted from `src/NSharpLang.Compiler.Dogfood/CompilerServices`;
their extracted parity sources are still compiled through the dedicated product+parity merge and
per-file parity tests. Current coverage accounting is therefore product-only for routing evidence
and parity-merged only for rejected-probe evidence.

## 2026-06-14 — SoA null-conditional projections fail before emission

The analyzer now rejects null-conditional access on experimental SoA tables and row projections before
the IL backend sees them. `table?[index].column`, `table[index]?.column`, and `table?.column` now get
direct SoA diagnostics with column-access guidance instead of drifting into the generic null-conditional
member/index emitter, which only owns ordinary CLR reference/member shapes.

## 2026-06-14 — SoA row-view escape ratchets cover pattern, with-index, and block-lambda edges

The SoA row-view escape suite now pins three previously unratcheted analyzer paths: row views returned
from block-bodied lambdas, row views used as literal-pattern values at the analyzer AST boundary, and
row views used as `with` initializer indexes at that same boundary. All three report the SoA-specific
diagnostic with the standard `table[index].column` guidance instead of falling through to generic
typing or backend behavior.

## 2026-06-14 — Nameof targets are checked before emission

The analyzer now enforces the same `nameof` target shape the direct IL backend can emit: identifiers and
member accesses only. Unsupported targets report `NL103` during analysis instead of reaching
`EmitNameofExpression`, and SoA row-view targets get the row-specific diagnostic with the standard
`table[index].column` guidance. This closes another backend-crash path in the experimental SoA row-view
escape surface.

## 2026-06-14 — SoA wrap validation reports null and length failures directly

The generated experimental `Table.wrap(columns..., length)` method now separates all validation
branches. Null column arrays report `columns for TableName.wrap cannot be null`, active lengths below
zero or beyond column capacity report `length for TableName.wrap must be between 0 and column length`,
and mismatched column lengths keep the existing table-specific mismatch diagnostic.

## 2026-06-14 — SoA verified column types have runtime and IL proof

The experimental SoA wrapper proof now exercises every currently accepted column element kind:
`int`, `uint`, `long`, `bool`, `char`, `string`, `string?`, and aliases to those types. Runtime
coverage pins row load/store semantics across the full set, and IL-shape coverage keeps those
row projections as direct column-array traffic with no row allocation, boxing, hidden array
allocation, or dispatch.

## 2026-06-14 — SoA constructor IL shape is pinned

The experimental `new Table(capacity)` lowering now has direct IL-shape evidence: the constructor
allocates exactly one CLR array per declared column, initializes `length` and `capacity` fields
directly, and performs no row-object allocation, boxing, element traffic, or dispatch.

## 2026-06-14 — SoA row allocation requests report hidden allocation directly

`alloc (table[index])` now reports the design-level hidden-allocation diagnostic instead of the
generic row-escape wording. The analyzer points at the row access and tells the developer to use
column access, preserving the no-row-object contract for experimental SoA tables.

## 2026-06-14 — Anonymous-union shim trusted wrapper leaves product dogfood

`AnonymousUnionDeclaresPublicShimTrusted` no longer ships as a top-level dogfood export. The live
adapter ABI still binds `AnonymousUnionDeclaresPublicShim`, which now performs the bounds guard,
constructs the parameter table, and calls the table-shaped core directly. Reflection coverage pins
the public product surface so this transition-era convenience wrapper does not come back.

## 2026-06-14 — SoA wrap length mismatch reports a direct table diagnostic

The generated experimental `Table.wrap(columns..., length)` method now distinguishes mismatched
column-array lengths from other invalid arguments. Mismatched arrays throw
`column lengths for TableName do not match`, matching the SoA design requirement while preserving the
zero-copy reference-store lowering for valid wraps.

## 2026-06-14 — SoA unsupported column diagnostics are enforced

The experimental `soa record` analyzer now rejects column element types outside the verified wrapper
lowering set. The accepted set is `int`, `uint`, `long`, `bool`, `char`, `string`, `string?`, and
aliases to those types; broader object, array, enum, and user value-type columns stay behind a direct
`SoA column type 'X' is not supported in this lowering` diagnostic until their load/store shape is
IL-verified.

## 2026-06-14 — SoA add and ensureCapacity IL shape is pinned

The experimental SoA table-operation evidence now covers `add` and `ensureCapacity` directly.
`add` is pinned as a length read/update with one direct `ensureCapacity` call and no column traffic.
`ensureCapacity` is pinned to direct `Array.Resize` calls, one per column, followed by the capacity
field update; it must not allocate row objects, box, build delegates, or dispatch virtually.

## 2026-06-14 — SoA copyRow and clear IL shape is pinned

The experimental SoA wrapper proof now inspects the generated `copyRow` and `clear` methods directly.
`copyRow` is allowed only the direct `ensureCapacity` call before copying column-array elements; it must not
allocate row objects, box, build delegates, or dispatch virtually. `clear` is pinned as the minimal
`length = 0` field store with no column traffic. This tightens the emitter-port evidence for table operations,
not just row projection.

## 2026-06-14 — Formatter safety-scan rejected probe leaves product dogfood

`FormatterSafetyHasError`, `FormatterSafetyErrorIndicesInto`, and their small table/core helpers
moved to the parity corpus beside `FormatterSafetyErrorIndicesChecksumInto`. The scan remains
compiled for the original first-real-file parity/benchmark evidence, but it is not a product route:
the documented representative benchmark missed the 5x gate, so `Formatter.FormatSafe` stays on the
C# safety path.

## 2026-06-14 — Code-intelligence convenience wrappers leave product dogfood

The source-splitting convenience wrappers for identifier spans, editor spans, declaration-name
columns, member receivers, source contexts/lines, completion prefixes, doc comments, and variable
declaration names moved to the parity corpus beside their checksum or benchmark oracles. The now
unrouted non-cached member-receiver and variable-declaration `FromLines` helper pairs moved with
those wrappers. Product dogfood keeps the adapter-bound cached `FromLines`/`FromCache` kernels that
the code-intelligence service actually routes through.

## 2026-06-14 — Declared-type exact-name probe leaves product dogfood

`DeclaredTypeExactNameFirstIndex` and its tiny table/capacity helper moved to the parity corpus with
`DeclaredTypeExactNameFirstChecksum`. Product dogfood keeps the accepted declared-type suffix,
name-candidate, and creation-order routes; the exact-name first-wins scan remains benchmark-only
because it passed parity but missed the normal speed gate.

## 2026-06-14 — Typo-suggestion pressure probe leaves product dogfood

`TypoSuggestionIndicesInto` and its Levenshtein/scoring helper closure moved to the parity corpus
with `TypoSuggestionChecksumInto`. Production keeps the current C# `SmartSuggester` path because the
N# dynamic-programming candidate passed parity but missed the normal speed gate.

## 2026-06-14 — Path-matching pressure probe leaves product dogfood

`CodeIntelligencePathMatches`, `CodeIntelligencePathMatchFlagsInto`, and the private slash-normalized
case-fold helpers moved to the parity corpus with `CodeIntelligencePathMatchChecksumInto`. The probe
remains compiled for parity and real-file columnar coverage, but production path matching stays on the
current C# helper because the N# char-loop candidate missed the normal speed gate.

## 2026-06-14 — Diagnostic-cluster public-string probes leave product dogfood

`DiagnosticClusterTraitsAndPatternsInto`, `DiagnosticClusterIdsInto`, and
`DiagnosticClusterNextCommandsInto` plus their private public-string materialization helpers moved to
the parity corpus beside their checksum oracles. Product dogfood still keeps the accepted trait and
compact grouping/member routes the code-intelligence adapter calls, while the missed-speed
message-pattern/id/next-command probes no longer ship in the product assembly.

## 2026-06-14 — Query-position batch probe leaves product dogfood

`CliQueryPositionsInto`, its batch core, the private position input table, and later the scalar
query-position parser cluster moved to the parity corpus beside `CliQueryPositionChecksumInto`.
Product dogfood keeps only the adapter-routed duplicate-rank and packed-result query kernels, while
the benchmark-only `nlc query --pos` pressure path no longer ships in the product assembly.

## 2026-06-14 — Build-operand batch wrappers leave product dogfood

`CliBuildOperandSummaryInto`, `CliBuildOperandIndicesInto`, and the batch index core moved to the
parity corpus. The product dogfood file keeps `CliBuildOperandSummaryCore` because the accepted
`CliBuildFirstOperandIndexInto` adapter route still calls it for leading-option fallback cases, but
the direct batch wrappers no longer ship in the product dogfood assembly.

## 2026-06-14 — Fix-edit flattening probe leaves product dogfood

`CliFixEditFlattenIndicesInto`, its table core, and the private flatten table wrappers moved to the
parity corpus beside `CliFixEditFlattenChecksumInto`. The shipped `nlc fix` path still uses the C#
`SelectMany(...).ToList()` edit materialization because the N# pressure kernel missed the 5x route
gate, so the benchmark-only flatten probe no longer ships in the product dogfood assembly.

## 2026-06-14 — Build-option summary probe leaves product dogfood

`CliBuildOptionSummaryInto`, its table core, and the private option-kind classifier now live in the
parity corpus with `CliBuildOptionSummaryChecksumInto`. The shipped CLI path still uses the accepted
`CliBuildFirstOperandIndexInto` route for build operands and keeps build option discovery in C#, so
the old benchmark-only build-option summary probe no longer ships in the product dogfood assembly.

## 2026-06-14 — Positional-argument batch probe leaves product dogfood

`CliPositionalArgIndicesInto` and its batch core moved from product `CliArguments.nl` to the parity
corpus beside `CliPositionalArgChecksumInto`. The live CLI adapter still uses the scalar
`CliFirstPositionalArgIndex` ABI, while the benchmark-only batch positional scan no longer ships in
the product dogfood assembly.

## 2026-06-14 — Watch-argument forwarding probe leaves product dogfood

`CliWatchForwardedArgIndicesInto` and its watch-option helper moved from product `CliArguments.nl` to
the parity corpus beside `CliWatchForwardedArgChecksumInto`. The benchmark/parity evidence remains
available when compiling the parity corpus, but the shipped dogfood assembly no longer exposes this
unrouted `nlc watch` argument probe.

## 2026-06-14 — Reference-resolution score probe leaves product dogfood

`CliReferenceResolutionBestScoreIndex` and its private score table moved out of product `CliArguments.nl`
into the parity corpus beside `CliReferenceResolutionBestScoreChecksum`. The probe remains compiled and
checked with the parity batch, but the shipped dogfood assembly no longer exposes a benchmark-only CLI
reference-resolution helper with no adapter or command caller.

## 2026-06-14 — SoA records are first-class in language-server navigation

The language server now treats `soa record` declarations as navigable type symbols instead of dropping
them at the IDE boundary. Document symbols show the SoA declaration with its column fields, workspace
symbols index both the declaration and columns, selection ranges descend to column lines, and CodeLens
emits the normal reference lens on the declaration. This keeps the systems-language data layout work
visible in the same VS Code/LLM-facing surfaces as classes, records, structs, and enums.

## 2026-06-14 — SoA row-view event target coverage is pinned

The SoA row-view escape suite now pins event subscription targets as well as unsubscribe handles.
`on table[index] (...) => { }` reports the SoA-specific diagnostic with the `table[index].column`
guidance instead of falling through to the generic event-target validation path, so both event
subscription boundaries are covered by focused tests.

## 2026-06-14 — Analyzer overload-signature parity probe leaves product dogfood

The overload-signature distinctness probe in `AnalyzerExhaustiveness.nl` has moved to the parity corpus
with its checksum batch oracle. Product dogfood still exposes the analyzer exhaustiveness kernels the
C# adapter calls for missing members and union cases, but no longer ships the rank-buffer/table helpers
used only by overload-signature parity tests.

## 2026-06-14 — Format-discovery path filtering stops shipping as dogfood product surface

The remaining `CliShouldFormatDiscoveredPath` test/parity island now lives wholly in the parity corpus:
the path table, scalar predicate, batch flag core, and segment comparison helpers moved out of product
`CliArguments.nl`. The parity tests still compile the path-filter oracle with the product kernels, but
the shipped dogfood assembly no longer exposes format-discovery helpers with no CLI or adapter caller.

## 2026-06-14 — Parity-only CLI and overload cores leave the shipped dogfood surface

`CliTestOptionSummaryCore` now lives in the parity corpus beside its checksum oracle instead of the
product `CliArguments.nl` compiler-service file. The table/batch-only overload candidate probes moved
the same way: their parameter/call/result table structs and core functions are now parity-corpus
support code, while the shipped product dogfood file keeps only the scalar overload selector that the
compiler adapter actually calls.

## 2026-06-14 — Analyzer records `base` expressions as their base type

Bare `base` expressions and `base.member` receivers now get the same semantic type the IL backend already
uses when emitting them: the declared base class when one exists, otherwise `object` for the implicit CLR base.
This keeps semantic-model queries from reporting `unknown` for a parser/compiler-supported expression form.

## 2026-06-14 — Analyzer records `sizeof` as an `int` expression

`sizeof(T)` now participates in semantic analysis instead of falling through to `unknown`. The analyzer
validates the operand type and records the expression as `int`, matching the IL backend's `sizeof` lowering
and keeping semantic-model consumers from losing type information for a parser/IL-supported expression form.

## 2026-06-14 — SoA row-view escape diagnostics cover tuple elements

Tuple expressions now analyze their elements and report the SoA-specific escape diagnostic when an element
is a row view. A tuple literal such as `(row: table[i], fallback: 0)` can no longer package a bare row
while the runtime has no public row object model.

## 2026-06-14 — SoA row-view escape diagnostics cover discards and yields

SoA row views now report the SoA-specific escape diagnostic when they are explicitly discarded with
`_ = row` or yielded from iterator bodies. Yield statements also analyze their yielded expression now,
so generator bodies do not skip row-view validation.

## 2026-06-14 — SoA row-view escape diagnostics cover thrown values

SoA row views now report the SoA-specific escape diagnostic when they are used as thrown values in both
`throw value` statements and `throw value` expressions. Throw expressions also analyze their operand now,
so row-view misuse cannot hide behind `condition ? value : throw row`.

## 2026-06-14 — SoA row-view escape diagnostics cover expression-body returns

SoA row views now report the SoA-specific return diagnostic across expression-bodied functions, local
functions, properties, typed delegate lambdas, and inferred zero-parameter lambdas. That closes the return
edge for every expression-body form, so a bare row view cannot become a function value or property result
while the runtime still has no public row object model.

Focused SoA coverage pins each expression-body path to the same actionable `table[index].column` guidance
used by explicit `return` statements.

## 2026-06-14 — SoA row-view escape diagnostics cover initializer and constructor boundaries

SoA row views now report the SoA-specific escape diagnostic when they appear in array literals,
array/collection initializer values, constructor arguments, `print` values, or interpolated-string
holes. The existing return-path diagnostic is also pinned by coverage, so row views cannot leak through
the common storage/API boundaries while the runtime still has no public row object model.

Focused SoA coverage asserts each path reports the actionable `table[index].column` guidance instead
of allowing a row view to become an array element, initializer value, constructed-object argument, or
formatted/printed value.

## 2026-06-14 — Parity-only dogfood wrappers stop shipping

Several checksum-only dogfood helper wrappers now live entirely in the parity corpus instead of the
product dogfood surface. The parity oracles call the table-shaped cores directly for overload batch
selection, overload signature distinctness, CLI query position parsing, CLI test option summaries, and
format-discovered-path filtering; the variable-declaration-name cached checksum now composes the live
cache-build and cache-query entries directly.

This removes redundant array-shaped exports from the shipped dogfood assembly while preserving the
same parity coverage and the live host ABIs used by the compiler, CLI, and code-intelligence adapters.

## 2026-06-13 — SoA row-column assignment statements stop reloading discarded values

SoA row-column assignments now use the statement-context lowering path directly. Plain row writes like
`nodes[row].kind = 3` and compound row writes like `nodes[row].kind += 1` reuse the existing column-array
store lowering with `leaveValueOnStack: false`, instead of emitting an assignment expression result and then
letting the expression-statement wrapper discard it with `pop`.

IL-shape coverage now asserts representative row writes have no discard `pop` while still using direct
column-field loads plus array element loads/stores and no row allocation or dispatch.

## 2026-06-13 — SoA row-column increments lower to columns

The experimental SoA wrapper emitter now handles `++` and `--` on row-column projections without routing
through the normal member-addressing path. `nodes[row].kind++` caches the backing column array and row index
once, reads the current element, stores the updated element back into the same column array, and preserves the
postfix expression value when the increment is used as an expression.

Behavior coverage pins postfix increment/decrement semantics across expression and statement contexts. IL-shape
coverage asserts the row-column update uses direct column-field loads plus array element loads/stores, with no
row allocation, boxing, delegate construction, heap array allocation, or virtual dispatch.

## 2026-06-13 — SoA row-column null-coalescing assignment lowers to columns

The experimental SoA wrapper emitter no longer throws if a row-column assignment uses `??=`.
`nodes[row].text ??= "fallback"` now uses the same single-evaluation shape as normal indexed
null-coalescing assignment: cache the backing column array and row index, load the current element,
branch when it already has a value, and store only the fallback value back into the column array.

Behavior coverage proves null values are adopted and non-null values are preserved. IL-shape coverage pins
the important SoA invariant: direct column-field loads plus array element loads/stores, with no row object
allocation, boxing, delegate construction, or virtual dispatch.

## 2026-06-13 — Roadmap cursor syncs to route-all and SoA-stage reality

`roadmap-to-done.md` now reflects the imported endgame state instead of the older Stage-5/6 snapshot:
route-all/default-on has landed, the Phase-P columnar ports and IF-2 residuals are complete, and Stage 6 is
now a C# surface-shrink plus SoA/emitter-port proof phase rather than a rich-language coverage wait. The
stale multi-file route comment in `NSharpCompilerDogfoodAdapter` now describes the current default-on
Stage-5 route instead of "remaining work".

This is documentation/comment-only, but it is an execution fix: future self-host slices should start from
SoA wrapper evidence or redundant adapter-surface deletion, not from the completed scalar/route-all queue.

## 2026-06-13 — Binding lookup drops unused flattened helper exports

`BindingLookup.nl` no longer emits declaration-only flattened wrappers for strict lookup equality,
hash-slot lookup, candidate-column compact sorting, or candidate-column append. The live
code-intelligence adapter entries remain `BindingLookupBuildSlotsInto`,
`BindingLookupQueryDeclarationIndicesInto`, `BindingLookupCandidateColumnsInto`,
`BindingLookupBuildNearestDeclarationIndexInto`, and `BindingLookupFindNearestDeclarationIndicesInto`;
those still route through the table-shaped cores directly.

This removes the final low-reference dogfood compiler-service helper exports while leaving the
production semantic lookup ABI unchanged.

## 2026-06-13 — Lexer indentation standalone wrapper retired

`LexerTokenKindScanner.nl` no longer emits the standalone flattened `InsertIndentationBracesInto`
entry. The indentation post-pass remains in N# as `InsertIndentationBracesCore`, and the production
dogfood adapter/test route continues through the composed `TokenizeMetadataWithIndentationInto`
entry that tokenizes raw metadata and invokes the core directly.

This removes the last non-code-intelligence single-reference compiler-service export surfaced by the
backend cleanup sweep while preserving the token-stream ABI used by the compiler and parity tests.

## 2026-06-13 — Unrouted CLI test-filter benchmark probe retired

`CliArguments.nl` no longer carries the `CliTestFilterMatchIndicesInto` benchmark probe or its private
test-name/filter helper tables. The probe had parity evidence and zero-allocation dry-run results, but
the documented benchmark topped out around 2x and explicitly missed the 5x production routing gate, so
it was never adapter-bound or used by `nlc test --filter`.

The historical benchmark finding remains documented in `compiler-dogfood-rewrite.md`; the live dogfood
source now keeps only CLI kernels that are routed, coverage-pinned, or still active transition targets.

## 2026-06-13 — Compiler-service kernels drop unused flattened helper exports

The query-position parser, project-source filter, diagnostic clustering, diagnostic/reference
deduplication, and typo-suggestion kernels no longer emit declaration-only flattened wrappers around
their table-shaped cores when those wrappers have no production, adapter, parity, or test callers. The
stable batch entries such as `CliTryParsePositionPartsInto`, `ProjectSourceFilterKeptIndicesInto`,
`DiagnosticClusterCompactGroupsInto`, `DiagnosticDeduplicateInto`, and `TypoSuggestionIndicesInto`
continue to own the host ABI, while real-file columnar coverage pins such as
`SortDiagnosticDeduplicationIndices` and `IsDiagnosticClusterRootBefore` remain in place.

This keeps backend compiler-service dogfood code centered on table-wrapped product routes instead of
old scalar and sort-helper compatibility conveniences.

## 2026-06-13 — CLI argument kernels drop wrapper-only scalar helpers

`CliArguments.nl` no longer emits single-item raw helper wrappers that had no source, adapter, parity, or
test callers. Tidy classification/removal, test-filter matching, option-value classification, and build
remove-option pairing now expose only the stable batch `...Into` entries plus their wrapper-aware core
helpers.

This keeps the CLI dogfood surface focused on product routes instead of scalar compatibility conveniences.

## 2026-06-13 — Semantic-scope query internals drop unused raw helper exports

`SemanticScopes.nl` no longer emits raw-array wrappers for internal scope lookup and name-set operations.
`SemanticScopeFindBestContainingScope`, `SemanticScopeFindBestContainingScopeByScan`, and
`SemanticScopeAddNameToSet` were declaration-only helpers after the visible-symbol and lookup kernels moved
onto `SemanticScopePositionTable`, `SemanticScopeSortedIndexTable`, and `SemanticScopeNameSetScratch`.

The adapter-bound semantic-scope entries and the parser-coverage helpers remain unchanged.

## 2026-06-13 — Lexer and ordering kernels drop declaration-only pass shims

`LexerTokenKindScanner.nl`, `TextEditOrdering.nl`, and `FormatterImportOrdering.nl` no longer emit
flattened helpers that had no remaining source, adapter, parity, or test callers. `CopyKinds`,
`TextEditOrderCountingPass`, `FormatterImportOrderNamePass`, and `FormatterImportOrderSystemPass`
are gone; their adapter-bound entry points already route through the wrapper-aware cores directly.

The stable host ABIs remain unchanged: `TokenizeKinds`, `TokenizeKindsInto`,
`TextEditOrderIndicesInto`, and `FormatterImportOrderIndicesInto` still own the external boundary.

## 2026-06-13 — Parser kernels drop unused flattened compatibility wrappers

The type-reference and statement parser kernels no longer emit raw-array compatibility helpers for internal
recursive-descent steps. `ConsumeGreaterForTypeNode`, `ParseUnionTypeReferenceNode`, and
`ParseBlockStatementNode` were unused flattened wrappers around table-based cores; the stable host entries
remain `ParseTypeReferenceNodesInto` and `ParseStatementNodesInto`.

The real cross-file parser dependency now stays on `ParseUnionTypeReferenceNodeCore`, which carries named
token, node, argument-stack, and child-index tables instead of rebuilding those views from raw columns.

## 2026-06-13 — CLI and performance dogfood adapter scratch members stop advertising public visibility

`NSharpCliDogfoodAdapter` and `NSharpPerformanceDogfoodAdapter` no longer have source-level `public`
members inside their private scratch buffers. Those buffers are implementation details for flattened
adapter shims around N# kernels, so their arrays, counters, and reset/capacity helpers now use internal
visibility instead of looking like public object surface.

This is behavior-neutral, but it keeps the remaining CLI/performance C# transition scaffolding aligned
with the compiler adapter cleanup.

## 2026-06-13 — Columnar analysis probes stop advertising assembly-internal entry points

The Stage 1-3b columnar parity probes on `NSharpCompilerDogfoodAdapter` are now private helper entries
rather than assembly-internal surface. Production routing only needs `TryEmitColumnarProgram` and
`TryEmitColumnarProgramMultiFile`; the symbol, name-resolution, type-inference, structural-diagnostic,
and unused-local probes are test-only scaffolding kept reachable through non-public reflection.

This removes another adapter-facing transition seam without changing the default columnar backend route.

## 2026-06-13 — Compiler dogfood adapter scratch members stop advertising public visibility

`NSharpCompilerDogfoodAdapter` no longer has source-level `public` declarations inside its private
columnar token bundle, semantic-scope cache, or scratch buffers. Those members are purely transitional
adapter internals, so they now use internal visibility rather than looking like API-shaped service surface.

This is behavior-neutral cleanup, but it keeps the remaining C# adapter boundary honest while Stage 6
continues shrinking it.

## 2026-06-13 — Columnar program emission drops test-only overload

`NSharpCompilerDogfoodAdapter.TryEmitColumnarProgram` now has one entry shape: the production-shaped
assembly/type-named route used by `MultiFileCompiler`. The old four-argument convenience overload was only
used by tests after the single-function spike route was retired, so the tests now exercise the same signature
as production.

This removes another adapter-only convenience surface from the C# transition layer.

## 2026-06-13 — Columnar implementation members stop advertising public visibility

All source-level `public` declarations under `src/NSharpLang.Compiler/Columnar` are now internal. The
columnar backend types were already assembly-internal after the adapter cleanup, so this is a behavior-neutral
surface tightening: DTO constructors/properties, analysis pass entry points, lattice helpers, and private
emitter helper shapes no longer look like supported product APIs inside the transitional C# implementation.

This keeps the standalone columnar backend aligned with the Stage 6 rule: the C# code is a temporary
implementation boundary, not a public service layer.

## 2026-06-13 — Single-function columnar spike route retired

The old `TryEmitColumnarFunction` / `TryEmitSingleFunctionAssembly` path is gone. The former spike
coverage now exercises the same whole-program `TryEmitColumnarProgram` route that production uses, and
the obsolete `ColumnarSpike` wrapper assembly/type no longer exists.

This deletes another parallel adapter/emitter entry after the standalone columnar backend became the
default production route.

## 2026-06-13 — Columnar function inputs drop raw body accessors

`ColumnarFunctionInput` now has a single body-table representation: the internal `ColumnarNodeTable`
view built at the adapter/parser boundary. Its old raw-array constructor and raw `Kinds`/`ValueStarts`/
`Child*` compatibility accessors are gone.

This removes the last anonymous function-body table escape hatch from the C# columnar input model; callers
must carry the named node-table view that the emitter and analysis passes already consume.

## 2026-06-13 — Columnar transition API is compiler-internal

The standalone columnar C# transition model is no longer exposed as public compiler package API.
`ColumnarProgramInput`, the declaration input DTOs, `ColumnarIlEmitter`, the columnar analysis passes,
and the shared parity helpers now live behind `internal` compiler boundaries while remaining visible to
the friend test assembly.

This keeps the temporary C# bridge from hardening into a supported service surface as Stage 6 continues
to delete adapter/orchestration code around the N#-owned columnar pipeline.

## 2026-06-13 — Columnar transition classes drop flattened compatibility shims

`ColumnarNameResolver`, `ColumnarTypeInferer`, and `ColumnarDiagnosticsPass` now expose only their
`ColumnarNodeTable` constructors inside the compiler assembly. `ColumnarIlEmitter` likewise dropped
the old flattened single-function and wide whole-program emission overloads; production now enters
through `ColumnarFunctionInput` and `ColumnarProgramInput`.

This removes another C# transition-layer surface after the adapter stopped passing anonymous node and
declaration arrays through those routes.

## 2026-06-13 — Columnar function collector drops final source-string shim

`TryEmitColumnarFunction` now owns its one-time tokenization and then calls the
`ColumnarTokenizedSource`-shaped function collector directly. This removes the last private
source-string collector overload from `NSharpCompilerDogfoodAdapter` while preserving the standalone
single-function spike's decline behavior.

All declaration-family collectors now share the same named tokenized-source contract.

## 2026-06-13 — Columnar type-family collectors drop source-string shims

The enum, struct/class/record, union, and interface input collectors now expose only the
`ColumnarTokenizedSource`-shaped entry points used by whole-program collection. Their old private
source-string overloads were no longer called after program input collection began tokenizing once
and sharing the bundle across declaration families.

The single-function source-string shim remains intentionally scoped to `TryEmitColumnarFunction`,
which still owns the standalone function-emission spike behavior.

## 2026-06-13 — Columnar declaration-index helper uses tokenized source only

The top-level function declaration-index helper now has a single token-bundle-shaped entry point.
After the symbol, name-resolution, type-inference, structural-diagnostic, and unused-local parity
passes moved to `ColumnarTokenizedSource`, the older raw-array overload was dead adapter surface and
has been removed.

This keeps declaration-family discovery behind the same named source-input contract as the rest of
the columnar top-level function pipeline.

## 2026-06-13 — Columnar unused-local diagnostics reuse tokenized source inputs

The Stage 3b unused-local parity pass now consumes `ColumnarTokenizedSource` instead of owning its
own local tokenize/compact sequence. It reuses the bundle's raw line/column columns for NL001
position parity and the shared compact columns for signature/body parsing.

Unused-local parity remains the correctness gate. This removes the final local tokenize/compact
sequence from the top-level function symbol/name/type/diagnostic parity passes.

## 2026-06-13 — Columnar diagnostics reuse tokenized source inputs

The Stage 3b structural diagnostics parity pass now consumes `ColumnarTokenizedSource` instead of
owning another local tokenize/compact sequence. The token bundle now carries the tokenizer's raw
line/column columns, so diagnostics can keep exact position parity while sharing the same raw and
compacted token columns used by symbols, name resolution, type inference, and program collection.

Definite-return, unreachable-code, and finally-transfer parity remain the correctness gates. The
unused-local pass still has its own local token setup and is the next narrow cleanup target.

## 2026-06-13 — Columnar type inference reuses tokenized source inputs

The Stage 3 top-level function type-inference parity pass now starts from
`ColumnarTokenizedSource` instead of owning another local tokenize/compact sequence. Its signature
pass and body pass both consume the shared compact token columns while retaining the same
function-return map and body inference behavior.

Type-inference parity remains the correctness gate. This continues shrinking the adapter surface
around one named source-input contract for the columnar stages.

## 2026-06-13 — Columnar name resolution reuses tokenized source inputs

The Stage 2 top-level function name-resolution parity pass now consumes the shared
`ColumnarTokenizedSource` bundle instead of owning another local tokenize/compact sequence. Raw
token columns still feed the declaration-name span kernel, while compacted columns feed signature
and body parsing.

Name-resolution parity remains the correctness gate. This keeps another columnar stage on the same
source-input contract as program collection and symbol building.

## 2026-06-13 — Columnar symbol pass reuses tokenized source inputs

The Stage 1 top-level function symbol builder now consumes the same `ColumnarTokenizedSource`
bundle used by program-input collection. It reuses the bundle's raw token columns, compacted token
columns, and declaration-kind rows instead of owning a local tokenize/compact/declaration-kind
sequence.

Symbol parity remains the correctness gate; this continues the adapter cleanup by keeping token table
ownership in one helper instead of scattering anonymous token arrays through each columnar stage.

## 2026-06-13 — Columnar program input collection shares token tables

`NSharpCompilerDogfoodAdapter.TryGetColumnarProgramInput` now tokenizes and compacts a source once,
then shares that token bundle across function, enum, struct/class/record, union, and interface input
collection. The older private string-shaped collectors remain as compatibility shims that tokenize
for their own callers, but the default whole-program Stage 5 route no longer repeats the same
tokenization work for every declaration family.

This is a transition-boundary cleanup, not a new benchmark claim: it keeps the current semantics and
decline behavior while moving the program collector toward one named columnar source input.

## 2026-06-13 — Columnar function inputs own body-node views

`ColumnarFunctionInput` now stores its function-body forest as a `ColumnarNodeTable` rather than
retaining six independent raw body-column fields and reconstructing the view at every emitter access.
The public raw-array properties remain as compatibility accessors over the stored table.

`NSharpCompilerDogfoodAdapter` now wraps parser-produced body columns once when it creates regular
functions, constructors, property getters, and property setters. This keeps raw parser arrays at the
kernel boundary while the columnar program/emitter path carries named node-table inputs.

## 2026-06-13 — Columnar program emission consumes program inputs

`ColumnarIlEmitter` now accepts a `ColumnarProgramInput` bundle for whole-program emission: source
text, functions, enums, structs, unions, and interfaces travel as one typed compiler input instead of
five separate declaration lists plus a source string. The old wide `TryEmitColumnarAssembly`
signature remains as a compatibility shim and delegates through the program-input overload.

`NSharpCompilerDogfoodAdapter.TryEmitColumnarProgram` now constructs that bundle once before calling
the emitter. This keeps the C# transition boundary moving from raw argument plumbing toward named
columnar compiler inputs without changing the default-on Stage 5 routing behavior.

## 2026-06-13 — Columnar single-function spike consumes function inputs

The original single-function columnar spike path now accepts a `ColumnarFunctionInput` directly.
`NSharpCompilerDogfoodAdapter.TryEmitColumnarFunction` no longer peels an already-parsed function back
into six raw body columns just to call the emitter. The flattened `TryEmitSingleFunctionAssembly`
signature remains as a compatibility shim and delegates through the function-input overload.

This closes the last raw body-table handoff in the C# adapter/emitter spike route while preserving
the public spike helper used by tests and external callers.

## 2026-06-13 — Columnar analysis passes accept node table views

`ColumnarNameResolver`, `ColumnarTypeInferer`, and `ColumnarDiagnosticsPass` now have internal
constructors that consume `ColumnarNodeTable` directly. Their flattened public constructors remain as
compatibility shims, but `NSharpCompilerDogfoodAdapter` now wraps parser-produced body columns once
and passes the shared node-table view into the analysis passes.

This keeps raw statement-node columns at the parser-kernel boundary. Name resolution, type inference,
definite-return/unreachable/finally-transfer diagnostics, and unused-local analysis now all enter
through the same named node accessor surface used by the emitter.

## 2026-06-13 — Columnar function inputs expose body-node views

`ColumnarFunctionInput` now exposes an internal `BodyNodes` view over its flattened body columns, and
`ColumnarIlEmitter` routes top-level, local-function, interface-method, struct-method, and constructor
body emission through that view. The public flattened arrays stay in place for adapter and test
compatibility, but emitter orchestration no longer rebuilds six-column node-table arguments at every
call site.

With those call sites converted, the private array-based emitter constructor was removed. Emitter
instances now enter through `ColumnarNodeTable` directly, keeping raw node columns at input boundaries
instead of transition-layer service paths.

## 2026-06-13 — Columnar binding-name scan uses node table view

`ColumnarIlEmitter`'s local-function parent-binding pre-scan now walks statement nodes through
`ColumnarNodeTable` instead of receiving six raw node columns. The public columnar function input
and flattened adapter contracts remain unchanged, but the recursive binding-name helper no longer
duplicates kind/value/child indexing logic outside the shared table view.

This keeps the C# transition code aligned with the node-table cleanup: raw node columns now stay at
ABI boundaries or inside `ColumnarNodeTable`, while emitter-local analysis helpers consume named
node accessors.

## 2026-06-13 — Columnar IL emitter node table view adopted

`ColumnarIlEmitter` now stores the shared statement/expression forest through `ColumnarNodeTable`,
matching the smaller columnar name-resolution, type-inference, and diagnostics passes. The flattened
array-based constructor remains available at the current adapter boundary, but nested emitters reuse
the named table view and emitter logic no longer owns kind/value/child columns as anonymous
parallel-array fields.

This is still a representation-cleanup slice, not an emitter routing or benchmark claim. It removes
the remaining raw columnar node-table fields from the C# columnar frontend/backend transition code;
future work still needs to move the emitter logic itself out of C#.

## 2026-06-13 — Columnar name resolver node table view adopted

`ColumnarNameResolver` now consumes the shared `ColumnarNodeTable` view internally, matching the
type-inference and diagnostics passes. The constructor remains flattened for the current adapter
boundary, but lexical name resolution no longer stores node kind/value/child columns as anonymous
parallel-array fields.

This removes the last raw columnar node-table fields from the small C# columnar analysis/name
resolution passes. `ColumnarIlEmitter` still owns its larger emitter-local column fields and remains
a separate, higher-risk migration target.

## 2026-06-13 — Columnar analyzer node table view introduced

`ColumnarTypeInferer` and `ColumnarDiagnosticsPass` now share a named `ColumnarNodeTable` view for
node kind, value-span, child-run, child-index, and diagnostic span columns. Their public constructor
shape remains unchanged for the current C# transition boundary, but the implementation no longer
carries the columnar node forest as six or seven anonymous parallel-array fields.

This is a representation-cleanup slice, not a production routing or benchmark claim: no adapter was
removed and bootstrap coverage is unchanged. It narrows the C# analyzer scaffolding that still
stands between the N# parser tables and a fully N#-owned analyzer/binder pipeline.

## 2026-06-13 — Parser declaration result slots wrapped

`ParserDeclarations.nl` now also routes declaration-parser scalar result slots through
`ParserDeclarationResultTable` inside its core functions. The public `outResult: int[]` delegate
contracts remain unchanged, while package, interface, enum, struct/class/record, constructor-chain,
and union parser bodies no longer write result slots through anonymous arrays.

This completes the current declaration-parser wrapper cleanup: token streams, output columns, and
result slots are all named tables past the flattened adapter boundary.

## 2026-06-13 — Parser declaration token streams wrapped

`ParserDeclarations.nl` now keeps its flattened declaration parser ABI but routes every body through
named token-stream wrappers. Package/header scans, top-level declaration kind/name/modifier scans,
interface, enum, struct/class/record, constructor-chain, and union declaration parsers now consume
`ParserDeclarationTokenTable` or `ParserDeclarationKindStream` cores instead of carrying raw
token-kind/start/length arrays through the implementation.

The existing declaration output table wrappers remain unchanged, so the dogfood adapter still calls
the same public entry points. Focused parser declaration parity and merged dogfood corpus route tests
passed, as did the full non-VS-Code product gate.

## 2026-06-13 — Binder reconciliation: unary and bitwise promotion fixed

The production analyzer now concretely types the ECMA numeric surface that stage-3 columnar review
had flagged as a binder gap: unary `-` promotes small integrals to `int` and `uint` to `long`,
unary `~` applies integral unary promotion, bitwise `& | ^` type bool/bool as `bool` and integral
operands as their binary-promoted integral type, and shifts promote the left operand only.

`ColumnarTypeLattice` now matches those analyzer rules instead of preserving the old `Unknown` /
`External` behavior. Regression coverage pins semantic-model types for built-in analyzer cases,
declared bitwise/shift/unary operator overloads, target-typed signed negative integer literals,
and the columnar AST-vs-table type-inference parity corpus.

## 2026-06-13 — Semantic scope query and sort scratch tables wrapped

`SemanticScopes.nl` now carries visible-symbol queries/results, lookup queries/results, and
sorted-index scratch storage through named normal structs in its internal cores. The exported
dogfood adapter entry points still expose the same flattened arrays, while
`SemanticScopeVisibleSymbolIndicesCore`, `SemanticScopeLookupSymbolIndicesCore`, and
`SemanticScopeBuildSortedIndexCore` no longer receive anonymous query/result/scratch columns.

The sorted-index helper path now compares IDs through `SemanticScopeSortSourceTable`, and the depth
walk helper uses `SemanticScopeDepthTable`, keeping raw array parameters at compatibility boundaries
only.

## 2026-06-13 — Parser expression recursion tables wrapped

`ParserExpressions.nl` now routes its pattern, primary, postfix, call-argument, unary, binary,
ternary, assignment, lambda, and expression-entry recursion through shared parser token,
argument-stack, child-index, expression-node, and result wrappers. The public
`ParseExpressionNodesInto` ABI remains flattened, while `ParseExpressionNodesCore` carries the
wrapper-aware implementation.

Expression parsing now composes type-reference parsing through `ParseExpressionTypeReferenceNode`,
which views the shared expression node columns as a type node table and calls
`ParseUnionTypeReferenceNodeCore` directly. `ParserStatements.nl` was updated to call the expression
parser with wrappers from its own statement cores, leaving flattened arrays at host/compatibility
boundaries only.

## 2026-06-13 — Parser statement recursion tables wrapped

`ParserStatements.nl` now routes its recursive statement kernels through shared parser token,
argument-stack, child-index, expression-node, and result table wrappers. The flattened
`ParseStatementNodesInto` host entry remains stable, and `ParseBlockStatementNode` is retained as a
flattened compatibility shim for expression-parser block-bodied lambda calls.

The internal `ParseBlockStatementNodeCore`, `ParseStatementCoreNode`, `ParseSimpleStatementNode`, and
`ParseStatementNodesCore` signatures no longer carry raw parallel arrays, while calls into the still
flattened expression parser bridge through the wrapper columns.

## 2026-06-13 — Parser function-signature tables wrapped

`ParserFunctionSignatures.nl` now keeps its flattened `ParseFunctionSignatureInto` ABI as a host
entry shim, then routes the parser body through a wrapper-aware `ParseFunctionSignatureCore`.
Function parameters, type parameters, generic constraint rows, parser tokens, type-reference argument
scratch, child-index output, type-node output, and result slots are grouped behind named table
structs.

The slice also composes the type-reference parser through `ParseUnionTypeReferenceNodeCore`, so
function signatures no longer re-flatten the token/type-node tables when parsing parameter types,
return types, or `where` constraint type roots.

## 2026-06-13 — Parser type-reference token tables wrapped

`ParserTypeReferences.nl` now wraps the recursive type-reference parser's token stream, argument
stack, child-index output, and result slots behind named normal structs. The public flattened entries
remain available for parser cross-file calls and host adapters, while `ParseBaseTypeReferenceNodeCore`,
`ParsePostfixTypeReferenceNodeCore`, `ParseUnionTypeReferenceNodeCore`, and
`ParseTypeReferenceNodesCore` now route through wrapper-aware parser tables.

`ConsumeGreaterForTypeNode` also keeps its flattened compatibility signature for expression-parser
callers and forwards to a token-table core, so existing parser expression call sites do not need to
change in the same slice.

## 2026-06-13 — CLI test filter and format path tables wrapped

`CliArguments.nl` now wraps the remaining test-filter and format-discovery batch columns behind named
normal structs. Test filter matching routes filter parts, primary/secondary/tertiary names, and
result indexes through wrapper-aware cores, while format discovery routes path batches and output
flags through path/flag tables.

This completes the current `CliArguments.nl` table-wrapper pass: the exported dogfood adapter
functions still expose the stable flattened array ABI, and the remaining array parameters in the
file are compatibility shims or scalar helper shims over wrapper-aware cores.

## 2026-06-13 — CLI dependency and reference rank tables wrapped

`CliArguments.nl` now wraps the update-dependency, reference-type, stable-distinct, best-score, and
summary-counter rank/flag/score columns behind named normal structs. The exported CLI dogfood
adapter functions keep their flattened caller-owned array signatures, while the internal cores use
wrapper-aware flag, rank, seen-rank, score, index-result, and count-result tables.

This covers the `nlc update` dependency filters, reference resolution type filtering, stable
distinct rank selection, reference best-score selection, tidy dependency summaries, and test outcome
summaries.

## 2026-06-13 — CLI diff and clean artifact tables wrapped

`CliArguments.nl` now wraps unified-diff hunk range line inputs and hunk output columns behind named
normal structs. The exported `CliUnifiedDiffHunkRangesInto` ABI stays flattened for the CLI dogfood
adapter, while the range merge loop and hunk writer use wrapper-aware line/result tables.

The clean-artifact directory ordering pass now also groups kind/module/path inputs and
seen-path/length-bucket/temp scratch columns behind normal table wrappers, with the caller-owned
result index output still exposed through the existing flattened entry point.

## 2026-06-13 — CLI fix safety and grouping tables wrapped

`CliArguments.nl` now wraps the `nlc fix` safety-rank, edit-count, edit-flattening, file-rank,
rank-bucket, and applied-file grouping columns behind named normal structs. The apply/skip safety
filters still expose their flattened caller-owned array ABI, but the core loops now route ranks and
result indexes through wrapper-aware tables.

The edit-flattening pass and applied-file grouping pass likewise keep their public array signatures
while grouping action/edit results, bucket scratch columns, and grouped file outputs behind table
wrappers.

## 2026-06-13 — CLI argument symbol and build tables wrapped

`CliArguments.nl` now also wraps symbol-name filter batches and the build/export operand scratch
columns. Glob and substring symbol filters route their name inputs and result indexes through named
tables, and the build/export operand walkers now group kind ids plus the next/previous/next-option
linked-list columns behind `CliBuildArgumentKindTable` and `CliBuildArgumentLinkTable`.

`CliBuildFirstOperandIndexInto`, `CliBuildOptionSummaryInto`,
`CliExportCSharpFirstOperandIndexInto`, `CliBuildOperandSummaryInto`, `CliBuildOperandIndicesInto`,
and the shared remove-option helper all retain their flattened public signatures while the core
loops use wrapper-aware tables internally.

## 2026-06-13 — CLI argument option tables wrapped

`CliArguments.nl` has started its table-wrapper migration. Positional-argument filtering,
run/watch forwarded arguments, publish option summary parsing, test option summary parsing, lint
file-argument filtering, and tidy dependency/removal-line classification now route through named
normal structs for argv inputs, option-value sets, result indexes, project-option value indexes,
package/import-name batches, status-rank outputs, line batches, and keep-flag outputs.

The public CLI dogfood adapter entry points keep their flattened caller-owned array ABI, while the
first large CLI argv cluster now uses wrapper-aware core functions internally. Remaining
`CliArguments.nl` surfaces are still separate slices.

## 2026-06-13 — Small service tables wrapped

The remaining small compiler-service kernels now use named normal structs for their table-shaped
inputs, scratch storage, and outputs. This covers formatter safety diagnostics, code-intelligence
path matching, typo-suggestion dynamic-programming rows/results, AOT requirement grouping,
completion receiver batches, completion grouping buckets/results, and CLI tree dependency
deduplication ranks/buckets/index buffers.

The public dogfood adapter methods still expose the existing flattened arrays, while the internal
loops route through wrapper-aware cores and avoid anonymous table plumbing.

## 2026-06-13 — Lexer metadata and trivia tables wrapped

`LexerTokenKindScanner.nl` now also groups the full token metadata stream, indentation-brace
post-pass inputs/outputs, indentation stack, and comment-trivia output columns behind named normal
structs. `TokenizeMetadataInto`, `TokenizeMetadataWithIndentationInto`, and `CommentsInto` keep the
flattened dogfood adapter ABI; the indentation post-pass stays behind the composed tokenizer route,
and their internals now route through wrapper-aware core functions.

Together with the token-kind slice below, the lexer scanner no longer carries anonymous
parallel-array tables through its main token kind, token metadata, indentation, or comment loops.

## 2026-06-13 — Lexer token-kind tables wrapped

`LexerTokenKindScanner.nl` now groups token-kind buffers and parser-compaction result indexes behind
named normal structs for the plain token-kind scanner path. `TokenizeKinds`, `TokenizeKindsInto`,
`ParserTokenCompactionIndicesInto`, and `CopyKinds` keep their flattened public signatures, while
their internal loops operate on wrapper-aware token-kind and index tables.

This is the first lexer table-wrapper slice. The larger token metadata, indentation post-pass, and
comment-output tables are still separate lexer surfaces and remain to be wrapped in later slices.

## 2026-06-13 — CLI query parsing tables wrapped

`CliQueryParsing.nl` now groups CLI query position inputs, parsed line/column outputs, duplicate
batch-id rank columns, duplicate-count/result scratch arrays, packed batch-result words, and
integer parse result storage behind named normal structs. The parser helpers now forward those
wrappers through the fast positive-position path and the whitespace-tolerant integer segment path.

The exported CLI dogfood adapter functions remain flattened for `nlc query` and batch execution,
while the internal parsing/counting loops no longer pass anonymous result arrays and scratch buffers
through their bodies.

## 2026-06-13 — Doc query tables wrapped

`DocQuery.nl` now groups documentation-query type candidate columns behind a named normal struct for
scores, namespace lengths, full names, and active count. Its member-ordering counting sort also now
routes kind/name ranks, name/kind bucket counts and offsets, and temp/result index buffers through
wrapper-aware core functions.

The public code-intelligence dogfood adapter entry points remain flattened (`DocQueryBestTypeIndex`
and `DocQueryMemberOrderIndicesInto`), while the query-ranking and member-order internals no longer
carry anonymous parallel arrays through their loops.

## 2026-06-13 — CLI doc and linter import tables wrapped

`CliDocOrdering.nl` now groups doc-symbol ordering rank columns, name/kind bucket counts and
offsets, temp/result index buffers, slug input/output arrays, and symbol-kind filter inputs behind
named normal structs. `LinterImports.nl` now groups import namespace ranks, used namespace ranks,
used-flag/touched-rank scratch storage, and result indexes behind wrapper-aware core functions.

The exported dogfood adapter functions remain flattened, including the checksum helpers appended by
the parity corpus, while the internal CLI docs and linter loops no longer pass those table columns
anonymously through their bodies.

## 2026-06-13 — Ordering scratch tables wrapped

`FormatterImportOrdering.nl` and `TextEditOrdering.nl` now group their stable counting-sort scratch
columns behind named normal structs. Formatter import ordering wraps the System-prefix flags,
namespace ranks, bucket counts/offsets, and temp/result permutation indexes; text-edit ordering wraps
start/end position rank tables, bucket counts/offsets, and temp/result permutation indexes.

The exported dogfood entry points still expose the flattened caller-owned array ABI, while the core
ordering passes operate on wrapper-aware sort-key, rank, bucket, and index tables. This keeps the
formatter and edit-ordering kernels in the post-parser table-wrapper migration without relying on the
experimental `soa record` surface.

## 2026-06-13 — Compiler-service utility tables wrapped

`StructCopyAnalysis.nl`, `AnonymousUnionShims.nl`, and `ProjectSourceFilter.nl` now route their core
loops through named normal structs for struct-copy field flags, anonymous-union parameter flags,
project source paths, exclude patterns, and kept-index output. The exported dogfood entry points keep
their flattened caller-owned array ABI, while the internal loops no longer pass those utility table
columns anonymously.

This closes another set of small compiler-service kernels in the post-parser table-wrapper pass
without widening the experimental `soa record` surface.

## 2026-06-13 — Source text line tables wrapped

`SourceTextLines.nl` now groups logical line start/length ranges, line-start-only indexes, and dense
offset-to-line maps behind named normal structs. The exported dogfood parity functions still expose
the flattened arrays used by the adapter and tests, while range building, line-start building,
offset-to-line lookup, column lookup, line/column-to-offset lookup, and dense offset-map construction
route through wrapper-aware cores.

This finishes the shared source-text line utility table migration used by compiler-service and
code-intelligence slices.

## 2026-06-13 — Analyzer coverage and signature tables wrapped

`AnalyzerExhaustiveness.nl` now groups member coverage flags, union coverage/partial flags,
missing-case result columns, and packed overload-signature rank rows behind named normal structs. The
public analyzer dogfood adapter functions still accept the existing flattened arrays, while the
missing-member, union-missing-case, and overload-signature distinctness cores operate on explicit
coverage/result/signature table wrappers.

This moves another semantic analyzer kernel out of anonymous parallel-array plumbing while preserving
the shipped delegate ABI and parity corpus surfaces.

## 2026-06-13 — Code-intelligence line query tables wrapped

`IdentifierSpans.nl` now groups code-intelligence line ranges, position queries, line-only queries,
span outputs, declaration-name match inputs, identifier-name column outputs, member receiver caches,
and variable-name caches behind named normal structs. The existing dogfood adapter delegates still
consume the flattened `*FromLinesInto` and cache entry points, while the identifier span, editor span,
declaration match, source context/line, completion prefix, doc comment, member receiver, and variable
name cores operate on explicit table wrappers.

This extends the post-parser table-wrapper pass into the editor/code-intelligence text kernels used by
`nlc query` and the production dogfood adapter without changing the host ABI.

## 2026-06-13 — Production overload candidate tables wrapped

`OverloadCandidates.nl` now groups compact overload score columns, candidate parameter-type ranges,
argument type buffers, batch call slices, and selection results behind named normal structs. The
public IL-compiler dogfood adapter ABI remains the same flattened arrays, while the single-call,
table-backed, and batch selector cores operate on explicit overload-candidate table wrappers.

This routes the production overload-candidate kernel through the same wrapper pattern that the
earlier experimental SoA fixture proved, without enabling the experimental `soa record` surface in
the dogfood project.

## 2026-06-13 — Binding lookup tables wrapped

`BindingLookup.nl` now groups declaration, binding, query, candidate-column, nearest-declaration,
result, slot, and scratch columns behind named normal structs. The production code-intelligence
adapter still calls the same flattened entry points, while the strict lookup, candidate-column, hash
slot, nearest-index build, nearest-query, and helper loops route through wrapper-aware cores.

This extends the post-parser semantic table pass beyond scopes, declared types, and diagnostics into
the binding lookup cache path used by `nlc query` and code-intelligence operations.

## 2026-06-13 — Diagnostic clustering tables wrapped

`DiagnosticClusters.nl` now groups its severity, trait, cluster-id, command-location, grouping-key,
root/count, member-output, and scratch columns behind named normal structs. The public dogfood adapter
entry points still expose the same flattened arrays, while the classification, grouping, member
ordering, root comparison, and sorting cores operate on typed table wrappers.

This completes the diagnostic table pair called out after semantic scopes and declared type lookup:
deduplication and clustering now both preserve the flattened ABI at the host boundary while removing
anonymous parallel-array plumbing from their internal loops.

## 2026-06-13 — Diagnostic deduplication tables wrapped

`DiagnosticDeduplication.nl` now groups diagnostic key columns, reference key columns, and shared
slot/result scratch arrays behind named normal structs. The compact and stable deduplication entry
points still expose the flattened dogfood adapter ABI, while the hash-table probe loops and sort
helpers route through wrapper-aware cores.

This continues the post-parser symbol/type/diagnostic table pass after semantic scopes and declared
type lookup. The remaining work in this group is diagnostic clustering and any other compiler-service
kernels that still move anonymous parallel arrays through their internal loops.

## 2026-06-13 — Declared type lookup tables wrapped

`TypeLookup.nl` now groups declared-type lookup columns behind named normal structs for suffix rank
lookup, imported-name candidate selection, exact-name fallback, and type-creation ordering scratch.
The production dogfood adapter and parity corpus still call the same flattened functions, while the
core loops now operate on explicit type-table wrappers.

This is the first type-table slice in the post-parser table pass, following the semantic scope
symbol tables. Remaining work in this group is the diagnostic clustering/deduplication tables and
other symbol/type kernels that still carry anonymous parallel arrays.

## 2026-06-13 — Semantic scope symbol tables wrapped

`SemanticScopes.nl` now groups the semantic-scope columns behind named normal structs for source
positions, parent/symbol ranges, sorted lookup indexes, symbol names, depth output, and name-set
scratch storage. The C# dogfood adapter still calls the same flattened array entry points, while the
visible-symbol, lookup, depth, and sorted-index kernels route through wrapper-aware cores.

This starts the post-parser table pass called out in the SoA migration plan. Remaining work in this
group is the other symbol/type/diagnostic kernels that still pass raw parallel column groups directly
through their bodies.

## 2026-06-13 — Declaration parser tables wrapped

`ParserDeclarations.nl` now groups its declaration output columns behind named normal structs at the
flattened entry boundary: imports, top-level names/modifiers, interface bases/methods, enum members,
struct/class/record members, constructor chain arguments, and union cases/fields. The public delegate
signatures consumed by the dogfood adapter are unchanged, while the parser body no longer writes those
parallel declaration columns through anonymous raw arrays.

This completes the parser table-wrapper pass after the type-reference and expression/statement node
tables. Remaining table work moves out of parser kernels and into symbol/type/diagnostic tables.

## 2026-06-13 — Expression and statement parser nodes wrapped

`ParserExpressions.nl` now owns a normal `ParserExpressionNodeTable` wrapper for the shared
expression/statement node table, and `ParserStatements.nl` threads that same wrapper through its
mutually-recursive statement helpers. The public `ParseExpressionNodesInto` and `ParseStatementNodesInto`
entry points still expose the flattened column ABI, and type-reference subtrees still bridge through
the existing flattened type-reference entry.

This keeps the host and multi-file dogfood adapter contracts stable while removing another large run
of raw parallel-array parameters from the recursive parser core. The remaining parser table work is
the declaration-specific tables.

## 2026-06-13 — Type-reference parser nodes wrapped behind flattened ABI

The parser node-table migration has started with the type-reference kernel. `ParserTypeReferences.nl`
now has a normal `ParserNodeTable` struct that groups the node kind/value/child/span columns for the
recursive core, while `ParseTypeReferenceNodesInto` and the cross-file `ParseUnionTypeReferenceNode`
entry still accept the existing flattened array ABI.

This is intentionally not the experimental `soa record` surface yet. It proves the production
columnar backend can thread a by-ref table wrapper with array fields through recursive parser code
without changing host interop, and leaves the expression/statement/declaration node tables as the
next migration targets.

## 2026-06-13 — Parser state moved out of magic integer slots

The parser dogfood kernels now thread a named `ParserState` struct by reference instead of a six-slot
`int[]`. `Pos`, `NodeCursor`, `ChildCursor`, `ArgStackTop`, `SplitGreaterDepth`, and
`OwedGreaterByteEnd` are explicit fields shared across the type-reference, expression, statement, and
function-signature kernels, while the external flattened table ABI remains unchanged.

This also forced the next by-ref correctness case: a function receiving `st: &ParserState` must be able
to forward `ref st` into another `&ParserState` helper. The analyzer now unwraps by-ref arguments when
checking `&T` parameters and overload scores, and the columnar by-ref proof covers the forwarding shape
with IL-shape checks.

---

## 2026-06-13 — Columnar by-ref state parameters proven

The columnar parser and emitter now cover the by-ref shape needed before replacing magic parser
state arrays with a named state struct. Call arguments can carry `ref`/`out` as a stable expression
node wrapper, top-level columnar function parameters can resolve `&T` for supported value types, and
sibling calls emit addressable local/parameter/field-chain arguments only when the callee parameter is
actually by-ref.

The proof fixture mutates a `ParserState` value through `advance(st: &ParserState)` and calls it with
`advance(ref st, ...)` from a normal `run` function. IL-shape coverage pins the important lowering:
the callee parameter is a CLR by-ref parameter, field reads/writes go through `ldfld`/`stfld`, and the
callee does not take the address of the by-ref parameter slot (`ldarga`). This removes the by-ref
lowering blocker for the later `st: int[]` to `ParserState` migration; it does not yet change the real
parser kernels.

---

## 2026-06-13 — SoA cold table migration fixture: overload candidates

The first real compiler-table shape has been moved through the experimental SoA wrapper surface
without routing production code. The overload-candidate compact table now has a parity fixture that
wraps the existing primitive columns as `OverloadCandidateTable`, ranks candidates through
`table[i].column` row projections, and compares against the current parallel-column tie-break rules.

IL-shape coverage pins the migrated loop: no `newobj`, `newarr`, `box`, delegate construction,
`call`, or `callvirt`, with candidate facts loaded through direct column-field loads and array
element loads. This proves the cold-table migration pattern while the default dogfood project remains
SoA-free until the columnar backend owns declarations or the hot-function flattened ABI lands.

---

## 2026-06-13 — SoA row escape diagnostics: assignment paths closed

Row-view escape analysis now covers direct assignment and object-initializer values in addition to
local declarations, returns, and call arguments. That closes the remaining obvious heap-storage
paths for the experimental wrapper slice: `holder.Value = nodes[i]` and `new Holder { Value:
nodes[i] }` now report the SoA-specific diagnostic instead of relying on incidental type mismatch
or later emission failure.

---

## 2026-06-13 — SoA IL-shape evidence: row projection stays columnar

The SoA wrapper proof now has IL-shape evidence for the core non-negotiables. Row projection methods
that receive an existing table are asserted to emit direct column-field loads plus array element
loads/stores, with no `newobj`, `newarr`, `box`, delegate construction, or virtual dispatch. The
zero-copy `wrap` method is asserted to store the incoming array references and metadata fields without
`newarr`, `ldelem*`, or `stelem*` traffic.

This keeps the experimental wrapper slice honest while the production columnar backend still falls
back for SoA declarations. The next real migration step remains one cold compiler table under the
experimental flag, with IL-shape and benchmark evidence before parser node tables move.

---

## 2026-06-13 — SoA wrapper ABI proof: direct IL lowering behind a migration flag

The first SoA lowering slice is implemented behind `NSHARP_EXPERIMENTAL_SOA=1`. Top-level
non-generic `soa record` declarations now emit a sealed value-type wrapper with one CLR array field
per column plus `length` and `capacity`. The direct IL backend supports `new Table(capacity)`,
zero-copy `Table.wrap(columns..., length)`, column access, row projection (`table[i].column`),
`add`, `clear`, `ensureCapacity`, and `copyRow`. Row projections lower directly to column array
loads/stores, and analyzer row-view escape checks reject storing row views as values.

Production builds stay gated: without the flag, SoA still reports `NL323 FeatureNotImplemented`.
When the flag is enabled, `MultiFileCompiler` skips the default columnar route for programs that
contain SoA declarations and falls back to the direct IL backend, because the standalone columnar
emitter does not own this table surface yet.

Coverage: focused SoA tests pin analyzer gating, flagged table/member typing, row escape diagnostics,
direct IL execution for allocation/growth/row projection, zero-copy wrap, copy/clear operations, and
production multi-file fallback with columnar routing enabled.

NEXT: port one cold compiler table to this wrapper surface, verify emitted row-projection IL shape,
then decide whether the next slice is flattened hot-function ABI lowering or direct columnar emitter
ownership for SoA declarations.

---

## 2026-06-13 — SoA syntax slice: non-generic declarations parse, query, and gate

The first implementation slice for the emitter-port table model is in place without enabling production
lowering. `soa record Name { column: Type }` is a contextual top-level or nested declaration form, so `soa`
remains a normal identifier everywhere except immediately before `record`. The AST now carries
`SoaRecordDeclaration` plus typed `SoaColumnDeclaration` entries, formatter output round-trips columns, namespace
qualification preserves column type references, and code-intelligence symbol/outline output exposes columns as
field-like children under the existing record-shaped schema.

The analyzer deliberately reports build-blocking `NL323 FeatureNotImplemented` for every SoA declaration after
resolving its column types and registering its type name. That means duplicate-name checks, binding maps, file
imports, and query calls see a real declaration, but no backend can silently lower it. The IL backend also has a
recursive defense-in-depth guard that throws a compiler-bug exception if a SoA declaration reaches emission.

Coverage: parser tests pin column parsing and the contextual `soa` identifier behavior; analyzer tests pin the
NL323 gate without spurious type-not-found diagnostics; formatter tests pin stable round-tripping. Auxiliary
linter, systems/AOT, source-generator, binding-map, nullability, and dogfood-adapter walkers understand the new
declaration enough to avoid secondary failures while lowering remains blocked.

NEXT: migrate the first cold compiler table use to the non-generic SoA surface behind the NL323 gate/feature flag,
then prove the wrapper ABI before touching parser node tables or Stage-6 C# surface deletion.

---

## 2026-06-13 — SoA table-type design gate: row syntax without row objects

The emitter-port design gate is written in `docs/design/soa-table-types.md`. The contract is a small
`soa record` surface for the compiler's existing struct-of-arrays tables: column fields lower to the
same CLR arrays used today, row syntax such as `nodes[i].kind` is only a compile-time projection to
`nodes.kind[i]`, and caller-owned buffers remain first-class through a zero-copy `wrap` form. The doc
explicitly rejects row-object allocation, array-of-structs lowering, AST materialization, hidden copies,
and deleting C# fallback merely because the syntax exists.

The design also pins the implementation and verification gates: flattened hot-function ABI, no `newobj`/
`box`/delegate traffic from row projections, no copies on `wrap`, parser/diagnostic parity on the dogfood
corpus, zero-new-declines over product+parity corpus, no slower parser/compiler-service benchmarks, and the
usual isolated non-IDE product gate before each commit.

Roadmap and memory index links now point to the SoA design as the entry point for emitter-port planning.

NEXT: implement the first non-generic `soa record` slice without production use, then migrate cold table
uses before parser node tables and Stage-6 C# surface shrink. Completed by the syntax slice above.

---

## 2026-06-13 — M8: columnar type inference resolves overload returns by signature

The Stage-3 columnar type inferer no longer keys sibling function return types by simple name alone. The adapter
now records every top-level function's canonical parameter-type vector with its return canonical, and
`ColumnarTypeInferer` resolves bare sibling calls against that overload list. Single-overload names keep the
existing behavior; overloaded names require one exact arity/type match, otherwise the call remains `External`
instead of silently taking the last declaration's return type.

Coverage: `ColumnarTypes_Inference_MatchesAstWalk` now includes `pick(int): int` plus `pick(string): string`
and asserts `pick(1)` infers `int` even though the string overload appears later. The C# AST oracle uses the
same canonical-signature selection so future inference drift is still caught by parity.

NEXT: keep richer overload conversion/scoring out of this route until the columnar analyzer owns the same
semantic candidate ranking as the production analyzer; exact signature matching closes the last-wins hazard.

---

## 2026-06-13 — Route safety: contextual test declarations decline columnar

The Stage-5 route-all path now has an adapter-level guard for top-level contextual test declarations before it
trusts the N# `TopLevelDeclarationKindsInto` kernel. The parser kernel recognizes real declaration keyword
ordinals and intentionally omits contextual `setup`/`teardown`; current lexer output also leaves `test` as an
identifier. A mixed source with `func helper` plus `test "..."`, `setup { ... }`, or `teardown { ... }` could
therefore look like a function-only program to the columnar route and silently emit a partial assembly.

`TryGetColumnarFunctionInputs` and the shared top-level-function discovery helper now scan the raw token metadata
for declaration-shaped top-level `test`/`setup`/`teardown` before the declaration-kind kernel runs. Detection is
shape-aware so package/import segments or a normal function named `test` still route, while test-lifecycle
declarations decline to the authoritative C# test emitter.

Coverage: `Stage5_ColumnarBackend_DeclinesContextualTestDeclarations` pins mixed `func` + contextual
`test`/`setup`/`teardown` decline and the non-regression cases for `package test` plus `func test`.

NEXT: keep test parsing/emission as a real columnar coverage expansion item; route safety is closed.

---

## 2026-06-13 — Route-all: columnar backend is default-on with C# opt-out

The Stage-5 route-all switch is flipped. `MultiFileCompiler.CompileToIlAssembly` now tries the
standalone columnar backend by default, using the already-routed single-file path or the 32/32
dogfood-corpus multi-file merge, then falls back to the C# `ILCompiler` if the columnar backend
declines an unsupported program. `NSHARP_COLUMNAR_BACKEND=0` (or `false`) is the explicit opt-out
for A/B benchmarking, ILCompiler-forcing tests, and emergency rollback; `NSHARP_COLUMNAR_BACKEND=1`
continues to force the same enabled behavior.

The flip is gated by the prior route-all evidence now satisfied together: the full compiler-service
corpus routes through the multi-file columnar merge, the Phase P vectorized loop families have columnar
parity/IL-shape coverage, and the Stage-5 production-routing tests compare the enabled route against a
forced-C# baseline. The benchmark harness now forces the C# baseline with `0` so the never-slower A/B
measurement remains meaningful after the default changes.

Coverage: `Stage5_ColumnarBackend_RoutesEligibleProgramByDefault` proves an unset environment routes an
eligible program through columnar and still value-matches the forced-C# assembly. Existing Stage-5 tests
continue to prove explicit enabled single-file and multi-file routing plus C# fallback for unsupported
programs.

NEXT: write the SoA table-type design doc that gates the emitter-port phase, then start shrinking the
C# surface where columnar ownership is complete.

---

## 2026-06-13 — IF-2d default interface methods: concrete slots and body emission

The last planned IF-2 structural residual routes C#-8-style default interface methods through the
columnar dogfood path. The interface declaration kernel now accepts balanced block bodies after
interface `func` signatures, the adapter carries those bodies alongside method signatures, and the
emitter declares defaulted interface slots as concrete virtual methods instead of abstract slots.

Default interface bodies emit before interface finalization with the interface itself as the
implicit receiver context, so a DIM can call another interface member through the same bare
`this` dispatch path used by class and struct instance methods. Implementer completeness skips
defaulted slots, while explicit class or struct overrides still bind to the matching interface
method when present.

Coverage: `ColumnarCodegen_Parity_Interfaces` now value-compares a class that relies entirely on
defaults, a class that overrides one default while inheriting another, and a struct implementer that
uses the defaults. The same coverage pins a default method calling another default/interface member
through implicit `this`. Expression-bodied DIMs, generic interface members, where-clauses, and local
functions inside DIM bodies still decline to the oracle path.

NEXT: run route-all and close any residual declines it exposes. Then the emitter port remains gated
by the SoA design doc.

---

## 2026-06-13 — IF-2c multi-interface lists: direct slots plus one class base

The third IF-2 residual slice routes colon-lists on classes, structs, and records through the
columnar dogfood path. The struct declaration kernel now emits every colon-list name as spans
instead of a single `BaseName`, the adapter materializes `BaseNames`, and the emitter resolves the
list semantically: every interface becomes a direct implemented interface, inherited interfaces are
deduped into metadata, and at most one class can become a class parent for a class. Structs,
records, duplicate direct interfaces, unknown names, multiple class bases, and record base shapes
decline instead of changing type identity or producing unloadable IL.

Implementing methods now bind to every matching interface slot, not just the first direct interface.
Required-member completeness walks all direct and inherited interfaces with deduplication, and
interface upcasts scan the direct-interface set, so the same class or struct can flow as any of its
implemented interface views.

Coverage: `ColumnarCodegen_Parity_Interfaces` now value-compares multi-interface class and struct
implementers, direct argument coercions to two interfaces, and `class Derived: Base, IShape, IWeight`
with both inherited class method dispatch and interface dispatch. It also pins duplicate direct
interfaces, multiple class bases, and missing members from any direct interface as declines.

NEXT: finish default interface methods. Then route-all, then the emitter port gated by the SoA
design doc.

---

## 2026-06-13 — IF-2b interface inheritance: base metadata and inherited slots

The second IF-2 residual slice routes base-interface hierarchies through the columnar
dogfood path. The parser kernel now records base-interface names on interface declarations, the
adapter carries those spans into `ColumnarInterfaceInput`, and the emitter defines all interface
builders before resolving base lists so declaration order no longer matters for interface-to-interface
references. Derived interfaces add their base interfaces to metadata, cycles and duplicate bases
decline, and interface `CreateType` runs base-before-derived.

Implementers now add both the directly named interface and inherited interfaces to their type
metadata. Override binding, required-member completeness, method lookup, and interface upcasts all
walk inherited interface slots, so `class C: ITagged` and `struct S: ITagged` satisfy and dispatch
`IArea` members when `ITagged: IArea`.

Coverage: `ColumnarCodegen_Parity_Interfaces` now value-compares inherited-interface dispatch
through base-interface values, derived-interface dispatch, class and struct implementers, and
explicit base-interface views. It also pins cycle and missing-inherited-member declines. The test
intentionally avoids direct inherited-interface overload matching in the oracle path; that analyzer
gap rejects `f(new TaggedSquare())` for `f(IArea)` even though the local `IArea` view routes.

NEXT: finish multi-interface implementation lists and default interface methods. Then route-all,
then the emitter port gated by the SoA design doc.

---

## 2026-06-13 — IF-2a interface residuals: upcast flow gaps and List<IShape>

The first IF-2 residual slice closes the review-found interface value-flow gaps without widening the
interface declaration model yet. The existing `TryEmitInterfaceUpcast` coercion now participates in
implicit-`this` instance calls, external user instance calls, closed generic receiver method calls,
generic/reference/value object initializers, and the shared `EmitArg` helper used by BCL collection
methods. Value-type implementers still box at the boundary; reference implementers pass as object
refs.

Coverage: `ColumnarCodegen_Parity_Interfaces` now value-compares interface upcasts through
instance-method arguments, bare `this` calls inside a class, reference object initializers, value
struct object initializers, and `List<IShape>` add/index/foreach flows with mixed class and struct
implementers. The old IF-1 dispatch/return/local/field/constructor coverage remains in the same
parity test.

NEXT: finish the structural IF-2 residuals: interface inheritance, multi-interface implementation
lists, and default interface methods. Then route-all, then the emitter port gated by the SoA design
doc.

---

## 2026-06-13 — Phase P-5 columnar port: uint arrays unlock SumUInt32

The deferred `uint[]` Phase P gap is closed. Columnar array support now admits `uint` as the
unsigned i4 element lane: `new uint[](n)`, indexed reads (`ldelem.u4`), writes (`stelem.i4`),
foreach array lowering, `Array.Fill<T>`, and the general `T[]` type gate all route through the
same array machinery as the existing integer element families. This makes the already-shipped
runtime `SumUInt32(uint[], int, int)` helper reachable from the columnar counted-reduction matcher.

Coverage: `ColumnarCodegen_Parity_ArrayAlloc` now value-compares `new uint[]` plus write/read
round-trips over high-bit values, `ColumnarCodegen_Parity_ForeachLoop` value-compares `uint[]`
foreach accumulation, and `ColumnarCodegen_Parity_VectorizedIntegerReductions` value-compares
while/for `uint[]` reductions while asserting the emitted IL contains no scalar `ldelem.u4` loop
and does contain the helper call. With this, Phase P's current helper families are ported in the
columnar route.

NEXT: continue IF-2 residuals as route-all demands, then route-all, then the emitter port gated by
the SoA design doc.

---

## 2026-06-13 — Phase P-4 columnar port: count-transitions emits shifted-compare helper

The fourth Phase P rung ports the adjacent-transition count kernel into columnar. The route now
recognizes the canonical body `current := a[i]; if current != previous { count++ }; previous = current`
inside `for` and `while` unit-stride loops over `int[]`, then emits
`CountTransitionsInt32(array, index, bound, previous)`. The helper returns `(countDelta, last)`, so
columnar adds `countDelta` into the live counter, restores `previous` to the scalar loop's terminal
carried value, and preserves the scalar terminal index with `index = max(index, bound)`.

False-positive guards: exact temp/if/carry body order, no `else`, a single unit counter increment,
int counter/index/previous locals or parameters, int[] source, side-effect-free int bound, and five
distinct names for counter/array/index/previous/current. Bounds that read `count`, `previous`, or
`current` decline so mutable-bound loops stay scalar. The temp-shadow guard applies here too because
the vectorized path replaces the temp declaration.

Coverage: `ColumnarCodegen_Parity_VectorizedCountTransitions` value-compares for/while forms,
terminal `previous` restoration, terminal index behavior on empty/negative ranges, mutable-bound
scalar fallback, and `long[]` fallback. IL-shape assertions prove matched `int[]` loops emit one
helper call and keep only seed loads, while mutable-bound and `long[]` cases retain scalar element
loads. A temp-shadow decline pin covers the columnar-only guard.

NEXT: handle `uint[]` only after columnar array support admits `uint`; otherwise Phase P's current
helper families are ported. Continue IF-2 residuals as route-all demands, then route-all, then the
emitter port gated by the SoA design doc.

---

## 2026-06-13 — Phase P-3 columnar port: min/max reductions emit SIMD helpers

The third Phase P rung ports the min/max reduction family into columnar. The route now recognizes
canonical `if subject < min { min = subject }` and `if subject > max { max = subject }` loops over
`int[]`, with temp or inlined subjects, `for` or `while` unit-stride loops, min-only/max-only bodies,
reversed comparison operand order (`min > a[i]`, `max < a[i]`), and the canonical one-min plus
one-max body. A single min or max emits `MinInt32` / `MaxInt32`; exactly one min plus one max emits
the fused `MinMaxInt32` helper so the scan reads each element once. Terminal index semantics remain
the scalar `index = max(index, bound)` value.

The false-positive boundary is the same as the ILCompiler shape, plus the columnar temp-shadow guard:
`int[]` array, int index, int accumulators, side-effect-free int bound, strict `<`/`>` comparisons,
no `else`, a single assignment body, distinct accumulator/array/index/temp names, distinct
accumulators, and no bound reads of loop-written names. Non-`int[]` arrays stay scalar.

Coverage: `ColumnarCodegen_Parity_VectorizedMinMaxReductions` value-compares fused min+max,
min-only, temp/inlined subjects, reversed comparisons, while/for forms, empty/negative terminal
index behavior, and `long[]` fallback. IL-shape assertions prove matched shapes emit exactly one
helper call and keep only the seed `ldelem.i4` loads, while the `long[]` fallback still has scalar
`ldelem.i8`. A temp-shadow decline pin covers the columnar-only guard.

NEXT: finish Phase P count-transitions, then `uint[]` once columnar array support admits it, then
IF-2 residuals as route-all demands, then route-all, then the emitter port gated by the SoA design
doc.

---

## 2026-06-13 — Phase P-2 columnar port: range-predicate counts emit CountInRangeInt32

The second Phase P rung ports the ILCompiler's masked-SIMD count-ascii shape into columnar. The
columnar route now recognizes both supported predicate subject forms inside counted loops:
`value := a[i]; if value >= lo && value <= hi { count++ }` and the inlined
`if a[i] >= lo && a[i] <= hi { count++ }`, for both `for` and `while` unit-stride loops. The
lowering emits `count += SimdReductions.CountInRangeInt32(array, index, bound, lo, hi)` and preserves
the scalar terminal index with `index = max(index, bound)`.

False-positive guards mirror the C# shape and add one columnar-specific rule: a temp-subject
declaration must not shadow any visible binding, because the vectorized path replaces the loop body
instead of emitting that `:=` declaration. The shape is restricted to pure int bounds and int
lo/hi operands, an `int[]` source, int counter/index locals or parameters, no `else`, a single
counter increment body, and distinct counter/array/index/temp names. Non-`int[]` arrays remain scalar.

Coverage: `ColumnarCodegen_Parity_VectorizedRangePredicateCounts` value-compares temp/inlined
forms, `for`/`while`, inclusive boundaries, `lo > hi`, empty/negative ranges, terminal index
visibility, and `long[]` fallback. IL-shape assertions prove matched `int[]` functions contain no
scalar `ldelem.i4`, while `long[]` still emits `ldelem.i8`. A temp-shadow route-decline pin covers
the columnar-only guard.

NEXT: finish remaining Phase P ports (min/max including fused min+max, count-transitions, and
`uint[]` once columnar array support admits it), then IF-2 residuals as route-all demands, then
route-all, then the emitter port gated by the SoA design doc.

---

## 2026-06-13 — Phase P-1 columnar port: canonical integer reductions emit SIMD helpers

Phase P has started in the columnar route. The first rung ports the ILCompiler's counted integer
sum reduction lowering without materializing the C# AST: columnar now recognizes canonical
`while i < bound { acc = acc + a[i]; i = i + 1 }` and `for i := start; i < bound; i++ { acc += a[i] }`
node-table shapes after the `for` initializer has run, then emits the same helper-call form:
`acc += SimdReductions.Sum...(array, index, bound); index = max(index, bound)`. The matcher is
strict by construction: local/parameter accumulator, array, and int index must be three distinct
names; the bound must be a side-effect-free int identifier, int literal, or array `.Length`; captured
or lifted locals decline; non-integer arrays decline to the scalar loop.

Coverage pins both lenses: `ColumnarCodegen_Parity_VectorizedIntegerReductions` value-compares
while/for forms, `+=`, array `.Length` bounds, empty/negative ranges, post-loop index visibility,
`int[]`, `long[]`, and `ulong[]`; then inspects emitted IL to prove the integer paths call the SIMD
helpers and no longer contain scalar `ldelem.i4` / `ldelem.i8` loops. `double[]` is pinned as scalar
fallback because floating-point addition is not associative. `uint[]` stays deferred with an explicit
reason: the runtime helper exists, but the columnar array element whitelist does not yet support
`uint`, so widening the vector helper before array parity would be fake progress.

NEXT: finish the remaining Phase P ports (range-predicate count, min/max including fused min+max,
count-transitions, and `uint[]` once columnar array support admits it), then IF-2 residuals as
route-all demands, then route-all, then the emitter port gated by the SoA design doc.

---

## 2026-06-12 — INTERFACES slice IF-1: the FIFTH user-defined type family

Recon first (3 agents): all probed shapes oracle-PASS (direct/dispatched calls, struct-implementer
boxing, heterogeneous dispatch, returns/fields, inheritance, DIMs); the columnar route started
from ZERO (decl-kind 10 outside the adapter gate). Oracle facts that shaped the slice: members are
METHOD signatures + C#-8 default methods ONLY (`DeclareInterfaceMembers` silently DROPS bare
members — defect #27); implementation binding is NAME+SIGNATURE matching → `DefineMethodOverride`
(implementing methods FORCED `Public|Virtual|Final|NewSlot`); the class colon-list's first name
lands in the parser's BASE slot even for interfaces (reclassified downstream); struct implementers
BOX at interface boundaries; **a class MISSING an interface member compiles with ZERO diagnostics
and the assembly throws TypeLoadException at LOAD (defect #26)**.

**The slice:** kernel `ParseInterfaceDeclarationInto` (interface name + method-signature member
delimitation — default bodies/bare members/properties/generics/base lists all `-1`); adapter
decl-gate +10, `TopLevelInterfaceIndices`, `TryGetColumnarInterfaceInputs` (signatures via the
shared `ParseFunctionSignature` kernel); emitter PASS-0i defines `Public|Interface|Abstract` types
with abstract members **registered in the STRUCT registry (`IsInterface=true`)** so
interface-typed locals/params/returns/fields resolve and `iface.Method(args)` dispatches
(ldloc+callvirt) through the EXISTING machinery — object-init declines via the null DefaultCtor
and PASS 0d/0e skip interfaces for free. PASS-0a' reclassifies the colon name when it resolves to
an interface (`ImplementedInterface` + `AddInterfaceImplementation` — classes, structs, AND
records implement). PASS-0b matches implementers by name+signature (`Virtual|Final|NewSlot` +
`DefineMethodOverride`) and enforces **COMPLETENESS — a missing member declines** (never emit the
pipeline's unloadable assembly). `TryEmitInterfaceUpcast` (the `EmitValueCoercion` interface-arm
mirror: value implementers BOX, references pass) wired at returns / typed-locals / reassignments /
sibling args / member writes / positional-ctor args. Interfaces `CreateType` before implementers.

**2-lens adversarial review (~50 probes + ilverify): zero columnar wrong-IL.** Dispatch/aliasing
identity, struct-box snapshot semantics at every wired upcast site, direct calls on
now-Virtual|Final implementer methods (`call` on virtual-FINAL is verifiable — ECMA III.3.19,
ilverify-confirmed), matching edges, value-flow reassignments, and null-field NRE parity all
REFUTED. Found+fixed in-slice: **cross-registry NAME collisions routed** (interface-vs-enum emitted
a loadable assembly with two same-named types where the pipeline rejects NL306 — a PRE-EXISTING
hole across enum/struct/union pairs, widened by each type family; the registries now enforce
uniqueness across kinds). Found+pinned: **ORACLE DEFECT #28** (the #26 ordering variant) — an
implementer declared BEFORE its interface makes the PIPELINE emit an UNLOADABLE assembly (its
interface wiring is declaration-order-sensitive); columnar's PASS-0i is order-insensitive and
emits CORRECT ilverify-clean IL — pinned ROUTE-ONLY at the working value (never degrade correct
columnar to mirror a pipeline bug). STALE DECLINE flipped to parity: `is`/`as` on interfaces
already route through the kind-46/47 isinst lowerings — both polarities now parity-pinned.
Recorded (pre-existing, NOT IF-1): lowercase non-implementing class methods emit Public columnar
vs Assembly oracle (metadata-surface divergence value-parity hides — bundle note). INFO coverage
targets for IF-2: the interface upcast at instance-method args + object-init member inits (clean
declines today).

Parity: `ColumnarCodegen_Parity_Interfaces` — 9 value functions (direct call, interface-typed
`let` local, param dispatch, STRUCT implementer boxed through a param, two implementers through
one param 906, interface return, interface-typed FIELD through a ctor, `is`/`as` both polarities)
+ the #28 route-only pin + decline pins (missing-member #26, bare-member #27, cross-registry
NL306, DIMs, interface inheritance, multi-interface lists). One old pin flipped (the "interface
unsupported" gate pin). 319/319 dogfood; 4167/4167 full suite. NEXT: IF-2 residuals (List<IShape>,
inheritance, multi-interface, DIMs, the upcast coverage targets) as route-all demands — then
route-all (gate: Phase P port) → emitter port (gate: SoA design doc).

---

## 2026-06-12 — ASYNC rung A: the SYNC-LOWERING MIRROR — async funcs + await emit columnar

The arc's main rung, riding the recon's headline (neither pipeline emits a state machine — the
oracle's async is synchronous by design). FOUR pieces, each mirroring the oracle exactly:

**Kernel (kind 53):** `await <operand>` parses as a prefix unary (token 69, the `must`-arm
template — the operand recurses at the unary level so `await await x` chains); both kind ledgers
updated (54 next free). The ASYNC modifier needs NO kernel change: the decl scanner already maps
token 68 → Modifiers.Async (1<<11); the ADAPTER now reads `TopLevelDeclarationModifiers` and
threads per-function `IsAsync` (the i-th kind-7 decl = the i-th `TopLevelFuncIndices` entry),
replacing rung 0's blanket decline.

**Signatures:** the declared return resolves to the INNER type; the METHOD's CLR return wraps —
`ValueTask`/`ValueTask<T>` default, `Task`/`Task<T>` for `main` (case-insensitive, the oracle's
entry-point rule), explicit `Task`/`ValueTask`(/`<T>`) annotations keep their declared family
(`TryComputeAsyncReturnShape`, the WrapAsyncReturnType mirror). **The sibling table registers the
WRAPPED type** — the slice's one real bug, found by probe: registering the inner type made every
await of a sibling decline (the call site thought `fetch()` returned `int`). Generic async
declines.

**Bodies:** the whole async body runs inside the FAULT GUARD (the oracle's
Begin/EndAsyncFaultGuard) — one protected region per body reusing the E2 machinery: returns WRAP
(`new ValueTask<T>(v)` / `Task.FromResult<T>` / `default(ValueTask)` / `Task.CompletedTask`) then
store+leave to the shared tail; a unit body falling off the end wraps the completed task;
`catch (Exception)` converts to a FAULTED task (`Task.FromException(<T>)` + the ValueTask
Task-wrapping ctor) — probe-pinned faulted-task parity (invoking a throwing async returns
normally; the task carries the InvalidOperationException). Value async bodies must still
always-return; unit-task asyncs are exempt (the analyzer's rule). Nested try/lock decline via the
one-region rule (pinned — flips with nested-region support).

**Await (`TryEmitBlockingAwait`):** the EmitAwaiterGetResult mirror — exactly the four BCL task
shapes; ValueTask(/T) spills and converts via `AsTask()`; Task(/T) goes callvirt `GetAwaiter()`
then the STRUCT awaiter spills for `call GetResult()`. Await is legal in NON-async functions too
(probe-pinned: no diagnostic exists; identical lowering), and await-as-STATEMENT pops non-void
results like a bare call. The parity HARNESS gained task-unwrapping (`ResolveTaskLikeResult` in
both invoke paths — two correct emissions would otherwise compare distinct Task instances).

**2-lens adversarial review (~50 probes): one ORACLE defect found+fixed, two columnar over-accepts
found+fixed, everything else refuted.** (1) ORACLE: non-async LAMBDAS and LOCAL FUNCTIONS declared
inside async bodies inherited the enclosing `_currentAsync*` return context (saved but never
CLEARED) — the nested body took the async wrap path and `ret` a ValueTask&lt;T&gt; struct from a
T-signature method; callers read 0/null (`zero := () => 99; return zero()` gave 0; string lambdas
gave silent null). Newly EXPOSED by this rung's routing (rung 0 declined all async programs).
Fixed front-door: the `_currentAsync*` trio now CLEARS after `SaveAndResetNestedMethodReturnContext`
in all three LambdaEmitter paths + the local-function emitter (async nested bodies re-establish
it); pinned by `ILCompiler_NonAsyncNestedBodiesInsideAsync_DoNotInheritAsyncReturnContext` AND two
columnar parity functions at the now-correct values. (2) columnar: a bare `return` under an
EXPLICIT `Task`/`ValueTask` annotation routed where the pipeline rejects NL305 (the unit-task
exemption covers FALL-THROUGH bodies only — boundary probe-pinned); explicit-unit asyncs now
decline bare returns. (3) columnar+pre-existing: a leading UNKNOWN token before `func`
(`pub async func f`) routed — with the async wrap applied — where the pipeline rejects NL101; the
adapter now requires each top-level func to be preceded only by modifier tokens chaining to the
file start, a `}`, or an import/package header's dotted tail (empirically tokenized: `import
System.Text` = 17,0,124,0). REFUTED: fault-guard interplay (throw-only/conditional/unit faulted
tasks), await-of-faulted propagation (async re-faults, non-async sync-throws — both match),
return widening/adoption under the wrap, all await positions, break/continue inside the guard,
main casing, modifier/index alignment over interleaved decls, the full regression sweep, and
idempotence.

Parity: `ColumnarCodegen_Parity_Async` — 13 value functions (constants, sibling awaits, sequential
awaits, awaits in if/while flow, params+locals across awaits, await-in-non-async, explicit
Task<int>, unit Task/bare bodies, await-as-statement composition, async+collections+interpolation
`sum=15`, lambda-in-async, local-func-in-async) + the `main` Task<int> surface pin + the
faulted-task pin + decline pins (try-in-async, generic async, explicit-unit bare returns ×2,
leading-garbage ×2). 318/318 dogfood. NEXT: async residual rungs (await-foreach kind 54, async
iterators, task-typed params, try-in-async) as needed by route-all — then interfaces → route-all
(gate: Phase P port) → emitter port (gate: SoA design doc).

---

## 2026-06-12 — ASYNC rung 0: the modifier guard — a live method-surface divergence closed

The async-arc recon (3 agents: oracle map / 15-probe sweep / kernel surface) re-shaped the arc and
found a LIVE soundness hazard. **Headline: the oracle emits NO async state machine** — N# async
lowers SYNCHRONOUSLY (ILCompiler.Async.cs header, deferred-by-design): `await` is a blocking
`GetAwaiter().GetResult()` (ValueTask via `AsTask()` first), returns wrap into completed tasks
(non-entry default **ValueTask&lt;T&gt;**; explicit task-likes honored; entry point = Task), the body
wraps in a fault guard whose catch converts to `Task.FromException` (probe-pinned faulted-task
parity), `await foreach` is a blocking enumerator loop, and async iterators eagerly materialize.
So the columnar arc is a SYNC-LOWERING MIRROR, not a state-machine build — the protected-region
(E2) and display-class machineries cover the structural needs. More recon pins: NO
await-outside-async diagnostic exists (probe: await in a plain func compiles and blocks — analyzer
stub at AnalyzeAwaitExpression); NL004 async-without-await is LINTER-side (runs regardless of
backend — no columnar mirror needed); the parity harness does NOT unwrap Task/ValueTask returns
(both invoke paths need an unwrap step before async parity rungs); `asyncDefaultType` is honored
by the Transpiler but HARDCODED to ValueTask in ILCompiler (oracle-bundle note #25); tokens
async=68/await=69 exist; node kind 53 still next-free (awaits take it in rung A).

**THE HAZARD (probe-found, fixed here):** an `async func` with NO await parses clean through every
kernel — the body has no kind-69 token to refuse, and the adapter's func scan picks the bare
`func` token, silently DROPPING the modifier (TopLevelDeclarationModifiers is scanned by the
symbol path but the emit path never asked). Columnar emitted `String Fetch()` where the oracle
emits `ValueTask&lt;string&gt; Fetch()` — a diverging method surface, exposed only behind
NSHARP_COLUMNAR_BACKEND=1 plus the corpus having zero async. Rung 0 adds the adapter guard: read
the declaration modifiers, decline any async-flagged function (Modifiers.Async = 1&lt;&lt;11) until the
lowering is modeled. Pinned both ways (`ColumnarCodegen_AsyncFunctionsDecline`). 317/317; gate
(see commit). NEXT: async rung A — the sync-lowering mirror (kernel kind-53 await + IsAsync
threading + wrap/fault-guard emit + harness Task unwrapping), then await-foreach/iterators rungs,
then interfaces → route-all (gate: Phase P port) → emitter port (gate: SoA design doc).

---

## 2026-06-12 — Arc M1a: CHECKSUM-CORPUS EXTRACTION — the product dogfood files shed their test scaffolding

The 94 `*Checksum*` functions (3,975 lines — 19% of the 20,912-line corpus) that existed solely as
parity-test oracles moved VERBATIM out of `src/NSharpLang.Compiler.Dogfood/CompilerServices/*.nl`
into a new **`src/NSharpLang.Compiler.Dogfood.ParityCorpus/`** (27 twin files, same names) — the
product files shrink 4,093 lines and the SHIPPED dogfood assembly no longer carries test
scaffolding (the MSBuild targets glob only covers the project root). The destination stays under
`src/` deliberately: the gate's BENCH step-input set covers `src/`+`benchmarks/`, so a `tests/`
corpus would have escaped cache invalidation (recon finding; GateStepInputSetGuardTests enforces
the set lists).

**All three consumer families re-pointed in-slice (the recon's hidden-consumer map):**
(1) the 9 in-test whole-project compiles now build product+corpus explicitly
(`CreateDogfoodWithParityCorpusCompiler` — `config.GetSourceFiles` + the corpus glob), keeping the
~80 `GetMethod("…ChecksumInto")` binds resolving; (2) the 13 real-file columnar parity tests read
through `ReadDogfoodFileWithParityCorpus` — the product text plus its corpus twin CONCATENATED is
the exact pre-extraction compilation unit (the wrappers delegate to sibling kernels in the product
file); (3) the BENCHMARKS — 67 checksum functions bound BY NAME in `[GlobalSetup]` across ~55
classes — embed the corpus via a glob `EmbeddedResource` (`NSharpLang.Benchmarks.ParityCorpus.*`)
and `DogfoodCompilerSources.ReadResource` now appends each corpus twin centrally, so every recorded
evidence suite still binds (probe-verified: 27 resources, merged sources contain the fused twins).
This consumer would have broken at benchmark RUNTIME only — the commit gate runs just
`SystemsFastGateBenchmarks` (inline sources), so nothing in the gate would have caught it.

**Zero-new-declines (the M-slice invariant):** new pin
`ColumnarCodegen_MultiFile_ParityCorpusCompilesWithZeroDeclines` — ALL product files + ALL corpus
files merged via `RouteColumnarMultiFile` must route AND emit every checksum function by name
(≥94, name-scanned from the corpus so the pin tracks its evolution). Single-file corpus routing
would decline by construction (the wrappers' sibling-kernel calls are cross-file), hence the
multi-file shape. The existing coverage ratchet + 32-file cluster pins keep passing on the slimmed
product files. 316/316 dogfood. Non-goals kept: the 11 fused class-(b) bodies (incl. the 8-way
LexerTokenKindScanner twin) moved VERBATIM — no restructuring; the wrapper-dedupe into generic
helpers is M1b (corpus-internal only, no product impact). Note: non-gated lexer/parser benchmark
evidence numbers shift on the slimmed files (SourceTextLines −70% … LexerTokenKindScanner −4%) —
the merged benchmark sources keep the OLD substrate via concatenation, so recorded numbers remain
reproducible there. NEXT: M1b wrapper dedupe (optional polish) or the queue: async → interfaces →
route-all (gate: Phase P port) → emitter port (gate: SoA design doc).

---

## 2026-06-12 — STRINGS slice 4: INTERPOLATION — the Arc-M1 rider rung

The queued `$"…"` rung, pulled forward per the M1 plan. Recon re-derived the machinery at HEAD:
a $-string lexes as **ONE kind-4 token** with the `$` and the holes inside the span (the kernel's
LexerTokenKindScanner already mirrors the production interpolation state machine and parses the
literal as a plain kind-3 node — NO kernel change, NO new node kind); the production parser
re-lexes the span (`ParseInterpolatedString`: `{{}}` collapse, brace-depth hole scan, the
`FindFormatSpecifierColon` ternary-guarded state machine, escapes VERBATIM in text parts); the
oracle lowers via **DefaultInterpolatedStringHandler** (`EmitInterpolatedString` ILCompiler.cs
~14423: empty → `ldstr ""`, no-hole → constant-fold to concatenated DECODED text, else
ctor(literalLength = decoded text lengths, formattedCount) + AppendLiteral(DecodeBody) +
AppendFormatted overload routing + ToStringAndClear). Alignment does not exist in N#.

**Columnar:** a new shared `ColumnarInterpolationSplitter` (one file) splits the kind-3 $-span
under a deliberately narrow hole grammar — **identifier chains only** (`name` / `name.field.field`)
with an optional `:format` (formats containing braces/quotes/backslashes decline outright: the
production hole scan is brace-depth aware while the splitter closes at the first `}`, so banning
those characters makes boundary divergence structurally impossible). The emitter's kind-3 arm
routes `$`-spans to `TryEmitInterpolatedString`: constant folds mirror the oracle; the handler
lowering resolves every hole EMISSION-FREE first (roots = locals/params — lifted/boxed roots
decline, so capture-scan blindness to in-span identifiers can never mis-capture; hops = registry
instance fields; builder-typed hole values decline — the oracle boxes those, a later rung), then
emits AppendFormatted by the oracle's routing (string→(string); format→generic (T,string);
else generic (T)). The diagnostics pass consumes the SAME splitter to mark hole ROOT identifiers
as uses (no more false NL001; un-splittable literals keep the throw → decline → the production
linter, exactly matching the emitter's decline of the identical program — uses and IL agree by
construction). The static-field-initializer `$` guard stays (general-expression inits unmodelled).

Parity: `ColumnarCodegen_Parity_StringInterpolation` — 12 value functions (basic, nested member
hole, `:F2` format, `{{}}` braces, escapes-in-text, empty, no-hole fold, adjacent holes,
int+string+double mix, param hole, string-with-format, and `onlyHoleUse` — a local used ONLY in a
hole routes without a false NL001) + 3 decline pins (call hole, ternary hole, builder-typed hole —
all oracle-accepted via the full sub-parse). The slice-3 wholesale-decline pin flipped (expression
position; the static-init decline pin stays). 315/315 dogfood; gate (see commit). NEXT: the M1
checksum-corpus extraction (plan pinned in the retirement-map memory: ParityCorpus sibling dir,
6 in-test whole-project compile sites, the benchmark EmbeddedResource/concatenation re-point,
multi-file zero-declines pin), then async → interfaces → route-all (gate: Phase P port) → emitter
port (gate: SoA design doc). Post-self-host perf queue opens with match→IL-switch.

---

## 2026-06-12 — D-18b: COLUMNAR MEMBER WRITES — param receivers, class/record locals, nested field chains, compound members

The columnar twin of D-18a, mirroring the FIXED oracle. The kind-8 assignment arm's two old tiers
(reference property setters on bare receivers; struct field writes on `:=` locals only) are
replaced by a unified CHAIN model: `TryResolveMemberWriteChain` resolves the receiver
**emission-free** (the emit-ownership rule) — the root must be a bare LOCAL or PARAM (lifted/boxed
roots decline: the capture-mutation family stays conservative; indexer/call-result roots decline:
those writes are pipeline-REJECTED NL322, parity by rejection via the fallback), hops must be
instance FIELDS on registered defs — then `EmitMemberWriteLocator` emits the owner value uniformly:
value-typed links by ADDRESS (`ldloca`/`ldarga`/`ldflda`), reference links by OBJECT REF
(`ldloc`/`ldarg`/`ldfld`); `stfld`/`ldflda` accept either owner form so the chain composes. New
arms: FIELD writes (int-literal/null adoption + TypesEquivalent/implicit widening on the value),
PROPERTY setters through chains ending in a REFERENCE receiver, and COMPOUND member writes
(`s.X += 1`, `o.i.X += 3` — locator; dup; ldfld; value; op; stfld, the dup'd-locator
read-modify-write on the same storage; scalar/string ops, decimal declines). `EmitLoadArgumentAddress`
(ldarga) uses the PRE-SHIFTED `_paramOrdinals` — instance methods already store i+1. Record fields
write like class fields (NOT init-only — probe-pinned). The capture-lifting write scans already
walk kind-8 chains to the root name, so member-written roots lift/classify correctly (verified).

TWO old decline pins FLIPPED (param-receiver struct mutation; record field mutation — its
"records may be init-only" rationale was probe-refuted in D-18a). TWO pre-existing DECL-level
gaps probe-bisected and pinned as declines (NOT this arm): structs with CLASS-typed fields
(oracle-accepted W11), and get/SET properties (the adapter parses both accessors, the emitter
models get-only — the nested-setter write flips when set-accessors emit).

**2-lens adversarial review (~70 value-compared probes): ZERO D-18b findings — every attack
refuted** (captures/lifts: member-written roots lift or decline exactly as designed, order-
independent; ldarga ordinals correct in static funcs, instance methods on classes AND structs,
ctors, local functions, closures; mixed-chain aliasing — reference links share storage, value links
copy — all match; compound opcode sweep incl. Div_Un/Concat/negative literals; widening
sign-extends; idempotent re-routing; a mixed collections+member-writes+generics program matches).
The review DID bisect one of this slice's decline pins to its true cause: the nested-receiver
SETTER write `h.p.Value = 5` IS modeled and value-correct — the pinned decline was the decl
kernel's member-ORDERING limit (the field/property loop stops at the first `id (` member, so a
property declared AFTER a ctor never parses). Re-pinned: property-first ordering is now a PARITY
case; the ordering limit is its own decline pin.

**Pipeline-side defects found by the review (columnar declines them ALL — recorded for the oracle
bundle):** (#23) string `-=`/`*=` is analyzer-ACCEPTED (no CS0019 analog) and
EmitCompoundAssignmentOperation (ILCompiler.cs ~15904) falls through to raw `sub`/`mul` on object
refs → AccessViolationException; the same fallthrough emits raw `add` on decimal members → SIGSEGV
(the member-target variant of known defect #15 — same site; a fix chip was filed). (#24)
enum-member writes (`Color.Red = Color.Green`) are accepted and emit unloadable field refs →
MissingFieldException. NL322 RESIDUAL: BCL PROPERTY hops (`kvp.Value.X = 5` in a dict foreach)
still accept-and-lose pipeline-side — the conservative classifier cannot resolve
GenericTypeInfo-typed owners (KeyValuePair) so it stays silent by design; columnar declines the
shape. Postfix `s.X++` on member targets: pipeline accepts (columnar declines — a small later
rung).

Parity: `ColumnarCodegen_Parity_MemberWrites` — 16 value functions (struct param local-vis +
caller-copy, class/record locals + params, nested struct-in-struct, struct-of-class, 3-deep
class→class→struct tail, nested-via-param, whole-struct field stores, compound struct/class/nested,
foreach-var copy semantics 51, nested property setter) + NL322 both-side pins (List<S> indexer +
call-result receivers: pipeline rejects AND columnar declines) + declines (closed-generic
receivers — field-handle rebind rung; class-typed struct fields; the member-ordering limit).
314/314 dogfood; focused suite green; gate (see commit). NEXT (retirement-map queue): **Arc M
interleave (M1 checksum extraction FIRST; pull the queued strings-interpolation rung forward to
ride with it)** → async → interfaces → route-all **(gate: Phase P port to columnar)** → emitter
port **(gate: SoA table design doc)**. Post-self-host perf queue opens with match→IL-switch.

---

## 2026-06-12 — D-18a ORACLE FIX: defect #22 — member writes through nested receivers were SILENTLY LOST (+ NL322, the CS1612 analog)

The D-18 recon's 24-probe oracle sweep found the pipeline UNSOUND for the exact shapes the slice
targets: any member write whose receiver chain passes through a value-typed hop that is not a bare
local/param/`this` compiled clean and **silently dropped the store** — `o.i.X = 5` read back 1
(struct-in-struct), `c.s.X = 5` → 1 (struct-field-of-class), nested-via-param → 1, 3-deep chains →
1, compound `o.i.X += 3` → unchanged, `arr[0].X = 5` (struct array) → 1, `lst[0].X = 5`
(List&lt;struct&gt;) and `makeS().X = 5` accepted-and-lost where C# rejects (CS1612). Mechanism:
`EmitAddressableExpression` (ILCompiler.cs ~9475) had NO MemberAccess/IndexAccess case — every
nested receiver fell to the temp-spill fallback and the Stfld wrote into the copy. The oracle could
not arbitrate D-18 until fixed (fix-oracle-first, the generic-user-types-arc pattern).

**Emitter fix:** `EmitAddressableExpression` gained the two missing cases. A MemberAccess receiver
whose member is an instance FIELD builds a real address chain — value-typed receivers recurse for
THEIR address (`ldflda` chains rooted at `ldloca`/`ldarga`/`ldarg.0`), reference-typed receivers
load the object ref (`ldflda` on a ref yields the interior pointer); resolution uses
`FindInstanceFieldOnBaseChain` for TypeBuilders and `TryGetDeclaredRuntimeField` (closed-generic
rebind included) otherwise. An ARRAY-ELEMENT receiver addresses via `ldelema`. Property receivers
keep the spill — they are rvalues, rejected up front by:

**NL322 `MemberWriteThroughValueCopy` (front-door analyzer rule, all backends):** a member write
(plain or compound) through a value-typed receiver that is NOT a variable — a List indexer result,
a call result, a property result — is now a compile error with an Elm-style explanation (the write
would land in a temporary copy and be thrown away). The classifier reads a reference-keyed
expression-type cache populated during target analysis (no re-analysis, no duplicate diagnostics)
and is CONSERVATIVE: unresolvable hops never fire. Legal and pinned: field chains rooted at
locals/params/`this`, array elements, every reference-typed receiver shape, and N#'s value-copy
semantics (struct params, foreach loop vars — mutable LOCAL copies, kept by design where C#
rejects).

Post-fix sweep: all six lost-write shapes store through (=5); W14b/W19b/N9 reject NL322; all 15
reference/value-semantics shapes unchanged. Pins: `ILCompiler_NestedValueReceiverMemberWrites_StoreThrough`
+ `ILCompiler_ThreeDeepStructTailWrite_StoresThrough` (oracle), 5 NL322 AnalyzerTests
(3 fire / 2 no-false-positive). Records confirmed NOT init-only in the pipeline (`r.X = 5` → 5 —
the columnar tier-3 comment overstated; D-18b models it). Full unit suite green. NEXT: D-18b —
the columnar member-write slice (param receivers via `ldarga`, class/record-local receivers,
nested field chains mirroring the FIXED oracle), then the queue line below.

> NEXT (retirement-map queue): D-18b columnar member writes → **Arc M interleave (M1 first; pull
> the queued strings-interpolation rung forward to ride with it)** → async → interfaces →
> route-all **(gate: Phase P port to columnar)** → emitter port **(gate: SoA table design doc)**.
> Post-self-host perf queue opens with match→IL-switch.

---

## 2026-06-12 — COLLECTIONS rung 4: BUILDER-ELEMENT REBIND — List&lt;UserType&gt; + List&lt;T&gt;-in-generic-funcs

The last pinned collection rung flipped: collections closed over types **still under construction**
— user TypeBuilder elements/values (`List&lt;Pt&gt;`, `Dictionary&lt;string, Pt&gt;`, nested
`List&lt;List&lt;Pt&gt;&gt;`, collection-typed record FIELDS) and a generic function's own `T` (`List&lt;T&gt;`
params/returns/foreach/indexing/Count, inferred `first(l)` and explicit `first&lt;int&gt;(l)`). Recon
workflow first (4 agents: oracle map / columnar site map / Reflection.Emit spike / 24-probe oracle
sweep — ALL target shapes oracle-ACCEPTED with pinned values).

**Mechanism (the oracle's idiom, spike-proven):** every member binding on a builder-bound closed
instantiation REBINDS from the open runtime definition — `TypeBuilder.GetMethod/GetConstructor(closed,
openDefMember)` — because ALL plain reflection throws on a TypeBuilderInstantiation. New helpers:
`ContainsBuilderBoundType` (detects builders ANYWHERE in a shape — `Module`/`Assembly`/
`ContainsGenericParameters` all report baked-looking values on BCL-headed TBIs, spike-proven; a
USER-headed instantiation like `Box&lt;int&gt;` is builder-bound via its DEFINITION) +
`ResolveClosedGenericMethod/Ctor` (rebind vs `GetMethodFromHandle` by that predicate) +
`IsAdmissibleCollectionElement` (replaces the `Module is not ModuleBuilder` gate, which was both
too strict for this rung and silently leaky for tuple-over-builder elements). Nine sites converted:
ctor (parameterless+capacity), Add/RemoveAt/ContainsKey, Count, kvp Key/Value, get_Item, set_Item,
foreach GetEnumerator/get_Current (interface instantiations rebind identically). **Two wrong-IL
hazards pre-empted:** a REBOUND member reports the OPEN T/TValue as its ReturnType (spike-proven) —
get_Item and the KVP getters now derive result types from the CLOSED GetGenericArguments.
**Foreach note:** the oracle takes the STRUCT `List&lt;T&gt;.Enumerator` route for builder elements
(TBI.GetInterfaces() throws, so its interface lookup comes back empty); columnar keeps the
boxed-interface shape — value-identical (same MoveNext version check; mutation-IOE parity pinned,
review-probed across break/continue/early-return).

**Generic-function path:** `TryResolveTypeWithTypeParams` gained the collection arm (threads the
type-param map into element resolution — `List&lt;T&gt;` closes over the GenericTypeParameterBuilder);
`TryEmitGenericSiblingCall` gained `TryUnifyGenericContainer` (structural recursion: `List&lt;int&gt;`
vs `List&lt;T&gt;` ⇒ T=int, mirroring the oracle's TryCollectGenericBindings); `TrySubstituteReturnType`
gained a BCL-collection arm that re-closes the runtime definition (MUST intercept builder-bound
instantiations — the defensive `ContainsGenericParameters` tail reports FALSE on TBIs, so falling
through would leak an open MVAR). `TryUnifyTypeParam` now declines ALL builder-bound bindings
(T=Pt / T=List&lt;Pt&gt; pinned out — MakeGenericMethod/constraint checks reflect on the binding).

**Cross-cutting:** `TypesEquivalent` generalized to every closed instantiation (independent
`MakeGenericType` calls over builders yield referentially DISTINCT TBIs — probe-proven) and
`EmitArg` now uses it (`outer.Add(inner)` crosses two resolutions); object-init field-value checks
likewise. Gate hardenings so new shapes decline CLEANLY instead of throwing into the adapter's
blanket catch: tuple elements (recognition AND the literal-emission ctor site), delegate args,
StrongBox lift, and the PASS 0e record-synthesis bakedness test (a `List&lt;Pt&gt;`-field record would
have whole-program-declined via EqualityComparer reflection; synthesis now SKIPS it like any
builder-typed field — `.Equals`/`with` on such records decline, pinned).

**Record collection FIELDS needed a kernel extension:** `ParseStructDeclarationInto`'s field type
was hard-coded to ONE token — instance fields now accept a balanced generic suffix (`Items:
List&lt;int&gt;`, `Dictionary&lt;string, Pt&gt;`, `List&lt;List&lt;Pt&gt;&gt;`; RightShift 112 credits TWO close
levels), whitespace-stripped onto the canonical grammar by the adapter. Static/property composed
types stay single-token (whole-decl decline → fallback).

**3-lens adversarial review (92+60+~40 probes, all value-compared against the oracle):** soundness
lens — ALL SIX attack surfaces REFUTED (open-type leaks, TypesEquivalent equating distinct types,
nested/conflicting/explicit unification, foreach divergence, record-field aliasing, kernel `&gt;&gt;`
scan). Over-accept lens found **one slice-introduced CONFIRMED-BREAK, fixed in-slice:** the
whitespace strip FUSED adjacent identifiers (`List&lt;i nt&gt;` → `List&lt;int&gt;` routed; pipeline rejects
NL102) — the kernel scan now rejects identifier-after-identifier; **plus the List/Dictionary
HEAD-SHADOWING divergence (fixed):** a user type NAMED List/Dictionary makes the pipeline reject
every closed-generic use (NL207 non-generic, NL303 generic — the "user wins, Action precedent"
ordering is WRONG for these heads), so columnar now declines shadowed heads outright (the
pre-existing baked-element variant of this hole closed too). Decline-cleanliness lens: regression
sweep fully green; `ContainsBuilderBoundType` gained the user-headed-definition check (the
`List&lt;Box&lt;int&gt;&gt;` pin was declining only via a swallowed NotSupportedException — now a clean
resolution decline, which also restored the PASS 0e skip for closed-user-generic fields).

**Oracle laxness recorded (defect-bundle candidates, both probe-found by the review):** the
pipeline ACCEPTS `Items: int&lt;int&gt;` field types (no arity/genericity validation on the head —
columnar declines, safe), and the object-initializer accepts mismatched generic collection field
types (pre-existing, slice-independent; columnar declines).

Parity: `ColumnarCodegen_Parity_CollectionsBuilderElements` — 16 value functions + the
mutation-during-foreach IOE pin + 11 decline pins (enum elements — un-baked EnumBuilder dies at
ILGenerator.Emit token resolution, bake-first is a later rung; builder dict KEYS — record-key
hashing rides synthesized equality, PASS 0e skew; `List&lt;Box&lt;int&gt;&gt;`; body-side `new List&lt;T&gt;()`
— no type-param map at body resolution, signature surface only this rung; T=Pt inference;
tuple-over-collection; `.Equals` on collection-field records; identifier fusion; head shadowing
×3). The two old decline pins flipped; HashSet + Dictionary.Add stay out. 311/311 dogfood; full
unit suite green (`dev.sh --since` escalated to it); gate (see commit). NEXT (retirement-map
queue): pinned collection rungs DONE → **D-18 member writes (param receivers / nested receivers /
class-local receivers)** → **Arc M interleave (M1 first; pull the queued strings-interpolation rung
forward to ride with it)** → async → interfaces → route-all **(gate: Phase P port to columnar)** →
emitter port **(gate: SoA table design doc)**. Post-self-host perf queue opens with match→IL-switch.

---

## 2026-06-11 — COLLECTIONS: List&lt;T&gt;/Dictionary&lt;K,V&gt; — construction, members, indexers, foreach

A recon workflow mapped corpus/oracle/columnar in parallel first; the **20-probe oracle sweep came
back ALL GREEN** (construction incl. capacity ctors, Add/RemoveAt/ContainsKey/Count, index
read/write, foreach + break/continue, mutation-during-foreach throwing, nested
List&lt;List&lt;int&gt;&gt;/Dictionary-of-Dictionary, user-record elements, List&lt;T&gt; in generic funcs, dict
foreach with kvp). Notably the dogfood corpus itself uses ZERO collections — this slice serves the
examples/route-all surface.

**Landed (baked runtime type args only):** TryResolveType closes `List&lt;`/`Dictionary&lt;` AFTER user
generics (the Action precedent; builder-typed args decline → List&lt;UserRecord&gt; and List&lt;T&gt;-in-
generic-funcs are pinned for a later rebind rung); IsSupportedCollectionType joins IsSupportedType;
kind-15 newobj (parameterless + int-capacity ctors); Add/RemoveAt/ContainsKey instance calls; Count
in case 8's user-type branch (the Message precedent — all non-Length members route there); get_Item
in case 10 and set_Item in the index-assignment arm (the dominant `d[k] = v` shape; nested chains
compose for free — `d["db"]["host"] = v` is a get_Item receiver under a set_Item).

**FOREACH-over-List mirrors the oracle's exact shape** (recon pre-read, ILCompiler.cs:13180-13325):
the enumerator comes from the IEnumerable&lt;T&gt; INTERFACE — the List&lt;T&gt;.Enumerator struct is BOXED
(the oracle resolves the interface first); MoveNext/get_Current/Dispose callvirt through the
interfaces; Dispose sits at a DISPOSE LABEL after the loop, NOT in try/finally — `break` branches to
it (the loop-label Break target IS the dispose label), early returns/exceptions skip it (the boxed
List enumerator's Dispose is a no-op, so value parity holds — mirrored, not "fixed"). This is what
makes mutation-during-iteration throw InvalidOperationException identically — an index loop would
have silently diverged (probe-pinned).

**Rung 2 (same day): DICTIONARY FOREACH flipped** — the boxed-interface enumerator branch
generalizes to Dictionary with element = KeyValuePair&lt;K,V&gt; (the same shape; mutation-throws
included), plus case-8 `kvp.Key`/`kvp.Value` arms (a VALUE-type receiver: spill + ldloca + call the
non-virtual getter) and IsSupportedKeyValuePairType for the loop-var local.

**Rung 3 (same day): COMPOUND INDEXERS flipped** — `d[k] += v` / `lst[i] += 1` in the
compound-assignment arm: receiver and index evaluate ONCE into temps (C#'s single-evaluation
semantics), get_Item, the scalar/string op selection (the bare-local compound discipline), set_Item.

**Gate-validation postscript:** rung 3's first two gate runs failed the Systems benchmark step on
SHIFTING scenarios (CallerBuffers 1.0556, then ResultAbi 1.4774) with absolute medians DOUBLED
machine-wide — concurrent-session load, not the commit. An A/B settled it: the parent `402bbae1`
passed in a calm window, and the DECIDING run at `cab8581d` in the same window passed clean
(CallerBuffers 0.9994, all scenarios ≤1.0, medians back to baseline). Process lessons recorded:
commits are BLOCKED on the gate-verdict grep (never chained blindly); benchmark disputes get
benchmark-only/A-B controls; shifting-scenario failures with elevated absolute medians = load, not
regression.

Parity: `ColumnarCodegen_Parity_Collections` — 15 value functions + 3 exception-parity pins
(ArgumentOutOfRangeException / KeyNotFoundException / mutation InvalidOperationException) + 4
decline pins (List-of-user-type, List&lt;T&gt;-in-generic-func, HashSet, Dictionary.Add — every one
oracle-ACCEPTED, flips when its rung lands). 307/307; gate (see commit). NEXT: the builder-element
rebind rung or the queue's async/interfaces.

---

## 2026-06-11 — RECORDS COMPLETION: `with` + the synthesized value members

**PASS 0e** synthesizes the record value members on every NON-GENERIC record whose field types are
baked runtime types, mirroring the oracle VERBATIM: `Equals(object)` (null-check + isinst + per-field
`EqualityComparer<T>.Default.Equals`), `GetHashCode()` (the 17/23 accumulator), and `<Clone>$`
(MemberwiseClone + castclass — the FAMILY-access wrapper `with` lowers through). A USER method named
Equals/GetHashCode keeps ownership (the pinned `hsh` behavior — that member's synthesis is skipped).
Classes get NONE: a class `.Equals` is the pipeline's NL103 (probe-pinned) — parity by rejection.

**Probe-pinned N# semantic, mirrored exactly: `==`/`!=` on records AND classes is REFERENCE
equality** (NOT C# record semantics — value equality lives only in `.Equals`): a new ceq arm for
registered reference-type operands. `.Equals(other)`/`.GetHashCode()` resolve AFTER user methods in
the instance-call path (record receivers only; unboxed value args decline).

**`with`** (token 71 — empirical) parses in the kernel's postfix loop exactly where the production
parses it (Parser.cs:4510): expression kind 52 [receiver, name/value pairs] (53 next free), the
kind-36 pair layout with the receiver in place of the type root; zero pairs = a pure clone. Emit:
callvirt `<Clone>$`, stfld overwrites, exactly the oracle's EmitWithExpression. Kind 52 joined
ContainsCaptureOpaqueKind (its kind-6 children are FIELD names — the positional capture scan would
mis-read them). DECLINED: with-on-CLASS (oracle-side it calls the protected MemberwiseClone
cross-type — unverifiable IL), with-on-GENERIC-record (the known-broken oracle B4 residual),
unknown field names, builder-typed-field records (no synthesis).

Slice tooling note: first slice run on the new `./scripts/dev.sh` inner loop (aea1ca80) — focused +
`--since` change-aware selection; the full --commit gate unchanged. Record `.ToString()` remains
pipeline-rejected (NL905 maybe-null on the receiver) — pinned by probe, no columnar surface.

Parity: `ColumnarCodegen_Parity_RecordValueMembersAndWith` — 7 value functions (with-one/all/pure-
clone, value-Equals, hash agreement, record + class reference-`==`) + 4 decline pins. 306/306; gate
(see commit). NEXT (retirement-map queue): collections, async, interfaces — toward route-all (Arc 2).

---

## 2026-06-11 — Oracle defects #20 and #21 FIXED: NL319 (control transfer out of finally) + NL320 (lock requires reference type)

Both queued exceptions-arc oracle defects closed with FRONT-DOOR analyzer rules shared by every
backend (IL, columnar routing, C# export), plus emitter defense-in-depth.

**Defect #20 → NL319 (`ControlTransferOutOfFinally`, the CS0157 analog).** A `return` anywhere
inside a `finally` (depth-based — a return inside a try/lock nested in the finally still leaves it),
or a `break`/`continue` whose target loop/switch was entered at a SHALLOWER finally depth, is now a
compile error. Pre-fix, the void-return/break/continue forms BUILT clean and threw
InvalidProgramException on every call (ilverify: LeaveOutOfFinally), and the "NL305 shields value
functions" assumption was WRONG for the returning-catch shape (try+catch satisfy always-returns, the
finally is ignored — probe-proven invalid IL). The C# export leaked raw CS0157; it now fails at
analysis with NL319. Legal and probe-kept: `throw` in a finally, loops opened INSIDE the finally,
returns in lambdas/local functions declared in the finally (analyzer context resets at nested-body
boundaries). Emitter guards: ILCompiler `_finallyHandlerDepth` (BranchTarget now also records the
finally depth at loop entry) throws "compiler bug … NL319" from EmitReturn/EmitBreak/EmitContinue
rather than ever emitting `leave` out of a handler; the columnar declines remain as emitter-contract
guards. Columnar mirror: `ColumnarDiagnosticsPass.CollectFinallyTransfers`
(`finally-transfer@line:col`), AST-walk parity-pinned; the E4 decline pins now also pin the NL319
pipeline verdict.

**Defect #21 → NL320 (`LockRequiresReferenceType`, the CS0185 analog).** A `lock` on a KNOWN value
type (builtins, struct, enum, record struct, tuple, `T?` over a value type, reflection IsValueType)
is now a compile error — pre-fix it built clean and SEGFAULTED the process (no managed exception) in
Monitor.Enter via the raw `stloc` of an unboxed value into the object lock local. STRICTER than C#
on generics by decision: an unconstrained/non-reference-constrained `T` lockee is NL320 with a
constraint hint (`where T: class`) — Roslyn boxes it into a lock that can never provide mutual
exclusion. The predicate is conservative: Unknown/External/GenericTypeInfo stay silent (no false
positives on unclassifiable external reference types). EmitLock now emits the defensive
`box` for value/generic-parameter lockees — the required Roslyn lowering for the legal
class-constrained `T`, ilverify-clean. The columnar value-lockee decline remains as the emitter's
contract guard; the E5 decline pin now also pins the NL320 pipeline verdict.

Coverage: 30 analyzer facts (AnalyzerTests NL319/NL320 regions), emitter-guard fact
(ILCompiler_ControlTransferOutOfFinally_NeverReachesEmit), lock IL-shape box pins
(LockStatementIlShapeTests), CheckCommand JSON span pins, export-fails-with-NL319 pin, columnar
finally-transfer parity (ColumnarDiagnostics_FinallyTransfers_MatchesAstWalk; the in-test AST mirror
gained the E4/E5 throw/try/lock arms it had lagged). Docs: language-tour lock section + the first
in-repo error pages (website/docs/errors/NL319.md, NL320.md). Codes NL317/NL318 were events; 319/320
are the next slots. NOT touched (still queued): oracle defects #16/#17 (unknown catch types become
catch-alls / non-exception catch types accepted) and the `using` IDisposable TODO (explicitly
deferred).

---

## 2026-06-11 — EXCEPTIONS E5: the lock statement — THE EXCEPTIONS ARC's MAIN LADDER CLOSES

`lock <expr> { }` (Lock token **80** — empirically verified) parses as **kind 51** [lockee, body]
(52 next free). The emit mirrors the oracle's EmitLock verbatim — `Monitor.Enter(obj); try { body }
finally { Monitor.Exit(obj) }` — so locks ride the whole E2–E4 protected-region machinery for free:
structured returns through the lock's finally, loop-crossing leaves (break out of a lock runs
Monitor.Exit), the body-level tail. Always-returns propagates the BODY in both mirrors
(probe-pinned: `lock s { return 1 }` needs no trailing return).

**Probe-found oracle defect #21 (queued, PROCESS-KILLING):** a value-type lockee (`lock n` on int)
compiles — no CS0185 analog — and the emitted IL stores the unboxed value into the object local: a
fake reference that HARD-CRASHES the process (segfault, no managed exception) in Monitor.Enter.
Columnar declines value lockees; the decline pin is route-only and must never invoke the oracle.
`using` stays deferred — the columnar type surface has no IDisposable values to model (kernel-refused,
pinned). Also noted pre-existing: member WRITES through locals (`b.v = ...`) are unmodeled in
top-level bodies (lock or no lock) — the parity shape reads instead.

Parity: `ColumnarCodegen_Parity_LockStatement` (string/class lockees, return-in-lock,
break-out-of-lock-in-loop) + 3 decline pins (#21 value lockee, lock-nested-in-try, using). 305/305;
gate (see commit).

**THE EXCEPTIONS ARC IS COMPLETE** — E1 throw `4358d24c`, E2 try+bare-catch `d02f30c2` (+E2b invalid-
IL twin fix `6774728d`/`eaed17b1`), E3 typed catches `c3367729`, E4 finally + loop-crossing
`a91112ed`/`a77116b0`, E5 lock — seven gated commits, FOUR new oracle defects found (#18 fixed, #19
fixed, #16/#17/#20/#21 queued), one cardinal NL316 class closed. NEXT (retirement-map queue): records
completion, collections, async, interfaces — toward route-all (Arc 2).

---

## 2026-06-11 — EXCEPTIONS E4: finally + the try-inside-loop revisit — and oracle defect #19

The `finally` parses as a trailing kind-25 BLOCK child of kind 49 (distinguishable from kind-50
catches by kind); zero catches are valid WITH a finally. Emit: BeginFinallyBlock + statements +
EndExceptionBlock — leaves through the region run the handler natively.

**Probe-found oracle defect #19, FIXED in-slice (fix-oracle-first):** break/continue from inside a
try/catch/finally whose loop began OUTSIDE the region emitted a plain `br` — invalid IL,
InvalidProgramException on EVERY call (while/for/foreach, fully general). The dormant
BranchTarget.useLeave scaffolding (every push passed false) was replaced with the protected-region
DEPTH recorded at loop entry; EmitBreak/EmitContinue emit `leave` exactly when the branch crosses
outward (running an intervening finally — probed 32 on the break-through-finally shape), `br` when
the loop is wholly inside one region (probed 3). The columnar twin: `_loopLabels` entries record
(InProtectedRegion, InFinallyRegion) at push; cases 21/22 emit leave on crossing, and DECLINE a
branch out of a FINALLY (illegal IL — the pipeline still emits invalid IL for break/void-return in
finally, **defect #20, queued**; NL305 shields the value-return form).

**The always-returns QUIRK, mirrored verbatim:** the analyzer's TryStatement arm requires ≥1 CATCH —
the finally is ignored — so a zero-catch `try {return} finally {}` NEVER satisfies always-returns
(NL305 demands a trailing return; probe-pinned). Both mirrors skip the kind-25 finally child and
return false with zero catches. CollectUnreachable recurses the finally; NL312 fires after a
try+all-catches-return regardless of the finally (probe-pinned).

Parity: `ColumnarCodegen_Parity_FinallyAndLoopCrossing` — 9 value invocations (tcf both paths,
zero-catch tf, return-in-try+trailing, break/continue-in-try-in-loop, break-through-finally,
plain-try-in-loop, loop-wholly-in-try) + route-only propagation/throw-in-finally pins + 6 decline
pins (NL305 quirk, NL312-after-tcf, return-in-finally ×2, break-in-finally, catchless-finallyless
try). Oracle pin: ILCompiler_LoopBranchesCrossingExceptionRegions_EmitValidIl. E2's finally and
try-inside-loop pins FLIPPED. 304/304; gate (see commit). NEXT: E5 using/lock.

---

## 2026-06-11 — EXCEPTIONS E3: typed catches + exception binding

Each catch is now a **kind-50 CatchClause** node (value span = the exception TYPE name token, -1 for
bare; children [nameIdent (kind 6)?, block]) under kind 49's `[tryBlock, catch1..catchN]` (variable
arity via the LIFO arg-stack, the block discipline). All FOUR production catch forms parse
(Parser.cs:3016-3051): `catch (e: T)`, `catch (T)`, `catch (T e)`, paren-less `catch e: T` — plus
bare. The TYPE must be a single Identifier token. Cross-line `}\ncatch` follows the same
no-newline-skip discipline as `}\nelse` (pre-existing kernel policy).

**Emit:** clauses become sequential `BeginCatchBlock(type)` regions — first-match-in-declaration-
order natively; base-before-derived is accepted with a dead second clause (probe-pinned: no
dead-clause diagnostic in the pipeline). The bound variable is a fresh clause-scoped local (stloc of
the pushed exception, registered in `_locals` only during its clause's block). Types resolve through
a strict 14-name BCL exception whitelist; `e.Message` resolves via a new Exception-receiver arm in
case 8's user-type branch (callvirt get_Message) — the arm must live INSIDE that branch: all
non-Length/non-ItemN members route there and `return false` for unregistered receivers (bisected
when the first parity run declined every `.Message` shape).

**Probe-found oracle defects (queued #16/#17):** an UNKNOWN exception type (`catch (e:
TotallyMadeUpException)`) compiles with no NL201 and silently becomes a CATCH-ALL; a NON-exception
type (`catch (e: int)`) compiles to a dead clause (no CS0155 analog). Columnar declines both rather
than inherit either. Catch-var SHADOWING is the pipeline's NL316 error — declining is parity-by-
rejection (the oracle EmitTry's store-into-existing-local branch is dead code behind it). NO bare
rethrow exists in N# (NL102, E1) — `throw e` of the bound var is the rethrow spelling.

**Faithfulness:** both AlwaysReturns mirrors take the all-clauses rule (try AND every clause block);
CollectUnreachable recurses every region. The name child being a kind-6 USE makes every name scan
treat catch vars as always-used — the Linter's exact rule (no NL001), for free. The NL001 mirror
test's C#-side walk gained TryStatement/ThrowStatement arms (a latent test-mirror gap: a local used
only in a throw expression was missed C#-side) + catch cases.

**Adversarial review → the REAL hole was NL316 across nested-body boundaries.** The review flagged
the capture scan reading the catch-var name child; probing the claim found the adjacent CARDINAL
violations: sub-emitters couldn't see the parent's binding names, so a nested binding shadowing an
enclosing one — pipeline-REJECTED NL316 — COMPILED columnar-side. Probe matrix: catch vars (E3-new),
lambda `:=` locals, lambda PARAMS, local-func locals, local-func PARAMS all over-accepted (the
lambda/local-func ones pre-existing since the lambdas/L4-i arcs); foreach/deconstruction-in-lambda
already declined. Fix: `_enclosingBindingNames` threaded into every nested sub-emitter — lambdas get
the parent's LIVE snapshot (textual visibility, matching the analyzer's sequential scope walk), local
functions get the parent's STRUCTURAL binding superset (their bodies emit after the parent's; extra
declines are safe) — and ALL six binding sites (`:=`, typed locals, foreach vars, deconstruction
names, match-arm bindings, catch vars) plus lambda/local-func PARAM registration now check it via one
`IsVisibleBindingName` helper. Legit nested try/catch (capturing and isolated lambdas) value-proven.

Parity: `ColumnarCodegen_Parity_TypedCatches` — 16 value invocations across all forms (selectivity,
multi-catch, same-name sibling clauses, e.Message/.Length, base-typed binding, DivideByZeroException
runtime fault, base-first ordering) + 3 route-only exact-exception pins (uncaught-type propagation,
wrap-and-rethrow via e.Message, `throw e`) + 5 decline pins (#16, #17, NL316 shadowing, `_` binding,
multi-token type) + `ColumnarCodegen_NestedBindingShadowing_DeclinesAndLegitCasesEmit` (6 NL316
decline pins + 2 nested-try value cases). E2's typed-catch/multi-clause pins FLIPPED. 302/302; gate
(see commit). NEXT: E4 finally (+ try-inside-loop revisit), E5 using/lock.

---

## 2026-06-11 — E2b: throw-terminated exception blocks emitted INVALID IL — both pipelines, fixed both

E3's VERIFY-FIRST probe sweep found the wrap-and-rethrow catch pattern (`try {...} catch { throw new
... }`) throwing **InvalidProgramException on every call — in BOTH pipelines** (oracle defect #18 +
an E2 columnar hole the parity tests missed because no shape exited every region via throw).

**Mechanics:** Reflection.Emit's BeginCatchBlock/BeginFinallyBlock/EndExceptionBlock append implicit
`leave` instructions, which make the post-block position reachable in the JIT importer's view EVEN
when every region exits via `throw` (the leaves are dead, but the importer doesn't do dead-code
analysis — a `leave` makes its target reachable). A value body whose only exits are throws inside a
try/catch (or lock/using — same mechanics through their try/finally) therefore still needs a method
tail; without one, control "falls off" a reachable method end. IL dump pinned it: both leaves
targeted offset 33 of a 33-byte method.

**Oracle fix:** new `_emittedExceptionBlockInBody` (set at all SIX BeginExceptionBlock sites —
EmitTry/EmitLock/EmitUsing/EmitAssertThrows, plus EmitErrorTupleDeconstruction and
BeginAsyncFaultGuard, the latter two found by the adversarial review as invariant gaps that cannot
manifest on analyzer-accepted input — NL305 guarantees code follows a non-exiting declaration, and
async tails are unconditional — but are hardened anyway; reset per body; saved/restored across
nested-body emission in NestedMethodReturnContext). The structured-return tail now also fires when the body
emitted an exception block and never returned, at all THREE tail sites: top-level functions
(~11140), type-member methods (~24009), nested lambda/local-function bodies
(TryCloseNestedStructuredReturn — value bodies only; void/generator/async keep their own tails).

**Columnar twin:** EmitProtectedReturnTail emits whenever ANY try exists (`_protectedDoneCreated`),
not only when a protected return targeted it; `_protectedReturnUsed` deleted. The all-throws tail is
`done: ldloc result; ret` over a never-stored (zero-initialized, InitLocals) local — dead in
practice, reachable in the importer's view, valid.

Pins: ILCompiler_ThrowTerminatedExceptionBlocks_EmitValidIl (wrap, var-flow wrap, lock-throw,
local-func all-throws — exact messages) + TryBareCatch grew throwTry/throwCatch value parity and the
route-only all-throws wrap/wrapVoid pins. 300/300; gate (see commit).

---

## 2026-06-11 — EXCEPTIONS E2: try + bare catch — protected regions enter the emitter

`try { } catch { }` (Try **38** / Catch **39** / Finally **40** — empirically verified) parses as
**statement kind 49** (children [tryBlock, catchBlock]; 50 next free), in ParseStatementCoreNode — the
branch needs `depth` for its block recursions, which the simple-statement entry doesn't carry. The
kernel models exactly the BARE single-catch form: a non-`{` token after `catch` (BOTH typed forms —
parenthesized `catch (e: T)` and the pipeline's paren-less `catch e: T`, Parser.cs:3046), a second
`catch`, or a `finally` refuse.

**The spike-pinned IL rules** (a /tmp Reflection.Emit spike, green first run): (1) `ret` is INVALID
inside a protected region — a protected `return` lowers to `stloc result; leave done` with ONE
body-level `done: ldloc result; ret` tail (value-less returns just `leave`; the tail emits only when
some protected return used it); (2) `BeginCatchBlock(Type)` implicitly ends the try and PUSHES the
exception object (`Pop` — the bare catch), `EndExceptionBlock` implicitly leaves the catch. The
oracle's bare catch is `BeginCatchBlock(typeof(Exception)) + Pop` (ILCompiler.EmitTry) — matched
exactly. Declines: NESTED try (one level this rung) and try-inside-LOOP (`_loopLabels.Count > 0` — a
break/continue in the region would branch out of it; E4 revisits with the leave-through-region rules).

**Faithfulness, again in-slice:** both AlwaysReturns mirrors grew the kind-49 arm — a try exits iff
the try block AND the (single bare) catch exit, the analyzer's TryStatement rule restricted to this
rung — and CollectUnreachable recurses both regions. So `try {return} catch {} return d` keeps its
trailing return reachable (no NL312) while `try {return} catch {return}` satisfies NL305 alone.

**Probe-found lexer truth:** a function literally named `partial` declines — the lexer tokenizes
`partial` as a keyword token, not Identifier(0), so the kernel's name check refuses it (pre-existing,
not E2; surfaced because the test's fall-through function was named `partial`). Under-accept, safe.

Parity: `ColumnarCodegen_Parity_TryBareCatch` — 5 shapes × 10 invocations (runtime-fault catch,
user-throw catch, both-regions-fall-through, try-returns/catch-empty + trailing return, VOID body
with value-less protected return) + 7 pipeline-valid decline pins (typed catch ×2 forms, second
catch, finally, try-only-finally, nested try, try-inside-loop). 299/299; gate (see commit). NEXT:
E3 typed catches + exception binding, E4 finally, E5 using/lock.

---

## 2026-06-11 — EXCEPTIONS E1: the `throw` statement

The exceptions arc opens (probed: typed catches, bare catch, finally, throw all work oracle-side —
20/-1/1025 pinned). E1: `throw <expr>` (Throw token 37) parses as **statement kind 48** (one child; a
bare rethrow is the catch rung's shape, unparsed); the emit checks Exception-assignability and emits
`throw`. The kind-15 BCL ctor whitelist gained the 1-arg-string exception constructions
(Exception/InvalidOperationException/ArgumentException/FormatException/NotSupportedException — the
identical ctors the pipeline binds).

**The faithfulness discipline, applied:** ColumnarDiagnosticsPass's correctness was BY CONSTRUCTION
("the kernel refuses throw/try/switch") — so BOTH AlwaysReturns mirrors (the emitter's and the
diagnostics pass's) grew the kind-48 always-exits arm IN THIS SLICE, keeping NL305 (`throwOnly` needs
no return) and NL312 (code after throw is unreachable) exact. Every future kernel statement addition
must extend the pass the same way.

Parity: `ColumnarCodegen_Parity_ThrowStatement` (+ the route-only throw pin with exact exception
type/message) + 3 decline pins (unreachable-after-throw NL312, non-exception operands, bare rethrow).
298/298; gate (see commit). NEXT exception rungs: E2 try + bare catch (BeginExceptionBlock machinery +
the diagnostics try/catch reachability rules), E3 typed catches + binding, E4 finally, E5 using/lock.

---

## 2026-06-11 — NULL & NULLABLE N4: `is`/`as` type tests — the null arc's main ladder closes

`is` (token **47**) / `as` (**48**) parse as kernel kinds **46/47** (children [value, typeRoot] — the
TYPE subtree in child 1, so every name scan walks the VALUE child only; a single non-chaining wrap after
the unary operand, binding at the production's relational tier; 48 next free). `is` emits
`isinst; ldnull; cgt.un` → bool; `as` keeps the target type (null on mismatch). Targets resolve to UNION
CASES — including cases CLOSED over a generic scrutinee via the match machinery (`o is Opt.Some` on
Opt&lt;int&gt;) — or registered REFERENCE types; value-type `as` targets and cross-union `is` tests decline
(pipeline-rejected, pinned).

Parity: `ColumnarCodegen_Parity_IsAsTypeTests` (8 functions incl. closed-generic-union `is`, `as`-null
propagation, `is` in if-conditions) + 2 decline pins. 297/297; gate (see commit).

**THE NULL ARC's MAIN LADDER IS CLOSED** (N1 references `50859b68`, N2 Nullable&lt;T&gt; `de4d453f`, N3 must
`ebda73d3`, N4 is/as — four gated commits). Remaining minor rung: lifted Nullable arithmetic
(probe-first, queued). NEXT (retirement-map queue): exceptions/using/lock, records completion,
collections — toward route-all (Arc 2).

---

## 2026-06-11 — NULL & NULLABLE N3: the `must` prefix null-assert

`must <operand>` (Must token **20** — empirically verified, NOT the 51 a source-line count suggested;
the doctrine's verify-ordinals rule pays again) parses as kernel kind **45 MustExpression** (one child,
recursing at the unary level so `must must x` chains — the production shape; 46 next free). The emit
mirrors the oracle's `EmitMustExpression` exactly: a Nullable&lt;T&gt; unwraps HasValue/get_Value, throwing
`InvalidOperationException("must unwrap failed: value was null")` — the byte-exact pipeline message —
when empty; a reference null-checks dup/brtrue/pop/throw keeping its type. **A redundant `must` on a
plain value type DECLINES** — probe-found: the pipeline's analyzer rejects it with NL907 before the
oracle emitter's no-op pass-through would ever run (the emit-side mirror alone would have over-accepted).

Parity: `ColumnarCodegen_Parity_MustOperator` (5 functions incl. `(must s).Length` chaining and
Nullable unwraps) + the route-only THROW pin (exact exception type + message) + the NL907 decline pin.
296/296; gate (see commit). REMAINING null rungs: is/as (kernel parse), lifted arithmetic (probe-first).

---

## 2026-06-11 — NULL & NULLABLE N2: Nullable&lt;T&gt; value types

`int?` (and every baked value scalar's `?`) resolves to the REAL `System.Nullable<T>`. **Lifting** at all
five expected-type sites: bare null → `initobj` default(T?); an int literal adopting T or a T-typed value
→ `newobj Nullable<T>(T)`; an already-T? value passes through — the exact C# implicit conversions.
**`n ?? d`** lowers `tmp.HasValue ? tmp.GetValueOrDefault() : d` with the ELEMENT result type;
**`n == null` / `n != null`** lower to `!HasValue` / `HasValue`. Nullable over BUILDER value types (user
structs/enums) declines — emit-time reflection cannot reach their members; lifted ARITHMETIC (`n + 1`)
declines pending oracle probes (pinned).

**Emit-ownership lesson (caught by the parity harness as InvalidProgramException):** the first lifting
draft emitted the value before knowing its type and let call sites FALL THROUGH and re-emit on mismatch —
a double load. The rule now: when the target IS a supported Nullable, the lifted path OWNS the emission
and a false return is a whole-program decline (the emit-then-check pattern is only safe when false
abandons the assembly — never when a caller continues emitting).

Parity: `ColumnarCodegen_Parity_NullableValueTypes` (13 functions, 11 invocations incl. lifted args,
nullable returns, double?) + 2 decline pins; the two N1 Nullable pins flipped. 295/295; gate (see commit).
REMAINING null rungs: `must`, is/as (kernel parse work), lifted arithmetic (probe-first).

---

## 2026-06-11 — NULL & NULLABLE N1: null literals, reference nullability, `??` coalescing

The null arc opens. The kernel ALWAYS parsed the surface (null literal = kind 5; `??` = the precedence-1
binary op) — N1 is emitter + type-resolution work. **`T?` on a REFERENCE type resolves to its element**
(`string?` → string — annotation-only at runtime; the nullable TRACKING is the analyzer's side); a
VALUE-type `?` (int? = Nullable<T>, a real different runtime type) declines — the N2 rung, pinned.
**A bare NULL literal adopts any reference-typed target** (returns — incl. arrays, a flipped spike pin —
typed-locals, reassignment, param stores, sibling-call args). **Null comparisons** (`s == null`,
`null != s` — both operand orders) emit ldnull+ceq; `null == null` folds constant. **`??`** lowers
`dup; brtrue; pop` — the exact C# shape — with TypesEquivalent-unified reference arms and chained
right-associativity (`a ?? b ?? "last"`).

Parity: `ColumnarCodegen_Parity_NullAndCoalesce` (9 functions, 11 invocations) + 5 decline pins
(Nullable<T> shapes ×2, value-typed `??`, `must`, value-type null compares); one stale spike pin
flipped. 294/294; gate green (see commit). REMAINING null rungs: N2 Nullable<T> value types
(HasValue/GetValueOrDefault machinery, `int? = 5` lifting, `n ?? 0` lowering), `must`, is/as (kernel
parse work).

---

## 2026-06-11 — STRINGS slice 3: the interpolation DECLINE GUARD + interpolated-text escapes

The interpolation machinery map (2-agent workflow) found **live soundness bugs, probe-verified**: an
interpolated literal lexes as the SAME token kind as a plain string with the `$` in the span (production
parity — there is no separate TokenType), the expression kernel parses it as a plain kind-3 literal, and
the columnar emitter **silently emitted the mangled raw text** (`$"hello {name}` — wrong codegen, not a
decline); the unused-locals analysis produced a **FALSE NL001** for locals used only in holes. The two
"the kernel refuses them" comments were factually wrong — protection was only the corpus containing zero
$-strings. FIXED: $-prefixed literals now DECLINE at both consumption sites (the kind-3 emit and
static-field initializers) and the diagnostics walk throws-to-decline — until the full interpolation
slice (node kind 45) lands.

**Oracle escape divergence FIXED (the #16 family, found by the same map):** interpolated TEXT segments
bypassed the strings-slice decoder (emitted RAW at the constant-fold and AppendLiteral sites, with the
UNDECODED literalLength — the IL path diverged from the transpile path on `$"a\nb"`). The decoder gained
a body-level entry (`StringLiteralDecoder.DecodeBody`) and all three sites decode. ALSO fixed a latent
slice-1 gap: columnar **static-field string initializers** kept `Trim` while the oracle's rewired path
decoded — escaped static initializers would have diverged; both now decode + parity-pinned.

Tests: `ILCompiler_InterpolatedStringTextSegmentsDecodeEscapes` (oracle),
`ColumnarCodegen_InterpolationDeclinesAndStaticInitEscapes` (decline pins + static-init escape parity).
**The full 4001-test suite green.** Remaining strings rung: the real columnar interpolation surface
(expression node kind 45, handler-mirror lowering — the corpus has ZERO $-strings so this is
examples/route-all coverage, not self-host-blocking).

---

## 2026-06-11 — STRINGS slice 2: the BCL string-method whitelist widened

Parameterless **ToString() on every value scalar** (int/long/ulong/uint/short/ushort/byte/sbyte/double/
float/bool/char/decimal — spill + ldloca + `call` the type's OWN overload, the exact C# binding, culture
and all), **string.Substring(int)** (the match-positions ROUTE-ONLY gap — its pin FLIPS to a parity
case), **ToUpper/ToLower/ToString** on string, **Contains/StartsWith/EndsWith(string)** → bool, and
**Replace(string,string)**. Every entry binds the identical overload the pipeline binds. Parity:
`ColumnarCodegen_Parity_StringBclWhitelist` (10 functions, 14 invocations incl. the chained
`n.ToString().Substring(1).ToUpper()`); two stale pins flipped (the match-receiver ToString route-only
pin became a parity case; the old `s.ToUpper()` unsupported-method pin). 291/291; gate green.

Remaining strings rung (queued): interpolation columnar-side ($-strings — the kernel refuses them).

---

## 2026-06-11 — STRINGS slice 1: FULL ESCAPES — a language-semantics fix, all three paths converge

N# string literals historically materialized RAW on the IL path (`Trim('"')` only —
`GetStringLiteralRuntimeValue`): `"a\nb"` was FOUR characters, a lone `"` was UNWRITABLE (the lexer
consumed `\"` for delimiting while the value kept the backslash), and the IL path silently DIVERGED
from the TRANSPILE path (Roslyn always decoded the same token text) — while CHAR literals always
decoded. Probes + the corpus audit settled the design: the corpus uses backslashes almost exclusively
in char literals (unaffected), the only string hits are example ASCII art where raw rendering was
visibly wrong, and N# has a SEPARATE raw-string feature (`"""`, DESIGN.md) for no-escape semantics —
so C#-style escapes in regular strings are the intended design and raw was the defect.

Fix: the single shared **`StringLiteralDecoder`** (new file) decodes the char-literal escape set
(`\' \" \\ \0 \a \b \f \n \r \t \v`; an UNKNOWN pair passes through raw — no new diagnostic, the
parser never rejected one); ALL SIX of the oracle's Trim sites route through it, and the columnar
kind-3 emit calls the same decoder — both pipelines materialize byte-identically and now agree with
the transpile path. The lexer needed NO change (it always kept escape pairs verbatim, quote-aware).

**The ENTIRE 3997-test unit suite passed unchanged** — nothing relied on raw semantics. Parity:
`ColumnarCodegen_Parity_StringEscapes` (7 functions incl. char-escape match patterns and the
unknown-escape pass-through, + exact-value pins: `say \"hi\"` decodes to `say "hi"`, `"a\nb"`.Length
is 3). Remaining strings rungs (queued): the BCL string-method whitelist gaps (parameterless
int.ToString(), .Substring(1) — the match-positions ROUTE-ONLY pins), interpolation columnar-side.

---

## 2026-06-11 — SCALAR COMPLETENESS SC-6: decimal — THE SCALAR ARC CLOSES

decimal joins the modelled set (builtin + IsSupportedType — a baked VALUE struct, not an IL primitive).
**Literals** (`2.5m` kind-1, `5m` kind-0 — the kernel always lexed the suffix through) emit the
bits-decomposed 5-arg Decimal ctor (lo/mid/hi/isNegative/scale — exact, never via double; 2.5m + 0.1m
is 2.6 exactly). **Arithmetic/comparisons/negate** call System.Decimal's op_* statics (op_Addition …
op_Inequality, op_UnaryNegation); **compound assignment** lowers through the same operators; **casts**
route through op_Implicit (from int-family) / op_Explicit (from double/float, and decimal→anything) —
the exact C# emit throughout.

**ORACLE DEFECT #15 (probe-confirmed standalone):** the pipeline emits INVALID IL for compound decimal
assignment — `d := 10m; d += 2.5m` is InvalidProgramException at JIT. Columnar's op_*-lowered emit is
CORRECT (probed 5.0 through the four-op sequence) — per the don't-degrade-correct-columnar doctrine the
compound case is pinned ROUTE-ONLY (columnar emit + direct invocation = 5.0m) until the oracle is fixed.

Parity: `ColumnarCodegen_Parity_Decimal` (10 parity functions, 12 invocations + the route-only compound
pin) + 3 decline pins (`d: decimal = 1.5` NL202, decimal `++`, mixed decimal/int-literal arithmetic);
one stale pin updated (the multi-function ineligibility example now uses a 2-D array — decimal is no
longer ineligible). 289/289; gate green (see commit).

**THE SCALAR ARC IS COMPLETE** (SC-1+3 compound/ternary `bfd517c9`, SC-2 postfix `210dd072`, SC-4 small
ints `b2145312`, SC-5 widening/casts `3cdf0504`, SC-6 decimal — five gated commits; FIVE oracle defects
found by probes/parity along the way, the bundle now at 15). NEXT (retirement-map queue): STRINGS (full
escapes, typed host boundary design slice), then null & nullable — toward route-all (Arc 2).

---

## 2026-06-11 — SCALAR COMPLETENESS SC-5: implicit widening + negative literals + the full cast grid

**Implicit widening** (`TryEmitImplicitWidening` — C#'s implicit numeric conversions emitted on the
already-on-stack value): the int-promotable set → long/double/float (conv.i8/r8/r4) or int (identity —
loads already extend), long/float → double, long → float; applied at EVERY flow site — typed-locals
(`d: double = n`), returns (`return n` on long, `return f` on double), local/param reassignment, and
ALL call-argument tiers (sibling/static/implicit-this/struct-method — `takesLong(n)` works). uint/ulong
SOURCES stay excluded (extension/precision subtleties — pinned). **Negative literals** join the constant
conversion through the unary-minus wrap (`s: short = -300`, `v: sbyte = -127`) for signed targets.
**The full explicit-cast grid**: conv.u1/i1/i2/u2 truncations, `(uint)n`/`(int)u` slot-mate identity,
`(ulong)` sign- vs zero-extends by source (C# unchecked semantics), every numeric → double/float/long.

**TWO new oracle defects (parity-harness/probe-found):** (#13) the pipeline OVERFLOWS on any unsuffixed
literal beyond int range regardless of target (`l: long = 5000000000` → NL103 "Arithmetic operation
resulted in an overflow"; suffixed `5000000000L` is fine) — columnar caps constant conversion at int
range to match; (#14) the pipeline rejects exact-MINVALUE negative literals (`v: sbyte = -128` → NL202 —
its negation range check is off by one) — columnar caps negative magnitudes at MaxValue to match.

Parity: `ColumnarCodegen_Parity_WideningAndCasts` (15 functions, 16 invocations) + 5 decline pins
(beyond-int literals, MinValue literals, negative-on-unsigned, long→int narrowing, uint-source widening);
three stale pins flipped (`(long)a` ulong cast, float-literal double return — the old pin's "pipeline
rejects" claim was WRONG, probed: the oracle always accepted; ULong cast pin). 288/288; gate green.

SCALAR ARC remaining: SC-6 decimal (op_* host boundary — the last scalar rung).

---

## 2026-06-11 — SCALAR COMPLETENESS SC-4: small-int scalars + uint + constant conversion

byte/sbyte/short/ushort/uint join the modelled scalar set. All are i4-slot types — loads sign/zero-extend
by the storage type — so the SMALL INTS join char in the ECMA §12.4.7 **int-promotion set** (`IsIntPromotable`):
ANY mix (`b + s`) promotes to int with NO conversion IL, and arithmetic/bitwise RESULTS are int (the
existing char precedent, now generalized); comparisons run signed on the extended i4 values. **uint runs
NATIVE u4 against itself**: unsigned div/rem (`Div_Un`) and unsigned ordering (`Clt_Un` — 4000000000 must
order as large-positive), result uint.

**Constant conversion** (`TryEmitIntLiteralAsType`): an UNSUFFIXED in-range int literal ADOPTS a
small-int/uint/long/ulong target — C#'s implicit constant conversion — at typed-locals (`b: byte = 200`,
`u: ulong = 10`), returns (`return 50` on byte), local/param reassignment, compound values (`u /= 3` —
the SC-1 pin FLIPS), and binary RIGHT operands against a uint/long/ulong left (`l + 1`, `u / 2` — two
old LongType pins flip; a literal LEFT operand still declines, pinned). Out-of-range = failed adoption →
exact-type decline (the pipeline's NL202).

**ORACLE DEFECT #12 (parity-harness-found, probe-confirmed):** uint locals initialized with literals
ABOVE int.MaxValue mis-evaluate in the pipeline — `u: uint = 4000000000; u / 2` returned 4147483648 (the
SIGNED-division bit pattern; columnar's unsigned 2000000000 is the correct value) and `print u / 2`
dropped the line entirely. uint PARAMS carry large values correctly on both sides. Columnar caps uint
literal adoption at int.MaxValue so it never diverges; queued for the oracle bundle.

Parity: `ColumnarCodegen_Parity_SmallIntScalars` (13 functions, 15 invocations: promotion incl. mixed
small-int pairs, byte locals/returns/reassignment, ushort unsigned-range compares, sbyte flows, uint
native div/ordering with large params, ulong/long adoption) + 6 decline pins (out-of-range, negative
literals — unary-minus shapes are the widening rung, non-literal narrowing, casts, int/uint mixing,
the defect-#12 shape); three stale pins flipped. 287/287; gate green (see commit).

REMAINING scalar rungs: SC-5 widening/implicit conversions (negative-literal adoption, int→long at flow
sites, mixed ternary arms, literal LEFT operands, casts incl. small-int conv.u1/i2), SC-6 decimal.

---

## 2026-06-11 — SCALAR COMPLETENESS SC-2: postfix `++`/`--`

Kernel kind **44 PostfixUnary** (Increment 113 / Decrement 114 — verified by reflection; operator token
in the value span, ONE child [target], a single wrap after the postfix suffix chain — `n++++` does not
re-enter; 45 is next free). Statement position steps in place (a kind-44 expression-statement branch in
case 23 — which also makes the classic `for i := 0; i < n; i++` increment work with NO for-loop change,
the kernel already wraps increments as expression statements); expression position keeps the PRE-step
value (`ldloc; dup; ldc.i4.1; [conv.i8]; add/sub; stloc` — C# post-semantics, probe-pinned: `m := n++`
reads the old n). int/long/ulong on bare locals/params; **double/float DECLINE — ORACLE DEFECT #11: the
pipeline's `++`/`--` on them silently NO-OPS** (probed: `d := 1.5; d++` leaves 1.5); prefix `++n` is
pipeline-rejected NL313 (unparsed). **Write-scan soundness:** all three write scans
(IsNameBareAssigned / IsNameStructurallyWritten / IsAnyNameWritten) treat kind 44 exactly like a kind-14
assignment to its target — a captured `n` mutated via `n++` lifts/declines correctly (the L3a lesson).

Parity: `ColumnarCodegen_Parity_PostfixIncrementDecrement` (6 functions incl. the counting for loop and
pre-step expression value) + 3 decline pins. 286/286; gate green (see commit).

---

## 2026-06-11 — SCALAR COMPLETENESS SC-1+3: compound assignment + ternary (emit-only)

The scalar arc opens with its two EMIT-ONLY rungs — both shapes were ALREADY PARSED (the assignment
kernel has always carried `+=` `-=` `*=` `/=` `??=` op text on kind 14; ternary is kind 13 with a full
precedence level) and only the emitter declined them.

**Compound assignment** (`+=` `-=` `*=` `/=`) lowers to load/op/store on a bare LOCAL or PARAM target
with the binary operator's exact opcode selection (ulong divides Div_Un; string `+=` is Concat; both
sides must share one type — `int += double` is the pipeline's NL202). Lifted/boxed captures, member and
array-element targets, `%=` (unparsed) and `??=` (nullability slice) decline, pinned. **Ternary** is a
branch/merge whose arms must agree by TypesEquivalent — MIXED-type arms (the pipeline unifies via
implicit conversion) decline to C#, a widening-slice concern, pinned. Probed: `u /= 3` (int literal
against a ulong target) is pipeline-accepted via implicit literal typing — columnar declines (pinned,
the widening/literal-typing rung).

Parity: `ColumnarCodegen_Parity_CompoundAssignmentAndTernary` (9 functions, 16 invocations: all four
ops, params, ulong/double/string, nested right-associative ternary, ternary in `:=`/arg positions) + 5
decline pins; one stale spike pin flipped. 285/285; gate green (see commit).

REMAINING scalar rungs (queued): SC-2 postfix `++`/`--` (kernel work), SC-4 small-int scalars
(byte/sbyte/short/ushort/uint with int-promoted arithmetic), SC-5 widening/implicit conversions +
literal typing, SC-6 decimal (op_* host boundary).

---

## 2026-06-11 — NAMED TUPLES: oracle member-access fix (`7e151c7c`) + columnar end-to-end

The retirement-map queue's named-tuples slice, in two halves.

**ORACLE HALF (fix-oracle-first, `7e151c7c`):** `t.x` on a value typed `(x: int, y: int)` was accepted by
the ANALYZER (TupleTypeInfo has always mapped both ItemN and element names) but THREW at emit — the
ILCompiler resolved members by literal-name reflection over the erased CLR ValueTuple<> (ItemN fields
only): "Member x not found on type ValueTuple`2" (NL103). Names parsed and silently dropped everywhere.
Fix: a per-variable element-name retention map (`_tupleElementNamesByVariable`, fresh per body in
InitializeBodyContext, saved/restored with `_parameterTypes` across lambda/local-function/embedded-call
boundaries) + name→ItemN rewriting at the three member-resolution tails. Name sources: annotated
locals/params, NAMED literal initializers, identifier copies, direct call receivers via the callee's
declared return (single-overload). Probe-pinned semantics: tuple identity is POSITIONAL (cross-named
assignment legal — C# rule; the receiving annotation's names govern), partial naming is a parse error,
the BARE tuple-typed local (`t: (int, int) = ...`) is a production parse error (only `let` parses).

**COLUMNAR HALF:** the kernels gained name channels — type-kernel kind 7 NamedTupleElement (name span +
one child, only ever a kind-6 tuple child) and expression-kernel kind 43 (the literal twin, only ever a
kind-17 child); naming is all-or-nothing in both. **Canonicals stay name-ERASED** (`(int,int)` — .NET
positional identity; ColumnarTypeCanon unwraps kind-7, matching ColumnarFunctionSymbol which always
dropped names) and the names travel separately: `ColumnarFunctionInput.Return/ParamTupleElementNames`
(adapter-extracted) → the emitter's `_tupleNamesByVariable` + a sibling return-names map (threaded as
optional emitter-ctor params — sub-emitters without them just decline named access, safely). The
member-access path rewrites name→ItemN by peeking the receiver node (identifier/paren/named-literal/
sibling-call); `let t: (x: int, y: int) = ...` strips names from the span canonical and records them.
**Pre-existing OVER-ACCEPT fixed:** columnar routed the BARE tuple-typed local the production grammar
rejects — the kind-40 kernel now refuses a `(`-starting type span in the bare form (pinned).

Parity: `ColumnarCodegen_Parity_NamedTuples` (7 both-pipeline shapes: call-derived names, cross-named
assignment, named literals + copies + mixed ItemN, direct-call receivers, `let` annotations, positional
tuples unchanged, deconstruction) + 5 decline pins (bare forms, partial naming ×2, wrong member name);
2 oracle regression tests (all receiver shapes incl. lambda-boundary; cross-named). Two stale pins
flipped (the kernel type-tree refusal test now pins PARTIAL naming instead; the named-param route pin
became a parity case). Residual (recorded): TupleElementNamesAttribute is not emitted on signatures —
C# interop sees positional tuples from the IL backend (the Transpiler path preserves names); a future
interop slice. 284/284; both gates green (see commits).

NEXT (retirement-map queue): SCALAR COMPLETENESS (byte/sbyte/short/ushort/uint, decimal, widening,
`+=`/`++`/`--`, ternary, casts) — toward route-all (Arc 2).

---

## 2026-06-11 — Columnar GENERIC RECORDS: the D-16 adapter decline flips

The retirement-map queue's generic-records slice — small by design: columnar's record model emits plain
public FIELDS (no init-only properties), so the oracle's backing-field lowering for closed-generic init
members (`14faa92c`, the .NET 10 PersistedAssemblyBuilder modreq workaround) is oracle-internal with no
columnar analog needed. The slice: (1) the adapter's generic-RECORD decline removed (generic-with-BASE
stays declined); (2) a CLOSED GENERIC REFERENCE object-init branch in kind 36 (`new Pair<int> { first: 1 }`
— rebound default ctor + rebound `GetField` stores + positional field-type substitution, the
generic-union construction machinery's analog; generic ctor-less CLASS object-init lands free); (3) a
kind-0 guard declining object-init on a BARE generic head (`new Pair { ... }` = NL207 — this also closed a
latent open-generic-newobj hazard). Member reads/methods on closed records ride the existing D-16
closed-receiver machinery unchanged. Probe-pinned: records do NOT adopt the expected type (NL207 —
explicit args required everywhere, unlike union cases).

**ADVERSARIAL REVIEW (focused single-lens, probe-confirmed pre/post-diff) found two HIGHs, both from the
adapter flip routing unmodeled shapes — fixed by adapter declines + pins:** (1) a MEMBER name colliding
with a TYPE-PARAMETER name (`record W<T> { T: int }`, methods/properties too) — pipeline NL306, columnar
accepted; now declined (union CASE fields are a DIFFERENT scope — `union U<T> { A { T: int } }` is
pipeline-ACCEPTED, probe-pinned with a parity case). (2) RECORDS with USER CONSTRUCTORS: **the pipeline
silently DROPS record ctor-body field assignments** (`new R(5)` → x==0; columnar's faithful emit → 5) — a
pre-existing, previously-unpinned behavior divergence LIVE for non-generic records too; records with user
ctors now decline (generic AND non-generic) until the oracle is fixed. Also declined: STATIC FIELD use on
generic types (BOTH pipelines emit an invalid open-generic static-field token → BadImageFormatException —
parity-by-accident on broken IL).

**ORACLE DEFECT BUNDLE grows to 10:** (7) generic VALUE-STRUCT object-init = NL103 emit crash ("Specified
method is not supported"; analyzer accepts); (8) record user-ctor body assignments DROPPED (the HIGH above
— harms real users silently); (9) static-field tokens on open generics = BadImageFormatException (both
emitters); (10) duplicate type-parameter names (`record W<T, T>`) accepted undiagnosed (columnar declines).
Bundle items 4 (unchecked object-init field initializers) is confirmed FULLY GENERAL — records, unions,
generic and non-generic alike.

Parity: `ColumnarCodegen_Parity_GenericRecords` (7 functions: explicit-args init, two instantiations,
methods returning T, nested Pair<Pair<int>>, generic ctor-less class init; 10 decline pins incl. the
review findings); the D-16 generic-record pin in `ColumnarCodegen_GenericTypeDeclines` replaced with a
pointer; `caseFieldNamedT` parity case added to the generic-unions test. 147/147 dogfood; full gate green
(see commit).

NEXT (retirement-map queue): NAMED TUPLES (per-element name metadata in the columnar table), then scalar
completeness — toward route-all (Arc 2).

---

## 2026-06-11 — Columnar GENERIC UNIONS: the D-10 pin flips (`union Result<T>` emits columnar)

The retirement-map queue's generic-unions slice lands; the columnar pipeline now emits the README's
flagship shape end-to-end, mirroring the oracle's `d1c41b6e` machinery exactly (spike-proven first):
the abstract base declares the type parameters, every sealed nested case REDECLARES them (CLR metadata
does not inherit generic parameters into nested types), `DefineNestedType` with NO parent then
`SetParent(base.MakeGenericType(caseOwnParams))` (Some<T> : Opt<T>), and the case ctor rebinds the base
ctor via `TypeBuilder.GetConstructor`. Closed work rebinds member handles via
`TypeBuilder.GetField/GetConstructor` with positional substitution (`value: T` on `Opt<int>` is an int).

**Kernel:** `ParseUnionDeclarationInto` gained the optional `<T, U>` list (same bare-identifier shape as
the struct/class kernel; spans out via two new arrays, count in outResult[2]); a new expression node kind
**42 BareNew** (`new <type>` with neither `(args)` nor `{inits}` — children [typeRoot], a TYPE subtree all
name scans skip like kind 38) carries the brace-less construction form (`new Color.Red`,
`new Opt.None<int>`, adoption shapes) — the emitter declines every non-union-case BareNew root, so
previously-unparseable programs stay declined. 43 is the next free kind.

**Surface (VERIFY-FIRST probed, ~25 probes):** explicit type args go AFTER the case name
(`new Opt.Some<int> { value: v }` — `new Opt<int>.Some` is pipeline-rejected); adoption of the expected
type's arguments happens at FIVE exact-expected-type positions — return statements, typed-local inits,
union-case object-init FIELD VALUES (`new Opt.Some<Opt<int>> { value: new Opt.None }`), and local/param
REASSIGNMENT — and is REJECTED at call arguments (NL103, an oracle accept/emit divergence) and `:=`
(NL207, no inference from field initializers); patterns never repeat args (the scrutinee's closed type
drives per-case isinst + binding substitution); brace-less construction of PAYLOAD cases is legal with
CLR-default fields. Adoption is implemented by PEEKING at the construction node at those statement sites —
NOT via an expected-type field (the oracle's expected-type leak bug this week is the cautionary tale).

**Emitter:** PASS 0 generic branch; `TryResolveClosedUserGeneric` accepts union-base heads (`Opt<int>`
annotations, incl. nested `Opt<Opt<int>>`); a BARE generic-union name FAILS resolution (NL207 parity —
this also fixed a working-tree over-accept where the in-progress kernel parse + ignoring TypeParamNames
emitted a NON-generic hierarchy for the D-10 pin program); match discovery/`IsSupportedMatchValueType`
admit closed instantiations via `TryGetUnionDefForMatchValue`/`TryGetCaseTestType`; **TypesEquivalent
replaces raw `!=` at the value-flow sites** (return, match-arm unification, typed-local init, local/param
reassignment, sibling/local-function/implicit-this/static/struct-method call args, duplicate-ctor
signature guard) — two closed instantiations of one user generic are referentially distinct.

**ADVERSARIAL REVIEW found two probe-confirmed REAL breaks (fixed + pinned):** (1) trailing-comma
type-parameter lists (`union Opt<T,>`, `struct Box<T,>`, `func id<T,>`) parsed cleanly in all THREE
declaration kernels while the production parser errors NL102 — cardinal-rule over-accept, the struct one
shipped pre-slice; the comma branch now requires a following parameter name. (2) A generic sibling's
`Opt<T>` RETURN escaped unsubstituted into callers — `o := makeNone(5)` baked `Opt<!!T>` MVAR references
into a non-generic method's locals/isinst → **BadImageFormatException** on a program the oracle runs;
`TrySubstituteReturnType` now recursively substitutes closed-user-generic instantiation arguments and
re-closes (plus a defensive refuse-any-open-shape fallthrough). Hardening: `IsSupportedValueTuple`
excludes closed instantiations (same reflection-throw as builders — future-tuple-slice crash prevented);
`ColumnarDiagnosticsPass.WalkUnused` gained the kind-38/42 skip + value-less kind-6 guard (a type-tuple
node crashed Text()). Review-noted deferrals: columnar's union metadata surface (public fields, no payload
ctor) diverges from the oracle's (nonpublic + payload ctor) — pre-existing from D-10, acceptable for
single-assembly dogfood scope, backlogged for the interop story; the pre-existing
type-param-vs-registered-type SCOPING divergence (columnar: param shadows type, mirroring C#; oracle:
registered type wins, rejecting `func f<T>(a: T)` + `struct T` programs columnar accepts) joins the
ORACLE DEFECT BUNDLE as item 6 — direction likely fix-the-oracle (C# precedent: method type params shadow).

**ORACLE DEFECT BUNDLE grows to 6:** (4) union case construction field initializers are NEVER type-checked
(generic AND non-generic — `new U.A { x: "str" }` emits and throws InvalidCastException at runtime; NL202
missing); (5) generic-union expected-type adoption in CALL-ARGUMENT position passes the analyzer but fails
ILCompiler overload binding (NL103); (6) the scoping divergence above. Known composition gap (safe
declines, queued): generic functions with `Opt<T>`/`Opt<int>` params decline at the generic-call unify
loop (the MVAR-closed BODIES emit soundly — probe-proven via MakeGenericMethod invocation); recursive
unions (`tail: L<T>`) decline at the kernel's single-token field-type gate; struct fields of closed-union
type decline likewise.

Parity: `ColumnarCodegen_Parity_GenericUnions` — 24 functions, 26 both-pipeline invocations (explicit
args, all five adoption positions, two instantiations in one program, two type params, nested generic
args, user-struct args, guards, catch-all, bare patterns, local functions, the generic-sibling-return
shape, the former pin program), metadata pins (generic abstract base, sealed generic case parented to the
closed base, generic-param field), 14 decline pins. The old D-10 pin line is REPLACED with a pointer.
`examples/05-unions/README.md`'s stale call-style construction blocks normalized to the implemented
surface. 146/146 dogfood; full gate green (see commit).

NEXT (retirement-map queue): columnar GENERIC RECORDS via backing-field lowering (mirror `14faa92c`),
then named tuples, scalar completeness — toward route-all (Arc 2).

---

## 2026-06-10 — Match POSITIONS complete + oracle expected-type-leak fix (`acc338b5`, `8c16c46d`)

Phase D resumes with the retirement-map queue's match slice, resolved in two commits.

**ORACLE FIX (`acc338b5`):** `GetMatchExpressionType` returned `_expectedExpressionType` unconditionally —
but a match used as a postfix RECEIVER inherits the OUTER expression's expected type, and a match used as
another match's SCRUTINEE inherits the outer match's result type. Probe-proven consequences: `match {…}.Length`
under an int target → NL103 "Member Length not found on type Int32"; `[0]` → "does not support index access";
`.ToString()` under a string target → broken IL accepted, runtime InvalidCastException; match-as-scrutinee →
InvalidProgramException (parenthesized or not). Fix: the expected type wins only when EVERY arm can produce it
(null arms fit any null-assignable target via CanAssignNullToType); scrutinee typing+emission run with the
expected-type context CLEARED. Target-typed arms preserved (null under string, int under long/double —
probe-confirmed). 5 ILCompiler regression tests.

**COLUMNAR POSITIONS (`8c16c46d`):** probes showed the emitter's kind-18 case is ALREADY position-general
(it lives in the main EmitExpression switch; the kernel parses `match` as a PRIMARY) — every position emits
oracle-exact results with NO emitter change. The slice is parity COVERAGE:
`ColumnarCodegen_Parity_MatchExpressionPositions` (22 functions, 38 both-pipeline invocations): `:=`/typed-local
inits, call args, binary operands both sides (incl. precedence and comparisons), parenthesized arithmetic,
if/while conditions, reassignment, nested arms, complex scrutinees, index positions, postfix receivers
(member + whitelisted call — both pin the oracle fix), match-as-scrutinee (paren + unparen), non-capturing
lambda bodies, foreach iterables, unary `!`. Pins: bare match STATEMENT = NL313 (N# has NO match statement —
match is expression-only), wrong-typed local = NL202, mixed arm types, and ROUTE-ONLY parameterless
int.ToString() on a match (a BCL instance-call whitelist gap, NOT a position failure — the scalar/strings
slice flips it). Bisection lesson: a combined-program decline that individual probes miss can be a
BCL-whitelist boundary; bisect cumulative programs before suspecting new code. 3987/3987; gate 1m35s.

NEXT: columnar GENERIC UNIONS (model the oracle's `d1c41b6e` machinery: case redeclares the union's params,
closes over scrutinee args, IsClosedGeneratedTypeAssignableToBase), then generic records via backing-field
lowering (`14faa92c`), named tuples, scalar completeness — toward route-all (Arc 2).

---

## 2026-06-10 — Lambdas arc L4-i: LOCAL FUNCTIONS, non-capturing (`1118b3d4`)

`func name(...) { ... }` statements emit columnar: kernel kind 41 (byte-span anchor + balanced skip),
adapter re-parses the nested declaration recursively (root-block only — nested-block kind-41s decline),
emitter pre-declares `<parent>g__{n}` statics with the LOCAL-shadows-SIBLING call tier (probe-pinned, the
OPPOSITE of the value rule). **TWO pipeline truths the parity harness surfaced that columnar-only probes
missed:** (1) local-function visibility is STRICTLY TEXTUAL (NL412 on any forward reference, parent and
inter-local — true mutual recursion is IMPOSSIBLE in N#; the emitter's first draft over-accepted it, now a
visible-set grows as declarations are reached); (2) ORACLE DEFECT: a lambda argument to a LOCAL function
fails the oracle's emit (NL103 "No matching overload for local function use"; lambda-to-sibling works) —
columnar declines the shape, defect queued for an oracle bundle (with the interface-constraint dispatch
crash and the parameterless-struct-ctor bypass). Parity: 6 shapes + 6 pins. 3981/3981; gate 291s.

**The lambdas arc closes its main ladder at NINE landed rungs in one session** (oracle inference fix,
L1a/b/c, L2 typed locals, L3a/b captures, block bodies, this-captures, L4-i local functions) — columnar
lambdas went from nonexistent to covering the practical surface. Remaining minor rungs (captures in local
functions, locals-as-values, nested-block scoping, capture-opaque widening, `this` primary parse) are
pinned and documented. NEXT: Phase D resumes the retirement-map queue — match STATEMENTS, columnar generic
unions/records — toward route-all (Arc 2).

---

## 2026-06-10 — Lambdas arc: THIS captures (`8463d7c4`)

Instance-method lambdas referencing bare fields/members bind the delegate DIRECTLY to `this` (the oracle's
this-only path): BodyReferencesEnclosingChain detects chain-resolving bare names (siblings excluded — they
beat members in the pinned order), and the lambda becomes an instance method ON THE ENCLOSING TypeBuilder
(`ldarg.0; ldftn; newobj`, no display class). True reference capture: field WRITES inside lambdas hit the
live object (probe: BumpTwice across two closures = 2; reads 105; instance-helper calls 40). Value-type
`this` + ctor bodies decline. The probe detour re-confirmed a pre-existing decline (this-qualified ctor
writes; bare writes are the modeled form). 3980/3980; gate 287s. The LAMBDAS ARC now stands at EIGHT landed
rungs (oracle fix, L1a/b/c, L2, L3a/b, blocks, this) — remaining: capture-opaque widening (minor), L4 local
functions; then Phase D resumes the retirement-map queue (match statements, columnar generic unions/records)
toward route-all.

---

## 2026-06-10 — Lambdas arc L3b: MUTATED captures via StrongBox lifting (`5aa789e5`)

Shared closure mutation lands — the oracle's box-lift model: captured + bare-assigned names lift into a
shared StrongBox<T> (declaration allocates; lifted params box-init at body start; every read/write routes
through `.Value`; display classes snapshot the BOX reference). Six shared-mutation directions probe-exact
(closure-writes 207, body-writes-after 51, bidirectional 114, lifted params 15, two-closures-one-box 42,
mixed lift+snapshot 109, lifted strings); structural writes (foreach/decon/member-rooted) stay declined.
One probe-bisected mid-slice bug (capture scan missed lifted LOCALS). **Adversarial review (2 lenses): one
HIGH break confirmed-then-fixed** — a lifted DELEGATE param invoked the dead arg slot (columnar 8 vs oracle
700); now box-routed Invoke and a positive parity case — plus the scope-discipline cluster (lifted maps
block-scoped; binding/redeclaration/type-vs-value gates lifted-aware; bare-assign scan respects lambda-param
shadowing). 3979/3979; gate 289s clean. REMAINING lambda surface: capture-opaque body widening (match/
object-init in capturing lambdas), `this` captures, L4 local functions.

---

## 2026-06-10 — Lambdas arc: BLOCK-BODIED lambdas (`2d0199e6`)

`x => { ... }` emits columnar — the slice that makes lambdas practically useful. Kernel: the lambda's `{`
body parses as a statement BLOCK (kind 25) via the FIRST expressions→statements cross-kernel call (same
mutual recursion as statements-call-expressions, other direction). Emitter: kind-25 bodies route through
the sub-emitter's EmitBody — always-returns checking (non-returning value blocks decline, NL305 family)
and trailing-ret for void come free, exactly like a function body; shared by the static and capturing
branches. EMERGENT + induction-sound: nested lambdas inside block-bodied lambdas capture the block's
locals (the outer EmitBody sets the sub-emitter's body root, so the L3a never-written scan applies one
level down — probe-verified). `:=` inferred lambdas stay expression-only (block returns need the type up
front — pinned). Parity: 7 invocations + 3 pins; the L1b block pin replaced. 3978/3978. Gate took four
attempts for THREE distinct non-code causes (stale pin → fixed; HotResultCombinations thermal flake 1.46
post-sleep; post-sleep OOM; then green at 318s with healthy ratios 0.71/0.86 after build-server shutdown).
REMAINING lambda surface: L3b mutated captures (box-lifting), capture-opaque body widening (match/object-
init in capturing lambdas), `this` captures, L4 local functions.

---

## 2026-06-10 — Lambdas arc L3a: CAPTURING lambdas, never-mutated captures (`4aefe87c`)

The columnar pipeline emits its first CLOSURES. Scope contract: a by-value snapshot into a display class
equals the oracle's lowering exactly when nothing in the enclosing body WRITES the captured name (the
oracle only box-lifts mutated captures) — so the never-written surface accepts and everything else
declines. Machinery: capture collection with nested-lambda shadowing + precise type-subtree skipping;
whole-body write scan (assignments incl. compound, foreach vars, deconstructions); module-level
`<>c__DisplayClass{n}` with snapshot fields, the lambda as an instance method whose captured names resolve
through a synthetic ColumnarStructDef via the existing `_currentStruct` field chain; `newobj; dup; stfld`*
+ `ldftn; newobj (object, IntPtr)` at the use site; display classes bake before Program (threaded list).

**ADVERSARIAL REVIEW (the §1.6 mandatory slice) — both soundness findings CONFIRMED by probe, then fixed:**
(1) member writes through a captured VALUE-STRUCT local (`b.V = 99`) escaped the bare-ident write scan —
columnar 101 vs oracle 199 on an accepted program (the oracle box-lifts member-mutated value-type
captures); the scan now walks member/index targets to the root receiver. (2) generic-T captures embedded an
out-of-context MVAR in the display field signature (TypeLoadException at load); ContainsGenericParameters
declines. After four review arcs refuted by verify-first, this is the first review with confirmed real
findings — on exactly the slice family (closures) the doctrine flags for review. Parity: 6 shapes + 8
decline pins. 3976/3976; gate green — first gate on the concurrent collectible-ALC test infra (`2587fc2a`,
the OOM fix). REMAINING lambda surface: L3b mutated captures (box-lifting), block bodies, nested capture
chains, capture-opaque bodies (match), `this` captures, L4 local functions.

---

## 2026-06-10 — Lambdas arc L2: TYPED LOCALS — param-ful lambda locals unlocked (`abadc3aa`)

`let name: Type = init` + the bare form emit columnar (statement kind 40). Type trees can't share the
statement table's kind space, so the declared TYPE rides as a SOURCE SPAN in the value slot (structurally
delimited — balanced angles incl. `>>`-closes-two, ()/[] groups, to the depth-0 `=`); the emitter
whitespace-strips the span onto the canonical grammar and resolves it. A kind-39 lambda initializer types
contextually from the DECLARED delegate via the L1b machinery — **`let g: Func<int, int> = x => x + 3` is
the headline: param-ful lambda locals work end-to-end** (L1a Invoke path). `let` locals are MUTABLE
(probe-pinned), so plain locals; mismatches (NL202), no-initializer, lambda-arity, captures, shadowing all
decline. Parity: 7 shapes + 5 pins. 3973/3973; gate green (595s). Next: **L3 captures/display classes** —
the arc's hardest rung (adversarial review required): /tmp display-class spike, then L3a scoped to
NEVER-MUTATED captures (pure by-value snapshot — semantics-identical to the oracle without box-lifting),
then the mutation-sharing model.

---

## 2026-06-10 — Lambdas arc L1c: zero-param `:=` lambdas, body-inferred returns (`36f47ac3`)

`zero := () => 99` emits columnar: the `:=` initializer now parses at the lambda level, and a zero-param
kind-39 initializer synthesizes its `<Lambda>_{n}` method signature-LESS, emits the body FIRST, then
SetReturnType/SetParameters AFTER (spike-proven define-then-sign order) — void bodies yield Action, others
Func<bodyType>; the local flows through the L1a delegate surface (Invoke, passing to delegate params).
Param-ful `:=` lambdas stay declined (pipeline NL203) as do captures. Parity: int/void/string inferred
bodies + pass-to-param + capture pin. 3972/3972; gate green (502s, no OOM with build servers pre-shutdown).
Next: L2 typed locals (`let f: Func<int, int> = x => x + 1` — statement-kernel work, unlocks param-ful
lambda locals via the L1b contextual machinery), then L3 captures (adversarial review) → L4 local functions.

---

## 2026-06-10 — Lambdas arc L1b: columnar NON-CAPTURING lambda ARGUMENTS (`0b22ac3b`)

The columnar pipeline now emits its first lambda expressions. Kernel: Lambda node kind 39 at a NEW precedence
level above assignment (`ParseLambdaOrAssignmentExpressionNode`, mirroring Parser.cs:3660) — `x => e`,
`() => e`, `(x, y) => e` via the production's exact lookaheads (ident+Arrow; speculative paren-list scan);
children = [param idents..., body root]; the body parses at the lambda level (lambda-returning-lambda);
BLOCK bodies refuse. Wired into the expression entry + call ARGUMENTS only (match guards keep their path —
the `when <ident> =>` hazard stays avoided). Emitter: contextual typing from the declared delegate parameter
(TryEmitLambdaLiteral in the sibling-call arg loop): synthesize Private|Static `<Lambda>_{n}` on the Program
type (TypeBuilder + shared counter threaded through all 3 emitter construction sites), body emitted via a
SUB-emitter whose scope holds ONLY the lambda params — enclosing-local references fail to resolve, which IS
the no-captures rule (sibling calls in bodies work); use site emits `ldnull; ldftn; newobj` (the oracle's
EmitStaticDelegate minus its unobservable cache). Void delegates require void bodies. Parity: 7 shapes + 7
decline pins + synthesized-method metadata. 3971/3971; probe map perfect first-try.

**GATE INFRA FINDING (two flakes today explained):** the test host intermittently crashes "Out of memory" in
the gate's isolated run — the parity suite Assembly.Loads every emitted assembly into the default ALC
(pinned forever, grows every slice) on top of the MSBuild fleet + desktop apps. Mitigation: shut down build
servers before gates; the gate script also CONTINUES past a failed unit-test step into ~50 min of benchmarks
(monitor now fires early on unit-test failure). Structural fix queued as its own task: collectible
AssemblyLoadContexts for emitted test assemblies. Next: L1c zero-param `:=` lambdas (define-then-
SetReturnType ordering spike), then L2 typed locals → L3 captures → L4 local functions.

---

## 2026-06-10 — Lambdas arc L1a: columnar DELEGATE-TYPE plumbing (`bac8966e`)

`Func<p,...,ret>` resolves in the columnar emitter as the production parser's function-type sugar — checked
BEFORE the user-generic path (the parser special-cases the NAME, so the spelling is always a function type);
the LAST argument is the return, and `void` there lowers to the matching System.Action (`Func<int,void>` IS
Action<int>, the oracle's CreateDelegateType mapping). `Action<...>` falls back AFTER user-generic lookup
(no parser sugar — a user Action<T> wins); bare `Action` after the registries. Args cap at 4 and must be
BAKED runtime types (builder-arg delegates can't resolve ctor/Invoke — the tuple rule). IsSupportedType
gains IsSupportedDelegateType; tuple elements exclude delegates. Case-9 bare-ident callees now split: a name
carried by BOTH a value and any method tier still declines (pinned method-beats-local), a delegate-typed
local/param with no competing method emits `callvirt Invoke` with exactly-typed args. PARITY FIX:
ColumnarFunctionSymbol.CanonicalType renders FunctionTypeReference as `Func<p0,...,ret>` (previously "?" vs
the kernel's verbatim generic — a latent signature mismatch). Parity test passes REAL delegate instances as
invocation args (both pipelines resolve identical closed BCL delegates), incl. a stateful Action proving
invocation reaches the instance; six decline pins incl. the first explicit LAMBDA-expression pin (kernel
boundary until L1b). 3970/3970; gate green. **L1b spike GREEN in one shot:** forward-ldftn baking,
interleaved DefineMethod, `Func<int,int>` (object, IntPtr) ctor persistence, delegate-local Invoke — the
non-capturing lambda emit shape is fully de-risked. Next: L1b (kernel lambda node kind 39 + synthesized
`<Lambda>_{n}` static methods + argument-position lambdas).

---

## 2026-06-10 — LAMBDAS ARC opened: oracle lambda-inference fix (`b20476e8`) + full recon

VERIFY-FIRST probing of the oracle's lambda surface (the arc's §1.1 step) found a CRITICAL defect:
`f := (x) => x + 1` — a `:=` lambda with NO delegate-type home — flowed Unknown parameter types into emit
and produced a delegate whose invocation CRASHED with **AccessViolationException** at runtime. AnalyzeLambda
now reports NL203 ("I can't figure out the type of lambda parameter 'x'" + help) when a parameter has
neither an explicit type nor an expected-signature slot; zero-param `:=` lambdas stay legal. The fix exposed
a second latent defect: EXTENSION-method calls (`count.Times(i => ...)`) threaded expected argument types
positionally INCLUDING the `this` receiver, so a lambda argument paired with the receiver's type and lost
its inference source (silently Unknown before; the 07-interfaces example lint caught the false NL203 after).
The expected-type pairing now skips the `this` parameter, mirroring the validator's paramStartIndex shift.

**Recon (workflow wx4ol2vbt; full maps in its task output).** Grammar: lambda params are UNTYPED-only
(`(x: int) =>` does not parse — typing is 100% contextual via `Func<...>` annotations or argument position);
`Func<T1..TRet>` is the only function-type spelling (no arrow types — Arrow is a type TERMINATOR). Oracle
emit: 3-way split (non-capturing → static `<Lambda>_{n}` + ldnull/ldftn/newobj + per-callsite cache;
this-only → instance method bound to arg0; captures → heap `<>c__DisplayClass{n}` with by-value snapshot +
box-lifting for mutated captures; `<>LiftedStruct{n}` stack box for non-escaping local-function captures).
Columnar TODAY: lambdas decline at KERNEL PARSE (-1, no Arrow branch — no explicit decline pin exists);
`Func<int,int>` canonicals decline at TryResolveType (BCL generic heads); IsSupportedType rejects delegates;
the C#-AST canonicalizer renders FunctionTypeReference as "?" (latent parity mismatch). Node kind 39 is free.

**Sub-slice ladder:** L1a delegate-TYPE plumbing (Func/Action canonicals resolve + delegate-typed params
invocable via callvirt Invoke; parity passes real Func instances as args) → L1b non-capturing
expression-bodied lambdas in ARGUMENT position (expected type known → synthesize + ldftn) → L1c zero-param
`:=` lambdas → L2 typed locals (`let f: Func<int,int> = ...`, statement kernel) → L3 captures/display
classes (adversarial-review territory) → L4 local functions. L1b's /tmp spike: Func ctor persistence,
forward-ldftn baking, interleaved DefineMethod (questions enumerated in the recon output).

---

## 2026-06-10 — Phase D-17b: columnar generic-function `where` CONSTRAINTS + oracle circular-constraint fix

Generic functions with `where` clauses now emit columnar instead of declining whole-file. Kernel
(`ParserFunctionSignatures.nl`): clauses parse into FLAT ROWS — owner-name span + code (type-tree root >= 0 in
the shared node table, or -2 `class` / -3 `struct` / -4 `new()`); `sres` grew int[7]→int[8] (`sres[7]` = row
count) with three new out-arrays through the Bindings boundary (the D-15a/D-16 pattern; delegate + all 7 call
sites). `sres[6]` (signature end) now lands PAST the clauses on the body `{`.

**Scanner hazard found by fragment bisection:** a depth-0 `class`/`struct` KEYWORD inside a where clause was
picked up as a phantom DECLARATION by all three top-level kernel scanners (`ParserDeclarations.nl`) AND the
adapter's C#-side `TopLevelClassIndices`/`TopLevelStructIndices` → declCount mismatch → whole-file decline
(`new()` and type refs were invisible to scanners — the giveaway). All five scanners now suppress keyword
recognition from a depth-0 `where` (53) until the body `{`.

Adapter: rows group per declared type parameter (specials mirror SpecialConstraintKind Class=1/Struct=2/New=4;
type constraints canonicalize); declines — unknown owner name, `class`+`struct` or `struct`+`new()` combos
(the production parser errors on the one-clause forms; the two-clause forms must not slip through), rows on a
non-generic function or a constructor. Emitter: definition-time application between `DefineGenericParameters`
and `SetReturnType` (attrs map exactly as the oracle's `ApplyGenericConstraints`; ONE base-type constraint per
param — admissible targets: another of the function's own params (`where T: U`), a user REFERENCE-layout
TypeBuilder, or a baked BCL class; interface lists / value types / arrays / enums / closed generics decline);
the siblings tuple carries `(SpecialConstraints, BaseConstraints)` per position; CALL-SITE enforce-or-decline
at the single `MakeGenericMethod` chokepoint (inferred + explicit paths): class/struct/new()/assignability
checked on baked runtime bindings; a caller's open param or any emitted shape bound into a constrained
position declines. /tmp spike proved: constraints persist + load under PersistedAssemblyBuilder; builder
`MakeGenericMethod` validates NOTHING (a violating instantiation silently persists an assembly that fails at
load) — so emitter enforcement is mandatory; `t.Assembly is AssemblyBuilder` cleanly separates emitted shapes
from runtime types.

**ORACLE DEFECT FIXED (probe-found): circular constraints HUNG the compiler.** `where T: T` (and mutual
`where T: U where U: T`) sent `nlc check`/`run` into an infinite loop — 100% CPU, declaration-time, even
UNCALLED (bisected to the ILCompiler's base-chain walks: a constrained param's BaseType IS its constraint, so
a cycle never terminates). The analyzer now rejects direct type-parameter constraint cycles with NL208
"circular constraint dependency" (C#'s CS0454 analog) before emit; F-bounded shapes (`where T:
IComparable<T>`) stay legal. The columnar emitter independently declines cycles (the CLR refuses the metadata
at load — probed TypeLoadException). **ORACLE DEFECT RECORDED (future bundle):** member dispatch on `T`
through an INTERFACE constraint crashes at emit (NL103 "Method CompareTo not found on generic type parameter
T") while base-CLASS constraint dispatch works — analyzer accepts, emitter can't bind; columnar declines both.

Tests: `ColumnarCodegen_Parity_GenericConstraints` (parity over struct/class/new()/`T: U` accepts + metadata
asserts on the loaded definitions + 11 decline pins incl. violations, circularity, `new T()` bodies,
unverifiable open-param bindings); 4 where-clause cases in the kernel-vs-production signature parity test; 4
analyzer circularity tests; the D-15a "where clause declines" pin FLIPPED (an uncalled user-class-constrained
function now emits). 3966/3966; gate log `/tmp/gate-d17b.log`. Next: the lambdas/closures arc.

---

## 2026-06-10 — Phase D-17a: columnar VALUE-STRUCT user constructors (`e2f4a553`)

PASS 0c's wholesale value-type ctor decline lifted; generic structs (`GCell<int>`) flow through the D-16
closed machinery. Value-type ctor bodies: NO base chain, NO all-fields validation (the oracle ACCEPTS
partial assignment in struct ctors — probed; unassigned fields keep the newobj-zeroed value; classes keep
NL304), bare field WRITES enabled via a new `isConstructorBody` emitter flag (a ctor's arg 0 IS the caller's
storage pointer — struct METHODS still decline field mutation, spilled-copy semantics). Construction sites'
IsReference gates lifted (`newobj` on a value type zero-inits → ctor → pushes the value).

**ORACLE DEFECT found by probing (recorded for a future fix bundle):** `new S()` with a declared
parameterless `: this(9)` struct ctor ZERO-INITS instead of running the user ctor. Columnar declines
value-type ctor chains AND parameterless value-type user ctors (pinned).

**Test-authoring landmine:** `partial` is a LEXER KEYWORD — `func partial(...)` in a parity source declines
at PARSE (bisection burned an hour on it); same family as the member-order and multi-line-get rules.
Parity: ColumnarCodegen_Parity_ValueStructConstructors; two D-16 decline pins flipped. 3961/3961; gate
559aa0c5b3e0456e (one gate validated the merged union+B4+follow-on+D-17a tree; commits split by author).
Next: D-17b `where T: Base` constraints for columnar generic funcs, then the lambdas/closures arc.

---

## 2026-06-10 — ORACLE GENERIC UNIONS: `union Result<T>` end-to-end (`d1c41b6e`) + docs/examples sweep

Closes chip `task_7bd7b47c` (implement-vs-fix-docs): the README's flagship `union Result<T>` did not parse
(NL102 at the `<`). Decision: IMPLEMENT (option a) — generic union syntax pervades README/website/editor
docs as the language design, and the generic-user-types oracle arc had just landed the machinery to build
on. The columnar pipeline still declines generic unions to this path (D-10 pin unchanged), so columnar
parity is preserved; columnar generic unions remain future Phase D coverage.

**Surface** (matches the docs, normalized where they disagreed): declaration `union Result<T,...>`;
annotations `Result<int>`; construction takes type arguments AFTER the case name
(`new Result.Success<int> { value: 42 }` — cases never declare their own params, so the args bind
unambiguously to the union, consistent with `Identity<int>(42)`/`new Box<int>(...)` name-then-args) or
adopts the expected type for payload-free cases (`return new Option.None` on `Option<User>`); patterns
never repeat the args (`Result.Success { value }` — inferred from the scrutinee).

- **Parser/AST**: `TypeParameters` on `UnionDeclaration`; `ParseTypeParameters()` after the union name.
- **Analyzer**: type params scoped over case property types; arity diagnostics for annotations AND
  construction (NL207 InvalidTypeArgument, mirroring the B2/B13 bundle); scrutinee normalization
  (`TryResolveDeclaredUnionType`: `GenericTypeInfo` naming a declared union → union + substitution map)
  drives case validation, binding substitution (`value: T` binds int on `Result<int>`), and exhaustiveness —
  including NESTED-union coverage (splitting `Outcome.Ok` arms by the nested `Option` case still counts,
  via substitution threaded into `IsUnionCaseCoveredByPatterns`).
- **ILCompiler**: the abstract base gets `DefineGenericParameters`; each sealed nested case REDECLARES the
  union's params (CLR metadata does not inherit them) and derives from the base closed over its own params
  (`Success<T> : Result<T>`); case ctor bodies rebind the base-ctor call to that instantiation; patterns,
  bare type-patterns, and `is`-tests close the open case definition over the scrutinee's args (the isinst
  token must be loadable); pattern member loads rebind fields on `TypeBuilderInstantiation` with positional
  substitution; overload binding accepts a closed case where the closed base is expected by walking the
  definition's substituted base chain (`IsClosedGeneratedTypeAssignableToBase` — reflection's
  IsAssignableFrom cannot answer this); `IsEnumSafe` guards `Type.IsEnum`'s IsSubclassOf on
  TypeBuilderInstantiation. Generic unions never take the value-struct layout (explicit `Classify` guard).
- **Transpiler** (`nlc export csharp`): `abstract record Result<T>` with cases deriving from `Result<T>`;
  JSON polymorphic attributes skipped for generic unions (cannot describe an open generic hierarchy);
  construction reorders args onto the union (`new Result<int>.Success`). Known inspection-only edges:
  target-typed case construction and generic-union case patterns export without C#'s required args.
- **Interop**: PascalCase payloads surface as public CLR fields on the nested case;
  `CSharpInteropTests` gained a hand-mirrored `Fetched<T>` + consumer test (C# switch over
  `Fetched<int>.Hit/.Miss` works naturally). camelCase payloads stay assembly-internal — the interop docs
  now say so explicitly.

**Regression caught by the example, not the unit suite:** inside a `namespace`, a dotted payload-free
pattern (`Option.None =>`) misses the exact type-registry key and flows through the bare type-pattern path,
which emitted `isinst` against the OPEN nested definition — TypeLoadException at assembly load. Fixed in
`EmitTypePatternTest` (close over the scrutinee's args) and pinned with a namespaced unit test. Lesson:
unit-test programs skip `namespace`; single-file examples are real product surface that exercises it.

**Docs/examples sweep** (evidence over hype): README Quick Example is now a real program that compiles and
runs (verified via `nlc run`; it previously used top-level statements N# doesn't have, and the POSTFIX
match form `result match {` that never parsed — only prefix `match result {` exists; normalized the
postfix form across README + memory/features/pattern-matching.md + collections.md + testing.md +
components/parser.md). types.md/interop.md CLR-shape snippets now match the real emission (protected base
ctor, public FIELDS for PascalCase payloads — not `private` ctor + `required ... { get; init; }`);
rider-plugin SETUP.md had F#-style `| Case(T)` union syntax. New `examples/05-unions/GenericUnions.nl`
(gate-built). Known pre-existing edge, not new: a user generic type named `Result` with arity 2 is shadowed
by compiler-known `NSharpLang.Runtime.Result` in ILCompiler's `ResolveGenericTypeDefinition` order (affects
all user types, not unions specifically).

Implementation gated+committed `d1c41b6e` (fresh isolated /tmp-worktree run — a CONCURRENT session was
mid-slice on columnar value-struct ctors in this checkout; zero file overlap, gates sequenced). Docs sweep
gated separately.

---

## 2026-06-10 — B4 CLOSED: generic-record init members WORK via backing-field lowering (modreq workaround)

The upstream report for the PersistedAssemblyBuilder modreq drop was withdrawn (user decision: no upstream
dependency); the oracle now WORKS AROUND the bug instead of refusing. Key insight, spike-proven: the bug is
confined to rebound **MemberRef** signatures — the **MethodDef** keeps its `modreq(IsExternalInit)`, and a
**field** signature has no custom modifiers to lose. Since every N# init-only member with auto storage is
backed by an `Assembly`-visible synthesized field, closed-generic call sites (object-init, `with`, member
assignment) now store the rebound backing field directly (`TypeBuilder.GetField`) instead of calling the
setter — byte-for-byte the setter body's effect. The emitted setter keeps its modreq, so **C# consumers of
the saved assembly still see a true init-only property**. Block-form members resolve by member name;
primary-constructor members only register `<Name>k__BackingField`, hence
`FindInitOnlyBackingFieldOnClosedGeneratedType` tries both. Two previously UNTRACKED init-setter definition
sites (primary-constructor record setters, custom-bodied `init` properties) carried the modreq but bypassed
the old refusal — runtime MissingMethodException holes. Primary-ctor setters now join `_initOnlySetters`
(auto storage); custom-bodied init setters land in `_customInitOnlySetters` and refuse with a clear compile
error on closed generics (a field store would bypass the custom body — the one case with no sound lowering).

**Latent generic-record body defects fixed in the same arc** (reachable the moment construction works):
synthesized `<Clone>$`/`Equals` used the bare generic TypeBuilder as a TYPE token (castclass/isinst/local
signature) — `TypeLoadException: Could not load type 'Pair'` at runtime; bodies now use the
self-instantiation (`GetSelfInstantiatedType` → `Pair<!T>`; field/method DEF tokens on the bare builder are
fine and unchanged). **Block-form record value semantics were vacuous** — `Equals`/`GetHashCode`/`ToString`
enumerated only primary-constructor members, so block-form records compared always-equal with constant hash
17 and printed name-only. New `GetRecordDataFields` enumerates primary members then block-form instance
members (each resolved to backing storage); equality/hashing cover ALL instance data, ToString prints
primary + public auto-property members (C#'s printable rule). ToString's box decision now also boxes
unconstrained `!T` (was `IsValueType`-only — invalid IL for value instantiations).

Pins: object-init returns values (not refusal), distinct instantiations coexist, modreq preserved on the
emitted setter (CompileAndInspect), structural Equals per instantiation, primary-ctor form, `with` on closed
generic records. Known follow-up: the ANALYZER does not yet enforce init-only assignment restrictions
(assignment outside initializers is an emitter-level concern only); columnar still declines generic records
until it models this lowering.

---

## 2026-06-10 — Phase D-16: columnar GENERIC TYPES (`a10d33f9`)

Generic user CLASSES compile through the columnar pipeline end-to-end, built directly on the corrected
oracle. Kernel: `ParseStructDeclarationInto` parses `<T, U>` after the type name (D-15a's loop; constraints/
empty lists → -1; spans in new outTypeParamStarts/Lengths, count in outResult[7], outResult now size 8 —
ONE adapter call site, no test-harness scratch to bump for this kernel). Adapter declines generic RECORDS
(oracle's deliberate init-modreq refusal) + generic-with-base. Emitter: PASS 0 `DefineGenericParameters` +
`ColumnarStructDef.GenericParameters`; member signatures resolve the type's own params first
(`TryResolveMemberType`); static members on generics decline (per-instantiation semantics unprobed);
`TryResolveClosedUserGeneric` resolves `Box<int>` canonicals (typeParams threaded for `Box<T>` shapes inside
another generic); case-15 closed construction via `TypeBuilder.GetConstructor` + positional substitution;
closed-receiver field/property/method access via `TypeBuilder.GetField/GetMethod` rebinding — mirroring the
oracle's fix-bundle machinery.

**Two harness lessons re-confirmed by bisection** (probes deleted): test programs must respect the kernel
member-order rule (fields+properties BEFORE ctors/methods) and the multi-line `get` block shape. **One real
emitter hazard found:** `TypeBuilderInstantiation` equality is REFERENTIAL and `MakeGenericType` does not
cache — nested `new Box<Box<int>>(new Box<int>(v))` produced two unequal instances of the same closed type;
new structural `TypesEquivalent` (definition reference + recursive args) guards the construction/call checks.

Parity: int/string instantiations × ctor+field+method+property, `Pair2<A,B>`, nested `Box<Box<int>>`.
Declines pinned: generic record, generic-with-base, inline constraint, wrong arity, static-on-generic,
generic value-struct construction (the last is the natural next sub-slice alongside `where T: Base`
constraints for funcs). 3932/3932; gate green first try.

---

## 2026-06-10 — Generic-user-types ORACLE arc COMPLETE: bundles 2/3 (`c4b42395`) + 3/3 (`ee5a60ba`)

All 8 probed defects from the 49-probe acceptance map are resolved. Final disposition:
**B1/B10/B12 fixed** (bundle 1); **B2/B13 diagnosed at compile time** (bundle 2: NL207 InvalidTypeArgument —
missing type args on generic `new`, arity validation in ResolveGenericType covering `new` AND annotations,
with the NL201 dedupe guard since the resolver runs in both passes); **B14 fixed by the NL201 slice**
(pinned); **B5 generic structs fixed transitively** by bundle 1's closed-generic member resolution (pinned);
**B4 generic records refuse cleanly** — blocked upstream.

**Upstream .NET 10 runtime bug discovered (B4 root cause):** `PersistedAssemblyBuilder` drops required
custom modifiers (`modreq IsExternalInit`) from member references rebound via `TypeBuilder.GetMethod` over a
closed generic instantiation — the init-setter call fails at RUNTIME with
`MissingMethodException: Void Pair.set_First(!0)`. Proven by a minimal pure-Reflection.Emit spike (no N#
code; identical program without the modreq returns correctly — causality pinned by control run). Per the
cardinal rule the oracle now REFUSES init-only setter assignment on closed generics with a clear compile
error (init setters tracked in `_initOnlySetters` at definition); plain auto-property setters and fields on
closed generics work and are pinned. Evidence gathered: inline repro, metadata-blob analysis (modreq
present on the MethodDef signature, absent from the MemberRef signature, so ECMA-335 binding cannot match),
and root cause: `ModuleBuilderImpl.GetMethodSignature` rebuilds MemberRef signatures from
`ParameterInfoWrapper`s that never consult the modifier arrays stored at `DefineMethod` time.
Parameter-level modreqs are dropped too (verified); present since .NET 9 and still on `main`. The upstream
report was withdrawn the same day (user decision: solve it in-compiler, no upstream dependency) — the
refusal is SUPERSEDED by the backing-field workaround entry above. **Consequence for columnar generic types
(next slice): generic CLASSES and STRUCTS are in scope; generic RECORDS decline, matching the oracle's
deliberate refusal** (still true for columnar after the workaround — it declines until it models the
lowering).

Process notes: one Systems benchmark gate failure (HotResultCombinations 1.13 vs 1.05 limit) re-ran green
after a 300s cool per the thermal protocol — and exposed a verification gap now fixed: gate verdicts are
read from the LOG's own `GATE EXIT:` line (the wrapper echo had masked an exit-1 once; bundle 2's commit was
retro-validated by the clean re-run on its exact pushed tree, B4 WIP stashed). One full-suite host OOM abort
under machine pressure was not reproducible.

---

## 2026-06-09 — Generic-user-types ORACLE fix bundle 1/3: resolution defects B1 + B10 + B12 (`47bd7d2e`)

First sub-bundle of the fix-oracle-first arc. All three resolution defects fixed with verify-first probes
and 5 `ILCompiler_*` regression pins; 3921/3921 unit tests; gate green first try.

- **B1 closed-generic member access**: `b.item`/properties on `Box<int>` — reflection member queries throw
  on TypeBuilderInstantiation and the open-definition recursion dead-ended (uncreated `TypeBuilder.GetField`
  throws too; only the METHOD path had its own bookkeeping). New
  `FindInstanceFieldOnClosedGeneratedType`/`...AccessorOnClosedGeneratedType` walk the open chain and rebind
  via `TypeBuilder.GetField/GetMethod`; typing substitutes closed args positionally (int, not object).
  Generic BASE chains under closed derived types remain unsupported (null → existing diagnostics).
- **B10**: `BindDeclaredConstructorCall` substitutes closed type args into the OPEN ctor parameter shapes
  (`Holder<T>(i: Box<T>)` now binds `Box<int>`), fixing coercion types too.
- **B12 was BROADER than the probe map**: generic instance methods failed on ALL user types — `DeclareMethod`
  never called `DefineGenericParameters` (U degraded to object at definition; `MakeGenericMethod` threw).
  Now mirrors `DeclareFunction`'s define→generic-params→Set* order (non-generic path byte-identical);
  `EmitMethodBody` merges method+type generic params (method-first = innermost scope) — without this,
  interpolating a value-type U emitted InvalidProgram IL that only verified for reference instantiations;
  `BindDeclaredMethodCall` rebinds onto the closed receiver BEFORE `MakeGenericMethod` (`Box<int>.Pair<bool>`
  composes; Reflection.Emit rejects the reverse) and falls back to declaration-resolved parameter types when
  a MethodBuilderInstantiation can't enumerate parameters.

**Sub-bundle 2 probes (done):** B14 is ALREADY FIXED by the NL201 slice (`new Box<Nope>(5)` → NL201 at
check time — pin it); B2 (`new Box(5)`) still emits BadImageFormat garbage and B13 (wrong arity) emits
TypeLoadException garbage — both need analyzer-side arity validation (InvalidTypeArgument NL207: missing
args on a generic local type at `new`, count mismatch in ResolveGenericType for locally-declared generics).
Next: that sub-bundle, then B4/B5 (generic records/structs emit).

---

## 2026-06-09 — Oracle/toolchain hygiene bundle: NL201 unresolved types, NL923 reference-load failures, installer integrity (audit-driven)

Four audit-driven commits landed between D-15b and the generic-user-types bundle (`d4be7eef`, `e9273453`,
`ad96360a`, `109efcd2`), two of which CHANGE ORACLE BEHAVIOR that future columnar/analysis slices must mirror:

- **NL201 TypeNotFound at declared-type positions** (`109efcd2`): the Analyzer's ResolveSimpleType fallback no
  longer silently fabricates `ExternalTypeInfo` for unrecognized names at parameter/return/field/property/
  variable annotations, type aliases, union case properties, and `new` expressions (generic args via
  recursion). Includes Levenshtein "Did you mean 'X'?" suggestions. Leniency deliberately retained: pass-1
  signature collection, lazy cross-file member resolution, and DOTTED names (`new Union.Case`,
  namespace-qualified externals). Generic-name probing is arity-aware (`List` → `` List`1 ``) and consults the
  compiler-known generics map (extracted as `TryGetKnownOpenGenericType`). Local functions now register their
  generic type parameters (latent gap). Visibility-blocked cross-file types now error (contract test updated).
  **Phase D relevance:** partially addresses defect B14 (unknown type args now diagnosed at declared
  positions — re-probe B14 before building its bundle slice); Arc 3's columnar diagnostics pass must
  reproduce NL201 + suggestion semantics.
- **NL923 ReferenceLoadFailure** (`e9273453`): all reference-assembly load/inspect failures (MLC probe loops,
  metadata resolver candidate DLLs, reference loaders) are recorded and surfaced as advisory NL923 warnings
  whenever the same analysis produced unresolved-name/type errors — a broken reference can no longer
  masquerade as a bare "not found". NL923 is the one deliberate non-blocking exception in the NL9xx range
  (special-cased in DiagnosticCatalog). Arc 3 must carry this pairing behavior.
- Toolchain hardening (no oracle impact): GitHub Actions pinned to SHAs + `permissions:` on build.yml
  (`d4be7eef`); `scripts/install.sh` now verifies SHA256SUMS for URL downloads and `publish-toolset.sh`
  emits the sums asset (`ad96360a`) — releases MUST upload `SHA256SUMS` per docs/PUBLISHING.md.

Full unit suite 3916/3916; all four commits individually gated (`VSCODE_TESTS=skip ./scripts/test-all.sh
--commit`). Also flagged for a user decision: **generic unions (`union Result<T>`) do not parse** (NL102 at
the `<`) despite being README's flagship example — chip `task_7bd7b47c` tracks implement-vs-fix-docs.
Next: the generic-user-types ORACLE fix bundle (B1 first; recon below confirms root cause).

---

## 2026-06-09 — Phase D-15b: columnar EXPLICIT generic type arguments (kind-38 GenericCallee)

`Identity<int>(42)` now compiles through the columnar pipeline (`d0c079ba`), completing the generic-FUNCTION
story. The expression kernel gained an `IsGenericCallTypeArgs` lookahead mirroring `Parser.cs
IsGenericMethodCall` (:1993) EXACTLY — committing to a type-argument list only when a bare-identifier callee's
`<` scan reaches a close followed DIRECTLY by `(` — and a new **GenericCallee node (kind 38**, value span =
callee name, children = TYPE-kernel subtrees; 38 is the next free kind after UnionCasePattern 37). The postfix
loop's `(` branch then wraps it like any callee. On the emit side the inference block refactored into a shared
`TryEmitGenericSiblingCall` taking the binding array — empty for inference, PRE-SEEDED from resolved explicit
type args (simple type nodes only; TypeBuilder/EnumBuilder bindings decline) — with the unify loop VERIFYING
seeded bindings (`Identity<string>(5)` declines). A committed-but-non-generic shape (`a < b > (c)` over locals)
yields a kind-38 node the emitter declines — decline-safe whichever way the oracle's grammar rules it. 4 new
parity invocations + 4 new decline pins; the D-15a explicit-args pin flipped. 1236 tests green; gate green
(first try). Next: the generic-user-types ORACLE fix bundle (8 probed defects: closed-type field lookup,
inferred-construction BadImageFormat, generic records/structs, generic-typed ctor params, generic methods on
generic types, runtime arity TypeLoadException, undiagnosed type args), then columnar generic types.

---

## 2026-06-09 — Phase D-15a: columnar GENERIC FUNCTIONS (real CLR generic methods + call-site inference)

The generics arc opens on its oracle-solid surface (`ca0b64da`). A 49-probe fan-out mapped the acceptance
surface first: generic FUNCTIONS are fully sound in the pipeline (inference, explicit args, multi-params, T
locals/arrays, `new T[n]`, `= default`, `==` on T, `where T: Base` constraints/NL208, recursion); **generic
USER TYPES are an 8-defect oracle minefield** (field access on closed types, generic records/structs,
generic-typed ctor params, generic methods on generic types all fail; inferred construction and wrong arity
CRASH at runtime; unknown type args undiagnosed) — deferred to a fix-oracle-first bundle; BCL generics
(List/Dictionary) all 10 probes accepted. An emission-strategy recon + a /tmp Reflection.Emit spike (deleted
after) de-risked the design: mirror the oracle's PRIMARY path — one real CLR generic method
(`DefineGenericParameters`) instantiated per call site via `MakeGenericMethod` (the oracle's selective
value-type monomorphization is an optimization parity does not need).

- **Kernel**: `ParseFunctionSignatureInto` now PARSES `<T, U>` lists (previously blind-skipped — safely, since
  T was unresolvable at emit) into new out-arrays, and reports the signature-end token (`outResult[6]`) so the
  adapter declines anything but a direct body `{` — catching `where` clauses (which CANNOT be dropped: NL208
  is call-site enforced), inline constraints, and `=>` bodies.
- **Emitter**: generic functions declare open CLR generic methods; `T`/`T[]` resolve through a type-param map
  checked first (the oracle's ResolveType order); T-typed locals and `ldelem !!T` admitted; the sibling-call
  tier unifies declared parameter shapes against emitted argument types (conflict/uninferrable/composed-shape/
  TypeBuilder-binding declines), binds via `MakeGenericMethod` — including over the CALLER's own open T
  (generic-calls-generic, recursion) — and substitutes the binding into the return shape. Generic METHODS on
  user types decline (oracle-broken, B12).

`ColumnarCodegen_Parity_GenericFunctions`: 14 value-matched invocations + `IsGenericMethodDefinition`
metadata + 10 decline pins; passed FIRST TRY (the spike's patterns transferred exactly). The corpus' own
`ParserFunctionSignatures.nl` — now containing the generic-parsing kernel code — still compiles through the
columnar pipeline and value-matches (the self-host loop verifying its own new code). 1236 tests green; full
non-IDE gate green (first try). Next: explicit type arguments (the `IsGenericMethodCall` lookahead mirror in
the expression kernel), then the generic-user-types oracle fix bundle, then lambdas/closures.

---

## 2026-06-09 — Phase D-14: columnar STATIC PROPERTIES (the static-member arc is COMPLETE) + 3-defect oracle fix bundle

`static Name: Type { get {...} [set {...}] }` now compiles through the columnar pipeline (`c3da5311`),
completing the static-member arc (D-12 methods → D-13 fields → D-14 properties). Kernel: the static-field
branch routes a `{` after the type into outPropIndices with a static flag (the pre-existing member-order rule —
fields+properties before methods/ctors — unchanged). Emitter: CLR-static `get_Name`/`set_Name` (setter `value`
at arg 0), accessor BODIES are STATIC contexts (`_currentStruct` null → a bare backing-field reference declines
exactly at the pipeline's NL103, probe-pinned d3b — backing access must be `TypeName.field`); `TypeName.Name`
read/write chain-walks (after static fields); bare READS resolve in instance bodies (pbare-pinned asymmetry).

THREE more oracle defects, found by probing and fixed first:
- **NL304 demanded ctor assignment of uninitialized STATIC fields** (`Analyzer.CheckDefiniteAssignment` now
  skips statics — a static is `.cctor`/zero-initialized, never an instance ctor's contract).
- **A static property through an instance receiver (`c.X`) died at RUNTIME** (`callvirt` on a static accessor →
  MissingMethodException) while instance-receiver static FIELDS already worked — because the CLR itself
  tolerates ldfld/stfld on statics (ECMA-335 III.4.10/28 pops the receiver). Six accessor sites now mirror the
  field behavior (Pop+`call` getters; spill-pop-call setters). N# semantics note: static member ACCESS through
  an instance receiver is permitted (fields by CLR tolerance, properties by these helpers); static method
  INVOCATION through a receiver stays an error (A3).
- **`class D: R` (record base) compiled into an UNLOADABLE assembly** ("parent type is sealed" — records emit
  sealed). Now a compile-time error like the struct-base rejection. The columnar side gained the record/class
  distinction it lacked (`IsRecord` through input+def): record-as-base and record inheritance were silently
  accepted with UNSEALED metadata (latent over-acceptance + metadata divergence) — both now decline, pinned.

`ColumnarCodegen_Parity_StaticProperties`: 10 value-matched invocations + CLR metadata asserts + 11 decline
pins; one stale D-12 pin flipped. 1235 ILCompiler+Analyzer+dogfood tests green; full non-IDE gate green.
Cumulative static-member arc: 3 columnar slices, 3 oracle fix bundles (6+1+1+3 defects), ~80 parity
invocations, ~60 decline pins. Next per the retirement-map order: **GENERICS** (generic functions → generic
types → constraints → specialization; two-sided — the kernels do not parse `<T>` yet; the briefing's probe
fan-out applies), then lambdas/closures.

---

## 2026-06-09 — Phase D-13: columnar STATIC FIELDS (literal initializers, `.cctor`, chain-walked `Type.field`, bare-access asymmetry)

The columnar pipeline now compiles `static name: Type [= <literal>]` fields on classes/records/structs
(`2982ef50`), value-matched against the oracle — which needed ANOTHER verify-first fix first: **a RECORD's
static-field initializers were silently DROPPED** (`EmitRecordBodies` never called
`EmitDeclaredStaticFieldInitializers`, so `static label: string = "rc"` read back null at runtime; classes and
structs were fine). Fixed + pinned (`ILCompiler_RunsRecordStaticFieldInitializers`).

- **Kernel**: the fields loop parses static fields with SINGLE-TOKEN literal initializers (Int/Float/Char/
  String/true/false; optional leading `-` on numerics) into four new out-arrays; a `{` after the type (static
  property), a general initializer expression, instance-field initializers, and `static constructor` keep
  returning -1. General-expression initializers are a documented residual (same shape as the chain-arg
  restriction, checklist #14).
- **Emitter**: statics are CLR-static, EXCLUDED from FieldOrder/Fields (object-init/positional-ctor/NL304 never
  see them), initialized in the type's `.cctor` in declaration order with EXACT literal/field-type agreement
  (suffix-classified ints incl. L/UL, f/d floats, RAW strings — `Trim('"')`, no escape decode, matching the C#
  path — escape-decoded chars, bools). `TypeName.field` read/write chain-walks (the fixed oracle's semantics).
  **Bare access models the pipeline's pinned ASYMMETRY** (probed directly, c4/c6): resolves inside INSTANCE
  member bodies only; a STATIC body's bare access declines structurally (`_currentStruct` is null there) exactly
  where the pipeline reports NL103. A value struct with zero INSTANCE fields declines even when statics exist.
- **Parity-harness state lesson** (baked into the test as a comment): the columnar side invokes ONE loaded
  assembly across the whole call list while the oracle compiles FRESH per invocation — stateful parity functions
  must self-reset their statics or the two sides diverge legitimately.

`ColumnarCodegen_Parity_StaticFields`: 24 value-matched invocations + CLR `IsStatic` metadata asserts + 14
decline pins. One stale D-12 pin flipped (static-field declaration now accepted). 638 ILCompiler+dogfood tests
green; full non-IDE gate green (first try). Next: static PROPERTIES — NOTE the D3 probe showed the oracle FAILS
on a static get/set property with a static backing field ("Undefined variable: s_value"); probe + likely
fix-oracle-first before the columnar slice. Then generics → lambdas/closures.

---

## 2026-06-09 — Phase D-12: columnar STATIC METHODS (`static func` members, chain-walked `TypeName.M()`, pinned bare-call precedence)

The columnar pipeline now compiles `static func` members on classes/records/structs end-to-end, value-matched
against the static-resolution-fixed oracle (`80204c27`):

- **Kernel** (`ParserDeclarations.nl`): `ParseStructDeclarationInto` records `static func` members (token 63
  immediately before 7) into a NEW `outMethodStaticFlags` array (the func index still points at `func`, so the
  same signature/body kernels parse it); the fields loop hands off at `static func`. `static` before a field/
  property/`constructor` still returns -1 (those are the next slices).
- **Adapter**: marshals the flag onto `ColumnarFunctionInput.IsStatic`.
- **Emitter**: PASS 0b declares statics with `MethodAttributes.Static` — no implicit `this`, UNSHIFTED param
  ordinals, `void` allowed (a static body emits exactly like a top-level procedure), overloads by distinct PARAM
  COUNT (the ctor-overload rule; same-arity type-distinguished sets decline), NL306 name collisions decline in
  both declaration orders. PASS 0b'': static-over-STATIC hiding is accepted (nearest declaration wins, pinned
  against the oracle); every MIXED static/instance shadowing shape declines. STATIC bodies emit with
  `_currentStruct = null` — no implicit-`this` path can structurally fire (a static body's bare instance-field/
  method access declines precisely where the N# pipeline errors) — while a new `_enclosingType` anchors bare
  static resolution on the type's own chain. Qualified `TypeName.M(args)` resolves USER types FIRST via a
  chain-walked arity match mirroring the oracle's bind-or-walk-on rule, and a user type name never falls through
  to the BCL whitelist — closing a LATENT OVER-ACCEPTANCE (a user `record Math` + `Math.Abs(x)` emitted
  System.Math IL while the pipeline errors; now pinned both directions).
- **Bare-call precedence, re-verified DIRECTLY**: sibling top-level function > instance method on the chain >
  static method on the chain. A probe-AGENT claim that own-instance beats top-level was REFUTED by hand-run
  probes (top-level wins in all three shapes) — and the parity harness caught the wrongly-flipped dispatch within
  one run. The D-11d "bare-call sibling ambiguity" decline pin is now a parity case (top-level binds). Lesson
  reinforced: agent probe RESULTS get re-verified before acting, same as review verdicts.
- **Test-harness pollution found+fixed**: loading an emitted assembly containing a GLOBAL public type named
  `Math` poisons the C# oracle's AppDomain-wide external-type scan (`TryResolveLoadedExternalType`) for every
  later in-process compile using `Math.Abs` — manifesting as `FileNotFoundException: ColumnarProgram` inside
  unrelated dogfood tests. The Math-shadowing positive pin is ROUTE-ONLY (never loaded); the decline pin carries
  the gate-regression coverage; the value case was verified out-of-process via the CLI.

Parity tests `ColumnarCodegen_Parity_StaticMethods` + `…InheritanceAndPrecedence`: 30+ value-matched invocations
+ CLR `IsStatic` metadata asserts + 17 decline pins. 636 ILCompiler+dogfood tests green; full non-IDE gate green
(fresh isolated; one flake re-run on an identical tree). Residual declines for later slices: static fields,
static properties, expression-bodied members, same-arity static overloads, array literals (blocked one parity
shape — `[a, b, c]` is checklist item 11). Next per the retirement-map order: columnar STATIC FIELDS
(+ initializers) → static properties → generics.

---

## 2026-06-09 — N# ILCompiler fix bundle: STATIC-member resolution (inherited-static chain walks + this-in-static diagnostic)

VERIFY-FIRST probing for the columnar STATIC METHODS slice (a 58-probe acceptance map over 4 read-only probe
agents, plus a 10-probe residual round, all against the production pipeline) produced the empirical static-member
map AND surfaced two oracle defect classes — both fixed in the C# ILCompiler (the parity oracle) and pinned by 12
new `ILCompilerTests` regressions (`7952bc54`):

- **Inherited STATIC resolution never walked the base-class chain** — `Derived.F()` ("Static method F not found on
  type Derived"), bare `F()` inside derived member bodies ("Function call … not yet fully implemented"),
  `Derived.count` / `Derived.X` static field/property access ("Static member … not found") all failed, while the
  e356aa0d/37b70349 fix bundle deliberately made every INSTANCE-member path chain-walk. The same walk now exists at
  all 9 static sites: the member-access static call and the bare-identifier own-type static call (each at BOTH the
  emit site and its type-inference twin), `EmitStaticMemberLoadValue`/`StoreValue`, the `EmitMemberAccess` static
  read path, `GetMemberAccessType` inference, and ref/out static-field addresses (`EmitMemberArgumentAddress`).
  Static HIDING stays nearest-declaration-wins (the walk starts at the named/enclosing type). One recon claim was
  REFUTED empirically: the suspected ref/out site at ILCompiler.cs:5594 is attribute-argument constant evaluation,
  not a resolution path — left unchanged.
- **`this` in a static context emitted garbage `ldarg.0`** — `this.x` reads compiled then died at RUNTIME with
  `InvalidProgramException`; `return this` even "ran". Both `EmitLoadImplicitThisReference` and
  `EmitLoadImplicitThisAddress` (the two chokepoints every this-path funnels through) now throw a compile-time
  diagnostic ("'this' cannot be used in a static context …") after the captured-this check. `_currentHasThis` is
  set true in ctors/instance methods/accessors/instance lambdas and false in static methods/top-level
  functions/static lambdas, so the guard cannot over-fire (pinned by `ILCompiler_ThisRemainsValidInInstanceContexts`).

EMPIRICAL ACCEPTANCE MAP pinned for the columnar slice (bare-call precedence, verified twice): own/chain INSTANCE
members beat top-level functions (P1: prints own); top-level functions beat own STATIC methods (A14/P2); qualified
`Type.M()` always binds the static (P10); locals do NOT shadow method names in call position (P8). Oracle REJECTS
(columnar must decline): static via instance receiver (A3 — C# CS0176 semantics), static→instance bare call (A6),
instance-field read from a static body (A7), static+instance same name / static method+property same name (NL306,
A11/D11), bare static-FIELD access even inside static methods (C4 — only `Type.field` resolves), `static x := v`
fields (C10), method-as-value (NL411, D10). Oracle ACCEPTS (columnar must value-match): statics on
class/struct/record incl. fieldless structs, arity AND type-distinguished static overloads, void statics, static
factories, expression-bodied statics, `static func Main()` entry (lowercase top-level `main` wins when both exist),
static fields with initializers (int/string/double/bool/user-type) + `Type.field` read/write incl. `+=`, and
expression-bodied/get-block static properties. 509 ILCompilerTests + 125 columnar dogfood tests green; full
non-IDE product gate green (fresh isolated). Next: columnar STATIC METHODS (kernel `static func` member flags →
adapter `IsStatic` → emitter `StaticMethods` declaration/resolution + registry-gated `TryEmitStaticCall`, which
also closes a latent columnar over-acceptance: a user type named `Math`/`Char`/… currently falls through to the
BCL static whitelist).

---

## 2026-06-09 — Phase D-11d: columnar CLASS INHERITANCE (`class D: Base`, `: base(args)`, chain-walking resolution)

The columnar pipeline now compiles single-inheritance class hierarchies end-to-end, value-matched against the
(fix-bundle-corrected) C# ILCompiler oracle:

- **Kernel** (`ParserDeclarations.nl`): `ParseStructDeclarationInto` parses an optional single-identifier base
  (`class D: Base {`) into `outResult[5]/[6]`; plus the ZERO-FIELD lift — a fieldless type with ≥1
  method/ctor/property now returns fieldCount 0 instead of -1 (a fully empty body still declines). Pure-behavior
  base classes (`class HBase { func Tag… }`) were declining the whole program before this.
- **Adapter**: carries `BaseName` onto `ColumnarStructInput`; admits fieldCount 0 for REFERENCE types only (a
  zero-size value struct stays declined — CLR layout edge).
- **Emitter** (`ColumnarIlEmitter`): PASS 0a' resolves the base + `SetParent` and computes chain depths (cycle ⇒
  decline); PASS 0b'' declines every member SHADOWING shape except method-over-METHOD hiding (oracle-accepted,
  nearest-declaration-wins); PASS 0c admits `ChainInitKind == 2` when a base is declared; new PASS 0d synthesizes
  default ctors depth-ascending — a no-base class keeps `DefineDefaultConstructor`, a derived one gets a MANUAL
  parameterless ctor chaining to the base's parameterless ctor (decline when the base has only parameterized
  ctors, matching the oracle's "must chain to a base constructor"). `EmitChainedConstructorCall` resolves
  `: base(args)` among the DIRECT base's ctors by chain-arg count (zero-arg falls back to the synthesized default
  ctor); a NO-initializer ctor implicitly chains to the base parameterless ctor instead of `object::.ctor`
  (ECMA-335: a ctor must run the DIRECT base ctor). NL304 own-fields-only validation unchanged; `: base(...)`
  skips it exactly like `: this(...)` (pinned). Member resolution CHAIN-WALKS nearest-first at six sites: bare
  field read, bare field write, external field/property read, property-setter write, external instance call, and
  NEW bare own-method calls (`GetX()` ⇒ `ldarg.0; call/callvirt`, declined if the name also matches a sibling
  top-level function — unverified resolution order). `CreateType` bakes base-before-derived by chain depth, so
  FORWARD base references (derived declared first) work.

Parity tests `ColumnarCodegen_Parity_ClassInheritance` + `…ImplicitChainHidingAndBareCalls`: headline
`f(5,3)=8` surface, 3-level chain, inherited field/property/method via derived receivers, `: base(x)` leaving own
fields default, int-literal chain args, derived ctor assigning an inherited field, implicit chain to a fields-only
base, explicit `: base()`, method hiding, bare own-method calls on a class AND a value struct, forward base,
fieldless class. DECLINES pinned: base-arity mismatches, implicit chain vs arg-only base (ctor and no-ctor),
class:struct/unknown/self/cycle bases, struct-with-base, object-init of an inherited field, field/property
shadowing, bare-call sibling ambiguity, empty class body, fieldless value struct. Two stale "inheritance
declines" assertions from earlier slices updated. 623 ILCompiler+dogfood tests green; full non-IDE gate green.
Next per the Phase D order: static methods → generics → lambdas/closures.

---

## 2026-06-09 — N# ILCompiler fix bundle: inheritance member resolution + base-ctor chaining (verify-first findings)

VERIFY-FIRST probing for the columnar inheritance slice (two probe rounds against the production pipeline:
acceptance map + Reflection facts on the emitted types) surfaced FIVE oracle defects beyond the already-fixed
e356aa0d receiver-qualified case. All fixed in the C# ILCompiler (the parity oracle), each pinned by a regression
test in `ILCompilerTests`:

- **A — bare inherited method call**: `GetX()` (no receiver) inside a derived method body failed
  ("Function call … not yet fully implemented") — implicit-instance call resolution bound only the enclosing
  type's own methods. Both the emit site and its type-inference twin now walk `BaseType` up the chain.
- **B — inherited member access on a derived receiver**: `d.X` / `d.X = v` / `d.Doubled` failed
  ("Member X not found on type D") — ~10 sites did own-type-only `_fields`/`_methods` lookups and `FindField`
  walked exactly ONE level. New `FindInstanceFieldOnBaseChain`/`FindInstanceAccessorOnBaseChain` helpers walk the
  full N# chain (then external bases via reflection) and are applied across the member read/write/inference/
  pattern sites.
- **C — `: base()` zero-arg against an arg-only base** resolved an ARBITRARY declared ctor with no args pushed →
  `InvalidProgramException` at runtime. The zero-arg fallback now applies only when the target declares NO
  constructors (the synthesized parameterless case); otherwise it must bind a declared overload or fail.
- **D — silent `object::.ctor()` substitution**: a derived ctor with NO `: base(...)` whose base has only
  parameterized ctors silently chained to `object` — unverifiable IL per ECMA-335 (a ctor must run the DIRECT
  base ctor) with every base field left zero. Now a compile-time diagnostic ("must chain to a base constructor …
  add ': base(...)'"); the implicit-chain path (`EmitConstructorInitializerCall` with no initializer,
  `EmitDefaultConstructorBody`, `EmitPrimaryConstructorBody`) all route through the same resolution.
- **E — `class D: S` (struct base) silently DROPPED the base** (D extended Object, S's members vanished):
  `DeclareClass` now rejects a non-class/non-interface base with a diagnostic.

Also EMPIRICALLY pinned (briefing assumption overturned): NL304 definite-assignment fires ONLY for ctors with NO
initializer — BOTH `: this(...)` AND `: base(...)` skip it entirely (a `: base(x)` ctor assigning nothing of its
own is accepted; Y stays default). The columnar slice's decline rules are derived from this map, not from
C#-the-language reasoning. 9 new regression tests (headline bare-call surface, 3-level chain, inherited field
read+write, inherited property, implicit chain to a fields-only base, NL304-skip pin, and the three rejection
diagnostics); 621 ILCompiler+dogfood tests green; full non-IDE gate green (fresh isolated). This completes the
oracle prerequisites for the columnar INHERITANCE slice (next).

---

## 2026-06-09 — N# ILCompiler fix: INHERITED instance-method resolution (unblocks columnar inheritance)

Surfaced while scoping the columnar inheritance slice: the N# pipeline ITSELF rejected a call to an inherited
instance method on a derived receiver — `d.GetX()` where `GetX` is declared on the base reported
`NL103: … Method GetX not found on type D` — even though inheritance and inherited FIELD/property access both
worked. Root cause: the C# ILCompiler's instance-method-call resolution (`EmitMemberAccessCall` + the call-type
inference path) keyed only on the receiver's OWN type (`GetMethodKey(D, "GetX")`) and never walked the base-class
chain, whereas field/property resolution (`TryResolveCurrentTypeMember`) did. FIX: both resolution sites now walk
`typeBuilder.BaseType` up the chain (binding the inherited overload on the declaring base type; the derived receiver
is implicitly upcast by the call). Regression-tested: `ILCompiler_CanCallInheritedInstanceMethodOnDerivedReceiver`
(the exact repro) + `ILCompiler_CanCallInheritedMethodAlongsideOwnMembers` (a derived class with its own field +
method); 489 ILCompilerTests + 123 columnar tests green. This UNBLOCKS the columnar inheritance slice — the parity
oracle can now value-match inherited method calls. (Pure C#-pipeline fix; no columnar change.)

---

## 2026-06-09 — Phase D-11b-iv: constructor CHAINING (`: this(args)`)

A constructor can delegate to another constructor of the same class: `constructor(x): this(x, 0) { … }`.
- **Kernel**: `ParseFunctionSignatureInto` no longer treats a `: this`/`: base` after the param `)` as a return type
  (a ctor-only change — a regular function's `: ReturnType` always has a TYPE token after `:`, never `this`(42)/
  `base`(43) — so function-signature parsing is unchanged, and a chaining ctor now parses with returnRoot = -1). A new
  `ParseConstructorChainInfoInto` kernel parses the `: this(args)`/`: base(args)` initializer, recording each chained
  ARG (restricted to a param IDENTIFIER or an INT LITERAL — a complex/other-literal arg returns -1 → decline) +
  outResult[0] = initKind (0 none / 1 this / 2 base).
- **Adapter**: `TryParseColumnarConstructorAt` returns a new `ColumnarConstructorInput` wrapping the ctor body
  (ColumnarFunctionInput) + the chain init-kind + chain-arg kinds/texts; `ColumnarStructInput.Constructors` is now a
  list of those.
- **Emitter**: PASS 0c declines a `: base(...)` ctor (no modelled base class). PASS 2 — for a `: this(...)` ctor,
  `EmitChainedConstructorCall` resolves the chained ctor by chain-arg COUNT (excluding self; ambiguous-by-count
  declines), emits `ldarg.0; <args (ldarg for a param, ldc.i4 for an int literal, type-checked against the chained
  ctor's params)>; call <chained ctor>` IN PLACE of the base `object` ctor, then the body. A chaining ctor SKIPS the
  NL304 all-fields-assigned check (the chained ctor assigns them) but still forbids `return` (NL103).

Parity-gated: `ColumnarCodegen_Parity_ClassConstructorChaining` value-matches the C# ILCompiler over `new C(v)`
(1-arg → chains to the 2-arg ctor) vs `new C(a, b)` (the 2-arg ctor directly), and a 3-field class whose 2-arg ctor
chains to the 3-arg ctor passing a literal; metadata-asserts two constructors; decline-pinned for a complex chained
arg (`this(x + y)`) and inheritance (`class D: Base`, which a `: base(...)` chain requires). 123 columnar tests green
(the shared signature-kernel change broke nothing); full non-IDE gate green (fresh isolated). **Class CONSTRUCTORS
complete** (single + overloaded + chaining) for the modelled surface. Next: INHERITANCE (blocked on an N# pipeline
bug — inherited instance-method calls report NL103; flagged as a separate fix).

---

## 2026-06-09 — Phase D-11c2: class get/SET computed PROPERTIES

Extends get-only properties (D-11c) with a setter + property assignment.
- **Adapter** (`TryParseColumnarPropertyAt`): after the get body's `}`, an OPTIONAL `set { … }` accessor parses into a
  "set_Name" function with one implicit parameter `value` of the property type, returning void (vs the property block
  closing `}` for get-only). A set-first ordering / expression-bodied / third accessor declines. `ColumnarPropertyInput`
  carries the optional setter. (A small `MatchingCloseBrace` helper factors the balanced-brace scan.)
- **Emitter**: PASS 0b' also declares `set_Name` (SpecialName, param `value`: property type, void) when present, its
  body emitted via structMethodJobs — the emit loop now passes `isVoid` by the job's declared return type (a void
  setter body falls through to a trailing `ret`; a getter/method always-returns). case 23 (assignment) gains a
  PROPERTY setter branch: `receiver.Name = value` on a reference-type local/param with a settable property `Name`
  emits `<receiver ref>; <value>; callvirt set_Name` (a get-only property has no setter → falls through to decline).
  `def.Properties` now carries the setter MethodBuilder; the get_Name/set_Name collision check covers both accessors.

Parity-gated: `ColumnarCodegen_Parity_ClassGetSetProperty` value-matches the C# ILCompiler over `b.Value = v; return
b.Value`, a property read in the RHS of its own write (`box.Value = box.Value + c`), and a setter doing arithmetic on
the implicit `value` (`raw = value * 2`); metadata-asserts get_Value + set_Value; decline-pinned for assigning a
get-only property (N# NL103). The get-only test's "set accessor declines" assertion is flipped. 117 columnar tests
green; full non-IDE gate green (fresh isolated). **Class PROPERTIES (get + get/set) complete** for the modelled
surface. Next: ctor chaining (this), then INHERITANCE.

---

## 2026-06-09 — Phase D-11c: class get-only computed PROPERTIES

A class/record can expose a computed read-only property: `Doubled: int { get { return val * 2 } }`, read via
`c.Doubled`. Spans all three layers.
- **Kernel** (`ParseStructDeclarationInto` field loop): a PROPERTY is an `Identifier : Type {` member — disambiguated
  from a field `id : type` by the trailing `{` (129). Records the property NAME token index in a new `outPropIndices`
  and skips the balanced `{ … }` block; outResult[4]=propCount. (Single-token property types only — a composed type
  presents no `{` at +3 and falls to the field path → declines.)
- **Adapter** (`TryParseColumnarPropertyAt`): from the name index, expects `name : Type { get { body } }` and parses
  the get body via `ParseStatementNodes` into a "get_Name" function (no params, returning the property type). Declines
  a `set` accessor (the get body's `}` is not immediately followed by the property `}`) or an expression-bodied
  `get => …`. `ColumnarStructInput` gains a `Properties` list.
- **Emitter**: PASS 0b' declares each property as a `get_Name` SpecialName instance method (body emitted like a
  method, reading fields via `_currentStruct`), registered in `def.Properties`. case 8 (member read) resolves
  `receiver.Name` to `callvirt get_Name` (vs a field's ldfld). Declines a VALUE-type property and a property name
  colliding with a field/method.

Parity-gated: `ColumnarCodegen_Parity_ClassGetOnlyProperty` value-matches the C# ILCompiler over a computed property
(Doubled), a property over multiple fields (Sum), a property with control flow (Bigger, an if), and property reads
inside expressions (`p.Sum + 1`); metadata-asserts the `get_Doubled` accessor; decline-pinned for a `set` accessor
and a value-type struct property. VERIFY-FIRST confirmed CONSISTENT (both N# and columnar reject): a getter that
doesn't always-return, a property/field NAME COLLISION (NL306), and ASSIGNING a get-only property (NL103). 116
columnar tests green; full non-IDE gate green (fresh isolated). A 2-lens read-only review (parser + soundness)
surfaced one real edge — a property `Double` whose synthesized getter `get_Double` collides with a user method
`get_Double` (the N# pipeline accepts the two as distinct symbols, but two identical-signature CLR methods clash at
CreateType). It was already SAFE (the adapter's try/catch declines on the CreateType throw), but hardened to a
PROACTIVE decline (`def.Methods.ContainsKey("get_" + name)`) + a pinned test. Next: get/SET properties (the setter +
property assignment `p.X = v` → callvirt set_X), then ctor chaining + inheritance.

---

## 2026-06-09 — Phase D-11b-iii: constructor OVERLOADS

Extends the single-constructor slice (D-11b-ii) to multiple overloaded constructors distinguished by PARAM COUNT.
- **Emitter PASS 0c**: loops over ALL of a reference type's constructors (the `Constructors.Count > 1` decline is
  removed), `DefineConstructor` + validating each (NL304 all-fields-assigned + NL103 no-return, per ctor). A
  DUPLICATE-signature ctor (identical param types) declines — the N# binder rejects the duplicate member.
- **Emitter case 15** (positional construction): resolves the overload by arg COUNT — exactly one ctor must have
  that param count; two ctors of the same arity are ambiguous-by-count, so any `new T(...)` with that count declines
  to C# (type-distinguished same-count overloads route to the C# overload resolver). The chosen ctor's args are
  type-checked, then `newobj`.

Parity-gated: `ColumnarCodegen_Parity_ClassConstructorOverloads` value-matches the C# ILCompiler over a `P` with a
2-arg and a 1-arg ctor, each constructed and consumed (Sum/Diff); metadata-asserts two public constructors;
decline-pinned for a duplicate-signature ctor and an ambiguous-by-count construction. Verify-first confirmed C#
accepts count-distinguished overloads (P(5) → the 1-arg ctor). 115 columnar tests green; full non-IDE gate green
(fresh isolated). Next: ctor CHAINING (this/base), then INHERITANCE (the N# pipeline itself rejects object-init of
an inherited field — needs a ctor-based surface), PROPERTIES (need the correct N# property syntax — `X: int { get }`
is NL102).

---

## 2026-06-09 — Phase D-11b-ii: class user CONSTRUCTORS + positional construction

The key class feature: `class Counter { Count: int  constructor(start, step) { Count = start  Step = step } … }`
constructed positionally `new Counter(a, b)`. Spans all three layers, reusing the function-signature/statement
kernels.
- **Kernel** (`ParseStructDeclarationInto`): the field loop now STOPS at an `Identifier (` member (a constructor —
  `constructor` is NOT a keyword, it is an Identifier recognized by text), and the member loop delimits BOTH `func`
  methods and `id (` constructors (recording the ctor's identifier index in a new `outCtorIndices`; outResult[3]=
  ctorCount). New `outCtorIndices` parameter threaded through the delegate.
- **Adapter** (`TryParseColumnarConstructorAt`): verifies the identifier text is literally "constructor", then parses
  the ctor via the EXISTING `ParseFunctionSignature` (a ctor yields name=-1, returnRoot=-1) + `ParseStatementNodes` —
  declining a chaining initializer (`: this(...)`/`base(...)` makes the return-type parse fail). `ColumnarStructInput`
  gains a `Constructors` list.
- **Emitter**: a reference type with a user ctor gets NO default ctor (object-init on it declines — matches the N#
  pipeline, which rejects `new C { … }` with no parameterless ctor). PASS 0c `DefineConstructor(paramTypes)` for a
  SINGLE ctor on a REFERENCE type (declines a 2nd ctor / a struct ctor). PASS 2 emits the ctor body: `ldarg.0; call
  object::.ctor()`, then field assignments (the IsReference field-write path from D-11b-i), then a trailing `ret`.
  case 15 (New): `new C(args)` matches the single ctor by arg count, emits args (type-checked), `newobj <ctor>`.

Two OVER-ACCEPTANCES caught by VERIFY-FIRST (before the review even returned) + fixed with `IsValidReferenceCtorBody`:
(1) NL304 — the N# pipeline requires DEFINITE ASSIGNMENT of every non-nullable field in a ctor; columnar now declines
a ctor that doesn't assign every field (conservative: only top-level `field = expr` counts — a conditionally-
assigned field declines). (2) NL103 — the N# pipeline rejects `return` inside a constructor; columnar now declines a
ctor body containing any Return statement. (All modelled fields are non-nullable — a nullable/composed field type
declines at the kernel — so "assign every field" == NL304 exactly.)

Parity-gated: `ColumnarCodegen_Parity_ClassConstructor` value-matches the C# ILCompiler over Counter (2-arg ctor,
field assignment, Get/Next/Scaled) and Person (string field + arithmetic `Birth = year - age` in the ctor body);
metadata-asserts a single 2-arg ctor with no parameterless ctor; decline-pinned for object-init-on-user-ctor-class,
ctor OVERLOADS, a struct ctor, NL304 partial assignment, and NL103 return-in-ctor. The slice-1a "class-with-ctor
declines" assertion is flipped. A 2-lens read-only review found 0 issues (it read the post-fix code; verify-first had
already caught the only two real bugs). 114 columnar tests green; full non-IDE gate green (fresh isolated). Next:
ctor OVERLOADS + chaining (this/base), then INHERITANCE, properties.

---

## 2026-06-09 — Phase D-11b-i: field WRITE in a reference-type method body

The foundation for constructor bodies (which assign fields): an assignment to a bare field name inside an instance
method/ctor body. The assignment emit (case 23) gains a `_currentStruct.Fields` fallback — `field = expr` →
`ldarg.0; <value>; stfld <FieldBuilder>` (after locals/params, so they shadow; mirrors the bare-field READ).
GATED to REFERENCE types: a value-type (struct) instance call spills the receiver to a TEMP COPY
(TryEmitInstanceCall), so a struct method's field mutation would write the copy, not the caller's variable —
diverging from C#'s in-place value semantics — so struct field-mutation-in-method DECLINES (the receiver-own-address
fix is a later slice). A class/record ref is shared through the temp, so the mutation persists correctly.

Parity-gated: `ColumnarCodegen_Parity_ClassFieldMutationInMethod` value-matches the C# ILCompiler over a class
accumulator (Add/SetTo/Double), mutation PERSISTING across calls on the same ref (two Adds accumulate; mutate-then-
read-field), and a RECORD method that mutates a field (verify-first confirmed the N# pipeline accepts record in-method
field writes — records are NOT init-only for these); decline-pinned for a struct field mutation in a method. The
slice-1a "class field-mutating method declines" assertion is flipped (now supported). VERIFY-FIRST confirmed: a class
`Bump()` and a struct `Bump()` BOTH return 6 in the N# pipeline (the `this.X`-garbage note task_468eee1d was about
EXPLICIT `this.X`, not bare-field `X`), and record in-method mutation returns 6 — so the gate is about value-semantics
PERSISTENCE, not the write itself. 113 columnar tests green; full non-IDE gate green (fresh isolated). Next:
class slice 1b-ii — user CONSTRUCTORS (parse + DefineConstructor + body field-writes via this slice's fallback) +
positional construction `new C(args)`.

---

## 2026-06-09 — Phase D-11a: CLASS slice 1a — the FIFTH user-defined type + reference-type METHODS

Data-driven priority: `class` is the most common construct in the example corpus (41 of 113 N# files, vs record
14 / union 7 / enum 7 / struct 6). Slice 1a lands the foundation, REUSING the record infrastructure.
- **A `class` (token 8) = a RECORD** in the columnar emitter: a reference type (`DefineType` class + a public
  default ctor + public fields), constructed via an object initializer (`new Box { Value: v }`), fields read via
  ldfld on the ref. The parser kernel `ParseStructDeclarationInto` now accepts `class` (8) alongside `struct` (9)
  and `record` (13); the adapter gate permits decl kind 8; `TopLevelClassIndices` collects classes (IsReference=true).
- **NEW: instance METHODS on a REFERENCE type** (class AND record — records previously DECLINED methods). The PASS 0b
  `IsReference && Methods.Count > 0` decline is removed; the body emit is shared with value types (bare field →
  `ldarg.0; ldfld`, valid for both a managed pointer and an object ref); `TryEmitInstanceCall` branches on
  IsReference — a REFERENCE receiver emits `stloc temp; ldloc temp; <args>; callvirt method`, a VALUE receiver keeps
  `ldloca temp; <args>; call`. This unblocks record methods as a bonus.

Parity-gated: `ColumnarCodegen_Parity_ClassObjectInitAndMethods` value-matches the C# ILCompiler over a class with
four methods (field reads + params), a direct field read on the ref, and a RECORD with a method (the unblock);
metadata-asserts the class is a reference type with public instance methods. DECLINES (slice-1a scope, all safe
under-acceptance, verify-first-confirmed): a user `constructor` (the kernel stops at the `constructor` keyword), a
PRIMARY constructor `class C(x)` (the kernel needs `{` after the name), INHERITANCE `class D: Base` (the `:`), and a
method that WRITES a field (the assignment path has no this-field fallback — returns false). Slice 1a is object-init
+ field-READING methods only. Stale decline assertions updated (record-method + bare-class now compile; the enum
test's "non-enum decl declines" now pins an `interface`). VERIFY-FIRST confirmed the whole surface in C# before
building (boxGet/boxPlus/boxSum correct). A 2-lens read-only review CONFIRMED 3 "soundness" findings — a record/class
method named like a synthesized member (`Equals`/`GetHashCode`/`ToString`) supposedly rejected by CS0114 — but
VERIFY-FIRST OVERTURNED ALL THREE (the THIRD review-overturn this session): the N# pipeline ACCEPTS such methods (it
is NOT C#-the-language) and columnar value-matches (callvirt dispatches to the USER method, e.g. a `GetHashCode(): int
{ return X*2 }` returns X*2 on both paths). Pinned as a parity case (`hsh`) so the review's wrong "decline" fix can't
be applied later. 112 columnar/dogfood tests green; full non-IDE gate green (fresh isolated).
Next: class slice 1b — user CONSTRUCTORS (with bodies — field assignment via `ldarg.0; <value>; stfld`) + positional
construction `new C(args)`; then ctor chaining (this/base), inheritance, properties.

---

## 2026-06-09 — Phase D-10c: union BARE TYPE patterns — `Color.Red => …` (union match now complete)

A match arm `Result.Success => …` (NO braces) matches a union case by TYPE without destructuring/binding (the
proven oracle `ILCompiler_CanExecuteUnionMatchWithoutPropertyBinding`). EMITTER-ONLY — a bare `Union.Case` already
parses as a MemberAccess (kind 8, no `{` suffix).
- **`EmitPatternMatch` case 8** now has two branches: the existing `Enum.Member` constant (underlying-int Ceq) and a
  NEW union branch — if `recvName.member` is a registered union case and the match value is that case's union base
  (and `recvName` is not shadowed), emit `ldloc value; isinst Case; brtrue success; br fail` (isinst-only, NO
  binding). Because it binds nothing it is SAFE inside `and`/`or`/`not` combinators (reached by EmitPatternMatch),
  unlike the binding property pattern (kind 37, top-level only).
- **case 18 union exhaustiveness** now counts a bare kind-8 `Union.Case` arm toward coverage (with kind-37 property
  patterns + the kind-6 catch-all). This is the IDIOMATIC way to match a payload-free case (where `Case {}` is NL503).

Parity-gated: `ColumnarCodegen_Parity_UnionBareTypePatterns` value-matches the C# ILCompiler over bare patterns on a
PAYLOAD union (no destructure), a ZERO-FIELD union (Color as a named enum), a MIXED match (bare type pattern + a
property pattern), a bare-arm + `_` catch-all, and `Color.Red or Color.Green` (a bare pattern composed with `or`);
decline-pinned for a non-exhaustive bare match and for an `or`-combinator arm that doesn't make the match exhaustive.
Capstone read-only review (2 lenses + adversarial verify) confirmed 2 findings, BOTH safe-direction (columnar
declines, never over-accepts): (1) the exhaustiveness check doesn't re-check receiver shadowing that the EMIT phase
declines anyway — net decline, harmless (a `func f(c: Color, Color: int)` param shadowing the type, pathological);
(2) the exhaustiveness check ignores combinator arms, declining `Color.Red or Color.Green => …, Color.Blue => …`
(no catch-all). VERIFY-FIRST OVERTURNED the review's suggested fix for (2): C# ALSO rejects that program (NL501
"Pattern matching is not exhaustive" — the C# analyzer likewise ignores `or` coverage), so columnar's decline is
CORRECT; counting `or` coverage would have ACCEPTED a program C# rejects. Duplicate union-case arms verified
consistent (C# accepts the unreachable arm, columnar matches). 112 columnar tests green; full non-IDE gate green
(fresh isolated). LESSON (again): verify-first is the arbiter — it overturned a confident adversarial review for the
SECOND time this arc. **Union MATCH is now complete for the modeled surface**: property patterns, `when` guards,
bare type patterns, zero-field handling (construct + catch-all; `{}` declines), exhaustiveness. Remaining union work
(separate slices): nested/renamed `{ f: <pat> }` sub-patterns, generic unions (needs generics), match STATEMENTS.

---

## 2026-06-09 — Phase D-10b: union match completeness — `when` guards + zero-field cases (+ a soundness fix)

Extends D-10 toward complete union match. Two increments, both verify-first against the C# ILCompiler:
- **`when`-guarded union arms** (EMERGENT — no production change, pinned by a parity test): a union-case pattern
  that binds a field composes with the existing GuardedPattern (kind 19) unwrap, so the binding is in scope when
  the guard is emitted. Verified over multiple guarded arms on one case + an unguarded fallthrough, and a guarded
  arm with a `_` catch-all; a match whose ONLY coverage of a case is a guarded arm correctly DECLINES (NL501 — a
  guard may be false at runtime).
- **Zero-field (payload-free) cases** + a **SOUNDNESS FIX** that verify-first surfaced: C# ALLOWS constructing a
  payload-free case (`new Color.Red {}` — an empty object initializer) and matching it via a catch-all (or a bare
  type pattern, not modelled), but REJECTS destructuring one with a `{ }` property pattern (NL503 — "doesn't carry
  any data"). The committed D-10 `EmitUnionCasePattern` was emitting an `isinst`-only test for `Case {}` on a
  zero-field case — ACCEPTING a program C# refuses (an over-acceptance vs the parity oracle, which the D-10
  3-lens review missed because it never probed payload-free cases). FIX: `EmitUnionCasePattern` declines when
  `caseDef.Fields.Count == 0`. Construction + catch-all match of zero-field cases value-matches C#; the `Case {}`
  property pattern now declines, matching NL503.

Parity-gated: `ColumnarCodegen_Parity_UnionMatchWhenGuards` (guarded arms, value-matched, + the guarded-only-coverage
decline) and `ColumnarCodegen_Parity_UnionZeroFieldCases` (zero-field construct + catch-all value-matched, + the
`Case {}`-on-payload-free decline). A TARGETED read-only over-acceptance re-review (2 soundness lenses — construction
+ pattern/exhaustiveness — + adversarial verify), run specifically because the D-10 review missed the zero-field
gap: its single candidate (`Case { value, value }` duplicate binding) was refuted — columnar already declines it via
the shadowing guard, matching C#'s NL019. No remaining union over-acceptance. 111 columnar tests green; full non-IDE
gate green (fresh isolated). LESSON: verify-first against the C# oracle is the real soundness backstop — it caught
what a 7-agent adversarial review did not, because the review reasoned about the code while verify-first exercises
the actual analyzer. Next union work: nested/renamed `{ f: <pat> }` sub-patterns, bare type patterns, generic unions
(needs generics).

---

## 2026-06-09 — Phase D-10: UNION — the FOURTH user-defined type (the rich-type-system centerpiece)

The columnar backend gains DISCRIMINATED UNIONS — declaration, object-initializer construction, and union-case
match patterns (the feature that motivated rich match support). Emitted exactly like the C# ILCompiler's
`DeclareUnion`: an ABSTRACT base reference class + one SEALED NESTED case class per case.
- **Parser kernel** (`ParseUnionDeclarationInto`, ParserDeclarations.nl): parses `union Name { Case { f: T, … } … }`
  into flat parallel arrays — per-case name + per-case field-count, with fields flattened across cases (the host
  re-segments via the counts). Declines (→ C#) a bare case with no `{ }` body, a composed/generic field type, a
  generic union (the `<` after the name), or an empty union.
- **Parser pattern** (ParserExpressions.nl): a `<Union.Case> { bind0, bind1, … }` suffix on a MemberAccess (kind 8)
  pattern leaf → UnionCasePattern (kind 37), children `[memberAccess, bind0 (Identifier), …]`. Bare-identifier
  bindings only; a renamed/positional `{ f: <pat> }` declines (the `:` is neither `,` nor `}`). Composes with the
  existing `when`-guard wrapper. Sits below the or/and/not chain so a union-case pattern under a combinator declines.
- **Adapter** (`NSharpCompilerDogfoodAdapter`): the gate permits decl kind 12; `TopLevelUnionIndices` +
  `TryGetColumnarUnionInputs` collect each union into a `ColumnarUnionInput` (name + per-case names + per-case field
  names/type-canonicals); `ParseUnionDeclarationInto` delegate wired into `Bindings`.
- **Emitter** (`ColumnarIlEmitter`): a NEW union PASS 0 builds, per union, an abstract base
  `DefineType(Public|Class|Abstract, object)` with a protected (`Family`) parameterless ctor, and per case a
  `DefineNestedType(NestedPublic|Class|Sealed, base)` with a public parameterless ctor chaining to the base + a
  public field per case field. (Trivial ctor bodies emitted inline, as the spike proved.) `ColumnarUnionDef`/
  `ColumnarUnionCaseDef` registries: `_unionRegistry` (name→base, for `Union`-type resolution + exhaustiveness),
  `_unionCaseRegistry` (qualified "Union.Case"→case, for construction + patterns). `TryResolveType` resolves a bare
  union name to its base. **Construction** (case 36, before the struct/record branch): `newobj <case ctor>; per
  field dup; <value>; stfld`, reporting the expression's STATIC type as the union BASE (an upcast — the runtime
  object is the concrete case; a later match recovers it via `isinst`). **Match** (`EmitUnionCasePattern`, dispatched
  only at an arm's TOP LEVEL from case 18): `ldloc value; isinst Case; dup; brtrue ok; pop; br fail; ok: stloc; per
  binding ldfld + stloc` into a fresh local; the stack is empty at both labels (matching every other pattern).
  **Exhaustiveness** (case 18): a union match must cover every case or carry an unguarded catch-all, else decline
  (C# reports NL501). Nested case types are finalized BEFORE their base (deepest-first, matching the C# ILCompiler's
  `OrderTypeBuildersByDescendingTypeKeyDepth`).

Parity-gated: `ColumnarCodegen_Parity_UnionConstructAndMatch` value-matches the C# ILCompiler over int cases (the
canonical `Result`, via make-returns-base helpers), string-field cases with the SAME field name across cases
(binding collision), a MULTI-FIELD case alongside a single-field one (heterogeneous arity), and a `_` catch-all arm;
metadata-asserts the base is abstract + the case is a sealed nested class deriving from it with a public int field;
decline-pinned for a non-exhaustive match without catch-all, a renamed sub-pattern, a non-field binding, and a
generic union. Adversarially reviewed (read-only, 3 lenses — soundness/IL/parser — + per-finding judges): 4 parser
candidates ALL refuted with code-grounded mechanism (st[2] not corrupted on decline; field-array writes bounded by
n/2 < n+1 + `pos>=count` guards; the `{…}` binding loop exits at `}` so a `when` guard parses cleanly; partial field
binding matches C#'s analyzer). Soundness + IL lenses found nothing. 109 columnar tests green; full non-IDE gate
green (fresh isolated). Next: union slice 2 — when-guarded union arms over bindings, nested/renamed patterns,
generic unions; then generics/lambdas/exceptions toward Phase S.

---

## 2026-06-09 — Phase D-9a: RECORD — the THIRD user-defined type (a reference type)

Records reuse the struct infrastructure with an `IsReference` flag — the same decl kernel, object-init parsing, and
type registry, branching only where value-type vs reference-type IL differs.
- **Parser kernel**: `ParseStructDeclarationInto` now accepts the `record` keyword (token 13) as well as `struct` (9)
  — the body syntax is identical.
- **Adapter**: the gate permits decl kind 13; `TopLevelRecordIndices` + `TryGetColumnarStructInputs` collect records
  (`IsReference=true`) alongside structs (`IsReference=false`) into one input list.
- **Emitter** (`ColumnarIlEmitter`): PASS 0 — a record is `DefineType(Public|Class, object)` + a public
  `DefineDefaultConstructor`; a struct stays `Public|Sealed, ValueType`. `ColumnarStructDef` carries `IsReference` +
  the record's `DefaultCtor`. Object-init (case 36) branches: a record emits `newobj <ctor>; per field dup; <value>;
  stfld` (the ref is the result); a struct keeps `ldloca; initobj; stfld; ldloc`. Field read (case 8) branches: a
  record reads `ldfld` directly on the ref (no address spill); a struct spills + `ldloca; ldfld`. Record field
  MUTATION and record METHODS DECLINE this slice (records may be init-only; record methods need a ref-`this` shape).

Parity-gated: `ColumnarCodegen_Parity_RecordFieldsAndObjectInit` value-matches the C# ILCompiler over field sum/first,
reversed-order + arithmetic init, partial init (default 0), and a string-field record (`.Length`); metadata-asserts the
type is a CLASS with public int fields; decline-pinned for a record method, a record field mutation, and a `class`
decl. Adversarially reviewed (read-only, 2 lenses + judge) → SHIP, no in-scope defects (all 5 reviewer claims
empirically refuted: primary-ctor records / char→int / name collisions all decline). A raw-Reflection.Emit spike
de-risked the reference-type construction. 77 columnar tests green; full non-IDE gate green (fresh isolated). Next:
record methods + mutation, then UNION (the rich-type-system centerpiece — gates union-case match patterns).

---

## 2026-06-09 — Phase D-8d: struct instance methods WITH PARAMETERS

Extends D-8c (parameterless methods) to methods that take arguments.
- **Emitter** (`ColumnarIlEmitter` PASS 0b): a method's params now resolve to types and `DefineMethod` declares them;
  the per-method ordinal map shifts user params by +1 (arg 0 is the value-type `this`), so inside the body a bare
  name resolves param-before-field (a param shadows a like-named field, matching C#). `ColumnarStructDef.Methods`
  carries the param types. The instance call `r.m(args)` spills the receiver, `ldloca temp`, emits each arg (type-
  checked against the declared param type), then `call` — arg count must match.
- No parser/adapter change: the method-delimit + `TryParseColumnarFunctionAt` path from D-8c already parses a full
  signature (params included).

Parity-gated: `ColumnarCodegen_Parity_StructInstanceMethod` extended with one- and two-parameter methods
(`scaled(k)`, `plus(dw, dh)`) value-matched vs the C# ILCompiler over several argument sets, alongside the
parameterless cases. 76 columnar tests green; full non-IDE gate green (fresh isolated). Next: mutating struct methods,
static methods; then record/union toward the rich type system.

---

## 2026-06-09 — Phase D-8c: struct INSTANCE METHODS (parameterless, bare-field, value-returning)

The columnar backend gains BEHAVIOR on user types — the emit model now supports instance methods on a user struct.
- **Parser kernel** (`ParseStructDeclarationInto`): after the fields, a method-delimit loop records each method's
  `func` token index (`outMethodFuncIndices`) and balanced-brace-scans its body — it does NOT parse the sig/body
  itself. Method count in `outResult[2]`. Fields-then-methods; declines a body-less / expression-bodied method, a
  field after a method, a `static func` (keyword token, not a field).
- **Adapter** (`TryGetColumnarStructInputs`): parses each method via `TryParseColumnarFunctionAt` — the SAME
  signature + statement-body kernels as a top-level func — so a struct method body is a `ColumnarFunctionInput`.
- **Emitter** (`ColumnarIlEmitter`): PASS 0b declares each method as an INSTANCE method (`DefineMethod`,
  Public|HideBySig, no Static) on the struct TypeBuilder (after all struct types exist; param/void methods decline; a
  method NAME colliding with a field declines — NL306). PASS 2 emits method bodies (before the struct CreateType) with
  a new `_currentStruct` context: a bare name that is neither a local nor a param resolves to a FIELD via
  `ldarg.0; ldfld` (`this` = arg 0; locals/params still shadow). An instance call `r.area()` spills the receiver,
  `ldloca; call <MethodBuilder>` (non-virtual, parameterless).
- **C# oracle caveat** (verified before building, flagged as task_468eee1d): C# only compiles BARE-field + object-init
  correctly — `this.X` field access returns garbage and ctor construction is wrong in the C# ILCompiler — so those
  forms DECLINE (the slice builds on bare-field access, which the oracle gets right).

Parity-gated: `ColumnarCodegen_Parity_StructInstanceMethod` value-matches the C# ILCompiler over multiple methods on
one struct, multiple structs, and constant/field-derived returns; metadata-asserts the instance method; decline-pinned
for `this.X`, a param method, a void method, a field-after-method, and a field/method name collision. Adversarially
reviewed (read-only, 3 lenses + judge) → the judge caught the field/method name-collision over-acceptance (now fixed;
other claims empirically refuted, incl. that a struct method's bare call matches the N# binder's top-level resolution).
A raw-Reflection.Emit spike de-risked the structural unknown (instance MethodBuilder body survives CreateType+Save).
76 columnar tests green; full non-IDE gate green (fresh isolated). Next: methods with params, mutating methods, then
record/union toward the rich type system.

---

## 2026-06-09 — Phase D-8b: struct field MUTATION + (locking in) struct passing & nested fields

- **Emitter** (`ColumnarIlEmitter` case 23, assignment): a struct field write `local.Field = value` on a `:=` LOCAL
  struct receiver now emits `ldloca <local>; <value>; stfld <FieldBuilder>` (mutate in place). The receiver must be a
  bare-identifier local of a registered struct; a PARAM receiver, a nested receiver (`p.q.X`), or a non-struct/
  non-field target declines → C# fallback.
- **No new code needed** for two capabilities the type plumbing already provided (confirmed by probe + the slice-8a
  review): a struct PARAM + RETURN across sibling functions (`make(): Point` / `dot(p: Point)`), and NESTED
  struct-typed fields (`o.In.V`). This slice adds parity TESTS that lock them in.

Parity-gated: `ColumnarCodegen_Parity_StructMutationAndPassing` value-matches the C# ILCompiler over read-modify-write
and direct field sets on a local struct, a struct round-trip through sibling `make`/`dot`, and nested struct-typed
field reads; decline-pinned for a param-receiver mutation. (C# acceptance of struct field mutation verified before
implementing — `bump(5)` = 6.) 75 columnar tests green; full non-IDE gate green (fresh isolated). Next struct slices:
param-receiver mutation, struct methods, primary constructors; then record/union toward the rich type system.

---

## 2026-06-09 — Phase D-8a: STRUCT — the SECOND user-defined type (fields + object-init + field read)

The columnar backend gains value-type structs, reusing the enum type-emission architecture.
- **Parser kernel**: `ParseStructDeclarationInto` (`ParserDeclarations.nl`) parses a fields-only
  `struct Point { X: int  Y: int }` — name + `{` + a sequence of `Identifier : <single builtin-token type>` fields
  (no separator; newlines are stripped, so fields are detected by the repeating `name : type` pattern) until `}`.
  Declines primary-ctor `(`, methods, field initializers `=`, composed field types, empty bodies. `ParserExpressions.nl`
  gained OBJECT-INITIALIZER parsing in the New-expr branch: `new <type> { Field: value, ... }` →
  `ObjectInitializerExpression` kind 36, children `[typeRoot, name0 (Identifier kind 6), value0, …]`. (C# REJECTS
  positional `new Point(a, b)` for a fields-only struct — object-init is the only valid construction, verified.)
- **Emitter** (`ColumnarIlEmitter`): a PASS 0 (after enums) calls `module.DefineType(name, Public|Sealed, ValueType)`
  + `DefineField` per field (matching C#'s `DeclareStruct` — no `SequentialLayout`), building a `structRegistry`
  (name → `TypeBuilder` + `FieldBuilder` map); structs `CreateType()` after enums, before the Program type.
  `TryResolveType` resolves a struct name to its `TypeBuilder`; `IsSupportedType` admits `t is TypeBuilder`;
  `IsSupportedValueTuple` excludes it (struct-in-tuple declines, like enums). Case 36 constructs:
  `ldloca temp; initobj struct; per field: ldloca temp; <value>; stfld <FieldBuilder>; ldloc temp` (unknown/dup/
  type-mismatched field declines). Case 8 reads a struct field: spill the receiver, `ldloca; ldfld <FieldBuilder>`.
  FieldBuilders are stored at DefineField and used directly (never `GetField`, which throws on a TypeBuilder).
- **Adapter**: the gate permits decl kind 9; `TopLevelStructIndices` + `TryGetColumnarStructInputs` collect each
  struct; the emit stays in the try/catch (declines on any Reflection.Emit surprise).

Parity-gated: `ColumnarCodegen_Parity_StructFieldsAndObjectInit` value-matches the C# ILCompiler over field sum/first,
reversed-order + arithmetic-valued init, and partial init (unset field = 0 via `initobj`), plus metadata assertions
(IsValueType, `ValueType` base, fields X/Y:int in order); decline-pinned for positional ctor / method / field
initializer / primary-ctor struct. Adversarially reviewed (read-only, 3 lenses + judge: parser/obj-init, emitter IL,
parity/over-accept) → SHIP, no in-scope defects (assignment-valued init declines = C# parity; nested struct-typed
fields emergently work). 74 columnar tests green; full non-IDE gate green (fresh isolated). Next struct slices: field
mutation `p.X = v`, struct param/return across funcs, then methods / primary ctors.

---

## 2026-06-09 — Phase D-7c: ENUM `(int)` conversion + explicit member values — enums COMPLETE

The final enum slice — observe the underlying int, and honor explicit values.
- **Emitter** (`ColumnarIlEmitter` case 16, cast): an `EnumBuilder` cast operand is treated as its underlying
  `int` (an i4-underlying enum is its int on the stack), so `(int)c` is identity (no opcode) and `(long)c`/`(double)c`
  widen exactly like `int`→that type via the existing target-driven conversion switch. A non-numeric cast target
  (string/bool) and the reverse `(Color)5` int→enum cast still decline (TryResolveBuiltin doesn't know enums).
- **Adapter** (`TryGetColumnarEnumInputs`): explicit `= N` member values are now honored, computed via C#'s exact
  rule (`ILCompiler.NestedTypes.cs` ~415): `nextValue=0`; an explicit member sets its value AND resets
  `nextValue=value+1`; an implicit member takes the running `nextValue` (`A=5, B, C=20, D` → 5,6,20,21). A
  non-decimal/overflowing literal declines (`int.TryParse`); negative/hex/underscore values decline at parse or
  collect (safe C# fallback, no value divergence).

Parity-gated: `ColumnarCodegen_Parity_EnumIntCastAndExplicitValues` value-matches the C# ILCompiler over `(int)`/
`(long)` of auto-incremented AND explicit enums, and pins the explicit values 5/6/20/21 by invoking the compiled
methods. (Note: for `(int)enum`, columnar emits no opcode while C# emits a redundant `conv.i4` — different IL, but a
verifiable no-op yielding the identical value, so the value-matching oracle holds.) Adversarially reviewed (read-only,
2 lenses + judge: cast parity, explicit-value algorithm) → SHIP, no in-scope defects (the value algorithm byte-matches
C#; cast/decline edges all safe). 73 columnar tests green; full non-IDE gate green (fresh isolated). **ENUMS COMPLETE**
(declaration, member access, typing, param/return/local, match patterns + exhaustiveness, `(int)` casts, explicit
values). Next user-defined type: struct.

---

## 2026-06-09 — Phase D-7b: ENUM in match patterns (`match c { Color.Red => … }`) + exhaustiveness decline

Enums become first-class match scrutinees.
- **Parser kernel** (`ParserExpressions.nl`): the match-pattern precedence chain's leaf now bottoms out at
  `ParsePostfixExpressionNode` (was `ParsePrimaryExpressionNode`) — the columnar analogue of C#'s
  `ParseRelationalPattern` falling back to `ParsePrimaryExpression` (which includes postfix member access). This lets
  `Enum.Member` parse as a MemberAccess (kind 8) in pattern position; literals/identifiers/discards parse identically
  (no postfix to apply); calls/indices parse but the emitter declines them.
- **Emitter** (`ColumnarIlEmitter`): `IsSupportedMatchValueType` admits `EnumBuilder`; `EmitPatternMatch` gained a
  kind-8 case — a registered-enum `Enum.Member` (matching the scrutinee's enum, not shadowed) emits
  `ldloc; ldc.i4 <value>; ceq; brtrue/br` (underlying-int equality, mirroring C#'s Beq-on-underlying-int). Enum
  constants compose with `or`/`and`/`not` for free (the recursive helper recurses into kind 8).
- **Exhaustiveness DECLINE gate** (found by the adversarial review): C# rejects a non-exhaustive enum match (NL501).
  The columnar match emit now DECLINES an enum match that lacks a catch-all AND does not cover every member via
  top-level unguarded `Enum.Member` arms — so columnar never accepts a program C# refuses (→ C# fallback reports
  NL501). This is a DECLINE (route to the analyzer-backed C# path), not a duplicated diagnostic; production already
  analyzes before columnar (so this is defense-in-depth + harness consistency). Guarded/combinator arms conservatively
  don't count toward coverage (a richer-but-exhaustive form simply declines, still correct).

Parity-gated: `ColumnarCodegen_Parity_EnumMatch` builds AND consumes the enum inside one pipeline (int-in/string-out,
since the two `Color` types are distinct), value-matching C# over enum-constant arms, `or`/`not` over enum constants,
and a full-coverage no-catch-all match. Decline-pinned: a non-enum member access, a PARTIAL enum match (NL501);
accept-pinned: full coverage and catch-all. Adversarially reviewed (read-only, 2 lenses + judge: parser-leaf
divergence, enum-pattern emit) → the judge caught the exhaustiveness over-acceptance (now fixed). 72 columnar tests
green; full non-IDE gate green (fresh isolated). Next: `as int` / explicit values (sub-slice C), then struct.

---

## 2026-06-09 — Phase D-7a: ENUM declarations — the FIRST user-defined TYPE (declaration + member access + typing)

The columnar backend was FUNCTIONS-ONLY (the adapter rejected any top-level declaration kind ≠ 7=func). This slice
adds the first user-defined TYPE, establishing the type-emission architecture (define types in a new pass-0, resolve
them for functions) that struct/record/union will reuse.
- **Parser kernel** (`ParserDeclarations.nl`): new `ParseEnumDeclarationInto` parses `enum Name { A, B, C }` (and the
  explicit-value form `A = N`) into flat member arrays — enum name span, member name spans, optional value spans +
  hasValue flags — mirroring `Parser.cs ParseEnumDeclaration` for the int-enum subset. (`enum`→14 was already
  classified by `TopLevelDeclarationKindsInto`.)
- **Adapter** (`NSharpCompilerDogfoodAdapter.cs`): the func-only gate now also permits `enum` (decl kind 14);
  `TopLevelEnumIndices` + `TryGetColumnarEnumInputs` collect each enum into a `ColumnarEnumInput` (name + member
  names + auto-incremented `0,1,2,…` values), declining the whole program on any explicit `= N` value (sub-slice C).
  The emit call is now wrapped in a try/catch so a columnar emit failure always DECLINES → C# fallback, never a hard
  error.
- **Emitter** (`ColumnarIlEmitter.cs`): a new PASS 0 calls `module.DefineEnum(name, Public, int)` + `DefineLiteral`
  per member, building an `enumRegistry` (name → `EnumBuilder` + constants); enum builders are `CreateType()`'d just
  before the Program type. `TryResolveType` resolves a bare enum name to its `EnumBuilder` (the SAME instance used for
  member access, so reference-equality return/assign checks hold); `IsSupportedType` admits `EnumBuilder`; case 8
  member access emits `ldc.i4 <value>` for `Enum.Member`. Enum-as-array-element and enum-in-tuple DECLINE (their
  Reflection.Emit member resolution is unsupported on a TypeBuilder), keeping enums scalar-only this slice.

Pinned: `ColumnarCodegen_Enum_DeclarationAndMemberAccess` — member access as a value, enum-typed param + `:=` local
round-trips, the `0,1,2` underlying ints (compared to the C# pipeline via `Convert.ToInt32`, since the two `Color`
types are distinct CLR types), `Enum.GetNames`/underlying-type assertions; decline-pinned for explicit values, a
`struct` decl, and enum-in-tuple (value + deconstruct). Adversarially reviewed (read-only, 3 lenses + judge: emitter
type lifecycle, adapter collection/gate, parser + parity) → found + FIXED the enum-in-tuple hard-error (now a clean
decline). 100 columnar/tuple tests green; full non-IDE gate green (fresh isolated, 308s). Next: enum in match
patterns (sub-slice B), then `as int` / explicit values (sub-slice C); then struct/record/union.

---

## 2026-06-09 — Phase D-6e: `match` `and`/`or`/`not` combinator patterns (+ C# ILCompiler stack-discipline FIX)

Completes the scalar pattern ALGEBRA, and fixes a real pre-existing IL bug in the C# reference pipeline.
- **Parser kernel** (`ParserExpressions.nl`): a pattern is now parsed by a precedence chain mirroring the C#
  `ParsePattern` — `ParseMatchPatternNode` → or (token 56, `OrPattern` kind 34) → and (55, `AndPattern` kind 33) →
  not (57, `NotPattern` kind 35) → relational (kind 32) → primary. or/and are left-associative; not recurses
  (depth-guarded). Combinator children are `[left, right]` / `[inner]`. A `when` guard still attaches to the whole
  pattern (54 isn't an or/and/not token, so the chain stops before it).
- **Columnar emitter** (`ColumnarIlEmitter`): a NEW recursive `EmitPatternMatch(node, type, matchLocal,
  successLabel, failLabel)` — reads the value from the `matchLocal` (no stack dup), branching to success on match /
  fail on no-match. `and` = left-then-right, `or` = short-circuit on left, `not` = swap the labels. The match arm
  (case 18) keeps the top-level identifier binding/discard inline and routes every other pattern through the helper.
  Bindings inside combinators decline (→ C# fallback), matching C#'s restriction.
- **C# ILCompiler FIX** (`ILCompiler.cs` `EmitPatternTest` And/Or/Not): the reference combinator emit `Dup`'d the
  scrutinee but left the SPARE copy on the stack on the branch that went straight to the outer success/fail label,
  producing unverifiable IL → **`InvalidProgramException` at JIT for EVERY and/or/not pattern** (match expressions
  AND switch statements). Fixed by routing each exit through a cleanup label that `Pop`s the spare copy before
  branching, so every path nets −1 (consumes exactly the scrutinee), making the leaf contract hold inductively under
  nesting. This was discovered BY this slice: the columnar emit was correct, but the parity oracle threw — the C#
  pipeline was the broken one.

Parity-gated: `ColumnarCodegen_Parity_MatchCombinators` value-matches the C# ILCompiler over `and`/`or` of relationals
and literals, or-chains, `not` over a relational and a literal, a combinator under a `when` guard, and boundary
values; decline-pinned for a binding (`0 or x`) and a non-literal leaf (`(0) or 1`). Independent C#-pipeline pin:
`CSharpILCompiler_MatchCombinatorPatterns_EmitValidIL` (incl. nested `not < 0 and not > 10`). Adversarially reviewed
(read-only, 3 lenses + judge: C# stack discipline, columnar recursive emit, parser precedence) → SHIP, no in-scope
defects (the stack discipline hand-verified net −1 on all paths). 413 + 2 match/pattern/switch/columnar tests green;
full non-IDE gate green (fresh isolated, 310s). **Scalar pattern algebra COMPLETE.** Next: type declarations (enum).

---

## 2026-06-09 — Phase D-6d: `match` relational patterns (`< c`, `<= c`, `> c`, `>= c`)

Extends match patterns with relational comparisons against a constant.
- **Parser kernel** (`ParserExpressions.nl`): a relational operator (`<` 100 / `<=` 101 / `>` 102 / `>=` 103) at the
  start of a pattern slot parses the operand (a primary) and emits a `RelationalPattern` node kind 32 — operator in
  the value span, 1 child = the operand. (`>=` is a single token, no `>`-split.) Bare/literal/identifier patterns are
  unchanged; a `when` guard still composes (kind 19 over a kind-32 inner).
- **Emitter** (`ColumnarIlEmitter` case 18, relational arm): requires an ORDERED match type (`IsOrderedMatchType` —
  int/long/ulong/char/double/float, NOT bool/string) and a LITERAL operand (`IsLiteralPatternKind`), then
  `ldloc matchLocal; <operand>;` and a switch that MIRRORS the C# `EmitPatternTest` RelationalPattern lowering
  EXACTLY — plain ordered `Clt`/`Cgt` for ALL types (no `_Un` float/unsigned variants): `<`/`>` skip the arm on a
  false compare (`Brfalse nextCase`), `<=`/`>=` are the negations and skip on a true compare (`Brtrue nextCase`).
  Identical opcodes ⇒ columnar value-matches C# even on NaN and large ulong.

Parity-gated: `ColumnarCodegen_Parity_MatchRelational` value-matches the C# ILCompiler over all four operators on
int/long/char/double/**float**, chained `>=` arms (first-match-wins), relational MIXED with a literal arm and a
`when`-guarded arm, boundary values, and **NaN inputs** (which agree precisely because the lowering is identical).
Decline-pinned: a non-literal operand (`< k`), and relational over string/bool (unordered) → C# fallback.
Adversarially reviewed (read-only, 3 lenses + judge: opcode/NaN parity, parser correctness, accept/decline boundary)
→ SHIP, no in-scope defects (the float arm proven live by the `fband` case). Full non-IDE gate green (fresh
isolated, 309s). Next: `and`/`or` combinator patterns, then type declarations (enum first).

---

## 2026-06-09 — Phase D-6c: harden match patterns (decline non-literal patterns)

A correctness fix closing the over-acceptance hole surfaced by the `when`-guard adversarial review. The match-arm
emitter modelled exactly two pattern shapes — LITERAL (int/float/char/string/bool, node kinds 0-4) and IDENTIFIER
(`_` discard / binding, kind 6) — but the literal branch ran for ANY non-identifier pattern node, blindly emitting
`ldloc; <expr>; ceq`. The pattern parser (`ParsePrimaryExpressionNode`) can yield other primaries — parenthesized
`(0)` (kind 7), member access (8), call (9), index (10), null (5) — so e.g. `match n { (0) => … }` compiled a bogus
equality test even though the C# pipeline REJECTS it (C# parses `(0)` as a positional pattern → `NL103` on a scalar).
- **Emitter** (`ColumnarIlEmitter` case 18): the literal branch now first checks `IsLiteralPatternKind` (kinds 0-4);
  a non-literal, non-identifier pattern node declines (`return false`) so the whole match falls back to the C#
  pipeline, which emits the proper diagnostic — never a silently-wrong program. This also covers the same hole
  reached through a `when`-guarded slot (kind 19 wrapping a non-literal inner pattern).

Pinned: `ColumnarCodegen_MatchPattern_NonLiteralDeclines` asserts `(0)` / member / call / guarded-`(0)` patterns
decline while literal + identifier + literal-under-guard patterns still accept; the existing `Parity_MatchExpression`
and `Parity_MatchGuard` value-matching is unchanged (no modelled pattern lost). Full non-IDE gate green (fresh
isolated, 309s). Next: relational patterns (`< 0`, `>= 100`), then range patterns, then type declarations.

---

## 2026-06-09 — Phase D-6b: `match` `when` guards (`<pattern> when <bool>`)

Extends the match-expression slice with guard clauses without touching the match node's `[value, pat, res, …]`
encoding.
- **Parser kernel** (`ParserExpressions.nl`): in the match-case loop, after parsing a pattern (primary expr), a
  `when` (token 54) introduces a guard — parsed via `ParseAssignmentExpression` — and the pattern is wrapped in a new
  `GuardedPattern` node kind 19, children `[pattern, guard]`, which occupies the pattern slot. A bare pattern (no
  `when`) is unchanged (no wrapper), so existing cases keep their exact shape.
- **Emitter** (`ColumnarIlEmitter` case 18): each case's pattern slot is unwrapped — a kind-19 node yields the inner
  pattern + a guard node, else the guard is absent. The inner pattern is tested exactly as before (identifier
  discard/binding always-matches; literal `ldloc; <lit>; ceq/op_Equality; brfalse nextCase`). THEN, if guarded, the
  guard (a `bool`, with the pattern's binding already in `_locals` so it may reference it) is emitted and
  `brfalse nextCase`. A guarded catch-all is NOT exhaustive, so the trailing no-match throw stays reachable. Mirrors
  the C# `EmitMatchExpression` (store-binding-then-guard) path; non-`bool` guards and unsupported guard exprs decline.

Parity-gated: `ColumnarCodegen_Parity_MatchGuard` value-matches the C# ILCompiler over guards on binding patterns
(`x when x > 0`), a literal pattern with a guard falling through to the bare-literal case, a guard reading an outer
parameter, a guard calling `char.IsDigit`/`IsLetter` on the bound char, and an all-guarded match. (The C# reference
parser parses `when <ident> =>` as a lambda, so the test writes `flag == true` not bare `flag`; the columnar kernel
handles either — out-of-scope reference-parser quirk.) Adversarially reviewed (read-only, 3 lenses + judge:
binding-scope, IL stack/control-flow, C#-parity) → SHIP, no in-scope defects. The review also surfaced a
PRE-EXISTING over-acceptance (the literal-pattern branch emits a `ceq` for ANY non-identifier primary — `(0)`, calls,
member access — which C# rejects); hardened next. Full non-IDE gate green (fresh isolated, 310s). Next: harden the
pattern branch to decline non-literal patterns, then relational/range patterns.

---

## 2026-06-09 — Phase D-6: `match` expressions (first pattern class — literal/discard/binding over scalars)

The first slice of pattern matching: `match value { pattern => result, … }` as an EXPRESSION over scalars/strings.
- **Parser kernel** (`ParserExpressions.nl`): `ParsePrimaryExpressionNode` gained a `match` branch (Match token 31)
  parsing the value (`ParseAssignmentExpression`, stops at `{`), then cases — each a PRIMARY-expression pattern,
  `=>` (Arrow 120), and a result — comma-separated, `}`-closed → `MatchExpression` node kind 18, children
  `[value, pat0, res0, pat1, res1, …]`. ≥1 case required; state restored on every failure.
- **Emitter** (`ColumnarIlEmitter` case 18): mirrors the C# `EmitMatchExpression` linear chain — eval value (a
  supported scalar/string) → temp; per case: an identifier pattern is a catch-all (`_` discard, or any other name
  BINDS a local = the matched value, scoped to that arm), a literal pattern emits `ldloc temp; <literal>; ceq` (or
  `string.op_Equality`) `; brfalse nextCase`; then the result (all arms share one result type) + `br end`. After
  all cases: `throw new InvalidOperationException(...)` (the C# no-match path). Leaves one result on the stack.
  Richer patterns (union-case/property/relational/`when` guards) decline → C# fallback.

Parity-gated: `ColumnarCodegen_Parity_MatchExpression` value-matches the C# ILCompiler over int/bool/char/string
literal patterns, the `_` discard, and an identifier binding (`x => x*2`), incl. catch-all and grade-table forms.
Adversarially reviewed (read-only, parser + emit lenses). All 95 dogfood tests green. Next match slices: `when`
guards, relational/range patterns, then union-case patterns (gated on union types). Then properties/exceptions.

---

## 2026-06-09 — Phase D-5b: tuple DECONSTRUCTION `a, b := f()` — tuples are now COMPLETE

The idiomatic completion of tuple multi-return.
- **Parser kernel** (`ParserStatements.nl`): `ParseSimpleStatementNode` gained a branch — an Identifier followed by
  a Comma begins a deconstruction. It collects each bare-identifier target (emitted as an Identifier node kind 6 so
  the name lives in the value span), requires `:=`, parses the value expression, and emits a
  `TupleDeconstructionStatement` node kind 30 with children `[name0, …, nameN-1, value]`. A non-identifier target /
  missing `:=` / missing value refuses (state restored) → declines to the C# parser.
- **Emitter** (`ColumnarIlEmitter` case 30): emits the value (a `ValueTuple`), stores it to a temp, requires the
  tuple arity to equal the target count, then for each non-`_` target declares a local of the `ItemN` field type
  and `ldloca temp; ldfld ItemN; stloc` — mirroring the C# `EmitTupleDeconstruction` plain path. `_` targets are
  discards (skipped, but still advance the `ItemN` index). The Go-style `name, err := …` 2-target form declines
  (the C# ILCompiler emits that error path specially — never diverge from it).

Parity-gated: `ColumnarCodegen_Parity_TupleDeconstruction` value-matches the C# ILCompiler over deconstructing a
tuple LITERAL and a CALL result (`lo, hi := minMax(a)`), `_` discards, mixed int+string, chained use, and the
`, err` decline. Adversarially reviewed (read-only, parser + emit lenses). All 94 dogfood tests green. **Tuples
are now COMPLETE** (expressions + `.ItemN` + types + multi-return + deconstruction). Next: match.

## 2026-06-09 — Phase D-5: tuples — expressions + `.ItemN` + tuple TYPES + MULTI-RETURN (the complete core)

The complete core tuple feature (two sub-slices landed together), so tuples cross function boundaries — not a
crippled locals-only half-version. Deconstruction (`a, b := f()`) is the remaining ergonomic follow-on.

- **Tuple expressions** (`ParserExpressions.nl`): inside the `(` handling, after the cast-speculation rollback and
  the first inner expr, a `,` makes it a tuple — elements collected on the LIFO arg-stack → `TupleExpression`
  kind 17. Emitter case 17 emits each element then `newobj` the `ValueTuple<...>` ctor; MemberAccess case 8 now
  handles `.ItemN` (`Ldfld` on the value-type receiver) alongside `.Length`. Positional only.
- **Tuple TYPES** (`ParserTypeReferences.nl`): `ParseBaseTypeReferenceNode` gained a `(` branch → `(T0, T1, …)`
  (≥2 elements, `)`-terminated) → `TupleTypeReference` node kind 6. A single `(T)` or a NAMED `(x: int, …)`
  refuses. The `(int,int)` canonical is produced IDENTICALLY by the kernel's `ColumnarTypeCanon` (case 6) and the
  C# parity oracle `ColumnarFunctionSymbol.CanonicalType` (so the symbol-parity model agrees), and the emitter's
  `TryResolveType` parses it back into a `System.ValueTuple<…>` (arity 2–7) by splitting top-level commas
  (`SplitTopLevelCommas`, depth over `()`/`<>`/`[]`) and `MakeGenericType`. `IsSupportedType` admits supported
  ValueTuples.
- **Multi-return**: `func f(): (int, int) { return (a, b) }`, tuple PARAMS, a tuple as a sibling-call argument,
  and a returned tuple consumed by another function all work — the `ValueTuple` from `MakeGenericType` (param/
  return) is Type-identical to the one the tuple-expression emit produces, so the return-type and call-arg checks
  match.

Parity-gated: `ColumnarCodegen_Parity_TupleExpression` (2/3-tuples, nested, mixed elements, `.Item2.Length`) +
`ColumnarCodegen_Parity_TupleMultiReturn` (return/param/sibling-arg/consumed-tuple/mixed) value-match the C#
ILCompiler. Adversarially reviewed (read-only — sub-slice 1: parser+emit → SHIP; sub-slice 2: tuple-type parser +
the 3-site canonical agreement + `TryResolveType`). All 93 dogfood tests green (two stale parser-pin assertions
updated — `(1, 2)` and `(int, string)` now parse instead of being refused). Next: tuple deconstruction
`a, b := f()`, then match.

## 2026-06-08 — Phase D-4: `foreach` over arrays (N# parser kernel + emitter index-loop lowering)

The second two-sided slice. `foreach <var> in <array> { body }` (the no-paren, Go-style form).
- **Parser kernel** (`ParserStatements.nl`): a `foreach` branch (Foreach token = 26) parsing the var name
  (Identifier) + `In` (28) + collection expression (`ParseAssignmentExpressionNode`, stops at `{`) + body →
  columnar node kind 29, the loop-variable name in the VALUE SPAN, children `[collection, body]`. A parenthesised
  `foreach (x in y)`, or a missing var/`in`/body, refuses → declines to the C# parser.
- **Emitter** (`ColumnarIlEmitter` case 29): lowers to the SAME index loop the C# ILCompiler's `EmitForeachForArray`
  emits — `arr := collection; i := 0; check: if i >= arr.Length goto end; <var> := arr[i]; body; cont: i = i+1;
  br check; end:`. `continue` → increment, `break` → end. ARRAY collections only (the element load picks
  `Ldelem_I4/I8/U2/R8/R4/Ref` by element type; int/long/ulong/char/double/float/string); a non-array collection
  (e.g. a string iterated as chars) declines → C# fallback. Loop var + body locals are loop-scoped; declines if
  the var shadows an existing local/param or the body always-returns.

Parity-gated: `ColumnarCodegen_Parity_ForeachLoop` value-matches the C# ILCompiler over int[]/string[]/double[]
elements, early `return`, `continue`, `break`, foreach CONTAINING a for, and the non-array + always-returns
declines. Adversarially reviewed (read-only, parser + lowering lenses). All 91 dogfood tests green. Next: tuples
or match per the retirement map.

## 2026-06-08 — Phase D-3: C-style `for` loops — the FIRST two-sided slice (N# parser kernel + emitter)

The first rich-language construct needing BOTH the N# parser kernel AND the emitter (the scalar slices were
emitter-only — the kernel already parsed them). Establishes the two-sided pattern for the remaining Phase-D work
(foreach/tuples/match/structs).

- **Parser kernel** (`ParserStatements.nl`, itself systems-N# compiled to the dogfood assembly): `ParseStatementCoreNode`
  gained a `for` branch (For token = 25) that parses `for <init>; <cond>; <incr> { body }` → columnar node kind 28,
  children `[init, cond, incr, body]`. init/incr parse via `ParseSimpleStatementNode` (a `:=` decl or assignment
  expr-statement), cond via `ParseAssignmentExpressionNode`, each clause separated by a required `Semicolon` (133);
  a missing `;`/clause/body refuses with -1 → declines to the C# parser. Mirrors the proven `while` branch (child-run
  captured AFTER the sub-parses; contiguous 4-node run). Token ordinals verified empirically (For=25, Semicolon=133
  — the naive line-offset would have given 137; gaps in the enum).
- **Emitter** (`ColumnarIlEmitter` case 28): `init; check: cond; brfalse end; body; cont: incr; br check; end:`.
  `continue` targets the INCREMENT (`contLabel`, then re-test — C# for-loop semantics, vs `while`'s direct re-test);
  `break` targets the end. The loop variable + body locals are scoped to the loop (removed after, so a second
  `for i := 0` re-declares `i`); an outer local (e.g. `total` before the loop) is preserved. A body that ALWAYS
  returns (never falls through) is declined (degenerate — the increment would be unreachable).

Parity-gated: `ColumnarCodegen_Parity_ForLoop` value-matches the C# ILCompiler over counting loops, array iteration,
`continue` (→increment), `break` (→end), NESTED for (inner/outer loop-label discipline), SEQUENTIAL for re-declaring
`i`, early `return` from the body, and a count-down (`i = i - 1`); plus the always-returns-body decline. Adversarially
reviewed (read-only, 3 lenses: parser kernel, emit semantics, control-flow edges). All 90 dogfood tests green. Next:
foreach (array iterator), then tuples/match per the retirement map.

## 2026-06-08 — Phase D-2: `float` scalar (r4) in the columnar emitter — completes the numeric-scalar tier

A per-construct parse-vs-emit probe (route each candidate, check `TryGetColumnarFunctionInputs` parse vs
`RouteColumnarProgram` emit) showed `float` is the only remaining EMITTER-ONLY rich construct — tuples, for,
foreach, struct decls all parse=False (need N# parser-kernel work). float directly mirrors the just-shipped double:
`IsSupportedType`/`IsSupportedElementType` admit float + float[]; the FloatLiteral case now narrows an f/F-suffixed
literal to `Ldc_R4 (float)value` (a bare/d-suffixed literal stays double; m/M decimal declines); FP `+-*/%`, `Neg`,
NaN-correct comparisons (the existing `isFloat` complement path now covers float too), target-driven casts
(→float=`Conv_R4`, float→int=`Conv_I4`, float↔double via Conv_R4/Conv_R8), and float[] `Ldelem_R4`/`Stelem_R4`.
Mixed float+double / float+int still DECLINE (no implicit widening — operand types must match).

Parity-gated: `ColumnarCodegen_Parity_FloatScalar` value-matches the C# ILCompiler over NaN/±Inf, all comparisons,
casts in 4 directions (incl. `d2f` double→float overflow→+Inf and NaN→int), float[] read + new+write+read, f-literals,
and the mixed-type + bare-literal-as-float declines. Not separately heavy-reviewed — it's a mechanical r4 mirror of
the double slice (already adversarially reviewed: same FP comparison/cast/literal logic, R4 opcodes). All 89 dogfood
tests green (the multi-function "ineligible function" example moved float→decimal, still unmodelled). The numeric
scalar tier (int/long/uint?/ulong/char/double/float) is now columnar-complete; the next ILCompiler-retirement slices
(for/foreach/tuples/match/structs) require N# parser-kernel work.

## 2026-06-08 — Phase D-1: `double` scalar (r8) in the columnar emitter — first rich-language coverage toward retiring the C# ILCompiler

A 7-agent read-only landscape map (what columnar already replaces, gating deps, the #1 next slice) picked `double`
as the highest-leverage, lowest-risk first Phase-D slice: bounded, IEEE-754-standardized, fully parity-gateable,
matching the existing int/long/ulong scalar pattern. A per-construct probe confirmed the N# parser kernel ALREADY
parses double types + float literals (FloatLiteral = node kind 1) — so this is a pure EMITTER slice (no kernel
work). (Note: this reverses the self-host-only "skip double" guidance — correct, since the goal is now covering
the whole language to retire C#, not just the dogfood corpus.)

Added to `ColumnarIlEmitter`: `IsSupportedType`/`IsSupportedElementType` admit double + double[]; a FloatLiteral
case (`Ldc_R8`; parses via `TryParseDoubleLiteral` mirroring the C# `ParseFloatLiteralValue` — strip a d/D suffix,
drop `_`, invariant parse; an f/F float or m/M decimal suffix DECLINES); unary `Neg` on r8; FP `+-*/%` (double is
NOT unsignedDivRem, so plain `Div`/`Rem` are IEEE FP — x/0.0→±Inf, 0.0/0.0→NaN, no throw); NaN-CORRECT comparisons
(`EmitComparison` gained an `isFloat` flag — `<`/`>` use ordered Clt/Cgt, but `<=`/`>=` negate the UNORDERED
complement Cgt_Un/Clt_Un so a NaN operand yields false, matching C#'s `a<=b ⇒ !(a cgt.un b)`; `==`/`!=` use Ceq);
target-driven casts matching the C# `TryGetNumericConversionOpcode` (→double=Conv_R8, →long=Conv_I8, →char=Conv_U2,
long/double→int=Conv_I4); double[] `Ldelem_R8`/`Stelem_R8`/`Newarr`. Mixed int+double still DECLINES (no implicit
widening — the operands' types must match), as do bitwise/shift on double and float/decimal.

Parity-gated: `ColumnarCodegen_Parity_DoubleScalar` value-matches the C# ILCompiler over 50+ cases — every
arithmetic op with NaN/±Inf/signed-zero, all 6 comparisons with NaN on each side, negate, casts in 4 directions
(incl. NaN→int and large double→long), double[] read + new+write+read, float literals, and the int+double / `3.5f`
declines. Adversarially reviewed (read-only, 3 lenses: IEEE/NaN semantics, casts+literals, decline surface). All
88 dogfood tests green (one now-stale assertion updated: the multi-function "ineligible function" example switched
from double, now supported, to float/Single, still unmodelled). Unlocks vectorization examples + float benchmarks;
the next ILCompiler-retirement slices are for/foreach, then tuples/match/structs (per the retirement map).

---

## 2026-06-08 — Phase C: never-slower benchmark — columnar emit backend is end-to-end TIED-to-marginally-faster vs C# (REAL numbers)

Added `ColumnarBackendEmitBenchmarks` — the Phase-C never-slower gate. It compiles a systems-subset program
end-to-end (parse → analyze → emit → save) BOTH ways through the SAME production entry
(`MultiFileCompiler.CompileToIlAssembly`), toggling only `NSHARP_COLUMNAR_BACKEND`. Because parse + analyze are
byte-identical between the two runs, the measured end-to-end delta IS the backend difference. Setup asserts the
flag genuinely re-routes (the two backends emit DIFFERENT IL, both succeed), so `Columnar=true` truly measures
the columnar path, not a silent C# fallback.

**MEASURED (BenchmarkDotNet default job, Apple M4, .NET 10):**
| Corpus | C# `ILCompiler` | columnar backend | result |
|---|---|---|---|
| Representative (2 funcs) | 3.963 ms | 3.947 ms | columnar 0.4% faster (CIs overlap → tied) |
| LargeGenerated (40 funcs) | 21.520 ms | 21.193 ms | columnar 1.5% faster |

Allocations identical (~1.54 MB / ~22.5 MB). **NEVER-SLOWER holds: columnar ≤ C# on both corpora.** The columnar
path RE-PARSES via the kernels (on top of the C# parse+analyze the production pipeline already ran) AND emits,
yet still costs LESS than the C# `ILCompiler` emit alone — i.e. (columnar kernel-parse + table-driven emit) <
(C# AST-walking emit). The margin is small because the SHARED parse+analyze dominate the end-to-end total; the
emit swap is the only delta. The large end-to-end win is deferred to Stage 6, when the columnar pipeline OWNS
parse+analyze and the C# front-end is eliminated entirely (gated on Phase D rich-language coverage).

STRATEGIC READ: the never-slower gate PASSES, so the roadmap's flip-`NSHARP_COLUMNAR_BACKEND`-default-on is
unblocked on perf grounds. But the end-to-end benefit of flipping is only ~0.4–1.5% (the emit is a small slice of
the total), so the flip trades a marginal speedup for a production-wide decline-safety risk surface + a change to
the flag's default semantics. Whether to flip now vs. keep it opt-in until the columnar front-end ownership lands
is a judgment call surfaced to the user (the roadmap pre-decided "flip" assuming a larger emit win than measured).

## 2026-06-08 — Phase B: route multi-file through columnar in production + DELETE the parser-front-end dead-end route (~1205 net LOC removed)

Two Phase-B slices. (1) **Multi-file production routing:** `MultiFileCompiler.TryEmitWithColumnarBackend` was
single-file-only — a multi-file program fell back to the C# ILCompiler even with `NSHARP_COLUMNAR_BACKEND=1`. It
now gathers every source in `_sourceFiles` order and routes >1 file through `TryEmitColumnarProgramMultiFile`
(the already-parity-tested merge); a single file still uses the single-file entry. Gated by
`Stage5_ColumnarBackend_RoutesEligibleMultiFileProgramThroughProduction` (a 2-file program with a cross-file
public call compiled BOTH ways through the production path — columnar IL differs from C#, the cross-file call
resolves + runs identically). Flag off by default → production unchanged.

(2) **Deleted the deliberately-off `NSHARP_PARSER_FRONTEND` route** — the materialize-the-columnar-tables-back-
into-the-C#-AST path (`NSharpCompilerDogfoodAdapter.TryParseCompilationUnit` + `ParserFrontEndRoutingEnabled` +
the `ColumnarAstMaterializer` class + the `Parser.ParseCompilationUnit` hook + the `CompilationUnitRoutingBenchmarks`
+ the `Materializer_*`/`Router_*` tests + their `RouteCompilationUnit`/`StructuralJson`/`WriteStructural` helpers).
It was a MEASURED dead-end (~4.4× slower / ~18× more allocation — materializing re-incurred the full C# AST
allocation on top of the table cost; see the removed benchmark's own header) and is superseded by the standalone
columnar backend, which consumes the columnar tables DIRECTLY. Parse correctness is now validated by the columnar
symbol/type/diagnostic parity tests + the emit backend (parses + emits the whole corpus, value-matched vs C#),
so the materialize-to-AST oracle is redundant. Shared pieces preserved: the kernel binding delegates +
`RoutingCorpusSources` (relocated to `benchmarks/RoutingCorpusSources.cs` for `ColumnarSemanticPassBenchmarks`),
and `CSharpCompilationUnit` (still the parity reference for the live columnar kernel tests). Net **~1205 LOC
removed** (529 benchmark + 240 materializer + 184 adapter + 323 test + 13 parser, −84 relocated). All 87 dogfood
tests + the full gate green; zero production behavior change (the route was off by default). Directly serves
AGENTS.md "shrink/remove the *DogfoodAdapter bridges."

## 2026-06-08 — implicit-void return type (`func f(...) {`) → SemanticScopes.nl: **the systems-dogfood corpus is now 32/32 via merge** (single-file 28→29, cluster 31→32)

The LAST parse-blocked file falls — Phase A self-host coverage COMPLETE. SemanticScopes.nl declined at PARSE
(`TryGetColumnarFunctionInputs` returned false). A per-function parse probe (reflect the private parse entry, route
each of the 20 funcs solo, tag parse-fail vs emit-fail) pinned two procedures — `SemanticScopeSortIdsByStart`
(an iterative quicksort) and `SemanticScopeClearTouchedCore` — that OMIT the return type: `func name(params) {` with
no `: ReturnType` (implicit void). A synthetic `func f(a: int[]) {` reproduced it; `func g(a: int[]): void {`
parsed fine — isolating the construct to the omitted return type.

ROOT CAUSE was the C# adapter, NOT the N# kernel: `ParseFunctionSignatureInto` (ParserFunctionSignatures.nl)
correctly sets `returnRoot = -1` for an omitted return type (it starts -1 and is only assigned when a `:`
colon token is present; a FAILED type-parse returns -1 for the WHOLE function, so paramCount goes negative).
But `TryParseColumnarFunctionAt` (NSharpCompilerDogfoodAdapter.cs) treated `sres[1] < 0` (the returnRoot) as a
parse failure and called `ColumnarTypeCanon(..., sres[1])` unconditionally. FIX: drop `sres[1] < 0` from the
failure guard and canonicalize `sres[1] >= 0 ? ColumnarTypeCanon(...) : "void"` — mirroring the symbol/type
services (`TryInferTopLevelFunctionTypes` already did `sres[1] >= 0 ? canon : "void"`). The emitter already
maps a "void" ReturnCanonical → typeof(void) (the void-functions slice), so no emitter change was needed: with
the parse fixed, SemanticScopes compiled end-to-end with NO additional emit gap.

Parity-gated: `ColumnarCodegen_Parity_ImplicitVoidFunctions` (implicit-void `fillWith` fall-through + `clearIf`
value-less early `return`, each driven by a non-void caller that allocates its OWN array from an int arg so
there's no shared-mutable-state across the columnar/oracle runs; plus the value-bearing-return-in-void decline)
and the milestone `ColumnarCodegen_CompilesRealDogfoodFile_SemanticScopes` (`BuildSortedIndexChecksumInto`
exercises the implicit-void quicksort transitively, value-matched vs the C# pipeline). Adversarially reviewed
(read-only workflow, 2 lenses + judge). Ratchets: single-file floor 28→29, multi-file cluster 31→32. **Corpus
coverage now 29/32 single-file, 32/32 (100%) via multi-file merge** — the 3 still-not-single-file files
(ParserExpressions/ParserFunctionSignatures/ParserStatements) are legitimately CROSS-FILE (they call public
functions in sibling files) and compile when merged; nothing in the corpus is unmodeled. **Phase A DONE.**

## 2026-06-08 — Math.Abs + int.ToString(fmt) + string concat + String.Compare(3/6-arg) + Trim + StringBuilder params → DiagnosticClusters.nl (single-file 27→28, cluster 30→31)

The LAST emit-blocked systems-dogfood file falls. The roadmap predicted DiagnosticClusters.nl needed "exactly"
four BCL features; a per-function STUB probe (route each of the 49 funcs solo, tag leaf-vs-sibling-call declines)
found the four PLUS two the construct-scan missed — string concatenation and a StringBuilder PARAMETER type:
1. **`Math.Abs(int)→int`** (static `call`); **`String.Compare`** 3-arg `(string,string,StringComparison)` and
   6-arg `(string,int,string,int,int,StringComparison)` → int (the `StartsWithIgnoreCase` sub-range prefix check);
   **`string.Trim()→string`** (instance `callvirt`, parameterless).
2. **`int.ToString(string)→string`** — the first VALUE-TYPE instance call. `Int32.ToString(string)` needs a
   managed-pointer `this`, so the receiver int (already on the stack) is spilled to a temp local and `ldloca`'d,
   then the format string is pushed and `call`ed. `.ToString("x")` (lowercase hex) is the `FormatDiagnosticClusterId`
   small-buffer path; the parity test PROVES the format overload (255 → "ff", not the decimal "255").
3. **string concatenation** `s1 + s2 → String.Concat(string,string)` — the binary `+` case only handled numerics;
   `opType==string && op=="+"` now emits Concat (the exact line-554 shape `"diag-" + Math.Abs(hash).ToString("x")`).
   Only string+string is modelled; string+int etc. still decline (the opType gate rejects the mix).
4. **`StringBuilder` as a param/return type** — the root single-file blocker. StringBuilder was modelled as a
   `new`-created local/return and admitted by `IsSupportedType`, but `TryResolveType` (which resolves param/return
   CANONICAL strings in pass 1) only knew builtins, so a function taking `builder: StringBuilder` IN (e.g.
   `AppendQuotedDiagnosticCommandArgument`) declined the whole program at pass 1. `TryResolveType` now maps the
   canonical `"StringBuilder"` → `typeof(StringBuilder)`; it is resolved there (param/return/local), NOT in
   `TryResolveBuiltin`, so `StringBuilder[]` stays unsupported (array elements gate through TryResolveBuiltin /
   IsSupportedElementType, which exclude it).

Flips `DiagnosticClusters.nl` (1505 lines, 49 funcs). Parity-gated: `ColumnarCodegen_Parity_MathAbsCompareTrimToString`
(absInt; hex PROVES "x" hex-format; diagId the literal+hex concat shape; cmpCI PROVES OrdinalIgnoreCase ("ABC","abc")→0;
startsCI the 6-arg sub-range; trimmed) and the milestone `ColumnarCodegen_CompilesRealDogfoodFile_DiagnosticClusters`
(`FormatDiagnosticClusterId` over both buffer paths, `StartsWithIgnoreCase`, `IsDiagnosticClusterRootBefore`,
`NormalizeDiagnosticMessagePattern`, `ContainsIgnoreCase` — value-matched vs the C# pipeline). Adversarially reviewed
(read-only workflow, 3 lenses + judge → SHIP): IL/stack balance correct (Ldloca+Call, not Callvirt, for the value-type
ToString; temp local cannot alias a named local), every added overload binds exactly what the C# binder picks, and the
decline surface has no holes (string+int / StringBuilder[] / Trim-on-non-string / wrong-arity Compare all decline).
Ratchets: single-file floor 27→28, multi-file cluster 30→31. Coverage now **28/32 single-file, 31/32 via multi-file
merge (~97%)** — only `SemanticScopes` (parser-kernel-blocked) remains for 32/32.

## 2026-06-08 — StringComparison enum + IndexOf overloads + char/int promotion → CliArguments.nl (single-file 26→27, cluster 29→30)

A per-function stub probe of `CliArguments.nl` (4125 lines, 83 funcs) — after adding the obvious string features
— left ONE culprit, `CliExportCSharpFirstOperandChecksumInto`, on `checksum + arg[i] * (i + 1)`: a `char * int`
mix. Three features land:
1. **`StringComparison` enum** — the corpus' only enum. `StringComparison.Ordinal`/`.OrdinalIgnoreCase`/… is a
   MemberAccess whose receiver names the enum TYPE (not a value); it emits `ldc.i4 <underlying value>` (an enum
   IS its underlying int on the stack; values 0–5 per the documented enum) typed `StringComparison`.
2. **`string.IndexOf` overloads** — `IndexOf(char)` (1-arg) and `IndexOf(string, StringComparison)` (2-arg,
   distinguished from `IndexOf(char, int)` by the first arg's type) → int. The case-insensitive "contains" idiom
   `text.IndexOf(part, StringComparison.OrdinalIgnoreCase) >= 0`.
3. **char/int NUMERIC PROMOTION** (ECMA §12.4.7) — the blanket same-type binary-operator gate became a promotion:
   int and char are BOTH i4 on the stack, so a char/int mix promotes both to int with NO conversion IL (an
   `opType` drives the opcode + result type). long/ulong/bool/string still require exact match (an int/long mix
   would need a conv the backend doesn't emit → declines safely). This makes `c * (i+1)`, `c + n`, `c < n`,
   `c == n` work as int, matching the C# binder's GetWiderType (Analyzer.cs:12820); char-char arithmetic→int and
   char comparison-signed behavior is preserved.

Flips `CliArguments.nl` (the heaviest CLI file). Parity-gated: `ColumnarCodegen_Parity_StringComparisonAndIndexOf`
(the case-insensitive containsCI cases PROVE the OrdinalIgnoreCase=5 value — a wrong value would flip the match),
`ColumnarCodegen_Parity_CharIntPromotion` (weight `s[i]*(i+1)`, char±int, char</>== int with negatives), and the
milestone `ColumnarCodegen_CompilesRealDogfoodFile_CliArguments` (`CliSymbolNameContainsAsciiIgnoreCase` +
`CliExportCSharpFirstOperandChecksumInto` value-matched vs the C# pipeline). Updated a now-stale `IndexOf('a')`
1-arg decline assertion (it's supported now). Adversarially reviewed (read-only, 2 lenses): NO wrong promotions
(only char/int → int; all other mixes decline safely, none emit i4/i8-mismatched IL), enum values correct,
IndexOf dispatch correct, same-type behavior preserved, tests discriminating + non-vacuous. Ratchets: single-file
floor 26→27, multi-file cluster 29→30. Coverage now **27/32 single-file, 30/32 via multi-file merge (~94%)** —
only `DiagnosticClusters` (needs Math.Abs + String.Compare + Trim + ToString(fmt) atop the now-modeled
StringBuilder/StringComparison/void) and `SemanticScopes` (parser-kernel-blocked) remain.

## 2026-06-08 — `StringBuilder` (first mutable reference type) → CompletionReceivers.nl (single-file 25→26, cluster 28→29)

Added `System.Text.StringBuilder` — the columnar backend's first MUTABLE reference type with instance methods:
`new StringBuilder()` / `new StringBuilder(int capacity)` (`newobj`); `.Append(char|string|int)` (the overload is
bound by the ARGUMENT'S columnar type — exact-match reflection, so `Append(char)` appends one char while
`Append(int)` appends the DECIMAL text, matching the C# binder's exact-overload pick); `.Clear()`; `.ToString()`
→ string; `.Length` → int. The fluent `.Append(...)`/`.Clear()` result (a StringBuilder) is normally discarded
as a statement — the existing bare-call-statement path `pop`s it. `IsSupportedType` admits StringBuilder (valid
local/param/return) but NOT `IsSupportedElementType` (no StringBuilder[] arrays). Unmodeled Append arg types,
other ctor overloads, other methods (Insert/Remove/Replace/AppendLine), and non-StringBuilder `new Foo(...)` all
DECLINE (C# fallback).

This flips `CompletionReceivers.nl`, whose `NormalizeCodeIntelligenceCompletionReceiverCalls` builds a normalized
receiver string into a `new StringBuilder(end - start)` via `Append(char)` + `ToString()` (also a while-scan loop
with continue — relying on the prior slice). Parity-gated: `ColumnarCodegen_Parity_StringBuilder` (buildChars
Append(char); wrap mixing char+string Append → "(abc)"; appendInts PROVING `Append(int)` is DECIMAL text "012"
not char code points; lenAfter `.Length`; clearIt `.Clear()`) and the milestone
`ColumnarCodegen_CompilesRealDogfoodFile_CompletionReceivers` (the real paren-normalizer over nested-paren inputs,
value-matched vs the C# pipeline). Adversarially reviewed (read-only, 2 lenses): Append/ctor/dispatch/`.Length`
all match the C# pipeline (exact-type reflection binding is deterministic and picks the same overloads), the
decline surface is comprehensive, tests discriminating + non-vacuous. Ratchets: single-file floor 25→26,
multi-file cluster 28→29. Coverage now **26/32 single-file, 29/32 via multi-file merge (~91%)**.

## 2026-06-08 — `while` scan loops (always-transferring body) → IdentifierSpans.nl (single-file 24→25, cluster 27→28)

A per-function stub probe (route each function with stub siblings so only the intrinsic gap remains) pinpointed
`IdentifierSpans.nl`'s lone blocker: `IsCodeIntelligenceSnapFriendlyNeighbor`, a `while` SCAN loop that
`continue`s past whitespace/punctuation and `return`s on the first other char (`while i <= end { if skippable {
i++; continue } return false } return true`). Its body always-TRANSFERS (every path `continue`s or `return`s),
so the emitter's `AlwaysReturns(body)` was true — and case 26's blanket `if (AlwaysReturns(body)) return false;`
WRONGLY declined it as a "degenerate run-once loop," even though the `continue`s make it a real iterating scan.

Fixed: removed the blanket decline; the bottom back-edge `br check` is now emitted ONLY `if (!AlwaysReturns(body))`
— i.e. only when the body can FALL THROUGH to it. A body that always-transfers never falls through, so the
bottom `br` would be dead code; skipping it both ADMITS the scan-loop pattern AND avoids emitting unreachable IL.
The loop still iterates because `continue` branches directly to `checkLabel`. Soundness rests on a proven
invariant (adversarially verified): `AlwaysReturns(block)==true` ⟹ the block's only always-returning child is its
LAST (the "transfer must be last" rule rejects any earlier one) ⟹ no fall-through. This also makes the previously
-declined degenerate `while c { return X }` form compile correctly (run-once; `c false` → exit, no missing
iteration, no dead code).

Flips `IdentifierSpans.nl` (1841 lines, 56 funcs — pure int/char/array otherwise). Parity-gated:
`ColumnarCodegen_Parity_WhileAlwaysReturnsBody` (a `continue`-scan `firstTrue` that PROVES iteration — `{0,0,1,0}`
→ 2 requires scanning past two leading zeros; `allSkippable`; the degenerate `runOnce`) and the milestone
`ColumnarCodegen_CompilesRealDogfoodFile_IdentifierSpans` (the real scan function + char classifiers value-matched
vs the C# pipeline). Updated the spike's now-stale `degen`-declines assertion (it compiles now). Adversarially
reviewed (read-only, 2 lenses): the back-edge logic is correct for scan/run-once/normal/nested/braceless bodies,
the IL is valid (the dogfood tests load+invoke it), tests are discriminating + non-vacuous. Ratchets: single-file
floor 24→25, multi-file cluster 27→28. Coverage now **25/32 single-file, 28/32 via multi-file merge (~88%)**.

## 2026-06-08 — `void` functions (procedures) → DiagnosticDeduplication.nl (single-file 23→24, cluster 26→27)

Diagnosed the last "0-feature but declines" mystery: `DiagnosticDeduplication.nl` is pure int/int[] EXCEPT its
heapsort helpers `SortDiagnosticDeduplicationIndices` / `SiftDownDiagnosticDeduplicationIndices` return `void`
(they mutate index arrays in place, called as statements). The emitter's `TryResolveType("void")` failed, so
the WHOLE program declined at pass 1 — invisible to the construct-scan since `void` is a return type, not an
expression form. Added void-function support (the function-emission CONTRACT now distinguishes value vs void):
- Pass 1: `ReturnCanonical == "void"` → `returnType = typeof(void)` (void is valid ONLY as a return type; it is
  NOT admitted by `IsSupportedType`, which gates params/locals/array-elements/values — so void can't leak).
- New `EmitBody(bodyRoot, isVoid)`: a VALUE function still REQUIRES `AlwaysReturns` (NL305) then emits; a VOID
  function emits the body, then a trailing `ret` IFF it can fall through (`!AlwaysReturns`) — so an
  always-returns void body gets no trailing `ret` (no unreachable code), and a fall-through one ends in exactly
  one reachable `ret`.
- Return (kind 20): in a void function a value-less `return` emits a bare `ret`; a value-bearing `return`
  declines (arity mismatch). (Value functions unchanged: value required, type-checked.)

Flips `DiagnosticDeduplication.nl`. Parity-gated: `ColumnarCodegen_Parity_VoidFunctions` (all three void shapes —
falls-through while-loop body, value-less early `return`, a void sibling invoked as a STATEMENT — with a
non-void `driver` observing the in-place mutations so the EFFECTS are verified, plus the value-bearing-return
decline) and the milestone `ColumnarCodegen_CompilesRealDogfoodFile_DiagnosticDeduplication` (the real file's
`DiagnosticDeduplicateStableChecksumInto` exercises the void heapsort, value-matched vs the C# pipeline).
Adversarially reviewed (read-only, 2 lenses): void emission is CORRECT + VERIFIABLE for every body shape (the
C# ILCompiler emits the trailing `ret` identically), void cannot leak into a value context, the value-function
always-return contract is preserved, and the tests are non-vacuous. Ratchets: single-file floor 23→24,
multi-file cluster 26→27. Coverage now **24/32 single-file, 27/32 via multi-file merge (~84%)**. (`DiagnosticClusters`
also has 4 void funcs but needs StringBuilder/Math too; `IdentifierSpans` has 0 void funcs — its decline is a
still-separate gap.)

## 2026-06-08 — lowercase `char.` static predicates (+ IsLetter/IsDigit) → LexerTokenKindScanner.nl (single-file 22→23, cluster 25→26)

`char`/`int`/`string` are NOT reserved keywords in N# — they lex as plain Identifiers (confirmed: no Char/Int
keyword token in Token.cs; the lexer's keyword table doesn't special-case them) and bind to the builtin types
by context. So a static call `char.IsDigit(c)` arrives columnar-ly as a Call whose MemberAccess receiver is an
Identifier node with text `"char"` — but `TryEmitStaticCall` only matched `"Char"` (capital, the System.Char
type name via `using System`), declining the lowercase alias. Fixed: accept BOTH `"Char"` and `"char"` (they
bind to the same System.Char in N#/C#), and added `IsLetter`/`IsDigit` to the Char static whitelist (alongside
the existing IsLetterOrDigit/IsWhiteSpace/ToLowerInvariant/ToUpperInvariant).

This flips `LexerTokenKindScanner.nl` (all 31 functions — its char classifiers `IsIdentifierStart`/`IsDigit`/
`IsHexDigit`/etc. mirror the C# lexer's BCL `char.Is*` predicates; the earlier "for"/concat hits in it were all
comments). Parity-gated: `ColumnarCodegen_Parity_LowercaseCharStatics` (lowercase `char.IsLetter/IsDigit/
IsWhiteSpace/IsLetterOrDigit/ToLowerInvariant` + capital `Char.IsLetter` over letters/digits/whitespace/punct)
and the milestone `ColumnarCodegen_CompilesRealDogfoodFile_LexerTokenKindScanner` (the real file's classifiers
value-matched vs the C# pipeline). Small, low-risk slice (whitelist + alias acceptance) — the parity oracle
directly verifies each predicate's result, so no separate adversarial workflow. Ratchets: single-file floor
22→23, multi-file cluster 25→26. Coverage now **23/32 single-file, 26/32 via multi-file merge (~81%)**.

## 2026-06-08 — `ulong` scalar (unsigned) + `BitOperations.PopCount` → CliQueryParsing.nl (single-file 21→22, cluster 24→25)

Added `ulong` — the first UNSIGNED scalar. It is u8 on the stack like `long` (i8), but its operations use the
UNSIGNED opcodes, matching the C# binder (`ulong` promotes to `ulong`, ECMA §12.4.7) and the C# ILCompiler's
`UsesUnsignedNumericOpcode` path exactly: `>>` → `Shr_Un` (logical, zero-fill, NOT the signed `Shr`), `/` →
`Div_Un`, `%` → `Rem_Un`, ordering `< > <= >=` → `Clt_Un`/`Cgt_Un` (the `<=`/`>=` via `!(a>b)`/`!(a<b)`); `<<`,
`& | ^`, `==`/`!=` share long's opcodes (bit-identical). `~` is allowed (Not); unary `-` DECLINES (C# forbids
unary minus on unsigned). `ulong` literals (a `u`/`U` AND `l`/`L` suffix in any order — UL/LU/…) load via
`Ldc_I8(unchecked((long)value))` (the bit pattern; bare `u`/`U` = uint still declines). `ulong[]` reads/writes
reuse `Ldelem_I8`/`Stelem_I8` (8-byte slot; unsignedness is purely in how the value is operated on). Casts
involving `ulong` and mixed `ulong`/other-type operands DECLINE (C# fallback). Added
`System.Numerics.BitOperations.PopCount(ulong)` → int to the static-call whitelist.

This flips `CliQueryParsing.nl`, whose packed-result kernels store success bits in `ulong[]` words, mask a
partial last word via `(word << shift) >> shift` (exercising `Shr_Un`), and sum `BitOperations.PopCount` over
the words. Parity-gated: `ColumnarCodegen_Parity_ULong` — every operator tested with a HIGH-BIT-SET value
(> long.MaxValue) so a wrong SIGNED opcode would diverge (e.g. `0x8000…UL >> 1` logical 0x4000… not signed
0xC000…; `0x8000…UL < 1UL` is FALSE unsigned but TRUE signed), plus `ulong.MaxValue` literal, `ulong[]` read,
`~`, and the unary-minus / cast declines — and the milestone `ColumnarCodegen_CompilesRealDogfoodFile_CliQueryParsing`
(the product file: `CliBatchResultPackedSuccessCount` over high-bit-set words and
`CliBatchResultPopCount64`; the parity source now owns `CliTryParsePositionInto` and
`CliQueryIsWhiteSpace`). Adversarially reviewed (read-only, 2 lenses): every unsigned
opcode matches the C# ILCompiler with file:line evidence (15604/15618/15652…), the literal matches
`EmitUnsignedIntegerLiteralMagnitude`, the tests are discriminating + non-vacuous, declines are safe. The one
implementation difference (`Ldelem_I8` vs the C# generic `Ldelem` for `ulong[]`) is benign — same bit pattern,
both verifiable, empirically parity-confirmed (identical to how `long[]` already ships). Ratchets: single-file
floor 21→22, multi-file cluster 24→25. Coverage now **22/32 single-file, 25/32 via multi-file merge (~78%)**.

## 2026-06-08 — `new string(char[], int, int)` ctor → CliDocOrdering.nl (single-file 20→21, cluster 23→24)

Added the `String(char[] value, int startIndex, int length)` constructor — the columnar backend's first
constructor invocation (`newobj`). In `EmitExpression`'s New case (kind 15), a Simple type node (kind 0) named
`string` with 3 args now emits the char[] arg + two int args then `newobj instance void
System.String::.ctor(char[], int32, int32)` → string. (The array-alloc path — an Array type node, kind 2 — is
unchanged; the `String(char,int)` repeat overload and any other constructor decline.) This flips
`CliDocOrdering.nl`, whose slug builder copies filtered/lowercased chars into a `char[]` buffer and returns
`new string(buffer, 0, slugLength)` — everything else it uses (string indexing, `(int)`/`(char)` casts, capital
`Char.IsLetterOrDigit`/`ToLowerInvariant`, int[]/string[]/char[], `new char[]`) was already modelled, and all
its calls are self-defined siblings (no cross-file dep).

Parity-gated: `ColumnarCodegen_Parity_StringFromChars` (full-buffer + sub-slice + empty char[] + the
`new string('a', 3)` repeat-ctor decline) and the milestone `ColumnarCodegen_CompilesRealDogfoodFile_CliDocOrdering`
— which reads the real file and invokes `CliDocSlugInto` (it RETURNS the built string, so slug-content parity vs
the C# pipeline is directly checked) over hyphen/digit/punctuation/empty inputs, plus `CliDocSlugsInto`,
`SymbolKindFilter{Indices,Checksum}Into`, `CliDocOrderingMinInt`. Ratchets raised: single-file coverage floor
20→21, multi-file eligible cluster 23→24 (~75%). Coverage now **21/32 single-file, 24/32 via multi-file merge**.

## 2026-06-08 — MULTI-FILE coverage measured: 23/32 (~72%) compile as a merged cluster

Follow-up to the multi-file merge: a probe established exactly which declining files are PURELY cross-file-blocked
(eligible, just need the merge) vs feature-blocked. Merging the 20 single-file-compiling files with the three
cross-file-only files — `ParserExpressions`, `ParserStatements` (depends on ParserExpressions),
`ParserFunctionSignatures` (depends on ParserTypeReferences) — yields a CLOSED 23-file cluster that compiles
end-to-end as one columnar program (the merge declines on any unresolved cross-file call, so success proves
closure). That is **23 of 32 (~72%)** of the corpus compilable via the columnar backend with no C# AST. Pinned
by the ratcheting `ColumnarCodegen_MultiFile_EligibleClusterCompiles` (asserts the merge compiles, the assembly
loads, and the three newly-flipped files' public functions are emitted). `DiagnosticDeduplication` and
`IdentifierSpans` decline even merged (a real feature gap the closeness analysis missed, or a dep on a
feature-blocked file); `SemanticScopes` is parse-blocked (a parser-kernel limit). The remaining feature gaps
gating the rest: `StringBuilder`, `StringComparison` enum + `String.Compare`, `ulong` + `BitOperations`, the
`new string(char[],int,int)` ctor, lowercase `char.IsLetter`/`IsDigit`.

## 2026-06-08 — MULTI-FILE merge: cross-file calls resolve (the dogfood program is multi-file)

A per-file gap analysis (read-only workflow over the 16 not-in-floor files) surfaced that **6 declining files
have NO unmodeled language feature** — they decline for a STRUCTURAL reason. Ground-truth routing of all 32
files (a throwaway probe) showed the real state: **20/32 compile single-file** (the ratcheting floor under-counted
at 16 — `BindingLookup`, `ErrorSuggestions`, `ParserTypeReferences`, `ProjectSourceFilter` already compiled but
were unnamed; floor raised to 20), and the declines split into PARSE-level (SemanticScopes — a parser-kernel
limit on its 9th function) vs EMIT-level. The key discovery: several emit-declining files call PUBLIC functions
defined in OTHER files — e.g. `ParserFunctionSignatures.ParseFunctionSignatureInto` calls
`ParserTypeReferences.ParseUnionTypeReferenceNode`. Single-file emission can't resolve a cross-file callee (it
is not a sibling), so the file declines even though every construct it uses is modelled — and the C# path
ALSO can't compile such a file standalone (it's part of a multi-file program). This is the **multi-file merge**
remaining-work item, NOT a language gap.

Added `NSharpCompilerDogfoodAdapter.TryEmitColumnarProgramMultiFile(IReadOnlyList<string> sources, …)`: it merges
the files by concatenating their sources (blank-line separated) into ONE columnar program, so the unified
sibling map (pass 1 of `TryEmitColumnarAssembly`) resolves every cross-file call exactly as the C#
`MultiFileCompiler` binds declarations across files. A function body's IL is independent of how the program is
assembled, so the merged program runs identically to a genuine multi-file C# build. Declines (C# fallback) if
any file fails to parse or any function is ineligible.

Parity-gated by a MULTI-FILE harness whose ORACLE is a GENUINE separate-file `MultiFileCompiler` build (each
source written to its own `File{i}.nl`, all paths compiled together — NOT a concatenation on both sides, which
would prove nothing): `ColumnarCodegen_MultiFile_CrossFileCalls` (a synthetic two-file program where file B
calls file A's public helpers — proven to DECLINE single-file, then compile + value-match merged) and
`ColumnarCodegen_MultiFile_RealParserCluster` (the real `ParserTypeReferences` + `ParserFunctionSignatures`
merge: the signatures file declines alone, compiles merged, and `ParseFunctionSignatureInto` value-matches the
multi-file C# build on hand-built `func f(x: int)` / `func g(): int` token streams that exercise the real
cross-file `ParseUnionTypeReferenceNode` call). Adversarially reviewed (read-only, 2 lenses): concatenation is
SOUND for the single-package corpus (all-PascalCase public names, no collisions, no parse hazards across the
blank-line join, imports ignored) and the harness is NON-VACUOUS (independent multi-file oracle, asserts the
merge did not decline + the oracle compiled, deterministic out-arrays). Documented limitations (none arise for
the corpus): cross-file name collisions decline rather than per-file mangle; file-private/cross-package
visibility is not enforced under concatenation — and the genuine-multi-file oracle would catch any such
divergence as a compile failure. This is the foundational capability for Stage-5 whole-program routing
(production currently routes single-file only) and Stage 6; it does not by itself raise whole-program coverage
(the corpus still has feature-ineligible files — StringBuilder/StringComparison/ulong/etc. — so an all-32 merge
still declines), but it unblocks the cross-file-dependent feature-eligible files once the whole eligible set is
merged.

## 2026-06-08 — char arithmetic + discarded-call statement → corpus coverage 14 → 16 (PathMatching, LinterImports)

Two small, independent gap-fills, each flipping a real dogfood file:

1. **`char` arithmetic promotes to `int`** (ECMA §12.4.7). The arithmetic operators (`+ - * / %`) now accept
   `char OP char`, emitting the SAME signed opcode (char is already an i4 code point on the stack) and
   reporting the result TYPE as `int` — matching the C# binder's `GetWiderType` (Analyzer.cs:12820:
   "byte/sbyte/short/ushort/char promote to int") AND the C# ILCompiler (Operators.cs:1024 + EmitValueCoercion
   to int, signed Div/Rem). So a NEGATIVE difference like `'A' - 'z'` stays `-57` (int), NOT a u2-wrapped char.
   This flips **`PathMatching.nl`** — its case-insensitive matcher uses `left - 'A' == right - 'a'` (on top of
   the char-param assignment from the prior slice). char-int / int-char MIXES still decline (the pre-switch
   `leftType != rightType` guard is intact), and char is still excluded from bitwise ops.
2. **Discarded non-void call result in statement position** (`pop`). The prior slice's bare-void-call statement
   is generalized: a bare call statement now emits the call and, if the result is non-void, discards it with
   `pop` (a void call emits nothing extra) — exactly what the C# ILCompiler emits (`EmitExpressionStatement`,
   ILCompiler.cs:12500). This flips **`LinterImports.nl`**, which is otherwise pure int/int[]/control-flow but
   calls a flag-clearing helper `LinterImportsClearAllUsedFlagsCore(...)` as a statement for its side effect,
   ignoring the returned count. (The earlier void-only restriction was tighter than N# / the C# path require.)

Parity-gated: `ColumnarCodegen_Parity_CharArithmetic` (incl. the negative `'A' - 'z'` = -57 case that would
catch a u2-wrap bug, the case-fold `==` idiom, char addition); `ColumnarCodegen_Parity_DiscardedCallResult`
(a side-effecting call whose result is dropped — the side effect is PROVEN to still run via a following read);
and the milestone tests `ColumnarCodegen_CompilesRealDogfoodFile_PathMatching` /
`..._LinterImports` (read the real files, assert acceptance, parity-match representative functions incl. the
early-return-(-1) path that exercises the discarded clear-call). Updated the `Array.Fill` test's stale
"discarded result declines" assertion (it now compiles). Corpus coverage **14 → 16 of 32 (~50%)**; ratcheting
`..._Coverage` floor raised to 16. Adversarially reviewed (read-only, 2 lenses): both CORRECT, no divergence —
char-char emission matches the ILCompiler (signed opcodes, int result, no missing conv), the discarded-call
pop matches `EmitExpressionStatement`, stack balance holds (one value → one pop; void → none), and the
"transfer must be last" + decline-surface guards are intact.

## 2026-06-08 — Array.Fill + void-call statement + parameter assignment → corpus coverage 13 → 14 (SourceTextLines)

Three composing features land together, flipping the heaviest line-mapping I/O kernel `SourceTextLines.nl`
(the actual dogfood compiler-service file) to compile end-to-end through the columnar backend with NO C# AST:

1. **Bare VOID-call statement.** `ExpressionStatement` (columnar kind 23) previously handled only a `=`
   assignment (to a `:=` local or `a[i] = v`). It now also accepts a Call (kind 9) whose emitted result type
   is `typeof(void)` — emit the call, no stack residue, done. A NON-void result in statement position declines
   (the spike does not model discarding a value), keeping the C# path authoritative; siblings are never void
   (a void return type fails to resolve and declines at declaration), so today the only void statement-call is
   the BCL `Array.Fill`.
2. **`Array.Fill<T>(T[], T, int, int)`** — the columnar backend's first GENERIC static method. `TryEmitStaticCall`
   matches `Array.Fill` with argCount 4: emit the array (must be an SZ array of a supported element int/long/
   char/string), then value (type-checked == element type), startIndex (int), count (int); resolve the 4-arg
   generic method DEFINITION (`ResolveArrayFill4` filters `typeof(System.Array).GetMethods` for name `Fill`,
   `IsGenericMethodDefinition`, 4 params — excluding the 2-arg `Fill<T>(T[],T)` overload), then
   `Emit(Call, fill.MakeGenericMethod(elementType))`; result type void.
3. **Parameter assignment (`param = expr` → `starg`).** The assignment statement now stores into the argument
   slot (`EmitStoreArgument`: `Starg_S` for ordinal ≤255 else `Starg`) when the target is a parameter, after
   checking the value's type == the parameter's declared type. N# value params have method-local value
   semantics (a reassignment does not escape to the caller — identical to C# by-value params), so `starg` is
   a faithful lowering. This is the pervasive clamp idiom `if offset < 0 { offset = 0 }`.

Parity-gated (`ColumnarCodegen_Parity_ArrayFill`: int/long/char/string element fills + a partial start/count
range + decline surface — 2-arg overload, discarded non-void result, value/element type mismatch;
`ColumnarCodegen_Parity_ParamAssignment`: int/long param mutation inside if/while + re-read + a wrong-type
decline). The milestone test `ColumnarCodegen_CompilesRealDogfoodFile_SourceTextLines` reads the actual file,
asserts the backend accepts it, and invokes representative functions (incl. the `Array.Fill`-using
`BuildDenseLineRangesAndOffsetLineIndicesInto` directly, and `LineMapCachedChecksumInto` which exercises it
transitively) over five line-ending shapes (empty / no-break / `\n` / mixed `\n\r\n\r` / only-`\n`) with
out-of-range offsets + invalid query lines, asserting identical results vs the C# pipeline. A diagnostic pass
confirmed **parameter assignment was the LAST gap** — the other declines in isolation were sibling-call
artifacts of the per-function probe (all four called siblings absent from a single-function program). Corpus
coverage **13 → 14 of 32 (~44%)**; the ratcheting `..._Coverage` floor raised to 14. Removed a now-stale
spike decline assertion (`setp` param assignment used to decline; it is now a parity-tested feature).

## 2026-06-08 — 🚦 STAGE 5: columnar backend ROUTED into the production compile path (flagged)

**The inflection where C# starts being replaced.** The standalone columnar backend is now wired into the
PRODUCTION entry point (`MultiFileCompiler.CompileToIlAssembly`): when `NSHARP_COLUMNAR_BACKEND=1` is set and
the program is eligible (single-file, all top-level funcs in the systems subset), emission is routed through
the columnar backend — which OWNS the assembly (its own `PersistedAssemblyBuilder`, NO C# AST) — producing a
drop-in replacement (assembly named after the project, type `Program`, matching the C# `ILCompiler` output).
Anything it declines (a class/struct/match/double/multi-file/etc.) falls back to the C# `ILCompiler`. The
flag is OFF by default, so production is unchanged unless opted in, and always safe (decline → fallback).
The program is parsed + analysed by the existing pipeline first (diagnostics), so the columnar backend only
does codegen on validated input; full columnar-owned analysis (stages 1–3b) replaces that later.

Parameterised the emitter (`TryEmitColumnarAssembly`/`TryEmitColumnarProgram` now take an assembly name + a
type name) so the routed output names match the C# path. Proven end-to-end by
`Stage5_ColumnarBackend_RoutesEligibleProgramThroughProduction`: the same source compiled through the
production path with the flag OFF vs ON yields DIFFERENT assemblies (so the flag really re-routed the
backend) that run IDENTICALLY (`add(2,3)=5`, `fib(10)=55`) — i.e. the production-routed columnar output is
correct. `Stage5_ColumnarBackend_FallsBackToCSharpForIneligibleProgram` proves a `double` program declines
and the C# path still produces it. 599 MultiFileCompiler-using tests unaffected.

**Stage 6 (delete C#) remains correctly blocked:** the columnar backend models ~41% of the *systems dogfood
subset* and ~0% of the rich language (classes/generics/match/async/LINQ — all the examples + full suite).
Deleting the C# `ILCompiler` now would break the product. Stage 6 is gated on the columnar pipeline reaching
full-language coverage; until then the flag stays off-by-default and the C# path is the production default.

---

## 2026-06-08 — string[]/char[] arrays → corpus coverage 11 → 13 files (DocQuery, TypeLookup)

Extends the int[]/long[] array infrastructure to a REFERENCE element (`string`) and a u2 element (`char`):
`IsSupportedElementType` now admits string/char, element READ adds `Ldelem_Ref` (string) / `Ldelem_U2`
(char), element WRITE adds `Stelem_Ref` / `Stelem_I2`, and `new string[](n)`/`new char[](n)` work via the
existing `Newarr` path. Parity-gated (`ColumnarCodegen_Parity_StringCharArrays`): string[] read/write/alloc/
`.Length`, char[] alloc+fill+read, empty arrays. Int[] regression intact.

**This crossed the threshold for two real dogfood files — corpus coverage 11 → 13 (~41%):** `DocQuery.nl`
and `TypeLookup.nl` now compile end-to-end with no C# AST (the ratcheting `..._Coverage` floor raised to 13).
A satisfying payoff for the accumulated string subsystem: a file flips when its FULL compound of features is
present (here string/char + arrays + IndexOf/Substring/Char.* + control flow + casts + escapes together), not
from any single slice. SourceTextLines still needs `Array.Fill` (a generic static void method + bare-call
statements); other string files need `String.Compare` + the `StringComparison` enum.

## 2026-06-08 — BCL method dispatch slice 2: `Char.ToLowerInvariant`/`ToUpperInvariant`

Incremental on the slice-1 dispatch infrastructure: two more static Char methods (`ToLowerInvariant(char)`,
`ToUpperInvariant(char)` → char) — two whitelist entries in `TryEmitStaticCall`, the result type taken from
the resolved method. Parity-gated (extends `ColumnarCodegen_Parity_StringMethods`): `toLow`/`toUp` over
mixed-case/digit chars + the case-insensitive compare idiom `Char.ToLowerInvariant(a) == Char.ToLowerInvariant(b)`
(the `PathMatching` pattern). Still 11/32 files — `DocQuery`/`PathMatching` compound further needs (`new char[]`,
`String.Compare`+`StringComparison`), so a per-method addition doesn't flip a file alone. Confirms the
breadth-first method approach yields correct, parity-proven building blocks but the next coverage flip needs
a TARGETED file effort (pick one declining file, add exactly its remaining compound of methods/features).

## 2026-06-08 — BCL METHOD DISPATCH (slice 1): instance string + static Char calls

The columnar backend's first BCL method-call dispatch — the gateway to the string batch. Scoped first with a
read-only understanding workflow (corpus method usage, columnar encoding, exact CLR signatures by reading how
`ILCompiler` emits them). A method call is columnar Call (kind 9) whose callee is a MemberAccess (kind 8)
`[receiver, method-name]`. The Call case now dispatches: a bare-identifier callee → sibling function (as
before); a MemberAccess callee → `TryEmitBclMethodCall`, which **detects a STATIC call BEFORE emitting the
receiver** (a bare-identifier receiver not in `_locals`/`_paramOrdinals`/`_siblings` is a type name like
`Char`, not a value — emitting it would wrongly decline), else emits the receiver as a value and dispatches
on its type. Supported (slice 1): instance `string.IndexOf(char,int)`→int and `string.Substring(int,int)`→
string (`callvirt`); static `Char.IsLetterOrDigit(char)`→bool and `Char.IsWhiteSpace(char)`→bool (`call`).
Each arg's type is checked against the BCL signature; unknown method/receiver/overload declines.

Parity-gated (`ColumnarCodegen_Parity_StringMethods`) vs the C# pipeline — a wrong overload, `call`-vs-
`callvirt`, or instance-vs-static mistake would diverge — across `IndexOf`/`Substring` over hits/misses, the
static Char predicates, a `firstWsAt` scan combining `Char.IsWhiteSpace` + indexing + `.Length`, and
unsupported-overload/method declines. Did NOT flip a file yet (still 11/32): the close files compound more
methods (`Array.Fill`, `ToLowerInvariant`/`ToUpperInvariant`, `ToString`, `String.Compare`) — but the
dispatch INFRASTRUCTURE (the hard part: instance/static detection, call/callvirt, arg-typing) is now in
place, so adding each further method is incremental (slice 2+). Adversarial review (read-only): ship-with-
nits — sound dispatch; the one nit (the instance path used a null-forgiving `GetMethod!` while the static
path null-checked) is fixed (both now resolve + null-check before emitting), plus the judge's safe edge
cases added (IndexOf on an empty string → -1, Substring length 0 → "").

## 2026-06-08 — literal escapes: char decoding + raw strings (matched to N#'s actual semantics)

The parity oracle EARNED ITS KEEP again: my first cut decoded C-style escapes in BOTH char and string
literals, but the C# path returned a RAW string for `"a\tb"` — revealing N#'s real (asymmetric) semantics,
confirmed in `ILCompiler`: **char literals DECODE escapes** (`ParseCharLiteralValue` — `\n \r \t \\ \" \' \0
\a \b \f \v`, no `\u`/`\x`), but **string literals are RAW** (`GetStringLiteralRuntimeValue` = `Value.Trim('"')`,
no decode — a backslash stays literal). Matched both exactly: char literals decode via a shared
`TryDecodeLiteralBody` (declining `\u`/`\x` and any unknown escape, exactly as `ParseCharLiteralValue`
throws), and string literals emit `Ldstr` of `Text.Trim('"')` with NO decode. This both ADDS char-escape
literals (`'\n'`, `'\t'`, … — previously declined) and makes string literals containing a backslash compile
correctly as raw (the prior cut declined any backslash). Parity-gated (`ColumnarCodegen_Parity_Escapes`):
char-escape code points (`(int)'\r'` etc.), an `isNewline` guard (`c == '\n' || c == '\r'`), raw strings
with `\t`/`\n`/`\\`, and a `'A'` char decline. A reminder that codegen must MATCH the existing
compiler's semantics (even quirky ones), not an assumed ideal — which only the parity oracle can enforce.

## 2026-06-08 — columnar codegen grows explicit casts `(int)char`/`(char)int`/int↔long

Third string-subsystem slice — explicit numeric casts among int/long/char (columnar Cast, kind 16,
`[type, operand]`; child[0] is a Simple TYPE subtree, child[1] the operand). int/long/char are all i4/i8 on
the stack, so the conversion opcode is emitted only when the representation differs: `(long)` → `Conv_I8`
(widen int/char), `(char)` → `Conv_U2` (truncate int/long), `(int)` from long → `Conv_I4`; `(int)char` and
same-type casts are no-ops (a char is already an i4 code point). Casts to/from string/bool decline. This is
the pervasive dogfood idiom `code := (int)s[i]` (index a string → char → int for arithmetic). Parity-gated
(`ColumnarCodegen_Parity_Casts`): `(int)s[i]`, `(char)int`, a composite `(char)((int)c + 32)` lowercasing,
and int↔long widen/truncate. Did NOT flip a file (still 11/32): the string-using files also need the BCL
methods `IndexOf`/`Substring` (instance method-call dispatch) and `new char[]`/escapes — the next, meatier
slices before the ~37% string batch starts compiling.

## 2026-06-08 — columnar codegen grows `char` + string indexing `s[i]` (character scanning)

Second string slice — the character-scan capability the corpus uses pervasively. Added: `char` as a
supported scalar type; char literals (`'x'` → `ldc.i4` of the code point; escaped/multi-char literals like
`'\n'` decline, escapes not yet processed); string INDEXING `s[i]` (index-access kind 10 now branches:
string → `callvirt get_Chars(int)` → char, array → `ldelem`); and char in the comparison guards (ordering
`< > <= >=` and equality `== !=`) — a char is a non-negative i4, so the existing signed `clt`/`cgt`/`ceq`
are correct (no `.un` needed). Parity-gated (`ColumnarCodegen_Parity_CharAndStringIndex`): index→char,
`s[0] == 'A'`, the `countChar` scan loop, a `c >= '0' && c <= '9'` range check, char param/return round-trip,
and an escaped-char-literal decline. Next toward the ~37% string batch: casts `(int)char`/`(char)int`
(char↔int math the corpus does constantly), then the BCL string methods `IndexOf`/`Substring`.

## 2026-06-08 — STRING subsystem begins: type + literals + `.Length` + `==`/`!=` (the ~37% batch)

First slice of the string subsystem (the gap analysis' next big batch — strings/char gate ~37% of the
corpus). Added: `string` as a supported scalar type (params/returns/locals via the existing type machinery);
string literals (columnar kind 3 → `Ldstr` of the quote-stripped value; a literal containing a backslash
declines, since escapes are not yet processed — the C# path stays authoritative for those); `.Length` on a
string (member-access kind 8 now branches: array → `Ldlen;Conv_I4`, string → `callvirt get_Length`); and
value equality `==`/`!=` (`String.op_Equality`, NOT reference `ceq` — `!=` negates). This is the first BCL
interop in the columnar backend (a property getter + a static operator method, resolved by reflection).

Parity-gated (`ColumnarCodegen_Parity_StringBasics`) vs the C# pipeline: `.Length`, literal returns,
param round-trip, literal-in-`==`, empty-string check, and — crucially — a value-equality PROOF: `eq` is
invoked with a runtime-built `new string('a', 3)` that is value-equal to but a DISTINCT reference from the
`"aaa"` literal, so a wrong reference `ceq` would diverge (it returns true via op_Equality, matching C#).
Plus an escape-literal decline. Still building toward string-using files: the next pieces are string
INDEXING `s[i]` (→ `char`), then the methods `IndexOf`/`Substring` (BCL method-call dispatch), then `char`
+ casts — after which the ~37% string batch starts compiling. (No file flipped yet; same as `new int[]`.)

## 2026-06-08 — columnar codegen grows `new int[](n)` array allocation

`new T[](size)` allocation (columnar New, kind 15, `[type, args...]`) for supported element arrays
(int/long). child[0] is a TYPE subtree (TYPE-kind semantics: 2 = Array, its child[0] the Simple element);
the single arg is the int length. Emit the length, then `Newarr <element>` (which zero-initialises); result
type is the array type. Jagged/generic element types, a non-array `new`, and wrong arg counts decline.
Parity-gated (`ColumnarCodegen_Parity_ArrayAlloc`): alloc + `.Length`, zero-init sum, allocate/fill/read-back
(`a[i] = i * 2`), a sized expression (`new int[](n + 1)`), and `new long[](n)`. This completes the int[]/long[]
array story (resolve, alloc, `.Length`, read, write). It did NOT raise file coverage (still 11/32): the files
that allocate arrays also use strings/char, so allocation alone doesn't flip them — confirming the remaining
declines are gated on STRINGS, the next (bigger) batch. The cheap int[] unblocks are now exhausted.

## 2026-06-08 — columnar codegen grows `break`/`continue` (corpus coverage 10 → 11 files)

Loop `break`/`continue`. The emitter keeps a stack of the enclosing loops' (end, check) labels; `while`
pushes (endLabel, checkLabel) around its body, `break` branches to the innermost loop's end label,
`continue` to its check label (re-testing the condition). Both reach their target with an empty stack (the
body up to the transfer is net-zero), so they are stack-consistent; nested loops work (an inner break exits
only the inner loop). A `break`/`continue` outside any loop declines. The block emitter's "must be last"
rule now also covers a DIRECT `break`/`continue` child (anything after it is unreachable NL312 code) — a
break/continue nested inside an `if` is conditional, so only a direct child counts. Parity-gated
(`ColumnarCodegen_Parity_BreakContinue`): break-on-match, break-until-negative, continue-to-skip, and nested
loops. This unblocked one more real dogfood file (`ParserDeclarations.nl`), raising measured corpus coverage
to **11 of 32 files**. Cheapest remaining unblocks: `new int[](n)` allocation, then strings/char/casts.

## 2026-06-08 — 🎯 MILESTONE: columnar backend compiles a REAL dogfood file (int[] arrays + Stage-5 proof)

**The standalone columnar backend now compiles a real compiler-service file — `FormatterSafetyScan.nl` —
end-to-end straight from its columnar tables with NO C# AST, and every function matches the authoritative C#
pipeline.** This is the Stage-5 proof-of-concept: the inflection where the columnar pipeline does real
self-host work, not just synthetic spike functions. The new test
`ColumnarCodegen_CompilesRealDogfoodFile_FormatterSafetyScan` reads the ACTUAL file (so it tracks the real
source), asserts the backend accepts it (a silent decline fails the test), and invokes all three functions
(`FormatterSafetyHasError`, `FormatterSafetyErrorIndicesInto`, `FormatterSafetyErrorIndicesChecksumInto`)
via BOTH paths over error/no-error/empty inputs, asserting identical results.

The enabling feature: **`int[]`/`long[]` arrays**. `TryResolveType` maps a canonical `int[]` to the CLR
array type (a single trailing `[]` → `MakeArrayType()`); `IsSupportedType` admits an `IsSZArray` of a
supported element (int/long); `.Length` (member access kind 8) emits `Ldlen; Conv_I4` → int; element read
`a[i]` (index access kind 10) emits `Ldelem_I4`/`Ldelem_I8` (result = element type); element write `a[i] = x`
(assignment to a kind-10 target) emits `Stelem_I4`/`Stelem_I8` after checking the value type == element type.
Index must be int. Jagged (`int[][]`), multi-dimensional (`int[,]`), and unsupported-element (`bool[]`,
`string[]`, `double[]`) arrays all DECLINE (resolution fails → C# path stays authoritative).

Parity-gated across synthetic arrays (sum loops; `safeAt` proving `&&` short-circuits BEFORE indexing so an
out-of-range index can't throw; long[] past int range), array writes (`collectInto` — the real
`FormatterSafetyErrorIndicesInto` pattern; deterministic-overwrite so the shared array across the two
invocations is benign), the decline surface, AND the real file. **Adversarial review (read-only): SHIP** —
array support is SOUND (every seam type-checked; no jagged/multi-dim/element-opcode/stack hole), and the
milestone test is GENUINE (asserts Ok, truly compares both paths, exercises real logic). Added the judge's
suggested decline-boundary cases.

Next real targets (per `project_columnar_gap_analysis`): the ~13 pure-`int[]` dogfood kernels (~40% of the
corpus) now within reach, then strings (`string` type + `.Length` + `str[i]` + IndexOf/Substring) for ~37%.

**Measured corpus coverage: 10 of 32 real dogfood files (~31%, 39 functions) now compile** end-to-end through
the columnar backend with NO C# AST: `AnalyzerExhaustiveness`, `AnonymousUnionShims`, `AotRequirements`,
`CliTreeDependencies`, `CompletionGrouping`, `FormatterImportOrdering`, `FormatterSafetyScan`,
`OverloadCandidates`, `StructCopyAnalysis`, `TextEditOrdering`. Pinned by a ratcheting coverage test
(`ColumnarCodegen_CompilesRealDogfoodCorpus_Coverage`): each named file must compile to a loadable assembly,
and the total compiling count is asserted ≥ the floor, so new features only RAISE coverage. The 22 declines
are blocked by (in rough order): strings/char (most), `break`/`continue`, `new int[](n)` allocation,
match/foreach, casts — the cheapest next unblocks are `break`/`continue` + array allocation, then strings.

## 2026-06-08 — GAP ANALYSIS (target-driven pivot) + short-circuit `&&`/`||`

A read-only gap-analysis workflow surveyed the real 32-file dogfood corpus
(`Compiler.Dogfood/CompilerServices/*.nl` — the compiler's own services in N#) against the backend's
coverage. Findings drove a strategy decision (memory `project_columnar_gap_analysis`): the corpus is
**procedural and array-heavy with NO custom types** (structs/records/classes/enums/unions, generics, match,
foreach, lambdas, exceptions are rare-to-ABSENT — so none are needed for self-host), and **`double` is 0% of
the corpus — a dead end**. Universal needs: int/bool, `int[]` arrays (`a[i]`, `.Length`), if/else, while,
funcs, calls. Very common: casts `(int)char`, string ops, `&&`/`||`. **Decision: go TARGET-DRIVEN** — build
arrays + `&&`/`||` toward compiling the simplest real file (`FormatterSafetyScan.nl`: int[] params, `.Length`,
read+write indexing, `&&`/`||`, sibling calls — nothing else), then the ~13 pure-int[] kernels (~40%), then
strings (~37%). Skip `double`. This replaces the naive scalar-ladder plan (`double`/`string` next).

First slice toward that: **short-circuit `&&`/`||`**. Handled BEFORE evaluating either operand (emit left,
branch on it, evaluate right only on the non-short-circuiting path) — `&&` branches to a `0` on a false left,
`||` to a `1` on a true left. This is both C#-correct AND safety-critical: `i < n && a[i] == x` must not index
`a[i]` when `i >= n`. Both operands and the result are bool. Parity-gated (`ColumnarCodegen_Parity_ShortCircuit`)
incl. chained `a > 0 && b > 0 && c > 0` and a `safeDiv(a, b) = b != 0 && a / b > 0` case that PROVES
short-circuit — with `b == 0`, evaluating `a / b` would throw, so a correct (no-throw) result requires not
evaluating the right side. The former `&&` decline test is now removed. Next: int[] arrays
(param type + `a[i]` read + `.Length`, then `a[i] = x` write) → compile the first real file.

## 2026-06-08 — Stage 4b-bit: columnar codegen grows bitwise & shift operators (int/long)

Bitwise `&`/`|`/`^` (And/Or/Xor) and shifts `<<`/`>>` (Shl/Shr) for int/long — mechanically simple, no
NaN/BCL complexity. `&`/`|`/`^` require both operands the same int/long type (result that type). Shifts are
the exception to the same-type rule: the value is int/long but the shift COUNT is always int, and the result
is the value's type; `>>` is the SIGNED/arithmetic right shift (sign-extends a negative value), matching C#.
Confirmed the columnar `>>` is a single binary operator in expression context (the `>>` token split only
applies inside generic type arguments). Parity-gated (`ColumnarCodegen_Parity_Bitwise`) incl. negative `>>`
sign-extension (`-8 >> 1`, `-1 >> 4`), long shifts past 32 bits (`1L << 40`), and the `Modifiers`-flag idiom
`1 << 11 | 1 << 12` — directly relevant to compiling the compiler's own flag code. Next on the type ladder:
`double` (NaN-correct `<=`/`>=` deferred for fresh review) and `string` (BCL `op_Equality`/`Concat`).

## 2026-06-08 — Stage 4b-div: columnar codegen grows integer/long division & modulo

Rounds out the arithmetic operators for int/long: `/` → `Div`, `%` → `Rem` (the SIGNED forms, matching C#
for int/long). No type-system subtlety — both operands the same int/long type, result that type — and no
new BCL/NaN complexity, so a small, low-risk slice. Divide-by-zero and `INT_MIN / -1` throw at runtime
exactly as the C# path does. Parity-gated (`ColumnarCodegen_Parity_DivMod`) with NEGATIVE operands to pin
the C#-matching semantics (truncation toward zero; the remainder's sign follows the dividend), an
in-expression use (`(a + b) / 2`), and large long values. Useful for real compiler code (hashing, indexing
math). Next on the type ladder: `double` (`ldc.r8` + NaN-correct `<=`/`>=` via the `.un` compare variants —
deferred for fresh review of the NaN subtlety) and `string` (BCL `op_Equality`/`Concat`).

## 2026-06-08 — Stage 4b-ii: columnar codegen grows `long` (i8 — first distinct stack representation)

On the type-aware foundation, `long` slots in cleanly. A long literal is an `IntLiteral` token whose text
keeps the `L`/`l` suffix (the lexer preserves it), so the emitter distinguishes `5L` → `ldc.i8` (type long)
from `5` → `ldc.i4` (type int); unsigned suffixes (`u`/`U`, `UL`/`LU`) decline (uint/ulong unsupported).
Long arithmetic/comparison/unary reuse the SAME opcodes as int (`add`/`sub`/`mul`/`neg`/`not`/`clt`/`cgt`/
`ceq` all work on i8) — the only new opcode is `ldc.i8` — with the result type propagated as long. Long
params/locals/returns work via the existing type machinery. Mixed int/long arithmetic (implicit widening)
is NOT modelled — both operands must be the same type, else decline (safe: the C# path handles widening).

This is the first type where the per-arg type check added in 4b-i genuinely matters: int and long have
distinct stack representations (i4 vs i8), so passing an int where a long is expected would be invalid IL —
the check declines it. Parity-gated (`ColumnarCodegen_Parity_LongType`) vs the C# pipeline, deliberately
including VALUES BEYOND int range (`1e9 * 1e9 = 1e18`, `factL(20)`) to prove it is genuinely i8, not i4.
Declines mixed int/long and a `ulong` literal. Updated the now-stale int-only decline tests (a pure-long
function is no longer declined). Next: 4b-iii `double` (`ldc.r8`, float arithmetic), then `string`.

## 2026-06-08 — Stage 4b-i: TYPE-AWARE columnar emitter + bool (first type beyond int)

The biggest Stage-4 refactor: `ColumnarIlEmitter` went from an UNTYPED int-only emitter to a TYPE-AWARE
one. `EmitExpression(int idx, out Type type)` now reports each expression's CLR type, and every consumer
checks it — Return requires the value type == the declared return type; a `:=` local declares its type from
the initializer (`DeclareLocal(initType)`); assignment requires value type == the local's `LocalType`; a
Binary requires both operands the same type (no implicit conversions); a Call checks each argument's type
against the callee's param types. This is the foundation for every type beyond int.

Proven by adding **bool** alongside int: bool literals (`true`/`false` → i4 1/0), comparisons in VALUE
position (the comparison opcodes moved from the old `EmitCondition` into `EmitExpression`'s Binary case via
a shared `EmitComparison`; ordering `< > <= >=` on int, equality `== !=` on int or bool → bool), logical
`!` (`ldc.i4.0; ceq`), bool params/locals/returns, and — since conditions are now any bool expression —
a bool literal/param/local or a bool-returning call drives `if`/`while` directly. The type machinery
prevents cross-type mixing (a bool can never leak into int arithmetic or an int return).

Verified in two stages: FIRST the int subset was confirmed behavior-preserving (all existing int tests pass
unchanged — the refactor adds type checks as a safeguard layer without altering int opcodes/control flow),
THEN bool was added. Parity-gated (`ColumnarCodegen_Parity_BoolType`) vs the C# pipeline across all bool
forms, plus declines for `&&` (short-circuit, not yet lowered), bool-from-int-return, and bool+int mixing.

**Adversarial review (read-only) — ship-with-nits.** The int-regression probe confirmed behavior
preservation (all-info findings); the soundness probe found ONE real gap that bool *introduced*: call
ARGUMENT types weren't checked against callee param types, so (int and bool both being i4) `needsBool(5)`
would emit verifiable-but-wrong IL. Fixed by carrying callee param types in the sibling map and checking
each arg's type; added the judge's exact suggested cases (a `needsBool(5)` decline + a correct
`needsBool(x > 0)` positive). Next: 4b-ii `long` (distinct i8 representation — `ldc.i8`, long arithmetic/
comparisons), then `double`, then `string`.

## 2026-06-08 — Stage 4i: columnar codegen grows sibling calls (incl. recursion + mutual recursion)

Direct calls to top-level functions (columnar Call, kind 9, `[callee, args...]`). The multi-function
backend's two-pass structure makes this clean: pass 1 declares ALL methods and builds a sibling map
(name → declared `MethodBuilder` + param count) BEFORE any body is emitted, so a body can `call` any
function — including a forward reference (a callee declared later) and **itself** (the map includes the
current function, so direct recursion works for free). The Call case: require a bare-identifier callee
(kind 6) not shadowed by a local/param (a delegate/closure invocation declines), look it up in the sibling
map, check arity (no overloads/defaults/params-array), emit each int arg left-to-right, then
`call` the `MethodBuilder` (the token is baked at `CreateType`/`Save`). Param count is carried in the map
because `MethodBuilder.GetParameters()` is unsupported before the type is created. A duplicate top-level
function name (an overload set the spike does not model) declines the whole program.

Parity-gated (extends `ColumnarCodegen_Parity_MultiFunction`) and matched to the C# pipeline across: a
sibling call + a NESTED call (`add(add(a,b), c)`); **self-recursion** (`fact`, two-call `fib`); and
**mutual recursion** with a FORWARD reference (`isEven` calls `isOdd` declared after it). With calls the
columnar backend can now compile genuinely recursive int programs end-to-end with no C# AST. Next: 4b
(types beyond int — long/bool/double/string via the builtin map + type-aware emission).

## 2026-06-08 — ROUTING DECISION + Stage 4-multi: standalone columnar backend, multi-function emission

**Architecture decision (user, 2026-06-08):** route columnar codegen into production via a **standalone
columnar pipeline** — a columnar-first backend that OWNS parse→bind→analyze→codegen→assembly with NO
internal C# AST — NOT by re-parsing each function inside the AST-driven `ILCompiler`. The scoping (two
read-only workflows) found the load-bearing constraint: `ILCompiler` consumes only the `CompilationUnit`
AST and has no source access (`CompilationUnit`/`FunctionDeclaration` carry Line/Column but no source text
or byte span), while the columnar kernels parse source strings — so the re-parse-in-ILCompiler path means a
redundant second parse + unsolved per-function source extraction. The standalone pipeline avoids both and
IS the Stage 5/6 endgame. (Recorded in memory `project_routing_standalone_columnar_pipeline`.) The Stage-4
spike's `TryEmitColumnarFunction` already builds a real assembly (PersistedAssemblyBuilder→DefineType→
DefineMethod→Save) — it is the seed of this backend, not throwaway.

**First slice — multi-function emission.** Generalised the single-function spike into
`ColumnarIlEmitter.TryEmitColumnarAssembly(typeName, funcs[], source)`: emit EVERY top-level function into
ONE assembly/type via a **two-pass** structure — pass 1 resolves each signature (int-only) and DECLARES all
methods up front; pass 2 emits each body. Declaring all methods before emitting any body is the foundation
for sibling calls (4i): a body will resolve a call to a sibling `MethodBuilder` that is declared but not yet
emitted. The whole program declines if ANY function is ineligible (keeping the C# path authoritative). New
`ColumnarFunctionInput` carries one function's signature + columnar body tables; the adapter's orchestration
was refactored into a shared `TryGetColumnarFunctionInputs` (tokenize+compact, require every top-level decl
to be a `func`, parse each) + `TryParseColumnarFunctionAt` (one function's signature+body), with
`TryEmitColumnarFunction` (single, unchanged surface) and the new `TryEmitColumnarProgram` (multi) on top.

Parity-gated by the new `ColumnarCodegen_Parity_MultiFunction`: two/three independent int functions
(arithmetic, guard clause, while accumulation, if/else) emitted into one assembly, each invoked and matched
to the C# pipeline; a single function through the multi path; and a decline when a second function is
non-int. The single-function spike + parity tests still pass (back-compat preserved). Next: 4i (sibling
calls — emit `call` to a declared MethodBuilder), then 4b (types beyond int).

## 2026-06-08 — Stage 4g-ii: columnar if/else completed — general fall-through merge (all four arm combos)

Unifies `ColumnarIlEmitter`'s `If` (kind 27) into one general algorithm covering all four
then/else fall-through-vs-return combinations, replacing the two special cases (closed both-return else +
bare if-without-else). The merge: `cond; brfalse else; then; [br end (if then falls through)]; else:
<else>; [end: (if then falls through)]`. The skip-`br` over the else-block and the `end` label it targets
are emitted **only when the then-branch can fall through** — exactly the just-landed EmitIf fix carried into
the columnar emitter; if the then-branch always returns, that `br` is dead and would risk a method-end
label. The function-level always-returns gate guarantees a later statement follows whenever the if itself
falls through, so the merge is never the bare method end. Both branches' `:=` locals are scoped. The
both-return form (`max`/`sign`) is unchanged behaviorally — it now flows through the same code with
`thenFallsThrough == false`, so no `br`/`end` is emitted (identical IL).

Parity-gated across the full if/else state space, each over multiple inputs: then-falls/else-returns,
then-returns/else-falls, both-fall-through (and both-return via the existing `max`/`sign`), plus the 4g
guard-clause and merge-position cases. The former `elseFall` decline is now the positive `tf`. The if/else
control flow is now complete in the columnar emitter.

## 2026-06-08 — Stage 4g: columnar codegen grows if-WITHOUT-else (guard clauses, fall-through merge)

Extends `ColumnarIlEmitter`'s `If` (kind 27) to the bare `if cond { then }` form (childCount 2) — the
first fall-through branch with a merge label: `cond; brfalse end; then; end:`. Both edges reach `end` with
an empty stack (the brfalse pops the condition bool; a fall-through then-branch is net-zero; a then-branch
that returns ends in `ret` and never reaches `end`). The just-fixed EmitIf/EmitSwitch method-end-label
hazard **cannot arise here**: an if-without-else has `AlwaysReturns == false`, and the block emitter
declines any non-last statement that always-returns, so a successfully-emitted always-returning body always
has a later statement after the guard (a loop back-edge, an enclosing merge, or a trailing `return`) — `end`
is never the bare method end. The then-branch's `:=` locals are scoped (a braceless `:=` would otherwise
leak), mirroring the while-body scoping. The if-WITH-else fall-through shape (else present, not both-return)
is still declined — only the closed both-return else and the bare if-without-else are modelled so far.

Verified empirically (the strongest check for codegen — it caught the EmitIf/EmitSwitch bugs the adversarial
review missed): the parity oracle now compiles guard-clause functions via BOTH paths and asserts identical
results across inputs, including the **risky merge-label positions** — a guard nested in another guard's
then-branch, a guard as the LAST statement of a while body (merge label followed by the back-edge), and a
guard as a non-last while-body statement. Plus spike invoke-tests for then-returns / then-falls-through /
sequential guards. The former `noElse` decline is now a positive; a new `elseFall` case pins that the
else-with-fall-through shape still declines.

## 2026-06-08 — Stage 4c: columnar↔C# parity oracle — and the two production codegen bugs it caught

The Stage-4 inflection needs an acceptance gate before any routing: proof that the columnar emitter is
semantically equivalent to the C# path it will replace, not merely self-consistent. New test
`ColumnarCodegen_Parity_MatchesCSharpPath` compiles each eligible function **both** ways — the columnar
path (`TryEmitColumnarFunction`) and the authoritative production pipeline (`MultiFileCompiler` →
`ILCompiler`) — then invokes each emitted method over a spread of inputs (negatives, zero, comparison
boundaries, overflow extremes) and asserts the results are identical. 15 functions spanning every
supported form (literals, params, `+ - *`, unary `-`/`~`, paren, `:=` locals, assignment, if/else, nested
if/else, while accumulation incl. `fact`). This is the gate every future codegen-routing slice must clear.

**The oracle immediately earned its keep — it caught two real, latent production codegen bugs in the C#
`ILCompiler`, both the same class** ("a `br` to a label marked at the very end of the method, i.e. an
offset with no instruction" → IL that crashes ilverify with `MarkPredecessorWithLowerOffset` and faults
the JIT with `InvalidProgramException` *on invoke*). Both compile cleanly and only fail when the method is
actually run — which is why they hid: the prior coverage (`ILCompiler_CanCompileIfStatement`,
`ILCompiler_CanExecuteSwitchStatement`) either never invoked, or never used the triggering shape.

- **`EmitIf` (`ILCompiler.cs:~12312`)** — `if/else` where **both arms return and nothing follows the
  `if`** (e.g. `func max(a,b) { if a > b { return a } else { return b } }`). It unconditionally emitted
  `br endLabel` to skip the else, then marked `endLabel` at method-end. Fix: a sound, conservative
  `StatementCompletesNormally(Statement)` helper (false only for provable always-transfer:
  return/throw/break/continue, a block whose any statement transfers, an if whose both arms transfer;
  everything else defaults to "may fall through"); the skip-branch and its label are emitted only when
  the then-branch can fall through. Reachable control flow is unchanged in every other case (the elided
  `br` was always dead).
- **`EmitSwitch` (`ILCompiler.cs:~12776`)** — the **identical shape**: a `switch` as the last statement of
  a non-void function where every case body **including `default`** returns (definite-return is satisfied
  by the cases, so it compiles). Same fix: gate the per-case implicit-break `br endLabel` on
  `StatementsCompleteNormally(case.Statements)`; `endLabel` stays unconditionally marked because `break`
  and the no-default no-match dispatch path still target it.

**Verification discipline:** standalone CLI repros confirmed each bug as an ilverify `MarkPredecessorWith­
LowerOffset` crash *before* the fix and `CLEAN` after, with fall-through controls staying clean. A
read-only adversarial workflow (Explore agents + judge) ruled the `EmitIf` fix **sound** (no unsound
false-positive, no label-marking hazard). The judge under-rated `EmitSwitch` ("endLabel is always marked,
so the branch is valid") — but that misdiagnoses the bug (the *original* `EmitIf` endLabel was also always
marked; the hazard is a label at method-*end*, not an unmarked one). A direct ilverify repro proved the
`EmitSwitch` bug real and in-scope. Lesson reaffirmed: **empirically reproduce, don't trust a judge's
hand-wave.** Two columnar-independent regression tests added
(`ILCompiler_IfElseBothBranchesReturn_NoTrailingStatement_IsRunnable`,
`ILCompiler_SwitchAllCasesReturn_AsLastStatement_IsRunnable`) so the guards survive even if the spike is
later removed. Gate green (3781 tests + IL-verification gate).

**On 4j (routing into `ILCompiler`):** scoping confirmed `ILCompiler` consumes only the `CompilationUnit`
AST and has **no access to raw source** (`CompilationUnit`/`FunctionDeclaration` carry `Line`/`Column` but
no source text or byte span), while the columnar kernels parse source strings. So "inject columnar
body-emit into `EmitFunctionBody`" as originally framed implies threading source through `ILCompiler` and
**re-parsing each function** — a redundant second parse, blocked on unsolved per-function source
extraction. 4c was the right fork-independent step regardless; the routing approach (re-parse-in-ILCompiler
vs a standalone columnar codegen pipeline that Stage 5 routes to wholesale) is the open architecture fork.

## 2026-06-08 — Stage 4e: columnar codegen grows unary `-`/`~`

Small slice: int prefix unary in `ColumnarIlEmitter` — `-`→`neg`, `~`→`not` (emit the operand, then the
opcode). `!` (logical not), `++`, and `--` decline (the operator-token text isn't `-`/`~`). Invoke-tested:
`neg(5)==-5`, `bnot(0)==-1` / `bnot(5)==-6` (one's-complement = two's-complement minus one), and unary inside a
larger expression (`x := -a; return x + b`). Nested `- -a` parses as nested unary and works; the unsupported
`!a` declines. Proportionate to a 2-opcode slice, this skipped the heavy adversarial workflow — the direct
load+invoke test across signs/edge cases plus the gate's IL-verification are dispositive here.

With this the spike covers params, int literals, unary `-`/`~`, `+/-/*` and comparisons, paren, `:=` locals,
assignment, if/else, and while — enough to compile real int functions, and the columnar→IL question is well
proven. The strategic next step is the inflection itself: 4c (a parity-vs-C#-path harness) then 4j (routing the
columnar codegen into `ILCompiler` with C# fallback), where it starts replacing C#.

## 2026-06-07 — Stage 4h: columnar codegen grows while loops (general control flow) + block scoping

The first GENERAL (fall-through) control flow in the columnar emitter. A While (kind 26) emits
`check: cond; brfalse end; body; br check; end:` — the stack is empty at both merge labels (the condition
pushes a bool that `brfalse` pops; the body is net-zero), so it is stack-consistent and verifiable. A
degenerate loop whose body always returns (exits on the first iteration) declines rather than emit a dead
back-edge. Invoke-tested with real iterative computations: `count` (accumulate to n), `sumTo` (1..n with `<=`),
`fact` (`fact(5)==120`, a local read+written each iteration), and `twice` (a `:=` local declared inside the
loop body and used within it).

Also added BLOCK SCOPING: a `:=` local declared in a block leaves scope when the block ends (snapshot the local
names on entry, remove the ones added on exit). Without it, a flat name table would let a loop-body local leak
into the post-loop scope — and a reference there (out of scope in N#) could read a method-level slot that is
unassigned when the loop runs zero times (invalid IL), or just wrong. **Adversarial review surfaced a gap in
the first cut:** block scoping only covered `{ }` Block bodies, but the kernel also allows a BRACELESS
single-statement loop body (a bare `:=`), which isn't a Block and leaked. Fix: the while case scopes its body
directly too. Decline tests for both the braced and braceless leak shapes, plus the degenerate loop.

Note the if/else first cut still requires BOTH branches to always return, so an `if` with non-returning branches
(the common in-loop conditional) currently declines — the general fall-through `if` is deferred to 4g+. Gate
green. Next: 4c (real dispatcher + parity-vs-C#-path harness), 4i (calls), 4j (route).

## 2026-06-07 — Stage 4f: columnar codegen grows simple assignment statements

Extends `ColumnarIlEmitter` with a simple `local = expr` assignment statement. An ExpressionStatement (kind 23)
whose child is an Assignment (kind 14) with operator `=` and an Identifier target that is an existing `:=` local
emits the value expression then `stloc` into that local. Invoke-tested: `acc` (`x = x + b`) and `bump` (two
reassignments). Declines: compound assignment (`+=`/`-=`/… — the operator-token text is not `=`), assigning to
a parameter or a non-identifier target (`arr[i]`, `obj.f`), and any non-assignment statement (a bare call). The
columnar fact that made this clean: AssignmentExpression carries its operator token in its value span
(`ParserExpressions.nl:578`), so `=` vs `+=` is a string check; and the corpus uses no compound assignments.

**Adversarial review caught a latent codegen bug (present since 4d):** a function body that does not return on
all paths — e.g. `func f(a: int): int { x := a` then `x = x + 1 }` (ends in an assignment) or `{ x := a }`
(ends in a `:=`) — emitted IL that falls off the end with no `ret` = invalid (`InvalidProgramException` on load).
All prior positive tests happened to end in `return`, so it slipped through. Fix: the emitter requires the
function body to ALWAYS return (the same `AlwaysReturns` subset) before emitting; a non-returning body declines
to the C# analyzer (which would flag NL305). Decline tests added for an assignment-ended and a `:=`-ended body.
Gate green. Next: 4c (real dispatcher + parity-vs-C#-path harness), 4h (while), 4i (calls), 4j (route).

## 2026-06-07 — Stage 4g: columnar codegen grows if/else (first cut) + int comparisons

Extends `ColumnarIlEmitter` with control flow. **First cut deliberately requires an `if`/`else` where BOTH
branches always return** — then there is no fall-through, so no merge label or trailing-`ret` analysis is
needed: emit the condition, `brfalse elseLabel`, emit the then-branch (ends in `ret`), `MarkLabel(elseLabel)`,
emit the else-branch (ends in `ret`). Conditions are restricted to an int comparison (`< > <= >= == !=`, the
negated ones as `cgt`/`clt` followed by `ceq 0`), emitted via a separate `EmitCondition` so a comparison (a
bool) can never leak into an int value/return position (which would diverge from N#'s type rules). A new
`AlwaysReturns` helper (the same subset as the diagnostics pass) gates the both-branches-return requirement.
Invoke-tested: `max` (via `>`), `absish` (via `>=` and `0 - a`), and a nested `sign` whose else branch is itself
a both-returning if/else.

**Adversarial review caught a real codegen bug:** `AlwaysReturns(Block)` is true if ANY statement returns, but
the Block emitter emits ALL statements — so a block with code after a return (e.g. `{ return 1` then `y := 2 }`,
which the parser accepts and NL312 flags as unreachable) would emit IL past a `ret`. Fix: a returning statement
must be the LAST in its block; otherwise the emitter declines (keeping the C# analyzer/codegen authoritative —
the dogfood corpus has zero unreachable code, so no coverage cost). Decline tests added for if-without-else, a
fall-through branch, non-comparison conditions, a comparison in value position, and unreachable-after-return.
Gate green. Next: 4c (real dispatcher + parity-vs-C#-path harness), 4h (while), 4i (calls), 4j (route).

## 2026-06-07 — Stage 4d: columnar codegen grows `:=` locals

Extends the Stage-4 spike (`ColumnarIlEmitter`) to int `:=` local variables. A VariableDeclaration (kind 24)
emits its initializer, `DeclareLocal(typeof(int))`, then `stloc`; identifiers resolve to a local (`ldloc`)
before a parameter (`ldarg`). Invoke-tested: a `:=` local feeding a return (`sum`), chained locals where the
second reads the first (`chained`: `x := a + 1` then `y := x * 2`), and a local mixed with a param in the
returned expression (`square`: `t := a * a` then `return t + a`).

**Adversarial review caught a real divergence:** a local that shadows a parameter (`func shadow(x: int): int {
x := x + 1 … }`) was accepted, but N# treats shadowing as a diagnostic — so the columnar path would silently
compile a program the C# path flags. Fix: the VariableDeclaration case DECLINES when the name is already a
parameter (shadow) or an already-declared local (redeclaration), keeping the C# analyzer authoritative. With
that, the local and parameter name sets are disjoint for accepted programs. Decline tests added for shadowing,
redeclaration, and assignment statements (`x = …`, kind 23 — an ExpressionStatement, not handled yet). Gate
green. Next: 4c (turn the spike into a real dispatcher + a parity-vs-C#-path harness), 4g–4h (if/while), 4i
(calls), then 4j (route through `ILCompiler.DeclareFunction`).

## 2026-06-07 — Stage 4 SPIKE: columnar codegen proven end-to-end (columnar tables → runnable IL)

The Stage 4 inflection point, de-risked. New `Columnar/ColumnarIlEmitter.cs` + adapter
`TryEmitColumnarFunction` emit a real one-method .NET assembly whose body IL is generated **directly from the
columnar statement/expression tables — no C# AST** — then the test **loads and invokes** it and checks results.
This proves the columnar pipeline can drive codegen, which is the load-bearing assumption for routing C# out
(stages 5–6).

Self-contained (`PersistedAssemblyBuilder` → `Save` → `Assembly.Load`), so it touches NONE of the 25k-line
`ILCompiler.cs` — the emit primitives (`ldarg`/`ldc.i4`/`add`/`sub`/`mul`/`ret`) are exactly what the full
columnar codegen will emit, so the logic transfers; only the tiny assembly-build harness is spike-local (replaced
by `ILCompiler`'s flow at slice 4j). Proven INT-ONLY for: param load, int literal, parenthesized expr, and int
`+`/`-`/`*` binary including nested left-associative (`a - b - c`) and multi-param (`a * b - c`, `(a+b)*b`).
Invoke-tested: `identity(42)==42`, `answer()==42`, `add(2,3)==5`, `poly(3,4,5)==7`, `chain(10,3,2)==5`,
`paren(2,3)==15`, `inc(5)==6`.

Adversarially verified (read-only Explore): decline-safety is strong — every unsupported form (locals, expr
statements, if/while, calls, member/index, unary, comparison/logical/division operators, non-int types,
multi-function sources, empty bodies) returns false (no assembly) so the C# path is untouched. Two mis-emit
risks were caught and fixed proactively: (1) mixed-type arithmetic (`int + long`) would emit `add` on (i4, i8)
= invalid IL → added an INT-ONLY guard (return + every param must be `int`); (2) a value-less `return` in an
int function would emit `ret` with an empty stack → now declined. Both have decline tests.

Folds in 4a (binary) + 4f (int literals) for the int subset. **Next:** 4c — turn the spike into a real columnar
dispatcher + a parity-vs-C#-path harness (compare columnar-emitted output to `NSharpCompiledMethod.Bind`); then
4d locals, 4g–4h if/while, and 4j route through `ILCompiler.DeclareFunction` (where emitted IL hits the
ilverify gate).

## 2026-06-07 — Stage 3b-iii: columnar unused-local (NL001) — Stage 3b COMPLETE

Third and last columnar diagnostic, completing Stage 3b. NL001 ("declared but never read") lives in the
**Linter** (not the Analyzer), and it is **time-/scope-ordered**: `CheckUnusedVariables` runs at each block's
`PopScope` against a file-level `_usedVariables` set that `MarkVariableUsed` populates for every identifier use
(including assignment targets and call callees) plus every parameter, accumulates in traversal order, and is
**never cleared between functions**. So a use appearing AFTER a block closes (a later sibling block, or a later
function) does NOT suppress that block's unused locals, while an EARLIER use (a prior function, an earlier
statement, or a parameter) does.

**A first attempt got this wrong** and was reverted (`fe61aa51`): it used a naive "a local is unused iff its
name never appears as an identifier anywhere in the source" GLOBAL rule. That over-suppresses — e.g.
`func first() { x := 42 }` (an unused `x`) followed by a `func second()` whose body reads `x`: the Linter flags
`first`'s `x` (its block closed before `second` was visited), but the global rule does not. The first adversarial review's *judge* approved it on
mirror-parity grounds, but a direct audit of `Linter.cs` (functions push a scope at `:631`, blocks at `:833`;
the check at `PopScope`/`:285`) showed the mirror itself wasn't faithful to the Linter — so it was discarded.

**The faithful implementation** (`ColumnarDiagnosticsPass.CollectUnusedLocals` + the adapter's
`TryCollectUnusedLocals`): process functions in source order sharing one `usedNames` set (seeded per function
with its params, never cleared); walk each body in source order with a stack of per-Block scopes; record each
`:=` local (kind 24) in the innermost block; and at each Block (kind 25) exit, flag its locals whose name is not
`_`/`_`-prefixed and not in `usedNames` AS OF THEN. The per-scope `used` flag is correctly subsumed (used=true ⟹
name in `_usedVariables`, so the check reduces to "name not in `usedNames` at block exit"). Braceless bodies
(`if c x := 1`) attribute the local to the enclosing block — matching the Linter, which pushes no scope for a
non-block body. Interpolated strings (`$"...{x}..."`) can't hide a use: the kernel refuses them, so such sources
decline (`bodyNodeCount <= 0`) to the C# linter (verified empirically). Reported at the declaration's line:col.

**Parity:** a new `MirrorWalkUnused` reproduces the exact time-ordered walk on the C# AST; 9 hand-built cases
pin both ordering directions (later use does NOT suppress / earlier use DOES), nesting, assignment-marks-used,
and discard exemption; plus the full 32-file dogfood corpus (sorted columnar == sorted mirror). Re-verified
clean (APPROVE) after the rewrite. **Stage 3b is now COMPLETE** (NL305 + NL312 + NL001). Next: Stage 4 —
columnar codegen, the inflection point where the C# binder/analyzer begin to be routed out and deleted.

## 2026-06-07 — Stage 3b-ii: columnar unreachable-after-terminal (NL312), parity-gated

Second columnar diagnostic. `ColumnarDiagnosticsPass.CollectUnreachable` mirrors `Analyzer.AnalyzeStatements`
(2017): in each statement list (a Block), once a statement always exits (`StatementAlwaysReturns`), the
IMMEDIATELY following statement is reported unreachable (once, then the rest of that list is skipped), recursing
into nested blocks / if-branches / while-bodies exactly as `AnalyzeStatement` does. Emitted per function before
the definite-return descriptor (deterministic order).

**Position fidelity (the tricky bit):** the diagnostic reports the unreachable statement's `line:col`. The AST
carries `Statement(Line, Column)`; the columnar statement node carries only a byte span. Rather than reconstruct
line/col (and risk a counting-convention mismatch with the C# lexer), the adapter builds a byte-offset → (line,
col) map straight from the tokenizer's own per-token metadata (`rawStarts`/`rawLines`/`rawColumns`) and passes a
`PositionOf` resolver to the pass. Because the dogfood tokenizer and the C# lexer agree byte-identically, the
resolved line/col equals the AST `Statement.Line/Column` — confirmed empirically: the test asserts the FULL
descriptor strings (incl. `line:col`) equal the C#-AST-walk mirror, which would fail on any position drift.

**Parity:** a new `MirrorCollectUnreachable` walks the AST with identical logic; tested on 6 hand-built cases
(dead code after return; after a terminal if/else; only-first-reported-then-skip; unreachable inside a reachable
nested block; the unreachable-before-missing-return ordering; and a clean negative) asserting columnar == mirror
+ a non-vacuous unreachable count. The 32-file dogfood corpus (in the definite-return test's corpus loop) now
also validates zero unreachable on valid self-host source. Adversarially verified (read-only Explore workflow:
control-flow parity, position fidelity, test non-weakening — all clean, APPROVE). Note the analyzer's NL312 keys
off `StatementAlwaysReturns`, which is FALSE for break/continue, so code after break/continue is NOT flagged —
the columnar pass matches (it does not "improve" on the analyzer). Next: 3b-iii unused-local.

## 2026-06-07 — Stage 3b-i: columnar definite-return (NL305) — first columnar diagnostic, parity-gated

First slice of Stage 3b (columnar diagnostics): definite-return / not-all-paths-return (NL305), computed
DIRECTLY over the columnar statement tables with no C# AST. New `Columnar/ColumnarDiagnosticsPass.cs` +
adapter entry `NSharpCompilerDogfoodAdapter.TryCollectTopLevelFunctionDiagnostics` (reuses the stage-3 parse
scaffold; per function returns `[]` or `["missing-return:<canonicalReturnType>"]`).

`ColumnarDiagnosticsPass.StatementAlwaysReturns` is the columnar **subset** of the real
`Analyzer.StatementAlwaysReturns`: Return always exits; a Block exits if any statement exits; an If exits only
with an else where both branches exit; Break/Continue/ExpressionStatement/VariableDeclaration/While are
non-exiting. This subset is faithful by construction because the parser kernel REFUSES throw/switch/try/wrapper
forms (the richer terminal shapes the real analyzer also handles can't appear on any body the pass accepts), and
an omitted return type is treated as void — matching `Analyzer.cs:621` (`func.ReturnType != null ? ResolveType :
Void`).

**Limitation found + resolved (adversarial review):** the real analyzer EXEMPTS async-unit-task
(`async func f(): Task {}` / `ValueTask`) and iterator (`func* g()`) functions from NL305 — exemptions that need
BCL task-type knowledge the structural pass cannot model. The first cut accepted `async func f(): Task {}` and
wrongly emitted `missing-return:Task`. Fix: the adapter now DECLINES any source with an async/generator function
(via `TopLevelDeclarationModifiers` + `Modifiers.Async|Generator`), falling back to the C# analyzer for exact
parity. The dogfood corpus has zero async/generator functions, so coverage is unaffected. (Generators already
declined at the parse stage; the modifier guard makes it explicit and covers async.)

**Parity:** per hand-built case against the EXACT expected diagnostics AND a C#-AST-walk mirror
(`MirrorAlwaysReturns`); on the full **32-file dogfood corpus**, equal to the mirror AND emitting ZERO
missing-return (valid self-host source compiles → the real analyzer emits no NL305 → a real-analyzer parity
check). Plus boundary assertions that async/generator sources decline. Adversarially verified twice (read-only
Explore workflow): the first pass caught the async unit-task divergence; the re-verify after the fix was clean
(no remaining columnar-vs-analyzer divergence on valid input). Definitive routed parity follows at stages 4–5.
Next: 3b-ii unreachable-after-terminal, 3b-iii unused-local.

## 2026-06-07 — Track C perf capstone: rigorous single-machine native re-run + P4 backend decision

Closed out Phase P with the rigorous step the roadmap reserved: a **cross-language re-run with all four
languages measured back-to-back on one cool, idle machine** (Apple M4, .NET 10, rustc 1.96, Apple clang 17),
using the **vectorizing N# compiler** (P1+P2+P-minmax+P-ctrans, default-on). This converts the previously
*implied* "~1.6–2× behind native" into a **measured** result and refreshes the stale 2026-06-06
pre-vectorization table in [`systems-vs-native.md`](systems-vs-native.md).

**Measured N#/best-native (was scalar 2026-06-06 → now vectorized):** checksum-sum 8.78× → **2.02×**;
count-ascii 6.30× → **1.63×**; count-transitions 4.54× → **1.97×**; min-max-delta 10.5× → **1.67×**;
rolling-hash 1.61× → **1.62×** (non-vectorizable floor, correctly unchanged); parse-eight-digits 1.84× →
**1.80×** (all at 4096). Worst single cell across the whole matrix is **2.49×** (min-max-delta @64, where the
SIMD helper's fixed setup dominates a 4.5 ns native min/max) — down from 10.5×. N# now **beats C#/RyuJIT
~2–6×** on the vectorizable kernels (it emits `Vector<T>`; RyuJIT runs scalar) and ties C# on the
non-vectorizable ones (rolling-hash, scan-tag ≈1.0×). Native (Rust/C) columns are within run-to-run noise of
2026-06-06 — only the N# column moved, by emitting SIMD. Internal consistency confirms the vectorized path
(MinMaxDelta 5.9× faster than C# matches P-minmax(c); CountTransitions 2.2× matches P-ctrans; RollingHash/ScanTag
correctly ≈1.0×).

**P4 — LLVM/NativeAOT backend decision (DEFERRED, evidence-gated).** New decision doc
[`p4-llvm-nativeaot-backend-evaluation.md`](p4-llvm-nativeaot-backend-evaluation.md). The structural backend's
original justification was the 8.8–10.5× SIMD-vs-scalar gap; Phase P's per-pattern `Vector<T>` emission (the
.NET-recommended approach, since RyuJIT does not auto-vectorize loops — dotnet/runtime#11263) already captured
that prize. The residual ~1.6–2× is latency-bound / small-input / scalar-scheduling tax, which a backend swap
does not cheaply remove: NativeAOT shares RyuJIT's codegen (no loop auto-vectorization either), and
NativeAOT-LLVM is experimental and WASM-targeted. **Decision: defer the vectorizing structural backend (D/E)
behind gates G1–G4; keep extending per-pattern `Vector<T>` only on measured need; treat NativeAOT *image
emission* as a separate, lower-risk CLI startup/size track (orthogonal to throughput — `nlc publish --aot` is
analysis-only today).** Cheapest next perf step: broaden the corpus from synthetic i32 kernels to a real
compiler hot path before any structural bet. Docs-only slice; non-VS-Code gate green.

## 2026-06-07 — Rust-perf P-ctrans: shifted-compare SIMD count-transitions — the LAST vectorizable kernel, Rust-class

Vectorizes the count-transitions kernel (the last addressable Rust gap, ~2.5–4.5× behind native). This is the
realization of the roadmap's "P3" — but as VECTORIZATION rather than literal bounds-check elision, which is the
bigger win (the BCE goal — removing the per-iteration indexed-load+branch tax — is subsumed by replacing the loop
with a SIMD helper). count-transitions counts `i in [1,len)` where `a[i] != a[i-1]`. The loop carries `previous`,
but seeding the helper with `previous`'s live value makes the rewrite value-identical for ANY init — no non-local
init analysis: the scalar loop's first comparison is `a[start]` vs `previous` and every later one is `a[i]` vs
`a[i-1]`, which the helper reproduces exactly.

`SimdReductions.CountTransitionsInt32(array, start, end, seedPrevious) -> (int Count, int LastPrevious)`: compares
`a[start]` vs the seed (scalar), then SIMD-compares `a[i]` vs `a[i-1]` over `[start+1, end)` via shifted loads —
`~Vector.Equals(curr, prevShifted)` is an all-ones mask per NOT-equal lane, `acc -= mask` accumulates +1 per
mismatch across four lane-accumulators — then a scalar tail; returns the count and the terminal `previous`
(`a[end-1]`, or the seed when empty). It reads ONLY `a[start..end-1]` (the seed replaces `a[start-1]`), so the
empty/OOB guards match the other helpers (OOB → `IndexOutOfRangeException` at the same element).
`TryEmitMatchedCountTransitions` lowers a matched `current := a[i]; if current != previous { count++ };
previous = current` to `(delta, last) = CountTransitionsInt32(a, i, bound, previous); count = count + delta;
previous = last; index = max(i, bound)` (ValueTuple `Item1`/`Item2` via `ldloca`/`ldfld`, reusing the P-minmax(c)
fields). The terminal `previous = last` restores the carried scalar to its scalar-loop exit value for any later use.

**Measured (BDN short job, M4, isolated worktree):** CountTransitions @4096 — C# 1119.8 ns → **N# 471.9 ns =
0.421× = 2.37× faster than C#** (was ~0.99×, scalar) → implied **~4.54× → ~1.9× behind native**; @64 — 16.91 →
**10.93 ns = 0.646×** → ~2.45× → ~1.6× behind native. **With this, EVERY vectorizable kernel is Rust-class
(within ~2× of native):** checksum ~2×, count-ascii ~1.6×, score-frame ~2×, min-max-delta ~1.77×,
count-transitions ~1.9×, parse-eight-digits already faster than C#. Only rolling-hash remains (~1.5×, the
latency-bound floor — a carried multiply-mask dependency, not vectorizable). Phase P's auto-vectorization program
is essentially complete on the systems kernels.

Tests: 46 count-transitions tests — 17 detector accept/reject (for/while, carry/distinctness near-misses); parity
scalar≡vectorized for the COUNT and the restored terminal `previous` across lengths incl. SIMD tails (for+while);
lowers to ONE helper call; non-int[] falls back (0 calls); OOB → `IndexOutOfRangeException`; empty/negative → seed;
direct helper edge cases (all-equal→0, all-different→N, runs, int extremes, seed ==/!= a[start], partial ranges).
Adversarially verified; full gate green. Developed in the `systems-language-perf` worktree.

## 2026-06-07 — Rust-perf P-minmax(c): FUSED single-pass MinMaxInt32 — min-max-delta to Rust-class (~1.8× native)

The fused follow-up to P-minmax(b). (b) lowered min-max-delta to TWO passes (`MinInt32` then `MaxInt32`, each
re-scanning the array); (c) adds `SimdReductions.MinMaxInt32(array, start, end, seedMin, seedMax) -> (int Min,
int Max)` that loads each `Vector<int>` ONCE and applies both `Vector.Min` and `Vector.Max`, and routes the
canonical `[1 min, 1 max]` body to it. `TryGetMinMaxPair` (in `ILCompiler.Vectorization.cs`) detects exactly one
min + one max reduction; the emitter calls the fused helper (seedMin = the min accumulator, seedMax = the max
accumulator), stores the `ValueTuple<int,int>` to a local, and reads `Item1 -> min` / `Item2 -> max` via
`ldloca + ldfld`. min-only/max-only (and any homogeneous pair) keep the per-reduction `MinInt32`/`MaxInt32` path.
The fused helper reuses the same empty/negative-range early-out, in-bounds guard, and scalar-tail OOB semantics.

**Measured — rigorous back-to-back on the SAME machine (worktree `systems-language-perf`, isolated tree; BDN
short job, MinMaxDelta):**

| size | two-pass (b) | fused (c) | fused speedup | fused vs best-native |
|---|---|---|---|---|
| 4096 | 453.2 ns (0.296× C#) | **262.5 ns (0.168× = 5.94× faster than C#)** | **1.73×** | ~10.5× → **~1.77× behind** |
| 64 | 30.6 ns (1.303× — *slower* than C#) | **18.4 ns (0.768×)** | **1.67×** | — |

The fused path is **1.73× faster than two-pass** at 4096 — far beyond the ~10–15% I'd predicted from memory
traffic alone. The extra win is the eliminated second call/loop boundary (visible at size 64, where two-pass was
actually *slower* than C#, 1.303×, and fused is 0.768×). This puts min-max-delta at **~1.77× behind native —
BELOW the ~2× DONE bar, matching checksum-sum and count-ascii (Rust-class).** Decision rule honored: I measured
fused vs two-pass before keeping it (would have dropped it if ≈ two-pass).

Tests: 69 MinMax tests (the codegen `[1 min, 1 max]` now lowers to ONE fused call — `MinMax_LowersToOneFusedHelperCall`;
end-to-end scalar≡vectorized parity through the fused path; direct `MinMaxInt32` helper edge cases proving fused ≡
the two separate helpers ≡ the scalar fold across seeds/partial ranges/extremes/all-equal/empty). Developed in an
isolated worktree (`systems-language-perf` off `ca9ba88e`) after a concurrent session made the shared
`systems-language` tree non-compiling. Adversarially verified; full gate green.

## 2026-06-07 — Rust-perf P-minmax: lane-wise SIMD min/max reduction (min-max-delta) — the 10.5× kernel

The codegen that vectorizes the min-max-delta kernel — the single LARGEST remaining native gap (10.5× behind
best-native at size 4096 when N# tied C#). min-max-delta is two min/max reductions in one loop body
(per element `value := a[i]`, then `if value < min { min = value }` and `if value > max { max = value }`). Signed integer min and max
are associative AND commutative (a total order), so lane-wise `Vector.Min`/`Vector.Max` across SIMD lanes and
four accumulators is value-identical to the sequential scalar fold — the same class of safe rewrite as P1's
integer sum, just a different operator and the conditional-assignment shape.

`SimdReductions.MinInt32(array, start, end, seed)` / `MaxInt32(...)` seed all four `Vector<int>` accumulators
with the pre-loop accumulator value broadcast, run `Vector.Min`/`Vector.Max` over the SIMD body, fold the four
accumulators + the lanes horizontally (no `Vector.Min`-reduce intrinsic), then a scalar tail. They reuse P1's
guards verbatim: empty/negative range early-out (`end <= start`, which also avoids the P1(d) `end - step`
int.MinValue overflow); SIMD only over a provably in-bounds range; the scalar tail reproduces
`IndexOutOfRangeException` at the same element (not the Vector ctor's `ArgumentOutOfRangeException`).
`ILCompiler.TryEmitMatchedMinMaxReduction` (hooked into `EmitWhile`/`EmitFor` after the reduction + range-count
hooks) lowers a matched loop to `min = MinInt32(a, i, bound, min); max = MaxInt32(a, i, bound, max);
i = max(i, bound)` — one helper call per reduction, the bound evaluated once, the index unchanged between calls
so both helpers see the same start. The detector (`MinMaxReductionLoopShape`, P-minmax(a)) matches while/for,
temp/inlined subject, one OR two reductions, and reversed `min > value` operand order, with full
distinct-name/no-aliasing/single-write-per-accumulator safety.

**Measured (2026-06-07, Apple M4, .NET 10, BenchmarkDotNet `SystemsHotPathBenchmarks`, N# vectorized vs the C#
scalar baseline; short job):** MinMaxDelta size 4096 — C# 1535.3 ns → **N# 468.0 ns = 0.305× (3.28× faster)**;
size 64 — C# 23.55 ns → **N# 16.79 ns = 0.713× (1.40× faster)**. Was ~1.0× (tied, scalar) on 2026-06-06.
Implied vs best-native (applying the measured speedup to the prior M4 native numbers): **10.5× → ~3.2× behind**
(4096), 5.70× → ~4.1× (64). The same-run cross-check confirms surgical scope: checksum 0.226×, count-ascii
0.249×, score-frame 0.228× hold their P1/P2 wins, and every non-matching kernel (count-transitions ~0.99×,
rolling-hash ~1.0×, scan-tag, parse-eight-digits) is unchanged — the min/max codegen fires only on min-max-delta.
The 3.28× (vs checksum's ~4.4×) reflects the TWO-PASS cost (MinInt32 + MaxInt32 each re-scan the array); a fused
single-pass `MinMaxInt32` (slice c) is the obvious follow-up to push toward checksum's ratio (~2.4× behind native).

Tests (236 Simd-category total): the min-max-delta benchmark shape (for/while, temp/inlined), min-only/max-only,
scalar≡vectorized across lengths incl. SIMD tails and signed extremes (int.MinValue/MaxValue mid-array);
fires-only-when-enabled (2 helper calls for min+max, 1 for min-only); non-int[] array falls back (0 calls) and
stays correct; OOB bound → `IndexOutOfRangeException`; empty/negative/int.MinValue bound → seed; plus direct
helper edge cases on the SIMD path (all-equal, seed=extremum, partial ranges, empty/negative). The
adversarial-verify workflow (3 lenses → skeptic-per-finding → judge) raised 7 candidates; I adjudicated all as
non-divergent. The one the judge flagged "real" (a cached `array.Length` bound diverging under "concurrent array
resize") rests on an impossible premise — .NET `int[]` is fixed-length, `array.Length` is immutable for an
instance (`Array.Resize` allocates a new array), the function holds the array by a fixed local reference for the
call, and the cached-bound pattern is identical to the already-shipped/reviewed SumInt32 (P1) and CountInRangeInt32
(P2) emitters; the detector also rejects every genuinely-mutable bound, and the `a.Length`-bound parity test passes.
Full `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` gate green; no IL-shape test fallout (the min/max shape is
specific, like the range count).

## 2026-06-07 — Rust-perf P2(b): masked-SIMD range-predicate count (count-ascii) — the 5.7–6.3× kernel

The codegen that vectorizes the count-ascii kernel. `SimdReductions.CountInRangeInt32(array, start, end, lo, hi)`
counts in-range elements via packed compares — `Vector.GreaterThanOrEqual(v, lo) & Vector.LessThanOrEqual(v, hi)`
gives an all-ones lane mask per in-range element; `acc -= mask` accumulates +1 per match across four independent
lane-accumulators; then `Vector.Sum` + a scalar tail. It reuses P1's empty/OOB/extreme-bound guards verbatim
(`end <= start` early-out; SIMD only over a provably in-bounds range; the scalar tail throws
`IndexOutOfRangeException` at the same element as the scalar loop — not the Vector ctor's
`ArgumentOutOfRangeException`). `ILCompiler.TryEmitMatchedRangeCount` (hooked into `EmitWhile` + `EmitFor`
after the reduction hook) lowers a matched `if a[i] >= lo && a[i] <= hi { count++ }` loop body (optionally
preceded by `value := a[i]`) to `count = count + CountInRangeInt32(a, i, bound, lo, hi)` then `i = max(i, bound)`.
Fires for an `int[]` array, int
counter/index, int side-effect-free bound, and int side-effect-free `lo`/`hi` (evaluated ONCE — the masked
compare must match the scalar `int a[i]` comparison exactly, so non-int `lo`/`hi` or a non-`int[]` array fall
back to scalar). Counts are order-independent, so the result is value-identical to the scalar loop.

Tests (162 Simd-category total): count-ascii while/for forms, temp + inlined subject; scalar≡vectorized across
lengths incl. SIMD tails and inclusive boundaries (values exactly `== lo`/`== hi`); fires-only-when-enabled;
non-int `lo`/`hi` and non-`int[]` array fall back (0 helper calls) and stay correct; OOB bound →
`IndexOutOfRangeException`; empty/negative/`int.MinValue` bound → 0; plus direct helper edge cases on the SIMD
path (`lo>hi`→0, `lo==hi`, negative ranges, `int.MinValue`/`int.MaxValue` boundaries). The adversarial-verify
workflow (3 lenses) found NO codegen divergence: signed compare semantics, the mask arithmetic, no accumulator
overflow (count ≤ length ≤ `int.MaxValue`; per-lane and intermediate sums ≤ total), once-evaluation of the
side-effect-free `lo`/`hi`, and the terminal index are all correct. Full `VSCODE_TESTS=skip ./scripts/test-all.sh
--commit` gate green; no IL-shape test fallout (the range-count shape is specific, unlike the broad for-form).

## 2026-06-07 — Rust-perf P2(a): range-predicate count detector (count-ascii; no codegen change)

First sub-slice of the count-ascii vectorization (the 5.7–6.3× Rust gap). `RangePredicateCountShape.TryMatch`
recognizes the canonical range-predicate count loop — `for`/`while i < n { [value := a[i];] if a[i] >= lo &&
a[i] <= hi { count++ } }` (inclusive range; while- and for-forms; temp or inlined subject; counter increment
`count = count + 1`/`+= 1`/`++`) — purely structurally, enforcing every safety condition that makes the future
masked-SIMD rewrite (P2(b)) value-preserving: loop-invariant side-effect-free `lo`/`hi` (not index/temp/counter,
so evaluating them once in the helper matches per-iteration evaluation), no `else`, a single unit-counter-increment
body, the array indexed only by the loop var, and distinct counter/array/index/temp names. 19 tests pin 6 accepted
shapes + 13 near-miss rejections (else branch, exclusive `>`/`<`, `||`, non-unit increment, extra statements,
wrong index, two arrays, loop-variant bound, subject mismatch). **No IL emission yet → zero regression risk** —
this is the analytical gate the masked-count emission (P2(b)) will hook into `EmitWhile`/`EmitFor`. The masked
helper design is validated (`Vector.GreaterThanOrEqual & Vector.LessThanOrEqual` → an all-ones mask per in-range
lane; `acc -= mask`; `Vector.Sum`), and will reuse P1's empty/OOB/overflow-guarded helper structure. **Next:
P2(b)** — the masked-count helper (`SimdReductions.CountInRangeInt32`) + the emitter hook + parity tests.

## 2026-06-07 — Rust-perf P1(f): vectorize the FOR-form — the win now fires where it is actually measured

**Discovery (high-leverage):** the reduction auto-vectorizer (P1 a–e) hooked ONLY `EmitWhile`, but the systems
benchmarks (`SystemsHotPathBenchmarks`: checksum, countAscii) and idiomatic N# use the **`for`-form**.
Empirically confirmed via a probe: a for-form reduction emitted **0** SIMD helper calls while the equivalent
while-form emitted **1** — so the measured "~8.8× → ~2×" checksum win was **not actually reaching the benchmark
or any for-loop code**. `EmitFor` emits its own loop and never called `TryEmitVectorizedReduction`; there is no
for→while desugaring. P1(f) closes that gap so the existing, proven SIMD machinery finally fires where it counts
(and unblocks P2 — count-ascii is for-form).

`ReductionLoopShape` now also matches the for-form `for i := start; i < bound; i++ { acc = acc + a[i] }` — the
increment is the ITERATOR (`i++`/`++i`/`i = i + 1`/`i += 1`) and the body is the single accumulator-update
statement (braced or braceless). `EmitFor` emits the initializer (so the index holds its start value), then the
SAME shared core (`TryEmitMatchedReduction`) used by the while-form lowers the loop to the SIMD helper call plus
the terminal `index = max(index, bound)` — which equals a counted for-loop's exit value `max(start, n)` for all
start/n. The detector + emitter were refactored to share all matching/emission logic between the two forms with
**no while-form behavior change** (verified: the while-body increment is still matched as an `AssignmentExpression`,
so an `i++` statement cannot slip into the while-form).

35 new tests (121 Simd-category total): for-form detector accept (`i++`/`++i`/`i=i+1`/`i+=1`, `a.Length` bound,
non-zero start) + reject (stride≠1, `i--`, `a[i]*2`, two arrays, `a[j]`, `<=`, extra body statement); end-to-end
for-form scalar≡vectorized across lengths incl. SIMD tails for int/long/uint/ulong (with uint/ulong wraparound);
non-zero-start `[start, n)` parity incl. empty ranges; for-form terminal index = `max(start, n)`; braceless body;
OOB bound → `IndexOutOfRangeException`. The read-only adversarial-verify workflow (3 lenses) returned **SAFE TO
SHIP — no for-form-specific divergence**: the only genuinely new surface (initializer emitted exactly once,
terminal index, single-statement body shape-matched-then-discarded) is correct, and the helper's overflow/OOB/
wrap fixes from P1(d) are shared by both forms. Full `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` gate green
(this is the higher-blast-radius change — it now vectorizes every matching for-loop in the dogfood compiler,
examples and templates; the gate compiles and runs all of them + IL verification).

## 2026-06-07 — Rust-perf P1(d): widen auto-vectorized reductions to long/uint/ulong (+ 2 correctness fixes)

Widened the counted-reduction auto-vectorization (P1 a–e, previously `int[]`-only) to the rest of the
associative-add integer family: `long[]`, `uint[]`, `ulong[]`. `NSharpLang.Runtime.SimdReductions` gains
`SumInt64`/`SumUInt32`/`SumUInt64` (the same unrolled 4-accumulator `Vector<T>` reduction); the emitter
(`ILCompiler.TryEmitVectorizedReduction`) now resolves the helper by the array element type and requires the
accumulator type to equal the element type. **float/double remain scalar by construction** — there is no FP
helper, because FP addition is not associative (reassociating across lanes/accumulators changes the result).
44 new tests pin scalar≡vectorized across lengths (incl. 0 and SIMD-tail non-multiples) for all three widths,
including deliberate uint/ulong wraparound (mod-2^32 / mod-2^64), plus "lowers to a helper call only when
enabled" and "float/double never vectorize."

The adversarial-verify workflow (4 lenses, read-only) — the self-host-loop.md review substitute now that Codex
is lifted — found **two real correctness divergences**, both pre-existing in the shipped `int` path and now
fixed for all four widths in the runtime helper (the bound is a runtime parameter, so the fix must live in the
helper, not the emitter):

1. **`int.MinValue` bound overflow (CRITICAL).** The helper computed the vector-loop limit as `end - step` in
   unchecked int arithmetic. For `end = int.MinValue` (a caller passing `n = int.MinValue`), `end - step` wraps
   to a large positive, so the SIMD loop ran and read out of bounds — while the scalar loop `while i < n`
   never runs (returns 0). Fixed with an `if (end <= start) return sum;` early-out (the empty/negative range is
   the scalar identity AND `end - step` is never reached for a hugely-negative `end`).
2. **Out-of-bounds exception-type divergence.** When `n > array.Length` (or a negative start index), the scalar
   loop throws `IndexOutOfRangeException` at `a[i]`, but `new Vector<T>(array, i)` throws a *different*,
   observable type — `ArgumentOutOfRangeException` (verified empirically on .NET 10). Fixed by taking the SIMD
   fast path only over a provably in-bounds range (`start >= 0 && end <= array.Length`); otherwise the scalar
   tail reproduces the exact `IndexOutOfRangeException` at the same element. Regression tests cover
   `n = int.MinValue/+1/+8/-1/-100` (→ 0, no OOB read) and `n > length` (→ `IndexOutOfRangeException`, not
   `ArgumentOutOfRangeException`) for int/long/uint/ulong.

Also added a defensive `_overflowCheckingEnabled` guard: a `checked` reduction would emit `add.ovf` (throws on
overflow) in the scalar path, which the wrapping helper would not reproduce — so vectorization is skipped in a
checked context. (Currently unreachable: N# `checked` is expression-only and `while` is a statement, so a while
body is never emitted under overflow checking — but the guard pins the invariant against a future `checked`
block.) The full `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` gate is green (unit suite incl. the 81
Simd-category tests + Systems BenchmarkDotNet zero-tolerance gate + IL verification + dogfood/examples/templates).

## 2026-06-07 — Rust-perf P1(e): vectorization ON by default — the perf win is now ACTIVE

Flipped reduction auto-vectorization ON by default (env `NSHARP_VECTORIZE_REDUCTIONS=0` opts out). The N#
systems compiler now auto-vectorizes `int[]` counted reductions for every program — the worst-case
checksum-sum kernel goes from ~8.8× behind C/Rust to ~2× (the helper's measured 4.5× over scalar). Never-
regress proven broadly: the FULL 3466-test unit suite passes with vectorization active (no test changed
behavior), and the gate (dogfood recompile + all examples + templates + IL-verification + the SystemsFastGate
benchmark) is green. This is the first Rust-perf win shipped active, not just built. Design constraint for the
next widening (P1(d)): integer types only (long/uint/ulong — wrapping add is associative); float/double
reductions must stay scalar (FP reassociation changes results).

## 2026-06-07 — Rust-perf P1(b): counted-reduction auto-vectorization codegen (off by default)

The codegen that realizes the measured ~4.5× checksum-sum win. When `NSHARP_VECTORIZE_REDUCTIONS` (or a
thread-local test override) is set, `ILCompiler.TryEmitVectorizedReduction` (hooked into `EmitWhile`) lowers a
matched `int[]` counted reduction to `acc = acc + NSharpLang.Runtime.SimdReductions.SumInt32(array, index,
bound); index = max(index, bound)` — i.e. a call to the unrolled 4-accumulator `Vector<int>` reduction in
plain testable C#, instead of hand-emitting vector IL (much safer; the emitted IL is just load-args + call +
add + store + a max). Off by default + thread-local so it can't affect other tests or production.

27 tests: run(vectorized) == run(scalar) across lengths incl. 0 and non-multiples of the SIMD width (scalar
tail), the post-loop index left at the scalar terminal value `max(index,bound)` (incl. empty/negative bounds),
the array.Length path, and the optimization-fires shape check (scalar element-load loop replaced by a call).

Adversarial review (4 agents) caught one real divergence and it was fixed: the bound was evaluated multiple
times and `.Count`/custom `.Length` bounds could be side-effecting property getters, so a vectorized loop
would observe a different evaluation count than the scalar loop. Now bounds are restricted to provably
side-effect-free int (int local/param read, int literal, or `.Length` on an ARRAY = the pure ldlen intrinsic)
and evaluated exactly once; anything else falls back to the scalar loop. Next: (d) widen element types, then
(e) the end-to-end SystemsFastGate bench + default-on once never-regress is proven.

## 2026-06-07 — Rust-perf P1(a): counted-reduction loop detector (safe, no codegen change)

First sub-slice of the auto-vectorization codegen (the measured ~4.5× checksum-sum win). `ReductionLoopShape
.TryMatch` recognizes the systems `while`-form counted reduction — `while index < bound { acc = acc +
array[index]; index = index + 1 }` (and the `+=` forms, with bound = identifier / int literal / `x.Length`/
`x.Count`) — purely structurally, enforcing every safety condition that makes the SIMD rewrite
value-preserving (unit stride, single array indexed only by the loop var, distinct acc/array/index, the fixed
two-statement body so no break/continue/other-write, accumulator-update-before-increment). 11 tests pin 3
accepted shapes + 8 near-miss rejections. No IL emission yet → zero regression risk; this is the analytical
gate the emission (P1(b)) will hook into EmitWhile. Scoped by workflow w8urlgage (EmitWhile hook, Vector<int>
Reflection.Emit feasibility via RuntimeCalls.cs patterns, associativity of int wrapping add).

## 2026-06-06 — Columnar pipeline STAGE 3: expression type inference (no C# AST) + 2 binder gaps surfaced

Third downstream stage: infer the canonical type of every expression in a function body, walking the columnar
tables directly. `Columnar.ColumnarTypeInferer` + the shared `ColumnarTypeLattice` (numeric promotion,
operator results, literal/element/cast/new types) over the columnar + symbol tables; `:=` locals take their
initializer's inferred type, calls take the function-signature return type (two-pass, forward refs resolve),
BCL forms (member access, non-N# calls) yield `External` (the typed host boundary a later stage fills).
`NSharpCompilerDogfoodAdapter.TryInferTopLevelFunctionTypes` orchestrates it; fallback-safe.
`ColumnarTypes_Inference_MatchesAstWalk` verifies the inferer implements the spec identically to the C#-AST
walk on every dogfood file + hand corpora.

**Adversarial review (3 lenses vs the REAL binder) surfaced two genuine C# binder ECMA gaps** — the binder
does not concretely type bitwise binary ops (`& | ^ << >>` → Unknown) nor numeric-promote unary `-`/`~`
(Analyzer.cs §12.4 gaps); both appear in the corpus (e.g. `BindingLookup.nl` `(lower+upper) >> 1`). It also
correctly flagged that the parity oracle was self-referential. Resolution (behavior-preserving self-host):
`ColumnarTypeLattice` was **aligned to the binder's actual behavior** (bitwise → External/deferred, unary as
the binder does), so the columnar inferer is a faithful replacement rather than silently diverging. The
binder's ECMA gaps are logged as a **reconciliation roadmap item** (fix the binder + promote the lattice, or
keep matching). The DEFINITIVE binder/output parity is verified end-to-end at stages 4-5 (IL that runs
identically) — the right place for it, since intermediate type differences only matter if they change output.

## 2026-06-06 — Rust-perf: auto-vectorization CEILING measured — unrolled Vector<int> = 4.5x over scalar

The first move on the Rust performance bar (after stages 1–2): quantify the prize before any codegen change.
`benchmarks/VectorReductionCeilingBenchmarks.cs` measures `System.Numerics.Vector<int>` reductions vs the
scalar reduction the N# codegen emits today, under the same RyuJIT (Apple M4 / .NET 10), ratios vs scalar:

- single-accumulator `Vector<int>`: **2.08×** faster (N=4096), 3.8× (N=64)
- **4 accumulators (unrolled): 4.5×** faster (N=4096), 5.0× (N=64)

checksum-sum is 8.8× behind C/Rust today; unrolled-vectorized codegen would close it to **≈2× behind native**
(8.8/4.5) — the worst-case kernel becomes top-tier for a CLR language. UNROLLING is the key (a single
accumulator is add-latency-bound at ~2×; four independent accumulators hide the latency, the LLVM trick).
Full numbers + the concrete codegen plan in [`systems-vs-native.md`](systems-vs-native.md) item A. The
codegen itself (recognize the `while`-form counted reduction + emit unrolled `Vector<int>` IL + parity/
benchmark gate) is justified and is the next major, focused Rust-perf effort — large + correctness-critical,
not folded into a slice.

## 2026-06-06 — Columnar pipeline STAGE 2: lexical name resolution over columnar tables (no C# AST)

The second downstream stage: resolve every bare identifier in a function body to its binding, walking the
columnar statement/expression node tables directly — no C# AST.

- `Columnar.ColumnarNameResolver` performs scoped pre-order resolution over the columnar tables: parameters as
  the base scope, `:=` locals entering at their declaration point, Block/While/If bodies introducing nested
  scopes, all top-level functions pre-declared (forward references resolve). Each bare identifier (kind 6)
  classifies as Parameter / Local / Function / NotInScope (the last = BCL/types, a later stage's concern).
  Member names (kind-8 value span) and New/Cast TYPE subtrees (child[0]) are not scope lookups.
- `NSharpCompilerDogfoodAdapter.TryResolveTopLevelFunctionNames` orchestrates it (tokenizer + declarations
  kernel for the pre-declared function set + per-function signature kernel for parameters + statement kernel
  for the body), fallback-safe.
- `ColumnarNames_Resolution_MatchesAstWalk` asserts the columnar resolution is IDENTICAL to the same algorithm
  walking the C# AST — every identifier, same classification, same pre-order — on **every dogfood file** plus
  hand-built corpora (forward refs, while/if scopes, member access, BCL receivers, cast/new). The terrain was
  mapped by a parallel understanding sweep (corpus binding patterns + the C# binder's resolution order +
  the columnar traversal spec); the resolver then passed a 3-lens adversarial review (scoping, traversal
  completeness, mirror fidelity) → clean.

Perf is covered by slice 27 (resolution = the same cache-friendly columnar traversal, ~1.6× faster than the
AST walk, plus O(1) scope-set lookups). Stage 3 (type checking) builds on this + the stage-1 symbol model.

## 2026-06-06 — Columnar pipeline STAGE 1: declared-symbol model (the first downstream stage, no C# AST)

Decision "go big" (2026-06-06): commit to the columnar self-host pipeline (architecture + staged plan in
[`columnar-pipeline.md`](columnar-pipeline.md)). This is stage 1 — the declared-symbol model that name
resolution queries, built DIRECTLY from the columnar declaration + signature tables with NO C# AST
materialization.

- `NSharpCompilerDogfoodAdapter.TryBuildTopLevelFunctionSymbols(source)` → `List<ColumnarFunctionSymbol>`
  (name, modifiers, canonical parameter + return type signatures). It runs the dogfood tokenizer + the
  declarations kernel (kinds + modifier flags) + the per-function signature kernel, and canonicalizes each
  parameter/return type subtree to a string via `ColumnarTypeCanon` — straight off the columnar type tables,
  never building a `FunctionDeclaration`/`TypeReference` object. Conservative + fallback-safe (false on any
  non-function decl or kernel refusal).
- `Columnar.ColumnarFunctionSymbol` (new) holds the symbol; `CanonicalType(TypeReference)` is the matching C#
  AST canon used only by the parity baseline.
- `ColumnarSymbols_TopLevelFunctions_MatchProductionBinderModel` asserts the columnar symbol model matches the
  C# AST-derived model (name + modifiers + canonical signatures) on **every dogfood file** plus hand-built
  corpora (arrays, generics, nullable, casts). First proof that the columnar IR feeds a real **semantic
  model**, not just round-trips through the parser.

This is the foundation stage 2 (name resolution → symbol IDs) builds on. Per the pipeline design rules, the
never-slower benchmark + production routing (with C# fallback) come with stage 2's integration; the front-end
and downstream-traversal perf are already established (slices 26–27: 2.4× faster parse, ~1.6× faster passes,
no AST allocation). Design rule reaffirmed: resolve names to symbol IDs once — the symbol model is the place
that interning will live.

## 2026-06-06 — Slice 27: downstream-pass spike — the columnar win COMPOUNDS past the parser

Validates the columnar-pipeline thesis on the NEXT stage after parsing. `ColumnarSemanticPassBenchmarks`
takes an already-parsed file and runs the SAME semantic pass two ways — collect the distinct identifier names
referenced in every function body (a full traversal with representative per-node work) — on the C# object-graph
AST vs the flat columnar int[] node tables. Parsing is done in Setup, so this isolates the PASS. Apple M4 /
.NET 10, LargeGenerated (40 funcs), ratios vs the C# AST pass:

| Pass | Time | Alloc |
|---|---|---|
| C# AST walk (recursive visitor) | 1.00× (11.2 µs) | 1.00× (368 B) |
| Columnar scan, naive `Substring` per ref | **0.62× (1.6× faster)** | 53× (19.6 KB) |
| Columnar scan, **interned names** | **0.64× (1.56× faster)** | 2.74× (1.0 KB) |

**Findings:**
- **Columnar traversal is ~1.6× faster** than walking the AST — sequential int[] scan vs virtual-dispatch
  pointer-chasing. The traversal advantage is real and holds past the parser.
- **Name handling matters:** the naive columnar scan re-materializes a string per identifier *occurrence*
  (53× alloc). Done right — intern each distinct name once (a span-keyed lookup; in a real pipeline, integer
  symbol IDs) — allocation collapses to ~1 KB. This is standard fast-compiler practice, not a columnar flaw.
- **The C# pass's tiny 368 B is an illusion:** it reuses strings already allocated in the **662 KB AST built
  at parse time** (slice 26). The columnar path never builds that AST. So end-to-end (parse + N passes) the
  columnar pipeline wins decisively and the gap **compounds with each pass** — every AST pass re-walks the
  600 KB+ graph; every columnar pass scans tiny, cache-resident int[] tables.

**Verdict:** the 2.4×-faster front-end (slice 26) is not a one-off — the advantage carries into downstream
semantic passes (~1.6× faster, no AST allocation). This confirms the columnar self-host pipeline (port the
binder/analyzer to consume the columnar tables directly, with interning/symbol IDs) is the path that BOTH
eliminates the C# reliance AND captures the speed. The naive-vs-interned result also pins the one design
rule: never re-materialize names per access — resolve to symbol IDs once.

## 2026-06-06 — Slice 26: routing-cost DECOMPOSITION — the front-end is 2.4x FASTER; the tax is materialization, not marshaling

Slice 25 showed routing is ~4-5x slower end-to-end, but lumped the causes together. This slice decomposes the
cost with two more `CompilationUnitRoutingBenchmarks` variants (columnar-parse-only with fresh per-function
tables, and the same with POOLED tables), isolating each tax. Apple M4 / .NET 10.0.5, LargeGenerated (40
funcs), ratios vs the C# parser (ratios are stable; absolute µs drift with machine temperature):

| Variant | Time | Alloc |
|---|---|---|
| **Columnar front-end, POOLED tables, no materialize** | **0.41× (2.4× FASTER)** | 1.88× |
| Columnar front-end, fresh per-function tables, no materialize | 3.65× slower | 16.95× |
| Full routing (fresh tables + materialize → C# AST) | 5.52× slower | 18.5× |

On a small file the pooled front-end is **0.39× time (2.6× faster) and 0.51× allocation (HALF of C#)**.

**The regression is NOT a marshaling/boundary problem.** The delegate boundary is crossed identically in the
pooled variant, which is 2.4× *faster* — so the C#↔N# boundary is negligible. The 4-5x came from two
separable taxes:

1. **Table over-allocation (fixable artifact):** pooled → fresh is 0.41× → 3.65× and 1.88× → 16.95× alloc.
   The naive orchestrator (and `TryParseCompilationUnit`) allocate ~19 int[] tables sized to the *whole file*
   *per function*, i.e. O(funcs·N). Pooling/right-sizing the buffers removes it entirely. Not fundamental.
2. **Materialization to the C# AST (the real, structural tax):** no-materialize → materialize adds the rest.
   This is the cost of rebuilding the C# object-graph AST (`ColumnarAstMaterializer`) so the *C# binder/
   analyzer/codegen* can consume it.

**Conclusion — and the answer to "how do we eliminate C#":** the N# parser front-end is genuinely **2.4×
faster than C# and lower-allocation** when it is NOT forced back into the C# AST. Materialization exists ONLY
because the downstream stages are still C# and consume the C# `CompilationUnit`/`Statement`/`Expression`
records. So **"eliminate the C# reliance" and "capture the speed win" are the same goal**: port the binder/
analyzer (and eventually codegen) to N# consuming the columnar tables directly — no materialization, no C#
AST, no boundary. Materialization is a *symptom of the half-ported state* (N# parser feeding a C# back end),
not an integration bug to optimize. The path is a columnar semantic pipeline, built incrementally downward
from the (now correctness-complete, 2.4×-faster) parser, with pooled tables. Next concrete step: a contained
spike — one semantic pass (declaration/symbol collection) reading the columnar tables directly, benchmarked
vs the C# AST-based pass — to confirm the win compounds past the parser before committing to the full port.

## 2026-06-06 — Slice 25: END-TO-END routing benchmark — materialization erases the kernel's win (never-slower FAILS)

The never-slower gate for flipping parser routing on. `CompilationUnitRoutingBenchmarks` measures the full
**source → `CompilationUnit`** path both ways: the C# `Parser` (Lexer + ParseCompilationUnit) vs the N#
routing path (dogfood tokenizer + declarations/signature/statement kernels + `ColumnarAstMaterializer`).
Apple M4, .NET 10.0.5:

| Corpus | C# parser | N# routing | Time | Alloc |
|---|---|---|---|---|
| Representative (~2 funcs) | 6.28 µs / 21.95 KB | 5.12 µs / 61.58 KB | **0.82× (faster)** | **2.81× more** |
| LargeGenerated (40 funcs) | 214.6 µs / 662 KB | 934.9 µs / 12.2 MB | **4.36× slower** | **18.5× more** |

**Verdict: routing stays OFF.** On realistic input the routed path is **4.36× slower and allocates 18.5×
more**. This is *fundamental*, not a tuning gap:

1. **Materialization re-creates the C# object-graph AST** — the routed path allocates the *same* records the
   C# parser does (via `ColumnarAstMaterializer`), so routed allocation is **C#'s allocation + the columnar
   int[] tables**, i.e. strictly greater. Materializing to the C# AST can never beat the C# parser on memory.
2. **Per-function table over-allocation** — each function allocates ~11 int[] arrays sized to the whole-file
   token count, so a 40-function file allocates O(40·N) table memory vs the parser's O(N).
3. Plus re-tokenization and delegate-boundary overhead.

The statement kernel's **5–6× raw-parse win (slice 21) does NOT survive materialization.** The kernel is fast
because it writes compact int[] tables instead of an object graph; materializing those tables back into the
object graph throws that advantage away.

**Implication for the endgame:** the self-host *speed* win is **not** "route the parser + materialize to C#
records" — that path regresses perf. The real win requires the binder/analyzer/codegen to **consume the
columnar tables directly (zero materialization)**, with pooled, right-sized tables — a large architectural
bet (a columnar semantic pipeline), not parser routing. The slice-24 routing path remains valuable as the
**correctness oracle** (it proves the N# parser parses 100% of its own source identically to C#) and as the
front-end for that future columnar pipeline — but it must not be the production speed path while it
materializes. See also [`compiler-dogfood-boundary-profiling.md`](compiler-dogfood-boundary-profiling.md).

## 2026-06-06 — Slice 24: PRODUCTION ROUTING + cast expressions — the N# front-end parses 100% of its own systems source

The N# parser front-end is now **wired into the production parse path** and parses the entire dogfood
compiler-service corpus (32 `CompilerServices/*.nl` files) **byte-for-byte identically** to the C# parser.

- **`NSharpCompilerDogfoodAdapter.TryParseCompilationUnit`** (new): a whole-file orchestrator that runs the
  dogfood tokenizer + declarations kernel (imports/package/decl kinds) + per-function signature & statement
  kernels + `ColumnarAstMaterializer`, assembling a production `CompilationUnit`. It is conservative and
  **fallback-safe**: any non-function top-level declaration, package declaration, or kernel refusal makes it
  return `false` so the C# parser handles the file.
- **`Parser.ParseCompilationUnit()` routes through it** when `NSharpCompilerDogfoodAdapter
  .ParserFrontEndRoutingEnabled` is set (env var `NSHARP_PARSER_FRONTEND=1`). **Off by default**, so
  production behavior is unchanged until the end-to-end benchmark (next) justifies flipping it on.
- **Cast expressions (kind 16)** were the *only* gap to full-corpus parity. Building the orchestrator + a
  whole-corpus parity test surfaced that the expression kernel silently mis-parsed C-style casts `(int)x` as
  `(int)` (parenthesized) + a stray statement — a real refusal-incompleteness bug. Added faithful cast
  detection to `ParserExpressions.nl` mirroring `Parser.cs` `IsCastExpression`: speculatively parse a type
  after `(`, and if it is followed by `)` and an expression-start token (`IsExpressionStartKind`, mirroring
  C#'s `IsExpressionStart`), emit a `CastExpression`; otherwise roll back and parse as parenthesized. With
  casts, the corpus went from 29/32 to **32/32 files routed, 0 divergent**.
- **Safety:** `Router_CompilationUnit_MatchesProductionParserAst` asserts every dogfood file routes AND
  matches the C# parser structurally (the corpus is the safety proof — a silently-wrong tree fails here).
  `Router_RefusesUnsupportedForms` proves the front-end declines class/struct/enum/package/`let`/`foreach`
  (so "kernel didn't refuse" + whole-file acceptance is a trustworthy routing signal).

This is the self-host **parser** milestone: the N# parser is genuinely USED in production (env-gated) and is
correct on 100% of the compiler's own systems source. Next: end-to-end benchmark (routed tokenize+kernels
+materialize vs C# Lexer+Parser) — the never-slower gate before flipping the default on — then expand the
supported declaration forms (types/classes) and begin shrinking the C# parser surface.

## 2026-06-06 — Slice 23: whole-function-declaration materialization (the routing unit)

Composes the fnsig kernel (name + parameter names/types + return type) and the statement kernel (body) and
materializes both into a C# `FunctionDeclaration` via `ColumnarAstMaterializer`. Verified
(`Materializer_FunctionDeclaration_MatchesProductionParserAst`) on every dogfood function within the
supported forms (>30 real functions): name, each parameter's name + type tree, return type tree, and the
whole body all match the production parser's `FunctionDeclaration` shape. So the full pipeline
**tokenize → parse signature + body (N# kernels) → materialize (C#) → FunctionDeclaration** now round-trips
real compiler functions. This is the declaration-level unit the whole-file `CompilationUnit` materialization
and the production routing are built from. Next: assemble imports + declarations → `CompilationUnit`, then
wire it into an actual production parse path (behind an engine flag, C# fallback for unsupported forms) so
the N# front-end is demonstrably USED in production — then drive coverage up and shrink the C# parser/adapter
surface.

## 2026-06-06 — Slice 22: MATERIALIZATION — columnar front-end → production C# AST (the routing bridge)

The first real step beyond "verified-but-unrouted": `ColumnarAstMaterializer`
(src/NSharpLang.Compiler/ColumnarAstMaterializer.cs) turns the N# front-end's columnar node table (the flat
int[] forest the kernels emit) into the production C# AST records (`Expression`/`Statement`/`TypeReference`)
the rest of the compiler consumes. This is the bridge between the fast columnar parser output and a usable
`CompilationUnit` — the prerequisite for routing the N# front-end into production and deleting the C#
`Parser`. Dispatches by node kind, disambiguating shared type/expr kind ranges positionally (e.g. a New
node's child[0] is a type subtree, the rest are argument expressions), and derives Line/Column from byte
spans via a line map.

Verified by `Materializer_Expression_MatchesProductionParserAst`: each corpus expression's columnar output
is materialized and **structurally identical** (positions aside — operator nodes key off different tokens)
to the C# parser's `Expression`; AND every dogfood function body within the supported forms (>30 real bodies)
is materialized into a C# `BlockStatement` matching the production parser's `FunctionDeclaration.Body`. Found
+ matched a real fact: the C# parser keeps char/string `Value` as the verbatim source token (quotes
included, no unescape), so the materializer uses the raw span.

This is the honest answer to "is the bridge eliminated?" advancing from "no, nothing" toward "the bridge now
EXISTS and round-trips real code." Remaining to actually delete `Parser.cs`: (1) whole-FILE materialization
(imports + function declarations w/ signatures + bodies → `CompilationUnit`), (2) full language-form parity
(handle arbitrary N#, not just the supported subset), (3) route the production parse path through
tokenize→parse→materialize and delete/shrink the C# parser + `*DogfoodAdapter` surface.

## 2026-06-06 — Systems N# vs Rust vs C head-to-head + direction decision

Ran the `systems-nsharp-vs-rust-c` workflow (5 phases, adversarial fairness). Full report:
[`systems-vs-native.md`](systems-vs-native.md); reproducible harness: `benchmarks/native-comparison/`;
deferred-bet backlog: [`systems-vs-native.md`](systems-vs-native.md). Headline: **systems-N# ties
C#/RyuJIT (top-of-class among CLR languages) but trails Rust/C by 1.4×–10.5×**, entirely RyuJIT's missing
auto-vectorization (N# ties C# everywhere → 100% of the native gap is RyuJIT codegen, not N#-specific). The
adversarial pass caught + I fixed two `clang -O3` DCE'd C harnesses (per-iteration pointer-launder barrier);
now 6-of-6 clean.

**Decision (user, 2026-06-06):** finish self-host (the Roslyn-class N# entry point) and sharpen the evidence
first; **backlog** the two big perf bets (auto-vectorization codegen; LLVM/NativeAOT backend) — see
systems-vs-native.md. Key unblocker this gives the self-host work: since systems-N# is performance-neutral
vs C#, porting compiler hot paths to N# carries NO speed regression, so the migration proceeds on
correctness/ergonomics. Near-term order: (1) sharpen evidence (broaden the comparison corpus from synthetic
i32 kernels to a real compiler hot path — token scan / symbol-table probe), (2) resume finishing the N#
front-end + production routing (materialize the columnar AST into the host CompilationUnit / N# consumers,
route CLI/LSP, delete C# `*DogfoodAdapter` surface — the still-untouched criteria 5-6).

## 2026-06-06 — N# parser slice 21: front-end perf benchmark — the N# parser is ~5-6x faster than C# (clears the 5x gate)

The perf answer for the parser front-end (benchmark-first, per the loop). `CompilerServiceParserBenchmarks`
(benchmarks/CompilerServiceParserBenchmarks.cs) parses the SAME supported-form function body with the
N#-native statement kernel (`ParseStatementNodesInto`, composed lexer→type→expression→statement, compiled
from the concatenated kernel sources) vs the production C# `Parser`. Tokenization is done once in setup;
the benchmark measures the PARSE phase only. `[MemoryDiagnoser]` captures allocation.

Results (`--job short`, this machine):

| Corpus         | N# kernel | C# parser | Speedup | N# alloc | C# alloc | Alloc ratio |
|----------------|-----------|-----------|---------|----------|----------|-------------|
| Representative | 550 ns    | 3,266 ns  | **5.9x**| 400 B    | 5,688 B  | 14x less    |
| LargeGenerated | 15.9 us   | 83.3 us   | **5.2x**| 8,608 B  | 148,224 B| 17x less    |

The N# columnar parser is **~5-6x faster and allocates 14-17x less**, and **clears the acceptance standard's
5x gate** (3266/550 = 5.94x; 83259/15887 = 5.24x) on both corpora. This is the first hard evidence that the
N# parser approach meets the "at least as fast as C#, ideally faster" bar — decisively.

**Honest framing of the comparison.** The two implementations are behaviorally equivalent (the kernel's tree
is parity-verified node-for-node against the C# parser by slice 20's whole-body pin) but represented
differently: the C# parser allocates a record per AST node + `List`s; the N# kernel writes a flat columnar
node table into caller-pre-allocated arrays (its only per-call allocation is the small `st`/`argStack`
scratch — hence 400 B / 8,608 B). The columnar design IS the source of the win; this is exactly the
"systems-tier N# beats allocating C#" thesis. The C# baseline also parses the trivial `func benchBody() {…}`
wrapper (signature + constructor token-compaction); for the body-dominated LargeGenerated corpus that
overhead is negligible, so the 5.2x there is the conservative, representative number.

This is the acceptance-standard speed gate met for the front-end parse path. Remaining toward full
acceptance: (1) complete parser parity for the deferred language forms, and (2) production routing of the
in-assembly N# front-end (materialize the columnar table into the host's `CompilationUnit`, or route N#
consumers) so the CLI/LSP path actually uses it — the swap-evidence criterion.

## 2026-06-06 — N# parser slice 20: real-corpus WHOLE-BODY pin (capstone — the N# parser parses real compiler code)

The capstone dogfood validation. Runs the full N#-native front-end statement kernel — which composes the
type + expression + `new` kernels in-assembly over one shared columnar node table — on every dogfood
compiler-kernel function body whose statements stay within the supported forms, and compares the resulting
statement tree **structurally to the C# parser's `FunctionDeclaration.Body`**. This is the N# parser parsing
the actual N# compiler kernels (real recursive-descent compiler code: `:=` declarations, `while`/`if`/`else`,
`return`/`break`/`continue`, assignments, calls, member/index access, the full operator precedence chain,
`new int[](...)`) and matching the production parser node-for-node. 30+ supported-form bodies verified; bodies
using a not-yet-supported form (deferred expression/statement kinds) are skipped and counted via a recursive
`IsSupportedStatement`/`IsSupportedExpr` filter, with a per-file func-count safety net so nothing is silently
mis-paired. Test-only (no kernel change). **No language gaps surfaced — the N# parser reproduces the C#
parser's AST on real compiler code.**

This closes the parser self-host arc for the supported language subset: slices 1-5 (declaration index),
6-8 (type-reference grammar), 9 (function signatures), 10-15 (full common expression grammar), 16-17
(statements + control flow), 19 (`new` + type/expr composition), and now whole-body parity on real code.
Remaining for FULL parser parity (each a future slice): for/foreach, let/const + typed local declarations,
tuple deconstruction, the remaining statement forms (throw/try/using/lock/switch/yield/print/assert), and the
remaining expression primaries (`new[size]`/`new{init}`, match, tuple, array/object literals, interpolated
strings, lambdas, is/as, range, cast). After full parity: production routing of the in-assembly front-end
behind a 5x benchmark (the acceptance-standard endgame).

## 2026-06-06 — N# parser slice 19: st-layout unification + `new` expressions (type/expr kernel composition)

Unblocks whole-body parsing of the dogfood kernels, which use `new int[](...)` array allocation (20 sites).
A `NewExpression` composes the TYPE kernel (the constructed element type) with the EXPRESSION kernel (the
constructor arguments) in one node tree — which required the two kernels to share parser state. They had
incompatible `st` slot layouts, so this slice **unified the `st` layout**: the type + function-signature
kernels' slots were remapped (via a precise simultaneous regex remap, 75 + 16 refs) to match the expression
layout — `st[0]=pos, st[1]=nodeCursor, st[2]=childCursor, st[3]=argStackTop, st[4]=splitGreaterDepth,
st[5]=owedGreaterByteEnd` — and the expr/statement kernels now allocate a 6-slot `st`. The remap is a pure
no-behavior-change refactor, verified by the type + fnsig parity tests passing unchanged.

`new <type>(args)` (kind 15) then drops cleanly in: `ParsePrimaryExpressionNode` calls the type kernel for
the element type (child[0]) and the expression kernel for the positional constructor args (children 1+),
sharing the unified `st` + `argStack`. The type child is a type-kernel subtree (kinds 0-5) and the args are
expression subtrees (kinds 0-14) in ONE table; the host walker disambiguates **positionally** (child[0] →
type walker, rest → expression walker), so the overlapping kind numbers never conflict. The shared `argStack`
stays LIFO-safe under nesting (`f(new List<int>(k))`: the type's generic-arg gathering pushes/pops within the
new's arg region, which nests within the call's). Verified against the production parser's NewExpression on
`new int[](n)`, `new char[](length + 1)`, `new Foo()`, `new List<int>()`, `new int[](count + 1)`, and
nested `f(new int[](k))` / `buffer = new int[](count + 1)`, plus all five existing parser parity tests
(type/fnsig/expr/statement/real-corpus) still green, then a focused adversarial-refutation pass
(new-composition + shared-state-safety lenses).

**Adversarial pass found + fixed 1 fragility:** the `new` branch called the type kernel without first
resetting `st[4]` (splitGreaterDepth), inconsistent with the function-signature kernel which resets it
before every type parse. Latent for valid input (a balanced generic always leaves `st[4]=0`), but the
"`st[4]==0` entering a type parse" invariant should be explicit, not rely on the caller's prior state.
Fixed by resetting `st[4]=0` before the call (NOT `st[3]`/argStackTop — that is the nested LIFO base);
pinned with nested-generic `new` cases (`new List<List<int>>()`, two-news-in-sequence).

Deferred: `new <type>[size]` (sized array), `new <type>{init}` (object initializer), target-typed `new(...)`,
named/ref/out constructor args. Milestone: the front-end kernels (lexer → type → expression → statement)
now compose in-assembly over one shared node table — the substrate for parsing whole dogfood function bodies.

## 2026-06-06 — N# parser slice 18: real-corpus expression pin (anti-overfitting)

Validates the slice 10-15 expression kernel against the production parser on REAL dogfood code — the
anti-overfitting discipline the lexer's 108-file pin established. For each dogfood `.nl` kernel, every
`return <expr>` value whose expression stays within the supported forms (recursively: literals/identifiers/
parenthesized/member/index/call/prefix-unary/binary/ternary/assignment) is parsed by
`ParseExpressionNodesInto` and compared structurally to the C# AST (50+ real return expressions verified).
A per-file safety net — skip the file if the recursively-collected return count disagrees with the `return`
token count — means a missed statement-container in the harvest can never silently mis-pair returns. No
language gaps surfaced; the expression kernel reproduces the C# expression AST on real compiler code.

**Next-step architectural note:** parsing whole dogfood function bodies (the natural real-corpus *statement*
pin) is blocked on `new int[](...)` array-allocation, which is ubiquitous in the kernels. A `NewExpression`
composes the TYPE kernel (its element type) with the EXPRESSION kernel (its arguments) in one node tree, but
the two kernels currently use incompatible `st` slot layouts (type: pos/splitDepth/nodeCursor/childCursor/
owedGreaterByteEnd/argStackTop; expr: pos/nodeCursor/childCursor/argStackTop). The clean unblock is to unify
the `st` layout (expr already matches slots 0-3; renumber the type kernel's slots and let both use a 6-slot
`st`, with the New node bridging a type child + expression-argument children positionally). That is the next
deliberate slice; the type parity test (`Parser_TypeReferenceTree_MatchesProductionParser`) is a fast safety
net for the renumber.

## 2026-06-06 — N# parser slice 17: control flow — blocks, while, if/else

Restructures the statement kernel into a recursive dispatcher (`ParseStatementCoreNode`) and adds
`BlockStatement` (kind 25, `{ stmt* }` — children gathered on the LIFO arg-stack), `WhileStatement`
(kind 26, children [condition, body]), and `IfStatement` (kind 27, children [cond, then, else?]). Following
the C# parser, if/while bodies are ANY statement (a `{ }` block or a single statement), so they recurse
through the dispatcher; `else if` chains as a nested if in the else child. This lets the kernel parse whole
function bodies. Verified against the production parser's Statement AST on blocks, while, if/else, else-if
chains, break/continue in loops, and **deep nesting** (`while i < n { if arr[i] == target { return i }
i = i + 1 }`) which stresses the block arg-stack under recursion (nested blocks push/append/pop within their
own region, LIFO). Followed by a focused adversarial-refutation pass (structure + bounds/arg-stack lenses).

**Language feature exercised:** the N# compiler's own unused-parameter lint (NL012) caught a dead `depth`
parameter in `ParseSimpleStatementNode` during this slice — a nice dogfood signal that the analyzer works on
real kernel code. Fixed by dropping the parameter.

Deferred: for/foreach, let/const/readonly + typed `name: Type = init` declarations, tuple deconstruction,
throw/try/using/lock/switch/yield/print/assert/local-functions, and `new`/`alloc` initializers. Next: those
remaining statement/expression forms as needed, then a real-corpus pin over whole dogfood function bodies.

## 2026-06-06 — N# parser slice 16: simple statements (statement subsystem begins)

Starts the last major parser subsystem — function bodies, the critical path for parsing the dogfood kernels
(flat top-level functions whose bodies are statements). `ParseStatementNodesInto` (new
`ParserStatements.nl`) parses ONE statement, dispatching like the C# `ParseStatement` (Parser.cs:2165), and
COMPOSES the slice 10-15 expression kernel into a SHARED node table (statement kinds 20+, expression kinds
0-14): `ReturnStatement` (20, optional value child), `BreakStatement` (21), `ContinueStatement` (22),
`ExpressionStatement` (23, incl. assignment expressions like `x = e`/`x += 1`), and
`VariableDeclarationStatement` (24, the `:=` shorthand after a bare identifier — name in the value span,
initializer child). `:=` (ColonAssign 121) is the declaration; `=` (Assign 93) is an assignment expression
wrapped in an ExpressionStatement. Verified against the production parser's Statement AST (extracted from a
`func f() { <stmt> }` body) on return-with/without-value, break/continue, `:=` declarations, assignment and
call expression-statements, with full-consumption (the statement ends at the body `}`).

Deferred to later slices: control flow (if/else, while, for, foreach) and their nested blocks (the block
kernel parsing a `{ ... }` sequence is next); let/const/readonly and typed `name: Type = init` declarations;
tuple deconstruction; throw/try/using/lock/switch/yield/print/assert/local-functions; and `new`/`alloc`
initializers (a deferred expression primary). No language gaps surfaced.

## 2026-06-06 — N# parser slice 15: ternary + assignment (expression top)

Adds the two levels above the binary chain (mirroring `ParseTernaryExpression` Parser.cs:3916 and
`ParseAssignmentExpression` Parser.cs:3599): `TernaryExpression` (kind 13, `cond ? then : else`, children
[cond, then, else]) and `AssignmentExpression` (kind 14, `target OP value` for `=`/`+=`/`-=`/`*=`/`/=`/`??=`,
operator token in the value span, children [target, value]). Assignment is right-associative (`a = b = c`
=> `a = (b = c)`) and the ternary else-branch is a full expression, so it nests right (`a ? b : c ? d : e`).
The "full expression" entry now routes through assignment -> ternary -> binary -> unary -> postfix ->
primary. Verified against the production parser's TernaryExpression/AssignmentExpression on nesting,
right-associativity, compound assignments, and composition (`result = cond ? f(x) : g(y)`,
`total = total + n`, `x ??= y`), plus the full expression corpus, refusals, determinism, root-span, and
full-consumption invariants.

**Milestone:** the N# expression kernel now covers the full common expression grammar — primaries, postfix
(member/index/call), prefix unary, the binary precedence chain, ternary, and assignment. Remaining for full
parity: `is`/`as`, range `..`, lambdas, and the less-common primaries (new/alloc/match/tuple/array&object
literals/interpolated strings/cast). Next: statements (the function bodies — the last major piece for
parsing the dogfood kernels), composing this expression kernel. No language gaps surfaced.

## 2026-06-06 — N# parser slice 14: binary-operator precedence chain (expression core complete)

Adds the full left-associative binary precedence chain via **precedence climbing**
(`ParseBinaryExpressionNode` + `BinaryOpPrecedence`, mirroring the C# levels
ParseNullCoalescing..ParseMultiplicative, Parser.cs:3940-4185): `??` < `||` < `&&` < `|` < `^` < `&` <
`==`/`!=` < relational(`<` `<=` `>` `>=`) < shift(`<<` `>>`) < `+`/`-` < `*`/`/`/`%`. Each
`BinaryExpression` (kind 12) records the operator token in the value span with children `[left, right]`
(fixed arity → contiguous, no arg-stack). The left-associative formulation (parse RHS at `precedence + 1`)
reproduces the same left-leaning trees as the C# while-loop levels; the "full expression" entry is
`minPrec == 1`. Operators above this chain (`is`/`as`, range `..`, assignment, ternary) correctly STOP the
loop (deferred). Verified against the production parser's BinaryExpression on precedence boundaries
(`1 + 2 * 3`, `a == b && c != d`, `x | y & z`), left-associativity (`a - b - c`), and composition with
postfix/unary (`i < count && tokenKinds[pos] == 102`, `f(x) + g(y) * 2`, `!found && i < n`), then a focused
adversarial-refutation pass (precedence/associativity + safety/dual-use lenses).

**Milestone:** the N# expression kernel now covers the core expression grammar — primaries, full postfix
(member/index/call), prefix unary, and the complete binary precedence chain — enough to parse the bulk of
real dogfood expression shapes. Remaining for full expression parity: `is`/`as`, range, assignment,
ternary, and the less-common primaries (new/alloc/match/tuple/array&object literals/interpolated strings/
lambda/cast). Next natural step: a real-corpus expression pin over the dogfood kernel bodies (supported-form
filtered), then statements. No language gaps surfaced.

## 2026-06-06 — N# parser slice 13: prefix unary expressions

Adds the unary level (`ParseUnaryExpressionNode`, mirroring `ParseUnaryExpression` Parser.cs:4223):
prefix `!` (Not), `-` (Negate), `~` (BitwiseNot), `++` (PreIncrement), `--` (PreDecrement), `^`
(IndexFromEnd) wrapping a recursively-parsed unary operand -> `UnaryExpression` (kind 11, the operator
token in the value span). The "full expression" recursion points (entry, parenthesized-inner, index, call
arguments) now route through this unary level, so prefixes compose with postfix: `-arr[i]`, `!a.b`,
`-f(x)`, `!!x`, `-(value)`. Verified against the production parser's UnaryExpression (operator + recursive
operand) plus the full primary/postfix corpus, refusals, determinism, root-span, and full-consumption
invariants. Prefix `+` is invalid in N# and is refused (fall-through to primary). Postfix `++`/`--` and
`must` are deferred. Next: the binary-operator precedence chain (after which a real-corpus expression pin
over the dogfood kernel bodies becomes possible). No language gaps surfaced.

## 2026-06-06 — N# parser slice 12: call expressions (postfix level complete)

Adds `CallExpression` (kind 9) to the postfix loop: `callee(args)` with children `[callee, arg0, arg1, ...]`.
Arguments are variable-arity, so the callee + argument node ids are gathered on a caller-owned LIFO
arg-stack (the exact pattern the type kernel uses for generic arguments — recursion is LIFO, append the
contiguous child run after the closing `)`) — the expression kernel's `st` gains `st[3]=argStackTop` and an
`argStack` array. Composes with member/index: `obj.method(x)`, `f(g(x))`, `f(a)(b)` (curried), `f(x)[i]`,
`compute(a, b, c).result`. Verified against the production parser's CallExpression (callee + positional
argument trees, no type arguments) on empty/single/multi/nested/curried/mixed calls, plus refusals (-1) for
named (`f(x: 1)`) and ref/out (`g(ref y)`) arguments (deferred), plus determinism, root-span, and
full-consumption invariants.

The N# expression kernel now covers the full primary + postfix level (literals, identifiers, parenthesized,
member access, indexing, calls). Deferred: `?.`/`?[`, generic calls, `++`/`--`, `with`, then unary and the
binary precedence chain (after which a real-corpus expression pin over the dogfood kernel bodies becomes
possible). No language gaps surfaced.

## 2026-06-06 — N# parser slice 11: postfix expressions (member + index access)

Extends the expression kernel with the postfix level (`ParsePostfixExpressionNode`, mirroring
`ParsePostfixExpression` Parser.cs:4312): a primary followed by any run of `.member` (MemberAccess, kind 8 —
member name in the value span) and `[index]` (IndexAccess, kind 10 — children [object, index]) suffixes. The
entry and the parenthesized-inner now route through this postfix level, so chains compose:
`arr[i].field`, `a[b][c]`, `(x).y`, `data[i].next.value`. Index expressions recurse to the postfix level.
Both forms are fixed-arity, so their child runs stay contiguous by appending right after the object/index
are fully parsed — no arg-stack needed (that is reserved for the variable-arity CallExpression in the next
slice). Verified against the production parser's MemberAccess/IndexAccess (member name + recursive object/
index trees, non-null-conditional) on member/index/mixed chains, plus the existing primary corpus, refusals,
determinism, root-span, and full-consumption invariants.

Deferred: CallExpression (kind 9, reserved — needs the arg-stack for variable arity), `?.`/`?[`
null-conditional, generic method calls, `++`/`--`, `with`; then unary and the binary precedence chain. No
language gaps surfaced.

## 2026-06-06 — N# parser slice 10: primary expressions (the expression subsystem begins)

Starts the largest parser subsystem — the ~17-level expression precedence chain
(Parser.cs ParseExpression..ParsePrimaryExpression). This is the critical path for self-hosting the dogfood
kernels themselves, which are flat top-level functions whose BODIES are statements + expressions (they have
no type members). `ParseExpressionNodesInto` (new `ParserExpressions.nl`) parses PRIMARY expressions —
int/float/char/string/bool/null literals (kinds 0-5), identifiers (kind 6), and parenthesized expressions
(kind 7, `( expr )`) — into a columnar node table (post-order, root last), mirroring
`ParsePrimaryExpression`. Verified against the production parser's Expression AST (extracted from a
`return <expr>` statement) on every primary form incl. nested parens, plus refusals (-1) for tuples
`(a, b)`, named elements `(x: e)`, and non-primary leads (`+5`, `.x`, `)`), plus determinism, root-span, and
full-consumption (continuation lands on the block's `}`) invariants.

Deferred to later slices (the rest of the chain): postfix (call/index/member access), unary, the binary
precedence chain, assignment, ternary, range, new/alloc, match, tuples, array/object literals, interpolated
strings, lambdas, casts. Literal VALUE materialization (unescaping) stays the host's job — the kernel
records the value token's byte span (int/float values verified to equal that span; string/char are
kind-only). No language gaps surfaced.

## 2026-06-06 — N# parser slice 9: function signatures (first declaration-level kernel, composes the type kernel)

The first slice that goes ABOVE type references: `ParseFunctionSignatureInto` (new
`ParserFunctionSignatures.nl`) parses a function's signature — name, parameter names + parameter type
trees, and the return type tree — mirroring C# `ParseFunctionDeclaration`/`ParseParameterList`
(Parser.cs:405-535, 770-840). It COMPOSES the slice 6-8 type kernel: every parameter type and the return
type are parsed by `ParseUnionTypeReferenceNode` and share ONE columnar node table (each is an independent
root), with the shared parser-state array carrying the node/child cursors across the per-type parses while
`st[0]` is repositioned to each type's start. This proves the kernels compose cleanly in-assembly
(cross-file calls within the merged `Program` type) — the pattern the whole N# parser will use.

Handles parameter modifiers (`ref`/`out`/`params`/`this`, skipped), attribute lists (skipped), `= default`
values (skipped balanced, not parsed), and optional `<TypeParams>` between the name and `(` (skipped by
scanning to the first `(`). Verified against the production parser's `FunctionDeclaration`
(Name, Parameters[].Name/.Type, ReturnType) on a synthetic corpus exercising every supported param/return
form plus modifiers/defaults/`this`/generic-function, AND on a real-corpus pin: **every top-level function
in the dogfood kernels whose signature stays within the supported type forms (>100 verified)**, with
deferred-form signatures filtered out and counted.

**Adversarial pass found + fixed 2 real defects.** A focused refutation pass (signature-correctness +
bounds-safety lenses) confirmed that on a MALFORMED default value with unbalanced brackets (e.g.
`func f(x: int = {): void`), the default-value skip's single depth counter let a `)` close a `{`, so the
scan ran past the parameter list's `)` and silently mis-parsed (wrong parameter count / dropped return
type). Valid input was always correct (the corpus + real-corpus pin passed), but silent wrong output on
malformed input violates the rock-solid bar. Fix: after skipping a parameter's optional default, require
the next token to be `,` or `)` — otherwise refuse with -1 (fail-fast; full error recovery stays deferred).
Locked with negative tests (`= {`, `= (,`, `= [` → -1).

**Finding — the parser layer consumes a newline-compacted token stream.** The C# `Parser` drops every
`Newline` token in its constructor (Parser.cs:24-26); N# is not newline-significant at the parse level
(indentation already became virtual braces in the lexer). The single-line type-reference tests never hit
this, but real multi-line signatures do, so the host now compacts the lexer's raw token arrays (removing
ordinal 136) before invoking the parser kernels — matching production. Byte offsets are unaffected. No
language gaps surfaced.

## 2026-06-06 — N# parser slice 8: by-ref type references + the source-access limit finding

Adds `ByRefTypeReference` (`&T`, node kind 5) to the type kernel — `&` prefixing a postfix type, placed in
`ParseBaseTypeReferenceNode` exactly as the C# parser (Parser.cs:1830-1840), so a by-ref is reachable as a
union arm or generic argument too (`&int | string`, `List<&int>`). Verified against the production parser
on `&int`, `&List<int>`, `&int[]`, by-ref-as-generic-arg, and by-ref-in-union.

The N# type-reference parser now covers Simple / Generic / Array / Nullable / Union / ByRef — the
overwhelming majority of real type references — each parity-verified against `Parser.cs`.

**Finding (documented, not a hack): the two remaining type forms hit real design limits, not parser bugs.**
- **`Func<...>`** — the C# parser special-cases the *identifier text* `"Func"` to produce a
  `FunctionTypeReference` (Parser.cs:1849-1852). The kernel works on token kind/offset arrays and has **no
  source string**, so it cannot distinguish `Func` from any other generic name; it would parse `Func<...>`
  as a `GenericTypeReference`. Func is therefore excluded from the corpus. Resolving it requires giving the
  parser kernels **source access** (a future architectural step that also unlocks name-based contextual
  keywords like `duck`/`scoped` and on-the-fly name materialization).
- **Tuple `(...)`** — needs per-tuple-element **name** edge-metadata (`(x: int, y: string)`) that the
  current columnar node table does not carry, plus the single-unnamed-element `(T)` → parenthesized-type
  collapse. Refused with -1 for now.

These two limits — source access for text-based decisions, and richer edge-metadata — are the natural
inputs to the next parser phase. No language gaps surfaced.

## 2026-06-06 — N# parser slice 7: union type references (closes the first deferred form)

Extends slice 6's recursive-descent type kernel with the top-of-grammar union level
(`ParseUnionTypeReferenceNode`, mirroring C# `ParseUnionTypeReference`, Parser.cs:1723-1756): a postfix
type optionally followed by `| postfix` arms becomes a `UnionTypeReference` (node kind 4) whose arms are
its children; with no `|` it returns the single postfix node unchanged (matching the C# `return first`).
Both the top-level entry AND generic arguments now route through this level (matching the C# parser, where
generic args call full `ParseTypeReference`), so a union can be a generic argument — `List<int | string>`,
`Dictionary<int | string, bool>`. Arms are gathered on the same shared LIFO arg-stack as generic args, so
union+generic nesting keeps every node's child run contiguous. Span = first-arm-start .. last-arm-end.

Verified against the production parser's `UnionTypeReference` (arm count + recursive arm trees) on
multi-arm unions, unions of generics/arrays/nullables (`int[] | List<int> | string?`), and union-as-
generic-arg, plus a focused adversarial-refutation pass (union-correctness + arg-stack-discipline lenses).
Remaining deferred type forms: Tuple `(...)`, Func `Func<...>` (a `FunctionTypeReference` in the C# AST),
ByRef `&T` — all still refused with -1. No language gaps surfaced.

## 2026-06-06 — N# parser slice 6: FIRST recursive-descent, tree-building kernel (type references)

The qualitative jump from flat single-pass token *scans* (slices 1-5) to genuine recursive-descent AST
*construction*. `ParseTypeReferenceNodesInto` + helpers (NEW file `ParserTypeReferences.nl`) reproduce the
C# parser's `ParseTypeReference` → `ParsePostfixTypeReference` → `ParseBaseTypeReference` recursion
(Parser.cs:1718-1907) for the four dominant forms — `SimpleTypeReference` (incl. dotted `A.B.C`),
`GenericTypeReference`, `ArrayTypeReference`, `NullableTypeReference` (incl. `?[]` → `Array(Nullable)`) —
and emit a real parent→child AST as a flat columnar node table (kind / name span / child run / byte span),
in **post-order** so the root is the last node. Verified structurally against the production parser's
`TypeReference` tree (kind + name + recursive children) plus byte-span, post-order-root, full-consumption,
determinism, deferred-form-seam, and depth-cap invariants, on a corpus covering every form and composition.

**Why this rung is the product blocker:** `ParseTypeReference` is the shared leaf of every
field/param/return/constraint parse, so no declaration/statement/expression parser slice can self-host
until type references do. It also begins Phase 2 (the in-assembly N# front-end that removes the
~1.2 ns/token delegate boundary blocking production routing of the lexer and the routed kernels).

**Capability proven (no language gap surfaced):** N# supports recursive-descent **tree construction** —
mutual recursion (`ParsePostfix` ↔ `ParseBase`) plus shared mutable state threaded through recursive
frames (the `st[]` parser-state array — pos / splitGreaterDepth / node & child cursors — and the
columnar out-arrays). Recursion alone was already proven (`ProjectSourceFilterMatchFrom`); building a tree
with it is the new, now-validated surface.

**Correctness highlights handled (faithful to the C# parser):**
- **`>>` RightShift split.** The lexer emits one `RightShift` (112) token for `>>`, so `List<List<int>>`
  has ONE token closing TWO generics. The kernel mirrors C# `ConsumeGreater`/`_splitGreaterDepth`: a
  `RightShift` close consumes the token and credits one *owed* `>` (tracked with its byte-end) that the
  enclosing close consumes without advancing. Proven: `splitGreaterDepth` provably never exceeds 1 (each
  `RightShift` is immediately followed by an owed close), so a single owed-byte-end slot suffices.
  Corpus: `List<List<int>>`, `Foo<Bar<Baz<int>>>`.
- **Child-run contiguity under interleaving (the one real bug found & fixed mid-slice).** A generic whose
  arguments are themselves generic would, with naïve append-as-you-parse, fragment the parent's child run
  in the shared `outChildIndices` (the nested arg appends ITS edges in between). Fix: gather each generic's
  argument ids on a shared **LIFO arg-stack** (recursion is LIFO, so nested generics push/append/pop within
  their own region) and append the parent's contiguous child block only after the whole arg list + closing
  `>` are consumed. Regression pin in the corpus: `Dictionary<List<int>, List<int>>`.
- **Deferred-form seam.** Union (`A | B`) cleanly STOPS at `|` (returns the first arm, leaves `|`
  unconsumed — the next slice). Tuple `(...)`, `Func<...>` (a `FunctionTypeReference` in the C# AST, not a
  generic — intentionally out of corpus), and ByRef `&T` are REFUSED with -1 (non-identifier first token).
- **Depth cap.** Generic nesting > 64 returns the -1 overflow sentinel (a tested, documented limit; the
  real stack is never blown). Pin: a 70-deep `List<...>` asserts -1.

Deferred to later rungs: Union arms, Tuple, Func semantics, ByRef, lifetimes, line/col `SourceSpan`
(byte-span only this slice), a full real-corpus type-annotation harvest, and production routing. No
language gaps surfaced.

## 2026-06-06 — N# parser slice 5: top-level declaration modifiers

`TopLevelDeclarationModifiersInto` + `ModifierFlag` (ParserDeclarations.nl) record, for each top-level
declaration, the accumulated modifier-flag set from the modifier keywords appearing at depth 0 before
its keyword — mirroring `ParseModifiers` (Parser.cs:330) and the `Modifiers` `[Flags]` enum
(Declarations.cs:271). All twelve recognized declaration modifiers are mapped by TokenType ordinal to
their flag bit (Public 1, Private 2, Internal 4, Protected 8, Static 16, Virtual 32, Abstract 64,
Sealed 128, Partial 256, Async 2048, File 32768, Override 65536); attributes sit inside brackets so the
depth tracking skips them, and member-level modifiers (Readonly/Const/Required/Init) are correctly
excluded. Verified against `(int)Declaration.Modifiers` on a new modifier-rich corpus (every modifier
singly and combined — `private static func`, `internal async func`, `public abstract class`,
`internal partial struct`, `[Obsolete] public record`, `protected virtual`/`public override` funcs),
plus the controlled/indentation corpora and all 27 dogfood kernels. `type`/`test` are skipped in the
modifier check: their C# AST nodes (`TypeAliasDeclaration`/`TestDeclaration`) carry no `Modifiers`
field, so the parser discards leading modifiers there while the kernel records raw leading modifiers
for every declaration keyword — corpora intentionally do not modify `type`/`test` to avoid that one
known C#-AST-vs-kernel divergence. No new language gaps surfaced.

## 2026-06-06 — N# parser slice 4: namespace imports (file-structure index complete)

`NamespaceImportSpansInto` (ParserDeclarations.nl) walks the `package`/`import` header prefix linearly
(matching `Parser.cs:52-81`), recording each `import A.B.C [as X]` namespace import's dotted-name span +
optional alias span, and skipping file imports (string after `import`, which the C# parser routes to
FileImports). Verified against `CompilationUnit.Imports` (namespace + alias) on the controlled corpus
(`import System`; `import A.B.C as Alias`), the indentation corpus, and all 27 dogfood kernels.

**Milestone:** the N# parser now extracts a complete top-level file-structure index — namespace imports,
package, and the ordered declaration kind+name list — entirely in-assembly from the lexer's tokens, each
piece verified against the C# parser. Next rungs deepen into declarations (modifiers, signatures) and
then statements/expressions toward a full N# parser. No new language gaps surfaced in slices 1-4.

## 2026-06-06 — N# parser slice 3: package name

`PackageNameSpanInto` (ParserDeclarations.nl) records the file's `package A.B.C` dotted-name span (or
returns 0 when absent), matching the C# parser's `CompilationUnit.Package?.Name`. Verified on the
controlled/indentation corpora and all 27 dogfood kernels. The N# parser now extracts a coherent
file-structure index — package + top-level declaration kinds + names — from the lexer's tokens,
in-assembly. (Imports' namespace-vs-file-import distinction is deferred to a later careful slice.)

## 2026-06-06 — N# parser slice 2: top-level declaration names

`TopLevelDeclarationNameSpansInto` (ParserDeclarations.nl) extends slice 1 to also record each
top-level declaration's NAME span. A declaration's name is the token immediately after its keyword
(modifiers precede the keyword), so `name = next token when it is an Identifier` is exact for all eight
keyword declaration kinds and correctly yields no-name for `test "..."` (string-named, out of scope
this slice). Verified against the C# parser's `Declaration.Name` (kind + name pairs) on the controlled
corpus, the indentation-style corpus, and all 27 dogfood kernels. The N# parser now extracts a
top-level declaration index (kind + name) from the lexer's tokens, all in-assembly.

## 2026-06-06 — Phase 2 begins: first N#-native parser slice (top-level declaration extraction) + nlc query ast

**What:** Two slices that open the parser-migration phase (the path to actually deleting the
`*DogfoodAdapter` bridge and, ultimately, bootstrap).

1. **`nlc query ast`** (LLM-first CLI + verification harness). New `nlc query ast [--file F]`
   subcommand emits the parsed `CompilationUnit` AST(s) as stable, node-typed JSON
   (`OutputFormatter.AstToJson`: each node `{ "node": "<ConcreteType>", …declared props }`, recursing,
   preserving the concrete kind through the polymorphic Declaration/Statement/Expression bases). This
   is both an AGENTS LLM-first-CLI deliverable and the **canonical AST representation** for verifying an
   N# parser against the C# parser. Hardened by `Parser_RealCorpus_AstSerializesDeterministically`
   (parse + serialize all 108 real .nl files: valid, deterministic, no crashes).

2. **First N#-native parser kernel** (`CompilerServices/ParserDeclarations.nl`):
   `TopLevelDeclarationKindsInto` extracts the top-level declaration KIND sequence from the
   brace-inserted token stream (output of the now-complete N# lexer), tracking brace/bracket/paren depth
   so it captures declaration keywords (Func/Class/Struct/Interface/Union/Record/Enum/Type/Test) only at
   depth 0 — naturally skipping modifiers, attributes, and NESTED declarations, and capturing
   `ref struct`/`duck interface` at their `struct`/`interface` keyword exactly as the C# dispatch
   (`Parser.cs:226-273`) produces. Verified by `Parser_TopLevelDeclarationKinds_MatchProductionParser`
   against the C# parser's `CompilationUnit.Declarations` (mapped to keyword ordinals) on a controlled
   corpus (all keyword kinds + nested-decl exclusion + modifiers + attributes), an indentation-style
   corpus (virtual braces handled identically to explicit), and all 27 dogfood kernels (real code).

**Significance:** the lexer is feature-complete and an N# consumer of its tokens now exists in-assembly
(the kernel reads the lexer's token arrays). This is the first verified rung of the parser ladder.
Building it surfaced no new language gaps. Bootstrap coverage remains 0% (these are services behind the
adapter), but the verification harness (AstToJson) + the first parser rung are the scaffolding for
growing an N# parser slice-by-slice against the C# parser.

## 2026-06-06 — Lexer real-corpus dogfood parity (108 real .nl files) + CommentsInto benchmark

**What:** Two consolidation slices proving the now-complete N# lexer on real code.

1. **Real-corpus parity.** Extended `LexerTokenKindScanner_ProjectCompilesAndMatchesProductionLexer`
   to run the COMPLETE N# lexer (`TokenizeMetadataWithIndentationInto` + `CommentsInto`) against the C#
   production lexer (`Lexer.Tokenize()` / `Lexer.Comments`) over **every real `.nl` file** — 81 in
   `examples/` + 27 dogfood compiler-service kernels = **108 files**, including the systems source the
   compiler is written in (lifetimes, `scoped`/`unsafe`, raw/interpolated strings, comments,
   indentation). Full token-stream parity (kind/start/valueLength/line/column) AND comment-trivia
   parity hold on all 108 — the strongest available correctness evidence that the N# lexer matches C#
   on the code that matters. (This is the "use the compiler on itself to ensure correctness" mandate.)

2. **CommentsInto benchmark** (`CompilerServiceLexerCommentBenchmarks`, see
   [`compiler-benchmark-metrics.md`](compiler-benchmark-metrics.md)): N#'s zero-alloc comment scan vs
   C#'s tokenize-byproduct comment collection — 4.7× representative (0 B vs 33.9 KB), 18× large
   (0 B vs 10.7 MB). Framed honestly there (C# has no dedicated comment scanner).

**Status:** the N# lexer is feature-complete AND validated correct on the real compiler/example corpus.
The remaining self-host work is the large subsystem migration (parser → N#, consuming N# tokens
in-assembly) needed to actually delete the `*DogfoodAdapter` bridge — a multi-slice Phase 2/3 effort.

## 2026-06-06 — Phase 1 lexer: comment-trivia collection (N# lexer feature-complete vs C#)

**What:** Added the `CommentsInto` N# kernel — the last lexer feature gap. The C# `Lexer.Tokenize`
collects line/doc/block comments into `Lexer.Comments` (consumed by the formatter) while excluding them
from the token stream. `CommentsInto` reproduces it exactly: for each comment it records line, column,
start offset, length, and `isMultiLine` (1 = block `/* */`, 0 = line `//` or doc `///`). C#'s stored
text is the full span for line/doc comments and `"/*" + inner + "*/"` for block comments — both equal
`end - start`, so `length` = `end - start` uniformly. The kernel mirrors `TokenizeMetadataInto`'s token
dispatch (consuming string / raw-string / char / lifetime / number / identifier / operator runs as
units), so a `//` or `/*` INSIDE a literal is never misread as a comment and line/column tracking
through multi-line raw strings stays exact.

**Verified:** `AssertCommentsLikeProductionLexer` compares `CommentsInto` to `new Lexer(src).Comments`
(line/column/start/length/isMultiLine) on a dedicated `commentSource` (line + doc + single-line block +
multi-line block + trailing comment with no final newline + `//`/`/*` inside string and char literals
that must NOT be collected) plus the representative/metadata/source/lifetime corpora. Targeted test
green.

**Milestone — the N# lexer is now feature-complete vs the C# production lexer:** token kind, source
position (start/line/column), value length, indentation braces, Unicode classification, lifetimes,
malformed-number Unknown tokens, AND comment trivia all match `Lexer.Tokenize()`/`Lexer.Comments`.
Token-text is host-derivable from start+length (not a kernel gap). The Phase 0/1 lexer beachhead's
correctness work is done; what remains for the lexer is the **architecture** (Phase 2): an N#-native
Token representation + an in-assembly N#→N# consumer (parser) so the `*DogfoodAdapter` delegate
boundary can actually be deleted — the dogfood kernels remain behind that bridge until their caller is
also N#.

## 2026-06-06 — Phase 1 lexer: malformed-number Unknown tokens (raw-tokenizer kind-stream parity complete)

**What:** Closed the last raw-tokenizer kind divergence — malformed numbers. The C# `ReadNumber`
emits an `Unknown` token (137) for: a `0x`/`0b` prefix with no valid digit immediately after (a leading
`_` counts as "no digit", `Lexer.cs:592/614`), a second decimal point (`Lexer.cs:650-659`), and an
exponent `e`/`E[+/-]` with no following digit (`Lexer.cs:681-684`). The N# `ScanNumberInfo` had no
error path — it returned `IntLiteral`/`FloatLiteral` and (for a leading `_` after `0x`/`0b`)
over-consumed the span. Added the four error branches: `ScanNumberInfo` now returns a kind-`3` sentinel
(Unknown) with the exact span C# consumes, and the two metadata/kind callers map `3`→`137`. Because
the error branches return C#'s consumed span and `NumberValueLength` counts non-`_` chars, the Unknown
token's value text/length matches C#'s `sb` automatically (`1_e'`→"1e", `0x`→"0x", `1.2.3`→"1.2.3").

**Cleanup:** consolidated the duplicate number scanner — `TokenizeCount` now uses
`ScanNumberInfo(...) >> 2` for the end offset, and the redundant `ScanNumber` function was removed
(single source of truth for number consumption).

**Coverage completion (honest accounting):** also added `indentLifetimeSource` (the indentation-style
lifetime corpus the `5c793e57` entry claimed to restore but missed) and composed-path asserts for the
flat lifetime/unicode/char-literal/malformed-number corpora — closing the two coverage gaps from the
earlier agent-revert incident.

**Verified:** `malformedNumberSource` (`0x`, `0b`, `1e`, `1.2.3`, `0x_F`, `1e+`) asserted across all
three raw tokenizers + the composed path vs `Lexer.Tokenize()` (kind/start/valueLength/line/column +
count). Targeted test green. With this, **N# raw-tokenizer kind-stream parity with the C# production
lexer is complete** — identifiers, keywords (incl. systems), literals (incl. raw/interpolated/char),
lifetimes, operators, delimiters, comments-excluded, indentation braces, Unicode classification, and
now malformed-number Unknown tokens all match.

**Remaining lexer gaps:** comment-trivia collection for the formatter (`Lexer.Comments`) and token-text
materialization (host-derivable from start+length) — neither is a *kind/position* parity gap.

## 2026-06-05 — Phase 1 lexer: Unicode character classification + char-literal fix

**What:** Closed the last raw-tokenizer character-classification gap and restored lost test coverage.

1. **Unicode classification.** The scanner's char helpers were ASCII-only; the C# lexer uses the BCL
   Unicode predicates throughout (`char.IsDigit` 336/631/…/757, `char.IsLetter` 342/905,
   `char.IsLetterOrDigit` 567/922/926/942, `char.IsWhiteSpace` 912/1084). Rewrote
   `IsWhitespaceExceptNewline` → `char.IsWhiteSpace(ch) && ch != '\n' && ch != '\r'`,
   `IsIdentifierStart` → `ch == '_' || char.IsLetter(ch)`, `IsIdentifierPart` →
   `ch == '_' || char.IsLetterOrDigit(ch)`, `IsDigit` → `char.IsDigit(ch)`, and the lifetime-lookback
   whitespace → `char.IsWhiteSpace(ch)`. `IsHexDigit` stays `IsDigit || a-f || A-F` (now matching C#'s
   `char.IsDigit(c) || a-f || A-F`). **The C# lexer has no ASCII fast path, so calling the same BCL
   predicates is BOTH exact-parity AND the same cost** — no perf regression vs C#.
2. **Char-literal `'\<CR>` fix.** `ScanCharLiteral` consumed the escaped char unconditionally; C#
   `ReadCharLiteral` guards it with `!IsAtLineBreak()` (Lexer.cs:882). Added the `\n`/`\r` guard so a
   backslash at end-of-line leaves the line break to become a separate Newline token (pre-existing gap
   surfaced by the lifetime slice's fuzz).

**Audit answer (resolved):** the open question "do `char.IsWhiteSpace`/`IsLetter`/`IsLetterOrDigit`/
`IsDigit` compile in the dogfood kernel?" is **YES** — verified by compiling the dogfood project with
them and passing the full ASCII corpus. This also retroactively confirms the lifetime port could have
used them; the ASCII helpers it used are exactly equivalent on ASCII, and now share the Unicode upgrade.

**Verification:** added `unicodeSource` (Unicode-letter identifiers `café`/`ident١`, NBSP U+00A0 as an
inline separator splitting `x y`, Arabic-Indic digit U+0661 in identifier-continuation) asserted via
all three raw tokenizers + the composed path, and `charLiteralLineBreakSource` (`'\<CR>`) — all match
`Lexer.Tokenize()`. Targeted test green; gate green.

**Test-coverage restoration (honest accounting):** the prior lifetime slice's commit `dc42b0f0` was
SUPPOSED to add `lifetimeSource`/`indentLifetimeSource` parity corpora, but a concurrent adversarial
review agent (running in the main repo, not an isolated worktree) ran `git checkout HEAD -- tests/...`
to revert its own scratch edits — which silently wiped my uncommitted lifetime corpora before the
commit. The lifetime KERNEL code committed fine and was independently validated by the review's
differential-fuzz harness, but the corpora were missing from `dc42b0f0`'s test. This slice restores
`lifetimeSource` (all contexts: `<'a>`, `<'a,'b>`, `scoped 'a`, `returns 'a`, char-literal non-lifetimes)
+ `indentLifetimeSource`. Process fix recorded: verify/review agents must be read-only or worktree-
isolated, and never commit while they run against the shared tree.

**Remaining lexer gaps:** a number-scanner exponent/underscore divergence (`1_e'`-style, surfaced by
fuzz — separate from classification; **closed in the next-dated entry above**); then comment-trivia
(`Lexer.Comments`) + token-text materialization for a full production N# lexer.

## 2026-06-05 — Phase 1 lexer: lifetime tokens ported to N# (blocker closed)

**What:** Closed the lifetime-token blocker from the prior entry's audit. The C# lexer
(`Lexer.cs:325-328`, `IsLifetimeStart`/`IsLifetimeContext`/`ReadLifetime` at `Lexer.cs:903-958`) emits
a single `Lifetime` token (ordinal 142) — instead of a char literal — when an apostrophe begins an
identifier (next char letter/`_`, and the char after that is not a closing quote, so `'a` vs the char
literal `'a'`) AND it sits in a lifetime *context*: the nearest preceding non-whitespace char is `<`
or `,`, or the identifier word immediately before it is `scoped`/`returns`. The N# scanner had no
lifetime handling, so it lexed `'a` as a char literal — wrong kind, and for multi-char lifetimes
(`'a1`) even the wrong token *count*.

**Port** (`CompilerServices/LexerTokenKindScanner.nl`): added `IsLifetimeStartAt`,
`IsLifetimeContextAt`, `MatchesScopedOrReturns`, `ScanLifetime`, and `IsAsciiWhitespace`, mirroring the
C# methods statement-for-statement, and inserted a lifetime branch **before the char-literal branch in
all three tokenizers** (`TokenizeKindsInto`, `TokenizeMetadataInto`, `TokenizeCount`) so every parity
path agrees. The backward context scan (skip whitespace incl. newlines → `<`/`,` early-true → else read
the preceding identifier word and match `scoped`/`returns`) reuses the scanner's existing ASCII
classification helpers (`IsIdentifierStart` ≡ `char.IsLetter||'_'`, `IsIdentifierPart` ≡
`char.IsLetterOrDigit||'_'`, `IsAsciiWhitespace` ≡ `char.IsWhiteSpace` — exact on ASCII), keeping the
scanner uniformly ASCII; the scanner-wide ASCII-vs-Unicode gap (next slice) will upgrade all helpers
together. The systems-keyword recognition landed in the prior slice is what makes the `scoped` context
word resolve correctly.

**Verified:** added a brace-style `lifetimeSource` corpus (so `InsertIndentationBraces` is a no-op and
it exercises ALL three raw tokenizers + the composed path against `Lexer.Tokenize()`) mixing every
lifetime context (`<'a>`, `<'a, 'b>`, `scoped 'a`, `returns 'a`) with char literals that must STAY char
literals (`'x'`, `'\n'`, escaped quote, and `name 'a` whose preceding word is not scoped/returns), plus
an indentation-style `indentLifetimeSource` (lifetimes + virtual braces + a char literal in one stream).
Full token-stream parity (kind/start/valueLength/line/column + count) holds; targeted test green. An
adversarial differential-fuzz workflow (compiled dogfood DLL vs the real C# `Lexer.Tokenize()` over
many ASCII lifetime/char-literal inputs) confirmed no divergence.

> **Correction:** these two corpora were LOST from this commit — a concurrent review agent reverted the
> test file before commit, so `dc42b0f0` shipped the lifetime kernel + an under-covered test. The
> corpora were RESTORED in the next-dated entry above. The kernel itself was independently validated by
> the differential-fuzz harness, so the port was correct; only the in-suite regression coverage lapsed.

**Remaining lexer gaps:** (a) ASCII-vs-Unicode character classification (whitespace/digits/letters);
(b) a pre-existing `ScanCharLiteral` edge case surfaced by this slice's adversarial fuzz — a char
literal whose body is a backslash immediately followed by a line break (`'\<CR>`): C# `ReadCharLiteral`
guards the escaped-char consumption against EOL, the N# `ScanCharLiteral` does not (pre-existing, from
commits d636e3a2/ff921348, NOT a lifetime-port regression). Both fold into the char-classification /
char-literal parity slice. Then comment-trivia + token-text for a full production N# lexer.

## 2026-06-05 — Phase 1 lexer: indentation tokens + systems-keyword recognition ported to N#

**What:** Two cohesive N# lexer kind-stream parity improvements, plus an adversarial audit that
surfaced (and this slice partly closes) several pre-existing raw-tokenizer gaps.

1. **Indentation tokens.** Ported `Lexer.InsertIndentationBraces` (`src/NSharpLang.Compiler/Lexer.cs:167-266`)
   — the virtual `{`/`}` insertion for indentation-style (brace-free) source — to N#. Until now the N#
   scanner emitted only the *raw* token stream (`TokenizeMetadataInto`), so metadata parity was pinned
   only on explicit-brace corpora where `InsertIndentationBraces` is a no-op.
2. **Systems keywords.** `KeywordKind` now recognizes the five systems keywords the C# lexer emits
   (`Lexer.cs:97-101`): `alloc`→`Alloc(143)`, `allow`→`Allow(144)`, `stackalloc`→`Stackalloc(145)`,
   `unsafe`→`Unsafe(146)`, `scoped`→`Scoped(147)` — appended to the length-gated first-char dispatch,
   so near-miss prefixes (`all`/`scope`/`alloca`) stay `Identifier`. Previously the scanner returned
   `Identifier(0)` for these, so it could not even tokenize the dogfood's own systems-N# source.

**Adversarial audit:** a 4-agent workflow (line-by-line + edge-case + metadata lenses + synthesis,
with 400k-program structural fuzzing and a differential harness against the compiled C# lexer)
confirmed the **indentation post-pass port is faithful** (zero divergences across all fuzz + 92
hand-built cases) and drove out the gap list below. Systems keywords are closed here; the rest are the
next slices.

Added two N# kernels to `CompilerServices/LexerTokenKindScanner.nl`:
- `InsertIndentationBracesCore(...)` — a faithful, zero-alloc (caller-owned-buffer) port of
  `InsertIndentationBraces`, operating purely over the raw metadata arrays
  (kind/start/valueLength/line/column). It tracks an indent stack, explicit-brace depth, and
  paren/bracket depth; opens a virtual `LeftBrace` (ordinal 129) on indentation increase and closes
  virtual `RightBrace` (130) tokens on dedent and at EOF, with the base-indent capture, the
  `Math.Max(0, …)` clamps, the "halfway dedent pops without re-opening" stack walk, and the
  brace-vs-indentation suppression rules matching the C# source statement-for-statement. A virtual
  brace's start offset is derived as `tokenStart - (tokenColumn - 1)` (the trigger token's line start)
  with column fixed to 1 — exactly what the parity test's `TokenStartFromLineColumn` expects.
- `TokenizeMetadataWithIndentationInto(source, …)` — the composed entry: tokenize raw, then run the
  brace post-pass, producing the exact stream `Lexer.Tokenize()` yields on any source **whose tokens
  are already correctly recognized by the raw scanner** (i.e. excluding the gaps below).

**Verification (parity, not a perf-routing slice):** extended
`LexerTokenKindScanner_ProjectCompilesAndMatchesProductionLexer` with
`AssertTokenMetadataWithIndentationLikeProductionLexer`, asserting full token-stream parity (kind +
start + valueLength + line + column, count included) against `new Lexer(src).Tokenize()`. Coverage:
the composed entry is first proven a correct **superset** on all four existing explicit-brace corpora
(it must equal the raw stream there), then proven on indentation-style corpora that genuinely trigger
insertion — simple single indent, nested indents with multi-level dedent and sibling blocks,
globally-indented source with interior blank lines, paren-continuation + explicit-brace suppression,
CRLF endings, tab indentation, an inconsistent "halfway" dedent, and degenerate empty / whitespace-
only inputs. The count assertion makes the tests non-trivial: if the port inserted nothing while C#
did (or vice-versa) the token counts would differ and the test would fail. For systems keywords, added
a `systemsKeywordSource` corpus asserted three ways (raw kinds, raw metadata, composed) that exercises
each of the five keywords plus near-miss prefixes (`all`/`scope`/`alloca`/`scopes`/`unsaf` must stay
`Identifier`). Targeted test passes; full `CompilerDogfoodProjectTests` class green, including the
`Newline == 136` ordinal-layout pin. Full `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` gate run
for the commit.

**Language/compiler findings (Phase 0 audit):** the port compiled on today's N# with **no new gaps** —
confirming the audit's "lexer port is feasible" finding extends to the control-heavy indentation
logic. Specifically exercised and confirmed working: an 11-array-parameter function signature
(previously the widest kernel was 7 arrays), intra-assembly N#→N# calls with internal `new int[](…)`
allocation, `bool` locals with reassignment and logical `!`/`&&`/`||`, nested `while` with `continue`,
mid-loop `return`, and `else if` chains. No principled compiler change was required this slice.

**Architecture note (honest framing):** this is a correctness/parity slice that **advances the N#
lexer's kind-stream** (indentation post-pass), not a production-routing slice. Per the
boundary-profiling finding, the lexer adapter bridge cannot be deleted until its *caller* (the parser)
is also N# and the call inlines in-assembly; routing tokenization through this kernel today would only
add another ~1.2 ns delegate boundary. The indentation logic is written in the fast canonical style
(counted loops, manual int stack, zero per-call allocation in the pure kernel) so it is ready to be
the production lexer once the in-assembly N#→N# parser path lands (Phase 2). No adapter added/removed.

**Audit findings (pre-existing raw-tokenizer parity bugs, NOT in the new indentation code; latent
because no in-tree corpus exercised them):**

- ✅ **Systems keywords (blocker) — CLOSED this slice.** `KeywordKind` returned `Identifier(0)` for
  `alloc`/`allow`/`stackalloc`/`unsafe`/`scoped`; now emits `143/144/145/146/147`. Empirically
  confirmed against the compiled C# lexer and pinned by `systemsKeywordSource`.

**Remaining gaps (the immediate next slices):**

> ✅ Gap 1 (lifetime tokens) was closed in the next-dated entry above.

1. **Lifetime tokens (blocker) — CLOSED (see entry above).** `TokenizeMetadataInto` has no lifetime handling; C# `NextToken`
   (`Lexer.cs:325-328`) calls `IsLifetimeStart()`/`ReadLifetime()` (`Lexer.cs:903-960`) to emit a
   single `Lifetime(142)` token (e.g. `,'a`→`Lifetime`, `,'b1`→`Lifetime`). `IsLifetimeStart` is
   context-sensitive: apostrophe, next char letter/`_`, char-after-next not `'`, AND the nearest
   preceding non-whitespace char is `<` or `,` or the word `scoped`/`returns`. The N# scanner instead
   lexes `'a` as a char literal, diverging on kind AND count. Fix: port `IsLifetimeStart`/`ReadLifetime`
   into the scanner before the char-literal branch — its own slice given the source lookback. **Note:**
   the systems-keyword recognition landed here is a prerequisite for the `scoped`/`returns` lookback.
2. **ASCII-vs-Unicode character classification (major).** The scanner's `IsWhitespaceExceptNewline`,
   `IsDigit`, and `IsIdentifierStart` are ASCII-only, but the C# lexer uses the Unicode-aware BCL
   predicates `char.IsWhiteSpace` (`Lexer.cs:1084`), `char.IsDigit` (`Lexer.cs:336`), and
   `char.IsLetter` (`Lexer.cs:342`). So non-ASCII whitespace (NBSP/NEL/U+2028/U+2029/U+2000–U+200A/
   U+202F/U+205F/U+1680/U+3000 — note C# treats U+0085/U+2028/U+2029 as inline whitespace, not line
   breaks, since `IsAtLineBreak` is `\n`/`\r` only), Unicode letters in identifiers, and Unicode
   decimal digits all diverge (the scanner emits `Unknown(137)` / wrong kinds/columns/count). Fix as
   one coherent slice: ASCII fast-path + BCL-predicate fallback for ch > 127 in all three helpers
   (parity guaranteed by sharing the BCL predicate), with Unicode corpora. **Open audit question:**
   confirm the kernel compile path supports `char.IsWhiteSpace`/`char.IsLetter`/`char.IsDigit` interop
   (the Phase 0 probe verified `char.IsDigit`/`char.IsLetter` standalone; no dogfood kernel calls them
   today — they all hand-roll ASCII checks).
3. **Comment-trivia + token-text** for the formatter (`Lexer.Comments`) and token-text materialization
   (derivable from start+length by the host) — the last pieces to a full production N# lexer.

## 2026-06-05 — Consolidation: dogfood work merged onto `systems-language`

**What:** Consolidated all scattered dogfood worktrees/branches onto the canonical working branch
`systems-language` (which carries the separate "Systems N#" line: memory pools, zero-copy proofs,
ref/lifetime safety, source generators, etc.). Previously the dogfood self-hosting work lived only on
`codex/compiler-dogfood-benchmarks` and a fan of unit branches.

Merged in:
- `nsharp-dogfood-profiling` — the real integration branch: canonical dogfood base (145 commits) +
  accepted/routed units **1** (formatter import ordering), **3** (ProjectFile source filtering),
  **5** (ILCompiler overload selection) + rejection-evidence units **2** (formatter safety scan),
  **4** (analyzer overload-signature distinctness), **6** (declared-type exact-name lookup) + all
  three design docs + the `DogfoodBoundaryOverheadBenchmarks` decomposition benchmark.
- `nsharp-dogfood-unit-7-code-intel-audit` — the audit-only doc section.

**Routed (production) kernels carried in** (unchanged numbers, see metrics doc):
- Formatter import ordering — 6.2× representative / 20.2× large, 0 B.
- ProjectFile source filtering — 25.8× / 26.9×.
- ILCompiler overload selection — 11.3× / 10.9×, 0 B (runs on every declared-method/ctor call).

**Conflicts reconciled (8 core files)** — preserving BOTH systems-language semantics and dogfood
routing:
- `ILCompiler.cs`: kept profiling's routed compact-candidate overload ranking
  (`SelectBestDeclaredMethodCandidate`) **and** systems-language's `HasRuntimeTypeParameters` generic
  detection; kept systems-language's `FinalizeTopLevelEnumTypes` (re-registers baked enums in
  `_enumTypes`/`_typeKeys`) **and** the dogfood `OrderTypeBuildersByDescendingTypeKeyDepth` helper;
  kept systems-language's `EmitExpressionStatement`/`TryEmitAssignmentStatement` lowering (a superset
  of profiling's inline assignment-discard); combined profiling's member-load null-guard with the
  correct `memberOwnerType`.
- `Program.cs`: preserved systems-language's `--systems` template flag on top of profiling's
  `GetFirstPositionalArg` refactor.
- `Program.Backends.cs`: dropped profiling's now-dead `ValidateStrictLintDiagnostics` (systems-language
  moved strict-lint into the compiler via `CompileToIlAssembly(validateStrictLint: true)`).
- `CompilationStubEmitter.cs`, `Analyzer.cs`, `memory/README.md`, `runTest.ts`: additive.

### Limitation found + principled fix: TokenType ordinal coupling

**Symptom:** After a clean (compiling) merge, the full gate hit **63 failures** — formatting gate,
unit tests, example builds, IL verification — all braced N# source failing to parse with
"Unexpected token newline in expression."

**Root cause:** The systems-language line inserted six token types (`Lifetime`, then
`Alloc`/`Allow`/`Stackalloc`/`Unsafe`/`Scoped`) into the **middle** of the `TokenType` enum. The
production-routed dogfood kernel `ParserTokenCompactionIndicesInto`
(`src/NSharpLang.Compiler.Dogfood/CompilerServices/LexerTokenKindScanner.nl`) — reached from the
`Parser` constructor via `NSharpCompilerDogfoodAdapter.TryCompactParserTokens` — filters newline
tokens by the **hard-coded integer ordinal 136**. The insertions shifted `Newline` from 136 to 142,
so the kernel filtered the wrong token type and left stray newlines in the parser's token stream.
This is the dogfood kernels' ordinal-coupling fragility surfacing through a real enum change.

**Fix (smallest principled change):** Restore the kernels' ordinal contract by appending the six new
token types at the **end** of `TokenType` (they are referenced only by name in C#, never by ordinal).
Documented the load-bearing ordering on the enum, and added an explicit guard test
`ParserTokenCompactionParityRespectsTokenTypeLayout` pinning `(int)TokenType.Newline == 136` so any
future mid-enum insertion fails loudly at the C# test layer instead of silently in production.

**Follow-up debt (tracked, not yet done):** The dogfood `TokenType`-ordinal kernels remain coupled to
a fixed enum layout. The more robust long-term fix is to pass ordinal constants (e.g. the newline
kind) into the kernels as data rather than baking them — decoupling kernels from enum layout entirely.
Deferred to avoid widening the binding/benchmark/test surface during consolidation; the guard test +
enum comment prevent silent recurrence in the meantime.

**Verification:** `format --project examples --check` → "All files are properly formatted"; targeted
re-run of the previously-failing classes (`CompilerDogfoodProjectTests`, `StructCopyEliminationTests`,
`AnalyzerBindingMapTests`) → 42/42 pass.

### Limitation found + principled fix: short-circuit `&&`/`||` codegen vs C#

**Symptom:** After the ordinal fix the full gate had exactly one remaining failure — the Systems
BenchmarkDotNet gate (`SystemsFastGateBenchmarks`), `HotResultCombinations` scenario, N# at
~1.01× the C# baseline (zero-tolerance gate; N# must be ≤ C#).

**Root cause (verified by emitted-IL diff vs pre-merge `84dda83`):** the merge correctly brought in
the dogfood branch's short-circuit `&&`/`||` lowering (commit `b4a873e "Fix IL primitive operator
semantics"`, with the `ILCompiler_LogicalOperatorsShortCircuit` test). Pre-merge systems-language
lowered `&&`/`||` **eagerly** (`clt; cgt; or; brfalse` — one branch) which is a *latent correctness
bug* (the right operand is always evaluated). The IL diff showed only `scanDigits`,
`scanAndChecksumDigits`, `copyDigits` changed — each a hot loop with `if value < 48 || value > 57`.
The materializing short-circuit helper (`EmitLogicalOr`) added `ldc.i4.0`/`ldc.i4.1`/`br`
boolean-materialization and a second branch; RyuJIT compiles the equivalent C# range check
(`value < 48 || value > 57`) to a single branch, so correct-but-two-branch N# lost by ~1–2%.

**Fix (compiler self-improvement — explicitly in scope):** added a short-circuiting
`EmitConditionBranch(condition, target, branchIfTrue)` used by `EmitIf`/`EmitWhile`/`EmitFor`. It
lowers `&&`/`||`/`!` to branches taken directly against the target labels (no boolean
materialization), and:
- **fuses** integer relational comparisons with their branch into one
  `blt`/`bgt`/`ble`/`bge`/`beq`/`bne.un` opcode (gated to integral operands, where the relational
  inverse is exact — no NaN/unordered hazard);
- **eagerly** evaluates `a && b`/`a || b` as `left; right; and/or; br` (a single branch) ONLY when
  both operands are provably pure and non-throwing (an integer comparison whose leaves are integer
  locals/params or integer/char literals) — observably identical to short-circuit but one branch
  instead of two, matching the JIT-folded C# shape.

Side-effecting operands (calls, member access, indexing, division) still short-circuit, so
`ILCompiler_LogicalOperatorsShortCircuit` and the operator-matrix/IL-shape suites pass (100/100 on
the targeted run). After the fix the emitted IL for the hot loops is *smaller* than pre-merge's, and
`HotResultCombinations` measures **0.99×** (N# faster), so the benchmark gate passes. This is a net
codegen quality improvement for every `if`/`while`/`for` condition in the language.

**Verification:** Systems BenchmarkDotNet gate passes (all 6 scenarios ≤ 1.00, HotResultCombinations
0.99); 100/100 targeted short-circuit/operator/control-flow tests pass. Full
`VSCODE_TESTS=skip ./scripts/test-all.sh --commit` re-run pending.

---

## 2026-06-05 — Lever 3 codegen: `array.Length` → `ldlen` for SZ arrays

**What:** `EmitMemberAccess`/`EmitMemberLoadValue` lowered `array.Length` on a single-dimension
zero-based array (`IsSZArray`) to a non-virtual `call Array.get_Length()`. Replaced with the canonical
`ldlen; conv.i4`. Strings, `Span<T>`, and multidimensional arrays are unaffected (not `IsSZArray`).

**Why (boundary-profiling Lever 3):** `ldlen` is the form the JIT's bounds-check elimination
pattern-matches, so an `array.Length`-bounded counted loop (`for i := 0; i < a.Length; i++ { a[i] }`)
now emits the same shape C# does and the JIT elides the `ldelem` bounds check.

**Evidence (direct micro-benchmark, 4096-int sum, 2M iterations, identical checksums):**

| N# array.Length form | N# / C# ratio | IL size (`sumArray`) |
|----------------------|---------------|----------------------|
| `call get_Length` (before) | 1.003× (slightly slower) | 33 B |
| `ldlen; conv.i4` (after)   | **0.999× (parity)** | 30 B |

Modest but real: moves the canonical counted array loop from marginally-slower to parity with C#,
meeting the "never slower than C#" bar, with smaller and canonical IL. 537 array/length/span/string/
loop tests pass; parity is guaranteed (same value). Benefits every `array.Length`-bounded loop,
including the array-heavy dogfood kernels.

## 2026-06-05 — Phase 0 audit kickoff: lexer feature surface + N# interop readiness

Per [`roadmap-to-done.md`](roadmap-to-done.md), began the language-completeness audit by scoping
the **lexer** beachhead (`src/NSharpLang.Compiler/Lexer.cs`, 1150 LOC). Its dependency surface:
`string` indexing, one `Dictionary<string,TokenType>` (keywords), `List<Token>` (output), 13
`StringBuilder` uses (token text), one `Stack`/indentation, 15 `char.Is*` calls, 14 `switch`, the
`Token` record, the `TokenType` enum. No LINQ.

**Finding — a correct lexer port is feasible on today's N#.** N#'s C# interop already covers every BCL
dependency. Verified by compiling AND running an N# probe that uses `new StringBuilder()` +
`Append`/`ToString`, `new Stack<int>()` + `Push`/`Pop`, `char.IsDigit`/`char.IsLetter`, and
`new Dictionary<string,int>()` + indexer + `ContainsKey` (output `hi 2 True True True`). Examples
already use `List<T>`, nested `Dictionary<...>`, collection expressions, records, enums, and `switch`.

**Open work for the port (not feasibility, but the "super fast" bar):**
- Decide BCL collections (mechanical, allocates) vs **systems-native pooled/zero-alloc** `Token`/
  `TokenStream` for the hot path — the latter is what makes the migrated lexer dramatically faster.
- Confirm full trivia / indentation-token / diagnostic / source-position parity in N#.
- The keyword table: prefer the existing first-character dispatch (already proven in the dogfood
  scanner) over a `Dictionary` lookup on the hot path.

**Finding 2 — the existing N# lexer scanner is production-close.** `LexerTokenKindScanner.nl`
(1573 LOC) already emits full per-token metadata (kind, start, value length, line, column) for
identifiers, separated int/hex/binary/float numbers, string/raw/interpolated/char literals, the full
operator set, and keywords, and it excludes comments from the stream exactly as the C# lexer does.
Pinned with a new representative-corpus parity test in `CompilerDogfoodProjectTests`
(`AssertTokenMetadataLikeProductionLexer`) over a single source that combines line/doc/block comments,
string + interpolated + char literals, separated numeric literals, a wide operator set, and keywords —
it matches the production `Lexer.Tokenize()` token stream exactly (count + kind + start + length +
line + column), and the compaction parity holds too.

**Remaining gaps to a full production N# lexer** (narrower than first thought): indentation-token
insertion for indentation-style (brace-free) source, comment-trivia collection for the formatter
(`Lexer.Comments`), and token-text materialization (derivable from start+length by the host). Token
*kind/position* parity — the hard part — is already met on realistic code.

Next slice: cover indentation-token insertion in the N# scanner (the main remaining kind-stream gap),
or stand up the N#-native pooled `Token`/`TokenStream` so the parser can consume N# tokens directly
(removing the host materialization boundary). Record any language gap here and close it principled.

> **Update (newest entry above):** indentation-token insertion is now DONE and verified faithful.
> BUT the adversarial audit of that slice surfaced three pre-existing raw-tokenizer parity gaps
> (systems keywords, lifetime tokens, Unicode whitespace) that the old "kind/position parity is
> already met on realistic code" claim missed — they were latent only because no corpus exercised
> them. See the newest entry's "Gaps surfaced" list; those are the immediate next slices.

## Bootstrap coverage

- **0%** — no compiler source is yet compiled by the N# compiler itself. The dogfood kernels are
  N#-authored compiler *services* compiled through the normal `NSharpLang.Sdk` path and bound via the
  `*DogfoodAdapter` delegate boundary; this is the pre-bootstrap stage. The endgame (per the boundary
  profiling doc) is removing those delegate boundaries via in-assembly N#-to-N# calls.

## Adapters (debt to shrink toward zero)

- `NSharpCompilerDogfoodAdapter`, `NSharpCodeIntelligenceDogfoodAdapter`,
  `NSharpPerformanceDogfoodAdapter`, `NSharpCliDogfoodAdapter` — all still present as temporary
  transition boundaries. None removed yet. Each routed kernel still crosses the ~1.2 ns
  delegate-dispatch + bounds-check floor documented in the boundary profiling doc.
