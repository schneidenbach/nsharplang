# Task 024: Create A Current `setup-nsharp` GitHub Action

Priority: P2 ecosystem and CI setup.

Work in the N# repository and create a current GitHub Action for installing N#. There is no `actions/setup-nsharp` composite action, and old action specs are stale because the installer no longer supports a `--version` flag.

## Scope

- Add `actions/setup-nsharp/action.yml` around current installer semantics.
- Install .NET, install N# from latest or explicit toolset source, add `~/.nsharp/bin` to PATH, and verify `nlc`.
- Document inputs that match the current installer; do not reintroduce unsupported `--version` behavior.
- Dogfood the action in an appropriate workflow without depending on stale csproj assumptions for csproj-free projects.

## Likely Files

- `actions/setup-nsharp/action.yml`
- `.github/workflows`
- `scripts/install.sh`
- `docs`
- `website/docs`
- `tests` if script/action parity tests are available

## Acceptance

- `actions/setup-nsharp/action.yml` installs .NET, installs N# from latest or explicit toolset source, adds `~/.nsharp/bin` to PATH, and verifies `nlc`.
- README documents inputs that match the current installer.
- The repository dogfoods the action in an appropriate workflow without depending on stale `dotnet build` assumptions for csproj-free projects.
- Unsupported inputs fail with clear guidance.

## Verification

- Validate workflow/action YAML.
- Run focused script or docs parity tests where practical.
- Run `./scripts/test-all.sh` before committing if code, scripts, or workflows change.
