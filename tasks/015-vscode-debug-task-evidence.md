# Task 015: Keep VS Code Debug And Task Claims Gated By Real Evidence

Priority: P1 IDE tooling and launch honesty.

Work in the N# repository and make VS Code task/debug claims match verified behavior. VS Code tasks use `nlc` paths and debug build plumbing exists, but public claims around F5, debug, and test workflows must stay conservative until freshly verified.

## Scope

- Audit VS Code extension task/debug contributions, generated launch/task files, template output, docs, README, website docs, and launch materials.
- Verify a fresh template project can build, run, test, and debug from VS Code only to the extent public docs claim.
- Tighten docs if behavior is not fully supported.
- Do not claim zero-config debugging, test discovery, or source mapping unless verified in the real editor.

## Likely Files

- `editors/vscode`
- `templates`
- `docs`
- `website/docs`
- `docs/talk`
- `tests` for extension/template behavior

## Acceptance

- Fresh template project can build, run, test, and debug from VS Code using contributed tasks/configuration to the extent docs claim.
- Debugging uses the generated C# bundle correctly, and breakpoint/source mapping behavior is visually verified before any public claim is kept or added.
- Docs and launch claims match exactly what was verified in VS Code.
- Unsupported or partial workflows are described honestly.

## Verification

- Run focused tests for templates, extension configuration, and docs parity where practical.
- Run `./scripts/test-all.sh` before committing if code or templates change.
- Run `./scripts/reload-vscode-extension.sh` and visually verify the workflow in real VS Code.
