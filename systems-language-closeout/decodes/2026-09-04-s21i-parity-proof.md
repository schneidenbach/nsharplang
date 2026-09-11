# S2.1(i): method-override integration proof

Baseline compiler and fixed corpus: `69ad857ba5766ff546f285bf6571731f5dfc192f`.
Implementation compiler: `75fa5a77bc70e5d6c4302013c6002a499d465281`.
[Implementation and focused evidence](2026-09-04-s21i-method-override-rows.md).

The proof directory is `/private/tmp/nsharp-023-s21i-proof-20260904`. `run-prepost.py` archives
committed source for each compiler and corpus arm, builds the CLI and required support assemblies,
records hashes, and runs each corpus command from its own corpus root. The fixed archive SHA256 is
`5dd02b4612fdf5959ceb7ab0e622727d234d8d85373411abbbe155070ead7e74`.

## Comparison and controls

Independent baseline runs d/e compare **94 emitted images**, with zero normalized PE, output-set,
or project-outcome differences. Each arm contains **75 projects, 73 successful projects, and 2,145
passed native tests**, zero failed/skipped tests. The two unchanged failures are the systems CLI
and library templates, both exit 1 with NL402. `compare-d-e.json`, `control-coverage.json` and
per-arm manifests retain the completed control. Implementation arm f also passes 73/75 projects and 2,145 native tests. Both d/e and d/f compare
**94 images with IL_DIFFS=0, identical path sets and identical outcomes**. The final comparison
and per-arm coverage are retained in `compare-d-f.json` and `coverage.json`.

The unchanged normalizer zeroes PE timestamp/checksum, debug volatility and GUID heap. All method
bodies, metadata tables, strings and blobs remain, including MethodImpl rows and method attributes.
The comparison preserves physical metadata order as emitted. Physical iterator MethodImpl row order
is distinct from the host attachment-call order; neither is inferred from the other.

Two executed mutation controls establish sensitivity:

- The `Program.Hi` operand changes 42 to 43: one byte, one of 94 normalized images, and the
  predicted stdout line change. Both executions exit 0. See `nonvacuity.json`.
- An independent two-interface executable changes only MethodImpl row 1 MethodBody at PE offset
  1064 from `DistinctSlots.First` to `Second`. Exactly one raw and normalized byte changes;
  both programs exit 0 with empty stderr, while stdout changes from `11\n22\n` to `22\n22\n`.
  Method-body bytes and signatures remain unchanged. Prediction was written before mutation.
  Scripts, dumps, hashes and results are retained under `/private/tmp/nsharp-s21i-review`.

Independent admitted N# fixtures pass 10/10 on the baseline: five dispatch controls for inherited
and diamond source interfaces, closed generic interfaces, combined base/source slots, distinct
slots, and nongeneric iterator dispatch; five exact production return/parameter/base/default
precedence controls. The exact committed test sources also pass **10/10 on both compilers**,
with identical normalized PE, complete IL and all **13 physical MethodImpl rows/order**. The
original dispatch fixture separately passes 5/5 with the same metadata/IL equality. Both compiler
snapshots and exact source hashes were verified; test-result comparisons remove elapsed times
only. The independent review directory retains the final replay and source/assembly manifests.

## Ownership and source checks

The reviewed implementation removes all **14** C# DefineMethodOverride calls. Ordinary rows own
source selection, two MethodInfo equality sets, captured source names/signatures, flags, deferred
base-target validity and base → source → external application order. Iterator rows replace the
unconsumed MemberOverrides strings, retain canonical identity plus resolved handle, and supply
lookup names at the existing define → resolve → attach → body phase. Generic Current retains its
GetMethod("get_Current") lookup; nongeneric and async Current retain property lookup. The source
modifier helper reuses the existing Modifiers.Override enum value. No C# policy/helper is added.

The emitter decreases **20,714/19,703 → 20,688/19,677** total/nonblank lines. Focused evidence is
estate **7,676/7,676**, native declarations **76/76**, iterators **25/25**, and dev.sh Columnar
**12/12**. Ten new estate tests cover the records, exact flags, identity/deduplication and execution;
ten new native tests cover real dispatch and production failure precedence.

Strict source remains **425 files / 259 findings**. Raw pre/post compiler JSON on the same edited
source is identical. Versus the frozen baseline, only four ColumnarInputs rows move +11 lines:
NL202 124 → 135 and 224 → 235, plus their explanation lines; NL402 424 → 435 and 429 → 440.
No finding is added, removed or waived. Raw JSON and the exact mapping are retained under
`/private/tmp/nsharp-s21i-executor-logs`.

Pinned-SDK fixture probes explain the rejected draft spellings: typeof(void), IDisposable,
IEnumerator, IEnumerable and IList<int> decline; typeof(Type[]) works. Existing runtime-Type
helpers obtain the identical intended CLR types. Static helper arguments must be explicit, and
indexed field writes use a named local. The final estate tests invoke Complete directly; the
suspected custom-return limitation was not the cause and its reflection scaffolding was removed.
All rejected/admitted probe sources and logs are retained under
`/private/tmp/nsharp-s21i-review/type-spelling-evidence`.

The actual merged N# ownership audit observes `head-v1:dc4ce2dde3db9257`; both keys are repinned
to that value and the audit passes **18/18**. The emitter text fingerprint is
`text-v1:6d91ef39c2ffa861`. Epoch 381, path/fact fingerprints and every other file row remain
unchanged; no ceiling increases. The expected pre-repin OWN008 and the accepted final audit are
retained as `audit-observed-head.json` and `audit-repinned.json`. Root formatting passes.

## Integration checkpoint and remaining work

The fresh backend gate is recorded at `/private/tmp/gate-20260904-goal-s21i-r1/`: `source.json`
identifies its exact committed revision, `gate.log` records the fresh
`VSCODE_TESTS=skip ./scripts/test-all.sh --commit`, and `exit-code.txt` is the terminal verdict.
Read the actual terminal verdict before advancing or pushing; the ledger is not a gate verdict. This backend-only slice does not publish a bootstrap SDK.

Next is [S2.2 structural resolution](2026-09-04-s22-resolution-next-cut.md). The second metadata
writer, unified binding, emitter deletion, NativeAOT and the
terminal ownership/IDE audit remain open. This slice does not complete task 023 or the goal.
