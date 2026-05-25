# Task 009: Install, Release, And CI Setup

Priority: P2.

Unify public install, local dogfood setup, release artifacts, VSIX install, `doctor`, and the `setup-nsharp` GitHub Action into one coherent toolchain story. These belong together because every path answers the same question: how does a developer or CI runner get a verified N# toolset?

## User Outcome

A developer should understand one supported model for getting N# installed locally, in CI, and in VS Code. A repository should be able to use `actions/setup-nsharp` to install .NET, install N#, put `nlc` on PATH, and verify the toolchain without relying on stale installer flags.

## Scope

- Audit public installer, local setup, local toolset deployment, `doctor`, package artifact generation, VSIX install, docs, website docs, and CI setup.
- Add `actions/setup-nsharp/action.yml` using current installer behavior.
- Support latest or explicit toolset/source inputs without reintroducing unsupported `--version` behavior.
- Make version/source selection explicit and tested.
- Remove, document, or mark internal-only stale deployment scripts.
- Keep setup commands clear about PATH changes and VS Code extension installation.
- Dogfood the action in an appropriate workflow without assuming old `.csproj`-based project shapes.

## Likely Files

- `actions/setup-nsharp/action.yml`
- `.github/workflows`
- `scripts`
- `scripts/install.sh`
- `src/NSharpLang.Cli`
- `editors/vscode`
- `docs`
- `website/docs`
- `tests/SetupLocalScriptTests.cs`
- `tests/CliCommandTests.cs`

## Acceptance

- Public install docs, local setup docs, `doctor`, package artifacts, VSIX install, and CI setup describe the same model.
- The action installs .NET, installs N#, adds `~/.nsharp/bin` to PATH, and verifies `nlc`.
- Version/source selection is explicit and tested.
- Unsupported action inputs fail with clear guidance.
- Stale or ad hoc deployment scripts are documented as internal-only or removed.
- Setup leaves a clear verified `nlc` path or explains why not.
- At least one repository workflow dogfoods the action.

## Verification

- Validate workflow/action YAML.
- Run focused setup/install/CLI tests while developing.
- Run relevant dry-run setup commands.
- Run `./scripts/test-all.sh` before committing if code, scripts, or workflows change.
