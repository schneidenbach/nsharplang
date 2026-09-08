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

## Selected area: complete ColumnarProgramInputBuilder

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

This complete class remains open until sole production ownership, canonical coverage, required
verification, review, commits and push pass. See the current compiler cursor in
[STATUS.md](../systems-language-closeout/STATUS.md).
