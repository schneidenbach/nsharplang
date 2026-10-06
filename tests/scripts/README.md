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

The compile-time and agent-loop gates use exact `--stats` structural counters as their machine-independent
contract. They compare timing against a base compiler built in the same run, interleaved in three pairs,
and gate the median of per-pair head/base ratios at 1.20x. The base is `git merge-base HEAD
origin/systems-language` when the worktree is ahead of origin, otherwise `HEAD~1`; its build is cached
by commit. Absolute medians, machine, load and commit are trend artifacts only. Load never skips a verdict.

To compare an explicit base CLI locally, build the benchmark project and run:

```bash
dotnet src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll build --project tests/native/compile-time-bench
dotnet tests/native/compile-time-bench/bin/Debug/net10.0/tests/NSharpLang.CompileTimeBench.dll \
  --agent-loop --base-cli /path/to/base/src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll
```

See `memory/testing.md` sections 8 and 8a for the counter rows, base selection, artifacts and ratchet workflow.
