# Systems-language closeout — live execution ledger

**Audited implementation base:** `97454855a` (2026-07-10). This file is the resume point. Current
code and git history outrank it; update it whenever they disagree.

**Emitter handoff debt:** `0206a1ed1` routes the persisted `399008ea9` range/index read surface
through the N# planner and direct executor and deletes its 130-line C# assertion. The old C#
branches still accept broader recursive receivers/endpoints/selectors that the N# planner does not
yet own, so they remain deletion debt rather than an approved fallback. No further C# growth is
permitted. Array `Index`/`^` writes, compound/postfix mutation, and ref/out address lowering remain
plan-first debt, while range writes/ref and string writes remain intentional errors.

Status meanings:

- `complete` — the production route and required evidence exist at the recorded commit.
- `partial` — useful code landed, but the production route, parity proof, deletion, or exit gate
  is incomplete. Partial never satisfies a dependency that requires completion.
- `ready` — prerequisites are complete and one owner may start after revalidation.
- `blocked` — a named stop gate failed; another independent ready stage should proceed.

## Verified campaign state

- A detached-HEAD `dotnet test tests/Tests.csproj` run at `fb856ee46` completed with zero
  failures on 2026-07-09. The former 67-failure baseline and all stash/`comm` instructions are
  retired.
- The fresh non-VS-Code product gate at `347e5aa71` ran all 3,182 unit tests, 121 compiler-service
  native contracts, and all 71 discovered product native N# tests green, then ended `FAILURES: 4`.
  The ownership audit was 18/18, scalar plans were 2/2, and range/index was 15/15 in the isolated
  copy. The concrete product blockers are unchanged and inventoried below: Web API base binding,
  async generators, iterators, and the seven normalized IL findings. Unit/native green is not a
  substitute for the Track A product gate.
- Range/index value and read semantics are complete at `399008ea9`: all four range forms,
  array/string/reference-array slicing, typed and conditional `Index`/`Range`, byte/short/enum
  endpoints, parenthesized starts, and the existing Span integer-index path have persisted
  execution evidence. `RangeAndIndex.nl` and `OpenEndedRanges.nl` build/run and their four emitted
  assemblies passed ILVerify.
- `NSharpLang.Compiler.Dogfood`, `DogfoodKernelLoader`, reflection delegate binding, and the
  parity corpus are gone. Static binding is complete.
- Per-file columnar source identity, construction, decline provenance, and multi-file routing are
  in the production route.
- Plain test declarations and assert/assert-throws are modeled. The full test grammar is not:
  setup/teardown, table-driven `with`, skip, and full framework parity remain live gaps.
- Syntax-diagnostic kernels exist but are preparatory: `ColumnarSyntaxDiagnostics.ParseFile`
  has no production consumer or direct differential parity suite. Do not count the diagnostic
  families as ported until that proof and routing exist.
- The first native compiler-closeout probe reached project-reference compilation on 2026-07-09,
  but rebuilding `NSharpLang.Compiler.BootstrapServices/project.yml` through `nlc test` activates
  the legacy validation path and rejects sources that the pinned Stage-0 SDK compiles with
  `NSharpEmitValidateWithLegacyAnalysis=false`. A DLL-reference probe then reached emission but
  correctly declined construction of an unmodeled external compiler-service type. C/D/H must
  remove the validation discrepancy; E0 successor tests exercise plans through their production
  route instead of retaining either probe as a fallback.
- E0's direct Reflection.Emit prerequisite is production-routed through
  `ColumnarExternalBindingPlans.nl` at `da2304315`: N# selects exact assembly-qualified types,
  static members, opcode fields, call forms, and signatures; the existing emitter only
  materializes that payload and is 132 lines smaller.
- E0's first production plan vertical is committed at `1bb109831`: schema v1 records the actual
  signed `OpCode.Value`, N# constructs, validates, and executes the plan, the production route
  calls it before legacy dispatch, and the old boolean emit/type branches are deleted. Seven N#
  schema/planner contracts, five persisted boolean tests, and the 102-test Columnar slice pass.
  The native gate now rejects empty or internally inconsistent results before caching and ran
  58/58 tests; a clean first BootstrapServices build excludes `.tests.nl` declarations. E0 is
  not complete: range/index ownership from `399008ea9` and the cross-language audit remain.
- Callback-free schema v2 is N#-owned at `c3a17419b`. It carries exact signed opcodes, typed
  argument/local/handle pools, labels, fragment kind/source/parent/interval/result columns,
  deepest operation ownership, one-shot consumption, and branch-safe transactional rollback.
  Pure structural validation is linear, rejects discarded-checkpoint ABA and every v1-smuggling
  path, and is now the production v1 executor's validation authority. BootstrapServices ran
  30/30 native contracts and the Columnar slice ran 102/102.
- The exact executor/planner metadata surface is N#-owned at `d8ece513a`: `LocalBuilder`/`Type`
  facts plus exact method/constructor/field/parameter signature getters are admitted without a
  C# bridge. Reflection bootstrap contract v3 executes the handle metadata getters and compiles
  the local getter surface (1/1). A clean worktree repin installed `d8ece513a`; the `~/.nsharp`
  package and stage-0 local-feed package hashes match. Direct schema-v2 execution is next;
  production range routing/deletion has not happened yet.
- Generic array metadata is exact and N#-owned at `6bfcc11ac`: `Type.IsGenericParameter`
  distinguishes typed generic element loads, `MethodInfo.IsGenericMethodDefinition` rejects only
  raw definitions, and the runtime contract proves both `GetSubArray<int>` and valid
  open-in-context `GetSubArray<TEnclosing>` are constructed handles. A clean repin installed that
  commit; the installed and local-feed SDK package hashes are
  `9fb36768b54f5b1b91df06781597f655dbcb77de1459be60a7142bad9efced7b`.
- Reflected enum backing metadata is exact and N#-owned at `99785ed8f`; schema validation can
  distinguish I4-backed enum values from incompatible I8-backed values rather than assuming every
  public-plan `Type` came from an N# declaration. The latest clean repin installed that commit;
  the installed and local-feed SDK package hashes are
  `7d9eaa74096b93f91306cb64e36d962ac5598f2ed03628dc5297ae727c32bf94`.
- Callable safety metadata is exact and N#-owned at `acf6712fb`/`0ae1cf22b`: abstract methods and
  declaring types, raw generic type definitions, and varargs calling conventions are visible to
  the executor without reflection-name guesses or a C# bridge. The runtime contract distinguishes
  constructed-open from raw generic definitions and abstract/concrete metadata. The latest clean
  repin installed `0ae1cf22b`; installed and local-feed SDK package hashes are
  `6b63b8d59b016f9ab6c6a7111d190975371fcfce9223d7cebd712c46627c59ad`.
- Direct schema-v2 execution is N#-owned at `1345ec9fc`. The executor validates structure,
  reflected signatures, hidden pool state, forward-only control flow, exact evaluation-stack
  categories, fragment boundaries, and plan-local definite assignment before the first
  `ILGenerator` call, then consumes the plan and emits through an explicit opcode map. Persistent
  stack nodes keep an 8,193-row straight-line validation contract linear. BootstrapServices ran
  80/80 shared contracts (28 executor contracts) and the Columnar slice ran 102/102. A clean
  worktree repin installed `1345ec9fc`; the installed and local-feed SDK package hashes are
  `6c54169c71160562da9c9ff921e984db865ac9e2df2c62af4a215ba5835956f9`. The production
  range/index route is the first non-null executor oracle and remains the next E0 boundary.
- Recursive range/index plan construction is N#-owned at `cc53a347e` for the persisted
  `399008ea9` corpus: all range forms, direct and from-end `Index`, exact narrow-integer and enum
  conversions, conditional selectors, string reads, and concrete/reference/generic SZ-array
  reads and slices. Exact CLR handle selection, raw binding/shadow facts, and transactional
  rollback are native contracts; BootstrapServices remains 80/80. A clean repin installed
  `cc53a347e`; installed and local-feed SDK hashes are
  `33c447f76777e95581943f5846b6ae9f5312c974db7a631e16ad7636ebd21eaf`. Production deletion
  is not yet safe: the old `399008ea9` path recursively accepted general expression receivers,
  endpoints, and selectors (including binary expressions, calls, members, array literals,
  current-instance/lifted facts, and richer conditions) that this bounded planner still declines.
  Port those accepted child families through N# plans before
  routing and deleting the entire C# owner; a legacy fallback or callback is forbidden.
- Constructed generic signature substitution is N#-owned at `f618b3bf3`/`0206a1ed1`.
  `MethodBuilderInstantiation` exposes definition-owned parameter/return wrappers for an unbaked
  caller `T`; the executor now substitutes the definition recursively with the constructed
  method's exact arguments, structurally compares only array/generic wrapper shells, and rejects
  unsupported compound substitutions. A foreign generic parameter at position 1 prevents
  accidental substitution by the caller argument's position.
- The persisted range/index surface is production-routed through N# at `0206a1ed1`. A temporary
  N# throw proved the former C# assertion traversed `TryEmitFromFacts`; the probe was removed, the
  assertion reran green, and its 130 C# lines were deleted. BootstrapServices and the 102-test
  Columnar slice pass; the native successor is 14/14 and includes generic `T[]` slicing plus
  reference-array copy independence. `RangeAndIndex.nl` and `OpenEndedRanges.nl` build/run, and
  their four assemblies pass ILVerify. A clean worktree repin installed `0206a1ed1`; the
  `~/.nsharp`, local-feed, and global-cache SDK hashes all equal
  `bc726dddbc9edfa59637e8d72fe9436ff2d52b6ab37eaf4be0d53f5ecb0b2b91`. This does not close
  E0: general child-expression parity and complete C# branch deletion remain required.
- Recursive ordinary integer indexing beneath an N#-owned range/index root is production-owned at
  `6d8bc72db`: array children use the exact `ldelem*` family, string children call `get_Chars`, and
  direct ordinary-index roots remain outside this planner. Native contracts pin successful nested
  planning, direct-root exclusion after a nested child succeeds, and atomic rollback; persisted
  execution covers `values[^counts[0]]`, `matrix[0][^1]`, and the string-character child path. The
  range suite is 15/15 and BootstrapServices is green. A clean worktree repin installed
  `6d8bc72db`; the `~/.nsharp`, local-feed, and global-cache SDK hashes all equal
  `38acbfd98b6b6954fb288d36b8ee4c4908cff7a25f4a7b922ab710116fab446e`.
- Schema-v3 scalar-constant execution is N#-owned at `9957c0657`, after the exact opcode and
  DynamicMethod binding prerequisites `cd711be2e`/`7dbee4304`. The callback-free plan carries
  Int64, Single, Double, and String pools with closed opcode/operand pairings, exact-use validation,
  transactional rollback, version isolation, one-shot consumption, and an I8 stack category that
  refines only to `long` or `ulong`. Native compiler-service contracts pass 102/102, including real
  DynamicMethod execution of long, high-bit ulong, float, double, and string constants; the
  Reflection.Emit bootstrap contract passes 1/1. Two adversarial reviews approved the final
  malformed-payload, stack-merge, and validation-before-emission behavior. A clean committed
  worktree repin installed `9957c0657`; the installed, local-feed, and global-cache SDK package
  hashes all equal `cba9c47bed7e2d8ceb99746c97a6142693dd6b9f2ebf427e0beabb36668a2155`.
- The columnar numeric source-span ABI is repaired in N# at `f2440777f`. Numeric token metadata
  now preserves the complete raw decimal/hex/binary/float spelling (including separators and
  suffixes), all primary literal ordinals have named N# identities, and the enum value consumer
  normalizes separators with exact signed-bound checks. The scanner intentionally gained no
  octal branch. Ten focused contracts and the full 112-test BootstrapServices estate pass, as
  does `./scripts/dev.sh BootstrapServices`. A clean committed-worktree repin installed that
  commit; the installed, local-feed, and global-cache SDK hashes all equal
  `971cf58f1bf16b70720558c8e506d6c037d35f7d5a8aee2c85c7ddd934ed8182`. Existing C#
  contextual/default/static-initializer integer consumers remain separator-hostile deletion debt;
  they must be retired through N# ownership rather than patched in C#.
- Direct scalar literal production ownership is N#-only at `548c211fe`. One schema-v3 planner
  constructs and executes exact decimal/hex/binary Int32, signed-Int64 `L`, UInt64 `UL`/`LU`,
  character, ordinary-string, and triple-string plans; recursive range/index planning consumes
  the same integer owner. Emit and preflight route through the N# plan before legacy dispatch,
  the direct integer/character/plain-string C# decisions and `TryGetIntLiteralType` are deleted,
  and `ColumnarIlEmitter.cs` is 64 lines smaller (21,723 to 21,659). BootstrapServices is 121/121,
  the Columnar slice is 102/102, persisted scalar and range projects are 2/2 and 15/15, the six
  scalar-output assemblies pass ILVerify, ownership is 18/18, and two adversarial semantic audits
  approved the route. The reviewed audit head is `5c540427ac3e58b4`. A clean repin installed
  `548c211fe`; installed, local-feed, and global-cache SDK hashes all equal
  `424abfe553b11be25a537446b17c6d0c50e36e77bc2c21e7b619f036d1c0536d`, and the cached
  BootstrapServices DLL hash is `d55a85b3c02eb734aec5452aaef2dee8af28cf02769ae9e29199b8730e148cfc`.
  Decimal, interpolation, contextual adoption, defaults, and static initializers remain separately
  inventoried deletion debt rather than scalar-plan fallbacks.
- Exact external static parse-call selection is N#-owned at `2e6e7f0b0`. The plan maps actual
  `CultureInfo` facts to exact `IFormatProvider` method signatures and owns CoreLib Int32/Double
  Parse/TryParse identities, including Int32&/Double& parameter types and bounded aliases. The
  existing planned-call materializer now consumes static plans after user-type/enum/union shadow
  barriers, validates plan kind and method staticness, and mechanically flattens only exact
  `ref`/`out` targets. The two feature-specific Int32 C# branches are deleted and the emitter is
  another three lines smaller (21,656). BootstrapServices is 123/123, Columnar is 102/102,
  reflection bootstrap and task-cli are 2/2 and 12/12, ownership is 18/18, and the adversarial
  audit approved the route. The reviewed audit head is `d1ce8b9415f1d087`. A clean repin installed
  `2e6e7f0b0`; installed, local-feed, and global-cache SDK hashes all equal
  `c0c573cd540eadee80aa122478944ef905316ada180567221abc0a0c31193d01`, and the cached
  BootstrapServices DLL hash is `43f34ff586a1682ea1353e64a58c924e3edebe62c8d6bda64f3a5a0248a39abd`.
- Floating-point literal ownership is N#-only at `e3ef2ef2b`. Parser-produced unsuffixed and
  `d`/`D` doubles plus `f`/`F` singles now use the schema-v3 scalar planner with invariant
  double parsing and exact double-then-float narrowing; `m`/`M` remains the isolated decimal
  debt. The old direct emission and preflight decisions are deleted, shrinking the emitter by
  17 lines. Native contracts pin suffixes, separators, exponent forms, overflow to infinity,
  underflow, negative zero, double-rounding, opcode/pool identity, type preflight, and atomic
  rollback. BootstrapServices is 130/130, Columnar is 102/102, scalar-code-plan is 2/2, and the
  ownership audit is 18/18.
- Syntactic `nameof` and constant range children are N#-only at `97454855a`. A schema-v3 N#
  planner owns exact identifier/member final-name selection, root emission and preflight, and
  recursive range consumption; the range planner also consumes the shared character and string
  scalar owner. The old C# `nameof` emission, preflight, text helper, and a dead range predicate
  are deleted, shrinking the emitter by another 27 lines. BootstrapServices is 130/130,
  Columnar is 102/102, range-index is 16/16, `PrintNameofTypeof` builds/runs and passes ILVerify,
  and an adversarial audit approved the boundary. A clean repin installed `97454855a`; the
  installed, local-feed, and global-cache SDK hashes all equal
  `772948e517e6094cd66a86c0cf70516fba28a86a1439ddae33fe18e3acc2c3b6`, and the cached
  BootstrapServices DLL hash is `861d23adef17dd74bd5e391385b1baac968d8a633c17cf6f88e141653a360f91`.
- The N#-only ownership-growth ratchet is committed at `5e5d8c8ba`. Its strict schema-v1 manifest
  covers 381 tracked paths: 364 closeout paths and 17 explicitly separate runtime/native-reference
  paths. N# derives every language/surface/scope classification, rejects new paths and metric or
  assertion growth, preserves removal tombstones, fingerprints binaries as raw bytes, and pins
  both immutable epoch facts and the reviewed current/state head. The path, epoch-fact, and head
  fingerprints are `8a26e1529863444b`, `1b3090747e517fc1`, and `ffbef88c68ba441a` respectively.
  Native tests pass 18/18 locally and in a `.git`-free archive; the executable audit and the fresh
  product gate's isolated discovery both pass. This is an E0 growth guard, not the final H8
  survivor allowlist or a claim that existing debt is acceptable.
- The H2 gate currently discovers direct `.tests.nl` projects under `examples/` and `tests/`.
  Template suites are not silently counted: `templates/nsharp-systems-cli` currently declines
  `BinaryPrimitives.ReadUInt32LittleEndian(ReadOnlySpan<byte>)` at
  `emit.call.static-member-unmodeled`. That N# external static-call owner must land before
  templates join the same structurally validated gate.
- A B3a DocQuery candidate is preserved, uncommitted, in `/tmp/nsharplang-b3a` on
  `codex/b3a-docquery` (base `d002be14b`): N# native tests are 9/9 and the DocQuery focused slice
  is 8/8. Its fresh VS Code-enabled checkpoint passed 3,183 unit tests and 36 smoke tests, then
  hit the same four product-gate buckets below. It still requires integration, a green required
  gate, extension reload, and visual IDE verification before commit.

## Ownership trend that changed the priority

| Owner | `9538ab66` | `fb856ee46` | Verdict |
|---|---:|---:|---|
| `ColumnarIlEmitter.cs` | 13,712 LOC | 21,828 LOC | frozen legacy owner; E now deletes it |
| `Analyzer.cs` | 22,783 LOC | 23,451 LOC | no retirement yet |
| `Parser.cs` | 7,117 LOC | 7,117 LOC | no retirement yet |
| `SystemsAnalyzer.cs` | 2,390 LOC | 2,390 LOC | not started |
| `Linter.cs` / `Formatter.cs` | 1,611 / 2,303 LOC | unchanged | not started |
| `OutputFormatter.cs` | 669 LOC | 379 LOC | real but incomplete reduction |
| `DocQuery.cs` | 918 LOC | 740 LOC | partial |
| `Program.Testing.cs` | 740 LOC | 653 LOC | partial |

LOC is a smoke alarm, not the completion test. The completion test is sole N# production
ownership plus deletion or an approved mechanical-host inventory. The emitter growth makes the
first post-audit priority non-negotiable: establish N# lowering plans before any more language
coverage work.

## Active dependency queue

Execute dependency-ready lanes in parallel only when their file domains do not contend. With one
owner, finish one commit-sized stage before switching.

1. **E0 — finish range/index branch deletion under the N# ownership ratchet.** Direct schema-v2
   execution, the persisted production handoff, canonical assertion migration, and cross-language
   growth guard are done at `1345ec9fc`/`0206a1ed1`/`5e5d8c8ba`. Port every still-accepted general
   receiver/endpoint/selector family through callback-free N# plans, then delete the corresponding
   C# range/index branches rather than retaining the current transition fallback. The live
   endpoint inventory proves that call/member/binding/control prerequisites cross E2–E4; the old
   E0 note excluding those recursive dependencies is stale and must not justify a partial route.
2. **C2a — prove the existing syntax-diagnostic candidate.** Before adding another diagnostic
   family, add native N# ordered full-tuple successor tests over invalid, clean, and recovery
   corpora, then delete the superseded C# assertions. Resolve the current duplicate-lex/collector
   architecture against the single-parser contract; do not grow two diagnostic parsers.
3. **D1 — move the AST model to N#.** Revalidate live shapes, preserve names/defaults/mutable
   members, delete the C# AST records atomically, and run the IDE-required evidence because the
   shared analyzer/tooling path consumes those types. This unlocks typed linter and code-
   intelligence kernels.
4. **B3a — close DocQuery in parallel when an owner is available.** Static binding is complete
   and this file domain does not contend with E0/C2a/D1. Run the live go/no-go API probes, move
   remaining lookup/index/format policy into the existing N# owner, and shrink C# to a raw
   metadata/XML-loading host or delete it. Nullability is a separate B3b lane coordinated with D.
5. **Close Track A through N# ownership.** Fix the recorded product-gate blockers—including the
   remaining native-test grammar—through N# parser/semantic/lowering owners. Record the first
   fresh green product-gate commit, then mark A complete.
6. **Continue ownership lanes by the DAG.** Prefer a vertical stage that deletes the largest
   reachable old owner: C syntax flip; D analyzer families; E lowering families; B residual
   DocQuery/nullability/CLI ownership; F systems policy; G tooling/LSP; H tests/release. Never
   return to open-ended C# corpus widening.

## Fresh product-gate blocker inventory (`347e5aa71`)

Reproducer for the complete checkpoint: `VSCODE_TESTS=skip ./scripts/test-all.sh --commit`.
The isolated run ended `FAILURES: 4` after 3,182/3,182 unit tests, 121/121 compiler-service native
contracts, and 71/71 discovered product native tests passed. Ownership was 18/18, scalar plans
were 2/2, and range/index was 15/15; `RangeAndIndex.nl` and `OpenEndedRanges.nl` both passed.
Focused decline reproducers use
the fresh
`src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll` plus
`NSHARP_COLUMNAR_DECLINE_LOG=1`; IL rows were confirmed directly with `ilverify` and the same
framework-reference set as `scripts/ilverify.sh`.

| Product blocker | Deepest evidence | Owning N# layer and dependency |
|---|---|---|
| Generated `nsharp-webapi` project | `emit.declaration.base-type`: base/interface type `ControllerBase` could not be resolved for `WeatherController`. Reproduce: generate `nsharp-webapi`, then run `nlc build` in it with decline logging. | Track E external type/base binder. E2 owns the decision after E0's plan boundary and E1's handle-capability matrix. |
| `examples/08-async/AsyncStreams.nl` | `parse.declaration-scan` at 1:1: function scan rejected the first `async func*`. | Columnar parser/function-declaration facts in Track A/C must model `async func*`; generator state-machine lowering then belongs to E plans. No handwritten C# coverage; E0 is the lowering prerequisite. |
| `examples/09-linq-and-collections/Iterators.nl` | `parse.declaration-scan` at 3:1: function scan rejected the first `func*`. | Columnar parser/function-declaration facts in Track A/C must model `func*`; iterator state-machine lowering then belongs to E plans. No handwritten C# coverage; E0 is the lowering prerequisite. |
| `IssueTracker.dll` IL | `IL:MethodAccess` in `IssueTracker.Routes::Map`: `ldftn Program::<Lambda>_0` targets a private method on another type. | Track E N# lambda-definition placement and visibility plan; depends on E0, then the E3 definition registry/E4 lowering family. |
| `RecordStructs.dll` IL | At `Program::Main` offset `0x55b`, `callvirt Color::<Clone>$` consumes a `Color` value instead of its address (`IL:CallVirtOnValueType` and `IL:StackUnexpected`). | Track E N# record-`with`/value-receiver lowering plan after E0; the old C# branch must be deleted with the fix. |
| `RecordsAndInterfaces.dll` IL | `IL:InitOnly` in `Circle::<InitializeFields>$`: helper method executes `stfld` for readonly `Pi` outside `.ctor`. | Track E N# declaration/constructor initialization plan; depends on E0 and the E3 definition model before its E4 lowering deletion. |
| `TaskCli.dll` IL | `IL:MethodAccess` in `Formatter::FormatTags`: `ldftn Program::<Lambda>_0` targets a private method on another type. | Same E lambda-definition placement/visibility owner and E0 → E3/E4 dependency as `IssueTracker.dll`. |
| `WeatherDemo.dll` IL | `IL:MethodAccess` in `GetMinMaxTemp` and `GetHotDaysSummary`: three `ldftn` sites target private `Program::<Lambda>_0..2` methods from `WeatherService` (two normalized gate findings). | Same E lambda-definition placement/visibility owner and E0 → E3/E4 dependency; both affected methods are independently pinned. |

Do not baseline these IL findings: they are product-emission defects. The four gate failure counts
are Web API template build, `AsyncStreams`, `Iterators`, and the IL verification step; the IL step
contains the five assembly rows and seven normalized verifier codes above (with Weather's repeated
member finding deduplicated by the gate).

## Track status

| Track / stage | Status | Evidence | Remaining binding work |
|---|---|---|---|
| A1 decline diagnostics | complete | `18df2415e`…`465856bef` | Preserve stable reason ids and spans. |
| A2 product-path restoration | partial | 3,182 unit + 121 compiler-service native + 71 product native green/four-category product-gate inventory at `347e5aa71`; range/index A0 at `399008ea9`; plain tests in `d34e7e6e7`; asserts in `9996d4525` | Fix the inventoried template, iterator/async-iterator, and IL blockers; full test grammar; dynamic corpus sweep; fresh green product gate. All remaining coverage is N# plan-first. |
| B1 static kernel binding / Dogfood deletion | complete | `27bb97773`, `aa9ec5326`, `3c963eb5d` | Never recreate reflection binding or the deleted project. |
| B2 JSON and CLI decisions | partial | unverified partial; live inventory required | Re-inventory live C# command policy; `OutputFormatter.cs` is not yet a tiny host. |
| B3a DocQuery | partial candidate, not landed | `/tmp/nsharplang-b3a`: native 9/9, focused 8/8, unit 3,183/3,183, VS smoke 36/36; required gate still red in the four global buckets | Integrate after resolving the required checkpoint, then reload/reinstall and visually verify the IDE before commit. Keep only proved raw metadata/XML extraction/loading glue. |
| B3b nullability | partial, blocked on D caller seam | partial N# owner exists; live inventory required | Remove `typeOverride` callbacks with D's canonical type/call bridge; keep only proved raw NullabilityInfo extraction glue. |
| C1 per-file pipeline/provenance | complete | `dd494cd29`…`6382af774` | Preserve file identity; no merged-source route. |
| C2 syntax diagnostics | partial | foundation `760cf0203` plus family ports | Direct differential harness first; integrate with the real columnar parse; then finish families. |
| C3 syntax ownership flip | ready after C2 | — | Flip compiler, FormatSafe error gate, lint/fmt, imported-file, and LSP consumers; delete C# reporting. |
| D0 MetadataLoadContext probe | complete | `fef45dd22` | Apply the recorded verdict to the final metadata host inventory. |
| D1 AST model | ready | — | Atomic N# move and C# record deletion. |
| D2–D10 semantic ownership | ready after D1 by dependencies | — | Port vertical families, canonical ids, shared package policy, and retarget non-LSP consumers. |
| D/G facade cleanup | blocked on D API + G re-host | — | G retargets the final IDE consumer and deletes the then-zero-consumer facade; H only verifies. |
| E0 N# lowering-plan ratchet + range/index debt | in progress and highest priority | `1bb109831` schema-v1 plan/boolean deletion; `c3a17419b` recursive schema v2; `1345ec9fc` direct schema-v2 executor; `cc53a347e` recursive planner; `f618b3bf3` generic signature facts; `0206a1ed1` persisted production route and C# assertion deletion; `6d8bc72db` nested ordinary array/string child ownership; `5e5d8c8ba` 381-path N# growth ratchet; `9957c0657` schema-v3 scalar constants; `f2440777f` raw numeric spans; `548c211fe` integer/character/string production ownership; `2e6e7f0b0` exact static parse calls; `e3ef2ef2b` floating production ownership; `97454855a` `nameof` plus constant range children; emitter now 21,612 lines; BootstrapServices 130/130; Columnar 102/102; scalar/range successors 2/2 and 16/16; ownership 18/18 at reviewed head `ffbef88c68ba441a`; clean repin hash `772948…c3b6` | Close callback-free binding/member/call/control child families, then delete the complete remaining C# range/index owner introduced by `399008ea9`. Preserve the reviewed audit head with each shrink/removal. |
| E1–E6 emitter ownership | pending after E0 as applicable | — | N# binder/resolver/passes/plans; typeref policy in N#; Cecil deletion; mechanical PE host only. |
| F1 systems input columns | ready after current parser writer releases the file | — | Attribute/modifier/alloc facts only; no F-specific semantic identity. |
| F2–F4 systems policy | blocked on C/D canonical identity contract | — | Stable caller node and resolved declaration/function ids, N# walker, mechanical fact flatten, C# owner deletion. |
| G tooling / IDE | partial only for isolated prior work | `0d42981b0` deleted the XML-doc stub | Linter, formatter, code-intel, completion, handlers, and front-end re-host remain. |
| H1 native runner host shrink | blocked on N# execution-plan ownership | A deletion probe proved the current reflection route runs the emitted synchronous Fact+Trait estate, but it cannot preserve the xUnit controller's whole-run timeout for a blocking void test; the probe was fully reverted with no commit | N# must own discovery rows, lifecycle/result policy, sync/Task/ValueTask invocation, and one whole-run deadline—including blocking void methods—before the xUnit controller and package can be deleted. Theory/InlineData, skip, async, failure JSON, and timeout successors must all be native N# tests. |
| H2 initial native gate | partial | `347e5aa71`: 121 compiler-service native contracts + 71 discovered product tests, including ownership 18/18 and scalar plans 2/2; nonempty/reconciled cache guard; clean product test exclusion | Remove the legacy-validation discrepancy so BootstrapServices runs through fresh `nlc test`; add templates and the complete estate before deleting predecessor suites. |
| H3 CLI assertion migrations | blocked on A grammar + green product gate | — | Move CLI product assertions to N# process-boundary suites after the complete native route is trustworthy. |
| H4–H8 release/endgame | blocked on named track exits | — | Playground, C# test closeout, deletion integration, docs, and final audit. |

## Corrections that override the track notebooks

These are binding. Patch the relevant track file when launching the affected stage.

1. **Node kinds are live, not reserved by old prose.** Kind 57 is already
   `CheckedContextExpression`; the in-flight range slice claims kind 69. Re-read the one live
   ledger, allocate the next globally free kind, and update every producer, consumer, and ledger
   entry in the same commit. Never follow a fixed number from the July 2 notes.
2. **Parser topology changed.** Former Dogfood parser files are now the single statically-bound
   `CompilerServices/ColumnarParserKernels.nl`. C, F, and G all contend on that file. Old paths
   and import-component assumptions are invalid.
3. **One parse, one diagnostic authority.** The current syntax candidate calls `Lexer` and runs
   independent collectors, while the original design required diagnostics to share the columnar
   scanner/parser state. Before growing it, either integrate it with that state or record a new
   design with equivalent single-owner, clean-path allocation, recovery-parity, and performance
   proof. Two parser-like decision engines are not an acceptable end state.
4. **FormatSafe belongs to the syntax flip.** C must move its parse-error refusal gate to the N#
   syntax authority before deleting `ParseResult.Errors`. A silent AST reparse may remain only
   for the temporary AST/idempotence comparison and must disappear with the formatter re-host.
5. **Analyzer facade ownership is split at one explicit seam.** D exposes the stable N# API and
   retargets `MultiFileCompiler` plus every non-IDE product consumer. A temporary zero-policy
   facade may then serve only the exact G-owned IDE consumer recorded in this ledger. G retargets
   that final consumer and deletes the facade in the same commit. H verifies absence; it neither
   retargets the consumer nor deletes the facade.
6. **Use canonical semantic identity.** C/D must introduce source-qualified SymbolId/TypeId
   values; name plus line/column is insufficient. F call facts must contain caller node id and
   resolved declaration/function id, including overload/local/generic-instantiation identity.
   C# may flatten already-resolved facts; it may not reimplement resolution policy.
7. **One package-version policy owner.** CLI and Analyzer metadata loading must consume the same
   N# resolver/version-selection facts. The SemVer policy recently added to `Analyzer.cs` is
   deletion debt, not a second canonical implementation.
8. **IDE gates follow reachability, not track labels.** Any commit changing code reached by
   `DocumentManager`, the shared Analyzer, linter/formatter/code-intelligence, an LSP handler, or
   the extension is IDE-affecting even when parity is expected. It requires the VS Code-enabled
   gate, extension reload, computer-use verification, and screenshots after that commit.
9. **E ordering is a DAG.** Interface-pass work depends on the N# definition model; do not run
   the old E3.4 before E4.1. Do not take the old Route B that grows temporary C# Reflection.Emit
   whitelists. Member/binder and typeref-owner selection policy belongs in N#; C# only invokes
   reflected APIs or patches/replays already-selected metadata operations.
10. **H has no allowed deferred product suite.** TypeScript may own editor/UI adapter assertions,
    but canonical language/LSP semantics also require N# tests. A `query ast` schema change is a
    separate versioned contract with goldens and an approval boundary, not incidental cleanup in
    the front-end delete.
11. **A wave is not a commit.** Broad sub-arcs may contain many commits. Every actual commit unit
    must name its input contract, N# production owner, exact deleted/shrunk C# owner, focused
    evidence, and checkpoint. Avoid both one-helper churn and multi-thousand-line catch-all
    commits.
12. **Build.Tasks is in scope for decisions.** `LoadProjectConfig.cs` and
    `LoadProjectReferences.cs` may keep MSBuild `ITaskItem` materialization, but output/default,
    dependency-classification, ordering, and projection policy must move to N# plan objects. The
    final audit covers `.cs`, `.targets`, `.props`, TypeScript, shell, and WASM glue—not only C#.
13. **No new C# survives the amended closeout.** Every notebook direction requesting a new C#
    test, differential harness, replayer, seed, whitelist, callback, adapter, or feature branch is
    stale. Implement the prerequisite and successor in N#, run it through the product/native gate,
    then delete or reduce the old C# owner. Existing C# boundary files may not grow.

## Contention ledger (live)

- `CompilerServices/ColumnarParserKernels.nl`: C diagnostics, F inputs, and G formatter trivia.
  The A0 writer has released it; one writer at a time, with partitioning only when merges are
  guaranteed.
- `ColumnarIlEmitter.cs`: E owns it exclusively after `399008ea9`. Track A may no longer add
  feature branches.
- `MultiFileCompiler.cs`: C flip, F systems host, D consumer retarget, H playground/deletion.
- `Analyzer.cs`: D owns retirement; B may supply N# metadata/version APIs but does not edit the
  analyzer concurrently.
- `tests/Tests.csproj` and shared fixtures: append-only, never reorder; new C# product assertions
  must be entered in H's migration inventory.
- SDK repins and package/build-script changes: announce before changing shared installed state;
  gate from a clean `/tmp` worktree when the main checkout is active.

## Updating this ledger

After a stage commits, update its row with the commit and evidence, record the next dependency,
and remove obsolete blocker prose. Do not accumulate a narrative history: compact completed
stages to one evidence line. Delete this temporary ledger during the final documentation
closeout after the survivor inventory becomes the durable architecture record.

The durable inventory lives at `memory/architecture.md#non-nsharp-survivors`. The campaign must
also land a committed ownership-audit script and reviewed allowlist that cover product-adjacent
`.cs`, `.targets`, `.props`, TypeScript, shell, and WASM files; H8 runs that guard as final proof.
