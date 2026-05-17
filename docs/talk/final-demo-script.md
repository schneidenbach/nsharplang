# N# Final Demo Script

Talk operator checklist:
- Run from `/Users/spencer/code/nsharplang` unless a beat says otherwise.
- Use repo-local commands (`dotnet run --project src/NSharpLang.Cli/Cli.csproj -- ...`) unless the final package-install task proves a clean `nlc` tool is installed.
- Capture or refresh terminal/IDE/browser screenshots before the talk; do not depend on network, Docker, or a live GitHub API during the talk.
- Keep `examples/17-issue-tracker/.demo-artifacts/` from a fresh `ISSUE_TRACKER_HOLD=0 ./scripts/demo.sh` run available for static fallback.
- Never show raw SampleMigration source/config/log files. Use only redacted docs under `docs/migration-notes/` and task handoff summaries.
- Do not say or imply there is a public `nlc convert` command.

## Evidence categories for the operator

Safe to say:
- N# is an active pre-release CLR/.NET language/toolchain with Go-style simplicity goals and project.yml-first workflow. Evidence: `README.md`, `docs/DESIGN.md`, `docs/talk/evidence-matrix.md`.
- The core unit suite has recently passed and should be re-run for the talk. Evidence command: `dotnet test tests/Tests.csproj -v q`; earlier matrix evidence recorded `2265 passed, 3 skipped` at SHA `6f8cf1d5b842ba172a7d5381b1d255bce40ce833`.
- The CLI exposes build/run/check/query/etc. Evidence command: `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- --help`; docs parity evidence in task `t_fca31d81`.
- `nlc query` is intended for humans, editors, and agents. Evidence command: `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query help`; docs parity evidence in task `t_fca31d81`.
- The issue-tracker flagship demo has a reviewed green proof path. Evidence: `examples/17-issue-tracker/README.md`, PR #114 handoff in `t_94785070`, and command `cd examples/17-issue-tracker && ISSUE_TRACKER_HOLD=0 ./scripts/demo.sh`.
- Template quickstarts are replayed by a script and PR #119 had green GitHub Build at handoff. Evidence: `templates/README.md`, `scripts/replay-template-quickstarts.py`, task `t_f9f28953`.

Safe to demo live after same-day dry run:
- CLI help, `check`, and `query symbols` commands listed below.
- Issue-tracker script in `ISSUE_TRACKER_HOLD=0` mode if local Node/.NET environment is warm.
- Static VS Code screenshots/recordings from `.hermes/visual-qa/t_bd0074d7-20260516-024609/` if the live editor is noisy.

Experimental / caveated:
- Full end-to-end launch-green status: requires `./scripts/test-all.sh` green in clean checkout. Evidence matrix originally marked this red from a VS Code integration timeout; later parent evidence in `t_3039dc17` says it passed after restore, so re-run before claiming.
- CodeLens/reference-count click-through: visual evidence was partial/negative in `t_bd0074d7`; keep semantic CodeLens counts out of the live claim unless a stronger screenshot exists.
- SampleMigration migration: source-grounded internal validation story only. Evidence: `docs/migration-notes/migration-recipe-library.md` and parent handoffs; the task-requested `baseline-report.md` path is not present in this checkout, so do not cite it as a local file until restored.
- Public package availability: package/install artifacts are assigned to the separate package task; do not claim NuGet/public install is complete from this script alone.

Do not say:
- “N# is launch-green” unless the final rehearsal gate proves it.
- “The full suite is green” unless `./scripts/test-all.sh` is green in the talk environment or clean checkout.
- “SampleMigration compiles/runs end-to-end in N#” or “SampleMigration is safe to show publicly.”
- “Run `nlc convert`” or “N# has a public one-shot C# converter.” The supported migration framing is AI-assisted diagnostic/idiom/fix/test iteration.
- “CodeLens reference counts are visually proven” unless new visual proof exists beyond the partial evidence in `t_bd0074d7`.

## Minute-by-minute runbook

### 0:00–0:45 — Frame the product honestly

Say:
> “N# is a pragmatic CLR language: Go-flavored syntax, normal .NET interop, project.yml-first projects, and tooling that treats the CLI and VS Code as product surface.”

Show slide or terminal with evidence pointers:
```bash
pwd
git rev-parse --short HEAD
git status --short --branch
```

Expected output shape:
```text
/Users/spencer/code/nsharplang
<current-sha>
## <branch>...<remote>/<branch>
```

Evidence:
- `README.md:1-5` describes current pre-release status and the working compiler/SDK/CLI/templates/VS Code/examples.
- `docs/talk/evidence-matrix.md` records the public-claim categories and no-go gates.

Do not say:
- Do not imply the working tree is clean unless `git status --short` proves it.
- Do not cite stale hard-coded test counts from docs; use the live `dotnet test` output.

Fallback if terminal state is dirty:
- Use a static screenshot of the commit/release slide and say “This is the evidence bundle; the branch state is visible in the release checklist.”

### 0:45–2:00 — Prove the CLI surface exists

Command:
```bash
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- --help
```

Expected output snippets:
```text
N# Compiler (nlc)
Commands:
  build
  run
  check
  query
  format
  lint
  test
  pack
  publish
  completion
```

Follow-up command:
```bash
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query help
```

Expected output snippets:
```text
symbols
outline
diagnostics
definition / def
references / refs
hover
call-graph
implementors
```

Safe-to-say wording:
> “The CLI has the usual build/run/check path, but the interesting bit is `query`: it gives editors and agents a stable way to ask semantic questions.”

Evidence:
- `docs/talk/evidence-matrix.md` dry-run rows “CLI top-level surface” and “CLI query surface”.
- `README.md:146-184` documents current CLI usage and query surface.
- Task `t_fca31d81` verified help/completion/docs parity and confirmed `convert` is not a public command.

Do not say:
- Do not say every query command is equally hardened unless each exact command is rehearsed.
- Do not say `nlc convert` exists; it intentionally does not.

Fallback:
- Show a captured terminal text file containing help output; this beat has no network dependency.

### 2:00–3:15 — Fast feedback: `check` on the console template

Command:
```bash
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- check --project templates/nsharp-console --text
```

Expected output snippet:
```text
Checked 1 file — no errors.
```

Safe-to-demo wording:
> “This is the boring-but-important loop: edit N#, run a fast check, get diagnostics without doing a whole demo dance.”

Evidence:
- `docs/talk/evidence-matrix.md` row “CLI project check” recorded `Checked 1 file — no errors. [0.1s]`.
- `templates/nsharp-console/Program.nl` and `templates/nsharp-console/project.yml` are the checked artifacts.

Do not say:
- Do not generalize one-template success into “all examples are green” unless the current example gates have been run.

Fallback:
- Use the static output snippet above; if local restore is cold, skip live restore time and move to recorded output.

### 3:15–4:45 — Semantic JSON for agents: issue-tracker symbols

Command:
```bash
dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query symbols --project examples/17-issue-tracker/backend --json | python3 -m json.tool | sed -n '1,60p'
```

Expected output snippets:
```json
{
  "schemaVersion": 1,
  "ok": true,
  "symbols": [
```

Names to look for if the output is long:
```text
Routes.Map
HandleCreate
IssueService
IssueStatus
```

Safe-to-say wording:
> “This is the LLM-first part. A tool does not have to scrape text; it can ask for schema-versioned symbols from a real multi-file app.”

Evidence:
- `docs/talk/evidence-matrix.md` row “CLI semantic query” recorded parsed JSON with `schemaVersion=1`, `ok=true`, and real issue-tracker symbols.
- `examples/17-issue-tracker/backend/` contains the multi-file N# backend.

Do not say:
- Do not claim the query API is frozen forever; say schema-versioned.
- Do not claim all semantic operations are perfect; CodeLens/reference count visual proof is still caveated.

Fallback:
- Use a saved `query-symbols.json` from the rehearsal bundle and show the first 60 formatted lines.

### 4:45–7:30 — Flagship app: issue tracker

Fast proof command:
```bash
cd examples/17-issue-tracker
ISSUE_TRACKER_HOLD=0 ./scripts/demo.sh
```

Expected output snippets:
```text
GET /api/health ... ok
GET /api/issues ... []
POST /api/issues ... 201
JSON contract assertion passed
```

If doing browser visuals live:
```bash
cd examples/17-issue-tracker
./scripts/demo.sh
open http://localhost:5167
```

Safe-to-demo wording:
> “This is a full-stack example: N# backend, ASP.NET Minimal API, React frontend, records, unions, pattern matching, visibility-by-casing, and a boring JSON contract to the browser.”

Evidence:
- `examples/17-issue-tracker/README.md` documents the script, artifact files, and feature tour.
- `t_94785070` handoff: PR #114 merged; runtime demo, targeted lint, frontend/backend build/test, audit, browser proof, GitHub Build, and scoped review were green.
- Reviewer browser screenshots from `t_94785070`: rendered app with API live and issue creation.

Do not say:
- Do not pretend this is pure N# all the way down. The demo includes a React/TypeScript frontend and an ASP.NET bridge where needed.
- Do not include `.demo-artifacts/backend.log` in slides without checking it for environment-specific noise.

Fallback:
- Use browser screenshots from reviewer proof or pre-recorded clip.
- Use static artifacts: `examples/17-issue-tracker/.demo-artifacts/health.txt`, `issues-before.json`, `create-response.json`, and `issues-after.json` from the most recent successful run.

### 7:30–8:45 — Templates: “try this after the talk”

Command:
```bash
python3 -m py_compile scripts/replay-template-quickstarts.py
./scripts/replay-template-quickstarts.py
```

Expected output snippets:
```text
replayed console
replayed library
replayed test
replayed webapi
["Sunny","Cloudy","Rainy"]
```

Safe-to-say wording:
> “The post-talk path is intentionally short: install the toolchain, create a project, build, run or test. The quickstart blocks are replayed by a script so docs rot is caught.”

Evidence:
- `templates/README.md` contains `quickstart:console`, `quickstart:library`, `quickstart:test`, and `quickstart:webapi` command blocks.
- `t_f9f28953` handoff: standalone replay passed; PR #119 had green GitHub Build.

Do not say:
- Do not claim a public NuGet/package install is final unless the package artifact/install-log task is complete.
- Do not demo `dotnet new install NSharpLang.Templates` from public feed unless the package task gives a verified source.

Fallback:
- Show the four quickstart blocks from `templates/README.md` and the prior replay output from `t_f9f28953`.

### 8:45–10:00 — VS Code: keep the visual claim scoped

Preferred live/recorded evidence:
```bash
npm run test:smoke
```
from `editors/vscode`, plus screenshots in:
```text
.hermes/visual-qa/t_bd0074d7-20260516-024609/screenshots/
```

Safe-to-say wording:
> “The VS Code story is real enough to show core editing: diagnostics, completion, hover, definition/references smoke coverage, formatting, and test UI evidence. I am deliberately not overselling every IDE edge case.”

Evidence:
- `t_bd0074d7` handoff: headless smoke 7/7 for activation, diagnostics, completion, hover, definition, references, code-actions.
- Visual artifacts under `.hermes/visual-qa/t_bd0074d7-20260516-024609/`.

Do not say:
- Do not say semantic reference-count CodeLens click-through is visually proven; reviewer caveat says it is partial/negative.
- Do not say F5/debug is complete; templates docs say F5/debug is intentionally hidden until a real debugger-backed workflow exists.

Fallback:
- Use static screenshots/recordings. Do not open a live, dirty VS Code profile on stage if Copilot/keychain/sidebar noise is visible.

### 10:00–11:15 — Migration story: AI-assisted, evidence-driven, not one-shot convert

Show docs only, not raw customer/project files:
```bash
sed -n '1,80p' docs/migration-notes/migration-recipe-library.md
```

Safe-to-say wording:
> “The migration story is not ‘press a magic convert button.’ The evidence says the honest loop is diagnostics, cluster root causes, apply one recipe, rerun checks/tests, and review behavior-changing edits.”

Evidence:
- `docs/migration-notes/migration-recipe-library.md` states the loop and recipe families.
- Parent `t_d28776a7` handoff records a baseline benchmark with 79 failure/debt clusters and redaction audit, but the requested `baseline-report.md` file is not present in this checkout.
- Parent `t_0bf73bad` handoff: Entities green slice had `nlc check` 0 errors, diagnostics clusters 0, and focused `dotnet build` 0 errors.

Do not say:
- Do not show raw SampleMigration source/config/logs.
- Do not say SampleMigration is safe for public demo.
- Do not say there is a public `nlc convert` command.

Fallback:
- Use a slide with the recipe loop and the artifact references from the recipe library.

### 11:15–12:00 — Close with the honest release posture

Say:
> “The honest release posture is: compiler and core CLI are demonstrable, query JSON is useful for tools and agents, the flagship app has a reviewed proof path, template quickstarts are replayed, and the remaining launch gates are explicit rather than hidden.”

Evidence to cite on the slide:
- `docs/talk/evidence-matrix.md` for categories and no-go gates.
- `docs/talk/release-notes.md` for source-grounded release claims.
- `docs/talk/fallback-plan.md` for no-live-dependency backup.

Do not say:
- Do not use “production-ready from day one” as an achieved factual claim in this talk; it is an aspiration in `AGENTS.md`, not a completed gate.
- Do not call the package public until install logs/package artifacts prove it.
