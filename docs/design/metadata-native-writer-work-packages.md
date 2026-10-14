# Metadata-native writer: work packages and owner decisions

Companion to [metadata-native-writer.md](metadata-native-writer.md). Generated from the planning workflow's final plan (2026-10-14).

## Owner decisions

Pending. Each item lists the plan's recommendation first.

1. Integration model. Recommended: land each wave on mainline through the integration session, with transitional code quarantined and ratcheted. Accept a freeze of at most 72 hours on ColumnarIlEmitter.nl for the W2.1 split, which is scheduled only after W1.7 has landed one real seam through the seed. Codemods apply at merge time, with --check as a merge gate for in-flight streams. The alternative is a side branch until cutover, which carries drift risk at 815 commits per 30 days. Mainline already moved 30 commits (f6a6751bb to 9818469cf) during planning.

2. Pre-cutover shadow hook: an env var read in one function, with compare and adopt modes, deleted at W4.1. In adopt mode, one quarantined catch turns PAB failures into the writer-only verdict. Is this an acceptable transitional harness under AGENTS.md's no-fallback rule?

3. Single source-symbol producer on the SDK route. Recommended: retire the Sdk.targets:15 by-name emit-only exception, so every emission is preceded by analysis. The alternative is a declarations-only analyzer mode. Decide from the W1.8 measurements. Either way the change reaches the compiler's own build only at the next reseed, so W4.2 carries a rehearsal and W5.1 depends on it.

4. New-project build mode. Recommended: Metadata, MetadataWriter and TestRunner are analyzed on the SDK route, outside the shrink-only emit-only list. That matches the seed's current behaviour, so no reseed is needed. They accept the implicit NSharpLang.Runtime reference from Sdk.props:175, which amends the BCL-only layering statement. The alternative is emit-only, which needs a reseed before the seed honours it.

5. Seed identity. Recommended: from the program's first reseed (W1.4 if needed, otherwise W5.1), publish every seed as a distinct 0.1.0-seed.<n>, moving 12 src/*/global.json pins, Plan's Runtime pin, the seed Sdk.props:10 default and verify-bootstrap.py with it. Also always add the fail-closed seed-hash check and put bootstrap/ into the step-cache inputs. This ends the repeatedly recorded shared-cache seed collisions. The alternative is a same-version republish guarded only by the check.

6. Reference-set end state (W8.1). Recommended: the targeting pack for binding and emission (Roslyn model). Missing packs are restored from NuGet, or reported as an actionable diagnostic, never a fallback. This accepts that programs using implementation-only public APIs stop compiling. It can be deferred without blocking AOT.

7. Test execution through a dedicated N# NSharpLang.TestRunner, which is also the only loader for the O2 loadcheck. Accept the cold nlc test latency delta, or require a persistent worker by default.

8. CompilerWorkCounters policy exception. The agent-loop golden policy treats increases as regressions. The runner spawn raises processesSpawned from 0 to 1 on cold nlc test rows, and W8.1 changes referenceAssembliesLoaded once pack images live outside the installed runtime path. Approve integrator re-baselining of these declared increases, with row-by-row explanations.

9. Estate fixtures. The NativeAOT design doc says the 22 test-only dynamic-assembly fixtures stay. Planner fixtures built on TypeBuilder or ILGenerator must still be re-expressed on the model when planner APIs change, with count deltas explained row by row. Confirm.

10. Emitter split style. Extension functions, if W1.7's seam proof succeeds, with up to about 708 private members widened to internal (76 fields, 632 functions; never public). Or explicit-state helper classes. Confirm the visibility policy.

11. Scope. Recommended: binder convergence (Plan consuming analyzer bindings, one overload ranker) is a follow-on program, made mechanical by this one, not part of it.

12. Iterator unification sequencing. Slices 1-3 are landing on mainline (through 9818469cf); slices 4-6 have not started. Should slice 6 (deleting the old iterator body emitter) be required before W6.8? Otherwise W6.8 also migrates the old body owner, which is throwaway work.

13. AOT ownership. W2.8 takes the 42 Driver JsonSerializer envelopes, including the TestCommandKernels site, plus AOT-safe incremental identity, rather than assigning them to the CLI stream. Slice 4 (AST trimming, 123 calls) stays external, and the 21/21 claim depends on it.

14. Playground image source (W6.19, before W7.2). Bounded host-type resolution cannot survive W7.2, because Assembly.Location is empty in browser-wasm. Recommended: embedded reference images through a general N# project.yml resources: feature (ManifestResource rows). This is N#-only, and download size grows. The alternative is static assets fetched by main.js and PlaygroundExports.cs, which grows permanent C# and JS boundaries and needs an explicit exception.

15. Visual verification budget. AGENTS.md requires computer-use visual verification for IDE-affecting packages, and Codex cannot do it. Approve Claude computer-use runs by the integrator after the W3.5, W4.2, W4.4, W5.10 and W8.2 merges, and after W6.19 if the integrator's browser tool is the in-browser smoke harness. The global CLAUDE.md requires asking before spending Claude credits.

16. Reference-source download (W1.11). Approve shallow, read-only checkouts of dotnet/runtime at v10.0.5 (to ~/repos/dotnet-runtime-v10.0.5) and dotnet/roslyn at a pinned release tag (to ~/repos/roslyn, the path AGENTS.md names). Neither exists on the machine. If declined, W2.4 becomes a black-box differential port, and W2.3's tables come only from probes.

17. Constant encoding. Recommended: encode the declared parameter or field type (C#'s rule) and declare any PAB difference as a ScopeMap class. W2.3's probe will say whether PAB writes ELEMENT_TYPE_I4 or throws for, for example, a long parameter with an int literal. The alternative is reproducing PAB byte for byte.

18. CI enforcement scope. Recommended: CI enforces tool-project controls, O2 over gate images plus the canary set, and canary O0 against the merge-base on every push. Full-corpus O0/O1/O3/O4, the compiler corpus, the self-compile rehearsal and O6 stay integrator-run at merge batches and wave boundaries.

19. TFM policy. net10.0+ only means no embedded compiler-attribute synthesis; an absent attribute is a located refusal with its own NL code and page. Supporting older TFMs requires Roslyn-style embedded attributes.

20. Approve the deliberate byte-changing slices and their timing: strong-name directory 0 (at cutover); the modreq-route-around-flip class (W5.12, which also re-enables previously refused programs); override modifier copying (W6.9, correctness); the constant-encoding class (if any); and the optional W9.3 items (castclass removal, exact maxstack, branch shortening, naming every parameter).

21. PDB default once W8.2 lands (debugType portable, embedded or none), and whether packages ship symbols. Optionally emit a .mvid section for CopyRefAssembly.

22. Concurrency cap. Use min(16, measured merge-queue capacity), with serialized full gates and a self-compile rehearsal at every wave boundary. Confirm the machine budget for wave 6 (19 packages plus the steward).

## Coordination with in-flight work

Facts below were re-measured on 2026-10-13. Refs are shared by every worktree, so these are current mainline facts, not scout-local ones.

Branch status:
- origin/systems-language is 9818469cf, which is f6a6751bb + 30 commits.
- **feat/async-iterator-cancellation** (5 commits, tip c1d37d677) has LANDED. Its tip is an ancestor of mainline.
- **feat/iterator-lowering-unification** has LANDED through 9818469cf. That is 25 commits after c1d37d677, from 6c4816244 to 9818469cf. The branch tip equals the mainline tip (0 ahead, 0 behind). The critic's "23 ahead, 0 behind" was a snapshot taken mid-push.
- The unification stream is still ACTIVE. Worktree /private/tmp/nsharp-agent-wt/iterator-unify is at 9818469cf, and its last commit is 2026-10-13 18:52 -0500.
- Its design doc at 9818469cf reports slices 1-3 in progress: shared locals and assignments, non-suspending loops, and constrained protected regions with catches and filters. Slices 4-6 have not started: async suspension, generics and debug info, and deleting the old iterator body scanner and emitter.
- The design doc (line 85) also says the stream does not run test-all.sh. The landed slices therefore have only focused evidence until the program's own gates run.
- **plan/iterator-lowering-unification** (fde720855, worktree iterator-unify-plan) is a stale planning branch. Ignore it.
- **census/merge** a7017b423 is 102 commits behind mainline. The program never commits there.

Landed deltas on files this program owns (f6a6751bb → 9818469cf):
- ColumnarMethodBodyPlanner.nl: 1,219 → 2,379 lines.
- ColumnarIteratorPlanner.nl: 7,320 → 7,751 lines. The PAB builder region W3.1 edits moved from about :4103-4270 to about :4317 onward.
- ColumnarIlEmitter.nl: 32,148 → 32,153 lines, from the five EnsureAutomaticEnumeratorCancellationAttribute walk call sites.
- ColumnarIteratorRealization.nl: 1,210 → 1,222 lines.
- New files: ColumnarIteratorCancellationFacts.nl (128 lines), the NL353 docs, tests/native/async-iterator-cancellation, and tests/scripts/test-async-iterator-cancellation-interop.sh.
- AnalyzerAttributeValidator.nl +112 lines; tests/scripts/test-all-core.sh +9.
- The ownership ratchet was repinned.

Rules for the program:
1. **Base.** The wave-1 base tag is current mainline at wave-1 start (≥ 9818469cf), not f6a6751bb.
   - Before tagging it, the integrator runs a fresh `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` on it, because the landed unification slices were not gated with test-all.
   - W1.1 re-measures every count and line reference at that tag.
   - f6a6751bb remains only W1.6's control build.
   - Every A/B uses the per-batch base. W4.1 uses the wave-4 base tag.
2. **Re-measure at every wave start.** For each in-flight branch, record ahead/behind, merge-base, files touched against the wave's ownership map, and active worktrees. Record the tips in the wave's briefs. Line references in briefs are re-located from the measurement base, through the W2.1 split map once it exists.
3. **Codemod gate.** From the W2.1 freeze onward, `codemod --check` (the W1.7 IL recipe and split recipe) is a merge gate for every unification merge. Before the freeze, the stream either merges its current slice or pauses edits to Plan and Emit IL-vocabulary files for the freeze window of at most 72 hours.

Async cancellation has landed and is absorbed as planned:
- W3.1 routes the EnumeratorCancellation attachment through the tee and owns ColumnarIteratorCancellationFacts in wave 3.
- W4.4 covers the AnalyzerAttributeValidator additions.
- W6.8 moves the CancellationToken identity checks to Wk and the catalog.
- async-iterator-cancellation is an acceptance row in W4.4 and W6.8.
- Its interop script sets the pattern for C#-consumer rows. W2.3 generates its C# consumers into temp directories from N# tests rather than committing new scripts or C# files, which would be new ownership-epoch code rows.

Iterator lowering unification, contract alignment (unchanged):
- Its generated-type identity and generated-method inputs use the frozen W1.2 SynthesizedOrigin, TypeDefKey and SourceModuleSymbolBuilder.AppendSynthesized/SynthesizedDefinitionSet.
- After W3.1, new machine types go through ColumnarTransitionalDefinitions.DefineSyntheticType. After W4.1 they go through the writer's DefineSyntheticType.
- WriterBoundaryRatchet blocks new TypeBuilder, ILGenerator, OpCodes, reflection-declaration or host-catalog growth in its files.

Iterator lowering unification, ownership windows:
- W3.1 edits only ColumnarIteratorPlanner's builder region (re-located at wave-3 start) and the line-51 site.
- W4.1 removes ledger plumbing from ColumnarIteratorPlanner, ColumnarIteratorBodyScope and ColumnarIteratorRealization.
- W5.12 owns ColumnarForeachLoopPlanner and ColumnarSourceSelfInstantiation in wave 5.
- W6.8 owns ColumnarIteratorPlanner, IteratorBodyScope, IteratorCancellationFacts and IteratorRealization for the whole of wave 6. W6.6 owns IteratorMemberResolver.
- W6.11 owns ColumnarMethodBodyPlanner, now 2,379 lines and carrying the shared iterator statement paths.
- During those windows the stream either merges first, with our WPs rebasing, or pauses edits to those files.

Iterator lowering unification, sequencing:
- Recommended order: unification slices 4-6 complete before wave 6 starts. W6.8 then migrates only the surviving lowering and realization surface, and W6.11 covers the rewritten MoveNext bodies through the general planner.
- If slice 6 has not landed when wave 6 starts, the owner chooses between two options: W6.8 also migrates the old body emitter (throwaway work), or wave 7 waits for slice 6.
- The W7.1 audit cannot pass while the old iterator owner still holds builder or System.Type code.
- Slice 4 (async iterators) keeps tests/native/async-iterator-cancellation green.
- Unification's PDB and sequence-point work records origin spans and hidden markers against the W1.3 IlBodyBuilder.MarkSequencePoint contract. W8.2 owns the PDB writer.

Self-compile coverage for the stream:
- The integrator's per-wave `emit-parity rehearse` and fresh gate cover the unification slices that have landed. That includes a stage-2 compiler built by the new writer from wave 4 on.
- A unification merge that breaks the rehearsal blocks the wave tag, exactly like a program package.

Both streams:
- Keep the ILVerify baseline empty. W2.7 expands it to every native project, including the iterator projects, and adds loadcheck.
- Never edit the ratchet, the snapshot or the counter goldens. The integrator repins.
- Hand branches or tags to the integration session.

## Wave-1 frozen interfaces

These contracts are frozen in wave 1. Later waves code against them; changing one needs owner review.

0. Wave-1 order
- W1.4 is the head of wave 1. It lands, together with its seed republish if the probe needs one, before W1.3 and W1.5 start.
- Every other wave-1 package rebases onto W1.4's merged tag (mnw-w1-seed) before its API-freeze commit and before its gate.
- W1.5 lands last in wave 1. It depends on W1.2, W1.3, W1.4, W1.6, W1.7, W1.8 and W1.9.

1. Projects, dependency edges and build lists
- src/NSharpLang.Compiler.Metadata (namespace NSharpLang.Compiler.Metadata): BCL, plus the implicit NSharpLang.Runtime package reference that the seed's Sdk.props:175 gives every project except Core, Plan and Emit. No other dependency.
- src/NSharpLang.Compiler.MetadataWriter (namespace NSharpLang.Compiler.Metadata.Writing): Metadata, plus the same implicit Runtime reference.
- src/NSharpLang.TestRunner: a framework-dependent N# app with no compiler references. It is the only process that loads emitted images, both for tests and for loadcheck.
- New edges: Model→Metadata and Plan→MetadataWriter.
- SDK route: the three new projects are ANALYZED, not emit-only.
  - The seed's Sdk.targets:15 names only the 8 legacy projects, so this is already the seed's behaviour, and the decision takes effect without a reseed.
  - The emit-only list may only shrink.
  - Any Sdk.targets or Sdk.props edit reaches the compiler's own build only at the next reseed.
- Each new project has: a one-line csproj; project.yml; a global.json pinning the current seed version; `excludeTests: true`; estate rows in its own directory.
- W1.5 adds the new projects to every hard-coded list:
  - reseed.sh COMPILER_PROJECT_DIRS and ESTATE_PROJECTS;
  - scripts/lib/packages.sh NSHARP_PACKAGE_SPECS;
  - verify-release.py's expected set;
  - in test-all-core.sh: the format list, SELF_HOST_PROJECTS/SELF_HOST_CEILINGS (14 projects, ceilings 0), BOOTSTRAP_TEST_PROJECTS, native_requires_serial_run, and the step-cache COMMON set (which also gains bootstrap/);
  - dev.sh ESTATE_PROJECTS and the --since mapping;
  - .github/workflows/build.yml;
  - IncrementalCompilerIdentity.Describe and the Sdk.targets:201 Inputs;
  - the 44 tests/native/*/project.yml compiler-DLL lists.
  - W1.9 adds TestRunner to build-native-prerequisites.sh.
- Contract rows (gate-script-contracts, W1.5):
  - every Driver-reachable compiler project is in COMPILER_PROJECT_DIRS, and is either in the emit-only list or in the pinned analyzed list;
  - IncrementalCompilerIdentity.Describe and the Sdk.targets EmitNSharpIlAssembly Inputs each equal the compiler's project closure, including the currently missing Tooling and Compiler.dll.

2. Model API (W1.2; API-freeze commit by day 2)

   Identity and kinds
   - AssemblyIdentity(Name, Version, Culture, PublicKeyOrToken, IsPublicKey, IsRetargetable, ContentType), with value equality.
   - TypeDefKey(Assembly, Namespace, MetadataName-with-backtick, Containing?, Arity).
   - DeclarationId(FileId, SpanStart, MetadataName, MemberOrdinal).
   - SymbolOrigin = Reference(moduleId, token) | Source(DeclarationId) | Synthesized(owner, ordinal, name).
   - TypeKind {Class, Struct, Interface, Enum, Delegate}.
   - NsTypeKind {Ordinary, Record, RecordStruct, Union, UnionCase, ValueUnion, StringEnum, Newtype, Soa, Holder, Display, StateMachine, Anonymous, EntryWrapper}.

   Symbols
   - TypeSymbol {Key, Kind, NsKind, Attributes, GenericParameters (inherited first), OwnGenericParameterCount, BaseType, Interfaces, Fields, Methods, Properties, Events, NestedTypes, MethodImpls, Layout, CustomAttributes, Origin, SpecialType}.
   - GenericParameterSymbol {Owner, Ordinal, Name, Attributes, Constraints[(TypeShape, CustomModifier[])]}.
   - MethodSymbol {DeclaringType, Name, Attributes, ImplAttributes, GenericParameters, Signature, Parameters, ReturnParameter, ImplMap?}.
   - MethodSignature {HasThis, ExplicitThis, GenericArity, Return: SignatureType, Parameters: SignatureType[]}.
   - SignatureType {Type, Modifiers (metadata order, required and optional), IsByRef}.
   - FieldSymbol {Type, Constant?, Offset?, Rva?, Marshal?}. PropertySymbol and EventSymbol carry their accessors.
   - ParameterSymbol {Sequence, Name, Attributes, Type, Default?, Marshal?}.

   Shapes
   - TypeShape is interned per compilation, so reference equality equals structural equality. Cases: Special | Named | Constructed(def, args) | SzArray | Array(rank, sizes, bounds) | ByRef | Pointer | FunctionPointer | TypeParameter | MethodParameter.
   - StructuralKey serves cross-compilation caches.
   - MethodShape, FieldShape, PropertyShape and EventShape {Definition, Owner, MethodArguments} give a substituted view plus OpenSignature.

   Query API (on TypeShape and MethodShape; formatting identical to reflection)
   - IsValueType, IsEnum, IsInterface, IsGenericType, IsGenericTypeDefinition, GetGenericTypeDefinition, GetGenericArguments, MakeGenericType, MakeArrayType([rank]), MakeByRefType, MakePointerType, GetElementType, IsGenericParameter, GenericParameterPosition, DeclaringType, DeclaringMethod, BaseType, GetInterfaces, IsAssignableFrom, ContainsGenericParameters.
   - GetMethod / GetMethods / GetConstructor(s) / GetField(s) / GetProperty / GetProperties / GetEvent(s), taking System.Reflection.BindingFlags and returning MemberLookupResult {Found | NotFound | Ambiguous}.
   - GetEnumUnderlyingType, GetCustomAttributes(): AttributeData[] (pseudo attributes raised from tables, as reflection does), FullName, Name, Namespace, AssemblyQualifiedName, ToString.
   - MethodShape adds GetParameters, ReturnType, IsGenericMethodDefinition and MakeGenericMethod.

   Values
   - CustomModifier(IsRequired, Modifier).
   - AttributeData {Constructor: MethodShape, Fixed: TypedConstant[], Named: (Name, IsField, TypedConstant)[], Blob?}.
   - ConstantValue(ConstantTypeCode, Value). The constant rule encodes the DECLARED type: an enum uses its underlying type, Nullable<T> uses T, and a reference type gets CLASS with 4 zero bytes. W2.3's PAB probe confirms the rule; any difference from PAB is the declared ScopeMap class constant-encoding.

   Pseudo-custom attributes (contract frozen here; lowering half implemented in W2.3, raising half in W3.3)
   - PseudoAttributeLowering lives in Metadata/Attributes/PseudoAttributeLowering.nl and is the single classifier.
   - PseudoAttributeTarget {Assembly, Module, Type, Method, Constructor, Field, Parameter, ReturnValue, Property, Event, GenericParameter}.
   - TryLower(target, attributeType: TypeDefKey, blob: byte[], out lowered: LoweredAttribute): bool. LoweredAttribute {TypeFlags?, MethodFlags?, MethodImplFlags?, FieldFlags?, ParamFlags?, ClassLayout(pack, size)?, FieldOffset?, Marshal(blob)?, ImplMap(moduleName, entryPoint, flags)?}.
   - Raise(symbol): AttributeData[]. This is the reflection-parity read of attributes stored as flags and tables.
   - The per-target table equals PAB's as measured black-box by W2.3. An intercepted attribute never becomes a CustomAttribute row.

   Special and well-known types
   - SpecialType: the ELEMENT_TYPE-encodable set plus ValueType, Enum, Array, Delegate, MulticastDelegate and Nullable`1.
   - Named(core System.X) interns to Special.
   - WellKnownType and WellKnownMember descriptors carry Id, Namespace, MetadataName, Arity, AssemblyHint and a member signature descriptor.
   - Wk.<Name> accessors read the ambient MetadataCompilationScope. Resolving a missing descriptor produces a located MetadataDiagnostic. Whichever package first surfaces one to users adds its DiagnosticCatalog entry and errors page.

   Compilation, algebra and source symbols
   - MetadataCompilation {Catalog, SourceModule, Synthesized, Shapes, CoreLibrary, WellKnown}.
   - MetadataCompilationScope.Open(c) has exactly two production openers: the emit thread and AnalyzerMetadataLoadSurface.Attach.
   - No static field holds a shape, symbol or catalog object outside Metadata/Compilation/**. The ratchet enforces this.
   - TypeAlgebra: Substitute, IsAssignableTo (I.8.7 + ArrayIntrinsics + Nullable boxing), InterfaceClosure, FindImplementation, SatisfiesConstraints, Unify, SignatureEquals(includeModifiers).
   - SourceModuleSymbolBuilder: DeclareType(key, kind, nsKind, attrs, declId) returns an incomplete TypeSymbol; it has completion setters with a lazy resolver, Freeze, and AppendSynthesized until the writer freezes.

   Catalog contracts
   - IReferenceImageProvider {TryGetImage(path, out byte[]), Paths}.
   - IReferenceAssemblyResolver {Resolve(requesting, AssemblyIdentity): path?}.
   - IMetadataCatalog {TryFindType(ns, metadataName, out TypeSymbol, out CatalogLookupStatus), TryFindNested, ModuleOf, ForwardedFrom}.
   - CatalogLookupStatus {Found, Missing, Unknown}.
   - Phase-1 providers: the reference paths MLC reads, plus Model/ColumnarTransitionalHostScopeImages (W2.6, deleted in W7.2) for host-scope assemblies.

   CompilerWorkCounters semantics
   - referenceAssembliesLoaded counts a reference image opened for a compilation at a path outside the installed runtime (ReferenceImageSnapshotStore.IsInstalledRuntimePath), once per path per compilation, at exactly the paths MLC counts today.
   - Until W7.2, the MLC sites remain the only counting sites: ExternalAssemblyScan.nl:402 and :710, AnalyzerMetadataLoadSurface.nl:405, AnalyzerMetadataAssemblyResolver.nl:135. Catalog opens are not counted. W7.2 moves counting to the catalog with identical rows.
   - processesSpawned counts every process started on a request's critical path, including the TestRunner for an in-process nlc test. A standby runner started at daemon warm-up is not counted in the request.
   - Every package that moves a row declares the delta in its brief. The integrator re-baselines agent-loop-baseline.golden.json and bootstrap-build-baseline.golden.json with row-by-row explanations.

3. Writer API (W1.3)

   Module
   - ModuleDefinitionBuilder.Create(identity, moduleName, outputKind, compilation).
   - Members: AddAssemblyAttribute(ctor: MethodShape, blob), DefineType(symbol, attrs, base?, declaring?), DefineSyntheticType(owner, name, attrs, base?, declaring?), SetEntryPoint(method), Serialize(options, out image, out decline): bool. MetadataOnly(options) is optional and used by the projector. W6.19 may add AddManifestResource(name, bytes, attributes).

   Definition builders (Reflection.Emit member names)
   - TypeDefinitionBuilder: DefineField, DefineMethod, DefineConstructor, DefineDefaultConstructor, DefineTypeInitializer, DefineProperty, DefineEvent, DefineMethodOverride, AddInterfaceImplementation, DefineGenericParameters, SetParent, SetCustomAttribute(ctor, blob), SetLayout, DefineNestedType, DefinePInvokeMethod, CreateType (freeze marker), Symbol, AsShape().
   - MethodDefinitionBuilder: DefineGenericParameters, SetSignature, SetReturnType, SetParameters, DefineParameter, SetImplementationFlags, SetCustomAttribute, GetILGenerator(): IlBodyBuilder, Symbol, AsShape().
   - FieldDefinitionBuilder: SetConstant, SetOffset, SetRvaData, SetMarshal, SetCustomAttribute.
   - PropertyDefinitionBuilder: SetGetMethod, SetSetMethod, SetConstant.
   - EventDefinitionBuilder: SetAddOnMethod, SetRemoveOnMethod, SetRaiseMethod.
   - ParameterDefinition: SetConstant, SetCustomAttribute.
   - GenericParameterDefinition: SetGenericParameterAttributes, SetBaseTypeConstraint, SetInterfaceConstraints, SetCustomAttribute.

   Rules
   - SetCustomAttribute(ctor, blob) on every builder routes through PseudoAttributeLowering.
   - SetConstant(value) encodes per the section 2 constant rule, using the declared type from the builder's signature.
   - Every MemberRef and MethodSpec signature carries the target's full custom-modifier chain in metadata order, for definitions and references alike.
   - Members of a generic type, including a type's own members referenced from its own body, are a MemberRef on a TypeSpec with the open signature.

   IL
   - IlOpCode {Value: ushort, Size, OperandKind, StackPop, StackPush, Flow, Name}. IlOpCodes.<every System.Reflection.Emit.OpCodes field name, spelled identically>. IlOpCode.FromValue(ushort).
   - IlLabel(Id). IlLocal(LocalType: TypeShape, LocalIndex, IsPinned).
   - IlBodyBuilder:
     - Emit(op) / Emit(op, int|long|float|double|string|short|byte|sbyte|IlLabel|IlLabel[]|IlLocal|TypeShape|MethodShape|FieldShape)
     - DeclareLocal(TypeShape, pinned = false), DefineLabel, MarkLabel
     - BeginExceptionBlock(): IlLabel, BeginCatchBlock(TypeShape?), BeginExceptFilterBlock, BeginFinallyBlock, BeginFaultBlock, EndExceptionBlock
     - MarkSequencePoint(document, span), ILOffset

   Transitional facade
   - ColumnarTransitionalIl has the same member names. Until W4.1 it takes reflection operands; from W4.1 it also takes model operands.
   - ColumnarTransitionalLocal(LocalType: Type, LocalIndex) and ColumnarTransitionalIl.For(builder).
   - Removed in W7.1.

4. Quarantine grammar and ratchet tokens
- Transitional code lives only in ColumnarTransitional*.nl or AnalyzerTransitional*.nl (in any project), or on lines tagged `// TRANSITIONAL(W7.1)` or `// TRANSITIONAL(W7.2)`.
- The shadow env var is read in exactly one function. In adopt mode, exactly one quarantined catch in ColumnarTransitionalDefinitions produces the writer-only verdict.
- WriterBoundaryRatchet (W1.10) scans every production .nl in src/ with word-boundary, qualifier-aware matching. Tokens:
  - Reflection.Emit type names (TypeBuilder, MethodBuilder, FieldBuilder, ConstructorBuilder, GenericTypeParameterBuilder, EnumBuilder, PropertyBuilder, EventBuilder, ParameterBuilder, CustomAttributeBuilder, ILGenerator, LocalBuilder, PersistedAssemblyBuilder);
  - `import System.Reflection.Emit`;
  - `OpCodes.` not preceded by an identifier character, so `IlOpCodes.` never counts;
  - MetadataLoadContext; Mono.Cecil;
  - Assembly.Load*/LoadFrom/LoadFromAssemblyPath; AppDomain.CurrentDomain.GetAssemblies;
  - `is TypeBuilder`;
  - reflection declaration types: System.Type, `: Type`, `Type[]`, MethodInfo, ConstructorInfo, FieldInfo, PropertyInfo, EventInfo, ParameterInfo, MethodBase, MemberInfo;
  - host catalogs: RequiredRuntimeTypes, WellKnownTypeCatalog, RuntimeContext, and ExternalAssemblyScan's RuntimeAssembliesInScope, LoadedAcrossContexts and TryLoadHostAssemblyByName;
  - route-arounds: SurvivesAMemberRef, ReadOnlySpanElementRead, IsReferenceablePattern, HasRequiredModifiers, TryFindInitAutoPropertyBackingField;
  - the ColumnarTransitional, AnalyzerTransitional and TRANSITIONAL( markers;
  - static fields typed with TypeShape, TypeSymbol, MethodShape, FieldShape, IMetadataCatalog, ReferenceCatalog or MetadataCompilation outside Metadata/Compilation/**.
- MakeGenericType and MakeGenericMethod are not tokens, because they are also model query names.
- Metadata and MetadataWriter have a ceiling of 0 for the reflection, load, MLC and Cecil tokens from day one.
- Counts may only fall against the integrator-owned wave-base snapshot. Targets become 0 at the W7 close.

5. Oracle CLI (W1.6; verb files added by W2.5 and W2.7)

   Commands
   - emit-parity manifest --cli <path> --corpus <name> --out <file>
   - diff-manifest a b
   - dump <image>
   - compare a b --mode body-exact|semantic|definitions --scope <ScopeMap>
   - validate <image> (W2.5)
   - loadcheck <image...> (W2.7; runs in a TestRunner process)
   - rehearse <commit> (W2.7)
   - corpus run --arms base,head --oracles O0,O1,O2,O3,O4 --subset affected|canary|full --corpus examples|single-file|fixtures|native|compiler@<commit>|all --route sdk|cli

   Rules
   - The dispatcher reserves validate, loadcheck and rehearse. Each verb lives in its own *Command.nl file, and no package edits the dispatcher after wave 1.
   - compiler@<commit> means every N# src project at that commit (12 today, 15 after wave 1).
     - --route sdk is a dotnet build driven by the arm's stage-1 SDK package, materialized by tests/native/frozen-compiler, so it exercises the EmitIlAssembly MSBuild task.
     - --route cli is nlc build, wherever it builds the project; refusals are recorded with an owner.
   - Base arm: the mainline commit immediately before the batch. That is the wave-base tag for a package, merge-base with origin/systems-language for a branch, and HEAD~1 at the tip (the CompileTimeRunner.nl:810-816 rule). f6a6751bb is only W1.6's control build.
   - Caches are keyed by commit under $NSHARP_PARITY_CACHE, outside the repo.
   - A run refuses a verdict on zero rows, missing projects, or ctlA≠ctlB.
   - Shadow verdicts: identical | scoped(<class>) | writer-regression (blocks) | writer-only (counted; image kept; O2 required) | both-declined (decline reasons must match) | decline-mismatch (blocks).
   - O2 = ILVerify (empty baseline) + validate + loadcheck.
     - loadcheck runs Assembly.GetTypes(), then RuntimeHelpers.PrepareMethod on every non-generic MethodDef of every non-generic type, including .cctor bodies.
     - It then prepares the closed instantiations that the image's own TypeSpec and MethodSpec rows name.
     - No class constructor ever runs.
   - O5 = rehearse. In a throwaway worktree at /private/tmp/nsharp-agent-wt/mnw-rehearsal-<sha>, it runs reseed.sh through estate, then a stage-3 rebuild, then stage2==stage3, then O2 on the stage-2 compiler assemblies, then compiler-corpus O0/O1.
     - NSHARP_RESEED_PACKAGES_DIR and NSHARP_RESEED_STAGE_ROOT point at scratch.
     - BOOTSTRAP_DIR stays at the default, the worktree's own bootstrap/, because NuGet.config:4 restores from it.
     - It never commits.
   - stage2==stage3 is byte identity of every extracted tools/*.dll and lib/**/*.dll in both packages, plus SHA256SUMS over the extracted payloads, never nupkg bytes.
   - CI on every push runs: each tool project's controls and perturbation rows; O2 over the gate's images and the canary set; canary O0 against the merge-base. Integrator-only, at merge batches and wave boundaries: full-corpus O0/O1/O3/O4, the compiler corpus, rehearse, and O6.
   - Every tests/native tool project carries *.tests.nl rows. Heavy ones (emit-parity, frozen-compiler, producer-spike, compiler-codemods, catalog-parity, metadata-writer) are serial in native_requires_serial_run.

6. Codemod CLI (W1.7)
- Commands: rename-type, rename-qualifier, replace-call, move-to-extension, typeof-to-wk. Each is idempotent, has --check (non-zero when the tree is not normalized) and has --dry-run.
- The IL-vocabulary and emitter-split recipes are published.
- Seam proof: one real seam of ColumnarIlEmitter.nl is merged through the committed seed (Emit builds, front door 0, O0 identical including compiler@base) before W2.1's freeze is scheduled.
- Visibility policy: widened members become `internal`, which is package-private and emitted as CLR assembly; they never become public.
- The fallback split style is explicit-state helper classes, as in ColumnarArgumentInstructionEmitter, ColumnarEmitReflectionFacts and the ColumnarEmitContext derivation. W2.1 uses whichever style is proven.
- `codemod --check` is a merge gate for every in-flight stream touching Plan or Emit from the W2.1 freeze onward.

7. Determinism
- The ColumnarDeterministicPeIdentity algorithm is the single owner: a content-derived v4 MVID and a high-bit COFF stamp.
- It moves unchanged in W2.2 and keeps its name through wave 4. W5.4 renames it to DeterministicImageIdentity, with grants for its call sites and comment mentions.
- Rule for later work: PDB id first, then the debug directory, then the PE id.

8. Protocol
- Each WP is one Codex luna-xhigh brief in /private/tmp/nsharp-agent-wt/mnw-<wp>, branched from the wave-base tag, with an isolated NUGET_PACKAGES (symlinks to everything except nsharplang.*).
- Ownership:
  - A WP owns its files exclusively within its wave.
  - The only exception is a declared line-level grant with sequencing: the second owner's dependsOn names the first, and it edits only after that owner's MERGE.
  - Same-wave dependents otherwise consume only published API-freeze commits.
- Repins: a package may end with a package-local ownership repin commit (JSON header and OwnershipPolicy constant). Its acceptance means a fresh gate green with that commit. The integrator discards and regenerates repins and the WriterBoundary snapshot at merge.
- Seed identity:
  - From the program's first reseed, each seed is 0.1.0-seed.<n>. Its pins move together: 12 src/*/global.json files, Plan's Runtime pin, the seed's Sdk.props:10 default and verify-bootstrap.py.
  - scripts/lib/seed-check.sh fails closed when the effective cache's seed nupkgs differ from bootstrap/SHA256SUMS.
- The integrator, per merge batch or wave:
  1. Merge in dependency order.
  2. Regenerate repins and the snapshot.
  3. Run full-corpus O0 against the per-batch base, with the compiler corpus where required.
  4. Run a fresh `VSCODE_TESTS=skip ./scripts/test-all.sh --commit`, plus the VS Code gate when analyzer, LSP or IDE files moved.
  5. Run rehearse (waves 2-9).
  6. Run test-nativeaot-compiler.sh on the current manifest.
  7. Re-baseline the goldens from declared deltas, and refresh ci-test-durations.json.
  8. After W3.5, W4.2, W4.4, W5.10 and W8.2, do Claude computer-use visual verification, with owner approval obtained up front; Codex cannot run computer use.
  9. Re-measure in-flight branches and record their tips in the next briefs.
  10. At the wave-4 tag, freeze the residual census.
  11. Tag the wave and hand it to the integration session. Nobody commits on census/merge.
- Reference sources: briefs cite the W1.11 checkouts by path and SHA, or state black-box mode if the owner declined the download.

## Work packages

### W1.1 — Program charter, design doc, ownership map, deletion ledger

- **Wave:** 1  **Size:** S
- **Depends on:** none
- **Owns:** docs/design/metadata-native-writer.md; docs/design/full-compiler-nativeaot.md; memory/architecture.md; tasks/023-ecma335-metadata-writer.md

**Scope.** Land docs/design/metadata-native-writer.md, carrying: the decision; the fatal-flaw ledger; the critic-gap ledger (section 2b); the per-wave file-ownership map (one owner per file per wave, except declared line-level grants with sequencing); the deletion ledger, where each item names its deleting WP, including the modifier route-arounds, the host-scope provider, the reflection-keyed static caches, the verifier MLC rows and the package references outside the src/NSharpLang.Compiler.* glob; the brief template; the integrator checklist. Re-measure every section-1 count at the wave-1 base tag (mainline is 9818469cf as of 2026-10-13). Record the W1.11 reference-source paths and SHAs, or the owner's refusal. Point the design fork and slices 5-7 of full-compiler-nativeaot.md at this program, and mark tasks/023's il-writer A/B plan as superseded.

**Acceptance.** Owner sign-off recorded for each decision, or marked pending. Every critic-gap row maps to a WP. The ledger is complete. Section-1 counts re-measured at the wave-1 base tag. A fresh non-VS gate on the wave-1 base tag is recorded before tagging (the unification stream's own design doc says it does not run test-all.sh). Fresh docs-only non-VS gate green, with a package-local repin if needed.

### W1.2 — Metadata model project: contract and core

- **Wave:** 1  **Size:** L
- **Depends on:** none
- **Owns:** src/NSharpLang.Compiler.Metadata/project.yml; src/NSharpLang.Compiler.Metadata/NSharpLang.Compiler.Metadata.csproj; src/NSharpLang.Compiler.Metadata/global.json; src/NSharpLang.Compiler.Metadata/Identity/**; src/NSharpLang.Compiler.Metadata/Symbols/**; src/NSharpLang.Compiler.Metadata/Shapes/**; src/NSharpLang.Compiler.Metadata/Signatures/**; src/NSharpLang.Compiler.Metadata/Attributes/** (except PseudoAttributeLowering.nl); src/NSharpLang.Compiler.Metadata/WellKnown/**; src/NSharpLang.Compiler.Metadata/Algebra/**; src/NSharpLang.Compiler.Metadata/Compilation/**; src/NSharpLang.Compiler.Metadata/Source/SourceModuleSymbolBuilder.nl; src/NSharpLang.Compiler.Metadata/Source/SynthesizedDefinitionSet.nl; src/NSharpLang.Compiler.Metadata/Catalog/CatalogContracts.nl; src/NSharpLang.Compiler.Metadata/Diagnostics/**; docs/design/metadata-model-api-census.md

**Scope.** Create src/NSharpLang.Compiler.Metadata. Contents: AssemblyIdentity, TypeDefKey, the symbols, TypeShape and ShapeTable interning, member shapes, signatures with CustomModifier, AttributeData/TypedConstant, ConstantValue, SpecialType and the WellKnownType/WellKnownMember descriptor format with the Wk scope, TypeAlgebra (substitution, I.8.7 assignability, ArrayIntrinsics, unification, constraints), MemberLookup with reflection-quirk parity, MetadataCompilation and its Scope, SourceModuleSymbolBuilder, SynthesizedDefinitionSet, and Catalog/CatalogContracts (IReferenceImageProvider, IReferenceAssemblyResolver, IMetadataCatalog, CatalogLookupStatus). Primitive canonicalization; kind conflicts are diagnostics. Also freeze three contracts in firstWaveInterfaces section 2: the CompilerWorkCounters semantics for catalog image opens and TestRunner spawns; the PseudoAttributeLowering contract (lowering half implemented by W2.3, raising half by W3.3); the declared-type constant rule (confirmed by W2.3's probe). Layering: BCL plus the implicit NSharpLang.Runtime reference from the seed's Sdk.props:175. Publish an API-freeze commit within 2 working days, rebased onto W1.4's tag. Write the census mapping every reflection member used in Plan, Emit, Core, Model and CodeIntel.

**Acceptance.** Estate rows green: interning laws (8 threads); VAR/MVAR including inherited parameters; assignability including array intrinsics and Nullable boxing; quirk parity (ambiguous, hide-by-sig, FlattenHierarchy, interface GetMethods, GetInterfaces order); constructed-member substitution exposing the open definition. Two MetadataCompilations with different reference sets in one process share no interned object. Source-scan rows: no System.Type, Reflection.Emit or MLC in the project, and no static field typed with a shape, symbol or catalog type outside Compilation/**. The census covers 100% of the grep-derived members. API frozen by review.

### W1.3 — Writer contract and skeleton (MetadataWriter project)

- **Wave:** 1  **Size:** M
- **Depends on:** W1.2, W1.4
- **Owns:** src/NSharpLang.Compiler.MetadataWriter/project.yml; src/NSharpLang.Compiler.MetadataWriter/NSharpLang.Compiler.MetadataWriter.csproj; src/NSharpLang.Compiler.MetadataWriter/global.json; src/NSharpLang.Compiler.MetadataWriter/Definitions/**; src/NSharpLang.Compiler.MetadataWriter/IL/IlOpCode.nl; src/NSharpLang.Compiler.MetadataWriter/IL/IlOpCodes.nl; src/NSharpLang.Compiler.MetadataWriter/IL/IlOpFacts.nl; src/NSharpLang.Compiler.MetadataWriter/IL/IlLabel.nl; src/NSharpLang.Compiler.MetadataWriter/IL/IlLocal.nl; src/NSharpLang.Compiler.MetadataWriter/IL/IlBodyBuilder.nl; src/NSharpLang.Compiler.MetadataWriter/WriterOptions.nl; src/NSharpLang.Compiler.MetadataWriter/Serialization/ModuleSerializer.nl; src/NSharpLang.Compiler.MetadataWriter/Skeleton.tests.nl; tests/native/metadata-writer/project.yml

**Scope.** Create src/NSharpLang.Compiler.MetadataWriter with the frozen API: the definition builders (Reflection.Emit member names); IlOpCode/IlOpCodes (every OpCodes field name, with value, size, operand, stack and flow); IlOpFacts, IlLabel, IlLocal(TypeShape); IlBodyBuilder (ILGenerator member names, straight-line encoding only); WriterOptions; a skeleton ModuleSerializer. The API states that: SetCustomAttribute(ctor, blob) intercepts pseudo-custom attributes through PseudoAttributeLowering (implementation in W2.3); SetConstant encodes the declared type; every MemberRef and MethodSpec carries the target's full custom-modifier chain. Also create tests/native/metadata-writer/project.yml, which the wave-2 writer test files (W2.2, W2.3, W2.4) add to.

**Acceptance.** A test-only row proves IlOpCodes equals OpCodes field by field (name, value, size, operand, stack). A hello-world executable and a generic library round-trip through PEReader/MetadataReader with validation on and run in a TestRunner process. Builds under the seed published by W1.4. API frozen by review.

### W1.4 — Seed head: bootstrap surface probe, seed widening and seed identity

- **Wave:** 1  **Size:** M
- **Depends on:** none
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarWriterBootstrapSurface.tests.nl; src/NSharpLang.Compiler.Plan/ColumnarExternalBindingPlans.nl (admission predicates only); src/NSharpLang.Compiler.Plan/ColumnarExternalBindingPlans.tests.nl (admission rows only); src/NSharpLang.Compiler.Plan/project.yml (NSharpLang.Runtime pin line only; W1.5 edits the dependency lines after this merges); src/*/global.json (the msbuild-sdks NSharpLang.Sdk pin only; 12 files); src/NSharpLang.Sdk/Sdk/Sdk.props (NSharpLangRuntimeVersion default only); scripts/reseed.sh (pack version and verification; W1.5 edits the two arrays after this merges); scripts/verify-bootstrap.py; tests/native/gate-script-contracts/ReseedScripts.tests.nl (seed-identity rows); bootstrap/NSharpLang.Sdk.*.nupkg; bootstrap/NSharpLang.Runtime.*.nupkg; bootstrap/SHA256SUMS; bootstrap/README.md

**Scope.** Wave-1 head. W1.4 lands before W1.3 and W1.5 start. Every other wave-1 package rebases onto its merged tag (mnw-w1-seed) before its API-freeze commit and before its gate. (1) Probe: a seed-compiled estate probe for every SRM member the writer, catalog and PDB use. Writer side: MetadataBuilder Add* and GetOrAdd*; ReserveGuid/ReservedBlob writes; BlobBuilder writes; MetadataTokens; the 11-argument ManagedPEBuilder with deterministicIdProvider as a lambda and as a method group; BlobContentId.FromHash. Reader side: PEReader/MetadataReader row-struct accessors for every table (TypeDefinition, MethodDefinition, FieldDefinition, Parameter, MemberReference, TypeReference, TypeSpecification, MethodSpecification, CustomAttribute, Constant, GenericParameter, InterfaceImplementation, MethodImplementation, PropertyDefinition, EventDefinition, AssemblyReference, ExportedType with forwarder chains); BlobReader; GetBlobBytes loops; SignatureHeader; ImmutableArray<T>. PDB side: PortablePdbBuilder (idProvider) and DebugDirectoryBuilder entries. Already spelled by seed-compiled source and expected to pass: PEReader, MetadataReader, the TypeDefinition and ExportedType rows, GetBlobBytes, HandleKind, TableIndex (ExternalAssemblyScan.nl:222-231, :1753-1767; ReferenceImageSnapshotStore.nl:166-188). (2) For each decline: either record a spelling-around in a published table, or admit the member (admission predicates near ColumnarExternalBindingPlans.nl:187-199) and run an isolated two-stage reseed. The reseed must not overlap the concurrent wave-1 window. (3) Seed identity: reseed.sh packs the seed as 0.1.0-seed.<n> for both packages. With it move the 12 src/*/global.json SDK pins, Plan's NSharpLang.Runtime pin, and verify-bootstrap.py, which stops hard-coding Runtime 0.1.0 (:10-11). The seed SDK's Sdk.props NSharpLangRuntimeVersion default (:10) must resolve to the seed runtime, or the implicit reference (:175) would restore the dev runtime. Examples and templates keep the dev SDK 0.1.0. If no reseed is needed, the scheme lands unused and W5.1 is its first use.

**Acceptance.** The probe passes under the committed or republished seed. Every decline is listed with its resolution. If reseeded: the seed carries a distinct version; stage2==stage3, meaning byte identity of every extracted tools/*.dll and lib/**/*.dll plus SHA256SUMS over the extracted payloads (not nupkg bytes); verify-bootstrap.py passes locally and in CI (build.yml:40/115/177/342, publish.yml:24, deploy-website.yml:48); a row proves a cache holding the old seed cannot satisfy the new pins. ReseedScripts rows cover the version scheme. Package-local repin, regenerated by the integrator.

### W1.5 — Plumbing for the new projects

- **Wave:** 1  **Size:** L
- **Depends on:** W1.2, W1.3, W1.4, W1.6, W1.7, W1.8, W1.9
- **Owns:** NSharpLang.sln; src/NSharpLang.Sdk/NSharpLang.Sdk.csproj; src/NSharpLang.Sdk/Sdk/Sdk.targets (EmitNSharpIlAssembly Inputs only); src/NSharpLang.Compiler.Model/project.yml; src/NSharpLang.Compiler.Plan/project.yml (dependency lines; after W1.4); src/NSharpLang.Compiler.Driver/IncrementalBuildInputs.nl (IncrementalCompilerIdentity.Describe only); tests/scripts/test-all-core.sh; scripts/dev.sh; scripts/reseed.sh (COMPILER_PROJECT_DIRS and ESTATE_PROJECTS only; after W1.4); scripts/lib/packages.sh; scripts/verify-release.py; scripts/lib/seed-check.sh (new); scripts/build-native-prerequisites.sh (seed-check call only; after W1.9); scripts/ci-test-durations.json; scripts/ci-test-shards.sh (only if discovery needs a change); .github/workflows/build.yml; tests/native/*/project.yml (compiler-DLL rows only; codemod); tests/native/gate-script-contracts/SdkEmitStampPaths.tests.nl; tests/native/gate-script-contracts/SelfHostFrontDoor.tests.nl; tests/native/gate-script-contracts/DevScript.tests.nl; tests/native/gate-script-contracts/CiTestSharding.tests.nl; tests/native/gate-script-contracts/GateStepInputSets.tests.nl; src/NSharpLang.Cli/Cli.csproj (ProjectReference rows only; after W1.9)

**Scope.** Wire Metadata, MetadataWriter and TestRunner into every build, pack, gate and CI list. Starts after W1.4 and W1.9 merge and after the API freezes of W1.2, W1.3, W1.6, W1.7 and W1.8. Decision recorded: the three projects are analyzed on the SDK route. They are not added to the shrink-only Sdk.targets:15 emit-only list, which matches the seed's default for unnamed projects, so the decision takes effect without a reseed. They take the implicit NSharpLang.Runtime reference (seed Sdk.props:175). Lists to update: NSharpLang.sln; the NSharpLang.Sdk.csproj tools payload; the Model->Metadata and Plan->MetadataWriter edges; reseed.sh COMPILER_PROJECT_DIRS and ESTATE_PROJECTS (:52-53, sequenced grant after W1.4); scripts/lib/packages.sh NSHARP_PACKAGE_SPECS (:7-20); verify-release.py's expected set (:8-11); in test-all-core.sh, the format list (:326-337), SELF_HOST_PROJECTS/SELF_HOST_CEILINGS (:409-421, :646-658; 14 projects, Metadata first, ceilings 0), BOOTSTRAP_TEST_PROJECTS (:741-749), native_requires_serial_run (:804-839: add emit-parity, frozen-compiler, producer-spike, compiler-codemods) and the step-cache COMMON set (:204: add bootstrap/); dev.sh ESTATE_PROJECTS (:94-102) and the --since mapping (Metadata and MetadataWriter are central); .github/workflows/build.yml (:57 format list, builds, a canary-oracle job running W1.6's canary O0 and O2 subset); IncrementalCompilerIdentity.Describe (IncrementalBuildInputs.nl:262-275: add Metadata and MetadataWriter, plus the already-missing Tooling and Compiler.dll) and the Sdk.targets:201 Inputs; the 44 tests/native/*/project.yml compiler-DLL lists (codemod adding Metadata and MetadataWriter rows). Add a fail-closed seed check, scripts/lib/seed-check.sh, which compares the effective cache's seed nupkgs with bootstrap/SHA256SUMS. It is called from dev.sh, test-all-core.sh and build-native-prerequisites.sh (call line by grant after W1.9) and shared with reseed_verify_restored_packages. Update the contract tests: SdkEmitStampPaths (every Driver-reachable compiler project is in COMPILER_PROJECT_DIRS and is either in the emit-only list or in the pinned analyzed list; IncrementalCompilerIdentity and the Sdk.targets Inputs both equal the project closure); SelfHostFrontDoor (14 projects); DevScript; CiTestSharding; GateStepInputSets. Edit Cli.csproj ProjectReference rows only by sequenced grant after W1.9, and only if transitive references fail.

**Acceptance.** The new projects build under the current seed with analysis on. dev.sh --list and --since route them. The self-host front door checks 14 projects at ceiling 0. DRY_RUN=1 scripts/reseed.sh lists them in both arrays. scripts/pack-nuget.sh produces NSharpLang.Compiler.Metadata and NSharpLang.Compiler.MetadataWriter packages, and verify-release.py passes on that output. ci-test-shards.sh discovers the two new estates. The contract rows pass, and a perturbation dropping one assembly from either identity list fails. The seed check refuses a tampered cached nupkg (row). CI build.yml formats and builds the new projects. installed-toolchain-integration (40) proves the DLLs ship. Fresh non-VS gate green with a package-local repin.

### W1.6 — Parity and oracle tooling, including the compiler corpus

- **Wave:** 1  **Size:** L
- **Depends on:** none
- **Owns:** tests/native/emit-parity/**; tests/native/frozen-compiler/**; tests/native/compile-time-bench/CompileTimeRunner.nl; tests/native/compile-time-bench/project.yml; tests/native/gate-script-contracts/CompilerPerformanceGate.tests.nl

**Scope.** Build tests/native/emit-parity with: manifest (O0) and diff-manifest; dump/compare (O1 with entity keys, resolved operands, semantic order keys for fields, methods, params and EH clauses, orphans excluded, ScopeMap with per-class controls); corpus run (O3 counts and run contracts, O4 check JSON); affected/canary/full subset selection. Corpora: examples, single-file, fixtures, native, and compiler@<commit>, which is every N# src project at that commit (12 today, 15 after wave 1). The compiler corpus has two routes: --route sdk is a dotnet build driven by the arm's stage-1 SDK package, so it exercises the EmitIlAssembly task; --route cli is nlc build, wherever that builds a compiler project (UNVERIFIED; record refusals with an owner). The dispatcher reserves the validate (W2.5), loadcheck and rehearse (W2.7) verbs, each in its own *Command.nl file; nobody edits the dispatcher after wave 1. Base arm: the mainline commit immediately before the batch, by the CompileTimeRunner.nl:810-816 rule (the wave-base tag for packages, merge-base with origin/systems-language for branches, HEAD~1 at the tip). f6a6751bb is used only for controls. Move base-compiler preparation (BenchPrepareBaseCompiler, BenchBaseCompilerCliPath, BenchPrepareBaseCliProject, BenchApplyHeadCliDependencyClosure) into tests/native/frozen-compiler as the single owner. Extend it to materialize an arm as a CLI and as a stage-1 SDK package, with a commit-keyed cache outside the repo. compile-time-bench consumes it, and CompilerPerformanceGate.tests.nl:11-27 is re-pointed with the same assertions. Every tool project carries *.tests.nl rows (controls and perturbations). Publish wall times and merge-queue capacity.

**Acceptance.** ctlA==ctlB across O0/O1/O3/O4 on the full corpus, including compiler@base by the SDK route. A one-character perturbation and a struct-field swap are detected and correctly keyed. Missing or empty input is refused. Base-arm selection rows (branch picks merge-base, tip picks HEAD~1). compile-time-bench behaviour unchanged, and CompilerPerformanceGate passes against the new owner. Every tool project has test rows. Timings and queue capacity recorded.

### W1.7 — Semantic codemod toolkit and one real seam

- **Wave:** 1  **Size:** M
- **Depends on:** W1.6
- **Owns:** tests/native/compiler-codemods/**; src/NSharpLang.Compiler.Emit/ColumnarIlEmitter.nl (the one seam only, line-level); src/NSharpLang.Compiler.Emit/ColumnarTupleLabelFacts.nl (or the chosen seam file; new)

**Scope.** Build an N# test-scope tool, tests/native/compiler-codemods, on the compiler's semantic model. Operations: rename-type, rename-qualifier, replace-call-with-facade, move-to-extension (moves methods to func F(this e: C) in other files, qualifies member references, rewrites bare calls, adjusts visibility), and typeof-to-Wk. Each is idempotent and has --check and --dry-run. Ship the IL-vocabulary recipe and the emitter-split recipe. Before W2.1's freeze is scheduled, land ONE real seam end to end through the committed seed: the smallest cohesive region from the W2.1 seam list (for example TupleLabelFacts), moved into its own file. Verified starting shape: ColumnarIlEmitter has 76 private fields (44 private readonly) and 632 private functions (493 instance, 139 static); its only non-private function is TryEmitColumnarAssembly (:4742); src/ has no production extension function. Visibility policy: widened members become internal (package-private, emitted as CLR assembly; website/docs/language-tour.md:3480-3486), never public. If extension functions fail through the seed, prove the fallback style on the same seam: helper classes with explicit state objects, as in ColumnarArgumentInstructionEmitter, ColumnarEmitReflectionFacts and the ColumnarEmitContext derivation. W2.1 uses whichever style is proven.

**Acceptance.** The IL recipe, applied to a scratch copy of the tree, compiles and is O0-identical. Re-application is a no-op. The real seam is merged: Emit builds with the committed seed, the self-host front door is at 0, and O0 is identical on the full corpus, including compiler@base by the SDK route. The chosen split style and visibility policy are recorded, and W1.1 records them in the design doc. The full tree runs in under 2 minutes. compiler-codemods has test rows.

### W1.8 — Source-symbol producer and emit-only spike

- **Wave:** 1  **Size:** S
- **Depends on:** none
- **Owns:** tests/native/producer-spike/**; systems-language-closeout/decodes/metadata-producer-spike.md

**Scope.** Measure and record a decision on: (a) the SDK-route build cost of the 8 compiler projects with analysis versus the Sdk.targets:15 emit-only exception; (b) the cost of a declarations-only analyzer pass; (c) DeclarationId join mismatches (AST spans versus columnar node tables) over the 21 examples, the 154 native projects and every N# src project; (d) the inventory of analyzer declaration owners. producer-spike carries test rows. W1.5 marks it serial.

**Acceptance.** Join mismatches are 0, or each is listed with a fix owner. Costs are measured as medians. The recommendation is signed off by the owner. producer-spike has test rows.

### W1.9 — Out-of-process test execution and image loading (NSharpLang.TestRunner)

- **Wave:** 1  **Size:** L
- **Depends on:** none
- **Owns:** src/NSharpLang.TestRunner/**; src/NSharpLang.TestHost/ReflectionTestRunner.nl; src/NSharpLang.TestHost/XunitTestRunner.nl; src/NSharpLang.TestHost/NativeTestLoadContext.nl; src/NSharpLang.TestHost/TestWorkerHost.nl; src/NSharpLang.TestHost/TestCommandHost.nl; src/NSharpLang.TestHost/WatchCommandHost.nl; src/NSharpLang.TestHost/CliPipeline.nl; src/NSharpLang.Compiler.Driver/TestCommandKernels.nl; src/NSharpLang.Compiler.Driver/DaemonExecHost.nl; src/NSharpLang.Compiler.Driver/DaemonExecKernels.nl; src/NSharpLang.Cli/Cli.csproj (runner copy and reference rows); scripts/lib/toolset.sh; scripts/publish-toolset.sh; scripts/install.sh; scripts/build-native-prerequisites.sh; src/NSharpLang.Compiler.Model/DiagnosticCatalog.nl (runner diagnostic lines); website/docs/errors/ (the new runner diagnostic page); website/docs/cli-reference.md (nlc test section)

**Scope.** Create a framework-dependent N# app that references no compiler assembly. It loads the emitted test assembly, runs native, xunit and NUnit tests, and streams the TestWorkerHost protocol. It has a persistent mode for daemon and watch, generalizing today's __test-worker (TestWorkerHost.nl). Move the loads at ReflectionTestRunner.nl:28, XunitTestRunner.nl:398-399/514 and NativeTestLoadContext.nl:27 into it. Timeouts, filters and output modes are preserved. Add a loadcheck verb for O2: Assembly.GetTypes(); then RuntimeHelpers.PrepareMethod on every non-generic MethodDef of every non-generic type, including .cctor bodies (compiled only; no class constructor runs, since cctors execute user code); then the closed instantiations named by the image's own TypeSpec and MethodSpec rows. Runner locator: the dev bin beside Cli.dll, the installed toolset (scripts/lib/toolset.sh:315-355 publishes lib/nlc, lib/nsharp-lsp and bin), the SDK tools folder, and a NativeAOT nlc. A missing runner is a fail-closed located diagnostic, with a DiagnosticCatalog entry and a website/docs/errors page. Deployment: Cli.csproj copy rules; publish-toolset.sh, install.sh and build-native-prerequisites.sh, which archives src/NSharpLang.TestRunner. Daemon routing (DaemonExecKernels.nl:193 routes test; the DaemonExecHost.nl warm-up hook) and TestHost/CliPipeline.nl worker dispatch (:43-44, :186). Counters: a runner spawn on the request path is CountProcessSpawned; a standby runner started at daemon warm-up is not. Declare the expected agent-loop golden deltas for the integrator: cold nlc test rows go from processesSpawned 0 to 1; daemon-warm rows are unchanged. Document nlc test's runner behaviour in website/docs/cli-reference.md.

**Acceptance.** O3 identical on 154 projects and the test examples. TestHost estates green. A source-scan row finds no LoadFromAssemblyPath/AssemblyResolve/Resolving in the compiler, CLI or TestHost. The runner references no compiler assembly. installed-toolchain-integration and scripts/smoke-turnkey-install.sh run nlc test through the runner. A toolset without the runner fails with the located diagnostic (row). A CI archive round-trip (build-native-prerequisites.sh --archive) contains TestRunner. loadcheck catches an injected missing interface implementation (control). nlc test medians are within +10% of 840/841/2,609 ms, or the owner accepts the delta. Counter deltas declared.

### W1.10 — Writer-boundary ratchet

- **Wave:** 1  **Size:** S
- **Depends on:** none
- **Owns:** tests/native/ownership-audit/WriterBoundaryRatchet.nl; tests/native/ownership-audit/WriterBoundaryRatchet.tests.nl; tests/native/ownership-audit/WriterBoundarySnapshot.nl

**Scope.** Add an N# source scan over every production .nl in src/: all N# projects, including Metadata, MetadataWriter, TestHost, LanguageServer and Playground. Matching is word-boundary and qualifier-aware. It counts per file: (1) Reflection.Emit type names (TypeBuilder, MethodBuilder, FieldBuilder, ConstructorBuilder, GenericTypeParameterBuilder, EnumBuilder, PropertyBuilder, EventBuilder, ParameterBuilder, CustomAttributeBuilder, ILGenerator, LocalBuilder, PersistedAssemblyBuilder); (2) import System.Reflection.Emit; (3) OpCodes. not preceded by an identifier character, so IlOpCodes. never counts; (4) MetadataLoadContext; (5) Mono.Cecil; (6) Assembly.Load*/LoadFrom/LoadFromAssemblyPath; (7) AppDomain.CurrentDomain.GetAssemblies; (8) is TypeBuilder; (9) reflection declaration types (System.Type, : Type, Type[], MethodInfo, ConstructorInfo, FieldInfo, PropertyInfo, EventInfo, ParameterInfo, MethodBase, MemberInfo); (10) host catalogs (RequiredRuntimeTypes, WellKnownTypeCatalog, RuntimeContext, and ExternalAssemblyScan.RuntimeAssembliesInScope, LoadedAcrossContexts and TryLoadHostAssemblyByName); (11) modifier route-arounds (SurvivesAMemberRef, ReadOnlySpanElementRead, IsReferenceablePattern, HasRequiredModifiers, TryFindInitAutoPropertyBackingField); (12) ColumnarTransitional, AnalyzerTransitional and TRANSITIONAL( markers; (13) static fields typed with TypeShape, TypeSymbol, MethodShape, FieldShape, IMetadataCatalog, ReferenceCatalog or MetadataCompilation outside Metadata/Compilation/**. MakeGenericType and MakeGenericMethod are deliberately not tokens, because they are also model query names. Counts may only fall against the integrator-owned wave-base snapshot. Metadata and MetadataWriter have a ceiling of 0 for the reflection, load, MLC and Cecil tokens from day one.

**Acceptance.** Green at head, with the baseline snapshot recorded (route-around baselines: 7, 7, 3, 4 and 3 occurrences). Perturbation rows: an injected token fails; a new file with a non-zero count fails; IlOpCodes. is not counted as OpCodes.; a model-side MakeGenericType in Metadata is not counted; a static TypeShape cache outside Metadata/Compilation fails.

### W1.11 — Pinned reference sources (owner-approved download)

- **Wave:** 1  **Size:** S
- **Depends on:** none
- **Owns:** (no repository files; paths and SHAs are reported to W1.1)

**Scope.** With the owner's approval (this is a download), make read-only shallow checkouts. dotnet/runtime at tag v10.0.5 goes to ~/repos/dotnet-runtime-v10.0.5. dotnet/roslyn at a pinned release tag goes to ~/repos/roslyn, the path AGENTS.md names. Neither exists on this machine today. Record the commit SHAs. Locate and record the paths of the PersistedAssemblyBuilder sources (ILGeneratorImpl, TypeBuilderImpl, MethodBuilderImpl, FieldBuilderImpl, ParameterBuilderImpl, PropertyBuilderImpl, ModuleBuilderImpl) and Roslyn's MetadataWriter and PEWriter sources, for the W2.2-W2.4 briefs. If the owner declines: W2.4 runs as a black-box differential port against PAB, and W2.3's pseudo-attribute and constant tables come only from its black-box probes.

**Acceptance.** Both checkouts exist at the recorded SHAs, are never modified, and the file-path table is published to W1.1. Or the owner's refusal is recorded and W2.4's brief switches to black-box mode.

### W2.1 — Mechanical emitter restructuring: IL codemod, transitional IL facade, emitter split

- **Wave:** 2  **Size:** XL
- **Depends on:** W1.3, W1.6, W1.7
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarTransitionalIl.nl; src/NSharpLang.Compiler.Plan/ColumnarTransitionalLocal.nl; every Plan/Emit .nl and .tests.nl naming OpCodes/OpCode/ILGenerator/LocalBuilder/Label/GetILGenerator (81 production files); src/NSharpLang.Compiler.Emit/ColumnarIlEmitter.nl and the new split files; src/NSharpLang.Compiler.Emit/ColumnarIlEmitter.tests.nl; tests/native/columnar-emit-facts/ColumnarIlEmitterOwnership.tests.nl

**Scope.** Precondition: the iterator-unification stream (landed through 9818469cf, still active in /private/tmp/nsharp-agent-wt/iterator-unify) passes codemod --check, and its tip is recorded in the brief. (a) Add ColumnarTransitionalIl and ColumnarTransitionalLocal: IlBodyBuilder member names, backed by ILGenerator through a generated IlOpCode-to-OpCode table. Apply the W1.7 IL recipe across Plan and Emit at merge time, on the tip: OpCodes. to IlOpCodes., ILGenerator, LocalBuilder, Label, the 45 GetILGenerator sites, and the executor's numeric opcodes. (b) In a declared freeze window of at most 72 hours, split ColumnarIlEmitter.nl into about 20 files along the measured seams, using the style and visibility policy W1.7 proved (extension functions or explicit-state helpers; widened members become internal). The seams: AssemblyEmitter 4746-7756, EmitTypeResolution, Lambda, SourceCall, LocalFunction, Statement, Vectorization, EmitFlowFacts, Expression, Pattern, StaticCall, TupleLabelFacts (already moved by W1.7), Operator, PreflightTyping, ContextualCall, InstanceCall, MethodGroup, Foreach, Interpolation, EventAndConstructor. Each extraction is one O0-checked commit. Publish the split map (old line range to new file) that later packages use to re-locate cited lines. Update the reflection-based private pins, stating reasons.

**Acceptance.** Full-corpus O0 byte identity after the codemod and after each split commit, including compiler@base by the SDK route. Green: the Plan (1,885) and Emit estates, columnar-emit-facts (228), the native corpus, the self-host front door, and an unchanged ILVerify. compile-time-bench within noise. No Emit file exceeds about 3.5k lines. The --check codemod is clean. Split map published.

### W2.2 — Writer serializer, reference table, PE and determinism owner

- **Wave:** 2  **Size:** L
- **Depends on:** W1.2, W1.3, W1.4
- **Owns:** src/NSharpLang.Compiler.MetadataWriter/Serialization/RowNumbering.nl; src/NSharpLang.Compiler.MetadataWriter/Serialization/ReferenceTable.nl; src/NSharpLang.Compiler.MetadataWriter/Serialization/TableEmitter.nl; src/NSharpLang.Compiler.MetadataWriter/Serialization/PeEmitter.nl; src/NSharpLang.Compiler.MetadataWriter/Serialization/*.tests.nl; src/NSharpLang.Compiler.MetadataWriter/Identity/**; src/NSharpLang.Compiler.Model/ColumnarDeterministicPeIdentity.nl (moved out); tests/native/metadata-writer/Serialization.tests.nl

**Scope.** Implement row numbering, ReferenceTable (dedup by interned identity, fixed traversal), sorted tables (GenericParam before attribute attachment; pre-sorted CustomAttribute, Constant and MethodSemantics), StandaloneSig, ImplMap/ModuleRef, ClassLayout, FieldLayout, FieldMarshal, layout and RVA, MetadataRootBuilder with validation on, and ManagedPEBuilder (strong-name 0, writer entry point). Lowered pseudo-attributes, from PseudoAttributeLowering (W2.3, coded against the W1.2 contract), become flags and these table rows, never CustomAttribute rows. Primitives in token position become TypeRefs. Move ColumnarDeterministicPeIdentity.nl unchanged (same namespace) from Model to MetadataWriter/Identity as the single owner. Add the metadataOnly hook API.

**Acceptance.** Every table round-trips through MetadataReader with ECMA ordering asserted. Synthetic modules run: nested generics, enums, layout, P/Invoke, events, properties, MethodImpl, static abstract members, defaults. A synthetic module applying every intercepted attribute on every target has zero CustomAttribute rows for them, plus the expected flags and rows. Two serializations are byte-identical, with a v4 MVID and a high-bit stamp. No SRM sort is triggered.

### W2.3 — Writer encoders, pseudo-attribute lowering, constant rule

- **Wave:** 2  **Size:** L
- **Depends on:** W1.2, W1.3, W1.4
- **Owns:** src/NSharpLang.Compiler.MetadataWriter/Encoding/SignatureEncoder.nl; src/NSharpLang.Compiler.MetadataWriter/Encoding/CodedIndex.nl; src/NSharpLang.Compiler.MetadataWriter/Encoding/CustomModifiers.nl; src/NSharpLang.Compiler.MetadataWriter/Encoding/ConstantEncoding.nl; src/NSharpLang.Compiler.MetadataWriter/Encoding/MarshalEncoding.nl; src/NSharpLang.Compiler.MetadataWriter/Encoding/*.tests.nl; src/NSharpLang.Compiler.Metadata/Attributes/PseudoAttributeLowering.nl (lowering half); tests/native/metadata-writer/Signatures.tests.nl; tests/native/metadata-writer/PabPseudoAttributeProbe.tests.nl; tests/native/metadata-writer/PabConstantProbe.tests.nl; tests/native/metadata-writer/Constants.tests.nl

**Scope.** Write the hand-written II.23.2 SignatureEncoder (element codes, CLASS/VALUETYPE from the kind, GENERICINST, arrays, BYREF/PTR/FNPTR, VAR/MVAR with inherited counts, CMOD in metadata order), CodedIndex, ConstantEncoding, MarshalEncoding, and the lowering half of Metadata/Attributes/PseudoAttributeLowering.nl. Two black-box PAB probes, recorded as tables. (a) Pseudo-attributes: apply each candidate (StructLayout, Serializable, SpecialName, ComImport, SuppressUnmanagedCodeSecurity, MethodImpl, DllImport, PreserveSig, FieldOffset, NonSerialized, MarshalAs, In, Out, Optional) on each target (assembly, module, type, method, constructor, field, parameter, return, property, event) through PAB SetCustomAttribute. Read the CustomAttribute rows, the flags, and the ClassLayout/FieldLayout/FieldMarshal/ImplMap rows with MetadataReader. PAB's interception list is documented but was not re-read locally (UNVERIFIED); this probe is the specification, and the W1.11 source cross-checks it if available. (b) Constants: PAB SetConstant on long, double, byte, char, short, float, int? and enum parameters with an int literal; null on a struct parameter and on an int? parameter; a string-enum default. Record the encoding, or the exception. Rule: encode the declared type (enum uses its underlying type, Nullable<T> uses T, a reference type gets CLASS null). Any difference from PAB is the declared ScopeMap class constant-encoding.

**Acceptance.** Golden vectors for every element type and modifier placement. At the wave-2 merge the integrator runs the cross-check against the W2.6 decoder. JIT binding smoke: an init setter on a constructed generic, in virtuals, ref readonly returns. Both probe tables are recorded. The lowering equals the probe on every (attribute, target) row. Constant rows check ParameterInfo.RawDefaultValue's type through the runner, and a C# consumer that omits the argument. The consumer is generated into a temp directory by the N# test and built with dotnet build, following the tests/scripts/test-async-iterator-cancellation-interop.sh precedent; no committed C# or shell file. The constant rule and any ScopeMap class are recorded.

### W2.4 — Writer IL body builder (port of ILGeneratorImpl v10.0.5)

- **Wave:** 2  **Size:** L
- **Depends on:** W1.2, W1.3, W1.4, W1.11
- **Owns:** src/NSharpLang.Compiler.MetadataWriter/IL/ExceptionRegions.nl; src/NSharpLang.Compiler.MetadataWriter/IL/MaxStack.nl; src/NSharpLang.Compiler.MetadataWriter/IL/LocalSignatures.nl; src/NSharpLang.Compiler.MetadataWriter/IL/MethodBodySerializer.nl; src/NSharpLang.Compiler.MetadataWriter/IL/IlBodyEncoding.nl; src/NSharpLang.Compiler.MetadataWriter/IL/IlBodyBuilderVsIlGenerator.tests.nl; src/NSharpLang.Compiler.MetadataWriter/IL/*.tests.nl; tests/native/metadata-writer/IlBodies.tests.nl

**Scope.** Implement operand narrowing, label fix-ups (an out-of-range short branch is a decline), EH regions with implicit leave/endfinally/endfilter, PAB's maxstack algorithm, LOCAL_SIG, tiny and fat headers with InitLocals, small and fat EH sections, user strings, pseudo-tokens, and a no-op sequence-point API. Source: the W1.11 pinned ILGeneratorImpl. If the owner declined W1.11, this is a black-box differential port, and the byte differential below is the specification. Add a test-only byte differential against PAB's ILGenerator.

**Acceptance.** At least 40 scripts plus 10k seeded random sequences are byte-identical to PAB ILGenerator, with token values masked. Coverage: local boundaries 3/4/255/256; nested try/catch/filter/finally/fault; a try inside catch and a try inside finally; header thresholds 63/64 and 8/9; small and fat EH. Bodies execute and pass ILVerify and loadcheck.

### W2.5 — N# ECMA validator

- **Wave:** 2  **Size:** M
- **Depends on:** W1.3, W1.6, W1.4
- **Owns:** src/NSharpLang.Compiler.MetadataWriter/Validation/**; tests/native/emit-parity/ValidateCommand.nl

**Scope.** Validate: table sort keys by coded value; contiguity; EH nesting and non-overlap; MemberRef-on-generic using a TypeSpec parent with an open signature; GenericParam sorted before attribute parents; CLASS/VALUETYPE consistency; primitive element-code rules; no CustomAttribute row whose constructor belongs to a pseudo-custom attribute type. Implement the reserved validate verb in its own file. Run it as a control over today's PAB images.

**Acceptance.** Every rule has a negative fixture. Findings on the PAB corpus are filed, or there are none.

### W2.6 — SRM reference catalog core and host-scope images

- **Wave:** 2  **Size:** L
- **Depends on:** W1.2, W1.4
- **Owns:** src/NSharpLang.Compiler.Metadata/Catalog/ReferenceCatalog.nl; src/NSharpLang.Compiler.Metadata/Catalog/ReferenceModule.nl; src/NSharpLang.Compiler.Metadata/Catalog/TypeNameIndex.nl; src/NSharpLang.Compiler.Metadata/Catalog/Forwarders.nl; src/NSharpLang.Compiler.Metadata/Catalog/SignatureDecoder.nl; src/NSharpLang.Compiler.Metadata/Catalog/MemberTables.nl; src/NSharpLang.Compiler.Metadata/Catalog/*.tests.nl; src/NSharpLang.Compiler.Model/SharedReferenceMetadata.nl; src/NSharpLang.Compiler.Model/ReferenceImageSnapshotStore.nl; src/NSharpLang.Compiler.Model/ColumnarTransitionalHostScopeImages.nl; tests/native/catalog-parity/**

**Scope.** Build ReferenceCatalog over IReferenceImageProvider (byte[] snapshots). The resolver interface is implemented in Model with the ReferenceImagePathResolver policy. Per-module, lazy, publish-once symbols. The name/arity index with ExportedType forwarders (nested exported types; requested versus defining assembly). Nested lookup with + and . spellings; the tri-state answer. Members, the N# SignatureDecoder (preserving the custom-modifier chain), generic constraints, MethodImpls, interface closure. Attach SharedReferenceMetadata.Catalog next to Context. Add a transitional host-scope provider, Model/ColumnarTransitionalHostScopeImages.nl, deleted in W7.2. It reads the Assembly.Location bytes of every assembly that ExternalAssemblyScan.RuntimeAssembliesInScope (:506-530), LoadedAcrossContexts (:485-487) and TryLoadHostAssemblyByName (:469) can return, on the CLI, daemon and SDK-in-MSBuild routes, so host types used by the compiler (YamlDotNet, MSBuild ITaskItem, Cecil) get exact images. A host assembly with an empty Location is a located decline. Counting stays at the MLC sites until W7.2 (firstWaveInterfaces section 2), so this package changes no golden rows. Add catalog-parity: a test-only MLC differential that compares member ORDER, plus recorded-query replay, with test rows.

**Acceptance.** Answers equal MLC's, in order, for: the net10 targeting pack, the runtime directory, the NuGet closure (YamlDotNet 16.3.0, Mono.Cecil 0.11.6, MSBuild 18.0.2, Extensions.Logging), and project outputs. The host-scope provider supplies an image for every host-scope assembly on the CLI, daemon and SDK-in-MSBuild routes, under JIT and R2R. A parallel stress row passes. Open plus index cost is no higher than MLC's on the large agent-loop fixture. Golden counters unchanged.

### W2.7 — Gate infrastructure 2: loadcheck, self-compile rehearsal, stage 3

- **Wave:** 2  **Size:** L
- **Depends on:** W1.5, W1.6, W1.9, W2.5, W2.6
- **Owns:** scripts/ilverify.sh; scripts/ilverify-baseline.txt; scripts/reseed.sh; scripts/test-nativeaot-compiler.sh; tests/scripts/test-all-core.sh; tests/native/emit-parity/LoadCheckCommand.nl; tests/native/emit-parity/RehearseCommand.nl; tests/native/gate-script-contracts/ReseedScripts.tests.nl; tests/native/gate-script-contracts/IlVerifyBaseline.tests.nl

**Scope.** (1) Extend ilverify.sh to every native test assembly and the compiler stage assemblies (empty baseline; old-writer findings are measured, then fixed or filed). (2) Add a validate step and a loadcheck step: emit-parity LoadCheckCommand drives the W1.9 runner over every image the gate builds. (3) Add a stage-3 rebuild and a stage2==stage3 compare to reseed.sh. The compare is byte identity of every extracted tools/*.dll and lib/**/*.dll plus payload SHA256SUMS, never nupkg bytes. (4) Add emit-parity rehearse <commit>, the self-compile lane, as an N# verb: a throwaway worktree at /private/tmp/nsharp-agent-wt/mnw-rehearsal-<sha>; NSHARP_RESEED_PACKAGES_DIR and NSHARP_RESEED_STAGE_ROOT in scratch; the default BOOTSTRAP_DIR. NuGet.config:4 restores from the checkout's own bootstrap/, so an alternate NSHARP_RESEED_BOOTSTRAP_DIR would be refused after verify (reseed.sh:110-155). It runs reseed.sh through estate, then stage 3, then O2 on the stage-2 compiler assemblies, then compiler-corpus O0/O1 against the base arm. It never commits and refuses on vacuous input. (5) Add build and execute modes to test-nativeaot-compiler.sh, with cross-host image comparison done by emit-parity manifest/diff-manifest (no new script). Mark catalog-parity and metadata-writer serial. W2.7 owns ReseedScripts and IlVerifyBaseline in wave 2.

**Acceptance.** The expanded ILVerify control is recorded. loadcheck runs on every gate image and catches an injected missing override (control). DRY_RUN reseed shows the stage-3 and compare steps. rehearse runs end to end on the wave-2 base: builds green, stage2==stage3, O2 clean, stage-2 estate green. The AOT build mode works on the roots that build today. The gate-script contracts are green. Fresh non-VS gate green with a package-local repin.

### W2.8 — AOT-safe CLI JSON envelopes and build identity

- **Wave:** 2  **Size:** M
- **Depends on:** W1.9, W1.5
- **Owns:** src/NSharpLang.Compiler.Driver/OutputFormatterJsonKernels.nl; src/NSharpLang.Compiler.Driver/OutputFormatterAstJsonKernels.nl; src/NSharpLang.Compiler.Driver/DaemonClient.nl; src/NSharpLang.Compiler.Driver/DaemonServer.nl; src/NSharpLang.Compiler.Driver/DaemonProtocolKernels.nl; src/NSharpLang.Compiler.Driver/PackCommandKernels.nl; src/NSharpLang.Compiler.Driver/DocCommandKernels.nl; src/NSharpLang.Compiler.Driver/FixCommandKernels.nl; src/NSharpLang.Compiler.Driver/CompilationArtifacts.nl; src/NSharpLang.Compiler.Driver/CliStatsKernels.nl; src/NSharpLang.Compiler.Driver/BatchQueryRunner.nl; src/NSharpLang.Compiler.Driver/BatchQueryOutputKernels.nl; src/NSharpLang.Compiler.Driver/TestCommandKernels.nl; src/NSharpLang.Compiler.Driver/IncrementalBuildInputs.nl

**Scope.** Replace the 42 reflection JsonSerializer envelope sites with typed writers in the check-envelope style. The sites: OutputFormatterJsonKernels 22, DaemonClient 4, DaemonServer 3, Pack/Doc/DaemonProtocol 2 each, and one each in TestCommandKernels, OutputFormatterAstJsonKernels, FixCommandKernels, CompilationArtifacts, CliStatsKernels, BatchQueryRunner and BatchQueryOutputKernels. Make IncrementalCompilerIdentity (MVID reads) and IncrementalConfigFingerprint (reflection walk) AOT-safe, keeping exactly the assembly coverage that W1.5's contract row requires. Add a test-only guard that compares against reflection.

**Acceptance.** Every envelope is byte-identical, with contract tests. No reflection serializer remains in Driver. The fingerprint guard catches an added ProjectConfig field. The AOT-safe identity covers exactly the assemblies in W1.5's closure contract. ModuleVersionId behaviour under AOT is measured.

### W3.1 — Definition tee, importer and shadow (Plan side)

- **Wave:** 3  **Size:** XL
- **Depends on:** W2.1, W2.2, W2.3, W2.4, W2.6
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarTransitionalDefinitions.nl; src/NSharpLang.Compiler.Plan/ColumnarTransitionalImporter.nl; src/NSharpLang.Compiler.Plan/ColumnarTransitionalWriterShadow.nl; src/NSharpLang.Compiler.Plan/ColumnarFreeFunctionScope.nl; src/NSharpLang.Compiler.Plan/ColumnarLambdaPlacementPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarRecordValueMemberPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarInitRequiredMemberEmitter.nl; src/NSharpLang.Compiler.Plan/ColumnarConstructorDeclarationPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarBaseTypePlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarGenericConstraintPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarFieldMetadataEmitter.nl; src/NSharpLang.Compiler.Plan/ColumnarParameterDefaultEmitter.nl; src/NSharpLang.Compiler.Plan/ColumnarSignatureMetadataEmitter.nl; src/NSharpLang.Compiler.Plan/ColumnarMethodImplAttributes.nl; src/NSharpLang.Compiler.Plan/ColumnarInterfaceRealization.nl; src/NSharpLang.Compiler.Plan/ColumnarDeclarationPlan.nl; src/NSharpLang.Compiler.Plan/ColumnarDefinitions.nl; src/NSharpLang.Compiler.Plan/ColumnarAttributeBlobs.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceAttributeBinder.nl; src/NSharpLang.Compiler.Plan/ColumnarTupleElementNameEmitter.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceSelfInstantiation.nl; src/NSharpLang.Compiler.Plan/ColumnarIteratorPlanner.nl (builder region, re-located at wave start, and the line-51 site only); src/NSharpLang.Compiler.Plan/ColumnarIteratorCancellationFacts.nl; the other Plan files holding TypeBuilder.GetX lines (rerouting edit only); tests/native/pseudo-attributes/**; tests/native/writer-shadow-provenance/**

**Scope.** Add ColumnarTransitionalDefinitions: one function per Reflection.Emit call, with an API freeze published on day 1. Every SetCustomAttribute mirror goes through PseudoAttributeLowering. In adopt mode, one quarantined catch turns a PAB exception into the writer-only verdict and continues on the writer. Add ColumnarTransitionalImporter: reflection object to catalog symbol by MVID and token, covering MLC, runtime-twin and host-scope (W2.6) objects; a TypeBuilder registry; structural decoding of instantiations. Add ColumnarTransitionalWriterShadow (env var read in one function; compare or adopt). Route through the tee: the Plan definers; the 59 Plan TypeBuilder.GetX lines (via BindOnInstantiation); the IsReadOnly CustomAttributeBuilder (as a blob); the async-cancel EnumeratorCancellation attachment. Add tests/native/pseudo-attributes: one row per intercepted attribute per target, including a [DllImport]-spelled native import, an explicit-layout struct with [FieldOffset] fields, [Serializable] with a [NonSerialized] field, [MarshalAs] on a field and on a P/Invoke parameter, and [In]/[Out]/[Optional] parameters. Any analyzer refusal of one of these is recorded as the row's expected located diagnostic. Add tests/native/writer-shadow-provenance: per route (CLI, daemon, SDK-in-MSBuild), compilations referencing a project-reference type, a NuGet type and host-scope types (ITaskItem, YamlDotNet IParser).

**Acceptance.** Shadow off: O0 identical. Shadow on: every TypeDef, MethodDef, Field, Param, Property, Event and CustomAttribute row is mirrored. The importer coverage table has no unmapped kind. The IsReadOnly blob keeps O0. In pseudo-attributes, each row is read with MetadataReader and shows zero CustomAttribute rows for the attribute plus the expected flag or ClassLayout/FieldLayout/FieldMarshal/ImplMap row, and the PAB and writer images agree. GetCustomAttributesData() is not used as the oracle, because reflection synthesizes pseudo attributes. In writer-shadow-provenance, every operand on every route maps to the catalog module whose identity equals the AssemblyRef PAB wrote, and the provider that supplied the image (reference path, NuGet or host scope) is asserted.

### W3.2 — Tee on the Emit side and IL mirroring

- **Wave:** 3  **Size:** L
- **Depends on:** W3.1, W2.1, W2.4
- **Owns:** src/NSharpLang.Compiler.Emit/ColumnarAssemblyEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarIteratorRealization.nl; src/NSharpLang.Compiler.Emit/ColumnarEventMemberEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarEntryPointRealization.nl; src/NSharpLang.Compiler.Emit/ColumnarInternalsVisibleToEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarLambdaEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarLocalFunctionEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarExpressionEmitter.nl; the other split Emit files holding GetX lines; src/NSharpLang.Compiler.Plan/ColumnarTransitionalIl.nl; systems-language-closeout/decodes/writer-shadow-burndown.md

**Scope.** Route through the tee: the walk (ColumnarAssemblyEmitter); iterator realization (DefineMachineType, EmitSync, EmitAsync); events; the entry point; InternalsVisibleTo (IVT); display and anonymous-type sites; the 40 Emit GetX lines. In shadow mode, ColumnarTransitionalIl mirrors every IL call into IlBodyBuilder. File the first burn-down report.

**Acceptance.** Shadow off: O0 identical. compare produces an image pair, or a classified writer-only or both-declined verdict, for every corpus compilation, with zero writer exceptions. The first O1 report is filed. It includes, as an explicit item, shadow O1 on compiler@base by the SDK route against the ScopeMap, with the writer-regression, writer-only and both-declined counts.

### W3.3 — Catalog attributes, nullability, constants, friend grants

- **Wave:** 3  **Size:** L
- **Depends on:** W2.6, W1.4
- **Owns:** src/NSharpLang.Compiler.Metadata/Catalog/AttributeDecoder.nl; src/NSharpLang.Compiler.Metadata/Catalog/WellKnownAttributeViews.nl; src/NSharpLang.Compiler.Metadata/Catalog/NullabilityDecoder.nl; src/NSharpLang.Compiler.Metadata/Catalog/ConstantDecoder.nl; src/NSharpLang.Compiler.Metadata/Catalog/FriendGrants.nl; src/NSharpLang.Compiler.Metadata/Catalog/AttributeDecoding.tests.nl; src/NSharpLang.Compiler.Metadata/Attributes/PseudoAttributeLowering.nl (raising half); tests/native/catalog-parity/Attributes.tests.nl; tests/native/catalog-parity/Nullability.tests.nl

**Scope.** Add the II.23.3 value decoder producing AttributeData, and well-known attribute views. Pseudo-attributes are rebuilt from tables through the raising half of PseudoAttributeLowering, which this package owns in wave 3. Add NullabilityDecoder (byte/byte[], context inheritance, NullablePublicOnly with includeInternals, substitution, events), constants including Decimal and DateTime, and IVT grants.

**Acceptance.** Results equal MLC's CustomAttributeData (including synthesized pseudo attributes), NullabilityInfoContext, GetRawConstantValue and InternalsVisibleToGrants on the same corpora.

### W3.4 — Well-known tables, TypeAlgebra completion, Wk scope, performance

- **Wave:** 3  **Size:** M
- **Depends on:** W2.6
- **Owns:** src/NSharpLang.Compiler.Metadata/WellKnown/**; src/NSharpLang.Compiler.Metadata/Algebra/**; src/NSharpLang.Compiler.Metadata/Shapes/ShapeTable.nl; src/NSharpLang.Compiler.Metadata/Compilation/**

**Scope.** Fill SpecialType, WellKnownType and WellKnownMember for every census family: 194 generic families, 140 BCL types, 22 members, SimdReductions/ValueTuple statics, and Json/Yaml/MSBuild/Runtime types. Bind Wk to MetadataCompilationScope; interning and Wk are per compilation. Add inference helpers. Tune interning and laziness. Replay the recorded corpus query pairs.

**Acceptance.** Every entry resolves on net10 and the project-reference corpus. Inference and assignability equal reflection on the recorded pairs, including array receivers. Two MetadataCompilations with different reference sets in one process share no shape, symbol or Wk entry. Bench check and build within noise.

### W3.5 — Analyzer reference hub

- **Wave:** 3  **Size:** L
- **Depends on:** W2.6
- **Owns:** src/NSharpLang.Compiler.Model/TypeInfoModels.nl; src/NSharpLang.Compiler.Model/ReflectionTypeInfoModels.nl; src/NSharpLang.Compiler.Model/TypeInfoIdentityFacts.nl; src/NSharpLang.Compiler.Model/TypeInfoFactories.nl; src/NSharpLang.Compiler.Model/AnalyzerReflectionTypeConversion.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerMetadataLoadSurface.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerWellKnownTypes.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerTransitionalMetadataBridge.nl; their *.tests.nl under src/NSharpLang.Compiler.Core/Model and Semantics

**Scope.** ReflectionTypeInfo and ExternalTypeInfo become NamedTypeInfo(TypeShape), with a TRANSITIONAL .Type through AnalyzerTransitionalMetadataBridge (exact MVID and token mapping). Reflection method, group and event infos sit over MethodShape. TypeInfoIdentityFacts compares keys. AnalyzerMetadataLoadSurface and AnalyzerWellKnownTypes resolve through the catalog by name. MLC is retained transitionally. Counter delta declared: none.

**Acceptance.** O4 byte-identical and O0 identical. Core estate (4,451) green. playground-tooling-surfaces and playground-diagnostic-spans green, and Playground.Wasm builds. One LSP session and one daemon session, each running two compilations with changed references, give O4 identical to fresh processes. VS Code-enabled gate, plus integrator visual verification (owner-approved) of hover, completion and diagnostics on BCL and NuGet types. Check medians within noise. Golden counters unchanged.

### W4.1 — Shadow burn-down and writer cutover

- **Wave:** 4  **Size:** XL
- **Depends on:** W3.1, W3.2, W2.5, W2.7
- **Owns:** src/NSharpLang.Compiler.MetadataWriter/** (except ReferenceAssembly/** and Pdb/**); src/NSharpLang.Compiler.Plan/ColumnarTransitional*.nl; tests/native/emit-parity/ScopeMap.nl; src/NSharpLang.Compiler.Emit/ColumnarAssemblyEmitter.nl (serialization tail); src/NSharpLang.Compiler.Plan/ColumnarModifiedMemberReferenceRepair.nl (deleted) and its tests; ledger sites: ColumnarCodePlan.nl, ColumnarCodePlanExecutor.nl, ColumnarEmitContext.nl, ColumnarConstructionPlanner.nl, ColumnarIteratorBodyScope.nl, ColumnarRangeIndexPlanner.nl, ColumnarIteratorPlanner.nl, ColumnarDirectCallPlanner.nl, ColumnarIteratorRealization.nl, ColumnarIlEmitter.nl and the split files holding record sites; tests/native/compilation-backend/CompilationBackend.tests.nl (repair rows); systems-language-closeout/decodes/writer-shadow-burndown.md

**Scope.** Drive shadow O1 down to ScopeMap classes on every corpus, compiler@base by the SDK route included, fixing the writer, tee and importer. The adopt-mode gate must pass. Then, in one commit, the writer image becomes the product, with these deletions: the PAB tail (:7686-7741); ColumnarModifiedMemberReferenceRepair with its ledger in 12 files and its tests, including the record sites ColumnarConstructionPlanner.nl:961-970 and ColumnarIlEmitter.nl:15617-15630, :18053 and :25766 (line numbers at f6a6751bb, re-located through the W2.1 split map); the now-dead ColumnarConstructionPlanner.SetterSignatureSurvivesAMemberRef copy (:990-1001); the ILGenerator half of the facade; the shadow switch. The facade gains model-operand overloads. The identity owner keeps the name ColumnarDeterministicPeIdentity; W5.4 renames it. PAB stays only as body-less shells.

**Acceptance.** A/B of the wave-4 base tag against head (f6a6751bb is not used): O1 ⊆ scope map on every corpus, including compiler@base by the SDK route; O2 (ILVerify, validator and loadcheck, empty baseline); O3 and O4 identical. Shadow O1 ⊆ ScopeMap on compiler@base, recorded before the cutover commit. BLOCKING self-compile rehearsal (emit-parity rehearse) at the cutover candidate: stage-1 and stage-2 builds succeed; ILVerify, validator and loadcheck are clean on the stage-2 compiler assemblies; the stage-2 estate is green; stage2==stage3. tests/native/pseudo-attributes is green on the writer image, with tables and flags equal to PAB's. writer-shadow-provenance is green. Also green: emit-determinism (4), the parallel-analysis IL identity rows, compilation-backend, census-init-required, readonly-init, record-with, iterators, census-exception-filters, census-emit-shapes, systems-vectorization-facts, reflection-emit-bootstrap, and the sdk-* projects. Front door 0. Bench build within noise. Fresh non-VS gate.

### W4.2 — Single source-symbol producer

- **Wave:** 4  **Size:** XL
- **Depends on:** W3.5, W3.4, W1.8
- **Owns:** src/NSharpLang.Compiler.Core/Semantics/AnalyzerTypeDeclarations.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerDeclarationContext.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerDeclarationWalkers.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerDeclarationPolicy.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerDeclarationConventions.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerSourceMemberDeclarations.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerParameterDeclarations.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerScopeStack.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerTypeResolver.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerSourceSymbols.nl; src/NSharpLang.Compiler.Core/Semantics/Analyzer.nl; src/NSharpLang.LanguageServer/Services/DocumentManager.nl; src/NSharpLang.Compiler.Model/Declarations.nl; src/NSharpLang.Compiler.Model/CompilerWorkCounters.nl; src/NSharpLang.Compiler.Driver/MultiFileCompiler.nl (producer call sites); src/NSharpLang.Sdk/Sdk/Sdk.targets; tests/native/gate-script-contracts/SdkEmitStampPaths.tests.nl; tests/native/producer-spike/** (deleted); their *.tests.nl

**Scope.** The analyzer declaration phase plus AnalyzerTypeResolver feed SourceModuleSymbolBuilder exactly once per compilation on every route: analyze+emit, check, the persisted subset, LSP (DocumentManager.nl constructs the Analyzer), Playground, and the SDK route per the W1.8 decision (retire Sdk.targets:15, or add a declarations-only mode). Analyzer.nl gets the scope-opener and producer wiring. Type parameters become GenericParameterTypeInfo. Source TypeInfos link to symbols. Add a definitions-only cross-check harness of producer symbols against emitted images. Delete producer-spike. The Sdk.targets change reaches the compiler's own build only at the next reseed, because the compiler is built by the seed's Sdk.targets; so this package carries a rehearsal with the changed SDK, and W5.1 depends on it. Update SdkEmitStampPaths for the emit-only switch. Declare the counter deltas (filesAnalyzed on the SDK route if the exception is retired).

**Acceptance.** CompilerWorkCounters show exactly one build per compilation on all routes, with the declared golden deltas. O4 and O0 identical. The cross-check has zero mismatches for declared types and members on the corpus. Core estate green. BLOCKING rehearsal: the compiler projects build through the stage-1 SDK carrying the changed Sdk.targets, with the producer on, and the stage-2 estate is green. SdkEmitStampPaths is updated and green. VS Code gate, plus integrator visual verification (owner-approved). Agent-loop check medians within noise.

### W4.3 — Reference-assembly projector (removes Cecil from the ref-asm path)

- **Wave:** 4  **Size:** L
- **Depends on:** W2.2, W2.3, W2.6, W3.3, W1.4
- **Owns:** src/NSharpLang.Compiler.Driver/ColumnarReferenceAssemblyWriter.nl; src/NSharpLang.Compiler.Driver/SdkEmitTaskKernels.nl; src/NSharpLang.Compiler.MetadataWriter/ReferenceAssembly/**; tests/native/reference-assembly-surface/**

**Scope.** Rewrite ColumnarReferenceAssemblyWriter as an image-to-image projector on the catalog plus the writer, keeping the same TryWrite signature. Port the retention rules verbatim, and port the CoreLib-to-owner rescope, with ReferenceTypeOwners computed by the catalog name index. The call to the identity owner keeps the current name; W5.4 renames it.

**Acceptance.** Rule rows pass: struct fields kept, explicit implementations kept, fixed-point closure including attribute types, entry point, < types, ldnull; throw bodies, ReferenceAssemblyAttribute, keepInternals. O1 of projector versus Cecil ⊆ scope map on the corpus. Green: sdk-reference-incrementality (8), reference-assembly-surface (3), sdk-project-reference-boundary (29, no CS0012), emit-determinism. No Mono.Cecil on the path.

### W4.4 — Analyzer metadata readers on the catalog

- **Wave:** 4  **Size:** L
- **Depends on:** W3.3, W3.5
- **Owns:** src/NSharpLang.Compiler.Model/NullabilityMetadataReflection.nl; src/NSharpLang.Compiler.Model/NullabilityGenericSubstitution.nl; src/NSharpLang.Compiler.Model/NullabilityFlowFacts.nl; src/NSharpLang.Compiler.Model/NullabilityMemberPostconditions.nl; src/NSharpLang.Compiler.Model/NullState.nl; src/NSharpLang.Compiler.Model/AnalyzerTupleElementNames.nl; src/NSharpLang.Compiler.Model/AnalyzerReachabilityAttributes.nl; src/NSharpLang.Compiler.Model/InternalsVisibleToGrants.nl; src/NSharpLang.Compiler.Model/InternalsVisibleToEmissionScope.nl; src/NSharpLang.Compiler.Model/EditorTypeCatalog.nl; src/NSharpLang.Compiler.Model/EditorTypeCatalogFacts.nl; src/NSharpLang.Compiler.Model/AssemblyTypeNameIndex.nl; src/NSharpLang.Compiler.Model/MemberAccessibility.nl; src/NSharpLang.Compiler.Model/ExternalAssemblyScan.nl (additive); src/NSharpLang.Compiler.Core/Semantics/AnalyzerAttributeValidator.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerAttributeUsageFacts.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerMetadataAssemblyResolver.nl; their *.tests.nl

**Scope.** Move the nullability, tuple-name, reachability, attribute-validator, accessibility and IVT readers to the catalog decoders. That includes InternalsVisibleToEmissionScope and the async-cancel AnalyzerAttributeValidator additions. EditorTypeCatalog uses the catalog index, including forwarders. ExternalAssemblyScan gains additive catalog-returning APIs; runtime pairing stays until W7.2.

**Acceptance.** O4 identical. Estates green, including NullabilityMetadataReflection (27) and EditorTypeCatalog/Facts (8/30). Green natives: census-external-nullability (21), census-internals-visible-to (28), census-nullable-metadata (7), async-iterator-cancellation. The AssemblyTypeNameIndex ConditionalWeakTable cache becomes per compilation. VS Code gate, plus integrator visual verification (owner-approved).

### W5.1 — Reseed S2 on the new writer

- **Wave:** 5  **Size:** M
- **Depends on:** W4.1, W2.7, W4.2
- **Owns:** bootstrap/NSharpLang.Sdk.*.nupkg; bootstrap/NSharpLang.Runtime.*.nupkg; bootstrap/SHA256SUMS; src/*/global.json (seed pins); src/NSharpLang.Compiler.Plan/project.yml (Runtime pin line)

**Scope.** Run the two-stage reseed with the stage-3 fixed point, using isolated NUGET_PACKAGES and NSHARP_RESEED_*. Publish under the distinct-version scheme (0.1.0-seed.<n>), moving the pins with it, so no worktree or cache can serve the old bytes under the same name. The seed carries W4.2's Sdk.targets change.

**Acceptance.** stage2==stage3 over the extracted DLLs and payload SHA256SUMS. ILVerify, validator and loadcheck clean on the stage-2 compiler assemblies. O1 of seed-built versus stage-2 ⊆ scope map. Estate (10,063) green on stage 2. verify-bootstrap.py passes locally and in CI. The seed check refuses the previous seed bytes. Fresh gate.

### W5.2 — Plan hub

- **Wave:** 5  **Size:** XL
- **Depends on:** W4.1, W3.4
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarCodePlan.nl; src/NSharpLang.Compiler.Plan/ColumnarCodePlanExecutor.nl; src/NSharpLang.Compiler.Plan/ColumnarStructuralTypeReferences.nl; src/NSharpLang.Compiler.Plan/ColumnarDefinitions.nl; src/NSharpLang.Compiler.Plan/ColumnarFragmentBindings.nl; src/NSharpLang.Compiler.Plan/ColumnarEmitContext.nl; src/NSharpLang.Compiler.Plan/ColumnarInputs.nl; src/NSharpLang.Compiler.Plan/ColumnarSiblingMethodDefinition.nl; src/NSharpLang.Compiler.Plan/ColumnarPlannerSupport.nl; src/NSharpLang.Compiler.Plan/ColumnarEmissionPlanner.nl; their *.tests.nl; pool-read-site lines in other Plan files (listed in brief)

**Scope.** ColumnarCodePlan pools become shapes and IlLocal. The reflection Add* overloads become TRANSITIONAL via ToModel, and the *WithSignature arrays collapse. The executor replays model operands, and its validator runs on TypeAlgebra, with an explicit self-instantiation rule replacing IsSubstitutableOpenDefinition. StructuralTypeKey becomes TypeDefKey (this drops ColumnarStructuralTypeReferences' MLC use). Definitions gain Symbol and Definition fields, and the ColumnarPropertyDef.IsInitOnly contract comment (ColumnarDefinitions.nl:376-382) is rewritten: init-ness is a definition fact, not a decline. EmitContext.Module() returns ModuleDefinitionBuilder. The ColumnarDefinitions ConditionalWeakTable cache becomes per compilation. Includes one-time pool-read patches in other Plan files.

**Acceptance.** O0 identical. Plan estate (1,885) green, with row deltas explained. scalar-code-plan, boolean-code-plan and columnar-emit-facts green. Zero ExternalAssemblyScan, RequiredRuntimeTypes, SharedReferenceMetadata, WellKnownTypeCatalog and MetadataLoadContext references in owned files. A daemon session running two compilations with changed references gives O0 identical to fresh processes.

### W5.3 — Emit hub

- **Wave:** 5  **Size:** L
- **Depends on:** W4.1, W3.4
- **Owns:** src/NSharpLang.Compiler.Emit/ColumnarIlEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarEmitTypeResolution.nl; src/NSharpLang.Compiler.Emit/ColumnarEmitReflectionFacts.nl; src/NSharpLang.Compiler.Emit/ColumnarArgumentInstructionEmitter.nl; their *.tests.nl

**Scope.** Emitter state field types move to shapes, with transitional accessors so split files are not touched. The entry and body driver, ColumnarEmitTypeResolution, ColumnarEmitReflectionFacts (EmitMethod/EmitConstructor/EmitType, 127 callers) and ColumnarArgumentInstructionEmitter take shapes, with TRANSITIONAL reflection overloads. The static s_noTypeParameters (ColumnarIlEmitter.nl:144) becomes per compilation.

**Acceptance.** O0 identical. Emit estate and columnar-emit-facts green.

### W5.4 — Transitional bridge, steward, identity rename

- **Wave:** 5  **Size:** M
- **Depends on:** W4.1, W4.2, W4.3
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarTransitional*.nl; src/NSharpLang.Compiler.Plan/ColumnarTransitionalBridge.nl; src/NSharpLang.Compiler.Model/CompilerWorkCounters.nl; src/NSharpLang.Compiler.MetadataWriter/Identity/**; src/NSharpLang.Compiler.MetadataWriter/Serialization/PeEmitter.nl (identity call only); src/NSharpLang.Compiler.MetadataWriter/ReferenceAssembly/** (identity call only); src/NSharpLang.Compiler.Driver/ColumnarReferenceAssemblyWriter.nl (identity call and comment only); src/NSharpLang.Compiler.Model/ExternalAssemblyScan.nl (comment lines 1290-1294 only); src/NSharpLang.Compiler.Driver/IncrementalBuildInputs.nl (comment lines 241-245 only)

**Scope.** Make ColumnarTransitionalBridge complete by reflection kind: ToModel, and ToReflection through the shell registry or the host MVID and token. Switch the tee to link mode, with a continuous cross-check of producer symbols against the walk. Steward the shared registries and counters. Rename ColumnarDeterministicPeIdentity to DeterministicImageIdentity (codemod rename-type), with grants for its call sites (MetadataWriter/Serialization/PeEmitter.nl and the projector) and the comment mentions (ExternalAssemblyScan.nl:1290-1294, IncrementalBuildInputs.nl:241-245, ColumnarReferenceAssemblyWriter.nl:34-37). No other wave-5 package owns these lines. The residual census is NOT done here: the integrator freezes it at the wave-4 tag.

**Acceptance.** Round-trip identity holds over every object observed in the corpus. The link-mode cross-check has zero mismatches. Zero occurrences of the old identity name remain. O0 identical.

### W5.5 — N#-kind erasure moves into the producer

- **Wave:** 5  **Size:** XL
- **Depends on:** W4.2, W3.3
- **Owns:** src/NSharpLang.Compiler.Metadata/Source/SourceErasure*.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerSourceSymbols.nl

**Scope.** In Metadata/Source/SourceErasure, cover: union and value-union, enum, record, newtype, SoA, holders, accessors and backing fields, init modreqs, default and static constructors, test types, pseudo-attribute classification (calling PseudoAttributeLowering, so source symbols carry lowered flags and layout), and the synthesized-attribute plan. The producer's Complete phase calls it. Includes its own definitions-only cross-check.

**Acceptance.** Predicted erased definitions equal the emitted images, with zero mismatches over the corpus, including tests/native/pseudo-attributes. O4 and O0 identical.

### W5.6 — Analyzer: identity, assignability, conversions

- **Wave:** 5  **Size:** XL
- **Depends on:** W4.2, W4.4
- **Owns:** src/NSharpLang.Compiler.Core/Semantics/AnalyzerAssignability.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerAssignabilityFacts.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerStructuralAssignability.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerClrTypeConversion.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerExternalTypeProbe.nl; src/NSharpLang.Compiler.Core/Semantics/ExternalQualifiedTypeResolver.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerTypeSubstitution.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerTypeReferenceFacts.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerOpenTypeSpecificity.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerWellKnownTypeFacts.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerGenericConstraintChecks.nl; src/NSharpLang.Compiler.Core/Semantics/ConstantConversionFacts.nl; src/NSharpLang.Compiler.Core/Semantics/TypeMismatchDisplay.nl; src/NSharpLang.Compiler.Core/Semantics/ForeachElementConversionFacts.nl; src/NSharpLang.Compiler.Model/AnalyzerConversionFacts.nl; src/NSharpLang.Compiler.Model/ColumnarTypeEquivalenceFacts.nl; src/NSharpLang.Compiler.Model/ValueTupleTypeFacts.nl; src/NSharpLang.Compiler.Model/RuntimeTypeShapeFacts.nl; src/NSharpLang.Compiler.Model/KnownReceiverSpellings.nl; src/NSharpLang.Compiler.Model/NumericLiteralFacts.nl; src/NSharpLang.Compiler.Model/ExternalUserDefinedConversions.nl; their *.tests.nl

**Scope.** One TypeAlgebra closure serves source and reference types. Delete the surrogate funnel (AnalyzerClrTypeConversion :113, :711, :482-533). Analyzer use of WellKnownTypeCatalog and RequiredRuntimeTypes stops; the deletion itself is in W7.2. The Reflection.Emit import and builder probes in ColumnarTypeEquivalenceFacts and RuntimeTypeShapeFacts go to zero.

**Acceptance.** O4 and O0 identical. Estates green: Assignability (27), AssignabilityFacts (16), ClrTypeConversion (16), ExternalTypeProbe (14), TypeSubstitution (14), ConversionFacts (21).

### W5.7 — Analyzer: binders, overloads, member resolution

- **Wave:** 5  **Size:** XL
- **Depends on:** W4.2, W4.4
- **Owns:** src/NSharpLang.Compiler.Core/Semantics/AnalyzerReflectionArgumentBinder.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerOverloadScoring.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerMemberResolution.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerMemberAccess.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerExtensionMethodResolution.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerSyntheticCallBinder.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerCallAnalysis.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerCallableReferenceFacts.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerGenericReceiverInference.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerFunctionTypeFactory.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerPassThroughOperands.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerTargetTypedOperands.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerReflectionMemberProbe.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerReflectionCallReporter.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerReflectionCallFinalizer.nl; src/NSharpLang.Compiler.Core/Semantics/TaskLikeTypeFacts.nl; src/NSharpLang.Compiler.Model/AnalyzerOverloadSpecificity.nl; src/NSharpLang.Compiler.Model/ReflectedMethodCache.nl; src/NSharpLang.Compiler.Model/ReflectedParameterDirection.nl; src/NSharpLang.Compiler.Model/ExplicitInterfaceMemberFacts.nl; their *.tests.nl

**Scope.** Re-key reflection binding to symbols and GenericParameterSymbol substitutions. Source and reference candidates rank on one path. CloseGenericRuntimeMethod becomes MakeGenericMethod on shapes. The ReflectedMethodCache ConditionalWeakTable becomes per compilation.

**Acceptance.** O4 and O0 identical, with overload flips reviewed. Estates green: ReflectionArgumentBinder (51), OverloadScoring (42), OverloadSpecificity (10), FunctionTypeFactory (29).

### W5.8 — Analyzer: construction, writes, imports

- **Wave:** 5  **Size:** M
- **Depends on:** W4.2
- **Owns:** src/NSharpLang.Compiler.Core/Semantics/AnalyzerConstruction.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerWriteTargets.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerAssignment.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerExplicitInterfaceImplementation.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerImports.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerImportUsageCredit.nl; their *.tests.nl

**Scope.** Move construction, write targets, assignment, explicit implementation and imports onto symbols. AnalyzerWriteTargets.PropertySetterIsInitOnly (:811-825) stays the language rule that an init accessor is not assignable outside construction, and reads MethodSymbol return modifiers. Its IsTypeBuilder helpers (13 lines) go to zero.

**Acceptance.** O4 and O0 identical. Owned estates green. An init property assigned outside construction still reports the same located diagnostic.

### W5.9 — Analyzer: expressions and statements

- **Wave:** 5  **Size:** XL
- **Depends on:** W4.2, W4.4
- **Owns:** src/NSharpLang.Compiler.Core/Semantics/AnalyzerOperatorExpressions.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerLoopSequence.nl; src/NSharpLang.Compiler.Core/Semantics/LoopSequenceTypeFacts.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerFunctionBodies.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerResourceStatements.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerExpressionStatements.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerLambdaAnalysis.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerVariableDeclaration.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerIdentifierResolution.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerArrayLiteral.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerSoaDirectColumnCalls.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerIndexAccess.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerExpressionTreeValidator.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerMatchExpression.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerLiteralExpressions.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerPatternShapes.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerPatternReachability.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerPropertyPatternBinding.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerRangeExpression.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerExpressionTail.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerThrowability.nl; src/NSharpLang.Compiler.Core/Semantics/ForeachPatternFacts.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerCompileTimeConstants.nl; their *.tests.nl

**Scope.** Expression, statement and pattern analysis move onto NamedTypeInfo and shapes. Constants come from catalog Constant rows.

**Acceptance.** O4 and O0 identical. Estates green: LoopSequence (99), IndexAccess (36), CompileTimeConstants (30), NullFlow (55).

### W5.10 — Analyzer: IDE consumers

- **Wave:** 5  **Size:** L
- **Depends on:** W4.4, W4.2
- **Owns:** src/NSharpLang.Compiler.CodeIntel/CodeIntelligenceDisplayText.nl; src/NSharpLang.Compiler.CodeIntel/CodeIntelligenceSignatureKernels.nl; src/NSharpLang.Compiler.CodeIntel/CodeIntelligenceNavigation.nl; src/NSharpLang.Compiler.CodeIntel/CodeIntelligenceQueryModels.nl; src/NSharpLang.Compiler.CodeIntel/CodeIntelligenceMemberDocs.nl; src/NSharpLang.Compiler.CodeIntel/CompletionReflectionFacts.nl; src/NSharpLang.Compiler.CodeIntel/CompletionEngineKernels.nl; src/NSharpLang.Compiler.CodeIntel/CodeIntelligenceTypeResolution.nl; src/NSharpLang.Compiler.CodeIntel/DocQuery.nl; src/NSharpLang.Compiler.CodeIntel/DocQueryReflectionFacts.nl; src/NSharpLang.Compiler.CodeIntel/DocQueryTypeIndex.nl; src/NSharpLang.Compiler.CodeIntel/DocQueryKernels.nl; src/NSharpLang.Compiler.CodeIntel/EditorInlayHintFacts.nl; src/NSharpLang.Compiler.CodeIntel/SignatureHelpOverloadFacts.nl; src/NSharpLang.Compiler.Driver/SignatureHelpEngine.nl; src/NSharpLang.LanguageServer/Services/TypeResolver.nl; src/NSharpLang.LanguageServer/Handlers/HoverHandler.nl; their *.tests.nl

**Scope.** Completion, hover, navigation, signature help, inlay hints and DocQuery read symbols and AttributeData. DocQuery stops enumerating AppDomain. The LanguageServer type resolver and hover handler read symbols.

**Acceptance.** CodeIntel (1,121) and Tooling (368) estates green. nlc query JSON identical. VS Code-enabled gate, plus integrator visual verification (owner-approved) of completion, hover, definition, references and diagnostics.

### W5.11 — Analyzer, Model and Driver residual

- **Wave:** 5  **Size:** M
- **Depends on:** W4.2
- **Owns:** files listed in systems-language-closeout/decodes/metadata-writer-residual-census.md (frozen by the integrator at the wave-4 tag); src/NSharpLang.Compiler.Core/Semantics/MethodImplAttributeFacts.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerProjectDiscovery.nl

**Scope.** Take exactly the files listed in the residual census the integrator froze at the wave-4 tag: production files with non-zero WriterBoundary counts that no other package owns. Known members include Core/Semantics/MethodImplAttributeFacts.nl, AnalyzerProjectDiscovery.nl, TypeAliasKeywordFacts, DeclarationLeafModels and CompilationReferenceResolverKernels.

**Acceptance.** O4 and O0 identical. Every census file is at its target counts.

### W5.12 — Delete PAB modifier route-arounds and flip their declines

- **Wave:** 5  **Size:** L
- **Depends on:** W4.1, W5.3
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarForeachLoopPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceSelfInstantiation.nl; the post-split Emit files holding the member-assignment decline, the BCL writable-property helpers and the ReadOnlySpan index read (per the W2.1 split map; no other wave-5 package owns them); src/NSharpLang.Compiler.Emit/ColumnarIlEmitter.nl (TryFindInitAutoPropertyBackingField and its two uses only; grant sequenced after W5.3 merges); src/NSharpLang.Compiler.MetadataWriter/Encoding/CustomModifierReferences.tests.nl; tests/native/modreq-member-references/**

**Scope.** After the W4.1 cutover, every MemberRef, MethodSpec and TypeSpec-parent reference is encoded from the catalog symbol (references) or the source symbol (definitions), with the full custom-modifier chain. Prove that with writer-level tests. Then delete the route-arounds the PAB limitation produced (line numbers at f6a6751bb, re-located through the W2.1 split map): (1) the emit.member-assignment.unreferenceable-setter decline and SetterSignatureSurvivesAMemberRef (ColumnarIlEmitter.nl:10303-10316, :13184-13199); (2) TryFindInitAutoPropertyBackingField and its uses (:1449-1469, :10360, :10607), so an init setter on a constructed source generic is called through its MemberRef; (3) ColumnarSourceSelfInstantiation.BindSetter's init special case (:55-73); (4) ColumnarForeachLoopPlanner.IsReferenceablePattern and HasRequiredModifiers (:363-383), so ref-readonly enumerator patterns such as ReadOnlySpan<T> are ordinary patterns; (5) ColumnarReadOnlySpanElementRead (:454-500) and its uses (:393, ColumnarIlEmitter.nl:14945), so index reads call ReadOnlySpan<T>.get_Item then ldobj. Kept as language rules: IsInitOnlySetter (:13171, :13203), because an init accessor is not an assignment target outside construction (W5.8 handles the analyzer twin). Add tests/native/modreq-member-references with declared decline-to-success rows: an init property of a project-reference library, assigned from a derived constructor (success) and outside construction (analyzer diagnostic, never NL103); an init setter on a constructed source generic, in an object initializer and in a generic method body; a ReadOnlySpan<T> indexer read and foreach; a ref-readonly-returning external member; an in-parameter virtual override. Byte changes form the declared O1 class modreq-route-around-flip.

**Acceptance.** Writer tests show MemberRef and MethodSpec signatures carrying the modifier chain in metadata order, for definitions and references. The ratchet route-around tokens (SurvivesAMemberRef, ReadOnlySpanElementRead, IsReferenceablePattern, HasRequiredModifiers, TryFindInitAutoPropertyBackingField) reach 0. Every modreq-member-references row runs and is clean under O2 (ILVerify, validator, loadcheck). O0 identical except the declared modreq-route-around-flip class, which has a perturbation control. Green: census-init-required, readonly-init, iterators, systems-vectorization-facts, systems-proof-corpus.

### W6.0 — Fan-out steward

- **Wave:** 6  **Size:** S
- **Depends on:** W5.4
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarTransitional*.nl; src/NSharpLang.Compiler.Model/CompilerWorkCounters.nl

**Scope.** Continuation of W5.4: own the transitional files, the bridge, and the shared counters and registries. Fix bridge gaps on request. Maintain the frozen census as packages finish.

**Acceptance.** Every bridge request is closed within the wave. O0 identical.

### W6.1 — P-Types: canonical types, typeof, registries

- **Wave:** 6  **Size:** L
- **Depends on:** W5.2, W3.4, W6.0
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarCanonicalTypeResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarTypeOfPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarSemanticTypeRegistry.nl; src/NSharpLang.Compiler.Plan/ColumnarTypeCanonicalizer.nl; src/NSharpLang.Compiler.Plan/ColumnarRuntimeTypeFacts.nl; src/NSharpLang.Compiler.Plan/ColumnarGenericTypeReceiverFacts.nl; src/NSharpLang.Compiler.Plan/ColumnarNumericFacts.nl; src/NSharpLang.Compiler.Plan/ColumnarVectorizationShapes.nl; src/NSharpLang.Compiler.Plan/ColumnarInheritanceDepthOrder.nl; their *.tests.nl

**Scope.** Canonical spellings, typeof, IsSupported* and the registries move to shapes. TrySelectRuntimeType and its 48 MakeGenericType lines move to the catalog. The exception index (static RuntimeExceptionsBySimpleName, ColumnarCanonicalTypeResolver.nl:18) becomes a per-compilation catalog closure.

**Acceptance.** O0 identical. Green: type-arity, generic-member-types, erased-enum-identity, census-generic-signatures, systems-vectorization-facts (92). Zero host-catalog and MetadataLoadContext references in owned files; ColumnarTypeOfPlanner alone has 32 today, including the Cecil typeofs at :653 and :1152. A daemon session running two compilations with changed references gives O0 identical to fresh processes.

### W6.2 — P-External: external binding, catalog-resolvable admission, test-framework references

- **Wave:** 6  **Size:** L
- **Depends on:** W5.2, W3.4, W6.0
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarBindingScopeFacts.nl; src/NSharpLang.Compiler.Plan/ColumnarExternalBindingPlans.nl; src/NSharpLang.Compiler.Plan/ColumnarCompilerReferenceResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarExternalFreeFunctions.nl; src/NSharpLang.Compiler.Plan/ColumnarExternalBaseConstructors.nl; src/NSharpLang.Compiler.Plan/ColumnarInheritedExternalBase.nl; src/NSharpLang.Compiler.Plan/ColumnarInheritedOwner.nl; src/NSharpLang.Compiler.Plan/ColumnarExternalMethodSignatureRelation.nl; src/NSharpLang.Compiler.Plan/ColumnarSplitTypeIdentityFacts.nl (deleted); their *.tests.nl

**Scope.** Catalog-returning ColumnarExternalTypeCatalog. The closed allow-lists (ColumnarExternalBindingPlans :61-203) are replaced by 'catalog-resolvable is supported'. Test-framework and AspNet types resolve only from the project's reference paths. ColumnarCompilerReferenceResolver stops calling the host scopes (:31, :68, :173). ColumnarSplitTypeIdentityFacts is deleted.

**Acceptance.** O0 identical. Green: census-external-* projects, reflection-emit-bootstrap (47), census-testrefs, census-nunit-test-blocks. Zero host-catalog and MetadataLoadContext references in owned files; ColumnarCompilerReferenceResolver and ColumnarBindingScopeFacts have 12 each today.

### W6.3 — P-DirectCalls

- **Wave:** 6  **Size:** L
- **Depends on:** W5.2, W3.4, W6.0
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarDirectCallPlanner.nl; its *.tests.nl

**Scope.** Direct-call planning moves onto model members. The interface-receiver castclass (:3566-3596) is kept byte for byte.

**Acceptance.** O0 identical. Green: census-generic-callee-receiver, user-generic-methods, census-params-expansion.

### W6.4 — P-Resolvers: overloads and inference over references

- **Wave:** 6  **Size:** L
- **Depends on:** W5.2, W3.4, W6.0
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarOrdinaryRuntimeDirectCallResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarRuntimeDirectCallResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarRuntimeGenericMethodResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarDirectCallConstructedConversions.nl; src/NSharpLang.Compiler.Plan/ColumnarGenericCallBindingPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarNamedArgumentBinder.nl; src/NSharpLang.Compiler.Plan/ColumnarParamsExpansion.nl; src/NSharpLang.Compiler.Plan/ColumnarByRefCallArgumentFacts.nl; src/NSharpLang.Compiler.Plan/ColumnarProvisionalMemberBinding.nl; src/NSharpLang.Compiler.Plan/ColumnarRuntimeOperatorResolver.nl; their *.tests.nl

**Scope.** Move CandidateMethods, ResolveFromCandidatesCore, Unify/FindMatchingInstantiation/CloseOrNull, named arguments, params, by-ref arguments and operators onto the catalog.

**Acceptance.** O0 identical; O4 decline traces identical. Green: external-generic-methods, census-external-operands. Zero host-catalog references in owned files (ColumnarRuntimeDirectCallResolver has 5 today).

### W6.5 — P-Source: source members and self-instantiation

- **Wave:** 6  **Size:** L
- **Depends on:** W5.2, W3.4, W6.0, W5.12
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarSourceDirectCallResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceSelfInstantiation.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceStaticMemberPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceGenericStaticMemberFacts.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceInterfaceMethodResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceMemberChainResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceDefinitionResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceOperatorResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceImplicitConversionResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarClosedGenericMemberResolver.nl; their *.tests.nl

**Scope.** Closed source members are obtained via owner.GetMethod on constructed shapes. Self-instantiation becomes an explicit rule; W5.12 has already removed the init special case. The ColumnarSourceImplicitConversionResolver ConditionalWeakTable cache becomes per compilation.

**Acceptance.** O0 identical. Green: generic-static-members, complete-source-generic-args, census-closed-generic-source-base.

### W6.6 — P-MembersA: runtime instance and static members

- **Wave:** 6  **Size:** L
- **Depends on:** W5.2, W3.4, W6.0
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarRuntimeInstanceMemberResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarInstanceMemberPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarExternalStaticMemberPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarIteratorMemberResolver.nl; their *.tests.nl

**Scope.** RuntimeInstanceMemberResolver (198 typeof sites) uses catalog members instead of host Json, Yaml, MSBuild and Cecil types; the host typeofs at :1224 and :1248 go. Task.Run and EqualityComparer<T>.Default come from WellKnownMember.

**Acceptance.** O0 identical. Green: runtime-acceptance (98), census-external-nullable-members. LockStatement and WeatherDemo run. Zero host-catalog and MetadataLoadContext references in owned files.

### W6.7 — P-MembersB: extensions, conversions, interfaces, overrides

- **Wave:** 6  **Size:** L
- **Depends on:** W5.2, W3.4, W6.0
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarExtensionMethodResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarContextualExtensionInference.nl; src/NSharpLang.Compiler.Plan/ColumnarReferenceConversionFacts.nl; src/NSharpLang.Compiler.Plan/ColumnarExternalInterfaceMethodResolver.nl; src/NSharpLang.Compiler.Plan/ColumnarOverrideTargetResolver.nl; their *.tests.nl

**Scope.** Extension discovery over the catalog. Reference conversions use TypeAlgebra. External method descriptors anchor on catalog handles. Override targets move to symbols. Override signatures keep copying the overridden member's modifier chain.

**Acceptance.** O0 identical. Green: external-abstract-override, external-base-interface, census-generic-interface-method. ExplicitInterfaceImplementation runs. Zero host-catalog and MetadataLoadContext references in owned files.

### W6.8 — P-Iterators: lowering facts, machines, closures

- **Wave:** 6  **Size:** XL
- **Depends on:** W5.2, W5.3, W3.4, W6.0
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarIteratorPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarIteratorBodyScope.nl; src/NSharpLang.Compiler.Plan/ColumnarIteratorCancellationFacts.nl; src/NSharpLang.Compiler.Plan/ColumnarClosureBindingPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarLocalFunctionClosurePlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarLambdaPlacementPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarAsyncEntryPointPlanner.nl; src/NSharpLang.Compiler.Emit/ColumnarIteratorRealization.nl; their *.tests.nl

**Scope.** The surviving iterator lowering and realization surface moves onto the model. Machine types come through DefineSyntheticType. The dual display handles collapse. Sequence members and Monitor become WellKnownMember. Cancellation facts move to Wk. Coordinate with the unification stream (see coordination).

**Acceptance.** O0 identical. Green: iterators, async-generic-iterators, async-member-iterators, generic-instance-iterators, async-iterator-cancellation, census-iterators, census-closures. Zero host-catalog references in owned files (ColumnarIteratorPlanner has 5 today, ColumnarAsyncEntryPointPlanner 1).

### W6.9 — P-Declarations: declaration planning on symbols; attribute blob owner

- **Wave:** 6  **Size:** XL
- **Depends on:** W5.2, W5.5, W3.4, W6.0
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarDeclarationPlan.nl; src/NSharpLang.Compiler.Plan/ColumnarBaseTypePlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarGenericConstraintPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarInterfaceRealization.nl; src/NSharpLang.Compiler.Plan/ColumnarExplicitInterfaceImplementation.nl; src/NSharpLang.Compiler.Plan/ColumnarMethodImplAttributes.nl; src/NSharpLang.Compiler.Plan/ColumnarFreeFunctionScope.nl; src/NSharpLang.Compiler.Plan/ColumnarAttributeBlobWriter.nl (moved); src/NSharpLang.Compiler.Plan/ColumnarAttributeBlobs.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceAttributeBinder.nl; src/NSharpLang.Compiler.Plan/ColumnarSourceAttributes.nl; src/NSharpLang.Compiler.Plan/ColumnarSignatureMetadataEmitter.nl; src/NSharpLang.Compiler.Plan/ColumnarParameterDefaultEmitter.nl; src/NSharpLang.Compiler.Plan/ColumnarInitRequiredMemberEmitter.nl; src/NSharpLang.Compiler.Plan/ColumnarTupleElementNameEmitter.nl; src/NSharpLang.Compiler.Plan/ColumnarTupleElementNames.nl; src/NSharpLang.Compiler.Plan/ColumnarFieldMetadataEmitter.nl; src/NSharpLang.Compiler.Plan/ColumnarNullableMetadata.nl; src/NSharpLang.Compiler.Plan/ColumnarAttributeUsageTargets.nl; src/NSharpLang.Compiler.Plan/ColumnarReachabilityAttributeFacts.nl; src/NSharpLang.Compiler.MetadataWriter/Encoding/AttributeBlobEncoder.nl; src/NSharpLang.Compiler.Model/DiagnosticCatalog.nl (absent-attribute lines); website/docs/errors/ (absent-attribute page); their *.tests.nl

**Scope.** Declaration rows, base types, constraints, interface realization, MethodImpl and the holder scope consume producer symbols (W5.5). ColumnarAttributeBlobWriter moves to MetadataWriter/Encoding/AttributeBlobEncoder: source types are written as FullName, references as the referenced-assembly AQN. Parameter and field constants follow the W2.3 constant rule. Override modifier copying, with a native test. An absent compiler-feature attribute is a located refusal, with a DiagnosticCatalog entry and a website/docs/errors page.

**Acceptance.** O0 identical except the declared modifier-copy and constant-encoding classes. Green: census-source-attributes (61), census-nullable-metadata, census-init-required (35), methodimpl-attributes, census-explicit-interface-implementation (14), census-in-parameters, pseudo-attributes.

### W6.10 — P-Construction

- **Wave:** 6  **Size:** L
- **Depends on:** W5.2, W5.5, W3.4, W6.0
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarConstructionPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarConstructorDeclarationPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarRecordValueMemberPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarRecordWithPlanner.nl; their *.tests.nl

**Scope.** Construction, constructor declarations, record value members and with move onto symbols and shapes.

**Acceptance.** O0 identical. Green: record-with, readonly-init, construction-arrays, constructed-generic-interop, modreq-member-references. Zero host-catalog references in owned files.

### W6.11 — P-Body: general method-body planners

- **Wave:** 6  **Size:** L
- **Depends on:** W5.2, W3.4, W6.0, W5.12
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarMethodBodyPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarConditionalPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarForeachLoopPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarUsingResourcePlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarStoreTargetPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarBoundIdentifierPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarPrimitiveBinaryPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarScalarLiteralPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarUnaryLiteralPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarBooleanLiteralPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarCastConversionPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarRangeIndexPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarRangeIndexHandles.nl; src/NSharpLang.Compiler.Plan/ColumnarNullableArgumentLowering.nl; src/NSharpLang.Compiler.Plan/ColumnarThisExpressionPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarThrowExpressionPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarNameOfPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarReferenceCoercionPlanner.nl; src/NSharpLang.Compiler.Plan/ColumnarInterpolationPlans.nl; src/NSharpLang.Compiler.Plan/ColumnarMemberWriteChain.nl; src/NSharpLang.Compiler.Plan/ColumnarPatternFacts.nl; their *.tests.nl

**Scope.** Body planners move onto shapes and Wk. This includes ColumnarMethodBodyPlanner, now 2,379 lines, which carries the unification stream's shared iterator statement paths. ColumnarForeachLoopPlanner was already flipped by W5.12.

**Acceptance.** O0 identical. Green: scalar-code-plan, boolean-code-plan, census-catch-types, runtime-acceptance (98), systems-proof-corpus (44), census-iterators. The ExceptionFilters planner refusal is re-measured.

### W6.12 — E-Walk: writer definitions from complete source symbols

- **Wave:** 6  **Size:** L
- **Depends on:** W5.3, W5.5, W6.0
- **Owns:** src/NSharpLang.Compiler.Emit/ColumnarAssemblyEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarEventMemberEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarEntryPointRealization.nl; src/NSharpLang.Compiler.Emit/ColumnarInternalsVisibleToEmitter.nl; their *.tests.nl

**Scope.** The walk defines writer types from producer and erasure symbols, with no erasure logic left in Emit. Events, IVT and the entry point go through definitions.

**Acceptance.** O0 identical. Green: census-source-events (32), census-events (25), census-internals-visible-to (28), test-assembly-load-contexts, pseudo-attributes. All 21 roots build and run.

### W6.13 — E-Statements

- **Wave:** 6  **Size:** L
- **Depends on:** W5.3, W6.0, W5.12
- **Owns:** src/NSharpLang.Compiler.Emit/ColumnarIlEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarStatementEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarEmitFlowFacts.nl; src/NSharpLang.Compiler.Emit/ColumnarForeachEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarVectorizationEmitter.nl

**Scope.** Statement, foreach and vectorization emission, plus the body driver, move to shapes. SIMD helpers come from the project's NSharpLang.Runtime reference via WellKnownMember.

**Acceptance.** O0 identical. Green: census-exception-filters (19, FilterIlShape), systems-vectorization-facts (92). Zero host-catalog references in owned files (ColumnarIlEmitter.nl has 5 today).

### W6.14 — E-Expressions

- **Wave:** 6  **Size:** L
- **Depends on:** W5.3, W6.0, W5.12
- **Owns:** src/NSharpLang.Compiler.Emit/ColumnarExpressionEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarPatternEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarTupleLabelFacts.nl

**Scope.** Expressions, patterns, unions and anonymous types (via DefineSyntheticType) move to shapes. The YamlDotNet host typeofs (:14716-14717, :26310-26319 at f6a6751bb) become catalog members in whichever split file holds them.

**Acceptance.** O0 identical. census-emit-shapes (116) green.

### W6.15 — E-StaticSourceCalls

- **Wave:** 6  **Size:** L
- **Depends on:** W5.3, W6.0
- **Owns:** src/NSharpLang.Compiler.Emit/ColumnarStaticCallEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarSourceCallEmitter.nl

**Scope.** TryEmitStaticCall, BCL and JSON calls, and generic source and sibling calls move to shapes.

**Acceptance.** O0 identical. Green: user-generic-methods, runtime-acceptance.

### W6.16 — E-InstanceCalls

- **Wave:** 6  **Size:** L
- **Depends on:** W5.3, W6.0, W5.12
- **Owns:** src/NSharpLang.Compiler.Emit/ColumnarInstanceCallEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarMethodGroupEmitter.nl

**Scope.** Instance calls, constrained calls on generic parameters, method groups, and span and cast conversions move to shapes.

**Acceptance.** O0 identical. Green: generic-type-receivers, constructed-generic-interop.

### W6.17 — E-ContextualLambdas

- **Wave:** 6  **Size:** L
- **Depends on:** W5.3, W6.0
- **Owns:** src/NSharpLang.Compiler.Emit/ColumnarContextualCallEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarLambdaEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarLocalFunctionEmitter.nl

**Scope.** Contextual inference, AspNet handlers, and lambda and local-function displays (constraint copy by model substitution) move to shapes.

**Acceptance.** O0 identical. Green: census-lambda-inference, census-async-lambdas, census-local-functions. MinimalApi runs.

### W6.18 — E-OperatorsPreflight

- **Wave:** 6  **Size:** L
- **Depends on:** W5.3, W6.0, W5.12
- **Owns:** src/NSharpLang.Compiler.Emit/ColumnarOperatorEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarPreflightTyping.nl; src/NSharpLang.Compiler.Emit/ColumnarInterpolationEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarEventAndConstructorEmitter.nl

**Scope.** Operators and lifted nullables, preflight typing as model queries, interpolation, events and constructor chaining move to shapes.

**Acceptance.** O0 identical. Green: analyzer-event-subscription, census-events, runtime-acceptance.

### W6.19 — Playground reference images

- **Wave:** 6  **Size:** L
- **Depends on:** W2.6, W3.5, W4.4, W6.0
- **Owns:** src/NSharpLang.Playground/**; src/NSharpLang.Compiler.Model/ProjectFileParser.nl (resources key); src/NSharpLang.Compiler.Model/ProjectConfigModels.nl (resources field); src/NSharpLang.Compiler.MetadataWriter/Serialization/ManifestResources.nl; src/NSharpLang.Sdk/Sdk/Sdk.targets (resource items, if the SDK route needs them); tests/native/embedded-resources/**; tests/native/playground-tooling-surfaces/**; tests/native/playground-diagnostic-spans/**; website/docs/language-tour.md (resources section); scripts/build-playground-wasm.sh (smoke hook only)

**Scope.** Before W7.2 deletes the AppDomain inventory, runtime pairing and host loads, give the Playground the owner-chosen byte[] image source for the catalog's IReferenceImageProvider. Bounded host-type resolution cannot survive W7.2: in browser-wasm Assembly.Location is empty, and nothing else yields image bytes. Recommended: a general N# embedded-resource feature. A project.yml resources: key, added to the known-property list at ProjectFileParser.nl:187, is emitted as ManifestResource rows by the writer. src/NSharpLang.Playground uses it to embed the bounded reference set from the targeting pack. This is N#-only and grows no permanent C# boundary. The alternative, which needs an explicit owner exception, is static assets fetched through main.js and PlaygroundExports.cs, which are permanent-boundary files that may not grow. Includes language docs for resources:, and a declared O4 class for Playground diagnostics if binding moves from host types to pack images.

**Acceptance.** Playground estates are green with the catalog reading embedded (or shipped) images and no host-type path. The embedded-resources native project round-trips resources through Assembly.GetManifestResourceStream in the runner. An in-browser check smoke of the published Playground.Wasm bundle passes. No in-browser harness exists today, so choosing one is the package's first deliverable: a Node-hosted dotnet.js run of the exports, or the integrator's browser tool with owner approval (UNVERIFIED which works). Under the recommended option, the Playground.Wasm C# files and main.js do not grow. The download-size delta is recorded.

### W7.1 — Delete transitional layer, PAB and builder plumbing (Plan, Emit, writer)

- **Wave:** 7  **Size:** L
- **Depends on:** W6.0, W6.1, W6.2, W6.3, W6.4, W6.5, W6.6, W6.7, W6.8, W6.9, W6.10, W6.11, W6.12, W6.13, W6.14, W6.15, W6.16, W6.17, W6.18, W5.12
- **Owns:** src/NSharpLang.Compiler.Plan/** (sweep, including project.yml); src/NSharpLang.Compiler.Emit/** (sweep, including project.yml); src/NSharpLang.Compiler.MetadataWriter/IL/IlBodyBuilderVsIlGenerator.tests.nl; tests/native/ownership-audit/WriterBoundaryRatchet.tests.nl (Plan/Emit audit rows)

**Scope.** Delete ColumnarTransitional* and the bridge, the PAB shells, the TRANSITIONAL overloads, builder fields, and import System.Reflection.Emit. Rename facade call sites to IlBodyBuilder via codemod. Delete the remaining guards, catches and IsSafeSzArrayType. Convert the PAB IL differential to golden vectors. Remove the MetadataLoadContext and Mono.Cecil package references from Plan/project.yml and Emit/project.yml. Add audit rows to tests/native/ownership-audit/WriterBoundaryRatchet.tests.nl, the single audit owner.

**Acceptance.** O0 identical. Full estate and corpus green. Audit rows show zero of each of these in Plan and Emit: Reflection.Emit, PAB, TypeBuilder, ILGenerator, MetadataLoadContext, Mono.Cecil, the host-catalog tokens (RequiredRuntimeTypes, WellKnownTypeCatalog, RuntimeContext, and ExternalAssemblyScan's RuntimeAssembliesInScope, LoadedAcrossContexts and TryLoadHostAssemblyByName), the route-around tokens, ColumnarTransitional, and TRANSITIONAL(. The Plan and Emit project.yml files reference neither MLC nor Cecil. Fresh gate plus rehearsal.

### W7.2 — Delete MLC, executable loads, host catalogs, runtime pairing

- **Wave:** 7  **Size:** L
- **Depends on:** W7.1, W5.6, W5.7, W5.8, W5.9, W5.10, W5.11, W6.1, W6.2, W6.3, W6.4, W6.6, W6.7, W6.8, W6.19, W4.3, W4.4
- **Owns:** src/NSharpLang.Compiler.Model/** (sweep); src/NSharpLang.Compiler.Core/** (sweep); src/NSharpLang.Compiler.CodeIntel/** (sweep); src/NSharpLang.Compiler.Driver/** (sweep); src/NSharpLang.Compiler.Syntax/project.yml; src/NSharpLang.Compiler.Tooling/project.yml; src/NSharpLang.Compiler/project.yml; src/NSharpLang.Cli/Cli.csproj (shrink only); src/NSharpLang.Sdk/NSharpLang.Sdk.csproj; scripts/verify-bootstrap.py; scripts/verify-release.py; tests/native/catalog-parity/** (deleted); tests/native/*/project.yml (MLC and Cecil rows; 8 files); test .nl inspectors using MLC or Cecil (14 files); tests/native/ownership-audit/WriterBoundaryRatchet.tests.nl (final audit row; after W7.1)

**Scope.** Runs after W7.1 merges. Delete: the ExternalAssemblyScan loads (:401/448/466/471/1530/1567/1647), the ALC cache, the AppDomain inventory (:485-487), RuntimeAssembliesInScope (:506-530) and TryLoadHostAssemblyByName (:469); ColumnarTransitionalHostScopeImages; RuntimeContext* and ReferenceImageMetadataContext; AnalyzerTransitionalMetadataBridge and the .Type accessors; WellKnownTypeCatalog and RequiredRuntimeTypes (whose static cache is at :27); the DaemonLoadedReferenceGuard AppDomain scan, which becomes a file-version check; the pairing tests and catalog-parity. Move CompilerWorkCounters reference-load counting from the MLC sites to the catalog with identical semantics. Package references: remove MLC and Cecil from every src project.yml except Plan and Emit (W7.1 owns those), from src/NSharpLang.Compiler/project.yml (:9-10), from Cli.csproj (:47-48, shrink only), and from the SDK payload rows. YamlDotNet stays. Verifiers: verify-release.py requires the Compiler.Metadata and Compiler.MetadataWriter payload and refuses MLC and Cecil. verify-bootstrap.py stops requiring MLC (:25) and requires the new payload; it refuses MLC only at W9.1, so CI keeps passing on the W5.1 seed. Test inspection: re-plumb the 8 tests/native/*/project.yml files that pin MLC or Cecil DLLs from Cli/bin, and the 14 test .nl inspectors (10 MLC, 4 Cecil), to test-scope package references or to emit-parity dump. Final audit row in tests/native/ownership-audit: zero Reflection.Emit, TypeBuilder, EnumBuilder, ILGenerator, MetadataLoadContext and Mono.Cecil tokens in every N# production project (the compiler slices, Compiler, TestHost, LanguageServer, Playground, Metadata, MetadataWriter), with user-program reflection-emit tests excluded by path. The integrator then switches the WriterBoundarySnapshot targets to 0.

**Acceptance.** The audit rows pass: zero MetadataLoadContext, Mono.Cecil, Assembly.Load*/LoadFrom, ALC.Load* and AppDomain.GetAssemblies in the compiler, CLI and TestHost (TestRunner excepted for loads), and zero Reflection.Emit/TypeBuilder/EnumBuilder/ILGenerator/MLC/Cecil tokens in every N# production project. O0 and O4 identical. agent-loop and bootstrap-build goldens unchanged. Playground estates and the in-browser smoke are green. CI verify-bootstrap passes on the W5.1 seed, and verify-release passes on head packs. Every native project builds. Non-VS and VS Code gates, plus rehearsal.

### W8.1 — Reference-set switch to targeting packs

- **Wave:** 8  **Size:** L
- **Depends on:** W7.1, W7.2
- **Owns:** src/NSharpLang.Compiler.Model/AnalyzerMetadataLoadPolicy.nl; src/NSharpLang.Compiler.Model/DotnetInstallationLocator.nl; src/NSharpLang.Compiler.Model/ExternalAssemblyScan.nl; src/NSharpLang.Compiler.Core/Semantics/AnalyzerMetadataLoadSurface.nl; src/NSharpLang.Compiler.Driver/CompilationReferenceResolver.nl; src/NSharpLang.Compiler.Driver/SdkEmitTaskKernels.nl; src/NSharpLang.Compiler.Driver/IncrementalBuildInputs.nl; src/NSharpLang.Compiler.MetadataWriter/ReferenceAssembly/**; src/NSharpLang.Compiler.MetadataWriter/Encoding/AttributeBlobEncoder.nl; src/NSharpLang.Compiler.Model/DiagnosticCatalog.nl (missing-pack lines); website/docs/errors/ (missing-pack page); website/docs/cli-reference.md (build references section); tests/native/compilation-backend/CompilationBackend.tests.nl; other tests pinning System.Private.CoreLib scope

**Scope.** Binding and emission use the TFM pack, the ASP.NET pack, NuGet compile assets, project-reference assemblies and the test-framework compile set. A missing pack is restored from NuGet or reported as an actionable NL diagnostic, which gets a DiagnosticCatalog entry, a website/docs/errors page and a cli-reference build section. Implementation assemblies become contract-scoped; the projector rescope becomes identity; attribute AQNs use reference identities. Pack fingerprints enter incremental stamps. Declare the counter deltas: pack images outside the installed runtime path now count as reference loads. Re-baseline the CoreLib-pinned tests one by one.

**Acceptance.** O1 ⊆ declared classes (scopes, AQN strings). The O4 diff is reviewed line by line. O3 identical. ILVerify empty. Green: sdk-project-reference-boundary, reference-assembly-surface, census-external-*. Declared counter deltas match the integrator's re-baseline. Bench within the gate. Rehearsal at the wave tag.

### W8.2 — Portable PDB and determinism extension

- **Wave:** 8  **Size:** L
- **Depends on:** W7.1, W1.4
- **Owns:** src/NSharpLang.Compiler.MetadataWriter/Pdb/**; src/NSharpLang.Compiler.MetadataWriter/Identity/**; src/NSharpLang.Compiler.MetadataWriter/IL/IlBodyBuilder.nl (sequence points); src/NSharpLang.Compiler.Emit/ColumnarStatementEmitter.nl; src/NSharpLang.Compiler.Emit/ColumnarIlEmitter.nl (body driver); src/NSharpLang.Compiler.Driver/MultiFileCompiler.nl (PDB path); src/NSharpLang.Compiler.Driver/EmitIlAssembly.nl; src/NSharpLang.Sdk/Sdk/Sdk.props; src/NSharpLang.Sdk/Sdk/Sdk.targets (EmitNSharpIlAssembly Outputs); scripts/lib/packages.sh (symbol packing); tests/native/portable-pdb/**; tests/native/incremental-build/** (PDB rows); tests/native/sdk-reference-incrementality/** (PDB rows); tests/native/sdk-pack-symbol-contract/**; src/NSharpLang.Compiler.Model/DiagnosticCatalog.nl (PDB lines); website/docs/debugging.md; website/docs/cli-reference.md (debugType)

**Scope.** PdbWriter writes Document rows, MethodDebugInformation for every MethodDef, sequence points from statements (hidden where needed), LocalScope and LocalVariable. DeterministicImageIdentity orders the PDB id, then the debug directory, then the PE id. debugType none/portable/embedded becomes truthful. The SDK route outputs the PDB: EmitNSharpIlAssembly Outputs (Sdk.targets:202) gain it. PDB-only changes get rows in incremental-build and sdk-reference-incrementality. Packing stops forcing DebugType=None for N# projects (scripts/lib/packages.sh:26-30, :134-136), and sdk-pack-symbol-contract is updated. Docs: website/docs/debugging.md and cli-reference.md, plus DiagnosticCatalog entries for any new PDB diagnostics.

**Acceptance.** MethodDebugInformation count equals MethodDef count. Stack traces show the .nl file and line. PE and PDB are byte-identical across rebuilds and hosts, embedded PDBs included. A PDB-only change re-runs the emit and leaves the reference assembly unchanged (rows). Packages carry symbols per the contract. VS Code gate, plus integrator visual verification (owner-approved) of a breakpoint and a step.

### W9.1 — Final reseed and bootstrap cleanup

- **Wave:** 9  **Size:** M
- **Depends on:** W8.1, W8.2, W7.2
- **Owns:** bootstrap/NSharpLang.Sdk.*.nupkg; bootstrap/NSharpLang.Runtime.*.nupkg; bootstrap/SHA256SUMS; bootstrap/README.md; scripts/verify-bootstrap.py; src/*/global.json (seed pins); src/NSharpLang.Compiler.Plan/project.yml (Runtime pin line)

**Scope.** A two-stage reseed with the stage-3 fixed point, under the distinct-version scheme, so the seed is free of Reflection.Emit, MLC and Cecil. In the same commit, verify-bootstrap.py starts refusing MLC and Cecil in the seed SDK. Drop the MLC delivery-repair note from bootstrap/README.md.

**Acceptance.** stage2==stage3 over the extracted DLLs and payload SHA256SUMS. Stage-2 estate green. verify-bootstrap.py passes locally and in every CI workflow that runs it (build.yml four times, publish.yml, deploy-website.yml), and refuses a seed containing MLC (row). Fresh gate.

### W9.2 — NativeAOT 21/21 acceptance

- **Wave:** 9  **Size:** M
- **Depends on:** W8.1, W8.2, W1.9, W2.8
- **Owns:** scripts/nativeaot-check-projects.txt; scripts/test-nativeaot-compiler.sh; scripts/lib/nativeaot-warnings.sh; src/NSharpLang.Cli/NativeAot.Roots.xml; docs/design/full-compiler-nativeaot.md

**Scope.** Grow the manifest to 21 roots for check, build (byte-identical across JIT, R2R and AOT), run, and test through the TestRunner. Add warning-free scopes for Metadata, MetadataWriter, Plan, Emit and Driver emission. Shrink NativeAot.Roots.xml. Record cold AOT medians. Name slice 4 as the only remaining external owner.

**Acceptance.** All 21 roots pass on three hosts, with identical JSON, images, outputs and test results. Zero warnings in the finished scopes. Medians recorded against managed baselines.

### W9.3 — Optional deliberate byte-changing improvements

- **Wave:** 9  **Size:** M
- **Depends on:** W8.2
- **Owns:** src/NSharpLang.Compiler.Plan/ColumnarDirectCallPlanner.nl; src/NSharpLang.Compiler.MetadataWriter/IL/MaxStack.nl; src/NSharpLang.Compiler.MetadataWriter/IL/IlBodyEncoding.nl

**Scope.** Only items the owner approves, each as its own commit with a scope-map class: remove the interface-receiver castclass; exact-dataflow maxstack; branch shortening; name every parameter.

**Acceptance.** Each change has its own O1 class and control. ILVerify empty. O3 identical. Rehearsal green.

### W9.4 — Final integration and documentation

- **Wave:** 9  **Size:** S
- **Depends on:** W9.1, W9.2
- **Owns:** docs/design/metadata-native-writer.md; memory/architecture.md; memory/components/cli-toolchain.md; memory/testing.md; systems-language-closeout/STATUS.md; website/docs/** (final sweep)

**Scope.** Close the deletion ledger and the critic-gap ledger with commit evidence. Update docs, memory (architecture, cli-toolchain, testing), STATUS, and the user-facing website/docs pages touched by the program (errors, cli-reference, debugging, language-tour resources).

**Acceptance.** Fresh non-VS and VS Code-enabled gates green. Ownership audit green, with WriterBoundary targets at 0. Every ledger row closed. Every new NL code has its DiagnosticCatalog entry and errors page.
