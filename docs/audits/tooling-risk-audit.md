# NSharpLang Developer Tooling Risk Audit

Date: 2026-05-07
Scope: CLI, query/daemon contract surfaces, LSP/VS Code UX, templates/examples, shell completion, docs, and full-suite health.

Existing worktree note: this audit observed pre-existing modifications in `src/NSharpLang.LanguageServer/Handlers/CodeLensHandler.cs` and `tests/LanguageServerTests.cs` and did not edit them.

## P0 Findings

### P0-1 Full test suite is red in the current worktree

Evidence:
- `./scripts/test-all.sh` exited 1 with `FAILURES: 1`.
- Unit-test section reported `Failed: 6, Passed: 2212, Skipped: 3, Total: 2221`.
- Targeted rerun confirmed:
  - `DiagnosticClusteringTests.CheckJson_IncludesAiConsumableDiagnosticClustersWithRootLocationExamplesAndActions`: missing `diagnosticClusters`.
  - `DiagnosticClusteringTests.DiagnosticsText_StartsWithClusterSummaryBeforeIndividualDiagnostics`: missing cluster summary text.
  - `CliCommandTests.CheckCommand_DefaultsToJsonEnvelope`: expected `diagnosticClusters`, actual root keys omit it.
  - `CliCommandTests.QueryCommand_EmitsStableJsonEnvelope(...diagnostics...)`: expected `diagnosticClusters`, actual root keys omit it.
  - `CodeIntelligenceOutputTests.JsonContracts_MatchGoldenRootKeys`: golden root keys expect `diagnosticClusters`.
  - `CliParityAuditTests.CompletionCommand_Bash_IncludesTopLevelCommands`: completion output does not contain `convert`.
- Golden contract evidence: `tests/fixtures/json-contract-root-keys.golden.json:27-35` requires `diagnosticClusters` for diagnostics.
- Test evidence: `tests/DiagnosticClusteringTests.cs:22-58` asserts both JSON and text cluster output.

Affected files:
- `src/NSharpLang.Compiler/CodeIntelligence/OutputFormatter.cs`
- `src/NSharpLang.Cli/Commands/CheckCommand.cs`
- `src/NSharpLang.Cli/Commands/QueryCommand.cs`
- `src/NSharpLang.Cli/Commands/CompletionCommand.cs`
- `tests/fixtures/json-contract-root-keys.golden.json`

User impact:
- CI/release gate is blocked.
- More importantly, the structured JSON schema appears to have regressed by dropping an AI-consumable field that tests treat as stable.
- Shell completion drift is now caught by tests but still shipped by the command output.

Recommended fix:
- Restore `diagnosticClusters` in `nlc check` and `nlc query diagnostics` JSON output and restore the cluster summary in text diagnostics, unless this is an intentional schema break. If intentional, introduce a new schema version and update tests/docs together.
- Add `convert` and any other registered top-level commands to completion generation from a single source of truth.

Test coverage needed:
- Keep the existing golden-root-key tests.
- Add an integration test that runs `nlc check` and `nlc query diagnostics` through the actual CLI binary and verifies `diagnosticClusters` on both clean and erroring projects.
- Add one parity test that compares `nlc help` command names to generated bash/zsh/fish completions.

## P1 Findings

### P1-1 VS Code build/debug tasks conflict with the csproj-free template workflow

Evidence:
- Templates intentionally create no `.csproj`; `scripts/test-all.sh:248-255` enforces `No .csproj in template output (csproj-free)`.
- Direct command verification: `dotnet build templates/nsharp-console --disable-build-servers -v q` fails with `MSB1003: Specify a project or solution file`.
- Direct command verification: `dotnet test templates/nsharp-console --disable-build-servers -v q` fails with the same `MSB1003`.
- VS Code zero-config debug emits `preLaunchTask: 'build'` and expects `bin/Debug/<tfm>/<project>.dll` at `editors/vscode/src/extension.ts:163-172`.
- The registered build task runs `dotnet build` directly at `editors/vscode/src/extension.ts:187-194`.
- Generated tasks also use `dotnet build`, `dotnet run`, and `dotnet test` at `editors/vscode/src/extension.ts:338-366`.
- `nlc restore` help states direct `dotnet build` needs generated config and that `nlc build` runs restore automatically: `src/NSharpLang.Cli/Commands/RestoreCommand.cs:143-149`.
- `nlc new` is internally inconsistent: help says "No .csproj file is created" at `src/NSharpLang.Cli/Program.cs:552-558`, but implementation creates `<name>.csproj` at `src/NSharpLang.Cli/Program.cs:599-608`.

Affected files:
- `editors/vscode/src/extension.ts`
- `templates/nsharp-console/**`
- `templates/nsharp-webapi/**`
- `src/NSharpLang.Cli/Program.cs`
- `src/NSharpLang.Cli/Commands/RestoreCommand.cs`

User impact:
- A user following the `dotnet new nsharp-console` + VS Code path can press F5 and fail before the app starts.
- The product has two project-creation stories: `dotnet new` is csproj-free; `nlc new` creates a `.csproj` while claiming it does not.
- This undermines the "minimal project file / project.yml owns config" story and makes IDE behavior depend on how the project was created.

Recommended fix:
- Make VS Code tasks call `nlc build`, `nlc run`, and `nlc test` by default, respecting `nsharp.cli.path`.
- Standardize `nlc new` versus `dotnet new`: either both are csproj-free and use `nlc build`, or both create a one-line SDK `.csproj`. Update docs/tests accordingly.
- If direct `dotnet build` is still a supported workflow, ensure templates include the minimal one-line `.csproj` or provide a reliable automatic restore/project generation path before VS Code invokes dotnet.

Test coverage needed:
- VS Code integration test on a fresh `dotnet new nsharp-console` workspace that presses/builds the generated build task and zero-config F5 path.
- CLI/template parity test that asserts `nlc new` and `dotnet new nsharp-console` create the same project-shape contract.

### P1-2 CodeLens reference counts are clickable no-ops and are not semantic

Evidence:
- Non-test CodeLens entries set command name `nsharp.showReferences`: `src/NSharpLang.LanguageServer/Handlers/CodeLensHandler.cs:109-117`.
- The VS Code extension registers `nsharp.generateDebugConfig`, `nsharp.runTest`, and `nsharp.debugTest`, but no `nsharp.showReferences`: `editors/vscode/src/extension.ts:101-105`, `editors/vscode/src/testController.ts:82-96`.
- Reference counts call `_documentManager.FindAllReferences(doc.Uri, name)` across tracked documents: `src/NSharpLang.LanguageServer/Handlers/CodeLensHandler.cs:139-159`.
- `FindAllReferences` is explicitly text-based and whole-word-only: `src/NSharpLang.LanguageServer/Services/DocumentManager.cs:436-499`.

Affected files:
- `src/NSharpLang.LanguageServer/Handlers/CodeLensHandler.cs`
- `src/NSharpLang.LanguageServer/Services/DocumentManager.cs`
- `editors/vscode/src/extension.ts`
- `editors/vscode/src/testController.ts`

User impact:
- Clicking a reference-count CodeLens will not reliably do anything.
- Counts can include same-name unrelated symbols and exclude unopened files, so the UI can confidently display wrong reference counts.

Recommended fix:
- Either remove the command from non-actionable CodeLens entries or register `nsharp.showReferences` to call VS Code's references UI at the declaration position.
- Replace reference count computation with the same semantic project reference path used by `nlc query refs`/LSP references.
- If a semantic snapshot is unavailable, show no count or an explicitly degraded label rather than a precise-looking count.

Test coverage needed:
- LSP/VS Code test that verifies `nsharp.showReferences` is registered and opens references for a CodeLens.
- Semantic count fixture with two declarations sharing a simple name in different scopes/files.

### P1-3 Unsaved-buffer semantic tooling falls back to simple-name text behavior

Evidence:
- Definition handler falls back to `FindSymbolLocations(word)` and `PickBestLocation` when synchronized/disk project snapshots miss: `src/NSharpLang.LanguageServer/Handlers/DefinitionHandler.cs:43-86`.
- References handler falls back to text-based single-document search when no synchronized snapshot is available: `src/NSharpLang.LanguageServer/Handlers/ReferencesHandler.cs:67-100`.
- Rename handler falls back to same-document text edits when project references are unavailable: `src/NSharpLang.LanguageServer/Handlers/RenameHandler.cs:65-113`.
- `DocumentManager.FindAllReferences` documents the non-semantic fallback and says BindingMap is not yet used for LSP fallback: `src/NSharpLang.LanguageServer/Services/DocumentManager.cs:436-447`.

Affected files:
- `src/NSharpLang.LanguageServer/Handlers/DefinitionHandler.cs`
- `src/NSharpLang.LanguageServer/Handlers/ReferencesHandler.cs`
- `src/NSharpLang.LanguageServer/Handlers/RenameHandler.cs`
- `src/NSharpLang.LanguageServer/Services/DocumentManager.cs`

User impact:
- A normal editing state, where open buffers differ from disk, can degrade semantic operations to simple-name matching.
- Rename is the highest-risk case because an apparently semantic F2 operation can edit unrelated identifiers in the same document.

Recommended fix:
- Build in-memory project snapshots from open document text plus disk for unopened files, then use the same semantic resolver for definition/references/rename.
- Until that exists, disable rename/references when the project is unsynchronized rather than using text fallback.
- If definition keeps a fallback, mark it as best-effort in logs only and never use it for refactoring edits.

Test coverage needed:
- LSP tests with unsaved edits and duplicate names in nested scopes.
- Rename tests that assert unrelated same-name symbols are not edited when project snapshots are unavailable.

## P2 Findings

### P2-1 Shell completion and docs drift from the actual command tree

Evidence:
- `Program.Execute` registers `convert` and `idiom`: `src/NSharpLang.Cli/Program.cs:59-61`.
- `CompletionCommand.TopLevelCommands` omits both: `src/NSharpLang.Cli/Commands/CompletionCommand.cs:8-37`.
- `QueryCommand` implements `hover`, `call-graph`, and `implementors`: `src/NSharpLang.Cli/Commands/QueryCommand.cs:31-45`.
- Generated query completions omit those subcommands: `src/NSharpLang.Cli/Commands/CompletionCommand.cs:87-92`, `src/NSharpLang.Cli/Commands/CompletionCommand.cs:130-133`.
- Observed `nlc completion zsh` output omitted `convert`, `idiom`, `hover`, `call-graph`, and `implementors`.
- `docs/guide/cli-reference.md:34-48` also omits `hover`, `call-graph`, and `implementors` from the query table, despite `nlc query help` listing them.

Affected files:
- `src/NSharpLang.Cli/Commands/CompletionCommand.cs`
- `src/NSharpLang.Cli/Program.cs`
- `src/NSharpLang.Cli/Commands/QueryCommand.cs`
- `docs/guide/cli-reference.md`

User impact:
- Users and agents discover an incomplete command surface from shell completion and the main guide.
- This is especially harmful for the LLM-first CLI story because shell completion is one of the primary machine-navigation affordances.

Recommended fix:
- Generate completions from a shared command registry or a tested data model, not hand-maintained string lists.
- Update `docs/guide/cli-reference.md` from `nlc help` / `nlc query help` output or add a parity test that fails when docs omit implemented public commands.

Test coverage needed:
- Compare top-level help, completion scripts, and docs command tables in one parity audit test.
- Include query subcommands in the same parity check.

### P2-2 VS Code Test Explorer debug mode reports skipped instead of debug results

Evidence:
- `runDebug` sends `nlc test` to a terminal: `editors/vscode/src/testRunner.ts:129-150`.
- It immediately marks every requested test as skipped because it cannot capture results: `editors/vscode/src/testRunner.ts:152-155`.
- Comment says "run nlc test with dotnet test under the debugger" and "First build, then launch with coreclr attach", but implementation does neither: `editors/vscode/src/testRunner.ts:136-145`.

Affected files:
- `editors/vscode/src/testRunner.ts`

User impact:
- Debug Test CodeLens/Test Explorer actions appear supported, but they do not actually start a VS Code debug session or report pass/fail.
- Users can misread skipped status as test selection/filtering rather than an unimplemented debug workflow.

Recommended fix:
- Either implement real CoreCLR debug launch/attach for generated test assemblies or hide/disable Debug profile and Debug CodeLens until it is real.
- Capture JSON test output for debug runs where possible and report actual outcomes.

Test coverage needed:
- VS Code integration test for Debug Test action that verifies a debug session starts or that the command is absent/disabled.

### P2-3 Documentation overstates tooling maturity and contains stale counts

Evidence:
- `memory/README.md:3-4` says "Feature-complete" and `944+ total`.
- `memory/testing.md:5` says `944+ total`.
- `memory/components/cli-toolchain.md:3-4` says "Production-ready" and `1558+ tests passing`.
- `README.md:130` and `README.md:192` still reference `876` tests.
- Current observed unit count is `2221` total with 6 failures in `./scripts/test-all.sh`.
- VS Code docs claim "Zero-config debugging" and automatic build/test tasks at `editors/vscode/README.md:35-49`, but the extension uses direct `dotnet` tasks that fail for csproj-free templates.
- `editors/vscode/INTELLISENSE.md:91-95` claims `<100ms` completion performance with no observed performance gate in `./scripts/test-all.sh`.

Affected files:
- `README.md`
- `memory/README.md`
- `memory/testing.md`
- `memory/components/cli-toolchain.md`
- `docs/guide/cli-reference.md`
- `editors/vscode/README.md`
- `editors/vscode/INTELLISENSE.md`

User impact:
- Docs currently communicate confidence levels that are contradicted by the current suite and IDE workflow.
- Agents using memory docs as source of truth can make bad decisions about schema stability, command availability, and IDE readiness.

Recommended fix:
- Replace static test counts with either generated badges/artifacts or a "last verified by" section tied to `./scripts/test-all.sh`.
- Downgrade "production-ready/full/zero-config" claims where the audit findings show known gaps.
- Add docs parity checks for public commands and schema examples.

Test coverage needed:
- A docs lint/parity command that checks command tables against `nlc help`, `nlc query help`, and completion output.
- Optional generated test-summary artifact from CI instead of hand-maintained counts.

## P3 Findings

### P3-1 Full-suite script encodes known example failures without issue-level traceability

Evidence:
- `scripts/test-all.sh:383-389` lists known single-file example failures for `PrintNameofTypeof.nl`, `ConstructorChaining.nl`, and `12-multi-file-projects/imports/`.
- The run still reported known parent-directory `nlc check` warnings: `12-multi-file-projects (known: 11 errors)` and `17-issue-tracker (known: 13 errors)`.

Affected files:
- `scripts/test-all.sh`
- `examples/02-variables-and-types/PrintNameofTypeof.nl`
- `examples/06-classes-and-records/ConstructorChaining.nl`
- `examples/12-multi-file-projects/**`
- `examples/17-issue-tracker/**`

User impact:
- Known failures can become permanent because the script classifies them as acceptable without linking to owner, issue, or expiry criteria.
- The Language Server false-error guarantee in Step 10 is weakened by known parent-directory failures.

Recommended fix:
- Link each known failure to a tracked issue or TODO file with owner and expected fix condition.
- Prefer quarantined tests with explicit assertions over regex allowlists in a release gate.

Test coverage needed:
- Add a small "known failures registry" check that requires issue IDs and fails on stale entries past an expiry date.

## Commands Run

- `git status --short` — observed pre-existing modified `CodeLensHandler.cs` and `LanguageServerTests.cs`.
- `rg --files ...`, `rg -n ...`, `sed`, `nl -ba`, `find` — repo/source/docs inspection.
- `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- help` — confirmed top-level help includes `convert` and `idiom`.
- `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query help` — confirmed query help includes `hover`, `call-graph`, `implementors`.
- `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- completion zsh` — confirmed completion drift.
- `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- convert --help` — confirmed `convert` is currently registered.
- `dotnet build templates/nsharp-console --disable-build-servers -v q` — failed with `MSB1003` because no project file exists.
- `dotnet test templates/nsharp-console --disable-build-servers -v q` — failed with `MSB1003` because no project file exists.
- `./scripts/test-all.sh` — failed in unit-test section; later VS Code smoke, package, template, example, and example-check sections passed.
- `dotnet test --disable-build-servers tests/Tests.csproj -v n --nologo --filter ...` — first attempted with `--no-restore` after `test-all` cleared packages and hit `NETSDK1064`; rerun with restore captured the 6 failing unit tests above.

## Non-Findings / Positive Signals

- `convert` is not removed in this worktree; it is registered, has help text, and is covered by existing tests. The stale surface is completion/docs parity, not absence of the command.
- `./scripts/test-all.sh` successfully built template-generated projects via `nlc build`.
- VS Code smoke tests passed for extension activation, diagnostics, hover, and completion in this run.
