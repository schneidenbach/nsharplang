namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// WHAT MAY BE WRITTEN THROUGH, AND WHAT MAY NOT.
//
// THIS IS A FAMILY, NOT AN ARM. Nothing here walks an expression and nothing here is reached from the
// expression dispatch. It is the shared rule THREE arms consult before they let a value be stored:
// `=` and its compound forms, `++`/`--`, and a `ref`/`out` argument. Every one of them asks the same
// questions in the same order about the same node, and the only thing that differs is the ACTION
// WORDING each hands in — "assigned", "incremented or decremented", "used as the out argument" — so
// that a developer is told what they were trying to do rather than what the rule is called.
//
// IT IS ITS OWN OWNER BECAUSE THE DEPENDENCY DIRECTION SAYS SO, not because the reports are tidy
// together. The assignment arm needs the operator family (a compound assignment's result type is an
// operator's result), and the operator family needs these reports (`a?.b++` is refused before its
// operand is walked). Putting the reports in the assignment owner would make those two owners
// mutually dependent; putting them here makes the graph
// `assignment -> {writeTargets, operatorExpressions}` and `operatorExpressions -> writeTargets`,
// which is acyclic. The split is forced, and the slice that took it recorded the measurement.
//
// THE SEVEN RULES IT OWNS, and the order they are asked in is behaviour rather than convenience:
//   1  A NULL-CONDITIONAL WRITE TARGET. `a?.b = 1` is refused outright, and it is asked FIRST because
//      there is no value to write into when the receiver is null — the target is not even walked.
//   2  A SoA TABLE MEMBER. A table's columns and its `length`/`capacity` bookkeeping are refused
//      wholesale: writing one directly desynchronises it from the others.
//   3  AN UNSUPPORTED BUILT-IN INDEXED MUTATION. A column slice allocates (the index arm's own
//      refusal, asked here because it is the same question about the same node), a string is
//      immutable, and an array SLICE is not a storage location even though an array ELEMENT is.
//   4  A READ-ONLY PROPERTY, which is the only one of the seven that has to resolve a member.
//   5  A READONLY FIELD, whose verdict AND whose wording both turn on whether the walk is inside a
//      constructor and whether the field belongs to the current instance. Its three reports differ
//      only in the sentence they end with, so they share one target rule and nothing else.
//   6  WHICH TARGETS NEED THEIR SUB-EXPRESSION TYPES CAPTURED — a member or index chain does, a bare
//      name does not, and the difference is observable because the capture table's PRESENCE
//      suppresses rule 3's column-slice arm.
//   7  WHETHER A RECEIVER HOP IS AN INSTANCE FIELD, which is the addressability question underneath
//      both the NL322 value-copy rule and the `ref`/`out` argument rule.
//
// WHAT IT DOES NOT OWN: it never decides that a write is HAPPENING. Each arm decides that for itself
// and then asks; this family only answers, and answers the same way for all three.
class AnalyzerWriteTargets {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    typeSubstitutionValue: AnalyzerTypeSubstitution
    clrTypeConversionValue: AnalyzerClrTypeConversion
    ambientValue: AnalyzerAmbientContext
    soaEscapeValue: AnalyzerSoaEscape
    memberAccessValue: AnalyzerMemberAccess
    indexAccessValue: AnalyzerIndexAccess

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, typeSubstitution: AnalyzerTypeSubstitution, clrTypeConversion: AnalyzerClrTypeConversion, ambient: AnalyzerAmbientContext, soaEscape: AnalyzerSoaEscape, memberAccess: AnalyzerMemberAccess, indexAccess: AnalyzerIndexAccess) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        typeSubstitutionValue = typeSubstitution
        clrTypeConversionValue = clrTypeConversion
        ambientValue = ambient
        soaEscapeValue = soaEscape
        memberAccessValue = memberAccess
        indexAccessValue = indexAccess
    }

    // ------------------------------------------------------------------------------------------
    // RULE 6 — WHICH TARGETS NEED A CAPTURE TABLE.
    // ------------------------------------------------------------------------------------------

    // A member or index chain needs its sub-expression types recorded so rules 2, 3, 4, 5 and 7 can
    // read the chain without re-analysing it — re-analysis would duplicate every diagnostic the chain
    // already produced. A bare name needs nothing, and opening a table for one would suppress rule 3's
    // column-slice arm for no reason at all.
    static func IsWriteTargetNeedingExpressionTypes(expression: Expression): bool {
        return IsMemberAccessWriteTarget(expression) || IsIndexAccessWriteTarget(expression)
    }

    // The three transparent wrappers are seen through in every one of these shape tests, because a
    // developer who parenthesises or `checked`s a target has not changed what the target IS.
    static func IsMemberAccessWriteTarget(expression: Expression): bool {
        if expression as MemberAccessExpression != null {
            return true
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return IsMemberAccessWriteTarget(parenthesized.Inner)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return IsMemberAccessWriteTarget(checkedExpression.Expression)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return IsMemberAccessWriteTarget(uncheckedExpression.Expression)
        }

        return false
    }

    static func IsIndexAccessWriteTarget(expression: Expression): bool {
        if expression as IndexAccessExpression != null {
            return true
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return IsIndexAccessWriteTarget(parenthesized.Inner)
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return IsIndexAccessWriteTarget(checkedExpression.Expression)
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return IsIndexAccessWriteTarget(uncheckedExpression.Expression)
        }

        return false
    }

    // ------------------------------------------------------------------------------------------
    // RULE 1 — THE NULL-CONDITIONAL WRITE TARGET.
    // ------------------------------------------------------------------------------------------

    // `a?.b = 1`, `a?[0] = 1` and every chain that passes through one. There is nothing to write into
    // when the receiver is null, and C#'s answer — silently skip the store — is not an answer N# is
    // willing to give, so the shape is refused.
    func ReportNullConditionalWriteTargetIfNeeded(target: Expression, action: string): bool {
        // The out parameter is NON-nullable and seeded with the target itself, exactly as the C# was:
        // a nullable one cannot be threaded through the recursion, because the recursive call would be
        // handing an already-narrowed `Expression` to an `Expression?` slot.
        nullConditionalTarget: Expression = target
        targetKind := ""
        if !TryFindNullConditionalWriteTarget(target, out nullConditionalTarget, out targetKind) {
            return false
        }

        span := spansValue.GetExpressionDiagnosticSpan(nullConditionalTarget)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "Null-conditional " + targetKind + " can't be " + action, span.Line, span.Column, "Store the receiver in a local, guard it for null, then write through a normal member or index target.", span.Length)
        return true
    }

    // THE OUTERMOST null-conditional hop wins, and the search walks INWARD through the receiver chain
    // rather than stopping at the target: `a?.b.c = 1` is refused about `a?.b`, which is the hop that
    // can actually be null.
    static func TryFindNullConditionalWriteTarget(target: Expression, out nullConditionalTarget: Expression, out targetKind: string): bool {
        nullConditionalTarget = target
        targetKind = ""

        parenthesized := target as ParenthesizedExpression
        if parenthesized != null {
            return TryFindNullConditionalWriteTarget(parenthesized.Inner, out nullConditionalTarget, out targetKind)
        }

        memberAccess := target as MemberAccessExpression
        if memberAccess != null {
            if memberAccess.IsNullConditional {
                nullConditionalTarget = memberAccess
                targetKind = "member access"
                return true
            }

            return TryFindNullConditionalWriteTarget(memberAccess.Object, out nullConditionalTarget, out targetKind)
        }

        indexAccess := target as IndexAccessExpression
        if indexAccess != null {
            if indexAccess.IsNullConditional {
                nullConditionalTarget = indexAccess
                targetKind = "index access"
                return true
            }

            return TryFindNullConditionalWriteTarget(indexAccess.Object, out nullConditionalTarget, out targetKind)
        }

        return false
    }

    // ------------------------------------------------------------------------------------------
    // RULE 2 — THE SoA TABLE MEMBER MUTATION.
    // ------------------------------------------------------------------------------------------

    // A table's COLUMNS and its two bookkeeping fields are the table's invariant. Writing a column
    // array wholesale would leave `length` describing a different array; writing `length` would leave
    // the columns describing a different table. Both are refused, with different advice.
    func ReportSoaTableMemberMutationIfNeeded(target: Expression, expressionTypes: Dictionary<object, TypeInfo>?, action: string): bool {
        parenthesized := target as ParenthesizedExpression
        if parenthesized != null {
            return ReportSoaTableMemberMutationIfNeeded(parenthesized.Inner, expressionTypes, action)
        }

        checkedExpression := target as CheckedExpression
        if checkedExpression != null {
            return ReportSoaTableMemberMutationIfNeeded(checkedExpression.Expression, expressionTypes, action)
        }

        uncheckedExpression := target as UncheckedExpression
        if uncheckedExpression != null {
            return ReportSoaTableMemberMutationIfNeeded(uncheckedExpression.Expression, expressionTypes, action)
        }

        member := target as MemberAccessExpression
        if member == null || expressionTypes == null {
            return false
        }

        receiverType: TypeInfo = BuiltInTypes.Unknown
        if !expressionTypes.TryGetValue(member.Object, out receiverType) {
            return false
        }

        soaRecordType := declarationContextValue.ResolveDeclaredAlias(NonNullableType(receiverType)) as SoaRecordTypeInfo
        if soaRecordType == null {
            return false
        }

        isColumn := AnalyzerMemberResolution.TryGetSoaColumn(soaRecordType.Declaration, member.MemberName) != null
        isBookkeepingField := member.MemberName == "length" || member.MemberName == "capacity"
        if !isColumn && !isBookkeepingField {
            return false
        }

        ReportSoaTableMemberMutation(member, action, isColumn)
        return true
    }

    // PUBLISHED, because the call arm raises the identical report for a mutating array call on a
    // direct column and must say it the same way.
    func ReportSoaTableMemberMutation(member: MemberAccessExpression, action: string, isColumn: bool) {
        line := member.Line
        column := spansValue.GetMemberNameColumn(member)
        length := member.MemberName.Length
        if length < 1 {
            length = 1
        }

        suggestion := "Use add, clear, ensureCapacity, or copyRow so length and capacity stay consistent with the columns."
        if isColumn {
            suggestion = "Write individual rows with table[index].column, or construct/wrap the table with the desired column arrays."
        }

        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "SoA table member '" + member.MemberName + "' cannot be " + action, line, column, suggestion, length)
    }

    // ------------------------------------------------------------------------------------------
    // RULE 3 — THE UNSUPPORTED BUILT-IN INDEXED MUTATION.
    // ------------------------------------------------------------------------------------------

    // THREE REFUSALS UNDER ONE QUESTION, and the order between them is behaviour: a COLUMN SLICE is
    // refused as an allocation before the receiver is classified at all, because a column slice is a
    // column slice whatever the element type is. Then a STRING, which is immutable in whole and in
    // part. Then an ARRAY, where an ELEMENT is a storage location the emitter can address and a SLICE
    // is not — which is why the array arm answers `false` unless the access is a range.
    func ReportUnsupportedBuiltInIndexedMutationIfNeeded(target: Expression, expressionTypes: Dictionary<object, TypeInfo>?, action: string): bool {
        parenthesized := target as ParenthesizedExpression
        if parenthesized != null {
            return ReportUnsupportedBuiltInIndexedMutationIfNeeded(parenthesized.Inner, expressionTypes, action)
        }

        checkedExpression := target as CheckedExpression
        if checkedExpression != null {
            return ReportUnsupportedBuiltInIndexedMutationIfNeeded(checkedExpression.Expression, expressionTypes, action)
        }

        uncheckedExpression := target as UncheckedExpression
        if uncheckedExpression != null {
            return ReportUnsupportedBuiltInIndexedMutationIfNeeded(uncheckedExpression.Expression, expressionTypes, action)
        }

        indexAccess := target as IndexAccessExpression
        if indexAccess == null || expressionTypes == null {
            return false
        }

        receiverType: TypeInfo = BuiltInTypes.Unknown
        if !expressionTypes.TryGetValue(indexAccess.Object, out receiverType) {
            return false
        }

        resolvedReceiverType := declarationContextValue.ResolveDeclaredAlias(NonNullableType(receiverType))
        isRangeAccess := indexAccess.Index as RangeExpression != null
        if !isRangeAccess {
            indexType: TypeInfo = BuiltInTypes.Unknown
            if expressionTypes.TryGetValue(indexAccess.Index, out indexType) && AnalyzerIndexAccess.IsRangeLikeType(indexType) {
                isRangeAccess = true
            }
        }

        if isRangeAccess && soaEscapeValue.IsSoaColumnMemberAccess(indexAccess.Object) {
            indexAccessValue.ReportSoaColumnSliceHiddenAllocation(indexAccess)
            return true
        }

        if AnalyzerOperatorExpressions.IsStringType(resolvedReceiverType) {
            ReportUnsupportedStringIndexedMutation(indexAccess, action)
            return true
        }

        if !IsArrayReceiver(resolvedReceiverType) {
            return false
        }

        if !isRangeAccess {
            return false
        }

        ReportUnsupportedArraySliceMutation(indexAccess, action)
        return true
    }

    static func IsArrayReceiver(candidate: TypeInfo): bool {
        if candidate as ArrayTypeInfo != null {
            return true
        }

        reflectionType := candidate as ReflectionTypeInfo
        return reflectionType != null && reflectionType.Type.get_IsArray()
    }

    func ReportUnsupportedArraySliceMutation(indexAccess: IndexAccessExpression, action: string) {
        span := spansValue.GetExpressionDiagnosticSpan(indexAccess)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "Array slices cannot be " + action, span.Line, span.Column, "Assign individual elements, or construct a replacement array value explicitly.", span.Length)
    }

    func ReportUnsupportedStringIndexedMutation(indexAccess: IndexAccessExpression, action: string) {
        span := spansValue.GetExpressionDiagnosticSpan(indexAccess)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "String characters and slices cannot be " + action, span.Line, span.Column, "Create a new string value instead; strings are immutable.", span.Length)
    }

    // ------------------------------------------------------------------------------------------
    // RULE 4 — THE READ-ONLY PROPERTY.
    // ------------------------------------------------------------------------------------------

    // The action wording forks on the OPERATOR rather than on the rule: `++` and `--` "change" a
    // property, everything else "assigns" it, and the sentence a developer reads should describe what
    // they wrote.
    func ReportReadOnlyPropertyWriteTargetIfNeeded(target: Expression, opText: string, expressionTypes: Dictionary<object, TypeInfo>?): bool {
        propertyName := ""
        if !TryFindReadOnlyPropertyWriteTarget(target, expressionTypes, out propertyName) {
            return false
        }

        action := "assigned with '" + opText + "'"
        if opText == "++" || opText == "--" {
            action = "changed with '" + opText + "'"
        }

        span := spansValue.GetAssignmentTargetNameDiagnosticSpan(target, target.Line, target.Column)
        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "Property '" + propertyName + "' is read-only — it can't be " + action, span.Line, span.Column, "Use a variable, field, settable property, or indexed element as the target.", span.Length)
        return true
    }

    // TWO SHAPES ANSWER: a bare name that is a member of the enclosing type, and a member access whose
    // receiver's type the capture table knows. Everything else — a local, an index, a call result — is
    // not a property write at all and falls through silently.
    func TryFindReadOnlyPropertyWriteTarget(target: Expression, expressionTypes: Dictionary<object, TypeInfo>?, out propertyName: string): bool {
        propertyName = ""

        parenthesized := target as ParenthesizedExpression
        if parenthesized != null {
            return TryFindReadOnlyPropertyWriteTarget(parenthesized.Inner, expressionTypes, out propertyName)
        }

        identifier := target as IdentifierExpression
        if identifier != null {
            if !scopesValue.IsCurrentTypeMemberReference(identifier.Name) {
                return false
            }

            currentType := scopesValue.CurrentTypeScope()
            if currentType != null && TryIsReadOnlyPropertyMember(currentType, identifier.Name, false) {
                propertyName = identifier.Name
                return true
            }

            return false
        }

        memberAccess := target as MemberAccessExpression
        if memberAccess == null || expressionTypes == null {
            return false
        }

        receiverType: TypeInfo = BuiltInTypes.Unknown
        if !expressionTypes.TryGetValue(memberAccess.Object, out receiverType) {
            return false
        }

        resolvedReceiver := declarationContextValue.ResolveDeclaredAlias(receiverType)
        byRefReceiver := resolvedReceiver as ByRefTypeInfo
        if byRefReceiver != null {
            resolvedReceiver = declarationContextValue.ResolveDeclaredAlias(byRefReceiver.InnerType)
        }

        // A NULLABLE'S `HasValue` AND `Value` ARE READ-ONLY BY CONSTRUCTION, and they are answered here
        // rather than by the member lookup below because there is no declaration to find.
        if resolvedReceiver as NullableTypeInfo != null && IsNullableReadOnlyMemberName(memberAccess.MemberName) {
            propertyName = memberAccess.MemberName
            return true
        }

        ownerType := NonNullableType(resolvedReceiver)
        if TryIsReadOnlyPropertyMember(ownerType, memberAccess.MemberName, memberAccessValue.IsStaticMemberAccessTarget(memberAccess.Object)) {
            propertyName = memberAccess.MemberName
            return true
        }

        return false
    }

    static func IsNullableReadOnlyMemberName(memberName: string): bool {
        return memberName == "HasValue" || memberName == "Value"
    }

    // A PROPERTY WITH NO SETTER, OR ONE WHOSE SETTER IS `init`. A SoA table and a row view are never
    // read-only members — their own rule already refused them and a second report helps nobody — and a
    // SOURCE type that claims the name at all ends the search, because a source declaration outranks
    // whatever the reflected base happens to have.
    func TryIsReadOnlyPropertyMember(owner: TypeInfo, memberName: string, includeStaticMembers: bool): bool {
        resolvedOwner := declarationContextValue.ResolveDeclaredAlias(owner)
        byRefOwner := resolvedOwner as ByRefTypeInfo
        if byRefOwner != null {
            resolvedOwner = declarationContextValue.ResolveDeclaredAlias(byRefOwner.InnerType)
        }

        if resolvedOwner as NullableTypeInfo != null && IsNullableReadOnlyMemberName(memberName) {
            return true
        }

        if resolvedOwner as SoaRecordTypeInfo != null || resolvedOwner as SoaRowTypeInfo != null {
            return false
        }

        selection: AnalyzerMemberSelection = new AnalyzerMemberSelection()
        if declarationContextValue.TryFindMember(resolvedOwner, memberName, out selection) {
            member := selection.Member
            if member == null {
                return false
            }

            return member.Kind == DeclaredMemberKind.Property && member.IsStatic == includeStaticMembers && (!member.HasSetter || member.IsReadonly)
        }

        substitution: Dictionary<string, TypeInfo>? = null
        sourceOwner := typeSubstitutionValue.GetSourceDeclarationOwner(resolvedOwner, out substitution)
        shape: AnalyzerSourceMemberShape = new AnalyzerSourceMemberShape()
        if declarationContextValue.TryGetSourceMemberShape(sourceOwner, null, out shape) {
            return false
        }

        reflected := NormalizeReflectionOwner(resolvedOwner) as ReflectionTypeInfo
        if reflected == null {
            return false
        }

        reflectedType := reflected.Type
        if IsTypeBuilder(reflectedType) || reflectedType.get_IsGenericTypeDefinition() {
            return false
        }

        return TryIsReadOnlyReflectionProperty(reflectedType, memberName, includeStaticMembers)
    }

    // THE FIRST DECLARATION THAT CLAIMS THE NAME DECIDES, one base type at a time. A FIELD claims it
    // and answers no — a field is not a property. A PROPERTY claims it and answers whether its public
    // setter is absent. A method or an event claims it and answers no.
    static func TryIsReadOnlyReflectionProperty(reflectedType: Type, memberName: string, includeStaticMembers: bool): bool {
        flags := BindingFlags.Public | BindingFlags.DeclaredOnly | BindingFlags.Instance
        if includeStaticMembers {
            flags = BindingFlags.Public | BindingFlags.DeclaredOnly | BindingFlags.Static
        }

        current: Type? = reflectedType
        while current != null {
            // EVERY REFLECTED RECEIVER IS A LOOP BINDING OR A LOCAL, never an index expression.
            declaredType := current
            fields := declaredType.GetFields(flags)
            for field in fields {
                if field.get_Name() == memberName {
                    return false
                }
            }

            properties := declaredType.GetProperties(flags)
            for property in properties {
                if property.get_Name() == memberName {
                    return property.GetSetMethod(false) == null
                }
            }

            methods := declaredType.GetMethods(flags)
            for method in methods {
                if !method.get_IsSpecialName() && method.get_Name() == memberName {
                    return false
                }
            }

            events := declaredType.GetEvents(flags)
            for declaredEvent in events {
                if declaredEvent.get_Name() == memberName {
                    return false
                }
            }

            current = declaredType.get_BaseType()
        }

        return false
    }

    // ------------------------------------------------------------------------------------------
    // RULE 5 — THE READONLY FIELD, AND ITS THREE REPORTS.
    // ------------------------------------------------------------------------------------------

    // THE ASSIGNMENT FORM. A static readonly field can only ever be initialized at its declaration; an
    // instance one may be assigned by its OWN constructor, and the wording differs between "you are
    // not in a constructor" and "you are in a constructor but this is somebody else's instance",
    // because those are different mistakes with different fixes.
    func ReportReadonlyFieldAssignmentIfNeeded(target: Expression, line: int, column: int, expressionTypes: Dictionary<object, TypeInfo>?) {
        readonlyTarget: ReadonlyFieldTarget? = null
        if !TryGetReadonlyFieldTarget(target, expressionTypes, out readonlyTarget) {
            return
        }

        if readonlyTarget == null {
            return
        }

        if readonlyTarget.IsStatic {
            staticSpan := spansValue.GetAssignmentTargetNameDiagnosticSpan(target, line, column)
            diagnosticsValue.Report(ErrorCode.ReadonlyAssignment, "Field '" + readonlyTarget.Name + "' is static readonly — it can only be initialized at its declaration", staticSpan.Line, staticSpan.Column, "Move this value into the field initializer, or remove `readonly` if the static field needs to change later.", staticSpan.Length)
            return
        }

        inConstructor := ambientValue.InConstructor
        if inConstructor && readonlyTarget.IsCurrentInstance {
            return
        }

        span := spansValue.GetAssignmentTargetNameDiagnosticSpan(target, line, column)
        message := "Field '" + readonlyTarget.Name + "' is readonly — it can only be assigned in a constructor"
        suggestion := "Move this assignment into a constructor, or remove `readonly` if the field needs to change later."
        if inConstructor {
            message = "Field '" + readonlyTarget.Name + "' is readonly — constructors can only assign readonly fields on the current instance"
            suggestion = "Assign the current instance field directly, or remove `readonly` if other instances must be mutated."
        }

        diagnosticsValue.Report(ErrorCode.ReadonlyAssignment, message, span.Line, span.Column, suggestion, span.Length)
    }

    // THE `ref`/`out` ARGUMENT FORM. Passing a readonly field by reference hands out a writable alias,
    // which is the same violation as assigning it — so the same target rule answers, with a sentence
    // about the argument rather than about the store.
    func ReportReadonlyFieldRefOutArgumentIfNeeded(target: Expression, modifier: string, expressionTypes: Dictionary<object, TypeInfo>?): bool {
        readonlyTarget: ReadonlyFieldTarget? = null
        if !TryGetReadonlyFieldTarget(target, expressionTypes, out readonlyTarget) {
            return false
        }

        if readonlyTarget == null {
            return false
        }

        if !readonlyTarget.IsStatic && ambientValue.InConstructor && readonlyTarget.IsCurrentInstance {
            return false
        }

        span := spansValue.GetAssignmentTargetNameDiagnosticSpan(target, target.Line, target.Column)
        fieldKind := "readonly"
        suggestion := "Assign readonly fields inside a constructor, or remove `readonly` if this field must be passed by reference."
        if readonlyTarget.IsStatic {
            fieldKind = "static readonly"
            suggestion = "Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`."
        }

        diagnosticsValue.Report(ErrorCode.ReadonlyAssignment, "Field '" + readonlyTarget.Name + "' is " + fieldKind + " — it can't be used as a " + modifier + " argument", span.Line, span.Column, suggestion, span.Length)
        return true
    }

    // THE `++`/`--` FORM. A mutation is a read-modify-write, so the field rule applies unchanged; the
    // span is the TARGET NAME with the whole unary as the fallback, because the fix goes on the field.
    func ReportReadonlyFieldIncrementOrDecrementIfNeeded(unary: UnaryExpression, expressionTypes: Dictionary<object, TypeInfo>?): bool {
        readonlyTarget: ReadonlyFieldTarget? = null
        if !TryGetReadonlyFieldTarget(unary.Operand, expressionTypes, out readonlyTarget) {
            return false
        }

        if readonlyTarget == null {
            return false
        }

        inConstructor := ambientValue.InConstructor
        if !readonlyTarget.IsStatic && inConstructor && readonlyTarget.IsCurrentInstance {
            return false
        }

        opText := OperatorFacts.GetUnarySymbol(unary.Operator)
        if opText == null {
            opText = "operator"
        }

        span := spansValue.GetAssignmentTargetNameDiagnosticSpan(unary.Operand, unary.Line, unary.Column)
        fieldKind := "readonly"
        suggestion := "Move this mutation into a constructor assignment, or remove `readonly` if the field needs to change later."
        if readonlyTarget.IsStatic {
            fieldKind = "static readonly"
            suggestion = "Static readonly fields can only be initialized at their declaration; copy the value to a mutable local or remove `readonly`."
        } else if inConstructor {
            suggestion = "Assign the current instance field directly, or remove `readonly` if other instances must be mutated."
        }

        diagnosticsValue.Report(ErrorCode.ReadonlyAssignment, "Field '" + readonlyTarget.Name + "' is " + fieldKind + " — it can't be changed with '" + opText + "'", span.Line, span.Column, suggestion, span.Length)
        return true
    }

    // THE ONE TARGET RULE ALL THREE REPORTS SHARE. Three channels in order: a STATIC field reached
    // through a type name, an INSTANCE field reached through some other receiver, and finally a bare
    // name or `this.name`, which is looked up in the enclosing class and then in its bases.
    func TryGetReadonlyFieldTarget(target: Expression, expressionTypes: Dictionary<object, TypeInfo>?, out readonlyTarget: ReadonlyFieldTarget?): bool {
        readonlyTarget = null

        parenthesized := target as ParenthesizedExpression
        if parenthesized != null {
            return TryGetReadonlyFieldTarget(parenthesized.Inner, expressionTypes, out readonlyTarget)
        }

        memberAccess := target as MemberAccessExpression
        if memberAccess != null {
            if TryGetStaticReadonlyFieldTarget(memberAccess, expressionTypes, out readonlyTarget) {
                return true
            }

            if TryGetInstanceReadonlyFieldTarget(memberAccess, expressionTypes, out readonlyTarget) {
                return true
            }
        }

        fieldName := ""
        if memberAccess != null && memberAccess.Object as ThisExpression != null {
            fieldName = memberAccess.MemberName
        } else {
            identifier := target as IdentifierExpression
            if identifier != null {
                // A BARE NAME A LOCAL OR A PARAMETER CLAIMS IS NOT THE FIELD, and the member list
                // this channel searches cannot tell: `Size = 4` under a local `Size` stores into the
                // LOCAL, which is why Roslyn says nothing. `this.Size` is never a local and is
                // therefore never asked.
                if !scopesValue.BindsToLocalOrParameter(identifier.Name) {
                    fieldName = identifier.Name
                }
            }
        }

        if fieldName.Length == 0 || ambientValue.CurrentTypeMembers == null {
            readonlyTarget = null
            return false
        }

        return TryGetCurrentOrInheritedReadonlyFieldTarget(fieldName, out readonlyTarget)
    }

    // THE ENCLOSING TYPE'S OWN MEMBERS DECIDE FIRST, and a PROPERTY of the same name ends the search
    // with "no" — a property write is rule 4's business, not this one's. Only when the type declares
    // nothing by that name do the base types get asked, and an inherited readonly field is never "the
    // current instance" for the purposes of the constructor exemption.
    //
    // THE ENCLOSING TYPE IS NOT NECESSARILY A CLASS, and reading `CurrentClass` here is what made
    // this channel blind inside a struct and inside a record: that slot is typed `ClassDeclaration`,
    // so neither form could ever be put in it and every bare-name and `this.`-qualified readonly
    // write inside one — assignment, `++`/`--` and `ref`/`out` argument alike — was silently allowed.
    // The member list and the type NAME are read from the slots all four forms move together.
    func TryGetCurrentOrInheritedReadonlyFieldTarget(fieldName: string, out readonlyTarget: ReadonlyFieldTarget?): bool {
        readonlyTarget = null
        currentMembers := ambientValue.CurrentTypeMembers
        if currentMembers == null {
            return false
        }

        for member in currentMembers {
            field := member as FieldDeclaration
            if field != null && field.Name == fieldName {
                if !HasModifier(field.Modifiers, Modifiers.Readonly) {
                    return false
                }

                isStatic := HasModifier(field.Modifiers, Modifiers.Static)
                readonlyTarget = new ReadonlyFieldTarget(field.Name, isStatic, !isStatic)
                return true
            }

            property := member as PropertyDeclaration
            if property != null && property.Name == fieldName {
                return false
            }
        }

        currentTypeName := ambientValue.CurrentTypeName
        if currentTypeName == null {
            return false
        }

        currentType := scopesValue.LookupType(currentTypeName)
        if currentType == null {
            return false
        }

        inheritedFieldName := ""
        if !TryFindReadonlyInstanceField(currentType, fieldName, out inheritedFieldName) {
            return false
        }

        readonlyTarget = new ReadonlyFieldTarget(inheritedFieldName, false, false)
        return true
    }

    static func HasModifier(modifiers: Modifiers, flag: Modifiers): bool {
        modifierBits := Convert.ToInt32(modifiers)
        flagBits := Convert.ToInt32(flag)
        return (modifierBits & flagBits) == flagBits
    }

    func TryGetStaticReadonlyFieldTarget(target: MemberAccessExpression, expressionTypes: Dictionary<object, TypeInfo>?, out readonlyTarget: ReadonlyFieldTarget?): bool {
        readonlyTarget = null
        if !memberAccessValue.IsStaticMemberAccessTarget(target.Object) || expressionTypes == null {
            return false
        }

        ownerType: TypeInfo = BuiltInTypes.Unknown
        if !expressionTypes.TryGetValue(target.Object, out ownerType) {
            return false
        }

        fieldName := ""
        if !TryFindReadonlyStaticField(ownerType, target.MemberName, out fieldName) {
            return false
        }

        readonlyTarget = new ReadonlyFieldTarget(fieldName, true, false)
        return true
    }

    // `this.field` IS DELIBERATELY NOT AN INSTANCE TARGET HERE — it falls through to the enclosing
    // class channel, which is the only one that can tell "the current instance" from "some instance"
    // and therefore the only one that can apply the constructor exemption.
    func TryGetInstanceReadonlyFieldTarget(target: MemberAccessExpression, expressionTypes: Dictionary<object, TypeInfo>?, out readonlyTarget: ReadonlyFieldTarget?): bool {
        readonlyTarget = null
        if target.Object as ThisExpression != null || memberAccessValue.IsStaticMemberAccessTarget(target.Object) || expressionTypes == null {
            return false
        }

        receiverType: TypeInfo = BuiltInTypes.Unknown
        if !expressionTypes.TryGetValue(target.Object, out receiverType) {
            return false
        }

        receiver := declarationContextValue.ResolveDeclaredAlias(NonNullableType(receiverType))
        byRefReceiver := receiver as ByRefTypeInfo
        if byRefReceiver != null {
            receiver = declarationContextValue.ResolveDeclaredAlias(NonNullableType(byRefReceiver.InnerType))
        }

        fieldName := ""
        if !TryFindReadonlyInstanceField(receiver, target.MemberName, out fieldName) {
            return false
        }

        readonlyTarget = new ReadonlyFieldTarget(fieldName, false, false)
        return true
    }

    // PUBLISHED, and this is the estate's ONLY copy. The construction family asks the same question of
    // an object-initializer entry — "is this member a readonly field I must refuse a write to" — and
    // reproduced this rule while it was still private to `Analyzer.cs`. The duplicate is gone.
    func TryFindReadonlyInstanceField(receiver: TypeInfo, fieldName: string, out resolvedFieldName: string): bool {
        resolvedFieldName = ""
        resolvedReceiver := declarationContextValue.ResolveDeclaredAlias(receiver)
        sourceMemberClaimed := false
        if declarationContextValue.TryFindReadonlyField(resolvedReceiver, fieldName, false, out resolvedFieldName, out sourceMemberClaimed) {
            return true
        }

        if sourceMemberClaimed {
            return false
        }

        reflected := NormalizeReflectionOwner(resolvedReceiver) as ReflectionTypeInfo
        if reflected == null {
            return false
        }

        reflectedType := reflected.Type
        if reflectedType.get_IsGenericTypeDefinition() || IsTypeBuilder(reflectedType) {
            return false
        }

        return TryFindReadonlyReflectionInstanceField(reflectedType, fieldName, out resolvedFieldName)
    }

    func TryFindReadonlyStaticField(owner: TypeInfo, fieldName: string, out resolvedFieldName: string): bool {
        resolvedFieldName = ""
        resolvedOwner := declarationContextValue.ResolveDeclaredAlias(owner)
        sourceMemberClaimed := false
        if declarationContextValue.TryFindReadonlyField(resolvedOwner, fieldName, true, out resolvedFieldName, out sourceMemberClaimed) {
            return true
        }

        if sourceMemberClaimed {
            return false
        }

        reflected := NormalizeReflectionOwner(resolvedOwner) as ReflectionTypeInfo
        if reflected == null {
            return false
        }

        reflectedType := reflected.Type
        if reflectedType.get_IsGenericTypeDefinition() || IsTypeBuilder(reflectedType) {
            return false
        }

        return TryFindReadonlyReflectionStaticField(reflectedType, fieldName, out resolvedFieldName)
    }

    // PUBLISHED alongside its instance sibling. The first declaration that claims the name decides.
    static func TryFindReadonlyReflectionInstanceField(reflectedType: Type, fieldName: string, out resolvedFieldName: string): bool {
        resolvedFieldName = ""
        flags := BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly
        current: Type? = reflectedType
        while current != null {
            declaredType := current
            fields := declaredType.GetFields(flags)
            for field in fields {
                if field.get_Name() == fieldName {
                    if !field.get_IsInitOnly() {
                        return false
                    }

                    resolvedFieldName = field.get_Name()
                    return true
                }
            }

            if ReflectionMemberNameIsClaimed(declaredType, fieldName, flags) {
                return false
            }

            current = declaredType.get_BaseType()
        }

        return false
    }

    // A STATIC READONLY FIELD OR A CONSTANT. `const` is `IsLiteral` rather than `IsInitOnly` and is
    // just as unwritable, which is why both admit here where the instance rule admits only the first.
    static func TryFindReadonlyReflectionStaticField(reflectedType: Type, fieldName: string, out resolvedFieldName: string): bool {
        resolvedFieldName = ""
        flags := BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly
        current: Type? = reflectedType
        while current != null {
            declaredType := current
            fields := declaredType.GetFields(flags)
            for field in fields {
                if field.get_Name() == fieldName {
                    if !field.get_IsInitOnly() && !field.get_IsLiteral() {
                        return false
                    }

                    resolvedFieldName = field.get_Name()
                    return true
                }
            }

            if ReflectionMemberNameIsClaimed(declaredType, fieldName, flags) {
                return false
            }

            current = declaredType.get_BaseType()
        }

        return false
    }

    // WHETHER A NON-FIELD MEMBER CLAIMS THE NAME on this declaration level. Shared by all three
    // reflected walks because all three stop for the same three reasons.
    static func ReflectionMemberNameIsClaimed(declaredType: Type, memberName: string, flags: BindingFlags): bool {
        properties := declaredType.GetProperties(flags)
        for property in properties {
            if property.get_Name() == memberName {
                return true
            }
        }

        methods := declaredType.GetMethods(flags)
        for method in methods {
            if !method.get_IsSpecialName() && method.get_Name() == memberName {
                return true
            }
        }

        events := declaredType.GetEvents(flags)
        for declaredEvent in events {
            if declaredEvent.get_Name() == memberName {
                return true
            }
        }

        return false
    }

    // ------------------------------------------------------------------------------------------
    // RULE 7 — IS THIS RECEIVER HOP AN INSTANCE FIELD.
    // ------------------------------------------------------------------------------------------

    // PUBLISHED, because it is the addressability question underneath BOTH the NL322 value-copy rule
    // and the `ref`/`out` argument rule: a field hop keeps a chain rooted in real storage, a property
    // or method hop makes it a copy.
    //
    // IT IS A `Try` RATHER THAN A NULLABLE `bool`, and that is a language fact rather than a taste:
    // a `bool?`-returning call cannot initialise a typed local on the columnar surface
    // (`emit.typed-local.nullable-conversion`) nor be nested in another call's arguments. The RETURN
    // says whether the owner could be RESOLVED at all — both callers treat "no" as a reason to stay
    // silent rather than as a "not a field" — and the out parameter carries the answer.
    func TryClassifyInstanceFieldHop(hop: MemberAccessExpression, expressionTypes: Dictionary<object, TypeInfo>?, out isInstanceField: bool): bool {
        isInstanceField = false
        if expressionTypes == null {
            return false
        }

        ownerType: TypeInfo = BuiltInTypes.Unknown
        if !expressionTypes.TryGetValue(hop.Object, out ownerType) {
            return false
        }

        return TryClassifyInstanceFieldMember(ownerType, hop.MemberName, out isInstanceField)
    }

    func TryClassifyInstanceFieldMember(owner: TypeInfo, memberName: string, out isInstanceField: bool): bool {
        isInstanceField = false
        resolvedOwner := declarationContextValue.ResolveDeclaredAlias(owner)
        selection: AnalyzerMemberSelection = new AnalyzerMemberSelection()
        if declarationContextValue.TryFindMember(resolvedOwner, memberName, out selection) {
            member := selection.Member
            if member != null {
                isInstanceField = member.Kind == DeclaredMemberKind.Field && !member.IsStatic
            }

            return true
        }

        substitution: Dictionary<string, TypeInfo>? = null
        sourceOwner := typeSubstitutionValue.GetSourceDeclarationOwner(resolvedOwner, out substitution)
        shape: AnalyzerSourceMemberShape = new AnalyzerSourceMemberShape()
        if declarationContextValue.TryGetSourceMemberShape(sourceOwner, null, out shape) {
            return true
        }

        reflected := NormalizeReflectionOwner(resolvedOwner) as ReflectionTypeInfo
        if reflected == null {
            return false
        }

        reflectedType := reflected.Type
        if IsTypeBuilder(reflectedType) || reflectedType.get_IsGenericTypeDefinition() {
            return false
        }

        isInstanceField = IsReflectedInstanceField(reflectedType, memberName)
        return true
    }

    // A reflected owner ALWAYS answers — `false` when nothing claims the name at all, which is the
    // C#'s own fall-through and is deliberately not "unresolved": a reflected type that has been
    // walked to the root is resolved, and a name it does not declare is not a field of it.
    static func IsReflectedInstanceField(reflectedType: Type, memberName: string): bool {
        flags := BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly
        current: Type? = reflectedType
        while current != null {
            declaredType := current
            fields := declaredType.GetFields(flags)
            for field in fields {
                if field.get_Name() == memberName {
                    return true
                }
            }

            if ReflectionMemberNameIsClaimed(declaredType, memberName, flags) {
                return false
            }

            current = declaredType.get_BaseType()
        }

        return false
    }

    // ------------------------------------------------------------------------------------------
    // RULE 8 — IS THIS RECEIVER HOP A STATIC FIELD, AND IS A `ref`/`out` TARGET ADDRESSABLE AT ALL.
    // ------------------------------------------------------------------------------------------

    // THE STATIC HALF IS THE EXACT MIRROR OF RULE 7 AND BELONGS HERE FOR THE SAME REASON. Rule 7
    // answers the INSTANCE question and has answered it for two arms since it moved; the STATIC
    // question is the same question about a type-named receiver, differs from it in exactly one
    // `BindingFlags` bit and one `IsStatic` comparison, and had been left behind in the call arm only
    // because that arm had not moved yet. `NormalizeReflectionOwner` was published for this caller by
    // name and is now consumed rather than reached into.
    //
    // AND THE ADDRESSABILITY RULE ON TOP OF THEM IS THIS FAMILY'S, NOT THE CALL ARM'S. `ref x` and
    // `out x` hand a callee the right to STORE, so "may this be written through" is exactly the
    // question, and the four reports that run before it are already all this family's. What stays in
    // the call arm is the diagnostic that says so, and nothing that decides.
    //
    // THE THREE SHAPES THAT ARE ADDRESSABLE: a bare name always; a member hop whose receiver keeps the
    // chain rooted in real storage (a SoA COLUMN of a row view, a static field, an instance field, or
    // any owner that could not be resolved — the unresolved case is deliberately permissive and only a
    // PROVEN non-field is refused); and an ARRAY ELEMENT indexed by an `int` or a `System.Index`.
    // Everything else — a call result, a slice, a `string` index, a SoA record's own member, a
    // property — is a copy, and handing a callee the address of a copy is a silent defect.
    func IsRefOutArgumentTarget(target: Expression, expressionTypes: Dictionary<object, TypeInfo>?): bool {
        if target as IdentifierExpression != null {
            return true
        }

        member := target as MemberAccessExpression
        if member != null {
            return IsAddressableRefOutMember(member, expressionTypes)
        }

        indexAccess := target as IndexAccessExpression
        if indexAccess != null {
            return IsAddressableRefOutIndex(indexAccess, expressionTypes)
        }

        parenthesized := target as ParenthesizedExpression
        if parenthesized != null {
            return IsRefOutArgumentTarget(parenthesized.Inner, expressionTypes)
        }

        return false
    }

    // A MISSING CAPTURE TABLE MEANS "DO NOT REFUSE". The call arm opens the table only for the shapes
    // that need it, and a target walked without one is addressable by default rather than by proof.
    func IsAddressableRefOutMember(member: MemberAccessExpression, expressionTypes: Dictionary<object, TypeInfo>?): bool {
        if expressionTypes == null {
            return true
        }

        receiverType: TypeInfo = BuiltInTypes.Unknown
        if expressionTypes.TryGetValue(member.Object, out receiverType) {
            resolvedReceiverType := declarationContextValue.ResolveDeclaredAlias(NonNullableType(receiverType))
            byRefReceiver := resolvedReceiverType as ByRefTypeInfo
            if byRefReceiver != null {
                resolvedReceiverType = declarationContextValue.ResolveDeclaredAlias(NonNullableType(byRefReceiver.InnerType))
            }

            // A ROW VIEW'S COLUMN IS REAL STORAGE — the row is a view over the table's arrays, so its
            // column member has an address. The TABLE's own member does not: writing it directly is
            // the desynchronisation rule 2 refuses outright.
            soaRowType := resolvedReceiverType as SoaRowTypeInfo
            if soaRowType != null && AnalyzerMemberResolution.TryGetSoaColumn(soaRowType.Declaration, member.MemberName) != null {
                return true
            }

            if resolvedReceiverType as SoaRecordTypeInfo != null {
                return false
            }
        }

        if memberAccessValue.IsStaticMemberAccessTarget(member.Object) {
            isStaticField := false
            return !TryClassifyStaticFieldHop(member, expressionTypes, out isStaticField) || isStaticField
        }

        isInstanceField := false
        return !TryClassifyInstanceFieldHop(member, expressionTypes, out isInstanceField) || isInstanceField
    }

    // AN ARRAY ELEMENT HAS AN ADDRESS AND A SLICE DOES NOT, which is the whole of this rule. The
    // range test runs FIRST and refuses before the receiver is even looked at, because `xs[0..2]`
    // produces a new array however `xs` was declared.
    func IsAddressableRefOutIndex(indexAccess: IndexAccessExpression, expressionTypes: Dictionary<object, TypeInfo>?): bool {
        if expressionTypes == null {
            return true
        }

        isRangeAccess := indexAccess.Index as RangeExpression != null
        if !isRangeAccess {
            indexType: TypeInfo = BuiltInTypes.Unknown
            if expressionTypes.TryGetValue(indexAccess.Index, out indexType) {
                isRangeAccess = AnalyzerIndexAccess.IsRangeLikeType(indexType)
            }
        }

        if isRangeAccess {
            return false
        }

        // A DIRECT COLUMN INDEXES ITS OWN BACKING ARRAY, so its element is addressable even though the
        // receiver expression is a member access rather than an array-typed local.
        if soaEscapeValue.IsSoaColumnMemberAccess(indexAccess.Object) {
            return true
        }

        receiverType: TypeInfo = BuiltInTypes.Unknown
        if !expressionTypes.TryGetValue(indexAccess.Object, out receiverType) {
            return true
        }

        resolvedReceiverType := declarationContextValue.ResolveDeclaredAlias(NonNullableType(receiverType))
        reflectedReceiver := resolvedReceiverType as ReflectionTypeInfo
        isArrayReceiver := resolvedReceiverType as ArrayTypeInfo != null || (reflectedReceiver != null && reflectedReceiver.Type.get_IsArray())
        if !isArrayReceiver {
            return false
        }

        resolvedIndexType: TypeInfo = BuiltInTypes.Unknown
        if !expressionTypes.TryGetValue(indexAccess.Index, out resolvedIndexType) {
            return true
        }

        resolvedIndexType = declarationContextValue.ResolveDeclaredAlias(resolvedIndexType)
        return BuiltInTypes.IsUnknown(resolvedIndexType) || BuiltInTypes.Is(resolvedIndexType, BuiltInTypes.Int) || AnalyzerIndexAccess.IsIndexLikeType(resolvedIndexType)
    }

    // PUBLISHED for the same reason its instance twin is, and a `Try` for the same language reason:
    // the RETURN says whether the owner could be RESOLVED, the out parameter carries the answer, and
    // an unresolved owner is a reason to stay permissive rather than a "not a field".
    func TryClassifyStaticFieldHop(hop: MemberAccessExpression, expressionTypes: Dictionary<object, TypeInfo>?, out isStaticField: bool): bool {
        isStaticField = false
        if expressionTypes == null {
            return false
        }

        ownerType: TypeInfo = BuiltInTypes.Unknown
        if !expressionTypes.TryGetValue(hop.Object, out ownerType) {
            return false
        }

        return TryClassifyStaticFieldMember(ownerType, hop.MemberName, out isStaticField)
    }

    func TryClassifyStaticFieldMember(owner: TypeInfo, memberName: string, out isStaticField: bool): bool {
        isStaticField = false
        resolvedOwner := declarationContextValue.ResolveDeclaredAlias(owner)
        selection: AnalyzerMemberSelection = new AnalyzerMemberSelection()
        if declarationContextValue.TryFindMember(resolvedOwner, memberName, out selection) {
            member := selection.Member
            if member != null {
                isStaticField = member.Kind == DeclaredMemberKind.Field && member.IsStatic
            }

            return true
        }

        substitution: Dictionary<string, TypeInfo>? = null
        sourceOwner := typeSubstitutionValue.GetSourceDeclarationOwner(resolvedOwner, out substitution)
        shape: AnalyzerSourceMemberShape = new AnalyzerSourceMemberShape()
        if declarationContextValue.TryGetSourceMemberShape(sourceOwner, null, out shape) {
            return true
        }

        reflected := NormalizeReflectionOwner(resolvedOwner) as ReflectionTypeInfo
        if reflected == null {
            return false
        }

        reflectedType := reflected.Type
        if IsTypeBuilder(reflectedType) || reflectedType.get_IsGenericTypeDefinition() {
            return false
        }

        isStaticField = IsReflectedStaticField(reflectedType, memberName)
        return true
    }

    // The mirror of `IsReflectedInstanceField`, differing in exactly one `BindingFlags` bit. The
    // name-claimed walk is SHARED with it rather than copied, because "a property, method or event of
    // this name is declared here" is the same question at either binding.
    static func IsReflectedStaticField(reflectedType: Type, memberName: string): bool {
        flags := BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly
        current: Type? = reflectedType
        while current != null {
            declaredType := current
            fields := declaredType.GetFields(flags)
            for field in fields {
                if field.get_Name() == memberName {
                    return true
                }
            }

            if ReflectionMemberNameIsClaimed(declaredType, memberName, flags) {
                return false
            }

            current = declaredType.get_BaseType()
        }

        return false
    }

    // ------------------------------------------------------------------------------------------
    // TWO SHARED NORMALISATIONS.
    // ------------------------------------------------------------------------------------------

    // PUBLISHED. A closed generic is normalised through its CLR type so its members can be read;
    // anything else is normalised through its declaration and then its own CLR conversion. Its C#
    // original keeps one caller — the call arm's static-field classifier — and is routed here.
    func NormalizeReflectionOwner(owner: TypeInfo): TypeInfo {
        genericOwner := owner as GenericTypeInfo
        if genericOwner != null {
            runtimeType := clrTypeConversionValue.TryConvertTypeInfoToClrType(owner)
            if runtimeType != null {
                return new ReflectionTypeInfo(runtimeType)
            }
        }

        normalized := declarationContextValue.ResolveDeclaredAlias(owner)
        openGeneric := normalized as GenericTypeInfo
        if openGeneric != null {
            definition := typeSubstitutionValue.ResolveGenericDefinition(openGeneric)
            if definition != null {
                normalized = definition
            }
        }

        if normalized as SimpleTypeInfo != null || normalized as GenericTypeInfo != null || normalized as ArrayTypeInfo != null {
            clrOwner := clrTypeConversionValue.TryConvertTypeInfoToClrType(normalized)
            if clrOwner != null {
                return new ReflectionTypeInfo(clrOwner)
            }
        }

        return normalized
    }

    // AN EMITTED TYPE HAS NO MEMBERS TO READ YET. `TypeBuilder` is identified by name rather than by a
    // type test, because a `TypeBuilder` receiver is exactly the shape whose members are not built.
    static func IsTypeBuilder(candidate: Type): bool {
        return candidate.get_FullName() == "System.Reflection.Emit.TypeBuilder" || IsTypeBuilderSubclass(candidate)
    }

    static func IsTypeBuilderSubclass(candidate: Type): bool {
        current := candidate.get_BaseType()
        while current != null {
            if current.get_FullName() == "System.Reflection.Emit.TypeBuilder" {
                return true
            }

            current = current.get_BaseType()
        }

        return false
    }

    // The nullable unwrap every structural question here performs first. Its C# original keeps three
    // callers outside this family and therefore could not move.
    func NonNullableType(candidate: TypeInfo): TypeInfo {
        nullable := declarationContextValue.ResolveDeclaredAlias(candidate) as NullableTypeInfo
        if nullable != null {
            return nullable.InnerType
        }

        return candidate
    }
}
