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

Move all 24 methods, 22 declared fields and property backing state, nine properties, four public
constructors and the common private constructor. Preserve the public nonsealed type, optional
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

## Final compiler audit

Close `NSharpLang.Compiler` ownership.

Audit every tracked source file in `NSharpLang.Compiler` and verify that parser, syntax diagnostics,
AST, semantic analysis, systems policy, binding, lowering, IL generation,
compiler reference/metadata resolution and canonical compiler tests each have exactly one N#
production owner.

Delete every zero-consumer legacy C# owner and superseded C# assertion. Classify only genuine
pre-existing mechanical ecosystem boundaries, proving that none contains product decisions and
none grew during the closeout.

Run the complete canonical compiler estate, compiler tests and required integration checks under
AGENTS.md, including examples, templates, interop, ILVerify and the ownership audit. Use a fresh
backend product gate for backend-only work; retain the VS Code-enabled gate, extension reinstall
and visual verification for IDE-affecting changes. Repin only when required by a verified seed change.
Update present-tense architecture documentation and the queue ledger. Leave
a clean committed tree with no partial compiler stages.
