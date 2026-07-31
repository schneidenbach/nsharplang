namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Text
import NSharpLang.Compiler.Ast

// THE ANALYZER'S OVERLOAD SCORING AND APPLICABILITY KERNEL.
//
// Overload resolution in N# runs over TWO signature worlds and this owner holds the pure decision
// tables both of them consult:
//
//   * THE REFLECTION WORLD, over CLR `Type` / `ParameterInfo` / `MethodInfo` read out of a
//     MetadataLoadContext. A candidate is APPLICABLE when its arity admits the argument count
//     (`HasCompatibleReflectionArity`) and every position MATCHES — `TryMatchReflectionParameter`,
//     which is simultaneously the applicability predicate and the generic-inference walk: an
//     unbound type parameter BINDS to the argument, an already-bound one must agree. A candidate
//     that survives is RANKED by `GetReflectionMatchScore`.
//   * THE SOURCE WORLD, over `FunctionTypeInfo` built from N# declarations. Applicability is an
//     arity question answered by the params/optional tables, and ranking is `GetNSharpMatchScore`.
//
// THE TWO SCORE LADDERS ARE DELIBERATELY THE SAME SHAPE — 8 identical, 6 implicit numeric,
// 4 assignable, 2 otherwise — so a source overload and a reflected overload rank comparably. They
// are NOT the same function: the reflection ladder compares CLR types with the reflection identity
// rule (which is how the same type read through two MetadataLoadContexts compares equal), while the
// source ladder compares `TypeInfo`s, resolving declared aliases first and falling back to a
// CROSS-REPRESENTATION identity — a `SimpleTypeInfo` and a `ReflectionTypeInfo` denoting the same
// CLR type score 8, which is what stops `int` written in source from losing to `System.Int32` read
// from metadata.
//
// THE PARAMS RULES ARE THREE SEPARATE QUESTIONS and they must not be collapsed. Whether a parameter
// IS a params parameter is an attribute fact in the reflection world (`IsParamsParameter`) and a
// MODIFIER fact in the source world (`GetSyntheticParamsParameterIndex`, which additionally demands
// the modifier list be exactly as long as the signature, so a malformed signature never claims a
// params tail). What a params parameter's ELEMENT type is has its own table
// (`TryGetReflectionParamsElementType`) that accepts spans and the read-only sequence interfaces as
// well as arrays. And whether a given call EXPANDED the params tail is a third question
// (`IsExpandedReflectionParamsArgument`) answered by comparing the bound-argument's open parameter
// type against the declared one.
//
// THE RECEIVER OFFSET IS A ONE-PLACE RULE. `GetSyntheticParameterStartIndex` decides whether a
// signature's first parameter is supplied by a member-access RECEIVER rather than by the argument
// list, and every arity computation in the source world subtracts it. Getting this wrong shifts an
// entire extension call's argument-to-parameter map, so it lives here rather than being recomputed.
//
// THE FORMATTERS ARE PART OF THE KERNEL, NOT DECORATION. NL402's "no matching overload" text and its
// fix hint are how a user reads the resolution failure, so the signature renderers are pinned
// alongside the tables that produced the failure. They report nothing themselves — they return
// strings, and the reporting arms in the analyzer's walk decide what to do with them.
//
// Do not reintroduce any of this in C#. This owner reports nothing and records nothing: every member
// is a question with an answer.
public class AnalyzerOverloadFacts {

    // ------------------------------------------------------------------
    // The reflection world: applicability, generic inference and ranking.
    // ------------------------------------------------------------------

    // The reflection score ladder. 8 identical, 6 implicit numeric widening, 4 assignable,
    // 2 otherwise — and 2 rather than "inapplicable", because applicability was already decided by
    // `TryMatchReflectionParameter`; this only ORDERS the survivors.
    public static func GetReflectionMatchScore(parameterType: Type, argumentType: Type): int {
        if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(parameterType, argumentType) {
            return 8
        }

        if AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(argumentType, parameterType) {
            return 6
        }

        if AnalyzerConversionFacts.IsReflectionAssignableFrom(parameterType, argumentType) {
            return 4
        }

        return 2
    }

    // Applicability AND inference in one walk. `bindings` accumulates the type-parameter bindings the
    // match implies, so calling this over a parameter list in order is the inference algorithm: the
    // FIRST position that mentions a type parameter binds it, and every later position must agree
    // with the binding (identically, by assignability, or by an implicit numeric widening).
    //
    // A by-ref shell is stripped before anything else, an open ARRAY descends into its element, and
    // an open GENERIC descends pairwise — after `TryFindCompatibleGenericType` has re-expressed the
    // argument as the parameter's own generic definition, which is what lets a `List<int>` argument
    // match an `IEnumerable<T>` parameter. A closed parameter is a plain assignability question. An
    // open parameter that is NEITHER array nor generic (a generic pointer or function-pointer shell)
    // matches unconditionally rather than failing, so an exotic signature cannot silently drop a
    // candidate.
    public static func TryMatchReflectionParameter(
        parameterType: Type,
        argumentType: Type,
        bindings: Dictionary<Type, Type>): bool {
        effectiveParameterType := parameterType
        if effectiveParameterType.get_IsByRef() {
            byRefElement := effectiveParameterType.GetElementType()
            if byRefElement != null {
                effectiveParameterType = byRefElement
            }
        }

        if effectiveParameterType.get_IsGenericParameter() {
            existingBinding: Type = typeof(object)
            if bindings.TryGetValue(effectiveParameterType, out existingBinding) {
                if TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(existingBinding, argumentType) {
                    return true
                }

                if AnalyzerConversionFacts.IsReflectionAssignableFrom(existingBinding, argumentType) {
                    return true
                }

                return AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(argumentType, existingBinding)
            }

            bindings[effectiveParameterType] = argumentType
            return true
        }

        if !effectiveParameterType.get_ContainsGenericParameters() {
            if AnalyzerConversionFacts.IsReflectionAssignableFrom(effectiveParameterType, argumentType) {
                return true
            }

            return AnalyzerConversionFacts.IsImplicitNumericReflectionConversion(argumentType, effectiveParameterType)
        }

        if effectiveParameterType.get_IsArray() {
            if !argumentType.get_IsArray() {
                return false
            }

            parameterElement := effectiveParameterType.GetElementType()
            argumentElement := argumentType.GetElementType()
            if parameterElement == null || argumentElement == null {
                return false
            }

            return TryMatchReflectionParameter(parameterElement, argumentElement, bindings)
        }

        if !effectiveParameterType.get_IsGenericType() {
            return true
        }

        comparisonType := argumentType
        compatibleType: Type? = null
        if TryFindCompatibleGenericType(effectiveParameterType, argumentType, out compatibleType) {
            if compatibleType != null {
                comparisonType = compatibleType
            }
        } else {
            if !argumentType.get_IsGenericType() {
                return false
            }

            if argumentType.GetGenericTypeDefinition() != effectiveParameterType.GetGenericTypeDefinition() {
                return false
            }
        }

        parameterArguments := effectiveParameterType.GetGenericArguments()
        comparisonArguments := comparisonType.GetGenericArguments()
        if parameterArguments.Length != comparisonArguments.Length {
            return false
        }

        index := 0
        while index < parameterArguments.Length {
            if !TryMatchReflectionParameter(parameterArguments[index], comparisonArguments[index], bindings) {
                return false
            }

            index = index + 1
        }

        return true
    }

    // Re-expresses `actualType` as an instantiation of the parameter's own generic DEFINITION. The
    // search order is the type itself, then its interfaces, then its base chain — the interface pass
    // comes first because that is the case the argument-binding walk actually needs (`List<int>`
    // against `IEnumerable<T>`), and a type cannot implement the same definition twice with
    // different arguments.
    public static func TryFindCompatibleGenericType(
        parameterType: Type,
        actualType: Type,
        out compatibleType: Type?): bool {
        compatibleType = null

        if !parameterType.get_IsGenericType() {
            return false
        }

        genericDefinition := parameterType.GetGenericTypeDefinition()

        if actualType.get_IsGenericType() && actualType.GetGenericTypeDefinition() == genericDefinition {
            compatibleType = actualType
            return true
        }

        interfaces := actualType.GetInterfaces()
        index := 0
        while index < interfaces.Length {
            candidateInterface := interfaces[index]
            if candidateInterface.get_IsGenericType()
                && candidateInterface.GetGenericTypeDefinition() == genericDefinition {
                compatibleType = candidateInterface
                return true
            }

            index = index + 1
        }

        currentBase := actualType.get_BaseType()
        while currentBase != null {
            if currentBase.get_IsGenericType() && currentBase.GetGenericTypeDefinition() == genericDefinition {
                compatibleType = currentBase
                return true
            }

            currentBase = currentBase.get_BaseType()
        }

        return false
    }

    // Whether an extension method's RECEIVER parameter accepts a receiver of this CLR type. A closed
    // receiver is plain CLR assignability; an open one only has to be re-expressible over the
    // receiver, because the type arguments are inferred later by the argument walk.
    public static func IsExtensionParameterCompatible(parameterType: Type, targetClrType: Type): bool {
        if !parameterType.get_ContainsGenericParameters() {
            return parameterType.IsAssignableFrom(targetClrType)
        }

        ignored: Type? = null
        return TryFindCompatibleGenericType(parameterType, targetClrType, out ignored)
    }

    // The attribute test by FULL NAME rather than by type identity: the attribute is read through a
    // MetadataLoadContext, where the compiler's own `ExtensionAttribute` is a different type object.
    public static func HasExtensionAttribute(method: MethodInfo): bool {
        return HasAttributeNamed(
            method.GetCustomAttributesData(),
            "System.Runtime.CompilerServices.ExtensionAttribute")
    }

    // Same full-name discipline, for the params tail.
    public static func IsParamsParameter(parameter: ParameterInfo): bool {
        return HasAttributeNamed(parameter.GetCustomAttributesData(), "System.ParamArrayAttribute")
    }

    // The count comes through `object` deliberately: a generic `IList<T>` does not cast to the
    // non-generic `IList` on the columnar surface, but an `object` does.
    static func SequenceCount(sequence: object): int {
        list := (IList)sequence
        return list.Count
    }

    static func HasAttributeNamed(attributes: IList<CustomAttributeData>, fullName: string): bool {
        count := SequenceCount(attributes)
        index := 0
        while index < count {
            attribute := attributes.get_Item(index)
            attributeType := attribute.get_AttributeType()
            if attributeType.FullName == fullName {
                return true
            }

            index = index + 1
        }

        return false
    }

    // The reflection arity filter. `parameterOffset` skips an extension method's receiver. Optional
    // and params parameters are not REQUIRED, and a params tail removes the upper bound entirely.
    public static func HasCompatibleReflectionArity(
        parameters: ParameterInfo[],
        parameterOffset: int,
        argumentCount: int): bool {
        firstIndex := parameterOffset
        if firstIndex < 0 {
            firstIndex = 0
        }

        effectiveCount := parameters.Length - firstIndex
        if effectiveCount < 0 {
            effectiveCount = 0
        }

        hasParams := false
        if effectiveCount > 0 {
            hasParams = IsParamsParameter(parameters[parameters.Length - 1])
        }

        requiredParameters := 0
        index := firstIndex
        while index < parameters.Length {
            parameter := parameters[index]
            if !parameter.get_IsOptional() && !IsParamsParameter(parameter) {
                requiredParameters = requiredParameters + 1
            }

            index = index + 1
        }

        if argumentCount < requiredParameters {
            return false
        }

        if !hasParams && argumentCount > effectiveCount {
            return false
        }

        return true
    }

    // A by-ref parameter's underlying type; everything else is itself.
    public static func GetByRefElementType(clrType: Type): Type {
        if !clrType.get_IsByRef() {
            return clrType
        }

        element := clrType.GetElementType()
        if element == null {
            return clrType
        }

        return element
    }

    // What a params parameter binds ELEMENT-wise. Arrays answer their element type; the span and
    // read-only sequence shapes answer their single type argument, which is how a `params
    // ReadOnlySpan<T>` overload accepts a loose argument list. Anything else answers false — and
    // still writes `object`, because the caller uses the element type either way.
    public static func TryGetReflectionParamsElementType(paramsParameterType: Type, out elementType: Type): bool {
        elementType = typeof(object)

        if paramsParameterType.get_IsArray() {
            arrayElement := paramsParameterType.GetElementType()
            if arrayElement != null {
                elementType = arrayElement
                return true
            }
        }

        if paramsParameterType.get_IsGenericType() {
            genericDefinitionName := paramsParameterType.GetGenericTypeDefinition().get_FullName()
            if genericDefinitionName == "System.ReadOnlySpan`1"
                || genericDefinitionName == "System.Span`1"
                || genericDefinitionName == "System.Collections.Generic.IEnumerable`1"
                || genericDefinitionName == "System.Collections.Generic.IReadOnlyList`1"
                || genericDefinitionName == "System.Collections.Generic.IReadOnlyCollection`1" {
                elementType = paramsParameterType.GetGenericArguments()[0]
                return true
            }
        }

        elementType = typeof(object)
        return false
    }

    // The delegate a lambda argument is really being matched against: the by-ref shell comes off, and
    // an expression tree unwraps to the delegate it encodes.
    public static func GetDelegateParameterTypeForLambdaTarget(parameterType: Type): Type {
        effectiveType := GetByRefElementType(parameterType)
        expressionDelegateType: Type = typeof(object)
        if AnalyzerFunctionTypeFactory.TryGetExpressionTreeDelegateType(effectiveType, out expressionDelegateType) {
            return expressionDelegateType
        }

        return effectiveType
    }

    // A call written as `receiver.Method(...)` against a method carrying the extension attribute.
    // The two arities differ in whether the RECEIVER is also checked: the bare form is the syntactic
    // question the signature formatter asks, the receiver form is the applicability question.
    public static func IsExtensionMethodCall(method: MethodInfo, call: CallExpression): bool {
        memberAccess := call.Callee as MemberAccessExpression
        if memberAccess == null {
            return false
        }

        return HasExtensionAttribute(method)
    }

    public static func IsExtensionMethodCallOnReceiver(
        method: MethodInfo,
        call: CallExpression,
        receiverClrType: Type?): bool {
        if !IsExtensionMethodCall(method, call) {
            return false
        }

        if receiverClrType == null {
            return false
        }

        parameters := method.GetParameters()
        if parameters.Length == 0 {
            return false
        }

        return IsExtensionParameterCompatible(parameters[0].get_ParameterType(), receiverClrType)
    }

    // Whether a bound argument landed in an EXPANDED params tail. The bound argument records the OPEN
    // parameter type it was matched against; when the tail was expanded that is the ELEMENT type and
    // therefore differs from the declared parameter type, and when the whole array was passed
    // directly the two are the same type.
    public static func IsExpandedReflectionParamsArgument(
        openParameterType: Type,
        parameter: ParameterInfo): bool {
        if !IsParamsParameter(parameter) {
            return false
        }

        return !TypeInfoIdentityFacts.HaveSameReflectionTypeIdentity(
            openParameterType,
            GetByRefElementType(parameter.get_ParameterType()))
    }

    // Whether a user-defined operator's CLR parameter accepts this operand.
    //
    // A NULL operand type is INCOMPATIBLE, deliberately. The operand's CLR type is unknown, so the
    // operator cannot be proven to apply and the IL backend would not bind it either — it resolves
    // against concrete argument types. Answering true here would let an unrelated operand piggy-back
    // on a vector or struct operator (`Vector<int> + SomeUserType`) and swallow a real type mismatch.
    public static func IsRuntimeOperatorParameterCompatible(parameterType: Type, argumentType: Type?): bool {
        if argumentType == null {
            return false
        }

        if parameterType.IsAssignableFrom(argumentType) {
            return true
        }

        if parameterType == argumentType {
            return true
        }

        if !parameterType.get_IsByRef() {
            return false
        }

        return parameterType.GetElementType() == argumentType
    }

    // ------------------------------------------------------------------
    // The source world: the arity, params and receiver-offset tables.
    // ------------------------------------------------------------------

    // The index of a source signature's params parameter, or -1. The modifier list must be exactly as
    // long as the signature and its LAST entry must carry the modifier: a signature whose modifier
    // list disagrees with its parameter list is treated as having no params tail rather than being
    // indexed into.
    public static func GetSyntheticParamsParameterIndex(functionType: FunctionTypeInfo, expectedCount: int): int {
        if !functionType.HasParamsParameter || expectedCount == 0 {
            return -1
        }

        parameterModifiers := functionType.ParameterModifiers
        if parameterModifiers == null {
            return -1
        }

        if parameterModifiers.Count != expectedCount {
            return -1
        }

        if parameterModifiers[expectedCount - 1] != ParameterModifier.Params {
            return -1
        }

        return expectedCount - 1
    }

    // How many of a source signature's parameters have no default. A count outside the signature is
    // ignored rather than trusted.
    public static func GetSyntheticRequiredParameterCount(functionType: FunctionTypeInfo, expectedCount: int): int {
        requiredCount := expectedCount
        declaredRequiredCount: int? = functionType.RequiredParameterCount
        if declaredRequiredCount.HasValue {
            requiredCount = declaredRequiredCount.Value
        }

        if requiredCount < 0 || requiredCount > expectedCount {
            return expectedCount
        }

        return requiredCount
    }

    // The same count as the CALLER must supply — the receiver offset comes off.
    public static func GetSyntheticRequiredArgumentCount(
        functionType: FunctionTypeInfo,
        expectedCount: int,
        parameterStartIndex: int): int {
        requiredCount := GetSyntheticRequiredParameterCount(functionType, expectedCount)
        clampedStart := parameterStartIndex
        if clampedStart < 0 {
            clampedStart = 0
        }

        if clampedStart > expectedCount {
            clampedStart = expectedCount
        }

        difference := requiredCount - clampedStart
        if difference < 0 {
            return 0
        }

        return difference
    }

    // 1 when the signature's first parameter is supplied by a member-access RECEIVER instead of by
    // the argument list, else 0. Both halves are required: a receiver-style signature invoked
    // WITHOUT a member access (a bare call to an extension by its declared name) supplies every
    // parameter positionally.
    public static func GetSyntheticParameterStartIndex(functionType: FunctionTypeInfo, call: CallExpression): int {
        if !functionType.SourceHasReceiverParameter {
            return 0
        }

        memberAccess := call.Callee as MemberAccessExpression
        if memberAccess == null {
            return 0
        }

        return 1
    }

    // Whether a parameter is written as a BARE type-parameter name. This is the specificity signal
    // the source tie-break uses: an overload that matched by binding a type parameter is less
    // specific than one that matched a written type.
    public static func IsDirectFunctionTypeParameterReference(
        typeReference: TypeReference,
        typeParameters: List<TypeParameter>): bool {
        simple := typeReference as SimpleTypeReference
        if simple == null {
            return false
        }

        index := 0
        while index < typeParameters.Count {
            if typeParameters[index].Name == simple.Name {
                return true
            }

            index = index + 1
        }

        return false
    }

    // The type reference generic inference should read for a params parameter — its ELEMENT, so
    // `params xs: T[]` infers `T` from an argument rather than from the array.
    public static func GetParamsInferenceTypeReference(paramsTypeRef: TypeReference): TypeReference {
        array := paramsTypeRef as ArrayTypeReference
        if array != null {
            return array.ElementType
        }

        generic := paramsTypeRef as GenericTypeReference
        if generic != null && generic.TypeArguments.Count == 1 {
            return generic.TypeArguments[0]
        }

        return paramsTypeRef
    }

    // A `ref`/`out` source parameter's type is a by-ref type. Idempotent: a signature that already
    // carries the shell is left alone.
    public static func ApplySyntheticParameterModifier(
        functionType: FunctionTypeInfo,
        parameterIndex: int,
        parameterType: TypeInfo): TypeInfo {
        modifiers := functionType.ParameterModifiers
        if modifiers == null || parameterIndex < 0 || parameterIndex >= modifiers.Count {
            return parameterType
        }

        modifier := modifiers[parameterIndex]
        if modifier != ParameterModifier.Ref && modifier != ParameterModifier.Out {
            return parameterType
        }

        alreadyByRef := parameterType as ByRefTypeInfo
        if alreadyByRef != null {
            return parameterType
        }

        return new ByRefTypeInfo(parameterType)
    }

    // Whether a generic name written in a parameter denotes the same type as one read from metadata,
    // when exactly one of the two is namespace-qualified.
    public static func GenericNamesMatch(refName: string, infoName: string): bool {
        if refName == infoName {
            return true
        }

        if infoName.Contains(".") {
            return infoName.EndsWith("." + refName)
        }

        if refName.Contains(".") {
            return refName.EndsWith("." + infoName)
        }

        return false
    }

    // ------------------------------------------------------------------
    // The signature renderers NL402 reads.
    // ------------------------------------------------------------------

    // A reflected candidate's signature. A receiver-style extension call drops the receiver
    // parameter, so the rendered signature is the one the user actually wrote the call against.
    public static func FormatReflectionMethodSignature(method: MethodInfo, call: CallExpression): string {
        parameters := method.GetParameters()
        startIndex := 0
        if IsExtensionMethodCall(method, call) {
            startIndex = 1
        }

        builder := new StringBuilder()
        builder.Append(method.get_Name())
        builder.Append("(")
        index := startIndex
        while index < parameters.Length {
            if index > startIndex {
                builder.Append(", ")
            }

            builder.Append(NullabilityMetadataReflection.FormatParameter(parameters[index]))
            index = index + 1
        }

        builder.Append("): ")
        builder.Append(NullabilityMetadataReflection.FormatReturnType(method))
        return builder.ToString()
    }

    // A source candidate's signature, as the NL402 fix hint renders it. The receiver offset is
    // clamped rather than trusted, so a malformed offset renders the whole signature instead of
    // indexing out of it.
    public static func FormatSyntheticFunctionSignature(
        functionType: FunctionTypeInfo,
        functionName: string,
        parameterStartIndex: int): string {
        parameterCount := 0
        parameterTypes := functionType.ParameterTypes
        if parameterTypes != null {
            parameterCount = parameterTypes.Count
        }

        clampedStart := parameterStartIndex
        if clampedStart < 0 {
            clampedStart = 0
        }

        if clampedStart > parameterCount {
            clampedStart = parameterCount
        }

        builder := new StringBuilder()
        builder.Append(functionName)

        typeParameters := functionType.TypeParameters
        if typeParameters != null && typeParameters.Count > 0 {
            builder.Append("<")
            typeParameterIndex := 0
            while typeParameterIndex < typeParameters.Count {
                if typeParameterIndex > 0 {
                    builder.Append(", ")
                }

                builder.Append(typeParameters[typeParameterIndex].Name)
                typeParameterIndex = typeParameterIndex + 1
            }

            builder.Append(">")
        }

        builder.Append("(")
        index := clampedStart
        while index < parameterCount {
            if index > clampedStart {
                builder.Append(", ")
            }

            builder.Append(FormatSyntheticParameterSignature(functionType, index))
            index = index + 1
        }

        builder.Append(")")

        returnType := functionType.ReturnType
        if returnType != null {
            returnTypeObject := returnType as object
            builder.Append(": ")
            builder.Append(returnTypeObject.ToString())
        }

        return builder.ToString()
    }

    // One rendered parameter. The SOURCE type reference is preferred over the resolved `TypeInfo`, so
    // the hint echoes what the user wrote; a parameter past the required count renders ` = ...`
    // unless it is the params tail, which has no default.
    public static func FormatSyntheticParameterSignature(functionType: FunctionTypeInfo, index: int): string {
        name := "arg" + (index + 1).ToString()
        names := functionType.ParameterNames
        if names != null && index < names.Count {
            declaredName := names[index]
            if declaredName != null {
                name = declaredName
            }
        }

        typeName := "unknown"
        sourceTypes := functionType.SourceParameterTypes
        resolvedTypes := functionType.ParameterTypes
        if sourceTypes != null && index < sourceTypes.Count {
            typeName = TypeReferenceFacts.GetDisplayName(sourceTypes[index])
        } else {
            if resolvedTypes != null && index < resolvedTypes.Count {
                resolvedTypeObject := resolvedTypes[index] as object
                typeName = resolvedTypeObject.ToString()
            }
        }

        modifiers := functionType.ParameterModifiers
        modifierText := ""
        if modifiers != null && index < modifiers.Count {
            modifier := modifiers[index]
            if modifier == ParameterModifier.Ref {
                modifierText = "ref "
            }

            if modifier == ParameterModifier.Out {
                modifierText = "out "
            }

            if modifier == ParameterModifier.Params {
                modifierText = "params "
            }
        }

        requiredCount := 0
        if resolvedTypes != null {
            requiredCount = resolvedTypes.Count
        }

        declaredRequiredCount: int? = functionType.RequiredParameterCount
        if declaredRequiredCount.HasValue {
            requiredCount = declaredRequiredCount.Value
        }

        defaultValue := ""
        if index >= requiredCount && modifiers != null {
            if index >= modifiers.Count || modifiers[index] != ParameterModifier.Params {
                defaultValue = " = ..."
            }
        }

        return modifierText + name + ": " + typeName + defaultValue
    }
}

// The half of the scoring kernel that needs the analyzer's own collaborators — the declaration
// context (for alias resolution), the CLR conversion funnel, the assignability SCC, the well-known
// type bag and the type resolver. All five are already N#.
//
// This owner is REBUILT wherever the well-known-type bag is built or torn down, because two of its
// collaborators are: an owner's fields never change after construction.
public class AnalyzerOverloadScoring {

    declarationContext: AnalyzerDeclarationContext
    clrTypeConversion: AnalyzerClrTypeConversion
    assignability: AnalyzerAssignability
    typeResolver: AnalyzerTypeResolver
    wellKnownTypes: AnalyzerWellKnownTypes?

    constructor(
        context: AnalyzerDeclarationContext,
        conversion: AnalyzerClrTypeConversion,
        assignabilityOwner: AnalyzerAssignability,
        resolver: AnalyzerTypeResolver,
        wellKnown: AnalyzerWellKnownTypes?) {
        declarationContext = context
        clrTypeConversion = conversion
        assignability = assignabilityOwner
        typeResolver = resolver
        wellKnownTypes = wellKnown
    }

    // The source score ladder — the same 8/6/4/2 shape as the reflection one, over `TypeInfo`.
    //
    // TWO identity rules answer 8, and the second is load-bearing. Declared aliases resolve first, so
    // `type Meters = int` scores against `int`. Then reference identity. Then the CROSS-REPRESENTATION
    // rule: two `TypeInfo`s that convert to the SAME CLR type are identical even when one came from
    // source and the other from metadata, which is what stops `int` losing to `System.Int32`.
    public func GetNSharpMatchScore(parameterType: TypeInfo, argumentType: TypeInfo): int {
        resolvedParam := declarationContext.ResolveDeclaredAlias(parameterType)
        resolvedArg := declarationContext.ResolveDeclaredAlias(argumentType)

        if Object.ReferenceEquals(resolvedParam, resolvedArg) {
            return 8
        }

        paramClr := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedParam)
        argClr := clrTypeConversion.TryConvertTypeInfoToClrType(resolvedArg)
        if paramClr != null && argClr != null && paramClr == argClr {
            return 8
        }

        if AnalyzerConversionFacts.IsImplicitNumericConversion(resolvedArg, resolvedParam) {
            return 6
        }

        if assignability.IsAssignable(resolvedParam, resolvedArg) {
            return 4
        }

        return 2
    }

    // The final per-argument check a bound reflection call makes, with ONE relaxation over plain
    // assignability: a nullable REFERENCE-typed argument may satisfy a parameter its inner type
    // satisfies. Nullable value types are excluded — unwrapping one is a real conversion, not an
    // annotation.
    public func IsAssignableReflectionArgument(expectedType: TypeInfo, argumentType: TypeInfo): bool {
        if assignability.IsAssignable(expectedType, argumentType) {
            return true
        }

        resolvedArgument := declarationContext.ResolveDeclaredAlias(argumentType)
        nullableArgument := resolvedArgument as NullableTypeInfo
        if nullableArgument == null {
            return false
        }

        if !AnalyzerConversionFacts.IsReferenceType(declarationContext.ResolveDeclaredAlias(nullableArgument.InnerType)) {
            return false
        }

        return assignability.IsAssignable(expectedType, nullableArgument.InnerType)
    }

    // A source params parameter's element type: an array's element, or a single-argument generic's
    // argument (which is how `params xs: ReadOnlySpan<T>` answers). Null means the parameter is not a
    // sequence at all, and the caller treats the call as unexpandable.
    public func GetNSharpParamsElementType(paramsType: TypeInfo): TypeInfo? {
        resolved := declarationContext.ResolveDeclaredAlias(paramsType)

        array := resolved as ArrayTypeInfo
        if array != null {
            return array.ElementType
        }

        generic := resolved as GenericTypeInfo
        if generic != null && generic.TypeArguments.Count == 1 {
            return generic.TypeArguments[0]
        }

        return null
    }

    // Whether the caller passed the params ARRAY itself rather than a loose argument list: exactly one
    // trailing argument, not a spread, and assignable to the array type.
    public func IsSingleDirectNSharpParamsArrayArgument(
        regularParamCount: int,
        arguments: IReadOnlyList<Argument>,
        argTypes: IReadOnlyList<TypeInfo>,
        paramsArrayType: TypeInfo): bool {
        if argTypes.Count != regularParamCount + 1 {
            return false
        }

        spread := arguments[regularParamCount].Value as SpreadExpression
        if spread != null {
            return false
        }

        return assignability.IsAssignable(paramsArrayType, argTypes[regularParamCount])
    }

    // What generic inference should read from a params ARGUMENT: a spread of an array contributes its
    // ELEMENT type, so `f(...xs)` infers the same `T` a loose list would.
    public func GetParamsInferenceArgumentType(argument: Argument, argumentType: TypeInfo): TypeInfo {
        spread := argument.Value as SpreadExpression
        if spread == null {
            return argumentType
        }

        resolved := declarationContext.ResolveDeclaredAlias(argumentType)
        array := resolved as ArrayTypeInfo
        if array == null {
            return argumentType
        }

        return declarationContext.ResolveDeclaredAlias(array.ElementType)
    }

    // `System.Delegate` / `System.MulticastDelegate` themselves — a parameter that accepts ANY
    // delegate rather than one shape. Without a well-known-type bag there are no metadata facts yet
    // and the answer is false.
    public func IsBroadDelegateType(clrType: Type): bool {
        if wellKnownTypes == null {
            return false
        }

        effectiveType := AnalyzerOverloadFacts.GetDelegateParameterTypeForLambdaTarget(clrType)
        if effectiveType == wellKnownTypes.Delegate {
            return true
        }

        fullName := effectiveType.get_FullName()
        if fullName == "System.Delegate" {
            return true
        }

        return fullName == "System.MulticastDelegate"
    }

    // A lambda may be matched against a BROAD delegate parameter only when it annotates every
    // parameter: there is no delegate shape to infer them from, so an un-annotated (or `var`)
    // parameter has no type at all.
    public func CanInferBroadDelegateLambda(
        openDelegateType: Type,
        clrBindings: Dictionary<Type, Type>,
        lambda: LambdaExpression): bool {
        if !IsBroadDelegateType(AnalyzerReflectionTypeConversion.ApplyReflectionBindings(openDelegateType, clrBindings)) {
            return false
        }

        index := 0
        while index < lambda.Parameters.Count {
            parameterTypeReference: TypeReference? = lambda.Parameters[index].Type
            if parameterTypeReference == null {
                return false
            }

            simple := parameterTypeReference as SimpleTypeReference
            if simple != null && simple.Name == "var" {
                return false
            }

            index = index + 1
        }

        return true
    }

    // The signature such a lambda contributes: its own annotated parameters, no modifiers, and NO
    // return type — the delegate is broad, so nothing constrains the result.
    public func CreateBroadDelegateSignatureForLambda(
        openDelegateType: Type,
        clrBindings: Dictionary<Type, Type>,
        lambda: LambdaExpression): FunctionTypeInfo? {
        if !CanInferBroadDelegateLambda(openDelegateType, clrBindings, lambda) {
            return null
        }

        parameterTypes := new List<TypeInfo>()
        parameterModifiers := new List<ParameterModifier>()
        index := 0
        while index < lambda.Parameters.Count {
            parameterTypes.Add(typeResolver.ResolveType(lambda.Parameters[index].Type))
            parameterModifiers.Add(ParameterModifier.None)
            index = index + 1
        }

        signature := new FunctionTypeInfo()
        signature.ParameterTypes = parameterTypes
        signature.ParameterModifiers = parameterModifiers
        signature.ReturnType = null
        return signature
    }
}
