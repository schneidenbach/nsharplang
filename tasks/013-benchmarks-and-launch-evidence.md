# Task 013: Benchmarks And Launch Evidence

Priority: P2.

Turn performance, maturity, launch-readiness, and feature-completeness claims into measured evidence or remove them. These belong together because both are about public credibility: claims in docs, memory, README, website, talks, and package artifacts must track current source-state evidence.

## User Outcome

When N# claims speed, maturity, marketplace readiness, debug support, production readiness, or feature completeness, the claim is backed by current artifacts. If the evidence is not available, public docs should not make the claim.

## Scope

- Audit `nlc bench`, existing examples, README, public docs, website docs, memory docs, talk materials, launch docs, package artifacts, and CLI timing output.
- Build a benchmark corpus covering compile/check speed and representative runtime scenarios.
- Produce JSON/markdown artifacts that docs can cite.
- Decide whether build/check timing output should be exposed by the CLI.
- Remove or soften timing/performance claims that lack current evidence.
- Remove static test counts unless generated from fresh artifacts.
- Tie marketplace, debug, benchmark, production-ready, and feature-complete claims to current evidence.
- Keep planned, partial, and verified workflows clearly distinguished.

## Likely Files

- `README.md`
- `src/NSharpLang.Cli/Commands/BenchCommand.cs`
- `src/NSharpLang.Cli`
- `benchmarks`
- `examples`
- `docs`
- `website/docs`
- `memory`
- `docs/talk`
- `.github/workflows`
- `tests/CliCommandTests.cs`
- `tests/CliParityAuditTests.cs`

## Acceptance

- Benchmark corpus covers compile/check speed and representative runtime scenarios.
- Benchmarks run locally through documented commands and produce citeable artifacts.
- Any CLI timing output has a tested shape and avoids brittle duration assertions.
- Public performance claims cite current artifacts or are removed.
- Public docs, website docs, README, memory docs, and talk materials avoid static test counts unless generated from fresh artifacts.
- Marketplace, debug, benchmark, production-ready, and feature-complete claims are tied to current evidence.
- Docs build passes after claim updates.
- No launch claim depends on stale local-only evidence.

## Verification

- Run focused benchmark and CLI tests while developing.
- Run the benchmark corpus locally and inspect artifacts.
- Run docs/website build or link checks if available.
- Run `./scripts/test-all.sh` before committing if code changes.
