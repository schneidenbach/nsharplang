# Task 012: project.yml Support

**Priority:** CRITICAL (Project management)
**Dependencies:** None (but used by multi-file compilation)
**Estimated Effort:** Medium (4-6 hours)

## Goal
Parse and support `project.yml` configuration file for project metadata, dependencies, and language settings.

## File Format
```yaml
name: MyApp  # optional, defaults to directory name
version: 1.0.0
entry: Program.nl  # entry point for executables
outputType: exe  # or "library"
targetFramework: net8.0  # optional, defaults to latest

dependencies:
  Newtonsoft.Json: 13.0.3
  Microsoft.Extensions.DependencyInjection: 8.0.0
  Microsoft.AspNetCore.App: 8.0.0

language:
  asyncDefaultType: ValueTask  # or "Task"
```

## Implementation Steps

### 1. YAML Parser Dependency
- Add NuGet package: `YamlDotNet`
  ```xml
  <PackageReference Include="YamlDotNet" Version="13.7.1" />
  ```

### 2. ProjectFile.cs Structure
- Create data models for project.yml:
  ```csharp
  public class ProjectConfig {
      public string? Name { get; set; }
      public string? Version { get; set; }
      public string? Entry { get; set; }
      public string OutputType { get; set; } = "exe";
      public string TargetFramework { get; set; } = "net8.0";
      public Dictionary<string, string> Dependencies { get; set; } = new();
      public LanguageConfig Language { get; set; } = new();

      // Computed
      public string EffectiveName => Name ?? Path.GetFileName(Directory.GetCurrentDirectory());
  }

  public class LanguageConfig {
      public string AsyncDefaultType { get; set; } = "ValueTask";
  }
  ```

### 3. Parser Implementation
- Create `ProjectFileParser` class:
  ```csharp
  public class ProjectFileParser {
      public static ProjectConfig Parse(string yamlPath);
      public static ProjectConfig ParseFromDirectory(string directory);
  }
  ```
- Use YamlDotNet deserializer:
  ```csharp
  var deserializer = new DeserializerBuilder()
      .IgnoreUnmatchedProperties()
      .Build();
  var config = deserializer.Deserialize<ProjectConfig>(yaml);
  ```

### 4. Validation
- Validate asyncDefaultType: must be "Task" or "ValueTask"
- Validate entry file exists (if specified)
- Validate outputType: must be "exe" or "library"
- Validate targetFramework: warn if not supported

### 5. CLI Integration
- `nlc build` - Look for project.yml in current directory
- Use config to:
  - Determine output file name
  - Set entry point
  - Generate .csproj with dependencies
  - Pass language settings to compiler

### 6. Dependency Management
- Generate temporary .csproj with PackageReferences:
  ```xml
  <Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
      <OutputType>Exe</OutputType>
      <TargetFramework>net8.0</TargetFramework>
    </PropertyGroup>
    <ItemGroup>
      <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
    </ItemGroup>
  </Project>
  ```
- Let `dotnet build` restore packages automatically

### 7. Default Behavior
- If no project.yml exists:
  - Use directory name as project name
  - Default to exe output type
  - No dependencies
  - Default language settings
  - Look for Main() or top-level statements

### 8. `nlc new` Command
- Create new project with template project.yml:
  ```bash
  nlc new MyProject
  ```
- Creates:
  - `MyProject/` directory
  - `project.yml` with basic config
  - `Program.nl` with hello world

### 9. `nlc restore` Command
- Restore NuGet packages based on project.yml
- Essentially: generate .csproj and run `dotnet restore`

### 10. Tests
- Unit tests:
  - Parse valid project.yml
  - Handle missing fields (use defaults)
  - Validate required fields
  - Error on invalid values
- Integration tests:
  - Build project with dependencies
  - Custom entry point works
  - Language settings applied

## Success Criteria
- [x] project.yml parses correctly ✅
- [x] Dependencies translated to NuGet PackageReferences ✅
- [x] Entry point specified correctly ✅
- [x] Language settings accessible to compiler ✅
- [x] `nlc new` scaffolds project ✅
- [ ] `nlc restore` restores packages (not needed - dotnet build handles it)
- [x] All tests pass ✅ (270 tests, all passing)

## Implementation Summary (v1.24)

### Completed
1. ✅ Added YamlDotNet 16.3.0 dependency
2. ✅ Created ProjectConfig and LanguageConfig data models
3. ✅ Implemented ProjectFileParser with Parse, ParseFromDirectory, CreateDefault, GenerateTemplate
4. ✅ Added comprehensive validation (outputType, asyncDefaultType, entry file, targetFramework)
5. ✅ Integrated into CLI run command - automatic detection and usage
6. ✅ GenerateCsProj helper creates .csproj with dependencies
7. ✅ Implemented `nlc new` command for project scaffolding
8. ✅ Fixed transpiler to always emit `using System;`
9. ✅ 11 new tests covering all parser functionality
10. ✅ End-to-end testing with examples/SimpleProject and nlc new

### What Works
- Parse project.yml with YamlDotNet
- Validate all configuration fields
- Generate .csproj with NuGet dependencies
- `nlc new ProjectName` creates scaffolded project
- `nlc run Program.nl` automatically detects and uses project.yml
- Language config accessible for future features (async implicit wrapping)
- Graceful fallback when no project.yml present

### Test Count
270 tests total (259 existing + 11 new):
- 27 Lexer, 78 Parser, 63 Analyzer, 67 Transpiler
- 11 ProjectFile (NEW), 24 MultiFile
All passing ✅

## Notes
- YAML chosen for simplicity (vs XML .csproj)
- Minimal config needed (Go-style)
- Defaults to sensible values
- Compatible with .NET ecosystem (generates .csproj under hood)
