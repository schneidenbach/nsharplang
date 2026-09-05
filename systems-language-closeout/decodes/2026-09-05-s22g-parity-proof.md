# S2.2(g): source-definition discovery integration proof

Accepted baseline/seed: `1e3d8cbfc130cad4528d98609e97492122f94d4c` (g1), with gate and live SDK receipts
under `/private/tmp/gate-20260905-goal-s22g1-r1/`. Product `770482e8e` cherry-picks worker `c2981db60`;
controls `de83c4197` cherry-picks `587bc935`; strict correction `096968ae7` cherry-picks `bafce7640`.
The final compiler source is `096968ae7a3a6bf95392c1881bac758b2f08bc18`.

## Source and ownership

`ColumnarSourceDefinitionResolver.nl`: 181 lines, SHA256
`2b569fdaa21d11594f5a41182901b869340a8a7170e543cdb284848d40ea57a9`.
Timing contracts: `b0f539d487ece5d706177779a4d581232479d5734cdaf80c9c93b39a52b517d8`.
Independent direct contracts: `8af155726bb9e0a0f3eb3135743520a6a440b09148d25a530e54a5842483f4a8`.
C# emitter: `55e1b81b86f7c9b2f71d2521e227d4f0056d4fa5475b0868512092748f3f6419`.

Three private C# definitions and their policy bodies disappear: TryResolveUserInterfaceDef,
TryResolveUserStructDef and TryFindDefByBuilder. Three remaining doors forward in one expression;
four interface sites call N# at their original phases and one inline field scan uses the same owner.
`discovery-census.json` independently measures 19,377 lines / 18,407 nonblank / 1,012,012 bytes, reductions 107/98/
2646. AddType remains 36 calls / 12 files / 1 keyed / 35 handle-only. The manifest and audit constant move from
`head-v1:8484731b27e8462d` to `head-v1:5605ce87ef5e4440` under the shrink-only rule; epoch values,
assertion ceilings, unrelated rows and file count remain unchanged. No callback/fallback is added.

## Immutable corpus and diagnostics

Evidence root: `/private/tmp/nsharp-023-s22g-seeded-proof-20260905/` (H below).
compiler-pre.json pins actual f543; compiler-prerequisite.json pins f243; compiler-post.json pins
initial de83; compiler-final.json pins corrected 096. All retain 14 CLI / 77 support payloads. Corrected
archive SHA256 `17b38b13fe326e11c6f50f903a510b8adb0596cf58fea515ca3087c970fffb12`, BSS
`03f37a243219a3154b31ed2699d1669503d55dbc5c791792467f9a4c424ed74b`.

Reuse accepted fixed-f543 pre/pre/prerequisite arms d/e/p. Initial discovery f and corrected discovery g
replay that same corpus: 75 targets, 73 successful projects, 94 emitted images, 2,184 native passes each, zero
failed/skipped. The two existing systems-template NL402 refusals match. compare-d-g/compare-p-g/
compare-f-g report zero whole normalized image, image-set or full-outcome differences; earlier d/e/p/f
receipts remain. The fixed declaration suite is 104 tests / 55 physical MethodImpl rows. The newly updated
105 source suite is separate. Whole-image comparisons retain physical metadata; nonvacuity.json and
the fresh methodimpl-control fixture detect the exact one-byte output/attachment changes.

Initial strict-discovery/rejection.json records 261 errors: 259 inherited plus two new empty-catch NL011
findings. The source was corrected, not rebaselined. strict-discovery-final/strict-comparison.json
records 433 checked files / 259 errors / zero warnings or info, same-source pre/final JSON byte equality and
unchanged-line mapping for every inherited finding. root-discovery-format-receipt.json pins final
source and audit formatting. No IDE behavior or identical runtime exception-stack trace is claimed.

## Direct evidence and sensitivity

Sol's receipt `/private/tmp/nsharp-s22g-executor-logs/handoff-receipt.json` records dev 12/12,
focused 7/7, estate 7,765/7,765 and native 105/105. The later strict-catch-fix/receipt.json records the
focused 7/7 and dev 12/12 on corrected source; the already proved broad runs were not repeated there.
Terra's `/private/tmp/nsharp-s22g-controls-logs/seeded-direct-discovery/final-receipt.json` records
focused 4/4 and estate 7,763/7,763 over its exact owner overlay. These are separate snapshots; combined
canonical evidence belongs to the fresh integration gate.

The generator-state draft observed the factory enumerable, but GetEnumerator creates a new machine.
The accepted wrapper returns a captured exact enumerator, so hit/miss/MoveNext-failure assertions
observe the consumed instance. Bounded N# emitted fixtures use actual generic Current and a distinct
nongeneric Current; throwing disposal pins forwarded struct out versus interface-local candidate.
An explicit false-MoveNext/throwing-Dispose test pins miss-clear-after-cleanup. Typed test runners catch
before publishing their out local so reflection's exceptional byref copyback cannot hide the result.

Actual old private helper witness: `/private/tmp/nsharp-s22g-controls-logs/legacy-dispose-witness/`.
Final source 7ea46918 and receipt 6e2f4300 pin immutable g1 generating payloads and 3/3 execution. The
owner-associated DynamicMethod calls the real private MethodInfo using an authoritative byref local,
catches inside the wrapper and returns normally through a shared frame. Normal hit/miss twins and
post-hit disposal distinguish struct hit/out from interface caller-sentinel. This does not claim a
baseline throwing-miss or closed-catch witness. Review is under
`/private/tmp/nsharp-s22g-review/seeded-discovery/legacy-out-on-throw-review/`.

`/private/tmp/nsharp-s22g-discovery-out-mutation/` freezes its prediction before adding only
`definition = null` at TryFind entry. Raw TRX has exactly 7 total / 5 pass / 2 fail: MoveNext failure and
throwing-disposal-on-miss both detect the premature clear; every other control stays green. The
TryFind body and test bytes are unchanged by the subsequent generic-catch correction. Actual source,
SDK/output hashes, commands and logs remain; review is under seeded-discovery/entry-clear-mutation.
This is a purposeful negative control, never a product change or waived failure.

## Review and checkpoint

Independent review snapshots are under `/private/tmp/nsharp-s22g-review/seeded-discovery/`:
first-compiled, final-source, immutable-post, strict-catch-fix, legacy-out-on-throw-review,
entry-clear-mutation and immutable-final. The corrected immutable review passes at 096968ae;
README SHA256 `95fbc2a20754dfbec7c30e498ada2ed606b5f4b7a572ee7fbb4e8ace1640b392`, linkage SHA256
`6b94a940267480e94c0ee913922602db97735d53558db58091528b80cd184e87`. It verifies 1,797 archived source
files and all 14 CLI / 77 support payloads. Only TryResolveStruct's two explicit catch exits change
semantic IL; every other body is identical after method-RVA comment normalization. Type equality,
generic Current and all enumeration/output/getter phases remain. The exact TryFind source/IL and
whole timing-test file match the frozen mutation originals. Root's final ownership audit passes 18/18.

The exclusive fresh `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` tested
`8b19a8ba17ba31e1c4d09dc94f72ab312b8f6a67` and passed in448s: 593 unit / 7,769 canonical / 105 native
declaration / 18 ownership tests, 52 native projects and 68 IL-verified assemblies. A verified
documentation-only follow-up is accepted and pushed as `2ce6915544ebd8e55faac47e5177d9788783c729`.
`/private/tmp/gate-20260905-goal-s22g-r1/acceptance.json` SHA256
`aeec9dbc809e19a78999a585e4aa12bef1910a1e80644623dde41d39cafbe0a0` records both revisions, exact
remote and diagnostic archive. Timing was unjudged under load; benchmark correctness passed.
The already accepted g1 SDK remains sufficient, with no additional repin. No terminal task
015/021/022/023 box changes. Remaining ownership and writer/universe/NativeAOT closeout stay open;
see the live STATUS for the successor slice.
