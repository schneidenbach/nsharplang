# Task 028: Build Benchmark Corpus And Results Workflow Around `nlc bench`

Priority: P2 evidence and performance.

Work in the N# repository and turn `nlc bench` into an evidence-producing workflow. The command exists; the missing work is benchmark content, repeatable results, and regression visibility.

## Scope

- Audit current `nlc bench` behavior and any benchmark examples.
- Create a benchmark corpus covering compile/check speed and representative runtime scenarios.
- Produce JSON and markdown artifacts that can be cited by docs or launch materials.
- Decide whether CI should run benchmarks on a scheduled or manual cadence without slowing normal PR validation.

## Likely Files

- `src/NSharpLang.Cli/Commands/BenchCommand.cs`
- `benchmarks`
- `examples`
- `docs`
- `.github/workflows`
- `tests/CliParityAuditTests.cs`
- `tests/CliCommandTests.cs`

## Acceptance

- A benchmark corpus covers compile/check speed and representative runtime scenarios.
- Benchmarks run locally through documented commands and produce JSON/markdown artifacts.
- CI runs benchmarks on an intentional cadence and publishes artifacts without slowing normal PR validation.
- Docs and website claims cite actual benchmark artifacts, not targets.

## Verification

- Run focused benchmark command tests while developing.
- Run the benchmark corpus locally and inspect generated artifacts.
- Run `./scripts/test-all.sh` before committing if code or scripts change.
