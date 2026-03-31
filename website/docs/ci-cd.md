---
sidebar_label: CI/CD
title: CI/CD
---

# CI/CD for N# Projects

This guide shows you how to set up continuous integration and deployment for your N# projects.

## Table of Contents

- [Quick Start](#quick-start)
- [GitHub Actions](#github-actions)
- [Azure Pipelines](#azure-pipelines)
- [Docker](#docker)
- [Examples](#examples)
- [Best Practices](#best-practices)

## Quick Start

N# projects work seamlessly with standard .NET CI/CD tools. Here's the fastest way to get started:

### GitHub Actions (Recommended)

1. Copy workflow templates:
   ```bash
   mkdir -p .github/workflows
   cp ci/templates/github-actions/build.yml .github/workflows/
   ```

2. Push to GitHub - CI runs automatically!

### Azure Pipelines

1. Copy pipeline template:
   ```bash
   cp ci/templates/azure-pipelines/azure-pipelines.yml .
   ```

2. Create a new pipeline in Azure DevOps pointing to this file.

### Docker

1. Copy Dockerfile:
   ```bash
   cp ci/templates/docker/Dockerfile.webapi Dockerfile
   ```

2. Build and run:
   ```bash
   docker build -t myapp .
   docker run -p 8080:8080 myapp
   ```

## GitHub Actions

GitHub Actions is our recommended CI/CD platform for N# projects.

### Basic Build Workflow

Create `.github/workflows/build.yml`:

```yaml
name: Build and Test

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '9.0.x'

    - name: Restore dependencies
      run: dotnet restore

    - name: Build
      run: dotnet build --no-restore

    - name: Test
      run: dotnet test --no-build --verbosity normal
```

### Release Workflow

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '9.0.x'

    - name: Restore and Build
      run: |
        dotnet restore
        dotnet build -c Release --no-restore

    - name: Test
      run: dotnet test -c Release --no-build

    - name: Pack
      run: dotnet pack -c Release --no-build -o ./artifacts

    - name: Publish to NuGet
      run: dotnet nuget push ./artifacts/*.nupkg -k ${{ secrets.NUGET_API_KEY }} -s https://api.nuget.org/v3/index.json --skip-duplicate

    - name: Create GitHub Release
      uses: softprops/action-gh-release@v1
      with:
        files: ./artifacts/*.nupkg
        generate_release_notes: true
```

**Required Secrets:**
- `NUGET_API_KEY` - Your NuGet.org API key

### Code Quality Checks

#### Format Check

Create `.github/workflows/format-check.yml`:

```yaml
name: Format Check

on:
  pull_request:
    branches: [ main ]

jobs:
  format:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '9.0.x'

    - name: Install N# CLI
      run: dotnet tool install -g NSharpLang.Cli

    - name: Add .NET tools to PATH
      run: echo "$HOME/.dotnet/tools" >> $GITHUB_PATH

    - name: Check formatting
      run: nlc format --verify-no-changes
```

#### Linting

Create `.github/workflows/lint.yml`:

```yaml
name: Lint

on:
  pull_request:
    branches: [ main ]

jobs:
  lint:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '9.0.x'

    - name: Install N# CLI
      run: dotnet tool install -g NSharpLang.Cli

    - name: Add .NET tools to PATH
      run: echo "$HOME/.dotnet/tools" >> $GITHUB_PATH

    - name: Run linter
      run: nlc lint
```

### Caching

Speed up builds with NuGet caching:

```yaml
- name: Cache NuGet packages
  uses: actions/cache@v3
  with:
    path: ~/.nuget/packages
    key: ${{ runner.os }}-nuget-${{ hashFiles('**/project.yml') }}
    restore-keys: |
      ${{ runner.os }}-nuget-
```

### Matrix Testing

Test on multiple platforms:

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
    # ... rest of steps
```

## Azure Pipelines

### Complete Pipeline

Create `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
    - main
    - develop
  tags:
    include:
    - v*

pool:
  vmImage: 'ubuntu-latest'

variables:
  buildConfiguration: 'Release'

stages:
- stage: Build
  displayName: 'Build and Test'
  jobs:
  - job: Build
    steps:
    - task: UseDotNet@2
      displayName: 'Install .NET SDK'
      inputs:
        version: '9.0.x'

    - task: Cache@2
      displayName: 'Cache NuGet packages'
      inputs:
        key: 'nuget | "$(Agent.OS)" | **/project.yml'
        path: $(Pipeline.Workspace)/.nuget/packages

    - script: dotnet restore
      displayName: 'Restore'

    - script: dotnet build --configuration $(buildConfiguration) --no-restore
      displayName: 'Build'

    - script: dotnet test --configuration $(buildConfiguration) --no-build --logger trx
      displayName: 'Test'

    - task: PublishTestResults@2
      condition: succeededOrFailed()
      inputs:
        testResultsFormat: 'VSTest'
        testResultsFiles: '**/*.trx'

- stage: Lint
  displayName: 'Code Quality'
  dependsOn: []
  jobs:
  - job: Lint
    steps:
    - task: UseDotNet@2
      inputs:
        version: '9.0.x'

    - script: |
        dotnet tool install -g NSharpLang.Cli
        export PATH="$PATH:$HOME/.dotnet/tools"
        nlc lint
      displayName: 'Run linter'

  - job: Format
    steps:
    - task: UseDotNet@2
      inputs:
        version: '9.0.x'

    - script: |
        dotnet tool install -g NSharpLang.Cli
        export PATH="$PATH:$HOME/.dotnet/tools"
        nlc format --verify-no-changes
      displayName: 'Check formatting'
```

## Docker

### SDK Image (Development)

Use this for building and development:

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:9.0

RUN dotnet tool install -g NSharpLang.Cli && \
    dotnet tool install -g NSharpLang.LanguageServer

ENV PATH="${PATH}:/root/.dotnet/tools"

WORKDIR /app
COPY . .

RUN dotnet restore && dotnet build

ENTRYPOINT ["dotnet", "run"]
```

Build and run:

```bash
docker build -t myapp-dev -f ci/templates/docker/Dockerfile.sdk .
docker run -it --rm myapp-dev
```

### Runtime Image (Production)

Multi-stage build for smaller images:

```dockerfile
# Build stage
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build

WORKDIR /app
COPY *.csproj project.yml ./
RUN dotnet restore

COPY . ./
RUN dotnet publish -c Release -o out

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:9.0

WORKDIR /app
COPY --from=build /app/out .

# Security: non-root user
RUN groupadd -r appuser && useradd -r -g appuser appuser
RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 8080
ENTRYPOINT ["dotnet", "YourApp.dll"]
```

Build and run:

```bash
docker build -t myapp .
docker run -p 8080:8080 myapp
```

### Docker Compose

For local development with dependencies:

```yaml
version: '3.8'

services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
      - ConnectionStrings__Database=Server=db;Database=myapp
    depends_on:
      - db

  db:
    image: mcr.microsoft.com/mssql/server:2022-latest
    environment:
      - ACCEPT_EULA=Y
      - SA_PASSWORD=YourStrong@Password
    ports:
      - "1433:1433"
```

Run with:

```bash
docker-compose up
```

### GitHub Actions Docker Workflow

Create `.github/workflows/docker.yml`:

```yaml
name: Docker

on:
  push:
    branches: [ main ]
    tags: [ 'v*' ]

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Log in to Docker Hub
      uses: docker/login-action@v3
      with:
        username: ${{ secrets.DOCKER_USERNAME }}
        password: ${{ secrets.DOCKER_PASSWORD }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ github.repository }}
        tags: |
          type=ref,event=branch
          type=semver,pattern={{version}}
          type=sha

    - name: Build and push
      uses: docker/build-push-action@v5
      with:
        context: .
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
```

## Examples

See the `ci/examples/` directory for complete working examples:

### Console App
Location: `ci/examples/console-app/`

Features:
- Build and test on every push
- Automated NuGet publishing on version tags
- Format and lint checks on PRs

[View Console App Example →](https://github.com/schneidenbach/nsharplang/tree/main/ci/examples/console-app)

### Web API
Location: `ci/examples/web-api/`

Features:
- Docker image building and publishing
- Deployment to cloud platforms
- Health checks and monitoring

[View Web API Example →](https://github.com/schneidenbach/nsharplang/tree/main/ci/examples/web-api)

### Library
Location: `ci/examples/library/`

Features:
- Multi-targeting multiple .NET versions
- Pre-release and stable versions
- Symbol package publishing
- Documentation generation

[View Library Example →](https://github.com/schneidenbach/nsharplang/tree/main/ci/examples/library)

## Best Practices

### 1. Version Tags

Use semantic versioning for releases:

```bash
git tag v1.0.0
git push origin v1.0.0
```

### 2. Branch Protection

Require CI to pass before merging:

1. Go to repository Settings → Branches
2. Add rule for `main` branch
3. Enable "Require status checks to pass"
4. Select your CI workflows

### 3. Secrets Management

Never commit secrets! Use CI/CD secrets:

- **GitHub Actions**: Repository Settings → Secrets and variables → Actions
- **Azure Pipelines**: Library → Variable groups

Common secrets:
- `NUGET_API_KEY` - For publishing packages
- `DOCKER_USERNAME` / `DOCKER_PASSWORD` - For Docker Hub
- `AZURE_CREDENTIALS` - For Azure deployment

### 4. Caching

Always cache NuGet packages to speed up builds:

```yaml
- uses: actions/cache@v3
  with:
    path: ~/.nuget/packages
    key: ${{ runner.os }}-nuget-${{ hashFiles('**/project.yml') }}
```

### 5. Fail Fast

Run fast checks (linting, formatting) before expensive builds:

```yaml
stages:
  - lint    # Fast (30 seconds)
  - build   # Slower (2 minutes)
  - test    # Slowest (5 minutes)
```

### 6. Parallel Jobs

Run independent jobs in parallel:

```yaml
jobs:
  lint:     # Runs in parallel
  format:   # Runs in parallel
  build:    # Runs in parallel
```

### 7. Test Coverage

Track code coverage over time:

```yaml
- name: Test with coverage
  run: dotnet test --collect:"XPlat Code Coverage"

- name: Upload to Codecov
  uses: codecov/codecov-action@v3
```

### 8. Release Automation

Automate the entire release process:

1. Update version in `project.yml`
2. Update `CHANGELOG.md`
3. Create git tag
4. CI automatically builds, tests, and publishes

### 9. Security Scanning

Add security checks:

```yaml
- name: Run security audit
  run: dotnet list package --vulnerable
```

### 10. Documentation

Keep CI/CD documentation up to date:

- Document required secrets
- Explain workflow triggers
- Provide troubleshooting tips

## Troubleshooting

### "nlc not found" Error

The .NET tools might not be in PATH. Add this step:

```yaml
- name: Add tools to PATH
  run: echo "$HOME/.dotnet/tools" >> $GITHUB_PATH
```

### NuGet Push Fails

Common issues:
- Package version already exists (use `--skip-duplicate`)
- Invalid API key (check secret configuration)
- Package validation errors (check package metadata)

### Docker Build Fails

Check:
- All necessary files are copied before build
- .dockerignore isn't excluding needed files
- N# CLI is properly installed in the build stage

### Tests Fail in CI but Pass Locally

Usually caused by:
- Different .NET SDK versions
- Missing environment variables
- File path differences (Windows vs Linux)

Ensure CI environment matches local:

```yaml
- name: Setup .NET
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: '9.0.x'  # Match your local version
```

## Next Steps

- [View complete console app example](https://github.com/schneidenbach/nsharplang/tree/main/ci/examples/console-app)
- [View complete web API example](https://github.com/schneidenbach/nsharplang/tree/main/ci/examples/web-api)
- [View complete library example](https://github.com/schneidenbach/nsharplang/tree/main/ci/examples/library)
- [Learn about formatting](./cli-reference.md)
- [Learn about linting](./cli-reference.md)

## Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Azure Pipelines Documentation](https://docs.microsoft.com/en-us/azure/devops/pipelines/)
- [Docker Documentation](https://docs.docker.com/)
- [NuGet Publishing Guide](https://docs.microsoft.com/en-us/nuget/nuget-org/publish-a-package)
