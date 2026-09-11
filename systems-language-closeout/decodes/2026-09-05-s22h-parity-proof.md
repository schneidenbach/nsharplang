# S2.2(h): generic-constraint lookup integration proof

Product `47d0a062d7427eac6c825d921247714b418b64cd` (Sol `231ad51e`) replaces the C#
constraint query with `ColumnarGenericConstraintPlanner.ResolveCallConstraints`. The two old identity/
reflection helpers are deleted; `GetGenericInterfaceConstraints` is a direct N# forward. No map
producer, member selection, argument admission or other remaining C# policy is claimed migrated.

Source owner SHA256 `18e504174cd91979bf48e61dd341e77a1f75287f0789169b73780a9ff0be8d82`.
Emitter SHA256 `33a8e8e56c7e074bebeecdd36c3637ee100896fc1a2c130158beaea4d8c5ef2c`;
19,334 lines / 18,366 nonblank / 1,010,884 bytes, down43 /41 /1,128. N# owner grows77 lines.
Ratchet commit `e170415204` changes only the emitter's shrinking row and reviewed head to
`head-v1:3535178e0c882670`; all381 entries, epoch ceilings and assertion counts remain enforced.
AddType census remains36 calls /12 files /one keyed /35 handle-only.

The public query initializes a real null out local, uses the supplied map's TryGetValue and retains
its comparer and returned array, including null. A miss passes that same map directly as the helper's
exact inherited IEnumerable<KeyValuePair<Type, Type[]>>. There is no cast, materialization or new
compiler capability. Acquisition occurs before try; generic Current and left/right guards remain
ordered. Only ordinal reads catch NotSupportedException/NotImplementedException. Weak matching
intentionally retains legacy same-name/same-ordinal behavior across owners. The first match writes
the exact Value before finally; a completed miss clears after disposal. Raw reflection then returns
the actual array or the actual BCL Type.EmptyTypes for those two exceptions; other faults escape.

Direct map-enumerator/local/cast drafts declined under the seed. The exact helper-parameter spelling
passed1/1 through the live accepted g1 SDK with all three query routes and inspected generic Current/
finally IL. Evidence: `/private/tmp/nsharp-s22h-executor-logs/stage0-map/`. Rejected sources and logs
remain separate from the accepted probe. No live SDK repin was needed.

## Controls and independent review

Integrated controls: `68c0a8387` (two native constraint-order tests), `16a0f27f` (five reflection tests),
`5a5b3f001` + `18c079268` (ten map/lifecycle tests), plus three lookup tests in the product commit.
The exact canonical increment is18: the focused eight-test getter run includes the original three.
The initial root gate-verifier expectation7,790 was a double count; the measured fresh total is7,787.
Its initial failed analysis and correction are retained; no gate rerun or test change was needed.

Controls cover comparer behavior, exact/null values, live order, raw reflection-array identity,
guard/catch scope, left-before-right ordinal reads, actual generic Current, enumerator lifetime and
out-slot timing. The final public lifecycle tests share an actual Dispose/reflection event trace:
91→14 for an exhausted successful query, only91 for exhausted enumeration with throwing Dispose.
Earlier final-counter-only and hit/throw fixtures could not prove that ordering; the reviewed
follow-up fixes the observations before acceptance. Final map controls pass10/10; getter filter8/8.

An N# witness invokes the actual old private instance query from immutable predecessor binaries:
3/3 proves exact-array identity, real cross-owner weak order reversal and a true name-mismatch
reflection miss. It does not claim hostile-disposal coverage. Receipt:
`/private/tmp/nsharp-s22h-controls-logs/legacy-constraint-query-witness/final-receipt.json`, SHA256
`37ab9623e68e0a07904ebf8507159216fae5cb30cce02e613ce4f916bf32ec02`.

The frozen weak-array mutation changes only the helper's matched Value assignment to BCL EmptyTypes.
Exactly `CallConstraintsPreserveTheFirstLiveSameNameSameOrdinalFallback` fails; two positive controls
pass. Prediction precedes mutation and actual TRX. Receipt:
`/private/tmp/nsharp-s22h-weak-array-mutation/evidence/receipt.json`, SHA256
`a038666b75642a75fa97cfe2c041083dfb3dc5aa6c7f07c07668bd8f6df41dd8`.

Astra reviews are under `/private/tmp/nsharp-s22h-review/`: stage0-final, immutable-post,
getter-controls, map-controls-final, legacy-witness, weak-array-mutation, native-constraints and
strict-delta. The immutable linkage verifies14 CLI and77 support payloads and whole product IL
byte-identical to the first compiled review. Linkage SHA256
`eef80cceda4ba26003d81fcc060351f6fd059be55f05ab4f3a92b28c11cca128`. The final map review pins the
shared real-event fixture source `971a7585d3034990615eea3cfc4960a2cc44523451e72d7bcb6c93c280ac83fd`.
All review JSON hashes are included in the gate result.

## Immutable comparisons

Evidence root: `/private/tmp/nsharp-023-s22h-proof-20260905/` (H). Accepted predecessor is
`2ce6915544ebd8e55faac47e5177d9788783c729`; its reused immutable product compiler is `096968ae7`.
Post manifest pins product `47d0a062d`, archive SHA256
`f91bb50b1a6cf936beba7f22b9ee7443292812866b27ca7136e9bcc0e6c94238`, BootstrapServices
`1b1bdfa9c928e58c97bbacb7bc2bee3cca1d248b1d6b980e725bf52486bbc008` and Compiler
`f5db64e91e96340189b5e1d7af2ab9c9d9a8b74dea127bbcc38eeb73c46ffd2f`.
All14 CLI/77 support payload hashes are checked before acceptance. Later commits add tests and the
ratchet; product BootstrapServices excludes test sources, explicitly verified by the reviewer.

Fixed corpus `f54385d5d6b32efb0cb47e5761931bb63af707f4`: both arms have75 targets /73 successful
projects /94 normalized images /2,184 native passes /0 failures or skips and the same two NL402
template refusals. Accepted g results are reused with verified manifests. New h produces no image,
set or full-outcome differences. `H/compare-g-h.json` SHA256
`950e2af367d47892e4a1429a68c586d55ea127981fff32da7b1bbc18fe676ff1`.

New native corpus `68c0a8387` runs107/107 with both immutable compilers. Constraint-order twins retain
exact metadata order, runtime211/212 and constrained.!T followed by ConstraintLookupSecond::Select
callvirt. Whole IL, normalized PE and normalized output match. `H/native-constraints/receipt.json`
SHA256 `a0752b44277b110c83b66fe93e6a526573c4b8131f5d08754eaf1d68c43880f7`.
Two analysis corrections are preserved: ILSpy's update notice required its documented
--disable-updatecheck option; N# emitted class labels lacked the assumed backtick-arity suffix.
Neither was a compiler/test failure; the verified completed pre-run was reused.

Strict replay checks433 files:259→258 errors, no warnings/info. The sole removed finding is the old
NL010 at the planner's System import, now used by new unqualified types. All258 remaining findings
retain order and mapped unchanged-source locations, with no additions. Pre/post compilers on the
same final source produce identical bytes. `H/strict/strict-comparison.json` SHA256
`94e451a24d830237989740f0c730f4aefa54fdc457282f016d15324201751577`. The initial unchanged-count
assertion failed in analysis; retained output was reanalyzed without rerunning the checks.

## Fresh integration checkpoint

`VSCODE_TESTS=skip ./scripts/test-all.sh --commit` tested exact clean archive
`e1704152049b54b93c457ed634303bfcd7fd9482`; exit0 in453s. It passed593 unit /7,787 canonical /
107 native declaration /18 ownership tests, 52 native projects and68 IL-verified assemblies, plus
SDK/templates/examples/toolchain checks. Benchmark correctness passed; load4.65 exceeded threshold2,
so timing was unjudged. No analysis/emission timing claim is made. Backend-only scope required no
VS Code reload; the overall goal still requires terminal IDE verification.

Gate root `/private/tmp/gate-20260905-goal-s22h-r1/` retains source.json, gate.log, exit-code.txt,
gate-result.json and the three isolated diagnostic files in a hashed archive. The subsequent
Markdown-only commit is compared against the tested tree in documentation-followup.json; all other
tracked entries must be identical. acceptance.json records the final documentation revision, exact
verified remote and receipt hashes after push. This distinguishes tested code from its acceptance
notes without claiming a new gate ran on the later documentation archive.

All12 live accepted g1 SDK payloads remain unchanged; seed-repin acceptance remains
`/private/tmp/gate-20260905-goal-s22g1-r1/seed-repin/acceptance.json` SHA256
`ae49c1d7acdf4655767f5814506ce47056ec9c66cec878db86d675d28a9b0353`.
No terminal 015/021/022/023 box closes. Next: the [record synthesis cut](2026-09-05-s22i-record-next-cut.md),
followed by the remaining writer/type-universe/NativeAOT ownership work in the live ledger.
