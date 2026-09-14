# S2.2(e) — iterator declaration binding parity proof

The product owner is integrated at `588195300` (worker `200216576`); the baseline-supported native
binding controls are integrated at `d9d4ccf60`. All eleven C# iterator declaration lookups are removed.
N# derives and consumes a structural member binding at each original attachment phase. Base bindings,
source discovery/call admission, remaining type consumers, ambient locals and maxstack remain later
S2.2 cuts. This does not complete S2.2 or any terminal task box.

## Immutable compilers and fixed corpus

Baseline and corpus are `05d184c8335c0d6bee9d77d5d5ec83a3d01c8774`; post compiler source is
`d9d4ccf60f75c2b13a73cbfcc555af5bbabd6b0f`. The proof and retained execution receipts are under
`/private/tmp/nsharp-023-s22e-proof-20260905/`. Each compiler is built from an independent committed
archive, with fourteen CLI files and seventy-seven support files hashed before and after consumption.

Each of the three arms visits 75 projects: 73 succeed, the same two NL402 systems-template declines
remain, and 94 images plus 2,173 native test passes are measured. Pre/pre and pre/post have zero
normalized-image, output-set or complete-outcome differences. Both driver processes exit zero;
`coverage.json` verifies the actual counts. The fixed corpus excludes the new controls, which are
replayed separately. Image paths remain distinct, only established volatile PE fields are normalized,
and failed projects retain complete outcomes rather than being represented as passing projects.

## Sensitivity and declaration identity

The unchanged Hello operand mutation detects the predicted image and stdout change. A separate
all-N# `Values<T>` fixture obtains the nongeneric IEnumerator route and invokes Reset. Its physical
MethodImpl row 3 maps Reset to MethodBody code 16. Changing that code to 18 maps it to the compatible
void Dispose body: exactly one byte changes at offset 1520, including after normalization. Runtime
output changes from `7 / reset refused` to `7 / reset accepted`; both runs exit zero with empty stderr.
Source, predictions written before mutation, images, literal IL, metadata rows and process streams
are retained in `methodimpl-control/`.

The fixture has seven physical rows. Its physical order is MoveNext, nongeneric Current, Reset,
generic Current, Dispose, generic GetEnumerator, nongeneric GetEnumerator. That differs from the
source attachment and disassembled method order. The new generic native fixture has the same order;
its four async rows are MoveNextAsync, Current, DisposeAsync and GetAsyncEnumerator. The comparison
checks physical rows exactly, while independent per-class literal IL expectations retain constructed
parents and open `!0` signatures. Separate constructor operands distinguish factory `!!T` from machine
`!T`; native reflection contracts also check their distinct declaring owners.

`final-controls-78082a67809e/` replays both complete native projects from committed control source
`78082a67809edba12eddc2dcecb828b534ed512a`: compiler facts pass **97/97** and iterators **25/25**
on each immutable compiler, with zero failures or skips. That revision adds only the native ordering
file after the post compiler snapshot; the harness verifies this exact source-only difference.
Complete outcomes, support copies, output sets and normalized images match. `FINAL_CONTROLS=PASS`
is an actual zero exit. Final source hashes and independent literal expectations are retained.

The original iterator project contributes 117 physical rows; the expanded compiler-facts project
contributes 42. Whole normalized images, all physical rows and literal override declarations are equal
pre/post. These include the established ordinary, source, closed-source and external-interface
controls as well as all eleven new iterator declarations. The metadata reader retains numeric
TypeSpec placeholders; literal IL assertions independently pin each new constructed parent and open
signature. The synchronous fixture covers source and primitive closures, both Current and
GetEnumerator routes, repeated enumeration and disposal. The async fixture covers all four routes,
including CancellationToken, and repeats after disposal. Unsupported generic-async and instance-async
inputs require successful parsing, exact emitter declines and accepted MZ-image twins.

The ordering control uses the existing private synchronous emitter's precomputedShape seam. A valid
parsed iterator and its own catalog/view form the positive twin, which succeeds with all seven
targets. Mutating the last direct lookup to a missing name retains six earlier targets and the
original InvalidOperationException. A missing property retains two targets and NullReferenceException;
a missing rebound method retains one target and NullReferenceException. A null last lookup retains
six targets and ArgumentNullException naming `name`. Every negative retains zero decline records
and rejects later noncontiguous target capture.

Renaming only state field zero permits constructor setup and row-one attachment, then fails the
original FieldForName lookup in BuildMoveNextPlan with the exact missing-state-field message and
one retained target. This proves entry into body planning between rows one and two, not a raw IL
byte count. The factory has the matching Public|Static attributes. Semantic and final-source review
is `/private/tmp/nsharp-s22e-review/ordering-control-semantic-review/README.md`; exact baseline
receipts are under `/private/tmp/nsharp-s22e-controls-logs/iterator-ordering/`.

Opaque harness-emission failures were narrowed to admitted N# reflection spellings: exact
GetConstructor(Type[]) instead of unmodeled GetConstructors(flags), local argument arrays before
Invoke, split nullable field/compound guards, and explicit Exception boxing/InnerException typing.
Independent original/replacement probes are retained in the worker ordering-diagnosis directory.
No C# probe, product hook, assertion weakening or product change was used to admit the controls.

## Reflection boundary and review

The initial probe's unused GetParameters/ReturnType expressions did not establish a refusal. The
final consumed probe shows GetParameters succeeds, ReturnType exposes the open external generic
parameter rather than the machine VAR, and ReturnParameter throws NotSupportedException. ReflectedType
and DeclaringType retain the exact context. Frozen source/DLL/IL review is
`/private/tmp/nsharp-s22e-review/stage0-boundary/README.md`. The binding therefore derives effective
facts from the known open member and exact host-created context, retaining the actual rebound target
without reading a supposed effective signature from it.

Five direct method paths, one direct getter, four rebound method paths and one rebound getter preserve
their original lookup phases. Context factories snapshot handles without eager validation. Null names
reach reflection, and missing rebound methods reach the existing rebinder before the direct null
rejection. Each row validates, retains ResolvedBinding/ResolvedTarget, attaches, and then replays its
body; async core replay still precedes the first async attachment. Changing LookupName to a different
existing incompatible method is explicitly a new malformed-row structural rejection boundary, not a
claim of universal failure parity.

Definitive review is `/private/tmp/nsharp-s22e-review/immutable-post/README.md`. It links all committed
handoff sources and ninety-one compiler/support files to the exact post artifact. Its IL dump is
byte-identical to the reviewed candidate: 22 actual InitOnly context/binding fields, copied read-only
parameter and signature collections, one rebinder call, open-member-only signature reads and
validation before retention/attachment. The existing external reflected constructor and shared
signature-node IL remain equal to the accepted predecessor, apart from RVA comments.

Six new direct contracts cover all eleven bindings, external VAR versus synthesized machine VAR and
factory MVAR, lookup and attachment failures, foreign-table rejection and structural corruption.
Review strengthened the corruption test to change only the independent runtime companion while
asserting that the owner-qualified structural relation remains valid. Thus rejection actually proves
pair validation. Formatting changes only one blank line in the direct tests; the exact formatted
estate passes 7,742/7,742, with dev Columnar 12/12. Worker receipts are in
`/private/tmp/nsharp-s22e-executor-logs/handoff-receipt.json`.

## Strict source, ownership and checkpoint

Both immutable compilers return byte-identical strict JSON on the same final product source:
432 files, 259 existing errors and zero warnings/info, exit 1 with empty stderr. All 259 baseline
findings map to unchanged source lines, with zero changed diagnostic rows or waivers; baseline checked
430 files. The exact retained strict executions are reused only after compiler and committed source
hash validation when native-only controls are added; they are not substituted for the fresh product gate.

The emitter is 19,485 lines / 18,506 nonblank / 1,014,696 bytes, a reduction of 7 / 7 / 1,183.
SHA256 is `e719f880830907953a7852debbb7448eb841ccc8d8999c0b95fe002c6620ff08`;
text fingerprint is `text-v1:849b13451d652bc1`, and observed manifest/policy head is
`head-v1:69340a92fd35d5ea`. Only the measured emitter ratchet row and its reviewed head change;
ceilings, epoch facts and the path set remain unchanged. Ownership audit passes 18/18. Fresh census
finds zero old iterator alias lookups, eleven N# row forwards and two context forwards. AddType remains
36 calls in 12 files: one keyed and thirty-five handle-only, including the bare CodePlan mirror call.

The fresh committed-source backend checkpoint is `/private/tmp/gate-20260905-goal-s22e-r1/`.
`source.json` identifies its exact archive; `gate.log` and `exit-code.txt` establish the actual result.
`acceptance.json` is written only after verification and exact-SHA push. This document does not stand
in for that verdict. Command: `VSCODE_TESTS=skip ./scripts/test-all.sh --commit`. The preceding d
checkpoint passed and was pushed at `05d184c8`. All terminal 015/021/022/023 boxes remain open.
