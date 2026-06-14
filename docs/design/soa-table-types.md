# SoA Table Types

**Status:** Design gate plus first experimental wrapper-lowering slice for the emitter-port phase.
This document is the contract for adding a small N# surface that makes the existing columnar compiler
tables pleasant to write without changing their layout.

## Goal

The compiler already uses struct-of-arrays tables everywhere: token kinds, node kinds, value spans,
child runs, source spans, symbol ids, type ids, and diagnostics all live in parallel arrays. That
layout is the performance win. The problem is ergonomics: hot N# code still carries long parameter
lists like `outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, ...`.
The first scalar-state cleanup is now complete: parser recursion uses a named `ParserState` struct
instead of encoding cursor facts in magic integer slots.

`soa record` is the language-level name for those tables. It must lower to the same parallel arrays
the compiler uses today. It is not a row-object abstraction, not a mini ORM, and not permission to
materialize an AST.

## Non-Negotiables

1. **Byte-identical table layout:** every declared column is one CLR array field or one lowered array
   parameter. Rows are indexes into those arrays.
2. **No row allocation:** `table[i].kind` is a compile-time projection to `table.kind[i]`. A row view
   cannot be boxed, stored in a heap field, captured by a closure, or returned.
3. **Caller-owned buffers stay first-class:** hot kernels can still receive externally allocated
   columns and lengths. Construction must not force ownership transfer or hidden copies.
4. **Columnar pipeline stays canonical:** SoA tables name the existing IR columns; they do not create
   a tree IR, object graph, visitor surface, or mutable per-row records.
5. **C# fallback remains until replacement coverage is complete:** a SoA feature can make compiler
   code cleaner, but it does not justify deleting `ILCompiler` or `Analyzer` until coverage and gates
   prove the replacement.

## Surface

The intended syntax is deliberately small:

```nsharp
soa record NodeTable {
    kind: int
    valueStart: int
    valueLength: int
    childStart: int
    childCount: int
    sourceStart: int
}
```

Each field declares a column element type, not a scalar row field. A `NodeTable` value has these
logical members:

- `table.kind`: the `int[]` column.
- `table.length`: the active row count.
- `table.capacity`: the column capacity.
- `table[i].kind`: row projection, lowered to `table.kind[i]`.

Construction has two forms:

```nsharp
nodes := new NodeTable(capacity)
nodes := NodeTable.wrap(kind, valueStart, valueLength, childStart, childCount, sourceStart, length)
```

`new` takes exactly one non-negative `int` capacity argument, allocates exactly one array per column,
and initializes `length = 0`. `wrap` creates a view over caller-provided arrays, verifies matching
lengths/capacity, and performs no element copy.

## Lowering

For local code, the compiler may scalar-replace a `NodeTable` value into locals:

```nsharp
nodes.kind[i] = 18
nodes.childStart[i] = childCursor
```

lowers exactly like the current hand-written code:

```text
ldloc nodes_kind
ldloc i
ldc.i4.s 18
stelem.i4
```

For internal hot-function parameters, a SoA parameter lowers to the parallel-array ABI by default:

```nsharp
func Parse(nodes: NodeTable, start: int): int
```

lowers as if it had received:

```nsharp
func Parse(nodeKind: int[], valueStart: int[], valueLength: int[], childStart: int[], childCount: int[], sourceStart: int[], nodeLength: int, start: int): int
```

The public CLR boundary may expose a small readonly wrapper struct when necessary, but the compiler
hot path must keep the flattened ABI. The flattened form is the default for functions in the compiler
dogfood assemblies.

## Row Views

Row views exist only as lvalue/rvalue syntax sugar:

```nsharp
nodes[i].kind = NodeKind.MatchExpression
checksum += nodes[i].valueStart
```

The compiler rewrites those to column element operations. This means:

- `row := nodes[i]` declines unless `row` is a stack-only ephemeral used in the same statement.
- `return nodes[i]` declines.
- `list.Add(nodes[i])` declines.
- `func f(row: NodeTable.Row)` is not part of v1.

These restrictions are intentional. Persistable row values would reintroduce the object-row shape this
feature exists to avoid.

## Type Rules

The current experimental lowering admits only the column element types that have been verified by
the direct-IL wrapper proof:

- numeric scalars used by the compiler tables (`int`, `uint`, `long`, `bool`, `char`);
- `string` and `string?` columns.

Future slices can admit enum element columns when the enum has an explicit underlying representation,
and user value types only after their column element load/store shape is IL-verified.

No nested SoA columns, no generic SoA records in v1, and no columns whose element type requires hidden
copy constructors or disposal.

## Operations

The v1 standard operations are:

```nsharp
idx := nodes.add()
nodes.clear()
nodes.ensureCapacity(required)
nodes.copyRow(from, to)
```

`add` returns the old `length` and increments it after ensuring capacity. `clear` sets `length = 0`
without clearing column arrays. `ensureCapacity` grows every column together and preserves existing
rows. `copyRow` emits one element copy per column.

Bulk transforms such as filtering, sorting, and compaction remain explicit kernels. `soa record` should
not grow LINQ-like methods that obscure allocation or control flow.

Row-column access supports direct reads, simple stores, expression-valued stores, default stores,
null-coalescing reads and assignment, compound assignment, and increment/decrement over the verified
column element types. These accepted operations lower to the backing column arrays without row-object
materialization. Direct column-element access through `table.column[row]` is also permitted for explicit
systems kernels when the index shape is one the built-in array path supports. Replacing wrapper column
arrays, mutating `length`/`capacity` directly, or assigning to column slices is not allowed: shape changes
must go through construction, `wrap`, `add`, `clear`, `ensureCapacity`, or `copyRow`.

Direct column range reads (`table.column[start..end]`) are rejected because ordinary array slice
semantics allocate a sliced array. They can be admitted only after an allocation-free span/view lowering
has pinned IL-shape evidence.

## Diagnostics

The compiler must produce direct diagnostics for common misuse:

- duplicate or reserved column names: "SoA column 'X' is already defined" or
  "SoA column 'X' conflicts with a generated table member";
- row value escapes: "SoA row views cannot be stored or returned; use the table and row index" (including
  locals, assignments, explicit returns, expression-bodied functions/local functions/properties/lambdas,
  explicit discards, call/constructor arguments, array literals, tuple literals, initializer values, yielding,
  throwing, printing, string interpolation, assertions, assertion messages, using resources, locks, and
  switch subjects, operator operands, casts, `is` tests, `must` unwraps, awaits, ternary results, and match
  results, bare expression statements, control conditions, match subjects/guards, foreach collections,
  range bounds, spread expressions, `alloc`, allocation lengths, checked/unchecked expressions, field
  initializers, invalid member/index receivers, index values, pattern values, `with` targets/indexes/values,
  `nameof` targets, event subscription handles, and null-conditional table/row projections);
- mismatched `wrap` columns: "column lengths for NodeTable do not match";
- null `wrap` columns: "columns for NodeTable.wrap cannot be null";
- invalid `wrap` length: "length for NodeTable.wrap must be between 0 and column length";
- invalid `new` capacity: "SoA table capacity must be int" or "SoA table capacity must not be negative";
- invalid generated operation calls: "`add`, `clear`, `ensureCapacity`, and `copyRow` must be called with
  their declared argument counts and types";
- unsupported element type: "SoA column type X is not supported in this lowering";
- non-nullable row-column null coalescing: "The left side of '??' has type 'X', which can't be null";
- non-int or range row indexes: "SoA table indexes must be int row ids";
- direct table member mutation: "SoA table member 'X' cannot be assigned directly";
- non-int direct column element indexes: "Array indexes must be int, System.Index, or System.Range";
- direct column slice mutation: "Array slices cannot be assigned";
- direct column slice reads: "SoA column range slices allocate arrays";
- hidden allocation request: "this operation would allocate row objects; use column access instead".

These diagnostics must point at the row access or column declaration, not at generated lowering code.

## Verification Gates

Every SoA implementation slice must prove:

- generated IL for representative kernels has the same column `ldelem`/`stelem` shape as the current
  parallel-array version;
- row-view code emits no `newobj`, `box`, delegate construction, or object-array traffic;
- `wrap` performs no element copies;
- parser/signature/diagnostic parity remains byte-identical on the dogfood corpus;
- `ColumnarCodegen_MultiFile_ParityCorpusCompilesWithZeroDeclines` still routes product+parity corpus;
- `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` passes before commit.

Benchmark gate:

- parser kernels rewritten to SoA must be no slower than the current parallel-array kernels;
- whole compiler-service compile under default columnar routing must not regress beyond the existing
  BenchmarkDotNet tolerance;
- if an ergonomic SoA rewrite slows a hot kernel, the rewrite is reverted or lowered more directly.

## Current Experimental Slice

`NSHARP_EXPERIMENTAL_SOA=1` enables the first direct-IL proof slice for top-level, non-generic SoA
records. The slice emits a sealed value-type wrapper with one public array field per column plus
`length` and `capacity`, supports `new Table(capacity)`, zero-copy `Table.wrap(columns..., length)`,
column access, row projection, `add`, `clear`, `ensureCapacity`, and `copyRow`, and keeps row views
from escaping through locals, returns, call arguments, assignments, and object initializers. While
the flag is enabled, `MultiFileCompiler` deliberately falls
back from the default columnar backend to the C# IL backend for programs containing SoA declarations;
the columnar backend does not own this surface yet.

The flag is for compiler table-migration gates only. Production builds without the flag still report
`NL323 FeatureNotImplemented` for every `soa record`.

IL-shape tests pin the current wrapper proof: row projection over an existing table emits direct
column field loads and array element loads/stores with no row allocation, boxing, delegate
construction, heap array allocation, or virtual dispatch; the generated `copyRow` method has the same
direct column-element shape and no row object construction, inline array allocation, boxing, delegate
construction, or virtual dispatch, while still calling `ensureCapacity` for explicit growth. `wrap`
stores incoming column references without allocating arrays or copying elements; `add`, `ensureCapacity`,
and `clear` keep the same column-array shape without row allocation or virtual dispatch.

The first migration fixture uses the real overload-candidate compact table shape under the
experimental flag. It wraps the existing candidate columns as `OverloadCandidateTable`, preserves the
current ranking tie-break rules against a parallel-column baseline, and asserts the migrated
row-projection loop stays allocation-free and dispatch-free. The production dogfood project is still
kept free of SoA declarations until either hot-function flattened ABI lowering or columnar-emitter
ownership lands.

## Migration Plan

1. Done: add the parser and analyzer surface for non-generic `soa record` declarations, with no production use.
2. Done behind `NSHARP_EXPERIMENTAL_SOA=1`: lower `new`, `wrap`, column access, row projection, `length`,
   `capacity`, and the core table operations to wrapper-backed arrays in the direct IL backend.
3. Done as an experimental fixture: port the overload-candidate compact table shape to prove cold-table parity
   and row-projection IL shape without production routing.
4. Done: port parser recursion state from `st: int[]` to a small normal `ParserState` struct across the
   type, expression, statement, and function-signature kernels.
5. Done: port parser node/declaration tables while preserving the flattened ABI at hot call boundaries.
   The type-reference recursive core uses a normal `ParserNodeTable` wrapper, the mutually-recursive
   expression/statement cores share `ParserExpressionNodeTable`, and declaration kernels now group their
   import/top-level/member/case output columns behind named table wrappers.
6. In progress: port symbol/type/diagnostic tables. `SemanticScopes.nl` now wraps source-position,
   parent/symbol-range, sorted-index, symbol-name, depth-output, and name-set scratch columns behind
   normal table structs; its follow-up pass also wraps visible/lookup query-result columns and
   sorted-index scratch storage. `TypeLookup.nl` wraps declared-type lookup and type-creation ordering
   tables the same way. `DiagnosticDeduplication.nl` now wraps diagnostic/reference key columns and
   deduplication scratch indexes behind wrapper-aware cores, and `DiagnosticClusters.nl` wraps
   severity/trait/cluster-id/location/group/member tables for diagnostic clustering. `BindingLookup.nl`
   wraps declaration, binding, query, candidate-column, nearest-declaration, result, slot, and scratch
   tables for semantic binding lookup. `OverloadCandidates.nl` now wraps the production compact
   overload score, parameter-range, argument, call-slice, and result tables, `IdentifierSpans.nl`
   wraps code-intelligence line ranges, queries, results, and caches, and `AnalyzerExhaustiveness.nl`
   wraps analyzer coverage, missing-case result, and overload-signature rank tables. `SourceTextLines.nl`
   now wraps logical line ranges, line-start indexes, and dense offset-line maps. The small
   compiler-service utility pass also wraps struct-copy field flags, anonymous-union parameter flags,
   and project source filter path/pattern/result tables. Formatter import ordering and text-edit
   ordering now wrap their sort-key/rank, bucket, and temp/result index scratch tables. CLI doc
   ordering and linter import analysis now wrap doc-symbol ordering ranks/buckets, slug tables,
   symbol-kind filter inputs, import namespace ranks, used namespace ranks, flag scratch, and result
   indexes. `DocQuery.nl` now wraps documentation type-candidate columns plus member-order
   rank/bucket/index tables, and `CliQueryParsing.nl` wraps CLI query position inputs/results,
   duplicate-id rank/count/result tables, packed result words, and integer parse result storage
   without using the experimental `soa record` surface. `LexerTokenKindScanner.nl` now wraps
   token-kind buffers, parser-compaction indexes, token metadata streams, indentation post-pass
   inputs/outputs, indentation stacks, and comment-trivia output tables. The remaining small service
   kernels now wrap formatter safety diagnostics, path matching batches, typo-suggestion scratch and
   result tables, AOT requirement grouping columns, completion receiver/grouping tables, and CLI tree
   dependency deduplication buffers. `CliArguments.nl` has begun its large-file migration by wrapping
   argv inputs, option-value sets, result indexes, lint project-value indexes, tidy package/import
   name batches, status-rank outputs, source-line batches, and keep-flag outputs for the positional,
   run/watch, publish, test, lint, and tidy argument clusters. It now also wraps symbol-name filter
   inputs/results plus build/export operand kind columns and linked-list scratch columns, and wraps
   `nlc fix` safety-rank, edit-count, edit-flattening, file-rank, rank-bucket, and applied-file group
   result columns. Unified-diff hunk range inputs/results and clean-artifact directory ordering
   inputs/scratch/result columns are now table-wrapped as well. These slices preserve the flattened
   dogfood adapter ABI. The update-dependency, reference-type, stable-distinct, best-score, and
   summary-counter rank/flag/score columns now also route through named normal structs. The
   remaining `CliArguments.nl` test-filter name batches and format-discovery path/flag batches are
   table-wrapped too, leaving its array-taking functions as flattened adapter shims or scalar helper
   shims over wrapper-aware cores. `ParserTypeReferences.nl` has started the parser token-stream
   cleanup by wrapping token metadata, recursive argument stacks, child-index outputs, and result
   slots for the type-reference recursive cores. `ParserFunctionSignatures.nl` now composes those
   parser wrappers from a flattened entry shim and groups parameter, type-parameter, `where`
   constraint, and result columns behind named tables in its internal core. `ParserStatements.nl`
   now routes statement recursion through the same token, argument-stack, child-index, expression-node,
   and result wrappers, with only flattened compatibility shims left at expression/host boundaries.
   `ParserExpressions.nl` now does the same for its pattern, expression-precedence, call, lambda, and
   expression-entry recursion, and composes type-reference parsing through a wrapper-aware expression
   node/table bridge. `ParserDeclarations.nl` now also routes package/header scans, top-level declaration
   scans, interface/enum/struct/class/record, constructor-chain, and union parser bodies through
   declaration token-stream and result-slot wrappers while preserving the flattened adapter ABI.
7. Only after those gates pass, start replacing C# emitter/analyzer internals that still require untyped
   parallel-array plumbing.

## Explicit Non-Goals

- No array-of-structs lowering.
- No public row object model.
- No general table query language.
- No automatic AST materialization.
- No implicit reflection schema.
- No deletion of C# fallback merely because a SoA syntax slice exists.

## Open Questions

1. Whether `soa record` wrappers should be visible in public metadata or kept compiler-internal until the
   compiler self-host is complete.
2. Whether a future generic `soa record<T>` is worth the complexity once the compiler tables have migrated.
3. Whether dense enum columns should get a smaller physical storage type after explicit enum underlying types
   are fully settled. V1 uses the declared CLR element type and does not pack.
