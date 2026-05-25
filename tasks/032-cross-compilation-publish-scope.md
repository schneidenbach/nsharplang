# Task 032: Decide Cross-Compilation And Publish-Target Scope

Priority: P2 ecosystem.

Work in the N# repository and make release/publish target support explicit. Cross-compilation remains future work, and release/publish target evidence is limited.

## Scope

- Audit `nlc build --release`, `nlc publish`, target-runtime options, docs, website docs, templates, and tests.
- Define exactly what target-platform workflows are supported today.
- Make unsupported target scenarios fail with clear guidance.
- Add scenario tests for every supported publish target path.

## Likely Files

- `src/NSharpLang.Cli`
- `src/NSharpLang.Sdk`
- `docs`
- `website/docs`
- `tests/CompilationBackendTests.cs`
- `tests/CliCommandTests.cs`

## Acceptance

- Product docs state exactly what `nlc build --release`, `nlc publish`, and target-platform workflows support today.
- Unsupported target scenarios fail with clear guidance.
- Any supported cross-target path has scenario tests.
- Launch and website materials do not imply unsupported cross-compilation.

## Verification

- Run focused build/publish CLI and SDK tests while developing.
- Run `./scripts/test-all.sh` before committing.
