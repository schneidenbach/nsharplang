# Microsoft.NET.Sdk.NSharp

MSBuild SDK for N# language projects.

## Installation

This SDK is automatically referenced when you use N# templates or create a project with the N# SDK reference.

## Usage

### Create a new project

Create a `project.yml` file:

```yaml
name: MyApp
version: 1.0.0
entry: Program.nl
outputType: exe
targetFramework: net9.0
```

Create a minimal `.csproj` file to reference the SDK:

```xml
<Project Sdk="Microsoft.NET.Sdk.NSharp">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>
</Project>
```

Or use the dotnet new template:

```bash
dotnet new nsharp-console -o MyApp
```

### Build your project

```bash
dotnet build
dotnet run
```

The SDK will automatically:
- Detect and compile all `.nl` files
- Read configuration from `project.yml`
- Generate C# code in the intermediate output directory
- Compile to .NET assemblies

## Features

- Automatic detection of N# source files (`.nl`)
- Integration with `dotnet build`, `dotnet run`, `dotnet test`
- Support for project.yml configuration
- Incremental builds
- Full MSBuild integration

## Learn More

- [N# Documentation](https://github.com/nsharp-lang/nsharp)
- [Language Guide](https://github.com/nsharp-lang/nsharp/blob/main/DESIGN.md)
