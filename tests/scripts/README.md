# N# Test Scripts

This directory owns executable test and smoke-test implementations. Keep
product install, publish, and shared helper scripts in `scripts/`; put release
gates, editor test harnesses, and documentation replay tests here.

Stable compatibility wrappers remain in `scripts/` because local docs,
automation, and agent instructions already call those paths.

## Entrypoints

- `test-all.sh` - full product verification gate. Stable command:
  `./scripts/test-all.sh`.
- `test-vscode-integration.sh` - VS Code extension integration test harness.
- `test-vscode-headless.sh` - repeatable headless VS Code smoke test.
- `smoke-turnkey-install.sh` - isolated smoke for the public installer and
  local toolset archive.
- `replay-template-quickstarts.py` - replays template README quickstart blocks
  from a clean temporary workspace.
- `test-compile.sh` - minimal direct SDK compilation repro helper.
