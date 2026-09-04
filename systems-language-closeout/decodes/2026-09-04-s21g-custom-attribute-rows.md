# S2.1(g): custom-attribute declaration rows

Baseline: `5ac4faa798ffe60f89781e4ccaffd78e1949fc21`. Implementation branch:
`codex/023-s21g-attributes`, worktree `/private/tmp/nsharp-agent-wt/023-s21g`.
The earlier `stream/023-s2-writer` worktree and history are preserved.

## Re-derived policy and row shape

The baseline emitter had exactly four `SetCustomAttribute` calls. Their blob writer was already
N# (`ColumnarAttributeBlobs`); custom-attribute selection, attachment location, and test order were
still imperative C# policy. Moving only the shared trait key would not complete this slice.

| Baseline site | Selected owner and attachment | Missing constructor behavior |
|---|---|---|
| `ColumnarIlEmitter.cs:4089` | Ref struct TypeBuilder, `IsByRefLike()` | Return false |
| `ColumnarIlEmitter.cs:4927` | Value-union TypeBuilder, `IsReadOnly()` | Skip the attribute |
| `ColumnarIlEmitter.cs:5772` | Test MethodBuilder, `Trait("NSharpDescription", description)` first | Located `emit.tests.framework` decline |
| `ColumnarIlEmitter.cs:5773` | Same test MethodBuilder, `Fact()` second | Same decline, before defining any test method |

`ColumnarDeclarationPlan.CustomAttributes` now carries `ColumnarCustomAttributeRows`:

```text
StructByRefLikeBlobs : byte[][][]  // source struct ordinal, attachment ordinal, bytes
UnionReadOnlyBlobs   : byte[][][]  // source union ordinal, attachment ordinal, bytes
TestConstructorSlots: int[]       // 0 = Trait(string,string), 1 = Fact(); ordered [0,1]
TestBlobs            : byte[][][] // source test ordinal, attachment ordinal, bytes
```

Each marker owner has a sequence of length zero or one. Empty sequences preserve owner ordinals;
the columns are not compacted. Null and empty input test lists both publish no test rows or slots.
Each test has exactly two blobs, paired with the constructor-slot sequence. Constructor identities
are fixed by the named marker family and by the two documented test slots; resolved runtime
constructors are not embedded in the declaration data.

An empty sequence is shared within the plan. The four-byte no-argument blob is allocated only when
some marker or test requires it, then shared by all marker and Fact rows in that plan. Present marker
sequences are shared too. Different plans do not share mutable blobs. The emitted arrays are treated
as read-only after planning. Source lists retain stable ordinals through emission: these are captured
attribute rows, not a snapshot of every method body or declaration. The executor continues reading
the original test body/name by ordinal. Contracts show that the captured attribute rows themselves
remain unchanged if the fixture's source flags or test-list entry later change.

## Production ownership

`ColumnarDeclarationPlanner.BuildCustomAttributes` selects marker presence, captures descriptions,
chooses blob shapes, and records Trait-before-Fact ordering. Existing `ColumnarAttributeBlobs`
owns direct N# `ApplyToType` and `ApplyToTestMethod` calls. The latter alone interprets constructor
slots and iterates attachments. It uses a slot-selection function instead of allocating a
`ConstructorInfo[2]` per test; slots other than zero and one throw explicitly.

C# has zero remaining `SetCustomAttribute` calls. It passes already resolved builders/constructors
to three direct N# application calls. No C# helper, replay loop, constructor array, selector, or test
was added. The existing test declaration walk now indexes the planned test rows and their source
inputs. The source `IsRefStruct` attachment choice, four inline blob choices, two explicit test
attachments, and source test-list null/count admission are retired from C#.

The `un.IsValueStruct` branch still selects the union's broader representation; that layout policy
is outside this custom-attribute slice. Its attribute attachment consumes the independently planned
readonly sequence. Constructor binding remains S2.2: ref-struct resolution occurs only for a
present marker; readonly resolution remains inside the value-union layout branch; test resolution
still resolves Fact type then Trait type, Trait constructor then Fact constructor, before any
NSharpTests method is defined. All three distinct missing-constructor outcomes remain unchanged.

The C# file shrinks from 20,724/19,712 total/nonblank lines to **20,722/19,710**. Two comment lines were
also shortened while updating their stale attachment description; comment cleanup is not counted
as retired product policy.

The metadata key has one production owner, `ColumnarAttributeBlobs.DescriptionTraitKey()`. Planning
and both `TestCommandKernels` readers call it. The expected literal `NSharpDescription` and the
complete golden Trait blob are independently pinned: an emitter/reader rename cannot cancel out.
The existing `NoArgument` and `TwoStrings` encoders are unchanged.

## Focused evidence

All commands ran in the new worktree with the existing pinned SDK. No shared feed was published.

| Check | Observed result | Raw log |
|---|---|---|
| `./scripts/dev.sh --build-only` | CLI build passed in 22 s; TypeBuilder/MethodBuilder byte-array `SetCustomAttribute` and triple-jagged rows spell through stage 0 | `/private/tmp/nsharp-s21g-dev-build.log` |
| Focused canonical estate filter below | **10 passed, 0 failed, 0 skipped** | `/private/tmp/nsharp-s21g-focused-estate.log` |
| Complete N# estate | **7,658 passed, 0 failed, 0 skipped**, baseline 7,650, exactly eight added blocks | `/private/tmp/nsharp-s21g-estate.log` |
| `./scripts/dev.sh ColumnarDeclineDiagnostics` | **5 passed, 0 failed, 0 skipped**, 27 s including CLI build | `/private/tmp/nsharp-s21g-dev-focused.log` |
| Root `nlc format --check` | Exit 0, `All files are properly formatted.` | `/private/tmp/nsharp-s21g-root-format.log` |
| `git diff --check` | Exit 0 | Reproducible on this diff |

The focused filter was:

```text
FullyQualifiedName~CustomAttribute|FullyQualifiedName~CustomTestAttribute|FullyQualifiedName~AValueUnionAlone|FullyQualifiedName~TheTestDescriptionTraitReaders|FullyQualifiedName~TheXunitTraitShape
```

Its ten discovered names are recorded in `/private/tmp/nsharp-s21g-focused-list.log`: eight new
blocks, the existing xunit blob golden, and the existing flow-attribute metadata contract. Coverage
includes empty owner families, absent markers, interleaved owner ordinals, a value union alone,
Trait-before-Fact slots, literal key and complete blobs, Unicode and 128-byte descriptions, shared
within-plan/no-shared-cross-plan data, source-input capture, constructor identity, and invalid slots.

The estate was restored with
`dotnet restore src/NSharpLang.Compiler.BootstrapServices/NSharpLang.Compiler.BootstrapServices.csproj -p:NSharpExcludeTests=false --force-evaluate -v:q`
before running `dotnet test` with `-p:NSharpExcludeTests=false --no-restore -v:q --nologo`; the focused
run adds the filter above. Both runs emitted nonzero `Total` summaries. An initial test-fixture
constructor lookup declined emission; using known `object`/`InvalidOperationException` constructors
through local Type values admitted the identity contract. There was no product API spelling gap.

## Strict-source comparison

All three commands used `nlc check --project src/NSharpLang.Compiler.BootstrapServices --json`.
The baseline CLI is `/private/tmp/nsharp-023-s21g-proof-20260904/cli/pre/Cli.dll`; its baseline source
is the fixed committed archive under that proof directory's `trees/a`. The post CLI is the Debug CLI
in the implementation worktree.

| CLI / source | Files / diagnostic rows | Raw JSON |
|---|---|---|
| Baseline / baseline | 425 / 260 | `/private/tmp/nsharp-s21g-check-pre-baseline.json` |
| Baseline / current | 425 / 259 | `/private/tmp/nsharp-s21g-check-pre-current.json` |
| Post / current | 425 / 259 | `/private/tmp/nsharp-s21g-check-post-current.json` |

Baseline/current and post/current result arrays are exactly equal. After removing the single
baseline NL010 for the unused `System.Collections.Generic` import at `ColumnarDeclarationPlan.nl:4`,
all 259 remaining baseline diagnostic objects equal the post objects, including source lines,
spans, snippets, messages, and suggestions. No mapping or broad diagnostic allowance was needed.
All three commands exit 1 for those pre-existing findings. The first current-source walk found a new
NL905 because `testCount > 0` did not establish the nullable list's non-nullness; an explicit
`tests != null` guard removed it before these final comparisons.

## Integration boundary

The coordinator owns the control-first corpus proof, final merged ownership repin, and fresh backend
product gate. The pristine control at this baseline passed before implementation builds: 75 projects,
73 successful, two identical known NL402 template declines, 94 emitted assemblies, 2,138 native tests,
zero normalized PE/outcome/output-set differences. Its non-vacuity mutation changed exactly one
normalized assembly and stdout. Raw proof: `/private/tmp/nsharp-023-s21g-proof-20260904`.

This implementation commit does not claim final pre/post corpus acceptance. The post compiler must
be built from the committed integration tree and compared against those controls. The full-PE
normalizer retains custom-attribute table order and blob bytes. Named execution witnesses include
FrameReader/FrameResult in proof `24-zero-copy-frame-reader`, value unions such as Status/IssueStatus
in the task CLI/issue-tracker examples, and the corpus test methods' Trait/Fact rows. The coordinator
records final owner coverage and parity results. No S2.1(h), S2.2, SDK republish, default-writer flip,
or Reflection.Emit retirement is claimed here.
