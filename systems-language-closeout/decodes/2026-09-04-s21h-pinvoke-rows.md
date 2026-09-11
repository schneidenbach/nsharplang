# S2.1(h): P/Invoke declaration ownership

Baseline: `54faf94a77413bf22f5e9f3b667bcb4a7fb1659f`. Implementation branch:
`codex/023-s21h-pinvoke`, worktree `/private/tmp/nsharp-agent-wt/023-s21h`.
The earlier writer worktrees and commits are preserved.

## Re-derived boundary

The baseline has one `DefinePInvokeMethod` call at `ColumnarIlEmitter.cs:4435`, inside the
static-method branch. Return resolution, parameter resolution, and overload-list lookup happen
before the native-import check. A successful import defines parameter metadata, registers the
overload, and continues without adding a managed-body job. Shared parameter/default metadata can
still fail after method creation. Those ordering boundaries remain in place.

The C# native-import branch owned these decisions:

- The input is a bodyless native import, within the existing static-method branch.
- Modifier bit 131072 is present; library and entry-point names are not null or empty; the method
  has no type parameters and is not async. Whitespace names are accepted. There is no additional
  restriction on generic declaring types.
- The method's existing base attributes are ORed with `PinvokeImpl` 8192. Ordinary static imports
  have word 8342; operator names retain `SpecialName` and have word 10390.
- Managed calling convention `Standard` is 1, unmanaged `Cdecl` is 2, and `Ansi` charset is 2.
- Current implementation flags are preserved and ORed with `PreserveSig` 128.
- An invalid selected import produces site `emit.declaration.native-import`, message
  `native import metadata was invalid for '<struct>.<method>'`, and the unqualified struct name
  as the decline owner.

Library and entry-point parsing was already N# owned. `ParseColumnarNativeImportInfoInto` requires
the exact LibraryImport token and a nonempty library, and defaults the entry point to the method
name. No library fallback, extension synthesis, analyzer admission change, or broader attribute
spelling is introduced here.

## Planned records and production route

`ColumnarDeclarationPlan.PInvokes` now owns `ColumnarPInvokeRows.Methods`, an outer array by source
struct ordinal and an inner array by source method ordinal. Unselected methods retain null slots;
ordinary methods do not allocate declaration objects. Selection requires both `IsStatic` and
`IsBodylessNativeImport`, so an instance method cannot accidentally enter the native branch.

Each selected `ColumnarPInvokeDeclaration` captures:

```text
IsValid
DeclineCode, DeclineMessage, DeclineOwnerName
MethodName, LibraryName, EntryPointName
MethodAttributes
ManagedCallingConvention, UnmanagedCallingConvention, CharacterSet
ImplementationFlagsMask
```

Valid rows carry empty decline code/message strings. Invalidity is recorded without throwing or
returning early from planning. The host consumes it only after its existing return/parameter
resolution phase, preserving which failure wins. `MergeImplementationFlags(currentFlags)` performs
the OR in N#; C# only casts the recorded words at the existing APIs.

`BuildAssemblyAndEnums` computes the method rows once and supplies that same result both to the
plan and `BuildPInvokes`. The new planner consumes the supplied base words rather than recomputing
method policy. Its contract injects an unrelated base bit to make accidental recomputation visible.

Names and decline text are captured data. The source declaration lists retain stable ordinals
through emission; these rows do not claim to snapshot shared signature/default metadata or method
bodies. Captured-name contracts mutate fixture input fields after planning and verify that the
recorded names and messages retain their original values.

C# directly consumes the selected record at the old branch. Its validation predicates, private
native modifier constant, flag ORs, name selection, and convention/charset constants are removed.
No C# branch, helper, replay loop, adapter, or test is added. `DefineMethodParameterMetadata`, its
timing, overload registration, and the `continue` omitting the managed-body job remain unchanged.

## Measured helper relocation

The first implementation called the existing global
`ColumnarStructMethodFlagIsNativeImport` function. Stage-0 compilation and execution passed, but
both CLIs' strict checks on that source added NL412: the namespaced declaration planner could not
semantically resolve the global free function. That was an actual self-hosting regression, not a
reason to waive the strict check or duplicate the flag value.

The two existing helper bodies now live on the existing `ColumnarFunctionInput` owner as
`NativeImportModifierFlag()` and `HasNativeImportModifier(flags)`. The old global functions are
deleted. Both parser callers, the declaration planner, and the existing literal flag contracts
call the named owner. The global parser file imports its namespace explicitly. There is exactly
one production literal for this native flag, and no new enum member or helper class.

One further caller was found and updated mechanically:
`ColumnarProgramInputBuilder.cs:471` now calls
`ColumnarFunctionInput.HasNativeImportModifier(methodModifierFlags)` instead of the old global
function. This expression is shorter; it adds no policy. The relocation is in N#, with no analyzer,
language, SDK, or reflection-bound kernel change.

| C# host | Baseline total / nonblank / UTF-8 bytes | Final total / nonblank / UTF-8 bytes |
|---|---|---|
| `ColumnarIlEmitter.cs` | 20,722 / 19,710 / 1,076,565 | **20,714 / 19,703 / 1,076,258** |
| `ColumnarProgramInputBuilder.cs` | 1,044 / 975 / 50,982 | **1,044 / 975 / 50,973** |

## Canonical controls

Eight new estate blocks in `ColumnarDeclarationPlan.tests.nl` cover sparse/mixed ordinals and
ordinary/nonstatic exclusion; every validity predicate; null, empty and whitespace names;
generic declaring owners; literal metadata words and supplied method-row reuse; implementation-bit
preservation; stable captured names/declines; and parsed explicit/default entry points without an
invented missing-entry fallback. The existing parser flag block retains its literal 131072 golden.

Seven new blocks live in the existing `tests/native/columnar-emit-facts` project; no project or
compile-time corpus pin was added:

- `PInvokeDeclarationEmitFacts.tests.nl` verifies an emitted optional integer parameter's name,
  ordinal, default, method flags, PreserveSig and missing managed body. It invokes libc `abs` with
  an explicit argument on Unix; metadata assertions run on every platform. A separate metadata-only
  import pins `out` and bool/string/null defaults without loading its synthetic library.
- `PInvokeDeclarationOrder.tests.nl` parses one valid native input, mutates only its metadata, and
  invokes the existing emitter entry point through test-only reflection. Ordinary malformed source
  probes stopped at `parse.struct`, so they were rejected as evidence for late emit ordering.
  The canonical controls assert: bad return wins over parameter/native/default; bad parameter wins
  over native/default; invalid native metadata wins over an unsupported default; default kind 9999
  returns false with zero decline rows; and the unchanged default emits a nonempty MZ image. Each
  located decline must be the sole record, with exact site, message, and owner.

Two fixture-only spellings were narrowed after measured declines: a chained field write became
a named owner local, and an unsupported `as byte[]` cast became an admitted `IList` view retaining
the nonempty/MZ assertions. No product capability was added to make a fixture pass.

## Focused evidence

| Check | Final observed result | Raw evidence |
|---|---|---|
| Initial `./scripts/dev.sh --build-only` | Stage-0 build passed, 24 s | `/private/tmp/nsharp-s21h-dev-build.log` |
| Final `./scripts/dev.sh ColumnarDeclineDiagnostics` | CLI rebuilt; **5 passed, 0 failed**, 28 s | `/private/tmp/nsharp-s21h-dev-focused.log` |
| Focused estate, `FullyQualifiedName~PInvoke\|FullyQualifiedName~TheMethodFlagWordNames` | **9 passed, 0 failed** | `/private/tmp/nsharp-s21h-focused-estate.log` |
| Complete estate | **7,666 passed, 0 failed, 0 skipped**, baseline 7,658, exactly eight added blocks | `/private/tmp/nsharp-s21h-estate.log` |
| Final CLI, entire native emit-facts suite with `--no-cache --json` | **66 passed, 0 failed, 0 skipped**, seven new blocks | `/private/tmp/nsharp-s21h-native-all.json` |
| Independent baseline CLI, isolated canonical controls | **7 passed, 0 failed** | `/private/tmp/nsharp-s21h-review/canonical-controls-baseline.log` and source hashes beside it |
| Root `nlc format --check` | Exit 0, all files properly formatted | `/private/tmp/nsharp-s21h-root-format.log` |
| `git diff --check` | Exit 0 | Reproducible on this diff |

Estate restoration explicitly uses `-p:NSharpExcludeTests=false --force-evaluate`; test commands use
`-p:NSharpExcludeTests=false --no-restore -v:q --nologo`. The complete estate runs from that compiled
test assembly with `--no-build`; it emits a nonzero Total summary. Native commands run from this
worktree, using its `src/NSharpLang.Cli/bin/Debug/net10.0/Cli.dll`, against the existing project.

## Strict-source evidence

All checks use `check --project src/NSharpLang.Compiler.BootstrapServices --json`. The baseline CLI
is `/private/tmp/nsharp-023-s21h-proof-20260904/cli/pre/Cli.dll`, and baseline source is the committed
archive at that proof directory's `trees/d`. All three walks report **425 files / 259 findings**:

```text
/private/tmp/nsharp-s21h-check-pre-baseline.json
/private/tmp/nsharp-s21h-check-pre-current.json
/private/tmp/nsharp-s21h-check-post-current.json
```

Baseline/current and post/current result arrays are exactly equal. Baseline source retains every
finding on current source. Exactly four `ColumnarInputs.nl` locations move by nine lines:
NL202 115→124 and 215→224, NL402 415→424 and 420→429. The two NL202 explanation strings update their
embedded line numbers accordingly. With those explicit location mappings, all 259 result objects
are equal, including messages, spans, snippets, hints and ordering. There are no added or removed
findings. Coordinator verification is recorded in
`/private/tmp/nsharp-023-s21h-proof-20260904/strict-source-shifts.json`.

The intermediate NL412 walk is preserved as
`/private/tmp/nsharp-s21h-check-pre-current-before-helper-move.json` and its post-CLI counterpart.
All final checks exit 1 for the retained pre-existing findings; a zero process exit is not claimed.

## Integration handoff

This commit is focused-green implementation evidence. The coordinator owns the committed final-arm
corpus comparison, both changed C# fingerprint rows and two-key ownership repin, and the fresh backend
product gate. No SDK was published, no full gate was run here, and no upstream push was performed.

The coordinator's fresh pre/pre control at this baseline passed before acceptance: 94 images with
zero normalized PE, output-set, or outcome differences; 73 of 75 projects pass, with the same two
known NL402 template declines; 2,138 native tests per arm. A one-byte Hi 42→43 mutation changes exactly
one normalized image and stdout. Raw proof: `/private/tmp/nsharp-023-s21h-proof-20260904`.

The final post arm must retain whole-PE equality, including method/ImplMap/parameter tables and
implementation flags. Existing execution witnesses are proof 26-native-device-handle (`c`, explicit
open/close, successful `/dev/null` execution) and proof 27-c-library-cli (default Hash64 entry point,
array/out parameters, expected missing fast_hash loader outcome). Their current metadata and
outcomes are coordinator evidence. S2.1(i), shared parameter metadata ownership, S2.2 resolution,
the second writer, and emitter retirement remain subsequent work.
