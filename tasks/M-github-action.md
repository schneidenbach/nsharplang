# Task M: GitHub Action — `setup-nsharp` for CI/CD

## Context

Users need to build N# projects in CI. Right now there's no easy way. Create a GitHub Action that installs the N# toolchain.

## What to build

A composite GitHub Action at `actions/setup-nsharp/action.yml` that:

1. Installs .NET SDK (if not present)
2. Installs the N# CLI (`nlc`) as a global dotnet tool
3. Installs N# templates
4. Optionally installs the N# SDK NuGet package to a local feed
5. Adds `nlc` to PATH

### Usage (what users write in their workflows):

```yaml
name: Build
on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: schneidenbach/nsharplang/actions/setup-nsharp@main
        with:
          version: 'latest'  # or specific version like '1.0.0'

      - name: Build
        run: dotnet build

      - name: Test
        run: nlc test

      - name: Check
        run: nlc check
```

### Action inputs:

```yaml
inputs:
  version:
    description: 'N# toolchain version (default: latest)'
    required: false
    default: 'latest'
  dotnet-version:
    description: '.NET SDK version (default: 9.0.x)'
    required: false
    default: '9.0.x'
  include-templates:
    description: 'Install N# project templates (default: true)'
    required: false
    default: 'true'
```

### Implementation:

Create `actions/setup-nsharp/action.yml` as a composite action:

```yaml
name: 'Setup N#'
description: 'Install the N# toolchain for building .nl projects'
inputs:
  # ... as above
runs:
  using: 'composite'
  steps:
    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: ${{ inputs.dotnet-version }}

    - name: Install N# CLI
      shell: bash
      run: |
        if [ "${{ inputs.version }}" = "latest" ]; then
          dotnet tool install -g NSharpLang.Cli
        else
          dotnet tool install -g NSharpLang.Cli --version ${{ inputs.version }}
        fi

    - name: Install N# Templates
      if: inputs.include-templates == 'true'
      shell: bash
      run: dotnet new install NSharpLang.Templates

    - name: Verify installation
      shell: bash
      run: nlc --help
```

### Also update the project's own CI

Update `.github/workflows/build.yml` to use the action (dogfooding):

```yaml
- uses: ./actions/setup-nsharp
  with:
    version: 'latest'
```

### README

Create `actions/setup-nsharp/README.md` with:
- Usage example
- Input descriptions
- Badges
- Link to N# repo

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md

(For this task, "test" means: verify the action YAML is valid and the existing CI workflow still passes.)
