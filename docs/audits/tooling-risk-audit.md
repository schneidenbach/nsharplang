# NSharpLang Developer Tooling Risk Audit

Date: 2026-05-07
Last refreshed against `origin/main`: 2026-05-09
Scope: CLI, query/daemon contract surfaces, LSP/VS Code UX, templates/examples, shell completion, docs, and full-suite health.

## P0 Findings

No current P0 findings are carried by this audit after the 2026-05-09 refresh. A targeted current-source rerun of the previously cited diagnostic-clustering and completion parity tests passed 21/21, so the prior red-suite/`diagnosticClusters` claim is intentionally removed rather than preserved as current evidence.

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

Status: Mitigated in the LSP implementation. `DocumentManager` now builds semantic project snapshots from open-buffer text plus disk files, and logs structured degraded states when that snapshot cannot be built. Keep the old evidence below as historical context until the full launch gate is green.

Evidence:
- Definition handler now asks for a semantic project snapshot where open buffers override disk files before considering disk/text fallbacks: `src/NSharpLang.LanguageServer/Handlers/DefinitionHandler.cs:53-73` and `src/NSharpLang.LanguageServer/Services/DocumentManager.cs`.
- References handler falls back to text-based single-document search when no synchronized snapshot is available: `src/NSharpLang.LanguageServer/Handlers/ReferencesHandler.cs:67-100`.
- Rename handler falls back to same-document text edits when project references are unavailable: `src/NSharpLang.LanguageServer/Handlers/RenameHandler.cs:65-113`.
- `DocumentManager` logs structured project-snapshot degradation with reason/project/file/message before falling back or returning no semantic result.

Affected files:
- `src/NSharpLang.LanguageServer/Handlers/DefinitionHandler.cs`
- `src/NSharpLang.LanguageServer/Handlers/ReferencesHandler.cs`
- `src/NSharpLang.LanguageServer/Handlers/RenameHandler.cs`
- `src/NSharpLang.LanguageServer/Services/DocumentManager.cs`

User impact:
- A normal editing state, where open buffers differ from disk, should now preserve semantic definition/references/rename over the in-memory project snapshot.
- Residual risk: truly degraded snapshots still fall through to legacy fallback paths for some handlers, so completion/review should retain explicit degraded logging evidence and duplicate-name regression tests.

Recommended fix:
- Build in-memory project snapshots from open document text plus disk for unopened files, then use the same semantic resolver for definition/references/rename.
- Until that exists, disable rename/references when the project is unsynchronized rather than using text fallback.
- If definition keeps a fallback, mark it as best-effort in logs only and never use it for refactoring edits.

Test coverage needed:
- LSP tests with unsaved edits and duplicate names in nested scopes. Covered for cross-file duplicate member definition/references/rename.
- Rename tests that assert unrelated same-name symbols are not edited when project snapshots are unavailable. Covered for unsaved duplicate-member rename; still worth extending to degraded/no-project synthetic URI paths.

## P2 Findings

### P2-1 Shell completion and docs drift from the actual query command tree

Status: Remediated in the current working tree by centralizing public command metadata in `CommandRegistry` and adding parity coverage. Keep this section as a regression guard until the launch branch is cut.

Evidence:
- Current `Program.Execute` registers `pack`, `export`, and `idiom`, with no `convert` command.
- `nlc --help`, `nlc query help`, and `nlc completion zsh` now expose the same top-level/query command surface, including `hover`, `call-graph`, and `implementors`, while still omitting `convert`.
- `docs/guide/cli-reference.md` and `website/docs/cli-reference.md` list the current query subcommands and the no-public-`nlc convert` migration contract.
- `CliCommandRegistry_StaysInSyncWithHelpCompletionsAndDocs` covers registry/help/completion/docs parity.

Affected files:
- `src/NSharpLang.Cli/Commands/CompletionCommand.cs`
- `src/NSharpLang.Cli/Commands/QueryCommand.cs`
- `docs/guide/cli-reference.md`

User impact:
- Users and agents discover an incomplete query command surface from shell completion and the main guide.
- This is especially harmful for the LLM-first CLI story because shell completion is one of the primary machine-navigation affordances.

Recommended fix:
- Keep query completions generated from the command registry.
- Keep `docs/guide/cli-reference.md` and `website/docs/cli-reference.md` covered by the parity test when command metadata changes.

Test coverage needed:
- Continue running the parity audit that compares `nlc query help`, query completion scripts, and docs query tables.

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
- Earlier evidence found stale hand-maintained counts and maturity claims across `README.md`, `memory/README.md`, `memory/testing.md`, `memory/components/cli-toolchain.md`, website docs, and VS Code docs. Public-facing copies have been softened, but counts still drift unless generated from a fresh `./scripts/test-all.sh` artifact.
- Treat any remaining static counts in memory/completed-task history as historical notes, not current launch evidence.
- VS Code public docs now hide F5/debugging as an unsupported N# workflow and describe `nlc`-backed tasks, but this still requires fresh extension/visual QA before a launch claim.
- `editors/vscode/INTELLISENSE.md` no longer quotes a `<100ms` latency number without a current performance gate.

Affected files:
- `README.md`
- `memory/README.md`
- `memory/testing.md`
- `memory/components/cli-toolchain.md`
- `docs/guide/cli-reference.md`
- `editors/vscode/README.md`
- `editors/vscode/INTELLISENSE.md`

User impact:
- Docs currently communicate confidence levels that are contradicted by stale count drift and the IDE workflow evidence above.
- Agents using memory docs as source of truth can make bad decisions about schema stability, command availability, and IDE readiness.

Recommended fix:
- Replace static test counts with either generated badges/artifacts or a "last verified by" section tied to `./scripts/test-all.sh`.
- Downgrade "production-ready/full/zero-config" claims where the audit findings show known gaps.
- Add docs parity checks for public commands and schema examples.

Test coverage needed:
- A docs lint/parity command that checks command tables against `nlc help`, `nlc query help`, and completion output.
- Optional generated test-summary artifact from CI instead of hand-maintained counts.

## P3 Findings

### P3-1 Full-suite script previously encoded known example failures without issue-level traceability

Status: Remediated in current working tree. The single-file example allowlist was removed, the two stale single-file examples now build under the IL backend, `examples/12-multi-file-projects/imports/` has a project manifest so it is tested as a multi-file project, and parent umbrella `nlc check` allowlists were removed in favor of checking only real project/single-file scopes.

Evidence:
- `scripts/test-all.sh` no longer defines `KNOWN_FAILURES` or `CHECK_KNOWN_FAILURES`.
- `PrintNameofTypeof.nl` and `ConstructorChaining.nl` build directly with `nlc build`.
- `examples/12-multi-file-projects/imports/project.yml` makes the imports sample a first-class project.

Residual policy:
- Future known failures must not be hidden behind regex allowlists. Fix them, or link them to a tracked issue with owner and expiry before allowing the gate to pass.

Test coverage needed:
- Keep `./scripts/test-all.sh` as the audit: example build/check failures now fail the suite instead of printing "known" warnings.

## Commands Run

- `rg --files ...`, `rg -n ...`, `sed`, `nl -ba`, `find` — repo/source/docs inspection.
- `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- help` — confirmed top-level help includes `pack`, `export`, and `idiom`, with no `convert`.
- `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query help` — confirmed query help includes `hover`, `call-graph`, `implementors`.
- `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- completion zsh` — confirmed top-level `export`/`idiom` and query subcommands `hover`/`call-graph`/`implementors` are present; `convert` remains absent.
- `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- convert --help` — confirmed `convert` is not currently registered (`Unknown command: convert`).
- `dotnet build templates/nsharp-console --disable-build-servers -v q` — failed with `MSB1003` because no project file exists.
- `dotnet test templates/nsharp-console --disable-build-servers -v q` — failed with `MSB1003` because no project file exists.
- `./scripts/test-all.sh` — original 2026-05-07 audit run failed in the unit-test section; this refreshed document no longer treats that stale run as current P0 evidence.
- `dotnet test --disable-build-servers tests/Tests.csproj -v q --nologo --filter ...` — 2026-05-09 current-source rerun of the previously cited diagnostic-clustering/completion tests passed 21/21.

## Non-Findings / Positive Signals

- `convert` is not a current top-level command; `export`, `idiom`, and the current query subcommands are registered, documented, and present in shell completion.
- `./scripts/test-all.sh` successfully built template-generated projects via `nlc build`.
- VS Code smoke tests passed for extension activation, diagnostics, hover, and completion in this run.
