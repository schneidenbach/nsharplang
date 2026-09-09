namespace NSharpLang.Cli.Commands

import System
import System.IO

class InitCommand {
    static func Execute(args: string[]): int {
        options := InitCommandKernels.GetOptionSummary(args)
        if options.ShowHelp {
            print InitCommandKernels.GetHelpText()
            return 0
        }

        projectRoot := Environment.CurrentDirectory
        force := options.Force
        name := options.NameOption ?? Path.GetFileName(projectRoot) ?? "Project"
        projectType := options.TypeOption ?? "exe"

        if projectType != "exe" && projectType != "library" {
            return Error(InitCommandKernels.GetInvalidTypeMessage(projectType))
        }

        projectYml := Path.Combine(projectRoot, "project.yml")
        if File.Exists(projectYml) && !force {
            return Error(InitCommandKernels.GetProjectFileExistsMessage())
        }

        try {
            template := InitCommandKernels.GetProjectYamlText(name, projectType)
            File.WriteAllText(projectYml, template)
            print InitCommandKernels.GetCreatedFileMessage("project.yml")

            csprojPath := Path.Combine(projectRoot, name + ".csproj")
            if !File.Exists(csprojPath) {
                File.WriteAllText(csprojPath, InitCommandKernels.GetCsprojText())
                print InitCommandKernels.GetCreatedFileMessage(name + ".csproj")
            }

            if projectType == "exe" && Directory.GetFiles(projectRoot, "*.nl", SearchOption.TopDirectoryOnly).Length == 0 {
                programPath := Path.Combine(projectRoot, "Program.nl")
                File.WriteAllText(programPath, InitCommandKernels.GetProgramSourceText())
                print InitCommandKernels.GetCreatedFileMessage("Program.nl")
            }

            RestoreCommand.Restore(projectRoot, true)

            print ""
            print InitCommandKernels.GetSuccessMessage()

            return 0
        } catch ex: Exception {
            return Error(InitCommandKernels.GetFailedMessage(ex.Message))
        }
    }

    static func Error(message: string): int {
        Console.Error.WriteLine(message)
        return 1
    }
}
