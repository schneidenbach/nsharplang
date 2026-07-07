namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import System.IO
import System.Text

public class RemoveCommand {
    public static func Execute(args: string[]): int {
        arguments := RemoveCommandKernels.GetArgumentSummary(args)
        if arguments.ShowHelp {
            print RemoveCommandKernels.GetHelpText()
            return 0
        }

        packageName := arguments.PackageOperand
        if string.IsNullOrWhiteSpace(packageName) {
            return Error(RemoveCommandKernels.GetUsageMessage())
        }

        projectRoot := Environment.CurrentDirectory
        projectYml := Path.Combine(projectRoot, "project.yml")

        if !File.Exists(projectYml) {
            return Error(RemoveCommandKernels.GetMissingProjectFileMessage())
        }

        lines := ReadProjectLines(projectYml)
        packageNameValue := packageName ?? ""
        removed := false

        i := 0
        while i < lines.Count {
            action := RemoveCommandKernels.GetDependencyLineAction(lines[i], packageNameValue)
            if action == RemoveDependencyLineAction.RemoveSingleLine {
                lines.RemoveAt(i)
                removed = true
                break
            }

            if action == RemoveDependencyLineAction.RemoveMappingBlock {
                lines.RemoveAt(i)
                while i < lines.Count {
                    if RemoveCommandKernels.ShouldStopDependencyContinuationLine(lines[i]) {
                        break
                    }

                    lines.RemoveAt(i)
                }

                removed = true
                break
            }

            i = i + 1
        }

        if !removed {
            return Error(RemoveCommandKernels.GetPackageNotFoundMessage(packageNameValue))
        }

        WriteProjectLines(projectYml, lines)
        RestoreCommand.Restore(projectRoot, true)

        print RemoveCommandKernels.GetRemovedMessage(packageNameValue)
        return 0
    }

    static func ReadProjectLines(projectYml: string): List<string> {
        lineArray := File.ReadAllLines(projectYml)
        lines := new List<string>()

        i := 0
        while i < lineArray.Length {
            lines.Add(lineArray[i])
            i = i + 1
        }

        return lines
    }

    static func WriteProjectLines(projectYml: string, lines: List<string>) {
        builder := new StringBuilder()

        i := 0
        while i < lines.Count {
            builder.AppendLine(lines[i])
            i = i + 1
        }

        File.WriteAllText(projectYml, builder.ToString())
    }

    static func Error(message: string): int {
        Console.Error.WriteLine(message)
        return 1
    }
}
