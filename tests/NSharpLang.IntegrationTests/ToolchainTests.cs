using System;
using System.Threading.Tasks;
using DotNet.Testcontainers.Containers;
using Xunit;

namespace NSharpLang.IntegrationTests;

/// <summary>
/// End-to-end integration tests that verify the full N# toolchain works
/// on a fresh machine (simulated via a Docker container with only the
/// .NET SDK pre-installed and our NuGet packages available).
/// </summary>
[Trait("Category", "Integration")]
public class ToolchainTests : IClassFixture<ToolchainFixture>
{
    private readonly ToolchainFixture _fixture;

    public ToolchainTests(ToolchainFixture fixture)
    {
        _fixture = fixture;
    }

    [Fact]
    public async Task InstallTemplates_ListsConsoleAndWebApi()
    {
        await Bash("dotnet new install NSharpLang.Templates --force");

        var list = await Bash("dotnet new list nsharp");
        AssertSuccess(list, "dotnet new list");
        Assert.Contains("nsharp-console", list.Stdout);
        Assert.Contains("nsharp-webapi", list.Stdout);
    }

    [Fact]
    public async Task ConsoleApp_ScaffoldsCorrectFiles()
    {
        var dir = UniqueDir("scaffold");
        await InstallTemplates();

        var create = await Bash($"dotnet new nsharp-console -o {dir}");
        AssertSuccess(create, "dotnet new nsharp-console");

        // Verify expected files exist (the .csproj is renamed to match the output dir name)
        var dirName = dir.Split('/')[^1];
        var check = await Bash(
            $"test -f {dir}/project.yml && " +
            $"test -f {dir}/Program.nl && " +
            $"test -f {dir}/{dirName}.csproj && " +
            $"test -f {dir}/global.json");
        AssertSuccess(check, "expected files exist");
    }

    [Fact]
    public async Task ConsoleApp_BuildsSuccessfully()
    {
        var dir = UniqueDir("console-build");
        await InstallTemplates();
        await Bash($"dotnet new nsharp-console -o {dir}");

        var build = await Bash($"cd {dir} && dotnet build");
        AssertSuccess(build, "dotnet build (console)");
    }

    [Fact]
    public async Task ConsoleApp_RunsAndProducesOutput()
    {
        var dir = UniqueDir("console-run");
        await InstallTemplates();
        await Bash($"dotnet new nsharp-console -o {dir}");

        var run = await Bash($"cd {dir} && dotnet run");
        AssertSuccess(run, "dotnet run (console)");
        Assert.Contains("Hello, N#!", run.Stdout);
    }

    [Fact]
    public async Task WebApiApp_BuildsSuccessfully()
    {
        var dir = UniqueDir("webapi-build");
        await InstallTemplates();
        await Bash($"dotnet new nsharp-webapi -o {dir}");

        var build = await Bash($"cd {dir} && dotnet build");
        AssertSuccess(build, "dotnet build (webapi)");
    }

    [Fact]
    public async Task CliTool_InstallsAndReportsVersion()
    {
        var install = await Bash("dotnet tool install -g NSharpLang.Cli");
        AssertSuccess(install, "dotnet tool install NSharpLang.Cli");

        var version = await Bash("nlc --version");
        AssertSuccess(version, "nlc --version");
    }

    [Fact]
    public async Task LanguageServer_Installs()
    {
        var install = await Bash("dotnet tool install -g NSharpLang.LanguageServer");
        AssertSuccess(install, "dotnet tool install NSharpLang.LanguageServer");

        // Verify the tool is listed
        var list = await Bash("dotnet tool list -g");
        AssertSuccess(list, "dotnet tool list");
        Assert.Contains("nsharplang.languageserver", list.Stdout.ToLowerInvariant());
    }

    // --- Helpers ---

    private Task<ExecResult> Bash(string command) =>
        _fixture.Container.ExecAsync(["bash", "-c", command]);

    private async Task InstallTemplates()
    {
        var result = await Bash("dotnet new install NSharpLang.Templates --force");
        AssertSuccess(result, "template installation");
    }

    private static string UniqueDir(string prefix) =>
        $"/workspace/{prefix}-{Guid.NewGuid().ToString("N")[..8]}";

    private static void AssertSuccess(ExecResult result, string context)
    {
        Assert.True(
            result.ExitCode == 0,
            $"{context} failed (exit code {result.ExitCode})\n" +
            $"--- stdout ---\n{result.Stdout}\n" +
            $"--- stderr ---\n{result.Stderr}");
    }
}
