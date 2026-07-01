namespace NSharpLang.Compiler

import System

class LinterBindingUsageCore {
    static func ShouldReportUnusedVariable(name: string, scopeUsed: bool, externallyUsed: bool): bool {
        if scopeUsed {
            return false
        }

        if externallyUsed {
            return false
        }

        return !IsIntentionallyUnusedName(name)
    }

    static func ShouldReportUnusedParameter(name: string, used: bool): bool {
        if used {
            return false
        }

        return !IsIntentionallyUnusedName(name)
    }

    static func IsIntentionallyUnusedName(name: string): bool {
        if name == "_" {
            return true
        }

        return name.StartsWith("_", StringComparison.Ordinal)
    }

    static func UnusedVariableMessage(name: string): string {
        return "Variable '" + name + "' is declared but never read"
    }

    static func UnusedVariableSuggestion(name: string): string {
        return "If this is intentional, prefix it with '_' to indicate it's unused: '_" + name + "'"
    }

    static func UnusedParameterMessage(name: string, functionName: string): string {
        return "Parameter '" + name + "' in '" + functionName + "' is never read — is it needed?"
    }

    static func UnusedParameterSuggestion(name: string): string {
        return "If the parameter is required by an interface or override, prefix with '_' to suppress this: '_" + name + "'"
    }
}
