# Complete MultiFileCompiler ownership

The production owner is `NSharpLang.Compiler.MultiFileCompiler` in BootstrapServices.
`51fded82` deletes the entire 663-line C# class and replaces its constructors, state and connected
compilation methods in N#. Existing compiler, CLI and IDE callers use ordinary assembly references;
there is no C# facade, decision callback or fallback implementation.

The surviving compiler-service boundary is the three `CodeIntelligenceService.LoadProject` overloads:
they call the N# configuration parser and compiler, then copy nine existing properties into the N#
ProjectSnapshot. They contain no analysis or emission decisions. Its other query methods forward to
N# query owners. CompletionEngine, FixApplicator and OutputFormatter retain separately scoped editor,
fix-command and CLI presentation workflows; they are not compiler fallbacks. The four-file source and
caller audit is `/private/tmp/nsharp-multifile-assessment/code-intelligence-csharp-boundary-20260908.md`.

The owner retains source discovery and overrides, preprocessing, parsing, shared analysis lifetime,
import-cycle diagnostics, lint and systems analysis, reference handling, emission and output writes.
The former sole-caller `CompilationUnitFacts.RequiresColumnarSoaEmission` loop moves with its caller
and is deleted from the old location. The emission worker preserves stack size, background/name
configuration, Start/Join ordering and ExceptionDispatchInfo rethrow behavior.

Source override copying acquires one enumerator after the original Count reads and disposes it on
normal and exceptional exits. Constructor argument evaluation, live property views, repeated-call
state, diagnostic limits and failure timing remain part of the ownership contract. In particular,
emission failure may create the output directory, while validation failure precedes its creation.

The public class remains nonsealed with four public constructors, one private constructor and the
existing property surface. Thread state is a private nested type. A compile-time SystemsReport alias
resolves the existing property/type name collision without emitting another CLR type. The rejected
candidate with public top-level helper types was never accepted as the production owner.

`a32bfdb9` removes all ten cases in `ErrorRecoveryPipelineTests.cs`: nine execute as canonical N#
compiler tests, and the query case executes in the existing native query integration suite. Original
fixture bytes and diagnostic assertions are retained. Seven native owner lookups name BootstrapServices.
Additional N# controls exercise public/private metadata, live state, validation/output failure and the
actual AotMode string-foreach decline. AOT compiler behavior is covered without expanding NativeAOT work.

Focused evidence is bound by
`/private/tmp/nsharp-multifile-compiler-tests-20260908/final-owner-proof/final-focused-receipt-r1.json`.
The nine canonicals pass; native columnar/query suites pass 194/76, and the six other affected suites
pass 91 tests. Root ordinary `./scripts/dev.sh Columnar` passes five tests. Unfiltered candidate IL
verification covers 1,234 BootstrapServices types / 10,901 methods and five Compiler types / 58 methods.
`2813fd92` retires only the two deleted C# paths in the ratchet; all epochs remain fixed and audit18/18
passes at `head-v1:264c13f988214d1a`.

The formatter corrections in `7a3579e5` preserve all bodies and literals. AST comparison finds only
removal of redundant public modifiers on two default-public methods; the formatted native estate
passes 194/194, including public/private metadata. Final owner SHA-256 is
`84502f38c3389c64841adb5ca0a094afb9b09ad3b08218dc28f7f9aea678f0fc`; canonical source SHA-256 is
`85262edadfd590a00234167a1c2eaa6fe3f0de50550cde7180d34a79b629e9fc`.

The extension was rebuilt and reinstalled from that source. Real VS Code verification displayed a
new semantic diagnostic in an unsaved buffer, retained the other file's syntax diagnostics, and
navigated F12 across files despite the parse error. Disk hashes stayed unchanged during the unsaved
proof; reverting the buffer removed its diagnostic. Receipt and screenshots are under
`/private/tmp/nsharp-multifile-assessment/full-owner-ide-visual-receipt-r1.json`.

Fresh gate r1 failed formatting; r2 passed correctness,
formatting and IDE stages but failed throughput under load. A quiet focused rerun passes all 12
throughput cells at 1.00–1.06x baseline without changing thresholds. Neither failed gate is accepted.
Fresh gate r3 passes all stages in 625 seconds: 511 C# tests, 7,985 N# canonicals, 54 native-project
entries, 36 VS Code tests, 12 throughput cells and 68 IL assemblies. Installed SDK proof passes: a clean ordinary SDK self-host executes all
7,985 canonicals, and installed native columnar/query suites pass 194/76. Both feeds, ten Release
payloads and twelve SDK-cache files match. The installed production payload equals the packaged SDK;
unfiltered BSS 1,234/10,901 and Compiler 5/58 IL verification passes. SDK SHA-256 is
`705b8c9625689e1ccd6e6326c3b427a1c41b73b530192fbb71caad8f066cfb17`.
Final receipt: `/private/tmp/nsharp-multifile-assessment/full-owner-installed-verification/final-receipt.json`
(SHA-256 `b8a97ee24a7c9a7f48c16b30ed0ac2de662b4d5e957445901721978a602b347e`).
This complete ownership area is accepted; compiler-wide ownership remains open. Logs are
`/private/tmp/nsharp-multifile-assessment/full-owner-integration-gate-r{1,2,3}.log` and
`full-owner-throughput-quiet-r2.log`. The next compiler owner is the complete
CompilationReferenceResolver; broader CLI/editor initiatives remain separate.
