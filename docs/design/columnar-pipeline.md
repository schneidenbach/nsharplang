# The Columnar Self-Host Pipeline

**Status:** Active — the chosen self-host endgame (decision 2026-06-06, "go big"). This is the north-star
architecture for making the N# compiler the fast main entry point for all compiler tooling while eliminating
the C# reliance. Read [`self-host-progress.md`](self-host-progress.md) (slices 22–27) for the evidence that
produced this plan, and [`compiler-dogfood-boundary-profiling.md`](compiler-dogfood-boundary-profiling.md) for
the boundary-cost analysis.

## The thesis (why this, and why now)

The N#-native parser front-end is **correctness-complete** (parses 100% of the compiler's own systems source
byte-identically to the C# parser) and **2.4× faster / lower-allocation** than the C# parser — *but only when
its output is NOT materialized into the C# object-graph AST*. Routing the parser and materializing back to the
C# AST is **4–5× slower / 18× more allocation** (slice 25–26), because:

- Materialization rebuilds the *same* C# `CompilationUnit`/`Statement`/`Expression` object graph the C# parser
  builds, so routed allocation = C# allocation + the columnar tables. Strictly worse.
- That materialization exists *only* because the binder/analyzer/codegen downstream are still C# and consume
  the C# AST.

So **"eliminate the C# reliance" and "capture the speed win" are the same task**: make the downstream stages
consume the columnar node tables directly. The advantage **compounds** — a downstream semantic pass on the
columnar tables is ~1.6× faster than walking the AST and never allocates the 600 KB+ object graph (slice 27);
every additional pass widens the gap, because the AST is re-walked while the columnar tables stay tiny and
cache-resident.

It is NOT a marshaling/boundary problem — the C#↔N# delegate boundary is negligible (the pooled columnar path
crosses it identically and is 2.4× faster).

## The architecture

```
source ──► [N# Lexer kernel] ──► tokens (int columns: kind/start/len)
       ──► [N# parser kernels] ──► COLUMNAR NODE TABLES (flat int[] forest, per the kernel pattern)
       ──► [N# binder]        ──► symbols + columnar symbol/type tables (NO C# AST)
       ──► [N# analyzer]      ──► diagnostics + resolved columnar tables
       ──► [N# codegen]       ──► IL
```

The columnar node tables (kind, value-span, child-run, source-span columns; see
[`project_nsharp_parser_kernel_pattern`] in memory) are the *single intermediate representation* end-to-end.
The standalone columnar backend consumes those tables DIRECTLY (parse → symbol/type/diagnostic services →
`ColumnarIlEmitter`), never materializing an internal C# AST. The earlier `ColumnarAstMaterializer` +
`TryParseCompilationUnit` route — which materialized the tables back into the C# `CompilationUnit` AST as a
parser correctness oracle and a (deliberately-off) front-end routing path — was REMOVED (2026-06-08): it was a
measured dead-end (~4.4× slower / ~18× more allocation, because materializing re-incurred the full C# AST
allocation on top of the table cost), and parse correctness is now validated directly by the columnar services'
parity tests and the standalone emit backend (which parses + emits the whole dogfood corpus, value-matched vs
the C# pipeline). If a future public-API boundary ever needs an `Ast.CompilationUnit`, a fresh boundary adapter
is reintroduced then — it is not carried as dead scaffolding now.

## Non-negotiable design rules (pinned by the spikes)

1. **Pool / right-size the columnar tables.** Never allocate whole-file-sized tables per function (slice 26:
   that alone was 17× allocation). One reusable buffer set per worker, sized to the unit.
2. **Resolve names to integer symbol IDs / interned strings ONCE.** Never `Substring` a name per access
   (slice 27: naive re-materialization was 53× allocation; interning dropped it to ~1 KB). Downstream passes
   work on symbol IDs, not strings.
3. **No internal materialization to the C# AST.** Each ported stage consumes columnar tables and produces
   columnar tables (or symbol/diagnostic outputs). The C# AST is an output format, not a working format.
4. **Every ported stage is parity-gated against the C# stage** on the dogfood corpus before it routes, and
   **benchmarked** (never-slower vs the C# stage on representative + large input) before it becomes default.
5. **C# fallback always present** until a stage's columnar form covers the full language surface it replaces.

## Staged plan (each stage: build → parity-gate → benchmark → route with fallback → shrink C#)

1. **Symbol table / declared-symbol model** *(first stage — in progress).* Build the top-level symbol model
   (functions: name, parameter types, return type, modifiers; later: types and their members) directly from
   the columnar declaration + signature tables. Parity vs the C# AST-derived symbol model on the dogfood
   corpus; benchmark columnar-build vs AST-build. This is the foundation name resolution queries.
2. **Name resolution / binding.** Resolve identifier nodes to symbol IDs over the columnar tables (scopes as
   columnar ranges). Replaces the AST-walking binder for the supported surface.
3. **Type checking / analysis.** Port the analyzer's hot semantic passes to columnar; emit diagnostics with
   source spans (positions already in the node tables).
4. **Codegen.** Emit IL directly from the columnar + resolved tables.
5. **Shrink the C# surface.** As each stage routes, delete the corresponding C# path and the `*DogfoodAdapter`
   bridge surface it replaces (acceptance criteria 5–6: the bridges are the transition boundary, not product
   architecture).

Coverage grows in parallel: the parser kernels currently handle the systems subset (functions + the
statement/expression/type forms the dogfood corpus uses, incl. casts). Class/struct/enum/interface/union
declarations, `for`/`foreach`/`let`/`match`/lambdas etc. are added as stages need them — driven by real
corpus need, not speculatively.

## How we know it's working

- Per-stage parity tests (columnar output ≡ C# output on the dogfood corpus) — correctness.
- Per-stage benchmarks (columnar vs C#, representative + large) — the never-slower gate before routing.
- The cumulative metric: **C# back-end LOC deleted** and **dogfood-corpus end-to-end compile time/allocation**
  as stages route. The end state: parse→bind→analyze→codegen runs on columnar tables with no internal C# AST,
  and the `*DogfoodAdapter` bridges shrink toward deletion.
