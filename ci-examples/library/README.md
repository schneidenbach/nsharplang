# Library CI/CD Example

This example shows how to set up CI/CD for a N# library published to NuGet.org.

## Structure

```
library/
├── .github/
│   └── workflows/
│       ├── build.yml         # Build and test on PRs
│       ├── release.yml       # Publish to NuGet on tags
│       └── prerelease.yml    # Publish pre-release versions
├── src/
│   └── MyLibrary.nl          # Library code
├── tests/
│   └── MyLibrary.Tests.nl    # Unit tests
├── project.yml               # N# project configuration
├── CHANGELOG.md              # Version history
└── README.md
```

## Quick Start

### 1. Configure project.yml

Set up your library metadata:

```yaml
name: MyAwesomeLibrary
version: 1.0.0
type: library
targetFramework: net9.0

# Package metadata
package:
  id: MyAwesomeLibrary
  version: 1.0.0
  authors: Your Name
  description: A brief description of your library
  projectUrl: https://github.com/yourusername/myawesomelibrary
  licenseUrl: https://github.com/yourusername/myawesomelibrary/blob/main/LICENSE
  tags: nsharp, library, awesome
  releaseNotes: Initial release

dependencies:
  - System.Text.Json: "9.0.0"
```

### 2. Copy Workflows

```bash
mkdir -p .github/workflows
cp ../../ci-templates/github-actions/build.yml .github/workflows/
cp ../../ci-templates/github-actions/release.yml .github/workflows/
```

### 3. Configure GitHub Secrets

Add to your repository settings:

- `NUGET_API_KEY` - Your NuGet.org API key

### 4. Version Management

We recommend using semantic versioning and git tags:

```bash
# Update version in project.yml
# Update CHANGELOG.md

git add .
git commit -m "Release v1.0.0"
git tag v1.0.0
git push origin main --tags
```

## Semantic Versioning

Use [Semantic Versioning](https://semver.org/):

- `1.0.0` - Major release (breaking changes)
- `1.1.0` - Minor release (new features, backward compatible)
- `1.0.1` - Patch release (bug fixes)
- `1.0.0-beta.1` - Pre-release version

## Automated Versioning

### Option 1: Manual in project.yml

Update `version` field manually before each release.

### Option 2: GitVersion

Install GitVersion to automatically determine version from git history:

Add `.github/workflows/versioning.yml`:

```yaml
name: Version

on:
  push:
    branches: [ main, develop ]

jobs:
  version:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4
      with:
        fetch-depth: 0

    - name: Install GitVersion
      uses: gittools/actions/gitversion/setup@v0.10.2
      with:
        versionSpec: '5.x'

    - name: Determine Version
      uses: gittools/actions/gitversion/execute@v0.10.2
      id: gitversion

    - name: Display Version
      run: |
        echo "Version: ${{ steps.gitversion.outputs.semVer }}"
        echo "NuGet Version: ${{ steps.gitversion.outputs.nuGetVersion }}"
```

## Pre-release Workflow

Create `.github/workflows/prerelease.yml`:

```yaml
name: Pre-release

on:
  push:
    branches: [ develop ]
    tags: [ 'v*-*' ]  # e.g., v1.0.0-beta.1

jobs:
  prerelease:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '9.0.x'

    - name: Install N# CLI
      run: dotnet tool install -g nlc

    - name: Restore dependencies
      run: dotnet restore

    - name: Build
      run: dotnet build -c Release --no-restore

    - name: Test
      run: dotnet test -c Release --no-build

    - name: Pack
      run: dotnet pack -c Release --no-build -o ./artifacts

    - name: Publish to NuGet (Pre-release)
      run: dotnet nuget push ./artifacts/*.nupkg -k ${{ secrets.NUGET_API_KEY }} -s https://api.nuget.org/v3/index.json --skip-duplicate
```

## Testing

### Unit Tests

Create tests in `tests/MyLibrary.Tests.nl`:

```nsharp
import Testing

test "Should return correct result"
    let result = MyLibrary.DoSomething("input")
    assert result == "expected"

test "Should handle null input"
    let result = MyLibrary.DoSomething(null)
    assert result == ""
```

### Test Coverage

Add coverage reporting to build workflow:

```yaml
- name: Test with coverage
  run: dotnet test --no-build --collect:"XPlat Code Coverage"

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v3
  with:
    token: ${{ secrets.CODECOV_TOKEN }}
    files: '**/coverage.cobertura.xml'
```

## Documentation

### XML Documentation Comments

Add documentation to your code:

```nsharp
/// Processes the input string and returns a result.
///
/// # Arguments
/// * `input` - The input string to process
///
/// # Returns
/// The processed string
///
/// # Examples
/// ```
/// let result = ProcessString("hello")
/// assert result == "HELLO"
/// ```
public func ProcessString(input: string) -> string
    return input.ToUpper()
```

### Generate API Docs

Enable XML documentation in project.yml:

```yaml
generateDocumentation: true
documentationFile: MyLibrary.xml
```

### DocFX Integration

Use DocFX to generate a documentation website:

```bash
dotnet tool install -g docfx
docfx init
docfx build
```

## README Badge Examples

Add badges to your README.md:

```markdown
# MyAwesomeLibrary

[![NuGet](https://img.shields.io/nuget/v/MyAwesomeLibrary.svg)](https://www.nuget.org/packages/MyAwesomeLibrary/)
[![Build](https://github.com/yourusername/myawesomelibrary/workflows/Build/badge.svg)](https://github.com/yourusername/myawesomelibrary/actions)
[![Coverage](https://codecov.io/gh/yourusername/myawesomelibrary/branch/main/graph/badge.svg)](https://codecov.io/gh/yourusername/myawesomelibrary)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
```

## Changelog

Maintain a CHANGELOG.md following [Keep a Changelog](https://keepachangelog.com/):

```markdown
# Changelog

## [1.0.0] - 2025-11-10

### Added
- Initial release
- Core functionality for X, Y, Z
- Full test coverage

### Fixed
- Bug in edge case handling

## [0.9.0-beta.1] - 2025-11-01

### Added
- Beta release for testing
```

## Multi-targeting

Support multiple .NET versions in project.yml:

```yaml
targetFrameworks:
  - net9.0
  - net8.0
  - netstandard2.1
```

## Signing

### Strong Name Signing

Add to project.yml:

```yaml
signing:
  keyFile: MyLibrary.snk
  publicSign: false
```

Generate key:

```bash
sn -k MyLibrary.snk
```

### Package Signing

Sign NuGet packages:

```bash
dotnet nuget sign MyLibrary.1.0.0.nupkg \
  --certificate-path MyCert.pfx \
  --certificate-password ${{ secrets.CERT_PASSWORD }} \
  --timestamper http://timestamp.digicert.com
```

## Best Practices

1. **Semantic Versioning**: Follow SemVer strictly
2. **Changelog**: Keep an up-to-date CHANGELOG.md
3. **Tests**: Maintain high test coverage (>80%)
4. **Documentation**: Document all public APIs
5. **Breaking Changes**: Clearly mark in release notes
6. **Dependencies**: Minimize and keep up-to-date
7. **Multi-targeting**: Support LTS .NET versions
8. **Symbols**: Publish symbol packages for debugging

## Publishing Checklist

Before publishing a new version:

- [ ] Update version in project.yml
- [ ] Update CHANGELOG.md
- [ ] Run all tests locally
- [ ] Update documentation
- [ ] Review breaking changes
- [ ] Test with sample consumer project
- [ ] Create git tag
- [ ] Push tag to trigger release

## Troubleshooting

### Package upload fails

- Verify NUGET_API_KEY is correct
- Check package ID isn't already taken
- Ensure version doesn't already exist

### Build fails in CI

- Check .NET SDK version matches
- Verify all dependencies are restored
- Test locally with same SDK version

### Symbol publishing fails

- Enable symbol package generation in project.yml
- Use correct symbol server URL
- Verify certificate for signing
