# Publishing N# Packages

This document describes the release artifact set behind the one-line public installer.

## Public Artifact Set

Users install NSharpLang through one front door:

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash
```

That installer expects these artifacts to exist for the target version:

- `NSharpLang.Cli`: global tool that provides `nlc`
- `NSharpLang.Sdk`: MSBuild SDK restored by generated project build files
- `NSharpLang.Templates`: `dotnet new` templates used by `nlc new`/template consumers
- `NSharpLang.LanguageServer`: global tool that provides `nsharp-lsp`
- `NSharpLang.Compiler`: compiler API library used by SDK/tooling packages
- `nsharp.nsharp` VS Code extension, either published to the marketplace/Open VSX path or provided as a release VSIX via `NSHARP_VSIX_URL`

Internal package names can stay internal to scripts and release automation; public docs should point users at the installer and `nlc doctor`, not manual package-by-package setup.

## Version Source

NuGet package versions are read from each project file's `<Version>` element:

- `src/NSharpLang.Cli/Cli.csproj`
- `src/NSharpLang.Sdk/NSharpLang.Sdk.csproj`
- `src/NSharpLang.Compiler/Compiler.csproj`
- `src/NSharpLang.LanguageServer/LanguageServer.csproj`
- `templates/NSharpLang.Templates.csproj`

`scripts/pack-nuget.sh` packs those projects. `scripts/publish-nuget.sh` reads the same project-file versions when validating artifact names, so there is no second hard-coded version table to drift.

The public installer does not expose exact version pinning while those project-file versions are mixed. `scripts/install.sh --version ...` fails fast with an explanation instead of applying one version to every package and producing a partial install. Re-enable a single public pin only after CLI, SDK, templates, compiler, and language server releases share one unified NSharpLang version, or replace it with explicit package-specific pins.

The VS Code extension version is currently sourced from `editors/vscode/package.json`; publish the generated VSIX alongside the NuGet release or publish it to the extension marketplace before marking the IDE installer path public-green.

## Pack Locally

```bash
./scripts/pack-nuget.sh
```

Outputs:

- `artifacts/nuget/*.nupkg`
- `artifacts/vscode/*.vsix` unless `SKIP_VSCODE_PACKAGE=1` is set

For package-only smoke runs:

```bash
SKIP_VSCODE_PACKAGE=1 ./scripts/pack-nuget.sh
```

## Smoke the Turnkey Installer

Run the local-feed smoke before publishing:

```bash
./scripts/smoke-turnkey-install.sh
```

The smoke creates an isolated `HOME` with a NuGet config that clears all package sources except `artifacts/nuget`, verifies that unsupported `--version` pins fail fast, installs from that local feed, runs:

```bash
nlc --version
nlc doctor --skip-vscode
nlc new MyApp
cd MyApp
nlc build
nlc run
```

Logs are written under `artifacts/smoke-turnkey/<timestamp>/smoke.log`.

For a full workstation/IDE smoke after publishing the VSIX or marketplace entry:

```bash
./scripts/install.sh --source ./artifacts/nuget
nlc doctor --require-vscode
code --list-extensions | grep -i '^nsharp\.nsharp$'
```

## Publish NuGet Packages

```bash
export NUGET_API_KEY=your_api_key_here
./scripts/publish-nuget.sh
```

The script validates package names from project-file versions and pushes with `--skip-duplicate`.

## Publish VS Code Tooling

NuGet cannot install VS Code extensions. Before announcing the installer as public-green, do one of:

1. Publish `nsharp.nsharp` to the VS Code Marketplace/Open VSX, so `code --install-extension nsharp.nsharp --force` works; or
2. Attach the VSIX from `artifacts/vscode/` to a versioned GitHub release and set `NSHARP_VSIX_URL` in installer docs/release notes for that version.

If neither exists, block the release and state that the missing external artifact is the VS Code extension publication target.

## Uninstall / Update

Update to latest:

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash
```

Exact version pinning is disabled until all public NSharpLang packages use one unified release version. `--version` exits before installing anything so releases cannot silently mix incompatible package versions.

Uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash -s -- --uninstall
```

## Troubleshooting

### `nlc doctor` reports missing templates or tools

Re-run the installer with the exact source you intended:

```bash
./scripts/install.sh --source ./artifacts/nuget
```

### SDK restore fails in a fresh project

Check `global.json`, `NuGet.config`, and the configured feed. The installer writes a shared reference config to `~/.nsharp/NuGet.config`, but generated projects should carry the feed information needed for their target release.

### VS Code extension install fails

Confirm the external artifact exists:

```bash
code --install-extension nsharp.nsharp --force
# or
NSHARP_VSIX_URL=https://.../nsharp-<version>.vsix ./scripts/install.sh
```
