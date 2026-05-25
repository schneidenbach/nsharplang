# Task 015: `setup-nsharp` GitHub Action

Priority: P2.

Create a current GitHub Action that installs N# in CI and proves the public setup story. This task owns action YAML, installer semantics, docs, and dogfooding.

## User Outcome

A repository should be able to use `actions/setup-nsharp` to install .NET, install N#, put `nlc` on PATH, and verify the toolchain without relying on stale installer flags.

## Scope

- Add `actions/setup-nsharp/action.yml` using current installer behavior.
- Support latest or explicit toolset/source inputs without reintroducing unsupported `--version` behavior.
- Add docs that match the action inputs.
- Dogfood the action in an appropriate workflow without assuming old `.csproj`-based project shapes.

## Likely Files

- `actions/setup-nsharp/action.yml`
- `.github/workflows`
- `scripts/install.sh`
- `docs`
- `website/docs`
- `tests` if script/action parity tests are available

## Acceptance

- The action installs .NET, installs N#, adds `~/.nsharp/bin` to PATH, and verifies `nlc`.
- Unsupported inputs fail with clear guidance.
- Docs and examples match implemented inputs.
- At least one repository workflow dogfoods the action.

## Verification

- Validate workflow/action YAML.
- Run focused script or docs parity tests where practical.
- Run `./scripts/test-all.sh` before committing if code, scripts, or workflows change.
