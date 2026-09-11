# S2.2(l1): concrete dictionary value enumerator acceptance

Product `9e1093c678046aca2511dbf5c0b33ee4bc6fa2f0`; tested `6687505e48fd6384a2273c5a9445d1812def99a8`. Accepted predecessor `e7d4486d9`.
Sol product `ac1bb29aeaae27d7796cb2e3554f8dcc11e5ee1a`; Terra controls `e73c463913e9839a1b23c57f7f9a92d136d8807a`.

The exact live initializer takes the existing builder-bound admission arm. N# now accepts only the
genuine nested Dictionary value enumerator with recursively closed arguments, a supported key,
the existing non-enum-builder key restriction and existing collection-value admissibility. The
complete C# entry-point owner is unchanged. No C# or ownership-ratchet delta occurred.

| Evidence | Result |
|---|---|
| Producer focused canonical regression | 1/1, actual test-enabled TRX |
| Independent canonical identity/argument controls | 2/2, genuine nested foreign definition and retained open/key/value/sibling exclusions |
| Same final native source | Accepted predecessor refuses concrete local; candidate 114/114 |
| Concrete runtime behavior | First-hit break, two-value progression/order/reference identity, fresh-key mutation exception |
| Compiled methods | One concrete struct local, ldloca receiver, exact MoveNext/typed Current/direct Dispose; one finally per method, no box/interface replacement |
| Fixed f543 corpus | 75 targets, 73 successes, 94 normalized images, 2,184 native passes per arm; no image/set/outcome differences; same two NL402 template refusals |
| Strict identical-source comparison | Byte-identical stdout, 258 mapped findings /434 production files |
| Fresh backend gate | 448s; 593 unit /7,816 canonical /114 declarations /7 Reflection.Emit /15 records /18 audit; 52 native projects, 68 IL assemblies |
| Actual SDK 0.1.0 | Same committed fixture 3/3; all 10 packaged tools equal Release, all 12 SDK/tools equal live cache before/after build |

Immutable complete BSS IL equals the producer. Whole Compiler IL differs only by one relocated
static-data address with its six bytes unchanged; raw whole-Compiler IL equality is not claimed.
Product-to-tested differences are exactly the two new canonical/native control files. The full gate
includes both. C# emitter remains 18,923 lines /17,984 nonblank /985,534 bytes, AddType 36 calls
in 12 files /21 keyed /15 handle-only, and the 381-row ratchet is unchanged.

Gate result: `/private/tmp/gate-20260906-goal-s22l1-r1/gate-result.json`, SHA `e085142de34d8aa347cecc8e91d91f477491d82746faa666016f047942ba0a35`.
SDK acceptance: `/private/tmp/gate-20260906-goal-s22l1-r1/seed-repin/acceptance.json`, SHA `447cd1f21e756664facf5dc112e701d6f3b95f2daf4d918780cefa8e633f8918`.
SDK package SHA `431f3ae0476285110620a4c80117f32edc903f0fbc08009938ff2e8501599a90`; Compiler SHA `8990fee2fd433d4614e573a0497462e680a4a6d034d8b7e203a8c789bbd46ac6`;
BootstrapServices SHA `cb6021531f97e218752cd6cb43e40ace115471fc24e2b61c033bb2d262f0401f`.
Root proof: `/private/tmp/nsharp-023-s22l1-proof-20260906`. Independent review receipts:

- `/private/tmp/nsharp-s22l1-review/actual-handle/review.json` — `e73232b5f20631cb486b00a91e4a5c09268644567f34f9e97742decf3e4c47bf`.
- `/private/tmp/nsharp-s22l1-review/candidate-final/review.json` — `58dd3304cd7839bd9a954ba588204cc0c1403649bc1b9a3e3ff176be230a93c9`.
- `/private/tmp/nsharp-s22l1-review/immutable/review.json` — `71f365da921b884081bce72968b2ad6b63dad7825b12c3ae7ed105ff3d67ff8f`.
- `/private/tmp/nsharp-s22l1-review/native-candidate/review.json` — `1243a4429c6d1d5b17f0869a2d8a0a93e7d435e3f09107be7fe7c966a5b148e8`.
- `/private/tmp/nsharp-s22l1-review/controls-final/review.json` — `45e8a055598db6e6b6f81e309fbe54c947bdfe87a18c689ad13f52c41cef290b`.
- `/private/tmp/nsharp-s22l1-review/packaged-live-seed/review.json` — `287865f9b82cc43db26050e52dcb5586ddc800e532a7b59eb7e5adf620c20aee`.

The initial native source hit retained NL305 return-flow analysis before storage admission; it was
rewritten to the actual first-hit break/finally/post-finally return pattern. That failed source and
its launcher error remain recorded; no missing exit code was reconstructed. The initial foreign
identity test built a top-level plus-containing type instead of a nested type; its failed source,
failed test and corrected genuine nested fixture are retained in the controls receipts. An intermediate
corrected single-control TRX passed 1/1, but its shell recorder lost the exit code; that launcher error
is retained separately from the final two-control run with measured exit 0.
The early diagnostic kind-only result and later AQN instrumentation failure remain distinct from
the final actual-handle observation. No failed attempt is counted as passing evidence.

VS Code was skipped for this backend emission prerequisite; prior k IDE acceptance is separate.
Benchmark correctness passed, but front-end timing was unjudged under host load.
Actual SDK build still enables legacy validation, which remains bootstrap debt. The full entry-point
owner, remaining writer work, unified metadata, NativeAOT and final ownership/IDE acceptance are
still open. Resume [S2.2(l)](2026-09-06-s22l-entrypoint-next-cut.md) from the verified l1 seed. Final
Markdown review, exact-push/remote verification and gate-copy cleanup receipts remain beside the
gate result; all evidence and immutable proof are retained. Tasks 015/021/022/023 remain unchecked.
