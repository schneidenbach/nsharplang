# Next Up

Updated: 2026-03-27

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

Note: The query pipeline (96 tests), OutputFormatter (35 tests), LSP handlers (~60 tests), and CodeIntelligenceService (61 tests) are all well-covered.

## Remaining IDE Tooling (from current_issues.md)

### Tier 1 — Must Have
- [ ] Auto-import on completion (additionalTextEdits)
- [ ] Find All References LSP handler (BindingMap exists, need ReferencesHandler)
- [ ] Cross-file go-to-definition in LSP (CLI works, LSP needs CodeIntelligenceService)
- [ ] Workspace-wide diagnostics (analyze all .nl files on open)

### Tier 2 — Important
- [ ] N# function signature help (currently .NET types only)
- [ ] Document symbols / Outline LSP handler (CLI works, need DocumentSymbolHandler)
- [ ] Inlay hints for type inference (`: string` ghost text after `:=`)
- [ ] Snippet completions (`func` → template, `if` → block, `match` → expression)

### Tier 3 — LLM Toolchain Polish
- [ ] `nlc query doc` (API documentation from CLI)
- [ ] Audit `nlc format` (zero-config, one canonical style)
- [ ] SemanticModel field/property recording (completions use AST fallback)
- [ ] BindingMap for cross-file type references (imports don't record bindings)
