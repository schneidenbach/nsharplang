# Publishing N# Packages

This document describes how to pack and publish the NuGet packages that make up the N# toolchain.

## Package Set

The current package set is:

- `NSharpLang.Sdk`: MSBuild SDK for `dotnet build`
- `NSharpLang.Templates`: `dotnet new` templates
- `NSharpLang.Compiler`: compiler API package
- `NSharpLang.Cli`: standalone CLI tool package that provides the `nlc` command
- `NSharpLang.LanguageServer`: standalone LSP tool package

## Prerequisites

1. A NuGet.org account with permission to publish these package IDs.
2. `NUGET_API_KEY` exported in your shell.
3. A clean `artifacts/nuget/` directory containing fresh packages from this repo.

## Pack Locally

Run:

```bash
./scripts/pack-nuget.sh
```

This builds the task assembly and packs all published artifacts into `artifacts/nuget/`.

Expected output files:

- `artifacts/nuget/NSharpLang.Sdk.0.1.0.nupkg`
- `artifacts/nuget/NSharpLang.Templates.1.0.0.nupkg`
- `artifacts/nuget/NSharpLang.Compiler.1.0.0.nupkg`
- `artifacts/nuget/NSharpLang.Cli.0.1.0.nupkg`
- `artifacts/nuget/NSharpLang.LanguageServer.1.0.0.nupkg`

## Smoke Test Locally

### Templates

```bash
dotnet new uninstall NSharpLang.Templates
dotnet new install artifacts/nuget/NSharpLang.Templates.1.0.0.nupkg
dotnet new list nsharp
```

### SDK

Create a temporary test project and point it at the local package feed:

```bash
mkdir -p /tmp/nsharp-test
cd /tmp/nsharp-test

dotnet nuget add source /absolute/path/to/nsharplang/artifacts/nuget --name NSharpLocal
dotnet new nsharp-console -o TestApp
cd TestApp
dotnet build
dotnet run
```

When finished:

```bash
cd /tmp
rm -rf /tmp/nsharp-test
dotnet nuget remove source NSharpLocal
```

## Publish to NuGet.org

Run:

```bash
export NUGET_API_KEY=your_api_key_here
./scripts/publish-nuget.sh
```

The publish script verifies that all expected package files exist, then pushes each package to NuGet.org.

## Manual Publishing

If you need to push packages manually:

```bash
dotnet nuget push artifacts/nuget/NSharpLang.Sdk.0.1.0.nupkg --api-key "$NUGET_API_KEY" --source https://api.nuget.org/v3/index.json
dotnet nuget push artifacts/nuget/NSharpLang.Templates.1.0.0.nupkg --api-key "$NUGET_API_KEY" --source https://api.nuget.org/v3/index.json
dotnet nuget push artifacts/nuget/NSharpLang.Compiler.1.0.0.nupkg --api-key "$NUGET_API_KEY" --source https://api.nuget.org/v3/index.json
dotnet nuget push artifacts/nuget/NSharpLang.Cli.0.1.0.nupkg --api-key "$NUGET_API_KEY" --source https://api.nuget.org/v3/index.json
dotnet nuget push artifacts/nuget/NSharpLang.LanguageServer.1.0.0.nupkg --api-key "$NUGET_API_KEY" --source https://api.nuget.org/v3/index.json
```

## Publish to GitHub Packages (Private Feed)

For private consumption across machines, packages are published to GitHub Packages.

### Automated (CI)

Push a version tag to trigger the publish workflow:

```bash
git tag v0.1.0
git push origin v0.1.0
```

This runs `.github/workflows/publish.yml` which builds, tests, packs, and pushes all packages to `https://nuget.pkg.github.com/schneidenbach/index.json`.

### Manual

```bash
export GITHUB_TOKEN=ghp_your_pat_with_write_packages
./scripts/pack-nuget.sh
./scripts/publish-github-packages.sh
```

The script pushes all `.nupkg` files from `artifacts/nuget/` with `--skip-duplicate` to handle re-publishes gracefully.

### Consuming from Another Machine

**One-liner** (requires `gh` CLI authenticated with `gh auth login`):

```bash
bash <(gh api repos/schneidenbach/nsharplang/contents/scripts/setup-consumer.sh -H "Accept: application/vnd.github.raw")
```

This auto-detects your `gh` token, registers the feed, and installs templates + CLI + language server. It also writes a reusable `NuGet.config` to `~/.nsharp/NuGet.config` for new projects.

If you have the repo cloned locally, you can also run:

```bash
./scripts/setup-consumer.sh
```

## After Publishing

Verify the packages are searchable on NuGet.org, then update any external install docs to use:

```bash
dotnet new install NSharpLang.Templates
dotnet tool install -g NSharpLang.Cli
dotnet tool install -g NSharpLang.LanguageServer
```

## Troubleshooting

### SDK restore fails

Check that `global.json` references the correct `NSharpLang.Sdk` version and that the required package source is configured.

### Templates do not appear in `dotnet new list`

Clear the template cache and reinstall:

```bash
dotnet new --debug:reinit
dotnet new uninstall NSharpLang.Templates
dotnet new install artifacts/nuget/NSharpLang.Templates.1.0.0.nupkg
```

### CLI or language server install command fails

Use the package IDs, not the command names:

- `dotnet tool install -g NSharpLang.Cli`
- `dotnet tool install -g NSharpLang.LanguageServer`
