# Console App CI/CD Example

This example shows how to set up CI/CD for an N# console application.

## Structure

```text
console-app/
├── .github/
│   └── workflows/
│       ├── build.yml      # Build and test on push/PR
│       └── release.yml    # Publish on version tags
├── Program.nl
├── project.yml
├── MyApp.csproj
└── README.md
```

## Quick Start

### 1. Copy Workflows

```bash
mkdir -p .github/workflows
cp ../../ci/templates/github-actions/build.yml .github/workflows/
cp ../../ci/templates/github-actions/release.yml .github/workflows/
```

### 2. Configure GitHub Secrets

Add to your repository settings -> Secrets and variables -> Actions:

- `NUGET_API_KEY` for release publishing

### 3. Push to GitHub

```bash
git add .
git commit -m "Add CI/CD workflows"
git push
```

The build workflow will run automatically.

## What the Templates Do

### `build.yml`

Runs on pushes and pull requests:

1. Checkout code
2. Install .NET SDK
3. Restore dependencies
4. Build with `dotnet build`
5. Run tests with `dotnet test`
6. Upload test results

### `release.yml`

Runs on version tags:

1. Restore, build, and test the project
2. Run `dotnet pack`
3. Push generated NuGet packages
4. Create a GitHub release

## Optional Quality Checks

If you also want format and lint gates:

```bash
cp ../../ci/templates/github-actions/format-check.yml .github/workflows/
cp ../../ci/templates/github-actions/lint.yml .github/workflows/
```

Those workflows install the standalone CLI tool package, `NSharpLang.Cli`, because formatting and linting currently live there.

## Troubleshooting

### Build fails to restore the N# SDK

Check that your project includes the generated `global.json` and `NuGet.config`, or that `NSharpLang.Sdk` is available from your configured package feeds.

### Format or lint workflow fails with `nlc not found`

Those optional workflows need the .NET tools directory on `PATH`. The shipped templates add it with `$GITHUB_PATH`.

### NuGet push fails

Check that:

1. `NUGET_API_KEY` is set correctly.
2. The package version does not already exist.
3. Your `.csproj` contains the package metadata required by `dotnet pack`.
