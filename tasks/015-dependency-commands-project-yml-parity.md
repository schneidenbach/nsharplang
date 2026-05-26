# Task 015: Dependency Commands Project.yml Parity

Priority: P2.

Make dependency-facing CLI commands fully respect the csproj-free `project.yml` product model. `nlc tree` now handles direct `project.yml` dependencies, but the broader dependency command set still has legacy `.csproj` assumptions and incomplete transitive graph behavior.

## User Outcome

Users can add, inspect, audit, tidy, remove, and update dependencies from the N# CLI without knowing whether a project has a minimal MSBuild compatibility file. JSON automation gets consistent envelopes and clear capability metadata for every dependency command.

## Scope

- Audit `nlc add`, `nlc remove`, `nlc update`, `nlc tidy`, `nlc tree`, `nlc audit`, and related help/docs/tests.
- Make `nlc audit --json` return structured error envelopes on missing project roots/configuration.
- Make `nlc audit` work for csproj-free `project.yml` projects or explicitly report the precise unsupported capability.
- Decide whether `nlc tree` should generate a temporary MSBuild projection to resolve transitive NuGet packages for csproj-free projects, and implement or document the chosen behavior.
- Ensure dependency command JSON output uses versioned envelopes, normalized paths, stable root keys, and migration notes for breaking changes.
- Keep project.yml as the source of truth; do not require user-authored `.csproj` files.

## Likely Files

- `src/NSharpLang.Cli/Commands/AuditCommand.cs`
- `src/NSharpLang.Cli/Commands/TreeCommand.cs`
- `src/NSharpLang.Cli/Commands/AddCommand.cs`
- `src/NSharpLang.Cli/Commands/RemoveCommand.cs`
- `src/NSharpLang.Cli/Commands/UpdateCommand.cs`
- `src/NSharpLang.Cli/Commands/TidyCommand.cs`
- `src/NSharpLang.Compiler/ProjectFile.cs`
- `memory/components/cli-toolchain.md`
- `docs/guide/cli-reference.md`
- `website/docs/cli-reference.md`
- `tests/CliCommandTests.cs`
- `tests/CliParityAuditTests.cs`
- `tests/fixtures/json-contract-root-keys.golden.json`

## Acceptance

- Dependency commands that support JSON emit global `{ schemaVersion, command, ok, ... }` envelopes on both success and failure.
- `nlc audit` no longer fails with a misleading `.csproj` requirement for normal csproj-free projects.
- `nlc tree` documents and tests whether transitive NuGet dependencies are available without an MSBuild project file.
- Help text, memory docs, website docs, and guide docs agree with actual command behavior.
- New or changed JSON fields are covered by contract tests and versioned when breaking.

## Verification

- Run focused dependency command tests.
- Run JSON contract tests.
- Run docs/website checks if docs change.
- Run `./scripts/test-all.sh` before committing if code changes.
