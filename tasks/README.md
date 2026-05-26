# N# Vertical Task Files

Last audited: 2026-05-25

Each task file is a thread-sized vertical slice framed around a shippable user or tool workflow. Tasks that touch the same functionality are combined so one thread can carry the feature end to end. Tasks stay split when the combined slice would cross too many risky systems or bury a distinct product decision.

## P0: Trustworthy Semantics And Runtime Basics

- [001-semantic-authoring-and-navigation.md](001-semantic-authoring-and-navigation.md)

## P1: IDE Product Workflows

- [003-auto-import-writing-flow.md](003-auto-import-writing-flow.md)
- [004-workspace-diagnostics-lifecycle.md](004-workspace-diagnostics-lifecycle.md)
- [005-vscode-editing-and-workflow-evidence.md](005-vscode-editing-and-workflow-evidence.md)

## P1: Nullability Workflows

- [007-nullable-unwrap-and-match-idioms.md](007-nullable-unwrap-and-match-idioms.md)
- [008-csharp-nullability-interop.md](008-csharp-nullability-interop.md)

## P2: CLI, Release, Evidence, Docs

- [009-install-release-and-ci-setup.md](009-install-release-and-ci-setup.md)
- [010-library-publishing-workflow.md](010-library-publishing-workflow.md)
- [011-cli-command-truth-coverage-and-publish.md](011-cli-command-truth-coverage-and-publish.md)
- [013-benchmarks-and-launch-evidence.md](013-benchmarks-and-launch-evidence.md)
- [014-public-playground.md](014-public-playground.md)
- [015-dependency-commands-project-yml-parity.md](015-dependency-commands-project-yml-parity.md)
