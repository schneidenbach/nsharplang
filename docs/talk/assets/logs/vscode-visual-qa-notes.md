# Repeatable VS Code visual QA notes for t_bd0074d7

Generated: 2026-05-16T22:08:30Z

## Re-run

From repo root:

```bash
./.hermes/visual-qa/repeatable-vscode-visual-qa.sh
```

The script rebuild/headless-smoke checks via ./scripts/test-vscode-headless.sh, creates an isolated workspace, installs the latest packaged nsharp VSIX into an isolated extension dir, launches VS Code, and captures screenshots in `screenshots/`.

## Claim-to-artifact map

| IDE claim / talk-matrix gate | Artifact(s) | Evidence note |
|---|---|---|
| diagnostics | screenshots/01-diagnostics-broken-file.png; headless-smoke.log | Broken.nl intentionally returns a string from int function; Problems/editor should show N# diagnostic. |
| completion | screenshots/02-completion-name-dot.png; headless-smoke.log | Completion.nl puts cursor after `name.`; expected member completion list includes `ToUpper` per headless smoke. |
| hover | screenshots/03-hover-greet-or-symbol.png; headless-smoke.log | Program.nl hover command over a symbol; headless smoke verifies hover contents on `ToUpper`. |
| definition | screenshots/04-definition-greet.png; headless-smoke.log | F12 from Program.nl `greet(name)`; headless smoke verifies definition resolves to Helpers.nl. |
| references | screenshots/05-references-greet.png; headless-smoke.log | Shift+F12 from Program.nl `greet(name)`; headless smoke verifies at least declaration + use. |
| rename | screenshots/06-rename-oldName-dialog.png | F2 over Rename.nl `oldName` should open the VS Code rename input. |
| CodeLens / reference counts | screenshots/07-codelens-program-references.png | Program.nl should show N# CodeLens/reference UI above eligible symbols if enabled. If absent, keep CodeLens talk claim experimental. |
| tests | screenshots/08-tests-codelens-and-test-file.png | VisualQa.tests.nl gives two test blocks; expected Run/Debug CodeLens/Test Explorer surface if test controller discovers them. |
| formatting | screenshots/09-formatting-before.png; screenshots/10-formatting-after.png | Formatting.nl is intentionally ugly; Format Document screenshot pair proves formatter path visually. |

## Caveats

- This is macOS UI automation against real VS Code; screenshots must be inspected because keyboard focus/popups can be stolen by host-level UI.
- No Cloudflare/tunnel/public preview is used.
- No public `nlc convert` claim is introduced.
- CodeLens/test screenshots are evidence-gathering gates, not automatic approval to say those features are production-polished.
