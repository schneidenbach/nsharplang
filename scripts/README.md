# N# Scripts

Keep top-level scripts scarce. A file belongs here only when it is a stable
human or automation entrypoint; shared implementation belongs in `scripts/lib/`.
Contributor source installs start at the repo root with `./install-local.sh`.
Test and smoke-test implementations live in `tests/scripts/`; this directory
keeps compatibility wrappers for stable commands that automation already uses.

## Current Entrypoints

- `install.sh` - public one-line installer; must stay self-contained.
- `setup-local.sh` - compatibility entrypoint used by `./install-local.sh`.
- `setup-consumer.sh` - GitHub Packages consumer setup; must stay self-contained.
- `pack-nuget.sh` - build release artifacts into `artifacts/`.
- `publish-packages.sh` - publish the canonical package set to NuGet or GitHub Packages.
- `publish-toolset.sh` - publish the package-manager-ready `nsharp-toolset` layout.
- `build-vscode-extension.sh`, `reload-vscode-extension.sh`,
  editor build/reload loops.

## Compatibility Test Wrappers

These stable command names delegate to implementations in `tests/scripts/`:

- `test-all.sh` - full product verification gate.
- `smoke-turnkey-install.sh` - local-feed smoke for the public installer.
- `test-vscode-headless.sh`, `test-vscode-integration.sh` - editor test loops.
- `replay-template-quickstarts.py` - verifies template README quickstarts.

## Shared Libraries

- `common.sh` owns repository paths, command logging, dry-run execution, version
  readers, command checks, and small portability helpers.
- `packages.sh` owns the canonical NSharpLang package list and artifact path
  calculation.
- `toolset.sh` owns launcher generation, toolset publish/install, templates, and
  shared NuGet config helpers.
- `vscode-extension.sh` owns VS Code extension dependency, build, package, and
  reload helpers.

Prefer extending one of these files over adding another top-level script.
