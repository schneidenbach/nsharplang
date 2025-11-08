using System;
using System.IO;
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
  Newtonsoft.Json: 13.0.3
  System.Text.Json: 8.0.0

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
            Assert.Equal(2, config.Dependencies.Count);
            Assert.Equal("13.0.3", config.Dependencies["Newtonsoft.Json"]);
            Assert.Equal("8.0.0", config.Dependencies["System.Text.Json"]);
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
}
