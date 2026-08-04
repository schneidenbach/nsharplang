namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast

// WHAT IT MEANS FOR A CONDITION TO BE A CONDITION — the analyzer's five boolean questions, and the
// one gate that answers all of them.
//
// N# has exactly five places where a program hands the analyzer a value and claims it decides
// something: the `if` condition, the `while` condition, the `for` condition, the ternary's condition
// and a `match` case's guard. Every one of them asked the SAME three-part question and asked it in
// the same order — does this value escape its struct-of-arrays record as a ROW, does it escape as a
// direct COLUMN, and only if neither, is it actually a boolean. `assert` asks nothing of its own,
// there is no `do`/`while` in the language, and the operand rules for `&&`, `||`, `&`, `|` and `!`
// are the OPERATOR family's policy rather than a condition's, so this is the whole set.
//
// THE ESCAPE FLAGS ARE NOT DRIVER-VISIBLE, WHICH IS WHY THE WHOLE GATE LIVES HERE. In all five arms
// the two escape answers were read by nothing except the boolean test that followed them: no arm
// branched on them, none carried them further, none reported through them again. So relaying them
// across the boundary would have been a protocol with no reader — the same finding the diagnostic
// sink's `ErrorCount` and the SoA escape gates produced — and the gate moves into the sink instead.
// Each arm is left with ONE call, and the fact that BOTH escapes are always reported (neither
// short-circuits the other) is this type's invariant rather than something five callers each have to
// remember.
//
// THE FIVE DIFFER IN THREE THINGS AND NOTHING ELSE: the action word the escape reports use ("used as
// an 'if' condition"), the name the mismatch calls the owner ("a 'while' loop"), and — for two of
// them — the TEST and the REPORT SHAPE.
//   * `while`, `for` and the ternary run the plain test (`bool` and nothing else) and the plain
//     report.
//   * `if` runs the same plain test but reports through `ErrorMessageBuilder`, so a developer gets
//     the source line, the underline, the actual and expected type and a conversion hint. It falls
//     back to the plain wording — with `an 'if'` as the owner — when there is no snippet or no file
//     to anchor them to, which is the analyzer's in-memory and generated-source path.
//   * A match guard is measured by ASSIGNABILITY to `bool` rather than by identity with it, so a
//     guard whose type converts to `bool` is accepted where a `while` condition of the same type is
//     not. That difference is deliberate and is preserved exactly; it is also why the guard reports
//     NL505 rather than NL202.
//
// THE TWO SUPPRESSIONS ARE THE SAME IN ALL FIVE, and they are about not stacking a second complaint
// on top of a first: a condition whose type is already `unknown` carries whatever error made it
// unknown, and a condition containing a parser error placeholder never had a real type to begin
// with. The plain reporter applies them after the boolean test; the `if` arm's C# owner applied them
// inside the same `if`, which is the same set in a different place, and they are unified here.
//
// THE ASSIGNABILITY ORACLE IS PASSED IN AT THE CALL rather than held, for the reason the return and
// yield walks record: `Analyzer.cs` rebuilds it when the metadata load context opens and again when
// it is disposed, so an owner constructed once may not keep a reference to it.
public class AnalyzerBooleanConditions {

    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    soaEscapeValue: AnalyzerSoaEscape

    constructor(
        diagnostics: AnalyzerDiagnosticSink,
        spans: AnalyzerDiagnosticSpans,
        soaEscape: AnalyzerSoaEscape) {
        diagnosticsValue = diagnostics
        spansValue = spans
        soaEscapeValue = soaEscape
    }

    // THE `while`, `for` AND TERNARY CONDITIONS. `ownerText` names the construct in the wording ("a
    // 'while' loop"); `actionText` names what the value was about to do in the escape reports ("used
    // as a 'while' condition"). The two are different strings on purpose — the escape wording talks
    // about the value and the mismatch wording talks about the construct.
    public func ReportConditionTypeMismatchIfNeeded(
        condition: Expression,
        ownerText: string,
        actionText: string,
        conditionType: TypeInfo) {
        if EscapedBeforeTheBooleanQuestion(condition, conditionType, actionText) {
            return
        }

        if IsBoolean(conditionType) {
            return
        }

        ReportNotBoolean(condition, ownerText, conditionType)
    }

    // THE `if` CONDITION, which is the only one of the five that earns the rich report. The
    // suppressions are checked BEFORE the span is taken, because taking a span reads the file.
    public func ReportIfConditionTypeMismatchIfNeeded(condition: Expression, conditionType: TypeInfo) {
        if EscapedBeforeTheBooleanQuestion(condition, conditionType, "used as an 'if' condition") {
            return
        }

        if IsBoolean(conditionType) {
            return
        }

        if IsAlreadyExplained(condition, conditionType) {
            return
        }

        span := spansValue.GetExpressionDiagnosticSpan(condition)
        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.TypeMismatch(
                currentFilePath,
                span.Line,
                span.Column,
                sourceSnippet,
                span.Length,
                TypeText(conditionType),
                "bool"))
            return
        }

        diagnosticsValue.Report(
            ErrorCode.TypeMismatch,
            "The condition in an 'if' must be a boolean, but I found '" + TypeText(conditionType) + "'",
            span.Line,
            span.Column,
            null,
            span.Length)
    }

    // A `match` CASE GUARD. Measured by assignability rather than identity, and reported under its
    // own code with its own wording, because a guard is an expression the case is filtered by rather
    // than a construct's condition.
    public func ReportMatchGuardTypeMismatchIfNeeded(
        guardExpression: Expression,
        guardType: TypeInfo,
        assignability: AnalyzerAssignability) {
        if EscapedBeforeTheBooleanQuestion(guardExpression, guardType, "used as a match guard") {
            return
        }

        if assignability.IsAssignable(BuiltInTypes.Bool, guardType) {
            return
        }

        span := spansValue.GetExpressionDiagnosticSpan(guardExpression)
        diagnosticsValue.Report(
            ErrorCode.GuardNotBoolean,
            "A match guard must be a boolean, but this expression is '" + TypeText(guardType) + "'",
            span.Line,
            span.Column,
            null,
            span.Length)
    }

    // BOTH ESCAPES ARE ALWAYS REPORTED. Neither short-circuits the other: a value that is a row view
    // is told so, and the column probe still runs, exactly as the five arms wrote it out by hand.
    // Either answer silences the boolean question, because a value the analyzer has already refused
    // to let leave its record must not ALSO be told it is the wrong type.
    func EscapedBeforeTheBooleanQuestion(
        condition: Expression,
        conditionType: TypeInfo,
        actionText: string): bool {
        escapedAsRow := soaEscapeValue.ReportSoaRowEscapeIfNeeded(condition, conditionType, actionText)
        escapedAsDirectColumn := soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(
            condition,
            actionText)
        if escapedAsRow {
            return true
        }

        return escapedAsDirectColumn
    }

    // THE PLAIN REPORT, shared by `while`, `for`, the ternary and the `if` arm's fallback.
    func ReportNotBoolean(condition: Expression, ownerText: string, conditionType: TypeInfo) {
        if IsAlreadyExplained(condition, conditionType) {
            return
        }

        span := spansValue.GetExpressionDiagnosticSpan(condition)
        diagnosticsValue.Report(
            ErrorCode.TypeMismatch,
            "The condition in " + ownerText + " must be a boolean, but I found '" + TypeText(conditionType) + "'",
            span.Line,
            span.Column,
            null,
            span.Length)
    }

    // A CONDITION THAT ALREADY CARRIES ITS OWN COMPLAINT. `unknown` is what a failed resolution
    // leaves behind, and a parser error placeholder is a name the recovery parser minted for a token
    // it could not read; in both cases the developer has already been told what is wrong and a
    // second report about its type would be noise.
    static func IsAlreadyExplained(condition: Expression, conditionType: TypeInfo): bool {
        if BuiltInTypes.IsUnknown(conditionType) {
            return true
        }

        return AnalyzerParserErrorPlaceholders.ContainsInExpression(condition)
    }

    // IDENTITY WITH `bool`, which is the test four of the five run. It is `BuiltInTypes.Is` and
    // nothing more: no nullable unwrapping, no implicit conversion, no declared-alias resolution —
    // a `bool?` condition is not a boolean condition, and neither is a type with an implicit
    // conversion to one. The `if`/`while`/`for`/ternary arms have always been this strict.
    static func IsBoolean(conditionType: TypeInfo): bool {
        return BuiltInTypes.Is(conditionType, BuiltInTypes.Bool)
    }

    static func TypeText(typeInfo: TypeInfo): string {
        boxed := typeInfo as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }
}
