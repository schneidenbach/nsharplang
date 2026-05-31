# N# talk evidence matrix

Generated: 2026-05-14T19:58:00Z
Repo: `/Users/spencer/code/nsharplang`
Current SHA: `6f8cf1d5b842ba172a7d5381b1d255bce40ce833` (`main`, tracking `origin/main`)
Purpose: define the public-talk success bar in executable terms. Every talk claim or demo beat below is mapped to a command, artifact, screenshot requirement, or explicit no-go.

## Verdict legend

- **Safe to say**: defensible as a spoken claim using current command output/artifacts.
- **Safe to demo**: deterministic enough to run live or in a recorded clip using the exact command listed.
- **Experimental**: can be discussed as in-progress with caveats; do not present as complete or launch-ready.
- **Do not say**: contradicted by evidence, missing evidence, or blocked by security/reliability risk.

## Dry-run evidence captured

| Area | Command / artifact | Result | Talk use |
|---|---|---|---|
| Git state | `git status --short --branch` | `## main...origin/main`; untracked `.hermes/` and `docs/talk/` in this checkout. | Safe to say repo baseline is main at the SHA above, but do not imply a clean working tree until this file is committed. |
| Recent commits | `git log --oneline -5` | Latest: `6f8cf1d docs: add developer tooling risk audit`; then `652e74d`, `443e611`, `ccc2e72`, `07dae1d`. | Safe to say recent work includes tooling risk audit, visibility polish, migration-aware C#ism lints, CI lint fixes, and async Task return analysis. |
| Open PRs | `gh pr list --state open --json number,title,isDraft,mergeable,reviewDecision,statusCheckRollup,url` | One open PR: #106 `fix(lsp): correct code lens reference counts`; mergeable, not draft, Build check success, no review decision. | Experimental. Do not claim CodeLens/reference-count fixes are shipped until reviewed/merged/verified. |
| Main CI | `gh run list --branch main --limit 3 --json ...` | Latest main Build for `6f8cf1d` succeeded: https://github.com/schneidenbach/nsharplang/actions/runs/25618328993 | Safe to say main CI Build is green at this SHA. Do not equate this with all local/end-to-end gates. |
| Unit tests | `dotnet test tests/Tests.csproj -v q` | Passed: 2265 passed, 3 skipped, 0 failed, total 2268, duration 1m16s. | Safe to say and safe to show as a terminal screenshot. |
| Full suite | Prior baseline `./scripts/test-all.sh` | Timed out after 600s in Step 3b VS Code integration tests after compiler build and unit tests passed. | Do not say full suite is green. This is a no-go gate before a launch-green claim. |
| VS Code smoke | `npm run test:smoke` in `editors/vscode` | Passed: 32 passing in 45s across hover, extension activation, diagnostics, completions. | Safe to say and safe to demo/screenshot smoke-tested IDE basics. |
| Full VS Code integration | Prior baseline `npm test` in `editors/vscode` | Did not finish promptly; current repo has nested `.worktrees` that make discovery slow/noisy. | Experimental. Do not claim full VS Code integration suite is green. |
| CLI top-level surface | `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- --help` | Shows build/run/restore/publish/pack/check/fix/query/daemon/format/lint/test/dependency/project/doc/env/completion commands, plus `build --perf-report` for deterministic performance facts. | Safe to say broad CLI surface exists. Safe to demo help output. |
| CLI query surface | `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query --help` | Shows symbols, outline, diagnostics, type, inspect, definition, references, completions, doc, hover, call-graph, implementors, batch. | Safe to say LLM/terminal-oriented query commands exist. Individual semantic claims need command-specific proof. |
| CLI project check | `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- check --project templates/nsharp-console --text` | `Checked 1 file — no errors. [0.1s]` | Safe to demo checking the console template. |
| CLI semantic query | `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query symbols --project examples/17-issue-tracker/backend --json` | JSON parsed successfully; `schemaVersion: 1`, `ok: true`, symbols include `Routes.Map`, `HandleCreate`, etc. | Safe to demo JSON symbol listing on a real example. Do not oversell every query subcommand without per-command proof. |
| Known example/check failures | `scripts/test-all.sh` known-failure audit | No silent allowlists remain in `test-all`: former single-file failures were made buildable, `imports/` has a project manifest, and parent umbrella check allowlists were removed. | It is safe to treat example failures as real gate failures in current `test-all` output. |
| Templates | Files under `templates/nsharp-console` and `templates/nsharp-webapi` | Console and WebAPI templates have `Program.nl` and `project.yml`; no user-authored template `.csproj` files found in those folders. | Safe to say templates are project.yml-first. Demo only after running creation/build gate, not from file presence alone. |
| Packaging/projects | `templates/NSharpLang.Templates.csproj`, `src/NSharpLang.Cli/Cli.csproj`, `src/NSharpLang.Sdk/NSharpLang.Sdk.csproj`, `src/NSharpLang.LanguageServer/LanguageServer.csproj`, `src/NSharpLang.Compiler/Compiler.csproj` | Packaging projects exist. | Safe to say packaging infrastructure exists. Do not say NuGet publishing is live/current without package/version/publish evidence. |
| Docs/tooling risk | `docs/audits/tooling-risk-audit.md` | Current P1/P2 risks include remaining VS Code visual/IDE gate evidence, CodeLens/reference-count launch proof, debug-test UX caveats, and stale count risk in historical memory docs. CLI help/completion/docs parity and the no-public-`nlc convert` story are remediated in the working tree. Unsaved-buffer semantic fallback is mitigated by in-memory semantic snapshots but still needs full gate evidence before public overclaiming. | Use as caveat source. Do not say docs are launch-polished until these are closed or caveated. |
| Screenshots | `search_files("*.png", target="files")` | Only `editors/vscode/icon.png` found. No talk/demo screenshots found in repo. | Screenshot-backed claims are not ready. Capture fresh terminal/IDE screenshots or use live commands. |

## Claim and demo matrix

| Public claim / demo beat | Category | Exact evidence required | Current evidence | Public wording allowed now | No-go / upgrade gate |
|---|---|---|---|---|---|
| N# is a pragmatic CLR/.NET language with Go-style simplicity goals. | Safe to say | `AGENTS.md`, `docs/DESIGN.md`, guide docs. | Project philosophy and design docs exist; not a runtime correctness claim. | "N# is aiming for a Go-for-.NET feel: small syntax, .NET interop, project.yml-driven workflow." | Do not imply broad production adoption. |
| Go-style casing controls visibility, with explicit modifiers for interop escapes. | Safe to say | `docs/DESIGN.md` visibility section plus tests from `dotnet test`. | Design doc present; unit suite green. | "Visibility is casing-first, with explicit modifiers reserved for .NET boundary cases." | For live demo, prepare a tiny file and `nlc check`/query output showing exported vs hidden symbols. |
| N# supports async, records/classes/enums, pattern matching, imports, tests, and .NET interop. | Safe to say | Unit tests plus examples under `examples/`, `tests/fixtures`, and guide docs. | 2265 unit tests pass; examples exist. | "These language surfaces are implemented enough to be tested and demonstrated in curated examples." | Do not claim language completeness. Avoid unverified edge cases. |
| The compiler/unit test suite is green. | Safe to say | `dotnet test tests/Tests.csproj -v q` output. | 2265 passed, 3 skipped. | "The core unit suite is green: 2265 passing, 3 skipped at this SHA." | Re-run within 24h of talk and capture screenshot/log. |
| The entire product is launch-green. | Do not say | `./scripts/test-all.sh` must complete green. | Full suite timed out in VS Code integration. | None. | Required: full `./scripts/test-all.sh` green locally or in CI, with timeout fixed and evidence archived. |
| Main branch CI is green. | Safe to say | `gh run list --branch main` / GitHub Actions URL. | Latest Build on main succeeded for `6f8cf1d`. | "Main Build is green at this commit." | Re-check day of talk. Do not claim it covers all local demo gates. |
| N# has an LLM-first CLI/query surface. | Safe to say | `nlc --help`, `nlc query --help`, `nlc query symbols ... --json`. | Help lists query commands; symbols query returned schema-versioned JSON on issue-tracker backend. | "The CLI has a query surface for symbols, diagnostics, definitions, references, hover, call graphs, and more; here is symbols JSON on a real project." | For each query subcommand shown live, run and save the exact command output beforehand. |
| `nlc check` gives fast project feedback. | Safe to demo | `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- check --project templates/nsharp-console --text`. | Console template check succeeded in 0.1s. | Demo exact command on the console template. | Use repo-local `dotnet run` path unless `nlc` tool is installed in demo environment. |
| `nlc query symbols` works on a multi-file app. | Safe to demo | `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query symbols --project examples/17-issue-tracker/backend --json`. | JSON parsed and returned real symbols. | Demo symbol JSON and optionally pipe through `jq` in rehearsed script. | Avoid claiming all query commands are equally robust until each is dry-run. |
| The VS Code extension has diagnostics, hover, and completions. | Safe to demo | `npm run test:smoke` plus live/recorded VS Code clip. | Smoke suite passed: 32 tests in hover/activation/diagnostics/completion. | "Core IDE basics are smoke-tested: hover, diagnostics, completions." | Capture a real VS Code screenshot/clip. Do not rely only on tests in slides. |
| VS Code project build/debug/test tasks are production-polished and zero-config. | Experimental | Full VS Code integration plus audit closure. | Audit P1-1 and P2-2 remain. | "The VS Code experience is active work; core editing features are demonstrable." | Close P1-1/P2-2, run full integration, capture screenshots. |
| CodeLens reference counts are correct and semantic. | Experimental | PR #106 merged, reviewed, full VS Code/LSP verification. | PR #106 open/unreviewed; Build green only. | "Reference-count work is in review." | Merge/verify PR #106 or remove from talk. |
| Unsaved-buffer rename/definition/references are semantically safe. | Experimental | Specific unsaved-buffer integration tests, VS Code visual QA, and full gate evidence. | In-memory project snapshots now include open-buffer text; targeted LSP tests cover unsaved duplicate-member definition/references/rename. Full suite/visual evidence still required before public claim. | "Unsaved-buffer semantic tooling has targeted regression coverage and is being verified in the IDE." | Complete VS Code visual QA, Codex review, and full `test-all` evidence before saying it is safe/complete. |
| Templates support console and WebAPI project starts. | Experimental | `dotnet new install` from local package, `dotnet new nsharp-console`, `dotnet new nsharp-webapi`, `nlc check`, `dotnet build`. | Template files exist and console template checks, but creation/build gate was not run in this task. | "Templates exist and are project.yml-first; console template checks clean." | Run full template creation/build gate before live demo. |
| Projects are `.csproj`-minimal / project.yml-driven. | Safe to say | `AGENTS.md` rule, template file inspection, build help text. | Template folders have `project.yml` and no user-authored `.csproj`; `nlc build --help` says project.yml dispatches through SDK. | "The intended project shape is project.yml-first with minimal SDK wiring." | Resolve VS Code task workflow drift before making this the centerpiece. |
| Packaging/publish commands exist. | Safe to say | `nlc --help`, project files. | CLI help lists `publish` and `pack`; package project files exist. | "There are pack/publish commands and packaging projects." | Do not claim packages are published/current unless NuGet/package artifact evidence is captured. |
| N# has broad examples including task CLI, minimal API, multi-file projects, issue tracker. | Safe to say | `VSCODE_TESTS=skip ./scripts/test-all.sh` example/project phases. | Examples are present; project examples, single-file examples, and `nlc check` example scopes passed with no known-failure allowlist. | "There are substantial examples, including an issue-tracker backend and task CLI, and the example gate is currently green." | Keep full launch-green separate from the VS Code/full-suite gate. |
| Documentation is launch-polished and current. | Experimental | Docs audit closure plus generated/current test counts. | README/site/guide/VS Code public wording has been softened and CLI parity checks exist; historical memory/completed-task notes still contain stale counts by design. | "Public docs have been tightened; historical memory notes are not launch evidence." | Rerun docs build and full gate before treating docs as final launch copy. |
| Demo screenshots are ready. | Do not say | Versioned screenshots/recordings for every visual beat. | No repo screenshots except VS Code icon. | None. | Capture fresh terminal and VS Code screenshots/recordings after final commands pass. |

## Recommended talk success bar

The talk is "amazing and defensible" if every green-room rehearsal can produce these artifacts without hand-editing outputs:

1. Terminal screenshot/log: `git rev-parse HEAD`, `gh run list --branch main --limit 1`, and `dotnet test tests/Tests.csproj -v q` showing the exact SHA, green main Build, and green unit suite.
2. Terminal screenshot/log: `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- check --project templates/nsharp-console --text` showing fast no-error feedback.
3. Terminal screenshot/log: `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query symbols --project examples/17-issue-tracker/backend --json` showing schema-versioned semantic JSON on a multi-file app.
4. IDE screenshot/clip: VS Code with an `.nl` file showing diagnostics, hover, and completions, backed by `npm run test:smoke` passing.
5. Example screenshot/clip: one curated example (`examples/17-issue-tracker/backend` or `examples/16-task-cli`) with a rehearsed check/build/run command that completes under the talk time budget.
6. Slide caveat: the full suite is not public launch proof unless the gate below closes.

## Pre-talk no-go gates

These gates decide what can be said live. If a gate is red, use the downgraded wording in the matrix.

| Gate | Must be true before saying/demoing | Current status | If red |
|---|---|---|---|
| Launch-green gate | `./scripts/test-all.sh` completes successfully in a clean checkout within the agreed time budget. | Red: prior run timed out at VS Code integration. | Do not say launch-ready/full-suite-green. Say unit/smoke green only. |
| IDE visual gate | Fresh VS Code screenshot/recording shows hover, diagnostics, completions; smoke test passes same day. | Yellow: smoke passed; screenshot absent. | Demo terminal test output only or record the IDE before talk. |
| LSP CodeLens/reference gate | PR #106 reviewed/merged; reference counts verified in real VS Code; full relevant tests green. | Red/yellow: PR open and unreviewed. | Exclude CodeLens/reference-count claims. |
| Unsaved-buffer semantic gate | Definition/references/rename either use in-memory semantics or are disabled when stale; tests and screenshot prove behavior. | Yellow: in-memory semantic snapshots and duplicate-name LSP tests are present; screenshot/full gate evidence still pending. | Describe as targeted-test-covered, not broadly safe, until visual/full gate evidence is captured. |
| Template creation gate | From a clean temp dir: install local templates, create console and WebAPI projects, `nlc check`, `dotnet build`, and run if applicable. | Yellow/red: files exist and console template checks; creation/build gate not rerun here. | Say templates exist; do not live-demo creation unless rehearsed. |
| Example all-green gate | All examples build/check without unowned allowlists, or every allowlist has owner/issue/expiry. | Green for current working tree: examples build/check in `VSCODE_TESTS=skip ./scripts/test-all.sh`, and no script allowlist remains. | Keep this gate green by failing future unexpected example errors instead of reintroducing silent allowlists. |
| Docs launch-polish gate | Tooling risk audit P1/P2 docs issues closed; stale test counts removed or generated. | Yellow/red: audit items remain. | Avoid broad docs-polish claims. |
| Packaging/publishing gate | Package artifacts or NuGet pages for CLI/SDK/templates/language server are current and installable in clean environment. | Yellow: commands/projects exist; publish evidence not captured. | Say packaging path exists, not that release distribution is done. |

## Minimal defensible talk script

Use this if the no-go gates above are still mixed:

1. "N# is a Go-for-.NET language experiment becoming a real toolchain: small syntax, project.yml-first projects, .NET interop, and an LLM-friendly CLI."
2. Show unit suite: 2265 passing / 3 skipped at the current SHA.
3. Show `nlc check` on the console template: fast no-error feedback.
4. Show `nlc query symbols` JSON on the issue-tracker backend: real semantic project output for tools/agents.
5. Show VS Code smoke-backed basics: diagnostics, hover, completions. If no screenshot is captured, say this is smoke-tested and show terminal output instead of overclaiming live IDE polish.
6. Say clearly: "The full end-to-end suite is a pre-talk gate, not a proof point today."

## Immediate recommendation

Do not present N# as launch-green today. Present it as unit-test-green, main-Build-green, CLI-query-demonstrable, VS-Code-smoke-targeted, and example-gate-green. Treat full `test-all` with VS Code integration, PR #106, unsaved-buffer semantics, and screenshot capture as pre-talk gates before making stronger public claims.
