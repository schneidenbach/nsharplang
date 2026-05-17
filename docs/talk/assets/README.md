# N# launch talk assets

Generated: 2026-05-16T22:14:14Z
Source commit: `e8b2084cdf0fa3bb602b239fee1a4a23b89766cc`
Workspace: `/Users/spencer/code/nsharplang`

This manifest is the source of truth for launch-talk demo assets captured for task `t_38c8dea4`. Assets are intentionally scoped to toy/demo projects and generated logs. Do not use COTM or other real application material in the talk unless a separate redaction review approves it.

## Reproduce the capture set

From the repo root:

```bash
# VS Code visual QA screenshots and headless IDE proof
NSHARP_VISUAL_QA_TS=t_38c8dea4-$(date +%Y%m%d-%H%M%S) ./.hermes/visual-qa/repeatable-vscode-visual-qa.sh

# CLI/check/query/unit/smoke terminal evidence
mkdir -p docs/talk/assets/logs docs/talk/assets/vscode
{
  echo '$ git rev-parse HEAD'
  git rev-parse HEAD
  echo
  echo '$ git status --short --branch'
  git status --short --branch
} > docs/talk/assets/logs/source-state.txt
{
  echo '$ dotnet run --project src/NSharpLang.Cli/Cli.csproj -- check --project templates/nsharp-console --text'
  dotnet run --project src/NSharpLang.Cli/Cli.csproj -- check --project templates/nsharp-console --text
} > docs/talk/assets/logs/cli-check-console-template.txt 2>&1
{
  echo '$ dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query symbols --project examples/17-issue-tracker/backend --json'
  dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query symbols --project examples/17-issue-tracker/backend --json
} > docs/talk/assets/logs/cli-query-symbols-issue-tracker.json.log 2>&1
{
  echo '$ dotnet test tests/Tests.csproj -v q'
  dotnet test tests/Tests.csproj -v q
} > docs/talk/assets/logs/unit-tests.txt 2>&1
{
  echo '$ npm run test:smoke (editors/vscode)'
  (cd editors/vscode && npm run test:smoke)
} > docs/talk/assets/logs/vscode-smoke.txt 2>&1

# Issue tracker runtime proof path
{
  echo '$ ISSUE_TRACKER_HOLD=0 examples/17-issue-tracker/scripts/demo.sh'
  ISSUE_TRACKER_HOLD=0 examples/17-issue-tracker/scripts/demo.sh
} > docs/talk/assets/logs/issue-tracker-runtime-demo.txt 2>&1
cp examples/17-issue-tracker/.demo-artifacts/health.txt docs/talk/assets/logs/issue-tracker-health.txt
cp examples/17-issue-tracker/.demo-artifacts/issues-before.json docs/talk/assets/logs/issue-tracker-issues-before.json
cp examples/17-issue-tracker/.demo-artifacts/create-response.json docs/talk/assets/logs/issue-tracker-create-response.json
cp examples/17-issue-tracker/.demo-artifacts/issues-after.json docs/talk/assets/logs/issue-tracker-issues-after.json
cp examples/17-issue-tracker/.demo-artifacts/backend.log docs/talk/assets/logs/issue-tracker-backend.log
```

The VS Code screenshot PNGs were copied from the latest repeatable QA run recorded in `latest-vscode-visual-qa-source.txt` and cropped to the VS Code window with:

```bash
for f in docs/talk/assets/vscode/*.png; do
  /opt/homebrew/bin/ffmpeg -y -loglevel error -i "$f" -vf 'crop=1440:900:240:88' "$f.cropped.png"
  mv "$f.cropped.png" "$f"
done
```

## Asset manifest

| Asset | Capture command / source | Talk claim supported | Fallback beat if weak | Status / caveat |
|---|---|---|---|---|
| `logs/source-state.txt` | `git rev-parse HEAD`; `git status --short --branch` | Establishes source commit and working-tree context for all captured assets. | Say assets came from the named local branch/commit, not a pristine release checkout. | Safe; working tree was not clean before/after capture. |
| `logs/unit-tests.txt` | `dotnet test tests/Tests.csproj -v q` | Core compiler/unit suite is green at this source state. | If screenshots are not used, quote the final VSTest line. | Safe: 2396 passed, 3 skipped, 0 failed. Warnings are present. |
| `logs/cli-check-console-template.txt` | `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- check --project templates/nsharp-console --text` | `nlc check` gives fast no-error feedback on the console template. | Use as terminal-only proof if live CLI demo is skipped. | Safe: ends with `Checked 1 file — no errors. [0.1s]`; build warnings precede it. |
| `logs/cli-query-symbols-issue-tracker.json.log` | `dotnet run --project src/NSharpLang.Cli/Cli.csproj -- query symbols --project examples/17-issue-tracker/backend --json` | `nlc query symbols` returns schema-versioned semantic JSON on a real multi-file app. | Pipe through `jq` live or show selected symbol names only. | Safe for `symbols`; do not generalize to every query subcommand without per-command proof. |
| `logs/vscode-smoke.txt` | `(cd editors/vscode && npm run test:smoke)` | VS Code extension smoke tests cover activation, diagnostics, hover, and completions. | If visual screenshots are questioned, cite this test log as non-visual proof. | Safe: 36 passing, exit code 0. |
| `logs/vscode-headless-report.json` | `.hermes/visual-qa/repeatable-vscode-visual-qa.sh` via `./scripts/test-vscode-headless.sh` | Headless VS Code proof for activation, diagnostics, completion, hover, definition, references, code actions. | Use when screenshots are visually partial. | Safe: 7 passed, 0 failed. |
| `logs/vscode-headless-smoke.log` | `.hermes/visual-qa/repeatable-vscode-visual-qa.sh` | Verbose proof companion for `vscode-headless-report.json`. | Use only if someone asks for raw evidence. | Safe; generated in temp workspace. |
| `logs/vscode-visual-qa-notes.md` | `.hermes/visual-qa/repeatable-vscode-visual-qa.sh` | Maps each VS Code screenshot to the IDE feature it was intended to prove. | Use as operator notes, not slide content. | Safe; includes caveats that focus/popups can affect screenshots. |
| `logs/vscode-visual-qa-run-metadata.txt` | `.hermes/visual-qa/repeatable-vscode-visual-qa.sh` | Reproduction metadata: generated project, user-data dir, extension dir, server path, VSIX. | Use if the screenshots need to be regenerated. | Safe but local-path-specific. |
| `latest-vscode-visual-qa-source.txt` | `cat .hermes/visual-qa/latest-repeatable-vscode-qa-dir.txt` | Records source `.hermes/visual-qa` run for copied screenshots/logs. | Regenerate from the source run if the committed assets are insufficient. | Safe; local path only. |
| `vscode/01-diagnostics-broken-file.png` | `.hermes/visual-qa/repeatable-vscode-visual-qa.sh`; copied from `screenshots/01-diagnostics-broken-file.png`; cropped with ffmpeg | VS Code diagnostics are visible for an intentional type mismatch in `Broken.nl`. | Use `logs/vscode-headless-report.json` diagnostic `NL202` if the screenshot is too visually subtle. | Safe visual evidence; no secrets observed. |
| `vscode/02-completion-name-dot.png` | Same harness; `screenshots/02-completion-name-dot.png`; cropped with ffmpeg | Completion popup appears in an `.nl` file. | Use headless completion result count and sample from `vscode-headless-report.json`. | Safe visual evidence; completion is visible. |
| `vscode/03-hover-greet-or-symbol.png` | Same harness; `screenshots/03-hover-greet-or-symbol.png`; cropped with ffmpeg | Intended hover proof. | Use headless hover contents in `vscode-headless-report.json`. | Weak visual evidence: the hover popup is not visible in this crop; keep the claim backed by headless proof, not this screenshot alone. |
| `vscode/04-definition-greet.png` | Same harness; `screenshots/04-definition-greet.png`; cropped with ffmpeg | Go-to-definition was exercised from `greet(name)`. | Use headless definition result resolving to `Helpers.nl`. | Partial visual evidence; pair with headless report. |
| `vscode/05-references-greet.png` | Same harness; `screenshots/05-references-greet.png`; cropped with ffmpeg | Find references was exercised for `greet`. | Use headless references result with `Helpers.nl` and `Program.nl`. | Partial visual evidence; pair with headless report. |
| `vscode/06-rename-oldName-dialog.png` | Same harness; `screenshots/06-rename-oldName-dialog.png`; cropped with ffmpeg | Rename UI opens over `oldName`. | Mention rename is visually smoke-captured, not launch-polish proof. | Safe visual evidence if inspected; human visual approval recommended. |
| `vscode/07-codelens-program-references.png` | Same harness; `screenshots/07-codelens-program-references.png`; cropped with ffmpeg | Only proves the editor is open around a symbol; does not prove semantic reference-count CodeLens. | Say reference-count CodeLens remains experimental/no-go until stronger visual proof exists. | Negative/weak evidence; do not upgrade CodeLens/reference-count claim. |
| `vscode/08-tests-codelens-and-test-file.png` | Same harness; `screenshots/08-tests-codelens-and-test-file.png`; cropped with ffmpeg | Test file/editor surface for N# test blocks. | Use `vscode-smoke.txt` extension activation/test-controller checks if visual test UI is unclear. | Safe to show as test-surface evidence, not full test UX polish. |
| `vscode/09-formatting-before.png` | Same harness; `screenshots/09-formatting-before.png`; cropped with ffmpeg | Formatter before state. | Show as part of before/after pair only. | Safe visual evidence. |
| `vscode/10-formatting-after.png` | Same harness; `screenshots/10-formatting-after.png`; cropped with ffmpeg | Formatter after state. | Show as part of before/after pair only. | Safe visual evidence. |
| `logs/packaging-vscode-extension-install.log` | `.hermes/visual-qa/clean-vscode-debug-test-profile-20260516-025451/code-install-extension.log` | VSIX extension install succeeds in an isolated profile. | Say local package/install path exists; do not claim public Marketplace availability. | Safe: `nsharp-0.6.0.vsix` installed successfully. No packaging screenshot is included because the available old screenshot showed host UI noise rather than useful install proof. |
| `logs/packaging-dotnet-new.log` | `.hermes/visual-qa/clean-vscode-debug-test-profile-20260516-025451/dotnet-new.log` | `dotnet new` can create the N# console template in the clean profile. | Say template creation was captured locally, not public NuGet distribution. | Safe but minimal: only template creation success. |
| `logs/packaging-nlc-build.log` | `.hermes/visual-qa/clean-vscode-debug-test-profile-20260516-025451/nlc-build.log` | Locally installed `nlc` build path for the generated project. | If stale, rerun clean profile before live use. | Safe if reviewed; older available packaging evidence. |
| `logs/packaging-nlc-run.log` | `.hermes/visual-qa/clean-vscode-debug-test-profile-20260516-025451/nlc-run.log` | Locally installed `nlc` run path for the generated project. | If stale, rerun clean profile before live use. | Safe if reviewed; older available packaging evidence. |
| `logs/issue-tracker-runtime-demo.txt` | `ISSUE_TRACKER_HOLD=0 examples/17-issue-tracker/scripts/demo.sh` | Flagship issue-tracker example builds, tests, starts backend, performs health/list/create/list, and validates API JSON. | Use the JSON artifact files below if the full terminal log is too long. | Safe: demo path completed; warnings are present in generated C# stub build. |
| `logs/issue-tracker-health.txt` | Copied from `examples/17-issue-tracker/.demo-artifacts/health.txt` after demo script | Health endpoint returns `ok`. | Use as single-line runtime proof. | Safe. |
| `logs/issue-tracker-issues-before.json` | Copied from `.demo-artifacts/issues-before.json` after demo script | Initial issue list is empty before create. | Use as setup beat. | Safe. |
| `logs/issue-tracker-create-response.json` | Copied from `.demo-artifacts/create-response.json` after demo script | POST creates issue #1 with expected status/priority/tags. | Show selected JSON fields only in slides. | Safe demo data; timestamp is generated. |
| `logs/issue-tracker-issues-after.json` | Copied from `.demo-artifacts/issues-after.json` after demo script | List after create includes the created issue. | Show selected JSON fields only in slides. | Safe demo data; timestamp is generated. |
| `logs/issue-tracker-backend.log` | Copied from `.demo-artifacts/backend.log` after demo script | ASP.NET backend served health/issues/create endpoints locally. | Use if someone asks for server-side runtime proof. | Contains dummy `https://hooks.slack.example/issues`; safe placeholder, not a real secret. |

## What is proven vs. not proven

Proven enough for the talk:

- Core unit suite: `2396 passed`, `3 skipped`, `0 failed` at the captured source state.
- CLI check: console template reports `Checked 1 file — no errors. [0.1s]`.
- CLI query: issue-tracker backend returns JSON symbol output from `query symbols`.
- Issue-tracker runtime: frontend build, backend build/test, local server health/list/create/list, and JSON contract assertion all completed.
- VS Code diagnostics/completion/formatting have usable screenshots plus headless proof.
- VS Code definition/references/hover have stronger headless proof than visual proof; use screenshot + JSON report together.

Keep experimental / do not oversell:

- CodeLens/reference-count remains experimental. `vscode/07-codelens-program-references.png` does not visually prove semantic reference counts.
- Full end-to-end launch-green status is not proven here; `./scripts/test-all.sh` was not run to completion in this task.
- Packaging logs prove local install/template/build/run paths, not public distribution or NuGet availability.
- COTM remains internal-only; no COTM screenshots/logs are included.

## Redaction notes

- Screenshots are from an isolated `VisualQaProject` toy workspace and were cropped to the VS Code window to remove desktop/browser background.
- Logs were captured from generated demos and local commands. The only webhook-looking value is `https://hooks.slack.example/issues`, which is a dummy placeholder in demo output.
- No raw COTM files, credentials, tokens, `.env`, appsettings, or real customer/user data are included.
