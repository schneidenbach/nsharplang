# S2.1(i): N# method-override rows and execution

Implementation baseline: `69ad857ba5766ff546f285bf6571731f5dfc192f`. This slice moves all
fourteen production `DefineMethodOverride` attachment sites out of `ColumnarIlEmitter.cs`: seven
synchronous iterator members, four asynchronous iterator members and the three ordinary-method
target families. N# now owns the consumed records and the two executors. C# retains the existing
handle-resolution loops and calls the record at each original attachment phase.

## Measured stage-0 spelling

Before any product edit, a package-SDK probe compiled under `NSharpLang.Sdk/0.1.0`, ran and printed
`0`. Its emitted `SpellOverride` IL contains `new HashSet<MethodInfo>()`, two
`HashSet<MethodInfo>.Add` calls whose argument is a `MethodBuilder`, and
`TypeBuilder.DefineMethodOverride(MethodInfo, MethodInfo)` with a `MethodBuilder` body. This is a
compiler/IL spelling proof. `main` does not invoke `SpellOverride`; runtime duplicate equality and
attachment execution are covered by the implementation's passing N# contracts.

The source, minimal project, package hashes, observed binary, stdout/exit receipt and complete IL
are retained at `/private/tmp/nsharp-stage0-s21i-measurement` and
`/private/tmp/nsharp-s21i-executor-logs/stage0-probe.il`. The observed probe DLL SHA256 is
`2732834a138cc3b1e22cf155dc35c8b82c691a37af5a0ab558f01082672ac134`; the SDK package SHA256 is
`d4e626967646418fd26b60390a65480861c8d5d384e4fa3dcc449fcc97bca57e`.

## Ordinary declarations

`ColumnarDeclarationPlan` now carries sparse, source-ordinal `MethodOverrides` rows beside the
existing method rows. Static slots remain null. Each instance row captures the base attribute word,
override request, owner/member names and source signature before emission. The input modifier query
lives on the existing `ColumnarFunctionInput` owner and derives its value from `Modifiers.Override`;
this slice adds no duplicate override-bit literal, and the old C# constant is deleted.

The host offers successful handles to `AddSourceTarget` or `AddExternalTarget` in its unchanged
resolution order. Direct and closed source-interface handles share one `HashSet<MethodInfo>`;
external handles use a separate set. First occurrence wins within a domain and the same handle is
retained across domains. Default `MethodInfo` equality remains authoritative, including distinct
same-name/signature handles and runtime versus `MetadataLoadContext` handles.

`Complete` performs the requested base lookup at the old late phase, produces the exact existing
decline, calculates the final attribute word and materializes application order as base, source,
external. The four literal outcomes remain 134, 486, 198 and 230. `DefineMethodParameterMetadata`
still runs after method creation and before attachment. The N# completion then applies its ordered
handles before method registration and body-job creation. The row stores the already-known source
identity beside each handle and never asks an unfinished `MethodBuilder` or `TypeBuilder` for
signature metadata.

This representation adds eager per-instance-method storage: two lists, two sets and a cloned
parameter-canonical array, plus the resolved completion array. That is real row-storage cost. The
benchmark threshold is unchanged; no allocation-parity claim is made.

## Iterator declarations

The old `MemberOverrides` strings, which production never read, are replaced by explicit
`ColumnarIteratorOverrideDeclaration` records indexed by member ordinal. Constructor slots and async
`MoveNextCore` remain null. Each record carries the canonical declaration identity and the lookup
name; `Apply` retains the resolved `MethodInfo` beside that identity and performs the attachment.

All eleven sites consume those records at their existing define, resolve, attach, emit-body point.
Reflection sequence is unchanged: synchronous generic `Current` still uses
`IEnumerator<>.GetMethod("get_Current")`; nongeneric and async `Current` still use property lookup
followed by `GetGetMethod`. Closed-generic resolution remains explicit S2.2 debt. The synchronous
call order is MoveNext, generic Current, nongeneric Current, Reset, Dispose, generic GetEnumerator,
nongeneric GetEnumerator; the async order is MoveNextAsync, Current, DisposeAsync,
GetAsyncEnumerator.

## Canonical controls

Nine new `ColumnarDeclarationPlan` blocks and one new iterator block bring the N# estate from 7,666
to **7,676**. They cover sparse/static exclusion, captured identity, the named override bit, all four
attribute outcomes, both equality domains and cross-domain retention, distinct same-signature
interface handles, runtime/MLC twins, base/source/external ordering, the exact late-base decline,
and real application against unbaked `MethodBuilder` handles. Existing iterator contracts now assert
all seven/four record identities, lookup names and null constructor/core slots.

Ten controls were added to the existing `tests/native/columnar-emit-facts` project. They execute
inherited diamond interface dispatch, a closed generic source interface, one method attached to
both `Exception.ToString` and a source interface, two distinct interface bodies, nongeneric iterator
dispatch, and return then parameter then base-target then default-validation precedence. A valid
null default still produces a nonempty MZ image; invalid default kind 9999 still returns false with
no located decline.

Three fixture boundaries were measured and corrected without product expansion. Chained indexed
writes became named locals, static `TypeOfCreateSourceBuilder` calls spell their trailing boolean,
and off-surface `typeof(void)`/non-generic-interface operands use `ExecutorVoidType` or the existing
runtime-Type helper. The initial suspicion that a custom-class return initializer was unsupported
was false: direct typed `row.Complete(...)` calls pass with admitted operands, and the temporary
reflection wrapper was removed.

## Focused evidence

| Check | Result | Raw evidence |
|---|---|---|
| N# bootstrap-services estate | **7,676 passed, 0 failed** | `/private/tmp/nsharp-s21i-executor-logs/bootstrap-estate-9.log` |
| `./scripts/dev.sh Columnar` | CLI build passed; **12 passed, 0 failed** | `/private/tmp/nsharp-s21i-executor-logs/dev-columnar.log` |
| Native columnar emit facts | **76 passed, 0 failed**, including ten new controls | `/private/tmp/nsharp-s21i-executor-logs/native-columnar-emit-facts-1.log` |
| Native iterators | **25 passed, 0 failed** | `/private/tmp/nsharp-s21i-executor-logs/native-iterators.log` |
| `git diff --check` | exit 0 | Reproducible from this diff |

The fixture-only declined iterations remain in `bootstrap-estate-1.log` through `-8.log` beside the
passing log; they document the exact rejected spellings rather than a product capability change.

## Strict source and host reduction

All strict walks use `check --project src/NSharpLang.Compiler.BootstrapServices --json`. The baseline
CLI is `/private/tmp/nsharp-023-s21i-proof-20260904/cli/pre/Cli.dll`; baseline source is its archived
`source` tree. Baseline/pre-current/post-current each report **425 checked files / 259 findings**,
and both compilers' result arrays on current source are identical. Baseline to current differs only
by four expected `ColumnarInputs.nl` line movements from the eleven-line named helper addition:
NL202 124→135 and 224→235, including their embedded explanation lines, and NL402 424→435 and
429→440. There are no added or removed diagnostics. Raw JSON and the asserting comparison are in
`/private/tmp/nsharp-s21i-executor-logs/strict-*.json` and `strict-source-shifts.json`.

`ColumnarIlEmitter.cs` decreases from **20,714 / 19,703 / 1,076,258** total lines, nonblank lines and
UTF-8 bytes to **20,688 / 19,677 / 1,074,830**. It contains zero `DefineMethodOverride` references
and zero `MemberOverrides` references. No C# helper, branch, replayer or fallback was added.

The coordinator owns committed whole-PE parity, physical MethodImpl row/order comparison, ownership
ratchet repin, the fresh backend product gate and upstream push. This focused implementation does not
publish an SDK. Signature/closed-handle resolution remains explicit S2.2 work, and S2.1(i) alone does
not complete task 023.
