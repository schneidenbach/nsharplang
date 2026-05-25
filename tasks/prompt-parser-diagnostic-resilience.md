# Prompt: Parser And Diagnostic Resilience

Last updated: 2026-05-25

Copy this into a fresh agent/dev session.

```text
You are working in the N# repository. Your goal is to harden parser recovery and keep diagnostic quality high. This is not a from-scratch parser recovery implementation; current recovery already exists.

Read `tasks/CURRENT.md` first. Focus on these current issues:
- 8. Harden parser recovery beyond the current baseline
- 9. Keep diagnostic quality from regressing

Expected approach:
1. Audit current parser synchronization, partial AST behavior, analyzer behavior after parse errors, diagnostic formatting, golden tests, LSP diagnostic publishing, formatter behavior on bad input, and query command behavior.
2. Add malformed fixtures that represent real editing/migration failures.
3. Fix crashes, no-progress loops, missing high-signal diagnostics, and excessive cascades.
4. Keep diagnostic messages concrete and actionable.
5. Do not destabilize valid-code parsing.

Acceptance:
- Malformed files do not crash parser, analyzer, formatter, LSP, or query commands.
- Parser resumes at useful declaration and statement boundaries.
- Diagnostics retain useful source snippets, explanations, suggestions, stable codes, and docs links.
- Golden/snapshot tests cover representative recovery behavior.

Verification:
- Add parser recovery, error recovery pipeline, diagnostic golden, formatter bad-input, and LSP diagnostics tests as appropriate.
- Run focused tests during development.
- Run `./scripts/test-all.sh` before committing.
- If LSP diagnostics change, run `./scripts/reload-vscode-extension.sh` and visually verify in VS Code.
```
