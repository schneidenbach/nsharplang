# CI/CD Setup

## GitHub Actions

Copy `.github/workflows/build.yml` to your repo:

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
        dotnet-version: '10.0.x'

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

### Adding a Build Badge

Add this to your README.md:

```markdown
[![Build](https://github.com/yourusername/yourrepo/actions/workflows/build.yml/badge.svg)](https://github.com/yourusername/yourrepo/actions/workflows/build.yml)
```

## Azure Pipelines

Create `azure-pipelines.yml` in your repo:

```yaml
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: UseDotNet@2
  inputs:
    version: '10.0.x'

- script: dotnet build
  displayName: 'Build'

- script: dotnet test
  displayName: 'Test'
```

## GitLab CI

Create `.gitlab-ci.yml` in your repo:

```yaml
image: mcr.microsoft.com/dotnet/sdk:10.0

stages:
  - build
  - test

build:
  stage: build
  script:
    - dotnet build

test:
  stage: test
  script:
    - dotnet test
```

## Local CI Testing

You can run the same commands locally:

```bash
dotnet restore
dotnet build --no-restore
dotnet test --no-build --verbosity normal
nsharp lint
```
