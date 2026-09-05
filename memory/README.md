# N# Compiler and Toolset Documentation

**Status:** Active implementation notes. Current code and recent commits are authoritative; docs are useful
only when they match product-path behavior.

## Compiler Ownership Rule

The compiler core, compiler-service core, and CLI/tooling command logic are N#-owned. Two surfaces
remain still-owning C# and are named in `memory/architecture.md`'s reviewed allowlist:
`Columnar/ColumnarIlEmitter.cs` (IL generation, retiring under task 015) and `Analyzer.cs`'s
`MetadataLoadContext` quarantine (retiring with the AOT external-type-model task).
Do not use documentation to justify keeping legacy fallback/legacy emitter ownership or
`*DogfoodAdapter` layers alive. Old dogfood/columnar strategy logs that normalized fallback work have
been deleted.

Compiler-service kernels are statically compiled through `NSharpLang.Compiler.BootstrapServices`;
product paths must not use `Assembly.Load`/delegate reflection for N# compiler services. Because
BootstrapServices is built by the pinned stage-0 SDK, any kernel that uses a tip-only language or
backend feature requires a local SDK repin with `./scripts/setup-local.sh` before it is a valid
kernel shape.

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
