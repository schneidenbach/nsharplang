# Task 015: Native Test Coverage

Priority: P2.

Implement first-class coverage for `nlc test` instead of only failing unsupported coverage flags honestly. This is separate from command-truth work because it needs compiler/runtime instrumentation, report schemas, and docs that deserve a dedicated slice.

## User Outcome

A developer can run `nlc test --coverage` and get accurate coverage data for N# source files, with stable text and JSON output that can be used by humans, CI, and agents.

## Scope

- Design native coverage collection for IL-backed `.tests.nl` execution.
- Decide whether instrumentation happens in the IL emitter, a test-runner probe layer, or a documented bridge to Coverlet-compatible artifacts.
- Define schemaVersioned JSON output for coverage summary and per-file/per-line details.
- Support text output that reports useful totals and report file locations.
- Decide the initial report formats (`json`, `cobertura`, `opencover`, `lcov`) and document unsupported formats.
- Ensure generated stubs and non-source artifacts do not pollute N# source coverage.
- Update docs, website docs, and help text once coverage is real.

## Likely Files

- `src/NSharpLang.Cli/Program.Testing.cs`
- `src/NSharpLang.Compiler`
- `src/NSharpLang.Sdk`
- `tests/CompilationBackendTests.cs`
- `tests/CliCommandTests.cs`
- `docs/guide/cli-reference.md`
- `website/docs/cli-reference.md`
- `memory/components/cli-toolchain.md`

## Acceptance

- `nlc test --coverage` exits 0 when tests pass and writes accurate coverage summary data.
- `nlc test --coverage --json` emits a versioned, documented JSON schema.
- Coverage maps back to `.nl` files and excludes generated `.g.cs`/stub code.
- Failed tests still report test failures clearly and do not hide coverage collection errors.
- Unsupported report formats fail with clear guidance.
- Docs and CLI help no longer describe coverage as unavailable.

## Verification

- Add focused unit/scenario tests for passing, failing, filtered, and no-test coverage runs.
- Validate report files against their expected schema/format.
- Run `./scripts/test-all.sh` before committing.
