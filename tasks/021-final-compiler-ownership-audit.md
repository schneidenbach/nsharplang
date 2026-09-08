# 021 — Final compiler ownership audit

## Execution contract

Work in `/Users/spencer/repos/nsharplang` on the current `systems-language` branch.

Complete remaining compiler ownership areas under `tasks/README.md`, then verify the whole compiler
boundary. Do not hide unfinished product work, waive a failed gate, or classify policy as glue.

- Add no C# source, tests, helpers, bridges, callbacks, whitelists, or fallback logic.
- Delete zero-consumer legacy owners and superseded assertions.
- Every surviving non-N# compiler-core integration boundary must be pre-existing, non-growing,
  mechanical, and explicitly reviewed against a canonical N# owner. Separately tracked CLI/editor
  features do not become compiler scope merely because they share a folder.
- Follow every final backend, product, IDE, visual-verification, documentation, selective-staging,
  `Evidence:` commit, repin, and clean-tree rule in `AGENTS.md`.
- Report only after every terminal condition below is green.

## Selected area: complete MultiFileCompiler

After the accepted emitter checkpoint `8ec52542b`, move the complete 663-line C# class into
BootstrapServices with namespace `NSharpLang.Compiler`. All compiler dependencies already reside
there. Delete the C# file without a facade, type forwarder, callback or fallback.

Move all 24 methods, 18 runtime fields and property backing state, nine properties, four public
constructors and the common private constructor. The four private C# constants each have one
internal read and no named production/test consumers; replace those reads with their exact literals
(10, 20 and the two environment-variable names), as C# already does. Do not introduce runtime
static initialization or a member-constant language prerequisite just to preserve their private
metadata. The complete proposed N# class proved member-constant syntax unsupported; retain that
failed-source evidence with the owner handoff. Preserve the public nonsealed type, optional
defaults, initialization/enumeration order, live collection views, repeated-call state, diagnostics,
source overrides, reference identities, analyzer lifetime and the 64 MiB emission thread's exception
and decline-trace behavior. Move dependencies with callers when actual proposed N# compilation
demonstrates a missing capability; add no C# behavior to overcome it.

Migrate all ten `ErrorRecoveryPipelineTests.cs` assertions, including malformed cross-file analysis,
bounded/deduplicated import cycles, case-insensitive unsaved overrides and CRLF source snippets;
delete that complete C# test file. Nine cases can live beside the N# owner; the CodeIntelligenceService
integration case belongs in the native estate to avoid a reverse assembly reference. Update all
seven native assembly-qualified owner lookups in the same integration checkpoint. Add focused
ownership/failure coverage where the actual boundary has gaps, preserving existing native coverage.

Direct production callers should resolve through existing project references. Surrounding CLI,
Playground and editor policy stays in the separate backlog. Compiler reference/metadata decisions
remain in scope wherever they live; do not exclude them by directory or by calling them transport.
This owner affects IDE analysis: finish the IDE-enabled gate, extension reinstall and visual
unsaved-buffer verification before accepting it. Astra reviews, retires the two audit rows,
integrates, verifies and pushes; Sol Max or Terra Max implements the complete bounded owner/tests.

Source audit: `/private/tmp/nsharp-multifile-assessment/current-boundary-20260908.md`.

### Proven constructor-chain prerequisite (in progress)

The complete proposed owner uses constructor delegation with `null` and nested static input-builder
calls. Actual-source/prefix evidence in
`/private/tmp/nsharp-multifile-owner-20260908/ctor-parse-probes-r1` shows simple/default/private
constructors parse but the required delegated forms fail. `ParseConstructorChainInfoCore` currently
accepts only restricted argument forms. Implement the connected N# parsing, materialization and
emission support, preserving argument order and exceptions before instance initialization; do not
move input building into constructor bodies to evade that ordering. Verify the actual owner forms
and focused ordering/failure controls before integrating a seed.

Goodall owns this prerequisite in a separate worktree while the ten-case canonical migration stays
frozen. Hooke retains the complete owner and isolation of the remaining body parse failure. Astra
reviews and groups any related proven prerequisites for required seed verification; no SDK
publication is accepted merely because parsing succeeds.

## Next connected area after MultiFileCompiler

Move the entire `src/NSharpLang.Cli/CompilationReferenceResolver.cs` owner: 497 lines, 19 methods
and its shared two-minute `HttpClient`. Its recursive project builds, package cache lifecycle,
dependency mutation, I/O ordering and cleanup are compiler reference-resolution behavior.
Existing N# kernels do not make that orchestration mechanical. The current dependency on
MultiFileCompiler requires accepting that owner in BootstrapServices first.

Preserve the eight resolution callers and five assembly-name callers through the smallest supported
cross-assembly boundary; do not introduce a C# facade. Reuse existing N# models/kernels and native
coverage, migrate the canonical reference-resolution assertions in the existing build/publish/check
integrations, and add focused real gaps in cache/order/failure behavior. SDK/MSBuild projection and
broader CLI policy remain separate. Source and caller/test inventory:
`/private/tmp/nsharp-reference-resolution-assessment/current-boundary-20260908.md` (reviewed hash
`1b5d9dacf75acaa053d0634350b5985b3f720f3a2eef1b8fc863c8ec519feeb4`).

## Final compiler audit

Close `NSharpLang.Compiler` ownership.

Audit every tracked source file in `NSharpLang.Compiler` and verify that parser, syntax diagnostics,
AST, semantic analysis, systems policy, binding, lowering, IL generation,
compiler reference/metadata resolution and canonical compiler tests each have exactly one N#
production owner.

Review mixed integration test files by assertion, not by filename. For example,
`CheckCommandTests.cs` still asserts compiler diagnostic spans/messages, and
`IlSdkToolchainTests.cs` checks emitted assembly-version metadata. Compare their exact source
fixtures and assertions with existing N# coverage; migrate or retire superseded compiler assertions
without expanding into separate CLI feature work. Opening evidence:
`/private/tmp/nsharp-multifile-assessment/root-remaining-canonical-boundaries-20260908.json`.

Delete every zero-consumer legacy C# owner and superseded C# assertion. Classify only genuine
pre-existing mechanical ecosystem boundaries, proving that none contains product decisions and
none grew during the closeout.

Run the complete canonical compiler estate, compiler tests and required integration checks under
AGENTS.md, including examples, templates, interop, ILVerify and the ownership audit. Use a fresh
backend product gate for backend-only work; retain the VS Code-enabled gate, extension reinstall
and visual verification for IDE-affecting changes. Repin only when required by a verified seed change.
Update present-tense architecture documentation and the queue ledger. Leave
a clean committed tree with no partial compiler stages.
