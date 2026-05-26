# N# Vertical Task Files

Last audited: 2026-05-25

Each task file is a thread-sized vertical slice framed around a shippable user or tool workflow. Tasks that touch the same functionality are combined so one thread can carry the feature end to end. Tasks stay split when the combined slice would cross too many risky systems or bury a distinct product decision.

## P0: Trustworthy Semantics And Runtime Basics

- [001-semantic-authoring-and-navigation.md](001-semantic-authoring-and-navigation.md)

## P1: IDE Product Workflows

- [004-workspace-diagnostics-lifecycle.md](004-workspace-diagnostics-lifecycle.md)
- [005-vscode-editing-and-workflow-evidence.md](005-vscode-editing-and-workflow-evidence.md)
- [015-query-and-package-completion-parity.md](015-query-and-package-completion-parity.md)

## P1: Nullability Workflows

- [015-nullable-ide-and-must-message-polish.md](015-nullable-ide-and-must-message-polish.md)
- [015-csharp-flow-attribute-narrowing.md](015-csharp-flow-attribute-narrowing.md)
- [016-csharp-generic-nullability-substitution.md](016-csharp-generic-nullability-substitution.md)

## P2: CLI, Release, Evidence, Docs

- [009-install-release-and-ci-setup.md](009-install-release-and-ci-setup.md)
- [010-library-publishing-workflow.md](010-library-publishing-workflow.md)
- [013-benchmarks-and-launch-evidence.md](013-benchmarks-and-launch-evidence.md)
- [014-public-playground.md](014-public-playground.md)
- [015-build-and-test-warning-hygiene.md](015-build-and-test-warning-hygiene.md)
- [015-dependency-commands-project-yml-parity.md](015-dependency-commands-project-yml-parity.md)
- [015-native-test-coverage.md](015-native-test-coverage.md)
- [016-target-runtime-publish-and-apphost.md](016-target-runtime-publish-and-apphost.md)
