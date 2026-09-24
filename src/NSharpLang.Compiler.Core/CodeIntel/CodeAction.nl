namespace NSharpLang.Compiler

import System.Collections.Generic

class CodeAction {
    Title: string
    DiagnosticCode: string
    Edits: List<TextEdit>
    Kind: CodeActionKind
    Safety: FixSafety

    constructor(Title: string, DiagnosticCode: string, Edits: List<TextEdit>) {
        this.Title = Title
        this.DiagnosticCode = DiagnosticCode
        this.Edits = Edits
        this.Kind = CodeActionKind.QuickFix
        this.Safety = FixSafety.Safe
    }

    constructor(Title: string, DiagnosticCode: string, Edits: List<TextEdit>, Kind: CodeActionKind) {
        this.Title = Title
        this.DiagnosticCode = DiagnosticCode
        this.Edits = Edits
        this.Kind = Kind
        this.Safety = FixSafety.Safe
    }

    constructor(Title: string, DiagnosticCode: string, Edits: List<TextEdit>, Safety: FixSafety) {
        this.Title = Title
        this.DiagnosticCode = DiagnosticCode
        this.Edits = Edits
        this.Kind = CodeActionKind.QuickFix
        this.Safety = Safety
    }

    constructor(Title: string, DiagnosticCode: string, Edits: List<TextEdit>, Kind: CodeActionKind, Safety: FixSafety) {
        this.Title = Title
        this.DiagnosticCode = DiagnosticCode
        this.Edits = Edits
        this.Kind = Kind
        this.Safety = Safety
    }
}
