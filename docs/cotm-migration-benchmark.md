# COTM N# Migration Benchmark

COTM is the local external migration corpus for stress-testing compiler, CLI, formatter, lint, and migration changes against a real converted ASP.NET/EF application. It is intentionally not vendored into this repository and must remain opt-in: public CI must not fail just because a private/local COTM checkout is unavailable.

## Entrypoint

From an NSharpLang checkout or feature worktree:

```bash
scripts/run-cotm-migration-benchmark.sh
```

The script:

1. Finds the COTM repo from `COTM_NSHARP_ROOT`, `--cotm-root`, or `/Users/spencer/code/cotm2-nsharp`.
2. Skips cleanly with exit code `0` when the COTM repo or its benchmark harness is absent.
3. Builds `src/NSharpLang.Cli/Cli.csproj` from the current checkout, unless `--no-build` is supplied.
4. Delegates to `scripts/run-nsharp-cotm-benchmark.py` in the COTM repo with `--nsharp-root` pinned to this checkout.
5. Exits with the COTM harness exit code when the harness is present.

This keeps compiler/CLI branch validation local to the branch under test instead of accidentally benchmarking the default `/Users/spencer/code/nsharplang` checkout.

## Choosing the COTM checkout

Use either an environment variable:

```bash
COTM_NSHARP_ROOT=/Users/spencer/code/cotm2-nsharp scripts/run-cotm-migration-benchmark.sh
```

or an explicit flag:

```bash
scripts/run-cotm-migration-benchmark.sh --cotm-root /Users/spencer/code/cotm2-nsharp
```

During harness development, a separate worktree such as `/Users/spencer/code/cotm2-nsharp-cotm-benchmark-worktree` is also valid if that is where `scripts/run-nsharp-cotm-benchmark.py` exists.

## Passing artifact and baseline arguments

Arguments after `--` pass through to the COTM harness. Use this for artifact output directories, baseline comparison, rebaselining, timeouts, or explicit CLI wrappers:

```bash
scripts/run-cotm-migration-benchmark.sh \
  --cotm-root /Users/spencer/code/cotm2-nsharp \
  -- \
  --output-dir docs/nsharp-conversion/runs/manual-$(date -u +%Y%m%dT%H%M%SZ) \
  --baseline docs/nsharp-conversion/benchmark-baseline.json
```

Common pass-through options:

- `--output-dir <path>`: where the COTM harness writes command artifacts and `summary.json`.
- `--baseline <path>`: baseline summary JSON for regression comparison.
- `--rebaseline`: intentionally update the COTM baseline after accepting current results.
- `--timeout <seconds>`: per-command timeout inside the COTM harness.
- `--nlc <command>`: override the harness CLI command. Normally omit this so the wrapper uses this NSharpLang checkout via `--nsharp-root`.

## When to run it

Run this before merging compiler, CLI, formatter, lint, query, SDK, or migration changes that could affect converted C# projects. The benchmark is especially useful before accepting changes to diagnostics, generated C# shape, project resolution, or ASP.NET/EF idiom handling.

Docs-only changes do not require a full COTM run unless they change the benchmark contract itself.

## Regression criteria

Hard failures:

- Entities semantic diagnostics must stay green: `entities-query-diagnostics` exits `0` and reports `0` `ERROR` diagnostics.
- `api-check` or `tests-check` `ERROR` counts may not increase versus `docs/nsharp-conversion/benchmark-baseline.json` unless `--rebaseline` is used intentionally.
- No non-build `.cs` file may reappear under the converted Entities, API, or Tests project directories.

Soft failures:

- API or Tests error counts decreasing still require inspection for diagnostic class churn; a lower count can hide a worse replacement diagnostic.
- Project idiom score drops of more than 2 points, or regressions in key migration-cleanup counts, should be treated as owner-review failures once an idiom baseline gate is set.
- Warning/info budgets are tracked but not hard-gated until the owner sets explicit thresholds.

## Artifact schema

The COTM harness writes `summary.json` using `schemaVersion: 1` under:

```text
<COTM root>/docs/nsharp-conversion/runs/<run-id>/summary.json
```

It also copies the latest run to:

```text
<COTM root>/docs/nsharp-conversion/latest-summary.json
```

and stores the comparison baseline at:

```text
<COTM root>/docs/nsharp-conversion/benchmark-baseline.json
```

The schema is documented in the COTM repo at `docs/nsharp-conversion/README.md` under “Standing COTM N# Benchmark Harness”. The summary includes repo SHAs/dirty state, CLI version/env artifacts, project `.nl` and non-build `.cs` counts, command argv/exit/duration, diagnostic counts by severity/code, optional idiom report fields, artifact-relative stdout/stderr/metadata paths, totals, and `regression.status` with hard/soft failure arrays.
