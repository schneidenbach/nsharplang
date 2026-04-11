# Using N# with `dotnet build`

The primary N# workflow is an MSBuild SDK project: `project.yml` holds N# settings, a minimal `.csproj` opts into `NSharpLang.Sdk`, and the standard `dotnet` commands do the rest.

## Recommended Workflow

For local repo development, set up the SDK and templates once:

```bash
./scripts/setup-local.sh
```

Then create a project:

```bash
mkdir MyApp
cd MyApp
```

`project.yml`
```yaml
name: MyApp
version: 1.0.0
entry: Program.nl
outputType: exe
targetFramework: net10.0
```

`MyApp.csproj`
```xml
<Project Sdk="NSharpLang.Sdk" />
```

`Program.nl`
```n#
func main() {
    print "Hello from N#!"
}
```

For local development against this repo, add:

`global.json`
```json
{
  "sdk": {
    "version": "10.0.100"
  },
  "msbuild-sdks": {
    "NSharpLang.Sdk": "0.1.0"
  }
}
```

`NuGet.config`
```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="local" value="PATH_TO_REPO/artifacts/nuget" />
  </packageSources>
</configuration>
```

Replace `PATH_TO_REPO` with the absolute path to this repository, or generate a working project with `dotnet new nsharp-console` after running `./scripts/setup-local.sh`.

## Build, Run, and Test

```bash
dotnet build
dotnet run
dotnet test
```

Expected output:

```text
Hello from N#!
```

## What the SDK Does

1. MSBuild loads `NSharpLang.Sdk` from `global.json`.
2. The SDK reads `project.yml`.
3. It discovers `.nl` files automatically, excluding `.tests.nl` from the main build.
4. The compiler emits the project assembly directly via the IL backend during the build.
5. MSBuild continues with the normal .NET pipeline using the emitted assembly, references, and runtime assets.

## Why This Is the Preferred Path

- Minimal `.csproj`: the N# configuration lives in `project.yml`.
- Standard commands: `dotnet build`, `dotnet run`, and `dotnet test` work as expected.
- Better project ergonomics: multi-file projects, solutions, CI, and IDEs all fit the normal .NET model.
- Fewer moving parts: no temporary project generation is required for the common case.

The direct `nlc` workflow is still useful for single-file experiments and compiler debugging, but it is not the main project story.

## Relevant Source Layout

```text
src/
├── NSharpLang.Build.Tasks/       # MSBuild task implementation
│   ├── EmitIlAssembly.cs
│   └── NSharpLang.Build.targets
└── NSharpLang.Sdk/               # MSBuild SDK package
    ├── Sdk/
    │   ├── Sdk.props
    │   └── Sdk.targets
    └── NSharpLang.Sdk.csproj
```

## See Also

- [Quick Start](QUICK-START.md)
- [Templates](../templates/README.md)
- [Repository README](../README.md)
