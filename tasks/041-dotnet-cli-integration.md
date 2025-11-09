# Task 041: .NET CLI Integration (Phase 1 - MSBuild SDK)

**Priority:** 🔴 P0-Critical
**Estimated Effort:** Medium (12-15 hours)
**Status:** Not started
**Depends on:** None (foundational)
**Next Task:** 042 (dotnet templates)

## Goal

Create the MSBuild SDK (`Microsoft.NET.Sdk.NSharp`) that enables N# to work with `dotnet build`, `dotnet run`, and other standard .NET CLI commands.

## Why Phase 1

The MSBuild SDK is the foundation for everything else. Without it, we can't have:
- dotnet templates (Task 042)
- Project files recognized by IDEs
- Standard .NET build workflows
- Integration with existing .NET tooling

## Deliverables

### 1. SDK Project Structure

```
sdk/
├── Microsoft.NET.Sdk.NSharp/
│   ├── Sdk/
│   │   ├── Sdk.props
│   │   ├── Sdk.targets
│   │   └── Sdk.After.targets
│   ├── build/
│   │   └── Microsoft.NET.Sdk.NSharp.props
│   ├── buildCrossTargeting/
│   │   └── Microsoft.NET.Sdk.NSharp.props
│   └── Microsoft.NET.Sdk.NSharp.csproj
```

### 2. Sdk.props

Define default properties for N# projects:

```xml
<Project>
  <PropertyGroup>
    <!-- Default language version -->
    <LangVersion>latest</LangVersion>

    <!-- Enable nullable reference types -->
    <Nullable>enable</Nullable>

    <!-- Default target framework -->
    <TargetFramework Condition="'$(TargetFramework)' == ''">net9.0</TargetFramework>

    <!-- N# file extension -->
    <DefaultItemExcludes>$(DefaultItemExcludes);**/*.tests.nl</DefaultItemExcludes>
  </PropertyGroup>

  <ItemGroup>
    <!-- Include N# files as compile items -->
    <NSharpCompile Include="**/*.nl" Exclude="$(DefaultItemExcludes)" />
  </ItemGroup>
</Project>
```

### 3. Sdk.targets

Define build tasks:

```xml
<Project>
  <UsingTask TaskName="NSharpCompile" AssemblyFile="$(NSharpCompilerPath)/NSharp.Build.Tasks.dll" />

  <Target Name="CoreNSharpCompile"
          BeforeTargets="CoreCompile"
          DependsOnTargets="ResolveReferences">

    <NSharpCompile
      Sources="@(NSharpCompile)"
      References="@(ReferencePath)"
      OutputPath="$(IntermediateOutputPath)"
      TargetFramework="$(TargetFramework)"
      RootNamespace="$(RootNamespace)"
      OutputType="$(OutputType)" />

    <ItemGroup>
      <Compile Include="$(IntermediateOutputPath)/**/*.cs" />
    </ItemGroup>
  </Target>

  <!-- Test discovery -->
  <Target Name="DiscoverNSharpTests"
          BeforeTargets="VSTestDiscover"
          Condition="'@(NSharpTestCompile)' != ''">

    <ItemGroup>
      <NSharpTestCompile Include="**/*.tests.nl" />
    </ItemGroup>
  </Target>
</Project>
```

### 4. MSBuild Task (NSharpCompile)

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
        public string OutputPath { get; set; }

        [Required]
        public string TargetFramework { get; set; }

        public string RootNamespace { get; set; }

        public string OutputType { get; set; }

        public override bool Execute()
        {
            Log.LogMessage(MessageImportance.High,
                $"Compiling {Sources.Length} N# files...");

            try
            {
                var compiler = new MultiFileCompiler(
                    Sources.Select(s => s.ItemSpec).ToList(),
                    OutputPath,
                    new ProjectConfig
                    {
                        TargetFramework = TargetFramework,
                        OutputType = OutputType ?? "library",
                        // ... configure from MSBuild properties
                    }
                );

                var result = compiler.Compile();

                if (!result.Success)
                {
                    foreach (var error in result.Errors)
                    {
                        Log.LogError(error.Message);
                    }
                    return false;
                }

                Log.LogMessage(MessageImportance.High, "Compilation successful!");
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

## Project File Format: .nlproj

```xml
<Project Sdk="Microsoft.NET.Sdk.NSharp">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <OutputType>Exe</OutputType>
    <RootNamespace>MyApp</RootNamespace>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
  </ItemGroup>
</Project>
```

## Success Criteria

### Build Works
```bash
# Create .nlproj file
cat > MyApp.nlproj <<EOF
<Project Sdk="Microsoft.NET.Sdk.NSharp">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>
</Project>
EOF

# Write N# code
cat > Program.nl <<EOF
func main() {
    print "Hello from dotnet build!"
}
EOF

# Build with dotnet CLI
dotnet build
dotnet run
```

### Output
```
Compiling 1 N# files...
Compilation successful!
MyApp -> /path/to/bin/Debug/net9.0/MyApp.dll

Hello from dotnet build!
```

## Implementation Steps

1. **Week 1, Days 1-2**: Create SDK project structure
2. **Week 1, Days 3-4**: Implement MSBuild task (NSharpCompile)
3. **Week 1, Day 5**: Test basic compilation
4. **Week 2, Days 1-2**: Add reference resolution
5. **Week 2, Day 3**: NuGet packaging
6. **Week 2, Days 4-5**: Testing & documentation

## Testing Plan

```csharp
[Fact]
public void MSBuild_CompilesSimpleProject()
{
    // Arrange
    var projectDir = CreateTestProject(@"
        <Project Sdk=\""Microsoft.NET.Sdk.NSharp\"">
          <PropertyGroup>
            <OutputType>Exe</OutputType>
          </PropertyGroup>
        </Project>
    ", @"
        func main() {
            print \"Hello\"
        }
    ");

    // Act
    var result = RunDotNetBuild(projectDir);

    // Assert
    Assert.Equal(0, result.ExitCode);
    Assert.Contains("Compilation successful", result.Output);
}

[Fact]
public void MSBuild_ResolvesPackageReferences()
{
    // Test NuGet package resolution
}

[Fact]
public void MSBuild_WorksWithMultipleFiles()
{
    // Test multi-file projects
}
```

## NuGet Package

```xml
<PackageReference Include="Microsoft.NET.Sdk.NSharp" Version="1.0.0" />
```

Package structure:
```
Microsoft.NET.Sdk.NSharp.1.0.0.nupkg
├── Sdk/
│   ├── Sdk.props
│   ├── Sdk.targets
│   └── Sdk.After.targets
├── build/
│   └── Microsoft.NET.Sdk.NSharp.props
├── tools/
│   └── net9.0/
│       ├── NSharp.Build.Tasks.dll
│       └── Compiler.dll
```

## Next Steps

After this task:
- Task 042: dotnet new templates
- Task 043: NuGet publishing automation
- Task 044: IDE integration (recognize .nlproj)

---

**Estimated Time:** 12-15 hours
**Complexity:** High (MSBuild integration is complex)
**Impact:** 🔥 Critical - Foundation for all .NET integration
