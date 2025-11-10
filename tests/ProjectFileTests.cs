using System;
using System.IO;
using System.Linq;
using NewCLILang.Compiler;
using Xunit;

namespace NewCLILang.Tests;

public class ProjectFileTests
{
    [Fact]
    public void TestParseValidProjectFile()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        try
        {
            Directory.CreateDirectory(tempDir);

            var yaml = @"name: MyProject
version: 1.0.0
entry: Program.nl
outputType: exe
targetFramework: net9.0

dependencies:
  - nuget: Newtonsoft.Json
    version: 13.0.3
  - nuget: System.Text.Json
    version: 8.0.0

language:
  asyncDefaultType: ValueTask
";
            var projectFile = Path.Combine(tempDir, "project.yml");
            File.WriteAllText(projectFile, yaml);

            // Create dummy entry file to satisfy validation
            var entryFile = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(entryFile, "// test");

            var config = ProjectFileParser.Parse(projectFile);

            Assert.Equal("MyProject", config.Name);
            Assert.Equal("1.0.0", config.Version);
            Assert.Equal("Program.nl", config.Entry);
            Assert.Equal("exe", config.OutputType);
            Assert.Equal("net9.0", config.TargetFramework);
            // Check dependencies (new list format)
            Assert.Equal(2, config.Dependencies.Count);
            var newtonsoft = config.Dependencies.FirstOrDefault(r => r.Nuget == "Newtonsoft.Json");
            Assert.NotNull(newtonsoft);
            Assert.Equal("13.0.3", newtonsoft!.Version);
            var systemText = config.Dependencies.FirstOrDefault(r => r.Nuget == "System.Text.Json");
            Assert.NotNull(systemText);
            Assert.Equal("8.0.0", systemText!.Version);
            Assert.Equal("ValueTask", config.Language.AsyncDefaultType);
        }
        finally
        {
            if (Directory.Exists(tempDir))
                Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TestParseMinimalProjectFile()
    {
        var yaml = @"name: MinimalProject
";

        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllText(tempFile, yaml);

            var config = ProjectFileParser.Parse(tempFile);

            Assert.Equal("MinimalProject", config.Name);
            Assert.Null(config.Version);
            Assert.Null(config.Entry);
            Assert.Equal("exe", config.OutputType); // default
            Assert.Equal("net9.0", config.TargetFramework); // default
            Assert.Empty(config.Dependencies);
            Assert.Equal("ValueTask", config.Language.AsyncDefaultType); // default
        }
        finally
        {
            if (File.Exists(tempFile))
                File.Delete(tempFile);
        }
    }

    [Fact]
    public void TestParseLibraryProject()
    {
        var yaml = @"name: MyLibrary
outputType: library
targetFramework: net8.0
";

        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllText(tempFile, yaml);

            var config = ProjectFileParser.Parse(tempFile);

            Assert.Equal("MyLibrary", config.Name);
            Assert.Equal("library", config.OutputType);
            Assert.Equal("net8.0", config.TargetFramework);
        }
        finally
        {
            if (File.Exists(tempFile))
                File.Delete(tempFile);
        }
    }

    [Fact]
    public void TestParseWithTaskAsyncDefault()
    {
        var yaml = @"name: TaskProject
language:
  asyncDefaultType: Task
";

        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllText(tempFile, yaml);

            var config = ProjectFileParser.Parse(tempFile);

            Assert.Equal("Task", config.Language.AsyncDefaultType);
        }
        finally
        {
            if (File.Exists(tempFile))
                File.Delete(tempFile);
        }
    }

    [Fact]
    public void TestInvalidOutputType()
    {
        var yaml = @"name: BadProject
outputType: invalid
";

        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllText(tempFile, yaml);

            Assert.Throws<InvalidOperationException>(() => ProjectFileParser.Parse(tempFile));
        }
        finally
        {
            if (File.Exists(tempFile))
                File.Delete(tempFile);
        }
    }

    [Fact]
    public void TestInvalidAsyncDefaultType()
    {
        var yaml = @"name: BadProject
language:
  asyncDefaultType: Promise
";

        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllText(tempFile, yaml);

            Assert.Throws<InvalidOperationException>(() => ProjectFileParser.Parse(tempFile));
        }
        finally
        {
            if (File.Exists(tempFile))
                File.Delete(tempFile);
        }
    }

    [Fact]
    public void TestParseFromDirectory_Exists()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        try
        {
            Directory.CreateDirectory(tempDir);

            var yaml = @"name: DirProject
version: 2.0.0
";
            var projectFile = Path.Combine(tempDir, "project.yml");
            File.WriteAllText(projectFile, yaml);

            var config = ProjectFileParser.ParseFromDirectory(tempDir);

            Assert.NotNull(config);
            Assert.Equal("DirProject", config!.Name);
            Assert.Equal("2.0.0", config.Version);
        }
        finally
        {
            if (Directory.Exists(tempDir))
                Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TestParseFromDirectory_NotExists()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        try
        {
            Directory.CreateDirectory(tempDir);

            var config = ProjectFileParser.ParseFromDirectory(tempDir);

            Assert.Null(config);
        }
        finally
        {
            if (Directory.Exists(tempDir))
                Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TestCreateDefault()
    {
        var config = ProjectFileParser.CreateDefault("TestProject");

        Assert.Equal("TestProject", config.Name);
        Assert.Equal("exe", config.OutputType);
        Assert.Equal("net9.0", config.TargetFramework);
        Assert.Empty(config.Dependencies);
        Assert.Equal("ValueTask", config.Language.AsyncDefaultType);
    }

    [Fact]
    public void TestGenerateTemplate()
    {
        var template = ProjectFileParser.GenerateTemplate("MyNewProject");

        Assert.Contains("name: MyNewProject", template);
        Assert.Contains("version: 1.0.0", template);
        Assert.Contains("entry: Program.nl", template);
        Assert.Contains("outputType: exe", template);
        Assert.Contains("targetFramework: net9.0", template);
        Assert.Contains("asyncDefaultType: ValueTask", template);
    }

    [Fact]
    public void TestEffectiveName()
    {
        var config = new ProjectConfig { Name = "ExplicitName" };
        Assert.Equal("ExplicitName", config.EffectiveName);

        var config2 = new ProjectConfig { Name = null };
        Assert.NotNull(config2.EffectiveName);
        Assert.NotEmpty(config2.EffectiveName);
    }

    // ===== New Reference System Tests =====

    [Fact]
    public void TestParseReference_NuGet_WithVersion()
    {
        var yaml = @"name: TestProject
dependencies:
  - nuget: Microsoft.EntityFrameworkCore
    version: 9.0.0
";
        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllText(tempFile, yaml);
            var config = ProjectFileParser.Parse(tempFile);

            Assert.Single(config.Dependencies);
            Assert.Equal(ReferenceType.NuGet, config.Dependencies[0].Type);
            Assert.Equal("Microsoft.EntityFrameworkCore", config.Dependencies[0].Nuget);
            Assert.Equal("9.0.0", config.Dependencies[0].Version);
        }
        finally
        {
            if (File.Exists(tempFile)) File.Delete(tempFile);
        }
    }

    [Fact]
    public void TestParseReference_NuGet_WithoutVersion()
    {
        var yaml = @"name: TestProject
dependencies:
  - nuget: Dapper
";
        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllText(tempFile, yaml);
            var config = ProjectFileParser.Parse(tempFile);

            Assert.Single(config.Dependencies);
            Assert.Equal(ReferenceType.NuGet, config.Dependencies[0].Type);
            Assert.Equal("Dapper", config.Dependencies[0].Nuget);
            Assert.Null(config.Dependencies[0].Version);
        }
        finally
        {
            if (File.Exists(tempFile)) File.Delete(tempFile);
        }
    }

    [Fact]
    public void TestParseReference_NuGet_Shorthand()
    {
        var yaml = @"name: TestProject
dependencies:
  - nuget: Dapper@2.1.28
";
        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllText(tempFile, yaml);
            var config = ProjectFileParser.Parse(tempFile);

            Assert.Single(config.Dependencies);
            Assert.Equal(ReferenceType.NuGet, config.Dependencies[0].Type);
            Assert.Equal("Dapper", config.Dependencies[0].Nuget);
            Assert.Equal("2.1.28", config.Dependencies[0].Version);
        }
        finally
        {
            if (File.Exists(tempFile)) File.Delete(tempFile);
        }
    }

    [Fact]
    public void TestParseReference_Framework()
    {
        var yaml = @"name: TestProject
dependencies:
  - framework: Microsoft.AspNetCore.App
";
        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllText(tempFile, yaml);
            var config = ProjectFileParser.Parse(tempFile);

            Assert.Single(config.Dependencies);
            Assert.Equal(ReferenceType.Framework, config.Dependencies[0].Type);
            Assert.Equal("Microsoft.AspNetCore.App", config.Dependencies[0].Framework);
        }
        finally
        {
            if (File.Exists(tempFile)) File.Delete(tempFile);
        }
    }

    [Fact]
    public void TestParseReference_Dll()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        try
        {
            Directory.CreateDirectory(tempDir);

            // Create a dummy DLL file for validation
            var dllFile = Path.Combine(tempDir, "MyLibrary.dll");
            File.WriteAllText(dllFile, "dummy");

            var yaml = @"name: TestProject
dependencies:
  - dll: MyLibrary.dll
";
            var projectFile = Path.Combine(tempDir, "project.yml");
            File.WriteAllText(projectFile, yaml);
            var config = ProjectFileParser.Parse(projectFile);

            Assert.Single(config.Dependencies);
            Assert.Equal(ReferenceType.Dll, config.Dependencies[0].Type);
            Assert.Equal("MyLibrary.dll", config.Dependencies[0].Dll);
        }
        finally
        {
            if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TestParseReference_Project_CsProj()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        try
        {
            Directory.CreateDirectory(tempDir);
            var sharedDir = Path.Combine(tempDir, "Shared");
            Directory.CreateDirectory(sharedDir);

            // Create a dummy .csproj file for validation
            var csprojFile = Path.Combine(sharedDir, "Shared.csproj");
            File.WriteAllText(csprojFile, "<Project />");

            var yaml = @"name: TestProject
dependencies:
  - project: Shared/Shared.csproj
";
            var projectFile = Path.Combine(tempDir, "project.yml");
            File.WriteAllText(projectFile, yaml);
            var config = ProjectFileParser.Parse(projectFile);

            Assert.Single(config.Dependencies);
            Assert.Equal(ReferenceType.Project, config.Dependencies[0].Type);
            Assert.Equal("Shared/Shared.csproj", config.Dependencies[0].Project);
        }
        finally
        {
            if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TestParseReference_MultipleTypes()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        try
        {
            Directory.CreateDirectory(tempDir);

            // Create dummy files
            var dllFile = Path.Combine(tempDir, "Custom.dll");
            File.WriteAllText(dllFile, "dummy");
            var sharedDir = Path.Combine(tempDir, "Shared");
            Directory.CreateDirectory(sharedDir);
            var csprojFile = Path.Combine(sharedDir, "Shared.csproj");
            File.WriteAllText(csprojFile, "<Project />");

            var yaml = @"name: TestProject
dependencies:
  - nuget: Dapper@2.1.28
  - dll: Custom.dll
  - project: Shared/Shared.csproj
  - framework: Microsoft.AspNetCore.App
";
            var projectFile = Path.Combine(tempDir, "project.yml");
            File.WriteAllText(projectFile, yaml);
            var config = ProjectFileParser.Parse(projectFile);

            Assert.Equal(4, config.Dependencies.Count);
            Assert.Equal(ReferenceType.NuGet, config.Dependencies[0].Type);
            Assert.Equal("Dapper", config.Dependencies[0].Nuget);
            Assert.Equal("2.1.28", config.Dependencies[0].Version);

            Assert.Equal(ReferenceType.Dll, config.Dependencies[1].Type);
            Assert.Equal("Custom.dll", config.Dependencies[1].Dll);

            Assert.Equal(ReferenceType.Project, config.Dependencies[2].Type);
            Assert.Equal("Shared/Shared.csproj", config.Dependencies[2].Project);

            Assert.Equal(ReferenceType.Framework, config.Dependencies[3].Type);
            Assert.Equal("Microsoft.AspNetCore.App", config.Dependencies[3].Framework);
        }
        finally
        {
            if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
        }
    }

    // REMOVED: TestBackwardCompatibility_Dependencies
    // We no longer support the old dictionary format for dependencies.
    // Breaking changes are acceptable - use the new list format:
    // dependencies:
    //   - nuget: PackageName
    //     version: 1.0.0

    [Fact]
    public void TestReference_Value_Property()
    {
        var nugetRef = new Reference { Nuget = "TestPackage" };
        Assert.Equal("TestPackage", nugetRef.Value);

        var dllRef = new Reference { Dll = "test.dll" };
        Assert.Equal("test.dll", dllRef.Value);

        var projectRef = new Reference { Project = "test.csproj" };
        Assert.Equal("test.csproj", projectRef.Value);

        var frameworkRef = new Reference { Framework = "Microsoft.AspNetCore.App" };
        Assert.Equal("Microsoft.AspNetCore.App", frameworkRef.Value);
    }

    [Fact]
    public void TestReference_Type_Property()
    {
        Assert.Equal(ReferenceType.NuGet, new Reference { Nuget = "Test" }.Type);
        Assert.Equal(ReferenceType.Dll, new Reference { Dll = "test.dll" }.Type);
        Assert.Equal(ReferenceType.Project, new Reference { Project = "test.csproj" }.Type);
        Assert.Equal(ReferenceType.Framework, new Reference { Framework = "Test" }.Type);
    }

    [Fact]
    public void TestReference_InvalidEmpty()
    {
        var emptyRef = new Reference();
        Assert.Throws<InvalidOperationException>(() => emptyRef.Type);
        Assert.Throws<InvalidOperationException>(() => emptyRef.Value);
    }
}
