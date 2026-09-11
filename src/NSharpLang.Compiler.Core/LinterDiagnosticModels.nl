namespace NSharpLang.Compiler

struct Location(line: int, column: int, filePath: string? = null) {
    Line: int = line
    Column: int = column
    FilePath: string? = filePath
}

class Diagnostic {
    Code: string
    Message: string
    Location: Location
    Severity: DiagnosticSeverity
    Suggestion: string?
    Length: int

    constructor(Code: string, Message: string, Location: Location, Severity: DiagnosticSeverity, Suggestion: string? = null, Length: int = 1) {
        this.Code = Code
        this.Message = Message
        this.Location = Location
        this.Severity = Severity
        this.Suggestion = Suggestion
        this.Length = Length
    }
}

// WHAT A RULE DECIDED, BEFORE ANYTHING DECIDES WHERE TO PUT IT.
//
// A rule owner answers with one of these or with nothing. It is deliberately NOT a `Diagnostic`:
// a diagnostic carries a `Location` with a file path and a resolved span, and neither of those is
// the rule's to know — the file is the linter's, and the span comes from the source line after the
// rule has chosen a line and column. Keeping the two types apart is what lets a rule be tested by
// asking it a question, with no file on disk and no span resolver in the way.
//
// `Suggestion` is nullable because a rule may have nothing useful to add; every rule that moved
// with this type does have one.
class LinterRuleFinding {
    Code: string
    Message: string
    Suggestion: string?
    Severity: DiagnosticSeverity
    Line: int
    Column: int

    constructor(Code: string, Message: string, Suggestion: string?, Severity: DiagnosticSeverity, Line: int, Column: int) {
        this.Code = Code
        this.Message = Message
        this.Suggestion = Suggestion
        this.Severity = Severity
        this.Line = Line
        this.Column = Column
    }
}
