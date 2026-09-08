# 016 — Parser and syntax-diagnostic ownership

## Execution contract

Follow the active compiler-only contract in [README.md](README.md). Astra plans, reviews and
integrates; Sol Max or Terra Max implement bounded complete ownership areas. This supersedes the
historical one-vertical-slice, smallest-deletion and one-turn wording. Preserve the accepted N#
lexer/parser/diagnostic kernels and deleted Parser.cs; do not restart those migrations.

Move complete methods, classes or connected groups with their helpers and state. Add no C# compiler
behavior, tests, helpers, adapters, decision callbacks or fallback implementations. Compile actual
proposed N# to prove capability blockers; first consider moving dependencies with their callers.
Canonical assertions must execute in N# and production must route directly to its sole N# owner.
Preserve semantic identity, evaluation/materialization order, diagnostics and meaningful failure state.

Use ./scripts/dev.sh and targeted native/canonical tests while implementing; commit coherent passing
pieces. Root owns ratchets, review, fresh integration gates, any necessary verified SDK publication
and push. Backend-only changes use the non-VS-Code gate at integration checkpoints; retain mandatory
IDE-enabled gate and visual verification when a change actually affects IDE behavior. Broader branch
initiatives remain in [BRANCH-BACKLOG.md](BRANCH-BACKLOG.md).

## Accepted area: complete ColumnarProgramInputBuilder

At the accepted SystemsAnalyzer checkpoint `3c1b0f074`, replace all 17 methods in the 1,033-line C#
ColumnarProgramInputBuilder class. This is the remaining production owner for token/declaration
orchestration, function/constructor/property/type/test/newtype input materialization, trimmed node
tables, single/multi-file aggregation and decline location/failure ordering. Keep the existing N#
parser kernels, ColumnarTokenizedSource, input models, decline vocabulary and merge owner.

Delete the whole C# class and route MultiFileCompiler's existing TryBuildMultiFile call directly to N#.
Preserve out values on failure, allocation/copy order, node sentinel and child-table sizing, partial
materialization, source-file trace set/clear in finally, and the order of all declaration families.
Migrate the existing native columnar-emit-facts reflection lookups to the N# assembly/methods and
add focused N# assertions only for real gaps. Review any necessary cross-assembly visibility as an
explicit mechanical integration boundary; add no wrapper or callback.

Reviewed boundary: expose the N# type and static TryBuildMultiFile entry point for the existing
cross-assembly caller. Keep TryBuild and the remaining helpers private, with canonical reflection
targeting BootstrapServices directly; emitter lookups still target Compiler. Preserve a non-instantiable
type. The top-level program remains null on failure, but TryParseColumnarFunctionAt assigns its input
before local-function validation and can expose a partial input on a later failure. Single-source
inputs without tests retain null Tests; the accepted multi-file merge retains its empty test list.
Do not normalize these distinct states or add validation that changes failure ordering.

This complete class is integrated as c2379140a/7f747d76a. The fresh backend gate passes
574 unit / 7,943 canonical / 53 native projects / 12 throughput / 68 IL assemblies; ordinary installed
SDK probe15/15 and fresh self-host7,943/7,943 pass. The cross-assembly boundary and evidence are
[recorded here](../systems-language-closeout/decodes/2026-09-07-complete-columnar-input-builder-ownership.md).
Compiler-wide ownership remains open. See the current compiler cursor in
[STATUS.md](../systems-language-closeout/STATUS.md).
