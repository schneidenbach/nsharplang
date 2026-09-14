# S2.2(c) — closed source-interface parity proof

The implementation is `0813c1acfb6391f17bda8af1ac715d705f62075b`; Terra's direct and production
controls are integrated at `417f66e71` and `93ecaf6d`. This proof covers closed source-interface
lookup, matching and completeness, shared signature substitution and generic method rebinding.
External/base/iterator resolution, source-definition discovery and constrained-call argument
admission remain separate owners. All terminal task boxes remain open.

## Fixed compiler and corpus

Baseline and fixed corpus are `aff32a9e1a1a0df3d75cc3805223af5c235b12fb`; post is
`93ecaf6d1883aca9899605ad20c1240f685950fd`. The external harness is
`/private/tmp/nsharp-023-s22c-proof-20260905/`.

Each of the three arms visits 75 projects: 73 succeed, the same two NL402 template declines
remain, and 94 project images plus 2,165 native test passes are measured. Both `compare-d-e.json`
and `compare-d-f.json` have zero normalized-image, output-set and complete-outcome differences.
`control.log` ends with `CONTROL_VERDICT=PASS`; `post.log` ends with `PARITY_VERDICT=PASS` and the
driver exits zero. `coverage.json` checks actual counts in all three arms. The fixed corpus
intentionally excludes the newly added tests, which are replayed separately below.

Both compilers are independent committed-source builds. Their fourteen CLI files and 77 support
files are hashed in `compiler-pre.json` and `compiler-post.json`. Only the established volatile
PE fields are normalized. Paths remain distinct, and all output sets and complete outcomes are
compared. The two declined templates are not described as passing projects.

## Controls that make the comparisons meaningful

The retained operand one-byte control changes its predicted image and stdout. A second control
constructs IFirst<int>.First and ISecond<int>.Second. Changing the first physical MethodImpl row's
MethodBody code from 6 to 8 changes one byte at offset 1254 and runtime output from 11/22 to 22/22;
both processes exit zero. Raw and normalized image hashes, predicted and observed table rows,
complete IL and runtime streams are retained in `methodimpl-control/`.

The small-fixture reader leaves TypeSpec parents as numeric handles; it does not claim a general
generic-signature decoder. Separate literal IL declarations assert the constructed parents
IFirst<int32>/ISecond<int32> and original open `!0` return signatures. The initial direct
interface-local call spelling was refused by the baseline and remains in `attempt-1/`. The
accepted mutation fixture invokes CLR interface MethodInfo objects against the concrete receiver;
it proves slot mapping and runtime dispatch without claiming source typed-interface-call admission.

`final-controls-93ecaf6d1883/` replays four exact committed native files on both immutable compilers:
**20/20 pass per arm**, with matching complete outcomes, normalized project images and all
**24 physical MethodImpl rows**. Six ordinary source rows retain their literal order. Five newly
predicted closed rows check concrete body/member order and, independently, exact closed parent/open
VAR signature text: scalar and SZ-array members for int/string, then constrained Pick. Predictions
were derived from reviewed source before the final replay. `FINAL_CONTROLS=PASS` is an actual zero
exit, not an inference from partial output.

The new production controls verify open VAR reflection, two closed instantiations, CLR interface
mappings, scalar invocation and both array round trips. They also execute an actual constrained
generic source call whose parameter and return are closed. Default-only/default-override and
completeness positives reach the production emitter and produce an MZ image; these are emission
controls, not unmeasured default-body runtime claims. Missing/wrong-parameter negatives require
successful parsing, exact outcomes and matching positive twins. Their existing false-without-decline
outcome still cannot locate a failing emitter site more narrowly.

Terra's receipts retain refused direct typed-interface calls, nested generic/byref source signatures,
and the emitted source-plus-IDisposable fixture that fails type load. No accepted runtime coverage
or fix is claimed for those spellings. Original test commits are `a5332360` and `9f1cc12d`; sources
and complete probe receipts remain in `/private/tmp/nsharp-s22c-controls-logs/`.

## Identity, policy and compiled-code review

The moved policy retains first-Methods own/depth-first lookup, TypesEquivalent rather than ordinary
CLR Type equality, return-before-arity-before-parameters, default skipping, original closed-context
ordinal substitution and the original builder/runtime rebinding branch. Matching and completeness
perform no structural selection or rebinding on failure. Shared call-selection/body policy remains
in C#; the two substitution sites now use the same N# owner.

Review found and corrected two concrete integrity holes before acceptance. Independently supplied
effective types could originally validate without belonging to the open member/context. A deriving
match now produces the exact effective handles once. Keeping only the mutable source-row reference
then allowed old effective facts to be paired with altered open facts. The match now snapshots the
original signature/modifiers/builder; descriptor construction rejects changes since matching,
without repeating generic closure. Already captured descriptors survive later source-row changes.
New descriptor capture has explicit structural/source invariants; this proof does not claim every
arbitrary malformed private-helper input has an identical result.

Direct N# contracts prove short-circuit order with malformed later types, first-row/depth-first
behavior, Type-equivalent but CLR-unequal shapes, nongeneric/open/constructed context relationships,
foreign-table rejection, immutable storage, original MethodInfo deduplication domains and validation
of all bindings before any attachment. Parameter, return and builder mutations are independently
rejected during construction. Corrupting a selected effective return while retaining its original
runtime companion rejects the completion before the earlier valid mapping is attached.

Astra's definitive approval is `/private/tmp/nsharp-s22c-review/immutable-post/README.md`.
All 91 post manifest files and seven reviewed source files match their pinned values and actual
committed build source. The seven relevant post class IL blocks are byte-identical to the approved
worker artifact: 28 InitOnly fields, four copied BCL AsReadOnly wrappers, raw binder casts/order,
direct match construction and no redundant source-row check before rebinding. ApplyCore's first
loop validates/stores every target; only its second loop attaches overrides. Earlier historical
artifact receipts are explicitly distinguished from this final linkage.

The exact incompatible runtime owner was also measured through the immutable pre compiler's
private rebinder: ArgumentException inside the reflection wrapper. Two initial substitution tests
failed because builder SymbolType byref/pointer shapes reported IsSZArray; runtime generic-parameter
inputs now discriminate the intended branches. The original failed expectations/probe are retained.
That probe establishes current reflection behavior only; baseline equivalence is inferred from the
unchanged branch order, not represented as an executed pre-private closing comparison.

## Strict checking and integration checkpoint

Both immutable compilers return byte-identical strict JSON on the same final source: **429 files,
259 existing errors, zero warnings**. All 259 baseline findings match unchanged source lines, with
no changed rows or waiver; the baseline checked 428 files. An early candidate had two new nullable
out-flow errors. Direct match construction removed the unnecessary out wrapper and both findings.
Final receipts are `strict-comparison.json` and `verdict.json` under the exact-source replay directory.

Final formatted estate passes **7,726/7,726**, dev Columnar **12/12**, and current-compiler native
columnar emit facts **89/89**. Complete worker commands, hashes and frozen artifacts are in
`/private/tmp/nsharp-s22c-executor-logs/handoff-receipt.json`. The merged CLI builds with zero warnings
or errors; root formatter and ownership audit **18/18** pass. Emitter size is **19,517 lines /
18,537 nonblank** (−96/−85), fingerprint `text-v1:9890e3bb9db3bdcc`. The observed manifest/policy head
is `head-v1:3e5ff5c7c0070ed0`; no ceiling or path set changes. Root logs and ratchet receipts are in
the parent proof directory.

The fresh committed-source backend gate is `/private/tmp/gate-20260905-goal-s22c-r1/`.
`source.json` identifies the exact archive, `gate.log` and `exit-code.txt` establish its actual
result, and `acceptance.json` is written only after successful verification and exact-SHA push.
This document does not substitute for that result. The command is
`VSCODE_TESTS=skip ./scripts/test-all.sh --commit`; workers are paused and clean. The prior b
checkpoint's intermittent installer dry-run failure and successful fresh retry remain recorded
in its proof and failure receipt; no speculative installer workaround is included here.

Remaining external/base/iterator members, source discovery/call admission, type-pool consumers,
ambient locals and maxstack precede the writer stages and terminal deletion/AOT work.
