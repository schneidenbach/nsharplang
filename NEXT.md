# Next Up

Updated: 2026-03-27

## Completed (just merged)

All Tier 1 and Tier 2 IDE tooling from the previous roadmap has been merged:
- Auto-import on completion (PR #1)
- Find All References handler (PR #2)
- Snippet completions (PR #3)
- Inlay hints for type inference (PR #4)
- Workspace-wide diagnostics (PR #5)
- N# function signature help (PR #6)
- Cross-file go-to-definition (PR #7)
- Document symbols / Outline (PR #9)

## Test Coverage Gaps

### Critical: Zero Tests
| Feature | LOC | Gap |
|---------|-----|-----|
| **nlc daemon** | 400+ | Socket communication, file watching, idle timeout, PID files, start/stop lifecycle |
| **nlc check** | ~40 | Exit codes, output formatting, diagnostics reporting |
| **nlc fix CLI** (FixCommand) | 197 | `--dry-run`, `--file`, `--project`, multi-file application, JSON output envelope |

### Thin: Needs More Coverage
| Feature | Tests | Gap |
|---------|-------|-----|
| **CompletionEngine** | 3 | No namespace/type/parameter/generic completions tested |
| **FixApplicator** | 0 direct | Only tested indirectly via CodeFixTests — no multi-edit ordering or overlap tests |
| **BindingMap** | 5 integration | No unit tests for internals, forward refs, or generic bindings |

## Remaining Work

### Tier 3 — LLM Toolchain Polish
- [ ] Audit `nlc format` (zero-config, one canonical style)
- [ ] SemanticModel field/property recording (completions use AST fallback)
- [ ] BindingMap for cross-file type references (imports don't record bindings)
- [ ] `nlc build --release` and target/runtime selection for first-class cross-compilation
- [ ] `nlc deps tree` or equivalent dependency graph visualization
- [ ] `nlc test --coverage` with stable report formats
- [ ] `nlc bench` / benchmark mode
- [ ] Build timing reports (`cargo build --timings` equivalent)

### Infrastructure
- [ ] Fix CI: Visual Studio extension build (`langServerPath` variable error in NSharpLanguageClient.cs)
- [ ] Fix CI: 3 ASP.NET template/example build failures (Web API template, WeatherDemo, 13-aspnet-demo)
- [ ] Interpolated string AST support (currently parsed as single StringLiteralExpression — symbols inside `$"...{expr}..."` only resolve via text fallback, not semantic AST)

### Language Features (from limitations.md)
- [ ] Lambda type inference from call-site context
- [ ] Generic type inference (constraint solving)
- [ ] Method overload resolution by type (currently count-only)
- [ ] Extension methods on literals
- [ ] Circular import detection
