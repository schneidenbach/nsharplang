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

## Accepted area: complete MultiFileCompiler

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

The mixed-test audit also found one missing owner-pipeline assertion: carry the exact `countChars`
string-foreach fixture from `CheckCommand_AotVerificationRequiresColumnarWhenColumnarDeclines`
into N# coverage with `AotMode=true`. Use the validation-enabled route so emit-only diagnostic
precedence does not hide the AOT decision. Assert compilation failure, the required-AOT diagnostic,
null result path and no emitted file; an emission decline may already have created the output directory.

Direct production callers should resolve through existing project references. Surrounding CLI,
Playground and editor policy stays in the separate backlog. Compiler reference/metadata decisions
remain in scope wherever they live; do not exclude them by directory or by calling them transport.
This owner affects IDE analysis: finish the IDE-enabled gate, extension reinstall and visual
unsaved-buffer verification before accepting it. Astra reviews, retires the two audit rows,
integrates, verifies and pushes; Sol Max or Terra Max implements the complete bounded owner/tests.

Source audit: `/private/tmp/nsharp-multifile-assessment/current-boundary-20260908.md`.

### Proven constructor-chain prerequisite (focused integration complete; seed pending)

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

### Proven inherited collection Count prerequisite (focused integration complete; seed pending)

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

### Proven emission-thread delegate prerequisite (focused integration complete; seed pending)

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

The complete delegate/capture prerequisite is reviewed at worker commit `d1f8ec8dc`: exact ThreadStart
semantic and emission support, a nested private display holding the lexical receiver, and direct private
method calls with captured arguments. Native ThreadStart/Action/Func execution preserves worker
exception identity through Capture, Join and Throw. Five canonical tests, ten lambda-placement tests
and 45 reflection/emit tests pass; unfiltered IL verification passes all 1,231 compiler types / 10,851
methods and 45 native types / 238 methods. The real generic-owner regression uses the production
compiler harness; unsupported generic captures decline before invalid IL can be emitted. Identical
installed-baseline probes preserve the nested-lambda, field and static capture decline traces.
Receipt: `/private/tmp/nsharp-multifile-owner-20260908/threadstart-prerequisite/final-receipt-r1.json`.
The private combined-owner build and required seed/integration checks remain outstanding.

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

The Count implementation and its canonical/native assertions are integrated in `9dedb3c76`.
The final owner source now contains that exact exception-safe copy behavior. A private candidate
built from the combined Count and constructor production sources compiles the complete, stub-free
owner through all four constructor chains and the copy method, then declines at the emission-thread
lambda on line 566. This proves the next dependency, not successful owner emission. The candidate
passes unfiltered IL verification (1,231 types / 10,857 methods) and contains no NSharpTests types.
Receipt: `/private/tmp/nsharp-multifile-owner-20260908/count-constructor-combined-r1/final-receipt-r2.json`.

The constructor prerequisite now includes the reviewed correction that uses the existing exact-base
identity resolver for both selected and default constructor targets. Focused verification executes
16 canonical and 190 native tests, including failure before IL, ordered argument evaluation,
exceptions, self-exclusion and closed-generic rebinding. The corrected private candidate passes
unfiltered IL verification. Evidence is under
`/private/tmp/nsharp-constructor-chain-expressions-20260908/implementation`: `followup-canonical-r8.trx`,
`followup-native-columnar-r1.json`, `followup-ilverify-r3.log` and `final-source-r3.sha256`.
The combined Count/constructor candidate above predates that correction and is provisional.
Thread work includes the actual
mixed capture of the compiler instance and per-invocation state, private helper access, and exception
dispatch after Join. Complete these connected prerequisites, then integrate the owner and its frozen
canonical migration; do not resume unrelated backlog tasks or publish this provisional candidate.

## Selected area: complete CompilationReferenceResolver

Prerequisite integration checkpoint: `9dedb3c76`, `caf5d1fff` and `cfbc80bfe` are verified through
the fresh IDE-enabled gate, extension reinstall and visual thread-capture inspection, and installed
SDK self-host with 7,976 canonical assertions. Installed focused suites pass 10 dictionary, 45
reflection, 10 lambda and 190 columnar tests; all-method BSS IL verification passes 1,231 types and
10,859 methods. Both feeds and the restored SDK cache match the published seed. Receipt:
`/private/tmp/nsharp-multifile-assessment/prerequisite-installed-verification/final-receipt.json`.
This supersedes the provisional prerequisite status above. MultiFileCompiler is now accepted in
`51fded82`, `a32bfdb9`, `2813fd92` and final formatting `7a3579e5`. The fresh IDE-enabled gate passes
511 C# /7,985 N# /54 native-project entries /36 VS Code /12 throughput /68 IL assemblies. Installed
SDK self-host executes 7,985 canonicals; native194/query76, metadata and unfiltered IL pass. Real
unsaved-buffer diagnostics and cross-file definition navigation are visually verified after reinstall.
[Complete acceptance](../systems-language-closeout/decodes/2026-09-08-complete-multifile-compiler-ownership.md).
The source-probe history above is retained evidence, not remaining prerequisite work.

The entire `src/NSharpLang.Cli/CompilationReferenceResolver.cs` owner is deleted in `a641613ed`:
497 lines, 19 original methods and its shared two-minute `HttpClient` move into the complete N# class.
`3f880c86a` integrates seven direct and four command-level N# canonicals; root command tests pass
48/48. Source/IL review and exact frozen fixtures are recorded in
`/private/tmp/nsharp-compilation-reference-resolver-owner-20260908/final-owner-implementation-receipt-r2.json`
and `reference-resolver-tests/final-receipt-r1.json` in that directory. The fresh combined gate and
installed complete-owner verification now pass at `a20dc98af`: 7,999 self-host canonicals, installed
native47/196/76/4/82, unfiltered IL and package identity.
[Complete acceptance](../systems-language-closeout/decodes/2026-09-08-complete-reference-resolver-ownership.md).
Its recursive project builds, package cache lifecycle,
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

Include the exact two-project AOT-decline fixture from
`CheckCommand_AotProjectReferenceRequiresColumnarWhenColumnarDeclines`: options propagation into
the child compiler, failure diagnostics, output suppression and active-project-stack cleanup are
reference-resolution assertions. This does not expand the separate NativeAOT initiative.

### Proven resolver HTTP timeout prerequisite

The initial complete proposed resolver failed parsing in full-source runs r1–r3; C# iterator
spelling and nullable-array construction were corrected. The one-use iterator loop moved into its
caller with the original ordered existence checks. A separate reduction
from the actual private client initializer reaches `client.Timeout = TimeSpan.FromMinutes(2)` and
fails emission. The faithful direct-setter variant also fails at
`emit.call.instance-member-unmodeled: HttpClient.set_Timeout/1`, while FromMinutes resolves.
Evidence: `/private/tmp/nsharp-compilation-reference-resolver-owner-20260908`, especially
`reduction-field-r1.log` and `reduction-timeout-direct-setter-r1.log` with their proposed source.

Exact HttpClient.Timeout writable-property admission is integrated in `502a5de69`, entirely in N#.
The canonical admission control passed 1/1 and the native reflection family passed 47/47, including
receiver identity, receiver-before-value ordering and CLR setter failure/prior-value preservation.
No getter or broader external-property admission was added. A private SDK candidate compiles the
real assignment in the frozen complete proposed owner (SHA `0f31efcc85e7ebf4d49e722ab9509741d717c52831fec6cf794eafa9ee460650`),
then declines at the later CompileToIlAssembly call. Receipt:
`/private/tmp/nsharp-compilation-reference-resolver-owner-20260908/httpclient-timeout-prerequisite/final-receipt-r1.json`.
The complete proposed owner subsequently emits after faithful N# spelling and cleanup-helper
corrections; Timeout is the only new compiler capability required. The prerequisite seed at
`277ea2991` is accepted: a fresh backend gate passed in 548 seconds (511 C# tests, 7,992 N#
canonicals, 53 native projects, 12 throughput cells and 68 IL assemblies). The first gate's sole
failure was stale audit rows for the accepted pipeline/visibility assertion deletions; exactly two
rows shrank, with all 379 other rows and epoch facts preserved, and the fresh audit passed 18/18.
Official setup and ordinary installed clean/restore/self-host passed 7,992/7,992 without overrides.
Installed native families passed 47/196/76; unfiltered BSS 1,234 types/10,901 methods and Compiler
5/58 pass IL verification. Both four-package feeds, ten Release payloads, twelve cache files and
installed compiler payloads match; production contains no NSharpTests classes. SDK SHA256
`f81c86c52824c5e03451e55913666c0520db6cd5ab4fe1d5a4eeb34e6dca4b71`.
Evidence: `/private/tmp/nsharp-resolver-seed-20260908/installed-verification/final-receipt.json`
(SHA `ed307a5b76a3a0f5677572dcdce1eeaf99ce43045db2747dbe5833888ae8178c`).
This accepts the prerequisite seed and preceding pipeline/visibility integration, not complete
resolver ownership: final canonical acceptance, production integration and push remain open.

## Connected follow-on: SDK reference assembly ownership

The source audit at `27b1a8a1b` disproves the broad mechanical label on
`src/NSharpLang.Build.Tasks/EmitIlAssembly.cs`. Its reference selection, ordered owner scan,
recursive nested-type traversal, AssemblyRef reuse, scope mutation, write and cleanup still run in
C#. The connected ten-method group must move with its helpers/state. Prefer the complete existing
303-line task class, including its twelve methods and public MSBuild metadata, when actual proposed
N# source proves the required external APIs and inheritance. Any surviving task boundary must only
transport MSBuild inputs/results through direct N# calls; add no C# helper, callback or fallback.

Reuse the existing Cecil post-pass and N# ReferenceTypeOwners/SdkEmitTaskKernels. This is compiler
reference/metadata ownership, not a new metadata-writer objective. Necessary MSBuild/Cecil dependency
and package changes must be verified through ordinary installed SDK builds and self-hosting before
seed publication. Preserve accepted kernel and C# consumer ABI coverage; add real N# traversal,
mutation, identity and failure controls where the current predicate tests leave gaps.

Reviewed source boundary and hashes:
`/private/tmp/nsharp-sdk-reference-ownership-assessment/current-boundary-20260908.md` and its
`source-manifest-20260908.json`. With resolver implementation and canonicals integrated, the complete
task is delegated in an isolated worktree. Actual full N# source compilation, not hypothetical API
limitations, determines prerequisites; the existing Cecil writer remains the implementation.

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

The subsequent CompilationBackend/CodeIntelligence assertion audit is
`/private/tmp/nsharp-multifile-assessment/compilation-backend-code-intelligence-assertion-boundary-20260908.md`.
Its exact ordinary non-AOT CountChars emission decline and strict-lint NL001 blocking-emission gaps
are integrated in `a685037ef`. Two N# public-pipeline cases replace six C# compiler clauses; existing
command exit/banner observations remain. Original source/project bytes were independently checked,
both new cases passed individually, CompilationBackendTests passed 21/21, and the formatted native
columnar project passed 196/196 with no failures or skips. Evidence:
`/private/tmp/nsharp-mfc-pipeline-canonical-gaps-20260908/root-review-r1.json`,
`fixture-byte-identity-r2.json`, `dev-compilation-backend-r1.log`, and
`native-columnar-full-r2.log` in that directory. The fresh combined checkpoint at `277ea2991`
and installed seed verification above now cover this migration; push remains open. Complete
project/NuGet and child-AOT assertions move with the selected reference resolver. The ambient Turkish
culture formatting assertion is separately scoped presentation/runtime coverage, not compiler debt.

The three-file CLI/fix audit is
`/private/tmp/nsharp-multifile-assessment/cli-fix-csharp-assertion-boundary-20260908.md`.
Its compiler-relevant gaps include the exact six-case package/namespace visibility group, the stronger
malformed-source diagnostic bound (`undefinedFromCli`, at most four), and strict-lint diagnostic
aggregation on otherwise valid source. Preserve these exact fixtures in N# before deleting their
C# compiler clauses. The complete six-case visibility group is integrated in `a7c508f73`: six N#
cases replace seventeen C# compiler assertions. All twenty fixture writes are byte-identical;
the two positive cases verify successful public IL compilation as well as clean analysis. Focused
N# tests passed 6/6, CliCommandTests passed 52/52, and the exact six CLI cases passed 6/6. Original
CLI envelope checks remain. Reviewed evidence:
`/private/tmp/nsharp-mfc-visibility-canonicals-20260908/final-receipt.json` and
`root-review-r1.json` in that directory. Combined integration and installed verification at
`277ea2991` are accepted above; push remains open.

The complete compiler-bearing diagnostic group in LanguageServerDiagnosticsTests is integrated:
82 methods moved to N# with their required harness, exact source fixtures, diagnostics, spans and
connected LSP observations. The final parser and recovery/linter commits are `6c83e9d1a` and
`ee1300416`; root native verification passes 82/82. The ten retained C# methods construct synthetic
diagnostics and test only LSP range/severity/code transport (nine Converter_* methods and
LspLinterDiagnostic_UsesExactLinterSpan). No production or IDE behavior changed.
Exact fixture, source-hash and assertion reviews are under
`/private/tmp/nsharp-lsp-diagnostic-canonicals-20260908`, including
`root-parser-diagnostics-review-r1.json` and `root-recovery-linter-review-r1.json`.

The next connected canonical area is compiler-bearing diagnostics/binding in
LanguageServerWorkspaceDiagnosticsTests, LanguageServerTests and LanguageServerAutoImportTests.
Inspect complete methods and migrate actual compiler assertions with necessary state and harness;
keep pure editor publication/open-close/completion/auto-import policy in the separate backlog.
The six workspace/import methods are now integrated in `6d046bef2`; root diagnostics pass88/88.
The reviewed CLI/check/SDK compiler assertions are integrated in `aa841ec15`; root query tests
pass78/78, preserving the accepted malformed fixture and adding two exact missing cases. CLI
cluster/filter/envelope/text policy assertions remain separately owned. These follow the published
resolver checkpoint and await the next combined integration gate.
Preserve exact source/project bytes and failure behavior; existing similar cases do not prove parity.

The remaining CLI parity compiler diagnostic clauses are integrated in `c5144b9ea` and `69f0797fa`.
Review required an exact N# lint successor: one matching NL001 from the original `func Main` /
`value := 42` source, with the original source snippet projected from its actual diagnostic location.
The earlier existence-only and synthetic projection tests were insufficient. The successor passes1/1,
retained CLI tests53/53, and the lowered single-row ownership audit18/18. Command envelopes remain
separate policy. Evidence: `/private/tmp/nsharp-cli-parity-diagnostic-cleanup-20260908`.
These commits still require the next fresh combined integration checkpoint before push.

The audit's broader "compiler-service" label is not the active scope: JSON root-key/value envelopes,
LintToJson formatting, fix serialization/application policy, and query/editor presentation belong in
BRANCH-BACKLOG.md. Do not add those as compiler completion conditions merely because their N# owners
live in BootstrapServices. Binding/visibility and compiler diagnostic assertions remain in scope
regardless of the C# test filename or command that transports them.

The two-file assertion crosswalk is
`/private/tmp/nsharp-multifile-assessment/check-il-sdk-canonical-crosswalk-20260908.md`.
Its equivalent N# coverage supports removing redundant C# compiler clauses; it does not authorize
leaving those canonical assertions C#-owned. Preserve only the distinct mechanical or separately
tracked CLI/SDK observations when narrowing mixed tests.

Delete every zero-consumer legacy C# owner and superseded C# assertion. Classify only genuine
pre-existing mechanical ecosystem boundaries, proving that none contains product decisions and
none grew during the closeout.

Run the complete canonical compiler estate, compiler tests and required integration checks under
AGENTS.md, including examples, templates, interop, ILVerify and the ownership audit. Use a fresh
backend product gate for backend-only work; retain the VS Code-enabled gate, extension reinstall
and visual verification for IDE-affecting changes. Repin only when required by a verified seed change.
Update present-tense architecture documentation and the queue ledger. Leave
a clean committed tree with no partial compiler stages.
