# Task 016: Install, Release, And Local Toolset

Priority: P2.

Unify public install, local dogfood setup, release artifacts, VSIX install, and `doctor` into one coherent toolchain story.

## User Outcome

A developer should understand one supported model for getting N# installed locally, in CI, and in VS Code. Local setup and public install should not feel like different products.

## Scope

- Audit public installer, local setup, local toolset deployment, `doctor`, package artifact generation, VSIX install, docs, website docs, and CI setup.
- Make version/source selection explicit and tested.
- Remove, document, or mark internal-only stale deployment scripts.
- Keep setup commands clear about PATH changes and VS Code extension installation.

## Likely Files

- `scripts`
- `src/NSharpLang.Cli`
- `editors/vscode`
- `docs`
- `website/docs`
- `tests/SetupLocalScriptTests.cs`
- `tests/CliCommandTests.cs`

## Acceptance

- Public install docs, local setup docs, `doctor`, package artifacts, VSIX install, and CI setup describe the same model.
- Version/source selection is explicit and tested.
- Stale or ad hoc deployment scripts are documented as internal-only or removed.
- Setup leaves a clear verified `nlc` path or explains why not.

## Verification

- Run focused setup/install/CLI tests while developing.
- Run relevant dry-run setup commands.
- Run `./scripts/test-all.sh` before committing.
