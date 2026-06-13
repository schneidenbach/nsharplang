# SoA Table Types

**Status:** Design gate plus first experimental wrapper-lowering slice for the emitter-port phase.
This document is the contract for adding a small N# surface that makes the existing columnar compiler
tables pleasant to write without changing their layout.

## Goal

The compiler already uses struct-of-arrays tables everywhere: token kinds, node kinds, value spans,
child runs, source spans, symbol ids, type ids, and diagnostics all live in parallel arrays. That
layout is the performance win. The problem is ergonomics: hot N# code still carries long parameter
lists like `outNodeKinds, outValueStarts, outValueLengths, outChildStart, outChildCount, ...`, and
state arrays like `st[0]`, `st[1]`, `st[2]` encode named facts as magic slots.

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

`new` allocates exactly one array per column and initializes `length = 0`. `wrap` creates a view over
caller-provided arrays, verifies matching lengths/capacity, and performs no element copy.

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

V1 admits column element types already supported by the columnar backend:

- numeric scalars used by the compiler tables (`int`, `uint`, `long`, `bool`, `char`);
- `string` and nullable reference columns only when the surrounding code already routes them;
- enum element columns when the enum has an explicit underlying representation;
- user value types only after their column element load/store shape is IL-verified.

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

## Diagnostics

The compiler must produce direct diagnostics for common misuse:

- row value escapes: "SoA row views cannot be stored or returned; use the table and row index";
- mismatched `wrap` columns: "column lengths for NodeTable do not match";
- unsupported element type: "SoA column type X is not supported in this lowering";
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
non-escapable at analysis time. While the flag is enabled, `MultiFileCompiler` deliberately falls
back from the default columnar backend to the C# IL backend for programs containing SoA declarations;
the columnar backend does not own this surface yet.

The flag is for compiler table-migration gates only. Production builds without the flag still report
`NL323 FeatureNotImplemented` for every `soa record`.

## Migration Plan

1. Done: add the parser and analyzer surface for non-generic `soa record` declarations, with no production use.
2. Done behind `NSHARP_EXPERIMENTAL_SOA=1`: lower `new`, `wrap`, column access, row projection, `length`,
   `capacity`, and the core table operations to wrapper-backed arrays in the direct IL backend.
3. Port one cold parity-corpus table to prove diagnostics and IL shape.
4. Port `ParserState` from `st: int[]` to a small normal struct only after member writes and by-ref lowering
   are proven; do not mix that with SoA table columns.
5. Port parser node tables in `ParserExpressions.nl`, `ParserStatements.nl`, `ParserTypeReferences.nl`, and
   `ParserDeclarations.nl`, preserving the flattened ABI at hot call boundaries.
6. Port symbol/type/diagnostic tables.
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
