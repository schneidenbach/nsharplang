# S2.2(f) integration proof

Base bindings and ordinary declaration realization are integrated at `86c88c4960736768c5c466adb08608b07ab89f90`
(worker `1de1e51c`). Independent controls are `453e467b8` and `f6191720f` (workers `a123dd2e` and
`18fe3bd4`). The accepted predecessor is `18d112ce39205298327292e7d5bf05161d9e756e`, freshly gated
and pushed before this slice. No terminal task box is checked here.

## Fixed compiler and corpus evidence

Evidence root: `/private/tmp/nsharp-023-s22f-proof-20260905/`. Each immutable compiler manifest
records 14 CLI files and 77 support files, built from committed git archives. The fixed corpus is
accepted `18d112ce`; the post compiler is exact integrated `86c88c496`. The two independent baseline
arms were accepted before post replay. CLI/support hashes are checked before and after final controls.

| Arm | Projects / successes | Native passes | Emitted images |
|---|---|---|---|
| Pre compiler, first emission | 75 / 73 | 2,177 | 94 |
| Pre compiler, second emission | 75 / 73 | 2,177 | 94 |
| Post compiler, same committed corpus | 75 / 73 | 2,177 | 94 |

Both comparisons have zero whole normalized PE, output-set or complete canonical outcome differences.
The same two systems templates decline with NL402 in every arm. No zero-test run counts as success.
`control-acceptance.json`, `compare-d-e.json`, `compare-d-f.json`, `coverage.json`, compiler manifests,
per-project logs and retained images contain the exact evidence. Normalization removes only the
existing nondeterministic PE fields; it does not replace full images with selected IL fragments.

## Independent controls and sensitivity

The complete final `columnar-emit-facts` source passes **99/99** under each compiler, including the
five existing parsed-input return/parameter/base/default phase controls. The complete external-base
project passes **3/3** under each compiler. Their complete outcomes, output sets, normalized images,
all **45 + 5 physical MethodImpl rows**, and literal override declarations match.
`final-controls-86c88c496073/verdict.json` identifies the exact sources and executions.

The new native source is SHA256 `0fe8491017d8dc73bef5b29ddc7e7f5edd32851af9fdebe234343868137f2856`.
Its rows 19–21 declare MemoryStream.Flush, Stream.Close and Compare on closed Comparer<int>.
The latter retains an open `!0, !0` MemberRef signature. CLR GetBaseDefinition returns the ultimate
Stream owner for Flush; physical metadata separately proves the selected nearer MemoryStream slot.
Root independently dumped the frozen baseline test image and compared all IL bytes with the worker
copy. `base-control-design.json` predates that inspection; `base-control-expectations.json` freezes
literal declarations and physical ordering before post replay.

Two controls prove comparison sensitivity. The Hello 42→43 IL mutation changes the predicted image
and stdout. An all-N# MemoryStream-derived fixture overrides Flush and Close; changing one byte in
Flush's MethodImpl.MethodBody column redirects its base-dispatched call to Close's body. Predicted
stdout changes from `flush-body / close-body` to `close-body / close-body`, with exit zero and empty
stderr in both runs. Its normal image and dispatch also match in exact pre/post compiler replay.
See `methodimpl-control/provenance.json` and `base-mutation-replay/verdict.json`. A preliminary explicit
Exception.get_Message override was declined by the existing analyzer (NL311); that rejected source
is retained and no admission was changed to make the fixture work.

## Canonical tests and diagnostic mapping

The combined final source passes **7,756/7,756** after forced test-enabled restore. This contains
both workers' seven-test additions; neither separate 7,749 result is represented as combined evidence.
Final product focused tests pass **12/12**. Root formatter checks pass for all eight changed N#
product, test and audit files. Receipts are `combined-estate/`, `root-format-receipt.json` and the
worker final handoff receipts.

Canonical controls cover actual ancestors, public/non-final/non-generic policy, null/out behavior,
signature outcomes, copied declarations, runtime and MLC bindings, readonly storage, foreign tables,
and independent companion corruption before any attachment. The dynamic AQN fixture first proves
same-signature selection, then independently rejects return-only and parameter-only assembly identity
mismatches. A closed builder first demonstrates GetMethods refusal, then proves caught lookup can
continue to Object.ToString. The raw-first/corrupt-base-second attachment test has a positive dispatch
twin; its negative leaves the earlier raw mapping unattached.

Outcome tests do not independently prove competing getter order. Source and compiled review cover
arity-before-return, left-to-right parameters and both AQN reads. No throwing BaseType getter fixture
is claimed. Descriptor construction adds open-definition, return-parameter and modifier reads after a
successful match; malformed reflected facts can fail at this new structural integrity boundary.
Required/optional modifier arrays preserve their separate order, not arbitrary mixed interleaving.

Strict checking examines **432 files / 259 errors / zero warnings or info** before and after. Both
compilers produce byte-identical JSON on the exact final source. Every baseline diagnostic maps to
an unchanged source line, with no changed diagnostic records. See
`strict-final-product/strict-comparison.json` and retained command/hash receipts.

Final immutable compiled review verifies **57/57 InitOnly fields** across the eight audited classes
and nine actual AsReadOnly callsites. The post BootstrapServices IL is byte-identical to the frozen
worker dump (SHA256 `88821d7216de2000d9cf53be10f08c4bfcf84492f60f68061f49f4d7a2554319`). The
accepted external-interface descriptor constructor remains identical after removing only RVA comment
lines. Final source, binary, matching-order and attachment/realization review is retained at
`/private/tmp/nsharp-s22f-review/immutable-post/README.md`.

## Ownership and checkpoint

The ordinary instance DefineMethod replay and projections leave C#. Base matching was already N#;
this slice derives and consumes its binding without claiming another lookup migration. The emitter
is **19,484 lines / 18,505 nonblank / 1,014,658 bytes**, a reduction of **1 / 1 / 38**. Its SHA256 is
`96bbdf8546f51f13f08a6f13b2dc116334f291d558b158f078170b1a080b7a5c`; ratchet fingerprint is
`text-v1:5ccfb6149c9a7727`, reviewed head `head-v1:8484731b27e8462d`. Audit passes **18/18**.
AddType remains **36 calls in 12 files, one keyed and 35 handle-only**. The eleven accepted iterator
row forwards remain; no new C# helper, policy branch or fallback is introduced.

Fresh backend checkpoint artifacts are recorded at `/private/tmp/gate-20260905-goal-s22f-r1/`.
Read its exact `source.json`, `gate.log`, `exit-code.txt` and final `acceptance.json` before treating
this documentation as gated or pushed. The gate receipt is external to the committed snapshot it
verifies. IDE behavior is unchanged by this backend slice.

The next contingent cut is the pure first-hit source-definition discovery family, revalidated from
`/private/tmp/nsharp-s22g-next-cut/README.md` after this checkpoint. Its coupled member-selection and
conversion-emitting constrained-call predicates remain separate prerequisites. Remaining type-pool
consumers, ambient locals and maxstack still precede S2.3–S2.6; terminal tasks 015/021/022/023 stay open.
