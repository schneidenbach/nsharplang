# S2.2(b): ordinary source-interface member resolution proof

The baseline is `d29eac35f5c594599f2512c63787b78c8025a4de`. Implementation commit `4b592311`
and the two production-control commits form clean candidate `ad30338732e858e9cecaa1bdd3b0d242675a5021`.
This cut removes the ordinary source-interface lookup from C# and retains the actual selected
declaration in a structural binding consumed by the existing N# override executor.

## Fixed corpus and instrument controls

Proof root: `/private/tmp/nsharp-023-s22b-proof-20260905/`. The harness uses independent committed
archives, immutable compiler/support snapshots and the same baseline corpus for every arm.
The baseline archive SHA-256 is
`fd7bc186c9dc8a733c8d7a700c4899fd46a3bea381d7698ac9791f09e1c42155`.
`harness-provenance.json` records the copied instruments and the baseline change.
Each command runs from its own archived tree. Support binaries are explicitly classified;
emitted images keep their relative paths, so missing outputs cannot be hidden by flattening.
The normalizer clears only the PE nondeterminism stated in `nl98_ilnorm.py`; this compares whole
normalized images, including metadata and method bodies.

Independent baseline arms d/e each have **75 projects, 73 successes, 94 emitted images and
2,159 native tests passed**, with no failed or skipped tests. Their only failed projects are the
same systems CLI/library templates with NL402. `compare-d-e.json` has zero image, output-set or
outcome differences. The control driver exits zero with `CONTROL_VERDICT=PASS`.

Both live sensitivity controls pass. Changing one `ldc` operand from 42 to 43 changes exactly the
predicted image and stdout (`nonvacuity.json`). A separate two-interface executable has precisely
one MethodImpl MethodBody byte changed, at offset 1064; its unchanged method bodies dispatch
`11 / 22` before and `22 / 22` after, with both processes exiting zero and empty stderr.
`methodimpl-control/methodimpl-mutation-result.json` retains the bytes, hashes and runs. The
physical-table reader is deliberately limited to the small fixtures it checks; it is not a new
general-purpose product metadata reader.

## Exact new controls

Terra's production controls are commits `9eaeb015` and `b9e7bca9`. The final test source hash is
`5dc740b53168eeda0919ee43317e255f629454fddfc30c232055fea2f8f9d04e`.
Together with the unchanged override dispatch and precedence files, the exact source executes
**16/16** using the immutable baseline compiler. The image has **19 physical MethodImpl rows**.

The tests exercise own declaration selection, signature mismatch followed by the actual ancestor,
ordered diamond traversal, default bodies, and source/external equality domains. Missing and
mismatched member controls first require successful parsing and have matching positive inputs
through the same helper. Both negatives preserve the existing `false` return with no located
decline. A parser failure cannot satisfy either negative.

The attempted later-overload source is refused before emission, so it supplies no black-box
evidence for first-overload selection. The direct resolver contracts cover that policy. The
closed-derived interface runtime failure measured by Terra is outside this ordinary-source cut;
its probe and failure remain in `/private/tmp/nsharp-s22b-controls-logs/` for the later family.

The parent's preliminary test run passed 16/16, but an analysis assertion wrongly expected only
one DLL in the directory. The runner also copies five support DLLs. The corrected analysis reads
the named project image and explicitly classifies all five support names; original streams and
the correction remain in `new-controls-pre/analysis-note.txt`.

## Identity and validation review

The resolver retains the original own-first, depth-first order and CLR Type equality. Disassembly
of the deleted C# helper and candidate N# confirms `Type.op_Equality` / `Type.op_Inequality`.
Non-reference-equal TypeDelegator wrappers that compare equal are accepted; structurally equal
builder closures that compare unequal remain distinct matching candidates.

A descriptor is built only from the authoritative `owner.Methods[memberName]` row. It captures
the found declaring type, selected return/parameter types, modifier facts and independent original
runtime companions in the shared emission table. The original unbaked MethodBuilder is retained
separately. Application validates every direct binding against the consuming emission table
before its first attachment; the two-argument entry rejects descriptor-bearing rows.

Review exposed a real immutability gap in the preceding structural types: get-only properties
still emitted mutable public backing fields, and readonly array references still exposed writable
elements. This cut fixes the consumed identity dependency with InitOnly scalars and copied BCL
read-only collections. It makes no new field-visibility policy and no claim that reflection is a
security boundary. Three new metadata/mutation contracts compile and fail on the old representation,
then pass with the fix. The corrupted-binding contract replaces the selected return with a valid
string selection while its independent runtime companion remains void; validation rejects it and
the earlier valid default interface mapping remains unattached.

## Final candidate and checkpoint

Post arm f also has **75 projects, 73 successes, 94 images and 2,159 native tests passed**.
`compare-d-f.json` has zero whole-image, output-set and outcome differences; `coverage.json`
checks all three arms and the driver exits zero with `PARITY_VERDICT=PASS`.

`final-controls-ad30338732e8/` replays the exact three committed native files on both immutable
compilers: **16/16 per arm**, matching output sets, normalized project images and all **19 physical
MethodImpl rows**. Six literal source-slot rows and their physical order are checked independently
of the comparison. Both compilers return byte-identical strict JSON on the same final source:
**428 files, 259 errors, zero warnings**. The 259 baseline findings are entirely unchanged; the
line mapping has no changed rows and no diagnostic waiver. Final control driver exits zero with
`FINAL_CONTROLS=PASS`.

The final formatted estate passes **7,714/7,714**, dev Columnar **12/12**, native declarations
**85/85**, and iterators **25/25**. Worker commands and streams are in
`/private/tmp/nsharp-s22b-executor-logs/`. One postformat test invocation produced no counted verdict
because dev.sh had restored the project with tests excluded; the forced test-enabled restore and
subsequent 7,714-pass run are retained. Two added strict nullable-flow findings were corrected with
an explicit null-row invariant guard; the malformed internal null row now throws
InvalidOperationException instead of a null dereference. Valid source rows keep the original policy.

Final review is in `/private/tmp/nsharp-s22b-review/final-review/`. Its linked-post receipt verifies
six committed source hashes, all fourteen CLI files and all 77 support files. Disassembling the
immutable post binary produces IL byte-identical to the retained reviewed worker artifact. Earlier
Debug output was overwritten by a later build; that stale linkage is identified rather than reused.

The merged CLI builds with zero warnings/errors, the root format check is clean and the ownership
audit passes **18/18**. The emitter is **19,613 lines / 18,622 nonblank** (−16 / −15), fingerprint
`text-v1:e644af96facbeb0d`. The measured manifest/policy head is
`head-v1:8ff51ba796192fbc`; both keys are updated without increasing a ceiling or changing the path set.
Receipts are `ratchet-before.json`, `ratchet-after.json`, `root-cli.log`, `root-ownership-audit.log`
and `root-format.log`.

The fresh backend gate lives outside the committed snapshot at
`/private/tmp/gate-20260905-goal-s22b-r1/`. Its `source.json` identifies the exact archived commit;
`gate.log` and `exit-code.txt` provide the actual verdict. `acceptance.json` is written only after
successful verification and an exact-SHA push. This document does not substitute for that result.
The command is `VSCODE_TESTS=skip ./scripts/test-all.sh --commit`, with fresh steps. Workers are
paused and clean; the controls branch retains its original commits, with its exact duplicate
untracked source safely reconciled to the accepted implementation and external source copy.

All terminal task boxes remain open. Closed-source, external/base/iterator member resolution,
remaining type-pool consumers, ambient-local slots and retained maxstack precede the writer stages.
