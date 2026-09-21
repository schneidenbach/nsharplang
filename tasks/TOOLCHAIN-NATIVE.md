# Managed toolchain conversion and census closeout

## Census wave 14 — current status (2026-09-20)

Wave 14 is integrated, **pushed, gated and reseeded** through `977d336cf` on `census/merge`, which
equals `origin/systems-language`. The push happened on 2026-09-20. Nineteen commits sit between the
wave-13 docs tip `ec3bb3050` and `977d336cf`: nine compiler-blocker fixes, four CLI owner
conversions, two LanguageServer slices covering nine handlers, one glue-assertion slice, one IVT
fixture re-point, one async-iterator completion-race fix, and the seed republication itself. The
integration checkout is clean.

**This is not a completion record.** The managed-toolchain conversion objective this file was opened
for is NOT finished. **932 lines of CLI C# and 5,738 lines of LanguageServer C# remain**, plus 861 in
Runtime and 71 in Playground.Wasm. The rendered visual IDE proof is **still owed** — the extension
reload finally SUCCEEDED this round, which removes the excuse but not the debt. Two decisions are
**open and belong to the user**, and one of them (the test-runner host) is what the last of the CLI
conversion is blocked on. Do not read the accepted gate pair below as a complete production
migration.

### Status of the required sequence at a glance (2026-09-20, wave 14)

| Step | State | Where the receipt is |
|---|---|---|
| CLI owner conversion | **PARTIAL** — 4 more owners moved; **blocked on a user decision**, not a compiler gap | `3195323f8`, `c8484368a`, `c61df0392` |
| LanguageServer owner conversion | **PARTIAL** — nine handlers reduced to protocol glue | `f250f9773`, `fec639eb5` |
| Compiler blockers, rounds 2–3 | **9 landed**; the LS2 BLOCK-1 diagnosis was corrected | `7336b2d48` … `77215f1fe` |
| Async-iterator completion race | **FIXED** (pre-existing, not a regression) | `ebaf2eb1d` |
| Playground / Runtime / Wasm-hosting conversion | **NOT STARTED** | — |
| Gates at `23c6c650e` | non-VS **FAILED** (cross-lane fixture break) | `evidence/combined-23c6c650e/` |
| Gates at `11197708d` | non-VS **PASS**, VS **FAILED** (the async race) | `evidence/combined-11197708d/` |
| Gates at `ebaf2eb1d` | **both PASS** | `evidence/combined-ebaf2eb1d/` |
| Second real reseed, at packed source `ebaf2eb1d` | **SUCCESS on the first try** | `evidence/reseed-ebaf2eb1d/reseed.log` |
| Gates on the seed commit `977d336cf` | **both PASS** | `evidence/seed-977d336cf/` |
| Push to `origin/systems-language` | DONE 2026-09-20 | `977d336cf` |
| Extension reload | **SUCCEEDED** | `evidence/seed-977d336cf/reload-extension.log` |
| Rendered visual IDE proof | **STILL OWED** | nothing rendered has ever been observed |
| Converter census at the new seed | **DONE** | `evidence/seed-977d336cf/converter/RECEIPT.md` |

### CLI — lane 4: four more owners moved, `Program.cs` down to 163 lines

| Commit | Owner moved | C# deleted / shrunk | N# added |
|---|---|---|---|
| `3195323f8` | daemon server and `nlc daemon` | `Daemon/DaemonServer.cs` (632) + `Commands/DaemonCommand.cs` (96), both **deleted** | `DaemonServer.nl` (760), `DaemonCommand.nl` (91) |
| `c8484368a` | `nlc query` | `Commands/QueryCommand.cs` (1,081), **deleted** | `QueryCommand.nl` (1,401) |
| `c61df0392` | `build`, `run`, `publish`, `new`, `format` | `Program.cs` **757 → 163** | `ProgramCommands.nl` (592) |
| `b5429fe99` | (enabling) a perf fact's path read from `filePath` | — | `OutputFormatterJsonKernels.nl` |

All four N# owners land in `src/NSharpLang.Compiler`, not in the Cli project — which is why the
`CS0436` duplicate-`Program` warnings persist (below).

**Remaining CLI C# — 932 lines in 3 files**, measured at `977d336cf` with
`find src/NSharpLang.Cli -name '*.cs' -not -path '*/obj/*' -not -path '*/bin/*' | xargs wc -l`:

| File | Lines |
|---|---:|
| `Program.Testing.cs` | 614 |
| `Program.cs` | 163 |
| `Commands/WatchCommand.cs` | 155 |

**What is left is blocked on an architecture decision, not on a compiler defect.** `c61df0392`'s
own message states the chain precisely: `Program.Testing.cs` holds the xunit and reflection test
runners; `Compiler.csproj` does not and must not reference xunit, and `NativeTestLoadContext`
derives from `AssemblyLoadContext`. `Execute` (the command-number switch) cannot move while
`nlc test` is C#, because it dispatches to it; `WatchCommand.cs` re-enters `Program.Execute`, so it
can only move after `Execute` does; and `GetVersion` must keep reading `Cli.dll`'s assembly or
`nlc --version` starts lying. **See "Open decisions for the user" below — nothing further moves in
the CLI lane until that is answered.**

### CLI — lane 5: the test runner, the dispatch pipeline and `nlc watch`, on `census/testhost`

The decision below (open decision 1) was answered **option B** and implemented. `src/NSharpLang.Cli`
is now **one file, 25 lines**.

| Commit | Owner moved | C# deleted / shrunk | N# added |
|---|---|---|---|
| `79e706f31` | the whole `nlc test` runner: discovery, load-context isolation, the xunit front controller and sinks, filters, result shapes, exit codes | `Program.Testing.cs` (614), **deleted**; `Program.cs` 163 → 74 | `src/NSharpLang.TestHost/` — `TestCommandHost.nl`, `XunitTestRunner.nl`, `ReflectionTestRunner.nl`, `NativeTestLoadContext.nl` |
| `07e1dca0f` | the 26-arm dispatch pipeline and `nlc watch` | `Commands/WatchCommand.cs` (155), **deleted**; `Program.cs` 74 → **25** | `CliPipeline.nl`, `WatchCommandHost.nl` |

**`NSharpLang.TestHost` is a new N#-SDK library** (`project.yml` + a one-line csproj) that references
`NSharpLang.Compiler` and `nuget: xunit.runner.utility 2.9.2`. `Cli.csproj` gains one
`ProjectReference` and loses its own xunit `PackageReference`; `Compiler.dll`, the SDK `tools/`
payload, the LanguageServer publish and the wasm trim graph are all untouched. `dotnet pack` of the
tool package gains exactly four files (`NSharpLang.TestHost.dll` and its three siblings) and loses
nothing — no SDK nupkg, template or `dotnet new` change.

**`GetVersion` stayed in C# and the version is now a PARAMETER.** `nlc --version` and the help header
must report `Cli.dll`'s own `AssemblyInformationalVersion` — the gate greps it for provenance — and
`typeof(Program).Assembly` is the only spelling that names `Cli.dll` from inside it. `Main` reads it
once and hands it to `CliPipeline.Execute`, which carries it into a watched re-entry.

**What is left in `src/NSharpLang.Cli`:** `Main` (two lines) and `GetVersion`. Removing even that is
open decision 2 plus the three missing project.yml keys.

**Seed-compiled, so two shapes are routed around.** An N#-SDK project is compiled by the COMMITTED
seed (`977d336cf`), not by HEAD, so the fixes at `4d4f8b8a6` (writing a referenced assembly's
`Nullable<T>` property) and `910218d2d` (reading `AggregateException.InnerExceptions`) are not
available yet. Each route carries a `// SEED: simplify after next reseed (<sha>)` marker naming its
commit; both collapse back to the direct spelling at the next reseed. A THIRD shape is open at the
tip as well and is filed as blocker 28 in `census-briefs/CLI2-COMPILER-BLOCKERS.md`: an `object`
holding a `ValueTask` cannot be reached at emit by any spelling, so `ValueTask.AsTask` is invoked
reflectively.

**Verification.** An 87-case byte-compare matrix over `nlc test` and the whole dispatch surface is
byte-identical in stdout, stderr and exit code against a CLI built from `f0da9f94f`. Full native
sweep **113 projects / 4,651 passed / 0 failed / 1 skipped**, differing from the same sweep run with
the baseline CLI in exactly the two projects this lane changed. Estate **9,455 / 0**.
`cli-command-contracts` 205 → **213** (eight new rows, all on the reflection route, which had none);
ownership audit **25/25**, head `head-v2:028b60d62c4de883`. 220 repeated `nlc test` processes on each
route under CPU contention: 0 failures, 0 hangs. 60 runs of the reflection route inside ONE host
process: 8 MB RSS growth after warm-up against the baseline's 12 MB, so nothing stopped unloading.
`NSharpLang.TestHost.dll` passes IL verification.

### LanguageServer — lane 3: nine handlers reduced to protocol glue

`f250f9773` moved seven handlers' decisions into N# `Editor*Facts` owners, `fec639eb5` moved two
more, and `23c6c650e` added the glue-level assertions that estate rows structurally cannot reach.

| Handler | C# lines | N# owner |
|---|---|---|
| on-type formatting | 221 → 85 | `EditorOnTypeFormattingFacts` |
| document link | 186 → 77 | `EditorDocumentLinkFacts` |
| go to implementation | 272 → 104 | `EditorImplementationFacts` |
| document symbol | 262 → 99 | `EditorDocumentSymbolFacts` |
| inlay hint | 373 → 81 | `EditorInlayHintFacts` |
| type hierarchy | 402 → 231 | `EditorTypeHierarchyFacts` |
| selection range | 552 → 79 | `EditorSelectionRangeFacts` |
| call hierarchy | 734 → 399 | `EditorCallHierarchyFacts` |
| semantic tokens | 842 → 260 | `EditorSemanticTokenFacts` |

Two findings were **recorded rather than papered over**: the inlay hint's type text really is
nullable (the C# declared `string` while returning it), so the owner says `string?`; and the
selection-range walk threaded a target COLUMN through every frame into a containment test no caller
ever supplied a column to — it is gone, with a row saying the answer does not depend on it. The
call-hierarchy outgoing walk's reach is **partial and always was** (a `for` header, a `try`, a
`switch`, a `using` and a `lock` are not searched); that is now an asserted row rather than a gap
someone has to rediscover.

`23c6c650e` also bound seven inline nullable dereferences in estate files to locals and asserted
them non-null, taking the compiler's own front door **back to 1,340 exactly** after those seven
`NL905`s had counted against it.

**Remaining LanguageServer C# — 5,738 lines in 31 files** (from 8,167; the file count is unchanged
because every handler still owns its OmniSharp wire mapping). Largest survivors, measured at
`977d336cf`: `Services/DocumentManager.cs` 1,449 · `Handlers/CompletionHandler.cs` 620 ·
`Handlers/CallHierarchyHandler.cs` 399 · `Handlers/SemanticTokensHandler.cs` 260 ·
`Handlers/TypeHierarchyHandler.cs` 231 · `Handlers/CodeActionHandler.cs` 217.

### Remaining production C# per project, measured at `977d336cf`

`find <project> -name '*.cs' -not -path '*/obj/*' -not -path '*/bin/*' | xargs wc -l`:

| Project | C# lines | Files | at `d57586f54` |
|---|---:|---:|---|
| `src/NSharpLang.LanguageServer` | **5,738** | 31 | 8,167 / 31 |
| `src/NSharpLang.Cli` | **932** | 3 | 3,335 / 6 |
| `src/NSharpLang.Runtime` | 861 | 4 | 861 / 4 |
| `src/NSharpLang.Playground.Wasm` | 71 | 2 | 71 / 2 |
| `src/NSharpLang.Playground` | 0 | 0 | 0 |
| `src/NSharpLang.Compiler`, `.Compiler.Core`, `.Build.Tasks`, `.Sdk` | 0 | 0 | 0 |

### Compiler blocker fixes taken on merge — rounds 2 and 3

Nine landed. Each carries its own native regression project or extends an existing one.

| Commit | What it fixed |
|---|---|
| `7336b2d48` | a `catch` clause's exception type is resolved **in the compilation's own type universe**, so a type not in the core assembly no longer declines (CLI2 defect 5). New `tests/native/census-catch-types` (10 rows) |
| `ff9c7351c` | **`Process`'s whole instance surface** is read, and a struct's defaulted optional is filled (CLI2 defect 7, `Process.MainModule`). New `tests/native/census-process-members` (8 rows) |
| `a249df6c2` | an **inherited interface member through a source-typed generic receiver** resolves. New `tests/native/census-source-typed-generic-receiver` (6 rows) |
| `22844df87` | **`System.IO.Pipelines`** added to the one common-assembly table (LS2 BLOCK-3). New `tests/native/census-pipelines` (3 rows) |
| `fb7e5e473` | keeps the enumerator-protocol row inside its own import set (follow-on repair) |
| `179023f47` | **the compiler now owns a load context of its own** for package references. This **corrects the LS2 BLOCK-1 diagnosis**: `nlc restore` was not the defect. `Sdk.targets` already turns a `project.yml` `nuget:` dependency into a real `PackageReference`. The real defect was assembly **identity** — `Assembly.LoadFrom` binds into the DEFAULT context, which holds one assembly per simple name, so inside MSBuild the SDK's own `Microsoft.Extensions.Logging.Abstractions` answered instead of the project's 9.0.0 package, the identity check rightly refused it, and every signature naming one of its types declined at `emit.declaration.field-type`. `ExternalAssemblyScan` now consults its own context only after the default context fails to answer with the exact identity |
| `c44be120b` | a **by-reference argument may name a static field** (`Ldsflda`; CLI2 defect 6, `Interlocked.Increment(ref <static field>)`). New `tests/native/census-static-field-references` (8 rows) |
| `d556db18c` | a **quoted region inside an interpolation hole is opaque** (CLI2 defect 4) |
| `77215f1fe` | **declared variance is read when a constructed generic upcasts** |

**BLOCK-1's reported mechanism was wrong and the correction is the durable finding.** Writing the
same items into the generated props as well would only produce NU1504 duplicates — measured. Record
this wherever BLOCK-1 is cited.

### The async-iterator completion race — `ebaf2eb1d`, pre-existing, not a regression

An `async func*` drive completed its pending `MoveNextAsync` from **inside** the body's protected
regions, and only then ran the `leave` that carried it out. But `SetResult` releases the consumer,
and the promise is built with `RunContinuationsAsynchronously` precisely so resumption does not
re-enter the frame — which means it runs **beside** it. The rows the completing thread still owed
were the `leave` and the state-guarded handlers `leave` walks on the way out, each of which reads
`<>__state`; the re-drive's dispatch writes that field first. Lose the race and a handler no longer
sees a suspension and runs the `finally` a second time.

**Measured as pre-existing, explicitly:** a 5,000-iteration harness put the doubled release at
**35/5000 at this commit's parent** and **37/5000 at the published base `ec3bb3050`**, where
`EmitAsyncComplete` is byte-identical. After the fix: **0/5000** — relay stress 5000/5000 idle and
5000/5000 under 8-way CPU contention (load ~11); the named test 200/200 idle and 150/150 contended.

The answer is now **recorded rather than delivered**: `EmitAsyncComplete` stores it in `<>__result`,
raises the drive's completion flag and leaves, and the one `SetResult` stands past the last
`EndExceptionBlock` as the last thing `MoveNextCore` does. The regression test reads that ordering
off the plan rows the probe machine realized, so it is a **deterministic fact rather than a race
that has to be provoked**.

### Gate history for this checkpoint — two failures, then a clean pair, then the seed

Recorded honestly, in order. Every log is under `evidence/`.

**1. `23c6c650e`, non-VS — FAILED, `EXIT=1`, 32m41s.** `census-internals-visible-to` broke. This was
a **cross-lane fixture break, not a product defect**: the IVT friend-grant fixture stood on
`SemanticTokenLocation`, an internal record struct in the semantic-token handler, and the LS
ownership lane moved that walk into `EditorSemanticTokenFacts` and deleted the C# type. 27 rows went
red. `load-before-gate.txt`: `load averages: 1.90 2.50 2.86`. Log
`evidence/combined-23c6c650e/product-non-vscode.log`.

**2. `11197708d` — the fixture re-point, and the next failure.** The positive arm now stands on
`NSharpLang.LanguageServer.Program`, the entry point C# makes internal by default — named in full,
because N# puts this file's free functions in `Tests.Program`; it is constructed (`newobj` on a
non-public type), passed across two call signatures and read back through `typeof`, so the CLR still
re-checks the grant at run time. The refusal arm stands on `CallHierarchyProtocol`, the residue the
ownership lanes **produce** rather than delete. Its **non-VS gate PASSED** (`EXIT=0`, 32m43s, cache
`5e47abbf6cfc310c`); its **VS-enabled gate FAILED** (`EXIT=1`, 33m34s) on `census-iterators` — which
is the async completion race above, surfacing under the VS run's higher load. Logs
`evidence/combined-11197708d/`.

**3. `ebaf2eb1d` — both gates PASS.** `evidence/combined-ebaf2eb1d/`, pinned in `SHA256SUMS`;
`load-before-gate.txt` records `load averages: 1.90 2.76 3.37`.

| | non-VS | VS-enabled |
|---|---|---|
| Result | **PASS, `EXIT=0`** | **PASS, `EXIT=0`** |
| Wall time | 32m38s | 33m40s |
| Isolated test cache | `a53a7509754f0d53` (1958s) | `7f6b99bc8493c148` (2020s) |

`ebaf2eb1d` was **pushed**, and is the packed source the second reseed was taken from.

### The second real reseed — SUCCESS on the first try, at packed source `ebaf2eb1d`

`evidence/reseed-ebaf2eb1d/reseed.log` (byte-identical to `evidence/seed-977d336cf/reseed.log`;
`EXIT=0`). Contrast the 2026-09-19 reseed, which needed four attempts.

- **Stage 1** — clean self-rebuild of `NSharpLang.Compiler.Core` after `rm -rf obj bin` and a
  `--force-evaluate` restore: **Build succeeded, 0 Warning(s), 0 Error(s)**, 1m07.89s.
- **Stage 2** — same, from the stage-1 seed: **Build succeeded, 0 Warning(s), 0 Error(s)**,
  1m08.32s.
- **Exact byte equality**, both stages: `reseed.sh` compares the restored NuGet-cache package
  against the verified bootstrap package by SHA-256 and **aborts with
  `Error: restored NuGet cache package differs from verified bootstrap`** if they differ. It did not
  abort; `verify-bootstrap.py` printed `Pinned bootstrap SDK and runtime verified` at both stages.
- **Compiler-service estate against the new seed:**
  `Failed: 0, Passed: 9418, Skipped: 0, Total: 9418`, 17s.
- **Published seed hashes** (`bootstrap/SHA256SUMS` at `977d336cf`, re-read from the worktree):
  - Sdk `59627b7d892ed9e9c19d0a94d3f900c7a7998c97faa8fc15219a8d8f6252b9f6`
  - Runtime `b6fb63a56874a534fb3546618745c2732495819f17da98d5a886efc68fca5098`
  - (previous seed, for contrast: Sdk `bf4a1f9c…`, Runtime `35f1a227…`)

`977d336cf` commits those two `.nupkg`s with `bootstrap/SHA256SUMS`, repins the ownership head to
**`head-v2:1b2165aa23326dff`** and the delivery fingerprints, **ownership-audit 25/25**. Its diff is
five files and six lines.

### Gates on the seed commit `977d336cf` — both PASS

`evidence/seed-977d336cf/`, pinned in `SHA256SUMS`; `load-before-gate.txt` records
`load averages: 1.94 2.82 2.91` at 20:37.

| | non-VS | VS-enabled |
|---|---|---|
| Result | **PASS, `EXIT=0`** | **PASS, `EXIT=0`** |
| Wall time | **32m37s** | **33m40s** |
| Isolated test cache | **`89e9ee3b0f336d6d`** (1957s) | **`c8bb9fd0492ef697`** (2020s) |
| VS Code smoke | skipped (`VSCODE_TESTS=skip`) | **36 passing**, 0 pending/skipped, 42s |

Stage numbers, exactly as the non-VS log prints them:

| Stage | What the log shows |
|---|---|
| Format contract gate | PASSED — "All files are properly formatted." ×4 |
| Systems throughput | `PASS: 12 cells, 0 failed, tolerance 1.20x`; **worst ratio 1.01x** (`count-transitions`/4096, 583.086 → 587.840 ns); **load average { 2.98 2.86 2.91 }**, 10 cores; baseline unchanged (measured 2026-09-01 on an idle Apple M4, `8cf40128a`). 0m32s |
| Self-host front door | `src/NSharpLang.Compiler.Core: 1340 diagnostics (at the ceiling)`; `src/NSharpLang.Build.Tasks: 0 diagnostics (at the ceiling)`; **`Compiler` and `Playground` BLOCKED behind Compiler.Core's own front door — not counted**. 11m31s |
| Compiler-service estate | `Failed: 0, Passed: 9418, Skipped: 0, Total: 9418`, 14s |
| Native N# tests | **115 project rows, 4,651 passed, 0 failed, 1 skipped, 4,652 total**; 17m05s |
| — gate-script contracts | **38 / 38 — MEASURED at this tip** |
| — ownership audit | **25 / 25** |
| — compile-time bench | **74 functional pass**; the log prints **no timing verdict, no load and no ms** for that row — the timing is **UNJUDGED**, as at every prior checkpoint. Do not claim it judged |
| `nlc check` on examples | **26 directories, all PASSED** |
| IL verification | **`All 80 N# assemblies pass IL verification (no new errors vs baseline)`**, 19s |

The VS-enabled run agrees on every stage — front door 1,340 / 0, estate 9,418 / 0 / 0 in 16s, the
same 115 rows / 4,651 / 0 / 1, contracts 38/38, ownership 25/25, bench 74 functional and unjudged,
IL 80 assemblies. Its throughput worst ratio is **1.04x** (`rolling-hash`, both sizes: 42.249 →
44.103 and 4765.592 → 4962.264) at the higher **load average { 4.37 3.99 3.65 }**.

**Native row delta is fully accounted.** 110 rows at `d57586f54` → **115** here (+5, all new
projects), and 4,593 → 4,651 (**+58**), which decomposes exactly:

- five new blocker-regression projects, **+35**: `census-catch-types` 10, `census-process-members`
  8, `census-static-field-references` 8, `census-source-typed-generic-receiver` 6,
  `census-pipelines` 3;
- six existing projects grew, **+23**: `language-server-handlers` 139→144 (+5, the `23c6c650e`
  glue rows), `census-emit-shapes` 100→104 (+4), `cli-command-contracts` 201→205 (+4),
  `daemon-command` 28→32 (+4), `readonly-dictionary-widening` 10→14 (+4),
  `sdk-project-reference-boundary` 25→27 (+2).

The single skip is the same intentional one, `census-testrefs` 7/0/1/8. The estate moved
**9,326 → 9,418 (+92)** — the nine `Editor*Facts` owners' assertions and the iterator-planner rows.

`977d336cf` was **pushed** to `origin/systems-language` on 2026-09-20; `census/merge` and
`origin/systems-language` are the same commit.

### Extension reload — SUCCEEDED; rendered visual IDE verification STILL OWED

`evidence/seed-977d336cf/reload-extension.log`. The reload that had failed in both prior waves
because **VS Code would not quit** finally went through: the extension packaged
(`nsharp-0.6.0.vsix`, 300 files, 4.87 MB), `code --install-extension … --force` reported
`Extension 'nsharp-0.6.0.vsix' was successfully installed.`, the sample project opened, and the log
records the language server under test as **`LanguageServer.dll` pid 19822 (child of plugin host
19809), started Sun Sep 20 21:45:30 2026**.

**That closes the reload debt and nothing else.** The installed extension now matches `977d336cf`,
so an IDE observation made from here would finally describe the current server — but **no rendered
observation has been made.** The rendered visual IDE proof has never been produced in this campaign,
and the debt now covers the whole of this wave's editor work: the nine migrated handlers'
user-visible behaviour (semantic tokens, call hierarchy, type hierarchy, selection range, document
symbol, document link, inlay hint, go-to-implementation, on-type formatting), on top of the
still-unseen signature help and hover accessibility marker from wave 13.

### Converter census at the new seed — see the receipt

`evidence/seed-977d336cf/converter/RECEIPT.md`, run at `nlc 0.1.0+977d336cf` with the unchanged
converter `b9a49e0`; `convert-all.sh` **exit 0**, `census-merge` **clean before and after**.

**43 files / 62 diagnostics / 2 stubs**, against **51 / 86 / 11** at the `d932566aa` census —
runtime 0 (was 0), languageserver **8** (was 10), cli **4** (was 26), playground-wasm 22 (was 22),
tests 28 (was 28); mapped constructs 32,591 → 17,534.

**Read the delta as deletion, not as fixing.** The converter is byte-for-byte the same program. What
changed is the input: the CLI corpus went 11 converted files → 3, and 22 of the CLI's 24 lost
diagnostics were attached to files that no longer exist. `runtime`, `playground-wasm` and `tests`
are the control group — their C# did not change, and they are identical row-for-row, code-for-code
and first-site-for-first-site. Two rows moved the **wrong** way: **NL402 +4 and NL010 +2**, new
converter debt created by this round's own N# lanes, because the converter has not been taught to
spell calls into the new `Editor*Facts` owners or to plan imports around them.

### Open decisions — these belong to the user

1. **Where does the test-runner host live? — ANSWERED AND IMPLEMENTED (option B).** A new dedicated
   N# assembly, `src/NSharpLang.TestHost`, referenced only by `src/NSharpLang.Cli`. The runner did
   NOT go into `Compiler.dll`, which is loaded by the MSBuild task host inside every `dotnet build`
   of every N# project, is published with the LanguageServer and sits in the browser-wasm trim
   graph. See "CLI — lane 5" above; `Program.Testing.cs`, `Program.Execute` and
   `Commands/WatchCommand.cs` are all gone.
2. **Ship the CLI as an N# SDK project symbol-less, until a portable PDB exists?** The flip is
   otherwise reachable; the cost is debugging symbols for `nlc` itself. STILL OPEN, and it is now
   the only thing between `src/NSharpLang.Cli` and being csproj-free, together with the
   `packAsTool` / `toolCommandName` / `copyLocalLockFileAssemblies` project.yml keys.

### Open compiler items carried forward

- **Nullability metadata** — N#-emitted metadata still carries no nullability, so an N# caller in
  another assembly cannot pass `Dictionary<string, object?>`. The widest of the CLI2 defects, still
  open.
- **`System.Uri`** unmodeled — which is exactly why document-link canonicalisation stayed in C#.
- **`JsonSerializer`** 1-arg `Serialize` and `Deserialize<T>` unmodeled.
- **`OfType` on a call receiver** still declines (`MakeList().OfType<T>()`); `b73d55d41` answered
  only the non-generic extension slot.
- **`ldelema` / `in` arguments.**
- **`nlc format` and `{{`** — the doubled brace does not round-trip.
- **12 `format --check` failures that are out of the gate's scope** — 11 under `tests/native` plus
  `src/NSharpLang.Playground/PlaygroundCompiler.nl`. `tests/native` is not in the gate's format
  step, which is why the gate is green while these stand. *(Carried from the dispatch brief; not
  re-measured at this tip.)*
- **`Cli` `CS0436` duplicate-`Program` warnings** — now **2**, both in the 25-line `Program.cs`
  (`GetVersion`'s two `typeof(Program)` reads); the `WatchCommand.cs` site went with that file at
  `07e1dca0f`. Warning, not a gate failure. Do not silence with `NoWarn`.
- **The IVT metadata-grant test will need a new subject when LS/Cli flip.** `11197708d` says so
  itself: when either `LanguageServer.Program` or `CallHierarchyProtocol` goes, `LanguageServer.dll`
  and its `InternalsVisibleTo("Tests")` grant have gone with it, and that fixture is rewritten whole
  rather than re-pointed.
- IVT2's three original leftovers are unchanged: non-friend **member** refusals still arrive as
  emit-time `NL103`; `query def` on a metadata member returns `noSymbol`; free functions of a
  referenced N# assembly are unreachable.

### Still OWED

- **Rendered visual IDE verification.** Never produced. The reload excuse is gone; the debt is not.
- **The CLI and LanguageServer flips**, both gated on the decisions above and on nullability
  metadata.
- **Playground / Runtime / Wasm-hosting conversion** — not started.

### Process lessons from this round

- **A conversion lane deleting a type can break another lane's fixture.** `23c6c650e` failed because
  the IVT fixture stood on incidental helper surface — which is exactly the surface a conversion
  lane exists to delete. Pick fixture subjects that the lanes **produce**, not ones they remove.
- **A load-sensitive race hides in the cheaper gate.** `11197708d` passed non-VS and failed VS on
  the same commit. Do not read one green gate as covering the pair.
- **Measure "pre-existing" before calling it pre-existing.** `ebaf2eb1d` proved it with a
  5,000-iteration harness at the parent (35/5000) *and* at the published base (37/5000), plus a
  byte-identical-emitter check — not by inspection.
- **Convert an ordering race into a plan-row assertion.** The regression reads the completion's
  position off the realized plan, so it is deterministic instead of needing to be provoked.
- **A reported blocker's mechanism can be wrong.** LS2 BLOCK-1 named `nlc restore`; the defect was
  assembly identity in the default load context. Re-measure a reported mechanism before building on
  it.

## Census wave 13 — history (2026-09-20)

*Superseded by the wave-14 section above. Retained as written.*

Wave 13 is integrated, **pushed and gated** through `d57586f54` on `census/merge`, which equals
`origin/systems-language`. The push happened on 2026-09-20. Sixteen commits sit between the wave-12
tip `01f10ddfd` and `d57586f54`: the IVT2 trio, five CLI owner conversions, three LanguageServer
slices, three compiler-blocker fixes, and the two gate repairs the round's own failures forced. The
integration checkout is clean. The five lane worktrees (`ivt2`, `cli2`, `cli3`, `ls2`, `blockers`)
were retired after ancestry and cleanliness checks.

**This is not a completion record.** The managed-toolchain conversion objective this file was opened
for is NOT finished. **3,335 lines of CLI C# and 8,167 lines of LanguageServer C# remain**, plus 861
in Runtime and 71 in Playground.Wasm. The rendered visual IDE proof and the extension reload are
**both still owed**, and the debt is now larger than it was: it must also cover the new signature
help and the new hover accessibility marker. **No new bootstrap seed has been published** — the
published seed is still `6a50c373e`, and the compiler has changed since. Do not read the accepted
gate below as a complete production migration.

### Status of the required sequence at a glance (2026-09-20)

| Step | State | Where the receipt is |
|---|---|---|
| IVT2 — emit + refuse + editor marker | **LANDED, with three gaps open** | `d6a1b2684`, `881d330f2`, `02b879b7e` |
| SIGHELP — N# overload-signature owner | **LANDED** | `750e10a28`; `evidence/ls2-sighelp/` |
| CLI owner conversion | **PARTIAL** — 5 owners moved, 6 C# files left | `5b69d1646` … `68f1b4c8e` |
| LanguageServer owner conversion | **BLOCKED** — whole-project flip reverted | `census-briefs/LS2-COMPILER-BLOCKERS.md` |
| Playground / Runtime / Wasm-hosting conversion | **NOT STARTED** | — |
| Non-VS product gate at `d57586f54` | **PASS on rerun**, after one load-caused failure | `evidence/combined-d57586f54/` |
| VS Code-enabled product gate at `d57586f54` | **PASS** | `evidence/combined-d57586f54/product-vscode.log` |
| Push to `origin/systems-language` | DONE 2026-09-20 | `d57586f54` |
| Lane worktree retirement (5) | DONE | ancestry + clean checks below |
| Rendered visual IDE proof | **OWED** | nothing rendered has ever been observed |
| Extension reload | **OWED** | VS Code would not quit |
| New bootstrap seed | **NOT PUBLISHED** | still `6a50c373e`; decision deferred |

### IVT2 — landed, three gaps still open

Three commits, in landing order:

- **`d6a1b2684`** — refuse a **qualified** internal name of a non-granting reference as the simple
  one is already refused. The refusal is `NL201`.
- **`881d330f2`** — emit `internalsVisibleTo:` from `project.yml`, so an N# library can make a
  friend. New owner `src/NSharpLang.Compiler.Core/ColumnarInternalsVisibleToEmitter.nl` (115 lines),
  with `ProjectFileParser.nl` and `InternalsVisibleToEmissionScope.nl` changes behind it.
- **`02b879b7e`** — say `internal` in hover, so the editor tells the reader why a name resolves. The
  accessibility marker also reaches `query`.

Regressions: `tests/native/census-internals-visible-to` went **14 → 27** (two new files,
`SourceGrants.tests.nl` and `GrantedEditorVisibility.tests.nl`). *(The dispatch brief said 10 → 27;
the measured prior row is 14, from `evidence/seed-6a50c373e/product-non-vscode.log`.)*

**Still open after IVT2:**

1. A **non-friend member** refusal still arrives as an **emit-time `NL103`**, not as a front-door
   refusal — the type-level refusal landed, the member-level one did not.
2. `query def` on a **metadata member** returns `noSymbol`.
3. **Free functions of a referenced N# assembly are unreachable** — the friend grant does not make
   them resolvable.

### CLI — five owners migrated to N#, their C# deleted

| Commit | Owner moved | C# deleted | N# added |
|---|---|---|---|
| `5b69d1646` | IL build/run backend | `Program.Backends.cs` (366) | `CliIlBackend.nl` (346) |
| `9da4a7c4f` | `nlc pack`, both output modes pinned | `Commands/PackCommand.cs` (204) | — |
| `8ac294f86` | daemon JSON-RPC wire | `Daemon/DaemonProtocol.cs` (100) | — |
| `0a337fce7` | daemon client | `Daemon/DaemonClient.cs` (233) | `DaemonClient.nl` (258) |
| `68f1b4c8e` | batch query runner | `BatchQueryRunner.cs` (505) | `BatchQueryRunner.nl` (703) |

`Program.cs` shrank **786 → 757** across the round. `tests/native/cli-command-contracts` went
**195 → 201**.

**Remaining CLI C# — 3,335 lines in 6 files**, measured at `d57586f54`:

| File | Lines |
|---|---:|
| `Commands/QueryCommand.cs` | 1,081 |
| `Program.cs` | 757 |
| `Daemon/DaemonServer.cs` | 632 |
| `Program.Testing.cs` | 614 |
| `Commands/WatchCommand.cs` | 155 |
| `Commands/DaemonCommand.cs` | 96 |

The concrete blockers are the eight numbered defects in `census-briefs/CLI2-COMPILER-BLOCKERS.md`.
Two of them were **fixed on merge** this round (see below); **six remain**: `SHA256.HashData` /
`HashAlgorithm.ComputeHash` unmodeled; a string literal inside an interpolation hole declines the
interpolation; a `catch` clause whose exception type is not in the core assembly declines;
`Interlocked.Increment(ref <static field>)` declines; `Process.MainModule` unmodeled; and the widest
one — **N#-emitted metadata carries no nullability**, so an N# caller in another assembly cannot pass
`Dictionary<string, object?>`.

### LanguageServer — SIGHELP and folding moved; the whole-project flip is blocked

The whole-project flip **was attempted and reverted**. The five blockers are recorded in
`census-briefs/LS2-COMPILER-BLOCKERS.md`:

1. **BLOCK-1 (decisive, SDK)** — `nlc restore` writes **no `PackageReference`** into
   `obj/project.g.props`; `RestoreCommand.RestoreRecursive` filters to `ReferenceType.Project` only,
   so a `<Project Sdk="NSharpLang.Sdk" />` csproj cannot express a NuGet dependency at all.
2. **BLOCK-2 (pervasive)** — an instance call through a receiver typed `External<SourceType>`
   declines; declaring such a field is fine. All 23 handlers hold `ILogger<TheHandlerItself>`.
3. **BLOCK-3** — no type from `System.IO.Pipelines` can be emitted.
4. **BLOCK-4** — Serilog's `ILoggingBuilder.AddFile` is unmodeled.
5. **BLOCK-5** — `Process.WaitForExitAsync()` is unmodeled.

What did land:

- **`750e10a28` — SIGHELP is fixed in N#.** Signature help now resolves through the **project
  snapshot** rather than the current document's `SymbolsInfo`: new
  `SignatureHelpOverloadFacts.nl` (429) and `CodeIntelligence/SignatureHelpEngine.nl`.
  `Handlers/SignatureHelpHandler.cs` **382 → 151**. `tests/native/language-server-handlers`
  **132 → 139**. Probe evidence in `evidence/ls2-sighelp/`.
- **`0eb855332` — folding moved to N#**: `EditorFoldingFacts.nl` (243) with 185 lines of tests;
  `Handlers/FoldingRangeHandler.cs` **299 → 81**.
- **`c7333e15a`** — a declaration's source is read **only when its doc comment is wanted**.

**Remaining LanguageServer C# — 8,167 lines in 31 files.** Largest: `Services/DocumentManager.cs`
1,449; `Handlers/SemanticTokensHandler.cs` 842; `Handlers/CallHierarchyHandler.cs` 734;
`Handlers/CompletionHandler.cs` 620; `Handlers/SelectionRangeHandler.cs` 552.

### Remaining production C# per project, measured at `d57586f54`

`find <project> -name '*.cs' -not -path '*/obj/*' -not -path '*/bin/*' | xargs wc -l`:

| Project | C# lines | Files |
|---|---:|---:|
| `src/NSharpLang.LanguageServer` | 8,167 | 31 |
| `src/NSharpLang.Cli` | 3,335 | 6 |
| `src/NSharpLang.Runtime` | 861 | 4 |
| `src/NSharpLang.Playground.Wasm` | 71 | 2 |
| `src/NSharpLang.Playground` | 0 | 0 |
| `src/NSharpLang.Compiler`, `.Compiler.Core`, `.Build.Tasks`, `.Sdk` | 0 | 0 |

### Compiler blocker fixes taken on merge this round

Three defects the lanes reported were fixed on `census/merge` rather than worked around — the
`a2b98cd11`-equivalents:

- **`c8f0ddec9`** — bind the **declared parameterless constructor** an object initializer names
  (CLI2 defect 1; this also removes the `nlc format` footgun that turned a compiling file into a
  declining one).
- **`90e2f21f3`** — let a positional call **omit a defaulted parameter in its own compilation**
  (CLI2 defect 2; the boundary asymmetry is gone).
- **`e5ce20f39`** — plan a call whose **receiver is a static-member read**, so it can be an argument.

Still open: CLI2 defects 3–8 and LS2 BLOCK-1 … BLOCK-5, above.

### Gate history for this checkpoint — three failures before the accepted pair

Recorded honestly, in order. Every log is under `evidence/`.

**1. `e5ce20f39`, non-VS — FAILED, `EXIT=1`, self-host front door.**
`src/NSharpLang.Compiler.Core: 1351 diagnostics, ceiling 1342 — the compiler's own source got WORSE
through its own front door.` Nine new diagnostics, caused by the round's own new N#. Step 2d took
12m51s. Log `evidence/combined-e5ce20f39/product-non-vscode.log`.

**2. `c751edd7e` — the front-door repair, and the next failure.** `c751edd7e` took the front door
back under its ceiling at **1,340**, including a **checker false-positive fix** that adds
`System.Reflection.Emit` to `ExternalAssemblyScan.CommonAssemblyNames`, and **ratcheted the ceiling
DOWN to 1340**. Its own non-VS gate then **FAILED, `EXIT=1`, on the ownership audit**:

```
OWN005 [tests/scripts/test-all-core.sh]: reviewed delivery snapshot drift;
expected text-v1:d2b8de9771eb4ebf; observed text-v1:919e5bfcaac33f8c
at lines=1019, nonblank=916, bytes=0.
```

The row had not been repinned after a tracked non-N# edit. Log
`evidence/combined-c751edd7e/product-non-vscode.log`.

**3. `d57586f54` — the repin, and a load-caused throughput failure.** `d57586f54` repins that
delivery row; the ownership head is now `head-v2:9754bd17b78a7d95`. Its **first** non-VS run
**FAILED, `EXIT=1`, 36m38s**, on the throughput gate:

```
| count-transitions | 4096 | 583.086 | 718.006 | 1.23x | FAIL |
FAIL: 12 cells, 1 failed, tolerance 1.20x
load average { 5.53 5.08 4.75 }, 10 cores
```

This was **not a product failure**. A leaked subagent spin-loop shell was consuming the machine; the
recorded load average of 5.53 is more than double the 2.81 of the passing rerun at the same commit.
The log is retained as `product-non-vscode.FAILED-throughput-under-load.log` rather than deleted.

**4. `d57586f54`, rerun — both gates PASS.** `evidence/combined-d57586f54/`, files pinned in
`SHA256SUMS`; `load-before-gate.txt` records `load averages: 1.71 2.61 2.82` at start.

| | non-VS | VS-enabled |
|---|---|---|
| Result | **PASS, `EXIT=0`** | **PASS, `EXIT=0`** |
| Wall time | 32m11s | 33m09s |
| Isolated test cache | `71aa565f2527174a` (1931s) | `f1aad93e8d2e9483` (1989s) |
| VS Code smoke | skipped (`VSCODE_TESTS=skip`) | **36 passing**, 0 pending/skipped, 42s |

Stage numbers, exactly as the non-VS log prints them:

| Stage | What the log shows |
|---|---|
| Format contract gate | PASSED — "All files are properly formatted." ×4 |
| Systems throughput | `PASS: 12 cells, 0 failed, tolerance 1.20x`; **worst ratio 1.01x** (`count-transitions`/4096, 583.086 → 588.018 ns); **load average { 2.81 2.76 2.86 }**, 10 cores; baseline measured 2026-09-01 on an idle Apple M4 (`8cf40128a`) |
| Self-host front door | `Compiler.Core: 1340 diagnostics (at the ceiling)`; `Build.Tasks: 0 diagnostics (at the ceiling)`; **`Compiler` and `Playground` BLOCKED behind Compiler.Core's own front door — not counted**. 11m19s |
| Compiler-service estate | `Failed: 0, Passed: 9326, Skipped: 0, Total: 9326`, 17s |
| Native N# tests | **110 project rows, 4,593 passed, 0 failed, 1 skipped, 4,594 total**; 16m55s |
| — gate-script contracts | **38 / 38 — MEASURED at this tip** (the row was absent from both `d932566aa` logs) |
| — ownership audit | **25 / 25** |
| — compile-time bench | **74 functional pass**; the log prints **no timing verdict, no load and no ms** for that row — the timing is **UNJUDGED**, as at `d932566aa` |
| `nlc check` on examples | 26 directories, all PASSED |
| IL verification | `All 80 N# assemblies pass IL verification (no new errors vs baseline)` |

The VS-enabled run agrees on every stage; its throughput worst ratio is **1.05x** (`rolling-hash`, both
sizes) at the higher **load average { 4.17 4.10 3.83 }**, and its estate ran in 15s.

**Native row delta is fully accounted.** 110 rows both at `d932566aa` and here — no new project — and
4,552 → 4,593 (+41) decomposes exactly: `census-internals-visible-to` 14→27 (+13),
`language-server-handlers` 132→139 (+7), `census-named-arguments` 47→54 (+7),
`cli-command-contracts` 195→201 (+6), `construction-arrays` 7→13 (+6), `census-emit-shapes` 98→100
(+2). The single skip is the same intentional one, `census-testrefs` 7/0/1/8. The estate moved
9,295 → 9,326 (+31), which is where the new `EditorFoldingFacts` and `SignatureHelpOverloadFacts`
assertions live.

### Scratch self-host at `e5ce20f39` — passed, but no seed was published

`evidence/combined-e5ce20f39/scratch-selfhost.log`: both stages clean, `RESEED_EXIT=0`, and the
compiler-service estate against the new scratch seed at **9,325 passed / 0 failed / 0 skipped** in
18s. Bootstrap and baseline hashes pinned in `baseline-bootstrap.sha256` and
`baseline-nugetcache.sha256`; `NuGet.config.orig` records the feed repoint the scratch mode needs.

Two lines in that log read `RESULT … FAILED` for `src/NSharpLang.Cli/NSharpLang.Cli.csproj` and
`src/NSharpLang.LanguageServer/NSharpLang.LanguageServer.csproj`. They are `MSBUILD : error MSB1009:
Project file does not exist` — **stale project names in the sweep, not build failures**. The real
`Cli.csproj` and `LanguageServer.csproj` both built OK in the same log.

**This was a scratch validation. Nothing was published.** The bootstrap seed on disk and in git is
still `6a50c373e`, and the compiler has changed since. The next reseed is **pending a decision at
the next checkpoint**.

### Push and retirement (2026-09-20)

`d57586f54` was pushed to `origin/systems-language` on 2026-09-20; `census/merge` and
`origin/systems-language` are the same commit. The five lane worktrees — `ivt2`, `cli2`, `cli3`,
`ls2`, `blockers` — were **retired after ancestry and cleanliness checks**, i.e. after confirming
each lane's work is an ancestor of the pushed tip and each checkout carried nothing uncommitted.

### Still OWED — unchanged in kind, larger in scope

- **Extension reload.** Still failing for the same reason: **VS Code would not quit**. The installed
  extension therefore predates everything in this wave.
- **Rendered visual IDE verification.** Never produced. The debt now **also covers the new signature
  help and the new hover accessibility marker** — both shipped this round and neither has been seen
  rendered.
- **A new bootstrap seed.** None published since `6a50c373e`; the compiler has changed since.

### Process lessons from this round

- **No spin-wait loops in agents.** A leaked subagent spin-loop shell cost a full 36-minute gate by
  pushing the machine to load 5.5 and failing a throughput cell at 1.23x.
- **Measure the front door before reporting.** `e5ce20f39` was reported done and then failed step 2d
  at 1351 against a 1342 ceiling.
- **Re-run the ownership audit LAST**, after any tracked non-N# edit. `c751edd7e` failed OWN005 on a
  `tests/scripts/test-all-core.sh` row that a previous step had changed and not repinned.
- **Clean stale `obj/` before a scratch reseed.**
- **Followup:** the Cli build emits **3 `CS0436` warnings** — the `Program` type in
  `src/NSharpLang.Cli/Program.cs` conflicts with an imported `Program` from the `Compiler` assembly
  (sites: `Program.cs:750`, `Program.cs:753`, `Commands/WatchCommand.cs:129`). Filed for a later
  slice; it is a warning, not a gate failure.

## Census wave 12 — history (2026-09-19)

*Superseded by the wave-13 section above. Retained as written.*

Wave 12 is integrated, **pushed, reseeded and gated** through
`d932566aae5fc9522b558941704292f415c1b5e9` on `census/merge`, which equals `origin/systems-language`.
The push happened in two steps on 2026-09-19: `9b4c46174` (the docs closeout at `c6ab6f2e7`) and then
`d932566aa`. Between them sit the reseed repairs, the bench-corpus repin, the republished bootstrap
seed `6a50c373e`, and the test correction `d932566aa` that the seed's first gate forced. The
integration checkout is clean. Nineteen census worktrees and branches plus `codex/toolchain-integration`
have been **retired**; three stale lanes were archived by tag.

**This is not a completion record.** The managed-toolchain conversion objective this file was opened
for is NOT finished. CLI, LanguageServer, Playground, Runtime and Wasm-hosting production owners and
their assertions are still outstanding; the post-seed converter census measured **zero movement**
against the pre-seed one because no owner was converted between them. The rendered visual IDE proof
and the post-seed extension reload are both still owed. Do not read the accepted checkpoints below as
a complete production migration.

### Status of the required sequence at a glance (2026-09-19)

| Step | State | Where the receipt is |
|---|---|---|
| Fresh VS Code-enabled gate at the pre-seed tip | DONE | `c6ab6f2e7` sections below (pre-seed history) |
| Pre-seed extension reload | DONE | `astra-c6ab6f2e/` |
| Rendered visual IDE proof | **OWED** | nothing rendered has ever been observed |
| Tracked docs, review, push | DONE | `9b4c46174` then `d932566aa`, pushed to `origin/systems-language` |
| Retirement of 19 worktrees/branches | DONE | retirement section below |
| Two-pass reseed | DONE, after three failures | reseed-history section below |
| Repin bootstrap + ownership head, commit packed source | DONE | seed commit `6a50c373e` |
| Post-seed gates (non-VS and VS Code-enabled) | DONE, both PASS at `d932566aa` | `evidence/seed-6a50c373e/` |
| Post-seed converter rerun | DONE | `evidence/seed-6a50c373e/converter/RECEIPT.md` |
| Post-seed extension reload | **FAILED, owed** | `reload-extension.log` |
| IVT2, SIGHELP, remaining owner conversion | **OPEN** | not started |

### Current ownership rule (supersedes every earlier assignment in this file)

Root (Fable) plans, reviews, integrates, runs shared builds and the product gates, performs extension
reload and visual IDE verification, owns the bootstrap seed, package publication, the shared caches and
the worktree/branch lifecycle, and makes every commit and push. **Implementation is delegated to
Opus** in bounded worktrees from the accepted tip; workers do not run shared builds, product gates,
cache operations, or commits.

Every earlier implementation-model assignment recorded in this file and in
`systems-language-closeout/STATUS.md` — Luna Max, Sol, Terra, and the GLM CLI profile — is
**historical**. Those names remain in the retained sections below as a record of who did the work; they
do not describe current dispatch.

### Verified receipt: the push to `origin/systems-language` (2026-09-19)

Two pushes landed on `origin/systems-language`, both from `census/merge`:

- **`9b4c46174`** — "docs: census wave 12 closeout receipts at c6ab6f2e7". The reviewed docs closeout
  described by the `c6ab6f2e7` sections below.
- **`d932566aa`** — "Expect no empty Program holder in a types-only namespace". The current tip;
  `census/merge` and `origin/systems-language` are the same commit.

The seven commits between them, in order: `b73d55d41` (receiver relation for a non-generic extension
slot), `f369e5d22` (write a property's MSBuild marker exactly once), `ca8381cdb` (create a
namespace's `Program` holder only when something is placed on it), `23ed2f0bc` (repin the
compile-time bench corpus at its real 135 projects), `5d9e2de4b` (record the two metadata-shaped
seed-hidden defects in the self-host runbook), `6a50c373e` (republish the two-pass bootstrap seed
from `5d9e2de4b`), `d932566aa`. Six of those seven exist because the reseed and the post-seed gate
found defects — see the two sections below.

### Verified receipt: worktree and branch retirement — DONE (2026-09-19)

Retirement ran **after** the push, and every row was re-checked against the **actual pushed ref**,
not against the snapshot in the retirement manifest: `git -C <worktree> status --porcelain=v1` for
dirt, `git merge-base --is-ancestor <recorded-tip> <pushed ref>` for ancestry, and a check that no
process held a cwd inside the worktree.

- **19 census worktrees and their branches removed**, plus **`codex/toolchain-integration`**
  (`5ebd18b72`, fully absorbed) — 20 refs gone. All passed clean / ancestor / not-in-use.
- **Three stale lanes: worktrees removed, branches KEPT and tagged** `archive/<branch>` —
  `codex/check-remaining-assertions`, `codex/cli-native-owner`, `codex/runtime-owner`. The branches
  survive under `archive/codex/check-remaining-assertions`, `archive/codex/cli-native-owner` and
  `archive/codex/runtime-owner`.
- **`census/lsconvert-source-wip` KEPT and tagged** `archive/census/lsconvert-source-wip`. It is the
  **sole copy of the non-compiling full LanguageServer conversion** and is not an ancestor of the
  pushed ref. Do not delete it; its disposition is decided only by the post-seed LS reconversion
  (step 10 below), which has not run.

`census/merge` itself is preserved as the retained integration worktree.

### Verified receipt: the reseed — three failures, then success

The two-pass reseed did not work the first time, or the second, or the third. Each failure is a real
defect the gates could not have caught, and each has its own evidence directory under
`/Users/spencer/repos/nsharp-worktrees/evidence/`.

| attempt | evidence dir | outcome | defect and fix |
|---|---|---|---|
| at `9b4c46174` | `reseed-9b4c46174/` | **FAILED** in stage-1 self-rebuild | `NL103` on `OfType` — the compiler could not answer the receiver relation for a **non-generic** extension slot. Fixed by **`b73d55d41`**. |
| at `b73d55d41` | `reseed-b73d55d41/` | **FAILED** in the estate, **2 of 9,295** | duplicate MSBuild attribute — a property's MSBuild marker was written twice. Fixed by **`f369e5d22`**. |
| scratch validation | — | **FAILED** the CLI build | empty `public Program` holders were emitted for types-only namespaces, colliding as **`CS0433`**. Fixed by **`ca8381cdb`**. |
| corpus repin | — | — | **`23ed2f0bc`** repinned the compile-time bench corpus at its real **135** projects. |
| runbook | — | — | **`5d9e2de4b`** recorded the two metadata-shaped seed-hidden defects in the self-host runbook. |
| at `5d9e2de4b` | `reseed-5d9e2de4b/`, copied to `seed-6a50c373e/reseed.log` | **SUCCESS** | see below. |

**The successful reseed**, `./scripts/reseed.sh` at `5d9e2de4b`, EXIT 0:

- **Both stages clean: 0 warnings, 0 errors.** Stage-1 Build.Tasks 54.73s and Compiler.Core rebuild
  1m07.43s; stage-2 Build.Tasks 1m11.00s and Compiler.Core rebuild 1m07.50s.
- **Compiler-service estate against the new seed: `Failed: 0, Passed: 9295, Skipped: 0, Total: 9295`**
  (15s), run with `-p:NSharpExcludeTests=false`.
- **Exact hash equality: bootstrap == stage-2 == restored cache.** `verify-bootstrap.py` passed after
  each stage, and the restored cache nupkg bytes were verified against bootstrap bytes before each
  build. The pinned seed is
  `NSharpLang.Sdk.0.1.0.nupkg` **`bf4a1f9c663aa1343306137adb761c440b767ba7aa02115e9e4f6fc24a0154c4`**
  and `NSharpLang.Runtime.0.1.0.nupkg`
  **`35f1a2271f2498fbaf79bd2cfc088ed025bd4836c28d592c661cbc6bdd3ad9f6`** — the two lines now in
  `bootstrap/SHA256SUMS`.

**Seed commit `6a50c373e`** — "Republish the two-pass bootstrap seed from `5d9e2de4b`" — commits the
two `.nupkg` files and `SHA256SUMS` together, as the procedure requires. The **packed source is
`5d9e2de4b`**; the seed commit is `6a50c373e`. The ownership head is repinned at
**`head-v2:5ce298ee5fe53bf8`** and the ownership audit reads **25/25**.

### Verified receipt: post-seed product gates at `d932566aa` — both PASS

Evidence directory: `/Users/spencer/repos/nsharp-worktrees/evidence/seed-6a50c373e/`, with
`SHA256SUMS` covering all four logs.

**The first non-VS gate on the seed FAILED, and that is the point.** Run at the seed commit
`6a50c373e`, it finished **EXIT 1, FAILURES: 1**, total 31m49s, after 1,909s, and the cache was **not**
updated (`product-non-vscode.FAILED-at-6a50c373e.log`). The single failing row was
`tests/native/census-duplicate-declarations`, which **pinned the old empty `Catalog.Program` holder**
that `ca8381cdb` had just stopped emitting — the test asserted the defect. Corrected by
**`d932566aa`**, which expects no empty `Program` holder in a types-only namespace. Nothing was
relaxed: the fix moved the assertion onto the correct behavior.

Both gates were then re-run fresh at `d932566aa` and both passed.

| Gate stage | non-VS at `d932566aa` | VS Code-enabled at `d932566aa` |
|---|---|---|
| Result | **EXIT 0**, timing summary **31m39s**, cache `e0e1da00c8cb7ec0` (1899s) | **EXIT 0**, timing summary **32m30s**, cache `d6778e34d329aa6c` (1950s) |
| Build, format | pass (build 1m23s, format 0m03s) | pass (build 1m23s, format 0m04s) |
| Systems throughput | **PASS: 12 cells, 0 failed**, tolerance **1.20x**, worst measured ratio **1.04x** (`rolling-hash` at both 64 and 4096); load average `{ 3.61 3.87 3.82 }` / 10 cores; baseline unchanged (2026-09-01, idle Apple M4, `8cf40128a`) | same 12/12 pass, same tolerance and baseline |
| Self-host front door | pass, 11m14s — `Compiler.Core` **1342** *(at the ceiling)*, `Build.Tasks` **0** *(at the ceiling)*; `Compiler` and `Playground` BLOCKED behind `Compiler.Core` and not counted | pass, 11m11s — identical rows |
| Compiler-service estate | **Failed: 0, Passed: 9295, Skipped: 0, Total: 9295** (15s) | identical |
| Native sweep | **110 project rows, 4,552 passed, 0 failed, 1 skipped**. The one skip is `tests/native/census-testrefs` (7 passed / 1 skipped / 8 total) | identical |
| — ownership audit | `tests/native/ownership-audit` **25 passed, 0 failed, 0 skipped** | identical |
| — compile-time benchmark | `tests/native/compile-time-bench` **74 passed, 0 failed, 0 skipped** — functional only, see below | identical |
| — `census-duplicate-declarations` | **9 passed, 0 failed, 0 skipped** (was the failing row at `6a50c373e`) | identical |
| VS Code integration | skipped (`VSCODE_TESTS=skip`) | **36 passing (42s)**, 0 pending, 0 skipped — extension, diagnostics, hover, completion |
| Pack, templates, template project, examples, single-file examples | pass | pass |
| `nlc check` on examples | pass, **26 directories** | pass, 26 directories |
| IL verification | **all 80 N# assemblies pass**, no new errors vs baseline (0m20s) | same 80, no new errors (0m19s) |

**The native sweep moved from 109 rows to 110, and passed rows from 4,536 to 4,552 (+16).** Row and
count diffs against the `c6ab6f2e7` log account for all of it: the one added project is
`tests/native/source-typed-explicit-generic-extension` (**9 passed**, the regression for the
`OfType` defect, landed with `b73d55d41`); `tests/native/sdk-project-reference-boundary` rose
20 → 25 (`f369e5d22` added its MSBuild-attribute regression as a second `*.tests.nl` inside the
existing project, so it registers no new project); and `tests/native/census-free-function-identity`
rose 18 → 20 (`ca8381cdb`). No other row moved in either direction.

**Gate-script contracts: the logs do not print a contracts row.** Neither log contains a
`tests/native/gate-script-contracts` line, so the 38/38 figure carried from `c6ab6f2e7` is **not
restated by these runs** and must not be quoted as a `d932566aa` measurement.

**Compile-time: 74 functional pass; timing NOT judged.** The benchmark appears in both logs only as
the native row `tests/native/compile-time-bench`, **74 passed, 0 failed, 0 skipped**. Neither log
prints a timing verdict, a load reading or a millisecond figure for it. The only `load average` line
in either log belongs to the Systems throughput gate. Record 74 functional pass and timing **not
judged** — never as a timing pass.

### Verified receipt: post-seed converter census at `d932566aa` — zero delta

`ROOT=/Users/spencer/repos/nsharp-worktrees/census-merge ./convert-all.sh` (exit 0) and the follow-on
`run.sh census` (exit 0) were run on **2026-09-19** with converter `b9a49e0` and
`nlc 0.1.0+d932566aae5fc9522b558941704292f415c1b5e9`. The `Cli.dll` in the worktree was stale — it
reported `+6a50c373e`, the seed commit, one behind the pushed tip — so Cli, LanguageServer and Runtime
were rebuilt first (`dotnet build --disable-build-servers -nr:false`; Cli and Runtime 0 warnings /
0 errors, LanguageServer 0 errors with 7 pre-existing CS86xx nullable warnings). Receipt:
`evidence/seed-6a50c373e/converter/RECEIPT.md`.

**51 converted files, 86 diagnostics, 11 `// CONVERT:` stubs** — runtime **0**, languageserver **10**,
cli **26**, playground-wasm **22**, tests **28**.

**The delta against the pre-seed census is zero on every row**, and the per-code histogram is
identical code-for-code and count-for-count (NL907 31, NL412 26, NL201 18, NL202 3, NL301 2, NL010 2,
NL002 1, NL303 1, NL402 1, NL905 1), down to the first-site file, line and column. Mapped constructs
are 32,591 in both runs.

**Zero is the expected result and it is not progress.** No C# file under the five converted projects
changed between `c6ab6f2e7` and `d932566aa` — the eight intervening commits touched only `.nl` native
tests, the bench corpus pin, the growth-ratchet JSON and the bootstrap seed. With identical converter
and identical inputs, byte-identical output is what correctness demands, and it is what happened: the
converter repo's `git status --porcelain` and `git diff --stat` are byte-identical before and after
this run. What the zero delta **does** establish is that the reseed perturbed neither conversion nor
diagnosis — a compiler built from the republished seed yields exactly the same diagnostic set, so no
seed-introduced regression reaches the converted estate. What it **does not** establish is any
migration: the two censuses measure the same unconverted corpus twice, 45 of the 86 rows remain
missing-reference-root artifacts rather than language gaps, and CLI/LanguageServer reconversion is
untouched.

**The converter repo is dirty and stays dirty — 22 paths, exactly the 22 it started with.** That dirt
is the pre-seed run's own regenerated output, never committed; this run reproduced it byte-for-byte
and added nothing. It shows as dirt because the committed `out/` tree still reflects the product repo
of 2026-09-14 — before `DocCommand.cs` was deleted, before the C# unit suite was removed, and before
the signature-help work landed — so any regeneration against today's sources differs from what is
committed until the regenerated `out/` is itself committed. Nothing was committed or pushed in the
converter repo.

### Still OWED after the seed: extension reload and rendered visual IDE proof

**The post-seed extension reload FAILED.** `./scripts/reload-vscode-extension.sh` could not get VS
Code to exit: *"VS Code is still running after 30s — a pending self-update can hold it open. Quit it
by hand and re-run."* (`evidence/seed-6a50c373e/reload-extension.log`). **The installed extension is
therefore still the 13:01 build from `c6ab6f2e7`** — it does not contain the language server built
from the reseeded tip. Any IDE observation made right now describes the pre-seed extension.

**The rendered visual IDE verification remains owed**, exactly as it was before the seed. No
screenshot has ever been taken and no rendered UI has ever been observed in this closeout; only
protocol-level probes exist, and those were taken against the pre-seed build.

The user explicitly directed on **2026-09-19** to proceed with other work rather than block on VS
Code, which has been flaky. Proceeding is sanctioned. Both debts stay open and must be discharged
before this closeout is called complete.

### Lessons the seed taught — binding for the next reseed

- **The gates cannot see seed-hidden defects.** Every estate probe is compiled *by the seed*, so a
  defect baked into the seed is invisible to the estate that the seed compiles. All three reseed
  failures were found by the reseed itself, never by a passing gate. A green gate at a tip says
  nothing about whether that tip can reseed.
- **A test can pin the defect.** `census-duplicate-declarations` asserted the empty `Catalog.Program`
  holder and so failed the moment `ca8381cdb` fixed it. When a seed-hidden defect is fixed, re-read
  the tests that cover it before assuming a gate failure is a regression.
- **Reseed scratch mode requires temporarily repointing the root `NuGet.config` feed, and this is
  undocumented.** It cost a debugging cycle. Filed as a runbook/script fix in the pending list below
  and in `census-briefs/FOLLOWUPS.md`.
- **Two language declines were re-confirmed on the emit-only columnar path**, both filed in
  `census-briefs/FOLLOWUPS.md`: `this` as a value declines at `parse.struct`, and a call-expression
  receiver `MakeList().OfType<T>()` still declines.

### Pre-seed history: the `c6ab6f2e7` receipts

The next five subsections — the two `c6ab6f2e7` gate receipts, the pre-seed extension-reload
receipt, the pre-seed converter census and the retirement precheck, ending where **Wave-12 lane
classification** begins — describe the **pre-seed** tip `c6ab6f2e7`. All five were superseded on
2026-09-19 by the push, the reseed and the post-seed gates recorded above. They are retained as the
record of how the pre-seed tip was validated; do not quote their numbers as current. In particular
their native sweep is 109 rows / 4,536 passed and their estate is 9,291 — the current tip reads 110
rows / 4,552 passed and 9,295.

### Verified receipt: first valid fresh non-VS product gate at `c6ab6f2e7`

`NSHARP_TEST_KEEP_RUN=1 VSCODE_TESTS=skip ./scripts/test-all.sh --commit` finished **EXIT 0 in 36m36s
(2,196s)**. A full-log audit found zero `FAILED:` markers and zero JSON `"failed": [1-9]` rows.
Durable evidence copy: `/Users/spencer/repos/nsharp-worktrees/evidence/astra-c6ab6f2e/`
(`astra-c6ab6f2e-product-non-vscode.log`, with `SHA256SUMS`).

| Gate stage | Result at `c6ab6f2e7` |
|---|---|
| Build and format | pass |
| Systems throughput | **12/12**, max ratio 1.06, unchanged baseline and ×1.20 tolerance |
| Self-host front door (Step 2d) | pass at the immutable Core ceiling **1,342**; `Build.Tasks` 0; `Compiler`/`Playground` remain the known blocked (-1) rows |
| Compiler-service estate | **9,291/9,291**, zero skips |
| Native sweep | **109 rows, 4,536 passed, 0 failed, 1 intentional skip** |
| Gate-script contracts | **38/38** |
| Ownership audit | **25/25** |
| Pack / templates / example build / check | pass |
| IL verification | **80 assemblies, no new errors against the unchanged baseline** |
| Compile-time benchmark | **74 functional pass; timing UNJUDGED** — see below |

**The compile-time stage is a functional pass only.** Timing was NOT judged: observed load 3.43 (above
the threshold of 2), runs 144,486 / 147,030 / 145,668 ms, median 145,668 ms, which is numerically below
the 185,827 ms budget. A skipped-by-load measurement is not a timing pass and must never be recorded as
one.

Ownership head pins at this tip: both reviewed heads are `head-v2:5ce298ee5fe53bf8`; packages delivery
`text-v1:ef8f2afcc9069810` (138 lines / 115 nonblank), setup delivery `text-v1:4b95c568a243574b4`
(401 lines / 352 nonblank).

**Distinct, earlier, judged timing evidence** (standalone, not a product gate, recorded at `edcd6294`):
the root-only idle five-build baseline measured walls 125,410 / 123,533 / 123,885 / 123,124 / 126,452 ms
— median **123,885 ms**, median RSS 1,521,696,768 bytes, 526 non-test files / 288,658 lines, at idle
load 1.91 (`artifacts/astra-build-baseline-measurement`). The full 74-test benchmark then ran 74/74 with
0 failed and 0 skipped and its timing verdict **was judged ok** at load 1.89 (< 2): runs 126,462 /
141,056 / 148,862 ms, median 141,056 ms against baseline 123,885 ms and the ×1.5 limit 185,827 ms. Keep
that judged standalone result and the gate's unjudged stage strictly separate.

**Seven prior full-gate attempts failed or were aborted** before this one (analyzer-clean-source EF
fixture, repeated Systems throughput cells, a stale delivery fingerprint, and an intermittent
`setup-local.sh` dry-run row). None of them is a checkpoint receipt. The root causes were fixed in
`8f4fd091`, `fc2ae92a`, `d8553f18`, `2602fa07` and `c6ab6f2e` without relaxing any baseline, tolerance,
ceiling or allowlist.

### Verified receipt: fresh VS Code-enabled product gate at `c6ab6f2e7` — PASSED

`./scripts/test-all.sh --commit` with the VS Code stage **enabled** (no `VSCODE_TESTS=skip`) was run
fresh at `c6ab6f2e7` on **2026-09-19** and finished **EXIT 0**. The run was forced-fresh — the log
opens with *"Fresh isolated test run required: pre-commit verification / Existing cache entries will
not satisfy this invocation"* — and ended by storing the validated isolated cache result
**`37b5ea361a7805a7` (1858s)**; the gate's own timing summary totals **30m57s**. A full-log audit
found **zero `FAILED:` markers** and zero JSON `"failed": [1-9]` rows. Durable evidence:
`/Users/spencer/repos/nsharp-worktrees/evidence/astra-c6ab6f2e/product-vscode-20260919.log`, with its
entry in the sibling `SHA256SUMS`.

| Gate stage | Result at `c6ab6f2e7`, 2026-09-19, VS Code enabled |
|---|---|
| Step 1 clean | pass (skipped clean — incremental) |
| Step 2 build | pass, 1m08s |
| Step 2b format contract | pass |
| Step 2c Systems throughput | **PASS: 12 cells, 0 failed**, tolerance **1.20x**, worst measured ratio **1.03x** (`rolling-hash` 64); load average `{ 2.11 2.21 1.79 }` on 10 cores; baseline unchanged (measured 2026-09-01 on an idle Apple M4 at `8cf40128a`) |
| Step 2d self-host front door | pass, 11m14s — `src/NSharpLang.Compiler.Core` **1342** diagnostics *(at the ceiling)*, `src/NSharpLang.Build.Tasks` **0** *(at the ceiling)*; `Compiler` and `Playground` BLOCKED behind `Compiler.Core`'s own front door and not counted |
| Step 3a compiler-service estate | **Failed: 0, Passed: 9291, Skipped: 0, Total: 9291** (17s, `NSharpLang.Compiler.Core.dll`) |
| Step 3a native sweep | **109 project rows, 4,536 passed, 0 failed, 1 skipped, 4,537 total**. The single skip is `tests/native/census-testrefs` (7 passed / 1 skipped / 8 total) |
| — gate-script contracts | `tests/native/gate-script-contracts` **38 passed, 0 failed, 0 skipped** |
| — ownership audit | `tests/native/ownership-audit` **25 passed, 0 failed, 0 skipped** |
| — compile-time benchmark | `tests/native/compile-time-bench` **74 passed, 0 failed, 0 skipped** — see the timing note below |
| Step 3b VS Code integration | bounded release-gate smoke (extension, diagnostics, hover, completion): **36 passing (42s)**, 0 pending/skipped |
| Steps 4–9 pack / templates / examples | pass — runtime and SDK packed, templates packed and installed, template project created and built, example projects and single-file examples built |
| Step 10 `nlc check` on examples | pass, 26 directories |
| Step 10b IL verification | **all 80 N# assemblies pass IL verification, no new errors vs baseline** |

**What this log does and does not say about compile-time timing.** The compile-time benchmark appears
in this gate only as the native row `tests/native/compile-time-bench`, reported as **74 passed, 0
failed, 0 skipped** — a functional result. The log prints **no timing verdict, no load reading and no
millisecond figures** for that row, so this run judged nothing at all about compile-time performance:
record it as 74 functional pass, timing **not judged**, and never as a timing pass. The only load
reading anywhere in this log (`load average { 2.11 2.21 1.79 }`) belongs to the Systems throughput
gate, which did pass its own tolerance check. The judged/unjudged figures recorded earlier in this
section belong to the earlier runs and are not restated by this log.

### Verified receipt: extension reload done; visual IDE proof STILL OWED

**Extension rebuild and reinstall — DONE. Rendered-UI visual verification — NOT DONE.**

The extension was rebuilt and reinstalled on **2026-09-19** via
`./scripts/reload-vscode-extension.sh` (`nsharp-0.6.0.vsix` built from this worktree at `c6ab6f2e7`,
installed to `~/.vscode/extensions/nsharp.nsharp-0.6.0`, VS Code 1.137.0, server process
`dotnet .../nsharp.nsharp-0.6.0/server/LanguageServer.dll --stdio` confirmed running).

**No screenshots were taken and no rendered UI was observed** — computer-use access to Visual Studio
Code was unavailable, so no red squiggle, Problems row, hover popup or completion widget has been
seen. The visual IDE proof this sequence requires therefore **remains owed**. What exists is
protocol-level evidence only, recorded in
`/Users/spencer/repos/nsharp-worktrees/evidence/astra-c6ab6f2e/visual-ide-20260919/RECEIPT.md`:

| Check | Protocol-level result — NOT a visual confirmation |
|---|---|
| Diagnostics on a deliberate error | `NL202` published, Error severity, range tight to the offending literal, docs URL attached |
| Diagnostics on a clean hello-world | **0** diagnostics, 0 parse errors, in the live IDE session |
| Hover | **4/4** correct (locals, declaration, call site), doc comment attached |
| Completion | **39** `string` members after `greeting.`, with return-type details and overload counts |
| Signature help | same-document user functions work; **null** for external/BCL members and for cross-file N# types |
| Output channel and server log | no exceptions, stack traces, crashes or `[ERR]` entries; two benign startup warnings |

**The signature-help gap is pre-existing, not a regression.** It behaves identically on
`systems-language` `9faf75a1c`, and is recorded as **SIGHELP** in `census-briefs/FOLLOWUPS.md`: the
C# `SignatureHelpHandler` reads only the current document's `SymbolsInfo`. The fix belongs in the
LanguageServer N# conversion (step 10 below) as a new N# overload-signature owner driven by the
project snapshot — **do not grow the C# handler**.

The user explicitly directed on 2026-09-19 to proceed with other work rather than block on VS Code
computer-use, which has been flaky. Proceeding is sanctioned; the visual proof stays an open debt and
must be produced before this closeout is called complete.

> **History, superseded.** An earlier VS Code-enabled attempt at `c6ab6f2e7` was **interrupted by the
> user at the throughput stage** after a fresh build and format and terminated with exit 143
> (`astra-c6ab6f2e-product-vscode.log`). An interrupted gate is neither a pass nor a failure receipt.
> It is retained here as history only; the complete 2026-09-19 run recorded above supersedes it as
> the current state.

### Converter census at `c6ab6f2e7` — a pre-seed census, not proof of migration

`ROOT=/Users/spencer/repos/nsharp-worktrees/census-merge ./convert-all.sh` (exit 0) and the follow-on
`run.sh census` were run on **2026-09-19** with converter `b9a49e0` and
`nlc 0.1.0+c6ab6f2e7b69cda86c7503736c186b0e9ea647db` — the stale `88cf7534c` CLI binary sitting in
the worktree was rebuilt first so the census measured the integration tip. Receipt:
`evidence/astra-c6ab6f2e/converter-20260919/RECEIPT.md`.

**51 converted files, 86 diagnostics, 11 `// CONVERT:` stubs** — runtime **0**, languageserver **10**,
cli **26**, playground-wasm **22**, tests **28** — against **109** diagnostics on 2026-09-14.

**This is a census taken before the reseed, not evidence of migration.** It measures converter output
against the pre-seed compiler and closes nothing: CLI/LanguageServer reconversion stays seed-blocked,
45 of the 86 rows are missing-reference-root artifacts rather than language gaps, and the `tests` row
is not comparable to 2026-09-14 because the C# unit suite was deleted (19 files → 3). `census-merge`
was clean before and after the run and nothing was committed in either repo. The converter reruns
required after the first push and again after the reseed are still outstanding.

### Retirement precheck — read-only; nothing has been retired

`census-briefs/FABLE-RETIREMENT-AND-STALE-LANES-REVIEW.md` (2026-09-19, read-only snapshot, no ref or
worktree touched) checked all 19 manifest candidates against `c6ab6f2e7`: **19 of 19 clean**
(`git status --porcelain=v1` produced zero lines), **19 of 19 ancestors** with 0 unique commits each,
and no process holding a cwd inside any of them. Four stale lanes are separately recommended for
retirement: `codex/toolchain-integration` (`5ebd18b72`, fully absorbed), `codex/check-remaining-assertions`
(`537e248ac`, tag before removal), `codex/cli-native-owner` (`89ed8508f`) and `codex/runtime-owner`
(`0e61b67fe`) — all superseded, none to be replayed. `census-merge` and the unmerged
`census/lsconvert-source-wip` (`f81e37df2`) are confirmed must-preserve.

**Nothing has been retired.** Every row must be re-checked against the **actual pushed ref** before
any worktree or branch is removed.

### Wave-12 lane classification

The historical lane tables and findings retained below are evidence, not a dispatch board. No
historical `Active`, `Queued`, `final gate pending`, owner name or worktree claim in those sections
overrides this table.

**Rows updated 2026-09-19 for the pushed, reseeded tip `d932566aa`.** The five rows whose state
actually moved are RESEED, RETIREMENT, PUSH/GATES, CONVERTER CENSUS and the new SEED-HIDDEN DEFECTS
row; the rest are unchanged and are re-validated by the post-seed gates.

| Lane | State at `d932566aa` | Receipt |
|---|---|---|
| RESEED | **DONE** after three failures | `reseed-9b4c46174` (NL103 `OfType`) → `b73d55d41`; `reseed-b73d55d41` (2/9295 duplicate MSBuild attribute) → `f369e5d22`; scratch CS0433 empty `Program` holders → `ca8381cdb`; `reseed-5d9e2de4b` SUCCESS, both stages 0W/0E, estate 9295/0, exact bootstrap == stage2 == restored-cache hash equality. Seed commit `6a50c373e`, packed source `5d9e2de4b`. |
| SEED-HIDDEN DEFECTS | **New durable finding** | Three defects reached a green gate and were caught only by the reseed, because estate probes are compiled by the seed. `census-duplicate-declarations` had pinned one of them and failed when it was fixed; corrected in `d932566aa`. |
| RETIREMENT | **DONE** | 19 census worktrees/branches + `codex/toolchain-integration` removed after clean/ancestry/in-use checks **against the pushed ref**. `check-assertions`, `cli-native-owner`, `runtime-owner`: worktrees removed, branches kept and tagged `archive/<branch>`. `census/lsconvert-source-wip` kept and tagged `archive/census/lsconvert-source-wip` — sole copy of the non-compiling full LS conversion. |
| PUSH / POST-SEED GATES | **DONE** | `9b4c46174` then `d932566aa` pushed to `origin/systems-language`. First non-VS gate on the seed FAILED 1 at `6a50c373e`; both gates then PASS at `d932566aa` — non-VS exit 0 / 31m39s / cache `e0e1da00c8cb7ec0`, VS-enabled exit 0 / 32m30s / cache `d6778e34d329aa6c`, 36 VS Code smoke passing. |
| CONVERTER CENSUS | **Post-seed run DONE; reconversion still OPEN** | 51 files / 86 diagnostics / 11 stubs at `nlc +d932566aa` — **zero delta** against the pre-seed census on every row. No C# input changed, so this is a reproducibility and no-seed-regression result, not migration. |
| EXTENSION RELOAD / VISUAL IDE | **OWED** | Post-seed reload FAILED (VS Code would not exit within 30s); the installed extension is still the 13:01 build from `c6ab6f2e7`. No rendered UI has ever been observed. |
| IVT2 · SIGHELP · CLI/LS/Playground/Runtime/Wasm conversion | **OPEN** | Unchanged; see the rows in the historical table below and steps 9–11 of the sequence. |

The historical wave-12 table follows and is retained as written at `c6ab6f2e7`.

| Wave-12 lane | Classification | Evidence / required follow-up |
|---|---|---|
| CLICONVERT | Accepted checkpoint | The N# `DocCommand` owns project loading, symbol ordering, HTML/JSON/text results and browser launch. CLI/LanguageServer reconversion stays open until the seed is actually republished. |
| ENUMATTR | Accepted historical implementation | Preserve the enum declaration/member attribute evidence; revalidate through the final gates and conversion results. |
| SELFHOST | Accepted repair; front door still a backlog | `88cf7534` lowered the ceiling to 1,342 after a 946-file report (1,329 errors, 13 warnings) with zero stable-identity additions and 32 removals against the fixed 1,374 baseline. The gate re-proved 1,342 at `c6ab6f2e7`. The ceiling is a backlog to drive to zero, never a target and never to be raised. |
| TESTSCONVERT / DEV-EVIDENCE | Accepted migration / checkpoint | Native N# tests own the migrated C# unit coverage; the estate wrapper rejects zero-executed, unmatched, skipped-only, split and mixed-failure output. Gate-script contracts are 38/38 at this tip. |
| GENERICSIG, COMPLETION, EDITOR PROJECTIONS | Accepted checkpoints | Preserve the focused, query, raw-type/editor-detail and read-only visual evidence; the affected-editor proof must be repeated with the IDE gate. |
| INITREQ, STATICRECV, NAMEDARGS | Accepted checkpoints | `2db3c5f0`, `96c51cef` and `b21fd876` are integrated and are ancestors of `c6ab6f2e7`. |
| CAPTURE3 | Accepted implementation checkpoint | Generic-local `e75764af`, async `2a28e38e`, sibling `1550db30`, loop `f0c0aa55` and ledger `fd08ab819` are integrated and are ancestors of `c6ab6f2e7`. `ColumnarModifiedMemberReferenceLedger` remains the one assembly-local ledger; it is carried through `BodyFacts`, forwards ordinary async DirectCall, and expands no public host signature. Documented baseline refusals (postfix mutation of a lambda's own parameter or local, sync and async) remain limits. |
| BENCHMARK STAGE / WARMUP / ORDER | Accepted checkpoints | The schema-2 phase guard (`602da978`), measured baseline (`edcd6294`), warmup coverage (`fc2ae92a`), stage ordering with the throughput block moved ahead of the long self-host/native stages (`d8553f18`) and the reviewed delivery/head repin (`2602fa07`) are integrated. |
| INSTALLER ITERATION | Accepted checkpoint | `c6ab6f2e7` replaces the asynchronous package producers in `packages.sh` and `setup-local.sh` with synchronous array iteration, after a proven Bash 3.2 `EINTR` silent-helper failure. Contracts 38/38, ownership 25/25. |
| RESEED CACHE VERIFICATION | Script contract accepted; actual reseed OPEN | `46e22009` fail-closes on missing, mismatched or invalid hash evidence and compares restored SDK/runtime cache nupkgs against bootstrap bytes before each build. No bootstrap seed, shared cache or actual reseed has been touched. |
| IVT2 | OPEN — after the actual reseed | No IVT2 validation is recorded. COMPLETION's historical IVT 14 evidence does not substitute for it. |
| CLI / LanguageServer / Playground / Runtime / Wasm-hosting conversion | OPEN | Owner and assertion conversion is unfinished. Preserve `census/lsconvert-source-wip` (`f81e37df2`, not an ancestor of `c6ab6f2e7`, no registered worktree) until post-seed reconversion gives it a documented disposition. |
| SIGHELP | OPEN — pre-existing defect, fix in the LS conversion | `textDocument/signatureHelp` returns null for external/BCL members and cross-file N# types because the C# `SignatureHelpHandler` reads only the current document's `SymbolsInfo`. Identical on `9faf75a1c`, so not a regression. Fix as a new N# overload-signature owner over the project snapshot during the LanguageServer conversion, with native regressions; do not grow the C# handler. |
| CONVERTER CENSUS | Pre-seed census taken; reruns OPEN | 2026-09-19 census at `c6ab6f2e7` (converter `b9a49e0`): 51 files / 86 diagnostics / 11 stubs, versus 109 on 2026-09-14. A census, not a migration proof. Rerun after the first push and again after the reseed. |
| RETIREMENT PRECHECK | Precheck done; retirement OPEN | 19/19 candidates clean ancestors of `c6ab6f2e7` with 0 unique commits; four stale codex lanes recommended for retirement; `census/lsconvert-source-wip` preserved. Nothing removed; recheck every row against the actual pushed ref. |
| FINAL GATES / PUSH / RETIREMENT | Gates PASSED; visual IDE proof, push and retirement OPEN | Both required fresh gates have now passed at `c6ab6f2e7` — the non-VS gate and the VS Code-enabled gate of 2026-09-19. The visual IDE proof is still owed, and nothing has been pushed, reseeded, reconverted or retired. See the sequence below. |

### Accounting — the repin is now unblocked and still owed

Checkpoint accounting carried from `88cf7534` is catalog 108 (98 compiler plus 10 linter), 103 native
projects, corpus pin 134, and a net 10,919 C# lines removed versus `systems-language`; no Runtime
source changed. **These numbers are now two moves stale.** The `c6ab6f2e7` gate reported **109
native rows**, and the post-seed gates at `d932566aa` report **110** (the added project is
`tests/native/source-typed-explicit-generic-extension`, landed with `b73d55d41`). The compile-time
bench corpus pin was separately corrected by `23ed2f0bc` from **134** to its real **135** — the pin
had missed that same new project, so the row whose job is to notice a corpus change was the one
thing the change did not reach. The reseed has
now happened, so the repin is unblocked: re-measure and repin catalog, native-project, corpus,
line-delta and ownership facts. Do not infer a Runtime conversion or a completed production
migration from any of these numbers.

### Remaining required sequence — steps 1 and 3–8 have receipts; 2, 9, 10 and 11 do not

**Updated 2026-09-19.** Steps 3 through 8 have executed and are struck through below. What remains
is step 2's visual proof, the failed post-seed extension reload, and steps 9–11, none of which has
started.

1. ~~**Fresh VS Code-enabled product gate** at the accepted tip, run serially with every worker
   stopped.~~ **DONE 2026-09-19** — `./scripts/test-all.sh --commit`, VS Code enabled, EXIT 0, isolated
   cache result `37b5ea361a7805a7` (1858s); receipt above. Compile-time timing was not judged by that
   run and must not be recorded as a timing pass.
2. **Extension reload and visual IDE verification.** Pre-seed rebuild and reinstall — ~~DONE
   2026-09-19 via `./scripts/reload-vscode-extension.sh` (`nsharp-0.6.0.vsix`)~~. **The post-seed
   reload FAILED** and must be redone: VS Code would not exit within 30s, so the installed extension
   is still the 13:01 build from `c6ab6f2e7` and carries a pre-seed language server. **Visual
   verification still OWED:** observe the affected completion, hover, signature-help and diagnostic
   behavior in the real rendered editor and capture screenshots — after a successful reload, so that
   what is observed is the reseeded build. Protocol-level probes and unit tests are not sufficient.
3. ~~**Tracked closeout documents**, reviewed root commit, fast-forward the main checkout from
   `census/merge`, and push the first finalized integration ref.~~ **DONE 2026-09-19** — `9b4c46174`
   (docs closeout) and then `d932566aa` pushed to `origin/systems-language`; `census/merge` equals
   that ref.
4. ~~**Converter rerun after each push**, from the retained integration worktree
   (`ROOT=/Users/spencer/repos/nsharp-worktrees/census-merge ./convert-all.sh`).~~ **DONE 2026-09-19
   at `d932566aa`** — 51 / 86 / 11, zero delta; `evidence/seed-6a50c373e/converter/RECEIPT.md`. Note
   that the previously dirty `out/languageserver/project.yml` was absorbed by the pre-seed run and no
   longer appears; the converter repo's remaining 22 dirty paths are prior regenerated output.
   **This run did not close LS/CLI reconversion** — nothing was converted, so nothing moved.
5. ~~**Worktree retirement — 19 candidates**, re-checked per row against the actual pushed ref.~~
   **DONE 2026-09-19** — 19 census worktrees/branches plus `codex/toolchain-integration` removed;
   three stale lanes kept as `archive/<branch>` tags; `census/lsconvert-source-wip` kept and tagged.
   `census/merge` preserved.
6. ~~**Actual two-pass reseed** (`./scripts/reseed.sh`), root alone with no agents running.~~ **DONE
   2026-09-19 at `5d9e2de4b`, after three failed attempts** — both stages 0 warnings / 0 errors,
   estate 9,295/0/0, exact bootstrap == stage-2 == restored-cache hash equality. **Next time:**
   scratch mode requires temporarily repointing the root `NuGet.config` feed; that step is
   undocumented and is filed as a runbook/script fix in the pending list below.
7. ~~**Repin** bootstrap fingerprints and the ownership head, and commit the exact packed source, the
   bootstrap `.nupkg` files and `SHA256SUMS` together.~~ **DONE** — seed commit `6a50c373e` from
   packed source `5d9e2de4b`; Sdk `bf4a1f9c…0154c4`, Runtime `35f1a227…3ad9f6` (full digests above);
   ownership head `head-v2:5ce298ee5fe53bf8`, audit 25/25.
8. ~~**Post-seed gates** on the bootstrap commit.~~ **DONE 2026-09-19** — the first non-VS gate on
   the seed itself FAILED 1 and produced the fix `d932566aa`; both gates then passed at `d932566aa`
   (non-VS exit 0 / 31m39s / `e0e1da00c8cb7ec0`; VS-enabled exit 0 / 32m30s / `d6778e34d329aa6c`,
   36 VS Code smoke passing), the ref was pushed and the converter was rerun. **The reload and
   visual IDE proof this step also required are the parts that did NOT happen** — see step 2.
9. **IVT2** in an isolated worktree from the accepted tip
   (`STREAM-IVT2-emit-internals-visible-to-and-qualified-internals.md`): resolve actual accessibility by
   reflection, preserve the semantic non-friend refusal, cover source grants, the metadata attribute and
   editor/query behavior, and keep one `InternalsVisibleToGrants` owner.
10. **Remaining CLI, LanguageServer, Playground, Runtime and Wasm-hosting owner and assertion
    conversion**, refreshed from the exact tip with explicit `ROOT` and serialized converter ownership.
    Compiler defects either worker finds are reported to root for exclusive ownership; the two workers
    must not edit shared compiler sources concurrently. No legacy fallback, no C# or allowlist growth,
    and no boundary-only slice that leaves the old owner required. Record the disposition of
    `census/lsconvert-source-wip` only after the post-seed reconversion runs.
11. **SIGHELP**, inside step 10's LanguageServer conversion: a new N# overload-signature owner that
    returns per-overload parameter rows from the project snapshot, deleting the C# `SymbolsInfo` path,
    with native regressions in `tests/native/language-server-handlers` for external instance and static
    members, overloads, active parameter and cross-file types. Do not grow the C# handler, and fix
    `website/docs/getting-started.md:165`, which the current behavior contradicts.

### Evidence — filled receipts and the placeholders still open

**Updated 2026-09-19.** Six placeholders are now filled with executed results. The remaining
placeholders are still placeholders: no line below is a receipt until an executed result replaces
it.

- **FILLED — first main fast-forward and remote push:** `9b4c46174` (docs closeout) then
  `d932566aa`, both pushed to `origin/systems-language` on 2026-09-19. `census/merge` equals
  `origin/systems-language` at `d932566aa`.
- **FILLED — retirement removal receipts against the pushed ref:** 19 census worktrees and branches
  plus `codex/toolchain-integration` removed after per-row clean, ancestry and in-use checks against
  the **pushed** ref. `codex/check-remaining-assertions`, `codex/cli-native-owner` and
  `codex/runtime-owner`: worktrees removed, branches kept and tagged `archive/<branch>`.
  `census/lsconvert-source-wip` kept and tagged `archive/census/lsconvert-source-wip` as the sole
  copy of the non-compiling full LS conversion. `census/merge` preserved.
- **FILLED — reseed stage-one and stage-two receipts:** three failures then success. `reseed-9b4c46174`
  FAILED stage-1 self-rebuild on `NL103` `OfType` → `b73d55d41`; `reseed-b73d55d41` FAILED the estate
  2/9295 on a duplicate MSBuild attribute → `f369e5d22`; scratch validation found empty public
  `Program` holders breaking the CLI build with `CS0433` → `ca8381cdb`; bench corpus repin
  `23ed2f0bc` (135 projects); runbook note `5d9e2de4b`. `reseed-5d9e2de4b` **SUCCESS**: both stages
  0 warnings / 0 errors, tests-enabled estate **9,295 passed / 0 failed / 0 skipped**, and exact hash
  equality bootstrap == stage-2 == restored cache. Logs: `evidence/reseed-*/reseed.log` and
  `evidence/seed-6a50c373e/reseed.log`.
- **FILLED — bootstrap fingerprint and ownership-head repin, and the exact packed-source commit:**
  **packed source `5d9e2de4b`**, **seed commit `6a50c373e`**. `NSharpLang.Sdk.0.1.0.nupkg`
  **`bf4a1f9c663aa1343306137adb761c440b767ba7aa02115e9e4f6fc24a0154c4`**,
  `NSharpLang.Runtime.0.1.0.nupkg`
  **`35f1a2271f2498fbaf79bd2cfc088ed025bd4836c28d592c661cbc6bdd3ad9f6`**; the `.nupkg` files and
  `SHA256SUMS` were committed together. Ownership head **`head-v2:5ce298ee5fe53bf8`**,
  ownership-audit **25/25**.
- **FILLED — post-seed gate outcomes and the post-seed push:** first non-VS gate at the seed
  `6a50c373e` **FAILED 1** (`census-duplicate-declarations` pinned the old empty `Catalog.Program`
  holder) → test corrected in `d932566aa`; then at `d932566aa` non-VS **PASS exit 0, 31m39s, cache
  `e0e1da00c8cb7ec0`** and VS-enabled **PASS exit 0, 32m30s, cache `d6778e34d329aa6c`**, with **36**
  VS Code smoke tests passing. Both: throughput 12/12 at worst 1.04x; self-host `Compiler.Core`
  **1342** and `Build.Tasks` **0** at the ceiling; estate **9,295/0/0**; native sweep **110 rows,
  4,552 passed, 0 failed, 1 skip**; ownership **25/25**; IL **80 assemblies**, no new errors;
  compile-time **74 functional pass, timing NOT judged**. Contracts are **not printed** by either
  log. Logs and `SHA256SUMS`: `evidence/seed-6a50c373e/`.
  **This line does NOT include the visual IDE proof that step 8 also required** — see the two owed
  items below.
- **FILLED — post-seed converter rerun:** 2026-09-19, converter `b9a49e0` with `nlc +d932566aa`
  (the worktree binary was stale at `+6a50c373e` and was rebuilt first), 51 files / 86 diagnostics /
  11 stubs (runtime 0, languageserver 10, cli 26, playground-wasm 22, tests 28) — **zero delta**
  against the pre-seed census on every row and every code. `evidence/seed-6a50c373e/converter/RECEIPT.md`.
  A reproducibility and no-seed-regression result, **not** proof of migration; no owner was converted.
- **OWED — post-seed extension reload FAILED:** `reload-extension.log` records *"VS Code is still
  running after 30s"*; the installed extension remains the **13:01 build from `c6ab6f2e7`**. Must be
  redone before any post-seed IDE observation means anything.
- [PLACEHOLDER: rendered-editor visual IDE proof — screenshots of the affected completion, hover,
  signature-help and diagnostic behavior, taken against a successfully reloaded post-seed extension.]

The pre-seed evidence list follows, retained as written at `c6ab6f2e7`.

- **FILLED — fresh VS Code-enabled gate:** `c6ab6f2e7`, 2026-09-19, EXIT 0, isolated cache result
  `37b5ea361a7805a7` (1858s), timing summary 30m57s; 12/12 throughput cells at worst ratio 1.03x;
  self-host 1342/0 at the ceiling; estate 9291/9291; native sweep 109 rows / 4,536 passed / 0 failed /
  1 skip; contracts 38/38; ownership 25/25; VS Code smoke 36 passing; IL 80 assemblies; compile-time
  74 functional pass with **no timing verdict emitted**. Log: `product-vscode-20260919.log` + `SHA256SUMS`.
- **PARTIALLY FILLED — extension reload done, visual IDE proof OWED:** `nsharp-0.6.0.vsix` rebuilt and
  reinstalled 2026-09-19 via `./scripts/reload-vscode-extension.sh`; protocol-level evidence only in
  `visual-ide-20260919/RECEIPT.md` (NL202 on a deliberate error, 0 on clean hello-world, hover 4/4,
  completion 39 members, signature help null for external/BCL and cross-file — SIGHELP). **No rendered
  UI was observed and no screenshots exist.**
- **FILLED — pre-seed converter census:** 2026-09-19, converter `b9a49e0` with `nlc +c6ab6f2e7`,
  51 files / 86 diagnostics / 11 stubs (runtime 0, languageserver 10, cli 26, playground-wasm 22,
  tests 28) versus 109 on 2026-09-14 — `converter-20260919/RECEIPT.md`. A census, **not** proof of
  migration; the post-push and post-seed reruns are still open.
- **FILLED — retirement precheck only:** 19/19 candidates clean ancestors with 0 unique commits, four
  stale codex lanes recommended for retirement, `census/lsconvert-source-wip` preserved —
  `census-briefs/FABLE-RETIREMENT-AND-STALE-LANES-REVIEW.md`. **Nothing retired.**
- ~~[PLACEHOLDER: rendered-editor visual IDE proof.]~~ **Still open** — restated in the post-seed
  list above, now also blocked on redoing the failed reload.
- ~~[PLACEHOLDER: first main fast-forward and remote push receipt.]~~ **FILLED 2026-09-19** — see
  the post-seed list above.
- ~~[PLACEHOLDER: converter revision, `ROOT` input, and results after the first push.]~~ **FILLED
  2026-09-19** — see the post-seed list above.
- ~~[PLACEHOLDER: per-row clean/ancestor checks against the pushed ref and removal receipts for the
  19 retirement candidates.]~~ **FILLED 2026-09-19** — see the post-seed list above.
- ~~[PLACEHOLDER: reseed stage-one and stage-two package/cache/bootstrap SHA-256 receipts, package
  identities, and the tests-enabled estate result.]~~ **FILLED 2026-09-19** — see the post-seed list
  above.
- ~~[PLACEHOLDER: bootstrap fingerprint and ownership-head repin, and the exact packed-source
  commit.]~~ **FILLED 2026-09-19** — packed source `5d9e2de4b`, seed commit `6a50c373e`; digests and
  ownership head in the post-seed list above.
- ~~[PLACEHOLDER: post-seed non-VS and VS Code-enabled gate outcomes, and the post-seed push and
  converter run.]~~ **FILLED 2026-09-19 except the visual IDE proof**, which that placeholder also
  named and which remains owed.
- [PLACEHOLDER: IVT2 result.]
- [PLACEHOLDER: SIGHELP — the N# overload-signature owner, the deleted C# `SymbolsInfo` path, and the
  native regressions covering external, overloaded and cross-file signature help.]
- [PLACEHOLDER: final CLI/LanguageServer/Playground/Runtime/Wasm-hosting conversion results, remaining
  diagnostics or stubs, and the `census/lsconvert-source-wip` disposition.]

### Remaining pending work (2026-09-19) — nothing here is claimed complete

| Pending item | Why it is open |
|---|---|
| **Rendered visual IDE proof** | Never produced. No screenshot has ever been taken in this closeout. |
| **Post-seed extension reload** | FAILED — VS Code would not exit within 30s; the installed extension is still the 13:01 build from `c6ab6f2e7`. The visual proof cannot be meaningful until this succeeds. |
| **IVT2** | Not started. Was gated on the actual reseed, which has now happened, so this is unblocked. |
| **SIGHELP — N# overload-signature owner** | Not started; belongs inside the LanguageServer conversion. |
| **Remaining CLI / LanguageServer / Playground / Runtime / Wasm-hosting owner and assertion conversion** | Not started. The post-seed converter census measured zero movement precisely because none of it has happened. |
| **Runbook/script fix: reseed scratch mode and the root `NuGet.config` feed** | Reseed scratch mode requires **temporarily repointing the root `NuGet.config` feed**. This is undocumented, was discovered by debugging, and must be written into the reseed runbook or automated in `scripts/reseed.sh` so the next reseed does not rediscover it. |
| **Language decline: `this` as a value** | On the emit-only columnar path, `this` used as a value declines at `parse.struct`. Filed in `census-briefs/FOLLOWUPS.md`. |
| **Language decline: call-expression receiver** | `MakeList().OfType<T>()` — a call expression as the receiver of an extension call — still declines, after `b73d55d41` fixed only the non-generic extension-slot receiver relation. Filed in `census-briefs/FOLLOWUPS.md`. |
| **Gate-script contracts at `d932566aa`** | The two post-seed logs print no contracts row, so 38/38 is carried from `c6ab6f2e7` and is unmeasured at the current tip. Re-measure at the next gate. |
| **Accounting repin** | Catalog, native-project count, corpus pin, line delta and ownership facts still carry `88cf7534` numbers; the native sweep has now moved 109 → 110 rows. Re-measure. |

## Historical managed-toolchain conversion record

Everything below this heading is preserved historical evidence from the 2026-09-09 authorization
onward. Its owner names, lane states, worktree paths, "Active"/"Queued"/"pending" labels and test
totals describe the moment they were written. They are superseded by the census wave-12 status above.

## Historical scope and completion

Convert remaining managed Compiler facade, Build.Tasks, CLI, LanguageServer, Playground and Runtime
production ownership to N#. Evaluate and convert the Wasm export host where supported; document any
strictly mechanical host boundary. SDK/Templates remain native packaging configuration; change their
integration only as required by these ports. VS Code extension migration is deferred at very low priority.
NativeAOT, a new metadata writer and unrelated branch initiatives remain separate.

Migrate canonical C# assertions with each owner, including setup/state, ordering, exact diagnostics,
outputs and failure/lifecycle behavior. Remove replaced assertions and unused helpers after N#
successors execute. No new C# behavior, tests, helpers, adapters, callbacks or fallbacks. Intentional
C# interoperability fixture inputs may remain where they prove cross-language behavior.

Move complete classes or connected methods with necessary helpers and state. Preserve public and
package contracts; don't treat changing project extensions as completion. Compile actual proposed
N# sources to prove prerequisites; implement required compiler fixes in N#. Root serializes shared
compiler prerequisites, SDK seeds/feed writes, ratchets and integration gates. Use dev.sh and targeted
native tests while implementing. Commit coherent green pieces; root reviews and runs fresh required
integration gates and IDE verification before push. Retire completed worktrees/branches after checking
active users, unique history and dirty files, preserving evidence and recoverable unfinished work.

## Historical lanes (2026-09-09)

Base: 06186dc6d (includes bootstrap/CI work; preserve it).

| Area | Owner | Worktree / branch | Status |
|---|---|---|---|
| Complete Compiler service facade and assertions | Luna Max toolchain_facade | Integrated at 5691697ce; old lane retired | Four C# owners and remaining C# assertion removed; root combined build and 98 native tests pass; private package consumer passes; final gate pending |
| Complete LoadProjectConfig / LoadProjectReferences and assertions | Luna Max toolchain_build_tasks | Integrated; original lane retired | Owners and canonical SDK assertions integrated into candidate; 8,028 Core tests pass; 20 native SDK tests pass; final integration gate/push pending |
| CLI command owners and assertions | Luna Max toolchain_facade | CheckCommand integrated through a46c04d1d; FixCommand next | CheckCommand C# owner and 559-line C# test file removed; lane native contracts 123/123; array correction integrated through 6b3f4d669; root combined compiler canonicals pass 8,075/8,075 |
| LSP signature/services | Queued | Signature branch preserved | Refresh unique signature work without restarting |
| Playground compiler and interpreter | Luna Max toolchain_build_tasks | /private/tmp/nsharp-agent-wt/toolchain-playground; codex/toolchain-playground | Integrated through 5480fc33a; both C# owners deleted; lane 150 native assertions pass; root combined build/native verification pending |
| Runtime ABI and assertions | Luna Max toolchain_build_tasks | Starting codex/runtime-owner from 5480fc33a | Convert four remaining managed Runtime owners with CLR identity/behavior preserved; root owns seed publication |
| Wasm host | Queued | No new worktree yet | Prove export integration and retain only necessary mechanical boundary |

Assessment and actual probe evidence: /private/tmp/nsharp-other-projects-assessment-20260909/ASSESSMENT.md.
Unique held config/signature work remains preserved until integrated or safely archived.
The two clean query worktrees and branches were removed after confirming both tips are ancestors
of systems-language, have no active task users and contain only ignored build outputs. Cleanup
receipt: /private/tmp/toolchain-query-worktree-cleanup-20260909.json.
The completed SDK worktree and branch are also retired: its owner confirmed no active use,
the checkout was clean apart from ignored build outputs, and all three commits were patch-equivalent
to integration commits. Recoverable original history is in the verified bundle
/private/tmp/toolchain-build-tasks-retired-20260909.bundle.
The completed facade worktree/branch is retired after confirming a clean checkout and all six
lane commits patch-equivalent to integrated commits. Its agent moved to the separate check-command
worktree. Verified recovery bundle: /private/tmp/toolchain-facade-retired-20260910.bundle.
A finished lane is not completion of this whole objective.

## Historical integration findings

- Facade keeps its public Compiler assembly/API. Actual imported Core static-call probe passes;
  the remaining library interop work is ordinary property/member handling, not a Core call allowlist.
- Proven facade prerequisites: oblivious generic argument compatibility, nullable enum parameter/
  value/constructor binding. Root verified these with all 8,021 Core canonical tests passing (0 failed/skipped) using an
  isolated SDK candidate. Receipt: /private/tmp/toolchain-facade-prerequisite-receipt.json.
  This is prerequisite evidence; no seed publication or complete facade acceptance is claimed.
- Ordinary external member binding is integrated with exact public getter/field selection and
  builder-bound receiver rejection. Combined compiler assertions pass 8,039/8,039 after the
  SortedDictionary.Keys contract update; nominal Dictionary.KeyCollection rejections remain.
  Receipt: /private/tmp/toolchain-integrated-member-receipt-r3.json. Facade project/package routing
  remains incomplete, so this does not mark the whole facade area accepted.
- MSBuild owner commit also preserves exact OutputAttribute metadata through the N# parser and
  emitter. Full dictionary metadata is retained by the original TaskItem constructor shape.
  The Build.Tasks project now contains no C# source; its remaining empty assembly and MSBuild
  project are mechanical dependency-copy/package boundaries. SDK UsingTask resolves both owners
  directly from Compiler.Core.
- Playground's literal-field and ordinary value-receiver prerequisites pass all 8,048 N# Core
  canonical tests (zero failed/skipped) at c914a56fe. Evidence:
  /private/tmp/toolchain-integrated-const-value-canonicals-r8.log. The prior four failures/crash
  were traced to invalid IL for field writes through out-reference parameters; initializing
  local objects before assigning the out parameters preserves the intended source behavior.
  Underlying emitter defect evidence remains /private/tmp/core-r7.il, with its correction
  investigation assigned alongside the proven generic safe-cast prerequisite. No SDK seed is
  published from this candidate; complete Playground ownership remains in progress.
  Const completion/diagnostic changes require the IDE-enabled integration gate and visual
  verification; extension migration itself remains deferred.
- Closed generic safe casts are integrated through the canonical scoped type resolver, with
  reference-target checks and no ordinary-resolution fallback. All 8,051 Core assertions pass
  at 0f9e88185: /private/tmp/toolchain-integrated-generic-cast-canonicals-r1.log.
  A subsequent test-only revision makes rejection fixtures reach the cast expression rather
  than fail in return signatures; all three focused canonical cases pass at ffec3c5e0:
  /private/tmp/toolchain-integrated-generic-cast-body-tests-r1.log.
- Facade package identity/readme metadata now projects through N# configuration, restore and
  MSBuild task owners. All 8,055 Core assertions pass at 249563ee1 after preserving the original
  template bytes: /private/tmp/toolchain-integrated-package-canonicals-r2.log. Private SDK boundary
  tests pass 20/20: /private/tmp/toolchain-facade-sdk-native-r1.log. Those native checks used
  explicitly substituted private fixture binaries, so final clean production/package verification
  remains required.
- Closed generic catalog admission now validates the definition and arguments in the selected
  reflection universe, preserving exact identities instead of requiring a constructed-name lookup
  through the defining assembly. All 8,057 Core assertions pass at 8b968d92a:
  /private/tmp/toolchain-integrated-catalog-canonicals-r1.log. This resolves the facade's generic
  return-type blocker.
- Ordinary external ref/out calls now use the semantic call planner and lexical managed addresses;
  no loaded-assembly name scan or per-kernel adapter was added. Runtime tests cover mutation,
  nested argument evaluation, exact modifier matching, out initialization and uninitialized-ref
  rejection. All 8,068 Core assertions pass at ce44d49b8:
  /private/tmp/toolchain-integrated-static-byref-canonicals-r1.log. The facade can call the existing
  completion-prefix kernel directly; final owner/package integration remains in progress.
- The complete facade is integrated at 5691697ce with portable Core project references, SDK-supplied
  Runtime dependency, original Compiler.dll/NSharpLang.Compiler identities and no-PDB package routing.
  Lane native suites pass 79 query + 5 reference + 13 completion + 1 query-completion tests; the
  private package consumer builds/runs. The source API retains method sets, arities and defaults,
  but parameters previously named `file` are `fileName`: `file` is an N# keyword and the current
  language has no escaped-identifier syntax. Positional/binary callers are unchanged; named-argument
  source callers require that spelling change. This source-compatibility limitation is explicit.
  Root combined CLI build passes with zero warnings/errors, and all four native suites pass again
  against the real integrated outputs: /private/tmp/toolchain-integrated-facade-build-r1.log and
  /private/tmp/toolchain-integrated-facade-{query,reference,completion,query-completions}-r1.log.
  The next lane is complete CheckCommand ownership (Execute, IL verification and errors), including
  canonical CLI contracts; accepted query migrations remain intact.
- Playground's shared declaration-name helper is integrated at 006c4cc36, with all 20 focused
  Core canonical tests passing: /private/tmp/toolchain-integrated-playground-helper-canonicals-r1.log.
  Corrected private owner probes pass 34 tooling + 116 diagnostic-span tests; final project routing
  and C# owner deletion remain in progress.
- All five IlSdkToolchainTests.cs cases now have N# successors and the C# file is removed in the
  integration candidate. Review retained XML UnitTestResult/outcome semantics and removed new
  assertions that merely mirrored private field names. All 20 native SDK tests pass against a private package (22.7s). Receipt:
  /private/tmp/toolchain-integrated-sdk-receipt-r1.json. Final fresh integration gate remains pending.
- Concurrent release task owns packaging/bootstrap delivery fixes and its clean-snapshot gates.
  All accepted release fixes through dc7efda2 are integrated into this candidate. GitHub run
  34424070745 and its seven-asset unofficial prerelease passed verification; the remote hold is
  lifted. This candidate still requires its own fresh integration gate before push. Root serializes
  SDK seed/feed writes and retires lane worktrees only after their changes are accepted.

- CheckCommand is integrated through a46c04d1d. Execute, IL verification, cleanup and error output
  now reside in N#; all 559 lines of CheckCommandTests.cs are replaced by native process assertions.
  Review restored exact JSON trailing bytes and diagnostic-write/elapsed-evaluation order, and
  removed global temporary-directory count assertions that race concurrent processes. Lane native
  contracts pass 123/123; root default dev.sh build rejects GetArgumentSummary and FromCompilerError with NL402.
  Evidence: /private/tmp/toolchain-integrated-check-build-r1.log. The owner must resolve that
  integration gap before gate acceptance. No shared SDK seed or push yet.

- Runtime assembly pairing is integrated at 4244403ac. Runtime handles match selected metadata
  by exact assembly identity and MVID; known reference-assembly layouts retain their paired
  implementation behavior, and identical modules retain compiler-context preference across paths.
  All 8,070 Core canonical assertions pass (zero failed/skipped):
  /private/tmp/toolchain-integrated-runtime-pair-canonicals-r1.log.
- Playground compiler/interpreter ownership is integrated through 5480fc33a. Both C# files
  (1,505 lines) are deleted. Lane tests execute 34 tooling and 116 diagnostic assertions successfully
  against matching project outputs; root clean combined verification remains required.
  Receipts: /private/tmp/playground-native-tooling-artifact-r2.log and
  /private/tmp/playground-native-diagnostic-artifact-r2.log.

- Retired the clean CheckCommand worktree and codex/check-command-owner branch after confirming
  all five commits are patch-equivalent in integration and the owner moved to the FixCommand
  worktree. Verified history bundle: /private/tmp/check-command-retired-20260910.bundle.
  The in-flight default-validation correction remains preserved in codex/fix-command-owner.

- Forced self-rebuild with the new runtime-pair SDK candidate fails on EmitIlAssembly.sourcesValue
  (ITaskItem[]), independently reproduced without SIMD edits. Earlier 8,070 canonical and production
  evidence used the preceding facade seed; it does not prove self-hosting by the new candidate.
  Log: /private/tmp/toolchain-integrated-runtime-pair-selfbuild-r2.log. Publication is blocked
  while the runtime-pair owner corrects reference/runtime companion handling. SIMD edits are preserved.

- CheckCommand imported-array compatibility correction is integrated through 6b3f4d669.
  It unwraps only oblivious array annotations, keeps nullable element mismatches distinct, and
  restricts its additional reflected-call path to SZ arrays while preserving successful existing
  CLR matches. Typed null sourceTexts preserves the command failure/output behavior.
  Lane canonical suite passes 8,074 tests; root combined suite passes 8,075 with zero failures
  or skips: /private/tmp/toolchain-integrated-check-array-canonicals-r1.log.
  FixCommand complete ownership and C# assertion migration has resumed in its existing worktree.

- The partial runtime-pair correction clears ITaskItem[] but then fails ZipFile.ExtractToDirectory.
  A forced rebuild of the same source with the preceding facade seed succeeds, confirming this
  second failure belongs to the resolver regression. It is not a new SIMD or ZipFile feature gap.
  The candidate remains unpublished while exact dependency selection is corrected.

## Recovery after temporary worktrees disappeared

The former /private/tmp worktree directories, private candidates and logs are no longer present.
Committed branch tips survive. Git administrative metadata was archived at
/Users/spencer/repos/nsharp-worktree-recovery-gy0mvuhz before pruning missing registrations;
all eight saved indexes matched HEAD (no staged changes recoverable). Uncommitted resolver/SIMD
files that existed only in those directories must be reconstructed from recorded findings.

Active persistent worktrees are now /Users/spencer/repos/nsharp-worktrees/integration,
/Users/spencer/repos/nsharp-worktrees/fix-command and
/Users/spencer/repos/nsharp-worktrees/runtime-owner. FixCommand commit 33522d9c6 survived and
is under review; do not restart that port. Luna Max agents are reconstructing the self-hosting
resolver correction and verifying FixCommand assertions. Private build evidence now goes under
/Users/spencer/repos/nsharp-worktrees/evidence. Historical test counts above remain historical
evidence, not fresh recovery/build verification. Shared main checkout and SDK cache remain untouched.

Recovery verification: the recovered private stage-0 SDK rebuilt current compiler-core successfully
(0 warnings/errors; evidence/recovered-core-build-r3.log), and default dev.sh --build-only plus
all 123 native CLI contracts pass (evidence/recovered-cli-build-r1.log and
evidence/recovered-cli-contracts-r1.log). These are persistent paths beneath the evidence directory
above. The current candidate still fails normal Playground project build while rebuilding Core
on ITaskItem[]; its self-hosting correction remains mandatory before publication.

A source audit found 12 remaining CheckCommand assertion methods in tests/CliCommandTests.cs and
Check/Fix coverage in tests/CompilationBackendTests.cs. Their canonical N# migration is now a third
Luna Max lane at /Users/spencer/repos/nsharp-worktrees/check-assertions
(codex/check-remaining-assertions). Dedicated-test-file deletion alone is not owner completion.

FixCommand is now integrated through 3cc75672b: the 191-line C# owner, 838-line dedicated
C# test file and three shared Fix assertions are replaced by N# ownership/assertions. Review
preserved original edit tie ordering, per-file atomic writes and exact JSON/output bytes.
Root dev.sh build passes with 0 warnings/errors; all 130 native CLI contracts pass against the
integrated output. Receipts: evidence/integrated-fix-core-build-r1.log,
evidence/integrated-fix-cli-build-r1.log and evidence/integrated-fix-cli-contracts-r1.log.
The clean Fix worktree/branch is retired; verified persistent history bundle:
/Users/spencer/repos/nsharp-worktrees/evidence/fix-command-completed.bundle.
The remaining shared Check/backend assertions remain assigned to the separate lane.

## CLI project boundary correction

User clarified that CLI commands must not live in the Compiler project merely because it already
builds N#. Move CheckCommand/FixCommand and their command-specific helper/state/test groups into
a dedicated native NSharpLang.Cli.Core project. The existing CLI executable references it; the
dependency direction is CLI host -> CLI.Core -> Compiler -> Compiler.Core. Compiler, Playground
and SDK packages must not acquire a CLI command dependency. Reusable compiler-service FixApplicator
remains in Compiler. This is one coherent CLI library, not a project per command.

The bounded relocation is assigned to the Luna agent at
/Users/spencer/repos/nsharp-worktrees/cli-native-owner (codex/cli-native-owner). Preserve exact
command semantics and canonical tests, remove reverse test dependencies/host-assembly assumptions,
and verify the published CLI closure. Shared CLI-only code still in Compiler.Core remains explicit
placement debt to move with its complete caller group; do not introduce a reverse dependency.

## Compiler capability gaps for the Runtime conversion (2026-09-10)

Proven with the tip CLI (`nlc 0.1.0+dc7efda2f`) before any edit, then implemented as one integration
branch (`gap/integration`, 20 stream merges plus 3 root fixes) by Opus streams in persistent worktrees
under `/Users/spencer/repos/nsharp-worktrees/gap-*`; root planned, reviewed, merged, gated and pushed.
No Runtime `.cs` file was edited; the four acceptance sources are translated as executable native tests
that compare side by side with the real `NSharpLang.Runtime` types.

| Gap | Baseline | Now | Native evidence |
|---|---|---|---|
| Readonly structs | NL101 at `readonly struct` | all modifier orders, generic, `readonly ref/record struct`; NL326 mutable-instance-field rule; NL311 on non-structs; `IsReadOnlyAttribute` + `initonly` emission | `tests/native/readonly-structs` |
| Static members on generic types | NL323 at the declaration; `Box<int>.Create` parsed as a comparison | constructed generic receivers (`Name<T>.Member`, new AST node); static fields/properties/methods/operators/conversions on generic types with per-instantiation storage; generic methods on user types; `Result<int, string>.Ok(42)` | `generic-type-receivers`, `generic-static-members`, `user-generic-methods`, `runtime-acceptance` |
| Type identity by arity | NL306 for `Subscription` + `Subscription<T>`; generic user types emitted WITHOUT the `` `N `` CLR suffix | (name, arity) identity in every table; `` Name`N `` metadata names; qualified and unqualified references are one identity; abstract/virtual/override on source classes; faithful `NSharpEventSubscription` with zero deviations | `type-arity`, `class-inheritance`, `generic-member-types` |
| Constructed external generic members and constructors | `Vector<int>.Count` parse failure; `new Vector<int>(a, i)`, operators, indexer and `Vector.Sum` declined at emit | ordinary resolution for constructors, operators, indexers, generic static and instance methods (explicit and inferred type arguments), static members of constructed types; complete `SimdReductions` translation executing with parity against the C# helper | `external-generic-construction`, `external-generic-methods`, `simd-reductions`, `tuple-names` |

Adjacent gaps closed because the acceptance sources required them: external generics over the declaring
type's own parameters and over complete source types (`IEquatable<Self>` base lists with real dispatch,
`EqualityComparer<T>.Default`); `?.`, `default`, `base.Member` and `is` over any type in the columnar
backend; `[MethodImpl]` implementation flags (were silently dropped; NL930-NL932); `TupleElementNamesAttribute`
in both directions; namespace-qualified names in expression position; an explicit import now outranks
project-wide auto-discovery, and two imports supplying one name is NL209 (auto-discovery itself is kept:
`examples/12-multi-file-projects/AutoDiscovery` documents it); by-ref arguments in the semantic call planner;
user-defined conversions declared by external generic types; NL327 for `this`/`base` without a receiver.
Measured language limits that the translations spell around: `const` is not a field modifier (the
`MethodImplOptions` combination is written at each member), N# has no explicit interface implementation
(`IEnumerable<T>` on a source class does not load), and a generic method called directly on a call
result needs a local. Remaining documented limits are in `website/docs/types.md` "Current limits".

Evidence at the integrated tip: compiler-service estate 8,339/8,339; 66 native projects, every one
executing with zero failures; C# unit suite 399/399; format gate clean; ilverify clean over the new
assemblies. Three regressions were caught only by full sweeps or the product gate (a nullable-interface
typed local, `TryGetValue(key, out x)` on a static-field receiver, `base.Value` accepted in a constructor
initializer) plus a double-`box` IL defect from a merge collision — streams must run the FULL native
sweep, and a native project whose test build fails reports total 0, which a sweep must flag.
The A2 stream's three slices (abstract/virtual/override, generic-over-type-parameter member types,
exception property reads including the `ArgumentException::get_Message` override contract) are one
squashed commit whose message names only the first; this paragraph is the record for the other two.


## Converter-driven census slices (2026-09-12)

The conversion is now driven by a deterministic C#→N# transducer kept OUTSIDE the product repo
(`/Users/spencer/repos/nsharp-cs2nl`, Roslyn-based; `convert` writes a 1:1 N# translation with
`// CONVERT:` stubs where no N# spelling exists yet, `census` tallies those stubs per construct across
LanguageServer, Cli, Wasm and the C# tests; `CENSUS.md` there is the ranked gap list). The census
ranks compiler gaps by how much converted code they block; each slice fixes ONE rule in the N#
compiler with native contracts, and the converted projects are re-run through `nlc check` to
measure. Slices landed with this record (`census/merge` onto systems-language `a0bd6fd1e`):

| Slice | What blocked the conversion | Rule now | Evidence |
|---|---|---|---|
| `nlc check` non-termination | a 27-link `.WithHandler<T>()` chain in the converted LanguageServer `Program.nl`: every receiver read re-walked the chain, 2^N | a call walks its member-access receiver ONCE; later reads re-run only the expression tail at their own position (step kind 16); one report per fault in `check` and `build` | `AnalyzerCallAnalysis.tests.nl` receiver-walk counts; `analyzer-semantic-model` lambda scope census 15→7 / 7→5 |
| try/finally return | `return` inside `try` with `finally` read as falling through | C# rule: a protected region's return completes the function; regions nest | `tests/native/census-flow-rules/TryFinallyReturn` |
| break/continue narrowing | `if x == null { continue }` did not narrow `x` afterwards | jumps narrow the way `return` does | `census-flow-rules/JumpNarrowing` |
| external signature identity | `Nullable<T>` / array annotations and omitted defaulted arguments on cross-assembly members failed to bind | one reflected-type identity rule for both; constructor defaults filled like methods | `census-flow-rules/ExternalSignatures` |
| reference stores and casts | `object[]` element stores and array-literal explicit casts declined at emit | the conversion the analyzer proved is emitted; downcast arms stay ahead of the upcast funnel | `census-flow-rules/ReferenceStoresAndCasts` |

Corpus pin 94. Remaining ranked gaps (from `CENSUS.md`): non-literal field initializers, generators
(`yield`), source-declared attributes, struct-enumerator `foreach`, lambda result inference for
method type parameters, a deep-nesting parser crash, `nlc build` dropping the NL103 decline site,
NL010 false positives, generic methods on a call result, `IEnumerable<T>` on source classes. The
order of work is: close gaps until the mechanical conversion of LanguageServer, Cli and Wasm checks
clean, land those conversions 1:1, then rewrite them into idiomatic N# with the C# owner deleted.

## Census wave 3 (2026-09-13)

Nine streams from the refreshed census, each an Opus agent in `/Users/spencer/repos/nsharp-worktrees/census-<stream>`
from a brief in `census-briefs/`, merged onto `census/merge` in landing order with the corpus pin and the
diagnostic-catalog counts reconciled at each merge (every stream bumps both; the merge takes the sum):

| Stream | Rule now | Evidence |
|---|---|---|
| CONV | array covariance (`S[]`→`T[]` for reference elements), target-typed array literals in every position, `null` to a reflected nullable generic-interface parameter (`IsReferenceType` asks the definition) | `census-conversions`, `census-flow-rules` |
| FLOW2 | narrowing through parentheses, negation and the ternary; `Nullable<T>` members bind after narrowing (NL907 is a warning); `while true` reachability; `return` in a constructor; NL304 only for non-nullable reference fields; `x?.M == null` narrows | `census-flow-rules` (NarrowingLattice, ReachabilityAndConstructors) |
| TOOL | `nlc check` reads `*.tests.nl`; `nlc build` prints the decline site; NL111 bounds expression nesting at 512 (no stack overflow); NL010 counts every type position | `cli-command-contracts`, `error-docs-contract` |
| ENUM | `for..in` follows the C# foreach pattern (struct enumerators unboxed, disposal by the four C# answers, `ReadOnlySpan<T>` as an index loop); the emitter's collection name table is gone | `census-pattern-foreach` |
| PARSE2 | a whole TYPE in an explicit type-argument list (`Task.FromResult<List<int>?>(null)`); tuple element names per element in literals and types; a tuple-annotated bare local | `census-parse-shapes` |
| LAMBDA | one method-type-inference engine by position for extensions, statics, instance and user generic methods; method groups; NL413; the per-member Enumerable emit table deleted; reflection over referenced members is load-tolerant (`AnalyzerReflectionMemberProbe`) | `census-lambda-inference` |
| INIT | field initializers are expressions: a real `.cctor`, instance initializers before the base call, struct initializers in declared constructors (NL328/NL329), `beforefieldinit` | `census-field-initializers` |
| ATTR | attributes a program declares for itself: general ECMA-335 blob writer, `AttributeUsage` honored (NL933/NL934), attributes on properties and constructors | `census-source-attributes` |
| EXT | one extension-call path from receiver to IL: source-class element sequences, arrays, explicit type arguments on extension calls (the `Cast`/`OfType` table deleted), lambdas in every argument position through the columnar parser and the construction planner, type-parameter receivers | `census-extension-calls` |
| ITER | iterator bodies use the ordinary expression planner (the parallel mini-planner deleted): calls, literals, `new`, `for..in` over any sequence, target-typed `yield`; one BCL exception resolution path; external record initializers | `census-iterators` |
| LOCALFN | local functions bound by the block (forward calls, mutual recursion, definite assignment at the call); a substituted generic parameter takes the type argument's nullability (`Lazy<T>.Value`, `First` vs `FirstOrDefault`); `assert cond` narrows; postcondition attributes belong to the postcondition owner alone | `census-local-functions`, `census-flow-rules` |
| FLOW3 | `out` arguments take any nullability; `[NotNull]`/`[MaybeNull]`/`[NotNullWhen]`/`[MaybeNullWhen]`/`[NotNullIfNotNull]` read off reflected and source members; a `?.` chain's continuation lifts | `census-flow-rules` |
| CONV2 | shift operands typed by the operator; integer constants adopt a neighbour's type; user-defined implicit conversions on arguments (`op_Implicit`); array literals scored element-wise against overload sets | `census-conversions` |
| TUPLE2 | `System.ValueTuple\`N` is the tuple type it spells; element names survive `Nullable<T>.Value`, indexers, dictionary values, chains and foreach variables at emit; tuple-typed fields/properties; `(a, b) := e` / `(a, b) = e` and `Deconstruct(out …)` | `census-parse-shapes` |
| ENUM2 | `for x: T in e` — an annotated loop variable with the C# explicit element conversion (NL330), node kind 76 | `census-pattern-foreach` |

| LAMBDA2 | a lambda or method group converts to ANY delegate type (signature read off `Invoke`); method groups against overload sets; external generics' delegate positions and member reads through the definition; constrained type-parameter receivers at both lookup sites; external property assignment by ordinary resolution | `census-lambda-inference` |
| LOCALFN2 | local functions capture like lambdas — one display-class model (`ColumnarLocalFunctionClosurePlanner`), `this`-only capture on the declaring type, NL331 for a captured by-ref parameter; type members may declare local functions | `census-local-functions` |
| VIS | a camelCase top-level `func` is NAMESPACE-private (visible from every file of its namespace), in discovery, completion and `nlc query` | `census-visibility` |
| FLOW4 | `[DoesNotReturn]`/`[DoesNotReturnIf]` as one reachability fact both the analyzer and the planner ask; a narrowed `T?` (and a lifted tuple) is read as its `T` at emit; loop bodies that never fall through emit | `census-flow-rules` |
| EMIT2 | a struct assigns its own field from its own method (addressable receivers); enum instance members resolve against `System.Enum`; a conditional over an interpolated string and a `string` is a `string`; `T[]` → `T?[]` admitted; the "declining shape" sentinel moved to a bare static field as a call receiver (three N# fixtures and the three C# fixtures in `tests/CompilationBackendTests.cs`) | `census-emit-shapes` |
| ATTR2 | attributes on FIELDS (a `FieldDeclTokens` column on the struct scan), optional attribute-constructor parameters filled from declared defaults, per-element constant conversion in attribute arrays, chaining to an EXTERNAL base constructor with arguments, NL935 for attribute positions N# has none of | `census-source-attributes`, `class-inheritance` |
| ITER2 | a generator suspends inside a `try` whose handler is a `finally`; writes through a member, an indexer and an annotated loop variable inside the machine; `await` of anything; a lambda built from the machine the generator is already running on | `census-emit-shapes`, `census-local-functions` |
| EMIT3 | free functions keyed by NAMESPACE (two same-named functions in different namespaces no longer share one body); the holder type is `Program` unless the namespace declares one, then `<Program>`; free-function visibility follows the analyzer's rule | `census-free-function-identity` |
| INHERIT | a source type deriving from an external base sees every inherited member: reads and calls with and without a receiver, static members through the derived type, completion offers what a receiver inherits; the surrogate's base chain is written down | `class-inheritance` |
| LAMBDA3 | a method group a REFERENCED assembly declares converts to a delegate; a lambda's result is read through its CLR shape; an output is inferred from an overloaded group; a type parameter met by `X` and `X?` fixes to the lifted bound; a `ref`/`out` argument is an EXACT inference | `census-lambda-inference` |
| TUPLE3 | a tuple's element names survive a local, a source member and an inferred return | `tuple-names` |
| TESTREFS | one owner for the test-framework reference set (`TestFrameworkReferenceSet`: restore row, compile assemblies with the package that ships each, runtime assemblies, the emit host's probe list) — a metapackage such as `xunit` is never loaded by name; a project with `*.tests.nl` plans the rows without declaring the dependency; attributes on `test` blocks, a `[Fact]`-derived attribute decides the run (`Skip`); a source attribute declared in another file binds; writes to inherited external members | `census-testrefs`, `cli-command-contracts`, `language-server-diagnostics` |
| FLOW5 | `.Value`/`HasValue` answer only for nullable VALUE types; `x?.M(...)` binds its callee (overloads, arity, postconditions); lifted `==`/`!=` over `T?` in analysis and IL; `x?.TryGetValue(k, out v) == true` narrows `v`; postconditions bind through an oblivious or nullable-annotated receiver; a `null` ternary arm emits | `census-flow-rules`, `analyzer-clean-source` |
| EMIT4 | a bare static member of the enclosing type is a call receiver; `this` reaches object's own members on a source class; `GetType()` on a typed source receiver; `[DoesNotReturn]` tails in value functions and `Debug.Assert` by ordinary static resolution; `T?[]` local annotations and typed foreach; a `?`-lifted SOURCE struct at every declared position; tuple literals (named or not) into tuple-typed locals and as lambda results at generic positions; the "declining shape" sentinel is now `await foreach` inside a generator (four N# fixtures + the three C# sites) | `census-emit-shapes` |
| LIFT | every operator family lifts over a nullable value type with C# §12.4.8 semantics: arithmetic/bitwise/shift → `R?` absent-in-absent-out, comparison → plain `bool` (false when absent, narrows nothing), unary, compound and postfix on `T?`, `bool?` three-valued `&`/`|`, user-defined `op_*` on `decimal?`/`TimeSpan?`; one lowering per shape, no operator tables; `null + 1` stays refused | `census-lifted-operators` (IL-verified in the gate) |
| EVENTS | `on`/`off` reach the columnar pipeline (expression kind 79 / statement kind 80): any receiver a call accepts (static type, local, parameter, field, `this.`, property chain, indexer), the handler a lambda, a delegate value or a method group, the handle typed once for `on` and `off`, `add_`/`remove_` read off the `EventInfo` (no event tables); method groups bind against reference-assembly delegates; hover/definition on both keywords | `census-events` (IL-verified in the gate) |
| AMBIG | NL209 wherever two imports supply one simple name, external types included, in every position (annotation, `new`, type argument, `typeof`, `is`/`as`, static receiver, attribute); a metadata miss is memoized so the probe is affordable; a mismatch pair that renders the same is qualified by one owner (`TypeMismatchDisplay`); a delegate-constructor parameter type is resolved in its DECLARING file's scope (no NL209 at a line that never spells the name); the emitter's hardcoded `Range`/`Index`/`DateTime` table is the last resort, not the first; an imported CLR generic outranks an unimported source type of the same spelling; the `System` row of the NL010 import table completed by sibling (66 → 112) | `census-imports` |
| ACCESS | one accessibility relation (`MemberAccessibility.nl`) for source and reflected members: `protected`/`private`/`internal`/`protected internal`/`private protected` enforced on source members with the C# receiver rule (NL308 by one owner), every written word reaches CLR metadata (fields included; `private protected` → famandassem), `public`/`internal`/`private` words on free functions decide `Public|Static` vs `Assembly|Static`; `this.M()`/`base.M()` reach an external base's protected methods (`base.` non-virtual); completion filters by accessibility | `census-accessibility` |
| USING | the `using` statement with C# semantics (statement kind 77, `await using` 78): `using x := e { }`, `using x: T = e { }`, `using e { }`, the DECLARATION form released at the end of the enclosing block in reverse order, `await using` via `IAsyncDisposable`; a real `try`/`finally` lowering, struct resources by constrained call, null resources skipped, NL333 for a non-disposable resource, NL309 for rebinding the resource; termination analysis, generators, lambdas, local functions, formatter, hover/completion inside the block; `let x: T := e` fixed on the way | `census-using-statement` |
| OVERLOAD | C# §12.6.4.3 better-function-member for SOURCE and REFLECTED overload sets by one owner (`AnalyzerOverloadSpecificity`, a partial order over a verdict matrix — order-independent): the more specific type wins (`IEnumerable<T>` over `IEnumerable`, `T` over `object`), non-generic over generic only at identical parameters, `ref`/`out` positions scored through their by-ref shell, the extension receiver at position 0, lambda-return and method-group conversion scores; an unbreakable tie is NL414 (never a silent pick; withheld when an argument is `unknown`); the columnar source resolver applies the same rule (four emitter tie-contracts moved from Rejected to the specific overload) | `census-overload-resolution` |
| TOOL2 | lint fidelity: an aliased import is used when its alias is written AND when the namespace's own names are (both questions), an alias-qualified type reads as the one type it names, a declaration is not in scope inside its own initializer (no NL020 for a lambda parameter there), the converted language server's four lint reports pinned as executing editor contracts; a static receiver (`Thread.Sleep`) counts as an import use | `qualified-names`, `language-server-diagnostics` |
| ASYNC | `async` lambdas (expression kind 78) in every lambda position against `Task`/`Task<T>`/`ValueTask`/`ValueTask<T>` and any task-like delegate, capturing like ordinary closures, exceptions landing on the task; `async` local functions; `return <lambda>` (sync too); the `Task.Run` row picks `Action` or `Func<Task>` by the argument's shape; a bare `throw` re-throws (IL `rethrow`, kind 48 with no children) inside async and generator bodies, NL336 outside a handler; NL334 for an `async` lambda with no task-like target (`async void` refused by design), NL335 names the missing `async` keyword | `census-async-lambdas` |
| EVENTS2 | events DECLARED by N# types: `event Name: DelegateType` on classes, structs and records (static too) — a `[CompilerGenerated]` backing field, `add_`/`remove_` with the C# `Interlocked.CompareExchange` loop, `EventInfo` metadata; raised inside the declaring type (`Name?.Invoke(...)`), reached from outside only through `on`/`off` (NL337), NL338 for a non-delegate type, NL311 for `virtual`/`abstract`/`override`, NL323 for an interface event; a bare `this` as an expression (kind 82); `nlc query` and completion know the `event` kind | `census-source-events` (IL-verified in the gate) |
| CONV3 | target typing at REFLECTED parameter positions: an in-range integer constant converts to a narrower parameter (`byte`, `short`) as C# §10.2.11 says, an array literal of in-range constants takes the parameter's element type at analysis and at emit, an explicit type argument that is the enclosing method's own type parameter binds and emits open; `ConstantConversionFacts` compares types by name (reference equality was always false for MetadataLoadContext types); specificity still picks `Int32` for `Math.Max(0, 1)` | `census-conversions` |
| FLOW6 | flow state for PROPERTY PATHS: `must x.P` and `x.P ?? throw` prove the path they unwrapped for the rest of the block (invalidated by a write to any prefix, an `out` pass, scope exit — not by a method call on the receiver, C#'s rule); `[NotNull]`/`[NotNullWhen]` facts on members declared on a TYPE reach the caller (they never did); every loop form joins its back edge so a loop-carried nullable write is reported (all four were silently unsound); squiggles land on the last hop when the line spells the path through `must` | `census-flow-rules` |
| NULLABLE2 | an unconstrained `T?` substituted by a VALUE type erases to `T` (`FirstOrDefault` over `KeyValuePair<…>` is the pair, `Find`, `GetValueOrDefault`, `TryGetValue`'s out; source generics too; `where T : struct` keeps `T?`) — the carrier question is asked of the DEFINITION; every `Nullable<T>` has one surface read off the definition under substitution (`GetValueOrDefault` on a source struct or enum); any value type lifts into `Nullable<T>` (the three liftable-element lists are gone; `DateTime?`, `Guid?`, source structs at every position) | `census-flow-rules`, `census-lifted-operators`, `analyzer-clean-source` |
| INHERIT2 | every inherited external member reads and calls by ordinary resolution from `this.`, a bare name or `base.` (protected fields/properties, any result type; bare protected calls); a generic external base closed over a SOURCE type no longer CRASHES `check` (constructors rebound through `TypeBuilder.GetConstructor`); `override` of an external protected virtual, taking the overridden member's accessibility when no word is written; type members in any order (a field after a method kept its initializer — it was silently dropped); a lambda reads `this` in every spelling; completion offers the protected surface a receiver inherits; the formatter no longer widens a member's accessibility | `census-accessibility`, `class-inheritance`, `lambda-placement`, `census-parse-shapes` |
| LAMBDA4 | a BLOCK-bodied lambda's return type is the best common type of its `return` expressions and fixes `TResult` (reflected and source generics; the async half in both spellings of a constructed task); every generic delegate closed over a SOURCE type binds (`Action<T>`, `Predicate<T>`, `Comparison<T>`, `EventHandler<T>` — only `Func` escaped before, by parser accident); a delegate held in a member invokes (`h.Loader()`), a receiver-bound method group converts (`greeter.Greet`, `dup; ldvirtftn` for virtual targets); a function type prints as its signature (`(int) -> string`, 56 pinned assertions rewritten) | `census-lambda-inference`, `analyzer-semantic-model` |
| EVENTS3 | an event's own nullability metadata decides the handler it expects (`AssemblyLoadContext.Resolving` takes a handler returning `Assembly?`); `on`/`off` and block-bodied lambdas inside generator bodies (plan-IR `ldvirtftn`); `virtual`/`abstract`/`override` events with their own handler lists, `abstract` left unfilled is NL324, raising an abstract event NL337; events declared in interfaces and filled from classes (an unfilled interface event is NL325); an `async` handler on a `void` event names the `_ = RunAsync()` idiom | `census-events`, `census-source-events` |
| FLOW7 | the state after an `if` is the JOIN of the branch's exit state and the condition's false facts (C#'s rule; a branch that always leaves contributes nothing), so the TryGetValue-or-create idiom narrows; `else if` chains, both-branches-assign, `while`/`for` exits (the false facts hold unless a `break` reaches them) and `switch` arms join the same way; the narrowing scope stays separate from the branch scope (`if v is string { v := 5 }` is still a shadow, not a redeclaration) | `census-flow-rules` |
| TOOL3 | NL010 and NL002 are answered by what a file BINDS (`ImportUsageFacts` stamped on the compilation unit by the analyzer: the namespace each written name resolved through, credited across ten channels — types, declared member types, static receivers, attributes in both spellings, extension methods, delegate names, project types and functions, alias roots) — the hand-written import tables and NL002's whitelists are deleted; a dead import of any namespace is reported and a missing one suggested; analysis runs before strict lint; `nlc fix` reads the same ledger; NL339 for a type declared in two files of one namespace (they used to become two CLR types); LSP timing unchanged | `census-import-usage`, `census-duplicate-declarations`, `cli-command-contracts`, `language-server-diagnostics` |
| THROWEXPR | `throw` as an expression (node kind 83) in the three C# positions — `x ?? throw e`, `c ? v : throw e`, `=> throw e` (a `void` arrow body too) — emitted in place at every site incl. async lambdas; a throw anywhere else is NL340 (positional, judged by the parsers; a missing exception outranks the placement complaint); FLOW6's fact stands after `x ?? throw` | `census-emit-shapes` |
| NULLABLE3 | a generic returning `T? where T : struct` emits a real `Nullable<T>` (the parameter's constraint bit decides liftability; the declaration resolved its own return to bare `T` before); `List<SourceType>.Find/Exists/FindIndex/FindAll` with a lambda bind over a source element (the unique-arity tier reads the open definition and rebinds); a narrowed property PATH is a narrowed nullable (`h.Slot.Value` after `if h.Slot != null`); a `T?`'s member binds on whichever of its two types declares it (`ToString`/`Equals`/`GetHashCode` on the nullable, null-safe); `a.HasValue` inside `func F<T>(a: T?) where T : struct` | `census-flow-rules` |
| LAMBDA5 | C# §12.6.4.6 "more specific" over OPEN parameter types plus §12.6.4.4 "exact lambda match" (`Task.Run(() => Task.FromResult(11))` is `Task<int>`; a source `Pick<T>(Func<T>)` vs `Pick<T>(Func<List<T>>)` no longer NL414) — one owner `AnalyzerOpenTypeSpecificity` read by analyzer and emitter; the emitter's `Task.Run` table deleted (value lambdas emit); a `this`-capturing lambda in a constructor and a lambda literal at a source constructor argument emit; a call result invoked directly (`Make("a")("y")`); block-lambda emit join follows the analyzer's rule; a member miss on a BCL generic closed over a source type is NL303 (it reported nothing) | `census-lambda-inference`, `census-emit-shapes`, `census-async-lambdas` |
| IFACE | interface PROPERTIES — a bare `Name: Type` in an interface is a get-only abstract slot (`get_Name` + `PropertyInfo`), filled by a class's field (synthesized getter) or computed property, struct implementers boxed at the receiver, generic and base-interface slots, default methods reading the slot; NL342 for a write through the interface; `abstract` where the CLR cannot carry it is NL311 in five verdicts (a body-bearing `abstract func` used to emit silently with its body dropped); an override that NARROWS accessibility is NL311 instead of a TypeLoadException; duck matching now asks value members and events (a methodless interface used to match every type); a generic interface closed over a type being emitted no longer crashes `check` | `census-interfaces`, `class-inheritance` |
| IVT | `InternalsVisibleTo` honoured: an internal type or member of a referenced assembly is nameable when that assembly grants the compiling project's assembly name — one owner `InternalsVisibleToGrants` read by the metadata probe, the exported-name scan, member/extension/qualified-name resolution, the columnar resolvers and the editor catalog; negatives pinned under five project names | `census-internals-visible-to` |
| LOCALFN3 | a HIGH silent-codegen bug found by THROWEXPR's probe: the three declaration-scan walkers skipped bodies by BRACE DEPTH, so an expression-bodied `func F(): Func<Task<int>> => async () => 1` left `async` pending and the NEXT top-level function wore it (`string` return silently became `ValueTask<string>`, its `throw` a faulted task nobody awaited; `check`/`build`/analyzer all clean) — a modifier run now ends at any depth-zero non-modifier token; an arrow body followed by `async func`/an attribute group no longer declines the file; a `where` clause is closed by `=>` too; arrow-bodied LOCAL functions (statement kernel stops at the first depth-zero `{`/`=>`); `void` arrow bodies emit for every function kind (`return <expr>` was the only lowering); one `ApplyExpressionBodyRules` for both analyzer arms (NL202 names the function); `continue` in `for` pinned as never a gap; root fix c5aff76a5: the stream measured an arrow body's end against a BACKWARD-walked preamble start and read `=> items[0]`'s `]` as an attribute close (GenericMethods example stopped building) — the end is now walked FORWARD to the next `func` over that declaration's own modifiers/attributes | `census-local-functions` |
| ITER3 | `??`, the ternary's throw arms and the throw expression lowered on the PLAN side (`ColumnarThrowExpressionPlanner`, `ColumnarConditionalPlanner`) so generators take `yield name ?? "d"`, `yield x ?? throw e`, `yield flag ? v : throw e`; a source type's statics read and written inside iterator bodies (`ColumnarSourceStaticMemberPlanner`); a value-typed `using` resource in a generator released through its own address (`ldflda` + new plan opcode `Constrained` −490); `yield <lambda>` parses (block-bodied lambdas in generators emit); the emitter's `??`/throw arms stay as the fallback for bodies the plan door declines (pinned) | `census-iterators` |
| ATTR3 | an attribute on a POSITIONAL constructor parameter (record, record struct, class/struct primary ctor) is one declaration and two rows — its own `[AttributeUsage]` picks the parameter row where it allows parameters, the generated FIELD where it allows fields and not parameters, NL933 naming both rows when neither (the emitter reads a SOURCE attribute class's usage from its AST, `ColumnarAttributeUsageTargets`); a `constructor(...)` parameter's attributes were silently dropped (a method's carried theirs) — emitted; field attributes, optional attribute-ctor params, array-element conversion, external attribute base-ctor chaining re-verified as closed by ATTR2; enum-MEMBER attributes measured and NOT landed (deferring `EnumBuilder.CreateType` breaks nested-enum signatures in the persisted writer — an emitter type-model slice) | `census-source-attributes` |
| TOOL4 | `nlc lint` moved to N# (`src/NSharpLang.Compiler/LintCommand.nl`; `LintCommand.cs` DELETED — ratchet row `removed`, head repinned) and lints the ANALYSED unit so NL010/NL002 and every binding rule report (rows carry `docsUrl`; schema unchanged); completions reach the project's OTHER namespaces (`importNamespace` on the item when the file still owes the import — CLI/daemon only: the LSP identifier list is a C# path) and a granting reference's INTERNAL members (`FriendGrants` on the snapshot + the ACCESS relation, no name list); `inspect`/`def` call an interface instance value member a property (`DeclarationFacts.MemberKindName`, one owner); seven drifted `.nl` files formatted (the formatter was right each time); `nlc test --json` escaping and `FunctionTypeInfo.ToString` did NOT reproduce (already fixed); `MemberwiseClone`/`Finalize` in completion is what the analyzer ACCEPTS (`this.Finalize()` checks clean — an analyzer defect, C# CS0245) | `cli-command-contracts`, `query-integration`, `census-internals-visible-to`, `census-visibility` |
| NULLABLE4 | `==`/`!=` over two operands of the SAME open type parameter, bare or through one `?` (`func Same<T>(a: T?, b: T?)` — analyzer admits, emitter lowers via `EqualityComparer<T>.Default` / the lifted `HasValue`+`GetValueOrDefault` pair; C# refuses with CS0019 — a deliberate N# widening); the type-parameter question goes to the SCOPE (`AnalyzerScopeStack.IsTypeParameterInScope`) so generic structs/records/interfaces answer; a conditional with one typeless arm (`null`/`default`/`throw`) is decided by its TARGET at return, declared local, assignment and call-argument positions (`flag ? n : null` on `int?`, `ok ? null : throw a`); an OVERLOADED instance member on a receiver the planner does not claim (`count.CompareTo(other)` on a narrowed `int?`) resolves through a preflighted last-in-ladder tier (the `string.IndexOf` arity-1 arm now picks by argument type); the nullable→non-nullable NL202 fix-it names `if x != null`, `x ?? fallback` and `must x` (no postfix `!`); most-derived override annotations, `GetValueOrDefault` on lifted source structs, narrowed arithmetic and `T?[]` annotations re-verified as already correct and pinned (`typeInfo.ToString()` in the census is a TRUE positive: `TypeInfo` declares no override) | `census-lifted-operators`, `census-flow-rules`, `census-emit-shapes` |
| EMIT5 | `typeof(void)` (and only there); an EMPTY collection expression converted by its target alone (`sha.TransformFinalBlock([], 0, 0)`); an external call on a STATIC-member receiver resolved by its arguments (`Holder.Text.IndexOf("na", 3)` used to emit the WRONG overload — `IndexOf(string, StringComparison)`); a same-arity source STATIC overload chosen by its arguments as the instance arm does (`Sink.Accept([1, "b", null])` → `object[]`); a loop variable remembers its labelled context so `group.Key.Code` reads through `IGrouping.Key`; `??` given a preflight type — the hand-written `string.IndexOf` emitter arm DELETED (`Encoding.UTF8.GetString([72, 105])`, `GetBytes`, `GetByteCount` emit through ordinary resolution); the bare static-field receiver was already lifted (pinned) | `census-emit-shapes` |
| IFACE2 | a cross-assembly `protected internal` slot is inherited as `protected` (`InheritedAccessibilityLevel`, one owner; IVT grants keep it `protected internal`) — 22 census sites; `protected internal override` there stays ACCEPTED because the CLR loads it (measured by emitting all four spellings; CS0507 divergence documented in NL311.md); a base interface's members reach through a DERIVED-interface receiver (`AnalyzerSourceMemberShape.BaseInterfaces` — resolution, go-to-def, completions; emission states the widening as `castclass` because unbaked TypeBuilders cannot answer `IsAssignableFrom`); a class closing a GENERIC source interface binds to the closed slot (two MethodImpl rows were written, one against the open definition) and upcasts (`b: IBox<int> = new IntBox(5)`, `GenBox<string>` → `IBox<string>`); duck interfaces registered BEFORE fields/events (emitter passes 0a → 0a' base lists → 0a'' duck → 0a''' fields/events) so duck-interface events load; `on this.E`/`on E` inside the declaring type SUBSCRIBE (the `AllowEventReference` slot; the two parsers now agree); `abstract` in a non-abstract class was already NL311 (pinned) | `census-interfaces`, `census-accessibility`, `census-source-events`, `analyzer-clean-source` |
| CAPTURE2 | a NESTED lambda walks the display chain to any depth (`x => y => y > x + threshold`, block bodies, a write shared across levels, a lambda inside a local function, a local function capturing a delegate-typed local — `emit.local-function.capture` lifted); a lambda capturing BOTH `this` and a local reads the enclosing instance's fields, properties and inherited external members through the display's captured receiver (method and constructor); a lambda's body is typed in the frame around it when its output type is still inferring; `await <anything with the awaiter pattern>` as a bare statement (`await Task.Yield()`; the four-task-name list deleted); an overloaded method group on an instance receiver at an extension position is left to inference's phase two; delegate field/property invoke and `Func<Task<T>>` per-iteration captures pinned at runtime | `census-closures` (NEW, pin 120), `census-local-functions`, `census-lambda-inference`, `async-task-like` |
| ITER4 | AWAITS IN HANDLER POSITIONS inside an `async func*`: a `try`/`finally` whose finally awaits is hoisted past the region (a catch-all parks the exception as `ExceptionDispatchInfo`, a branch out records itself in a `<>__branch{k}` field, `AppendBodyExit` chains nested regions; one shared suspension counter — the region table was keyed by the YIELD count so every suspension after the first `await` recorded the wrong region); `await using` and `await foreach` inside an async generator (the inner enumerator/resource released on the end, abandon and exception paths; `DisposeAsync` drives the step core with the dispose flag); a conditional, `&&`/`||` or `??` as a CALL ARGUMENT or receiver in a generator (`IsAdmittedValueSyntax` takes `source`; the type step plans into a scratch of the destination's schema); the declining-shape sentinel moved to an `async` lambda inside a generator in the four N# fixtures and (root) the three C# strings; the emitter's `??` arm CANNOT go yet (`dup;brtrue;pop` — `pop` is not a schema-v3 opcode; `TryPlanReferenceCoalesce` guards on the method-body schema); `await` inside a `catch` and an awaiting finally on a try WITH a catch stay documented limits; USING's value-bearing-return-in-protected-region item does not reproduce (closed) | `census-iterators` |

Still running at this record: TOOL2 (import/shadowing fidelity). Open items from every report are collected in
`/Users/spencer/repos/nsharp-worktrees/census-briefs/FOLLOWUPS.md` (among them: overload specificity for
`Assert.Single`, NL209 for a simple name two imports supply, protected external members, the `using` statement,
async lambdas, `await foreach` inside a generator).

Converter (`nsharp-cs2nl`) mappings added in the same wave: iterators as `func*`, hoisted local functions, class
primary constructors, negated `HasValue`, discard assignments, lambda-parameter renames, typed-foreach casts,
`KeyValuePair`/`Deconstruct` deconstruction, primary-constructor field initializers in the constructor, nullable
`var` locals, `is` over a constant as equality. Census at `669674b9e`: runtime 0, cli 46, tests 91,
languageserver 123 (from 1 / 145 / 153 / did-not-finish at `755e53a14`). Wave 4 briefs (FLOW3, CONV2, TUPLE2,
LAMBDA2, TOOL2, ENUM2) are in `census-briefs/`.
