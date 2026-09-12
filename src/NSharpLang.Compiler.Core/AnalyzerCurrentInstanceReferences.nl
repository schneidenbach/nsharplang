namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast


// `this` AND `base` WHERE THERE IS NO CURRENT INSTANCE — NL327.
//
// Both words name the object a member was called on. A static member has no such object, and neither
// does a top-level function, so writing either one there is not a subtle type error: the reference
// has nothing to denote. Until this owner existed the analyzer answered `unknown` and said nothing,
// and the mistake surfaced only as an emission decline with no source position attached to it —
// which is the worst of both, because the reader is told about the compiler instead of about their
// code.
//
// The two arms differ only in the word and in what it names. `base` additionally needs the enclosing
// type to HAVE a base, but that is not this owner's question: every class has one (`System.Object`
// when none is written), and a member the base does not declare is already NL303.
//
// THE TEST HAS TWO HALVES, AND BOTH ARE NEEDED. `this` is bound in a TYPE's scope, which every one of
// its members sees, so the scope stack alone answers only "am I inside a type at all" — false for a
// top-level function's body and true everywhere else. The second half is the open member's own
// `static` modifier, recorded on the ambient context at the member boundary so that a lambda and an
// accessor answer it too (see `AnalyzerAmbientContext.CurrentMemberIsStatic`).
class AnalyzerCurrentInstanceReferences {

    // `this` in an expression position. Answers the enclosing type when there is one, and reports
    // NL327 plus `unknown` when there is not.
    static func ResolveThis(expression: ThisExpression, scopes: AnalyzerScopeStack, ambient: AnalyzerAmbientContext, diagnostics: AnalyzerDiagnosticSink): TypeInfo {
        current := scopes.CurrentTypeScope()
        if current != null && !ambient.CurrentMemberIsStatic {
            return current
        }

        Report(expression.Line, expression.Column, "this", ambient, diagnostics)
        return BuiltInTypes.Unknown
    }

    // `base` in an expression position. Answers the enclosing type's base when there is a current
    // instance, and reports NL327 plus `unknown` when there is not.
    static func ResolveBase(expression: BaseExpression, scopes: AnalyzerScopeStack, ambient: AnalyzerAmbientContext, declarationContext: AnalyzerDeclarationContext, diagnostics: AnalyzerDiagnosticSink): TypeInfo {
        current := scopes.CurrentTypeScope()
        if current != null && !ambient.CurrentMemberIsStatic {
            return declarationContext.ResolveBaseType(current)
        }

        Report(expression.Line, expression.Column, "base", ambient, diagnostics)
        return BuiltInTypes.Unknown
    }

    // The one report, in whichever shape the file allows. The rich builder needs source text to
    // underline; a buffer with none — the unsaved-editor path — still gets the sentence and the
    // advice through the detail-only door, because a diagnostic that vanishes with the snippet would
    // make the editor and the CLI disagree about whether the code compiles.
    static func Report(line: int, column: int, keyword: string, ambient: AnalyzerAmbientContext, diagnostics: AnalyzerDiagnosticSink) {
        memberIsStatic := ambient.CurrentMemberIsStatic
        memberName := ""
        declaration := ambient.CurrentFunction
        if declaration != null {
            memberName = declaration.Name
        }

        sourceSnippet := diagnostics.SourceSnippet(line)
        currentFilePath := diagnostics.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnostics.ReportBuilt(ErrorMessageBuilder.NoCurrentInstance(currentFilePath, line, column, sourceSnippet, keyword, memberName, memberIsStatic))
            return
        }

        diagnostics.Report(ErrorCode.NoCurrentInstance, DetailOnlyMessage(keyword, memberIsStatic), line, column, DetailOnlySuggestion(keyword, memberIsStatic), keyword.Length)
    }

    static func DetailOnlyMessage(keyword: string, memberIsStatic: bool): string {
        if memberIsStatic {
            return "'" + keyword + "' cannot be used in a static member"
        }

        return "'" + keyword + "' cannot be used outside a type"
    }

    static func DetailOnlySuggestion(keyword: string, memberIsStatic: bool): string {
        if memberIsStatic {
            return "Drop `static` from the enclosing member, or use a value it already has instead of `" + keyword + "`."
        }

        return "Move this code into an instance member of a class, or take the object it needs as a parameter."
    }
}
