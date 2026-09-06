# S2.2(i): record synthesis integration proof

Product `1b067f203a8f98405a21f4cadd7ad52d07503ca5` (Sol `c7ea0d434`) makes
`ColumnarRecordValueMemberPlanner.EmitRecordValueMembers` the sole PASS 0e owner. The C# loop and
`SynthesizeRecordValueMembers` / `SynthesizeRecordCloneMember` are deleted; the host directly calls N#.
The [implementation decode](2026-09-05-s22i-record-value-members.md) describes the preserved phase order.
No other call admission, iterator realization or remaining writer owner is claimed migrated.

The source owner SHA256 is `7e3cf9fed0eef0c91a7e4291b9070f5efb6c51616158c5fc63cd6020bfbfb30d`;
emitter SHA256 `df4d54035bbe0c6b62211790510615c2994ed6f11c0ea963f2f3f212ddb8614a`.
Emitter size is19,264 lines /18,300 nonblank /1,007,405 bytes, down70 /66 /3,479. Ratchet commit
`5dde45f26` changes only that shrinking row and reviewed head to `head-v1:aa711599f6919ff9`;
381 entries, epoch ceilings and assertion counts remain enforced. All five record AddType consumers
now retain keys, exact runtime companions and the caller's table: census36 /12 files /6 keyed /30
handle-only. No eager type selection or second table changes the old evaluation phase.

The live input count and IsRecord gate precede parallel-array access. Every nonnull generic map,
including empty, skips synthesis. The captured FieldOrder scan stops at the first builder-bound
field. Equals then Hash are declared, planned and executed in order; clone runs last for reference
records on either field path. It retains flags134 and actual BCL Type.EmptyTypes and publishes only
after successful execution. The chained FieldBuilder getter spelling declined; the admitted split local preserves the
same dictionary read and FieldBuilder.FieldType getter. Failed source/logs remain in executor stage0.

## Controls and sensitivity

Native controls `0d3c14c35` (Terra `e63811dee`) add3 to record-with, now15. They execute value/reference
equality and hash, preserve user methods, verify actual override identity and clone flags, and execute
clones for direct/nested builder fields including shallow child-reference retention. Canonical additions
are7: Sol's3 in the product commit and Terra's4 in `2d156b43b` (worker `a03c59079`). The initial1-test
seed proof is a subset of Sol's3, not another test. An initial incorrectly underscored filter selected
zero tests and is not accepted evidence; the corrected run and final3/3 TRX are retained.

Direct controls cover partial user-method slots, preexisting clone identity, value-record clone skip,
all five actual keyed entries and fresh invalid companion rejection before IL/local creation. A stale
later Hash overload row fails after the earlier record's three bodies and the later Equals body have
been emitted. After catching the failure, the controls bake and execute those bodies; a clean
later-position twin executes all three. Initial builder-only
observations did not prove body completion and were corrected before the final4/4 run. A first builder
field followed by a missing field name proves early scan termination. Missing/foreign registration
probes are new structural invariants, not historical malformed-table compatibility claims.

Final direct source SHA256 `d4cdaee2db2d38f834ce086a0a358b9e56eefc6b75a3d6af393564be5244fa27`;
receipt `/private/tmp/nsharp-s22i-controls-logs/direct-controls-5-receipt.json`, SHA256
`7764547a40c89045b19f288c97d0e42cbadf8e19b5c98a31ab6b458ecad69d46`. Final4/4 has empty stderr;
the inherited MVID extraction warning remains in stdout. Root format checks all five changed N# files.

The standalone N# witness invokes the actual old private static one-record helper through matching
immutable h Compiler/BootstrapServices dependencies:1/1. A clean row executes Equals/Hash391/clone;
a malformed later row produces the required TargetInvocationException/InvalidOperationException and
executes its retained Equals after failure. Scope is the helper called twice, not the deleted outer
batch loop. The rejected narrow-catch seed spelling remains retained; the admitted generic catch
checks actual runtime exception names. Receipt at
`/private/tmp/nsharp-s22i-controls-logs/legacy-record-synthesis/run-09-receipt.json`, SHA256
`c5b3e18a04644a374fdf8004ce3d93dce42a5a2f4323654911170d5aa2364f37`.

A frozen prediction changes only Hash's keyed source AddType to the old handle-only call. Exactly
`RecordValueMemberPlansRetainAllFiveSameTableStructuralTypePairs` fails with “Expected a structural
type-pool entry”; the other two controls pass. Actual3 =2 pass/1 fail, unchanged test source.
Receipt `/private/tmp/nsharp-s22i-key-removal-mutation/evidence/receipt.json`, SHA256
`4af62d208b97b10fce398c44c51dfd6a93a238689a67a1a356e0f1767d7ea9f4`.

## Immutable comparisons

Evidence root H: `/private/tmp/nsharp-023-s22i-proof-20260905/`. Accepted predecessor is
`b1abca5841924382006644d5fa5bdba26e77778f`; its reused product compiler is `47d0a062d`.
Post manifest pins product `1b067f203`, archive SHA256
`6e651a549e2eb4223b093566e31e04edb2b3a6aaa0cda1ff3a7d44040c497277`, BootstrapServices
`e83944991b5c22449a230cbe1d4cb1fad2acab160ff62e81f6251af889b7a7f4` and Compiler
`d2215ee14dd983f42e6f51efd69f09c70e3d4f9b72176871c960f28ee31ceeda`.
Independent review verifies1,805 source files,14 CLI/77 support payloads and whole product IL identical
to the first compiled review despite a later unused-import/comment cleanup. Tests/ratchet added after
product freeze do not change its non-test source; final gate covers their combined test assembly.

Fixed corpus `f54385d5d6b32efb0cb47e5761931bb63af707f4` has75 targets /73 successful projects /
94 normalized images /2,184 native passes /0 failures or skips per arm, same two NL402 template
refusals and zero image/set/full-outcome differences. Accepted h results are reused with hashes
verified. `H/compare-h-i.json` SHA256
`7d4001faa135b9e107cdf8a0e828260452f3043b67464b829463a0c45347806e`.

The fresh exact native pair runs all15 record tests on each immutable compiler. Whole IL, normalized
PE, normalized JSON and stderr match; only project-root/duration fields are normalized in output.
Compiler dependency paths select the correct arm even for nested compilation. Actual argv/cwd/exits
and all source/payload/image hashes are retained. An earlier worker receipt lacked retained exact
argv/exit provenance; its amendment marks it historical, and this fully recorded fresh pair supplies
acceptance. `H/native-records/receipt.json` SHA256
`6c6837079c9163058853a4b0e055e730c1ef70f0943ed603852b987ac96eb314`.

Strict replay checks433 files:258 errors, no warnings/info, unchanged ordered diagnostics with mapped
unchanged-source locations. Both immutable compilers on final source produce identical bytes.
`H/strict/strict-comparison.json` SHA256
`26c93dcce67871615e8cb940b241e14b7434d3813c06ef3f6df115e4df59ec1c`.
Independent source/compiled/control/native/mutation/legacy reviews are under
`/private/tmp/nsharp-s22i-review/`; the gate result pins their hashes.

## Fresh integration checkpoint

`VSCODE_TESTS=skip ./scripts/test-all.sh --commit` tested clean committed archive
`2d156b43b282807f9ce0909b711f9c88da584ff6`: exit0 in452s,593 unit /7,794 canonical /
107 native declarations /15 native record /18 ownership tests,52 native projects and68 IL-verified
assemblies, plus SDK/templates/examples/toolchain checks. Benchmark correctness passed; timing was unjudged because of host load.
This is the existing front-end parse/strict-lint benchmark; no analysis/emission timing claim is made.
Backend-only scope requires no editor reload; terminal whole-goal IDE verification remains required.

Gate root `/private/tmp/gate-20260905-goal-s22i-r1/` retains source, logs, result and the three isolated
diagnostic files in a verified archive. The later Markdown-only acceptance commit is compared with
the tested tree in documentation-followup.json; every other tracked entry must be identical.
acceptance.json records the final revision and exact verified remote after push. No gate is claimed
on the later documentation archive. All12 accepted g1 live SDK payload hashes remain unchanged;
no repin is needed. Whole goal and terminal015/021/022/023 boxes remain open. Next is the
[iterator realization cut](2026-09-05-s22j-iterator-next-cut.md), then remaining S2.2/writer/universe/AOT work.
