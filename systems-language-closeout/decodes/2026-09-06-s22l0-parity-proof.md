# S2.2(l0): catalog reference arrays — acceptance evidence

The existing N# element predicate now admits ordinary reference classes and interfaces through its
existing catalog identity check. The exact `Dictionary<string, Type>[]` entry-point input can be
declared and used by the SDK. This is a prerequisite to S2.2(l), whose complete C# owner remains.

## Revisions and source boundary

- Accepted predecessor: `31a0743d6f6f5f233c0e5e4c1def5eca1430540c`.
- Immutable product: `05187654eb2e045564adb71651efa0565e574f26`; Sol `30e8a5d5aff21396bf2e477e3bda39c23ca3444e`.
- Controls and fresh tested source: `71d489a5c6423a2cf78c8444dae36ee2e688c6fc`; Terra `f2c0317c4d8ba814c40c0046e1bc84a920af78ec`.
- Product-to-tested delta is exactly the two new `.tests.nl` files. The final documentation follow-up
  is verified by full tracked-tree comparison before the exact revision is pushed.
- C# and all 381 ratchet rows are unchanged. Emitter 18,923 lines /17,984 nonblank /985,534 bytes;
  AddType 36 /12 files /21 keyed /15 handle-only. This capability slice has zero C# reduction.

## Controls and preserved boundaries

The production change is the final `!IsValueType && IsSupportedCatalogType` branch after all prior
element cases and SZ-array recursion. The exact catalog lookup still rejects open definitions,
element shapes and builder-bound closures. Existing `List<int>`/`Queue<int>` limitation assertions are
intentionally positive; old value-type, rank-two, runtime pointer/byref/void and source-shape rules
remain. Four canonical controls cover Dictionary/Queue/interface, real foreign identity and
honest/forged TypeDelegator twins, runtime exclusions and builder/GP boundaries.

Two self-contained native controls declare the exact array parameter and return, allocate and
read/write/iterate it, retain array and dictionary identity, call the existing inferred Array.Fill,
and observe actual CLR IndexOutOfRangeException and NullReferenceException. The accepted-k compiler
refuses this byte-identical final source at `emit.declaration.function-param` before tests.
The root immutable candidate replay passes 111/111; the actual installed SDK fixture passes 2/2.
Direct explicit `Array.Empty<Dictionary<string,Type>>()` remains `emit.call.generic-unresolved`;
its failed source and receipt are retained separately and no generic-static fix is claimed.

Producer forced BootstrapServices estate 7,809/7,809 and new focused canonical 4/4 pass without skips.
The initial name-fragment command selected zero and is compile evidence only. The actual focused
launcher path is recorded by an explicit amendment; the final integrated gate independently executes
all 7,813 tests. An initial invalid TypeDelegator.MakeArrayType assumption was corrected, with the
failed draft retained. Native final source and artifact are linked by the root 111-test replay.

## Immutable regression proof and review

Proof root: `/private/tmp/nsharp-023-s22l0-proof-20260906`. Fixed corpus f543: 75 targets /73 successes /94 normalized whole images /
2,184 native passes per arm; zero image/set/outcome differences, same two NL402 template refusals.
Comparison SHA `bc34d5e694137456b4108194b310e6d24e6713204ead2787d9890a1115e8f47b`. Strict same-source raw stdout is byte-identical:
258 findings across 434 production files; comparison SHA `6b25c38e64d4a6d15d58622f39cd521e815c03bf5f6e9e76b96c91f44639fc27`.
The added test files are outside this production-source strict comparison and included in the gate.

The immutable source archive contains 1,829 regular files; compiler manifests retain 14 CLI and 77
support payloads. BootstrapServices whole IL equals the producer. Whole Compiler IL differs only
in a relocated static-data address label; normalization preserves its identical six data bytes.
Do not interpret that comparison as raw producer-byte equality or normalize semantic instructions.

- `/private/tmp/nsharp-s22l0-review/candidate/review.json` — SHA `8217712047f39043614dffabb9639d2f0b055b1bab764cdebedb950069265ca8`.
- `/private/tmp/nsharp-s22l0-review/immutable/review.json` — SHA `f8dfa87a096a61c718abf48fd6d7400b94764f10cf3d49c0a4dacba85de1d919`.
- `/private/tmp/nsharp-s22l0-review/controls-final/review.json` — SHA `8e3d9aae0c3730826a48a30201480b078024d41524c555ea57b312f199f5dc83`.

## Fresh gate and SDK publication

Gate: `/private/tmp/gate-20260906-goal-s22l0-r1/gate.log`; SHA `eb7d4a0c0224b62989c93ba8faa26ed25584db7510215438f6efcc92dcbb53cf`.
Fresh isolated `VSCODE_TESTS=skip ./scripts/test-all.sh --commit`, exit 0 in 450s:
593 unit /7813 canonical /111 declarations /7 Reflection.Emit /15 records /18 ownership,
52 native projects and 68 IL assemblies. This is emission/admission-only work; no analyzer/LSP or
editor behavior changed. k's accepted visual evidence is separate. Benchmark correctness passed;
front-end timing was unjudged under host load; no analysis/emission performance claim is made.

Only after the gate, the coordinator ran `setup-local.sh --skip-vscode --no-path-update`, verified
four package publications in both local feeds, matched all ten packaged tools to Release artifacts,
and compared all twelve SDK/tools entries against the actual live SDK cache before and after build.
The same-version cache retained four old DLLs; the narrow SDK-cache refresh preserved them before
restoring the new package. A minimal one-line SDK project builds the exact committed native fixture; diagnostic logs pin the actual NuGetSdkResolver
and EmitIlAssembly paths. Its two tests pass under the CLR and the compiled signature/array/Fill IL
is independently reviewed. Existing legacy validation is explicitly still enabled bootstrap debt.
The first scratch verifier read the retained Array.Empty diagnostic from stdout; the correction
checks its actual stderr and both stream hashes. The failed verifier and successful corrected run
are preserved under `seed-repin/`; no product, fixture or runtime invocation changed.

SDK package SHA `a9653d4673e949e9789cb8472c321d35bc0bbcedafe90a96706d6f3b10ec2647`; Compiler SHA `df9601b27117fa974cbafb0f2db33bbbd770ff007f78adf8763b518344d827a8`;
BootstrapServices SHA `441b4ee2bc47e3456debec8028a782a9698f666dd8388cba38562cc09970cc3b`.
Seed receipt: `/private/tmp/gate-20260906-goal-s22l0-r1/seed-repin/acceptance.json`;
SHA `3e4c4cefc79aa684641f00f4d415bd1ac41d1e412ee178295bac0ba17ece4606`. Actual installed seed probe source:
`tests/native/columnar-emit-facts/CatalogReferenceArrayEmitFacts.tests.nl`.

Gate diagnostics are archived and hash-verified before removing only the named disposable gate
copies. Immutable proof, failed attempts, published package snapshots, SDK probe and review receipts
are retained. Tasks 015/021/022/023 and the overall goal stay open. Resume the parked complete
entry-point cut against this verified capability; do not infer acceptance of its later body forms.
