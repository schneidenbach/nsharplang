# 017 — Semantic analyzer ownership

## Execution contract

Follow the compiler-only contract in [README.md](README.md). It supersedes the historical
one-vertical-slice, smallest-deletion and line-budget instructions formerly in this task.
Astra plans, reviews and integrates; delegate bounded implementation to Sol Max or Terra Max.

Select complete methods, classes or connected method groups with their necessary helpers and
state. Choose boundaries from production dependencies and consider moving dependencies with
callers. Preserve accepted N# semantic policies and valid baseline evidence.

Add no C# compiler behavior, tests, helpers, adapters, callbacks or fallbacks. N# must be the sole
production authority for a migrated area. Move canonical assertions with the behavior, preserving
semantics, diagnostics, evaluation order, identities and meaningful failure paths. Prove capability
blockers by compiling actual proposed N# source; implement necessary prerequisites in N#.

Use ./scripts/dev.sh and targeted tests, commit coherent passing pieces, then complete the selected
area through review, required fresh integration verification and push. Preserve required IDE
verification when behavior affects the IDE. SDK/tooling changes belong here only as demonstrated
compiler migration dependencies. Broader CLI/editor/runtime/NativeAOT work stays separate.

## Accepted ownership

The entire Analyzer class is now N#-owned in BootstrapServices. `Analyzer.cs` is deleted, including
all state, factories, recursive drivers and metadata lifecycle. Canonical fixtures target the sole
new owner, with no compatibility wrapper or legacy fallback. Four remaining C# analyzer cases and
their canonical assertions are migrated; existing accepted semantic families remain accepted.

The final fresh gate and ordinary installed-SDK self-host, native corpus, metadata and package
verification pass. See [the complete-owner record](../systems-language-closeout/decodes/2026-09-06-complete-analyzer-ownership.md)
and the current [compiler cursor](../systems-language-closeout/STATUS.md) for exact evidence.
Task 017 is complete; the broader compiler-only objective remains open.
