namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic
import NSharpLang.Compiler

class CompilerErrorSeverityFilter {
    static func Filter(errors: IEnumerable<CompilerError>, severity: ErrorSeverity): List<CompilerError> {
        targetSeverityId := Convert.ToInt32(severity)
        if targetSeverityId < 0 || targetSeverityId > 1 {
            throw new InvalidOperationException("N# diagnostic severity filter kernel rejected the severity.")
        }

        filteredErrors := new List<CompilerError>()

        for error in errors {
            if Convert.ToInt32(error.Severity) == targetSeverityId {
                filteredErrors.Add(error)
            }
        }

        return filteredErrors
    }
}
