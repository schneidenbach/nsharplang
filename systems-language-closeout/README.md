# Systems-language closeout

The former track-based campaign documents were retired on 2026-07-10 because they encouraged
large, partially routed migrations and allowed N# foundations to grow faster than C# owners were
deleted.

The authoritative work queue is now [`../tasks/README.md`](../tasks/README.md). Each numbered file
is an executable prompt with the no-new-C# contract prepended. Work proceeds in order, one vertical
ownership slice per goal turn.

[`STATUS.md`](STATUS.md) is only the live cursor and evidence ledger. It must not become another
architecture plan. Durable final survivor documentation belongs in
`memory/architecture.md#non-nsharp-survivors`.

[`MEASUREMENT-VERDICT-2026-09.md`](MEASUREMENT-VERDICT-2026-09.md) is the 2026-09-01 compile-time
measurement of `nlc` (harness: `tests/native/compile-time-bench`) and the written price of finishing
task 015, laid out as two options for the user to decide between.

## Pruned evidence, 2026-09-22

The per-slice decode records that lived under `decodes/` and the checked-in verification evidence
under `artifacts/` (the 2026-09-01 compile-time raw output and the 2026-09/-02b/-02c IDE
verification rounds) were removed from the tree: they are evidence, not product, and nothing in the
build, the gate or any test reads them. `artifacts/` was already gitignored and its contents were
force-added; the gate never saw them at all, because `tests/scripts/test-all.sh` excludes
`artifacts/` from the isolated gate tree.

Both sets remain recoverable in full from git history at `6cab15e2f`, for example
`git show 6cab15e2f:systems-language-closeout/decodes/2026-09-09-compiler-only-ownership-complete.md`.
Documents that cited a decode still name the record's file, in backticks rather than as a link.
