# S2.2(k): member-iterator ownership acceptance

The complete member-iterator discovery/admission owner is N#-owned at tested source
`137462ab1cf3898087304f6c4f524b4ea69bf478`. This is progress toward the active goal; tasks 015/021/022/023 remain open.
The next connected cut is [entry-point selection and wrapper realization](2026-09-06-s22l-entrypoint-next-cut.md).

## Source and ownership

| role | revision |
|---|---|
| accepted predecessor | `e64a17c847dfcf89eda86a675f1288ab3eb18683` |
| immutable predecessor compiler | `20caf6997c00757496c146fb143dc4ca11b76f2d` |
| initial member owner | `9dc7edc852c35536cdd56fe2985482a5387bc4f5` (Sol `ce23b618`) |
| measured ratchet | `5614eb20c039254da113d55a88825c3327f2b79e` |
| four canonical controls | `159dfab2f` (Terra `0d9f5ff5`), comment `7d579e98e` (Terra `32b8e18d`) |
| strict correction and combined tested source | `137462ab1cf3898087304f6c4f524b4ea69bf478` (Sol `ca520763`) |

`ColumnarIteratorRealization.EmitMember` receives the exact ten original inputs and owns async/static/
generic admission, live first-hit source discovery, public field and non-overloaded method facts,
shape analysis and sync realization. The remaining C# method only forwards and records the returned
ambient decline. C# changes by +6/−57 lines: **−51 lines /−51 nonblank /−3,115 bytes**, leaving
18,923 lines /17,984 nonblank /985,534 bytes. No other C# changes in this slice.

Compiled review pins both exact generic Current slots, two finally regions, first-hit disposal,
five live method Name reads, short-circuit field/method lookup, ordinal increments and the helper's
additional GetILGenerator timing. The outer caller already acquires an IL generator; that earlier
call is unchanged. Supported instance realization retains ordinal zero and five fresh snapshots.
The 67-byte C# forward retains the ten inputs and default decline spans −1/0. All eight previously
accepted realization methods remain identical after removing only disassembler RVA comments.

The strict correction adds one existing runtime-generic inheritance relation in N#:
`IReadOnlyList<T>` → `IEnumerable<T>`. Runtime-definition identity, arity and reference-only variance
checks are unchanged. Two raw typed acquisition helpers avoid an unsupported local spelling. A
22-byte nullable Count helper traps null at the original dereference phase with the default
NullReferenceException and otherwise calls concrete List.Count; it does not introduce interface
dispatch, fallback or a nonnull allocation. Type/message/disposal timing are controlled; stack traces
and allocation-failure behavior are not claimed equivalent.

## Executed evidence

- Forced Sol selection: **8/8**, including both new assignability/reference-pass tests and five
  existing iterator controls. Forced Terra selection: **4/4**, no skips. The new member controls
  exercise early refusal/static ordinal, first source row and disposal before field work, method
  disposal before shape, and repeated live Name/overload lookup. A positive Dispose repairs the
  actual selected canonical array before field access; the null-overload case raises the default
  NRE, disposes exactly once and leaves ordinal/synthesized state unchanged.
- The initial analyzer-control failure was localized before correction. A forged display name
  retained the target's real CLR definition, so full-owner identity correctly accepted it. Only
  that malformed-head assertion was moved to the classifier guard; both int→long and int→object
  value-variance negatives remain. The initial failed source, tagged output/TRX and recorded
  diagnostic source hash are retained.
- Fixed corpus `f54385d5d6b32efb0cb47e5761931bb63af707f4`: **75 targets /73 successes /94 normalized
  PE images /2,184 native passes per arm**, zero image, path-set or normalized outcome differences.
  The same two NL402 template refusals remain. This compares normalized whole PE images; `IL_DIFFS=0`
  is the harness's label, not a separate method-body-only comparison.
- Current native declarations: **109/109**, exact unchanged source and normalized candidate image
  equal to accepted j. Strict checking on identical final source: old compiler **260**, candidate
  **258**, removing exactly the two valid source-element acquisition NL202s. All 258 ordered
  accepted-baseline diagnostics map to unchanged source lines across 434 production files.
- AddType remains **36 sites /12 files /21 keyed /15 handle-only**, with all 15 iterator consumers
  and three lazy production contexts unchanged. All 381 ratchet epoch rows remain. Only the emitter
  current row shrinks; head `head-v1:70a30ce31ead17ba`, emitter `text-v1:3fb2d2f227bb2836`.
  The observed audit is 17/18 before repin and 18/18 after; final gate reruns 18/18.

The original 263-diagnostic source and immutable proof remain under
`/private/tmp/nsharp-023-s22k-proof-20260906/`. Initial source spellings that passed strict but did not
emit were not accepted. Corrected proof is under `/private/tmp/nsharp-023-s22k-proof-20260906-r2/`;
its `compiler-*.json` pins 14 CLI and 77 support files and the final source archive. The independent
`/private/tmp/nsharp-s22k-review/immutable-corrected/review.json` verifies all 1,825 archived source
files. Complete BSS IL is byte-identical to the corrected producer; complete Compiler IL matches
the previously reviewed, unchanged forwarding build.
Worker receipts and independent final controls are linked by `gate-result.json`.

## Product and editor verification

Fresh exclusive **VS Code-enabled** `./scripts/test-all.sh --commit` at the tested source passed in
**522s**: **593 unit /7,809 canonical /36 VS Code /109 native declarations /7 Reflection.Emit /
15 records /18 ownership**, 52 native projects and 68 IL-verified assemblies. No cached whole-gate
or per-step result is accepted. Benchmark correctness passed; front-end timing was unjudged because
of host load. The measurements are retained in `gate-result.json`; they make no analysis/emission
performance claim.

The extension was rebuilt and reinstalled as nsharp.nsharp 0.6.0. Installed LanguageServer, Compiler
and BSS hashes match the fresh package. Server pid 74118 was the child of plugin host 74106 after
reinstall. In the real editor, the valid source `IReadOnlyList<Item>` argument had no diagnostic,
while `IReadOnlyList<int>` retained NL202 on the exact line-15 argument. Clicking the Problems row
selected that argument. Removing the invalid function cleared the workspace to **No problems**.

Evidence: `/private/tmp/nsharp-023-s22k-proof-20260906-r2/ide/visual-verification.json`,
`negative.png`, `positive.png` and their AX states. The matching CLI probe proves old/new counts
2→1 with the negative present and 1→0 with only the valid source. The first primitive-string probe
was nondiscriminating because the old CLR metadata path already accepted it; that failed probe
assumption is retained separately, not presented as the new conversion proof.

All 12 live j1 SDK payload entries remain unchanged before/after verification. No new seed was
required. Legacy validation and the remaining emitter/type-universe/AOT work remain deletion debt.
Gate source, complete output, diagnostic archive and seed continuity are retained at
`/private/tmp/gate-20260906-goal-s22k-r1/`. The final Markdown-only follow-up is compared to this
exact tested source and reviewed before push; `acceptance.json` records the verified remote revision.
