# S2.1(h): P/Invoke integration proof

Baseline compiler and fixed corpus: `54faf94a77413bf22f5e9f3b667bcb4a7fb1659f`.
Implementation compiler: `0cde66a08bf725dfeddf9bbd053969e4b5b390ea`.
[Implementation and focused evidence](2026-09-04-s21h-pinvoke-rows.md).

The proof directory is `/private/tmp/nsharp-023-s21h-proof-20260904`. `run-prepost.py` archives
committed source for each compiler and each corpus arm, builds the CLI and required support
assemblies, records their hashes, and runs every command with its own corpus root as the working
directory. The live checkout is never the corpus working directory. No product source was
temporarily reverted and no missing dependency was treated as an accepted decline.

The fixed archive SHA256 is
`1a2b7f21948ac1e75d748801e55640c31e5f71dad71239a82f7325084bb82550`.
Arms d/e are independent baseline runs; f uses the implementation compiler on the same source.
Each sweep discovers all tracked project.yml files below examples/tests/templates, runs test
projects through `nlc test` and other projects through `nlc build`, and retains nested systems-proof
outputs. Compiler/framework/support copies are excluded from the emitted-assembly comparison.

## Comparison and controls

The completed baseline control compares **94 emitted assemblies**, with zero normalized PE,
missing/extra output or project-outcome differences. Each baseline arm has **75 projects**,
**73 successful projects**, and **2,138 passed native tests**, zero failed/skipped tests. The two
unchanged failures are the systems CLI/library templates, both exit 1 with NL402.

The implementation arm also passes **73/75 projects and 2,138 native tests**. Both d/e and d/f
compare **94 assemblies with IL_DIFFS=0, no missing/extra paths and no outcome differences**.
`compare-d-e.json`, `compare-d-f.json`, `coverage.json` and the per-arm manifests retain the result.

The unchanged `nl98_ilnorm.py` zeroes PE timestamps/checksum, debug volatility and the GUID heap.
Method bodies, metadata tables, strings and blobs remain in the comparison, including P/Invoke
ImplMap data, method implementation flags and parameter defaults. The test does not substitute
body-only equality for whole-PE equality.

Two controls establish that the comparison observes meaningful changes:

- The existing `Program.Hi` operand changes 42 → 43: exactly one byte, one of 94 normalized images,
  and the predicted stdout line change; both executions exit 0. `nonvacuity.json` records it.
- Proof26's native library string changes `c` → `x` at PE offset 1354: exactly that byte changes
  before and after normalization. Both import declarations now target x; the previously successful
  execution fails at `NativeMethods.Open` with `DllNotFoundException` naming x. Prediction, IL dumps
  and runtime output are retained under `/private/tmp/nsharp-s21h-review`.

The independent reviewer also runs the exact committed seven new native controls with both CLIs.
Both pass 7/7. They pin optional/out/default metadata, flags, missing managed body, a libc call,
precise return → parameter → native → default failure order, and a valid nonempty MZ output.
The final source hashes include the renamed metadata-only library. Earlier parser-only negative
probes and unsupported fixture spellings remain retained as rejected evidence.

Independent execution of fixed-corpus proofs 26 and 27 also matches pre/post: complete IL dumps
and normalized images are equal; exits, stdout and stderr match after isolated-path normalization.
Proof26 succeeds; proof27 retains its expected missing-fast_hash loader failure (SIGABRT/-6,
shell 134), with no marshalling failure. The review directory's `summary.json` and
`compare-final-proofs.py` retain the checked sources, manifests and full outcomes.

## Ownership and strict source

`ColumnarIlEmitter.cs` decreases **20,722/19,710 → 20,714/19,703** total/nonblank lines.
`ColumnarProgramInputBuilder.cs` stays **1,044/975** and loses nine bytes: one existing expression
calls the relocated N# helper. The native flag has one production literal, owned by
`ColumnarFunctionInput`; both old global helpers are deleted. No C# branch/helper/replayer is added.

The two observed text fingerprints are `text-v1:ff988483371488b9` (emitter) and
`text-v1:92134f7bec0baaed` (input builder). The actual N# audit reports the resulting head as
`head-v1:1a04757c9e9e81ad`; after repinning both keys, the merged audit passes **18/18**.
Epoch count 381, path fingerprint and fact fingerprint are unchanged; no ceiling increases.
`audit-observed-head.json` and `audit-repinned.json` retain those executions.

Strict checks retain **425 source files / 259 findings**. Both compilers produce identical result
arrays on current source. Four existing `ColumnarInputs.nl` rows move +9 lines, with the two
embedded explanation line numbers moving accordingly; no other result data changes.
`strict-source-shifts.json` verifies that exact mapping. The draft's new NL412 was removed by
relocating the shared helper, rather than waived. Self-hosting remains incomplete.

## Integration checkpoint and remaining work

The merged product/build source matches implementation commit `0cde66a0`; only integration
documentation and the two ownership-policy files differ. Root formatting is clean. Focused evidence
is estate **7,666/7,666**, native declaration suite **66/66**, focused estate **9/9**, and decline
tests **5/5**. The seven new native tests are separate from the fixed older corpus's 2,138 count.

The fresh backend gate is recorded at `/private/tmp/gate-20260904-goal-s21h-r1/`: `source.json`
identifies its exact committed revision, `gate.log` records the fresh
`VSCODE_TESTS=skip ./scripts/test-all.sh --commit`, and `exit-code.txt` is the terminal verdict.
Read that verdict before advancing or pushing. This backend-only slice introduces no IDE behavior
change and does not publish a new bootstrap SDK. The ledger is not a substitute for the gate log.

Next is [S2.1(i), override records](2026-09-04-s21i-overrides-next-cut.md). Shared parameter metadata,
S2.2 resolution, the second metadata writer, unified binding, emitter deletion, NativeAOT and the
terminal ownership/IDE audit remain open. P/Invoke row ownership alone does not complete task 023.
