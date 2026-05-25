# Task 009: Interpolated String Editing

Priority: P1.

Make interpolated strings look and behave correctly in VS Code while preserving compiler behavior. This task covers syntax highlighting, representative examples, and real editor verification.

## User Outcome

Nested interpolation expressions should highlight as N# expressions, not plain string text. Escapes, braces, raw strings, and multiline interpolation should be visually clear while editing.

## Scope

- Audit VS Code grammar and sample `.nl` files for interpolated strings.
- Fix highlighting for nested interpolation expressions, escapes, braces, raw strings, and multiline strings.
- Add representative samples or tests so the behavior is not lost.
- Keep normal string and raw-string highlighting stable.

## Likely Files

- `editors/vscode/syntaxes`
- `editors/vscode`
- `examples`
- `tests` if grammar/tokenization tests exist or need to be added

## Acceptance

- Nested interpolation expressions highlight as N# expressions.
- Escaped braces, raw interpolated strings, and multiline interpolation render correctly.
- Representative samples exist for future checking.
- No public screenshot or doc shows behavior that was not verified.

## Verification

- Run focused extension tests if available.
- Run `./scripts/test-all.sh` before committing if code or test infrastructure changes.
- Run `./scripts/reload-vscode-extension.sh`, open VS Code, and visually verify the highlighting cases in a real `.nl` file.
