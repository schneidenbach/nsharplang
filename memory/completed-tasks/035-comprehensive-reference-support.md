# Task 035: Comprehensive Reference Support in Project Files

**Priority:** High (Essential for real-world projects)
**Dependencies:** None
**Estimated Effort:** Medium (4-6 hours)
**Status:** Not started

## Goal

Enhance `project.yml` to support all three types of references that .NET projects commonly need:
1. **NuGet packages** (with or without version)
2. **Local DLL files** (direct assembly references)
3. **Local project references** (other N# or C# projects)

## Current State

The current `ProjectConfig` has two separate concepts:

```yaml
# NuGet packages with versions (as dependencies)
dependencies:
  Newtonsoft.Json: 13.0.3
  Dapper: 2.1.28

# Assembly references (for type resolution only)
references:
  - Microsoft.AspNetCore
  - Microsoft.EntityFrameworkCore
```

**Problems:**
1. `dependencies` are NuGet packages but not loaded for type resolution
2. `references` are loaded for type resolution but not added to .csproj
3. No way to reference local DLL files
4. No way to reference local projects
5. Confusing distinction between dependencies and references

## Desired State

A unified, clear `references` section that supports all three types:

```yaml
name: MyWebApp
version: 1.0.0
targetFramework: net10.0

references:
  # NuGet packages (with version)
  - nuget: Microsoft.EntityFrameworkCore
    version: 9.0.0

  # NuGet packages (latest version)
  - nuget: Newtonsoft.Json

  # NuGet packages (shorthand syntax with version)
  - nuget: Dapper@2.1.28

  # Local DLL files
  - dll: libs/MyCustomLibrary.dll
  - dll: ../shared/Utils.dll

  # Local project references
  - project: ../SharedModels/SharedModels.csproj
  - project: ../CoreLibrary/project.yml  # Another N# project

  # Framework references (special case)
  - framework: Microsoft.AspNetCore.App
```

**Benefits:**
- Single, clear place for all references
- Type resolution works for all reference types
- Generated .csproj has correct PackageReference, Reference, and ProjectReference
- Matches .NET conventions

## Implementation Steps

### 1. Update Data Model

**File:** `src/Compiler/ProjectFile.cs`

Replace current model with structured references:

```csharp
/// <summary>
/// Represents the project.yml configuration file
/// </summary>
public class ProjectConfig
{
    public string? Name { get; set; }
    public string? Version { get; set; }
    public string? Entry { get; set; }
    public string OutputType { get; set; } = "exe";
    public string TargetFramework { get; set; } = "net10.0";

    /// <summary>
    /// References (NuGet packages, DLLs, projects)
    /// </summary>
    public List<Reference> References { get; set; } = new();

    /// <summary>
    /// DEPRECATED: Use References instead
    /// Kept for backwards compatibility
    /// </summary>
    [Obsolete("Use References instead")]
    public Dictionary<string, string> Dependencies { get; set; } = new();

    public LanguageConfig Language { get; set; } = new();

    [YamlIgnore]
    public string EffectiveName => Name ?? Path.GetFileName(Environment.CurrentDirectory) ?? "Project";
}

/// <summary>
/// Reference to an external dependency
/// </summary>
public class Reference
{
    /// <summary>
    /// NuGet package name (e.g., "Microsoft.EntityFrameworkCore")
    /// </summary>
    public string? Nuget { get; set; }

    /// <summary>
    /// Version for NuGet package (optional, defaults to latest)
    /// </summary>
    public string? Version { get; set; }

    /// <summary>
    /// Path to local DLL file (e.g., "libs/MyLibrary.dll")
    /// </summary>
    public string? Dll { get; set; }

    /// <summary>
    /// Path to local project file (e.g., "../Shared/Shared.csproj" or "../Models/project.yml")
    /// </summary>
    public string? Project { get; set; }

    /// <summary>
    /// Framework reference (e.g., "Microsoft.AspNetCore.App")
    /// </summary>
    public string? Framework { get; set; }

    /// <summary>
    /// Get the reference type
    /// </summary>
    [YamlIgnore]
    public ReferenceType Type
    {
        get
        {
            if (Nuget != null) return ReferenceType.NuGet;
            if (Dll != null) return ReferenceType.Dll;
            if (Project != null) return ReferenceType.Project;
            if (Framework != null) return ReferenceType.Framework;
            throw new InvalidOperationException("Reference must specify one of: nuget, dll, project, or framework");
        }
    }

    /// <summary>
    /// Get the reference value (package name, path, etc.)
    /// </summary>
    [YamlIgnore]
    public string Value => Nuget ?? Dll ?? Project ?? Framework
        ?? throw new InvalidOperationException("Invalid reference");

    /// <summary>
    /// Validate this reference
    /// </summary>
    public void Validate(string projectDirectory)
    {
        switch (Type)
        {
            case ReferenceType.NuGet:
                if (string.IsNullOrWhiteSpace(Nuget))
                    throw new InvalidOperationException("NuGet reference must have a package name");
                break;

            case ReferenceType.Dll:
                if (string.IsNullOrWhiteSpace(Dll))
                    throw new InvalidOperationException("DLL reference must have a path");

                var dllPath = Path.IsPathRooted(Dll)
                    ? Dll
                    : Path.Combine(projectDirectory, Dll);

                if (!File.Exists(dllPath))
                    throw new FileNotFoundException($"DLL not found: {Dll} (resolved to {dllPath})");
                break;

            case ReferenceType.Project:
                if (string.IsNullOrWhiteSpace(Project))
                    throw new InvalidOperationException("Project reference must have a path");

                var projectPath = Path.IsPathRooted(Project)
                    ? Project
                    : Path.Combine(projectDirectory, Project);

                if (!File.Exists(projectPath))
                    throw new FileNotFoundException($"Project file not found: {Project} (resolved to {projectPath})");
                break;

            case ReferenceType.Framework:
                if (string.IsNullOrWhiteSpace(Framework))
                    throw new InvalidOperationException("Framework reference must have a name");
                break;
        }
    }
}

public enum ReferenceType
{
    NuGet,
    Dll,
    Project,
    Framework
}
```

### 2. Support Shorthand Syntax

Allow `nuget: Package@Version` shorthand:

```csharp
public class ReferenceConverter : IYamlTypeConverter
{
    public bool Accepts(Type type) => type == typeof(Reference);

    public object ReadYaml(IParser parser, Type type)
    {
        var scalar = parser.Consume<Scalar>();
        var value = scalar.Value;

        // Handle shorthand: "nuget: Package@Version"
        if (value.Contains('@'))
        {
            var parts = value.Split('@', 2);
            return new Reference
            {
                Nuget = parts[0].Trim(),
                Version = parts[1].Trim()
            };
        }

        // Otherwise, parse as object
        // ... standard YAML parsing
    }

    public void WriteYaml(IEmitter emitter, object value, Type type)
    {
        var reference = (Reference)value;

        // Write as shorthand if NuGet with version
        if (reference.Type == ReferenceType.NuGet && !string.IsNullOrEmpty(reference.Version))
        {
            emitter.Emit(new Scalar($"{reference.Nuget}@{reference.Version}"));
        }
        else
        {
            // Write as object
            // ... standard YAML writing
        }
    }
}
```

### 3. Backwards Compatibility

Support old `dependencies` field:

```csharp
private static void MigrateLegacyDependencies(ProjectConfig config)
{
    if (config.Dependencies.Count > 0)
    {
        Console.WriteLine("Warning: 'dependencies' field is deprecated. Use 'references' instead.");

        foreach (var (package, version) in config.Dependencies)
        {
            config.References.Add(new Reference
            {
                Nuget = package,
                Version = version
            });
        }

        config.Dependencies.Clear();
    }
}
```

### 4. Load References for Type Resolution

**File:** `src/Compiler/Analyzer.cs`

Update to handle all reference types:

```csharp
public void LoadProjectReferences(ProjectConfig project, string projectDirectory)
{
    foreach (var reference in project.References)
    {
        reference.Validate(projectDirectory);

        switch (reference.Type)
        {
            case ReferenceType.NuGet:
                // NuGet packages are loaded from the NuGet cache or bin directory
                LoadNuGetPackage(reference.Nuget!, reference.Version, project.TargetFramework);
                break;

            case ReferenceType.Dll:
                // Load DLL directly
                var dllPath = Path.IsPathRooted(reference.Dll!)
                    ? reference.Dll!
                    : Path.Combine(projectDirectory, reference.Dll!);
                LoadReferencedAssembly(dllPath);
                break;

            case ReferenceType.Project:
                // Load compiled output of the project
                var projectPath = Path.IsPathRooted(reference.Project!)
                    ? reference.Project!
                    : Path.Combine(projectDirectory, reference.Project!);
                LoadProjectReference(projectPath, project.TargetFramework);
                break;

            case ReferenceType.Framework:
                // Framework references (like Microsoft.AspNetCore.App)
                LoadFrameworkReference(reference.Framework!, project.TargetFramework);
                break;
        }
    }
}

private void LoadNuGetPackage(string packageName, string? version, string targetFramework)
{
    // Try to find package in:
    // 1. bin/Debug/net10.0/ (after restore)
    // 2. ~/.nuget/packages/packagename/version/
    // 3. Load by name (runtime resolution)

    var binPath = Path.Combine("bin", "Debug", targetFramework, $"{packageName}.dll");
    if (File.Exists(binPath))
    {
        LoadReferencedAssembly(binPath);
        return;
    }

    // Try NuGet cache
    var nugetCache = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    nugetCache = Path.Combine(nugetCache, ".nuget", "packages", packageName.ToLowerInvariant());

    if (Directory.Exists(nugetCache))
    {
        var versionDir = version != null
            ? Path.Combine(nugetCache, version)
            : Directory.GetDirectories(nugetCache).OrderByDescending(d => d).FirstOrDefault();

        if (versionDir != null)
        {
            var libPath = Path.Combine(versionDir, "lib", targetFramework, $"{packageName}.dll");
            if (File.Exists(libPath))
            {
                LoadReferencedAssembly(libPath);
                return;
            }
        }
    }

    // Fallback: try to load by name
    LoadReferencedAssemblyByName(packageName);
}

private void LoadProjectReference(string projectPath, string targetFramework)
{
    // If it's a .csproj, look for bin/Debug/net10.0/ProjectName.dll
    // If it's a project.yml (N# project), look for bin/Debug/net10.0/ProjectName.dll

    var projectDir = Path.GetDirectoryName(projectPath)!;
    var projectName = Path.GetFileNameWithoutExtension(projectPath);

    // Handle .csproj
    if (projectPath.EndsWith(".csproj"))
    {
        var outputPath = Path.Combine(projectDir, "bin", "Debug", targetFramework, $"{projectName}.dll");
        if (File.Exists(outputPath))
        {
            LoadReferencedAssembly(outputPath);
        }
        else
        {
            throw new FileNotFoundException(
                $"Project reference '{projectName}' has not been built. " +
                $"Expected: {outputPath}. Build the referenced project first.");
        }
    }
    // Handle project.yml (N# project)
    else if (projectPath.EndsWith(".yml"))
    {
        var nsharpProject = ProjectFileParser.Parse(projectPath);
        var outputPath = Path.Combine(projectDir, "bin", "Debug", targetFramework, $"{nsharpProject.EffectiveName}.dll");

        if (File.Exists(outputPath))
        {
            LoadReferencedAssembly(outputPath);
        }
        else
        {
            throw new FileNotFoundException(
                $"N# project reference '{nsharpProject.EffectiveName}' has not been built. " +
                $"Expected: {outputPath}. Build the referenced project first with 'nsharp build'.");
        }
    }
}

private void LoadFrameworkReference(string frameworkName, string targetFramework)
{
    // Framework references like Microsoft.AspNetCore.App don't have DLLs to load directly
    // They're implicit and provided by the runtime
    // Just record them for .csproj generation
    Console.WriteLine($"Framework reference: {frameworkName}");
}
```

### 5. Generate Correct .csproj

**File:** `src/Cli/Commands/BuildCommand.cs`

Update .csproj generation to include all reference types:

```csharp
private string GenerateCsProj(ProjectConfig project)
{
    var sb = new StringBuilder();
    sb.AppendLine("<Project Sdk=\"Microsoft.NET.Sdk\">");
    sb.AppendLine("  <PropertyGroup>");
    sb.AppendLine($"    <OutputType>{(project.OutputType == "exe" ? "Exe" : "Library")}</OutputType>");
    sb.AppendLine($"    <TargetFramework>{project.TargetFramework}</TargetFramework>");
    sb.AppendLine($"    <AssemblyName>{project.EffectiveName}</AssemblyName>");
    sb.AppendLine("    <Nullable>enable</Nullable>");
    sb.AppendLine("  </PropertyGroup>");

    if (project.References.Count > 0)
    {
        sb.AppendLine();
        sb.AppendLine("  <ItemGroup>");

        foreach (var reference in project.References)
        {
            switch (reference.Type)
            {
                case ReferenceType.NuGet:
                    if (reference.Version != null)
                        sb.AppendLine($"    <PackageReference Include=\"{reference.Nuget}\" Version=\"{reference.Version}\" />");
                    else
                        sb.AppendLine($"    <PackageReference Include=\"{reference.Nuget}\" Version=\"*\" />");
                    break;

                case ReferenceType.Dll:
                    var dllPath = Path.GetFullPath(reference.Dll!);
                    sb.AppendLine($"    <Reference Include=\"{Path.GetFileNameWithoutExtension(reference.Dll)}\">");
                    sb.AppendLine($"      <HintPath>{dllPath}</HintPath>");
                    sb.AppendLine("    </Reference>");
                    break;

                case ReferenceType.Project:
                    var projectPath = Path.GetFullPath(reference.Project!);
                    sb.AppendLine($"    <ProjectReference Include=\"{projectPath}\" />");
                    break;

                case ReferenceType.Framework:
                    sb.AppendLine($"    <FrameworkReference Include=\"{reference.Framework}\" />");
                    break;
            }
        }

        sb.AppendLine("  </ItemGroup>");
    }

    sb.AppendLine("</Project>");
    return sb.ToString();
}
```

### 6. Update Template

**File:** `src/Compiler/ProjectFile.cs`

Update template:

```csharp
public static string GenerateTemplate(string projectName)
{
    return $@"name: {projectName}
version: 1.0.0
entry: Program.nl
outputType: exe
targetFramework: net10.0

# References - all external dependencies go here
references:
  # NuGet packages (with version)
  # - nuget: Microsoft.EntityFrameworkCore
  #   version: 9.0.0

  # NuGet packages (shorthand with version)
  # - nuget: Newtonsoft.Json@13.0.3

  # NuGet packages (latest version)
  # - nuget: Dapper

  # Local DLL files
  # - dll: libs/MyCustomLibrary.dll
  # - dll: ../shared/Utils.dll

  # Local project references (.csproj or project.yml)
  # - project: ../SharedModels/SharedModels.csproj
  # - project: ../CoreLibrary/project.yml

  # Framework references
  # - framework: Microsoft.AspNetCore.App

language:
  asyncDefaultType: ValueTask
";
}
```

### 7. CLI Commands

Add `nsharp restore` command:

```csharp
// File: src/Cli/Commands/RestoreCommand.cs
public class RestoreCommand
{
    public async Task<int> Execute()
    {
        var project = ProjectFileParser.ParseFromDirectory(".");
        if (project == null)
        {
            Console.WriteLine("No project.yml found");
            return 1;
        }

        Console.WriteLine($"Restoring packages for {project.EffectiveName}...");

        // Generate temporary .csproj
        var csproj = GenerateCsProj(project);
        File.WriteAllText("obj/temp.csproj", csproj);

        // Run dotnet restore
        var process = Process.Start("dotnet", "restore obj/temp.csproj");
        await process.WaitForExitAsync();

        if (process.ExitCode == 0)
        {
            Console.WriteLine("Restore succeeded");
        }
        else
        {
            Console.WriteLine("Restore failed");
        }

        return process.ExitCode;
    }
}
```

## Example project.yml Files

### Web API Project
```yaml
name: TaskManagementApi
version: 1.0.0
entry: Program.nl
targetFramework: net10.0

references:
  # ASP.NET Core
  - framework: Microsoft.AspNetCore.App

  # Entity Framework Core
  - nuget: Microsoft.EntityFrameworkCore@9.0.0
  - nuget: Microsoft.EntityFrameworkCore.Sqlite@9.0.0

  # JSON handling
  - nuget: Newtonsoft.Json
```

### Library with Local References
```yaml
name: MyLibrary
version: 2.1.0
outputType: library
targetFramework: net10.0

references:
  # Project dependencies
  - project: ../SharedModels/SharedModels.csproj
  - project: ../CoreLibrary/project.yml

  # Local DLLs
  - dll: libs/ThirdPartyLibrary.dll

  # NuGet packages
  - nuget: Dapper@2.1.28
```

## Success Criteria

- [ ] `Reference` class supports nuget, dll, project, framework
- [ ] YAML deserialization works for all reference types
- [ ] Shorthand syntax `nuget: Package@Version` works
- [ ] Backwards compatibility with old `dependencies` field
- [ ] Validation checks that files exist (dll, project)
- [ ] Analyzer loads all reference types for type resolution
- [ ] Generated .csproj has correct ItemGroup entries
- [ ] `nsharp restore` command works
- [ ] Template updated with all reference examples
- [ ] At least 10 tests for reference parsing and validation
- [ ] Documentation updated

## Testing

```csharp
[Fact]
public void ParseReference_NuGet_WithVersion()
{
    var yaml = @"
references:
  - nuget: Microsoft.EntityFrameworkCore
    version: 9.0.0
";
    var config = Parse(yaml);

    Assert.Single(config.References);
    Assert.Equal(ReferenceType.NuGet, config.References[0].Type);
    Assert.Equal("Microsoft.EntityFrameworkCore", config.References[0].Nuget);
    Assert.Equal("9.0.0", config.References[0].Version);
}

[Fact]
public void ParseReference_NuGet_Shorthand()
{
    var yaml = @"
references:
  - nuget: Dapper@2.1.28
";
    var config = Parse(yaml);

    Assert.Single(config.References);
    Assert.Equal("Dapper", config.References[0].Nuget);
    Assert.Equal("2.1.28", config.References[0].Version);
}

[Fact]
public void ParseReference_Dll_ValidatesPath()
{
    var yaml = @"
references:
  - dll: nonexistent.dll
";

    Assert.Throws<FileNotFoundException>(() => ParseAndValidate(yaml));
}

[Fact]
public void ParseReference_Project_CsProj()
{
    var yaml = @"
references:
  - project: ../Shared/Shared.csproj
";

    var config = Parse(yaml);
    Assert.Equal(ReferenceType.Project, config.References[0].Type);
}

[Fact]
public void GenerateCsProj_AllReferenceTypes()
{
    var config = new ProjectConfig
    {
        References = new List<Reference>
        {
            new() { Nuget = "Dapper", Version = "2.1.28" },
            new() { Dll = "libs/Custom.dll" },
            new() { Project = "../Shared/Shared.csproj" },
            new() { Framework = "Microsoft.AspNetCore.App" }
        }
    };

    var csproj = GenerateCsProj(config);

    Assert.Contains("<PackageReference Include=\"Dapper\" Version=\"2.1.28\"", csproj);
    Assert.Contains("<Reference Include=\"Custom\">", csproj);
    Assert.Contains("<ProjectReference Include=", csproj);
    Assert.Contains("<FrameworkReference Include=\"Microsoft.AspNetCore.App\"", csproj);
}
```

## Documentation Updates

- `DESIGN.md` - Add section on project references
- `memory/features/project-files.md` - Document reference types
- `examples/13-aspnet-demo/TaskManagementApi/project.yml` - Use new format
- `README.md` - Update project.yml examples

## Notes

This brings N# project files to parity with .csproj functionality while keeping the YAML format clean and readable. The unified `references` section is clearer than splitting between `dependencies` and `references`.
