# N# Test Scripts

This directory owns executable test and smoke-test implementations. Keep
product install, publish, and shared helper scripts in `scripts/`; put release
gates, editor test harnesses, and documentation replay tests here.

Stable compatibility wrappers remain in `scripts/` because local docs,
automation, and agent instructions already call those paths.

## Entrypoints

- `test-all.sh` - isolated, validated full product verification gate. Stable
  command: `./scripts/test-all.sh`. It runs the core gate from a temporary
  copy with isolated HOME, temp, NuGet, and npm state (each run restores into
  its own packages folder, cloned from an immutable shared store of nuget.org
  packages; the seed is always the copied tree's `bootstrap/`, so concurrent
  gates at different commits never touch each other); successful runs write a
  content-addressed cache record so unchanged follow-up runs can validate and
  return quickly. Use `--no-cache`, `--rebuild-cache`, or `--clean` to force a
  fresh isolated run. Use `./scripts/test-all.sh --commit` before committing;
  cached results are only for development feedback.
- `test-all-core.sh` - implementation of the full product gate. Call through
  `./scripts/test-all.sh` so isolation and cache validation stay consistent.
  It records coarse per-stage timings and passes exact emitted assemblies to
  IL verification, keeping copied runtime dependencies as references rather than targets.
- `test-vscode-integration.sh` - VS Code extension integration test harness.
- `test-vscode-headless.sh` - repeatable headless VS Code smoke test.
- `smoke-turnkey-install.sh` - isolated smoke for the public installer and
  local toolset archive.
- `replay-template-quickstarts.py` - replays template README quickstart blocks
  from a clean temporary workspace.
- `test-compile.sh` - minimal direct SDK compilation repro helper.
## Compiler performance gates

The compile-time and agent-loop gates always enforce exact `--stats` structural counters. They compare
timing only when `git diff base..head` changes compiler product inputs: `.nl`, `.cs`, or `project.yml`
under `src/NSharpLang.Compiler.*`, `src/NSharpLang.Compiler/`, `src/NSharpLang.Cli/`,
`src/NSharpLang.TestHost/`, `src/NSharpLang.Runtime/`, or `src/NSharpLang.Build.Tasks/`, plus SDK
`.props`/`.targets` under `src/NSharpLang.Sdk/Sdk/`. `.tests.nl`, benchmark harness files, docs and
`.csproj` files do not trigger a timing comparison. A no-product-change run reports
`timing: not compared (no compiler change)` and checks the head counters and Core phase contract.

Changed-product timing discards one warm-up pair, alternates base/head order, and takes at least nine
measured pairs per row. Rows collect at least 350 ms of paired command wall time and stop at 17 pairs.
The gate fails only when the exact two-sided sign-test 95% lower confidence bound for the median
per-pair ratio exceeds 1.20x and the median slowdown is at least 30 ms per command. Short agent-loop
rows use CPU only when the timed child reports at least 30 ms median CPU and its paired-ratio MAD is
lower than wall's. The base is `git merge-base HEAD origin/systems-language` on a branch, otherwise
`HEAD~1`; its build is cached by commit. Absolute medians, confidence bounds, selected metric, both
wall and CPU medians, machine, load and commit remain trend artifacts. The agent-loop report gives
the zero-noise minimum detectable slowdown by size and mode; load never skips a timing verdict.

To compare an explicit base CLI locally, build the benchmark project and run:

```bash
dotnet src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll build --project tests/native/compile-time-bench
dotnet tests/native/compile-time-bench/bin/Debug/net10.0/tests/NSharpLang.CompileTimeBench.dll \
  --agent-loop --base-cli /path/to/base/src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll
```

Add `--scenario "no-op build"` to isolate that exact cold and daemon-warm row for a paired timing
probe; the product gate always uses the complete small/medium scenario matrix.

See `memory/testing.md` sections 8 and 8a for the counter rows, base selection, artifacts and ratchet workflow.
