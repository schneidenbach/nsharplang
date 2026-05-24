# N# Scripts

The top-level scripts in this directory are public entrypoints. Keep their names
stable because docs, CI, and contributor muscle memory call them directly.

Shared implementation belongs in `scripts/lib/`:

- `common.sh` owns repository paths, command logging, dry-run execution, version
  readers, command checks, and small portability helpers.
- `packages.sh` owns the canonical NSharpLang package list and artifact path
  calculation.
- `vscode-extension.sh` owns VS Code extension dependency, build, package, and
  reload helpers.

Standalone bootstrap scripts that are fetched directly, such as `install.sh` and
`setup-consumer.sh`, must remain self-contained and must not source `scripts/lib`.
