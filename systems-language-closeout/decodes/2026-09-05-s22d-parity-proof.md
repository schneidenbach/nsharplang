# S2.2(d) — external-interface member parity proof

The N# product owner is integrated at `405483ca4`; external generic-owner controls at `4343633df`
and `e330dfacc`, and native controls at `7009a190d`. The C# external matcher and both enumeration /
completeness loops are deleted. This proof covers that family and its consumed structural bindings.
Base/iterator descriptors, source discovery/call admission, remaining type consumers, ambient locals
and maxstack remain later S2.2 cuts. All terminal task boxes remain open.

## Fixed compilers and corpus

Baseline and fixed corpus are `2e256ef6f2634b14a984091f5fb2c2036afff953`; post compiler source is
`7009a190d4d66a3e07a2369248a9789f597ac882`. The external harness and complete receipts are under
`/private/tmp/nsharp-023-s22d-proof-20260905/`.

Each of the three arms visits 75 projects: 73 succeed, the same two NL402 systems-template declines
remain, and 94 project images plus 2,169 native test passes are measured. Pre/pre and pre/post have
zero normalized-image, output-set and complete-outcome differences. The drivers exit zero with
`CONTROL_VERDICT=PASS` and `PARITY_VERDICT=PASS`; `coverage.json` verifies actual counts. The fixed
corpus excludes newly added tests, which are replayed separately below.

Both compilers come from independent committed-source archives. Fourteen CLI files and 77 support
files per compiler are hashed in their manifests. Only established volatile PE fields are
normalized; image paths remain distinct. Failed builds retain their complete outcome. No new
failure is waived, and the two templates are not represented as passing projects.

## Controls and physical overrides

The retained Hello operand mutation changes the predicted image and stdout. A separate all-N#
fixture implements IDisposable.Dispose and IThreadPoolWorkItem.Execute. Changing physical MethodImpl
row 1's MethodBody coded index from 2 to 4 alters exactly one byte at offset 1182, changing runtime
output from 11/22 to 22/22. Both executions exit zero with empty stderr. The two physical rows and
literal external member declarations are independently checked; calls use CLR interface MethodInfo
objects against the concrete receiver. Source, mutation prediction, images, IL and streams are
retained in `methodimpl-control/`.

The first IEnumerator fixture was refused by NL325 completeness; an unqualified ThreadPoolWorkItem
import was refused by NL010. Fully qualifying that interface is the accepted spelling. Initial
inspection guessed contract scopes, while the actual baseline override operands use
System.Private.CoreLib for both interfaces. The receipt records this corrected observation; the
predicted dispatch change predates the mutation and passes unchanged.

`final-controls-7009a190d4d6/` replays five exact committed native files on both immutable compilers:
**24/24 pass per arm**, with identical complete outcomes, normalized project images and all
**31 physical MethodImpl rows**. Seven rows belong to the new external fixtures. DisposeOnly and
AllSlots each carry an inferred source Dispose mapping before IDisposable.Dispose; AllSlots then
carries IComparable<int>.CompareTo and IEquatable<int>.Equals, and ArraySlot carries
IEquatable<int[]>.Equals. These inferred source interfaces are existing N# structural behavior.

The small-fixture metadata reader retains numeric TypeSpec placeholders. All physical rows are
compared exactly pre/post, while fixture expectations identify the TypeSpec member name and separate
per-class literal IL assertions pin constructed parents and original open `!0` signatures. The
expected source hashes and order were recorded before final replay. `FINAL_CONTROLS=PASS` is an
actual zero exit.

Native controls exercise source upcasts, CLR interface maps, scalar dispatch and SZ-array round
trips. Missing/return/arity/parameter negatives require successful parsing, exact existing outcomes
and successful MZ-image twins. False without a decline remains the original result; it does not
locate an internal failed phase more narrowly. The immutable pre private-matcher probe separately
passes 3/3: wrong name and wrong return short-circuit malformed inputs, while matching name/return
reaches the original unbaked GetParameters exception before arity. That probe is N# scratch evidence,
not a new dependency on a deleted private helper.

## Policy, identity and review

The N# owner preserves interface-list order, parameterless GetMethods order, name then TypesEquivalent
return then GetParameters/arity then left-to-right parameters. Completeness retains first Methods
lookup and all three original Name reads. Neither path adds static/default/generic filtering or
inherited-interface recursion; completeness constructs no structural descriptor. Source/external
MethodInfo deduplication domains remain separate, preserving first representation and attachment
order.

Successful matches derive actual open declaration, lookup/reflected/declaring contexts and effective
signature snapshots. External VAR ownership uses the actual open metadata type; MVAR additionally
retains MVID and MethodDef token, name, arity, convention and static flag. Runtime/metadata convergence
is tested against the same module image, with those identities checked first. Unregistered builders
remain rejected and effective source parameters retain their emission-local identity.

Review corrected registry-first validation so a dedicated external signature is validated by its
explicit owner family. Review then found that an initial regression fixture registered a source
definition without populating the generic-parameter registry. The final test calls
RegisterGenericParameters, distinguishes normal source-key selection from dedicated external-key
selection, and validates both under their own rules; the previously defective dispatch would fail.

The direct N# modifier fixture constructs its own baked interface with nonempty return/parameter
modreq and modopt lists. It first checks literal reflected counts/order, then descriptor facts,
input-copy behavior and read-only storage. Two-entry lists are exposed in reverse of SetSignature
input order, which the descriptor preserves. Static IAdditionOperators selection is explicitly
covered. An independently forged effective-return key with its original runtime companion rejects
the entire completion before any attachment; baking verifies both original default-interface maps
remain intact.

Definitive immutable-post review is `/private/tmp/nsharp-s22d-review/immutable-post/README.md`.
Its manifest and extracted IL link the final formatted product to the committed build, including
54 actual InitOnly fields in nine new retained classes, five copied AsReadOnly sites, preserved
read order, explicit external owner validation and validation of all bindings before the attachment loop. Earlier candidate source/IL
receipts are historical and are not substituted for final linkage.

Constructed generic MethodInfo is outside this GetMethods-derived binding constructor, while matching
itself remains unfiltered. Reflection exposes required/optional modifier arrays separately; arbitrary
mixed or nested modifier serialization remains a writer fidelity boundary. An exploratory C# probe
was discarded and excluded from evidence; accepted spelling probes are N#. No C# probe or fallback
was introduced into the product.

## Strict checking and integration

Both immutable compilers return byte-identical strict JSON on the same final source: **430 files,
259 existing errors, zero warnings**, exit 1 and empty stderr. All 259 baseline findings map to
unchanged source lines, with zero changed diagnostic rows or waivers; baseline checked 429 files.
The first candidate's two nullable-key findings were corrected before final source acceptance.

Final formatted estate passes **7,736/7,736**, dev Columnar **12/12**, and current-compiler native
columnar facts **93/93**. Worker commands, source hashes and logs are in
`/private/tmp/nsharp-s22d-executor-logs/handoff-receipt.json`. Root verifies the integrated product/test source
hashes, formatting, diff hygiene and ownership audit **18/18**. The emitter is **19,492 lines /
18,513 nonblank / 1,015,879 bytes**, a reduction of 25/24/1,052. Fingerprint is
`text-v1:54782b0b178f25a0`, observed manifest/policy head `head-v1:5797117d0e0f694e`. Only its ratchet
row changes; ceilings, epoch facts and the path set remain unchanged. Fresh AddType census remains
36 calls / 12 files, one keyed and 35 handle-only; the bare CodePlan call is counted.

The fresh committed-source backend gate is `/private/tmp/gate-20260905-goal-s22d-r1/`.
`source.json` identifies its exact archive, `gate.log` and `exit-code.txt` establish the actual result,
and `acceptance.json` is written only after verification and exact-SHA push. This document does not
substitute for that verdict. Command: `VSCODE_TESTS=skip ./scripts/test-all.sh --commit`; workers are
paused and clean. The prior c checkpoint passed at `2e256ef6`. The b checkpoint's intermittent
installer dry-run failure remains recorded and unexplained; no speculative workaround is included.
