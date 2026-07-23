# Systems-language closeout cursor

Last updated: 2026-07-22

## Cursor

- Current task: `tasks/016-parser-and-syntax-diagnostics.md`
- Current iteration: one terminal slice
- Task 015 status: UNCHECKED, iteration PAUSED at `e0f987bba` — the movable decision surface is
  EXHAUSTED per the 015 completion roadmap (recorded below): every remaining emitter policy is
  BLOCKED-WITH-RECORD on four named future owners (plan-row lambda-body emitter, N# preflight/
  typing-owner port, async-func lowering, planner operand unlocks) or MECHANICAL. Resume 015 only
  when one of those owners lands. Emitter at 21,433/20,375 vs epoch 21,723/20,646 (−290 lines this
  task across 8 landed slices + 2 proven refutations + 1 restored regression).
- 016 note: Parser.cs is the LSP-fallback parser — the eventual PRODUCTION-WIRING/cutover slices are
  IDE-AFFECTING (VS Code-enabled gate + extension reinstall). The kernel-capability arc stages (Stage 1
  landed this turn) are NOT IDE-affecting: they add self-contained N# owner files + native contracts with
  NO production/LSP wiring, so the non-VS-Code path suffices until cutover.
- Task 016 status: UNCHECKED, ARC IN PROGRESS (STAGE 2 landed) — the prior PROVEN-BLOCKED-WITH-RECORD finding
  (below) is the STAGE-0 prerequisite record for a staged parser-front-end arc (arc plan recorded in the "016
  parser/diagnostic ownership finding" section). STAGE 1 (shared-panic RECOVERY MODEL + import/namespace/package
  family, 11 contracts) and STAGE 2 (the DECLARATION-NAME family — "Expected <kind> name" for func/class/struct/
  record/soa/interface/union/enum/type-alias, with `DiagnosticSpanFromToken` keyword-anchoring + the
  reserved-keyword-as-name variant, +24 contracts) have LANDED (no production edit to any consumer, no commit —
  mandate; working tree carries the two N# files + the STAGE-1 ColumnarSyntaxDiagnostics scaffolding deletion +
  this STATUS update). `ColumnarParserRecovery.nl` reproduces Parser.cs's recovery discipline faithfully and
  is proven byte-exact against the production Parser.cs path on a golden parity corpus (35 native contracts
  total, including the cascading-suppression, does-not-swallow-following, keyword-anchored absent/reserved
  name, and cross-boundary panic-reset shapes). Parser.cs REMAINS the sole production syntax authority; cutover
  is the arc's LAST stage. No wall tripped (self-contained shape, packaged SDK emits it — no repin).
- Active sub-slice (016 arc, THIS TURN, LANDED — no commit): STAGE 2 of the parser-front-end arc — the
  DECLARATION-NAME diagnostic family. Extended `ColumnarParserRecovery.nl` to carry the "Expected <kind>
  name" diagnostics for func / class / struct / record / soa record / interface / union / enum / type-alias
  declarations through the SAME shared-panic model, with the `DiagnosticSpanFromToken` KEYWORD-ANCHORING
  discipline (a missing/invalid name underlines the DECLARATION KEYWORD, not the offending token, in all
  three ConsumeIdentifier variants) and the reserved-keyword-as-name variant. Added `ConsumeDeclarationName`
  (Parser.cs ConsumeIdentifier with a non-null diagnosticSpan), the `ParseTopLevelDeclaration` dispatch
  (ParseModifiers + the exact Parser.cs keyword order incl. `ref struct` / `soa record` / `duck interface`
  / `record struct` variants + LookAhead), the per-kind name parsers, and the boundary/force-advance loop
  (Parser.cs ParseCompilationUnit :83/:99-108). Bodies are NOT parsed (a later arc stage); the loop makes
  progress by consuming the keyword (and, for reserved-keyword recovery, the offender) or the stray token.
  +24 native parity contracts in `ColumnarParserRecovery.tests.nl` (per-kind absent-name / reserved-keyword,
  plus func/enum/type found-other + two panic-model interaction fixtures), proven byte-exact against golden
  live-CLI Parser.cs output (`nlc check --json`, NL101-NL109). NO production wiring; NO wall tripped
  (self-contained edit to one owner + its tests, packaged SDK emits it — no repin). Evidence: BootstrapServices
  contracts 797/797 (773 baseline + 24); ownership audit 18/18; git status shows only the two `.nl` files
  changed (no non-N# file moved). Next: STAGE 3 = the next-smallest family per the arc plan (malformed-literal:
  unterminated string/char/triple/interpolated, empty char).
- Prior sub-slice (016 arc, STAGE 1, LANDED — no commit): the shared-panic RECOVERY MODEL + import/namespace/
  package family. Added `ColumnarParserRecovery.nl` (Parser.cs `_panicMode` lifecycle: one shared flag,
  suppress-while-set, set-on-report, reset only at the declaration-boundary sync point; ordered reporting;
  the ConsumeIdentifier reserved-keyword/EOF/found variants + LastVisibleTokenSpan anchoring) + 11 golden
  parity contracts. Deleted the inert divergent `ColumnarSyntaxDiagnostics` scaffolding closure (see the arc
  plan's scaffolding-fate decision).
- CORRECTION (post-Stage-2): sub-slice 5's Min/Max deletion (`86f4c251b`) was PARTIALLY WRONG — its
  "provably dead" claim held only for plannable receivers. `Select(v => ...).Min()/.Max()` chains
  whole-subtree-exit to the legacy residual (contextual-lambda decline), where the deleted emit +
  preflight arms were load-bearing: tests/native/lambda-placement failed to emit at the checkpoint
  gate. The arms are RESTORED as fenced load-bearing residuals (retire with arc stages 3-4); the
  resolver-side ownership of plannable Min/Max receivers stands. LESSON (bar raised): every
  byte-exact corpus sweep MUST include the tests/native/* projects — the 59-assembly example/fixture
  sweep alone missed this; sub-slice 6's refutation of the identical premise for ToArray/ToList/
  Contains applied retroactively to 5 and nobody re-checked.
- Active sub-slice (THIS TURN, LANDED a net-negative deletion): the interpolation BASE-CALL
  CLASSIFICATION decision. CHOICE recorded pre-edit: move the string-classification half of
  `TryResolveInterpolationBaseCallPlan` (the `base.` prefix + `()` suffix parse and the method-name
  extraction/validation, deciding THAT an interpolated hole is a well-formed `base.<name>()` call and
  extracting the name) into the N# splitter owner `ColumnarInterpolationSplitter.TrySplitBaseCall(text,
  out methodName)` — an exact mirror of the accepted `TrySplitCast`/`TrySplitEquality`/`TrySplitCoalesce`
  splits (9a3c20950/aaddf...). The reflection-coupled resolution half (`_currentStruct?.BaseDef`,
  `TryFindMethodOnChain` over the base chain, and the return-type guards `void`/enum/generic-param/
  `ContainsBuilderBoundType`/`IsSupportedType`) STAYS C# as a mechanical host. Byte-exact verifiable on
  the live corpus path `examples/06-classes-and-records/ConstructorChaining.nl:56`
  (`$"{base.GetInfo()} - {EmployeeId} ({Department})"`). N# splitter +TrySplitBaseCall + tests; C#
  emitter net-negative (removes the const/prefix/suffix guard + the name-validation block, keeps the
  `BaseDef==null` reflection guard + mechanical resolution). This supersedes the case-12 prune below,
  which is now COMMITTED at 6e94ca88c.
- Prior committed sub-slice (6e94ca88c, "Prune the dead case-12 residual arms by four-surface liveness
  proof"): pruned the case-12 primitive-binary whole-subtree residual to its live reaching-set. Four sub-arms proven DEAD
  across ALL FOUR exercise surfaces — corpus+native (162 assemblies), units (3,190), and self-emit
  (BootstrapServices kernels, full 228-arm run) — via IL-neutral arm instrumentation (0 IL diff baseline
  vs instrumented across all 162 assemblies), then DELETED:
  * `case "&"|"|"|"^"` bitwise residual arm
  * record-struct structural-equality residual arm (`==`/`!=` boxing through the synthesized Equals)
  * the `null == null` / `null != null` constant fold
  * the multi-term string-concat CHAIN lowering (`TryEmitStringConcatChain` + its sole-caller
    `CanProveStringExpression`) — the residual pair-concat (`String.Concat(string,string)`) STAYS.
  ColumnarIlEmitter.cs 21,534 -> 21,438 (net -96 lines / -92 non-blank; epoch ceiling 21,723/20,646
  untouched). N# delta: ZERO — ColumnarPrimitiveBinaryPlanner / ColumnarConditionalPlanner already own
  these operators at the front door; the residual only served a non-plannable-OPERAND band that is
  empty for these four families. No test migration (dead-code deletion; live coverage = native
  primitive-binary 16/16 + conditional 8/8). SLICE-5 GUARD HONORED: a PARTIAL self-emit run (166 arms)
  showed `stringcharconcat` dead, but the COMPLETE run (228 arms) caught it firing late, so it was
  RETAINED — the exact slice-5 escape signature; every dead verdict waited for the full self-emit.
  * Candidate (a) BLOCKED (definitive record): the live preflight static-call arm (case-9
    `TryFindStaticMethodOnChain` on `_enclosingType`) types the user's OWN enclosing-type static-method
    call results (bare identifier, no receiver) — NOT external `ColumnarExternalBindingPlans` catalog
    facts (external static calls have a type-name receiver whose `TryGetPreflightExpressionType` returns
    false, so they never reach this arm). It FIRED on the corpus -> load-bearing, not dead. Six lines
    fused into the unified bare-call preflight tier (localfn->sibling->ownstruct->ownstatic); deleting it
    regresses user-static-call-result typing. Rerouting to an N# planner return-type is the forbidden
    add-a-planner-for-a-relocation anti-pattern (identical to the lambda-arc Candidate A rejection): no
    decision deleted, net N#+plumbing positive. The other corpus-dead preflight arms are BCL-shape
    (span/AsSpan/ArrayPool/MemoryPool/Stream — self-emit-live: the kernels use them) or lambda-family
    (where/toarray/minmax/contains — blocked with the lambda arc). No net-negative deletion in (a).
  * Candidate (b) partial blocks (definitive record): within the SAME residual, three more sub-arms fire
    in SELF-EMIT (kernel compilation) though dead in corpus+native+units, so RETAINED: the case-13
    ternary residual (kernels have 80 ternaries incl. `setter == null ? 0 : 1`, ColumnarDefinitions.nl:189,
    the exact form task 007 flagged; the N# ColumnarConditionalPlanner declines non-Boolean conditions +
    mixed-type arms, so the residual still serves them); reference-identity equality on user reference
    types (`==`/`!=`); and string+char concat (`TryEmitStringCharConcat`). Residual arith (`+`/`-`/`*`/`/`)
    and ordering (`<`/`<=`/`>`/`>=`) are all self-emit-live. These retire only as their non-plannable
    OPERAND forms become N#-plannable — a future four-surface-gated cut, not this turn.

- Lambda-taking LINQ ownership ARC — staged plan (concrete owners + deletion targets; ordered by the
  d2257f33c refutation, whose three blockers are the ground truth for why stages 3–5 must precede any
  enumerable-arm deletion):
  * Stage 1 (THIS TURN): contextual-lambda SIGNATURE binding → `ColumnarLambdaPlacementPlanner`; delete the
    C# param-binding loop in `TryEmitLambdaLiteral`. DONE.
  * Stage 2 (THIS TURN): contextual-lambda CAPTURE-SET collection → N#. Move `CollectLambdaCaptures` (the pure
    AST capture-name scan against the enclosing local/param/lifted name sets) into an N# owner; the
    non-capturing-vs-capturing branch consumes the N# capture set. Delete the C# `CollectLambdaCaptures`
    walk (~35 lines). The this-capture member-chain scan `BodyReferencesEnclosingChain` (needs the emitter's
    member-chain resolvers) and the display-class capturing residual stay C# until Stage 6.
  * Stage 3a (THIS TURN): contextual-lambda RETURN-TYPE inference DECISION → N#. DONE. The
    `TryInferSingleParameterContextualDelegateReturnType` decision (which of the two admitted argument forms —
    a contextual lambda body vs a visible local-function method group — supplies a single-parameter
    contextual delegate's return type, refutation blocker 2's `Select`-result / MapGet-return machinery) now
    routes to `ColumnarLambdaPlacementPlanner.PlanSingleParameterContextualReturnType` (lambda precedence,
    null → decline). The two duplicated single/zero-parameter inference helpers
    (`TryInferSingleParameterLambdaReturnType` + `TryInferZeroParameterLambdaReturnType`) collapsed into one
    mechanical host `TryPreflightContextualLambdaReturnType` that reuses the N#-owned `PlanContextualSignature`
    for the parameter-SHAPE decision (removing the third duplicated C# shape authority) and consumes the
    scoped sub-emitter body-preflight mechanically. Emitter 21,551 → 21,534 (net −17). GROUND TRUTH from the
    inventory: the inference's core (recursive body preflight = the C# expression-typing engine) and its
    validity gates (`IsSupportedType`/`TypesEquivalent`, reflection-bound) cannot move without porting the
    whole preflight engine, so they stay mechanical; only the SHAPE + SELECTION decisions were movable.
  * Stage 3b/4: PROVEN BLOCKED (re-inventoried THIS TURN, Candidate C). N# cannot own lambda-chain EMISSION
    or DELETE the enumerable EMIT+PREFLIGHT arms until the lambda BODY is plan-row-emittable: today a lambda
    body is emitted by a recursive C# sub-emitter (`new ColumnarIlEmitter(...)` at ColumnarIlEmitter.cs:1551 +
    `EmitLambdaBody` at :1566, NOT `ColumnarCodePlanExecutor` plan rows) and typed by the C# preflight engine
    (`TryPreflightContextualLambdaReturnType` → scoped sub-emitter body preflight). Stage 3a moved only the
    return-type SELECTION to N#; it did NOT unblock emission. Neither the chain-admission decision (Candidate A)
    nor the Cast/OfType type-argument binding (Candidate B) is a net-negative decision deletion (reasons in the
    Active sub-slice above). Proven byte-exact: neutralizing the three arms fails 8 corpus builds + 3 native
    projects with 0 common-file IL diffs — the arms are the sole load-bearing emitter of lambda-taking chains
    and Cast/OfType. RE-SEQUENCED: this family retires as a DEDICATED FUTURE TASK "plan-row lambda-body emitter"
    (whole-expression columnar emission of lambda bodies via schema plan rows executed by
    `ColumnarCodePlanExecutor`, + N# lambda-chain planning that retires the `ColumnarDirectCallPlanner.nl:112`
    contextual-lambda decline). Only after that lands can the old Stage 4 (below) delete the arms.
  * Stage 4 (GATED on the plan-row lambda-body emitter task above): DELETE the lambda-taking enumerable EMIT +
    PREFLIGHT arms (`TryEmitEnumerableExtensionCall` Where/Select/ToArray/ToList/Contains/Min/Max +
    `TryGetPreflightEnumerableExtensionCallType` mirror) — retires refutation blockers 1+2 together.
  * Stage 5 (Cast/OfType, separable from lambdas but a NEW-capability slice): the explicit-type-argument
    `TryEmitExplicitEnumerableExtensionGenericCall` Cast/OfType arm is lambda-free but its `TResult` is a
    return-type-only generic parameter the N# `ColumnarExtensionMethodResolver` cannot structurally bind (the
    explicit arg is never consumed by inference). Owning it needs N# explicit-type-argument extension-call
    support + ported type-node/member-chain resolution — a new capability, not a duplicated-fact deletion.
    Separable from Stage 4 and can precede or follow it.
  * Stage 5' (was Stage 5): receiver WIDENING with user-source-extension precedence — model user-source extension precedence
    in `ColumnarExtensionMethodResolver` so BCL generic `First`/`Last` never shadow user extensions
    (`examples/07-interfaces/ExtensionMethods.nl`, refutation blocker 3), then admit interface/variance
    receiver widening for the generic non-lambda arms. NOTE: the widening logic itself was proven correct in
    isolation but the `ColumnarExtensionMethodResolver` widening test was REVERTED with the refuted slice —
    contracts baseline is 740 (now 747 with Stage 1), NOT 741.
  * Stage 6: value-capture DISPLAY-CLASS lowering → N# (the fenced capturing residual in `TryEmitLambdaLiteral`,
    the `<>c__DisplayClass` `ModuleBuilder.DefineType` path) — model the reflection-emit display-class surface
    in the columnar backend and retire the C# capturing path.
- Refutation ground truth (d2257f33c, do not re-litigate): the `ToArray`/`ToList`/`Contains` family has NO
  deletion-ready subset before Stages 3–4 land. (1) the EMIT arms are LOAD-BEARING for lambda chains routed
  via the contextual-lambda decline; disabling ToArray makes WeatherDemo fail to build. (2) the PREFLIGHT
  arms are LOAD-BEARING for lambda RETURN-TYPE inference (MapGet `() => …ToList()`, Endpoints.nl:28) — only
  the byte-exact corpus IL diff catches the `List<IssueResponse>` → `object` regression; builds + the full
  unit suite do not. (3) receiver widening is not admission-safe until user-source-extension precedence is
  modeled (BCL `First`/`Last` shadow user extensions).
- Next smallest concrete sub-slice: NONE remaining as a movable-decision deletion. See the "015 completion
  roadmap" below (the exhaustive three-way policy inventory that replaces the former ad-hoc residual lists):
  after this slice the directly-MOVABLE decision surface is EXHAUSTED (base-call was the last inline
  string-classification split), and every remaining policy decision is BLOCKED-WITH-RECORD on a named future
  task or is already a MECHANICAL reflection-emit host. Do NOT reopen the lambda arms (blocked on the plan-row
  lambda-body emitter task), the case-12/13 live residual families (retire only under the four-surface gate as
  planner OPERAND forms unlock), or candidate (a) preflight static-call typing (load-bearing, not net-negative).
- Method note (this turn): the byte-exact product-IL sweep (scratchpad `verify_basecall.sh`: baseline HEAD via
  `git stash` vs working tree, both fresh Release CLIs, `sweepall.sh` over examples+fixtures+all 18 tests/native)
  yielded PRODUCT_IL_DIFFS=0 across all 162 N#-emitted assemblies. The only expected non-product diffs are the
  C# `Compiler.dll`/`BootstrapServices.dll` binaries copied as a reflection-test dependency by the six native
  reflection projects (they reflect any emitter/kernel source change); exclude them and compare only N#-EMITTED
  assemblies.
- Last committed ownership slice: the case-12 residual dead-arm prune at `6e94ca88c` (ratchet head
  `40cb7fa576abc6c2`, a fresh non-VS-Code gate is fully green there). This turn's base-call classification
  deletion is NOT committed (mandate: do not commit); the working tree carries the emitter deletion + the
  N# splitter `TrySplitBaseCall` + its tests + repin + this STATUS update.
- Prior accepted ownership commits: task 014's slice commits (`d396a847c`, `73ae226d5`,
  `0a33f1ff2`, `f3d1e89c9`).
- Queue: `tasks/README.md`

## Current evidence

- Task 005 is accepted at `6746c1b2c` (stage-0 prerequisites `67a3e5803`,
  `37822d657`, `f9ed33dd9`, `aca8d35b3`, `91c062dd6`, `e63f27176`, and `ff2cf1138`). N# now owns
  construction planning end-to-end for the admitted family: ordinary source/runtime constructor
  calls with exact selection, defaults (including enum and dotted/aliased enum defaults), sized and
  inferred array literals with exact store opcodes, source class/struct/record and union-case object
  initializers (including nested values, generic-base member rebinding, and target-typed integers),
  closed source/runtime generic construction, and the approved runtime constructor catalog, all
  through schema-v3 plan rows executed and stack-validated by `ColumnarCodePlanExecutor`.
- The Analyzer's string-matched member/export/declaration resolution was deleted and replaced by
  the N#-owned `AnalyzerDeclarationContext`/`ColumnarSemanticTypeRegistry` exact-scope facts:
  `Analyzer.cs` fell from 23,471 to 23,068 lines. `ColumnarSynthesizedGenericScopeTests.cs` was
  deleted in favor of the native `generic-scope-invalid` project. Aggregate C# across the slice is
  net negative (−157 lines).
- The C# emitter retains exactly one fenced legacy surface for constructions: the whole-subtree
  residual (kinds 15/58/36 plus four helpers), reachable only when the N# planner declines without
  claiming (a value outside the plannable surface, e.g. interpolated holes or sibling-function call
  arguments). This mirrors the accepted task-004 fenced-call architecture; `ColumnarIlEmitter.cs`
  is 21,586 lines (epoch ceiling 21,723). The residual shrinks as later owners land (interpolation,
  sibling calls: task 015).
- Evidence: 3,182/3,182 units in the fresh gate (task 009's issue-tracker failure is FIXED by this
  slice); 553/553 BootstrapServices contracts; native product contracts all green: 14/14
  direct-calls, 18/18 ownership-audit, 7/7 construction-arrays (new), 3/3 generic-scope-invalid
  (new), 1/1 erased-enum-identity (new). Previously red vs HEAD and now green: `examples/16-task-cli`
  (union-case construction with interpolated argument), `examples/12-multi-file-projects/WeatherDemo`
  (record object initializer with call/index values), AutoDiscovery, issue-tracker backend check,
  and systems proof 36 (`new Dictionary<int,int>(capacity: 128)` named argument).
- The fresh non-VS-Code product gate has exactly four remaining failure groups, all verified
  byte-identical at HEAD `ff2cf1138` and assigned to later queue owners: Web API template build
  (009), Iterators single-file example (013), AsyncStreams single-file example (014), and the IL
  verification findings `RecordStructs.dll` CallVirtOnValueType/StackUnexpected (011) and
  `RecordsAndInterfaces.dll` InitOnly on `<InitializeFields>$` (012). Down from ten groups at the
  task-004 acceptance.
- The ownership growth ratchet is repinned to observed state (audit 18/18); the emitter entry rises
  only within its immutable epoch ceiling and records the restored fenced residual.
- Post-acceptance follow-ups `195028aa9` and `7f4e727d6`: columnar emission now runs on a dedicated
  wide-stack thread (MSBuild task threads run ~256 KB stacks and the emitter's per-node frames are
  large; the July-12 sources overflowed every fresh SDK-path emit), and the NL103 decline diagnostic
  is built inside that same thread (the decline trace is thread-local). The stale mid-slice SDK pack
  in `~/.nuget/local-feed` (the feed actually consulted; `~/.nsharp/packages` is not) was replaced,
  and the self-host loop is regenerative again: BootstrapServices Release re-emits cleanly through
  the packaged SDK, 553/553 contracts pass against the fresh kernel, and the clean repin is
  `nlc 0.1.0+7f4e727d615d2c38b5b71e6ac69690e5aa2275ff` with doctor status all-green.

## 015 completion roadmap

Exhaustive three-way classification of the REMAINING `ColumnarIlEmitter.cs` policy surface (this
replaces the former ad-hoc residual lists). Method: swept the full decision surface (516 members; the
`EmitExpressionCore` per-node-kind switch at ~10231, the `EmitStatement` switch at 6711, the preflight
typing engine `TryGetPreflight*`/`TryPreflight*` at 16718-17588, the interpolation core at 20340-21200,
the lambda family, and the declaration/reflection-emit hosting). N# planners run at the FRONT DOOR of
every dispatch (26 distinct `Columnar*Planner/Resolver/Facts` owners consulted before any C# residual
arm); the residual switch arms are whole-subtree-exit servers for non-plannable OPERAND bands.

### MOVABLE (an existing N# owner absorbs it with a named C# deletion) — EXHAUSTED
The interpolation string-classification splits were the only clean movable-decision family, and
`TrySplitBaseCall` (this slice) was the last of them (cast/equality/coalesce/integer-additive landed at
9a3c20950/aff33f1db/d37d3d732). The ~40-arm prior inventory (notes_015_pivot.md) plus this sweep find no
further decision an existing N# owner can absorb with a net-negative C# deletion. The two marginal
remainders are NOT clean decision deletions and are declined: decimal-literal VALUE parse (case 0/1 →
`TryEmitDecimalLiteral`, fused with the reflection-backed `decimal(...)` ctor emission → net N#+plumbing
positive, no decision deleted) and the entry-point return-shape rule (already N#-owned for async via
ColumnarIteratorPlanner facts; residual is reflection-typed return wrapping).

### BLOCKED-WITH-RECORD (proven/provable; retires via a named OTHER task)
1. LAMBDA-TAKING FAMILY — the dominant remaining policy block. `case 9` residual calls →
   `TryEmitEnumerableExtensionCall` (~17792: Where/Select/ToArray/ToList/Contains/Min/Max),
   `TryEmitExplicitEnumerableExtensionGenericCall` (~13943: Cast/OfType), `TryEmitLambdaLiteral` (~1491)
   + `EmitLambdaBody` recursive C# sub-emitter (~1702), `BodyReferencesEnclosingChain` (~1724), the
   `<>c__DisplayClass` capturing residual, and the preflight `TryPreflightContextualLambdaReturnType`
   (~17588) / `TryGetPreflightEnumerableExtensionCallType` (~17215). A lambda body is emitted by a
   recursive C# sub-emitter + typed by the C# preflight engine, not by plan rows. Stages 1–3a landed
   (signature/capture-set/return-type SELECTION → N#); Stage 3b/4/5/6 GATED on the FUTURE TASK "plan-row
   lambda-body emitter". Cited: lambda-arc Stages 3b–6, refutation d2257f33c, arms-off byte-exact proof.
2. C# PREFLIGHT TYPING ENGINE. `TryGetPreflightExpressionType` (~16718) + family
   (Binary/InstanceCall/MemberAccess/ExtensionSibling/ExtensionStatic). Reflection-bound expression-TYPING
   authority serving interpolation parsed holes + lambda return inference. Candidate (a) proven
   load-bearing (types the user's own enclosing-type statics, not catalog facts); its reroute is the
   forbidden add-a-planner-for-a-relocation anti-pattern. Retires via a FUTURE N# typing-owner port
   (adjacent to 017 analyzer semantic ownership).
3. LIVE case-12/13 RESIDUAL FAMILIES. `case 12` (short-circuit `&&`/`||`, null-comparison nullable+ref,
   `??` coalesce nullable+ref, signed arith `+`/`-`/`*`/`/`, ordering `<`/`<=`/`>`/`>=`, ref-identity
   equality on user reference types, string+char concat, String.Concat pair) and `case 13` ternary — all
   self-emit-load-bearing (four-surface probe). Retire ONLY as their non-plannable OPERAND forms become
   N#-plannable (member-chains-on-call-results, dictionary indexers, enum string constants) via the
   planners — an incremental four-surface-gated cut, not a movable relocation. Cited: 6e94ca88c prune.
4. BLOCKING-AWAIT MODEL. `case 53` await (`TryEmitBlockingAwait` ~6643) + `case 73` await-foreach
   consumer. The accepted synchronous GetAwaiter().GetResult() model retires when REAL async-func lowering
   lands (a FUTURE async-func task). Cited: 014 residuals.
5. INTERPOLATION CHAIN/PARSED-HOLE RESOLUTION. `TryResolveInterpolationChainPlan`/`TryResolveInterpolationHole`
   (~20885) + `TryResolveInterpolationMemberPlan` (~21041) + `TryParseInterpolationExpressionHole`/
   `TryGetParsedInterpolationExpressionType`. Chain tokenization is intertwined WITH reflection member/
   local/getter resolution (hop boundaries drive reflection) and parsed holes route through the preflight
   engine (#2). No clean string-classification split remains to peel off; retires with the preflight port.

### MECHANICAL (reflection-emit hosting, zero policy — the target end-state, already non-growing)
- Control flow + structural statement arms: block/if/while/for/return/break/continue, try/catch region ops
  (schema-4), lock lowering, throw, print, var/typed-local/tuple-deconstruction lowering, assert/
  assert-throws, expression-statement assignment, the StatementExits analysis mirror.
- Expression mechanical arms: parenthesized (7), checked-context (57), spread (64), unary (11, via
  ColumnarSourceOperatorResolver), is/as isinst (46/47), must (45), postfix ++/-- (44), match/pattern-test
  emit (18/34/33/35/32/8-pattern via ColumnarPatternFacts), index reads (10), anonymous-object synthesis (59).
- Construction/with/record/field-init: kinds 15/58/36/42 (ColumnarConstructionPlanner), 52
  (ColumnarRecordWithPlanner), record member synthesis, ColumnarFieldInitPlanner.
- Iterator/async hosting: yield (72), foreach (29), MoveNext/state-machine emission
  (ColumnarIteratorPlanner/ColumnarIteratorBodyPlanner), async fault guards.
- Type/member definition: DefineType/DefineMethod/DefineGenericParameters, union/generic declaration +
  constraints, delegate mapping (IsSupportedDelegateType/CreateDelegateType), bare-static + ref/out-deref
  reads (case 6), typeof, interpolation cast/equality/call-argument emit, and the base-call reflection
  RESOLUTION (this slice's mechanical host over TrySplitBaseCall's extracted name).

### VERDICT
015 does NOT complete this turn; its box stays UNCHECKED. After this slice the directly-MOVABLE decision
surface for 015-proper is EXHAUSTED. What concretely remains before the "reviewed, non-growing, zero-policy
mechanical host" criterion is met is ALL BLOCKED-WITH-RECORD policy that retires only via OTHER queue tasks:
- the FUTURE "plan-row lambda-body emitter" task (retires blocker #1: lambda family Stages 4/5/6 + the
  enumerable/Cast-OfType arms + display-class);
- a FUTURE N# preflight/typing-owner port (retires blockers #2 + #5: the C# typing engine and interpolation
  parsed-hole resolution) — adjacent to 017 analyzer;
- a FUTURE async-func-lowering task (retires blocker #4: blocking await);
- incremental planner-driven OPERAND unlocks that let the live case-12/13 residual families (#3) retire
  under the four-surface gate.
016 (parser) and 017 (analyzer) own the LSP-fallback parser/analyzer, NOT the emitter. 015's cursor is
therefore: no movable decision remains in the emitter; 015 is gated on the four future tasks above.

## 016 parser/diagnostic ownership finding

Verdict (this turn, PROVEN-BLOCKED-WITH-RECORD; no production edit, no commit): no bounded syntax
behavior can be moved from `src/NSharpLang.Compiler/Parser.cs` (7,117 lines; ratchet row
`compiler-core`, ceiling 7,117, fingerprint `text-v1:895641da1f9de8a6`) to N# as the "sole production
parser + ordered diagnostic authority" this turn while keeping every compiler AND Language Server
consumer byte-exact. The AST-shape half and the syntax-diagnostic half are gated on the SAME missing
prerequisite. Evidence below is code + committed-test grounded (the C# model is verified-green by the
full VS Code-enabled gate at HEAD `2859f8329`); no fresh live run was required.

### Inventory — who consumes `Parser.cs` output (exactly)
`Parser.ParseCompilationUnit()` returns `ParseResult { CompilationUnit, Errors }` — the C#
`CompilationUnit` AST + the syntax diagnostics. Every non-emit front-end consumes it MONOLITHICALLY:
- `MultiFileCompiler.ParseAllFiles` (192-198): `_allErrors.AddRange(parseResult.Errors)` — the
  production `nlc build`/check syntax-diagnostic source; Analyzer/Systems/Linter then run on the C# AST.
- `LanguageServer/Services/DocumentManager` (250-296): builds `state.CompilationUnit` ONCE, then the
  Analyzer, Linter, symbol/hover/completion extraction, and all 25+ LSP handlers read that one AST.
- `Analyzer.cs` (5 parse sites: cross-file/project/import), `Formatter.cs`, CLI `Program.FormatSource`
  (688) + `LintCommand` (90), `CodeIntelligence/{FixApplicator,CodeIntelligenceService}` (fix/query),
  `Playground`.
The N# columnar parser kernels (`CompilerServices/ColumnarParserKernels.nl`, 13,773 lines) produce
columnar node TABLES consumed ONLY by the emit pipeline (`ColumnarProgramInputBuilder` →
`ColumnarIlEmitter`), and only AFTER the C# path is error-free (`MultiFileCompiler` gates emit on zero
errors). They build no `CompilationUnit` and feed no tooling/LSP consumer. NO node-table→C#-AST bridge
exists; materialization-to-AST was explicitly rejected (memory
`project_parser_routing_materialization_deadend`: "port downstream to consume columnar tables directly").

### Why the AST-shape families are blocked (imports/namespaces, type/member decls, functions/generics, statements, expressions, patterns)
Moving any AST-shape behavior to N# requires the tooling/LSP front-end to consume N#-produced facts for
that behavior. The front-end reads the whole C# `CompilationUnit` as one recursive tree; a single node
family cannot be excised from that tree without breaking the tree the Analyzer/LSP read, and there is no
bridge to splice N# facts in per-family. Blocked on the bridge.

### Why the syntax-diagnostic families are blocked (the unwired `ColumnarSyntaxDiagnostics` arc)
A prior 9-commit arc (`760cf0203`..`771f741b7`, Jul 8, ALL ancestors of HEAD, ALL PURE ADDITIONS — zero
`Parser.cs` deletion, zero consumer wiring) built an UNWIRED N# owner: `ColumnarSyntaxDiagnostics.ParseFile`
+ `ParserDiagnosticMessages.Materialize` + `ParserDiagnosticsTable`. It has ZERO external references (C#
or N#), is in no `.tests.nl`, and `Parser.cs` still owns every production syntax diagnostic. It CANNOT be
wired byte-exact, for three independent reasons:
1. COVERAGE. It mirrors ~20 of `Parser.cs`'s ~256 distinct syntax diagnostics (100 emit sites) — 10
   "expected-token/malformed" families only (`ParserDiagnosticMessageKind` 1-20). Wiring `ParseFile` as
   the sole authority would LOSE ~236 diagnostics (missing `)`/`]`/`}`/`:`/`;`/`=>`, unexpected tokens,
   dangling operators, constraint conflicts, pattern/match/test-DSL errors, …) — a catastrophic regression.
2. DIVERGENT SUPPRESSION MODEL. `Parser.cs` emits inline during ONE recursive-descent pass gated by one
   shared `_panicMode` flag (`ReportError` at 6856 returns early if panic; sets panic after each error;
   resets only at true parse-structure sync points — declaration/statement/member/case boundaries).
   Committed tests PIN this: `Parser_CascadingErrorsSuppressed` (`Errors.Count <= 5`),
   `Parser_DanglingBinaryOperator_DoesNotSwallowFollowingStatements` (exactly one error, exact column 14
   / length 3, parse-context message "Expected expression after '+'"). The N# owner runs 10 INDEPENDENT
   whole-token-scan collectors, each with a per-token-boundary panic heuristic (`ParserDiagnosticTable.
   PanicMode`, reset at Newline/Semicolon/Comma/Brace) threaded across sequential passes. The models
   diverge exactly in the cascading-error cases the tests pin, and the collectors fire on scan-reached
   tokens vs the parser's parse-reached tokens.
3. SHARED-PANIC COUPLING ⇒ NO BOUNDED SINGLE-FAMILY EXTRACTION. Deleting any one family's inline
   `Parser.cs` report also deletes its `_panicMode = true` side-effect, changing the suppression seen by
   every subsequent diagnostic of EVERY OTHER family. So even a single-family diagnostic move is not
   side-effect-free and cannot be verified byte-exact against the 520-assertion
   `LanguageServerDiagnosticsTests` + `ParserErrorTests`/`ErrorHandlingTests`.
Note: the C# report site already delegates `CompilerError` CONSTRUCTION to the shared N#
`ParserErrorDiagnostics.Create`, so only the DECISION (whether/where to report, under the shared panic
model) + the message/hint/suggestion literals are C#-owned. Moving just the literals is NOT a
decision-ownership move and is declined.

### Prerequisite that unblocks 016 (sized honestly)
One N# parse front-end whose output the C# tooling/IDE consumers can consume in place of `Parser.cs`. Either:
(a) Extend the N# columnar parser kernels to (i) emit the FULL syntax-diagnostic surface WITH the parser's
    shared-panic recovery model (NOT the `ColumnarSyntaxDiagnostics` token-scan mirror) and (ii) expose a
    `CompilationUnit`-equivalent / node-table facts the Analyzer/Linter/Formatter/LSP handlers consume;
    validated byte-exact against the diagnostic + parser-error suites. This is a PARSER-KERNEL change → it
    TRIPS THE TWO-STAGE BOOTSTRAP WALL (coordinator toolset repin required before dependent code compiles)
    and is a multi-slice effort, not one bounded deletion. OR
(b) Port the tooling front-end (Analyzer/Linter/Formatter/LSP handlers) to consume the columnar node tables
    directly (the memory-endorsed direction) — task 017+ (analyzer ownership) scope, far beyond one bounded
    parser slice.
The `ColumnarSyntaxDiagnostics` arc is scaffolding for path (a)'s diagnostic half but is incomplete (~8%
coverage) and model-divergent; it must NOT be wired as-is. `Parser.cs` stays the sole production syntax
parser/diagnostic authority until the prerequisite lands; 016 stays UNCHECKED.

### Staged parser-front-end ARC PLAN (chosen: path (a), the recovery-aware N# front-end)
The finding above is STAGE 0 (the prerequisite record). The arc builds path (a)'s kernel-side capability to
FULL parity FIRST (family by family, each stage's diagnostics proven byte-exact against Parser.cs on a
native parity corpus), then production-wires the consumers LAST at parity, then deletes Parser.cs. This is
the 013/014/lambda-arc precedent: a proven-record capability arc, not a single byte-exact deletion. No
production shadow/comparison route ever runs — parity proofs live only in `.tests.nl`.

- STAGE 1 (LANDED this turn) — the SHARED-PANIC RECOVERY MODEL + first diagnostic family. New owner
  `src/NSharpLang.Compiler.BootstrapServices/ColumnarParserRecovery.nl` faithfully reproduces Parser.cs's
  recovery discipline (one shared `PanicMode`; `Report` suppresses-while-set / records-in-source-order /
  sets-panic; reset ONLY at the declaration-boundary sync point; the `ConsumeIdentifier` reserved-keyword /
  end-of-file / found-other variants; `LastVisibleTokenSpan` EOF anchoring) and carries the
  IMPORT / NAMESPACE / PACKAGE family end-to-end (qualified-name identifier errors, dot-access member
  errors, missing import alias, duplicate-package). Diagnostic CONSTRUCTION delegates to the already-live
  shared owner `ParserErrorDiagnostics.Create` (the same call Parser.cs uses), so codes/snippets/docs URLs
  match automatically. Proven by 11 native contracts in `ColumnarParserRecovery.tests.nl` against golden
  Parser.cs output captured from the fresh CLI — INCLUDING the two committed-test model shapes: cascading
  suppression (triple-package → 1 diagnostic; the third suppressed with no intervening reset, mirroring
  `Parser_CascadingErrorsSuppressed`) and does-not-swallow-following (package/package/stray-token → 2
  diagnostics; the declaration-boundary reset lets the stray token report, mirroring
  `Parser_DanglingBinaryOperator_...`). NO production wiring; NO wall tripped (self-contained new files, the
  packaged SDK emits them — no repin). Evidence: BootstrapServices contracts 773/773 (762 baseline + 11);
  ownership audit 18/18; dev.sh Parser 381/381.
- STAGE 2 (LANDED this turn) — the DECLARATION-NAME family. Extended `ColumnarParserRecovery.nl` with
  `ConsumeDeclarationName` (Parser.cs ConsumeIdentifier with a non-null diagnosticSpan, :6720) carrying the
  "Expected <kind> name" diagnostics for func / class / struct / record / soa record / interface / union /
  enum / type-alias, with the `DiagnosticSpanFromToken` KEYWORD-ANCHORING discipline (missing/invalid name
  underlines the declaration keyword in all three variants) and the reserved-keyword-as-name variant; plus
  the `ParseTopLevelDeclaration` dispatch (ParseModifiers + the exact Parser.cs keyword order incl.
  `ref struct` / `soa record` / `duck interface` / `record struct` + LookAhead), the per-kind name parsers,
  and the boundary/force-advance loop (Parser.cs ParseCompilationUnit :83/:99-108). Bodies are NOT parsed;
  the corpus keeps to shapes where a name-only parser is byte-exact with the full Parser.cs body parse
  (absent-at-EOF, reserved-keyword-then-EOF for every kind; found-other only for func/enum/type, whose
  failing body consumes no trailing token so the stray token fires at the next boundary — the panic-reset
  demonstration). +24 native contracts; BootstrapServices 797/797 (773+24); ownership audit 18/18; git
  status shows only the two `.nl` files (no non-N# move). NO production wiring; NO wall (self-contained).
- STAGE 3..N (per-family capability, each proven byte-exact on the parity corpus, NO production wiring):
  extend `ColumnarParserRecovery` family by family until it matches Parser.cs's full ~256-diagnostic
  surface under the shared-panic model. Suggested order (smallest-coherent first): malformed-literal family
  (unterminated string/char/triple/interpolated, empty char — the families the deleted scaffolding used to
  mirror) → member/parameter/field decls (`:`/`:=` colon and type errors) → generics/constraints
  (`ConsumeGreater`, split `>>`, type-param / type-argument errors) → statements (the
  `SynchronizeToNextStatement` sync point + dangling-operator / missing-initializer / missing-condition
  shapes the ParserErrorTests pin) → expressions/patterns → closing-delimiter recovery
  (`TryReportMissingClosingDelimiter`, missing `)`/`]`/`}`; note STAGE 2's declaration bodies retire here).
  Each stage adds the family's `ConsumeX`/`ReportError` sites + its sync-point discipline, and grows the
  parity corpus; each stays self-contained (new/edited `.nl` in BootstrapServices + `.tests.nl`) UNLESS a
  stage needs a kernel entry point dependents compile against — that stage TRIPS the two-stage bootstrap
  wall and needs a coordinator repin (call it out at stage start).
- STAGE N+1 (AST/node-table facts): expose a `CompilationUnit`-equivalent / node-table surface the
  Analyzer/Linter/Formatter/LSP consume in place of Parser.cs's C# `CompilationUnit`, proven fact-equivalent.
- STAGE N+2 (CUTOVER, IDE-AFFECTING): at full diagnostic + AST parity, route every consumer
  (`MultiFileCompiler.ParseAllFiles`, `DocumentManager`, `Analyzer`, `Formatter`, CLI format/lint,
  `CodeIntelligence`, Playground) directly to the N# front-end. VS Code-enabled gate + extension reinstall +
  computer-use visual check. No shadow route.
- STAGE N+3 (DELETION ARC): delete Parser.cs's per-family parsing/recovery/reporting decisions as each
  consumer is cut over, ending when Parser.cs is deleted or is a reviewed zero-policy mechanical host
  (`compiler-core` ratchet row retires). The C# `ParserErrorTests`/`ErrorHandlingTests`/
  `LanguageServerDiagnosticsTests` assertions migrate to native `.tests.nl` as their families cut over.

### Scaffolding fate decision (recorded): DELETE the divergent `ColumnarSyntaxDiagnostics` closure
The inert prior-arc scaffolding is SUPERSEDED by `ColumnarParserRecovery` (which uses the correct shared
ordered-panic model, not the divergent 10-pass per-token-scan model that must never be wired). The closure
`{ColumnarSyntaxDiagnostics.nl, ParserDiagnosticMessages.nl, ParserDiagnosticsTable.nl}` was fully
self-contained (zero external references — verified across all of src+tests; the four support types
`ParserDiagnosticTable`/`ParserDiagnosticTableOps`/`ParserDiagnosticMessageKind`/`ParserDiagnosticContextKind`
were reachable only through that closure) and has been DELETED this turn to honor the no-dead-code rule.
`ParserErrorDiagnostics.nl` is KEPT — it is LIVE (Parser.cs and now `ColumnarParserRecovery` both call
`ParserErrorDiagnostics.Create`). Its message templates are not lost: the message ORACLE is Parser.cs
itself, and git history preserves the scaffolding. Not ratchet-tracked (all `.nl`); the deletion left the
BootstrapServices contract count unchanged at 773 (the deleted files carried no `.tests.nl`).

## Iterative-task targets

These are populated only when their task becomes current.

- Task 015 next emitter sub-slice: NONE — movable-decision surface exhausted (see the 015 completion
  roadmap above); gated on the plan-row lambda-body emitter, N# preflight/typing-owner port, async-func
  lowering, and incremental planner OPERAND unlocks.
- Task 016 next parser sub-slice: STAGE 3 of the parser-front-end arc (see the "Staged parser-front-end
  ARC PLAN"). STAGE 1 (recovery model + import/namespace/package) and STAGE 2 (declaration-NAME family) have
  LANDED. STAGE 3 = the next-smallest family through the SAME shared-panic model, proven byte-exact on the
  parity corpus — smallest-coherent first: the MALFORMED-LITERAL family (unterminated string/char/triple/
  interpolated, empty char — the families the deleted scaffolding used to mirror), then member/parameter/
  field decls. Still kernel-capability-only (no production wiring, no IDE gate). Stays self-contained
  (BootstrapServices `.nl` + `.tests.nl`, no repin) unless the stage needs a kernel entry point dependents
  compile against — call out the two-stage bootstrap wall at stage start. Do NOT resurrect the deleted
  `ColumnarSyntaxDiagnostics` scanner (divergent per-token panic model). NOTE for a later stage: STAGE 2
  models declaration NAMES only (no bodies), so found-other names for class/struct/record/interface/union
  are deferred to the body/closing-delimiter stage where the member-list parse becomes byte-exact.
- Task 017 next semantic sub-slice: not selected
- Task 018 next systems-policy sub-slice: not selected
- Task 019 next tooling sub-slice: not selected
- Task 020 next native-runner sub-slice: not selected

## Completion ledger

Completed slices:

- Task 016 — THIRD slice (parser-front-end arc STAGE 2): the DECLARATION-NAME diagnostic family, in N#,
  PROVEN byte-exact against Parser.cs. NOT committed (mandate: do not commit); working tree carries the two
  edited N# files + STATUS. NO production wiring — Parser.cs remains the sole production syntax authority.
  - Extended N# owner `ColumnarParserRecovery.nl`: `ConsumeDeclarationName(message, anchor)` (Parser.cs
    ConsumeIdentifier with a non-null diagnosticSpan, :6720) — the keyword-anchor overrides the offending-
    token span in all three variants (reserved-keyword NL109 / end-of-file NL104 / found-other NL102), so a
    missing/invalid declaration name underlines the DECLARATION KEYWORD. Added the `ParseTopLevelDeclaration`
    dispatch (ParseModifiers + the exact Parser.cs ParseDeclaration keyword order, incl. `ref struct` /
    `soa record` (contextual, LookAhead) / `duck interface` / `record struct` variants), the per-kind name
    parsers (func/class/struct/record/soa/interface/union/enum/type-alias, each anchoring on
    DiagnosticSpanFromToken(keywordToken) per Parser.cs :435/939/984/1029/1067/1143/1173/1247/1337), a
    `LookAhead` helper, and the boundary loop with the force-advance safety net (Parser.cs
    ParseCompilationUnit :83/:99-108). Removed the now-unreferenced `IsDeclarationStart`/
    `IsContextualDeclarationStart` (superseded by the dispatch). Bodies are NOT parsed (a later arc stage).
  - Site inventory (Parser.cs ConsumeIdentifier sites carried, with keyword anchor): func :435, class :939,
    struct :984, record :1029, soa record :1067, interface :1143, union :1173, enum :1247, type-alias :1337
    (the last uses `new DiagnosticSpan(line,column,Math.Max(1,"type".Length))` = SpanFromToken(typeToken)).
    All route through the shared `ConsumeDeclarationName` + `ReportReservedKeywordAsName` + `Report` model;
    the terminal unexpected-token arm reuses Parser.cs ParseDeclaration :241.
  - +24 native contracts in `ColumnarParserRecovery.tests.nl`: per-kind absent-name (EOF, 11 incl. the soa
    col-5 / duck col-6 / record-struct anchor variants), per-kind reserved-keyword-as-name (8 core kinds),
    found-other for func/enum/type (the panic-reset shape: name error then the stray token fires at the next
    boundary), and two panic-model interaction fixtures (`func 5\nenum` three-diagnostic cross-boundary;
    `class struct\nfunc class` two reserved names at two boundaries). Every expected value is GOLDEN Parser.cs
    output captured from the fresh Release CLI (`nlc check --json`, filtered to NL101-NL109).
  - Method: BootstrapServices cannot reference Parser.cs, so parity is proven against golden Parser.cs output
    captured out-of-band, same as STAGE 1. class/struct/record/interface/union found-other cases were
    DELIBERATELY EXCLUDED (their member-list body consumes the trailing junk and resets panic, diverging from
    a name-only parser — verified against the oracle, e.g. `class 5` → NL102+NL106+NL102 not NL102+NL101);
    they retire in the body/closing-delimiter stage.
  - Evidence: BootstrapServices contracts 797/797 (773 baseline + 24 new; packaged SDK 0.1.0 self-emits the
    edited owner cleanly); ownership audit 18/18 (no ratchet change — all deltas are `.nl`); git status shows
    ONLY the two `.nl` files changed (no non-N# file moved). Full unit suite / corpus IL sweeps are N/A —
    nothing in the production compile path changed (the owner is inert, referenced only by its own tests). No
    LSP/VS Code change → no extension reload. NO wall tripped (self-contained, no dependent compiles against a
    changed kernel signature). Next: STAGE 3 (malformed-literal family).

- Task 016 — SECOND slice (parser-front-end arc STAGE 1): shared-panic RECOVERY MODEL + import/namespace/
  package diagnostic family, in N#, PROVEN byte-exact against Parser.cs. NOT committed (mandate: do not
  commit); working tree carries the two new N# files + the `ColumnarSyntaxDiagnostics` scaffolding deletion
  + STATUS. NO production wiring — Parser.cs remains the sole production syntax authority (cutover is the
  arc's last stage).
  - Added N# owner: `src/NSharpLang.Compiler.BootstrapServices/ColumnarParserRecovery.nl` — a faithful
    reproduction of Parser.cs's `_panicMode` lifecycle (one shared flag; suppress-while-set; set-on-report;
    reset only at the declaration-boundary sync point), ordered reporting, and the `ConsumeIdentifier`
    reserved-keyword / end-of-file / found-other message variants + `LastVisibleTokenSpan` EOF anchoring,
    carrying the import/namespace/package family end-to-end (qualified-name identifier errors, dot-access
    member errors, missing import alias, duplicate-package, and the declaration-boundary terminal
    unexpected-token arm). Diagnostic construction delegates to the live shared `ParserErrorDiagnostics.Create`.
    Introduces a local `RecoverySpan` reference class instead of the C#-owned `DiagnosticSpan` value struct
    (user value-struct construction is not yet columnar-emittable), and inlines the Newline-strip compaction
    (the reference-typed `out` argument on `ParserTokenCompactor.TryCompact` is not yet columnar-emittable) —
    both faithful to Parser.cs's behavior. Plus `ColumnarParserRecovery.tests.nl` — 11 native parity
    contracts against golden Parser.cs output (captured from the fresh CLI), including the cascading-
    suppression shape (`Parser_CascadingErrorsSuppressed`) and the does-not-swallow-following shape
    (`Parser_DanglingBinaryOperator_...`).
  - Deleted N# owner: the inert divergent `ColumnarSyntaxDiagnostics` scaffolding closure
    (`ColumnarSyntaxDiagnostics.nl` + `ParserDiagnosticMessages.nl` + `ParserDiagnosticsTable.nl`, ~2,177
    lines) — superseded by the correct-model `ColumnarParserRecovery`; zero external references (verified);
    `ParserErrorDiagnostics.nl` kept (live). See the arc plan's scaffolding-fate decision.
  - Method: BootstrapServices cannot reference Parser.cs (Compiler depends on BootstrapServices, not the
    reverse), so parity is proven against GOLDEN Parser.cs output captured out-of-band via `nlc check --json`
    on the malformed corpus, filtered to parser codes NL101-NL109. Both paths construct diagnostics through
    the identical live `ParserErrorDiagnostics.Create`, and the CompilerError→DiagnosticResult mapping +
    `DiagnosticSpanResolver.Resolve` (length>0) are identity for these cases, so the golden values equal the
    owner's raw CompilerError fields.
  - Evidence: BootstrapServices contracts 773/773 (762 baseline + 11 new; unchanged by the scaffolding
    deletion — no `.tests.nl` in it); ownership audit 18/18 (no ratchet change — all deltas are `.nl`, and
    the ratchet tracks only non-N# files); dev.sh Parser 381/381 (C# build re-emits the new file + the
    deletion cleanly, Parser oracle green). NO wall tripped: the self-contained shape (new `.nl` + `.tests.nl`,
    no dependent compiling against a changed kernel signature) emits through the packaged SDK 0.1.0 with no
    repin. Full unit suite / corpus IL sweeps are N/A this stage — nothing in the production compile path
    changed (the new owner is inert, referenced only by its own tests; the deletion removed inert code). No
    LSP/VS Code change → no extension reload. Next: STAGE 2 (next diagnostic family — declaration-name or
    malformed-literal — through the same model).

- Task 016 — FIRST slice: PROVEN-BLOCKED-WITH-RECORD (no commit; mandate: do not commit; STATUS.md-only,
  working tree otherwise clean). No C#/N# production delta. The full consumer inventory, the AST-bridge
  blocker, the syntax-diagnostic blockers (`ColumnarSyntaxDiagnostics` ~8% coverage / divergent panic
  model / shared-panic coupling), and the honestly-sized prerequisite are recorded in the "016
  parser/diagnostic ownership finding" section. Evidence is code + committed-test grounded: ~256 vs ~20
  diagnostic coverage; `Parser_CascadingErrorsSuppressed` + `Parser_DanglingBinaryOperator…` pin the
  shared-panic model; `ColumnarSyntaxDiagnostics`/`ParserDiagnosticMessages`/`ParserDiagnosticsTable` have
  ZERO external references and no `.tests.nl`; `MultiFileCompiler`/LSP/`Analyzer` all consume the C#
  `CompilationUnit` monolithically with no node-table→AST bridge. Next: the enabling PARSER-KERNEL slice
  (kernel-repin wall) or the task-017 front-end port.

- Task 015 sub-slice — interpolation BASE-CALL classification → N# splitter. NOT committed this turn
  (mandate: do not commit); working tree carries the emitter deletion + the N# splitter method + its tests
  + repin + STATUS.
  - Deleted C# owner: the string-classification half of `TryResolveInterpolationBaseCallPlan` (the `base.`
    prefix + `()` suffix Ordinal parse and the method-name extraction/validation with the no-`.`/`(`/`)`
    guard) in `ColumnarIlEmitter.cs`. Replaced by one mechanical call to
    `ColumnarInterpolationSplitter.TrySplitBaseCall(text, out methodName)` plus a fence comment; the retained
    `_currentStruct?.BaseDef == null` reflection guard, `TryFindMethodOnChain` base-chain resolution, and the
    return-type guards (`void`/enum/generic-param/`ContainsBuilderBoundType`/`IsSupportedType`) stay as the
    mechanical host. `ColumnarIlEmitter.cs` fell 21,438 → 21,433 (net −5 lines / −4 non-blank; epoch ceiling
    21,723/20,646 untouched). This was the LAST inline interpolation string-classification split (cast/
    equality/coalesce/integer-additive already N#-owned) — the movable-decision surface is now exhausted (see
    the 015 completion roadmap).
  - Added N# owner: `ColumnarInterpolationSplitter.TrySplitBaseCall` (an exact mirror of the accepted
    `TrySplitCast`/`TrySplitEquality`/`TrySplitCoalesce` split-decision methods; `import System` added for
    `StringComparison.Ordinal`) + two canonical `.tests.nl` contracts (decompose modeled base-call holes;
    decline non-base-call shapes: no prefix, no `()` suffix, arg-suffix, empty name, paren-in-name, dotted
    name).
  - Method: the live corpus path `examples/06-classes-and-records/ConstructorChaining.nl:56`
    (`$"{base.GetInfo()} - {EmployeeId} ({Department})"`) exercises the arm, making the relocation directly
    byte-exact verifiable rather than a dead-code deletion.
  - Evidence: product IL BYTE-EXACT — PRODUCT_IL_DIFFS=0 across all 162 N#-emitted example/fixture/native
    assemblies (baseline HEAD `6e94ca88c` via `git stash` vs working tree, both fresh Release CLIs,
    `sweepall.sh`); native 208/208 (18 projects; ownership-audit 18/18 post-repin — the single pre-repin
    failure was the ratchet net-negative check, cleared by the repin); BootstrapServices contracts 762/762
    (760 baseline + 2 new split tests, fresh Release self-emit); units 3,190/3,190 Release; Web API template
    builds via the IL backend; ratchet repin (currentLines 21,438→21,433, head `d7f043fb072388db`, mirrored
    in OwnershipAudit.nl).

- Task 015 pivot sub-slice — case-12 primitive-binary residual dead-arm prune (pivot off the blocked
  lambda family). COMMITTED at `6e94ca88c` ("Prune the dead case-12 residual arms by four-surface liveness
  proof"); ratchet head `40cb7fa576abc6c2`.
  - Deleted C# owners: the case-12 primitive-binary whole-subtree residual's four provably-dead sub-arms —
    the `&`/`|`/`^` bitwise arm, the record-struct structural-equality arm (`==`/`!=` boxing through the
    synthesized Equals), the `null == null`/`null != null` constant fold, and the multi-term string-concat
    CHAIN lowering (`TryEmitStringConcatChain` + its sole caller `CanProveStringExpression`). The residual
    pair-concat (`String.Concat(string,string)`) and the reference-identity/string+char/ternary residuals
    stay (self-emit-live). `ColumnarIlEmitter.cs` fell 21,534 -> 21,438 (net -96 lines / -92 non-blank;
    epoch ceiling 21,723/20,646 untouched).
  - Added N# owners: none — ColumnarPrimitiveBinaryPlanner / ColumnarConditionalPlanner already own the
    plannable surface at the front door; the deleted arms served an empty non-plannable-operand band.
  - Method: IL-neutral env-gated arm instrumentation (0 IL diff instrumented vs baseline across all 162
    assemblies) built a FOUR-surface liveness map (corpus+native, units 3,190, full self-emit 228 arms).
    The four deleted arms were 0 on all three logs; three sibling arms (ternary, ref-identity equality,
    string+char) were caught firing in the FULL self-emit and RETAINED (a partial 166-arm run had missed
    `stringcharconcat` — the slice-5 escape signature). Candidate (a) preflight static-call typing proven
    load-bearing (types user-owned enclosing-type statics, not catalog facts) — blocked, recorded.
  - Evidence: product IL BYTE-EXACT (0 diffs across all N#-emitted example/fixture/native assemblies; the
    only 12 sweep diffs are the C# `Compiler.dll`/`BootstrapServices.dll` binaries copied as a reflection-test
    dependency by 6 native projects — expected reflection of the emitter source change, not product IL);
    native 208/208 (18 projects, ownership-audit 18/18 post-repin); BootstrapServices contracts 760/760
    (two-stage, fresh deletion Release SDK); units 3,190/3,190 (Debug and Release); Web API template builds
    via the IL backend; ratchet repin (audit 18/18, head `40cb7fa576abc6c2`); clean feed restored.

- Task 001 — external static fields and properties; commit `6110bbbcf`.
  - Deleted C# owners: `TryUsePlannedExternalStaticMember`,
    `PreloadSupportedExternalReferenceAssemblies`, `TryGetStringComparisonValue`,
    `TryEmitPrimitiveStaticConstant`, and the matching enum/primitive/pool/static-member emission
    and preflight branches. `ColumnarIlEmitter.cs` fell from 21,515 to 21,361 lines.
  - Added N# owners: `ColumnarBindingScopeFacts`, `ColumnarExternalStaticMemberPlanner`,
    `ExternalAssemblyScan`, `ExternalQualifiedTypeResolver`, schema-v3 field handles/`ldsfld`, and
    their native contracts plus package and relative-DLL product fixtures.
  - Evidence: 3,182 units; 178 BootstrapServices contracts; 18 ownership tests; package,
    outside-CWD DLL, issue-tracker, exact-reference, persisted execution, and clean repin proofs.

- Task 002 — bound identifier reads; commit `61a593715`.
  - Deleted C# owners: ordinary local/non-byref-parameter, lifted-local, boxed-capture,
    explicit-`this`, and bare current-instance field/property identifier emission, plus the
    matching preflight/type branches. `ColumnarIlEmitter.cs` fell from 21,361 to 21,209 lines.
  - Added N# owners: `ColumnarBoundIdentifierPlanner`, exact lexical/current-instance binding
    facts, recursive code-plan argument-address and declared-signature validation, live source-type
    metadata, and atomic zero-arity property accessor definition, with native malformed, rollback,
    shadowing, generic/inherited receiver, persisted, and source-type-return contracts.
  - Evidence: 3,182 units; 201 BootstrapServices contracts; 26 range-index product contracts;
    18 ownership tests; fresh non-VS-Code product-gate task surfaces; clean SDK repin.

- Task 003 — instance fields and properties; commit `ad51692d4` (stage-0 prerequisites
  `da2be2c32`, `97cde7c6e`, and `aedb1267f`).
  - Deleted C# owners: direct one-receiver source field/property read emission, direct
    `Exception.Message` and `WebApplication.Environment` property arms, the member-chain preflight
    shortcut for the migrated roots, `typeof` emission/preflight, and zero-hole interpolation
    emission. The retained source-member branch is restricted to excluded nested receivers.
    `ColumnarIlEmitter.cs` fell from 21,209 to 21,164 lines.
  - Added N# owners: `ColumnarInstanceMemberPlanner`, exact runtime/source member resolvers,
    schema-v3 field/method/type handles and receiver-address operations, `ColumnarTypeOfPlanner`,
    zero-hole interpolation receiver planning, and live source type/union/tuple facts, with native
    accessibility, shadowing, inheritance, closed-generic, value/reference/byref, corrupt-handle,
    rollback, persisted-execution, nested-fallback, and recursive range/index contracts.
  - Evidence: 3,182 units; 238 BootstrapServices contracts; 41 range-index product contracts;
    18 ownership tests; three adversarial audits; fresh non-VS-Code product-gate task surfaces;
    clean SDK repin.

- Task 004 — fixed-arity direct calls; commit `5ad756e1d` (stage-0 prerequisites `d6d551ea1`,
  `d24ec7bb4`, `8ce4d49e2`, `fcbcf4ef6`, `0cd216a44`, `0e1d02ed1`, `507742abc`,
  `1e747dd97`, `469408917`, `1b63b9a82`, and `0035d82ae`).
  - Deleted C# owners: synthesized-record `Equals(object)` and `GetHashCode()` call preflight and
    emission, the direct `TextWriter.WriteLine(string)` arm, and unrestricted re-entry into ordinary
    source/runtime fixed-call paths. Retained C# routes are mechanically fenced to excluded call
    families. `ColumnarIlEmitter.cs` fell from 21,164 to 21,097 lines.
  - Added N# owners: `ColumnarDirectCallPlanner`, exact source/runtime resolvers, contextual
    conversion and nullable lowering, source-static scope resolution, exact method/constructor facts,
    address-preserving value receivers, synthesized record call facts, and schema/executor stack
    validation, with native overload, accessibility, malformed-handle, rollback, recursive,
    persisted, alias/shadowing, and IL-shape contracts.
  - Evidence: 3,181/3,182 fresh-gate units with only Task 009 remaining; 382 BootstrapServices
    contracts; 14 direct-call, 2 interface-parameter, 18 ownership, 4 decline-diagnostic, and 2
    reflection-bootstrap contracts; exact ILVerify; three adversarial audits; clean SDK repin.

- Task 005 — construction and array literals; commit `6746c1b2c` (stage-0
  prerequisites `67a3e5803`, `37822d657`, `f9ed33dd9`, `aca8d35b3`, `91c062dd6`, `e63f27176`,
  and `ff2cf1138`).
  - Deleted C# owners: the Analyzer's string-matched member/export/declaration resolution
    (nested-type, tuple, primary-constructor-parameter, declared-member and export-visibility
    string lookups; `Analyzer.cs` fell from 23,471 to 23,068 lines), the emitter's unconditional
    construction ownership (constructions claimed by the N# planner never reach C#; the retained
    kinds 15/58/36 arms are fenced to the whole-subtree residual), and
    `ColumnarSynthesizedGenericScopeTests.cs` (replaced by the native `generic-scope-invalid`
    project). Aggregate C# net −157 lines.
  - Added N# owners: `ColumnarConstructionPlanner` (source/runtime/closed-generic constructor
    selection with defaults, sized/inferred arrays, source and union-case object initializers,
    runtime catalog), construction-row execution in `ColumnarCodePlanExecutor`,
    `ColumnarSemanticTypeRegistry` + `AnalyzerDeclarationContext` exact declaration scopes,
    `ColumnarPrimitiveBinaryPlanner` (admitted value-position binaries),
    `ColumnarSourceOperatorResolver`, and `TypeInfoIdentityFacts`, with native construction-arrays,
    generic-scope-invalid, and erased-enum-identity product contracts.
  - Evidence: 3,182/3,182 fresh-gate units (issue-tracker fixed); 553 BootstrapServices contracts;
    14 direct-call, 18 ownership, 7 construction-arrays, 3 generic-scope-invalid, and 1
    erased-enum-identity contracts; fresh non-VS-Code product gate down to four failure groups all
    verified pre-existing at HEAD and owned by 009/011/012/013/014; ratchet repin (audit 18/18);
    clean SDK repin.

- Task 006 — primitive binary expressions; commit `e57c80c8a` (stage commits `3dcb60bd2`,
  `e41570f69`, `83941f204`, `62ab5ffdf`, `096655625`, `5523402c5`, `aade33590`, `8397811ea`).
  - Deleted C# owners: the case-12 shifts branch, decimal op_* table, and right-literal adoption
    path from both emission and preflight, plus the preflight's arith/bitwise/ordering/numeric
    equality arms. `ColumnarIlEmitter.cs` fell from 21,618 to 21,499. The retained fenced numeric
    core serves exactly the whole-subtree residual: contextual-lambda call operands (010), member
    chains on call results, unary-negated call operands, dictionary-indexer reads, and string-typed
    operands such as enum string-constant reads (015 grows the nested-operand surface).
  - Added N# owners: the full primitive binary family (arithmetic with checked/unchecked overflow
    selection, bitwise, shifts, ordering with float unordered complements, numeric/Boolean
    equality, decimal op_* calls, string-pair concat, right-literal adoption) at expression roots
    and value position; operand families unlocked along the way — numeric casts, decimal literals
    (incl. negative), sibling-function calls, local-delegate invocations, String.Join catalog,
    List<T> indexer chains, byref-parameter deref reads over the typed-ldind family, ushort literal
    casts, and slot-reinterpretation casts via explicit conv.
  - Evidence: 608 BootstrapServices contracts (Debug and fresh Release self-emit); 15 primitive-
    binary, 41 range-index, 14 direct-call, 3 interface-parameter, 18 ownership contracts;
    3,182/3,182 units; fresh non-VS-Code gate at the same four pre-existing later-owner failure
    groups (009/011/012/013/014) as the 005 acceptance; toolset repins at each two-stage bootstrap.

- Task 007 — conditional and short-circuit expressions; commit `e9df4eb60` (routing commit
  `7eaccb1e9`, Brtrue two-stage bootstrap with mid-stage toolset repin).
  - Deleted C# owner: the `&&`/`||` sub-arm in `TryGetPreflightBinaryExpressionType` (proven dead —
    N# types every plannable short-circuit at the front door; a residual short-circuit is only ever
    emitted, never preflight-typed; zero hits across units, native contracts, examples, and the
    self-emit). `ColumnarIlEmitter.cs` fell from 21,499 to 21,497. The case-12 short-circuit and
    case-13 ternary EMIT arms are verify-first load-bearing (self-emit ternary null-comparison
    conditions; example `||` chains over string equality) and are recut as precisely-fenced
    whole-subtree residual servers retiring with task 015's nested-operand/equality surface growth.
  - Added N# owners: `ColumnarConditionalPlanner` — Boolean `&&`/`||` with the exact case-12
    short-circuit lowering and relocated ternary planning with widened operand recursion, claimed
    at expression roots and value position across emit and preflight facades; the `Brtrue` schema
    identity (contract id 58, condition-gated validation, allowlist name).
  - Evidence: 619 BootstrapServices contracts (Debug and fresh Release-packed-SDK re-emit); new
    conditional product project 8/8 with executed side-effect-order and right-operand-not-evaluated
    proofs; 3,182/3,182 units; all native projects green; fresh non-VS-Code gate at the same four
    pre-existing later-owner failure groups (009/011/012/013/014); clean toolset repin.

- Task 008 — complete range/index owner deletion; commit `23ced5034`.
  - Deleted C# owners: every range/index decision from `399008ea9` and its expansions — five
    static handles plus their resolver, thirteen lowering helpers, the case-11 index-from-end and
    case-69 range arms, the case-10 string/array Index/Range reads, and both preflight
    type-selection helpers with their dispatch arms. Only the Index/Range type-system entries
    remain (typed locals/parameters, not lowering policy). Residual inventory: empty — no fallback
    from N# to any old branch. `ColumnarIlEmitter.cs` fell from 21,497 to 21,209 (net −288).
  - Added N# owners: none needed — `ColumnarRangeIndexPlanner`/`ColumnarRangeIndexHandles` already
    owned the entire surface; the historical C# canonical test was migrated at `0206a1ed1`.
  - Evidence: 41/41 range-index product contracts identical before and after the deletion (the
    decisive dead-code proof); 619 BootstrapServices contracts against both feed and fresh SDK;
    3,182/3,182 units; all native projects green; fresh Release self-emit clean; fresh non-VS-Code
    gate at the same four pre-existing later-owner failure groups (009/011/012/013/014).

- Task 009 — external base and interface resolution; slice commits `85c817440` (base/interface
  classification), `5f9bf3fce` (inherited external-base-method calls), and the extension-calls
  commit; ACCEPTANCE: the generated Web API template checks, builds, and ILVerifies clean, and the
  fresh gate fell from four failure groups to three (013/014 iterators, 011/012 ilverify).
  - Deleted C# owners: the emitter's PASS 0a' base/interface classification decision block
    (`ColumnarIlEmitter.cs` 21,209 → 21,164); the remaining slices added zero C#.
  - Added N# owners: `ColumnarBaseTypePlanner` (ordered base classification incl. external runtime
    class bases with protected-ctor default chaining), inherited external-base-method bare/this
    call planning over the recorded base chain, `ColumnarExtensionMethodResolver` (ExtensionAttribute
    index with instance-beats-extension precedence and trailing-optional null-default fill),
    IServiceCollection admission, and highest-version NuGet runtime-asset unification.
  - Evidence: 625 BootstrapServices contracts; external-base-interface 18/18, extension-calls 4/4
    executed; 3,182/3,182 units; fresh Release self-emit clean; Web API ILVerify fully verified;
    all native projects green; gate baseline shrunk to three groups.

- Task 014 — async iterators; staged commits `d396a847c` (async classification facts: IsAsync,
  AwaitResumeCount, async return-shape admission/declines), `73ae226d5` (await-foreach parsing in
  the N# kernels: awaited kind-29 form + kind-73 consumer statement, toolset repin), `0a33f1ff2`
  (async state machines with REAL suspension: IAsyncEnumerable/IAsyncEnumerator/IAsyncDisposable
  member specs, schema-4 catch regions op 7, awaiter/promise/result/continuation field roles 5-8,
  MoveNextAsync fast-path vs TaskCompletionSource pending path, ldftn MoveNextCore continuation
  ctor, both exception routes, clone/dispose discipline — proven resuming off-caller-thread),
  `f3d1e89c9` (closing: classic C-style for kind 28, postfix ++/-- kind 44 incl. yield i++,
  ToUpper/ToLower/Trim instance calls, kind-73 await-foreach consumer lowering via the accepted
  blocking-await model; AsyncStreams.nl end-to-end).
  - NEW SURFACE like 013: no C# async-iterator emitter ever existed; deletion contract satisfied
    by planner-owned decline sites (emit.iterator.async-*) plus the deleted
    emit.iterator.async-emit-pending gate and zero net C# decision growth (emitter net −2 across
    the closing slice: 21,719/20,644 vs immutable epoch 21,723/20,646 — case-73 additions paid by
    lossless comment compression).
  - Added N# owners: ColumnarIteratorPlanner async classification + AnalyzeShape async facts +
    BuildAsyncMoveNextCore/MoveNextAsync/DisposeAsync/GetAsyncEnumerator/AsyncFactory plans, the
    kind-28/44/instance-string-call body surface, ColumnarCodePlan/Executor schema-4 catch
    regions, parser-kernel await-foreach forms.
  - Evidence: FULL VS Code-ENABLED GATE GREEN — ZERO failure groups (first fully-green gate of
    the closeout; AsyncStreams cleared; 14m11s; gate exit 0 with ALL TESTS PASSED). 731/731
    BootstrapServices contracts (717+14); 3,185/3,185 units; native iterators 25/25 (21+4 async);
    ownership audit 18/18; AsyncStreams.nl builds via the columnar pipeline, output order exact,
    real delays (1.273s wall for 10×100ms+4×50ms), ILVerify 2/2; nlc check/lint on the example
    0 findings; post-commit SDK repin to ~/.nuget/local-feed + gate dependency-cache reseed
    (nsharplang.* must be copied into the active Caches/NSharpLang/test-all/dependencies/<key>
    after a repin — the isolated gate only sees nuget.org plus that cache). VS Code extension
    rebuilt+reinstalled (reload-vscode-extension.sh exit 0); gate VS Code integration tests
    (extension, diagnostics, hover, completion) pass. OUTSTANDING: the computer-use visual IDE
    spot-check was attempted at this acceptance and screen-control access was DENIED at the
    approval dialog again (second denial after 013); the automated VS Code integration evidence
    stands in. Retry at the next IDE-affecting acceptance only if the user re-enables access.
  - Residuals recorded for 015+: await foreach inside an async iterator body (machine
    composition), async instance/generic iterators, awaited operands beyond statement-position
    Task.Delay(int), real async-func lowering to retire the blocking consumer await model.

- Task 013 — synchronous iterators; staged commits `489895987` (func*/yield parsing in the N#
  kernels, node kind 72, generator flag 4096, toolset repin), `71c5450b1` (schema-4 stage 1:
  Ret/Throw/Isinst/Stsfld/Leave allowlist + exception-region operations incl. FAULT, repin),
  `dd7d12107` (method-body executor + backward-branch stack-fixpoint validator, 13 contracts incl.
  the leave-runs-finally-not-fault proof), `03849de55` (ColumnarIteratorPlanner decision layer),
  `d0a4ee530` (MoveNext lowering proven running), `0c0961048` (native iterators project registered
  in ilverify.sh at its 476 ceiling + fall-through fix), `9698fbb76` (array for..in, throw, slot
  reuse), `bb359043f` (enumerator hoisting under the Roslyn try/FAULT region discipline; Dispose
  cascade), `d3602cfa4` (generic iterators via self-instantiation TypeSpec rebinding + MVAR-leak
  guard), `edfcbeb66` (instance iterators: <>__this capture, member reads, user-type sequence
  elements, member-call for..in sources incl. recursion), `f1c1b3b9f` (consumer surface:
  interpolation multi-arg call holes, plan-pinned generic String.Join<Int32>, open-generic
  extension inference — all N#, zero C# growth).
  - NEW SURFACE, not a migration: no C# iterator emitter ever existed (the C# recursive-descent
    func*/yield parser/analyzer stays as the LSP-fallback/oracle owned by 016/017; the analyzer
    already validated func* correctly). The "delete the C# owner" premise did not apply; the
    deletion contract is satisfied by the planner-owned decline sites replacing the blanket
    emit.statement.yield-unsupported arm and by zero net C# decision growth (emitter hosts
    mechanically at 21,619 of the immutable 21,723 ceiling).
  - Added N# owners: parser kernels (func* scan/signature/method-scan + yield statements),
    ColumnarCodePlan/Executor schema-4 method bodies, ColumnarIteratorPlanner (shape facts, state
    numbering, field layout, member/override specs, MoveNext/member/factory plans, decline
    classification), interpolation splitter multi-arg holes, plan-pinned generic external calls,
    open-generic extension-method inference.
  - Evidence: examples/09-linq-and-collections/Iterators.nl builds through the columnar pipeline,
    runs byte-exact across all nine sections, and ILVerifies (all six assemblies); native
    tests/native/iterators 21/21 executed proofs (sequences, infinite+break, re-enumeration
    clones, lazy throw, recursive tree traversal 1,2,4,5,3,6, generic value+reference elements,
    LINQ chain); 690/690 BootstrapServices contracts; 3,182/3,182 units; ownership audit 18/18;
    FULL VS Code-ENABLED GATE: exactly one failure group remains (AsyncStreams, owned by 014) —
    the Iterators group is CLEARED; VS Code smoke tests (extension, diagnostics, hover,
    completion) pass; extension rebuilt+reinstalled via reload-vscode-extension.sh. OUTSTANDING:
    the computer-use visual IDE spot-check was not performed this session (screen-control access
    denied at the approval dialog); the gate's automated VS Code integration evidence stands in.
    Perform the visual check at the next IDE-affecting acceptance (014).
  - Fenced 015 residuals recorded: lambda-taking LINQ arms (TryEmitEnumerableExtensionCall,
    TryEmitLambdaLiteral), the interpolation hole/emission core, the C# generic String.Join arm
    for non-int/string elements, extension interface-receiver inference, preflight typing of
    legacy-owned static calls.

- Task 012 — readonly-field initialization placement; commit recorded in git ("Own readonly-field
  initialization placement in N#").
  - Deleted C# owners: the initialized-fields decision, unconditional helper synthesis, whole-body
    helper emission, and the inline default-ctor body decision — the N# plan is the sole placement
    authority.
  - Added N# owners: `ColumnarFieldInitPlanner` — initonly stores inline in every base-reaching
    constructor, mutable stores in a helper synthesized only when needed, static ownership
    untouched.
  - Evidence: RecordsAndInterfaces builds, runs, ILVerifies clean; estate-wide ILVerify 0 findings
    (empty baseline); the gate's IL-verification step now PASSES — the gate is down to TWO groups
    (013 Iterators, 014 AsyncStreams). New readonly-init project 18/18; 625 contracts; 3,182/3,182
    units; fresh Release self-emit clean.

- Task 011 — record-with lowering for value receivers; commit `8a90bcd92`.
  - Deleted C# owners: the case-52 arm's clone-always callvirt selection, receiver gate, per-field
    binding, and result-type decision, plus the value-record `<Clone>$` synthesis branch (record
    structs now carry no Clone, matching C#). The arm is mechanical over the N# plan.
  - Added N# owners: `ColumnarRecordWithPlanner` — clone/copy strategy (reference clone versus
    verifiable value copy through an addressed temp), receiver shape, ordered member resolution,
    readonly decline, exact call form, result type.
  - Evidence: RecordStructs builds, runs correctly, ILVerifies clean (delta −2 findings);
    whole-estate ILVerify over 91 assemblies leaves only the task-012 InitOnly finding; new
    record-with product project 12/12 registered in the ilverify gate; 625 contracts; 3,182/3,182
    units; fresh Release self-emit clean; gate steady at three groups.

- Task 010 — lambda definition placement and visibility; slice commit recorded
  in git ("Own lambda definition placement in N#").
  - Deleted C# owners: the non-capturing lambda placement decisions — visibility attribute
    literals, name+counter construction, synthesized-signature guards, value-type/ctor guard,
    type-parameter ownership decision, static-versus-this classification branching, and the dual
    sub-emitter constructions (unified). `ColumnarIlEmitter.cs` 21,164 → 21,150. The value-capture
    display-class path is a precisely-fenced residual pending ModuleBuilder/DefineType modeling.
  - Added N# owners: `ColumnarLambdaPlacementPlanner` — owning-type selection, generated method
    identity, exact visibility (assembly-static for verifiable cross-type ldftn), signature
    validation, and the physical DefineMethod, consumed mechanically by the emitter.
  - Evidence: byte-identical IL across all three product reproducers (which run correctly and
    ILVerify clean; the historical cross-type MethodAccess shapes are confirmed fixed); new
    lambda-placement product project 9/9 registered in the ilverify gate; 625 BootstrapServices
    contracts; 3,182/3,182 units; fresh Release self-emit clean; gate steady at three groups
    (013/014 iterators, 011/012 ilverify).

After each accepted slice, record only:

- task and concrete sub-slice;
- commit hash;
- exact C# owner/assertion deletion;
- N# production/test delta;
- focused, product, IL, IDE, and repin evidence as applicable;
- next queue cursor.
