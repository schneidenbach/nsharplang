# N# Task Files

Last audited: 2026-05-25

Each numbered file in this directory is a standalone task. Point an agent at one file and it should have enough context to start, inspect the repository, implement the work, verify it, and report what changed. Do not reintroduce a consolidated task-state file.

## P0: Semantic Correctness

- [001-type-reference-source-spans.md](001-type-reference-source-spans.md)
- [002-overload-resolution-edge-cases.md](002-overload-resolution-edge-cases.md)
- [003-generic-type-inference.md](003-generic-type-inference.md)
- [004-lambda-contextual-typing.md](004-lambda-contextual-typing.md)
- [005-linq-return-types.md](005-linq-return-types.md)
- [006-semantic-reference-parity.md](006-semantic-reference-parity.md)
- [007-semanticmodel-scope-lookup.md](007-semanticmodel-scope-lookup.md)
- [008-skipped-unit-tests-burn-down.md](008-skipped-unit-tests-burn-down.md)

## P1: Parser, Diagnostics, IDE, Nullability

- [009-parser-recovery-hardening.md](009-parser-recovery-hardening.md)
- [010-diagnostic-quality-regression-bar.md](010-diagnostic-quality-regression-bar.md)
- [011-signature-help-compiler-semantics.md](011-signature-help-compiler-semantics.md)
- [012-auto-import-completion-polish.md](012-auto-import-completion-polish.md)
- [013-workspace-diagnostics-hardening.md](013-workspace-diagnostics-hardening.md)
- [014-interpolation-syntax-highlighting.md](014-interpolation-syntax-highlighting.md)
- [015-vscode-debug-task-evidence.md](015-vscode-debug-task-evidence.md)
- [016-null-state-flow-facts.md](016-null-state-flow-facts.md)
- [017-nullable-flow-narrowing.md](017-nullable-flow-narrowing.md)
- [018-possible-null-diagnostics.md](018-possible-null-diagnostics.md)
- [019-must-explicit-unwrap.md](019-must-explicit-unwrap.md)
- [020-nullable-value-idioms.md](020-nullable-value-idioms.md)
- [021-nullable-match-exhaustiveness.md](021-nullable-match-exhaustiveness.md)
- [022-csharp-nullable-metadata.md](022-csharp-nullable-metadata.md)
- [023-nullability-query-fixes-lsp.md](023-nullability-query-fixes-lsp.md)

## P2: CLI, Ecosystem, Docs

- [024-setup-nsharp-github-action.md](024-setup-nsharp-github-action.md)
- [025-formatter-audit-ci-gate.md](025-formatter-audit-ci-gate.md)
- [026-nlc-fix-catalog-growth.md](026-nlc-fix-catalog-growth.md)
- [027-install-release-toolset-ergonomics.md](027-install-release-toolset-ergonomics.md)
- [028-benchmark-corpus-nlc-bench.md](028-benchmark-corpus-nlc-bench.md)
- [029-public-website-playground-scope.md](029-public-website-playground-scope.md)
- [030-nuget-library-publishing.md](030-nuget-library-publishing.md)
- [031-native-test-coverage.md](031-native-test-coverage.md)
- [032-cross-compilation-publish-scope.md](032-cross-compilation-publish-scope.md)
- [033-build-timing-evidence.md](033-build-timing-evidence.md)
- [034-dependency-tree-docs-parity.md](034-dependency-tree-docs-parity.md)
- [035-stale-launch-claims.md](035-stale-launch-claims.md)
- [036-cli-json-contracts-authoritative.md](036-cli-json-contracts-authoritative.md)
