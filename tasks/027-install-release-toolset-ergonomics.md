# Task 027: Unify Install, Release, And Local Toolset Ergonomics

Priority: P2 ecosystem.

Work in the N# repository and make public install, local dogfood setup, release artifacts, and VSIX install feel like one coherent supported toolchain.

## Scope

- Audit `scripts/install.sh`, `scripts/setup-local.sh`, local toolset deployment, `doctor`, package artifact generation, VSIX install, docs, website docs, and CI setup.
- Make version/source selection explicit and tested.
- Remove, document, or mark internal-only stale deployment scripts.
- Keep the public path, local development path, and release artifact path consistent.

## Likely Files

- `scripts`
- `src/NSharpLang.Cli`
- `editors/vscode`
- `docs`
- `website/docs`
- `tests/SetupLocalScriptTests.cs`
- `tests/CliCommandTests.cs`

## Acceptance

- Public install docs, local setup docs, `doctor`, package artifacts, VSIX install, and CI setup all describe the same supported model.
- Version/source selection is explicit and tested.
- Stale or ad hoc deployment scripts are either documented as internal-only or removed.
- Setup commands leave a clear, verified `nlc` on PATH or explain why not.

## Verification

- Run focused setup/install/CLI tests while developing.
- Run relevant dry-run setup commands.
- Run `./scripts/test-all.sh` before committing.
