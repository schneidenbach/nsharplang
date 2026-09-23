namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar


// THE THREE STEPS AN OPERATOR EXPRESSION TAKES, AND ALL THREE ARE WALKS.
//
// Each of them analyses ONE expression and differs only in what is in force around it, and the
// difference is observable in every case:
//   1  the ordinary walk, which leaves everything as it found it.
//   2  the walk with the NULLABILITY FLOW TYPE preserved. Only the left operand of `??` takes it:
//      the whole question `??` asks is whether its left side can be null, and the flow type is
//      exactly the fact that would have been narrowed away before the question was asked.
//   3  the walk inside a FRESH BLOCK SCOPE with a named list of narrowings installed. Only the
//      right operand of `&&` and `||` takes it, and only when the left operand proved something:
//      `x != null && x.Length > 0` is the reason the right side of a conjunction sees a narrower
//      `x` than the surrounding code does. The owner asks for this kind ONLY when the list is
//      non-empty, so the driver never decides whether a scope is wanted.
//
// SEVEN KINDS RETIRED WHEN THE WRITE-TARGET FAMILY BECAME N#. Five of them were WRITE-TARGET REPORTS
// and one was the QUESTION in front of them: they were steps only because the reports lived in
// `Analyzer.cs`, and this owner now calls `AnalyzerWriteTargets` itself. The seventh was the
// CAPTURING walk, which installed a fresh sub-expression table around the operand; the table is now
// an ambient slot, so the bracket is opened and closed by this owner around a kind-1 step exactly as
// the expected-type bracket is elsewhere in the arc. What was a ten-kind protocol with a separate
// decision slot is three kinds and one answer.
//
// `Narrowings` is kind 3's list. The numbering is this walk's own protocol with its own driver and
// starts at 1; the other walks' numbers mean different operations.
class OperatorExpressionRequest {
    Kind: int
    Node: Expression?
    Narrowings: List<FlowNarrowing>?
    Line: int
    Column: int

    constructor(kind: int, node: Expression?, narrowings: List<FlowNarrowing>?, line: int, column: int) {
        Kind = kind
        Node = node
        Narrowings = narrowings
        Line = line
        Column = column
    }
}

// THE WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Form` names which of the two this is — 0 a binary expression, 1 a unary one, and -1 for a node
// that is neither.
//
// `LeftType` and `RightType` are a binary's two operand answers; `OperandType` is a unary's one, and
// `Answer` is the outstanding step's answer before it is filed. The separate DECISION slot this state
// used to carry is gone with the report kinds that needed it: every step is a walk again, so one
// answer slot says everything.
//
// `ExpressionTypes` is the sub-expression capture table a mutating unary opens around its operand,
// `SavedExpressionTypes` is the slot's previous value and `CaptureOpen` says whether the bracket is
// open — which is a separate flag rather than a null test, because the saved value is legitimately
// null whenever this is the outermost write target.
//
// `SavedShiftOperandExpectedType` and `ShiftOperandOpen` are the SECOND bracket, and it is the same
// shape for the same reason: NEITHER operand of a shift takes the surrounding target — the count is
// an `int` and the value is its own promoted type — so the target-typing slot is replaced for each
// of those two steps and put back the instant its answer arrives.
//
// `ResultType` is decided AFTER the steps in every form. Not one operator in either family can say
// what it is worth before its operands have been walked, and the SoA refusals that can overrule the
// answer all run later still.
class OperatorExpressionState {
    formValue: int
    nodeValue: Expression?

    Form: int => formValue
    Node: Expression? => nodeValue

    Phase: int
    Pending: int
    Answer: TypeInfo
    LeftType: TypeInfo
    RightType: TypeInfo
    OperandType: TypeInfo
    ResultType: TypeInfo
    ExpressionTypes: Dictionary<object, TypeInfo>?
    SavedExpressionTypes: Dictionary<object, TypeInfo>?
    CaptureOpen: bool
    SavedShiftOperandExpectedType: TypeInfo?
    ShiftOperandOpen: bool

    constructor(form: int, node: Expression?) {
        formValue = form
        nodeValue = node
        Phase = 0
        Pending = 0
        Answer = BuiltInTypes.Unknown
        ExpressionTypes = null
        SavedExpressionTypes = null
        CaptureOpen = false
        SavedShiftOperandExpectedType = null
        ShiftOperandOpen = false
        LeftType = BuiltInTypes.Unknown
        RightType = BuiltInTypes.Unknown
        OperandType = BuiltInTypes.Unknown
        ResultType = BuiltInTypes.Unknown
    }
}

// WHAT AN OPERATOR MEANS.
//
// TWO ARMS, ONE FAMILY, AND THE REASON THEY ARE ONE SLICE IS MEASURED RATHER THAN ASSERTED. The
// unary and binary arms of the expression walk share four rules outright — the numeric-name reader
// under every promotion table, the integral predicate, the unary promotion table (which the SHIFT
// operator uses to type its result) and the CLR-type resolution under operator-overload lookup —
// so neither arm can move without the other unless the other is left calling back into it.
//
// IT OWNS WHAT EVERY OPERATOR IS WORTH:
//   * that ARITHMETIC over a string is concatenation and over anything else is numeric promotion,
//     that a promotion with no common type is an error rather than a guess, and that a user-declared
//     or runtime operator overload is consulted BEFORE the operands are refused — so `Vec + Vec`
//     type-checks exactly when the IL backend can bind it;
//   * that BITWISE over two booleans is a boolean, over the same flags enum is that enum, and over
//     two integral values is their common type;
//   * that a SHIFT is worth the UNARY promotion of its left operand — not the common type of the
//     two — which is why `byteValue << 1` is an `int` and not a `byte`;
//   * that RELATIONAL and EQUALITY comparisons answer `bool`, that an overload which answers
//     anything else is an error rather than silently that type, and that equality additionally
//     admits null, reference types, flags enums and record structs where relational comparison
//     admits only the primitive numerics;
//   * that `&&` and `||` are booleans whatever their operands were, and that they still SAY so when
//     an operand is not one;
//   * that `??` is worth its RIGHT side, except when that side is a `throw`, in which case it is the
//     left side with its nullability removed — and that a left side which cannot be null is told so;
//   * that `..` is `System.Range` and `^n` is `System.Index`;
//   * that NEGATION, COMPLEMENT and `!` each have their own promotion rule, that a negated integer
//     literal reads the target-typing slot so `value: byte = -1` is refused for the right reason,
//     and that `++`/`--` answer the operand's own type rather than a promotion of it;
//   * and that BOTH operands of a binary and the single operand of a unary are refused when they are
//     SoA row views or direct column values trying to leave their table.
//
// THE ORDER OF THE FOUR BINARY ESCAPE REPORTS IS PART OF THE BEHAVIOUR. They are joined by a
// non-short-circuiting OR: all four always run, so an expression with two escaping operands is told
// about both, and any one of them makes the whole expression `unknown`.
//
// IT IS AN OBJECT because everything it asks is ambient, and it is REBUILT WITH THE METADATA LOAD
// CONTEXT because three of the eleven facts it holds are — the assignability oracle, the CLR type
// conversion and the flow-narrowing extractor are all replaced when the analyzer opens or closes its
// load context, and an owner that captured them once would answer from a disposed context.
class AnalyzerOperatorExpressions {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationsValue: AnalyzerDeclarationContext
    substitutionValue: AnalyzerTypeSubstitution
    assignabilityValue: AnalyzerAssignability
    clrConversionValue: AnalyzerClrTypeConversion
    externalTypesValue: AnalyzerExternalTypeProbe
    soaEscapeValue: AnalyzerSoaEscape
    ambientValue: AnalyzerAmbientContext
    narrowingValue: AnalyzerFlowNarrowing
    writeTargetsValue: AnalyzerWriteTargets

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarations: AnalyzerDeclarationContext, substitution: AnalyzerTypeSubstitution, assignability: AnalyzerAssignability, clrConversion: AnalyzerClrTypeConversion, externalTypes: AnalyzerExternalTypeProbe, soaEscape: AnalyzerSoaEscape, ambient: AnalyzerAmbientContext, narrowing: AnalyzerFlowNarrowing, writeTargets: AnalyzerWriteTargets) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationsValue = declarations
        substitutionValue = substitution
        assignabilityValue = assignability
        clrConversionValue = clrConversion
        externalTypesValue = externalTypes
        soaEscapeValue = soaEscape
        ambientValue = ambient
        narrowingValue = narrowing
        writeTargetsValue = writeTargets
    }

    // THE ENTRY, AND IT DECIDES NOTHING. Neither arm can answer or report before its first operand
    // has been walked. A node that is neither answers `unknown` and takes no steps.
    func Begin(expression: Expression): OperatorExpressionState {
        return new OperatorExpressionState(FormOf(expression), expression)
    }

    // WHICH OF THE TWO THIS NODE IS, read off the NODE rather than off anything carried.
    static func FormOf(expression: Expression): int {
        binaryNode := expression as BinaryExpression
        if binaryNode != null {
            return 0
        }

        unaryNode := expression as UnaryExpression
        if unaryNode != null {
            return 1
        }

        return -1
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished.
    func NextStep(state: OperatorExpressionState): OperatorExpressionRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. A walk that asked for nothing folds in nothing. A null
    // type answer is `unknown` rather than a missing one — the expression walk never answers null,
    // and a walk that saw one would carry it into a report.
    func Supply(state: OperatorExpressionState, answer: TypeInfo?) {
        // THE CAPTURE BRACKET CLOSES THE INSTANT THE ANSWER ARRIVES, not when the next step is asked
        // for: the C# closed it in the `finally` around the walk itself, and a bracket that outlived
        // the walk by even one call would be a slot this family never left open.
        if state.CaptureOpen {
            ambientValue.ExitWriteTargetExpressionTypes(state.SavedExpressionTypes)
            state.SavedExpressionTypes = null
            state.CaptureOpen = false
        }

        // THE SHIFT-OPERAND BRACKET CLOSES ON THE SAME INSTANT AND FOR THE SAME REASON.
        if state.ShiftOperandOpen {
            ambientValue.ExitExpectedType(state.SavedShiftOperandExpectedType)
            state.SavedShiftOperandExpectedType = null
            state.ShiftOperandOpen = false
        }

        pending := state.Pending
        state.Pending = 0

        if pending == 0 {
            return
        }

        if answer != null {
            state.Answer = answer
        } else {
            state.Answer = BuiltInTypes.Unknown
        }
    }

    // WHAT THE WALK ANSWERS, which is what the dispatch hands to its caller.
    func Result(state: OperatorExpressionState): TypeInfo {
        return state.ResultType
    }

    func Advance(state: OperatorExpressionState): OperatorExpressionRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceEntry(state)
        }

        if phase == 1 {
            return AdvanceShortCircuitLeft(state)
        }

        if phase == 2 {
            return AdvanceShortCircuitRight(state)
        }

        if phase == 3 {
            return AdvanceCoalesceLeft(state)
        }

        if phase == 4 {
            return AdvanceCoalesceRight(state)
        }

        if phase == 5 {
            return AdvancePlainLeft(state)
        }

        if phase == 6 {
            return AdvancePlainRight(state)
        }

        if phase == 10 {
            return AdvanceMutatingUnaryEntry(state)
        }

        if phase == 12 {
            return AdvanceUnaryOperand(state)
        }

        state.Phase = 99
        return null
    }

    // THE FORK. A binary splits three ways on its OPERATOR before either operand is walked, because
    // the three groups walk their operands differently: `&&`/`||` install what the left side proved
    // before walking the right, `??` preserves the nullability flow type on the left, and everything
    // else walks both plainly. A unary splits on whether it MUTATES its operand, because only a
    // mutation asks the write-target questions.
    func AdvanceEntry(state: OperatorExpressionState): OperatorExpressionRequest? {
        node := state.Node

        binaryNode := node as BinaryExpression
        if binaryNode != null {
            left := binaryNode.Left
            state.Pending = 1
            if IsShortCircuit(binaryNode.Operator) {
                state.Phase = 1
                return new OperatorExpressionRequest(1, left, null, left.Line, left.Column)
            }

            if binaryNode.Operator == BinaryOperator.NullCoalesce {
                state.Phase = 3
                return new OperatorExpressionRequest(2, left, null, left.Line, left.Column)
            }

            state.Phase = 5

            // A SHIFT'S VALUE OPERAND DOES NOT TAKE THE SURROUNDING TARGET EITHER. C# has four shift
            // operators and each one fixes both of its operand types, so nothing about what the
            // expression is being written into reaches either side. Leaving the slot in place typed
            // `1` in `value: ulong = 1 << 40` as a `ulong` while the backend planned the same shift
            // in 32 bits, and the disagreement surfaced as an NL103 about the initializer rather than
            // as a sentence about the shift. Cleared, the shift is an `int` on both sides and the
            // mismatch is an ordinary assignment error the reader can act on — write `1UL << 40`.
            if IsShift(binaryNode.Operator) {
                state.SavedShiftOperandExpectedType = ambientValue.EnterExpectedType(null)
                state.ShiftOperandOpen = true
            }

            return new OperatorExpressionRequest(1, left, null, left.Line, left.Column)
        }

        unaryNode := node as UnaryExpression
        if unaryNode != null {
            operand := unaryNode.Operand
            state.Pending = 1
            if IsIncrementOrDecrement(unaryNode.Operator) {
                state.Pending = 0
                state.Phase = 10
                return null
            }

            state.Phase = 12
            return new OperatorExpressionRequest(1, operand, null, operand.Line, operand.Column)
        }

        state.Phase = 99
        return null
    }

    // THE LEFT SIDE OF `&&` OR `||` HAS ANSWERED, AND WHAT IT PROVED IS INSTALLED FOR THE RIGHT.
    // `&&` installs the THEN facts and `||` the ELSE facts, which is the whole difference between
    // them here: a conjunction's right side runs only when the left was true, a disjunction's only
    // when it was false. A left side that proved nothing gets the ordinary walk rather than an empty
    // scope, so the scope stack is not disturbed by a comparison that narrowed nothing.
    func AdvanceShortCircuitLeft(state: OperatorExpressionState): OperatorExpressionRequest? {
        binaryNode := state.Node as BinaryExpression
        if binaryNode == null {
            state.Phase = 99
            return null
        }

        state.LeftType = state.Answer
        split := narrowingValue.ExtractFlowNarrowings(binaryNode.Left)
        narrowings := split.Then
        if binaryNode.Operator == BinaryOperator.Or {
            narrowings = split.Else
        }

        right := binaryNode.Right
        state.Pending = 1
        state.Phase = 2
        if narrowings.Count > 0 {
            return new OperatorExpressionRequest(3, right, narrowings, right.Line, right.Column)
        }

        return new OperatorExpressionRequest(1, right, null, right.Line, right.Column)
    }

    // `&&` AND `||` ARE BOOLEANS. Both operands are measured for escape first, and neither operator
    // has a promotion rule of its own — the answer is `bool` whatever the operands turned out to be,
    // and the report is about the operands rather than about the result.
    func AdvanceShortCircuitRight(state: OperatorExpressionState): OperatorExpressionRequest? {
        binaryNode := state.Node as BinaryExpression
        if binaryNode == null {
            state.Phase = 99
            return null
        }

        state.RightType = state.Answer
        state.Phase = 99
        if OperandsEscaped(binaryNode, state.LeftType, state.RightType) {
            state.ResultType = BuiltInTypes.Unknown
            return null
        }

        state.ResultType = LogicalOperatorResult(state.LeftType, state.RightType, binaryNode)
        return null
    }

    // THE LEFT SIDE OF `??` HAS ANSWERED. Its right side is walked plainly: the fallback value is an
    // ordinary expression and nothing about the left side narrows it.
    func AdvanceCoalesceLeft(state: OperatorExpressionState): OperatorExpressionRequest? {
        binaryNode := state.Node as BinaryExpression
        if binaryNode == null {
            state.Phase = 99
            return null
        }

        state.LeftType = state.Answer
        right := binaryNode.Right
        state.Pending = 1
        state.Phase = 4
        return new OperatorExpressionRequest(1, right, null, right.Line, right.Column)
    }

    func AdvanceCoalesceRight(state: OperatorExpressionState): OperatorExpressionRequest? {
        binaryNode := state.Node as BinaryExpression
        if binaryNode == null {
            state.Phase = 99
            return null
        }

        state.RightType = state.Answer
        state.Phase = 99
        if OperandsEscaped(binaryNode, state.LeftType, state.RightType) {
            state.ResultType = BuiltInTypes.Unknown
            return null
        }

        state.ResultType = NullCoalesceResult(state.LeftType, state.RightType, binaryNode)
        return null
    }

    // THE LEFT SIDE HAS ANSWERED AND THE RIGHT ONE IS WALKED — PLAINLY FOR EVERY OPERATOR BUT TWO.
    //
    // A SHIFT'S COUNT IS AN `int` AND NOTHING ELSE, whatever the expression around it is being
    // written into. C# has exactly four shift operators and every one of them takes `int` on the
    // right (§12.11); the LEFT operand alone decides the result. N# target-types a suffixless
    // integer literal from the ambient slot, and that slot is still holding the ENCLOSING target
    // when the count is reached — so `okWords[i >> 6] | (1UL << (i & 63))` typed `63` as `ulong`,
    // made `i & 63` an `int` against a `ulong`, and reported NL202 about a mask idiom that is
    // correct in every language with shifts. The slot is replaced with `int` for the count's walk
    // and restored the instant its answer arrives.
    func AdvancePlainLeft(state: OperatorExpressionState): OperatorExpressionRequest? {
        binaryNode := state.Node as BinaryExpression
        if binaryNode == null {
            state.Phase = 99
            return null
        }

        state.LeftType = state.Answer
        right := binaryNode.Right
        state.Pending = 1
        state.Phase = 6
        if IsShift(binaryNode.Operator) {
            state.SavedShiftOperandExpectedType = ambientValue.EnterExpectedType(BuiltInTypes.Int)
            state.ShiftOperandOpen = true
        }

        return new OperatorExpressionRequest(1, right, null, right.Line, right.Column)
    }

    // BOTH OPERANDS ARE KNOWN AND THE OPERATOR CLASS DECIDES. Six classes, and the seventh — the
    // range operator — is the only binary whose answer does not depend on its operands at all.
    func AdvancePlainRight(state: OperatorExpressionState): OperatorExpressionRequest? {
        binaryNode := state.Node as BinaryExpression
        if binaryNode == null {
            state.Phase = 99
            return null
        }

        state.RightType = state.Answer
        state.Phase = 99
        if OperandsEscaped(binaryNode, state.LeftType, state.RightType) {
            state.ResultType = BuiltInTypes.Unknown
            return null
        }

        state.ResultType = PlainOperatorResult(state.LeftType, state.RightType, binaryNode)
        return null
    }

    static func IsShift(op: BinaryOperator): bool {
        return op == BinaryOperator.LeftShift || op == BinaryOperator.RightShift
    }

    func PlainOperatorResult(left: TypeInfo, right: TypeInfo, binaryNode: BinaryExpression): TypeInfo {
        op := binaryNode.Operator
        liftedResult: TypeInfo = BuiltInTypes.Unknown
        if TryLiftedBinaryResult(op, left, right, out liftedResult) {
            return liftedResult
        }

        if IsArithmetic(op) {
            return ArithmeticResult(left, right, binaryNode)
        }

        if op == BinaryOperator.BitwiseAnd || op == BinaryOperator.BitwiseOr || op == BinaryOperator.BitwiseXor {
            return BitwiseResult(left, right, binaryNode)
        }

        if op == BinaryOperator.LeftShift || op == BinaryOperator.RightShift {
            return ShiftResult(left, right, binaryNode)
        }

        if op == BinaryOperator.Equal || op == BinaryOperator.NotEqual {
            return EqualityResult(left, right, binaryNode)
        }

        if IsRelational(op) {
            return RelationalResult(left, right, binaryNode)
        }

        if op == BinaryOperator.Range {
            return RangeType()
        }

        return BuiltInTypes.Unknown
    }

    // THE `x += y` DOOR. The compound-assignment rule builds a SYNTHETIC binary node over the target
    // and the value and asks what that operator would be worth; only the four true arithmetic forms
    // have an answer, because `%=` is not a compound assignment the language admits. This is the one
    // entry into this owner that is not a walk, and it exists because the assignment arm has not
    // moved yet.
    func CompoundAssignmentOperatorResult(binaryOperator: BinaryOperator, targetType: TypeInfo, valueType: TypeInfo, operatorExpression: BinaryExpression): TypeInfo {
        if binaryOperator == BinaryOperator.Add || binaryOperator == BinaryOperator.Subtract || binaryOperator == BinaryOperator.Multiply || binaryOperator == BinaryOperator.Divide {
            liftedCompound: TypeInfo = BuiltInTypes.Unknown
            if TryLiftedBinaryResult(binaryOperator, targetType, valueType, out liftedCompound) {
                return liftedCompound
            }

            return ArithmeticResult(targetType, valueType, operatorExpression)
        }

        return BuiltInTypes.Unknown
    }

    // ALL FOUR ESCAPE REPORTS RUN, AND NONE OF THEM STOPS ANOTHER. The host wrote this as a
    // non-short-circuiting `|` over four calls, which is what makes an expression whose BOTH sides
    // are row views produce two reports rather than one; reproducing it with `||` would have been a
    // silent behaviour change no contract about a single operand could catch.
    func OperandsEscaped(binaryNode: BinaryExpression, leftType: TypeInfo, rightType: TypeInfo): bool {
        leftRow := soaEscapeValue.ReportSoaRowEscapeIfNeeded(binaryNode.Left, leftType, "used as an operator operand")
        rightRow := soaEscapeValue.ReportSoaRowEscapeIfNeeded(binaryNode.Right, rightType, "used as an operator operand")
        leftColumn := soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(binaryNode.Left, "used as an operator operand")
        rightColumn := soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(binaryNode.Right, "used as an operator operand")
        return leftRow || rightRow || leftColumn || rightColumn
    }

    // `??` IS WORTH ITS RIGHT SIDE — the fallback is what the expression evaluates to when the left
    // was null, and in N# `T? ?? T` is `T`. The one exception is a `throw` on the right: nothing
    // comes back from it, so the expression is worth the left side with its nullability removed.
    func NullCoalesceResult(leftType: TypeInfo, rightType: TypeInfo, expression: BinaryExpression): TypeInfo {
        ReportNullCoalesceLeftOperandIfNeeded(expression, leftType)

        throwNode := expression.Right as ThrowExpression
        if throwNode != null {
            return NonNullable(leftType)
        }

        return rightType
    }

    // A LEFT SIDE THAT CANNOT BE NULL IS TOLD SO, because `??` on it is dead code the programmer
    // meant something else by.
    func ReportNullCoalesceLeftOperandIfNeeded(expression: BinaryExpression, leftType: TypeInfo) {
        if CanBeNull(leftType) {
            return
        }

        span := spansValue.GetExpressionDiagnosticSpan(expression.Left)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "The left side of '??' has type '" + TypeText(leftType) + "', which can't be null", span.Line, span.Column, "Use the value directly, or make the left side nullable before using '??'.", span.Length)
    }

    func CanBeNull(candidate: TypeInfo): bool {
        resolved := declarationsValue.ResolveDeclaredAlias(candidate)
        if BuiltInTypes.IsUnknown(resolved) {
            return true
        }

        genericType := resolved as GenericTypeInfo
        if genericType != null {
            return true
        }

        nullableType := resolved as NullableTypeInfo
        if nullableType != null {
            return true
        }

        if AnalyzerConversionFacts.IsReferenceType(resolved) {
            return true
        }

        // A REFLECTED `Nullable<T>` is the fifth door, and it is not the same as a declared `T?`:
        // an imported member typed `int?` arrives as a reflection type whose underlying type is what
        // says it can be null.
        reflection := resolved as ReflectionTypeInfo
        return reflection != null && Nullable.GetUnderlyingType(reflection.Type) != null
    }

    func NonNullable(candidate: TypeInfo): TypeInfo {
        nullableType := declarationsValue.ResolveDeclaredAlias(candidate) as NullableTypeInfo
        if nullableType != null {
            return nullableType.InnerType
        }

        return candidate
    }

    // ARITHMETIC, AND ITS FIRST RULE IS NOT ARITHMETIC AT ALL. `+` with a string on EITHER side is
    // concatenation and answers `string`, which is why the numeric checks below never see it.
    //
    // An `unknown` operand is not an error: something has already been reported about it and a
    // second complaint about the operator would be noise.
    //
    // AN OPERATOR OVERLOAD IS CONSULTED BEFORE THE OPERANDS ARE REFUSED, never after a successful
    // promotion — so a user type with `operator +` works and `int + int` never goes looking for one.
    func ArithmeticResult(left: TypeInfo, right: TypeInfo, expression: BinaryExpression): TypeInfo {
        if expression.Operator == BinaryOperator.Add {
            if IsStringType(left) || IsStringType(right) {
                return BuiltInTypes.String
            }
        }

        if BuiltInTypes.IsUnknown(left) || BuiltInTypes.IsUnknown(right) {
            return BuiltInTypes.Unknown
        }

        if !IsNumericType(left) || !IsNumericType(right) {
            overloadResult: TypeInfo = BuiltInTypes.Unknown
            if TryResolveBinaryOperatorOverload(expression.Operator, left, right, out overloadResult) {
                return overloadResult
            }

            leftIsWrong := !IsNumericType(left)
            rightIsWrong := !IsNumericType(right)
            span := spansValue.GetBinaryOperandDiagnosticSpan(expression, leftIsWrong, rightIsWrong)
            opText := OperatorFacts.GetBinaryText(expression.Operator)
            sideText := SideText(left, right, leftIsWrong, rightIsWrong)
            diagnosticsValue.Report(ErrorCode.TypeMismatch, "The '" + opText + "' operator doesn't work with '" + TypeText(left) + "' and '" + TypeText(right) + "' — both sides need numeric values, but " + sideText, span.Line, span.Column, "Use numeric operands, convert the non-numeric value, or choose an operator that supports this type.", span.Length)
            return BuiltInTypes.Unknown
        }

        widened := WiderType(left, right)
        if widened == null {
            constantWidened := ConstantPromotedType(left, right, expression)
            if constantWidened != null {
                return constantWidened
            }

            if TryReportNoUnsignedCommonType(expression, left, right) {
                return BuiltInTypes.Unknown
            }

            ReportNoCommonType(expression, left, right)
            return BuiltInTypes.Unknown
        }

        return widened
    }

    // BITWISE, WHICH IS THREE OPERATORS OVER THREE DIFFERENT DOMAINS. Two booleans answer `bool`,
    // the SAME flags enum answers that enum, and two integral values answer their common type. The
    // enum rule is identity on the declaration, not merely "both are enums": `Colours | Sizes` is
    // not a flags combination and is refused.
    func BitwiseResult(left: TypeInfo, right: TypeInfo, expression: BinaryExpression): TypeInfo {
        if BuiltInTypes.IsUnknown(left) || BuiltInTypes.IsUnknown(right) {
            return BuiltInTypes.Unknown
        }

        if BuiltInTypes.Is(left, BuiltInTypes.Bool) && BuiltInTypes.Is(right, BuiltInTypes.Bool) {
            return BuiltInTypes.Bool
        }

        if IsSameBitwiseEnumType(left, right) {
            return left
        }

        if IsIntegralType(left) && IsIntegralType(right) {
            widened := WiderType(left, right)
            if widened != null {
                return widened
            }

            constantWidened := ConstantPromotedType(left, right, expression)
            if constantWidened != null {
                return constantWidened
            }

            if TryReportNoUnsignedCommonType(expression, left, right) {
                return BuiltInTypes.Unknown
            }

            ReportBinaryOperandMismatch(expression, left, right, "both sides need compatible integral values")
            return BuiltInTypes.Unknown
        }

        overloadResult: TypeInfo = BuiltInTypes.Unknown
        if TryResolveBinaryOperatorOverload(expression.Operator, left, right, out overloadResult) {
            return overloadResult
        }

        ReportBinaryOperandMismatch(expression, left, right, "both sides need integral values, or both sides need booleans")
        return BuiltInTypes.Unknown
    }

    // A SHIFT IS WORTH THE UNARY PROMOTION OF ITS LEFT OPERAND. The shift COUNT does not participate
    // in the result at all — `byteValue << longCount` is an `int`, not a `long` — which is the one
    // place in this family where the two operands are not symmetric.
    func ShiftResult(left: TypeInfo, right: TypeInfo, expression: BinaryExpression): TypeInfo {
        if BuiltInTypes.IsUnknown(left) || BuiltInTypes.IsUnknown(right) {
            return BuiltInTypes.Unknown
        }

        if IsIntegralType(left) && IsIntegralType(right) {
            promoted := UnaryNumericPromotionType(left)
            if promoted != null {
                return promoted
            }

            return BuiltInTypes.Unknown
        }

        overloadResult: TypeInfo = BuiltInTypes.Unknown
        if TryResolveBinaryOperatorOverload(expression.Operator, left, right, out overloadResult) {
            return overloadResult
        }

        ReportBinaryOperandMismatch(expression, left, right, "the left side needs an integral value, and the shift count needs an integral value")
        return BuiltInTypes.Unknown
    }

    // A COMPARISON ANSWERS `bool` OR NOTHING. An overload is consulted FIRST — before the primitive
    // rule, unlike arithmetic, where it is consulted last — because a user type that defines `<` has
    // said what comparing it means and the primitive rule has nothing to say about it. An overload
    // that answers something other than `bool` is an ERROR rather than that type: a comparison
    // operator is a predicate by definition.
    func RelationalResult(left: TypeInfo, right: TypeInfo, expression: BinaryExpression): TypeInfo {
        if BuiltInTypes.IsUnknown(left) || BuiltInTypes.IsUnknown(right) {
            return BuiltInTypes.Unknown
        }

        overloadResult: TypeInfo = BuiltInTypes.Unknown
        if TryResolveBinaryOperatorOverload(expression.Operator, left, right, out overloadResult) {
            return ComparisonOverloadResult(expression, left, right, overloadResult, "comparison operators must return 'bool'")
        }

        if !IsPrimitiveRelationalType(left) || !IsPrimitiveRelationalType(right) {
            leftIsWrong := !IsPrimitiveRelationalType(left)
            rightIsWrong := !IsPrimitiveRelationalType(right)
            span := spansValue.GetBinaryOperandDiagnosticSpan(expression, leftIsWrong, rightIsWrong)
            opText := OperatorFacts.GetBinaryText(expression.Operator)
            sideText := SideText(left, right, leftIsWrong, rightIsWrong)
            diagnosticsValue.Report(ErrorCode.TypeMismatch, "The '" + opText + "' operator doesn't work with '" + TypeText(left) + "' and '" + TypeText(right) + "' — both sides need primitive numeric values or a comparison operator overload, but " + sideText, span.Line, span.Column, "Use primitive numeric operands, convert the non-numeric value, or define an operator overload for this type.", span.Length)
            return BuiltInTypes.Unknown
        }

        if WiderType(left, right) == null {
            if ConstantPromotedType(left, right, expression) != null {
                return BuiltInTypes.Bool
            }

            if TryReportNoUnsignedCommonType(expression, left, right) {
                return BuiltInTypes.Unknown
            }

            ReportNoCommonType(expression, left, right)
            return BuiltInTypes.Unknown
        }

        return BuiltInTypes.Bool
    }

    // EQUALITY ADMITS FOUR THINGS RELATIONAL COMPARISON DOES NOT: null on either side, two reference
    // values, the same flags enum, and the same record struct. Everything else it admits is the
    // primitive rule with booleans added — `true == false` compares and `true < false` does not.
    func EqualityResult(left: TypeInfo, right: TypeInfo, expression: BinaryExpression): TypeInfo {
        if BuiltInTypes.IsUnknown(left) || BuiltInTypes.IsUnknown(right) {
            return BuiltInTypes.Unknown
        }

        overloadResult: TypeInfo = BuiltInTypes.Unknown
        if TryResolveBinaryOperatorOverload(expression.Operator, left, right, out overloadResult) {
            return ComparisonOverloadResult(expression, left, right, overloadResult, "equality operators must return 'bool'")
        }

        if TryReportNullComparisonWithValueType(expression, left, right) {
            return BuiltInTypes.Unknown
        }

        if CanCompareWithEqualityOperator(left, right) {
            return BuiltInTypes.Bool
        }

        if ConstantPromotedType(left, right, expression) != null {
            return BuiltInTypes.Bool
        }

        if TryReportNoUnsignedCommonType(expression, left, right) {
            return BuiltInTypes.Unknown
        }

        span := spansValue.GetBinaryOperandDiagnosticSpan(expression, true, true)
        opText := OperatorFacts.GetBinaryText(expression.Operator)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "The '" + opText + "' operator doesn't work with '" + TypeText(left) + "' and '" + TypeText(right) + "' — equality needs compatible primitive values, reference values, null, record structs, or an equality operator overload", span.Line, span.Column, "Use matching comparable operands, compare to null, convert explicitly, or define an equality operator for this type.", span.Length)
        return BuiltInTypes.Unknown
    }

    // A NULL COMPARISON THAT CANNOT BE NULL, WHERE THE TYPE IS THE PROOF.
    //
    // `CanCompareWithEqualityOperator` answers TRUE the moment either side is `null`, which is right
    // for every reference and nullable operand and wrong for a value-typed one: `count != null` where
    // `count: int` typed as `bool`, reached the backend, and died there as
    // `NL103 … Declined at emit.if.condition` — a sentence about the compiler's internals for a
    // mistake the type system can name. The LINTER already reports the LITERAL half of this shape as
    // NL003 (`3 == null`), and it cannot report this half, because it has no types. This is that
    // rule's other half, stated where the types are, in the linter's own words.
    //
    // The operand test is `IsDefinitelyNonNullableValueType`, a POSITIVE predicate: a bare type
    // parameter, a constructed generic, a nullable and an unresolved type all answer false and stay
    // silent, because reporting on `T == null` inside a generic function would accuse correct code.
    // An operator overload is resolved BEFORE this is asked, so a type that defines its own `==`
    // against null keeps it.
    func TryReportNullComparisonWithValueType(expression: BinaryExpression, left: TypeInfo, right: TypeInfo): bool {
        resolvedLeft := declarationsValue.ResolveDeclaredAlias(left)
        resolvedRight := declarationsValue.ResolveDeclaredAlias(right)

        valueSide := resolvedLeft
        leftIsNull := BuiltInTypes.Is(resolvedLeft, BuiltInTypes.Null)
        rightIsNull := BuiltInTypes.Is(resolvedRight, BuiltInTypes.Null)
        if leftIsNull == rightIsNull {
            return false
        }

        valueExpression := expression.Left
        if leftIsNull {
            valueSide = resolvedRight
            valueExpression = expression.Right
        }

        // THE PARTITION, READ FROM THE ONE PLACE THAT STATES IT. A literal operand is the LINTER's
        // NL003 — `3 == null` needs no types to be wrong — and reporting it here too would put two
        // codes carrying the same sentence on one line.
        if NullComparisonFacts.LinterOwnsOperand(valueExpression) {
            return false
        }

        if !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(valueSide) {
            return false
        }

        // The squiggle goes under the OPERAND that cannot be null, never under the whole comparison
        // or under the `null` — the same choice NL003 makes for the literal half.
        span := spansValue.GetBinaryOperandDiagnosticSpan(expression, !leftIsNull, leftIsNull)
        typeText := TypeText(valueSide)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "This null check is unnecessary — '" + typeText + "' is a value type and can never be null", span.Line, span.Column, "Remove the null check. If the value really can be absent, declare it as '" + typeText + "?'.", span.Length)
        return true
    }

    // THE SHARED TAIL OF BOTH COMPARISON CLASSES. `IsAssignable` rather than identity, because an
    // overload declared to return a type with an implicit conversion to `bool` still yields a
    // comparison the backend can bind.
    func ComparisonOverloadResult(expression: BinaryExpression, left: TypeInfo, right: TypeInfo, overloadResult: TypeInfo, requirement: string): TypeInfo {
        if assignabilityValue.IsAssignable(BuiltInTypes.Bool, overloadResult) {
            return BuiltInTypes.Bool
        }

        span := AnalyzerDiagnosticSpanFacts.GetBinaryOperatorDiagnosticSpan(expression)
        opText := OperatorFacts.GetBinaryText(expression.Operator)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "The '" + opText + "' operator on '" + TypeText(left) + "' and '" + TypeText(right) + "' returns '" + TypeText(overloadResult) + "', but " + requirement, span.Line, span.Column, "Change the operator overload to return bool.", span.Length)
        return BuiltInTypes.Unknown
    }

    // `&&` AND `||` ARE BOOLEANS EVEN WHEN THEIR OPERANDS ARE NOT. The report fires and the answer
    // is STILL `bool` — deliberately, because everything downstream of a condition wants a boolean
    // and cascading `unknown` out of a mistyped operand would silence the rules that follow.
    func LogicalOperatorResult(left: TypeInfo, right: TypeInfo, expression: BinaryExpression): TypeInfo {
        if BuiltInTypes.IsUnknown(left) || BuiltInTypes.IsUnknown(right) {
            return BuiltInTypes.Unknown
        }

        if !BuiltInTypes.Is(left, BuiltInTypes.Bool) || !BuiltInTypes.Is(right, BuiltInTypes.Bool) {
            leftIsWrong := !BuiltInTypes.Is(left, BuiltInTypes.Bool)
            rightIsWrong := !BuiltInTypes.Is(right, BuiltInTypes.Bool)
            span := spansValue.GetBinaryOperandDiagnosticSpan(expression, leftIsWrong, rightIsWrong)
            opText := OperatorFacts.GetBinaryText(expression.Operator)
            sideText := SideText(left, right, leftIsWrong, rightIsWrong)
            if IsLiftedBoolOperand(left) || IsLiftedBoolOperand(right) {
                diagnosticsValue.Report(ErrorCode.TypeMismatch, "Both sides of '" + opText + "' must be booleans, but " + sideText + " — a 'bool?' can be absent, and '" + opText + "' has to decide whether to evaluate its right side before it knows", span.Line, span.Column, "Say what an absent value means first: 'x == true' is true only when the value is present and true, 'x != false' also accepts an absent one, and 'x ?? false' supplies a default. The non-short-circuiting '" + BitwiseCounterpartText(expression.Operator) + "' does work on 'bool?' and answers the three-valued result.", span.Length)
            } else {
                diagnosticsValue.Report(ErrorCode.TypeMismatch, "Both sides of '" + opText + "' must be booleans, but " + sideText, span.Line, span.Column, "Use boolean expressions on both sides of the operator.", span.Length)
            }
        }

        return BuiltInTypes.Bool
    }

    // `bool? && bool?` IS REFUSED, AND IT IS REFUSED FOR A REASON THAT CAN BE SAID OUT LOUD. C#
    // refuses it too (§12.14 defines `&` and `|` over `bool?` and NOT the conditional forms): a
    // short-circuiting operator has to decide whether to evaluate its right side from the LEFT side
    // alone, and an absent left side cannot answer that question. The non-short-circuiting `&` and
    // `|` can, because they evaluate both sides and then consult the three-valued table, so the
    // suggestion names them alongside the three ways to say what an absent value means.
    func IsLiftedBoolOperand(candidate: TypeInfo): bool {
        unwrapped := UnwrapLiftedValueOperand(candidate)
        return unwrapped != null && IsBoolLikeType(unwrapped)
    }

    static func BitwiseCounterpartText(op: BinaryOperator): string {
        if op == BinaryOperator.Or {
            return "|"
        }

        return "&"
    }

    // THE MUTATING UNARY'S ENTRY, AND IT ASKS SIX QUESTIONS BEFORE THE OPERAND IS WALKED AT ALL.
    // `a?.b++` is refused outright: there is no value to increment when the receiver is null, so the
    // operand is never analysed. Then the SHAPE question decides whether the walk that follows needs a
    // sub-expression capture table — a member or index chain does, a bare name does not, and
    // installing one for a bare name would suppress the column-slice allocation rule for no reason.
    //
    // ALL SIX USED TO BE DRIVER STEPS. They were steps only because the reports they perform lived in
    // `Analyzer.cs`; now they are ordinary calls into the family that owns them, and the bracket the
    // capturing walk needs is opened here in the same instant the step is handed out.
    func AdvanceMutatingUnaryEntry(state: OperatorExpressionState): OperatorExpressionRequest? {
        unaryNode := state.Node as UnaryExpression
        if unaryNode == null {
            state.Phase = 99
            state.ResultType = BuiltInTypes.Unknown
            return null
        }

        operand := unaryNode.Operand
        changedWith := "changed with '" + UnarySymbolText(unaryNode.Operator) + "'"
        if writeTargetsValue.ReportNullConditionalWriteTargetIfNeeded(operand, changedWith) {
            state.Phase = 99
            state.ResultType = BuiltInTypes.Unknown
            return null
        }

        state.Pending = 1
        state.Phase = 12
        if AnalyzerWriteTargets.IsWriteTargetNeedingExpressionTypes(operand) {
            state.SavedExpressionTypes = ambientValue.EnterWriteTargetExpressionTypes()
            state.ExpressionTypes = ambientValue.WriteTargetExpressionTypes
            state.CaptureOpen = true
        }

        return new OperatorExpressionRequest(1, operand, null, operand.Line, operand.Column)
    }

    // THE OPERAND HAS ANSWERED, AND THE ROW ESCAPE IS ASKED FIRST OF ALL. The capture bracket has
    // already closed in `Supply`, so every report below runs with the slot restored exactly as it did
    // in the C#. A plain operand asks ONE further question — the direct-column escape — and a mutating
    // one asks FIVE, because a mutation is a write and every write-target rule applies to it.
    func AdvanceUnaryOperand(state: OperatorExpressionState): OperatorExpressionRequest? {
        state.Phase = 99
        unaryNode := state.Node as UnaryExpression
        if unaryNode == null {
            return null
        }

        state.OperandType = state.Answer
        operand := unaryNode.Operand
        if soaEscapeValue.ReportSoaRowEscapeIfNeeded(operand, state.OperandType, "used as a unary operand") {
            state.ResultType = BuiltInTypes.Unknown
            return null
        }

        if !IsIncrementOrDecrement(unaryNode.Operator) {
            if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(operand, "used as a unary operand") {
                state.ResultType = BuiltInTypes.Unknown
                return null
            }

            state.ResultType = UnaryOperatorResult(state.OperandType, unaryNode)
            return null
        }

        state.ResultType = BuiltInTypes.Unknown
        expressionTypes := state.ExpressionTypes

        // THE ORDER IS THE BEHAVIOUR, AND THE INTERLEAVING IS WHY THESE WERE FIVE SEPARATE STEPS
        // RATHER THAN ONE CHAIN: this owner's OWN direct-column escape falls between the table-member
        // rule and the indexed-mutation rule, and the assignable-target rule — also this owner's —
        // falls between the readonly-field rule and the read-only-property one, so that `1++` is told
        // it needs an assignable target instead of being asked whether it is a read-only property.
        if writeTargetsValue.ReportSoaTableMemberMutationIfNeeded(operand, expressionTypes, "incremented or decremented directly") {
            return null
        }

        if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(operand, "used as a unary operand") {
            return null
        }

        if writeTargetsValue.ReportUnsupportedBuiltInIndexedMutationIfNeeded(operand, expressionTypes, "incremented or decremented") {
            return null
        }

        if writeTargetsValue.ReportReadonlyFieldIncrementOrDecrementIfNeeded(unaryNode, expressionTypes) {
            return null
        }

        if ReportInvalidIncrementOrDecrementTargetIfNeeded(unaryNode) {
            return null
        }

        if writeTargetsValue.ReportInitOnlyMemberWriteIfNeeded(operand, "changed with '" + UnarySymbolText(unaryNode.Operator) + "'", expressionTypes) {
            return null
        }

        if writeTargetsValue.ReportReadOnlyPropertyWriteTargetIfNeeded(operand, UnarySymbolText(unaryNode.Operator), expressionTypes) {
            return null
        }

        if writeTargetsValue.ReportUsingResourceWriteIfNeeded(operand, "changed with '" + UnarySymbolText(unaryNode.Operator) + "'") {
            return null
        }

        if writeTargetsValue.ReportInParameterWriteIfNeeded(operand, "changed with '" + UnarySymbolText(unaryNode.Operator) + "'") || writeTargetsValue.ReportInParameterMemberWriteIfNeeded(operand, "changed with '" + UnarySymbolText(unaryNode.Operator) + "'") {
            return null
        }

        state.ResultType = UnaryOperatorResult(state.OperandType, unaryNode)
        return null
    }

    func UnaryOperatorResult(operandType: TypeInfo, unaryNode: UnaryExpression): TypeInfo {
        op := unaryNode.Operator
        liftedResult: TypeInfo = BuiltInTypes.Unknown
        if TryLiftedUnaryResult(op, operandType, out liftedResult) {
            return liftedResult
        }

        if op == UnaryOperator.Negate {
            return NegationResult(operandType, unaryNode)
        }

        if op == UnaryOperator.Not {
            return LogicalNotResult(operandType, unaryNode)
        }

        if op == UnaryOperator.BitwiseNot {
            return BitwiseNotResult(operandType, unaryNode)
        }

        if IsIncrementOrDecrement(op) {
            return IncrementOrDecrementResult(operandType, unaryNode)
        }

        if op == UnaryOperator.IndexFromEnd {
            return IndexFromEndResult(operandType, unaryNode)
        }

        return BuiltInTypes.Unknown
    }

    // `^n` IS A `System.Index`. Its operand is measured by ASSIGNABILITY to `int` rather than by the
    // numeric predicate, so a `byte` count is accepted and a `long` one is not.
    func IndexFromEndResult(operandType: TypeInfo, unaryNode: UnaryExpression): TypeInfo {
        if BuiltInTypes.IsUnknown(operandType) {
            return BuiltInTypes.Unknown
        }

        if !assignabilityValue.IsAssignable(BuiltInTypes.Int, operandType) {
            ReportUnaryOperandMismatch(unaryNode, operandType, "the from-end index count must be an int-compatible value")
            return BuiltInTypes.Unknown
        }

        return IndexType()
    }

    // `!` IS A BOOLEAN, and the declared-alias resolution is what makes `!isReady` work when
    // `isReady` is declared through an alias of `bool`.
    func LogicalNotResult(operandType: TypeInfo, unaryNode: UnaryExpression): TypeInfo {
        if BuiltInTypes.IsUnknown(operandType) {
            return BuiltInTypes.Unknown
        }

        overloadResult: TypeInfo = BuiltInTypes.Unknown
        if TryResolveUnaryOperatorOverload(unaryNode.Operator, operandType, out overloadResult) {
            return overloadResult
        }

        if BuiltInTypes.Is(declarationsValue.ResolveDeclaredAlias(operandType), BuiltInTypes.Bool) {
            return BuiltInTypes.Bool
        }

        ReportUnaryOperandMismatch(unaryNode, operandType, "the operand needs a boolean value")
        return BuiltInTypes.Unknown
    }

    // `++` AND `--` ANSWER THE OPERAND'S OWN TYPE, not a promotion of it: `byteCount++` stays a
    // `byte`, because the value is written back into the same storage it came from.
    func IncrementOrDecrementResult(operandType: TypeInfo, unaryNode: UnaryExpression): TypeInfo {
        if BuiltInTypes.IsUnknown(operandType) {
            return BuiltInTypes.Unknown
        }

        resolved := declarationsValue.ResolveDeclaredAlias(operandType)
        if IsIntegralType(resolved) || IsBitwiseEnumType(resolved) {
            return operandType
        }

        ReportUnaryOperandMismatch(unaryNode, operandType, "the operand needs an integral numeric value")
        return BuiltInTypes.Unknown
    }

    // NEGATION READS THE TARGET-TYPING SLOT, and it is the only unary that does. `value: byte = -1`
    // must be refused for the RIGHT reason — the magnitude is what does not fit, not the sign — so a
    // negated integer literal is typed against the annotation before the promotion table is asked.
    // The literal's own suffix wins: `-1L` is a `long` whatever it is being stored in.
    func NegationResult(operandType: TypeInfo, unaryNode: UnaryExpression): TypeInfo {
        if BuiltInTypes.IsUnknown(operandType) {
            return BuiltInTypes.Unknown
        }

        overloadResult: TypeInfo = BuiltInTypes.Unknown
        if TryResolveUnaryOperatorOverload(unaryNode.Operator, operandType, out overloadResult) {
            return overloadResult
        }

        intLiteral := unaryNode.Operand as IntLiteralExpression
        if intLiteral != null {
            targetTypedLiteralType: TypeInfo = BuiltInTypes.Unknown
            if TryGetExpectedNegativeIntegerLiteralType(ambientValue.CurrentExpectedType, intLiteral.Value, out targetTypedLiteralType) {
                return targetTypedLiteralType
            }
        }

        promoted := UnaryNegationType(operandType)
        if promoted != null {
            return promoted
        }

        ReportUnaryOperandMismatch(unaryNode, operandType, "the operand needs a signed numeric value, a floating-point value, decimal, or uint")
        return BuiltInTypes.Unknown
    }

    // `~` IS INTEGRAL OR A FLAGS ENUM. A flags enum answers ITSELF rather than its backing type, so
    // `~Flags.A` is still a `Flags` and can be `&`-ed with one.
    func BitwiseNotResult(operandType: TypeInfo, unaryNode: UnaryExpression): TypeInfo {
        if BuiltInTypes.IsUnknown(operandType) {
            return BuiltInTypes.Unknown
        }

        overloadResult: TypeInfo = BuiltInTypes.Unknown
        if TryResolveUnaryOperatorOverload(unaryNode.Operator, operandType, out overloadResult) {
            return overloadResult
        }

        if IsBitwiseEnumType(operandType) {
            return operandType
        }

        promoted := UnaryNumericPromotionType(operandType)
        if promoted != null && IsIntegralType(promoted) {
            return promoted
        }

        ReportUnaryOperandMismatch(unaryNode, operandType, "the operand needs an integral value")
        return BuiltInTypes.Unknown
    }

    // `++` AND `--` NEED SOMEWHERE TO PUT THE RESULT. A discard is refused along with everything
    // else that is not storage, because `_++` has nowhere to write back to.
    func ReportInvalidIncrementOrDecrementTargetIfNeeded(unaryNode: UnaryExpression): bool {
        if IsIncrementOrDecrementTarget(unaryNode.Operand) {
            return false
        }

        opText := UnarySymbolText(unaryNode.Operator)
        span := spansValue.GetExpressionDiagnosticSpan(unaryNode.Operand)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "The '" + opText + "' operator needs an assignable target", span.Line, span.Column, "Use a variable, field, property, or indexed element as the operand.", span.Length)
        return true
    }

    static func IsIncrementOrDecrementTarget(expression: Expression): bool {
        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return IsIncrementOrDecrementTarget(parenthesized.Inner)
        }

        identifier := expression as IdentifierExpression
        if identifier != null {
            return identifier.Name != "_"
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            return true
        }

        indexAccess := expression as IndexAccessExpression
        return indexAccess != null
    }

    // A NEGATED INTEGER LITERAL UNDER AN ANNOTATION. The magnitude is parsed UNSIGNED and compared
    // against the target's negative maximum, which is one MORE than its positive one — `-128` fits a
    // `sbyte` and `128` does not. A suffixed literal is not target-typed at all: the suffix is the
    // programmer saying what they meant.
    func TryGetExpectedNegativeIntegerLiteralType(expectedType: TypeInfo?, literalText: string, out targetType: TypeInfo): bool {
        targetType = BuiltInTypes.Int
        if expectedType == null {
            return false
        }

        suffix := NumericLiteralFacts.GetIntegerSuffix(literalText)
        if suffix.HasUnsigned || suffix.HasLong {
            return false
        }

        magnitude: ulong = 0
        if !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(literalText, out magnitude) {
            return false
        }

        resolved := declarationsValue.ResolveDeclaredAlias(expectedType)
        nullableResolved := resolved as NullableTypeInfo
        if nullableResolved != null {
            resolved = declarationsValue.ResolveDeclaredAlias(nullableResolved.InnerType)
        }

        simple := resolved as SimpleTypeInfo
        if simple != null {
            simpleMaxMagnitude: ulong = 0
            if NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude(simple.Name, out simpleMaxMagnitude) && magnitude <= simpleMaxMagnitude {
                targetType = simple
                return true
            }

            return false
        }

        reflection := resolved as ReflectionTypeInfo
        if reflection == null {
            return false
        }

        reflectionUnderlying := reflection.Type
        underlying := Nullable.GetUnderlyingType(reflection.Type)
        if underlying != null {
            reflectionUnderlying = underlying
        }

        reflectionType: SimpleTypeInfo = BuiltInTypes.Int
        if !NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(reflectionUnderlying, out reflectionType) {
            return false
        }

        reflectionMaxMagnitude: ulong = 0
        if NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude(reflectionType.Name, out reflectionMaxMagnitude) && magnitude <= reflectionMaxMagnitude {
            targetType = reflectionType
            return true
        }

        return false
    }

    // AN OPERATOR OVERLOAD, LOOKED FOR ON BOTH OPERANDS. The declaration side is searched before the
    // runtime side on each type, and BOTH types are searched before the search fails, because an
    // operator may be declared on either side of the expression.
    func TryResolveBinaryOperatorOverload(op: BinaryOperator, left: TypeInfo, right: TypeInfo, out result: TypeInfo): bool {
        result = BuiltInTypes.Unknown

        clrName := OperatorFacts.GetBinaryClrName(op)
        symbol := OperatorFacts.GetBinarySymbol(op)
        if clrName == null || symbol == null {
            return false
        }

        if TryResolveDeclaredBinaryOperator(left, symbol, left, right, out result) || TryResolveRuntimeBinaryOperator(left, clrName, left, right, out result) {
            return true
        }

        return TryResolveDeclaredBinaryOperator(right, symbol, left, right, out result) || TryResolveRuntimeBinaryOperator(right, clrName, left, right, out result)
    }

    // A DECLARED OPERATOR MUST ACTUALLY ACCEPT THE OPERANDS. Without the parameter check `Vec + Vec`
    // would bind to ANY `static func operator +` on the type — even one declared over two `int`s —
    // swallowing a real mismatch and diverging from the IL backend, which resolves against the
    // actual argument types.
    func TryResolveDeclaredBinaryOperator(operandType: TypeInfo, symbol: string, left: TypeInfo, right: TypeInfo, out result: TypeInfo): bool {
        result = BuiltInTypes.Unknown
        substitution: Dictionary<string, TypeInfo>? = null
        declarationOwner := substitutionValue.GetSourceDeclarationOwner(operandType, out substitution)
        members := DeclaredMembersOf(declarationOwner)
        if members == null {
            return false
        }

        memberIndex := 0
        while memberIndex < members.Length {
            member := members[memberIndex]
            memberIndex = memberIndex + 1
            memberReturnType := member.ReturnType
            if IsOperatorCandidate(member, symbol, 2) && memberReturnType != null {
                // The two parameter resolutions are NESTED rather than joined, because resolving a
                // written type reference RECORDS it — a second resolution that the host's `continue`
                // never reached would be a new observation, not a tidier condition.
                parameterTypes := member.ParameterTypes
                if assignabilityValue.IsAssignable(substitutionValue.ResolveTypeForSourceOwner(parameterTypes[0], declarationOwner, substitution), left) {
                    if assignabilityValue.IsAssignable(substitutionValue.ResolveTypeForSourceOwner(parameterTypes[1], declarationOwner, substitution), right) {
                        result = substitutionValue.ResolveTypeForSourceOwner(memberReturnType, declarationOwner, substitution)
                        return true
                    }
                }
            }
        }

        return false
    }

    // A RUNTIME OPERATOR, WHICH IS HOW EVERY IMPORTED VALUE TYPE'S ARITHMETIC BINDS. BOTH operand
    // CLR types must resolve and match: an operand whose CLR type is unknown is NOT a match, so a
    // real mismatch surfaces rather than being silently bound.
    func TryResolveRuntimeBinaryOperator(operandType: TypeInfo, clrName: string, left: TypeInfo, right: TypeInfo, out result: TypeInfo): bool {
        result = BuiltInTypes.Unknown

        clrType := TryResolveOperandClrType(operandType)
        if clrType == null {
            return false
        }

        leftClr := TryResolveOperandClrType(left)
        rightClr := TryResolveOperandClrType(right)
        candidates := clrType.GetMethods(BindingFlags.Public | BindingFlags.Static)
        candidateIndex := 0
        while candidateIndex < candidates.Length {
            candidate := candidates[candidateIndex]
            candidateIndex = candidateIndex + 1
            if candidate.get_Name() != clrName {
                continue
            }

            parameters := candidate.GetParameters()
            if parameters.Length != 2 {
                continue
            }

            if !AnalyzerOverloadFacts.IsRuntimeOperatorParameterCompatible(parameters[0].get_ParameterType(), leftClr) {
                continue
            }

            if !AnalyzerOverloadFacts.IsRuntimeOperatorParameterCompatible(parameters[1].get_ParameterType(), rightClr) {
                continue
            }

            result = AnalyzerReflectionTypeConversion.ConvertReflectionType(candidate.get_ReturnType())
            return true
        }

        return false
    }

    func TryResolveUnaryOperatorOverload(op: UnaryOperator, operand: TypeInfo, out result: TypeInfo): bool {
        result = BuiltInTypes.Unknown

        clrName := OperatorFacts.GetUnaryClrName(op)
        symbol := OperatorFacts.GetUnarySymbol(op)
        if clrName == null || symbol == null {
            return false
        }

        return TryResolveDeclaredUnaryOperator(operand, symbol, out result) || TryResolveRuntimeUnaryOperator(operand, clrName, out result)
    }

    func TryResolveDeclaredUnaryOperator(operandType: TypeInfo, symbol: string, out result: TypeInfo): bool {
        result = BuiltInTypes.Unknown
        substitution: Dictionary<string, TypeInfo>? = null
        declarationOwner := substitutionValue.GetSourceDeclarationOwner(operandType, out substitution)
        members := DeclaredMembersOf(declarationOwner)
        if members == null {
            return false
        }

        memberIndex := 0
        while memberIndex < members.Length {
            member := members[memberIndex]
            memberIndex = memberIndex + 1
            memberReturnType := member.ReturnType
            if IsOperatorCandidate(member, symbol, 1) && memberReturnType != null {
                parameterTypes := member.ParameterTypes
                if assignabilityValue.IsAssignable(substitutionValue.ResolveTypeForSourceOwner(parameterTypes[0], declarationOwner, substitution), operandType) {
                    result = substitutionValue.ResolveTypeForSourceOwner(memberReturnType, declarationOwner, substitution)
                    return true
                }
            }
        }

        return false
    }

    // THE RUNTIME UNARY OPERATOR, AND ITS PARAMETER CHECK IS AGAINST THE DECLARING TYPE rather than
    // against the operand's own CLR type — which is the host's shape exactly, and is why a unary
    // operator on a type binds whenever the type itself is the parameter.
    func TryResolveRuntimeUnaryOperator(operandType: TypeInfo, clrName: string, out result: TypeInfo): bool {
        result = BuiltInTypes.Unknown

        clrType := TryResolveOperandClrType(operandType)
        if clrType == null {
            return false
        }

        candidates := clrType.GetMethods(BindingFlags.Public | BindingFlags.Static)
        candidateIndex := 0
        while candidateIndex < candidates.Length {
            candidate := candidates[candidateIndex]
            candidateIndex = candidateIndex + 1
            if candidate.get_Name() != clrName {
                continue
            }

            parameters := candidate.GetParameters()
            if parameters.Length != 1 {
                continue
            }

            if !AnalyzerOverloadFacts.IsRuntimeOperatorParameterCompatible(parameters[0].get_ParameterType(), clrType) {
                continue
            }

            result = AnalyzerReflectionTypeConversion.ConvertReflectionType(candidate.get_ReturnType())
            return true
        }

        return false
    }

    // THE CLR TYPE AN OPERATOR OPERAND IS LOOKED UP ON. The fallback matters: the ordinary
    // conversion special-cases a fixed set of BCL generics, so an ARBITRARY imported generic —
    // `System.Numerics.Vector<T>` is the motivating one — is resolved by finding its open definition
    // in the load context and closing it over the converted arguments. Without it, operator overloads
    // would work only for the hardcoded generics.
    func TryResolveOperandClrType(operandType: TypeInfo): Type? {
        direct := clrConversionValue.TryConvertTypeInfoToClrType(operandType)
        if direct != null {
            return direct
        }

        generic := declarationsValue.ResolveDeclaredAlias(operandType) as GenericTypeInfo
        if generic == null {
            return null
        }

        openDefinitionName := generic.Name + "`" + generic.TypeArguments.Count.ToString()
        openCandidate := externalTypesValue.ResolveExternalType(openDefinitionName) as ReflectionTypeInfo
        if openCandidate == null {
            return null
        }

        openType := openCandidate.Type
        if !openType.get_IsGenericTypeDefinition() {
            return null
        }

        typeArguments := new Type[](generic.TypeArguments.Count)
        argumentIndex := 0
        while argumentIndex < typeArguments.Length {
            argumentClr := TryResolveOperandClrType(generic.TypeArguments[argumentIndex])
            if argumentClr == null {
                return null
            }

            typeArguments[argumentIndex] = argumentClr
            argumentIndex = argumentIndex + 1
        }

        return openType.MakeGenericType(typeArguments)
    }

    static func DeclaredMembersOf(declarationOwner: TypeInfo): DeclaredMemberInfo[]? {
        classType := declarationOwner as ClassTypeInfo
        if classType != null {
            return classType.DeclaredMembers
        }

        structType := declarationOwner as StructTypeInfo
        if structType != null {
            return structType.DeclaredMembers
        }

        recordType := declarationOwner as RecordTypeInfo
        if recordType != null {
            return recordType.DeclaredMembers
        }

        return null
    }

    static func IsOperatorCandidate(member: DeclaredMemberInfo, symbol: string, arity: int): bool {
        if member.Kind != DeclaredMemberKind.Function {
            return false
        }

        if !member.IsOperatorOverload || member.OperatorSymbol != symbol {
            return false
        }

        if member.ParameterCount != arity || member.ParameterTypes.Length != arity {
            return false
        }

        return member.ReturnType != null
    }

    // THE TWO REPORTS EVERY OPERATOR CLASS SHARES.
    //
    // The BINARY one re-derives which side is wrong from the INTEGRAL predicate rather than being
    // told, and a shift re-derives it differently: for `&`, `|` and `^` a boolean side is not wrong,
    // and for `<<` and `>>` it is.
    func ReportBinaryOperandMismatch(expression: BinaryExpression, left: TypeInfo, right: TypeInfo, requirement: string) {
        leftIsWrong := !IsIntegralType(left) && !BuiltInTypes.Is(left, BuiltInTypes.Bool)
        rightIsWrong := !IsIntegralType(right) && !BuiltInTypes.Is(right, BuiltInTypes.Bool)
        if expression.Operator == BinaryOperator.LeftShift || expression.Operator == BinaryOperator.RightShift {
            leftIsWrong = !IsIntegralType(left)
            rightIsWrong = !IsIntegralType(right)
        }

        span := spansValue.GetBinaryOperandDiagnosticSpan(expression, leftIsWrong, rightIsWrong)
        opText := OperatorFacts.GetBinaryText(expression.Operator)
        sideText := SideText(left, right, leftIsWrong, rightIsWrong)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "The '" + opText + "' operator doesn't work with '" + TypeText(left) + "' and '" + TypeText(right) + "' — " + requirement + ", but " + sideText, span.Line, span.Column, "Use compatible operands, convert the non-compatible value, or define an operator overload for this type.", span.Length)
    }

    // THE UNARY REPORT UNDERLINES THE OPERATOR RATHER THAN THE OPERAND, which is why it takes the
    // node's own position and the operator text's length instead of asking for a span.
    func ReportUnaryOperandMismatch(unaryNode: UnaryExpression, operandType: TypeInfo, requirement: string) {
        opText := OperatorFacts.GetUnaryText(unaryNode.Operator)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "The '" + opText + "' operator doesn't work with '" + TypeText(operandType) + "' — " + requirement, unaryNode.Line, unaryNode.Column, "Use a compatible operand, convert the value, or define an operator overload for this type.", opText.Length)
    }

    // THE "NO COMMON TYPE" REPORT, shared by arithmetic and relational comparison. It underlines the
    // OPERATOR, because neither side is individually wrong — it is the pair that has no meeting
    // point, which is what `decimal + double` and `ulong + long` are.
    func ReportNoCommonType(expression: BinaryExpression, left: TypeInfo, right: TypeInfo) {
        span := AnalyzerDiagnosticSpanFacts.GetBinaryOperatorDiagnosticSpan(expression)
        opText := OperatorFacts.GetBinaryText(expression.Operator)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "The '" + opText + "' operator doesn't work with '" + TypeText(left) + "' and '" + TypeText(right) + "'", span.Line, span.Column, "Use numeric operands with a compatible common type, or add an explicit conversion.", span.Length)
    }

    // WHICH SIDE THE MESSAGE BLAMES. Both wrong or both right reads as a pair; exactly one wrong
    // names that side. "Both right" reaches here only from the shift and bitwise report, where the
    // requirement text is what carries the complaint.
    static func SideText(left: TypeInfo, right: TypeInfo, leftIsWrong: bool, rightIsWrong: bool): string {
        if leftIsWrong == rightIsWrong {
            return "I found '" + TypeText(left) + "' and '" + TypeText(right) + "'"
        }

        if leftIsWrong {
            return "the left side is '" + TypeText(left) + "'"
        }

        return "the right side is '" + TypeText(right) + "'"
    }

    // WHAT TWO ANSWERS CAN BOTH BE AT ONCE. This is slice 52's driver kind 3, and it retires with
    // this slice: the ternary asked for a common type as a STEP because the widening table lived in
    // the host, and now that the table is here the ternary's owner calls it directly.
    static func CommonType(left: TypeInfo, right: TypeInfo): TypeInfo {
        // IDENTITY, NOT EQUALITY. The host compared the two answers with `==` on a class that
        // overrides `Equals` but not `operator ==`, so two SEPARATELY CONSTRUCTED `int`s are not the
        // same answer here — they reach the promotion table instead and come back `int` anyway. The
        // shortcut only fires for two references to one type, which is what a ternary over two reads
        // of the same declared type produces.
        if Object.ReferenceEquals(left, right) {
            return left
        }

        if IsNumericType(left) && IsNumericType(right) {
            widened := WiderType(left, right)
            if widened != null {
                return widened
            }

            return BuiltInTypes.Unknown
        }

        // TWO SEPARATELY CONSTRUCTED ANSWERS FOR ONE TYPE ARE ONE TYPE. Reference identity alone was
        // the whole non-numeric rule, and a numeric pair survived it only because the promotion table
        // below answered anyway — so `IsNullOrWhiteSpace(s) ? $"exited {code}" : s`, whose arms are an
        // interpolated string and a `string`, came back `unknown` and every use of the result reported
        // against a type the ternary plainly had. `TypeInfoIdentityFacts.AreEqual` is the analyzer's
        // own exact semantic identity (nominal leaves by declaration handle, composites by shape), so
        // this asks the same question the rest of the analyzer asks and gets the same answer.
        if TypeInfoIdentityFacts.AreEqual(left, right) {
            return left
        }

        // NULLABILITY LIFTS TO THE WIDER ARM, as it does in C#: when the two arms differ only in
        // whether the value may be null, the conditional is worth the nullable one — the non-null arm
        // converts to it and the reverse does not. `flag ? name : null` and `flag ? maybe : name` are
        // both `string?`, which is exactly what the value can be.
        leftNullable := left as NullableTypeInfo
        rightNullable := right as NullableTypeInfo
        if leftNullable != null && rightNullable == null && TypeInfoIdentityFacts.AreEqual(leftNullable.InnerType, right) {
            return left
        }

        if rightNullable != null && leftNullable == null && TypeInfoIdentityFacts.AreEqual(rightNullable.InnerType, left) {
            return right
        }

        return BuiltInTypes.Unknown
    }

    // N# BINARY NUMERIC PROMOTION. This is NOT implicit conversion: assignment asks whether a value
    // fits a declared type, and this asks what type an OPERATION over two values is performed in.
    // Small types promote to `int`, and two combinations have no answer at all rather than a widest
    // one — `decimal` with a floating-point type, and `ulong` with any signed integral — because
    // neither of those pairs has a type that holds both exactly.
    static func WiderType(left: TypeInfo, right: TypeInfo): TypeInfo? {
        l := NumericName(left)
        r := NumericName(right)
        if l == null || r == null {
            return BuiltInTypes.Int
        }

        if l == "decimal" || r == "decimal" {
            other := l
            if l == "decimal" {
                other = r
            }

            if other == "float" || other == "double" {
                return null
            }

            return BuiltInTypes.Decimal
        }

        if l == "double" || r == "double" {
            return BuiltInTypes.Double
        }

        if l == "float" || r == "float" {
            return BuiltInTypes.Float
        }

        if l == "ulong" || r == "ulong" {
            other := l
            if l == "ulong" {
                other = r
            }

            if other == "sbyte" || other == "short" || other == "int" || other == "long" {
                return null
            }

            return BuiltInTypes.ULong
        }

        if l == "long" || r == "long" {
            return BuiltInTypes.Long
        }

        if l == "uint" || r == "uint" {
            other := l
            if l == "uint" {
                other = r
            }

            if other == "sbyte" || other == "short" || other == "int" {
                return BuiltInTypes.Long
            }

            return BuiltInTypes.UInt
        }

        return BuiltInTypes.Int
    }

    // ECMA-334 §10.2.11 — THE IMPLICIT CONSTANT EXPRESSION CONVERSION, WHICH IS WHY `mask & 0xFF`
    // TYPE-CHECKS AND `mask & flags` DOES NOT.
    //
    // Binary numeric promotion has NO answer for `ulong` against a signed integral type, because no
    // one type holds every value of both. That is the right answer for two VARIABLES and the wrong
    // one for a CONSTANT: `0xFF` is not "an int", it is the value 255, and every integral type from
    // `byte` up holds it exactly. C# says so in one sentence — a constant expression of type `int`
    // converts implicitly to `sbyte`, `byte`, `short`, `ushort`, `uint` or `ulong` when its value is
    // in that type's range, and a constant of type `long` converts to `ulong` when it is
    // non-negative — and every operator that promotes inherits it: `&`, `|`, `^`, the arithmetic
    // four, the comparisons and the compound assignments built over them.
    //
    // IT IS ASKED ONLY AFTER THE ORDINARY PROMOTION HAS FAILED, so it can never change an answer the
    // promotion table already had. And it is asked of the OPERAND EXPRESSION rather than of its
    // type, because being constant is a property of what was written and of nothing else — which is
    // exactly the line C# draws at CS0034, and the line N# keeps: a non-constant operand still
    // fails, now with a sentence that names the rule and the cast.
    static func ConstantPromotedType(left: TypeInfo, right: TypeInfo, expression: BinaryExpression): TypeInfo? {
        rightConverted := ConstantConvertedOperandType(left, right, expression.Right)
        if rightConverted != null {
            return WiderType(left, rightConverted)
        }

        leftConverted := ConstantConvertedOperandType(right, left, expression.Left)
        if leftConverted != null {
            return WiderType(leftConverted, right)
        }

        return null
    }

    // WHETHER `source`, AS WRITTEN, IS A CONSTANT THE TARGET TYPE HOLDS — and the answer is the
    // TARGET type, because that is what the operand becomes.
    //
    // A SUFFIXED literal adopts nothing: `1L` is a `long` in `mask & 1L` and that pair still has no
    // common type, exactly as C# refuses it. Only the source types the rule names take part, so a
    // `uint` operand against a `ulong` one never reaches here — it has a common type already.
    static func ConstantConvertedOperandType(target: TypeInfo, source: TypeInfo, sourceExpression: Expression?): TypeInfo? {
        if !IsIntegralType(target) || !IsIntegralType(source) {
            return null
        }

        sourceName := NumericName(source)
        if sourceName != "int" && sourceName != "long" {
            return null
        }

        targetName := NumericName(target)
        if targetName == null || targetName == sourceName {
            return null
        }

        facts := ConstantOperandFacts.FromExpression(sourceExpression)
        if !facts.HasIntegerLiteral {
            return null
        }

        suffix := NumericLiteralFacts.GetIntegerSuffix(facts.LiteralText)
        if suffix.HasUnsigned || suffix.HasLong {
            return null
        }

        magnitude: ulong = 0
        if !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(facts.LiteralText, out magnitude) {
            return null
        }

        if facts.IsNegative {
            maxMagnitude: ulong = 0
            if !NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude(targetName, out maxMagnitude) {
                return null
            }

            if magnitude > maxMagnitude {
                return null
            }

            return target
        }

        maxValue: ulong = 0
        if !NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue(targetName, out maxValue) {
            return null
        }

        if magnitude > maxValue {
            return null
        }

        return target
    }

    // THE ONLY INTEGRAL PAIR WITH NO COMMON TYPE, AND THE READER IS TOLD WHY RATHER THAN THAT IT IS
    // SO. `ulong` against `sbyte`, `short`, `int` or `long` is the one combination binary numeric
    // promotion refuses, and the generic "these two don't work" sentence sends the reader looking
    // for a typo in an expression that has none. By the time this runs the constant rule above has
    // already been tried and declined, so what is in front of the reader is a VARIABLE — and what
    // they need is the name of the rule and the cast that settles it.
    func TryReportNoUnsignedCommonType(expression: BinaryExpression, left: TypeInfo, right: TypeInfo): bool {
        signedSide := SignedSideAgainstULong(left, right)
        if signedSide == null {
            return false
        }

        span := AnalyzerDiagnosticSpanFacts.GetBinaryOperatorDiagnosticSpan(expression)
        opText := OperatorFacts.GetBinaryText(expression.Operator)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "The '" + opText + "' operator doesn't work with '" + TypeText(left) + "' and '" + TypeText(right) + "' — no single integral type holds every value of both, so there is no common type to compute in. A constant whose value fits converts on its own; a variable needs a cast", span.Line, span.Column, "Cast the '" + signedSide + "' side to 'ulong', or make both sides signed.", span.Length)
        return true
    }

    // WHICH SIDE IS THE SIGNED ONE, or null when this is not the `ulong`-against-signed pair at all.
    static func SignedSideAgainstULong(left: TypeInfo, right: TypeInfo): string? {
        leftName := NumericName(left)
        rightName := NumericName(right)
        if leftName == null || rightName == null {
            return null
        }

        if leftName == "ulong" && IsSignedIntegralName(rightName) {
            return rightName
        }

        if rightName == "ulong" && IsSignedIntegralName(leftName) {
            return leftName
        }

        return null
    }

    static func IsSignedIntegralName(name: string): bool {
        return name == "sbyte" || name == "short" || name == "int" || name == "long"
    }

    // UNARY NUMERIC PROMOTION, which the SHIFT operator uses for its left operand and `~` for its
    // only one. Everything narrower than `int` becomes `int`; everything else keeps its own type.
    static func UnaryNumericPromotionType(operand: TypeInfo): TypeInfo? {
        name := NumericName(operand)
        if name == null {
            return null
        }

        if name == "byte" || name == "sbyte" || name == "short" || name == "ushort" || name == "char" || name == "int" {
            return BuiltInTypes.Int
        }

        if name == "uint" {
            return BuiltInTypes.UInt
        }

        if name == "long" {
            return BuiltInTypes.Long
        }

        if name == "ulong" {
            return BuiltInTypes.ULong
        }

        if name == "float" {
            return BuiltInTypes.Float
        }

        if name == "double" {
            return BuiltInTypes.Double
        }

        if name == "decimal" {
            return BuiltInTypes.Decimal
        }

        return null
    }

    // NEGATION'S PROMOTION DIFFERS FROM THE OTHER ONE IN EXACTLY TWO PLACES: `uint` widens to `long`
    // because `-uint` does not fit a `uint`, and `ulong` has no answer at all because no integral
    // type holds the negation of every `ulong`.
    static func UnaryNegationType(operand: TypeInfo): TypeInfo? {
        name := NumericName(operand)
        if name == null {
            return null
        }

        if name == "byte" || name == "sbyte" || name == "short" || name == "ushort" || name == "char" || name == "int" {
            return BuiltInTypes.Int
        }

        if name == "uint" || name == "long" {
            return BuiltInTypes.Long
        }

        if name == "float" {
            return BuiltInTypes.Float
        }

        if name == "double" {
            return BuiltInTypes.Double
        }

        if name == "decimal" {
            return BuiltInTypes.Decimal
        }

        return null
    }

    // THE READER UNDER EVERY PROMOTION TABLE, and it is deliberately narrow: only a SIMPLE type has
    // a numeric name. A reflected `System.Int32` does NOT promote here — that is what makes
    // `WiderType` answer `int` for an unrecognised pair rather than guessing at one.
    static func NumericName(candidate: TypeInfo): string? {
        simple := candidate as SimpleTypeInfo
        if simple != null {
            return simple.Name
        }

        return null
    }

    static func IsNumericType(candidate: TypeInfo): bool {
        return BuiltInTypes.Is(candidate, BuiltInTypes.Int) || BuiltInTypes.Is(candidate, BuiltInTypes.Long) || BuiltInTypes.Is(candidate, BuiltInTypes.Float) || BuiltInTypes.Is(candidate, BuiltInTypes.Double) || BuiltInTypes.Is(candidate, BuiltInTypes.Decimal) || BuiltInTypes.Is(candidate, BuiltInTypes.Byte) || BuiltInTypes.Is(candidate, BuiltInTypes.SByte) || BuiltInTypes.Is(candidate, BuiltInTypes.Short) || BuiltInTypes.Is(candidate, BuiltInTypes.UShort) || BuiltInTypes.Is(candidate, BuiltInTypes.UInt) || BuiltInTypes.Is(candidate, BuiltInTypes.ULong) || BuiltInTypes.Is(candidate, BuiltInTypes.Char)
    }

    static func IsIntegralType(candidate: TypeInfo): bool {
        return BuiltInTypes.Is(candidate, BuiltInTypes.Int) || BuiltInTypes.Is(candidate, BuiltInTypes.Long) || BuiltInTypes.Is(candidate, BuiltInTypes.Byte) || BuiltInTypes.Is(candidate, BuiltInTypes.SByte) || BuiltInTypes.Is(candidate, BuiltInTypes.Short) || BuiltInTypes.Is(candidate, BuiltInTypes.UShort) || BuiltInTypes.Is(candidate, BuiltInTypes.UInt) || BuiltInTypes.Is(candidate, BuiltInTypes.ULong) || BuiltInTypes.Is(candidate, BuiltInTypes.Char)
    }

    static func IsStringType(candidate: TypeInfo): bool {
        return BuiltInTypes.Is(candidate, BuiltInTypes.String)
    }

    // RELATIONAL COMPARISON'S DOMAIN, which is the numeric one MINUS `decimal` PLUS the reflected
    // and named spellings of the same set. `decimal` is excluded because its comparison goes through
    // an operator overload rather than through a primitive instruction.
    func IsPrimitiveRelationalType(candidate: TypeInfo): bool {
        resolved := declarationsValue.ResolveDeclaredAlias(candidate)
        if IsNumericType(resolved) && BuiltInTypes.IsNot(resolved, BuiltInTypes.Decimal) {
            return true
        }

        simple := resolved as SimpleTypeInfo
        if simple != null && IsPrimitiveRelationalTypeName(simple.Name) {
            return true
        }

        reflection := resolved as ReflectionTypeInfo
        return reflection != null && IsPrimitiveRelationalClrType(reflection.Type)
    }

    static func IsPrimitiveRelationalTypeName(name: string): bool {
        return name == "byte" || name == "Byte" || name == "sbyte" || name == "SByte" || name == "short" || name == "Int16" || name == "ushort" || name == "UInt16" || name == "int" || name == "Int32" || name == "uint" || name == "UInt32" || name == "long" || name == "Int64" || name == "ulong" || name == "UInt64" || name == "char" || name == "Char" || name == "float" || name == "Single" || name == "double" || name == "Double"
    }

    static func IsPrimitiveRelationalClrType(candidate: Type): bool {
        return candidate == typeof(byte) || candidate == typeof(sbyte) || candidate == typeof(short) || candidate == typeof(ushort) || candidate == typeof(int) || candidate == typeof(uint) || candidate == typeof(long) || candidate == typeof(ulong) || candidate == typeof(char) || candidate == typeof(float) || candidate == typeof(double)
    }

    // WHAT `==` ADMITS. Null on either side compares with anything; two booleans compare; two
    // primitives compare when they have a common type; the same flags enum compares; the same record
    // struct compares BY REFERENCE IDENTITY of its type info, which is what makes two DIFFERENT
    // record structs not comparable; the SAME open type parameter compares, `?` or not; and two
    // reference types always compare, because reference equality is always meaningful.
    func CanCompareWithEqualityOperator(left: TypeInfo, right: TypeInfo): bool {
        resolvedLeft := declarationsValue.ResolveDeclaredAlias(left)
        resolvedRight := declarationsValue.ResolveDeclaredAlias(right)
        if BuiltInTypes.Is(resolvedLeft, BuiltInTypes.Null) || BuiltInTypes.Is(resolvedRight, BuiltInTypes.Null) {
            return true
        }

        if ArePrimitiveEqualityTypesCompatible(resolvedLeft, resolvedRight) {
            return true
        }

        if IsSameBitwiseEnumType(resolvedLeft, resolvedRight) {
            return true
        }

        if IsSameRecordStructType(resolvedLeft, resolvedRight) {
            return true
        }

        if CanCompareLiftedEquality(resolvedLeft, resolvedRight) {
            return true
        }

        if CanCompareOpenTypeParameter(resolvedLeft, resolvedRight) {
            return true
        }

        return AnalyzerConversionFacts.IsReferenceType(resolvedLeft) && AnalyzerConversionFacts.IsReferenceType(resolvedRight)
    }

    // `a == b` WHERE BOTH SIDES ARE THE SAME OPEN TYPE PARAMETER, `?` OR NOT.
    //
    // A bare `T` already compared here, because the tail below reads an unresolved parameter name as
    // a reference; `T? == T?` did not, and that asymmetry is what the census caught. `Same<T>(a: T?,
    // b: T?)` under `where T : struct` is the shape a converter writes wherever the source compared
    // two optional values, and it was refused with a sentence about primitives and record structs
    // that named nothing the author could act on.
    //
    // BOTH SIDES MUST NAME THE SAME PARAMETER. `T == U` is two unrelated instantiations and stays
    // with the reference tail, which is the only rule that has anything to say about it, and a
    // parameter compared against a CONCRETE type is not this rule either.
    //
    // THE CONSTRAINT DOES NOT DECIDE THIS — it decides the LOWERING, not the legality. A `struct`
    // parameter's `T?` is a real `Nullable<T>` and lowers to the presence-and-value pair; an
    // unconstrained or `class` parameter's `?` is an annotation on one CLR type and lowers to the
    // same comparison the bare parameter gets. Both are `bool`, and both are decided.
    func CanCompareOpenTypeParameter(left: TypeInfo, right: TypeInfo): bool {
        leftName := OpenTypeParameterName(left)
        if leftName == null {
            return false
        }

        rightName := OpenTypeParameterName(right)
        return rightName != null && leftName == rightName
    }

    // The NAME an operand names when it is a type parameter visible here, seen through at most one
    // `?`, and null for everything else. A type parameter has no TypeInfo kind of its own — it
    // resolves to a `SimpleTypeInfo` carrying the written name — so the SCOPE is what says whether a
    // name is one, which is also what makes a generic `struct` and `record` answer as a `class` does.
    func OpenTypeParameterName(candidate: TypeInfo): string? {
        resolved := declarationsValue.ResolveDeclaredAlias(candidate)
        nullable := resolved as NullableTypeInfo
        if nullable != null {
            resolved = declarationsValue.ResolveDeclaredAlias(nullable.InnerType)
        }

        simple := resolved as SimpleTypeInfo
        if simple == null {
            return null
        }

        if !scopesValue.IsTypeParameterInScope(simple.Name) {
            return null
        }

        return simple.Name
    }

    // THE LIFTED FORM OF EVERY EQUALITY THE RULE ABOVE ALREADY ADMITS. `Nullable<T>` gets a lifted
    // `==` and `!=` for each predefined one on `T` — that is C# §12.12.7 — and the answer is `bool`,
    // not `bool?`: two absent values are EQUAL and an absent one differs from every present one, so
    // the comparison is always decided. `x?.TryGetValue(k, out v) == true` is the shape that needs it,
    // and it is the shape a converter writes wherever the source tested a lifted boolean.
    //
    // ONE SIDE LIFTED IS ENOUGH, because the non-nullable operand converts to `T?` implicitly. Both
    // sides are unwrapped and the SAME question is asked of what is left, so the lifted rule can
    // never admit a pair the unlifted rule refuses — and it recurses at most once, because an
    // unwrapped operand is not a nullable.
    //
    // A REFERENCE `T?` IS NOT A LIFT. Its `?` is an annotation on one CLR type, and the reference arm
    // below already answers it; unwrapping here would let `string? == int` through the primitive arm.
    func CanCompareLiftedEquality(left: TypeInfo, right: TypeInfo): bool {
        unwrappedLeft := UnwrapLiftedValueOperand(left)
        unwrappedRight := UnwrapLiftedValueOperand(right)
        if unwrappedLeft == null && unwrappedRight == null {
            return false
        }

        liftedLeft := unwrappedLeft ?? left
        liftedRight := unwrappedRight ?? right
        if AnalyzerConversionFacts.IsReferenceType(liftedLeft) || AnalyzerConversionFacts.IsReferenceType(liftedRight) {
            return false
        }

        return CanCompareWithEqualityOperator(liftedLeft, liftedRight)
    }

    // The `T` of a `T?` whose `T` is a VALUE type, and nothing else — a reference annotation and a
    // plain type both answer null, which is what stops the caller from unwrapping either of them.
    func UnwrapLiftedValueOperand(candidate: TypeInfo): TypeInfo? {
        nullable := declarationsValue.ResolveDeclaredAlias(candidate) as NullableTypeInfo
        if nullable == null {
            return null
        }

        inner := declarationsValue.ResolveDeclaredAlias(nullable.InnerType)
        if AnalyzerConversionFacts.IsReferenceType(inner) {
            return null
        }

        return inner
    }

    // C# §12.4.8'S LIFTED FORM OF EVERY BINARY OPERATOR THIS OWNER ALREADY ADMITS, and it is ONE
    // rule rather than one per family: unwrap whichever operands are a `T?` over a non-nullable VALUE
    // type, ask the UNLIFTED question of what is left, and wrap the answer back up.
    //
    // TWO RESULT SHAPES, BECAUSE C# HAS TWO. An ARITHMETIC, BITWISE or SHIFT answer is lifted --
    // `int? + int` is `int?`, absent exactly when an operand was absent -- while a COMPARISON is a
    // plain `bool`. The two comparison families reach that `bool` differently and both are right:
    // `x < y` is FALSE when either side is absent, so an ordering is always decided and nothing
    // downstream may narrow out of it, while two ABSENT values are EQUAL. EQUALITY's primitive,
    // enum and record-struct half is `CanCompareLiftedEquality`'s and is answered after this rule
    // declines; what this rule answers for equality is only its USER-DEFINED half, the `op_Equality`
    // an element type declares (`decimal? == decimal`), which that rule cannot see.
    //
    // IT CAN NEVER ADMIT A PAIR THE UNLIFTED RULE REFUSES, because the unlifted question is asked by
    // a PURE reader that reports nothing and answers null for every pair its reporting twin would
    // have complained about. A refusal therefore falls through to the ordinary arm, which states the
    // problem in the types the programmer WROTE -- `int? + string` is still about `'int?'`.
    //
    // BOTH OPERANDS MUST BE DEFINITELY NON-NULLABLE VALUE TYPES ONCE UNWRAPPED, which is C#'s own
    // requirement on a lifted form. A bare type parameter, a constructed generic and a reference
    // annotation all answer false to that question and are left to the rules that own them.
    func TryLiftedBinaryResult(op: BinaryOperator, left: TypeInfo, right: TypeInfo, out result: TypeInfo): bool {
        result = BuiltInTypes.Unknown
        if !IsArithmetic(op) && !IsBitwise(op) && !IsShift(op) && !IsRelational(op) && !IsEquality(op) {
            return false
        }

        unwrappedLeft := UnwrapLiftedValueOperand(left)
        unwrappedRight := UnwrapLiftedValueOperand(right)
        if unwrappedLeft == null && unwrappedRight == null {
            return false
        }

        liftedLeft := unwrappedLeft ?? declarationsValue.ResolveDeclaredAlias(left)
        liftedRight := unwrappedRight ?? declarationsValue.ResolveDeclaredAlias(right)
        if !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(liftedLeft) || !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(liftedRight) {
            return false
        }

        elementResult := UnliftedBinaryResultOrNull(op, liftedLeft, liftedRight)
        if elementResult == null {
            return false
        }

        if IsRelational(op) || IsEquality(op) {
            return LiftedComparisonResult(elementResult, out result)
        }

        if !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(elementResult) {
            return false
        }

        result = new NullableTypeInfo(elementResult)
        return true
    }

    // A LIFTED COMPARISON IS A `bool`, AND ONLY A `bool`. An operator overload that answered
    // something else was already refused by the unlifted reader, so the only answer that reaches
    // here is the one the comparison families produce.
    func LiftedComparisonResult(elementResult: TypeInfo, out result: TypeInfo): bool {
        result = BuiltInTypes.Unknown
        if !BuiltInTypes.Is(elementResult, BuiltInTypes.Bool) {
            return false
        }

        result = BuiltInTypes.Bool
        return true
    }

    // THE UNLIFTED QUESTION, ASKED WITHOUT REPORTING ANYTHING. Each arm is the DECIDING half of the
    // matching `*Result` rule with its diagnostics removed and in the same order: arithmetic promotes
    // and only then looks for an overload, bitwise reads its three domains (two booleans, the same
    // flags enum, two integrals), a shift is the UNARY promotion of its left operand alone, and a
    // comparison consults its overload FIRST and falls back to the primitive relational domain.
    //
    // IT IS A READER, NOT A SECOND RULE. Anything it answers null for is reported by the reporting
    // twin in terms of the written types, so the two can never disagree about what is legal.
    func UnliftedBinaryResultOrNull(op: BinaryOperator, left: TypeInfo, right: TypeInfo): TypeInfo? {
        overloadResult: TypeInfo = BuiltInTypes.Unknown

        if IsArithmetic(op) {
            if IsNumericType(left) && IsNumericType(right) {
                return WiderType(left, right)
            }

            if TryResolveBinaryOperatorOverload(op, left, right, out overloadResult) {
                return overloadResult
            }

            return null
        }

        if IsBitwise(op) {
            if BuiltInTypes.Is(left, BuiltInTypes.Bool) && BuiltInTypes.Is(right, BuiltInTypes.Bool) {
                return BuiltInTypes.Bool
            }

            if IsSameBitwiseEnumType(left, right) {
                return left
            }

            if IsIntegralType(left) && IsIntegralType(right) {
                return WiderType(left, right)
            }

            if TryResolveBinaryOperatorOverload(op, left, right, out overloadResult) {
                return overloadResult
            }

            return null
        }

        if IsShift(op) {
            if IsIntegralType(left) && IsIntegralType(right) {
                return UnaryNumericPromotionType(left)
            }

            if TryResolveBinaryOperatorOverload(op, left, right, out overloadResult) {
                return overloadResult
            }

            return null
        }

        // EQUALITY'S LIFTED FORM IS ONLY ITS OPERATOR-OVERLOAD HALF. The PRIMITIVE, enum and
        // record-struct halves are `CanCompareLiftedEquality`'s, and it answers them before this
        // reader is ever asked; what it cannot answer is a user-defined `op_Equality` on an
        // element type -- which is why `decimal? == decimal` and `TimeSpan? == TimeSpan` needed a
        // door of their own. Anything with no overload declines and falls back to that rule.
        if IsEquality(op) {
            if TryResolveBinaryOperatorOverload(op, left, right, out overloadResult) && assignabilityValue.IsAssignable(BuiltInTypes.Bool, overloadResult) {
                return BuiltInTypes.Bool
            }

            return null
        }

        if TryResolveBinaryOperatorOverload(op, left, right, out overloadResult) {
            if assignabilityValue.IsAssignable(BuiltInTypes.Bool, overloadResult) {
                return BuiltInTypes.Bool
            }

            return null
        }

        if IsPrimitiveRelationalType(left) && IsPrimitiveRelationalType(right) && WiderType(left, right) != null {
            return BuiltInTypes.Bool
        }

        return null
    }

    // THE UNARY TWIN OF THE SAME LIFT. `-x`, `~x` and `!x` over a `T?` answer `R?` -- absent in,
    // absent out -- and `++`/`--` answer the OPERAND'S OWN type, exactly as they do unlifted:
    // the value is written back into the storage it came from, so `count: int?` stays an `int?`.
    func TryLiftedUnaryResult(op: UnaryOperator, operandType: TypeInfo, out result: TypeInfo): bool {
        result = BuiltInTypes.Unknown
        if op == UnaryOperator.IndexFromEnd {
            return false
        }

        unwrapped := UnwrapLiftedValueOperand(operandType)
        if unwrapped == null || !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(unwrapped) {
            return false
        }

        elementResult := UnliftedUnaryResultOrNull(op, unwrapped)
        if elementResult == null || !AnalyzerConversionFacts.IsDefinitelyNonNullableValueType(elementResult) {
            return false
        }

        if IsIncrementOrDecrement(op) {
            result = operandType
            return true
        }

        result = new NullableTypeInfo(elementResult)
        return true
    }

    // The unary reader, and the same discipline: the deciding half of `NegationResult`,
    // `LogicalNotResult`, `BitwiseNotResult` and `IncrementOrDecrementResult` with every report
    // removed. The negated-literal door is deliberately absent -- a literal is never a `T?`.
    func UnliftedUnaryResultOrNull(op: UnaryOperator, operand: TypeInfo): TypeInfo? {
        overloadResult: TypeInfo = BuiltInTypes.Unknown
        if TryResolveUnaryOperatorOverload(op, operand, out overloadResult) {
            return overloadResult
        }

        if op == UnaryOperator.Negate {
            return UnaryNegationType(operand)
        }

        if op == UnaryOperator.Not {
            if BuiltInTypes.Is(operand, BuiltInTypes.Bool) {
                return BuiltInTypes.Bool
            }

            return null
        }

        if op == UnaryOperator.BitwiseNot {
            if IsBitwiseEnumType(operand) {
                return operand
            }

            promoted := UnaryNumericPromotionType(operand)
            if promoted != null && IsIntegralType(promoted) {
                return promoted
            }

            return null
        }

        if IsIncrementOrDecrement(op) {
            if IsIntegralType(operand) || IsBitwiseEnumType(operand) {
                return operand
            }

            return null
        }

        return null
    }

    // BOOLEANS COMPARE ONLY WITH BOOLEANS. The test is asymmetric on purpose: one boolean side makes
    // the whole question a boolean one, so `true == 1` is refused here rather than falling through
    // to the numeric rule.
    func ArePrimitiveEqualityTypesCompatible(left: TypeInfo, right: TypeInfo): bool {
        leftIsBool := IsBoolLikeType(left)
        rightIsBool := IsBoolLikeType(right)
        if leftIsBool || rightIsBool {
            return leftIsBool && rightIsBool
        }

        if !IsPrimitiveRelationalType(left) || !IsPrimitiveRelationalType(right) {
            return false
        }

        return WiderType(left, right) != null
    }

    func IsBoolLikeType(candidate: TypeInfo): bool {
        resolved := declarationsValue.ResolveDeclaredAlias(candidate)
        if BuiltInTypes.Is(resolved, BuiltInTypes.Bool) {
            return true
        }

        simple := resolved as SimpleTypeInfo
        if simple != null {
            if simple.Name == "bool" || simple.Name == "Boolean" {
                return true
            }
        }

        reflection := resolved as ReflectionTypeInfo
        return reflection != null && reflection.Type == typeof(bool)
    }

    static func IsSameRecordStructType(left: TypeInfo, right: TypeInfo): bool {
        if !Object.ReferenceEquals(left, right) {
            return false
        }

        recordType := left as RecordTypeInfo
        return recordType != null && recordType.IsStruct
    }

    // A FLAGS ENUM IS AN `int`-BACKED ONE, or any reflected enum. A `string`-backed enum has no
    // bitwise meaning and is excluded, which is why the declaration's backing type is read rather
    // than merely asking whether the type is an enum.
    func IsBitwiseEnumType(candidate: TypeInfo): bool {
        resolved := declarationsValue.ResolveDeclaredAlias(candidate)
        enumType := resolved as EnumTypeInfo
        if enumType != null {
            return enumType.Declaration.Type == EnumType.Int
        }

        reflection := resolved as ReflectionTypeInfo
        return reflection != null && reflection.Type.get_IsEnum()
    }

    func IsSameBitwiseEnumType(left: TypeInfo, right: TypeInfo): bool {
        resolvedLeft := declarationsValue.ResolveDeclaredAlias(left)
        resolvedRight := declarationsValue.ResolveDeclaredAlias(right)
        leftEnum := resolvedLeft as EnumTypeInfo
        rightEnum := resolvedRight as EnumTypeInfo
        if leftEnum != null && rightEnum != null {
            return leftEnum.Declaration.Type == EnumType.Int && rightEnum.Declaration.Type == EnumType.Int && Object.ReferenceEquals(leftEnum, rightEnum)
        }

        leftReflection := resolvedLeft as ReflectionTypeInfo
        rightReflection := resolvedRight as ReflectionTypeInfo
        if leftReflection != null && rightReflection != null {
            return leftReflection.Type.get_IsEnum() && rightReflection.Type.get_IsEnum() && leftReflection.Type == rightReflection.Type
        }

        return false
    }

    // THE TWO WELL-KNOWN TYPES THIS FAMILY ANSWERS. The scope is asked first so that a project which
    // declares its own `System.Range` gets that one; the reflected type is the fallback.
    func RangeType(): TypeInfo {
        named := scopesValue.LookupType("System.Range")
        if named != null {
            return named
        }

        return new ReflectionTypeInfo(typeof(Range))
    }

    func IndexType(): TypeInfo {
        named := scopesValue.LookupType("System.Index")
        if named != null {
            return named
        }

        return new ReflectionTypeInfo(typeof(Index))
    }

    static func IsShortCircuit(op: BinaryOperator): bool {
        return op == BinaryOperator.And || op == BinaryOperator.Or
    }

    static func IsEquality(op: BinaryOperator): bool {
        return op == BinaryOperator.Equal || op == BinaryOperator.NotEqual
    }

    static func IsBitwise(op: BinaryOperator): bool {
        return op == BinaryOperator.BitwiseAnd || op == BinaryOperator.BitwiseOr || op == BinaryOperator.BitwiseXor
    }

    static func IsArithmetic(op: BinaryOperator): bool {
        return op == BinaryOperator.Add || op == BinaryOperator.Subtract || op == BinaryOperator.Multiply || op == BinaryOperator.Divide || op == BinaryOperator.Modulo
    }

    static func IsRelational(op: BinaryOperator): bool {
        return op == BinaryOperator.Less || op == BinaryOperator.LessOrEqual || op == BinaryOperator.Greater || op == BinaryOperator.GreaterOrEqual
    }

    static func IsIncrementOrDecrement(op: UnaryOperator): bool {
        return op == UnaryOperator.PreIncrement || op == UnaryOperator.PreDecrement || op == UnaryOperator.PostIncrement || op == UnaryOperator.PostDecrement
    }

    // THE OPERATOR'S SYMBOL AS THE WRITE-TARGET REPORTS SPELL IT. `GetUnarySymbol` answers null for
    // an operator with no CLR symbol, and the host's fallback word is what the programmer then reads.
    static func UnarySymbolText(op: UnaryOperator): string {
        symbol := OperatorFacts.GetUnarySymbol(op)
        if symbol != null {
            return symbol
        }

        return "operator"
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
