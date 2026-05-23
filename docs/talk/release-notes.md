# N# Launch Release Notes

Status: public-talk release notes draft from the current evidence bundle.

These notes are deliberately source-grounded. Each claim below points to a local artifact, command, PR/task handoff, or an explicit caveat. They should be updated after final rehearsal, package/install artifact capture, and review.

## Headline

N# is an active pre-release CLR/.NET language and toolchain with a working compiler, SDK/CLI, project.yml-first templates, VS Code support, and app-shaped examples. The release story for this talk is not “everything is launch-green”; it is “the core toolchain is demonstrable, the claim boundaries are explicit, and the remaining gates have evidence-backed fallback paths.”

Evidence:
- `README.md:1-5` describes the current pre-release state and implemented surfaces.
- `docs/talk/evidence-matrix.md` classifies claims as safe-to-say, safe-to-demo, experimental, or do-not-say.
- `docs/talk/final-demo-script.md` turns those claims into a stage script with exact commands.

## What is safe to announce

### 1. N# has a real local compiler/CLI workflow

Claim:
- N# has a repo-local CLI with build/run/check/query/format/lint/test/package-related commands.

Evidence commands:
```bash
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- --help
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query help
```

Expected evidence snippets:
```text
build run restore publish pack clean check fix query daemon format lint test bench ...
```

```text
symbols outline diagnostics type inspect definition/def references/refs completions doc hover call-graph implementors
```

Source artifacts:
- `README.md:146-184`
- `docs/guide/cli-reference.md`
- `docs/talk/evidence-matrix.md`, dry-run rows “CLI top-level surface” and “CLI query surface”
- Task `t_fca31d81`, which verified CLI help/completion/docs parity and confirmed `nlc convert` is not public surface.

Public wording:
> “N# has a working CLI with build/run/check/test and a query surface for semantic tooling.”

Caveat:
- Use repo-local `dotnet run --project ...` in the talk unless package/install evidence proves `nlc` is installed in the talk environment.

### 2. Fast project feedback works on the console template

Claim:
- `check` can give fast no-error feedback on a template project.

Evidence command:
```bash
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- check --project templates/nsharp-console --text
```

Expected evidence snippet from the matrix:
```text
Checked 1 file — no errors. [0.1s]
```

Source artifacts:
- `templates/nsharp-console/Program.nl`
- `templates/nsharp-console/project.yml`
- `docs/talk/evidence-matrix.md`, row “CLI project check”

Public wording:
> “The fast feedback loop works: here is `check` on the console template.”

Caveat:
- Do not extrapolate this one command into “all projects are clean” without running the broader gates.

### 3. N# exposes semantic project data as JSON for tools and agents

Claim:
- `nlc query symbols` can return schema-versioned semantic JSON for a real multi-file example.

Evidence command:
```bash
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query symbols --project examples/17-issue-tracker/backend --json
```

Expected evidence snippets from the matrix:
```json
{
  "schemaVersion": 1,
  "ok": true
}
```

Source artifacts:
- `examples/17-issue-tracker/backend/`
- `docs/talk/evidence-matrix.md`, row “CLI semantic query”
- `README.md:158-168` for code-intelligence and migration-loop framing

Public wording:
> “The CLI is not only for humans. Editors and agents can ask semantic questions and receive versioned JSON.”

Caveat:
- Do not claim every query subcommand is equally mature unless the specific subcommand is rehearsed and captured.

### 4. The flagship issue tracker has a reviewed proof path

Claim:
- `examples/17-issue-tracker` is a full-stack app-shaped demo with an N# ASP.NET backend and a React/TypeScript frontend, and the runtime proof path has been reviewed green.

Evidence command:
```bash
cd examples/17-issue-tracker
ISSUE_TRACKER_HOLD=0 ./scripts/demo.sh
```

Expected evidence snippets from task handoffs:
```text
GET /api/health returns ok
GET /api/issues returns []
POST /api/issues returns 201 JSON
JSON-contract assertion passes
```

Source artifacts:
- `examples/17-issue-tracker/README.md`
- `examples/17-issue-tracker/scripts/demo.sh`
- Runtime artifact files documented in `examples/17-issue-tracker/README.md:21-30`: `.demo-artifacts/backend.log`, `health.txt`, `issues-before.json`, `create-response.json`, `issues-after.json`
- Task `t_94785070`: PR #114 merged at `d861e03a9df40e469c28cbfccc3d768d2b74e91f`; runtime demo, lint, frontend/backend build/test, audit, browser proof, GitHub Build, and scoped review were green.

Public wording:
> “The flagship app is not a snippet. It is a browser app backed by an N# ASP.NET Minimal API, and the demo script proves build, test, health, list, create, and contract checks.”

Caveat:
- The app includes normal web-stack pieces: React/TypeScript frontend plus an N# ASP.NET Minimal API backend. Do not present it as pure N# from browser to runtime.

### 5. Template quickstarts are replay-tested

Claim:
- Template docs include console, library, test, and webapi quickstarts that are replayed by a script.

Evidence commands:
```bash
python3 -m py_compile scripts/replay-template-quickstarts.py
./scripts/replay-template-quickstarts.py
```

Expected evidence snippets from `t_f9f28953`:
```text
replayed console/library/test/webapi quickstarts
webapi curl returned ["Sunny","Cloudy","Rainy"]
```

Source artifacts:
- `templates/README.md`, quickstart markers `quickstart:console`, `quickstart:library`, `quickstart:test`, `quickstart:webapi`
- `scripts/replay-template-quickstarts.py`
- Task `t_f9f28953`: PR #119 opened at `https://github.com/schneidenbach/nsharplang/pull/119`, GitHub Build passed, standalone replay passed.

Public wording:
> “The try-it-yourself path is intentionally short and the docs command blocks are replayed so they do not silently rot.”

Caveat:
- Do not claim public package installation is complete until the package artifact/install-log task provides evidence.

### 6. VS Code basics have smoke and visual evidence, but claims must stay scoped

Claim:
- Core VS Code basics have repeatable smoke/visual evidence: activation, diagnostics, completion, hover, definition, references, code actions, plus screenshots for core flows.

Evidence commands/artifacts:
```bash
cd editors/vscode
npm run test:smoke
```

```text
.hermes/visual-qa/repeatable-vscode-visual-qa.sh
.hermes/visual-qa/t_bd0074d7-20260516-024609/vscode-headless-report.json
.hermes/visual-qa/t_bd0074d7-20260516-024609/screenshots/
```

Source artifacts:
- Task `t_bd0074d7`: headless smoke 7/7 passed for activation, diagnostics, completion, hover, definition, references, code-actions; screenshots and notes were captured.

Public wording:
> “The VS Code experience has smoke-backed core editing features. We can show diagnostics, completion, hover, definitions/references, tests, and formatting with evidence.”

Caveat:
- Do not claim semantic reference-count CodeLens click-through is visually proven. `t_bd0074d7` explicitly marks CodeLens/reference-count as partial/negative evidence.
- Do not claim F5/debug is complete. `templates/README.md` states F5/debug is intentionally hidden until a real debugger-backed workflow exists.

### 7. C# to N# migration is diagnostic-driven, not a magic converter

Claim:
- The migration story is an AI-assisted loop: capture diagnostics, cluster root causes, apply recipes, rerun checks/tests, and review behavior-affecting edits.

Evidence artifacts:
- `docs/migration-notes/migration-recipe-library.md`
- Parent `t_d28776a7` handoff: baseline benchmark had 79 failure/debt groups, command coverage for `nlc check/lint/idiom/fix --dry-run/test`, and a high-confidence redaction scan.
- Parent `t_0bf73bad` handoff: Entities green slice reached `nlc check` 0 errors, diagnostics clusters 0, and focused `dotnet build` 0 errors.
- Parent `t_9beefea6` handoff: API green slice captured route snapshot and named the `NL103` method-attribute emission gap instead of hiding it.

Public wording:
> “Migration is evidence-driven: diagnostics, clusters, recipes, checks, tests, review. No public magic convert button.”

Caveat:
- The task-requested local path `docs/migration-notes/baseline-benchmark-20260514T213001Z/baseline-report.md` is not present in this checkout. Cite the task handoff and available recipe library unless that artifact is restored.
- Do not show raw SampleMigration source/config/logs publicly.

## Explicit non-claims

These are release-note guardrails, not footnotes:

- No public `nlc convert` command. Evidence: `README.md:168`, `docs/migration-notes/migration-recipe-library.md:6`, and task `t_fca31d81` command `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- convert --help` returned `Unknown command: convert`.
- No “full product launch-green” claim unless `./scripts/test-all.sh` passes in the final environment or clean checkout. Evidence: `docs/talk/evidence-matrix.md` no-go gate and final rehearsal task dependency.
- No public SampleMigration demo claim. Evidence: `docs/talk/evidence-matrix.md` SampleMigration redaction row and parent `t_d28776a7` redaction caveats.
- No CodeLens/reference-count visual claim unless stronger evidence supersedes `t_bd0074d7`.
- No public NuGet/package installation claim until the package artifacts/install logs task supplies evidence.

## Final release-gate checklist before publishing these notes

- Re-run `dotnet test tests/Tests.csproj -v q` and paste the current count into the talk operator notes.
- Re-run the exact CLI commands in `docs/talk/final-demo-script.md`.
- Re-run `cd examples/17-issue-tracker && ISSUE_TRACKER_HOLD=0 ./scripts/demo.sh` and keep `.demo-artifacts/` plus screenshots.
- Re-run `python3 -m py_compile scripts/replay-template-quickstarts.py && ./scripts/replay-template-quickstarts.py` after PR #119 lands or note the PR state.
- Use the package task’s install logs before saying “install this from NuGet/public feed.”
- Use final rehearsal output before saying “full suite green.”
