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
        var options = EnvCommandKernels.GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var outputMode = EnvCommandKernels.GetOutputMode(options.Json);

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

        if (outputMode == EnvOutputModeKind.Json)
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
            Console.WriteLine(EnvCommandKernels.GetTextLine(EnvTextLineKind.NlcVersion, nlcVersion));
            Console.WriteLine(EnvCommandKernels.GetTextLine(EnvTextLineKind.DotnetVersion, dotnetVersion));
            Console.WriteLine(EnvCommandKernels.GetTextLine(EnvTextLineKind.Runtime, runtime));
            Console.WriteLine(EnvCommandKernels.GetTextLine(EnvTextLineKind.Os, os));
            Console.WriteLine(EnvCommandKernels.GetTextLine(EnvTextLineKind.Arch, arch));
            Console.WriteLine(EnvCommandKernels.GetTextLine(EnvTextLineKind.NugetCache, nugetCachePath));
            Console.WriteLine(EnvCommandKernels.GetTextLine(EnvTextLineKind.NsharpBin, nsharpBinPath));
            Console.WriteLine(EnvCommandKernels.GetTextLine(EnvTextLineKind.NsharpPackages, nsharpPackageCachePath));

            if (projectName != null)
            {
                Console.WriteLine();
                Console.WriteLine(EnvCommandKernels.GetTextLine(EnvTextLineKind.Project, projectName));
                Console.WriteLine(EnvCommandKernels.GetTextLine(EnvTextLineKind.Target, targetFramework ?? string.Empty));
                Console.WriteLine(EnvCommandKernels.GetTextLine(EnvTextLineKind.OutputType, outputType ?? string.Empty));
                Console.WriteLine(EnvCommandKernels.GetTextLine(EnvTextLineKind.Sdk, sdk ?? string.Empty));
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

    static int ShowHelp()
    {
        Console.WriteLine(EnvCommandKernels.GetHelpText());

        return 0;
    }
}
