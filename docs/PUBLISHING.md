# Publishing N# Packages

This document describes the release artifact set behind the one-line public installer.

## Public Artifact Set

Users install NSharpLang through one front door:

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . "$HOME/.nsharp/env"
```

The installer downloads from `https://github.com/schneidenbach/nsharplang/releases/latest/download/`.
GitHub's latest release is the newest successful `main` build: the `Build` workflow publishes each
`main` push as a full (non-pre-release) `unofficial-main-*` release and marks it latest, while PR
builds stay pre-releases that never take latest (see `.github/RELEASES.md`). Every release carries:

- `nsharp-toolset.tar.gz`: package-manager-ready `nlc` and `nsharp-lsp` app payloads plus launchers
- `nsharp.vsix`: the `nsharp.nsharp` VS Code extension. It is not published to the VS Code
  Marketplace; the installer installs this asset directly when the `code` CLI is available.
- `SHA256SUMS`: one `<sha256>  <asset name>` line for every other asset. **Required.**
  `scripts/install.sh` verifies every URL download against this asset and refuses to install on a
  missing or mismatched checksum. The `Build` workflow's publish step generates it from the exact
  asset set it uploads.
- The NuGet packages, including `NSharpLang.Sdk` (MSBuild SDK restored by generated project build
  files), `NSharpLang.Templates` (`dotnet new` templates used by `nlc new`/template consumers), and
  `NSharpLang.Compiler` (compiler API library used by SDK/tooling packages)

Internal package names can stay internal to scripts and release automation; public docs should point users at the installer and `nlc doctor`, not manual package-by-package setup.

## Version Source

NuGet package versions are read from each project file's `<Version>` element:

- `src/NSharpLang.Cli/Cli.csproj`
- `src/NSharpLang.Sdk/NSharpLang.Sdk.csproj`
- `src/NSharpLang.Compiler/Compiler.csproj`
- `src/NSharpLang.LanguageServer/LanguageServer.csproj`
- `templates/NSharpLang.Templates.csproj`

`scripts/pack-nuget.sh` packs SDK/template/compiler NuGet packages and publishes the `nsharp-toolset.tar.gz` app artifact. `scripts/publish-packages.sh` reads project-file versions when validating NuGet package names, so there is no second hard-coded version table to drift.

The public installer does not expose exact version pinning while those project-file versions are mixed. `scripts/install.sh --version ...` fails fast with an explanation instead of applying one version to every package and producing a partial install. Re-enable a single public pin only after CLI, SDK, templates, compiler, and language server releases share one unified NSharpLang version, or replace it with explicit package-specific pins.

The VS Code extension version is currently sourced from `editors/vscode/package.json`; the generated VSIX ships as the `nsharp.vsix` release asset.

## Pack Locally

```bash
./scripts/pack-nuget.sh
```

Outputs:

- `artifacts/nuget/*.nupkg`
- `artifacts/toolset/nsharp-toolset.tar.gz`
- `artifacts/vscode/*.vsix` and the stable fallback asset `artifacts/vscode/nsharp.vsix` unless `SKIP_VSCODE_PACKAGE=1` is set

For package-only smoke runs:

```bash
SKIP_VSCODE_PACKAGE=1 ./scripts/pack-nuget.sh
```

## Smoke the Turnkey Installer

Run the local toolset smoke before publishing:

```bash
./scripts/smoke-turnkey-install.sh
```

The smoke creates an isolated `HOME`, builds `nsharp-toolset.tar.gz`, verifies that unsupported `--version` pins fail fast, installs from that local toolset archive, rewrites the generated smoke app's `NuGet.config` to remove `nuget.org`, asserts the app config has `<clear />` and exactly one package source (`nsharp-local` pointing at the installed N# package cache), then runs:

```bash
nlc --version
nlc doctor --skip-vscode
nlc new MyApp
cd MyApp
nlc build
nlc run
```

Logs are written under `artifacts/smoke-turnkey/<timestamp>/smoke.log`.

For a full workstation/IDE smoke from local build outputs (`file://` sources skip the
`SHA256SUMS` check):

```bash
./scripts/install.sh --source ./artifacts/toolset/nsharp-toolset.tar.gz --vsix-url "file://$(pwd)/artifacts/vscode/nsharp.vsix"
nlc doctor --require-vscode
code --list-extensions | grep -i '^nsharp\.nsharp$'
```

## Publish NuGet Packages

```bash
export NUGET_API_KEY=your_api_key_here
./scripts/publish-packages.sh --target nuget
```

The script validates package names from project-file versions and pushes with `--skip-duplicate`.

To publish the same package set to GitHub Packages:

```bash
export GITHUB_TOKEN=your_token_here
./scripts/publish-packages.sh --target github
```

## Publish VS Code Tooling

NuGet cannot install VS Code extensions, and `nsharp.nsharp` is not published to the VS Code
Marketplace or Open VSX. The extension ships only as the `nsharp.vsix` release asset, which the
public installer downloads from `https://github.com/schneidenbach/nsharplang/releases/latest/download/nsharp.vsix`,
verifies against `SHA256SUMS`, and installs with `code --install-extension`. A release without
`nsharp.vsix` and its `SHA256SUMS` entry breaks the installer's VS Code step.

## Release Asset Integrity

Every GitHub Release that carries downloadable assets MUST include a `SHA256SUMS` asset
listing every other asset by its release name, including `nsharp-toolset.tar.gz` and
`nsharp.vsix`. The `Build` workflow generates it for every `main` and PR release.
`scripts/install.sh` downloads `SHA256SUMS` from the same release
path as the asset (override with `NSHARP_SUMS_URL`), and hard-fails on a missing sums
asset, a missing entry, or a hash mismatch. `--no-verify` exists only for custom
`--source` locations that intentionally have no checksums; never document it as part of
the public install path.

## Uninstall / Update

Update to latest:

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . "$HOME/.nsharp/env"
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
./scripts/install.sh --source ./artifacts/toolset/nsharp-toolset.tar.gz
```

### SDK restore fails in a fresh project

Check `global.json`, `NuGet.config`, and the configured feed. The installer writes a shared reference config to `~/.nsharp/NuGet.config`, but generated projects should carry the feed information needed for their target release.

### VS Code extension install fails

Confirm the latest release carries `nsharp.vsix` and a `SHA256SUMS` entry for it, then re-run the
installer, or install a specific VSIX:

```bash
NSHARP_VSIX_URL=https://.../nsharp.vsix ./scripts/install.sh
```
