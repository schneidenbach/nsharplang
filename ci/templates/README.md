# N# CI/CD Templates

Ready-to-use CI/CD templates for N# projects.

## Contents

- **github-actions/** - GitHub Actions workflow templates
- **azure-pipelines/** - Azure Pipelines YAML templates
- **docker/** - Dockerfile templates and Docker Compose configurations

## Quick Start

### GitHub Actions

```bash
mkdir -p .github/workflows
cp github-actions/build.yml .github/workflows/
```

### Azure Pipelines

```bash
cp azure-pipelines/azure-pipelines.yml .
```

### Docker

```bash
cp docker/Dockerfile.webapi Dockerfile
cp docker/.dockerignore .
```

## GitHub Actions Templates

### build.yml
- Runs on push to main/develop and on PRs
- Builds and tests the project
- Uploads test results

### release.yml
- Triggers on version tags (v*)
- Builds, tests, packs, and publishes to NuGet
- Creates GitHub release

### format-check.yml
- Runs on PRs
- Ensures code is properly formatted
- Comments on PR if formatting issues found

### lint.yml
- Runs on PRs
- Checks code quality with N# linter
- Comments on PR if linting issues found

## Azure Pipelines Templates

### azure-pipelines.yml
Complete pipeline with:
- Build and test stage
- Code quality checks (lint + format)
- Publish to NuGet on tags

## Docker Templates

### Dockerfile.sdk
Full SDK image for development and building.
- Size: ~1.5GB
- Includes N# CLI and tools
- Good for CI/CD builds

### Dockerfile.runtime
Multi-stage production image.
- Final size: ~200MB
- Runtime only (no SDK)
- Good for deployments

### Dockerfile.webapi
Optimized for ASP.NET Core APIs.
- Multi-stage build
- Non-root user for security
- Health checks included
- Final size: ~200MB

### .dockerignore
Excludes unnecessary files from Docker builds.

### docker-compose.yml
Local development setup with:
- N# API service
- SQL Server database
- Redis cache

## Configuration

### Required Secrets

#### GitHub Actions
Set in: Repository Settings → Secrets and variables → Actions

- `NUGET_API_KEY` - Your NuGet.org API key
- `DOCKER_USERNAME` - Docker Hub username
- `DOCKER_PASSWORD` - Docker Hub password

#### Azure Pipelines
Set in: Azure DevOps → Pipelines → Library → Variable groups

- `NuGetApiKey` - Your NuGet.org API key
- `DockerUsername` - Docker Hub username
- `DockerPassword` - Docker Hub password

## Usage Examples

See the `ci-examples/` directory for complete working examples:

- **console-app/** - Console application CI/CD
- **web-api/** - Web API with Docker deployment
- **library/** - Library publishing to NuGet

## Customization

### Change .NET Version

Update the .NET SDK version in workflows:

```yaml
- name: Setup .NET
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '8.0.x'  # Change to desired version
```

### Add More Platforms

Test on multiple operating systems:

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, windows-latest, macos-latest]
runs-on: ${{ matrix.os }}
```

### Custom Build Configuration

Change build configuration:

```yaml
- name: Build
  run: dotnet build -c Debug  # or Release, or custom
```

## Documentation

Full documentation: [docs/guide/ci-cd.md](../docs/guide/ci-cd.md)

## Support

- [N# Documentation](../docs/README.md)
- [GitHub Issues](https://github.com/yourusername/nsharp/issues)
- [Examples](../ci-examples/)
