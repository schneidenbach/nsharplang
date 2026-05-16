using System;
using System.Linq;
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
    public async Task InstallTemplates_ListsConsoleLibraryTestAndWebApi()
    {
        await Bash("dotnet new install NSharpLang.Templates --force");

        var list = await Bash("dotnet new list nsharp");
        AssertSuccess(list, "dotnet new list");
        Assert.Contains("nsharp-console", list.Stdout);
        Assert.Contains("nsharp-library", list.Stdout);
        Assert.Contains("nsharp-test", list.Stdout);
        Assert.Contains("nsharp-webapi", list.Stdout);
    }

    [Fact]
    public async Task DotnetTemplates_ScaffoldCanonicalCsprojFreeShape()
    {
        await InstallTemplates();

        foreach (var (shortName, dir, expectedFile) in new[]
        {
            ("nsharp-console", UniqueDir("console-shape"), "Program.nl"),
            ("nsharp-library", UniqueDir("library-shape"), "Calculator.nl"),
            ("nsharp-test", UniqueDir("test-shape"), "Calculator.tests.nl"),
            ("nsharp-webapi", UniqueDir("webapi-shape"), "Controllers/WeatherController.nl"),
        })
        {
            var create = await Bash($"dotnet new {shortName} -o {dir}");
            AssertSuccess(create, $"dotnet new {shortName}");

            var check = await Bash(
                $"test -f {dir}/project.yml && " +
                $"test -f {dir}/global.json && " +
                $"test -f {dir}/NuGet.config && " +
                $"test -f {dir}/{expectedFile} && " +
                $"test -z \"$(find {dir} -maxdepth 1 -name '*.csproj' -print -quit)\"");
            AssertSuccess(check, $"canonical shape for {shortName}");
        }
    }

    [Fact]
    public async Task NlcNew_AndDotnetNewTemplates_ProduceCompatibleProjectShape()
    {
        await InstallTemplates();
        await InstallCli();

        foreach (var (template, shortName, sourceFiles) in new[]
        {
            ("console", "nsharp-console", new[] { "Program.nl" }),
            ("library", "nsharp-library", new[] { "Calculator.nl" }),
            ("test", "nsharp-test", new[] { "Calculator.nl", "Calculator.tests.nl" }),
            ("webapi", "nsharp-webapi", new[] { "Program.nl", "Controllers/WeatherController.nl" }),
        })
        {
            var nlcParent = UniqueDir($"nlc-new-{template}-parent");
            var nlcDir = $"{nlcParent}/Demo";
            var dotnetDir = UniqueDir($"dotnet-new-{template}");
            var templateArg = template == "console" ? "" : $" --template {template}";

            var nlcCreate = await Bash($"mkdir -p {nlcParent} && cd {nlcParent} && nlc new Demo{templateArg}");
            AssertSuccess(nlcCreate, $"nlc new Demo ({template})");

            var dotnetCreate = await Bash($"dotnet new {shortName} -n Demo -o {dotnetDir}");
            AssertSuccess(dotnetCreate, $"dotnet new {shortName}");

            var diffSources = string.Join(" && ", sourceFiles.Select(file => $"diff -u {nlcDir}/{file} {dotnetDir}/{file}"));
            var parity = await Bash(
                diffSources + " && " +
                $"diff -u {nlcDir}/global.json {dotnetDir}/global.json && " +
                $"diff -u {nlcDir}/NuGet.config {dotnetDir}/NuGet.config && " +
                $"grep -q '^name: Demo$' {nlcDir}/project.yml && " +
                $"grep -q '^name: Demo$' {dotnetDir}/project.yml && " +
                $"test -z \"$(find {nlcDir} -maxdepth 1 -name '*.csproj' -print -quit)\" && " +
                $"test -z \"$(find {dotnetDir} -maxdepth 1 -name '*.csproj' -print -quit)\"");
            AssertSuccess(parity, $"nlc new and dotnet new {template} parity");
        }
    }

    [Fact]
    public async Task ConsoleApp_ScaffoldsCorrectFiles()
    {
        var dir = UniqueDir("scaffold");
        await InstallTemplates();

        var create = await Bash($"dotnet new nsharp-console -o {dir}");
        AssertSuccess(create, "dotnet new nsharp-console");

        // Verify expected files exist — no .csproj (nlc generates it on build)
        var check = await Bash(
            $"test -f {dir}/project.yml && " +
            $"test -f {dir}/Program.nl");
        AssertSuccess(check, "expected files exist");
    }

    [Fact]
    public async Task ConsoleApp_BuildsSuccessfully()
    {
        var dir = UniqueDir("console-build");
        await InstallTemplates();
        await InstallCli();
        await Bash($"dotnet new nsharp-console -o {dir}");

        var build = await Bash($"cd {dir} && nlc build");
        AssertSuccess(build, "nlc build (console)");
    }

    [Fact]
    public async Task ConsoleApp_RunsAndProducesOutput()
    {
        var dir = UniqueDir("console-run");
        await InstallTemplates();
        await InstallCli();
        await Bash($"dotnet new nsharp-console -o {dir}");

        var run = await Bash($"cd {dir} && nlc run");
        AssertSuccess(run, "nlc run (console)");
        Assert.Contains("Hello, N#!", run.Stdout);
    }

    [Fact]
    public async Task LibraryTemplate_BuildsSuccessfully()
    {
        var dir = UniqueDir("library-build");
        await InstallTemplates();
        await InstallCli();
        await Bash($"dotnet new nsharp-library -o {dir}");

        var build = await Bash($"cd {dir} && nlc build");
        AssertSuccess(build, "nlc build (library)");
    }

    [Fact]
    public async Task TestTemplate_TestsSuccessfully()
    {
        var dir = UniqueDir("test-run");
        await InstallTemplates();
        await InstallCli();
        await Bash($"dotnet new nsharp-test -o {dir}");

        var test = await Bash($"cd {dir} && nlc test");
        AssertSuccess(test, "nlc test (test template)");
    }

    [Fact]
    public async Task WebApiApp_BuildsSuccessfully()
    {
        var dir = UniqueDir("webapi-build");
        await InstallTemplates();
        await InstallCli();
        await Bash($"dotnet new nsharp-webapi -o {dir}");

        var build = await Bash($"cd {dir} && nlc build");
        AssertSuccess(build, "nlc build (webapi)");
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

    private async Task InstallCli()
    {
        // Install nlc as a global tool (idempotent — update if already installed)
        var result = await Bash(
            "dotnet tool install -g NSharpLang.Cli 2>/dev/null || dotnet tool update -g NSharpLang.Cli");
        AssertSuccess(result, "CLI tool installation");
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
