namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// WHAT THE ANALYZER BELIEVES ABOUT NULL AT A POINT IN THE PROGRAM — the null-state authority, the
// flow type it induces, and the NL905 report.
//
// FIVE QUESTIONS AND ONE DIAGNOSTIC, and they compose in exactly one direction. What is this
// expression's null state? — the syntax answers it outright for a literal, a `new`, an array, a
// lambda and an interpolation, a null-conditional access answers MAYBE-NULL whatever its receiver
// says, and everything else falls back to the recorded fact for its stable path and then to the
// TYPE's default. What is a type's default null state? — `null` is null, a nullable is maybe-null,
// an unknown is unknown, and a REFLECTED type splits on whether the CLR calls it a value type. Is a
// state unsafe to dereference? — null and maybe-null are, oblivious is not. What TYPE does the flow
// state induce? — a not-null nullable reads as its inner type, and nothing else changes. And what
// does an assignment do to the fact? — it invalidates everything derived from the path and records
// the value's own state, defaulting to the TARGET's type when the value's state is unknown.
//
// THE SUPPRESSION FLAG IS PART OF THIS OWNER, NOT OF ITS CALLER. Two places analyse an expression
// while deliberately NOT collapsing a not-null nullable to its inner type — the semantic-model
// preserving read, and an assignment TARGET, which must keep its declared nullability so the
// assignment's own conversion check sees the real type. Both save and restore it around one call,
// so it is ambient state with a stack discipline, and it lives beside the one member that reads it.
//
// THE REPORT LOG IS DELIBERATELY NOT REBUILT WITH THE TOOLSET, for the same reason the callable
// reference log is not: a log rebuilt with its reader would forget what it had already said and
// squiggle the same dereference twice. It is cleared once per analysis, from the same reset block
// that clears the error list.
//
// THIS OWNER RE-ENTERS NOTHING EITHER. It reads the AST and five already-N# collaborators — the
// scope stack's null facts, the declaration context's alias resolution, the span calculator, the
// stable-path facts and the diagnostic sink — and it never asks what an expression's type is. The
// TYPE is always handed in by the caller that already computed it.
class AnalyzerNullFlow {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    reportedDiagnostics: HashSet<ValueTuple<int, int, string, string>>
    suppressFlowTypeValue: bool

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        reportedDiagnostics = new HashSet<ValueTuple<int, int, string, string>>()
        suppressFlowTypeValue = false
    }

    // The ambient "do not collapse a not-null nullable" flag. Its two readers save the previous
    // value and restore it in a `finally`, so this is a stack discipline expressed as a property
    // rather than a field the analyzer reaches into.
    SuppressFlowType: bool => suppressFlowTypeValue

    func SetSuppressFlowType(suppress: bool) {
        suppressFlowTypeValue = suppress
    }

    // One call per analysis, from the same reset block that clears the error list.
    func BeginAnalysis() {
        suppressFlowTypeValue = false
        reportedDiagnostics.Clear()
    }

    // THE FLOW TYPE. A nullable the flow has proved not-null reads as its inner type; everything
    // else reads as itself. Under suppression nothing collapses at all.
    //
    // `Analyzer.cs` also took the EXPRESSION here and never read it; N#'s own NL012 said so, so the
    // dead parameter is not carried across. Nothing about the answer changes — it was already a
    // function of the type and the state alone.
    func ApplyNullabilityFlowType(expressionType: TypeInfo, nullState: NullState): TypeInfo {
        if suppressFlowTypeValue {
            return expressionType
        }

        nullable := expressionType as NullableTypeInfo
        if nullState == NullState.NotNull && nullable != null {
            return nullable.InnerType
        }

        return expressionType
    }

    // THE STATE OF ONE EXPRESSION. The syntactic answers come first and they are unconditional —
    // what a `null` literal or a `new` evaluates to does not depend on any recorded fact. Only after
    // those does the recorded fact for the expression's STABLE PATH get a say, and only after that
    // the type's own default.
    func GetExpressionNullState(expr: Expression, expressionType: TypeInfo): NullState {
        nullLiteral := expr as NullLiteralExpression
        if nullLiteral != null {
            return NullState.Null
        }

        newExpression := expr as NewExpression
        arrayLiteral := expr as ArrayLiteralExpression
        lambda := expr as LambdaExpression
        interpolated := expr as InterpolatedStringExpression
        if newExpression != null || arrayLiteral != null || lambda != null || interpolated != null {
            return NullState.NotNull
        }

        stringLiteral := expr as StringLiteralExpression
        intLiteral := expr as IntLiteralExpression
        floatLiteral := expr as FloatLiteralExpression
        charLiteral := expr as CharLiteralExpression
        boolLiteral := expr as BoolLiteralExpression
        typeOfExpression := expr as TypeOfExpression
        nameofExpression := expr as NameofExpression
        if stringLiteral != null || intLiteral != null || floatLiteral != null || charLiteral != null || boolLiteral != null || typeOfExpression != null || nameofExpression != null {
            return NullState.NotNull
        }

        parenthesized := expr as ParenthesizedExpression
        if parenthesized != null {
            return GetExpressionNullState(parenthesized.Inner, expressionType)
        }

        memberAccess := expr as MemberAccessExpression
        if memberAccess != null && memberAccess.IsNullConditional {
            return NullState.MaybeNull
        }

        indexAccess := expr as IndexAccessExpression
        if indexAccess != null && indexAccess.IsNullConditional {
            return NullState.MaybeNull
        }

        path := AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(expr)
        if path != null && scopesValue.HasNullState(path) {
            return scopesValue.NullStateOrUnknown(path)
        }

        return GetDefaultNullState(expressionType)
    }

    // THE STATE A TYPE IMPLIES WITH NO FLOW FACT AT ALL. The reflected arm is the interesting one:
    // a CLR value type that is not `Nullable<T>` can never be null and is NOT-NULL, while every
    // other reflected type is OBLIVIOUS rather than not-null — external metadata the analyzer has
    // not been told the nullability of must not produce a confident answer in either direction.
    func GetDefaultNullState(typeInfo: TypeInfo): NullState {
        resolved := declarationContextValue.ResolveDeclaredAlias(typeInfo)

        if BuiltInTypes.Is(resolved, BuiltInTypes.Null) {
            return NullState.Null
        }

        nullable := resolved as NullableTypeInfo
        if nullable != null {
            return NullState.MaybeNull
        }

        unknown := resolved as UnknownTypeInfo
        if unknown != null {
            return NullState.Unknown
        }

        reflectionType := resolved as ReflectionTypeInfo
        if reflectionType != null {
            if reflectionType.Type.get_IsValueType() && Nullable.GetUnderlyingType(reflectionType.Type) == null {
                return NullState.NotNull
            }

            return NullState.Oblivious
        }

        return NullState.NotNull
    }

    // UNSAFE means "dereferencing this may throw". OBLIVIOUS is not unsafe: it is the analyzer
    // saying it does not know, and NL905 must never be a guess.
    static func IsUnsafeNullState(state: NullState): bool {
        return state == NullState.Null || state == NullState.MaybeNull
    }

    // THE NL905 REPORT, for a dereference, an index or a call through a receiver the flow says may
    // be null. A null-conditional access is silent by construction — that IS the guard. The log
    // keys on the site AND the path AND the operation, so a chain that dereferences twice at the
    // same position still reports for each distinct path.
    func ReportPossibleNullAccess(receiver: Expression, receiverType: TypeInfo, line: int, column: int, operation: string, isNullConditional: bool) {
        if isNullConditional {
            return
        }

        nullState := GetExpressionNullState(receiver, receiverType)
        if !IsUnsafeNullState(nullState) {
            return
        }

        resolvedPath := AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(receiver)
        path := "this value"
        if resolvedPath != null {
            path = resolvedPath
        }

        key := new ValueTuple<int, int, string, string>(line, column, path, operation)
        if !reportedDiagnostics.Add(key) {
            return
        }

        stateLabel := NullStateFacts.GetDiagnosticText(nullState)
        message := "Possible null " + operation + ": `" + path + "` is " + stateLabel
        if operation == "call" {
            message = "Possible null call: `" + path + "` is " + stateLabel
        }

        suggestion := "Guard with 'if " + path + " == null { return }' or add a fallback before using '" + path + "'."
        if operation == "dereference" {
            suggestion = "Use '?.', add a '??' fallback, guard with 'if " + path + " == null { return }', or explicitly assert after proving '" + path + "' is not null."
        } else if operation == "index" {
            suggestion = "Use '?[', add a '??' fallback, guard with 'if " + path + " == null { return }', or explicitly assert after proving '" + path + "' is not null."
        } else if operation == "call" {
            suggestion = "Guard with 'if " + path + " == null { return }', use '?.' when calling through a member, or explicitly assert " + "after proving '" + path + "' is not null."
        }

        span := spansValue.GetNullReceiverDiagnosticSpan(receiver, path, line, column)
        diagnosticsValue.Report(ErrorCode.PossibleNullAccess, message, span.Line, span.Column, suggestion, span.Length)
    }

    // WHAT AN ASSIGNMENT DOES TO THE FACT. Only a stable path can carry one at all. Everything
    // derived from that path is invalidated first — `a.b.c` stops being known when `a.b` is
    // rewritten — and then the target records the VALUE's state, falling back to the TARGET type's
    // default when the value's own state is unknown.
    func UpdateNullStateAfterAssignment(target: Expression, value: Expression, targetType: TypeInfo, valueType: TypeInfo) {
        path := AnalyzerDiagnosticSpanFacts.TryGetStableNullPath(target)
        if path == null {
            return
        }

        scopesValue.InvalidateNullFactsForAssignment(path)

        valueState := GetExpressionNullState(value, valueType)
        if valueState == NullState.Unknown {
            valueState = GetDefaultNullState(targetType)
        }

        scopesValue.SetNullStateInCurrentScope(path, valueState)
    }
}
