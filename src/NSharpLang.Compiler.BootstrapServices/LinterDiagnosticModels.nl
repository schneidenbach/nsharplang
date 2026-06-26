namespace NSharpLang.Compiler

public struct Location(line: int, column: int, filePath: string? = null) {
    Line: int = line
    Column: int = column
    FilePath: string? = filePath
}

public class Diagnostic {
    Code: string
    Message: string
    Location: Location
    Severity: DiagnosticSeverity
    Suggestion: string?
    Length: int

    constructor(
        Code: string,
        Message: string,
        Location: Location,
        Severity: DiagnosticSeverity,
        Suggestion: string? = null,
        Length: int = 1) {
        this.Code = Code
        this.Message = Message
        this.Location = Location
        this.Severity = Severity
        this.Suggestion = Suggestion
        this.Length = Length
    }
}
