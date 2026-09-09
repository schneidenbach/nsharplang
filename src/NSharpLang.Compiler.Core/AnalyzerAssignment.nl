namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE ONE STEP AN ASSIGNMENT TAKES, AND WHY TEN WALK SITES ARE ONE KIND.
//
// `a = b` walks exactly two expressions — the target and the value — but the arm reaches a walk from
// TEN places, because six of its refusals still walk the value afterwards so the developer is told
// about errors inside it too. Every one of those ten is the ORDINARY dispatch; not one is the
// named-expected-type walk, so there is no lambda fork anywhere in the arm and nothing this owner
// would have to simulate. What differs between the ten is only what is IN FORCE around them, and
// every one of those brackets is opened and closed by this owner:
//
//   * the TARGET walk runs with the nullability flow type suppressed, the error-tuple result use
//     suppressed exactly when the operator is a plain `=`, bare event references allowed, and — when
//     the target is a member or index chain — a fresh sub-expression capture table installed;
//   * four of the value walks run under the TARGET'S TYPE as the expected type, which is what makes
//     `total: byte = 0` and `total += 300` read the target's width;
//   * and five run under nothing at all.
//
//   1  analyse an expression. Handed out up to twice per walk, and the driver performs it the same
//      way every time.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class AssignmentRequest {
    Kind: int
    Node: Expression?

    constructor(kind: int, node: Expression?) {
        Kind = kind
        Node = node
    }
}

// THE WHOLE STATE, SUSPENDED ACROSS AT MOST TWO STEPS.
//
// `Phase` names WHICH step is outstanding, and the phases are not a sequence — they are a FORK. 0 is
// the entry; 1, 2 and 3 are the three shapes the entry can hand out; 4, 5, 6 and 7 are the four
// shapes the TARGET answer can hand out. Every one of them ends at 99.
//
//   1  the DISCARD value.                      2  a REFUSED value, walked plain.
//   3  the TARGET.                             4  a REFUSED value, walked under the target's type.
//   5  the EVENT value.                        6  a REFUSED value after a target-shape refusal.
//   7  the ORDINARY value.
//
// Phases 2 and 6 perform the same operation and are kept apart because they are reached from opposite
// sides of the target walk — folding them would make the state unable to say whether the target was
// ever walked, which is what decides whether the capture table exists.
//
// `TargetType` is the answer the target gave, and it is also the RESULT of a successful assignment:
// `a = b = c` reads the inner assignment as `b`'s type, not as `c`'s. `ExpressionTypes` is the
// capture table this walk opened, held on the state rather than read back from the ambient slot
// because the slot is CLEARED when the target bracket closes and the write-target rules that run
// afterwards still need it — which is exactly what the C# local did.
class AssignmentState {
    assignmentValue: AssignmentExpression?

    Assignment: AssignmentExpression? => assignmentValue

    Phase: int
    ResultType: TypeInfo
    TargetType: TypeInfo
    ExpressionTypes: Dictionary<object, TypeInfo>?
    SavedExpectedType: TypeInfo?
    SavedSuppressFlowType: bool
    SavedSuppressErrorTupleResultUse: bool
    SavedAllowEventReference: bool

    constructor(assignment: AssignmentExpression?) {
        assignmentValue = assignment
        Phase = 0
        ResultType = BuiltInTypes.Unknown
        TargetType = BuiltInTypes.Unknown
        ExpressionTypes = null
        SavedExpectedType = null
        SavedSuppressFlowType = false
        SavedSuppressErrorTupleResultUse = false
        SavedAllowEventReference = false
    }
}

// WHAT AN ASSIGNMENT MEANS.
//
// THE ORDER OF THE GATES IS THE BEHAVIOUR, and it is not the order a reader would guess. After the
// target has been walked, eight questions are asked in exactly the order `Analyzer.cs` asked them,
// and the first that refuses ends the walk with `unknown` — but never before the value has been
// walked too, because an error in the value is the developer's problem whether or not the target was
// valid:
//   1  the target is a SoA ROW VIEW, which can never be stored anywhere.
//   2  the target is a .NET EVENT. N# never assigns events; `on` subscribes and `off` unsubscribes,
//      and the three operators get three different sentences because they are three different
//      mistaken beliefs about what `+=` on an event does.
//   3  the target is a SoA TABLE MEMBER; 4 an unsupported BUILT-IN INDEXED mutation — both the
//      write-target family's, and both asked with the capture table this walk opened.
//   5  the target is not an ASSIGNABLE SHAPE at all.
//   6  the target is a READ-ONLY PROPERTY.
//   7  `??=` on a target that can never be null, which is a warning about a useless operator rather
//      than a refusal — it reports and CONTINUES.
//   8  NL322: a member write whose receiver chain bottoms out in a value-typed TEMPORARY. This one is
//      deliberately UNDER-enforcing: a hop whose type or member cannot be resolved never fires, so a
//      shape the analyzer does not model keeps compiling exactly as it did.
//
// AND THEN THE TWO THAT RUN AFTER THE VALUE: the READONLY FIELD rule, and the assignability gate.
//
// THE ASSIGNABILITY GATE IS THE LOAD-BEARING ONE. `EmitValueCoercion` silently no-ops for closed
// generics over emitted user types, so this check is the ONLY thing between `items: List<Rs>` stored
// into a `List<Pt>` field and a type-confused read at run time. It keeps both of its renderings — the
// rich `ErrorMessageBuilder.TypeMismatch` when a source snippet AND a file path exist, the bare
// report otherwise — because the rich one carries the source line a developer actually reads. The
// two renderings say the SAME SENTENCE; they differ only in how much they add to it.
//
// THE COMPOUND FORM IS AN OPERATOR QUESTION AND IS ASKED AS ONE. `x += y` is checked by building the
// binary expression it means and asking the operator family what that is worth, then whether the
// answer fits back into the target. That call used to be the arc's only non-walk door from
// `Analyzer.cs` into an expression owner; it is now one N# owner asking another, and the door is
// gone. `+=`/`-=` on a DELEGATE-like target skip the rule entirely, because delegate combination is
// not an arithmetic operator and has no result type to check.
class AnalyzerAssignment {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    ambientValue: AnalyzerAmbientContext
    nullFlowValue: AnalyzerNullFlow
    soaEscapeValue: AnalyzerSoaEscape
    identifierResolutionValue: AnalyzerIdentifierResolution
    assignabilityValue: AnalyzerAssignability
    assignabilityFactsValue: AnalyzerAssignabilityFacts
    writeTargetsValue: AnalyzerWriteTargets
    operatorExpressionsValue: AnalyzerOperatorExpressions

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, ambient: AnalyzerAmbientContext, nullFlow: AnalyzerNullFlow, soaEscape: AnalyzerSoaEscape, identifierResolution: AnalyzerIdentifierResolution, assignability: AnalyzerAssignability, assignabilityFacts: AnalyzerAssignabilityFacts, writeTargets: AnalyzerWriteTargets, operatorExpressions: AnalyzerOperatorExpressions) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        ambientValue = ambient
        nullFlowValue = nullFlow
        soaEscapeValue = soaEscape
        identifierResolutionValue = identifierResolution
        assignabilityValue = assignability
        assignabilityFactsValue = assignabilityFacts
        writeTargetsValue = writeTargets
        operatorExpressionsValue = operatorExpressions
    }

    // THE ENTRY, AND IT DECIDES NOTHING. Nothing about an assignment can be answered before at least
    // one of its two operands has been walked. A node that is not an assignment takes no steps.
    func Begin(expression: Expression): AssignmentState {
        assignment := expression as AssignmentExpression
        state := new AssignmentState(assignment)
        if assignment == null {
            state.Phase = 99
        }

        return state
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished.
    //
    // TWO PHASES HAND OUT STEPS AND THE REST ONLY ANSWER THEM. Phase 0 is the entry fork; phase 30 is
    // the GATE SEQUENCE, which runs after the target has answered and which reaches a value walk on
    // every path. The gates live here rather than in `Supply` because they are the decision about
    // WHICH walk comes next, and a phase machine whose answer handler also chose the next step could
    // not be read in one direction.
    func NextStep(state: AssignmentState): AssignmentRequest? {
        if state.Phase == 0 {
            return AdvanceEntry(state)
        }

        if state.Phase == 30 {
            return AdvanceAfterTarget(state)
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP. A null answer is `unknown` rather than a missing one — the
    // analyzer's expression walk never answers null, and a walk that saw one would carry it into a
    // report.
    func Supply(state: AssignmentState, answer: TypeInfo?) {
        answered: TypeInfo = BuiltInTypes.Unknown
        if answer != null {
            answered = answer
        }

        phase := state.Phase
        if phase == 1 {
            DiscardValueAnswered(state, answered)
            return
        }

        if phase == 2 || phase == 6 {
            RefusedValueAnswered(state, answered)
            return
        }

        if phase == 3 {
            TargetAnswered(state, answered)
            return
        }

        if phase == 4 {
            BracketedRefusedValueAnswered(state, answered)
            return
        }

        if phase == 5 {
            EventValueAnswered(state)
            return
        }

        if phase == 7 {
            ValueAnswered(state, answered)
            return
        }

        state.Phase = 99
    }

    func Result(state: AssignmentState): TypeInfo {
        return state.ResultType
    }

    // THE FORK BEFORE ANYTHING IS WALKED. A discard binds nothing, so its target is never analysed at
    // all; a null-conditional target is refused before it is analysed, because there is no storage to
    // write into; everything else walks its target under the four-part bracket below.
    func AdvanceEntry(state: AssignmentState): AssignmentRequest? {
        assignment := state.Assignment
        if assignment == null {
            state.Phase = 99
            return null
        }

        if IsDiscardTarget(assignment.Target) {
            if assignment.Operator != AssignmentOperator.Assign {
                span := spansValue.GetExpressionDiagnosticSpan(assignment.Target)
                diagnosticsValue.Report(ErrorCode.InvalidSyntax, "The discard `_` can only be used with a plain `=` assignment", span.Line, span.Column, "Use `_ = expr` to discard a value, or assign to a named variable for compound operators.", span.Length)
            }

            state.Phase = 1
            return new AssignmentRequest(1, assignment.Value)
        }

        if writeTargetsValue.ReportNullConditionalWriteTargetIfNeeded(assignment.Target, "assigned with '" + OperatorFacts.GetAssignmentText(assignment.Operator) + "'") {
            state.Phase = 2
            return new AssignmentRequest(1, assignment.Value)
        }

        // THE TARGET BRACKET, ALL FOUR PARTS, opened in the same instant the step is handed out.
        // The flow type is suppressed because a target is a STORAGE LOCATION and its narrowed type is
        // not what is being written to. The error-tuple suppression is conditional on a plain `=`,
        // because a compound operator READS the target first and a `must`-typed read is a real use.
        // Bare event references are allowed so the event gate below can raise its own sentence rather
        // than the generic "an event is not a value". And the capture table is opened only for a
        // member or index chain, because its PRESENCE is observable.
        state.SavedSuppressFlowType = nullFlowValue.SuppressFlowType
        state.SavedSuppressErrorTupleResultUse = identifierResolutionValue.SuppressErrorTupleResultUse
        nullFlowValue.SetSuppressFlowType(true)
        identifierResolutionValue.SetSuppressErrorTupleResultUse(assignment.Operator == AssignmentOperator.Assign)
        state.SavedAllowEventReference = ambientValue.EnterAllowEventReference()
        if AnalyzerWriteTargets.IsWriteTargetNeedingExpressionTypes(assignment.Target) {
            ambientValue.EnterWriteTargetExpressionTypes()
            state.ExpressionTypes = ambientValue.WriteTargetExpressionTypes
        }

        state.Phase = 3
        return new AssignmentRequest(1, assignment.Target)
    }

    // A DISCARD ANSWERS ITS VALUE'S TYPE, and both escape reports run — neither short-circuits the
    // other, because they name different problems with the same expression.
    func DiscardValueAnswered(state: AssignmentState, discardedType: TypeInfo) {
        state.Phase = 99
        assignment := state.Assignment
        if assignment == null {
            return
        }

        soaEscapeValue.ReportSoaRowEscapeIfNeeded(assignment.Value, discardedType, "discarded")
        soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(assignment.Value, "discarded")
        state.ResultType = discardedType
    }

    // A REFUSED ASSIGNMENT STILL REPORTS A ROW VIEW ESCAPING THROUGH ITS VALUE, and then answers
    // `unknown` so no caller piles a second diagnostic onto the same expression.
    func RefusedValueAnswered(state: AssignmentState, valueType: TypeInfo) {
        state.Phase = 99
        state.ResultType = BuiltInTypes.Unknown
        assignment := state.Assignment
        if assignment == null {
            return
        }

        if valueType as SoaRowTypeInfo != null {
            soaEscapeValue.ReportSoaRowEscape(assignment.Value, "assigned")
        }
    }

    // The same, with the expected-type bracket the three target-shape refusals opened around the walk.
    func BracketedRefusedValueAnswered(state: AssignmentState, valueType: TypeInfo) {
        ambientValue.ExitExpectedType(state.SavedExpectedType)
        state.SavedExpectedType = null
        RefusedValueAnswered(state, valueType)
    }

    // An event assignment has already been reported; the value was walked only so errors inside the
    // handler surface, and its type is deliberately discarded.
    func EventValueAnswered(state: AssignmentState) {
        state.Phase = 99
        state.ResultType = BuiltInTypes.Unknown
    }

    // THE TARGET HAS ANSWERED. The bracket closes FIRST, before any gate runs, because every one of
    // these reports ran in the C# with the four slots already restored — a report is free to consult
    // the ambient context and would see the wrong thing otherwise.
    func TargetAnswered(state: AssignmentState, targetType: TypeInfo) {
        ambientValue.ClearWriteTargetExpressionTypes()
        ambientValue.ExitAllowEventReference(state.SavedAllowEventReference)
        identifierResolutionValue.SetSuppressErrorTupleResultUse(state.SavedSuppressErrorTupleResultUse)
        nullFlowValue.SetSuppressFlowType(state.SavedSuppressFlowType)
        state.TargetType = targetType
        state.Phase = 30
    }

    // THE EIGHT GATES, IN THE ONE ORDER THAT IS THE BEHAVIOUR. Each of the first six ends the walk
    // with `unknown` — but never before the value has been walked, which is why every one of them
    // hands out a step rather than returning.
    func AdvanceAfterTarget(state: AssignmentState): AssignmentRequest? {
        assignment := state.Assignment
        if assignment == null {
            state.Phase = 99
            return null
        }

        targetType := state.TargetType
        expressionTypes := state.ExpressionTypes

        if targetType as SoaRowTypeInfo != null {
            soaEscapeValue.ReportSoaRowEscape(assignment.Target, "assigned")
            return EnterRefusedValue(state, targetType)
        }

        eventTarget := targetType as ReflectionEventInfo
        if eventTarget != null {
            ReportEventAssignment(assignment, eventTarget)
            state.Phase = 5
            return new AssignmentRequest(1, assignment.Value)
        }

        if writeTargetsValue.ReportSoaTableMemberMutationIfNeeded(assignment.Target, expressionTypes, "assigned directly") {
            return EnterRefusedValue(state, targetType)
        }

        if writeTargetsValue.ReportUnsupportedBuiltInIndexedMutationIfNeeded(assignment.Target, expressionTypes, "assigned") {
            return EnterRefusedValue(state, targetType)
        }

        if ReportInvalidAssignmentTargetIfNeeded(assignment) {
            state.Phase = 6
            return new AssignmentRequest(1, assignment.Value)
        }

        if writeTargetsValue.ReportReadOnlyPropertyWriteTargetIfNeeded(assignment.Target, OperatorFacts.GetAssignmentText(assignment.Operator), expressionTypes) {
            state.Phase = 6
            return new AssignmentRequest(1, assignment.Value)
        }

        CheckNullCoalesceAssignmentTarget(assignment, targetType)

        memberWriteTarget := assignment.Target as MemberAccessExpression
        if memberWriteTarget != null && expressionTypes != null {
            CheckMemberWriteReceiverIsVariable(memberWriteTarget, expressionTypes)
        }

        state.SavedExpectedType = ambientValue.EnterExpectedType(targetType)
        state.Phase = 7
        return new AssignmentRequest(1, assignment.Value)
    }

    // The three target-shape refusals all walk the value under the TARGET'S type, which is what the
    // C# did: a refused target still target-types its value, so the value's own diagnostics are the
    // ones the developer would have got had the target been legal.
    func EnterRefusedValue(state: AssignmentState, targetType: TypeInfo): AssignmentRequest? {
        assignment := state.Assignment
        if assignment == null {
            state.Phase = 99
            state.ResultType = BuiltInTypes.Unknown
            return null
        }

        state.SavedExpectedType = ambientValue.EnterExpectedType(targetType)
        state.Phase = 4
        return new AssignmentRequest(1, assignment.Value)
    }

    // THE VALUE HAS ANSWERED, and the last four rules run in order. The null-state update and the
    // error-tuple mark run even when the assignability gate refused, because the store is still what
    // the developer wrote and the flow after it should describe that.
    func ValueAnswered(state: AssignmentState, valueType: TypeInfo) {
        ambientValue.ExitExpectedType(state.SavedExpectedType)
        state.SavedExpectedType = null
        state.Phase = 99

        assignment := state.Assignment
        if assignment == null {
            return
        }

        targetType := state.TargetType
        if valueType as SoaRowTypeInfo != null {
            soaEscapeValue.ReportSoaRowEscape(assignment.Value, "assigned")
        } else {
            soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(assignment.Value, "assigned")
        }

        writeTargetsValue.ReportReadonlyFieldAssignmentIfNeeded(assignment.Target, assignment.Line, assignment.Column, state.ExpressionTypes)

        // 023/1e — the assignment position HAS `assignment.Value`, so it asks the constant-aware form.
        // This is the position `b[0] = 65` reaches: an element store is an assignment whose target is an
        // index expression, and the constant conversion onto the element type is decided here.
        if !assignabilityValue.IsAssignableWithConstant(targetType, valueType, ConstantOperandFacts.FromExpression(assignment.Value)) {
            ReportAssignmentTypeMismatch(assignment, targetType, valueType)
        } else if ReportInvalidCompoundAssignmentIfNeeded(assignment, targetType, valueType) {
            state.ResultType = BuiltInTypes.Unknown
            return
        }

        nullFlowValue.UpdateNullStateAfterAssignment(assignment.Target, assignment.Value, targetType, valueType)
        scopesValue.MarkErrorTupleResultAvailableAfterAssignment(assignment.Target)
        state.ResultType = targetType
    }

    // THE FRONT DOOR, IN BOTH ITS RENDERINGS, AND THE SENTENCE DOES NOT DEPEND ON WHICH ONE. The rich
    // builder adds the source line, the caret and the docs link; the bare report is what a diagnostic
    // with no file behind it can still say. Naming the two types is the report's whole job, so it is
    // done above the branch.
    func ReportAssignmentTypeMismatch(assignment: AssignmentExpression, targetType: TypeInfo, valueType: TypeInfo) {
        span := spansValue.GetExpressionDiagnosticSpan(assignment.Value)
        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        message := "Type mismatch in assignment — expected '" + TypeText(targetType) + "' but got '" + TypeText(valueType) + "'"
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.TypeMismatch(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, TypeText(valueType), TypeText(targetType), message))
            return
        }

        diagnosticsValue.Report(ErrorCode.TypeMismatch, message, span.Line, span.Column, null, span.Length)
    }

    // ------------------------------------------------------------------------------------------
    // THE ARM'S OWN RULES.
    // ------------------------------------------------------------------------------------------

    // `_` IS THE SANCTIONED ESCAPE HATCH for a must-use result, and it is a plain-`=` shape only:
    // `_ += x` has nothing to read from and nothing to write to.
    static func IsDiscardTarget(target: Expression): bool {
        identifier := target as IdentifierExpression
        return identifier != null && identifier.Name == "_"
    }

    // WHAT MAY APPEAR ON THE LEFT AT ALL — a name, a member, an index, or any of those in brackets.
    // A call result, a literal or an operator expression is refused here rather than later, which is
    // what makes `1 = x` a sentence about assignable targets instead of a type mismatch.
    static func IsAssignmentTarget(expression: Expression): bool {
        if expression as IdentifierExpression != null || expression as MemberAccessExpression != null || expression as IndexAccessExpression != null {
            return true
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return IsAssignmentTarget(parenthesized.Inner)
        }

        return false
    }

    func ReportInvalidAssignmentTargetIfNeeded(assignment: AssignmentExpression): bool {
        if IsAssignmentTarget(assignment.Target) {
            return false
        }

        opText := OperatorFacts.GetAssignmentText(assignment.Operator)
        span := spansValue.GetExpressionDiagnosticSpan(assignment.Target)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "The '" + opText + "' assignment needs an assignable target", span.Line, span.Column, "Use a variable, field, property, indexed element, or `_` discard as the left side.", span.Length)
        return true
    }

    // `??=` ON A TARGET THAT CANNOT BE NULL is a mistake about the target's type rather than about the
    // operator, so the sentence names the type. `unknown` is admitted because a target that already
    // failed to resolve should not collect a second complaint.
    func CheckNullCoalesceAssignmentTarget(assignment: AssignmentExpression, targetType: TypeInfo) {
        if assignment.Operator != AssignmentOperator.NullCoalesceAssign {
            return
        }

        if CanNullCoalesceCheckForNull(targetType) {
            return
        }

        span := spansValue.GetExpressionDiagnosticSpan(assignment.Target)
        diagnosticsValue.Report(ErrorCode.TypeMismatch, "The left side of '??=' has type '" + TypeText(targetType) + "', which can't be null", span.Line, span.Column, "Use '=' for values that are always present, or make the target nullable before using '??='.", span.Length)
    }

    // A GENERIC PARAMETER COUNTS, because the substituted type may well be a reference type and a
    // rule that refused `T` would refuse a correct program.
    func CanNullCoalesceCheckForNull(candidate: TypeInfo): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        if BuiltInTypes.IsUnknown(resolved) || resolved as GenericTypeInfo != null || resolved as NullableTypeInfo != null {
            return true
        }

        if AnalyzerConversionFacts.IsReferenceType(resolved) {
            return true
        }

        reflection := resolved as ReflectionTypeInfo
        return reflection != null && Nullable.GetUnderlyingType(reflection.Type) != null
    }

    // THREE OPERATORS, THREE BELIEFS, THREE SENTENCES. `-=` believes it can unsubscribe, `+=` believes
    // it can subscribe, `=` believes an event is a field. Each is told what to write instead, with the
    // developer's own target text rendered back at them.
    func ReportEventAssignment(assignment: AssignmentExpression, eventTarget: ReflectionEventInfo) {
        span := spansValue.GetExpressionDiagnosticSpan(assignment.Target)
        target := RenderEventTarget(assignment.Target)
        name := eventTarget.Name

        message := "'" + name + "' is a .NET event — it can't be assigned with '='"
        hint := "Subscribe with `on " + target + " (sender, args) => { ... }` and unsubscribe with `off`."
        if assignment.Operator == AssignmentOperator.SubtractAssign {
            message = "'" + name + "' is a .NET event — it can't be unsubscribed with '-='"
            hint = "Capture the subscription when you subscribe (`sub := on " + target + " handler`), then detach it with `off sub`."
        } else if assignment.Operator == AssignmentOperator.AddAssign {
            message = "'" + name + "' is a .NET event — it can't be subscribed to with '+='"
            hint = "Subscribe with `on " + target + " (sender, args) => { ... }`; it returns a subscription you can later pass to `off`."
        }

        diagnosticsValue.Report(ErrorCode.EventRequiresOnOff, message, span.Line, span.Column, hint, span.Length)
    }

    // THE TARGET AS THE DEVELOPER WROTE IT, rebuilt from the AST rather than from the source text so
    // it reads the same however the expression was spaced. PUBLISHED: two other reports about the same
    // kind of mistake — an event used as a value, and a generated SoA operation used as a value —
    // render their target the same way and must keep saying it identically.
    static func RenderEventTarget(expression: Expression): string {
        identifier := expression as IdentifierExpression
        if identifier != null {
            return identifier.Name
        }

        if expression as ThisExpression != null {
            return "this"
        }

        if expression as BaseExpression != null {
            return "base"
        }

        member := expression as MemberAccessExpression
        if member != null {
            return RenderEventTarget(member.Object) + "." + member.MemberName
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return RenderEventTarget(parenthesized.Inner)
        }

        cast := expression as CastExpression
        if cast != null {
            return RenderEventTarget(cast.Expression)
        }

        return "<event>"
    }

    // ------------------------------------------------------------------------------------------
    // NL322 — A MEMBER WRITE THROUGH A VALUE COPY.
    // ------------------------------------------------------------------------------------------

    // The store would land in a TEMPORARY and be silently discarded, which is the defect this rule
    // exists to make loud. It is CONSERVATIVE by design: an unresolvable hop answers "stay silent",
    // so a shape the analyzer does not model keeps compiling exactly as it did before the rule
    // existed. Compound operators are covered too — they read-modify-write through the same receiver.
    func CheckMemberWriteReceiverIsVariable(target: MemberAccessExpression, expressionTypes: Dictionary<object, TypeInfo>) {
        offender := FindValueCopyReceiver(target.Object, expressionTypes)
        if offender == null {
            return
        }

        // A CHAIN HOP THE TABLE DOES NOT KNOW still gets a report, named `unknown` — the C# read the
        // failed lookup's null and coalesced it, which is the same thing said differently.
        offenderType: TypeInfo = BuiltInTypes.Unknown
        lookedUpType: TypeInfo = BuiltInTypes.Unknown
        if expressionTypes.TryGetValue(offender, out lookedUpType) {
            offenderType = lookedUpType
        }

        receiverDescription := "a temporary value (a copy)"
        if offender as IndexAccessExpression != null {
            receiverDescription = "an indexer result (a copy of the element)"
        } else if offender as CallExpression != null {
            receiverDescription = "a call result (a copy of the return value)"
        } else if offender as MemberAccessExpression != null {
            receiverDescription = "a property result (a copy of the value)"
        }

        typeName := TypeText(declarationContextValue.ResolveDeclaredAlias(offenderType))
        if typeName.Length == 0 {
            typeName = "value"
        }

        span := spansValue.GetExpressionDiagnosticSpan(offender)
        sourceSnippet := diagnosticsValue.SourceSnippet(span.Line)
        currentFilePath := diagnosticsValue.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnosticsValue.ReportBuilt(ErrorMessageBuilder.MemberWriteThroughValueCopy(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, target.MemberName, typeName, receiverDescription))
            return
        }

        diagnosticsValue.Report(ErrorCode.MemberWriteThroughValueCopy, "Cannot assign to '" + target.MemberName + "' because its receiver is a temporary copy of '" + typeName + "', not a variable", span.Line, span.Column, "Copy the value into a local first, modify the local, then store the whole value back", span.Length)
    }

    // THE OFFENDING HOP, or null when the chain is rooted in addressable storage — or is reference
    // typed, or cannot be resolved. A local, a parameter, a bare field, `this`, `base` and an ARRAY
    // ELEMENT are all real variables; a FIELD hop passes the question to its own receiver, because a
    // field of a variable is a variable; and everything else is a copy.
    func FindValueCopyReceiver(receiver: Expression, expressionTypes: Dictionary<object, TypeInfo>): Expression? {
        parenthesized := receiver as ParenthesizedExpression
        if parenthesized != null {
            return FindValueCopyReceiver(parenthesized.Inner, expressionTypes)
        }

        receiverType: TypeInfo = BuiltInTypes.Unknown
        if !expressionTypes.TryGetValue(receiver, out receiverType) {
            return null
        }

        if !IsProvenValueTypeReceiver(declarationContextValue.ResolveDeclaredAlias(receiverType)) {
            return null
        }

        if receiver as IdentifierExpression != null || receiver as ThisExpression != null || receiver as BaseExpression != null {
            return null
        }

        arrayElement := receiver as IndexAccessExpression
        if arrayElement != null {
            indexedType: TypeInfo = BuiltInTypes.Unknown
            if expressionTypes.TryGetValue(arrayElement.Object, out indexedType) && declarationContextValue.ResolveDeclaredAlias(indexedType) as ArrayTypeInfo != null {
                return null
            }

            return receiver
        }

        hop := receiver as MemberAccessExpression
        if hop != null {
            hopIsField := false
            if !writeTargetsValue.TryClassifyInstanceFieldHop(hop, expressionTypes, out hopIsField) {
                return null
            }

            if !hopIsField {
                return receiver
            }

            return FindValueCopyReceiver(hop.Object, expressionTypes)
        }

        return receiver
    }

    // PROVABLY a value type — a user struct, a record struct, or an external CLR value type. Anything
    // unresolved or reference-like answers false, so the rule never fires on a shape it cannot prove.
    static func IsProvenValueTypeReceiver(candidate: TypeInfo): bool {
        if candidate as StructTypeInfo != null {
            return true
        }

        recordType := candidate as RecordTypeInfo
        if recordType != null {
            return recordType.IsStruct
        }

        reflected := candidate as ReflectionTypeInfo
        return reflected != null && reflected.Type.get_IsValueType()
    }

    // ------------------------------------------------------------------------------------------
    // THE COMPOUND FORM.
    // ------------------------------------------------------------------------------------------

    // `x op= y` MEANS `x = x op y`, so the check is: build that binary expression, ask the operator
    // family what it is worth, and refuse when the answer cannot be stored back. An `unknown` on
    // either side declines rather than guesses, and a DELEGATE target skips the rule entirely because
    // `+=` on a delegate is combination and not arithmetic.
    func ReportInvalidCompoundAssignmentIfNeeded(assignment: AssignmentExpression, targetType: TypeInfo, valueType: TypeInfo): bool {
        binaryOperator := BinaryOperator.Add
        if !OperatorFacts.TryGetCompoundAssignmentBinaryOperator(assignment.Operator, out binaryOperator) {
            return false
        }

        if BuiltInTypes.IsUnknown(targetType) || BuiltInTypes.IsUnknown(valueType) {
            return false
        }

        isAddOrSubtract := assignment.Operator == AssignmentOperator.AddAssign || assignment.Operator == AssignmentOperator.SubtractAssign
        if isAddOrSubtract && IsDelegateLikeAssignmentType(targetType) {
            return false
        }

        operatorExpression := new BinaryExpression(assignment.Target, binaryOperator, assignment.Value, assignment.Line, assignment.Column)
        resultType := operatorExpressionsValue.CompoundAssignmentOperatorResult(binaryOperator, targetType, valueType, operatorExpression)
        if BuiltInTypes.IsUnknown(resultType) {
            return true
        }

        if assignabilityValue.IsAssignable(targetType, resultType) {
            return false
        }

        opText := OperatorFacts.GetAssignmentText(assignment.Operator)
        length := opText.Length
        if length < 1 {
            length = 1
        }

        diagnosticsValue.Report(ErrorCode.TypeMismatch, "The '" + opText + "' assignment produces '" + TypeText(resultType) + "', which can't be stored in '" + TypeText(targetType) + "'", assignment.Line, assignment.Column, "Use an explicit assignment with a conversion, or choose operands whose operator result is assignable to the target.", length)
        return true
    }

    // A `Func`, an `Action`, a source function type or a runtime delegate — through an alias, through
    // an oblivious wrapper and through a nullable, because `handler?.Invoke` shapes are still
    // delegates and `handler += h` on one is still combination.
    func IsDelegateLikeAssignmentType(candidate: TypeInfo): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        if resolved as FunctionTypeInfo != null {
            return true
        }

        genericType := resolved as GenericTypeInfo
        if genericType != null && (genericType.Name == "Func" || genericType.Name == "Action") {
            return true
        }

        reflection := resolved as ReflectionTypeInfo
        if reflection != null {
            return assignabilityFactsValue.IsDelegateType(reflection.Type) || AnalyzerCallableReferenceFacts.IsRuntimeDelegateType(reflection.Type)
        }

        oblivious := resolved as ObliviousTypeInfo
        if oblivious != null {
            return IsDelegateLikeAssignmentType(oblivious.InnerType)
        }

        nullable := resolved as NullableTypeInfo
        if nullable != null {
            return IsDelegateLikeAssignmentType(nullable.InnerType)
        }

        return false
    }

    // A `TypeInfo`'s display text, read through `object` because the columnar surface does not model
    // `ToString` on the model types directly — the estate's standing idiom.
    static func TypeText(candidate: TypeInfo): string {
        boxed := candidate as object
        rendered := boxed.ToString()
        if rendered != null {
            return rendered
        }

        return ""
    }
}
