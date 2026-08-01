namespace NSharpLang.Compiler

import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

// THE NL411 REPORT LOG — one anchor, one squiggle.
//
// A method group can be reached more than once for a single written occurrence: the callee walk sees
// it, an argument walk under a different expected type sees it again, and generic inference can
// re-analyse the same node a third time. The reader must see ONE report, so the first one at a given
// anchor wins and the rest are dropped.
//
// ITS LIFETIME IS WHY IT IS ITS OWN OWNER. The reporter that reads it is rebuilt whenever the
// analyzer's toolset changes — the well-known types, and with them the assignability facts, are
// replaced — and a log rebuilt alongside it would forget what it had already said and report the
// same method group twice. So it is constructed ONCE and handed in, exactly as the assignability
// SCC's recursion guard is, and it is never cleared.
//
// The key is `line:column:name`. That spelling is injective because the two leading fields are
// written by `int.ToString()` and can contain no `:`, so the first two separators are unambiguous
// and everything after them is the name, however the name is spelled.
public class AnalyzerCallableReferenceReportLog {

    reported: HashSet<string>

    constructor() {
        reported = new HashSet<string>()
    }

    // True when this anchor and name have NOT been reported before and have now been recorded.
    // False means the caller must stay silent.
    public func TryBeginReport(line: int, column: int, name: string): bool {
        return reported.Add(line.ToString() + ":" + column.ToString() + ":" + name)
    }
}

// WHAT THE ANALYZER SAYS WHEN A CALL INTO REFLECTED .NET CODE DOES NOT BIND, AND WHEN A METHOD IS
// NAMED WHERE A VALUE IS REQUIRED.
//
// The reflection binder answers a single question — does this candidate accept this call — and
// answers it silently: every arm returns `null` rather than reporting, so a group of ten overloads
// does not produce ten reports for the nine that did not fit. That makes this owner the ONLY
// producer of a verdict on a failed reflected call, and the verdict has two shapes:
//
//   * an ordinary failure names the call, the argument count and the argument types, and lists up to
//     eight DISTINCT candidate signatures (NL402);
//   * a failure where one of the arguments is an N# METHOD GROUP names the group instead, because
//     the argument types are not the reader's problem — the delegate SHAPE is, and printing
//     `method group` in a type list tells them nothing.
//
// The method-group arm wins when it applies, so the probe that detects it runs FIRST and the two
// arms are mutually exclusive: one call produces exactly one report.
//
// THE CALLABLE-REFERENCE REPORT (NL411) IS THE SAME FAMILY SEEN FROM THE OTHER SIDE — a method named
// where no delegate is expected at all. Its GUARD travels with it: whether a bare name is an unbound
// callable reference depends on the EXPECTED type at that position, and separating the question from
// the answer is how the two drift. The expected type arrives as an ordinary `TypeInfo?` value, the
// established boundary shape.
//
// THE NL411 DEDUPE IS THE ANALYZER-LIFETIME LOG ABOVE, handed in rather than owned here, because
// this reporter is rebuilt with the toolset and the log must outlive that.
public class AnalyzerReflectionCallReporter {

    scopes: AnalyzerScopeStack
    declarationContext: AnalyzerDeclarationContext
    assignabilityFacts: AnalyzerAssignabilityFacts
    spans: AnalyzerDiagnosticSpans
    diagnostics: AnalyzerDiagnosticSink
    reportLog: AnalyzerCallableReferenceReportLog

    constructor(
        scopeStack: AnalyzerScopeStack,
        declarations: AnalyzerDeclarationContext,
        facts: AnalyzerAssignabilityFacts,
        spanResolver: AnalyzerDiagnosticSpans,
        diagnosticSink: AnalyzerDiagnosticSink,
        callableReferenceLog: AnalyzerCallableReferenceReportLog) {
        scopes = scopeStack
        declarationContext = declarations
        assignabilityFacts = facts
        spans = spanResolver
        diagnostics = diagnosticSink
        reportLog = callableReferenceLog
    }

    // THE VERDICT ON A REFLECTED CALL THAT BOUND TO NOTHING. Chooses the arm and answers `unknown`,
    // which is the type the call expression takes from here: the analysis continues so the rest of
    // the statement is still checked, but nothing downstream may claim to know the result's type.
    public func ReportUnboundCall(
        call: CallExpression,
        candidateMethods: IReadOnlyList<MethodInfo>,
        argTypes: IReadOnlyList<TypeInfo>): TypeInfo {
        methodGroupArgumentName := ""
        if TryGetNSharpMethodGroupArgumentName(call, out methodGroupArgumentName) {
            ReportNoMatchingMethodGroupOverload(call, candidateMethods, methodGroupArgumentName)
            return BuiltInTypes.Unknown
        }

        ReportNoMatchingOverload(call, candidateMethods, argTypes)
        return BuiltInTypes.Unknown
    }

    // NL402 over a reflected candidate list. The signature list is rendered DISTINCT and then capped
    // at eight, in that order, so the cap counts eight DIFFERENT signatures rather than eight
    // candidates — an overload group that differs only in a generic arity would otherwise fill the
    // hint with one repeated line.
    public func ReportNoMatchingOverload(
        call: CallExpression,
        candidateMethods: IReadOnlyList<MethodInfo>,
        argTypes: IReadOnlyList<TypeInfo>) {
        if candidateMethods.Count == 0 {
            return
        }

        functionName := ResolveReflectionCallName(call, candidateMethods)
        span := spans.GetCallDiagnosticSpan(call, functionName)

        argumentTypes := new List<string>()
        typeIndex := 0
        while typeIndex < argTypes.Count {
            argumentTypeObject := argTypes[typeIndex] as object
            argumentTypes.Add(argumentTypeObject.ToString())
            typeIndex = typeIndex + 1
        }

        candidateSignatures := new List<string>()
        candidateIndex := 0
        while candidateIndex < candidateMethods.Count && candidateSignatures.Count < 8 {
            signature := AnalyzerOverloadFacts.FormatReflectionMethodSignature(
                candidateMethods[candidateIndex], call)
            candidateIndex = candidateIndex + 1
            if !candidateSignatures.Contains(signature) {
                candidateSignatures.Add(signature)
            }
        }

        filePath := ""
        snippet := ""
        if TryGetRichContext(span.Line, out filePath, out snippet) {
            diagnostics.ReportBuilt(ErrorMessageBuilder.NoMatchingOverload(
                filePath,
                span.Line,
                span.Column,
                snippet,
                span.Length,
                functionName,
                call.Arguments.Count,
                argumentTypes,
                candidateSignatures))
            return
        }

        diagnostics.Report(
            ErrorCode.NoMatchingOverload,
            "No overload of '" + functionName + "' accepts " + call.Arguments.Count.ToString()
                + " argument(s) with these types",
            span.Line,
            span.Column,
            "Check the argument count and types against the available overloads.",
            span.Length)
    }

    // The method-group arm. There is no rich form here on purpose: the reader's problem is a SHAPE
    // mismatch between a named method and a delegate parameter, and a snippet with a type list would
    // point at the argument types, which are not what failed.
    public func ReportNoMatchingMethodGroupOverload(
        call: CallExpression,
        candidateMethods: IReadOnlyList<MethodInfo>,
        methodGroupArgumentName: string) {
        if candidateMethods.Count == 0 {
            return
        }

        functionName := ResolveReflectionCallName(call, candidateMethods)
        span := spans.GetCallDiagnosticSpan(call, functionName)
        diagnostics.Report(
            ErrorCode.NoMatchingOverload,
            "No overload of '" + functionName + "' matches method group '" + methodGroupArgumentName + "'",
            span.Line,
            span.Column,
            "Check that the method group's parameters and return type match one of the delegate parameter types.",
            span.Length)
    }

    // WHAT TO CALL THE FAILED CALL. What the user WROTE wins — an identifier names itself, a member
    // access names its member — and only a callee with no written name of its own (a call result, an
    // index) falls back to the first candidate's reflected name.
    func ResolveReflectionCallName(call: CallExpression, candidateMethods: IReadOnlyList<MethodInfo>): string {
        targetName := AnalyzerSyntheticCallFacts.GetCallTargetName(call)
        if targetName != null {
            return targetName
        }

        return candidateMethods[0].get_Name()
    }

    // IS ONE OF THE WRITTEN ARGUMENTS AN N#-DECLARED METHOD GROUP? Only a bare identifier can be
    // one — a member access resolves through reflection and a call is already a value — and the
    // FIRST such argument names the report. Two shapes count: an unresolved group of same-named
    // source functions, and a single source function, which is a group of one and is distinguished
    // from a lambda by carrying its declaration's identity.
    func TryGetNSharpMethodGroupArgumentName(call: CallExpression, out name: string): bool {
        name = ""

        index := 0
        while index < call.Arguments.Count {
            argument := call.Arguments[index]
            index = index + 1

            identifier := argument.Value as IdentifierExpression
            if identifier == null {
                continue
            }

            symbol := scopes.LookupSymbol(identifier.Name)
            methodGroup := symbol as NSharpMethodGroupInfo
            if methodGroup != null {
                name = identifier.Name
                return true
            }

            functionType := symbol as FunctionTypeInfo
            if functionType != null && AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(functionType) {
                name = identifier.Name
                return true
            }
        }

        return false
    }

    // THE GUARD ON NL411. A lambda is a value already. A position that EXPECTS a delegate binds the
    // reference rather than rejecting it, and that is the only thing the expected type is consulted
    // for. Everything else that names code without calling it is unbound.
    public func IsUnboundCallableReference(
        expression: Expression,
        candidate: TypeInfo,
        expectedType: TypeInfo?): bool {
        lambda := expression as LambdaExpression
        if lambda != null {
            return false
        }

        if expectedType != null && assignabilityFacts.CanBindCallableReferenceToExpectedType(expectedType) {
            return false
        }

        resolvedType := declarationContext.ResolveDeclaredAlias(candidate)
        return AnalyzerCallableReferenceFacts.IsCallableReferenceType(resolvedType)
    }

    // NL411. The DEDUPE happens before either report shape is built, so the choice of shape can
    // never change how many diagnostics a given anchor produces.
    public func ReportMethodGroupUsedAsValue(expression: Expression, candidate: TypeInfo) {
        span := spans.GetExpressionDiagnosticSpan(expression)
        name := AnalyzerCallableReferenceFacts.GetCallableReferenceName(expression, candidate)
        if !reportLog.TryBeginReport(span.Line, span.Column, name) {
            return
        }

        filePath := ""
        snippet := ""
        if TryGetRichContext(span.Line, out filePath, out snippet) {
            diagnostics.ReportBuilt(ErrorMessageBuilder.MethodGroupUsedAsValue(
                filePath,
                span.Line,
                span.Column,
                snippet,
                span.Length,
                name))
            return
        }

        diagnostics.Report(
            ErrorCode.MethodGroupUsedAsValue,
            "Method '" + name + "' must be called or passed to a delegate",
            span.Line,
            span.Column,
            "Call `" + name + "(...)`, or pass `" + name + "` to a parameter with a delegate type.",
            span.Length)
    }

    // The two values every rich report needs: the analysed file's path and the offending line's
    // source text. Both are read through the sink, so a report's snippet and its span are computed
    // against one resolution of the file's text.
    func TryGetRichContext(line: int, out filePath: string, out snippet: string): bool {
        filePath = ""
        snippet = ""
        resolvedFilePath := diagnostics.CurrentFilePath
        if resolvedFilePath != null {
            filePath = resolvedFilePath
        }

        resolvedSnippet := diagnostics.SourceSnippet(line)
        if resolvedSnippet != null {
            snippet = resolvedSnippet
        }

        return resolvedFilePath != null && resolvedSnippet != null
    }
}
