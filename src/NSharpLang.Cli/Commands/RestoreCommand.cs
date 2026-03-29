using System;
using System.IO;
using System.Linq;
using System.Text;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

/// <summary>
/// Generates obj/project.g.props from project.yml using the canonical YAML parser.
/// This is the single projection from YAML config to MSBuild XML properties.
/// </summary>
public static class RestoreCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h"))
        {
            ShowHelp();
            return 0;
        }

        var projectRoot = Directory.GetCurrentDirectory();
        return Restore(projectRoot);
    }

    /// <summary>
    /// Generate obj/project.g.props from project.yml.
    /// Returns 0 on success, 1 on failure.
    /// </summary>
    public static int Restore(string projectRoot, bool quiet = false)
    {
        var projectYmlPath = Path.Combine(projectRoot, "project.yml");
        if (!File.Exists(projectYmlPath))
        {
            if (!quiet)
                Console.Error.WriteLine("No project.yml found. Run 'nlc new <name>' to create a project.");
            return 1;
        }

        try
        {
            var config = ProjectFileParser.Parse(projectYmlPath);
            var projectName = config.Name ?? Path.GetFileName(projectRoot) ?? "Project";

            var objDir = Path.Combine(projectRoot, "obj");
            Directory.CreateDirectory(objDir);

            var outputType = config.OutputType == "exe" ? "Exe" : "Library";
            var baseSdk = config.Sdk ?? "Microsoft.NET.Sdk";

            var sb = new StringBuilder();
            sb.AppendLine(@"<Project xmlns=""http://schemas.microsoft.com/developer/msbuild/2003"">");
            sb.AppendLine(@"  <PropertyGroup>");
            sb.AppendLine($"    <TargetFramework>{config.TargetFramework}</TargetFramework>");
            sb.AppendLine($"    <OutputType>{outputType}</OutputType>");
            sb.AppendLine($"    <_NSharpOriginalOutputType>{outputType}</_NSharpOriginalOutputType>");
            sb.AppendLine($"    <AssemblyName>{projectName}</AssemblyName>");
            sb.AppendLine($"    <NSharpTestFramework>{config.TestFramework}</NSharpTestFramework>");
            sb.AppendLine($"    <_NSharpBaseSdk>{baseSdk}</_NSharpBaseSdk>");
            sb.AppendLine(@"  </PropertyGroup>");
            sb.AppendLine(@"</Project>");

            var propsPath = Path.Combine(objDir, "project.g.props");
            File.WriteAllText(propsPath, sb.ToString(), Encoding.UTF8);

            if (!quiet)
                Console.WriteLine($"Generated obj/project.g.props from project.yml");

            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to restore project configuration: {ex.Message}");
            return 1;
        }
    }

    static void ShowHelp()
    {
        Console.WriteLine(@"N# Restore

Usage: nlc restore

Generates build configuration (obj/project.g.props) from project.yml.
This must be run before 'dotnet build' can work directly.
'nlc build' runs this automatically.

Options:
  -h, --help    Show this help message");
    }
}
