using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

public static class EnvCommand
{
    public static int Execute(string[] args)
    {
        var options = GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var json = options.Json;

        var nlcVersion = Program.GetVersion();
        var dotnetVersion = RunCapture("--version")?.Trim() ?? "unknown";
        var runtime = RuntimeInformation.FrameworkDescription;
        var os = RuntimeInformation.OSDescription;
        var arch = RuntimeInformation.OSArchitecture.ToString();
        var nugetCachePath = Environment.GetEnvironmentVariable("NUGET_PACKAGES")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nuget", "packages");
        var nsharpHome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nsharp");
        var nsharpBinPath = Path.Combine(nsharpHome, "bin");
        var nsharpPackageCachePath = Path.Combine(nsharpHome, "packages");

        string? projectName = null;
        string? targetFramework = null;
        string? outputType = null;
        string? sdk = null;

        var projectYml = Path.Combine(Directory.GetCurrentDirectory(), "project.yml");
        if (File.Exists(projectYml))
        {
            try
            {
                var config = ProjectFileParser.Parse(projectYml);
                projectName = config.Name;
                targetFramework = config.TargetFramework;
                outputType = config.OutputType;
                sdk = config.Sdk;
            }
            catch
            {
                // Ignore parse errors — just skip project info
            }
        }

        if (json)
        {
            using var stream = new MemoryStream();
            using var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true });
            writer.WriteStartObject();
            writer.WriteNumber("schemaVersion", 2);
            writer.WriteString("command", "env");
            writer.WriteBoolean("ok", true);
            writer.WriteString("nlcVersion", nlcVersion);
            writer.WriteString("dotnetVersion", dotnetVersion);
            writer.WriteString("runtime", runtime);
            writer.WriteString("os", os);
            writer.WriteString("arch", arch);
            writer.WriteString("nugetCachePath", nugetCachePath);
            writer.WriteString("nsharpBinPath", nsharpBinPath);
            writer.WriteString("nsharpPackageCachePath", nsharpPackageCachePath);
            if (projectName != null)
            {
                writer.WriteStartObject("project");
                writer.WriteString("name", projectName);
                writer.WriteString("targetFramework", targetFramework);
                writer.WriteString("outputType", outputType);
                writer.WriteString("sdk", sdk);
                writer.WriteEndObject();
            }
            writer.WriteEndObject();
            writer.Flush();
            Console.WriteLine(System.Text.Encoding.UTF8.GetString(stream.ToArray()));
        }
        else
        {
            Console.WriteLine($"nlc version:    {nlcVersion}");
            Console.WriteLine($"dotnet version: {dotnetVersion}");
            Console.WriteLine($"runtime:        {runtime}");
            Console.WriteLine($"os:             {os}");
            Console.WriteLine($"arch:           {arch}");
            Console.WriteLine($"nuget cache:    {nugetCachePath}");
            Console.WriteLine($"nsharp bin:     {nsharpBinPath}");
            Console.WriteLine($"nsharp packages: {nsharpPackageCachePath}");

            if (projectName != null)
            {
                Console.WriteLine();
                Console.WriteLine($"project:        {projectName}");
                Console.WriteLine($"target:         {targetFramework}");
                Console.WriteLine($"output type:    {outputType}");
                Console.WriteLine($"sdk:            {sdk}");
            }
        }

        return 0;
    }

    static string? RunCapture(string arguments)
    {
        try
        {
            var result = DotnetRunner.Run(arguments);
            return result.ExitCode == 0 ? result.Stdout : null;
        }
        catch
        {
            return null;
        }
    }

    internal static EnvOptionSummary GetOptionSummary(string[] args)
        => EnvCommandKernels.TryGetOptionSummary(args, out var summary)
            ? summary
            : GetOptionSummaryWithCSharp(args);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product env option parsing routes through EnvCommandKernels.
    private static EnvOptionSummary GetOptionSummaryWithCSharp(string[] args)
        => new(
            ContainsArgWithCSharp(args, "--json"),
            ContainsArgWithCSharp(args, "--help") || ContainsArgWithCSharp(args, "-h") || (args.Length > 0 && args[0] == "help"));

    private static bool ContainsArgWithCSharp(string[] args, string value)
    {
        for (var i = 0; i < args.Length; i++)
            if (args[i] == value)
                return true;
        return false;
    }

    static int ShowHelp()
    {
        Console.WriteLine(@"N# Environment Info

Usage: nlc env [options]

Show toolchain and environment information.

Options:
  --json          Output as JSON envelope
  --help, -h      Show this help text

Examples:
  nlc env
  nlc env --json

Exit codes:
  0  Always succeeds");

        return 0;
    }
}
