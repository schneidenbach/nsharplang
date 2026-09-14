# S2.2(a) integration proof

Baseline/compiler/corpus revision: `665b1068ad6905b4de3fc98efdf6f404e454c525`.
Implementation and post compiler: `77686382de9eff2ba61524b91e24fccf2425fad2`.
The implementation is merged by fast-forward into `systems-language`. Astra planned and reviewed;
Sol integrated the executor changes, and Terra implemented the canonical resolver and identity tests.
See the [implementation record](2026-09-04-s22a-canonical-structural-resolution.md).

## Ownership and consumed identity

Thirteen C# resolver/helper definitions are deleted and existing callers invoke the N# owner directly.
`ColumnarIlEmitter.cs` shrinks from **20,688 / 19,677** total/nonblank lines to
**19,629 / 18,637**, a reduction of **1,059 / 1,040**. No new C# helper, policy branch,
adapter, callback or fallback is added. The separate existing loaded-assembly probe remains debt.

Canonical and exact resolution retain structural identity and the selected runtime companion.
The emission-scoped table is explicitly carried to the existing `typeof` planner; its selected row
passes through `AddType` and is validated before `ldtoken` execution. Pool validation precedes both
IL emission and local allocation. Source, synthesized and generic owners remain distinct across
emissions; erased string enums retain provenance beside their shared primitive signature key.

The corrected baseline pool census is **36 actual calls in 12 files**: after this slice, one is
keyed and **35** remain handle-only, including the internal plan-local-mirror append. The initial
37/13 name search included an unrelated extension-index helper; counting only qualified calls then
missed the internal append. Both original baseline revisions and the committed implementation were
recounted. The complete rows are in `addtype-reconciled-census.json` and the three-revision check is
`addtype-historical-census.json` under the evidence root below.

## Fixed corpus, controls first

Evidence root: `/private/tmp/nsharp-023-s22a-proof-20260904/`.
`run-prepost.py`, `nl98_ilnorm.py`, `nonvacuity.py` and `validate-arms.py` are retained there.
Each arm uses a fresh archive of the same committed corpus, its own CLI/support snapshot and its
own corpus root as the command working directory. Output paths are preserved; assembly files are
not flattened. Compiler manifests retain all fourteen CLI files and the supporting build outputs.

| Arm | Projects | Successful projects | Emitted images | Native tests |
|---|---:|---:|---:|---:|
| d: baseline control | 75 | 73 | 94 | 2,155 passed; zero failed/skipped |
| e: baseline repeat | 75 | 73 | 94 | 2,155 passed; zero failed/skipped |
| f: committed post compiler | 75 | 73 | 94 | 2,155 passed; zero failed/skipped |

**Both d/e and d/f compare all 94 images with zero normalized whole-PE differences, zero
output-set differences and zero project-outcome differences.** The two unchanged expected failures
are the `nsharp-systems-cli` and `nsharp-systems-lib` template NL402 declines. Complete raw output,
hash manifests, normalization details and coverage are retained in `out/`, `compare-d-e.json`,
`compare-d-f.json`, `control-coverage.json`, `coverage.json`, `control.log` and `post.log`.

The control-first live byte mutation changes the predicted one of 94 images and its stdout
(`42` to `43`), leaving exit status and stderr unchanged. Its source, changed image, comparisons
and result are retained in `nonvacuity.json` and the associated artifacts. This establishes that
the image/outcome comparison can detect a real changed result.

## Exact new controls and strict source

`final-controls-77686382de9e/` retains the exact input sources, commands, raw streams, emitted files,
compiler hashes before and after execution, and the final verdict. Both immutable compilers pass:

- **81 literal resolver cases** in ten tests: eleven canonical bool/out/throw contracts and
  seventy builtin/exception/miss contracts, including YAML and false-null behavior.
- **Three production signature/typeof tests**, with expected runtime identities obtained from
  constructed values independently of the selected type expressions.
- **One collection-shadowing test**, using a separate repository/CLI skeleton for each arm so the
  baseline test cannot accidentally launch the changed child compiler.

All fourteen tests pass per arm. Their emitted output sets and normalized images match.
The fixed corpus separately exercises the existing 38-shape `typeof` matrix.

The baseline strict source has 425 files and 259 existing findings. Both immutable compilers check
the same final edited source and return byte-identical JSON: **427 files, 259 errors, zero warnings,
expected exit 1**, with empty stderr. JSON SHA256:
`ed9b29010436aab6fb59b04f41930eaee386fed09117c791dc0907c582cecfe8`.
Every finding maps to its existing site. Twenty-six findings shift lines across BindingScope (12),
CodePlanExecutor (7), SemanticTypeRegistry (6) and TypeOfPlanner (1); three BindingScope NL412
explanations also contain the shifted line number. The two RangeIndexPlanner NL402 rows at lines
19 and 91 reflect the explicit trailing `null`
argument and corresponding 26→27 / 25→26 arities. Their full snippets and hint changes are retained
in `strict-comparison.json`.

The first analysis script incorrectly required those two edited source lines to belong to an
unchanged-line mapping. Its failure is retained in `final-controls.log`. The corrected analysis
verifies the exact trailing-argument edits and unchanged finding locations; it reuses the original
hash-checked execution receipts instead of rerunning or altering test outputs. The intermediate
overbroad NL402 predicate and its narrowed correction are also retained in the two
`final-controls-resumed-analysis*.log` files. The final analysis exits zero with `FINAL_CONTROLS=PASS`.

## Focused verification and review

The final formatted implementation passes **7,703 estate tests**, **12 focused Columnar unit tests**,
**79 native declaration tests**, **25 iterator tests**, and the collection-shadowing control.
The exact 79-test declaration project also passes under the baseline CLI. Logs, rejected fixture
spellings and source/artifact hashes are retained in `/private/tmp/nsharp-s22a-executor-logs/`;
`final-focused-receipt.json` identifies the final run set.

Read-only review receipts are in `/private/tmp/nsharp-s22a-review/final-review/`. Three formatter
deltas have exact lexical comparisons that retain literal contents and operator boundaries.
The pool's pre-format bytes were unavailable; no fourth lexical comparison is claimed. Its
assertions were reviewed before and after formatting and execute in the final 7,703-test result.
The persisted generic-parameter witness uses the installed runtime's public VAR/MVAR flags rather
than its null declaring-method property. All concrete review findings were fixed before commit.

The merged CLI rebuild passes with zero warnings/errors. The observed emitter fingerprint is
`text-v1:f9425feced0ba906`; the reviewed manifest/policy head is
`head-v1:0693c72e2dad21ec`. Both keys are repinned from the actual merged tree without increasing
a ceiling or changing the epoch/path set. The merged ownership audit passes **18/18**; receipts
are `ratchet-before.json`, `ratchet-after.json`, `root-cli.log` and `root-ownership-audit.log`.

## Fresh gate boundary

The fresh backend integration checkpoint is recorded outside the committed source at
`/private/tmp/gate-20260904-goal-s22a-r1/`. Its `source.json` identifies the exact archived commit;
`gate.log` and `exit-code.txt` carry the actual verdict. `acceptance.json` is written only after
successful verification and an exact-SHA push. This document does not substitute for that result.
All implementation agents are paused with clean committed worktrees; the gate uses
`VSCODE_TESTS=skip ./scripts/test-all.sh --commit` with fresh steps.

This is S2.2(a), not completion of S2.2 or task 023. Remaining type consumers, structural member and
override descriptors, ambient-local slots and retained maxstack precede the writer stages.
Tasks 015, 021, 022 and 023 remain unchecked, and the overall goal remains active.
