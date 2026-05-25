# Task 014: Finish Interpolation Syntax Highlighting

Priority: P1 IDE tooling.

Work in the N# repository and make interpolation highlighting correct in the VS Code extension. Grammar-only tests can miss visual editor failures, so this task must finish with real-editor verification.

## Scope

- Audit the VS Code grammar, sample files, syntax highlighting tests, and how interpolated strings are tokenized.
- Ensure nested interpolation expressions highlight as N# expressions, not plain string text.
- Cover escapes, braces, raw strings, multiline interpolation, and nested expressions.
- Keep grammar changes compatible with existing highlighting for normal strings and raw strings.

## Likely Files

- `editors/vscode/syntaxes`
- `editors/vscode`
- `examples`
- `tests` if grammar/tokenization tests exist or need to be added

## Acceptance

- Nested interpolation expressions highlight as N# expressions, not plain string text.
- Escapes, braces, raw strings, and multiline interpolation render correctly.
- Representative samples exist for future visual or automated checks.
- Docs or screenshots are updated only if they currently claim or show interpolation highlighting behavior.

## Verification

- Run focused extension tests if available.
- Run `./scripts/test-all.sh` before committing if code/test infrastructure changes.
- Run `./scripts/reload-vscode-extension.sh`, open VS Code, and visually verify the highlighting cases in a real `.nl` file.
