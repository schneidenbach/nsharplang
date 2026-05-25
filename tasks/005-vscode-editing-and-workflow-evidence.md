# Task 005: VS Code Editing And Workflow Evidence

Priority: P1.

Make the VS Code extension look correct while editing and make build/test/debug claims match verified behavior. These belong in one thread because both touch the real editor experience, extension assets/contributions, examples/templates, and public claims about what VS Code support actually does.

## User Outcome

Nested interpolation expressions should highlight as N# expressions, not plain string text. A fresh N# template project should also support the VS Code workflows that the product claims. If build, test, debug, breakpoints, or source mapping are partial, docs must say so precisely.

## Scope

- Audit VS Code grammar, extension contributions, sample `.nl` files, template output, generated tasks/launch configuration, docs, website docs, and launch materials.
- Fix highlighting for nested interpolation expressions, escapes, braces, raw strings, and multiline strings.
- Verify build, run, test, and debug flows in a fresh template project.
- Keep claims conservative unless the workflow is freshly verified.
- Add representative samples or tests so editor behavior is not lost.

## Likely Files

- `editors/vscode`
- `editors/vscode/syntaxes`
- `templates`
- `examples`
- `docs`
- `website/docs`
- `docs/talk`
- `tests` for extension/template behavior

## Acceptance

- Nested interpolation expressions highlight as N# expressions.
- Escaped braces, raw interpolated strings, and multiline interpolation render correctly.
- Fresh template projects can build, run, test, and debug from VS Code to the extent docs claim.
- Debugging uses the generated C# bundle correctly if debug support is claimed.
- Breakpoint/source mapping behavior is visually verified before being claimed.
- Docs and launch materials match verified behavior exactly.

## Verification

- Run focused extension/template tests where practical.
- Run `./scripts/test-all.sh` before committing if code or templates change.
- Run `./scripts/reload-vscode-extension.sh`, open VS Code, and visually verify highlighting plus build/run/test/debug workflows in a real project.
