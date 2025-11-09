# Task 055: GitHub Actions Template

**Effort:** Small (3-4 hours)
**Depends:** Task 042
**Ships:** CI template for N# projects

## Goal

Create GitHub Actions workflow template.

## Deliverable

Workflow file that builds and tests N# projects.

## Implementation

Create `.github/workflows/build.yml`:

```yaml
name: Build

on:
  push:
    branches: [ main ]
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

    - name: Lint
      run: nsharp lint
      continue-on-error: true
```

**Documentation:**

Add `docs/ci-cd.md`:
```markdown
# CI/CD Setup

## GitHub Actions

Copy `.github/workflows/build.yml` to your repo.

## Azure Pipelines

```yaml
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: UseDotNet@2
  inputs:
    version: '9.0.x'

- script: dotnet build
  displayName: 'Build'

- script: dotnet test
  displayName: 'Test'
```

## Done When

- [ ] Workflow file created
- [ ] Works on sample project
- [ ] Documentation added
- [ ] Badge for README
