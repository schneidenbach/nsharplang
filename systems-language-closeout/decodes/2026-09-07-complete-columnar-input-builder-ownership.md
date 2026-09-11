# Complete columnar input-builder ownership

The complete 17-method ColumnarProgramInputBuilder is implemented in N# and its 1,033-line C#
class is deleted. Production MultiFileCompiler binds its existing call directly to BootstrapServices.
The public sealed type and public static TryBuildMultiFile entry are the mechanical cross-assembly
boundary. Its constructor and all sixteen helper methods are private; no C# wrapper, callback or
fallback remains. Commits: owner c2379140a, canonical migration 7f747d76a, prerequisite 2ea07788e.

The replacement retains declaration-family ordering, token/node sentinel trimming and independent
array copies, null versus empty state, partial function outputs, nested local functions, native
signature materialization, and source-file trace set/clear in finally. Eight existing canonical
reflection callers now target BootstrapServices; emitter tests continue to inspect the emitter.
Four native controls cover trim/copy isolation, multi-file materialization/source identities,
single-source null Tests and later-file failure/trace cleanup.

Actual proposed N# compilation established two prerequisites: the exact Array.Empty<int> binding
and explicit constructor visibility propagation through existing N# parser/input/declaration owners.
Array.Fill and both Array.Copy overloads already work with faithful source spelling. No new C#
behavior or tests were added. Existing constructor-input ABI and default-public declaration overload
remain compatible with bootstrap consumers. A rejected first-generation candidate emitted invalid
field stores through out-argument addresses; local aliases preserve the original assignment timing
and partial state while producing verified IL. Rejected binaries and zero-match runs are not evidence.

Focused evidence: dev 12/12; columnar native 126/126; reflection native 39/39; parser visibility 2/2;
Array.Empty binding 9/9 and native 1/1; ownership audit 18/18. Final worker owner IL verification
covers all 18 methods; the corrected compiler/owner pair also passed selected IL verification.
Exactly one ratchet row retired, 380 other rows and all epochs unchanged;
head-v1:c15834f9d1324493. Evidence: /private/tmp/nsharp-columnar-input-builder-owner-20260907.

Fresh backend gate at d3e6fb20131fd909a41086955649f1b62ac6a689 passes in 480 seconds:
574 unit tests, 7,943 N# canonical tests, 53 native projects, 12 throughput checks and 68 IL assemblies.
Official setup succeeds; the ordinary installed-package probe passes 15/15, including direct invocation
of the packaged N# owner and absence of the old C# type. Both feeds hold the same four packages,
ten Release payloads and twelve loaded cache files match. SDK SHA256:
eae880bee83e67cd6613b544f4d77d28e80ca309339cb12884449a891a2ba979.
The installed SDK freshly emits and passes 7,943/7,943 canonical tests without SDK-path overrides.
The production SDK contains no NSharpTests types. Final gate and SDK receipts are in the evidence
folder above. Changes after the tested revision are acceptance documentation only.
The work changes emitter input materialization and CLR constructor visibility; it adds no IDE path
or editor behavior. Backend verification follows AGENTS.md. Compiler-wide ownership remains open:
MultiFileCompiler and ColumnarIlEmitter still contain C# compiler behavior. CLI/editor features,
runtime reimplementation, NativeAOT and independent writer work remain in the separate branch backlog.
