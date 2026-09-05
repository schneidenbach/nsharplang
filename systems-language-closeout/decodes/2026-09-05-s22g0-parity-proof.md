# S2.2(g0): enumerator storage prerequisite — integration proof

Product `504946215e709b2c45c7a6ae5a442522f6f63e78` integrates worker
`1a2f178943d13b3882b718eae72a601c4de8bde6`. Baseline-compatible discovery controls are
`958bffd63` (worker `b3e3ba266`). The accepted predecessor is
`70a84bc7270c98bbbbd2f33a56b2af1c464242ec`.

The storage prerequisite is implemented at the product commit. Source-definition discovery ownership
has not moved: its C# definitions, routing and census remain byte-identical to the predecessor.
The compiler services need a verified SDK seed containing this prerequisite before consuming the
new source-element enumerator local. The coordinator's gate and seed receipts below govern that
transition; the parked discovery draft is not accepted product code.

## Product boundary

`ColumnarTypeOfPlanner.IsSupportedType` admits the genuine closed BCL `IEnumerator<T>` in its
builder-bound storage branch, after all previously successful families. Its sole element must pass
the existing collection-element policy. Exact assembly-qualified identity rejects a baked foreign
namesake. `IsSupportedCollectionType` and `IsAdmissibleCollectionElement` retain their old bodies.
The new storage rule does not admit enumerators as collection expressions or `for` sources.

The old SDK declined both tested `typeof(IEnumerator<int>)` initializer spellings in this kernel.
The accepted spelling uses one required-definition `Type.GetType` lookup, matching existing kernel
patterns. That N# runtime lookup remains debt for the open metadata-universe closeout. The
[implementation decode](2026-09-05-s22g0-enumerator-protocol-storage.md) records the exact source,
rejected spellings and focused evidence.

## Fixed-corpus comparison

All evidence is retained under `/private/tmp/nsharp-023-s22g-proof-20260905/`.
`run-prepost.py` builds the committed predecessor and executes the same committed 75-project corpus
twice, as arms d/e. `run-prerequisite.py` builds committed `504946215` into the separate immutable
prerequisite compiler and executes that same predecessor corpus as arm p. Each compiler has 14 CLI
and 77 support files recorded by SHA-256. The source archive and repo-shaped support copies preserve
CLI subprocess discovery; copied dependencies are classified separately from N#-emitted images.

| Evidence | Result |
|---|---|
| `compare-d-e.json` / `compare-d-p.json` | 94 whole normalized PE images equal; no output-set or full-outcome differences |
| `prerequisite-coverage.json` | 75 targets, 73 successful projects, 2,179 native passes in every arm |
| Existing template refusals | The same two systems templates decline with NL402 in every arm |
| `strict-prerequisite/strict-comparison.json` | 432 files; 259 errors, zero warnings/info; same final-source JSON byte-equal; all baseline findings map to unchanged lines; changes empty |
| `prerequisite-census.json` | Emitter 19,484 lines / 18,505 nonblank / 1,014,658 bytes, unchanged |
| Ownership and formatting | Audit 18/18; four changed N# files format cleanly; no C# changes or ratchet repin |

The whole-PE normalization is defined in `nl98_ilnorm.py`; output normalization removes only the
recorded roots, elapsed-time text and terminal formatting. Complete project outcomes and original
images are retained. A one-byte Hello constant control changes the predicted image and stdout.

## New capability and independent discovery controls

`prerequisite-native/verdict.json` links the root's exact immutable generating compiler to two
separate observations:

- Identical `ProtocolRow` source is refused by the predecessor at `emit.local.unsupported-type`,
  before any test runs, and passes 1/1 with the prerequisite compiler. Root inspected the emitted
  `IEnumerator<ProtocolRow>` local and exact generic `get_Current`, with acquisition before the
  protected region and `Dispose` in `finally`. Source SHA-256 is
  `6929fb095e5487af21da226ba3d71249e13fc69500a476a7a7dc5e1e0965ec79`.
- The baseline-compatible discovery project passes 103/103 on both compilers. Its whole normalized
  image, complete outcome and all 48 physical MethodImpl rows match. The compatible project sources
  are frozen separately from the deliberately new protocol-storage test. The committed native suite
  includes that additional durable test; the fresh gate must execute the combined suite.

The original source-only prediction was 47 MethodImpl rows. The actual pre image has 48: the new
`SourceDiscoveryMarkerValue.Mark` also structurally implements the pre-existing `ConstraintMarker`.
Accepted emitter lines 3268–3306 inspect every source interface; both require `Mark():int`. The
prediction is preserved in `discovery-control-design.json`, and the measured literal declarations
and rows are frozen in `discovery-control-expectations.json`. No source or test was changed to hide
the extra row.

The narrow closed-interface sensitivity fixture under `methodimpl-control/` produces 41/42 through
`ISourceSlots<int>.First/Second`. Changing only the First row's MethodImpl.MethodBody byte at offset
1294 to the Second body produces 42/42. Both executions exit 0 with empty stderr, and the normalized
image comparison detects exactly that byte. This tests resulting attachment sensitivity; it does
not independently mutate source-discovery policy or prove exceptional out-slot timing.

Terra's external legacy fixture passes 2/2 against the frozen pre compiler and pins first-hit order,
normal out clearing, closed-head discovery and class-before-interface refusal. It has no canonical
fallback or product dependency. Its handoff, including the unexecuted direct N# draft, is
`/private/tmp/nsharp-s22g-controls-logs/handoff/s22g-controls-handoff.json`.

## Review, checkpoint and next owner

Astra's definitive review is
`/private/tmp/nsharp-s22g-review/seed-immutable-prerequisite/README.md`. It verifies committed
worker/root/archive source identity, all 14/77 compiler files and the emitted predicate ordering,
identity test and element-policy call. Focused worker evidence is dev 12/12, canonical estate
7,757/7,757 after test-enabled restore, and the selected native protocol test 1/1. These do not
substitute for the coordinator's fresh product gate.

The exclusive fresh backend gate is `/private/tmp/gate-20260905-goal-s22g0-r1/`.
`source.json`, `gate.log`, `exit-code.txt` and final `acceptance.json` identify the exact committed
source and actual verdict. After it passes, the coordinator runs `setup-local.sh --skip-vscode
--no-path-update` from that clean committed source. The seed command, package provenance and an
SDK-built source-element probe belong in `seed-repin/` under the same gate directory. Require those
actual receipts before resuming the discovery owner. No IDE behavior change is part of g0.

Resume S2.2(g) using the inferred exact typed enumerator with explicit `try/finally`, not the
rejected covariance, generic-helper or bare-`for` drafts. GetEnumerator remains outside the protected
lifetime. A hit writes the out slot before disposal; a completed miss clears it after disposal.
Closed-receiver argument reads and assignments remain inside the winning loop before disposal.
Struct resolution forwards its caller slot; interface resolution uses a local candidate. The four
discovery call phases and the later structural-binding phase remain distinct. General-call admission,
remaining type-pool consumers, locals/maxstack, the metadata writer and terminal tasks remain open.
