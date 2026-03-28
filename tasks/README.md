# N# Launch Task Board

All tasks follow the protocol in `STANDARD-SUFFIX.md`: test → Codex review → PR → merge → deploy.

## In Progress (Slices A-D)
- **A**: Overload resolution + generic inference (Analyzer.cs)
- **B**: Circular imports + exhaustiveness guards (Analyzer.cs)
- **C**: Parameter attributes + null-forgiving (Parser.cs)
- **D**: Source maps / #line directives (Transpiler.cs)

## Queue — Language
- **E**: [Lambda inference + extension on literals](E-lambda-inference-extension-literals.md) — Analyzer.cs
- **F**: [Type aliases → real `using` directives](F-type-aliases.md) — Transpiler.cs
- **G**: [Parser error recovery](G-parser-error-recovery.md) — Parser.cs
- **H**: [Error message quality audit](H-error-message-quality.md) — ErrorReporting.cs

## Queue — Validation
- **I**: [Stress test app](I-stress-test-app.md) — examples/16-task-cli
- **O**: [Benchmark suite](O-benchmark-suite.md) — benchmarks/

## Queue — Developer Experience
- **J**: [User-facing docs](J-user-docs.md) — docs/guide/
- **K**: [Website overhaul](K-website-overhaul.md) — website/
- **L**: [VS Code extension polish](L-vscode-extension-polish.md) — editors/vscode/
- **P**: [Interactive playground](P-playground.md) — website/playground.html
- **Q**: [`nlc format` audit](Q-nlc-format-audit.md) — Formatter.cs
- **S**: [CLI tooling quality audit](S-tooling-quality-audit.md) — Go/Rust parity for nlc

## Queue — Ecosystem
- **M**: [GitHub Action](M-github-action.md) — actions/setup-nsharp/
- **N**: [C# → N# converter](N-removed-internal-migration.md) — nlc convert command
- **R**: [NuGet publishing pipeline](R-nuget-publishing.md) — SDK + templates

## Parallelism

```
Language (conflict zone — sequence these):
  E (Analyzer) → F (Transpiler) → G (Parser) → H (ErrorReporting)

Everything else is independent — run in parallel:
  I, J, K, L, M, N, O, P, Q, R
```
