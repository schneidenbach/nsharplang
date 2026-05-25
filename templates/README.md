# NSharpLang.Templates

Project templates for N# language.

Canonical fresh-project policy: templates are csproj-free and `project.yml`-first. Neither `nlc new` nor `dotnet new nsharp-*` writes a user-authored `.csproj`. `nlc build`, `nlc run`, `nlc test`, and the VS Code N# tasks read `project.yml` directly and do not generate MSBuild project files. All project configuration belongs in `project.yml`.

The supported fresh-project workflow is `nlc build`, `nlc run`, and `nlc test`; the VS Code extension exposes those same commands as N# tasks and honors `nsharp.cli.path`.

Every quickstart block below is replayed by `scripts/replay-template-quickstarts.py` and by the template integration test. Keep the marked command blocks copy/pasteable and under five commands.

## Installation

Public users should install NSharpLang through the canonical installer, which installs the templates together with `nlc`, SDK restore support, language server, and VS Code tooling:

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash
```

Maintainers can still install this template package directly from a local feed while validating release artifacts, but that is not the public first-run path.

## Available Templates

### Console Application

Creates a simple N# console application.

<!-- quickstart:console -->
```bash
dotnet new nsharp-console -o MyApp
cd MyApp
nlc build
nlc run
```

Equivalent CLI scaffold:

```bash
nlc new MyApp --template console
```

**Template short name:** `nsharp-console`

**What's included:**
- `Program.nl` - Entry point with Hello World
- `project.yml` - Project configuration
- `NuGet.config` - Package source configuration
- `global.json` - SDK version pinning

Open the generated folder in VS Code and run the `nsharp: build`, `nsharp: run`, or `nsharp: test` tasks. F5/debugging is intentionally hidden until N# has a real debugger-backed workflow.

### Class Library

Creates a library project with a small `Calculator` type.

<!-- quickstart:library -->
```bash
dotnet new nsharp-library -o MyLib
cd MyLib
nlc build
```

Equivalent CLI scaffold:

```bash
nlc new MyLib --template library
```

**Template short name:** `nsharp-library`

**What's included:**
- `Calculator.nl` - Starter library type
- `project.yml` - Library configuration (`outputType: library`)
- `NuGet.config` - Package source configuration
- `global.json` - SDK version pinning

### Test Project

Creates a library-shaped project with `.tests.nl` examples ready for `nlc test`.

<!-- quickstart:test -->
```bash
dotnet new nsharp-test -o MyTests
cd MyTests
nlc build
nlc test
```

Equivalent CLI scaffold:

```bash
nlc new MyTests --template test
```

**Template short name:** `nsharp-test`

**What's included:**
- `Calculator.nl` - Starter code under test
- `Calculator.tests.nl` - xUnit-backed N# tests
- `project.yml` - Library/test configuration
- `NuGet.config` - Package source configuration
- `global.json` - SDK version pinning

### Web API Application

Creates a minimal ASP.NET Core N# web API.

<!-- quickstart:webapi -->
```bash
dotnet new nsharp-webapi -o MyApi
cd MyApi
nlc build
ASPNETCORE_URLS=http://127.0.0.1:5050 nlc run
```

Equivalent CLI scaffold:

```bash
nlc new MyApi --template webapi
```

**Template short name:** `nsharp-webapi`

**What's included:**
- `Program.nl` - API startup and route setup
- `Controllers/WeatherController.nl` - Sample controller
- `project.yml` - Project configuration with web SDK settings
- `NuGet.config` - Package source configuration
- `global.json` - SDK version pinning

Open the generated folder in VS Code and run the `nsharp: build`, `nsharp: run`, or `nsharp: test` tasks. F5/debugging is intentionally hidden until N# has a real debugger-backed workflow.

## Uninstall

```bash
dotnet new uninstall NSharpLang.Templates
```

## Template List

After installation, view all N# templates:

```bash
dotnet new list nsharp
```

## Learn More

- [N# Documentation](https://github.com/nsharp-lang/nsharp)
- [Language Guide](https://github.com/nsharp-lang/nsharp/blob/main/DESIGN.md)
- [Examples](https://github.com/nsharp-lang/nsharp/tree/main/examples)
