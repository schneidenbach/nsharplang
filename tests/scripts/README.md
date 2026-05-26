# N# Test Scripts

This directory owns executable test and smoke-test implementations. Keep
product install, publish, and shared helper scripts in `scripts/`; put release
gates, editor test harnesses, and documentation replay tests here.

Stable compatibility wrappers remain in `scripts/` because local docs,
automation, and agent instructions already call those paths.

## Entrypoints

- `test-all.sh` - isolated, validated full product verification gate. Stable
  command: `./scripts/test-all.sh`. It runs the core gate from a temporary
  copy with isolated HOME, temp, NuGet, and npm state; successful runs write a
  content-addressed cache record so unchanged follow-up runs can validate and
  return quickly. Use `--no-cache`, `--rebuild-cache`, or `--clean` to force a
  fresh isolated run.
- `test-all-core.sh` - implementation of the full product gate. Call through
  `./scripts/test-all.sh` so isolation and cache validation stay consistent.
- `test-vscode-integration.sh` - VS Code extension integration test harness.
- `test-vscode-headless.sh` - repeatable headless VS Code smoke test.
- `smoke-turnkey-install.sh` - isolated smoke for the public installer and
  local toolset archive.
- `replay-template-quickstarts.py` - replays template README quickstart blocks
  from a clean temporary workspace.
- `test-compile.sh` - minimal direct SDK compilation repro helper.
