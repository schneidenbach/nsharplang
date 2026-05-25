# N# Scripts

Keep top-level scripts scarce. A file belongs here only when it is a stable
human or automation entrypoint; shared implementation belongs in `scripts/lib/`.

## Current Entrypoints

- `install.sh` - public one-line installer; must stay self-contained.
- `setup-local.sh` - contributor bootstrap and local toolset deployment.
- `setup-consumer.sh` - GitHub Packages consumer setup; must stay self-contained.
- `test-all.sh` - full product verification gate.
- `pack-nuget.sh` - build release artifacts into `artifacts/`.
- `publish-packages.sh` - publish the canonical package set to NuGet or GitHub Packages.
- `publish-toolset.sh` - publish the package-manager-ready `nsharp-toolset` layout.
- `smoke-turnkey-install.sh` - local-feed smoke for the public installer.
- `build-vscode-extension.sh`, `reload-vscode-extension.sh`,
  `test-vscode-headless.sh`, `test-vscode-integration.sh` - editor loops.
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
