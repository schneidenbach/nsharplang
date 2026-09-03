# Known Limitations

This file is the current public-facing limitations register for N# docs. Keep it factual, dated by evidence when possible, and avoid resolved-item graveyards. Historical notes can live in git history or audit files.

## Launch and Verification

- **Full product gate is not launch-green by default.** Use the latest `./scripts/test-all.sh` output as evidence before saying the whole product is ready. Prior audit notes record full-suite/VS Code integration risk, so do not replace this with a blanket "all tests pass" claim without a fresh run.
- **Test counts move quickly.** Do not hard-code totals in README/site copy. Quote exact counts only from a fresh `./scripts/test-all.sh` run or a current, checked evidence artifact.
- **Packaging/public feed status must be verified per release.** Local/private setup exists, but docs should not imply broadly available public NuGet packages unless the package/feed evidence is current.

## CLI

- **CLI docs must track help/completions.** Current top-level commands and `nlc query` subcommands are registered in `CommandRegistry` and surfaced by `nlc --help`, `nlc query help`, and `nlc completion <shell>`.

## Language Semantics

- **Pattern guard exhaustiveness is conservative.** Guarded arms do not prove coverage. Add an unguarded union arm or wildcard fallback when a match must be exhaustive.
- **Nested union matching has edge cases.** Curated nested-union patterns are supported, but deep/constrained nested coverage should be verified with focused tests before it is advertised as complete.
- **Type alias emission has CLR metadata restrictions.** Same-namespace aliases and nullable reference aliases can hit backend limitations.
- **Attribute support is scenario-based, not blanket parity.** Declaration and parameter attributes are parsed/formatted and current targeted tests cover IL parameter metadata. Verify framework-specific attribute scenarios, especially ASP.NET controllers/model binding and xUnit discovery, with focused tests before using them as release evidence.
- **Null-forgiving `!` should not become an escape hatch.** Prefer explicit null checks or null-coalescing. Diagnostics for null/default-forgiving syntax should come from token/parser/AST/semantic analysis, not source-only scans.

## Build and Performance

- **Incremental behavior depends on the active workflow.** The daemon caches analysis for CLI/query flows, but broad project builds may still do more work than a mature incremental compiler.
- **Large-project performance needs scenario evidence.** Do not make Go/Rust-speed claims without benchmark output for the target repo and command.
- **Measured 2026-09-01 (idle Apple M4, tip `8cf40128a`; full record in `systems-language-closeout/MEASUREMENT-VERDICT-2026-09.md`, harness `tests/native/compile-time-bench`).** On the compiler's own sources (403 files / 172,653 lines) `nlc build` reaches only parse + strict lint (7.9 s, 172 MB, ~22 K lines/s) and `nlc check` parse + analysis (27.0 s, 683 MB, ~6.4 K lines/s); the SDK emit-only path that actually builds the compiler takes 132.6 s (611 MB, ~1.3 K lines/s) and was 3.4 s for 63,689 lines on 2026-07-08, a 14× per-line regression of the emit path. The SDK build also re-emits on every `dotnet build` (no incremental skip). On the 41 buildable corpus projects the tip pipeline ties the last C# pipeline (`5fce5896f`) at 0.995× on build and 0.959× on check with ~16 % more peak RSS; those projects are startup-bound (~200 ms host floor), so only the large project measures the compiler. Native kernels regressed 1.17–1.34× against June (`artifacts/native-comparison/2026-09-01` on `measure/native-comparison`).
- **`nlc build` and `nlc check` cannot compile the compiler's own sources.** Strict lint reports 45 findings (NL012 ×20, NL011 ×17, NL010 ×7, NL002 ×1) and stops `nlc build` before analysis; `nlc check` reports 243 error-severity results (NL202 ×85, NL402 ×65, NL905 ×26, NL301 ×16, NL303 ×3, NL412 ×3 plus the lint 45). The product builds `src/NSharpLang.Compiler.BootstrapServices` only because `src/NSharpLang.Sdk/Sdk/Sdk.targets` switches legacy analysis off for that one project name. The compile-time gate therefore pins that project's `nlc build` at exit 1 (front-end stage) until the diagnostics are fixed; do not advertise `nlc build` throughput on large projects as an end-to-end number until it exits 0 there.

## IDE Support

- **VS Code support is real but must be visually verified for launch claims.** Syntax highlighting, diagnostics, hover/completion, code actions, and related LSP behavior have tests, but user-facing IDE claims require a fresh extension reload plus real VS Code visual QA. Last visual verification: 2026-09-02 at systems-language d26460045 with VSIX 0.6.0 in VS Code 1.134 (record and screenshots in `artifacts/ide-verification/2026-09/README.md`). PASS: syntax highlighting, live NL202 diagnostic with the Elm-style body and squiggle, parser cast-lookahead fix, go-to-definition and find-references across files, NL002 auto-import quick fix applied, NSYS010/NSYS050 rendering identical to `nlc check --systems-report`. That pass found four defects (BCL hover empty, interpolation-hole hover typed as `string`, trailing-dot completion listing scope names, NL002 anchored on `new`); all four were re-verified FIXED in the editor on 529ad23bf the same evening, together with format-on-save (author-preserving argument wrapping, attributes and raw strings kept verbatim), hover doc summaries and call-site overload narrowing (`artifacts/ide-verification/2026-09-02b/README.md`). Rename was driven only to the widget (the click-tier harness cannot type), so end-to-end rename remains unverified in the editor.
- **Debugger UX is not a public polished workflow.** F5/debugging should remain hidden or caveated until there is a tested N# debugger-backed flow.

## Documentation Rules

- Avoid absolute claims such as "perfect interop," "all features implemented," "production-ready," or "it just works" unless the exact scenario is backed by a fresh gate.
- Prefer phrases like "designed for," "covered scenarios," "curated examples," and "verify with" when describing active surfaces.
- Keep private customer/application artifacts out of the repository unless explicitly redacted and approved.
