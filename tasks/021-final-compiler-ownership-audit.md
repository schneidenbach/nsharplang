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

### Proven inherited collection Count prerequisite (in progress)

After explicit optional-default arguments resolve input construction, the actual owner reaches
`IReadOnlyDictionary<string, string>.Count` and fails emission. The exact inherited-interface cast
also fails; preserve both source/log pairs under
`/private/tmp/nsharp-multifile-owner-20260908` (no-delegating build variants r13/r14). Implement the
N# inherited `IReadOnlyCollection<KeyValuePair<K,V>>.Count` resolution and getter emission for the
original receiver. Preserve all three getter reads; neither enumeration nor a cached count is an
equivalent replacement. This prerequisite has a separate implementation owner and will be combined
with the constructor-chain fix for review and required seed verification. Diagnostic variants that
omit delegation or bypass a helper are evidence only, never the accepted production owner.

Focused emitter/catalog canonicals pass, but the first ordinary native run rejects all three Count
reads during N# semantic analysis (`NL303`, with cascading array-length errors). Preserve
`readonly-dictionary-count-seed/native-focused-r1.json` and its stderr log under the same evidence
directory: it executed zero tests. Complete the connected inherited-interface semantic member
resolution in N# and rerun the ordinary native test; emission-only proof does not close this gap.

### Proven emission-thread delegate prerequisite (in progress)

The provisional constructor candidate clears all four real owner chains. With only the blocked
override-copy helper stubbed in a diagnostic snapshot, compilation then rejects the actual
`ThreadStart` capturing lambda in `EmitOnWideStackThread`; see
`/private/tmp/nsharp-multifile-owner-20260908/full-owner-copy-stub-provisional-build-r18.log`.
The emitter signature classifier and type admission currently support Action/Func but reject this
non-generic delegate. Preserve the dedicated thread, captured per-invocation state, same-thread
decline construction, Join and exception propagation. Implement the connected N# delegate support
with focused capture/thread controls in a separate prerequisite worktree. Review confirmed that
its signature-classification methods do not overlap the constructor call-site/new-method edits;
coordinate any new shared-method changes before editing. Combine the proven dependencies for
required seed verification; the complete owner
must ultimately compile and execute without any diagnostic stubs.

The later r19/r20 owner probes also reject the `IEnumerable<object>` boundary into
`CompilationUnitFacts.RequiresColumnarSoaEmission`. That complete N# method has only the owner as
a production caller. First compile moving its loop into the owner's existing private method and
delete the unused cross-owner method, retaining the existing declaration inspection helper.
Preserve evaluation of `SoaFeature.IsEnabled` followed by the dictionary Values getter before the
feature guard, then the same ordered enumeration, null handling and short-circuit result. Do not
introduce a snapshot or a covariance prerequisite merely to retain this unnecessary boundary.

Diagnostic r27 compiles the remaining owner with zero warnings/errors, retaining all real
constructor chains but stubbing exactly the override-copy and emission-thread methods. The moved
SoA loop uses one concrete enumerator with try/finally disposal, and the owner preserves the original
empty SystemsReport initialization through a private N# helper to resolve the property/type name
collision. This narrows known dependencies; it is not complete-owner acceptance. The Count native
estate subsequently executes 10/10 tests in `readonly-dictionary-count-seed/native-full-r2.json`.

Final copy-fixture evidence is `readonly-dictionary-count-seed/native-full-r6.json` (10/10) and
`native-count-method-il-final-r6.txt`. The original N# foreach emitted disposal only on normal exit;
the accepted replacement explicitly converts to `IEnumerable<KeyValuePair<string,string>>`,
acquires once, and wraps MoveNext/Current/copy in try/finally with null-safe IDisposable cleanup.
Root verified three inherited Count calls before acquisition, Key then Value before array writes,
and a real finally handler; all 8 native types/41 methods verify. Apply that exact behavior to the
production owner. The compiler candidate's 1,231 types/10,851 methods also verify; these focused
results do not replace the combined prerequisite/owner integration checkpoint.

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
