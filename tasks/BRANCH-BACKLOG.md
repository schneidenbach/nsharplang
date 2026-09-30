> CLI, LSP, runtime and remaining managed project conversion are now active under
> [TOOLCHAIN-NATIVE.md](TOOLCHAIN-NATIVE.md). Visual Studio is deferred; NativeAOT, metadata
> writer and unrelated initiatives remain held. Historical reports below retain their dates.

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

## Recovery coordination (2026-09-07)

The primary task inspected all four pinned N# tasks after the usage pause. Existing query, SDK
configuration and signature-help worktrees were clean; no live dev/full-gate process remained.
Previously completed independent work stays separate from compiler-only acceptance.

- **Compiler / primary:** complete Analyzer ownership is accepted. The whole C# class is deleted,
  canonical assertions execute in N#, and the final fresh gate at `d4dac34b6` passes in 481s.
  Official SDK publication, ordinary package tests 6/6, installed self-host 7,928/7,928 and Analyzer
  native corpus 1,088/1,088 pass. Evidence: `/private/tmp/nsharp-analyzer-owner-20260906`.
  Complete SystemsAnalyzer ownership is now also accepted: fresh gate 474s, 7,940 canonical,
  installed package probe 11/11 and installed self-host 7,940/7,940. Evidence:
  `/private/tmp/nsharp-systems-analyzer-owner-20260907`. Next compiler candidate is the complete
  ColumnarProgramInputBuilder. No sibling feature branch is implicitly resumed.
- **SDK task:** the necessary complete project-reference projection is integrated at `12c0e7f34` /
  `12e8d7406`; final native/MSBuild compatibility uses the real Runtime NuGet dependency and
  removes the SDK asset exclusion (`ef8502db8`). No duplicate stage-two project edge is needed. Preserve older `b2132a8a1` / `aecdb052c`
  separately; no runtime reimplementation or type callback/fallback was added.
- **Query task:** refresh against `2a15d2189` confirms both blockers remain. The accepted emitter
  `ColumnarCompilerReferenceResolver` is distinct from the surviving internal CLI
  `CompilationReferenceResolver`. Evidence: `/tmp/cli-query-probes/refresh-2a15d2189/README.md`.
  A complete query-help rendering route compiles with byte-identical output, but remains a separate
  CLI backlog area; the task holds with clean worktrees and preserved drafts.
- **Signature-help task:** read-only audit confirms clean `dfbd37528`, intact gate/screenshots, and
  no direct consumed-API drift against `2a15d2189`. Only the two shared ratchet files overlap; the
  three measured editor rows are distinct from compiler changes. A separate integration must
  retain both row sets, recompute the head, and run fresh combined VS Code/visual verification.
  The task holds; historical branch evidence is not combined-target acceptance.

Current compiler checkpoints also accept complete ColumnarProgramInputBuilder, ColumnarIlEmitter
and MultiFileCompiler ownership, ending at `27b1a8a1b` with a verified installed SDK. Preserve those
migrations. Complete CompilationReferenceResolver is now selected; the existing SDK reference-assembly
scan/rewrite is a compiler follow-on. CLI/editor and older SDK work remain separate.
The primary task owns shared ratchets, gates and publication. Older SDK/editor work requires
separate integration checkpoints; no duplicate verification or competing feed writes are authorized.

## Presentation and fix assertion debt (2026-09-08)

The source-only audit
`/private/tmp/nsharp-multifile-assessment/cli-fix-csharp-assertion-boundary-20260908.md` records missing
N# assertions for DefinitionSearchToJson, HoverToJson, CallGraphToJson, ImplementorsToJson, populated
and empty LintToJson, and complete fix ResultJson/BuildJsonEntry/GetExitCode/ResultText behavior.
These output schemas and fix-command policies remain separate from compiler-only completion.
Existing C# policy tests should remain until their own N# successors are verified; do not silently
delete coverage or start CLI implementation as a compiler prerequisite. The audit's compiler-facing
visibility and diagnostic gaps are tracked in task 021 instead.

## Standalone compiler facade package dependency (2026-09-09)

The `NSharpLang.Compiler` NuGet package declares a dependency on the compiler project package,
while `scripts/lib/packages.sh` publishes only SDK, Runtime, Templates and Compiler. Before the
compiler assembly rename, its nuspec required unpublished `NSharpLang.Compiler.BootstrapServices`;
afterward the same project reference names `NSharpLang.Compiler.Core`. This is existing standalone
facade-package distribution debt, separate from the SDK's directly bundled compiler tool payloads.
Do not claim the standalone Compiler package is usable on the strength of SDK integration checks.
Resolve the intended package distribution contract in the broader packaging lane. Baseline nuspec,
feed inventory and a corroborating isolated restore probe are preserved in
`/private/tmp/nsharp-compiler-core-name-review-20260909/baseline-compiler-package-restore`.
