# NSharpLang.Templates

Project templates for N# language.

## Installation

```bash
dotnet new install NSharpLang.Templates
```

## Available Templates

### Console Application

Creates a simple N# console application.

```bash
dotnet new nsharp-console -o MyApp
cd MyApp
nlc build
nlc run
```

**Template short name:** `nsharp-console`

**What's included:**
- `Program.nl` - Entry point with Hello World
- `project.yml` - Project configuration
- `NuGet.config` - Package source configuration
- `global.json` - SDK version pinning

### Web API Application

Creates a minimal ASP.NET Core N# web API.

```bash
dotnet new nsharp-webapi -o MyApi
cd MyApi
nlc build
nlc run
```

**Template short name:** `nsharp-webapi`

**What's included:**
- `Program.nl` - API startup and route setup
- `Controllers/WeatherController.nl` - Sample controller
- `project.yml` - Project configuration with web SDK settings
- `NuGet.config` - Package source configuration
- `global.json` - SDK version pinning

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
