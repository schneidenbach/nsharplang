# Task 039: .NET CLI Integration - First-Class Language Support

**Priority:** Critical (Essential for .NET ecosystem integration)
**Dependencies:** None (can start immediately)
**Estimated Effort:** Large (20-30 hours)
**Status:** Not started

## Goal

Integrate N# completely into the .NET CLI toolchain, making it a first-class .NET language like C# or F#. Users should use `dotnet` commands, not a separate `nsharp` CLI.

## Vision

**Instead of:**
```bash
nsharp build Program.nl
nsharp run Program.nl
nsharp test
```

**We want:**
```bash
dotnet new nsharp-console -o MyApp
cd MyApp
dotnet build
dotnet run
dotnet test
```

**Just like C# and F#!**

## Background

.NET supports multiple languages through:
1. **MSBuild SDK** - Defines how to build projects
2. **Project files** (.csproj, .fsproj) - MSBuild understands
3. **dotnet templates** - `dotnet new` templates
4. **Build tasks** - Custom build logic via MSBuild tasks
5. **NuGet packaging** - Standard .NET distribution

N# should follow this same pattern with `.nlproj` files and an MSBuild SDK.

## Current State vs Target State

### Current (Separate CLI)
```
Project Structure:
  MyApp/
    Program.nl
    project.yml        ← Custom format

Commands:
  nsharp build         ← Custom CLI
  nsharp run
  nsharp test

Build Process:
  nsharp → Transpile to C# → Call dotnet build
```

### Target (.NET Integrated)
```
Project Structure:
  MyApp/
    MyApp.nlproj       ← MSBuild project file
    Program.nl

Commands:
  dotnet build         ← Standard .NET CLI
  dotnet run
  dotnet test

Build Process:
  dotnet build → MSBuild → N# SDK → Compile to IL/C#
```

## Implementation Plan

### Phase 1: MSBuild SDK (Week 1-2)

**Goal:** Create `Microsoft.NET.Sdk.NSharp` MSBuild SDK

**File:** `src/Sdk/Sdk.props`
```xml
<Project>
  <PropertyGroup>
    <!-- Default properties for N# projects -->
    <LanguageTargets>$(MSBuildToolsPath)\Microsoft.CSharp.targets</LanguageTargets>
    <DefaultLanguageSourceExtension>.nl</DefaultLanguageSourceExtension>
    <Language>N#</Language>
    <LangVersion>latest</LangVersion>
  </PropertyGroup>

  <!-- Import N# compiler task -->
  <Import Project="Sdk.targets" />
</Project>
```

**File:** `src/Sdk/Sdk.targets`
```xml
<Project>
  <UsingTask TaskName="NSharpCompile"
             AssemblyFile="$(MSBuildThisFileDirectory)../tools/NSharp.Build.Tasks.dll" />

  <Target Name="CoreCompile"
          DependsOnTargets="$(CoreCompileDependsOn)">

    <!-- Compile .nl files to C# or IL -->
    <NSharpCompile
      Sources="@(Compile)"
      References="@(ReferencePath)"
      OutputAssembly="@(IntermediateAssembly)"
      DefineConstants="$(DefineConstants)"
      TargetType="$(OutputType)" />
  </Target>
</Project>
```

**File:** `src/Sdk/NSharp.Build.Tasks.dll` (C# project)
```csharp
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

namespace NSharp.Build.Tasks
{
    public class NSharpCompile : Task
    {
        [Required]
        public ITaskItem[] Sources { get; set; }

        public ITaskItem[] References { get; set; }

        [Required]
        public ITaskItem OutputAssembly { get; set; }

        public override bool Execute()
        {
            // 1. Parse all .nl files
            // 2. Run analyzer
            // 3. Transpile to C# OR emit IL
            // 4. Compile C# with Roslyn OR write IL directly
            // 5. Output assembly

            Log.LogMessage(MessageImportance.High,
                $"Compiling {Sources.Length} N# files...");

            try
            {
                var compiler = new MultiFileCompiler(
                    Sources.Select(s => s.ItemSpec),
                    projectRoot: Directory.GetCurrentDirectory(),
                    config: LoadProjectConfig());

                var result = compiler.Compile();

                if (!result.Success)
                {
                    foreach (var error in result.Errors)
                    {
                        Log.LogError(
                            subcategory: null,
                            errorCode: error.Code.ToString(),
                            helpKeyword: null,
                            file: error.FileName ?? "",
                            lineNumber: error.Line,
                            columnNumber: error.Column,
                            endLineNumber: 0,
                            endColumnNumber: 0,
                            message: error.Message);
                    }
                    return false;
                }

                // Transpile and compile
                // ... (existing logic from Cli/Program.cs)

                return true;
            }
            catch (Exception ex)
            {
                Log.LogErrorFromException(ex);
                return false;
            }
        }
    }
}
```

### Phase 2: Project File Format (Week 2)

**Goal:** Define .nlproj format based on MSBuild

**Example:** `MyApp.nlproj`
```xml
<Project Sdk="Microsoft.NET.Sdk.NSharp">

  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <RootNamespace>MyApp</RootNamespace>
    <LangVersion>latest</LangVersion>
  </PropertyGroup>

  <!-- N# files are included by default (*.nl) -->
  <!-- Exclude test files from main build -->
  <ItemGroup>
    <Compile Remove="**/*.tests.nl" />
  </ItemGroup>

  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
  </ItemGroup>

</Project>
```

**For ASP.NET Core:** `EmployeeApi.nlproj`
```xml
<Project Sdk="Microsoft.NET.Sdk.NSharp.Web">

  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.EntityFrameworkCore.Sqlite" Version="9.0.0" />
    <PackageReference Include="Swashbuckle.AspNetCore" Version="7.2.0" />
  </ItemGroup>

</Project>
```

**For Libraries:** `MyLibrary.nlproj`
```xml
<Project Sdk="Microsoft.NET.Sdk.NSharp">

  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <GeneratePackageOnBuild>true</GeneratePackageOnBuild>
    <PackageId>MyCompany.MyLibrary</PackageId>
    <Version>1.0.0</Version>
    <Authors>Your Name</Authors>
    <Description>My N# library</Description>
  </PropertyGroup>

</Project>
```

**Migration from project.yml:**
```csharp
// Tool to convert project.yml → .nlproj
dotnet nsharp migrate project.yml
```

### Phase 3: dotnet Templates (Week 3)

**Goal:** Create `dotnet new` templates for N#

**Templates to Create:**
1. **nsharp-console** - Console application
2. **nsharp-classlib** - Class library
3. **nsharp-webapi** - ASP.NET Core Web API
4. **nsharp-webapp** - ASP.NET Core Web App (MVC)
5. **nsharp-test** - Test project (xUnit)
6. **nsharp-blazor** - Blazor WebAssembly

**Template Structure:**
```
templates/
├── console/
│   ├── .template.config/
│   │   └── template.json
│   ├── Company.Project.nlproj
│   └── Program.nl
├── webapi/
│   ├── .template.config/
│   │   └── template.json
│   ├── Company.WebApi.nlproj
│   ├── Program.nl
│   └── Controllers/
│       └── WeatherForecastController.nl
└── classlib/
    ├── .template.config/
    │   └── template.json
    ├── Company.Library.nlproj
    └── Class1.nl
```

**template.json** (console):
```json
{
  "$schema": "http://json.schemastore.org/template",
  "author": "N# Project",
  "classifications": ["Common", "Console", "N#"],
  "identity": "NSharp.Console",
  "name": "N# Console Application",
  "shortName": "nsharp-console",
  "tags": {
    "language": "N#",
    "type": "project"
  },
  "sourceName": "Company.Project",
  "preferNameDirectory": true,
  "symbols": {
    "Framework": {
      "type": "parameter",
      "description": "Target framework",
      "datatype": "choice",
      "choices": [
        {
          "choice": "net9.0",
          "description": ".NET 9.0"
        },
        {
          "choice": "net8.0",
          "description": ".NET 8.0"
        }
      ],
      "defaultValue": "net9.0",
      "replaces": "net9.0"
    }
  }
}
```

**Install templates:**
```bash
dotnet new install NSharp.Templates
```

**Usage:**
```bash
# Create new console app
dotnet new nsharp-console -o MyApp

# Create new web API
dotnet new nsharp-webapi -o MyApi

# Create class library
dotnet new nsharp-classlib -o MyLib
```

### Phase 4: NuGet SDK Package (Week 3)

**Goal:** Publish MSBuild SDK as NuGet package

**Package:** `Microsoft.NET.Sdk.NSharp`
```xml
<package>
  <metadata>
    <id>Microsoft.NET.Sdk.NSharp</id>
    <version>1.0.0</version>
    <authors>N# Project</authors>
    <description>MSBuild SDK for N# language</description>
    <projectUrl>https://github.com/yourusername/nsharp</projectUrl>
    <license type="MIT" />
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
  </metadata>
  <files>
    <!-- SDK files -->
    <file src="Sdk\**" target="Sdk\" />

    <!-- Build tasks -->
    <file src="..\Build.Tasks\bin\Release\**\NSharp.Build.Tasks.dll"
          target="tools\" />

    <!-- Compiler assemblies -->
    <file src="..\Compiler\bin\Release\**\Compiler.dll"
          target="tools\" />
  </files>
</package>
```

**Distribution:**
```bash
# Pack SDK
dotnet pack src/Sdk/Microsoft.NET.Sdk.NSharp.csproj

# Publish to NuGet
dotnet nuget push Microsoft.NET.Sdk.NSharp.1.0.0.nupkg
```

**Installation:**
```bash
# SDK auto-installed when using .nlproj
# Or explicitly:
dotnet workload install nsharp
```

### Phase 5: Solution Integration (Week 4)

**Goal:** N# projects work in .sln files alongside C#/F#

**Solution file:**
```
MyCompany.sln
├── MyApp.nlproj              (N# console app)
├── MyLibrary.nlproj          (N# library)
├── MyLibrary.Tests.nlproj    (N# tests)
├── MyLegacyApp.csproj        (C# app that references N# library)
└── MySharedLib.fsproj        (F# library)
```

**Cross-language references:**
```xml
<!-- C# project referencing N# library -->
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="..\MyLibrary.nlproj" />
  </ItemGroup>
</Project>
```

**Benefits:**
- Mixed-language solutions
- Visual Studio integration
- Rider integration
- MSBuild understands dependencies

### Phase 6: IDE Integration (Week 4-5)

**Visual Studio Integration:**
1. Project templates in "New Project" dialog
2. IntelliSense (already have LSP)
3. Solution Explorer integration
4. Build/Run/Debug integration

**Rider Integration:**
1. Plugin for N# support
2. Uses LSP for IntelliSense
3. Project model integration

**VS Code:**
- Already works via LSP
- Add task.json templates for build/run

### Phase 7: Testing Integration (Week 5)

**Goal:** `dotnet test` works with N# test projects

**Test Project:** `MyLib.Tests.nlproj`
```xml
<Project Sdk="Microsoft.NET.Sdk.NSharp">

  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.8.0" />
    <PackageReference Include="xunit" Version="2.6.0" />
    <PackageReference Include="xunit.runner.visualstudio" Version="2.5.6" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\MyLib.nlproj" />
  </ItemGroup>

</Project>
```

**Test files:** `MyLib.tests.nl`
```n#
test "addition works correctly" {
    result := 2 + 2
    assert result == 4
}
```

**Run tests:**
```bash
dotnet test                    # Run all tests
dotnet test --filter "FullyQualifiedName~MyLib"
dotnet test --logger "console;verbosity=detailed"
```

## Migration Strategy

### Phase 1: Dual Support (Months 1-3)

**Both CLIs work:**
```bash
# Old way (still works)
nsharp build Program.nl

# New way
dotnet build MyApp.nlproj
```

**Migration tool:**
```bash
# Convert existing project
dotnet nsharp migrate

# Creates MyApp.nlproj from project.yml
# Preserves all settings
```

### Phase 2: Deprecation (Months 4-6)

**nsharp CLI shows deprecation warnings:**
```bash
$ nsharp build Program.nl

⚠️  WARNING: 'nsharp' CLI is deprecated.
    Please migrate to 'dotnet' CLI for better integration.

    Run: dotnet nsharp migrate

    See: https://nsharp.dev/docs/migration
```

### Phase 3: Removal (Month 7+)

**nsharp CLI becomes thin wrapper:**
```bash
$ nsharp build
→ Redirects to: dotnet build
```

Eventually remove or archive separate CLI.

## Project Structure

### New Directory Layout
```
src/
├── Sdk/
│   ├── Microsoft.NET.Sdk.NSharp/
│   │   ├── Sdk.props
│   │   ├── Sdk.targets
│   │   └── Microsoft.NET.Sdk.NSharp.csproj
│   └── Microsoft.NET.Sdk.NSharp.Web/
│       ├── Sdk.props
│       ├── Sdk.targets
│       └── Microsoft.NET.Sdk.NSharp.Web.csproj
├── Build.Tasks/
│   ├── NSharpCompile.cs
│   └── NSharp.Build.Tasks.csproj
├── Templates/
│   ├── console/
│   ├── webapi/
│   ├── classlib/
│   └── test/
├── Compiler/              (existing)
├── LanguageServer/        (existing)
└── Cli/                   (migrate logic to Build.Tasks)

templates/                 (dotnet new templates)
└── NSharp.Templates.csproj
```

## Benefits

### For Users
✅ **Familiar workflow** - Same as C#/F#
✅ **IDE integration** - Works in VS, Rider, VS Code
✅ **Solution support** - Multi-project solutions
✅ **NuGet packaging** - Publish N# libraries easily
✅ **Cross-language** - Reference C# from N# and vice versa
✅ **MSBuild ecosystem** - All existing MSBuild tools work
✅ **CI/CD** - Standard .NET build pipelines

### For .NET Ecosystem
✅ **First-class language** - Not a separate tool
✅ **Standard tooling** - No special setup
✅ **Discoverable** - `dotnet new` lists N# templates
✅ **Professional** - Looks like serious .NET language
✅ **Adoption** - Easier for .NET developers to try

## Testing Strategy

### SDK Tests
```csharp
[Fact]
public void MSBuild_BuildsNSharpProject()
{
    var projectXml = @"
<Project Sdk='Microsoft.NET.Sdk.NSharp'>
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>
</Project>";

    var result = BuildProject(projectXml);

    Assert.True(result.Success);
    Assert.True(File.Exists(result.OutputAssembly));
}
```

### Template Tests
```bash
# Test all templates
dotnet new nsharp-console -o test-console
cd test-console
dotnet build
dotnet run
```

### Integration Tests
```bash
# Mixed-language solution
dotnet new sln -o MixedSolution
cd MixedSolution
dotnet new nsharp-classlib -o NSharpLib
dotnet new console -o CSharpApp
dotnet sln add **/*.csproj **/*.nlproj
dotnet build
```

## Documentation

### User Guide
```markdown
# Getting Started with N#

## Installation
```bash
dotnet workload install nsharp
```

## Create Your First App
```bash
dotnet new nsharp-console -o MyFirstApp
cd MyFirstApp
dotnet run
```

## Project Structure
- MyFirstApp.nlproj - Project file
- Program.nl - Entry point
```

### Migration Guide
```markdown
# Migrating from nsharp CLI to dotnet CLI

## Step 1: Install SDK
```bash
dotnet workload install nsharp
```

## Step 2: Migrate Project
```bash
cd your-project
dotnet nsharp migrate
```

This creates a .nlproj file from your project.yml.

## Step 3: Use dotnet commands
```bash
dotnet build
dotnet run
dotnet test
```
```

## Success Criteria

- [ ] MSBuild SDK published to NuGet
- [ ] `dotnet new nsharp-*` templates available
- [ ] `dotnet build` works with .nlproj files
- [ ] `dotnet run` works with N# projects
- [ ] `dotnet test` works with N# test projects
- [ ] Mixed C#/N# solutions build correctly
- [ ] NuGet packages can be created from N# libraries
- [ ] All existing examples migrated to .nlproj
- [ ] Documentation updated
- [ ] CI/CD pipelines use `dotnet` commands

## Timeline

**Optimistic (Full-Time):**
- Weeks 1-2: MSBuild SDK + Build Tasks
- Week 3: NuGet packaging + Templates
- Week 4: Solution integration
- Week 5: Testing + Documentation
- **Total:** 5 weeks

**Realistic (Part-Time):**
- Months 1-2: Core SDK implementation
- Month 3: Templates and packaging
- Month 4: Integration and polish
- **Total:** 4 months

## Deliverables

1. **Microsoft.NET.Sdk.NSharp** - NuGet package
2. **NSharp.Templates** - dotnet new templates
3. **Migration tool** - project.yml → .nlproj
4. **Documentation** - Complete user guides
5. **Examples** - All converted to .nlproj
6. **CI/CD** - GitHub Actions using dotnet commands

## Dependencies

**NuGet Packages:**
- Microsoft.Build.Framework
- Microsoft.Build.Utilities.Core
- Microsoft.NET.Sdk

**Tools:**
- NuGet CLI (for packaging)
- dotnet workload install infrastructure

## References

**Learning Resources:**
- [F# MSBuild SDK source](https://github.com/dotnet/fsharp/tree/main/src/fsharp/FSharp.Build)
- [Custom .NET SDK Tutorial](https://natemcmaster.com/blog/2017/11/11/msbuild-sdk-resolve/)
- [MSBuild SDK documentation](https://learn.microsoft.com/en-us/visualstudio/msbuild/how-to-use-project-sdk)
- [Creating dotnet new templates](https://learn.microsoft.com/en-us/dotnet/core/tools/custom-templates)

## Next Steps After This Task

1. **Visual Studio Extension** - Full IDE integration
2. **Rider Plugin** - JetBrains support
3. **Azure DevOps Tasks** - CI/CD integration
4. **GitHub Actions** - Pre-built workflows
5. **Code Analysis** - .editorconfig support
6. **Format on Save** - Code formatter integration

This task transforms N# from a "side project" into a **professional .NET language**!
