# Prompt: IDE Product Hardening

Last updated: 2026-05-25

Copy this into a fresh agent/dev session.

```text
You are working in the N# repository. Your goal is to harden the VS Code/editor product experience without making unsupported launch claims.

Read `tasks/CURRENT.md` first. Focus on these current issues:
- 9. Keep diagnostic quality from regressing
- 12. Harden workspace diagnostics scheduling and coverage
- 13. Finish interpolation syntax highlighting
- 14. Keep VS Code debug/task claims gated by real-editor evidence

Expected approach:
1. Audit the current Language Server handlers, VS Code extension task/debug integration, syntax grammar, tests, and docs.
2. Make workspace diagnostics reliable for open/change/save/create/delete/watched-file paths.
3. Fix interpolation highlighting for nested expressions, escapes, braces, raw strings, and multiline strings.
4. Verify debug/task docs and extension behavior match the real current workflow. Tighten claims instead of expanding them when evidence is missing.
5. Ensure diagnostic presentation remains helpful in Problems, hover/squiggle text, and terminal/query output.

Acceptance:
- Workspace diagnostics update reliably and do not leave stale diagnostics in normal editor flows.
- Interpolated strings highlight correctly in real VS Code.
- A fresh template project can be exercised through contributed tasks/debug paths only to the extent docs claim support.
- Docs do not claim unverified zero-config behavior.

Verification:
- Add or update LSP and VS Code integration tests for workspace diagnostics and interpolation highlighting where possible.
- Run focused tests during development.
- Run `./scripts/test-all.sh` before committing.
- Mandatory: run `./scripts/reload-vscode-extension.sh`, open VS Code, visually verify the changed editor behavior, and capture screenshots/notes in the final report.
```
