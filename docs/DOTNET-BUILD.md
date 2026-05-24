# Using N# with `nlc` and `dotnet build`

The primary N# workflow goes through `nlc`: `project.yml` holds N# settings, and `nlc build`/`nlc run` compile directly through the native IL backend without generating MSBuild project files. Direct `dotnet build` remains supported for SDK interop, CI experiments, and host tooling that requires a `.csproj`.

## Recommended Workflow

For local repo development, set up the full local toolchain once:

```bash
./scripts/setup-local.sh
```

This installs the repo-built `nlc` and `nsharp-lsp` tools from the local feed, installs templates, and makes `~/.dotnet/tools` available to future shells. Then create a project through the N# CLI:

```bash
nlc new MyApp
cd MyApp
nlc build
nlc run
```

Fresh `nlc new` projects are `.csproj`-free. If you need to exercise direct SDK/MSBuild behavior, create a minimal project manually:

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

Replace `PATH_TO_REPO` with the absolute path to this repository, or use `nlc new MyApp` for the normal csproj-free project path after running `./scripts/setup-local.sh`.

## Build, Run, and Test

Use the N# CLI for the normal project workflow:

```bash
nlc build
nlc run
nlc test
```

For direct SDK/MSBuild validation against a minimal `.csproj`:

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

## Why `nlc` Is The Preferred Path

- It is the N# product surface: `nlc check`, `nlc query`, `nlc fix`, formatting, tests, and package commands share one workflow.
- Fresh projects stay `.csproj`-free; N# configuration lives in `project.yml`.
- Direct `dotnet build`, `dotnet run`, and `dotnet test` still work when a host tool needs SDK-level entry points, but that path is compatibility rather than the core `nlc` build path.

Do not add project settings to a hand-authored `.csproj`; fix the SDK/project.yml path instead.

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
