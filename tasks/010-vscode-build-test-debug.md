# Task 010: VS Code Build, Test, And Debug Evidence

Priority: P1.

Make VS Code build/test/debug claims match verified behavior. This task is a vertical slice through extension contributions, templates, generated tasks/launch configuration, docs, and real-editor evidence.

## User Outcome

A fresh N# template project should support the VS Code workflows that the product claims. If build, test, debug, breakpoints, or source mapping are partial, docs must say so precisely.

## Scope

- Audit VS Code task/debug contributions, template output, launch/task files, docs, website docs, and launch materials.
- Verify build, run, test, and debug flows in a fresh template project.
- Keep claims conservative unless the workflow is freshly verified.
- Tighten docs when behavior is unsupported or partial.

## Likely Files

- `editors/vscode`
- `templates`
- `docs`
- `website/docs`
- `docs/talk`
- `tests` for extension/template behavior

## Acceptance

- Fresh template projects can build, run, test, and debug from VS Code to the extent docs claim.
- Debugging uses the generated C# bundle correctly if debug support is claimed.
- Breakpoint/source mapping behavior is visually verified before being claimed.
- Docs and launch materials match verified behavior exactly.

## Verification

- Run focused template and extension tests where practical.
- Run `./scripts/test-all.sh` before committing if code or templates change.
- Run `./scripts/reload-vscode-extension.sh` and visually verify the workflow in VS Code.
