# Task 046: CI/CD Templates

**Status:** In Progress
**Priority:** P1-High
**Effort:** Small (8-10 hours)

## Goal

Provide ready-to-use CI/CD templates that make it trivial for N# projects to set up automated builds, tests, and deployments.

## Philosophy

> "Make the right thing easy" - Developers shouldn't need to figure out CI/CD from scratch. Provide templates that work out of the box.

## Deliverables

### 1. GitHub Actions Workflows

Create `.github/workflows/` templates:

#### a. `build.yml` - Basic build and test
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
        dotnet-version: '10.0.x'

    - name: Install N# CLI
      run: dotnet tool install -g nlc

    - name: Restore dependencies
      run: dotnet restore

    - name: Build
      run: dotnet build --no-restore

    - name: Test
      run: dotnet test --no-build --verbosity normal
```

#### b. `release.yml` - Automated releases
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
        dotnet-version: '10.0.x'

    - name: Install N# CLI
      run: dotnet tool install -g nlc

    - name: Build
      run: dotnet build -c Release

    - name: Pack
      run: dotnet pack -c Release

    - name: Publish to NuGet
      run: dotnet nuget push **/*.nupkg -k ${{ secrets.NUGET_API_KEY }} -s https://api.nuget.org/v3/index.json
```

#### c. `format-check.yml` - Ensure code is formatted
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
        dotnet-version: '10.0.x'

    - name: Install N# CLI
      run: dotnet tool install -g nlc

    - name: Check formatting
      run: nlc format --verify-no-changes
```

#### d. `lint.yml` - Run linter on PRs
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
        dotnet-version: '10.0.x'

    - name: Install N# CLI
      run: dotnet tool install -g nlc

    - name: Run linter
      run: nlc lint
```

### 2. Azure Pipelines YAML

Create `azure-pipelines.yml`:

```yaml
trigger:
  branches:
    include:
    - main
    - develop

pool:
  vmImage: 'ubuntu-latest'

variables:
  buildConfiguration: 'Release'

steps:
- task: UseDotNet@2
  displayName: 'Install .NET SDK'
  inputs:
    version: '10.0.x'

- script: dotnet tool install -g nlc
  displayName: 'Install N# CLI'

- script: dotnet restore
  displayName: 'Restore dependencies'

- script: dotnet build --configuration $(buildConfiguration)
  displayName: 'Build'

- script: dotnet test --configuration $(buildConfiguration) --no-build --logger trx
  displayName: 'Test'

- task: PublishTestResults@2
  inputs:
    testResultsFormat: 'VSTest'
    testResultsFiles: '**/*.trx'
```

### 3. Docker Images

Create two Dockerfile templates:

#### a. `Dockerfile.sdk` - For building
```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0

# Install N# CLI
RUN dotnet tool install -g nlc
ENV PATH="${PATH}:/root/.dotnet/tools"

# Install N# templates
RUN dotnet new install NSharp.Templates

WORKDIR /app

# Copy project files
COPY . .

# Build
RUN dotnet restore
RUN dotnet build

ENTRYPOINT ["dotnet", "run"]
```

#### b. `Dockerfile.runtime` - For running
```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build-env

# Install N# CLI
RUN dotnet tool install -g nlc
ENV PATH="${PATH}:/root/.dotnet/tools"

WORKDIR /app

# Copy csproj and restore dependencies
COPY *.csproj ./
COPY project.yml ./
RUN dotnet restore

# Copy everything else and build
COPY . ./
RUN dotnet publish -c Release -o out

# Build runtime image
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build-env /app/out .

ENTRYPOINT ["dotnet", "YourApp.dll"]
```

### 4. Example Configurations

Create a `ci-examples/` directory with real-world examples:

#### a. `ci-examples/console-app/`
- Complete GitHub Actions setup for a console app
- Includes versioning, changelog generation
- Automated NuGet publishing

#### b. `ci-examples/web-api/`
- Complete CI/CD pipeline for ASP.NET Core API
- Docker image building and pushing to registry
- Automated deployment to staging/production

#### c. `ci-examples/library/`
- NuGet package publishing pipeline
- Semantic versioning
- Release notes generation

### 5. Documentation

Create `docs/guide/ci-cd.md`:

```markdown
# CI/CD for N# Projects

## Quick Start

### GitHub Actions

Copy the workflows from `ci-templates/github-actions/` to your project:

```bash
mkdir -p .github/workflows
cp ci-templates/github-actions/*.yml .github/workflows/
```

### Azure Pipelines

Copy the pipeline YAML:

```bash
cp ci-templates/azure-pipelines.yml azure-pipelines.yml
```

### Docker

Choose the appropriate Dockerfile:

```bash
# For SDK image (build + run)
cp ci-templates/Dockerfile.sdk Dockerfile

# For runtime image (multi-stage, smaller)
cp ci-templates/Dockerfile.runtime Dockerfile
```

## Configuration

### GitHub Actions Secrets

Add these secrets to your repository:

- `NUGET_API_KEY` - For publishing packages
- `DOCKER_USERNAME` - For Docker Hub
- `DOCKER_PASSWORD` - For Docker Hub

### Azure Pipelines Variables

Configure these pipeline variables:

- `NuGetApiKey` - For publishing packages
- `DockerRegistry` - Your Docker registry URL

## Examples

See `ci-examples/` for complete working examples:

- `console-app/` - Console application CI/CD
- `web-api/` - Web API with Docker deployment
- `library/` - Library publishing to NuGet
```

## Implementation Steps

1. Create `ci-templates/` directory structure
2. Add GitHub Actions workflow templates
3. Add Azure Pipelines YAML template
4. Create Dockerfiles (SDK and runtime)
5. Create example projects in `ci-examples/`
6. Write CI/CD documentation
7. Test each template with a real project
8. Update main README with CI/CD section

## Success Criteria

- [ ] GitHub Actions workflows work out of the box
- [ ] Azure Pipelines YAML works without modification
- [ ] Docker images build successfully
- [ ] All example projects have working CI/CD
- [ ] Documentation is clear and complete
- [ ] Templates include best practices (caching, etc.)

## Testing

1. Create a new N# console app
2. Copy GitHub Actions workflow
3. Push to GitHub
4. Verify build passes
5. Repeat for web API and library

## Future Enhancements

- GitLab CI templates
- CircleCI configuration
- Jenkins pipeline
- Travis CI support
- Automated security scanning (Dependabot, Snyk)
- Code coverage reporting (Codecov, Coveralls)
- Performance benchmarking in CI

## Notes

- Use GitHub Actions cache for NuGet packages
- Pin .NET SDK versions for reproducibility
- Include formatting and linting checks in PR workflows
- Separate build and release workflows
- Use matrix builds for multi-targeting

---

**Estimated Effort:** 8-10 hours
**Priority:** P1-High
**Depends on:** None (all tooling is ready)
