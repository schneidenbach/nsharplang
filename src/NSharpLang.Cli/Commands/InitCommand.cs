using System;
using System.IO;

namespace NSharpLang.Cli.Commands;

public static class InitCommand
{
    public static int Execute(string[] args)
    {
        var options = InitCommandKernels.GetOptionSummary(args);
        if (options.ShowHelp)
        {
            Console.WriteLine(InitCommandKernels.GetHelpText());
            return 0;
        }

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

    static int Error(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}
