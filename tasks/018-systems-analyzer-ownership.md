# 018 — Systems analyzer ownership

## Execution contract

Follow the active compiler-only contract in [README.md](README.md). Astra plans, reviews and
integrates; Sol Max or Terra Max implement bounded ownership areas. This replaces the historical
one-vertical-policy-slice, smallest-deletion and line-budget instructions formerly in this task.
Move complete classes or connected method groups with all necessary helpers and state. Select
boundaries from production dependencies; first consider moving a dependency with its callers.

Add no C# compiler behavior, tests, helpers, adapters, callbacks or fallbacks. Preserve accepted N#
policies, semantic identities, diagnostics, evaluation order and meaningful failure state. Canonical
assertions must execute in N#; migrate remaining C# assertions and reuse existing coverage where
it already proves the selected behavior. Prove blockers by compiling actual proposed N# source.

Use ./scripts/dev.sh and targeted tests, commit coherent passing pieces, and continue until the
whole selected area is integrated. Root owns shared ratchets, SDK publication, review and the fresh
integration gate before push. Preserve IDE verification when behavior affects the IDE. Broader CLI,
editor, runtime reimplementation and NativeAOT initiatives stay separate; preserve existing AOT
report facts without making NativeAOT an implementation objective.

## Selected area: complete SystemsAnalyzer

Replace all of `src/NSharpLang.Compiler/Performance/SystemsAnalyzer.cs`, including its nested
MutableFunctionSummary, FunctionEntry, DeclarationSite, CallSite and WalkContext types. Move all
initialization, caches, declaration registration/site resolution, visible-file projection, recursive
traversal/effect propagation, scope stacks, finding transport and report construction together.
Keep the already migrated Systems* policies as their existing N# owners.

Route MultiFileCompiler directly to the sole N# SystemsAnalyzer type and delete the C# class.
Preserve declaration-site value equality, AST reference identity, report-list aliasing, traversal
and diagnostic order, recursion protocol, conservative ambiguity and failure timing. No C# host or
fallback is an acceptable completion of this selected class migration.

The earlier task checkbox recorded policy migration only. Complete-class ownership is now accepted:
`946821316` deletes the whole C# class; subsequent integration preserves private helpers and sealed
metadata and routes lifecycle assertions directly to N#. The fresh gate at `3617a809a` passes
574 unit / 7,940 canonical / 53 native projects / 12 throughput / 68 IL assemblies in 474s.
Official SDK publication, ordinary package tests 11/11 and installed self-host 7,940/7,940 pass.
See [the accepted boundary](../systems-language-closeout/decodes/2026-09-07-complete-systems-analyzer-ownership.md)
and [compiler cursor](../systems-language-closeout/STATUS.md). The compiler-wide objective remains open.
