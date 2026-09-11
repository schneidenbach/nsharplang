# Takeover integration and editor verification — 2026-09-04

The compiler and IDE source revision is `1527e823`; the gate-infrastructure repairs below land at
`a0380b68`, which passed fresh gate r26. All implementation agents are paused with clean committed
worktrees. The ownership audit passes 18/18 at `head-v1:873549ff87d77915`; no ceiling increased. CompletionHandler shrank from
638/559 to 620/546 total/nonblank lines. ColumnarIlEmitter remains 20,724/19,712.

## Installed editor evidence

Ran `./scripts/reload-vscode-extension.sh` with the sample workspace
`/private/tmp/nsharp-ide-takeover-20260904`. The script rebuilt, packaged, installed and reopened
VS Code. `/private/tmp/nsharp-takeover-final-reload.log` identifies **server PID 1684, parent 1671,
started 2026-09-04 16:25:58 America/Chicago**.

- VSIX SHA256: `362d7dae2a414c22c2830584f8bad4a4514dda18a3ffd5ceaf0c5ba7e966dce4`.
- Release AND installed LanguageServer.dll SHA256:
  `d69c265b0b00d76491acf3ca536f9aad369c7aaffcd735b53ff54fa9d6f024b5`.
- Native CUA screenshots were captured inline in Codex task
  `01a06e21-0284-7951-b602-15caa5246cfe`; these are actual editor observations, not headless assertions.
  No standalone screenshot-file paths are claimed.

| visual flow | observation |
|---|---|
| Package auto-import | `DeserializerBuilde` offered the unique `DeserializerBuilder (auto-import YamlDotNet.Serialization)` item. Enter inserted the import and completed the name. Saving left the package project with no diagnostics |
| Interior caret and multiline header | Completion before `Wrong` in `StringBuildeWrong` replaced the whole identifier. The import landed after the spanning header comment, and the following `/// Factory docs` stayed with the function. Saving/formatting preserved valid source and cleared all three file diagnostics |
| NL002 quick fix | Live diagnostic read `'StringBuilder' is used without the import that provides it`, anchored at the return type. `Add import System.Text` inserted the import and cleared both errors. Final workspace status displayed **No Problems, 0 errors, 0 warnings** |
| Server lifetime | Closed the probe window through CUA. `ps -p 1684` returned no process. The old owner-session orphans 1007/37105 were not killed or counted as this window's server |

The earlier takeover round at `f83bf86e2` discharged the catalog-growth check on a fresh server:
PID 86347 was started with the package project outside the workspace; the first import completion
had no YamlDotNet namespaces. Returning the project and opening its file in the SAME server exposed
`Core`, `Helpers`, `RepresentationModel`, and `Serialization` after `import YamlDotNet.`, and
hover identified DeserializerBuilder. That round discovered the missing completion import edit;
the final round above verifies its correction. First-round reload log:
`/private/tmp/nsharp-ide-takeover-reload.log`. Its separate fresh PID 85376 also exited on window close.

## Merged-tree focused evidence

The CLI and Debug LanguageServer were rebuilt from the merged tree before these checks:

- Ownership audit **18/18** — `/private/tmp/nsharp-takeover-final-audit.log`.
- Native LSP lifetime/completion **11/11** — `/private/tmp/nsharp-takeover-final-native-lsp.log`.
- Diagnostic honesty **32/32** — `/private/tmp/nsharp-takeover-final-honesty.log`.
- Error-docs contracts **13/13** — `/private/tmp/nsharp-takeover-final-docs.log`.
- Root format — `/private/tmp/nsharp-takeover-final-format.log`.

The writer's committed-arm whole-PE proof and the focused source-estate counts are recorded in
[its decode](2026-09-04-s21f-parity-proof.md) and the
[editor decode](2026-09-04-completion-auto-import.md). They are not substitutes for the fresh gate.

## Integration gate record

The checkpoint is run with `./scripts/test-all.sh --commit`, VS Code enabled, from a byte-copy
excluding nested `.claude/worktrees` and `artifacts/from-worktrees`. All implementation agents remain
paused. The source SHA, exit status, and complete fresh verdict are recorded externally at
`/private/tmp/gate-20260904-takeover-r27/gate.log`; read its verdict before using this checkpoint as
gated evidence. No SDK/feed republish is part of this takeover wave. Only the exact successful
checkpoint SHA is eligible for push to `origin/systems-language`.

The implementation checkpoint `a0380b68438b739cf3565e1be1306570d1fe6a64` passed r26 in **8m20s**:
**593/593** units, **7,650/7,650** compiler contracts, all native project suites, **36/36** VS Code smoke
tests, and IL verification of **68 assemblies**, with the throughput, package, template and example
steps green. Log: `/private/tmp/gate-20260904-takeover-r26/gate.log`. The compile-time timing judgment
was skipped at load 4.13/10 cores; its exact record is `compile-time-gate.txt` beside that log, and the
quiet measurement below supplies the timing evidence. The final documentation checkpoint follows
with a second consecutive fresh gate against the same dependency cache, exercising the bootstrap
repair after the successful run's package cleanup. No product code changes between those runs.

### First gate and failure-reporting correction

The r24 gate on `242e401d` exited 1 after 8m16s: unit **592 pass / 1 fail**,
compiler estate **7,650/7,650**, VS Code smoke **36/36**, and all remaining steps passed,
including verification of 68 emitted assemblies. The failing test was
`SetupLocalScriptTests.InstallLocalSkipVscodeDryRunKeepsCliOnlyPath`. Its scripts and assertions
are unchanged from takeover. The original `-v q` test invocation suppressed the assertion detail;
its early failure excludes the 180-second timeout, but no more specific cause can be established.
The complete failed log is `/private/tmp/gate-20260904-takeover-r24/gate.log`.

Without rebuilding, the exact test passed and the same full compiled unit suite then passed
**593/593** in the retained isolated tree. The focused `dev.sh SetupLocalScriptTests` rebuild also
passed **9/9**. Logs and TRX results are outside the repository at
`/private/tmp/nsharp-setup-local-repro/`. The gate now explicitly selects the console logger's
`minimal` verbosity while retaining quiet MSBuild output. A controlled invalid setup environment
proved the log includes the failing assertion, child stderr and the existing `Failed!` summary.
No assertions or timeout changed; this corrects missing failure evidence, not the unexplained
first-run failure. The shell row remains 916/815 lines; its observed fingerprint is
`text-v1:d27a5cd61db84583`, and both reviewed head keys are `head-v1:94e6b5916c964abc`.

### Consecutive fresh gate bootstrap repair

The r25 retry on `78cf8f4a` failed before tests after four seconds because the reused dependency
cache lacked `NSharpLang.Sdk` 0.1.0. The first run's package phase clears the SDK/runtime package-ID
cache directories, and subsequent builds restore only IL-stamped versions. The wrapper previously
copied bootstrap packages only when the entire package-ID directory was absent. Thus a directory
containing an unrelated version suppressed restoring the version required for the next compiler build.
The original caller SDK and both local feeds remain intact and were not republished.

The wrapper now always merges the caller's bootstrap package tree when it exists, refreshing
matching versions and retaining destination-only versions. Deterministic controls execute the actual
helper from the before/after scripts: the old helper leaves the required version missing; the fixed
helper restores exact SDK/runtime payloads, survives a second eviction, refreshes overlapping stale
bytes, and preserves gate-specific sibling versions. Evidence: `/private/tmp/nsharp-gate-bootstrap-repro/`.
The failed log is `/private/tmp/gate-20260904-takeover-r25/gate.log`. The wrapper shrinks 567/502 →
566/501 lines; observed fingerprint `text-v1:b85cb4a09a8d31f5`, both head keys
`head-v1:873549ff87d77915`. This repair is exercised against the same partial cache by the fresh r26 run.

## Quiet compile-time measurement

The five-run harness completed successfully on product revision `1527e823` with all implementation
work paused and the probe editor closed. Preflight one-minute load was **1.71 / 10 logical cores**,
below the documented **2.0** threshold. The unchanged baseline limit is **7,868 × 1.5 = 11,802 ms**.

| command | five wall times (ms) | median | median peak RSS | result |
|---|---|---:|---:|---|
| build | 7,834; 8,041; 8,098; 8,099; 8,180 | **8,098 ms** | 181,633,024 bytes | Within the unchanged 11,802 ms limit; every process exited 1 |
| check | 29,271; 28,332; 28,415; 28,311; 28,480 | **28,415 ms** | 765,231,104 bytes | Informational measurement; every process exited 1 |

Scope: **425 production files / 183,214 lines**. This is still a front-end build measurement:
strict lint rejects the compiler's own sources before analysis/emit. The check returns 260 results;
this does not claim that the compiler passes its own strict source check or builds itself through
`nlc build`. The MSBuild SDK/estate path and the product gate remain separate evidence.

The benchmark proved each build left its source tree untouched. No baseline was changed. Full report,
per-run CSV and summary CSV are in `/private/tmp/nsharp-takeover-compile-time-20260904/`;
preflight is `/private/tmp/nsharp-takeover-compile-time-preflight.log`, and driver output is
`/private/tmp/nsharp-takeover-compile-time.log`. The quiet measurement discharges the handoff's timing
judgment; a later product-gate load skip does not replace it.

## Compiler-source diagnostic comparison

A final read-only comparison used the SAME immutable final CLI over complete committed source archives:
`6ea697316` had **423 files / 261 results**, and `1527e823` has **425 files / 260 results**; both exit 1.
All 260 final findings match the takeover tree by code, message, file and column with unchanged source
lines mapped through the diff. **No new diagnostics were introduced.** The sole removal is NL012 on
`CodeFix.nl`'s formerly unused `sourceCode` parameter; the shared import planner now consumes it.
The inherited 403-file/243-result count was stale. Revisions, CLI/dependency hashes, raw JSON and mapped
comparison are retained under `/private/tmp/nsharp-takeover-live-check/`.
