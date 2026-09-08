# Complete MultiFileCompiler ownership

The production owner is `NSharpLang.Compiler.MultiFileCompiler` in BootstrapServices.
`51fded82` deletes the entire 663-line C# class and replaces its constructors, state and connected
compilation methods in N#. Existing compiler, CLI and IDE callers use ordinary assembly references;
there is no C# facade, decision callback or fallback implementation.

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

Integration acceptance remains pending. The first fresh IDE-enabled gate recorded canonical formatting
failures in the new owner and canonical file; formatter corrections, final gate, installed SDK proof and
visual unsaved-buffer verification must finish before this area is accepted and pushed. The next compiler
owner is the complete CompilationReferenceResolver; broader CLI/editor initiatives remain separate.
