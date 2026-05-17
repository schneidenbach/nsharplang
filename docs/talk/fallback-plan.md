# N# Talk Fallback Plan

Goal: every demo beat has a no-live-dependency path. If network, Docker, VS Code, package feeds, or local servers misbehave, the operator can continue with static artifacts and still stay truthful.

Global fallback rules:
- Prefer local static artifacts over live network calls.
- Do not use public tunnels or public preview URLs.
- Do not show raw COTM source/config/logs.
- Do not invent outputs. If an artifact is missing, downgrade the spoken claim.
- Keep the no-public-`nlc convert` direction intact.

## Fallback inventory to prepare before rehearsal

Create or refresh these local artifacts in the final rehearsal bundle:

```text
docs/talk/final-demo-script.md
docs/talk/release-notes.md
docs/talk/fallback-plan.md
docs/talk/evidence-matrix.md
examples/17-issue-tracker/.demo-artifacts/health.txt
examples/17-issue-tracker/.demo-artifacts/issues-before.json
examples/17-issue-tracker/.demo-artifacts/create-response.json
examples/17-issue-tracker/.demo-artifacts/issues-after.json
.hermes/visual-qa/t_bd0074d7-20260516-024609/screenshots/
.hermes/visual-qa/t_bd0074d7-20260516-024609/vscode-headless-report.json
```

Optional rehearsal captures:
```text
docs/talk/artifacts/git-status.txt
docs/talk/artifacts/cli-help.txt
docs/talk/artifacts/query-help.txt
docs/talk/artifacts/check-console.txt
docs/talk/artifacts/query-symbols.issue-tracker.json
docs/talk/artifacts/unit-tests.txt
docs/talk/artifacts/template-replay.txt
docs/talk/artifacts/issue-tracker-browser.png
docs/talk/artifacts/issue-tracker-demo.mp4
docs/talk/artifacts/vscode-core-features.mp4
```

The optional `docs/talk/artifacts/` directory does not exist yet in this checkout; create it only if the final asset task wants versioned local talk artifacts.

## Beat-by-beat fallback table

| Demo beat | Live dependency | Primary live command | Static fallback | Safe fallback wording | Do not say if fallback is used |
|---|---|---|---|---|---|
| Repo/release posture | Git working tree | `pwd; git rev-parse --short HEAD; git status --short --branch` | `docs/talk/evidence-matrix.md` plus a captured `git-status.txt` | “This is the evidence bundle and the exact branch/SHA from rehearsal.” | “The live worktree is clean” unless shown. |
| CLI top-level help | Local .NET restore/build | `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- --help` | Captured `cli-help.txt`; `README.md:170-184`; `docs/guide/cli-reference.md` | “Here is the current command surface captured from the CLI.” | “Every command is production-hardened.” |
| Query help | Local .NET restore/build | `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query help` | Captured `query-help.txt`; `README.md:178-184`; task `t_fca31d81` | “The query surface includes symbols, diagnostics, definition, refs, hover, call graph, implementors.” | “All query commands are equally mature.” |
| Fast check | Local .NET restore/build | `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- check --project templates/nsharp-console --text` | Captured `check-console.txt`; matrix row with `Checked 1 file — no errors. [0.1s]` | “The console template has a proven fast-check path.” | “All templates/examples are green today” unless rerun. |
| Symbol JSON | Local .NET restore/build; `python3`/`jq` if formatting | `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query symbols --project examples/17-issue-tracker/backend --json` | Captured `query-symbols.issue-tracker.json`; matrix row “CLI semantic query” | “A real multi-file app can produce schema-versioned symbol JSON.” | “The entire semantic API is bug-free.” |
| Unit tests | Local .NET test environment | `dotnet test tests/Tests.csproj -v q` | Captured `unit-tests.txt` from final rehearsal | “At rehearsal, the unit suite was green with this output.” | “The unit suite is green right now” unless live command ran. |
| Issue tracker API smoke | Node/npm, local .NET, free port 5167 | `cd examples/17-issue-tracker && ISSUE_TRACKER_HOLD=0 ./scripts/demo.sh` | `.demo-artifacts/health.txt`, `issues-before.json`, `create-response.json`, `issues-after.json`; task `t_94785070` reviewer proof | “The reviewed demo path proves health/list/create/contract checks; here are the artifacts.” | “The live server is running” or “I just created this issue” if using static JSON. |
| Issue tracker browser UI | Local server/browser | `./scripts/demo.sh` then open `http://localhost:5167` | Screenshot/recording from reviewer proof or final rehearsal | “This is the captured browser proof from the green demo run.” | “This is live” if static. |
| Templates quickstart replay | Local package build, temp HOME/feed, .NET, webapi port | `python3 -m py_compile scripts/replay-template-quickstarts.py && ./scripts/replay-template-quickstarts.py` | Captured `template-replay.txt`; `templates/README.md`; task `t_f9f28953` | “The quickstart commands are replay-tested; here is the proof output.” | “Public install is final” unless package artifact task proves it. |
| VS Code core features | VS Code UI, extension host, host profile cleanliness | `cd editors/vscode && npm run test:smoke`; visual screenshots | `.hermes/visual-qa/t_bd0074d7-20260516-024609/screenshots/` and `vscode-headless-report.json` | “Core IDE basics have smoke and visual evidence.” | “CodeLens reference counts are visually proven”; “F5 debugging is complete.” |
| Migration story | None if using docs only | `sed -n '1,80p' docs/nsharp-conversion/ai-migration-recipe-library.md` | Slides from `ai-migration-recipe-library.md`; handoffs `t_d28776a7`, `t_0bf73bad`, `t_9beefea6` | “Migration is diagnostic-driven and internally validated with redacted artifacts.” | “Raw COTM is safe to show”; “COTM compiles/runs end-to-end”; “use nlc convert.” |
| Release posture close | None | Show `release-notes.md` and gate list | `docs/talk/release-notes.md`; `docs/talk/evidence-matrix.md` | “These are the evidence-backed claims and remaining gates.” | “Launch-green” unless final rehearsal and review gate approve it. |

## Failure-specific playbooks

### If GitHub/network is down

Use:
- Local task handoffs already copied into `docs/talk/release-notes.md`.
- Local artifact references in `docs/talk/evidence-matrix.md`.
- Avoid live `gh run list`, `gh pr checks`, or PR pages.

Say:
> “I am not depending on GitHub live during the talk; the release notes cite the PR/task evidence and local artifacts from rehearsal.”

Do not say:
- Do not claim current CI state unless it was refreshed before the outage and captured.

### If .NET restore/build is cold or failing live

Use:
- Captured CLI help/check/query outputs from final rehearsal.
- `README.md`, `templates/README.md`, and `examples/17-issue-tracker/README.md` as source docs.

Say:
> “This machine is not the proof; the proof is the rehearsed command output and checked-in artifacts. I’ll switch to the capture and keep the claim scoped.”

Do not say:
- Do not describe a failed live command as passing.

### If Node/npm is slow or failing

Use:
- Issue-tracker static artifacts in `.demo-artifacts/`.
- Browser screenshot/recording from final rehearsal.
- `t_94785070` review evidence summarized in `release-notes.md`.

Say:
> “The live frontend build is not cooperating, so here is the captured green demo path: health, list, create, follow-up list, and the rendered browser.”

Do not say:
- Do not run `npm audit fix` or change package files during the talk.

### If port 5167 is busy

Try once:
```bash
cd examples/17-issue-tracker
ISSUE_TRACKER_PORT=5177 ./scripts/demo.sh
```

If still blocked:
- Switch to static `.demo-artifacts/` and screenshots.

Say:
> “Port conflict; using the captured local-server proof instead.”

Do not say:
- Do not expose via a public tunnel.

### If VS Code opens with noisy host UI

Use:
- `.hermes/visual-qa/t_bd0074d7-20260516-024609/screenshots/`
- `.hermes/visual-qa/t_bd0074d7-20260516-024609/vscode-headless-report.json`

Say:
> “The host profile is noisy, so I’m using the clean visual QA capture. The evidence is diagnostics/completion/hover/definition/reference smoke, not a claim that every IDE edge case is done.”

Do not say:
- Do not claim CodeLens/reference counts are proven.
- Do not claim F5/debug works.

### If Docker is unavailable

No main talk beat should require Docker.

Use:
- Avoid Testcontainers-dependent integration tests.
- For template quickstarts, use standalone replay evidence from `t_f9f28953`; it was accepted despite Docker blocking the integration test host.
- For COTM/test green-slice discussion, cite the blocker honestly from parent handoffs.

Say:
> “Docker-dependent tests are not part of the live talk path. Where Docker was unavailable, the evidence labels it as an environment blocker rather than hiding it.”

Do not say:
- Do not claim Testcontainers runtime validation passed unless it did in the final environment.

### If package feed/public install is not proven

Use:
- Repo-local CLI commands.
- Template quickstart replay from local package/feed isolation.
- Package task output if/when available.

Say:
> “For this talk I’m using repo-local tooling. Public install wording waits for the package artifact/install-log gate.”

Do not say:
- Do not present NuGet/public install as complete.

### If COTM baseline artifacts are missing

Current state:
- `docs/nsharp-conversion/ai-migration-recipe-library.md` exists.
- The task-requested `docs/nsharp-conversion/baseline-benchmark-20260514T213001Z/baseline-report.md` is not present in this checkout.

Use:
- The recipe library and task handoff summaries only.

Say:
> “The COTM baseline is an internal evidence story. The local baseline report path is not present in this checkout, so I’m citing the recipe library and handoff summary rather than showing raw artifacts.”

Do not say:
- Do not cite a missing local file as if it is present.
- Do not show raw COTM files.

## Static talk order if everything live fails

1. Show `docs/talk/release-notes.md` headline and explicit non-claims.
2. Show captured CLI help/query/check outputs.
3. Show captured `query-symbols.issue-tracker.json` first page.
4. Show issue-tracker browser screenshot/recording and `.demo-artifacts/*.json`.
5. Show template quickstart command blocks plus captured replay output.
6. Show VS Code screenshot set and headless report.
7. Show migration recipe loop from `ai-migration-recipe-library.md`.
8. Close on remaining gates from `evidence-matrix.md`.

This static path keeps the talk credible because it swaps live drama for receipts rather than stronger claims.
