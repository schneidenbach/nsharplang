# N# universal implementation/review gate

Use this block at the top of every N# launch implementation/review card. It is intentionally strict: N# should not accumulate untested compiler hacks, stale docs, fake IDE claims, or conversion-story regressions during the launch fan-out.

## Copy-paste Kanban gate

```text
N# UNIVERSAL IMPLEMENTATION/REVIEW GATE

Scope classification — choose every area touched by this card:
- [ ] Language/compiler/runtime/IL
- [ ] CLI/query/daemon/templates/project system
- [ ] LSP/VS Code/editor UX
- [ ] Docs/examples/talk/release claims
- [ ] Interop/export/tooling work
- [ ] Release/package/final demo gate

Required evidence before completion:
1. Tests: add or update targeted tests for the changed behavior. Name the exact test command(s) and result in the Kanban handoff.
2. Docs/examples: update user-facing docs, examples, template docs, or the talk evidence matrix when behavior, commands, claims, limitations, or demo steps change. If docs are intentionally unchanged, state why.
3. Codex review: run a Codex code/design review for code, architecture, compiler, CLI, LSP, VS Code, interop/export, or release-gate changes. Save the prompt/output path or quote the actionable findings. If Codex is unavailable, say that explicitly and record what should be reviewed later.
4. Full gate: run `./scripts/test-all.sh` when the change can affect compiler output, CLI behavior, SDK/templates, examples, packaging, VS Code/LSP, or release/talk readiness. If not run, give a concrete reason and list the narrower gates that were run instead.
5. IDE visual QA: for any LSP, VS Code extension, language-server, editor task/debug/test, completion, hover, diagnostics, references, rename, definition, CodeLens, formatting, or user-visible IDE behavior change, run the VS Code reload/headless gate and capture real VS Code visual evidence. Unit tests alone are not enough.
6. No conversion surface regression: do not reintroduce `nlc convert` or a public code-conversion workflow. Generated C# is for inspection and interop debugging.
7. No overclaim regression: do not strengthen launch/talk/docs claims beyond evidence. Do not say launch-green/full-suite-green/product-ready unless the full gate evidence exists.
8. Cleanliness: remove temporary files/logs unless they are deliberate artifacts under `.hermes/` or `docs/`; preserve unrelated dirty work; run `git diff --check` before handoff.

Area-specific minimums:
- Language/compiler/runtime/IL: parser/analyzer/emitter tests; negative diagnostics where relevant; no parse-cascade-only "fixes"; update DESIGN/docs for syntax or semantic changes.
- CLI/query/daemon/templates/project system: help/completion/schema parity tests; golden JSON for query outputs; stable schema/version notes; template creation/build/run/test evidence where templates or project shape are touched.
- LSP/VS Code/editor UX: language-server or extension tests plus `./scripts/reload-vscode-extension.sh`; `./scripts/test-vscode-headless.sh` or the relevant npm smoke/integration command; screenshot/clip/notes from real VS Code for changed UX.
- Docs/examples/talk/release claims: source-ground every claim; update `docs/talk/evidence-matrix.md` when public wording changes; avoid stale counts; include command evidence or downgrade the claim.
- Interop/export/tooling work: no DB schema changes; no secrets; redact artifacts; report exact check/fix/test commands and remaining blockers; keep services/product/software claims separated when relevant.
- Release/package/final demo gates: clean checkout or clean temp-dir evidence; package/template install evidence; screenshots/recordings for visual claims; explicit fallback plan for every live demo dependency.

Reviewer gate:
- [ ] Handoff includes changed files, tests run, docs touched/justification, Codex review result/path, `test-all` status/waiver, visual QA artifacts if applicable, and known residual risks.
- [ ] Reviewer rejects completion if any applicable area-specific minimum is missing or if the card overclaims beyond captured evidence.
```

## Short Kanban comment variant

Use this shorter comment when a card body is already long:

```text
Apply the N# universal gate from `docs/talk/universal-implementation-review-gate.md`: classify touched area(s); add targeted tests; update docs/examples/evidence matrix or justify no-docs; run Codex review for code/design changes; run `./scripts/test-all.sh` unless narrowly waived with replacement gates; perform real VS Code visual QA for IDE/LSP/editor UX; preserve the no-public-code-conversion direction; avoid launch/product-ready overclaims; include exact evidence and residual risks in the handoff.
```

## Reviewer checklist quick map

| Card type | Must see before approval |
|---|---|
| Language/compiler/runtime/IL | Targeted parser/analyzer/emitter tests, negative diagnostics if relevant, docs/design update for syntax/semantics, Codex review, `test-all` or explicit scoped waiver. |
| CLI/query/daemon/templates/project system | Help/completion/schema parity, golden JSON or command snapshots, template/project creation/build evidence when touched, docs parity, Codex review, `test-all` if product surface changed. |
| LSP/VS Code/editor UX | Unit/integration tests, reload extension, headless/smoke gate, real VS Code screenshot/clip/notes, no unit-test-only approval. |
| Docs/examples/talk/release claims | Source-grounded wording, evidence matrix update for public claims, stale-count/convert/launch-green checks, no stronger claim than captured evidence. |
| Interop/export/tooling work | Redacted artifacts, no secrets/schema changes, exact check/fix/test evidence, no public code-conversion workflow. |
| Release/package/final demo | Clean checkout/temp-dir proof, package/template install proof, full gate status, visual artifacts, fallback plan. |

## Current launch-card references

This gate was created from Kanban task `t_b9bd34fd` and should be referenced by active N# launch implementation/review cards. Prefer adding the short variant as a comment to cards that were created before this file existed.
