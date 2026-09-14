namespace NSharpLang.Compiler.CodeIntelligence

class DiagnosticSummary {
    errorsValue: int
    warningsValue: int
    infoValue: int

    Errors: int {
        get {
            return errorsValue
        }
        set {
            errorsValue = value
        }
    }

    Warnings: int {
        get {
            return warningsValue
        }
        set {
            warningsValue = value
        }
    }

    Info: int {
        get {
            return infoValue
        }
        set {
            infoValue = value
        }
    }

    constructor(Errors: int, Warnings: int, Info: int) {
        errorsValue = Errors
        warningsValue = Warnings
        infoValue = Info
    }
}
