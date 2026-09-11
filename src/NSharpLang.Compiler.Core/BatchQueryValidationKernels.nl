namespace NSharpLang.Cli

enum BatchQueryPayloadShapeKind {
    Invalid = 0,
    RootArray = 1,
    NestedRequestsArray = 2
}

class BatchQueryValidationKernels {
    static func GetPayloadShapeKind(rootIsArray: bool, rootIsObject: bool, hasRequests: bool, requestsIsArray: bool): BatchQueryPayloadShapeKind {
        if rootIsArray {
            return BatchQueryPayloadShapeKind.RootArray
        }

        if rootIsObject && hasRequests && requestsIsArray {
            return BatchQueryPayloadShapeKind.NestedRequestsArray
        }

        return BatchQueryPayloadShapeKind.Invalid
    }

    static func IsRequestItemObject(itemIsObject: bool): bool {
        return itemIsObject
    }

    static func HasRequiredInput(commandKind: BatchQueryCommandKind, filePath: string?, position: string?, query: string?): bool {
        if commandKind == BatchQueryCommandKind.Outline {
            return !string.IsNullOrWhiteSpace(filePath ?? "")
        }

        if commandKind == BatchQueryCommandKind.Doc {
            return !string.IsNullOrWhiteSpace(query ?? "")
        }

        if RequiresFileAndPosition(commandKind) {
            return !string.IsNullOrWhiteSpace(filePath ?? "") && !string.IsNullOrWhiteSpace(position ?? "")
        }

        return true
    }

    static func GetRequiredInputMessage(commandKind: BatchQueryCommandKind): string {
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

    static func GetCommandName(commandKind: BatchQueryCommandKind): string {
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
        return commandKind == BatchQueryCommandKind.Type || commandKind == BatchQueryCommandKind.Inspect || commandKind == BatchQueryCommandKind.Definition || commandKind == BatchQueryCommandKind.References || commandKind == BatchQueryCommandKind.Completions
    }
}
