namespace NSharpLang.Cli.Commands

import System
import System.Collections.Generic

public class CompilerErrorSeverityFilter {
    public static func Filter<T>(errors: IReadOnlyList<T>, severity: object): List<T> {
        targetSeverityId := Convert.ToInt32(severity)
        if targetSeverityId < 0 || targetSeverityId > 1 {
            throw new InvalidOperationException("N# diagnostic severity filter kernel rejected the severity.")
        }

        filteredErrors := new List<T>()

        i := 0
        while i < errors.Count {
            error := errors[i]
            if CompilerErrorSeverityId(error) == targetSeverityId {
                filteredErrors.Add(error)
            }

            i = i + 1
        }

        return filteredErrors
    }

    static func CompilerErrorSeverityId(error: object): int {
        property := error.GetType().GetProperty("Severity")
        if property != null {
            return CompilerErrorSeverityValue(property.GetValue(error))
        }

        field := error.GetType().GetField("Severity")
        if field == null {
            return -1
        }

        return CompilerErrorSeverityValue(field.GetValue(error))
    }

    static func CompilerErrorSeverityValue(rawSeverity: object): int {
        if rawSeverity == null {
            return -1
        }

        return Convert.ToInt32(rawSeverity)
    }
}
