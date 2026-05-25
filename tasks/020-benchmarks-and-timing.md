# Task 020: Benchmarks And Timing Evidence

Priority: P2.

Turn performance claims into measured evidence. This task owns `nlc bench` corpus work, build/check timing output decisions, artifacts, docs, and launch claims.

## User Outcome

When N# claims speed or shows timing, the claim is backed by current benchmark or build/check artifacts. If the evidence is not available, public docs should not make the claim.

## Scope

- Audit `nlc bench`, existing examples, docs, website, README, talk materials, and CLI timing output.
- Build a benchmark corpus covering compile/check speed and representative runtime scenarios.
- Produce JSON/markdown artifacts that docs can cite.
- Decide whether build/check timing output should be exposed by the CLI.
- Remove or soften timing/performance claims that lack current evidence.

## Likely Files

- `src/NSharpLang.Cli/Commands/BenchCommand.cs`
- `src/NSharpLang.Cli`
- `benchmarks`
- `examples`
- `docs`
- `website/docs`
- `docs/talk`
- `.github/workflows`
- `tests/CliCommandTests.cs`
- `tests/CliParityAuditTests.cs`

## Acceptance

- Benchmark corpus covers compile/check speed and representative runtime scenarios.
- Benchmarks run locally through documented commands and produce citeable artifacts.
- Any CLI timing output has a tested shape and avoids brittle duration assertions.
- Public performance claims cite current artifacts or are removed.

## Verification

- Run focused benchmark and CLI tests while developing.
- Run the benchmark corpus locally and inspect artifacts.
- Run docs/website checks if docs change.
- Run `./scripts/test-all.sh` before committing if code changes.
