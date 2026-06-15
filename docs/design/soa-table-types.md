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
lengths/capacity, and performs no element copy. `wrap` exposes generated parameter names for each
column plus `length`, so named calls such as `NodeTable.wrap(length: n, kind: kinds)` bind
semantically, including target-typed argument inference; negative literal `length` values are
rejected during analysis. Target-typed `default` is not a construction form for SoA tables because it
would produce a CLR wrapper value with null backing column arrays; use `new Table(capacity)` or
`Table.wrap(...)` instead. Target-typed `new()` without the required capacity argument is rejected
the same way as `new Table()`, including when the expected table type comes from a typed local,
return, expression-bodied function/local function, call argument, default parameter value, field,
expression-bodied property, object initializer member, `with` expression member, assignment target,
array literal element, array initializer element, collection literal element, tuple literal element,
typed ternary/match result arm, hard-cast target, or checked/unchecked expression wrapper.
The same construction rule applies when the expected type is nullable (`Table?`): `new()` still lacks
the required backing-column capacity and must not become a nullable wrapper around an invalid table.
Parameter declarations cannot use any SoA table as an optional-parameter default, including `null`
or `new Table(capacity)`, because defaults are metadata constants while table wrappers require
runtime-owned columns or caller-provided wrapped columns.

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

The compiler rewrites those to column element operations for both reads and writes. This means:

- `nodes[^1].kind` declines; row projection indexes are explicit `int` row ids, while `System.Index`
  from-end access is only valid on direct backing columns such as `nodes.kind[^1]`. The same rule
  applies to write targets such as `nodes[^1].kind = value`.
- `nodes[0..1].kind = value` declines; range indexes would be row-slice syntax, not a scalar row id.
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
- `string` and `string?` columns;
- int-backed enum columns.

Future slices can admit user value types only after their column element load/store shape is
IL-verified. String enums remain outside this lowering because they are string constants, not dense
table element values.

Generic SoA records are not accepted in v1 because their flattened ABI still needs an explicit
design. Array columns, nullable non-string columns, string-enum columns, nested SoA-table columns,
and any element type that requires hidden copy constructors or disposal are rejected until their
load/store and wrapper method shapes have direct IL proof.

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
rows. `copyRow` emits one element copy per column. The generated parameter names are part of the
semantic signature: `ensureCapacity(capacity: n)` and `copyRow(from: src, to: dst)` are valid, and
unknown or duplicate generated operation argument names are rejected before lowering.

Bulk transforms such as filtering, sorting, and compaction remain explicit kernels. `soa record` should
not grow LINQ-like methods that obscure allocation or control flow.

Row-column access supports direct reads, simple stores, expression-valued stores, default stores,
null-coalescing reads and assignment, compound assignment, and increment/decrement for integral
column element types. These accepted operations lower to the backing column arrays without row-object
materialization; `string` and `string?` columns support reads/stores, concatenating `+=`
expressions, and null coalescing. Both string column shapes have direct string equality/inequality
evidence, while `string?` columns additionally have direct null equality/inequality evidence. Both
string column shapes reject `-=`, `*=`, `/=`, `++`, and `--` during analysis. Bool columns support
same-bool equality/inequality, logical-not, and bitwise expressions but still reject arithmetic
compound assignment before lowering; non-bool column elements reject logical-not during analysis.
Numeric scalar columns support equality/inequality and relational comparisons,
including unsigned comparisons for `uint`, plus arithmetic expression stores, arithmetic compound
assignments, signed `int`/`long` unary negation, same-type bitwise expressions, and unary bitwise-not.
`uint` unary negation still promotes to `long`, so assigning it back to a `uint` column is rejected
before lowering. Numeric scalar columns also support shift expressions with direct signed and unsigned
right-shift lowering. Char columns support equality/inequality and relational comparisons. Int-backed
enum columns support the enum language's comparison expressions, prefix/postfix increment and decrement
forms, same-enum bitwise expressions, and unary bitwise-not.
Arithmetic compound assignment is not part of the enum column proof. Each compound assignment must
type-check through the underlying operator and produce a result assignable back to the column, so
boolean and enum columns reject `+=`, `-=`, `*=`, and `/=` before lowering, while string/string?
columns reject every compound operator except concatenating `+=`. Direct column-element access through `table.column[row]`
follows the same update typing rules and is also
permitted for explicit systems kernels when the index shape is one the built-in array path supports.
Direct column elements support the same scalar update shapes as row projection: expression-valued
stores and compound assignments return the stored value, prefix/postfix increments preserve their
ordinary result semantics, and default stores write the backing column without reading the old value
or materializing a row. These accepted direct-column update shapes also apply to literal and
variable-held `System.Index` from-end element access such as `table.column[^1]` and
`table.column[idx]`, including expression-valued simple stores, default stores, prefix/postfix
increment/decrement, null-coalescing reads, and null-coalescing assignments.
The same nullability rule applies to both row projection and direct column elements: `??` and `??=`
require a nullable/reference column element and non-nullable columns reject the operation during
analysis. Direct-column range slices remain rejected before IL lowering instead of falling into the
allocating array-slice backend.
Replacing wrapper column arrays, mutating `length`/`capacity` directly, or mutating column slices is
not allowed: shape changes must go through construction, `wrap`, `add`, `clear`, `ensureCapacity`, or
`copyRow`. Direct `length`/`capacity` simple assignment, compound assignment, and increment/decrement
forms all reject during analysis.

Direct column range reads (`table.column[start..end]`) are rejected because ordinary array slice
semantics allocate a sliced array. They can be admitted only after an allocation-free span/view lowering
has pinned IL-shape evidence. That rejection also applies when the range uses `System.Index`
from-end bounds, such as `table.column[1..^1]`. Slice update forms, including simple assignment,
compound assignment, null-coalescing assignment, increment, and decrement, all reject during analysis
for both ordinary and from-end ranges.

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
- row type annotations/type expressions: "SoA row type 'NodeTable.Row' is not part of this lowering"
  for parameter, return, local, other declared-type positions, `typeof`, and `sizeof`;
- mismatched `wrap` columns: "column lengths for NodeTable do not match";
- null `wrap` columns: "SoA table wrap column 'X' cannot be null" for literal null/default column
  arguments, or "columns for NodeTable.wrap cannot be null" for dynamic runtime values;
- invalid `wrap` length: "SoA table wrap length must not be negative" for negative literals, or
  "length for NodeTable.wrap must be between 0 and column length" for dynamic runtime bounds;
- invalid `new` capacity: "SoA table capacity must be int" or "SoA table capacity must not be negative"
  for analyzer-known literals, or "capacity for NodeTable must be non-negative" for dynamic runtime values;
- invalid default construction: "SoA table 'NodeTable' cannot be default-initialized";
- invalid target-typed zero-argument construction: "SoA table 'NodeTable' construction expects
  exactly one int capacity argument";
- invalid generated operation calls: "`add`, `clear`, `ensureCapacity`, and `copyRow` must be called with
  their declared argument counts, names, and types, and literal `ensureCapacity`/`copyRow` capacity
  or row arguments must be non-negative"; dynamic negative `ensureCapacity`/`copyRow` values throw
  "capacity/source row/target row for NodeTable.operation must be non-negative"; dynamic `add` length
  overflow throws "length for NodeTable.add is too large", and dynamic `copyRow` sources at or beyond
  `length` throw "source row for NodeTable.copyRow must be less than length";
  target rows too large to extend throw "target row for NodeTable.copyRow is too large";
- unsupported element type, including arrays, nullable non-string columns, string-enum columns, and
  nested SoA-table columns: "SoA column type X is not supported in this lowering";
- unsupported row/direct column compound assignment, including enum arithmetic compound assignment:
  "The '+' operator doesn't work with 'X' and 'Y'";
- non-integral row/direct column increment/decrement: "The '++' operator doesn't work with 'X'";
- non-nullable row/direct column null coalescing, including enum columns:
  "The left side of '??' has type 'X', which can't be null";
- non-int, `System.Index`, or range row indexes: "SoA table indexes must be int row ids";
- statically negative row indexes on row/direct-column reads or writes:
  "SoA table row indexes must not be negative" or "SoA column row indexes must not be negative";
- direct table member mutation: "SoA table member 'X' cannot be assigned directly" for simple and
  compound assignment, or "SoA table member 'X' cannot be incremented or decremented directly";
- non-int direct column element indexes: "Array indexes must be int, System.Index, or System.Range";
- direct column slice mutation: "Array slices cannot be assigned" or
  "Array slices cannot be incremented or decremented";
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
construction, heap array allocation, or virtual dispatch, including default stores across the
verified scalar/reference element-type set, including expression-valued default stores, without
old-element reads; explicit direct column element operations (`table.column[row]`) have the same
column-array proof for stores, expression-valued stores, default stores across the verified
scalar/reference element-type set, including expression-valued default stores, without old-element
reads, compound stores, prefix/postfix increments, reads across the verified scalar/reference
element-type set, direct column null-coalescing reads/assignments, and from-end `System.Index` access
including expression-valued simple stores, default stores across the verified scalar/reference
element-type set, including expression-valued default stores, without old-element reads, verified
scalar/reference element reads/stores, bool bitwise expression stores, int-backed enum
reads/stores/default stores/generated methods, string/string? concatenating compound assignments,
string/string? equality/inequality expressions, nullable-string null equality/inequality expressions,
bool equality/inequality and logical-not expressions, numeric scalar comparison expressions, char comparison
expressions, numeric scalar arithmetic expression stores, numeric scalar arithmetic compound
assignments, signed numeric scalar unary negation stores, numeric scalar bitwise expression stores,
numeric scalar unary bitwise-not stores, numeric scalar shift expression stores, same-enum comparison
expressions, bitwise and unary bitwise-not expression stores, plus prefix/postfix update forms,
integral `uint`/`long`/`char` update forms, and null-coalescing reads/assignments.
Row-projection null-coalescing
reads/assignments have the same direct column proof, with range/slice allocation still rejected during
analysis. Row-projection integral `uint`/`long`/`char` update forms are pinned with the same
backing-column array proof. The generated `new`, `wrap`, `add`, `clear`, `ensureCapacity`, and
`copyRow` methods are also pinned across the verified scalar/reference element-type set.
Construction allocates exactly one array per column and stores column/metadata fields; `wrap` stores
incoming column references without
allocating arrays or copying elements; `add` updates only length metadata after calling
`ensureCapacity`; `clear` resets only length; `ensureCapacity` emits one `Array.Resize<T>` per column;
and `copyRow` emits one element load/store pair per column while still calling `ensureCapacity` for
explicit growth. These generated methods avoid row object construction, backing-column element
traffic except for `copyRow`'s explicit element copies, boxing, delegate construction, and virtual
dispatch.

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
