namespace NSharpLang.Compiler

import System.Collections.Generic

class AnalysisResult {
    errorsValue: List<CompilerError>
    semanticModelValue: SemanticModel
    bindingsValue: BindingMap?

    Errors: List<CompilerError> => errorsValue
    SemanticModel: SemanticModel => semanticModelValue
    Bindings: BindingMap? => bindingsValue
    HasErrors: bool => HasErrorDiagnostics(errorsValue)

    constructor(errors: List<CompilerError>, semanticModel: SemanticModel, bindings: BindingMap?) {
        errorsValue = errors
        semanticModelValue = semanticModel
        bindingsValue = bindings
    }

    static func HasErrorDiagnostics(errors: List<CompilerError>): bool {
        for error in errors {
            if error.Severity == ErrorSeverity.Error {
                return true
            }
        }

        return false
    }
}
