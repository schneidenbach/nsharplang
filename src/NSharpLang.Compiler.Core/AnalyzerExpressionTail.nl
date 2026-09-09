namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast


// WHAT HAPPENS TO EVERY EXPRESSION'S TYPE ONCE THE DISPATCH HAS COMPUTED IT.
//
// The analyzer's expression walk is two things bolted together: a DISPATCH that sends each syntactic
// shape to its owner, and a TAIL that runs after EVERY one of them. The dispatch is mechanical — one
// arm per shape, each handing off whole. The tail is not: it applies null flow, records two facts
// into the semantic model, and then decides, through FOUR ORDERED GUARDS, whether the value the
// expression produced may be used as a value at all.
//
// THE ORDER OF THE FOUR GUARDS IS THE RULE, AND IT IS USER-VISIBLE. An expression can qualify under
// more than one of them; whichever fires first is the diagnostic the developer sees, and the other
// three never run. They are, in order:
//
//   1. A COMPILER-GENERATED SoA OPERATION used as a value. Reported here, with the call shape spelled
//      out, because the operation mutates table storage and is not a delegate.
//   2. AN UNSUPPORTED ARRAY INSTANCE-METHOD REFERENCE on a direct column. Asked of
//      `AnalyzerSoaDirectColumnCalls`, which reports for itself; suppressed while the walk is
//      analysing a CALL's callee, because in that position the reference is the call, not a value.
//   3. A BARE METHOD GROUP that no expected type binds. Asked of `AnalyzerReflectionCallReporter`,
//      which both decides and reports.
//   4. A .NET EVENT touched anywhere other than `on` / `off`. Reported here.
//
// Each of the four returns `Unknown` rather than the computed type, so a rejected value does not go
// on to produce a second, derived complaint about itself.
//
// EVERY GUARD IS OPENED BY AN AMBIENT PERMISSION, AND THE PERMISSIONS ARE NOT SYMMETRIC. Three of
// them (`AllowSyntheticSoaOperationReference`, `AllowUnboundCallableReference`, `AllowEventReference`)
// are permissions the paths that handle these shapes deliberately grant so they can emit their own
// tailored diagnostic instead. The fourth, `AnalyzingCallCallee`, is a POSITION rather than a
// permission — the same distinction `AnalyzerAmbientContext` records for itself.
//
// The two RECORDS that precede the guards are not conditional and happen for every expression,
// including one that is about to be rejected: the semantic model is an IDE surface, and a hover over
// a misused method group should still say what it is. That is why they sit above the guards rather
// than below them.
//
// This owner is NOT rebuilt with the metadata-load-context SCC: everything it holds is constructed
// once. The semantic model is the exception and arrives at `BeginAnalysis`, because the shell `new`s
// one per `Analyze` and a held one would be the previous file's.
class AnalyzerExpressionTail {
    diagnostics: AnalyzerDiagnosticSink
    spans: AnalyzerDiagnosticSpans
    nullFlow: AnalyzerNullFlow
    ambient: AnalyzerAmbientContext
    soaDirectColumnCalls: AnalyzerSoaDirectColumnCalls
    reflectionCallReporter: AnalyzerReflectionCallReporter

    // Recreated per `Analyze` by the shell, so it arrives at `BeginAnalysis` rather than at
    // construction.
    semanticModel: SemanticModel?

    constructor(diagnosticSink: AnalyzerDiagnosticSink, diagnosticSpans: AnalyzerDiagnosticSpans, flow: AnalyzerNullFlow, ambientContext: AnalyzerAmbientContext, directColumnCalls: AnalyzerSoaDirectColumnCalls, callReporter: AnalyzerReflectionCallReporter) {
        diagnostics = diagnosticSink
        spans = diagnosticSpans
        nullFlow = flow
        ambient = ambientContext
        soaDirectColumnCalls = directColumnCalls
        reflectionCallReporter = callReporter
        semanticModel = null
    }

    // One call per analysis, from the reset block, AFTER the semantic model has been recreated.
    func BeginAnalysis(model: SemanticModel) {
        semanticModel = model
    }

    // THE TAIL ITSELF. `expr` is the expression the dispatch just handled and `dispatchedType` is
    // what its owner answered. The result is what the walk returns to its caller.
    func Finish(expr: Expression, dispatchedType: TypeInfo): TypeInfo {
        nullState := nullFlow.GetExpressionNullState(expr, dispatchedType)
        flowType := nullFlow.ApplyNullabilityFlowType(dispatchedType, nullState)

        model := semanticModel
        if model != null {
            model.RecordExpressionType(expr.Line, expr.Column, flowType)
            model.RecordExpressionNullState(expr.Line, expr.Column, nullState)
        }

        ambient.RecordWriteTargetExpressionType(expr, flowType)

        // GUARD 1 — a generated SoA operation used as a value.
        if !ambient.AllowSyntheticSoaOperationReference {
            syntheticSoaOperation := flowType as FunctionTypeInfo
            if syntheticSoaOperation != null && HasSyntheticName(syntheticSoaOperation) && !AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(syntheticSoaOperation) {
                ReportSyntheticSoaOperationUsedAsValue(expr, syntheticSoaOperation)
                return BuiltInTypes.Unknown
            }
        }

        // GUARD 2 — an unsupported array instance-method reference. The owner reports for itself.
        if !ambient.AnalyzingCallCallee && soaDirectColumnCalls.ReportUnsupportedArrayInstanceMethodReferenceIfNeeded(expr, flowType, false) {
            return BuiltInTypes.Unknown
        }

        // GUARD 3 — a bare method group. The reporter both decides and reports.
        if !ambient.AllowUnboundCallableReference && reflectionCallReporter.IsUnboundCallableReference(expr, flowType, ambient.CurrentExpectedType) {
            reflectionCallReporter.ReportMethodGroupUsedAsValue(expr, flowType)
            return BuiltInTypes.Unknown
        }

        // GUARD 4 — a .NET event used as anything but an `on` / `off` target.
        if !ambient.AllowEventReference {
            bareEvent := flowType as ReflectionEventInfo
            if bareEvent != null {
                ReportEventUsedAsValue(expr, bareEvent)
                return BuiltInTypes.Unknown
            }
        }

        return flowType
    }

    // A synthetic name is present AND non-empty. The C# pattern `{ SyntheticName: { Length: > 0 } }`
    // is both tests at once; written out, the null test and the length test are separate because
    // `string.IsNullOrEmpty` is not a narrowing the analyzer follows.
    func HasSyntheticName(functionType: FunctionTypeInfo): bool {
        name := functionType.SyntheticName
        if name == null {
            return false
        }

        return name.Length > 0
    }

    // ----------------------------------------------------------------------------------------------
    // THE TWO REPORTS THIS OWNER MAKES FOR ITSELF
    // ----------------------------------------------------------------------------------------------

    // A generated SoA operation is not a delegate value. The suggestion spells out the CALL the
    // developer probably meant, with `()` when the operation takes nothing and `(...)` otherwise —
    // the parameter list is not rendered because the point is the call, not the signature.
    func ReportSyntheticSoaOperationUsedAsValue(expression: Expression, operation: FunctionTypeInfo) {
        span := spans.GetExpressionDiagnosticSpan(expression)

        // The name is re-bound into a NON-NULLABLE local rather than reassigned in place: an
        // assignment inside the guard is not a narrowing the analyzer follows to the call below.
        candidateName := operation.SyntheticName
        operationName := "operation"
        if candidateName != null && candidateName.Length > 0 {
            operationName = candidateName
        }

        callTarget := RenderSyntheticSoaOperationTarget(expression, operationName)
        callShape := callTarget + "(...)"
        parameterTypes := operation.ParameterTypes
        if parameterTypes != null && parameterTypes.Count == 0 {
            callShape = callTarget + "()"
        }

        diagnostics.Report(ErrorCode.InvalidSyntax, "SoA table generated operation '" + operationName + "' cannot be used as a value", span.Line, span.Column, "Call " + callShape + " directly; generated SoA operations mutate table storage and are not delegate values.", span.Length)
    }

    // WHAT TO CALL THE THING IN THE MESSAGE. A member access renders as its written target; the three
    // transparent wrappers are unwrapped so `(table.add)` reads as `table.add`; anything else falls
    // back to the operation's own name.
    static func RenderSyntheticSoaOperationTarget(expression: Expression, fallbackName: string): string {
        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            return AnalyzerAssignment.RenderEventTarget(memberAccess)
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return RenderSyntheticSoaOperationTarget(parenthesized.Inner, fallbackName)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return RenderSyntheticSoaOperationTarget(checkedExpression.Expression, fallbackName)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return RenderSyntheticSoaOperationTarget(uncheckedExpression.Expression, fallbackName)
        }

        return fallbackName
    }

    // A .NET event may only be touched with `on` / `off`. The suggestion is a WORKING subscription
    // written against the developer's own target, not a description of one.
    func ReportEventUsedAsValue(expr: Expression, eventRef: ReflectionEventInfo) {
        span := spans.GetExpressionDiagnosticSpan(expr)
        target := AnalyzerAssignment.RenderEventTarget(expr)
        diagnostics.Report(ErrorCode.EventRequiresOnOff, "'" + eventRef.Name + "' is a .NET event and can only be used with `on`/`off`", span.Line, span.Column, "Subscribe with `on " + target + " (sender, args) => { ... }`; the result is a subscription you can later pass to `off`.", span.Length)
    }
}
