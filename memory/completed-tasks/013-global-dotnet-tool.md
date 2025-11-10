# Task 013: Global .NET Tool Configuration ✅ COMPLETED

**Priority:** High (Developer experience - makes tool installable)
**Dependencies:** None
**Estimated Effort:** Small (2-3 hours)
**Completed:** v1.28

## Goal
Configure CLI as a global .NET tool so users can install with `dotnet tool install -g nlc` and use `nlc` command globally.

## Usage
```bash
# Install globally
dotnet tool install -g nlc

# Use anywhere
nlc build
nlc run Program.nl
nlc new MyProject
nlc test

# Update
dotnet tool update -g nlc

# Uninstall
dotnet tool uninstall -g nlc
```

## Implementation Steps

### 1. Configure Cli.csproj
- Add tool packaging properties:
  ```xml
  <Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
      <OutputType>Exe</OutputType>
      <TargetFramework>net8.0</TargetFramework>

      <!-- Tool Configuration -->
      <PackAsTool>true</PackAsTool>
      <ToolCommandName>nlc</ToolCommandName>
      <PackageId>nlc</PackageId>

      <!-- Package Metadata -->
      <Version>0.1.0</Version>
      <Authors>N# Team</Authors>
      <Description>N# (NewLang Sharp) - A tight, pragmatic language for .NET</Description>
      <PackageProjectUrl>https://github.com/yourorg/newclilang</PackageProjectUrl>
      <RepositoryUrl>https://github.com/yourorg/newclilang</RepositoryUrl>
      <PackageLicenseExpression>MIT</PackageLicenseExpression>
      <PackageTags>dotnet;language;compiler;nlang</PackageTags>
    </PropertyGroup>
  </Project>
  ```

### 2. Local Testing
- Create package:
  ```bash
  cd src/Cli
  dotnet pack -c Release -o ../../nupkg
  ```
- Install locally:
  ```bash
  dotnet tool install --global --add-source ./nupkg nlc
  ```
- Test:
  ```bash
  nlc --help
  nlc build examples/hello.nl
  ```

### 3. Version Management
- Update version in Cli.csproj for each release
- Follow semantic versioning: MAJOR.MINOR.PATCH
- Document version in CHANGELOG.md

### 4. README Documentation
- Update README.md with installation instructions:
  ```markdown
  ## Installation

  Install as a global .NET tool:
  ```bash
  dotnet tool install -g nlc
  ```

  Verify installation:
  ```bash
  nlc --version
  ```

  ## Usage

  Build a project:
  ```bash
  nlc build
  ```

  Run a file:
  ```bash
  nlc run Program.nl
  ```
  ```

### 5. Help Command
- Ensure `nlc --help` shows clear usage info
- Update Program.cs to display:
  ```
  N# (NewLang Sharp) Compiler v0.1.0

  Usage:
    nlc build [<file>]           Build project or single file
    nlc run <file>              Build and run file
    nlc transpile <file>        Transpile to C# (debug)
    nlc new <name>              Create new project
    nlc restore                 Restore dependencies
    nlc test                    Run tests
    nlc --version               Show version
    nlc --help                  Show this help

  Examples:
    nlc build                   # Build project in current directory
    nlc run Program.nl          # Run a single file
    nlc new MyApp               # Create new project
  ```

### 6. Version Command
- Add `--version` flag:
  ```csharp
  if (args.Contains("--version")) {
      Console.WriteLine("N# Compiler v0.1.0");
      return 0;
  }
  ```

### 7. Publishing (Future)
- Create NuGet account
- Publish to nuget.org:
  ```bash
  dotnet nuget push nupkg/nlc.0.1.0.nupkg --api-key <key> --source https://api.nuget.org/v3/index.json
  ```

### 8. Uninstall Instructions
- Document how to uninstall:
  ```bash
  dotnet tool uninstall -g nlc
  ```

### 9. Tests
- Manual testing:
  - Pack and install locally
  - Run all commands globally
  - Verify --help and --version
  - Test in different directories
- Verify package metadata is correct

## Success Criteria
- [x] `dotnet pack` creates valid tool package
- [x] `dotnet tool install -g nlc` works
- [x] `nlc` command available globally
- [x] `nlc --help` shows usage
- [x] `nlc --version` shows version
- [x] All commands work when installed globally
- [x] Uninstall works cleanly

## Notes
- Makes N# feel like a real, professional tool
- Easy distribution and updates
- Standard .NET tooling workflow
- Can publish to NuGet.org when ready
- Version in Cli.csproj is source of truth
