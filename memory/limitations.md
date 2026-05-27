# Known Limitations

This file is the current public-facing limitations register for N# docs. Keep it factual, dated by evidence when possible, and avoid resolved-item graveyards. Historical notes can live in git history or audit files.

## Launch and Verification

- **Full product gate is not launch-green by default.** Use the latest `./scripts/test-all.sh` output as evidence before saying the whole product is ready. Prior audit notes record full-suite/VS Code integration risk, so do not replace this with a blanket "all tests pass" claim without a fresh run.
- **Test counts move quickly.** Do not hard-code totals in README/site copy. Quote exact counts only in dated evidence artifacts such as `docs/talk/evidence-matrix.md`.
- **Packaging/public feed status must be verified per release.** Local/private setup exists, but docs should not imply broadly available public NuGet packages unless the package/feed evidence is current.

## CLI

- **No public C# conversion contract.** N# is authored directly. `nlc export csharp` is for inspection, not a conversion workflow.
- **CLI docs must track help/completions.** Current top-level commands and `nlc query` subcommands are registered in `CommandRegistry` and surfaced by `nlc --help`, `nlc query help`, and `nlc completion <shell>`.

## Language Semantics

- **Pattern guard exhaustiveness is conservative.** Guarded arms do not prove coverage. Add an unguarded union arm or wildcard fallback when a match must be exhaustive.
- **Nested union matching has edge cases.** Curated nested-union patterns are supported, but deep/constrained nested coverage should be verified with focused tests before it is advertised as complete.
- **Type alias emission inherits C# alias restrictions.** Same-namespace aliases and nullable reference aliases can hit C# `using` alias limitations.
- **Attribute support is scenario-based, not blanket parity.** Declaration and parameter attributes are parsed/formatted and current targeted tests cover C# stubs plus IL parameter metadata. Verify framework-specific attribute scenarios, especially ASP.NET controllers/model binding and xUnit discovery, with focused tests before using them as release evidence.
- **Null-forgiving `!` should not become an escape hatch.** Prefer explicit null checks or null-coalescing. Diagnostics for null/default-forgiving syntax should come from token/parser/AST/semantic analysis, not source-only scans.

## Build and Performance

- **Incremental behavior depends on the active workflow.** The daemon caches analysis for CLI/query flows, but broad project builds may still do more work than a mature incremental compiler.
- **Large-project performance needs scenario evidence.** Do not make Go/Rust-speed claims without benchmark output for the target repo and command.

## IDE Support

- **VS Code support is real but must be visually verified for launch claims.** Syntax highlighting, diagnostics, hover/completion, code actions, and related LSP behavior have tests, but user-facing IDE claims require a fresh extension reload plus real VS Code visual QA.
- **Debugger UX is not a public polished workflow.** F5/debugging should remain hidden or caveated until there is a tested N# debugger-backed flow.

## Documentation Rules

- Avoid absolute claims such as "perfect interop," "all features implemented," "production-ready," or "it just works" unless the exact scenario is backed by a fresh gate.
- Prefer phrases like "designed for," "covered scenarios," "curated examples," and "verify with" when describing active surfaces.
- Keep private customer/application artifacts out of the repository unless explicitly redacted and approved.
