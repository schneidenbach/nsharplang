namespace NSharpLang.Cli

import System

public class BatchQueryValidationKernels {
    public static func HasRequiredInput(
        commandKind: BatchQueryCommandKind,
        filePath: string?,
        position: string?,
        query: string?): bool {
        if commandKind == BatchQueryCommandKind.Outline {
            return !string.IsNullOrWhiteSpace(filePath ?? "")
        }

        if commandKind == BatchQueryCommandKind.Doc {
            return !string.IsNullOrWhiteSpace(query ?? "")
        }

        if RequiresFileAndPosition(commandKind) {
            return !string.IsNullOrWhiteSpace(filePath ?? "")
                && !string.IsNullOrWhiteSpace(position ?? "")
        }

        return true
    }

    public static func GetRequiredInputMessage(commandKind: BatchQueryCommandKind): string {
        if commandKind == BatchQueryCommandKind.Outline {
            return BatchQueryKernels.GetOutlineFileRequiredMessage()
        }

        if commandKind == BatchQueryCommandKind.Doc {
            return BatchQueryKernels.GetDocQueryRequiredMessage()
        }

        if RequiresFileAndPosition(commandKind) {
            return BatchQueryKernels.GetFileAndPosRequiredMessage()
        }

        return ""
    }

    public static func GetCommandName(commandKind: BatchQueryCommandKind): string {
        if commandKind == BatchQueryCommandKind.Symbols {
            return "symbols"
        }

        if commandKind == BatchQueryCommandKind.Outline {
            return "outline"
        }

        if commandKind == BatchQueryCommandKind.Diagnostics {
            return "diagnostics"
        }

        if commandKind == BatchQueryCommandKind.Type {
            return "type"
        }

        if commandKind == BatchQueryCommandKind.Inspect {
            return "inspect"
        }

        if commandKind == BatchQueryCommandKind.Definition {
            return "definition"
        }

        if commandKind == BatchQueryCommandKind.References {
            return "references"
        }

        if commandKind == BatchQueryCommandKind.Completions {
            return "completions"
        }

        if commandKind == BatchQueryCommandKind.Doc {
            return "doc"
        }

        return ""
    }

    static func RequiresFileAndPosition(commandKind: BatchQueryCommandKind): bool {
        return commandKind == BatchQueryCommandKind.Type
            || commandKind == BatchQueryCommandKind.Inspect
            || commandKind == BatchQueryCommandKind.Definition
            || commandKind == BatchQueryCommandKind.References
            || commandKind == BatchQueryCommandKind.Completions
    }
}
