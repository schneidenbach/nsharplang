# Metadata-native writer and one metadata universe

> **Status (2026-10-14):** proposed plan. The owner chose option 2 of the emitter design fork in
> [full-compiler-nativeaot.md](full-compiler-nativeaot.md): a metadata-native writer on `MetadataBuilder`/`ManagedPEBuilder`
> plus one metadata type universe. The owner decisions listed in
> [metadata-native-writer-work-packages.md](metadata-native-writer-work-packages.md#owner-decisions) are still pending; the
> plan's recommended defaults are marked there. Execution starts with wave 1 once they are confirmed.
> Produced by a planning workflow (6 parallel readers, 3 competing designs, 9 judges, synthesis, 3 critics,
> revision) against `f6a6751bb`.


**Status:** Owner decision recorded (design fork option 2). This program plan was synthesized from three ranked designs and nine judge verdicts, then revised against two critic rounds. This revision closes the 38 round-3 gaps; §2b lists each gap with its resolution.

**Base and drift:** Counts and line numbers are verified at origin/systems-language f6a6751bb unless marked otherwise. Mainline has since moved to 9818469cf (f6a6751bb + 30 commits): async-iterator-cancellation (5 commits, through c1d37d677) and 25 iterator-unification commits (6c4816244..9818469cf) landed on 2026-10-13.

| File this plan cites | Lines at f6a6751bb | Lines at 9818469cf |
|---|---|---|
| ColumnarIlEmitter.nl | 32,148 | 32,153 |
| ColumnarMethodBodyPlanner.nl | 1,219 | 2,379 |
| ColumnarIteratorPlanner.nl | 7,320 | 7,751 |
| ColumnarIteratorRealization.nl | 1,210 | 1,222 |

W1.1 re-measures every count at the wave-1 base tag. census/merge a7017b423 is an ancestor of f6a6751bb: 72 commits behind it and 102 behind 9818469cf.

**Decision:**
- PersistedAssemblyBuilder and the rest of Reflection.Emit are replaced by an N#-owned writer on System.Reflection.Metadata (MetadataBuilder, BlobBuilder, MetadataRootBuilder, ManagedPEBuilder, PortablePdbBuilder). The Reflection.Emit types being replaced are PAB, TypeBuilder, MethodBuilder, FieldBuilder, ConstructorBuilder, GenericTypeParameterBuilder, EnumBuilder, ParameterBuilder, CustomAttributeBuilder, ILGenerator and LocalBuilder. This is Roslyn's pattern: definitions are buffered, and rows and tokens are numbered at serialization.
- The writer consumes ONE immutable metadata model covering source, synthesized and reference types.
- End state:
  - no runtime System.Type for user or reference types;
  - no MetadataLoadContext, no Mono.Cecil;
  - no executable Assembly.Load*/AppDomain inventory in the compiler;
  - emitted test code runs out of process;
  - one NativeAOT nlc runs check/build/test on all 21 example roots with JIT/R2R/AOT parity.
- No fallbacks and no duplicate owners. All new code is N#. The permanent C# boundaries (Runtime, Playground.Wasm, Cli/Program.cs) do not grow.

## 1. Measured starting point (verified at f6a6751bb)

**Writer**
- ColumnarIlEmitter.nl: 32,148 lines, one sealed class at :31.
- The writer is TryEmitColumnarAssemblyPass (:4746-7756). Its tail (:7686-7753) does GenerateMetadata, then the modreq repair, then MetadataRootBuilder (validation on), then an 11-argument ManagedPEBuilder (strong-name size 128, entry point from MethodBuilder.MetadataToken), then ColumnarDeterministicPeIdentity.Apply.
- PAB core assembly = typeof(object).Assembly (:4778-4781). Emitted BCL references are therefore scoped to System.Private.CoreLib. The Cecil post-pass (ColumnarReferenceAssemblyWriter.nl, 923 lines; SdkEmitTaskKernels.nl:145-246) rescopes references only in the reference assembly.
- Emitter shape:
  - ColumnarIlEmitter declares 76 private fields (44 `private readonly`) and 632 private functions (493 instance, 139 static).
  - Its only non-private function is TryEmitColumnarAssembly (:4742).
  - Emit has 7 production files.
  - src/ contains no production extension function. The only extension functions are in examples/07-interfaces/ExtensionMethods.nl and in test source strings.

**Reflection.Emit and metadata API usage (non-test)**

| Item | Count |
|---|---|
| Files importing System.Reflection.Emit | 81 (71 Plan, 7 Emit, 3 Model) |
| `OpCodes.` lines | 1,749 |
| `.Emit(` lines | 1,428 in Emit, 176 in Plan |
| TypeBuilder.GetMethod/GetField/GetConstructor | 99 lines in 24 files |
| `is TypeBuilder` | 105 |
| IsSafeSzArrayType | 109 lines |
| NotSupported/NotImplemented catches | 101 lines |
| Files using MetadataLoadContext | 62 (7 in Plan) |
| JsonSerializer reflection envelopes | 42 in Driver (13 files) |
| SetCustomAttribute call lines | 30 in 9 files |

TypeBuilder is also named outside Plan and Emit:
- Core: AnalyzerWriteTargets.nl IsTypeBuilder (13 lines), plus 4 other analyzer files.
- CodeIntel: CompletionReflectionFacts.nl.
- Model: ColumnarTypeEquivalenceFacts, RuntimeTypeShapeFacts (EnumBuilder probe :46) and TypeInfoIdentityFacts.

Driver/ColumnarReferenceAssemblyWriter.nl uses Cecil, not Reflection.Emit.

**Workarounds that exist only because of PAB**
- ColumnarModifiedMemberReferenceRepair.nl (1,647 lines), with a second full emission at :7735-7741. Its ledger appears in 12 files (`ModifiedMemberReference`: 88 occurrences).
- ColumnarDeterministicPeIdentity.nl (303 lines). It is a byte patch that is valid only because no debug directory exists (its header :20-26).
- The Cecil reference-assembly writer.
- Modifier route-arounds outside the repair (the "MemberRef drops required modifiers" limitation):
  - The decline `emit.member-assignment.unreferenceable-setter` (ColumnarIlEmitter.nl:10303-10316), driven by SetterSignatureSurvivesAMemberRef (:13184-13199). A second copy (ColumnarConstructionPlanner.nl:990-1001) only feeds the repair ledger at :961-970.
  - Ledger record sites: ColumnarIlEmitter.nl:15617-15630, :18053, :25766.
  - TryFindInitAutoPropertyBackingField (:1449-1469; uses at :10360, :10607).
  - ColumnarSourceSelfInstantiation.BindSetter's init special case (:55-73).
  - ColumnarForeachLoopPlanner.IsReferenceablePattern/HasRequiredModifiers (:363-383).
  - ColumnarReadOnlySpanElementRead (:454-500; uses at :393 and ColumnarIlEmitter.nl:14945).
  - Ratchet baselines: SurvivesAMemberRef 7 occurrences in 2 files; ReadOnlySpanElementRead 7/2; IsReferenceablePattern 3/2; HasRequiredModifiers 4/1; TryFindInitAutoPropertyBackingField 3/1.
- Not route-arounds:
  - IsInitOnlySetter (ColumnarIlEmitter.nl:13171, :13203) and AnalyzerWriteTargets.PropertySetterIsInitOnly (:811-825) state the language rule that an init accessor is not an assignment target outside construction.
  - ColumnarExternalInterfaceMethodResolver (16 lines) and ColumnarIteratorMemberResolver (6) copy modifier chains into override signatures.
  - GetRequiredCustomModifiers: 16 non-test lines in 6 files; with GetOptionalCustomModifiers, 27 lines in 6 files.
- Object-initializer init setters on external and constructed-generic types are NOT refused today. They are repaired through the ledger.

**Pseudo-custom attributes**
- [MethodImpl] is the only pseudo attribute N# lowers itself: ColumnarSourceAttributeBinder.TryPlan :68-74 routes it to ColumnarMethodImplAttributes.
- Flush (:646-698) hands every other bound attribute to SetCustomAttribute on type, method, parameter, field, property and constructor targets. PAB's builders turn pseudo attributes into flags and table rows there. PAB's per-target list is documented runtime behaviour that was not re-read locally (UNVERIFIED); W2.3 measures it.
- Native imports ([LibraryImport] and the [DllImport] spelling, NativeImportSignatureFacts.nl:46) never reach SetCustomAttribute. They are planned as ColumnarPInvokeDeclaration and defined with DefinePInvokeMethod (ColumnarIlEmitter.nl:5548-5597). Their parameter attributes are still flushed.
- Corpus coverage: one application, tests/native/census-parse-shapes/MemberDeclarationOrder.tests.nl:23 `[StructLayout(LayoutKind.Sequential)]`.

**Constants.** SetConstant receives the literal's own CLR type at 11 sites:
- ColumnarParameterDefaultEmitter.TrySetParameterDefault (:188-235), 7 sites: int literal at :210, null at :196, enum as int at :231, string enum at :226;
- ColumnarFieldMetadataEmitter.nl:16;
- ColumnarIlEmitter.nl:4822 (string-enum literals), :4859 (enum literals) and :6423 (union case tags).

**Host-scope types**
- The binder returns types from host scopes as well as MLC:
  - ExternalAssemblyScan.TryLoadHostAssemblyByName (:469);
  - LoadedAcrossContexts (:485-487, AppDomain);
  - RuntimeAssembliesInScope (:506-530);
  - their consumers: ColumnarCompilerReferenceResolver.nl:31, :68, :173.
- Host typeofs flow into emitted operands:
  - ColumnarIlEmitter.nl:14716-14717 and :26310-26319 (YamlDotNet IParser/IEmitter);
  - ColumnarRuntimeInstanceMemberResolver.nl:1224, :1248 (MSBuild, Cecil);
  - ColumnarExternalBindingPlans.nl:1289-1296 (ITaskItem AQN);
  - ColumnarTypeOfPlanner.nl:653, :1152 (Cecil).
- Host-catalog references in Plan and Emit, across 19 files: ExternalAssemblyScan 44 occurrences (28 of them HasExactTypeIdentity), RequiredRuntimeTypes 28, SharedReferenceMetadata 12, WellKnownTypeCatalog 9.

**Seed and SDK route**
- What the seed admits:
  - The closed allow-list (ColumnarExternalBindingPlans.nl:187-199) names the SRM writer classes and the handle structs. Enums bind with no row.
  - Seed-compiled source already spells PEReader, MetadataReader, the TypeDefinition and ExportedType rows, GetBlobBytes, HandleKind, TableIndex and MetadataTokens (ExternalAssemblyScan.nl:222-231, :1753-1767; ReferenceImageSnapshotStore.nl:166-188; ColumnarModifiedMemberReferenceRepair.nl:271, :381, :441).
  - UNVERIFIED: BlobReader, SignatureHeader, ImmutableArray<T>, PortablePdbBuilder, DebugDirectoryBuilder, BlobContentId and the id-provider delegate shapes.
- Versions:
  - The seed is version 0.1.0, which is also the dev SDK's version (NSharpLang.Sdk.csproj:6).
  - All 41 global.json SDK pins say 0.1.0; 12 of them are in src/.
  - verify-bootstrap.py reads the SDK version from Core's global.json and hard-codes NSharpLang.Runtime.0.1.0.nupkg (:10-11).
- MLC requirements:
  - verify-bootstrap.py requires MLC in the seed SDK (:25).
  - verify-release.py requires MLC in releases (:20) and fixes the release package set (:8-11).
  - CI runs verify-bootstrap at build.yml:40/115/177/342, publish.yml:24 and deploy-website.yml:48.
- NuGet.config:4 maps the `nsharp-bootstrap` source to the checkout's own `bootstrap/`. An alternate NSHARP_RESEED_BOOTSTRAP_DIR therefore only works through STOP_AFTER=verify; after that, reseed_verify_restored_packages (reseed.sh:110-155) refuses the restored cache.
- Per-step gate caches (test-all-core.sh:204, COMMON) cover src/ but not bootstrap/.
- The compiler is built by the SEED's Sdk.targets and Sdk.props:
  - Sdk.targets:15 compiles 8 named projects emit-only;
  - Sdk.targets:201 lists the tool DLLs as EmitNSharpIlAssembly Inputs;
  - Sdk.targets:202 Outputs are only the stamp and IntermediateAssembly;
  - Sdk.props:175 adds an implicit NSharpLang.Runtime reference to every project except Core, Plan and Emit.
- Hard-coded project lists:
  - reseed.sh:52-53;
  - scripts/lib/packages.sh:7-20;
  - verify-release.py:8-11;
  - test-all-core.sh: format list :326-337, SELF_HOST_PROJECTS :409-421, SELF_HOST_CEILINGS :646-658, BOOTSTRAP_TEST_PROJECTS :741-749, native_requires_serial_run :804-839;
  - dev.sh ESTATE_PROJECTS :94-102;
  - build.yml:57;
  - IncrementalCompilerIdentity.Describe (IncrementalBuildInputs.nl:262-275): 7 assemblies, which already omit Tooling and Compiler.dll;
  - 44 tests/native/*/project.yml files pin compiler DLLs by Cli/bin path;
  - build-native-prerequisites.sh:18-23 archives src/NSharpLang.Compiler.* and nothing named TestRunner.
- Contract tests that pin these lists, all in tests/native/gate-script-contracts:
  - SdkEmitStampPaths.tests.nl:110-148;
  - SelfHostFrontDoor.tests.nl:56-63 (11 projects, Model first);
  - DevScript.tests.nl;
  - CompilerPerformanceGate.tests.nl:11-27;
  - ReseedScripts.tests.nl;
  - IlVerifyBaseline.tests.nl.
- Ownership audit: every delivery file above has an exact-fingerprint row in non-nsharp-growth-ratchet.v2.json (439 rows). A new code file needs a new epoch (OwnershipAudit.nl:232-245).
- Counter goldens:
  - agent-loop-baseline.golden.json has 99 rows. For example, the small 'body test' cold row has referenceAssembliesLoaded 8 and processesSpawned 0.
  - bootstrap-build-baseline.golden.json pins the Core counters.
  - CompileTimeBench.nl:1553 refuses any difference.

**Long-lived caches keyed by reflection**
- Static fields: ColumnarCanonicalTypeResolver.nl:18, ColumnarIlEmitter.nl:144, RequiredRuntimeTypes.nl:27.
- ConditionalWeakTable caches: ReflectedMethodCache, AssemblyTypeNameIndex, ColumnarDefinitions, ColumnarSourceImplicitConversionResolver, ReferenceImageSnapshotStore.

**Test execution today**
- The daemon already runs tests in a separate worker process of the same CLI (TestWorkerHost, `__test-worker`). In-process `nlc test` loads the emitted assembly.
- The three in-process load sites are ReflectionTestRunner.nl:28, XunitTestRunner.nl:514 and NativeTestLoadContext.nl:27.

**Playground, reference sources and churn**
- The Playground only analyzes, through MultiFileCompiler.CompileForAnalysis. PlaygroundRunner is an AST interpreter. Its external assembly resolution is intentionally bounded, and no in-browser test harness exists.
- Neither ~/repos/roslyn (the path AGENTS.md names) nor any dotnet/runtime checkout exists on this machine.
- Churn over 30 days: 815 commits. 36 of them touched ColumnarIlEmitter.nl, 29 ExternalAssemblyScan.nl and 14 ColumnarIteratorPlanner.nl.

## 2. Judge fatal flaws and their fixes

| Flaw | Fix in this plan |
|---|---|
| Ref-asm retention rules paraphrased | W4.3 ports ColumnarReferenceAssemblyWriter verbatim, as acceptance rows: value types keep every field (:289-295); explicit implementations kept (:280-281); package-private types reachable from the surface kept, to a fixed point (:378-410); entry point retained (:165); `<`-named synthesized types dropped unless the closure names them; `ldnull; throw` bodies; ReferenceAssemblyAttribute; keepInternals; CoreLib-to-contract rescope. O1 compares the projector's output against Cecil's on the same implementation image before Cecil is deleted. |
| Determinism breaks once a PDB exists | One owner, DeterministicImageIdentity (the moved ColumnarDeterministicPeIdentity; renamed by W5.4). Order: PDB content id first (provider delegate if W1.4 proves `Func<IEnumerable<Blob>,BlobContentId>` is spellable, otherwise zero, hash and patch the #Pdb id), then the debug directory (CodeView = PDB id, PdbChecksum, Reproducible, embedded PDB compressed after its id is final), then the PE MVID and stamp last. Byte-identity rows across hosts. |
| Reference scope cut over before binding moved | Implementation scope never changes until W8.1. In phase 1 the catalog reads exactly the images MLC reads, plus the W2.6 transitional host-scope images, so writer scopes equal PAB's. The targeting-pack switch happens once, after MLC and host types are deleted (W7.2). A member absent from the contract is a hard located diagnostic, never a CoreLib fallback. |
| Trunk churn makes mechanical slices unrebaseable | W1.7 semantic codemods in N#, idempotent and re-applied at merge time; in-flight streams run `--check` as a merge gate. The emitter split happens in a declared freeze window of at most 72 hours, after a seam is proven end to end through the seed (W1.7). Waves land on mainline at every boundary. |
| No Emit hub | W5.3 Emit hub: emitter state, ColumnarEmitTypeResolution, ColumnarEmitReflectionFacts (127 callers) and ColumnarArgumentInstructionEmitter move to shapes before the Emit fan-out. |
| Producer decision late; dependency inversion; third resolver | The W1.8 spike decides in wave 1. W4.2 makes the analyzer's own declaration phase plus AnalyzerTypeResolver the single producer before any analyzer fan-out package that needs source symbols (W5.6+). No new resolver is created. |
| Reference-set change had no owner | W8.1 is a dedicated package with declared O1 and O4 diff classes. W3.5 is truly O4-identical. |
| Playground | The catalog's image provider takes byte[] images. W6.19 implements the Playground's image source before W7.2. Playground estates are acceptance rows in W3.5, W6.19 and W7.2. |
| Merge-queue sizing; counters and `_il` owned twice | W1.6 publishes O0 wall times. Per-package acceptance uses an affected subset plus a canary set; full-corpus O0 runs per merge batch. Concurrency is capped by queue capacity. Shared registries and counters have a single steward (W5.4/W6.0). The IL facade has one owner per wave. Ratchet repins are regenerated by the integrator. |
| Host-loaded references | W6.2 resolves test-framework and AspNet types only from the project's resolved reference paths. The host-process scope and the host load-by-name are deleted in W7.2. Until then the W2.6 host-scope image provider gives the importer exact images. |
| Attribute AQN strings change with scope (ColumnarAttributeBlobWriter.TryGetMetadataTypeName :828) | AttributeBlobEncoder (W6.9) takes model identities. The string change under the targeting pack is a declared W8.1 diff class. |
| Primitive canonicalization, primitives in token position | W1.2 interns Named(core System.Int32, and similar) as Special. W2.3/W2.2 encode primitives as ELEMENT_TYPE inside signatures and as a TypeRef in token position. |
| O1 hid semantic order | O1 keys include field sequence for sequential and explicit layouts, method and param sequence, and EH clause order. A perturbation control swaps two struct fields. |
| Array intrinsics and reflection quirks | W1.2 TypeAlgebra.ArrayIntrinsics; quirk parity rows; W2.6 replays recorded queries, comparing order as well as sets. |
| AOT JSON envelopes and AST trimming unowned | W2.8 owns the 42 Driver envelope sites plus AOT-safe identity and config fingerprint. Slice 4 (AST trimming) stays an external owner, named in W9.2. |

## 2b. Critic gap closures (round 3)

Each item is either verified and fixed, or corrected where the evidence differs from the claim.

1. **Pseudo-custom attributes (high).**
   - Verified as described in §1. Two corrections: native imports are already routed through DefinePInvokeMethod, and the corpus has one application.
   - Fix: one classifier, Metadata/Attributes/PseudoAttributeLowering.nl. W2.3 writes the lowering half and W3.3 the raise-from-tables half.
   - W2.2 emits ClassLayout, FieldLayout, FieldMarshal, ImplMap/ModuleRef and the flag bits from its results.
   - Every writer SetCustomAttribute routes through it (frozen in W1.3). The W3.1 tee mirrors through it, and W5.5 calls it from the producer.
   - W3.1 adds tests/native/pseudo-attributes, with one row per intercepted attribute per target. The rows include a [DllImport]-spelled import, an explicit-layout struct with [FieldOffset] fields, [MarshalAs] on a field and on a P/Invoke parameter, and [In]/[Out]/[Optional].
   - Each row checks the image with MetadataReader: zero CustomAttribute rows for that attribute, plus the expected flag or table row. GetCustomAttributesData() is not the oracle, because runtime reflection synthesizes pseudo attributes from flags.
   - W4.1 requires the project to be green on the writer image.
2. **PAB modifier route-arounds (high).**
   - Inventory verified and corrected in §1: the object-initializer cases are repaired, not refused; the init rules are semantics; the override-signature copies are correct. The critic's count of 39 lines is UNVERIFIED (verified: 16 GetRequiredCustomModifiers lines, 27 including GetOptionalCustomModifiers).
   - W4.1 deletes the ledger record sites and the dead ColumnarConstructionPlanner copy.
   - New package W5.12 deletes every remaining route-around right after cutover, including BindSetter, which this round found. It proves the writer encodes modifier chains on MemberRef and TypeSpec-parent signatures, and adds declared decline-to-success rows in tests/native/modreq-member-references.
   - The sites are on the deletion ledger. W1.10 adds ratchet tokens for them.
3. **Compiler projects absent from the corpus (medium).**
   - W1.6 adds the `compiler@<commit>` corpus: every N# src project (12 today, 15 after wave 1).
   - It is built two ways. The SDK route uses each arm's stage-1 SDK package, materialized by frozen-compiler, which drives the EmitIlAssembly task. The CLI route uses `nlc build` where that builds a compiler project (UNVERIFIED; W1.6 records any refusals).
   - Shadow O1 ⊆ ScopeMap on this corpus is a W3.2 report item and a W4.1 gate.
4. **O2 gaps (medium).**
   - O2 gains `loadcheck`. W1.9 implements it in the TestRunner and W2.7 wires it into the gate.
   - loadcheck calls Assembly.GetTypes(), then RuntimeHelpers.PrepareMethod on every non-generic MethodDef of every non-generic type, including .cctor bodies (compiled, never run). It also prepares the closed instantiations that the image's own TypeSpec and MethodSpec rows name.
   - Shadow verdicts gain writer-only (PAB failed, writer succeeded). Adopt mode produces it through one quarantined catch in ColumnarTransitionalDefinitions. A writer-only result is counted, its image is kept, and it must pass O2.
   - Every flip acknowledgement requires a clean O2, including loadcheck.
5. **Constant encoding (low).**
   - W2.3 probes PAB black-box on long, double, byte, char, short, float, int? and enum parameters with int-literal defaults, a null default on a struct and on an int? parameter, and a string-enum default.
   - Rule: encode the declared type (C#'s rule). Any difference from PAB is the declared ScopeMap class `constant-encoding`.
   - Rows check RawDefaultValue's type through the runner, and a C# consumer that omits the argument. The consumer is generated into a temp directory by the N# test, following the precedent of tests/scripts/test-async-iterator-cancellation-interop.sh, so no C# or shell file is committed.
6. **Self-compile window (critical).**
   - New lane (§3.13): `emit-parity rehearse` (W2.7).
   - It is blocking acceptance for W4.1, W4.2, W5.1 and W9.1, and the integrator runs it at every wave boundary from wave 2 through wave 9.
   - Correction to the suggested recipe: an alternate NSHARP_RESEED_BOOTSTRAP_DIR is never restored (NuGet.config:4), so the rehearsal overwrites the throwaway worktree's own bootstrap/ instead.
7. **gate-script-contracts unowned (high).**
   - Owners: W1.5 owns SdkEmitStampPaths, SelfHostFrontDoor, DevScript, CiTestSharding and GateStepInputSets. W1.6 owns CompilerPerformanceGate. W1.4 owns ReseedScripts in wave 1, then W2.7. W2.7 owns IlVerifyBaseline. W4.2 owns SdkEmitStampPaths in wave 4.
   - Decision (W1.5): Metadata, MetadataWriter and TestRunner are ANALYZED on the SDK route. That is already the seed's behaviour for names absent from Sdk.targets:15, so the decision takes effect with no reseed.
   - SdkEmitStampPaths becomes: every Driver-reachable compiler project is in COMPILER_PROJECT_DIRS, and is either in the shrink-only emit-only list or in a pinned analyzed list.
   - Any later Sdk.targets edit reaches the compiler's self-build only at the next reseed. W4.2 therefore carries a rehearsal, and W5.1 depends on W4.2.
8. **Hard-coded lists (high).**
   - W1.5 owns every list in §1. reseed.sh's two arrays come to it by sequenced grant after W1.4. The 44 native project.yml rows change by codemod.
   - W1.9 adds TestRunner to build-native-prerequisites.sh. The Compiler.* glob there already covers the two new compiler projects.
   - Acceptance: DRY_RUN reseed lists the new projects; pack-nuget emits the new packages; verify-release passes on that output; a CI archive round-trip contains TestRunner.
9. **Incremental identity (high).**
   - W1.5 adds Metadata and MetadataWriter, plus the already-missing Tooling and Compiler.dll, to IncrementalCompilerIdentity.Describe and to the Sdk.targets:201 Inputs.
   - A contract row requires both lists to equal the project closure.
   - W2.8 keeps that coverage when it makes the identity AOT-safe.
   - W8.2 adds the PDB to the :202 Outputs and owns the PDB-only incremental rows.
10. **SRM spelling order (high).**
    - W1.4 heads wave 1. W1.3, W1.5, W2.2-W2.6, W3.3 and W4.3 depend on it, and every other wave-1 package rebases onto its tag before its API freeze.
    - The probe now covers the reader side.
    - Correction: most reader types are already spelled in seed-compiled source (§1). A reseed is therefore less likely than claimed, though still possible.
11. **Same-version reseeds (medium).**
    - From the first reseed, each seed is published as a distinct 0.1.0-seed.<n> (§3.13).
    - W1.5 adds a fail-closed seed check and puts bootstrap/ into the step-cache inputs.
    - Stated in W1.4, W5.1 and W9.1.
12. **Verifiers after MLC/Cecil deletion (medium).**
    - W7.2 owns verify-bootstrap.py and verify-release.py. Both require the new payload, and verify-release refuses MLC and Cecil.
    - verify-bootstrap stops requiring MLC at W7.2 but refuses it only at W9.1, so CI passes on the W5.1 seed.
    - W7.2 re-plumbs the 8 native project.yml files and the 14 test inspectors (10 MLC, 4 Cecil).
13. **Exact-counter goldens (medium).**
    - Counter semantics are frozen in W1.2 (firstWaveInterfaces §2).
    - Each package that moves counters declares its expected row deltas: W1.9, W4.2, W8.1, and none expected for W2.6, W3.5 and W7.2.
    - The integrator re-baselines both goldens row by row, and they join the integrator-owned list.
    - The runner's processesSpawned increase needs an owner policy exception.
14. **Baseline arms (medium).**
    - The base arm is the mainline commit immediately before the batch or cutover. It is chosen by the compile-time-bench rule (CompileTimeRunner.nl:810-816): merge-base for branches, HEAD~1 at the tip.
    - f6a6751bb is used only for W1.6 controls.
    - frozen-compiler archives and rebuilds per base commit.
15. **TestRunner deployment (medium).**
    - W1.9 owns the locator (dev bin, installed toolset at scripts/lib/toolset.sh:315-355, SDK tools, NativeAOT nlc), the Cli.csproj copy rules, publish-toolset.sh, install.sh and build-native-prerequisites.sh, and a fail-closed diagnostic when the runner is missing.
    - Acceptance includes installed-toolchain-integration and smoke-turnkey-install.
16. **CI integration of tooling (medium).**
    - Every tests/native tool project carries *.tests.nl rows; ci-test-shards.sh:59 refuses a project without them.
    - W1.5 and W2.7 mark the heavy oracle projects serial.
    - The integrator refreshes ci-test-durations.json.
    - The CI versus integrator split is stated in §5.
17. **Audit coverage (low).**
    - The final W7.2 audit row covers every N# production project, including TestHost, LanguageServer and Playground. Snapshot targets are set to 0 at the W7 close.
    - Correction: ColumnarReferenceAssemblyWriter does not import Reflection.Emit.
18. **Stage-2/3 and harness language (low).**
    - stage2==stage3 means byte identity of the extracted DLLs plus payload SHA256SUMS (§3.13).
    - The cross-host compare uses the emit-parity manifest/diff-manifest verbs, which are N#.
19. **W7.1/W7.2 collision (high).**
    - W7.2 runs after W7.1 and depends on it and on the wave-6 owners.
    - W7.1 owns the Plan and Emit project.yml files.
    - The host-catalog tokens join the ratchet and W7.1's audit.
    - Owners of the 19 host-catalog files and the 7 MLC Plan files accept on zero references.
    - Correction: ExternalAssemblyScan has 44 occurrences in Plan and Emit, not the critic's 47 (UNVERIFIED).
20. **Package references outside the glob (high).**
    - W7.2 owns Cli.csproj (removes MLC :47 and Cecil :48, shrink only) and src/NSharpLang.Compiler/project.yml (removes MLC :9-10).
    - W7.1 owns the Plan and Emit project.yml files.
    - YamlDotNet stays, because the project.yml parser uses it.
21. **Host-scope provenance (high).**
    - W2.6 adds ColumnarTransitionalHostScopeImages (Model). It reads Assembly.Location bytes for every assembly the host scopes return, on the CLI, daemon and SDK-in-MSBuild routes.
    - An assembly with no file is a located decline that the shadow report counts.
    - W3.1 adds per-route importer provenance rows.
22. **Seed ordering (high).**
    - Same fixes as items 10 and 7.
    - The new projects accept the implicit NSharpLang.Runtime reference (Sdk.props:175); the layering statement now admits it.
    - W5.1 depends on W4.2.
23. **Emitter split mechanism (high).**
    - Verified as in §1. The critic's count of 215 private members is UNVERIFIED; the verified count is 76 fields and 632 functions.
    - W1.7 lands one real seam end to end through the committed seed before W2.1's freeze is scheduled.
    - Visibility policy: widened members become `internal` (package-private, emitted as CLR assembly; language-tour.md:3480-3486), never public.
    - Fallback split style: helper classes with explicit state objects, as in ColumnarArgumentInstructionEmitter, ColumnarEmitReflectionFacts and the ColumnarEmitContext derivation.
24. **Wave-4 rename conflict (medium).**
    - The DeterministicImageIdentity rename moves to the W5.4 steward in wave 5.
    - W5.4 gets grants for the writer and projector call sites and for the comment lines (ExternalAssemblyScan.nl:1290-1294, IncrementalBuildInputs.nl:241-245, ColumnarReferenceAssemblyWriter.nl:34-37).
25. **Circular census (medium).**
    - The integrator freezes the residual census at the wave-4 tag, and W5.11 owns exactly that list.
    - Named owners: DocumentManager.nl and Analyzer.nl go to W4.2; InternalsVisibleToEmissionScope.nl to W4.4; DocQueryKernels.nl, TypeResolver.nl and HoverHandler.nl to W5.10; LoopSequenceTypeFacts.nl to W5.9; MethodImplAttributeFacts.nl and AnalyzerProjectDiscovery.nl to W5.11.
26. **Ratchet token precision (medium).**
    - Matching becomes qualifier-aware: `OpCodes.` counts only when not preceded by an identifier character.
    - MakeGeneric* tokens are dropped. Reflection declaration-type tokens replace them.
    - Metadata and MetadataWriter are held at 0 from day one.
27. **Ownership holes (medium).**
    - W2.8 owns TestCommandKernels.nl in wave 2.
    - W1.9 adds DaemonExecHost.nl, DaemonExecKernels.nl and TestHost/CliPipeline.nl.
28. **Fresh gate versus repins (medium).**
    - A package may end with a package-local ownership repin commit. The integrator regenerates it at merge (§6).
29. **CI and NativeAOT coverage (medium).**
    - W1.5 owns .github/workflows/build.yml.
    - Every wave tag requires test-nativeaot-compiler.sh to pass on the current manifest.
30. **W4.1 A/B base (medium).**
    - Same fix as item 14: the A/B runs against the wave-4 base tag.
31. **Stale coordination facts (medium).**
    - Re-measured: both in-flight streams have landed. See the coordination plan.
    - In-flight branches are re-measured at every wave start, and `codemod --check` is a merge gate.
32. **Visual IDE verification (medium).**
    - The integrator (Claude, with computer use) verifies after the W3.5, W4.2, W4.4, W5.10 and W8.2 merges, with owner approval obtained up front. Codex cannot run computer use.
33. **Reference sources (medium).**
    - New W1.11 makes owner-approved pinned checkouts of dotnet/runtime v10.0.5 and Roslyn (at ~/repos/roslyn).
    - If the owner declines, W2.4 becomes a black-box differential port.
34. **Playground after W7.2 (medium, PLAUSIBLE).**
    - Bounded host-type resolution cannot survive W7.2, because Assembly.Location is empty in browser-wasm.
    - New W6.19 implements the chosen image source and adds an in-browser smoke.
35. **Long-lived processes (low).**
    - Rows in W3.4, W3.5, W5.2 and W6.1: daemon and LSP sessions across compilations with changed references must equal fresh processes.
    - A ratchet rule keeps static shape and catalog caches at zero.
    - The reflection-keyed static caches in §1 have named migrating owners.
36. **Diagnostic documentation (low).**
    - DiagnosticCatalog.nl entries and website/docs pages are owned by W1.9, W6.9, W8.1, W8.2 and W9.4.
37. **Duplicate audit owner (low).**
    - W7.1's audit rows go into tests/native/ownership-audit/WriterBoundaryRatchet.tests.nl.
38. **Heavy projects in the gate (low).**
    - W1.5 marks emit-parity, frozen-compiler, producer-spike and compiler-codemods serial; W2.7 marks catalog-parity and metadata-writer.
    - Dependencies are added to match.

## 3. Architecture

### 3.1 Projects and layering

**`src/NSharpLang.Compiler.Metadata`** (namespace NSharpLang.Compiler.Metadata)
- The bottom project. It depends on the BCL plus the implicit NSharpLang.Runtime reference that the seed's Sdk.props:175 gives every project except Core, Plan and Emit. This is accepted: the Runtime is a permanent boundary that every N# program already references.
- Model depends on it.
- Holds:
  - identities, symbols, shapes, the ShapeTable and signatures;
  - AttributeData/ConstantValue and PseudoAttributeLowering;
  - SpecialType, the WellKnownType and WellKnownMember descriptor tables with their `Wk.*` accessors;
  - TypeAlgebra, MemberLookup, MetadataCompilation and its Scope;
  - SourceModuleSymbolBuilder, SynthesizedDefinitionSet, the source erasure rules (W5.5);
  - the SRM reference catalog (Catalog/).

**`src/NSharpLang.Compiler.MetadataWriter`** (namespace NSharpLang.Compiler.Metadata.Writing)
- Depends on Metadata. Plan depends on it.
- Holds:
  - the definition builders;
  - IL (IlOpCode/IlOpCodes/IlOpFacts/IlBodyBuilder);
  - the encoders and serialization;
  - Identity, the single determinism owner;
  - ReferenceAssembly, the projector;
  - Pdb;
  - Validation, an N#-owned ECMA validator.

**`src/NSharpLang.TestRunner`**
- A framework-dependent N# app that references no compiler assembly.
- It is the only process that loads emitted assemblies, both for tests and for the O2 loadcheck.

**Build route, lists and estates**
- The new projects follow the existing pattern: a one-line csproj, project.yml, a global.json pinning the current seed version, and `excludeTests: true`.
- On the SDK route they are analyzed. Sdk.targets:15 is a shrink-only emit-only list.
- W1.5 registers them in every hard-coded list in §1. Estate rows live in the projects' own directories.

### 3.2 Metadata model

**Identity**
- AssemblyIdentity is structured: name, version, culture, key or token, retargetable, content type.
- TypeDefKey is (assembly, namespace, metadata name including the backtick arity, containing key, arity). It is promoted from ColumnarStructuralTypeKey (ColumnarStructuralTypeReferences.nl:137-240), with value equality and hashing.

**Symbols**
- TypeSymbol carries Kind (the CLR kind) and a separate NsKind overlay: Record, Union, UnionCase, ValueUnion, StringEnum, Newtype, Soa, Holder, Display, StateMachine, Anonymous, EntryWrapper.
- Generic parameters are listed inherited first, then own.
- Origin is Reference(module, token), Source(DeclarationId) or Synthesized(owner, ordinal, name).
- Kind conflicts are catalog diagnostics, never exceptions.

**Shapes and lookup**
- Shapes are hash-consed per compilation, so reference equality is structural equality. A StructuralKey serves cross-compilation caches.
- Member views expose a substituted signature for typing and the open definition for encoding.
- The query API mirrors the reflection subset in use (W1.2 census). Answers are total: a lookup returns Found, NotFound or Ambiguous.
- `typeof(prim)` becomes `Wk.X`. The 717 `==` comparisons stay `==` because shapes are interned. Well-known members replace typeof(X).GetMethod. The 16 compiler-implementation typeof sites remain.

**Ambient scope**
- MetadataCompilationScope has exactly two production openers: the emit thread and AnalyzerMetadataLoadSurface.Attach.
- No static field may hold a shape, symbol or catalog object outside Metadata/Compilation/** (ratchet rule).
- Analyzer TypeInfo remains the semantic layer. Its leaves become NamedTypeInfo(TypeShape) and GenericParameterTypeInfo.

### 3.3 Source symbols: one producer

- The analyzer's declaration phase feeds SourceModuleSymbolBuilder exactly once per compilation on every route:
  - analyze+emit;
  - check and the persisted-check subset (MultiFileCompiler.nl:2603);
  - LSP (DocumentManager.nl);
  - Playground;
  - the SDK route.
- W4.2 owns this, together with the scope-opener wiring in Analyzer.nl.
- Plan joins symbols to node tables by DeclarationId. W1.8 proves zero join mismatches.
- Waves 3-4: the definition tee creates source symbols from PAB Define calls. From W5.4 the tee only links to producer symbols, with a continuous cross-check.
- W5.5 moves N#-kind erasure into the producer's Complete phase. That includes pseudo-attribute classification through PseudoAttributeLowering, init modreqs and the synthesized-attribute plan.
- Body-time types are appended through SynthesizedDefinitionSet.

### 3.4 Reference catalog

**Reading**
- ReferenceCatalog reads byte[] snapshots from ReferenceImageSnapshotStore through IReferenceImageProvider, with PEReader over a MemoryStream.
- Resolution goes through IReferenceAssemblyResolver, implemented in Model.
- Rows are walked by index. Signature and attribute blobs are decoded by N#-owned II.23.2/II.23.3 decoders over GetBlobBytes.

**Behaviour**
- Lazy, publish-once and thread-safe.
- The name and arity index covers TypeDefs and ExportedTypes, including forwarder chains and nested spellings, with a Found/Missing/Unknown answer.
- Decoders cover attributes, nullability, constants, IVT grants, MethodImpls, layout and pseudo-attributes (raised from tables).

**Reference set and proof**
- Phase 1 reads exactly MLC's set: the runtime directory and shared-framework ladder, NuGet, and project references.
- Host scope (phase 1, transitional): ColumnarTransitionalHostScopeImages (W2.6, deleted in W7.2) supplies the image of every assembly that RuntimeAssembliesInScope, LoadedAcrossContexts and TryLoadHostAssemblyByName can return on the CLI, daemon and SDK-in-MSBuild routes, read from Assembly.Location. The importer can therefore map every host type exactly, and the writer reproduces PAB's AssemblyRef identities.
- catalog-parity (test-only, deleted with MLC) proves catalog answers equal MLC's, including member order.

**Counting**
- Until W7.2 only the MLC sites count reference loads, at ExternalAssemblyScan.nl:402 and :710, AnalyzerMetadataLoadSurface.nl:405 and AnalyzerMetadataAssemblyResolver.nl:135.
- W7.2 moves counting to the catalog with identical semantics: once per non-installed-runtime path per compilation.

**Playground**
- W6.19 supplies byte[] images (§3.11).

### 3.5 Writer

- Definition builders mirror the Reflection.Emit member names in use. Definitions may be added until Freeze, and late signatures are allowed.
- **Pseudo-custom attributes:** SetCustomAttribute(ctor, blob) on every definition builder goes through PseudoAttributeLowering. The per-target table mirrors PAB as measured by W2.3. An intercepted attribute becomes flags, ClassLayout, FieldLayout, FieldMarshal or ImplMap/ModuleRef, never a CustomAttribute row.

**Serialize**
1. Row numbering: `<Module>` first, then TypeDefs in creation order. Field, MethodDef and Param rows are contiguous; PropertyMap and EventMap likewise.
2. The ReferenceTable is deduplicated by interned identity and allocated in a fixed traversal.
3. Bodies are emitted with pseudo-tokens patched.
4. Table ordering:
   - GenericParam is sorted before any attribute attaches;
   - InterfaceImpl, MethodImpl, NestedClass, ClassLayout, FieldLayout, FieldMarshal, FieldRVA and ImplMap are sorted;
   - CustomAttribute, Constant and MethodSemantics rows are added already sorted.
5. MetadataRootBuilder runs with validation ON.
6. ManagedPEBuilder is called with all 11 arguments. Strong-name size 0 is a declared change.
7. DeterministicImageIdentity runs last.

**Tokens**
- Members of any generic type, including a type's own members referenced from its own body, are a MemberRef on a TypeSpec with the OPEN signature.
- Members of non-generic module types are a MethodDef or FieldDef.
- Generic method instantiations are a MethodSpec.
- Every MemberRef and MethodSpec signature carries the target's full custom-modifier chain, in metadata order.
- The phase-1 reference scope is the catalog symbol's defining module.

### 3.6 IL encoding

- IlOpCodes is an N# table whose member names are exactly the System.Reflection.Emit.OpCodes names.
- IlBodyBuilder keeps ILGenerator's member names and is ported from PAB ILGeneratorImpl at dotnet/runtime tag v10.0.5. The source is the W1.11 checkout; if the owner declines that download, it is a black-box differential port.
- Behaviour that must match:
  - operand narrowing;
  - label fix-ups (an out-of-range short branch is a decline);
  - implicit leave/endfinally/endfilter;
  - PAB's maxstack algorithm;
  - tiny/fat headers with InitLocals and small/fat EH sections;
  - LOCAL_SIG and user strings.
- EH nesting is asserted by EcmaValidator.

### 3.7 Signatures and generics

**Encoding**
- Hand-written II.23.2: CLASS/VALUETYPE from the symbol kind; GENERICINST; SZARRAY/ARRAY; BYREF/PTR/FNPTR; VAR/MVAR with the inherited count; CMOD in metadata order.
- The encoder is cross-checked against the catalog decoder.

**Modifiers**
- Init setters get a native modreq(IsExternalInit), so the repair and its ledger are deleted in W4.1.
- The modifier route-arounds (§1) are deleted in W5.12, which adds declared decline-to-success rows.
- The language rules that an init accessor is not assignable outside construction stay, re-expressed on symbols:
  - IsInitOnlySetter in the emitter;
  - AnalyzerWriteTargets.PropertySetterIsInitOnly.
- `in`/ref readonly declaration policy is unchanged.
- Override and implementation signatures copy the overridden member's modifier chain (W6.9; byte changes declared).

**Generic parameters**
- Copied into displays, state machines and union cases by one model substitution.

### 3.8 Attributes and constants

**Custom attributes**
- Stored as a triple: parent, constructor MethodShape, II.23.3 blob.
- AttributeBlobEncoder (W6.9) is the single owner.
- The one CustomAttributeBuilder (ColumnarParameterDefaultEmitter.nl:87) becomes a blob in W3.1.

**Pseudo-attributes**
- Lowered through PseudoAttributeLowering (§3.5).
- Raised back to AttributeData from tables by the catalog (W3.3).
- Classified at producer time from W5.5.

**Constants**
- Encoded with the DECLARED type's code: an enum uses its underlying type, Nullable<T> uses T, and a reference type gets CLASS with 4 zero bytes for null. Decimal and DateTime use attributes.
- W2.3 records PAB's actual behaviour for the 11 SetConstant sites first. Any difference is the declared ScopeMap class `constant-encoding`.

**Compiler-feature attributes**
- The net10.0 reference pack exposes them publicly.
- An absent one is a located refusal; W6.9 owns its DiagnosticCatalog entry and errors page.

### 3.9 Determinism and PDB

- DeterministicImageIdentity is the only owner: a content-derived version-4 MVID and a high-bit COFF stamp. It moves unchanged in W2.2 and is renamed by W5.4.
- PDB (W8.2) follows the ordering in §2.
- The SDK route lists the PDB among the EmitNSharpIlAssembly Outputs (Sdk.targets:202).
- Packing stops forcing DebugType=None for N# projects (scripts/lib/packages.sh:26-30, :134-136).

### 3.10 Reference assemblies

- W4.3 is an image-to-image projector built on the catalog plus the writer. The entry signature never changes.
- Body-only edits leave the bytes unchanged.
- Until W8.1, the projector ports Cecil's CoreLib-to-owner rescope. After W8.1 the rescope is identity.

### 3.11 Reference-set policy

- Phase 1 (to W7) is today's set plus the transitional host-scope images.
- Phase 2 (W8.1, owner decision):
  - the TFM targeting pack, the ASP.NET pack, NuGet compile assets, project-reference assemblies and the test-framework compile set;
  - a missing pack is restored, or reported as an actionable NL diagnostic (DiagnosticCatalog entry and errors page);
  - implementation assemblies become contract-scoped.
- Playground:
  - After W7.2 the Playground has no host-type path, because in browser-wasm Assembly.Location is empty.
  - W6.19 implements the owner-chosen byte[] image source before W7.2. Recommended: embedded reference images through a general N# `resources:` project feature, emitted as ManifestResource rows. That is N#-only and grows no permanent C# boundary.

### 3.12 Test execution

- W1.9: nlc (JIT or AOT) launches the TestRunner, which streams the TestWorkerHost protocol. The three in-process loads move there.
- Daemon and watch use a pre-started persistent runner, generalizing today's `__test-worker`.
- The runner also implements `loadcheck` for O2.
- The locator covers four installs:
  - the dev bin beside Cli.dll;
  - the installed toolset (lib/ next to bin/);
  - the SDK tools folder;
  - a NativeAOT nlc.
- A missing runner is a fail-closed located diagnostic.
- Counting: a runner spawn on the request path is processesSpawned; a standby runner started at daemon warm-up is not.

### 3.13 Seed identity and self-compilation

**Seed identity**
- From the first reseed of this program (W1.4 if its probe needs one, otherwise W5.1), every republished seed is versioned 0.1.0-seed.<n> for both packages.
- What moves with it:
  - the 12 src/*/global.json SDK pins;
  - Plan's NSharpLang.Runtime pin;
  - the seed SDK's Sdk.props:10 NSharpLangRuntimeVersion default, so the implicit Runtime reference (Sdk.props:175) restores the seed runtime;
  - verify-bootstrap.py, which stops hard-coding Runtime 0.1.0.
- Examples and templates keep pinning the dev SDK 0.1.0, so the seed and the dev SDK never share a NuGet cache directory.
- W1.5 adds a fail-closed seed check, scripts/lib/seed-check.sh, shared with reseed_verify_restored_packages. It runs in dev.sh, test-all-core.sh and build-native-prerequisites.sh and compares the cached seed packages with bootstrap/SHA256SUMS.
- W1.5 also adds bootstrap/ to the step-cache COMMON set (test-all-core.sh:204).

**Self-compile lane (`emit-parity rehearse <commit>`, W2.7)**
- Recipe:
  1. Create a throwaway worktree at /private/tmp/nsharp-agent-wt/mnw-rehearsal-<sha>.
  2. Point NSHARP_RESEED_PACKAGES_DIR and NSHARP_RESEED_STAGE_ROOT at scratch.
  3. Leave BOOTSTRAP_DIR at the default, which is the worktree's own bootstrap/; restore reads it through NuGet.config:4.
  4. Run reseed.sh through `estate`.
  5. Do a third clean rebuild and repack.
- Checks:
  - stage2==stage3;
  - ILVerify, EcmaValidator and loadcheck on the stage-2 compiler assemblies;
  - the stage-2 estate;
  - the compiler-corpus O0/O1 against the base arm.
- The worktree is discarded and nothing is committed.
- **stage2==stage3** is byte identity of every extracted tools/*.dll and lib/**/*.dll in both packages, plus SHA256SUMS over the extracted payloads. nupkg bytes are not compared, because zip timestamps and nuspec metadata vary.
- When it runs:
  - blocking for W4.1 (cutover), W4.2 (Sdk.targets change), W5.1 and W9.1 (reseeds);
  - by the integrator at every wave boundary, waves 2-9.

## 4. Migration mechanics

**Quarantine**
- Transitional code lives only in ColumnarTransitional*.nl or AnalyzerTransitional*.nl (including Model/ColumnarTransitionalHostScopeImages.nl), or on lines marked `TRANSITIONAL(W7.1|W7.2)`.
- The shadow switch is read in one function and deleted at cutover.

**Phases**
- **T-seed (W1.4):** the seed head lands first. Its probe, and its reseed if one is needed, come before any package that spells new SRM types.
- **T0, mechanical (W2.1, byte-identical):**
  - the IL vocabulary codemod;
  - the emitter split into about 20 files, in the split style W1.7 proved end to end through the seed (extension functions, or explicit-state helpers). Widened members become `internal`.
- **T1, tee (W3.1/W3.2):**
  - Every Define/Set/CreateType call goes through ColumnarTransitionalDefinitions, and SetCustomAttribute mirrors go through PseudoAttributeLowering.
  - ColumnarTransitionalImporter maps reflection objects to catalog symbols by (Module.ModuleVersionId, MetadataToken). This is exact because MLC, the runtime twins, the host-scope provider and the catalog read the same files.
  - Shadow `compare|adopt`. In adopt mode a quarantined catch turns PAB failures into the writer-only verdict.
- **T2 (W4.1):** burn-down to the scope map, including the compiler corpus, then the blocking self-compile rehearsal, then cutover.
  - Deleted: the PAB tail; the repair and its ledger, including the record sites and the dead SetterSignatureSurvivesAMemberRef copy; the ILGenerator half of the facade; the shadow switch.
  - PAB TypeBuilders survive only as body-less identity shells until W7.1.
- **T3 (waves 5-6):** hubs, then fan-out. W5.12 deletes the modifier route-arounds right after cutover. A callee that changes signature keeps a TRANSITIONAL reflection overload. No package edits another package's file except under a declared, sequenced line grant.
- **T4 (wave 7):** deletion. W7.1 runs first, then W7.2.

## 5. Parity oracles

Every oracle refuses a verdict on vacuous input: zero rows, missing projects, or ctlA≠ctlB.

| Oracle | What it checks |
|---|---|
| O0 | Byte identity of every emitted image plus check JSON. Corpora: 21 example roots, single-file examples, fixtures, the main and test assemblies of all 154 native projects, and `compiler@<commit>` (every N# src project; SDK route through each arm's stage-1 SDK, CLI route where `nlc build` builds it). The base arm is the mainline commit immediately before the batch: the wave-base tag for packages, merge-base with origin/systems-language for branches, HEAD~1 at the tip. Per package: affected subset plus canary. Per merge batch: full corpus; the compiler corpus runs for batches touching Plan, Emit, Metadata, MetadataWriter or the SDK, and at every wave boundary. |
| O1 | Entity-keyed normalized dump with operands resolved to names. Modes: body-exact, semantic, definitions. Semantic order keys. ScopeMap classes each carry a perturbation control. |
| O2 | ILVerify with an empty baseline over everything, including compiler stage assemblies; EcmaValidator on every image; `loadcheck` in a TestRunner process. |
| O3 | Execution: non-zero identical pass/fail/skip per project; example stdout and exit code under run contracts. |
| O4 | Check JSON byte identity, including the NL103 decline census. |
| O5 | Self-compile: `emit-parity rehearse` (§3.13). |
| O6 | JIT/R2R/AOT: check, build (byte-identical images), run, test. The integrator runs test-nativeaot-compiler.sh on the current manifest at every wave tag. |

**Shadow verdicts**
- identical;
- scoped(<class>);
- writer-regression (blocks);
- writer-only (PAB failed, writer succeeded: counted, image kept, O2 required);
- both-declined (decline reasons must match);
- decline-mismatch (blocks).

**Flips and baselines**
- A decline flip in either direction needs a new native test, a clean O2 including loadcheck, and an explicit acknowledgement. A success-to-decline flip blocks the merge.
- f6a6751bb is only a W1.6 control build. Every A/B runs against its per-batch base. W4.1's A/B runs against the wave-4 base tag.

**CI versus integrator**
- On every push, CI runs:
  - every tool project's controls and perturbation rows;
  - O2 over the images the gate builds plus the canary set;
  - canary O0 against the merge-base.
- The integrator runs, at merge batches and wave boundaries:
  - full-corpus O0/O1/O3/O4;
  - the compiler corpus;
  - `rehearse`;
  - O6.

## 6. Execution protocol

- **One package, one Codex brief.** Each WP is one `codex exec -p luna-xhigh` brief in /private/tmp/nsharp-agent-wt/mnw-<wp>, branched from the wave-base tag (W1.4's merged tag for wave 1).
- **Environment.** Isolated NUGET_PACKAGES (symlinks to everything except nsharplang.*). Never pkill by pattern; never kill a test-all driver. Commit WIP before heavy gates.
- **Ownership.**
  - A package owns its listed files exclusively within its wave.
  - The only exception is a declared line-level grant with sequencing: the second owner's dependsOn names the first owner, and it edits only after that owner's MERGE.
  - Same-wave dependents otherwise consume only published API-freeze commits.
- **Repins.**
  - A package may end with a package-local ownership repin commit. That covers both keys: the JSON header and the OwnershipPolicy constant.
  - Its acceptance means a fresh gate green with that commit.
  - The integrator discards and regenerates repins and the WriterBoundary snapshot at merge.
- **Visual verification.** Codex cannot run computer use. After merging W3.5, W4.2, W4.4, W5.10 and W8.2, the integrator (Claude) performs the AGENTS.md visual VS Code verification, with owner approval for those Claude credits obtained up front.
- **Integrator checklist, per merge batch or wave:**
  1. Merge in dependency order.
  2. Regenerate the repins and the snapshot, and maintain the repin list: Cli.csproj, src/NSharpLang.Compiler/project.yml, the SDK files, the scripts, the workflows and the goldens.
  3. Run full-corpus O0 against the per-batch base, with the compiler corpus where required.
  4. Run a fresh `VSCODE_TESTS=skip ./scripts/test-all.sh --commit`, plus the VS Code gate when analyzer, LSP or IDE files moved.
  5. Run `emit-parity rehearse` on the candidate tag (waves 2-9).
  6. Run `./scripts/test-nativeaot-compiler.sh` on the current manifest.
  7. Re-baseline agent-loop-baseline.golden.json and bootstrap-build-baseline.golden.json row by row from the packages' declared deltas, and refresh ci-test-durations.json.
  8. Run the visual verification scenarios.
  9. Re-measure in-flight branches and enforce `codemod --check`.
  10. At the wave-4 tag only: freeze the residual census (systems-language-closeout/decodes/metadata-writer-residual-census.md).
  11. Tag the wave and hand it to the integration session. Nobody commits on census/merge.
- **Reference sources.** Briefs cite the W1.11 checkouts by path and SHA, or say "black-box" if the owner declined the download.
- **Concurrency.** At most min(16, the merge-queue capacity measured by W1.6).

## 7. Waves

| Wave | Content |
|---|---|
| 1 | W1.4 seed head first (probe, admission, seed identity, reseed if needed). Then contracts, oracles with the compiler corpus, codemods with a real seam proof, producer spike, TestRunner, ratchet, reference sources. W1.5 plumbing lands last. |
| 2 | Mechanical restructuring. Writer serializer, encoders with pseudo-attribute lowering and the constant probe, IL, validator. Catalog core with host-scope images. Gate infra (loadcheck, rehearse, stage 3). AOT-safe envelopes. |
| 3 | Tee (Plan and Emit) with pseudo-attribute and provenance rows. Catalog attributes and nullability. Well-known types and algebra. Analyzer reference hub. |
| 4 | Burn-down and rehearsal-gated cutover. Single producer. Ref-asm projector. Analyzer metadata readers. Residual census frozen. |
| 5 | Reseed S2 (versioned). Plan, Emit and bridge hubs, with the identity rename. Erasure. Analyzer fan-out. Modifier route-around deletion. |
| 6 | Plan and Emit fan-out (18 packages plus steward). Playground reference images. |
| 7 | Deletion: W7.1, then W7.2. |
| 8 | Reference-set switch. PDB. |
| 9 | Final reseed (MLC-free, verifiers flipped). AOT 21/21. Optional byte-changing improvements. Documentation. |

## 8. AOT outcome

| Current refusal | Fixed by |
|---|---|
| AutoDiscovery / MultiFileProject (TypeBuilder or MLC Type entering runtime APIs; cause UNVERIFIED) | W4.1 + wave 6 + W7.1 |
| InParameters | W3.1 blob path |
| EqualityComparer<T>, Task.Run, IEnumerator<string> | Wk members (W3.4, W6.6/W6.7) |
| TestExample / MinimalApi / TaskCli / IssueTracker | W7.2 (loads) and W1.9 (runner) |
| ExceptionFilters (cause UNVERIFIED) | W6.11/W6.13 |

- The integrator keeps the 8-root manifest green at every wave tag.
- W9.2 grows the manifest to 21 roots and makes Metadata, MetadataWriter, Plan, Emit and Driver emission warning-free scopes.
- The remaining external owner is slice 4: TypeInfoFactoryReflection, 123 calls and 208 roots.
- Whether ModuleVersionId works under AOT is UNVERIFIED; W2.8 measures it.

## 9. Deletion end state

**Gone from compiler production source.** WriterBoundaryRatchet enforces this. W7.2's final audit row covers every N# production project (the compiler slices, Compiler, TestHost, LanguageServer, Playground, Metadata, MetadataWriter), and snapshot targets are 0 at the W7 close.
- every Reflection.Emit type and the `import System.Reflection.Emit` lines (81 files);
- PAB, GenerateMetadata and the CreateType ordering loops;
- the 1,647-line repair and its ledger in 12 files, including the record sites;
- the modifier route-arounds: SetterSignatureSurvivesAMemberRef (both copies), the unreferenceable-setter decline, TryFindInitAutoPropertyBackingField, the BindSetter init special case, IsReferenceablePattern/HasRequiredModifiers and ColumnarReadOnlySpanElementRead;
- the Cecil writer and rescope;
- MetadataLoadContext (62 files) and ReferenceImageMetadataContext;
- ExactIdentityReferenceLoadContext, the 7 executable loads, the AppDomain inventory, RuntimeAssembliesInScope, TryLoadHostAssemblyByName, runtime pairing and ColumnarTransitionalHostScopeImages;
- SharedReferenceMetadata.RuntimeContext*;
- DaemonLoadedReferenceGuard's AppDomain scan;
- the 3 TestHost loads;
- ReflectionTypeInfo and its family, and AnalyzerClrTypeConversion's surrogate funnel;
- WellKnownTypeCatalog, RequiredRuntimeTypes, the ColumnarExternalBindingPlans closed allow-lists and ColumnarSplitTypeIdentityFacts;
- the reflection-keyed static caches;
- 105 `is TypeBuilder`, 99 GetX rebinds, 101 catch lines, 109 IsSafeSzArrayType lines;
- every ColumnarTransitional* file, the bridges and TRANSITIONAL overloads;
- the MLC and Cecil package references: Plan and Emit project.yml (W7.1); every other src project.yml, src/NSharpLang.Compiler/project.yml, Cli.csproj and the SDK payload (W7.2);
- the MLC requirements in verify-release.py (W7.2) and verify-bootstrap.py (W9.1, which then refuses MLC).

**Kept on purpose**
- User programs may still call Reflection.Emit (reflection-emit-bootstrap, 47 tests).
- NullabilityMetadataCore and AnalyzerMetadataLoadPolicy.
- The emit-parity and codemod test-scope tools.
- YamlDotNet, used by the project.yml parser.
- The init-accessor language rules, re-expressed on symbols.

**Single owners at the end**

| Concern | Owner |
|---|---|
| Model, catalog and pseudo-attribute classification | Metadata |
| Writer, IL, encoders, identity, ref-asm, PDB | MetadataWriter |
| Planning | Plan, model-typed |
| Orchestration | Emit |
| Analysis | Core over symbols |
| Test execution and image loading | TestRunner |
| Binder convergence | Follow-on program, unless the owner includes it |

## 10. Risks

| Risk | Mitigation |
|---|---|
| Model semantics drift from reflection | W1.2 quirk rows; W2.6 query replay; O0 and O4 on every package |
| Silent encoding errors | Validation on; EcmaValidator; encoder/decoder cross-check; ILVerify everywhere; loadcheck; shadow O1 |
| Pseudo-attributes silently become CustomAttribute rows | PseudoAttributeLowering; W2.3 black-box probe; tests/native/pseudo-attributes checked with MetadataReader |
| Writer miscompiles the compiler itself | Compiler corpus in O0/O1 from W1.6; blocking rehearsal (stage2==stage3, O2, stage-2 estate) at W4.1 and every wave boundary |
| Stale seed in shared caches | Distinct seed versions; fail-closed seed check; bootstrap/ in step-cache inputs |
| Host-scope types without an exact image | W2.6 host-scope provider; provenance rows on three routes; located decline counted in the burn-down |
| ILGeneratorImpl hidden behaviour | W1.11 source port; differential with at least 40 scripts and 10k random sequences |
| Seed spelling gaps | W1.4 head probe; admission plus two-stage reseed before dependents start |
| Churn | Codemods with `--check` merge gates; freeze windows; per-wave re-measurement |
| Long dual-universe window (waves 4-6) | Quarantine; single steward; ratchet ceilings; route-arounds deleted in wave 5 |
| Producer cost on the SDK route | W1.8 measurement plus owner decision; rehearsal with the changed Sdk.targets |
| Reference-set switch changes binding | Isolated W8.1 with a reviewed O4 diff |
| Counter goldens break or hide regressions | Frozen semantics; declared deltas; integrator re-baseline with explanations |
| Long-lived daemon or LSP state | Per-compilation interning; static-cache ratchet rule; daemon and LSP multi-compilation rows |
| Playground loses BCL resolution at W7.2 | W6.19 before W7.2 with an in-browser smoke |
| Gate load and flakiness | Serialized full gates; affected-subset O0; heavy oracle projects serial |
| Iterator unification overlap | See the coordination plan |
