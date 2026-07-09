# Track A — product-path closeout

**Live status:** decline diagnostics are complete, the full unit suite is green, and plain test
declarations plus assert/assert-throws execute. The fresh product gate and the complete promised
native-test grammar are not yet green. See [STATUS.md](STATUS.md) for the audited commit and the
in-flight range/index handoff.

This file contains only remaining work. The obsolete failure baseline, fixed test totals, Dogfood
paths, and handwritten-C#-emitter recipe were removed because they no longer describe the product
and would train an executor in the wrong direction.

## Mission

Close the product path without growing the owner that Track E must delete:

1. finish the current coherent range/index slice and sunset direct Track A edits to the C#
   emitter;
2. run a fresh product gate and turn every failure into a live, reproducible blocker;
3. finish the full documented native-test grammar and framework behavior through N# parser,
   policy, and lowering owners;
4. close the remaining dynamic example/template/fixture corpus through Track E's N# plan route;
5. record the first fresh green non-VS-Code product gate.

Track A is complete only at step 5. Unit green alone does not satisfy it.

## Current proof

- `ColumnarDeclineReasons.nl`, the trace glue, NL103 source attribution, env-var trace, tests, and
  docs landed in `18df2415e` through `465856bef`.
- Static parser-kernel binding and Dogfood deletion are complete; parser work is in
  `src/NSharpLang.Compiler.BootstrapServices/CompilerServices/ColumnarParserKernels.nl`.
- Assert and assert-throws landed in `9996d4525`; plain tests landed in `d34e7e6e7`.
- A detached-HEAD full unit run at `fb856ee46` had zero failures.
- Setup/teardown, table-driven `with`, skip, and complete xUnit/NUnit parity are still explicitly
  unmodeled. The last recorded full product gates predate the green unit baseline and were red.
- `ColumnarIlEmitter.cs` grew from 13,712 lines at the original snapshot to 21,497 committed
  lines. That temporary strategy ends with the working-tree slice named in `STATUS.md`.

## Standing harness

- Build/probe with the fresh in-repo CLI, never an installed `~/.nsharp/bin/nlc`.
- Inner loop: `./scripts/dev.sh Columnar`, `./scripts/dev.sh CompilationBackend`, and the smallest
  affected suite/pattern. Use `./scripts/dev.sh --since` for mixed shared changes.
- Every newly supported construct has an execute-and-assert test that reloads and runs the
  persisted assembly; compile-only evidence is insufficient.
- Emission mechanics run IL verification. Claims covering multiple receiver shapes test each
  advertised shape after persisted reload.
- Integration checkpoint: fresh `VSCODE_TESTS=skip ./scripts/test-all.sh --commit` from clean
  state. Discover examples/templates/fixtures dynamically; do not encode a count.
- If a Track A change becomes reachable from the IDE, apply the full IDE verification rule from
  `AGENTS.md`; track labels do not waive reachability.

## Remaining commit units

### A0 — finish the in-flight range/index slice

Keep the existing parser/emitter edits coherent, add focused execute-and-assert coverage for all
claimed array/string/span/range shapes, run the focused evidence, and commit only those files and
tests. Do not fold another corpus family into it. This commit is the final direct handwritten C#
lowering exception.

### A1 — fresh product-gate inventory

From A0's clean commit, run:

```bash
VSCODE_TESTS=skip ./scripts/test-all.sh --commit
```

If green, record the commit and continue to the promised test grammar audit before closing A. If
red, add each distinct failure to `STATUS.md` with its reproducer, deepest decline/fault, owning
N# layer, and dependency. Do not restore a historical baseline or use stash/`comm` comparisons.

### A2 — consume E0 plan/replay

Do not start another accept-set fix until Track E lands the N# code-plan model, mechanical
replayer, and first C#-arm deletion. Every later Track A lowering fix is plan-first:

1. model syntax in the consolidated N# parser and update the live node-kind ledger;
2. model semantic/binding facts in the relevant N# owner;
3. select opcodes, members, conversions, locals, labels, metadata, and diagnostics in N#;
4. let C# replay already-selected operations only;
5. delete any superseded feature-specific C# branch in the same commit.

When a BCL/Reflection.Emit capability is missing, C# may expose a data-only seed or mechanical
invocation. It may not add member-name/type/arity/overload policy.

### A3 — complete native-test grammar and framework parity

Revalidate the public grammar from the current parser/docs/tests. At minimum, finish:

- setup and teardown declarations;
- table-driven tests using `with` rows;
- skip reasons;
- unique stable method/display names across files;
- xUnit Fact/Theory/InlineData/Trait/Skip behavior;
- NUnit Test/TestCase/SetUp/TearDown behavior;
- synchronous and asynchronous lifecycle ordering;
- assert and assert-throws failure text and exit behavior.

N# owns recognition, test/lifecycle policy, names, framework selection, attribute/member choice,
and body lowering. A C# host may resolve or invoke an already-selected external reflection handle
only when that capability cannot live in N#; it contains no policy branch.

Evidence includes focused parser/emitter suites, `nlc test --json` on multi-file fixtures, the SDK
`dotnet test` route, a deliberately failing assert with exact surfaced text, table/skip cases, and
both framework configurations.

### A4 — dynamic corpus closeout

Run the gate's actual example/template/fixture discovery and work blockers by descending product
impact. One commit unit covers one coherent construct or one shared root cause. Each commit names:

- the N# production owner and live parser node/fact contract;
- the old C# branch deleted or why the touched C# is mechanical replay only;
- focused execute-and-assert evidence;
- which product-gate blockers it removes.

Do not fix unsupported syntax by editing examples unless the language contract rejects that
syntax deliberately and the user-facing docs already say so. Revalidate all former “intentional
decline” claims against current language docs, tests, and code; none survive merely because the
July 2 plan listed them.

### A5 — close the track

Run the full unit suite as breadth evidence, then a fresh
`VSCODE_TESTS=skip ./scripts/test-all.sh --commit`. Read the gate exit line and verify SDK install,
templates, dynamically discovered examples, IL verification, interop, and native tests. Update
`STATUS.md` with the exact green commit and mark A complete.

## Cross-track contracts

- E owns `ColumnarIlEmitter.cs` after A0. A supplies product blockers and parser/semantic needs;
  E supplies the plan-first lowering route.
- C owns syntax-diagnostic authority and parser recovery; A may add a construct to the shared
  parser only with C's live node/diagnostic contract.
- H consumes the complete native-test grammar and runner behavior; H owns test-estate migration,
  not missing language support.
- SDK repins and package/build-script changes are announced and gated from clean state.
- The consolidated parser kernel and shared fixtures are contended; one writer at a time and
  append-only test-project edits.

## Prohibitions

- No legacy emitter, fallback path, fault-to-decline conversion, C# AST materialization, or
  reparse-in-emitter route.
- No new feature-specific `ColumnarIlEmitter.cs` branch after A0.
- No fixed node-kind ordinal copied from an old plan; allocate from the live ledger.
- No compile-only claim for runtime semantics, persisted Reflection.Emit handles, generics,
  byref returns, records, patterns, or test discovery.
- No golden rebaseline, skipped/deleted/weakened test, or source rewrite merely to get green.
- No mega-commit spanning unrelated corpus families and no one-helper policy churn without a
  production owner deletion.

## Exit criteria

- [ ] Current product gate is fresh and green; no historical baseline mode remains.
- [ ] Complete promised native-test grammar works through both `nlc test` and SDK `dotnet test`,
      including lifecycle, table, skip, xUnit, NUnit, and deliberate failure probes.
- [ ] Every post-A0 coverage fix is N# plan-first and deletes/shrinks old C# ownership; no new
      feature-specific emitter/member-whitelist logic landed.
- [ ] Dynamic example/template/fixture corpus builds; runnable products run with asserted output;
      IL verification and interop gates are clean.
- [ ] Declines remain self-diagnosing with stable site ids and accurate per-file spans.
- [ ] Each commit is a coherent vertical slice with an `Evidence:` block and `STATUS.md` is
      updated with the final green commit.
