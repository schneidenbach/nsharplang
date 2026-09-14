# N# Compiler and Toolset Documentation

**Status:** Active implementation notes. Current code and recent commits are authoritative; docs are useful
only when they match product-path behavior.

## Compiler Ownership Rule

The compiler-only ownership objective is complete at the verified `0cc84110` checkpoint;
[final acceptance](../systems-language-closeout/decodes/2026-09-09-compiler-only-ownership-complete.md). Sole N# compiler behavior and canonical assertions remain required;
see [the execution contract](../tasks/README.md) and [current cursor](../systems-language-closeout/STATUS.md).
The complete Analyzer and SystemsAnalyzer are N#-owned in Compiler Core; both C# classes are
deleted and verified through installed SDK self-hosting. The complete ColumnarProgramInputBuilder
is also N#-owned, with its C# class deleted and canonical/package/self-host verification accepted.
The complete ColumnarIlEmitter is N#-owned and its C# class is deleted, with canonical, installed
SDK self-host and IDE verification accepted. Complete MultiFileCompiler ownership and its ten
recovery canonicals are accepted at `27b1a8a1b`, including installed SDK self-host and real unsaved
editor verification. Complete recursive compiler reference resolution is now N#-owned in the working
branch, with its C# class deleted and seven direct plus four command-level N# canonicals integrated;
its fresh gate and installed SDK verification are accepted at `a20dc98af`. The complete SDK task,
including reference-assembly scan/rewrite, is now N#-owned in `EmitIlAssembly.nl`; its C# class is
deleted and SDK routing is direct. Fresh integration and installed self-host verification pass at
`b13cc7622`; see [SDK task acceptance](../systems-language-closeout/decodes/2026-09-09-complete-sdk-emit-task-ownership.md). Historical allowlist labels do not prove
current compiler-wide completion. CLI/editor features and broader branch work stay separately
recorded; SDK/tooling changes are in scope only as demonstrated compiler migration dependencies.
Do not preserve fallback emitters or expand `*DogfoodAdapter` layers into product architecture.

Compiler-service kernels are statically compiled through `NSharpLang.Compiler.Core`;
product paths must not use `Assembly.Load`/delegate reflection for N# compiler services. Because
Compiler Core is built by the pinned stage-0 SDK, any kernel that uses a tip-only language or
backend feature requires a local SDK repin with `./scripts/setup-local.sh` before it is a valid
kernel shape.

## Self-Host: the front door and the seed

Two different compilers touch `src/NSharpLang.Compiler.Core` and they do not see the same program.

**The seed compiles it without analysis.** Every build and every gate step compiles Core with the
PINNED stage-0 SDK in `bootstrap/`, through the SDK's emit-only path, which skips analysis and lint
entirely. **The tip compiler's front door (`nlc check` / `nlc build --project`) runs the whole
pipeline.** So the tip compiler can stop being able to compile the compiler's own source and nothing
in the gate notices. That is not hypothetical: four `while true { ... return ... }` loops in Core
carried a dead trailing `return` that the old seed accepted and the tip refuses
(`emit.statement.unreachable-after-transfer`, NL312), and it surfaced only during a hand republish of
the seed.

`Step 2c: Self-Host Front Door` in `tests/scripts/test-all-core.sh` closes that blind spot. It runs
`nlc check --json` over `src/NSharpLang.Compiler.Core`, `src/NSharpLang.Compiler`,
`src/NSharpLang.Playground` and `src/NSharpLang.Build.Tasks` with the CLI the gate just built and
fails on any INCREASE over the committed ceilings. **The ceilings are a backlog, not a target**: the
front door reports diagnostics on Core's own source that the emit-only path never asked about
(missing and unused imports, nullable arguments passed to non-nullable parameters, definite-assignment
holes, ambiguous simple names). They exist to be driven to zero and must never be raised. The step is
inside the validated step cache on the UNIT input set, so it runs only when the compiler's own
sources move.

**Measured 2026-09-14 on the tip CLI** (`0.1.0+12cf4b384`, loaded machine): Core 1374 diagnostics in
**19m20s** — the brief's "Core check is seconds" is wrong by three orders of magnitude, and the cost
is the reason the step lives behind the step cache. `src/NSharpLang.Build.Tasks` has no `.nl` sources
at all today (MSBuild targets plus C# tasks): 0 diagnostics in 0.1s.

`src/NSharpLang.Compiler` and `src/NSharpLang.Playground` carry the ceiling **-1, meaning BLOCKED**.
`check` on a project builds its project references first, and that build fails while Core's own front
door is not clean — so both answer an `error` envelope rather than a diagnostic list and there is
nothing to count. Their own `.nl` sources report ZERO today (measured through `--text`, which renders
the failed reference build's 287 Core errors instead of aborting). When Core reaches 0 their ceilings
become real numbers.

The classification of Core's 1374, and what is left to drive it to zero, is the SELFHOST stream
report: the large buckets are NL905 (432 possible null dereference), NL202 (366 nullable argument),
NL002 (244 type used without its import), NL010 (192 unused import), NL012/NL011/NL304 (96 unused
parameters, empty catches and definite-assignment holes). Every one of those is a REAL source defect
that the emit-only path never asked about — not an analyzer bug — and fixing them touches roughly 300
of Core's 819 files, which is why they were not done inside a parallel census stream.

### Republishing the seed

`./scripts/reseed.sh` is the runbook, and every step of it exists because skipping it produced a seed
that could not rebuild itself:

1. pack the SDK and runtime with the CURRENT seed
2. install them into `bootstrap/` and re-pin `SHA256SUMS`
3. evict `nsharplang.sdk` and `nsharplang.runtime` from the NuGet cache — a republished seed keeps its
   version, so the cache serves the OLD bytes forever and the rebuild proves nothing
4. `scripts/verify-bootstrap.py`
5. clean self-rebuild of Core (`obj` must go: `project.assets.json` pins the resolved SDK path)
6. **pack AGAIN** — these are the packages a compiler COMPILED BY ITSELF produces, and they are the
   ones that get committed. A one-stage seed cannot carry a change to the MSBuild task surface,
   because stage 1's tasks were built by the OLD SDK
7. install stage 2, evict, verify, clean self-rebuild again
8. the compiler-service estate

`NSHARP_RESEED_BOOTSTRAP_DIR`, `NSHARP_RESEED_PACKAGES_DIR` and `NSHARP_RESEED_STAGE_ROOT` point the
run at a scratch seed and a scratch package cache, and `NSHARP_RESEED_STOP_AFTER=<step>` stops after
one; that is how the runbook is exercised without touching the committed seed.
`scripts/verify-bootstrap.py` honours `NSHARP_BOOTSTRAP_DIR` for the same reason. Commit the
`.nupkg` files and `SHA256SUMS` together, never separately.

## Quick Lookup

| Question | Read |
|----------|------|
| Understand current architecture? | [architecture.md](architecture.md) |
| Work on CLI/tooling behavior? | [components/cli-toolchain.md](components/cli-toolchain.md) |
| Run tests and gates? | [testing.md](testing.md) |
| Check known limitations? | [limitations.md](limitations.md) |
| Work on language features? | Current source, recent commits, tests, and focused website docs |
| Work on Systems N#? | Current source, recent commits, tests, and [../website/docs/systems.md](../website/docs/systems.md) |

## Components

| Component | File | Key Topics |
|-----------|------|------------|
| Lexer | [components/lexer.md](components/lexer.md) | Tokenization, strings, operators |
| Parser | [components/parser.md](components/parser.md) | AST construction, precedence, patterns |
| Analyzer | [components/analyzer.md](components/analyzer.md) | Types, scopes, semantic checking |
| CLI Toolchain | [components/cli-toolchain.md](components/cli-toolchain.md) | `check`, `fix`, `query`, daemon, completions, JSON schemas |
| Error Reporting | [components/error-reporting.md](components/error-reporting.md) | Error codes, formatting, suggestions |

## Testing

Read [testing.md](testing.md). Do not hard-code test totals; use fresh command output or dated evidence
from the relevant test run.

## Related Documentation

- [../README.md](../README.md) - repository overview and setup
- [../docs/README.md](../docs/README.md) - user-facing and design documentation map
- [../website/docs/](../website/docs/) - published documentation source

## Deleted Stale Docs

The old self-host progress log, dogfood rewrite plan, benchmark summary, columnar roadmap, SoA gate,
performance refactor plan, cross-language systems benchmark roadmap, implementation audit, and parity
audit docs were removed because they repeatedly instructed agents to route through N# while preserving
legacy compiler ownership or optimizing proof artifacts instead of deleting old owners. Do not
recreate those files as history archives; use current code, recent commits, and tests instead.
