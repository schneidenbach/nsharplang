using System;
using System.IO;

namespace NSharpLang.Cli.Commands;

public static class InitCommand
{
    public static int Execute(string[] args)
    {
        var options = GetOptionSummary(args);
        if (options.ShowHelp)
            return ShowHelp();

        var projectRoot = Directory.GetCurrentDirectory();
        var force = options.Force;
        var name = options.NameOption ?? Path.GetFileName(projectRoot) ?? "Project";
        var type = options.TypeOption ?? "exe";

        if (type != "exe" && type != "library")
            return Error(InitCommandKernels.GetInvalidTypeMessage(type));

        var projectYml = Path.Combine(projectRoot, "project.yml");
        if (File.Exists(projectYml) && !force)
            return Error(InitCommandKernels.GetProjectFileExistsMessage());

        try
        {
            var template = InitCommandKernels.GetProjectYamlText(name, type);
            File.WriteAllText(projectYml, template);
            Console.WriteLine(InitCommandKernels.GetCreatedFileMessage("project.yml"));

            var csprojPath = Path.Combine(projectRoot, $"{name}.csproj");
            if (!File.Exists(csprojPath))
            {
                File.WriteAllText(csprojPath, InitCommandKernels.GetCsprojText());
                Console.WriteLine(InitCommandKernels.GetCreatedFileMessage($"{name}.csproj"));
            }

            if (type == "exe" && Directory.GetFiles(projectRoot, "*.nl").Length == 0)
            {
                var programPath = Path.Combine(projectRoot, "Program.nl");
                File.WriteAllText(programPath, InitCommandKernels.GetProgramSourceText());
                Console.WriteLine(InitCommandKernels.GetCreatedFileMessage("Program.nl"));
            }

            // Generate obj/project.g.props
            RestoreCommand.Restore(projectRoot, quiet: true);

            Console.WriteLine();
            Console.WriteLine(InitCommandKernels.GetSuccessMessage());

            return 0;
        }
        catch (Exception ex)
        {
            return Error(InitCommandKernels.GetFailedMessage(ex.Message));
        }
    }

    internal static InitOptionSummary GetOptionSummary(string[] args)
        => InitCommandKernels.TryGetOptionSummary(args, out var summary)
            ? summary
            : GetOptionSummaryWithCSharp(args);

    // Stage 6 C#-surface-shrink: fallback/oracle only; product init option parsing routes through InitCommandKernels.
    private static InitOptionSummary GetOptionSummaryWithCSharp(string[] args)
        => new(
            GetOptionWithCSharp(args, "--name"),
            GetOptionWithCSharp(args, "--type"),
            ContainsArgWithCSharp(args, "--force"),
            ContainsArgWithCSharp(args, "--help") || ContainsArgWithCSharp(args, "-h") || (args.Length > 0 && args[0] == "help"));

    private static string? GetOptionWithCSharp(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == flag)
                return args[i + 1];
        return null;
    }

    private static bool ContainsArgWithCSharp(string[] args, string value)
    {
        for (var i = 0; i < args.Length; i++)
            if (args[i] == value)
                return true;
        return false;
    }

    static int ShowHelp()
    {
        Console.WriteLine(InitCommandKernels.GetHelpText());

        return 0;
    }

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}
