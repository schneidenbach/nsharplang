# Broader systems-language branch backlog

These initiatives retain their accepted work and outstanding evidence, but are separate from the
active compiler-only ownership objective in [README.md](README.md). Their historical records remain
in STATUS.md and their numbered tasks; this separation does not mark any initiative complete.

- CLI command ownership, query/daemon behavior and CLI presentation: task 019 and STATUS follow-ups.
- LSP/editor completion, hover, signature help, import acceptance and other editor features: task
  022 slice 4 and STATUS tooling chips. Keep existing IDE acceptance evidence; apply mandatory IDE
  verification whenever new compiler work actually affects IDE behavior.
- Runtime reimplementation and NativeAOT: task 022's native publishing and single-runtime-universe
  requirements remain open independently of compiler decision ownership.
- Metadata writer: task 023's second ECMA-335 executor and retirement of Reflection.Emit remain a
  branch initiative. Activate writer implementation for this objective only after demonstrating
  that compiler ownership requires it. Accepted declaration/plan migrations remain production code.
- Installer, gate infrastructure, performance follow-ups, documentation hosting, import hygiene and
  other branch chips remain in STATUS.md. Change SDK/tooling now only for compiler migration needs.

Compiler reference/metadata resolution and code generation themselves remain in the active compiler
objective, regardless of which historical task records them. Historical writer/AOT ordering cannot
force unrelated compiler ownership migrations to wait.

## Independent lane reports (2026-09-06; not compiler-goal acceptance)

- CLI query lane, `codex/cli-query-owner`: complete query-doc deletion is blocked on the proposed
  `Lazy<T>(Func<T>)` construction; both the accepted seed and freshly built lane CLI decline the
  actual source at `emit.local.initializer`. Source/log: `/tmp/cli-query-probes/lazy/`; full proposed
  slice preserved in `/tmp/cli-query-probes/proposed-slice`. Seven native contracts pass against the
  baseline, which is not migration acceptance. Hover additionally lacks daemon enum/admission/server
  dispatch and cannot directly call the current internal C# `CompilationReferenceResolver` boundary
  (actual source/log `/tmp/cli-query-probes/hover-boundary/`). Tracked work was restored buildable;
  no migrated ownership or commit claimed. These prerequisites are not part of the constraint seed.
- Signature-help lane, `codex/signature-help-owner`, is ready separately at `dfbd3752` (product
  `a500b6d3`, measured corpus-count fix `6e23ed1b`). Reported fresh VS Code-enabled gate: 517s,
  587 unit / 7,827 canonical / 53 native projects / 12 throughput cells / 68 IL assemblies;
  reload/reinstall and five real-editor screenshots passed. The source remains isolated and unmerged.
  Handoff: `systems-language-closeout/decodes/2026-09-06-signature-help-ownership.md` in that branch.
  Shared AST finder container traversal remains a proven editor dependency: class control passes,
  struct/record/default-interface method calls miss despite clean parsing/analysis (external 1/4).
  No shared AST or compiler-model change is part of this compiler checkpoint.
- SDK configuration lane, `codex/sdk-config-owner`, is isolated with exact SDK configuration/reference
  task and SDK-specific N# file claims. Ready commits `b2132a8a1` and `aecdb052c`
  are reported clean with 9/9 canonical tests and 1/1 private package/template/build/run/invalid-config
  integration passing. Shared integration and publication remain pending; neither commit is part
  of this compiler checkpoint.
