# Console App CI/CD Example

This example shows how to set up CI/CD for a N# console application.

## Structure

```
console-app/
├── .github/
│   └── workflows/
│       ├── build.yml         # Build and test on push/PR
│       └── release.yml       # Publish on version tags
├── src/
│   └── Program.nl            # Main application code
├── project.yml               # N# project configuration
├── MyApp.csproj             # Minimal .csproj
└── README.md
```

## Quick Start

### 1. Copy Workflows

```bash
mkdir -p .github/workflows
cp ../../ci-templates/github-actions/build.yml .github/workflows/
cp ../../ci-templates/github-actions/release.yml .github/workflows/
```

### 2. Configure GitHub Secrets

Add to your repository settings → Secrets and variables → Actions:

- `NUGET_API_KEY` - Your NuGet.org API key (for releases)

### 3. Push to GitHub

```bash
git add .
git commit -m "Add CI/CD workflows"
git push
```

The build workflow will run automatically!

## Creating a Release

```bash
# Tag a new version
git tag v1.0.0
git push origin v1.0.0
```

This will:
1. Build the project
2. Run tests
3. Pack as NuGet package
4. Publish to NuGet.org
5. Create GitHub release with artifacts

## Workflows Explained

### build.yml

Runs on every push to `main` or `develop`, and on all pull requests:

1. Checkout code
2. Install .NET SDK
3. Install N# CLI (`nlc`)
4. Restore dependencies
5. Build
6. Run tests
7. Upload test results as artifacts

### release.yml

Runs when you push a version tag (`v*`):

1. All steps from build.yml
2. Pack NuGet package
3. Publish to NuGet.org
4. Create GitHub release

## Customization

### Change Target Branches

Edit the `on` section in workflows:

```yaml
on:
  push:
    branches: [ main, develop, staging ]  # Add more branches
```

### Add Code Quality Checks

Copy additional workflows:

```bash
cp ../../ci-templates/github-actions/format-check.yml .github/workflows/
cp ../../ci-templates/github-actions/lint.yml .github/workflows/
```

### Matrix Testing

Test on multiple OS and .NET versions:

```yaml
jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        dotnet: ['8.0.x', '9.0.x']
    runs-on: ${{ matrix.os }}

    steps:
    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: ${{ matrix.dotnet }}
```

## Best Practices

1. **Version tags**: Use semantic versioning (`v1.0.0`, `v1.0.1`, etc.)
2. **Branch protection**: Require build to pass before merging PRs
3. **Dependabot**: Enable to keep dependencies updated
4. **Caching**: Add NuGet caching to speed up builds
5. **Test artifacts**: Always upload test results for debugging

## Troubleshooting

### Build fails with "nlc not found"

The PATH might not be set correctly. Add this after installing the tool:

```yaml
- name: Add tools to PATH
  run: echo "$HOME/.dotnet/tools" >> $GITHUB_PATH
```

### NuGet push fails

Check that:
1. `NUGET_API_KEY` secret is set correctly
2. Package version doesn't already exist on NuGet.org
3. You have permission to push to that package ID

### Tests fail in CI but pass locally

Common causes:
- Different .NET SDK versions
- Environment-specific code (file paths, etc.)
- Missing dependencies in CI environment

Fix by ensuring consistency between local and CI environments.
