# Library CI/CD Example

This example shows how to set up CI/CD for an N# library published through the normal .NET packaging flow.

## Structure

```text
library/
├── .github/
│   └── workflows/
│       ├── build.yml
│       ├── release.yml
│       └── prerelease.yml
├── src/
│   └── MyLibrary.nl
├── tests/
│   └── MyLibrary.tests.nl
├── project.yml
├── MyLibrary.csproj
└── README.md
```

## Project Setup

### `project.yml`

Use `project.yml` for the N# build settings:

```yaml
name: MyAwesomeLibrary
version: 1.0.0
outputType: library
targetFramework: net9.0

dependencies:
  - package: System.Text.Json@9.0.0
```

### `MyLibrary.csproj`

Put NuGet package metadata in the `.csproj`, because `dotnet pack` reads package identity and publish metadata from MSBuild properties:

```xml
<Project Sdk="NSharpLang.Sdk">
  <PropertyGroup>
    <PackageId>MyAwesomeLibrary</PackageId>
    <Version>1.0.0</Version>
    <Authors>Your Name</Authors>
    <Description>A brief description of your library.</Description>
    <PackageReadmeFile>README.md</PackageReadmeFile>
  </PropertyGroup>

  <ItemGroup>
    <None Include="README.md" Pack="true" PackagePath="/" />
  </ItemGroup>
</Project>
```

## Copy Workflows

```bash
mkdir -p .github/workflows
cp ../../ci/templates/github-actions/build.yml .github/workflows/
cp ../../ci/templates/github-actions/release.yml .github/workflows/
```

If you want a pre-release lane, add your own `prerelease.yml` based on the same pattern: restore, build, test, pack, and push with a prerelease version.

## Testing

Create tests in `tests/MyLibrary.tests.nl`:

```n#
namespace MyLibrary

test "should return correct result" {
    result := MyLibrary.DoSomething("input")
    assert result == "expected"
}

test "should handle null input" {
    result := MyLibrary.DoSomething(null)
    assert result == ""
}
```

Run them locally with:

```bash
dotnet test
```

## Versioning

Use semantic versioning:

- `1.0.0` for a breaking release
- `1.1.0` for a backward-compatible feature release
- `1.0.1` for a patch release
- `1.0.0-beta.1` for a prerelease

Update the version in your `.csproj`, commit it, and tag the release:

```bash
git add .
git commit -m "Release v1.0.0"
git tag v1.0.0
git push origin main --tags
```

## Release Flow

The shipped `release.yml` expects:

1. `dotnet restore` to succeed using your configured SDK/package feeds
2. `dotnet build` and `dotnet test` to pass
3. `dotnet pack` to emit one or more `.nupkg` files
4. `NUGET_API_KEY` to be present in GitHub secrets

## Troubleshooting

### `dotnet pack` creates nothing useful

That usually means the `.csproj` is missing package metadata such as `PackageId` or `Version`.

### CI restores locally but fails in GitHub Actions

Ensure the repository includes the `global.json` and `NuGet.config` required to resolve `NSharpLang.Sdk`, or switch the project to consume published packages from NuGet.org.
