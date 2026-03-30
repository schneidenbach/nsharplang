using System;
using System.IO;
using System.Linq;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

public static class InitCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var projectRoot = Directory.GetCurrentDirectory();
        var force = args.Contains("--force");
        var name = GetOption(args, "--name") ?? Path.GetFileName(projectRoot) ?? "Project";
        var type = GetOption(args, "--type") ?? "exe";

        if (type != "exe" && type != "library")
            return Error($"Invalid type '{type}'. Expected 'exe' or 'library'.");

        var projectYml = Path.Combine(projectRoot, "project.yml");
        if (File.Exists(projectYml) && !force)
            return Error("project.yml already exists. Use --force to overwrite.");

        try
        {
            // Generate project.yml
            var template = ProjectFileParser.GenerateTemplate(name);
            if (type == "library")
            {
                template = template.Replace("outputType: exe", "outputType: library");
                // Remove entry point line — libraries don't have one
                template = string.Join("\n", template.Split('\n')
                    .Where(line => !line.TrimStart().StartsWith("entry:")));
            }
            File.WriteAllText(projectYml, template);
            Console.WriteLine("Created: project.yml");

            // Generate minimal .csproj
            var csprojPath = Path.Combine(projectRoot, $"{name}.csproj");
            if (!File.Exists(csprojPath))
            {
                File.WriteAllText(csprojPath, "<Project Sdk=\"NSharpLang.Sdk\" />\n");
                Console.WriteLine($"Created: {name}.csproj");
            }

            // Generate starter Program.nl if exe and no .nl files exist
            if (type == "exe" && !Directory.GetFiles(projectRoot, "*.nl").Any())
            {
                var programPath = Path.Combine(projectRoot, "Program.nl");
                File.WriteAllText(programPath, "func main() {\n    print \"Hello, N#!\"\n}");
                Console.WriteLine("Created: Program.nl");
            }

            // Generate obj/project.g.props
            RestoreCommand.Restore(projectRoot, quiet: true);

            Console.WriteLine();
            Console.WriteLine("N# project initialized. Run 'nlc build' to compile.");

            return 0;
        }
        catch (Exception ex)
        {
            return Error($"Init failed: {ex.Message}");
        }
    }

    static string? GetOption(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == flag)
                return args[i + 1];
        return null;
    }

    static int ShowHelp()
    {
        Console.WriteLine(@"N# Init

Usage: nlc init [options]

Initialize N# in the current directory. Like 'cargo init' — works in an
existing directory instead of creating a new one.

Options:
  --name <name>   Project name (default: current directory name)
  --type <type>   Output type: exe or library (default: exe)
  --force         Overwrite existing project.yml
  --help, -h      Show this help text

Examples:
  nlc init
  nlc init --name MyLib --type library
  nlc init --force

Exit codes:
  0  Project initialized successfully
  1  Initialization failed");

        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}
