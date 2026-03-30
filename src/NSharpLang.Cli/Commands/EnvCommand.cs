using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

public static class EnvCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var json = args.Contains("--json");

        var nlcVersion = Program.GetVersion();
        var dotnetVersion = RunCapture("dotnet", "--version")?.Trim() ?? "unknown";
        var runtime = RuntimeInformation.FrameworkDescription;
        var os = RuntimeInformation.OSDescription;
        var arch = RuntimeInformation.OSArchitecture.ToString();
        var nugetCachePath = Environment.GetEnvironmentVariable("NUGET_PACKAGES")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nuget", "packages");
        var globalToolsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".dotnet", "tools");

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
            writer.WriteNumber("schemaVersion", 1);
            writer.WriteString("command", "env");
            writer.WriteBoolean("ok", true);
            writer.WriteString("nlcVersion", nlcVersion);
            writer.WriteString("dotnetVersion", dotnetVersion);
            writer.WriteString("runtime", runtime);
            writer.WriteString("os", os);
            writer.WriteString("arch", arch);
            writer.WriteString("nugetCachePath", nugetCachePath);
            writer.WriteString("globalToolsPath", globalToolsPath);
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
            Console.WriteLine($"global tools:   {globalToolsPath}");

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

    static string? RunCapture(string command, string arguments)
    {
        try
        {
            var psi = new ProcessStartInfo(command, arguments)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false
            };
            var process = Process.Start(psi);
            var output = process?.StandardOutput.ReadToEnd();
            process?.WaitForExit();
            return process?.ExitCode == 0 ? output : null;
        }
        catch
        {
            return null;
        }
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
