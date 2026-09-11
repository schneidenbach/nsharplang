namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// WHAT MAY BE DONE TO A STRUCT-OF-ARRAYS COLUMN BY A CALL.
//
// THIS IS A FAMILY, NOT AN ARM. Nothing here walks an expression, opens a scope, suspends, or
// re-enters the expression dispatch. Every member is a question-and-report over a node and a type
// the caller already holds, which is why the whole thing moves as one rule family in the shape
// `AnalyzerWriteTargets` established rather than as a resumable owner.
//
// WHY IT IS ITS OWN OWNER AND NOT A RULE ON THE CALL ARM. `AnalyzerSoaEscape` answers what a column
// VALUE may not do — be returned, thrown, printed, stored. This answers the narrower question a
// CALL raises: a column is a real array, so an `Array` method may legitimately be handed one, and
// the rule is a table of WHICH methods and WHICH parameter positions rather than a blanket refusal.
// Those two live next to each other because they are the same subject, and they are separate
// because one is a wholesale escape rule and the other is a per-method allow-list.
//
// THE FOUR GATES, in the one order they have always run, each ENDING the call at `unknown` when it
// fires so a later gate never reports over an earlier one's finding:
//   1  A MUTATING WHOLE-ARRAY CALL. `Array.Sort(points.x)` and `Array.Reverse(points.x)` reorder one
//      column in place and desynchronise it from its siblings, so they are refused as a table-member
//      MUTATION — the same report the assignment family gives, with "sorted directly" /
//      "reversed directly" as the action.
//   2  AN UNSUPPORTED STATIC `Array` CALL. `Array.Fill`, `Array.Copy` and `Array.Clear` are
//      SUPPORTED on a column at their array-shaped parameters, and `Array.Resize`/`Sort`/`Reverse`
//      have their OWN dedicated diagnostics (gate 1 and NL322), so both lists are skipped here.
//      Everything else — `Array.IndexOf`, `Array.BinarySearch`, … — is refused by name.
//   3  AN INSTANCE `Array` METHOD, called (`points.x.Clone()`) or taken as a VALUE
//      (`points.x.Clone`). This is the one gate reached from OUTSIDE the call walk.
//   4  A COLUMN AS AN ORDINARY RECEIVER OR ARGUMENT. Anything not allowed above escapes through
//      `AnalyzerSoaEscape`'s wording, receiver first and then arguments in order.
//
// THE ALLOW-LISTS ARE PARAMETER TABLES, NOT METHOD TABLES, and that is behaviour: `Array.Copy`'s
// array parameters are 0 and 1 in its three-argument form and 0 and 2 in its five-argument form, so
// `Array.Copy(points.x, other, 3)` is silent while `Array.Copy(a, points.x, 0, b, 3)` is not.
class AnalyzerSoaDirectColumnCalls {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    clrTypeConversionValue: AnalyzerClrTypeConversion
    soaEscapeValue: AnalyzerSoaEscape
    memberAccessValue: AnalyzerMemberAccess
    writeTargetsValue: AnalyzerWriteTargets
    supportedStaticArrayMethodsValue: HashSet<string>
    dedicatedStaticArrayDiagnosticsValue: HashSet<string>
    systemArrayTypeValue: Type?

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, clrTypeConversion: AnalyzerClrTypeConversion, soaEscape: AnalyzerSoaEscape, memberAccess: AnalyzerMemberAccess, writeTargets: AnalyzerWriteTargets) {
        diagnosticsValue = diagnostics
        spansValue = spans
        scopesValue = scopes
        declarationContextValue = declarationContext
        clrTypeConversionValue = clrTypeConversion
        soaEscapeValue = soaEscape
        memberAccessValue = memberAccess
        writeTargetsValue = writeTargets
        supportedStaticArrayMethodsValue = NameSet(["Fill", "Copy", "Clear"])
        dedicatedStaticArrayDiagnosticsValue = NameSet(["Resize", "Sort", "Reverse"])

        // `System.Array` is read out of the core library rather than written `typeof(Array)`,
        // the established `typeof(object).get_Assembly()` idiom: it yields the identical RUNTIME
        // Type instance, so the runtime-versus-MetadataLoadContext asymmetry the C# original
        // depended on is preserved exactly — an `Array` loaded into a MetadataLoadContext is not
        // reference-equal to this and, like the `== typeof(Array)` it replaces, answers false.
        systemArrayTypeValue = typeof(object).get_Assembly().GetType("System.Array")
    }

    static func NameSet(names: string[]): HashSet<string> {
        result := new HashSet<string>(StringComparer.Ordinal)
        index := 0
        while index < names.Length {
            result.Add(names[index])
            index = index + 1
        }

        return result
    }

    // THE WHOLE FAMILY AS ONE QUESTION, which is how the call walk asks it. The four gates run in
    // their fixed order and the first one that reports ends the call; the walk needs the verdict and
    // nothing else, so it is one boolean rather than four driver round trips.
    func ReportDirectColumnCallIfNeeded(call: CallExpression, calleeType: TypeInfo): bool {
        if ReportMutatingArrayCallIfNeeded(call) {
            return true
        }

        if ReportUnsupportedStaticArrayCallIfNeeded(call) {
            return true
        }

        if ReportUnsupportedArrayInstanceCallIfNeeded(call, calleeType) {
            return true
        }

        return ReportUnsupportedCallArgumentIfNeeded(call, calleeType)
    }

    // ------------------------------------------------------------------------------------------
    // GATE 1 — THE MUTATING WHOLE-ARRAY CALL.
    // ------------------------------------------------------------------------------------------

    // `Array.Sort` and `Array.Reverse` are the two static array methods that REORDER their argument
    // in place. A column reordered on its own no longer lines up with the columns beside it, so the
    // refusal is the table-member MUTATION report rather than an escape: the developer is told what
    // they were doing to the table, not that a value got out of it.
    func ReportMutatingArrayCallIfNeeded(call: CallExpression): bool {
        if call.Arguments.Count == 0 {
            return false
        }

        memberAccess := call.Callee as MemberAccessExpression
        if memberAccess == null {
            return false
        }

        action: string? = null
        if memberAccess.MemberName == "Sort" {
            action = "sorted directly"
        } else if memberAccess.MemberName == "Reverse" {
            action = "reversed directly"
        }

        if action == null {
            return false
        }

        if !IsStaticArrayTarget(memberAccess.Object) {
            return false
        }

        columnMember := FindMutatingArrayColumnArgument(call, memberAccess.MemberName)
        if columnMember == null {
            return false
        }

        writeTargetsValue.ReportSoaTableMemberMutation(columnMember, action, true)
        return true
    }

    // The FIRST array-shaped parameter that is a column wins, in argument order, so a call that
    // sorts one column by another names the one the method would have reordered.
    func FindMutatingArrayColumnArgument(call: CallExpression, methodName: string): MemberAccessExpression? {
        index := 0
        while index < call.Arguments.Count {
            argument := call.Arguments[index]
            if IsMutatingArrayParameter(call, methodName, argument, index) {
                candidate := soaEscapeValue.FindSoaColumnMemberAccess(argument.Value)
                if candidate != null {
                    return candidate
                }
            }

            index = index + 1
        }

        return null
    }

    // A NAMED argument is matched by the parameter's own name and a POSITIONAL one by its place,
    // because the two forms carry different information and neither can be derived from the other.
    static func IsMutatingArrayParameter(call: CallExpression, methodName: string, argument: Argument, positionalIndex: int): bool {
        if argument.Name != null {
            if methodName == "Sort" {
                return argument.Name == "array" || argument.Name == "keys" || argument.Name == "items"
            }

            if methodName == "Reverse" {
                return argument.Name == "array"
            }

            return false
        }

        if methodName == "Sort" {
            return IsPositionalArraySortParameter(call.Arguments.Count, positionalIndex)
        }

        if methodName == "Reverse" {
            return positionalIndex == 0
        }

        return false
    }

    // `Array.Sort`'s array parameters are decided by its ARITY: one array at 0 for the one- and
    // three-argument forms, and a keys/items PAIR at 0 and 1 for the two- and four-argument forms.
    // Any other arity is not an overload this rule recognises.
    static func IsPositionalArraySortParameter(argumentCount: int, positionalIndex: int): bool {
        if argumentCount == 1 {
            return positionalIndex == 0
        }

        if argumentCount == 2 {
            return positionalIndex == 0 || positionalIndex == 1
        }

        if argumentCount == 3 {
            return positionalIndex == 0
        }

        if argumentCount == 4 {
            return positionalIndex == 0 || positionalIndex == 1
        }

        return false
    }

    // ------------------------------------------------------------------------------------------
    // GATE 2 — THE UNSUPPORTED STATIC `Array` CALL.
    // ------------------------------------------------------------------------------------------

    // Every static `Array` method that is NOT on one of the two lists refuses a column by name, and
    // the diagnostic underlines the METHOD rather than the argument: the developer's choice of
    // method is what has to change, and the suggestion names the three that do work.
    func ReportUnsupportedStaticArrayCallIfNeeded(call: CallExpression): bool {
        if call.Arguments.Count == 0 {
            return false
        }

        memberAccess := call.Callee as MemberAccessExpression
        if memberAccess == null {
            return false
        }

        if !IsStaticArrayTarget(memberAccess.Object) {
            return false
        }

        columnMember := FindUnsupportedStaticArrayColumnArgument(call, memberAccess.MemberName)
        if columnMember == null {
            return false
        }

        line := memberAccess.Line
        column := spansValue.GetMemberNameColumn(memberAccess)
        length := memberAccess.MemberName.Length
        if length < 1 {
            length = 1
        }

        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "SoA table member '" + columnMember.MemberName + "' cannot be passed to Array method '" + memberAccess.MemberName + "' directly", line, column, "Use table.column[row] for element access, or Array.Fill, Array.Copy, and Array.Clear for supported whole-column operations.", length)
        return true
    }

    // The first column argument at a parameter position this rule does NOT already handle. A
    // supported whole-column operation and a method with its own dedicated diagnostic both count as
    // handled, so neither is reported twice.
    func FindUnsupportedStaticArrayColumnArgument(call: CallExpression, methodName: string): MemberAccessExpression? {
        index := 0
        while index < call.Arguments.Count {
            argument := call.Arguments[index]
            candidate := soaEscapeValue.FindSoaColumnMemberAccess(argument.Value)
            if candidate != null && !IsHandledStaticArrayParameter(call, methodName, argument, index) {
                return candidate
            }

            index = index + 1
        }

        return null
    }

    // INSTANCE rather than static, unlike the C# it replaces, because the two lists it consults are
    // constructor-built `HashSet`s: the estate holds no static mutable fields, so a name table is an
    // owner's field and every reader of one is an instance member.
    func IsHandledStaticArrayParameter(call: CallExpression, methodName: string, argument: Argument, positionalIndex: int): bool {
        return IsPinnedArrayParameter(call, methodName, argument, positionalIndex) || IsDedicatedArrayDiagnosticParameter(call, methodName, argument, positionalIndex)
    }

    // THE SUPPORTED WHOLE-COLUMN OPERATIONS. `Fill` and `Clear` take one array at 0; `Copy` takes
    // its source and destination at 0 and 1 in the three-argument form and at 0 and 2 in the
    // five-argument form — a length or an index at those positions is a plain `int` and is not this
    // rule's business.
    func IsPinnedArrayParameter(call: CallExpression, methodName: string, argument: Argument, positionalIndex: int): bool {
        if !supportedStaticArrayMethodsValue.Contains(methodName) {
            return false
        }

        if argument.Name != null {
            if methodName == "Fill" || methodName == "Clear" {
                return argument.Name == "array"
            }

            if methodName == "Copy" {
                return argument.Name == "sourceArray" || argument.Name == "destinationArray"
            }

            return false
        }

        if methodName == "Fill" || methodName == "Clear" {
            return positionalIndex == 0
        }

        if methodName == "Copy" {
            if call.Arguments.Count == 3 {
                return positionalIndex == 0 || positionalIndex == 1
            }

            if call.Arguments.Count == 5 {
                return positionalIndex == 0 || positionalIndex == 2
            }
        }

        return false
    }

    // THE METHODS THAT HAVE THEIR OWN SENTENCE. `Sort` and `Reverse` are gate 1's mutation report
    // and `Resize` is refused by the write-target family, so this gate stays silent at their array
    // parameters rather than adding a second, blunter diagnostic on the same call.
    func IsDedicatedArrayDiagnosticParameter(call: CallExpression, methodName: string, argument: Argument, positionalIndex: int): bool {
        if !dedicatedStaticArrayDiagnosticsValue.Contains(methodName) {
            return false
        }

        if argument.Name != null {
            if methodName == "Resize" {
                return argument.Name == "array"
            }

            if methodName == "Sort" {
                return argument.Name == "array" || argument.Name == "keys" || argument.Name == "items"
            }

            if methodName == "Reverse" {
                return argument.Name == "array"
            }

            return false
        }

        if methodName == "Resize" {
            return positionalIndex == 0
        }

        if methodName == "Sort" {
            return IsPositionalArraySortParameter(call.Arguments.Count, positionalIndex)
        }

        if methodName == "Reverse" {
            return positionalIndex == 0
        }

        return false
    }

    // ------------------------------------------------------------------------------------------
    // GATE 3 — THE INSTANCE `Array` METHOD, CALLED OR TAKEN AS A VALUE.
    // ------------------------------------------------------------------------------------------

    func ReportUnsupportedArrayInstanceCallIfNeeded(call: CallExpression, calleeType: TypeInfo): bool {
        return ReportUnsupportedArrayInstanceMethodReferenceIfNeeded(call.Callee, calleeType, true)
    }

    // THE ONE GATE REACHED FROM OUTSIDE THE CALL WALK. `points.x.Clone()` and the bare
    // `points.x.Clone` are the same mistake at two grammars, so they share one rule and differ only
    // in the two words the sentence ends with — which is why the expression walk's value tail asks
    // this directly with `isCall = false`.
    func ReportUnsupportedArrayInstanceMethodReferenceIfNeeded(expression: Expression, valueType: TypeInfo, isCall: bool): bool {
        memberAccess := expression as MemberAccessExpression
        if memberAccess == null {
            return false
        }

        if !IsRuntimeArrayInstanceMethodReference(valueType) {
            return false
        }

        columnMember := soaEscapeValue.FindSoaColumnMemberAccess(memberAccess.Object)
        if columnMember == null {
            return false
        }

        line := memberAccess.Line
        column := spansValue.GetMemberNameColumn(memberAccess)
        length := memberAccess.MemberName.Length
        if length < 1 {
            length = 1
        }

        action := "use"
        suffix := " as a value"
        if isCall {
            action = "call"
            suffix = " directly"
        }

        diagnosticsValue.Report(ErrorCode.InvalidSyntax, "SoA table member '" + columnMember.MemberName + "' cannot " + action + " array method '" + memberAccess.MemberName + "'" + suffix, line, column, "Use table.column[row] for element access, or Array.Fill, Array.Copy, and Array.Clear for supported whole-column operations.", length)
        return true
    }

    // A method group qualifies only if EVERY candidate is an instance method — a group that mixes a
    // static overload in is not an instance-method reference, and an EMPTY group is not one either.
    func IsRuntimeArrayInstanceMethodReference(valueType: TypeInfo): bool {
        resolvedType := declarationContextValue.ResolveDeclaredAlias(valueType)

        methodInfo := resolvedType as ReflectionMethodInfo
        if methodInfo != null {
            return IsRuntimeArrayInstanceMethod(methodInfo.Method)
        }

        methodGroup := resolvedType as ReflectionMethodGroupInfo
        if methodGroup != null {
            if methodGroup.Methods.Length == 0 {
                return false
            }

            index := 0
            while index < methodGroup.Methods.Length {
                if !IsRuntimeArrayInstanceMethod(methodGroup.Methods[index]) {
                    return false
                }

                index = index + 1
            }

            return true
        }

        return false
    }

    // The ACCESSOR spelling, not the property one: a reflected `MethodInfo`'s `IsStatic` is on the
    // columnar catalog as `get_IsStatic()` and declines as `.IsStatic` — the same accessor-spelling
    // hazard the declaration-context and resource owners already route around.
    static func IsRuntimeArrayInstanceMethod(method: MethodInfo): bool {
        return !method.get_IsStatic()
    }

    // ------------------------------------------------------------------------------------------
    // GATE 4 — THE COLUMN AS AN ORDINARY RECEIVER OR ARGUMENT.
    // ------------------------------------------------------------------------------------------

    // The RECEIVER is asked before the arguments, because a call ON a column is a more specific
    // mistake than a call that merely takes one. A `ref`/`out` argument is skipped: the write-target
    // family already ruled on it and a column IS addressable, so escaping is not what it did.
    func ReportUnsupportedCallArgumentIfNeeded(call: CallExpression, calleeType: TypeInfo): bool {
        if IsAllowedCall(call, calleeType) {
            return false
        }

        memberAccess := call.Callee as MemberAccessExpression
        if memberAccess != null && !BuiltInTypes.IsUnknown(calleeType) {
            receiverColumn := soaEscapeValue.FindSoaColumnMemberAccess(memberAccess.Object)
            if receiverColumn != null {
                soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscape(memberAccess.Object, receiverColumn, "used as the receiver for '" + memberAccess.MemberName + "'")
                return true
            }
        }

        index := 0
        while index < call.Arguments.Count {
            argument := call.Arguments[index]
            if argument.Modifier != ArgumentModifier.Ref && argument.Modifier != ArgumentModifier.Out {
                if soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(argument.Value, "passed as an argument") {
                    return true
                }
            }

            index = index + 1
        }

        return false
    }

    // TWO CALLS A COLUMN MAY ALWAYS APPEAR IN. `wrap` is the synthesised constructor that BUILDS a
    // table out of column arrays — refusing it would refuse the only way to make one — and any
    // static `Array` call has already been ruled on by gates 1 and 2, so reaching here means it was
    // allowed and must not be refused a second time under a blunter wording.
    func IsAllowedCall(call: CallExpression, calleeType: TypeInfo): bool {
        functionType := calleeType as FunctionTypeInfo
        if functionType != null && functionType.SyntheticName == "wrap" {
            return true
        }

        memberAccess := call.Callee as MemberAccessExpression
        return memberAccess != null && IsStaticArrayTarget(memberAccess.Object)
    }

    // ------------------------------------------------------------------------------------------
    // THE SHARED QUESTION — IS THIS EXPRESSION THE `System.Array` TYPE ITSELF?
    // ------------------------------------------------------------------------------------------

    // WHAT MAKES A RECEIVER THE STATIC `Array` TYPE, and every arm of it is a shadowing question
    // rather than a name test. A local called `Array` shadows the type and the answer is NO; a TYPE
    // called `Array` in scope answers by what it resolves to; and only when nothing in scope claims
    // the name does the bare spelling `Array` get to mean `System.Array`, which is the pragmatic arm
    // that lets an un-imported `Array.Fill` still be understood.
    func IsStaticArrayTarget(expression: Expression): bool {
        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return IsStaticArrayTarget(parenthesized.Inner)
        }

        identifier := expression as IdentifierExpression
        if identifier != null {
            if scopesValue.LookupSymbol(identifier.Name) != null {
                return false
            }

            localType := scopesValue.LookupType(identifier.Name)
            if localType != null {
                return IsSystemArrayTypeInfo(declarationContextValue.ResolveDeclaredAlias(localType))
            }

            identifierType: TypeInfo = BuiltInTypes.Unknown
            if memberAccessValue.TryResolveTypeValuedMemberAccess(identifier, out identifierType) && IsSystemArrayTypeInfo(identifierType) {
                return true
            }

            return identifier.Name == "Array"
        }

        // `System.Array`, spelled out. The qualifier is checked for shadowing the same way the bare
        // name is, and an unshadowed `System.Array` that resolves to nothing is still taken at its
        // word — the two-part spelling cannot mean anything else.
        qualified := expression as MemberAccessExpression
        if qualified != null && qualified.MemberName == "Array" {
            system := qualified.Object as IdentifierExpression
            if system != null && system.Name == "System" {
                if scopesValue.LookupSymbol(system.Name) != null {
                    return false
                }

                systemArrayType: TypeInfo = BuiltInTypes.Unknown
                if scopesValue.LookupType(system.Name) != null {
                    return memberAccessValue.TryResolveTypeValuedMemberAccess(expression, out systemArrayType) && IsSystemArrayTypeInfo(systemArrayType)
                }

                if memberAccessValue.TryResolveTypeValuedMemberAccess(expression, out systemArrayType) {
                    return IsSystemArrayTypeInfo(systemArrayType)
                }

                return true
            }
        }

        ownerType: TypeInfo = BuiltInTypes.Unknown
        if memberAccessValue.TryResolveTypeValuedMemberAccess(expression, out ownerType) {
            return IsSystemArrayTypeInfo(ownerType)
        }

        return false
    }

    // The CLR conversion answers first, and the external-name arm catches the case it cannot: a type
    // known only by name, from an assembly no MetadataLoadContext has opened.
    func IsSystemArrayTypeInfo(candidate: TypeInfo): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        converted := clrTypeConversionValue.TryConvertTypeInfoToClrType(resolved)
        if converted != null && systemArrayTypeValue != null && converted == systemArrayTypeValue {
            return true
        }

        external := resolved as ExternalTypeInfo
        return external != null && (external.Name == "Array" || external.Name == "System.Array")
    }
}
