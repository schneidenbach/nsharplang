# NSharp.Templates

Project templates for N# language.

## Installation

```bash
dotnet new install NSharp.Templates
```

## Available Templates

### Console Application

Creates a simple N# console application.

```bash
dotnet new nsharp-console -o MyApp
cd MyApp
dotnet build
dotnet run
```

**Template short name:** `nsharp-console`

**What's included:**
- `Program.nl` - Entry point with Hello World
- `project.yml` - Project configuration
- `.csproj` - MSBuild project file with SDK reference

## Uninstall

```bash
dotnet new uninstall NSharp.Templates
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
