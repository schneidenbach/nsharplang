namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// ONE ARGUMENT FAILED TO REACH A PARAMETER, OR ONE PARAMETER NEVER RECEIVED AN ARGUMENT.
//
// The source binder's placement walk is the ONE authority on which argument fills which parameter
// position, and it is the authority on why a placement failed too — the message below is written
// here, not by the reporting arm that renders it. The arm supplies only the diagnostic SPAN, which
// is read off the analyzer's source text and cannot be answered without it.
//
// `ArgumentIndex >= 0` is the discriminator: a failure ABOUT a written argument anchors on that
// argument, and a failure about a MISSING argument anchors on the call and names the parameter it
// wanted. The failures are appended in walk order, so replaying them in order reproduces the
// interleaving the walk itself would have produced.
class SyntheticArgumentBindingFailure {
    argumentIndexValue: int
    parameterIndexValue: int
    messageValue: string

    ArgumentIndex: int => argumentIndexValue
    ParameterIndex: int => parameterIndexValue
    Message: string => messageValue

    constructor(argumentIndex: int, parameterIndex: int, message: string) {
        argumentIndexValue = argumentIndex
        parameterIndexValue = parameterIndex
        messageValue = message
    }
}

// THE PLACEMENT WALK'S ANSWER.
//
// `ParameterIndexByArgument` is the map every later pass reads: entry `i` is the parameter position
// argument `i` was placed at, or -1 when it was placed nowhere. It is produced even when the bind
// FAILED, because scoring, validation and the NL402 renderers all keep walking a partially placed
// call — a single unknown argument name must not blank out the other arguments' diagnostics.
class SyntheticArgumentBinding {
    successValue: bool
    parameterIndexByArgumentValue: int[]
    failuresValue: List<SyntheticArgumentBindingFailure>

    Success: bool => successValue
    ParameterIndexByArgument: int[] => parameterIndexByArgumentValue
    Failures: List<SyntheticArgumentBindingFailure> => failuresValue

    constructor(success: bool, parameterIndexByArgument: int[], failures: List<SyntheticArgumentBindingFailure>) {
        successValue = success
        parameterIndexByArgumentValue = parameterIndexByArgument
        failuresValue = failures
    }
}

// THE TWO TYPES A SINGLE ARGUMENT POSITION IS SCORED ON.
//
// `Matched` false means the candidate is out — the position could not be described at all. Matched
// with a null type on either side means the position carries no information and must be SKIPPED
// rather than scored, which is a different answer from "does not match": an unresolved params
// signature, or a spread of an unknown type, must not eliminate the candidate.
class SyntheticArgumentComparison {
    matchedValue: bool
    expectedTypeValue: TypeInfo?
    argumentTypeValue: TypeInfo?

    Matched: bool => matchedValue
    ExpectedType: TypeInfo? => expectedTypeValue
    ArgumentType: TypeInfo? => argumentTypeValue

    constructor(matched: bool, expectedType: TypeInfo?, argumentType: TypeInfo?) {
        matchedValue = matched
        expectedTypeValue = expectedType
        argumentTypeValue = argumentType
    }
}

// THE SOURCE BINDER'S ARGUMENT FILLER — the pure half.
//
// Where the reflection binder places arguments into `ParameterInfo[]` read from metadata, this
// places them into a `FunctionTypeInfo` built from an N# declaration, and the two worlds do NOT
// share a walk: the source world has NAMED arguments, a params tail identified by a MODIFIER rather
// than an attribute, optional parameters counted by `RequiredParameterCount`, and a RECEIVER offset
// that hides the first parameter from the argument list entirely.
//
// THE WALK IS TWO PHASES AND THE ORDER IS LOAD-BEARING. Phase one places every written argument:
// a NAMED argument goes to the parameter with that name (and only to a parameter at or after the
// receiver offset — a receiver may not be passed by name), and a POSITIONAL argument goes to the
// next parameter no name has already claimed, which is why the positional cursor SKIPS over
// already-bound positions instead of assuming a dense prefix. Overflow positional arguments fall
// into the params tail when there is one and are an error when there is not. Phase two checks that
// every REQUIRED parameter — from the receiver offset up to the required count — received
// something. Optional parameters are simply not checked; they are filled later, by the walk that
// converts.
//
// A FAILED PLACEMENT DOES NOT STOP THE WALK. Every failure arm continues to the next argument, so
// one call reports every one of its placement problems rather than only the first.
//
// This owner reports nothing and records nothing. Do not reintroduce any of it in C#.
class AnalyzerSyntheticCallFacts {

    // The name a diagnostic calls this call target: the declaration's own synthetic name when it has
    // one, else the name written at the call site, else the generic word. Stated once because six
    // members in the family need the same string and a disagreement between them would show up as
    // two different names for one call.
    static func ResolveSyntheticFunctionName(functionType: FunctionTypeInfo, call: CallExpression): string {
        syntheticName := functionType.SyntheticName
        if syntheticName != null {
            return syntheticName
        }

        targetName := GetCallTargetName(call)
        if targetName != null {
            return targetName
        }

        return "function"
    }

    // The name WRITTEN at the call site, if the callee is named at all. A call through an arbitrary
    // expression (an invoked local, an element of an array of delegates) has no written name.
    static func GetCallTargetName(call: CallExpression): string? {
        identifier := call.Callee as IdentifierExpression
        if identifier != null {
            return identifier.Name
        }

        memberAccess := call.Callee as MemberAccessExpression
        if memberAccess != null {
            return memberAccess.MemberName
        }

        return null
    }

    // Phase one and two of the placement walk. See the class comment: the answer is the
    // argument-to-parameter map plus the ordered failures, and the map is produced either way.
    static func BindFunctionArguments(functionType: FunctionTypeInfo, functionName: string, call: CallExpression, parameterStartIndex: int): SyntheticArgumentBinding {
        expectedCount := 0
        parameterTypes := functionType.ParameterTypes
        if parameterTypes != null {
            expectedCount = parameterTypes.Count
        }

        argumentCount := call.Arguments.Count
        parameterIndexByArgument := new int[](argumentCount)
        resetIndex := 0
        while resetIndex < argumentCount {
            parameterIndexByArgument[resetIndex] = -1
            resetIndex = resetIndex + 1
        }

        clampedStart := parameterStartIndex
        if clampedStart < 0 {
            clampedStart = 0
        }

        if clampedStart > expectedCount {
            clampedStart = expectedCount
        }

        failures := new List<SyntheticArgumentBindingFailure>()
        parameterNames := functionType.ParameterNames
        paramsParameterIndex := AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(functionType, expectedCount)
        boundArgumentIndexByParameter := new int[](expectedCount)
        clearIndex := 0
        while clearIndex < expectedCount {
            boundArgumentIndexByParameter[clearIndex] = -1
            clearIndex = clearIndex + 1
        }

        nextPositionalParameter := clampedStart
        success := true

        argumentIndex := 0
        while argumentIndex < argumentCount {
            argument := call.Arguments[argumentIndex]
            argumentName := argument.Name
            if argumentName != null {
                parameterIndex := FindParameterIndexByName(parameterNames, argumentName)
                if parameterIndex < clampedStart || parameterIndex >= expectedCount {
                    unknownMessage := "'" + functionName + "' has no parameter named '" + argumentName + "'"
                    failures.Add(new SyntheticArgumentBindingFailure(argumentIndex, -1, unknownMessage))
                    success = false
                    argumentIndex = argumentIndex + 1
                    continue
                }

                if boundArgumentIndexByParameter[parameterIndex] >= 0 {
                    duplicateMessage := "'" + functionName + "' got multiple values for parameter '" + argumentName + "'"
                    failures.Add(new SyntheticArgumentBindingFailure(argumentIndex, -1, duplicateMessage))
                    success = false
                    argumentIndex = argumentIndex + 1
                    continue
                }

                boundArgumentIndexByParameter[parameterIndex] = argumentIndex
                parameterIndexByArgument[argumentIndex] = parameterIndex
                argumentIndex = argumentIndex + 1
                continue
            }

            while nextPositionalParameter < expectedCount && boundArgumentIndexByParameter[nextPositionalParameter] >= 0 {
                nextPositionalParameter = nextPositionalParameter + 1
            }

            if nextPositionalParameter >= expectedCount {
                if paramsParameterIndex >= 0 {
                    if boundArgumentIndexByParameter[paramsParameterIndex] < 0 {
                        boundArgumentIndexByParameter[paramsParameterIndex] = argumentIndex
                    }

                    parameterIndexByArgument[argumentIndex] = paramsParameterIndex
                    argumentIndex = argumentIndex + 1
                    continue
                }

                overflowMessage := "'" + functionName + "' got more positional arguments than its signature accepts"
                failures.Add(new SyntheticArgumentBindingFailure(argumentIndex, -1, overflowMessage))
                success = false
                argumentIndex = argumentIndex + 1
                continue
            }

            boundArgumentIndexByParameter[nextPositionalParameter] = argumentIndex
            parameterIndexByArgument[argumentIndex] = nextPositionalParameter
            nextPositionalParameter = nextPositionalParameter + 1
            argumentIndex = argumentIndex + 1
        }

        requiredCount := AnalyzerOverloadFacts.GetSyntheticRequiredParameterCount(functionType, expectedCount)
        missingIndex := clampedStart
        while missingIndex < requiredCount {
            if boundArgumentIndexByParameter[missingIndex] < 0 {
                parameterName := MissingParameterName(functionType, missingIndex)
                missingMessage := "'" + functionName + "' needs an argument for parameter '" + parameterName + "'"
                failures.Add(new SyntheticArgumentBindingFailure(-1, missingIndex, missingMessage))
                success = false
            }

            missingIndex = missingIndex + 1
        }

        return new SyntheticArgumentBinding(success, parameterIndexByArgument, failures)
    }

    // A named argument names a PARAMETER, and a signature with no recorded names admits none.
    static func FindParameterIndexByName(parameterNames: List<string>?, argumentName: string): int {
        if parameterNames == null {
            return -1
        }

        index := 0
        while index < parameterNames.Count {
            if parameterNames[index] == argumentName {
                return index
            }

            index = index + 1
        }

        return -1
    }

    // A signature that carries no name for the position still has to be able to name it, so the
    // ONE-BASED positional spelling is the fallback.
    static func MissingParameterName(functionType: FunctionTypeInfo, parameterIndex: int): string {
        parameterNames := functionType.ParameterNames
        if parameterNames != null && parameterIndex >= 0 && parameterIndex < parameterNames.Count {
            return parameterNames[parameterIndex]
        }

        ordinal := parameterIndex + 1
        return "arg" + ordinal.ToString()
    }

    // THE SPECIFICITY TIE-BREAK'S COST FUNCTION: how many of this call's arguments were placed at a
    // parameter written as a BARE type-parameter name. An overload that matched by BINDING a type
    // parameter is less specific than one that matched a written type, so the LOWER cost wins.
    //
    // The params tail is read through its ELEMENT reference, so `params xs: T[]` costs one per
    // element argument exactly as a plain `x: T` costs one — otherwise a params overload would look
    // artificially specific.
    //
    // A signature whose arguments do not even PLACE has no meaningful cost and answers zero: the
    // tie-break only ever runs between two candidates that already scored equally.
    static func GetGenericParameterCost(functionType: FunctionTypeInfo, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>): int {
        typeParameters := functionType.TypeParameters
        sourceParameterTypes := functionType.SourceParameterTypes
        if typeParameters == null || typeParameters.Count == 0 {
            return 0
        }

        if sourceParameterTypes == null || sourceParameterTypes.Count == 0 {
            return 0
        }

        parameterStartIndex := AnalyzerOverloadFacts.GetSyntheticParameterStartIndex(functionType, call)
        functionName := ResolveSyntheticFunctionName(functionType, call)
        binding := BindFunctionArguments(functionType, functionName, call, parameterStartIndex)
        if !binding.Success {
            return 0
        }

        paramsParameterIndex := AnalyzerOverloadFacts.GetSyntheticParamsParameterIndex(functionType, sourceParameterTypes.Count)
        parameterIndexByArgument := binding.ParameterIndexByArgument
        cost := 0
        argumentIndex := 0
        while argumentIndex < argTypes.Count && argumentIndex < parameterIndexByArgument.Length {
            parameterIndex := parameterIndexByArgument[argumentIndex]
            if parameterIndex >= 0 && parameterIndex < sourceParameterTypes.Count {
                sourceParameterType := sourceParameterTypes[parameterIndex]
                if paramsParameterIndex >= 0 && parameterIndex == paramsParameterIndex {
                    sourceParameterType = AnalyzerOverloadFacts.GetParamsInferenceTypeReference(sourceParameterType)
                }

                if AnalyzerOverloadFacts.IsDirectFunctionTypeParameterReference(sourceParameterType, typeParameters) {
                    cost = cost + 1
                }
            }

            argumentIndex = argumentIndex + 1
        }

        return cost
    }

    // CLOSES an inferred signature. A type parameter reaches the analyzer as a bare NAME — an
    // `ExternalTypeInfo` or a `SimpleTypeInfo` whose name is the parameter's — so substitution is a
    // name lookup at the leaves and a rebuild through every composite shell above them. An unbound
    // name is left alone rather than replaced with a hole: partial inference must still describe the
    // parameters it did close.
    static func ApplyGenericBindings(candidate: TypeInfo, bindings: Dictionary<string, TypeInfo>?): TypeInfo {
        if bindings == null || bindings.Count == 0 {
            return candidate
        }

        bound: TypeInfo = BuiltInTypes.Object
        external := candidate as ExternalTypeInfo
        if external != null && bindings.TryGetValue(external.Name, out bound) {
            return bound
        }

        simple := candidate as SimpleTypeInfo
        if simple != null && bindings.TryGetValue(simple.Name, out bound) {
            return bound
        }

        generic := candidate as GenericTypeInfo
        if generic != null {
            substituted := new List<TypeInfo>()
            index := 0
            while index < generic.TypeArguments.Count {
                argument := generic.TypeArguments[index]
                substituted.Add(ApplyGenericBindings(argument, bindings))
                index = index + 1
            }

            return new GenericTypeInfo(generic.Name, substituted, generic.GenericDefinition)
        }

        array := candidate as ArrayTypeInfo
        if array != null {
            elementType := ApplyGenericBindings(array.ElementType, bindings)
            return new ArrayTypeInfo(elementType)
        }

        nullable := candidate as NullableTypeInfo
        if nullable != null {
            innerType := ApplyGenericBindings(nullable.InnerType, bindings)
            return new NullableTypeInfo(innerType)
        }

        oblivious := candidate as ObliviousTypeInfo
        if oblivious != null {
            obliviousInner := ApplyGenericBindings(oblivious.InnerType, bindings)
            return new ObliviousTypeInfo(obliviousInner)
        }

        return candidate
    }

    // THE NUMERIC ARM OF THE LEAST UPPER BOUND: the WIDEST type in the fixed widening order
    // `byte < short < int < long < float < double < decimal`. A single non-numeric member answers
    // null for the whole list rather than a partial answer, because a numeric LUB over a mixed list
    // would silently drop the non-numeric constraint.
    //
    // Both spellings of every type are admitted — the source keyword and the CLR name — because one
    // bound may be written in source and another read from metadata for the same parameter.
    static func TryComputeNumericLub(types: List<TypeInfo>): TypeInfo? {
        maxIndex := -1
        index := 0
        while index < types.Count {
            typeObject := types[index] as object
            rendered := typeObject.ToString()
            if rendered == null {
                return null
            }

            order := NumericWideningIndex(rendered.ToLowerInvariant())
            if order < 0 {
                return null
            }

            if order > maxIndex {
                maxIndex = order
            }

            index = index + 1
        }

        if maxIndex < 0 {
            return null
        }

        return NumericTypeAtWideningIndex(maxIndex)
    }

    static func NumericWideningIndex(name: string): int {
        if name == "byte" || name == "system.byte" {
            return 0
        }

        if name == "short" || name == "system.int16" {
            return 1
        }

        if name == "int" || name == "system.int32" {
            return 2
        }

        if name == "long" || name == "system.int64" {
            return 3
        }

        if name == "float" || name == "system.single" {
            return 4
        }

        if name == "double" || name == "system.double" {
            return 5
        }

        if name == "decimal" || name == "system.decimal" {
            return 6
        }

        return -1
    }

    static func NumericTypeAtWideningIndex(order: int): TypeInfo? {
        if order == 0 {
            return BuiltInTypes.Byte
        }

        if order == 1 {
            return BuiltInTypes.Short
        }

        if order == 2 {
            return BuiltInTypes.Int
        }

        if order == 3 {
            return BuiltInTypes.Long
        }

        if order == 4 {
            return BuiltInTypes.Float
        }

        if order == 5 {
            return BuiltInTypes.Double
        }

        if order == 6 {
            return BuiltInTypes.Decimal
        }

        return null
    }
}

// THE SOURCE BINDER'S COLLABORATOR-BACKED HALF.
//
// Four owners are needed and no more: the declaration context (declared aliases must be resolved
// before two types are compared, or `type Id = int` loses to `int`), the scoring kernel (the params
// direct-vs-expanded rule and the spread's inference type), the assignability SCC (the least upper
// bound's "one candidate accepts them all" test) and the CLR conversion funnel (an argument that
// arrives as an `ExternalTypeInfo` has to be reopened as a CLR type before its type arguments can be
// matched). All four are rebuilt when the well-known-type bag changes, so this owner is too, and its
// fields never change after construction.
class AnalyzerSyntheticCallBinder {
    declarationContext: AnalyzerDeclarationContext
    overloadScoring: AnalyzerOverloadScoring
    assignability: AnalyzerAssignability
    clrTypeConversion: AnalyzerClrTypeConversion

    constructor(context: AnalyzerDeclarationContext, scoring: AnalyzerOverloadScoring, assignabilityOwner: AnalyzerAssignability, conversion: AnalyzerClrTypeConversion) {
        declarationContext = context
        overloadScoring = scoring
        assignability = assignabilityOwner
        clrTypeConversion = conversion
    }

    // THE TWO TYPES ONE ARGUMENT POSITION IS SCORED ON, and the three-way answer the scorer needs.
    //
    // An ordinary position is the placed parameter's type (closed by whatever inference produced)
    // against the argument's, both alias-resolved. The PARAMS position is where the shapes diverge
    // and all three arms are load-bearing:
    //   * A single argument that is ALREADY the params array — `f(xs)` where `xs: int[]` — is
    //     compared as the ARRAY, because it is passed straight through.
    //   * A SPREAD compares ELEMENT to ELEMENT when the spread source is an array, and carries no
    //     information at all when its type is unknown.
    //   * Anything else is an EXPANDED tail: the parameter contributes its element type and the
    //     argument stays whole.
    // A params parameter whose type is not an array at all describes nothing, so the position is
    // skipped rather than failed — a malformed signature must not eliminate a candidate that the
    // arity tables already admitted.
    func GetArgumentComparisonTypes(functionType: FunctionTypeInfo, call: CallExpression, argTypes: IReadOnlyList<TypeInfo>, argumentIndex: int, parameterIndex: int, paramsParameterIndex: int, parameterStartIndex: int, genericBindings: Dictionary<string, TypeInfo>?): SyntheticArgumentComparison {
        parameterTypes := functionType.ParameterTypes
        if parameterTypes == null || parameterIndex < 0 || parameterIndex >= parameterTypes.Count {
            return new SyntheticArgumentComparison(false, null, null)
        }

        boundParameterType := AnalyzerSyntheticCallFacts.ApplyGenericBindings(parameterTypes[parameterIndex], genericBindings)
        expectedType: TypeInfo? = declarationContext.ResolveDeclaredAlias(boundParameterType)
        argumentType: TypeInfo? = declarationContext.ResolveDeclaredAlias(argTypes[argumentIndex])
        if paramsParameterIndex < 0 || parameterIndex != paramsParameterIndex {
            return new SyntheticArgumentComparison(true, expectedType, argumentType)
        }

        boundParamsType := AnalyzerSyntheticCallFacts.ApplyGenericBindings(parameterTypes[paramsParameterIndex], genericBindings)
        paramsType := declarationContext.ResolveDeclaredAlias(boundParamsType)
        paramsArrayType := paramsType as ArrayTypeInfo
        if paramsArrayType == null {
            return new SyntheticArgumentComparison(true, null, null)
        }

        paramsArgumentIndex := paramsParameterIndex - parameterStartIndex
        isDirectParamsArrayArgument := overloadScoring.IsSingleDirectNSharpParamsArrayArgument(paramsArgumentIndex, call.Arguments, argTypes, paramsArrayType)
        if isDirectParamsArrayArgument {
            return new SyntheticArgumentComparison(true, expectedType, argumentType)
        }

        spread := call.Arguments[argumentIndex].Value as SpreadExpression
        if spread == null {
            elementExpected := declarationContext.ResolveDeclaredAlias(paramsArrayType.ElementType)
            return new SyntheticArgumentComparison(true, elementExpected, argumentType)
        }

        spreadArrayType := argumentType as ArrayTypeInfo
        if spreadArrayType != null {
            spreadExpected := declarationContext.ResolveDeclaredAlias(paramsArrayType.ElementType)
            spreadArgument := declarationContext.ResolveDeclaredAlias(spreadArrayType.ElementType)
            return new SyntheticArgumentComparison(true, spreadExpected, spreadArgument)
        }

        if argumentType != null && BuiltInTypes.IsUnknown(argumentType) {
            return new SyntheticArgumentComparison(true, null, null)
        }

        return new SyntheticArgumentComparison(true, expectedType, argumentType)
    }

    // THE BEST COMMON TYPE of everything one type parameter was constrained by. Four rules in order:
    // an empty list is `object`, one bound IS the answer, a bound that every other bound converts to
    // wins, and a numeric list widens. Nothing common leaves `object` — the conservative answer,
    // deliberately NOT a failure, because a call whose inference is imprecise should still be
    // checked against `object` rather than abandoned.
    func ComputeLeastUpperBound(types: List<TypeInfo>): TypeInfo {
        if types.Count == 0 {
            return BuiltInTypes.Object
        }

        if types.Count == 1 {
            return types[0]
        }

        first := types[0]
        if AllEqualTo(types, first) {
            return first
        }

        candidateIndex := 0
        while candidateIndex < types.Count {
            candidate := types[candidateIndex]
            if AllConvertibleTo(types, candidate) {
                return candidate
            }

            candidateIndex = candidateIndex + 1
        }

        numericLub := AnalyzerSyntheticCallFacts.TryComputeNumericLub(types)
        if numericLub != null {
            return numericLub
        }

        return BuiltInTypes.Object
    }

    static func AllEqualTo(types: List<TypeInfo>, candidate: TypeInfo): bool {
        index := 0
        while index < types.Count {
            if !TypeInfoIdentityFacts.AreEqual(types[index], candidate) {
                return false
            }

            index = index + 1
        }

        return true
    }

    func AllConvertibleTo(types: List<TypeInfo>, candidate: TypeInfo): bool {
        index := 0
        while index < types.Count {
            current := types[index]
            if !TypeInfoIdentityFacts.AreEqual(current, candidate) && !assignability.IsAssignable(candidate, current) {
                return false
            }

            index = index + 1
        }

        return true
    }

    // THE INFERENCE WALK, in its collecting form: every position a type parameter appears at
    // contributes a BOUND rather than binding the parameter outright, so a parameter mentioned twice
    // is resolved by the least upper bound of both sightings instead of by whichever position came
    // first.
    //
    // The walk descends structurally and every arm is a real shape the corpus produces: a bare name
    // BINDS; a generic reference descends pairwise against a source generic, against an
    // `ExternalTypeInfo` reopened as a CLR type, and against a `ReflectionTypeInfo` read from
    // metadata; an array descends into its element; a NULLABLE reference descends into a nullable
    // argument AND into a non-nullable one (`T?` matched against `T` still tells you `T`); a by-ref
    // shell is transparent; and a function reference descends into every parameter and the return,
    // which is how a lambda argument infers a type parameter.
    //
    // TWO ARGUMENT TYPES CARRY NO INFORMATION and are dropped at the top: `unknown`, because an
    // error-recovery type would bind a parameter to garbage, and `null`, because a null literal
    // constrains nothing.
    func CollectTypeParameterBounds(parameterTypeReference: TypeReference, argumentType: TypeInfo, typeParameters: List<TypeParameter>, allBounds: Dictionary<string, List<TypeInfo>>) {
        if BuiltInTypes.IsUnknown(argumentType) {
            return
        }

        if BuiltInTypes.Is(argumentType, BuiltInTypes.Null) {
            return
        }

        simple := parameterTypeReference as SimpleTypeReference
        if simple != null {
            index := 0
            while index < typeParameters.Count {
                if typeParameters[index].Name == simple.Name {
                    allBounds[simple.Name].Add(argumentType)
                    return
                }

                index = index + 1
            }

            return
        }

        generic := parameterTypeReference as GenericTypeReference
        if generic != null {
            CollectGenericTypeParameterBounds(generic, argumentType, typeParameters, allBounds)
            return
        }

        array := parameterTypeReference as ArrayTypeReference
        if array != null {
            argumentArray := argumentType as ArrayTypeInfo
            if argumentArray != null {
                CollectTypeParameterBounds(array.ElementType, argumentArray.ElementType, typeParameters, allBounds)
            }

            return
        }

        nullable := parameterTypeReference as NullableTypeReference
        if nullable != null {
            argumentNullable := argumentType as NullableTypeInfo
            if argumentNullable != null {
                CollectTypeParameterBounds(nullable.InnerType, argumentNullable.InnerType, typeParameters, allBounds)
            } else {
                CollectTypeParameterBounds(nullable.InnerType, argumentType, typeParameters, allBounds)
            }

            return
        }

        byRef := parameterTypeReference as ByRefTypeReference
        if byRef != null {
            innerArgumentType := argumentType
            argumentByRef := argumentType as ByRefTypeInfo
            if argumentByRef != null {
                innerArgumentType = argumentByRef.InnerType
            }

            CollectTypeParameterBounds(byRef.InnerType, innerArgumentType, typeParameters, allBounds)
            return
        }

        functionReference := parameterTypeReference as FunctionTypeReference
        if functionReference != null {
            CollectFunctionTypeParameterBounds(functionReference, argumentType, typeParameters, allBounds)
        }
    }

    // `List<T>` matched against a source `List<int>`, against an `ExternalTypeInfo` naming a generic
    // CLR type, and against a `ReflectionTypeInfo` wrapping one. The three arms exist because the
    // same argument can arrive in three representations depending on where its type came from, and
    // the head names are compared with the namespace-tolerant rule rather than by string equality.
    func CollectGenericTypeParameterBounds(generic: GenericTypeReference, argumentType: TypeInfo, typeParameters: List<TypeParameter>, allBounds: Dictionary<string, List<TypeInfo>>) {
        argumentGeneric := argumentType as GenericTypeInfo
        if argumentGeneric != null {
            if AnalyzerOverloadFacts.GenericNamesMatch(generic.Name, argumentGeneric.Name) && generic.TypeArguments.Count == argumentGeneric.TypeArguments.Count {
                index := 0
                while index < generic.TypeArguments.Count {
                    CollectTypeParameterBounds(generic.TypeArguments[index], argumentGeneric.TypeArguments[index], typeParameters, allBounds)
                    index = index + 1
                }
            }

            return
        }

        external := argumentType as ExternalTypeInfo
        if external != null {
            clrType := clrTypeConversion.TryConvertTypeInfoToClrType(external)
            if clrType != null && clrType.get_IsGenericType() {
                CollectClrTypeParameterBounds(generic, clrType, typeParameters, allBounds)
            }

            return
        }

        reflection := argumentType as ReflectionTypeInfo
        if reflection != null && reflection.Type.get_IsGenericType() {
            CollectClrTypeParameterBounds(generic, reflection.Type, typeParameters, allBounds)
        }
    }

    // The pairwise descent against a CLR type, shared by the external and reflection arms. The head
    // name comes off the CLR name's arity suffix.
    func CollectClrTypeParameterBounds(generic: GenericTypeReference, clrType: Type, typeParameters: List<TypeParameter>, allBounds: Dictionary<string, List<TypeInfo>>) {
        typeArguments := clrType.GetGenericArguments()
        if generic.TypeArguments.Count != typeArguments.Length {
            return
        }

        clrHeadName := clrType.Name
        tick := clrHeadName.IndexOf('`')
        if tick >= 0 {
            clrHeadName = clrHeadName.Substring(0, tick)
        }

        if !AnalyzerOverloadFacts.GenericNamesMatch(generic.Name, clrHeadName) {
            return
        }

        index := 0
        while index < generic.TypeArguments.Count {
            converted := AnalyzerReflectionTypeConversion.ConvertReflectionType(typeArguments[index])
            CollectTypeParameterBounds(generic.TypeArguments[index], converted, typeParameters, allBounds)
            index = index + 1
        }
    }

    // A `Func`/`Action` parameter against a lambda's inferred signature: every parameter position it
    // has in common, then the return. The shorter of the two lists governs, so an arity mismatch
    // contributes what it can rather than nothing.
    func CollectFunctionTypeParameterBounds(functionReference: FunctionTypeReference, argumentType: TypeInfo, typeParameters: List<TypeParameter>, allBounds: Dictionary<string, List<TypeInfo>>) {
        argumentFunction := argumentType as FunctionTypeInfo
        if argumentFunction == null {
            return
        }

        referenceParameters := functionReference.ParameterTypes
        argumentParameters := argumentFunction.ParameterTypes
        if argumentParameters != null {
            index := 0
            while index < referenceParameters.Count && index < argumentParameters.Count {
                CollectTypeParameterBounds(referenceParameters[index], argumentParameters[index], typeParameters, allBounds)
                index = index + 1
            }
        }

        argumentReturn := argumentFunction.ReturnType
        if argumentReturn != null {
            CollectTypeParameterBounds(functionReference.ReturnType, argumentReturn, typeParameters, allBounds)
        }
    }
}

// THE SOURCE BINDER'S REPORTING ARM, WHOLE.
//
// Slice 15 took the placement WALK and everything it decides — the failure kinds, their order, the
// `argN` fallback name and all four messages — but had to leave the arm that RENDERS them in C#,
// because the only thing the arm added was the diagnostic SPAN and the span resolver was still C#.
// It is not, any more. So the arm moves here whole: the walk produces an ordered failure list, this
// replays it in walk order through the sink, and the span each report anchors on comes from the
// span resolver. Nothing in the round trip is C# now.
//
// `reportErrors: false` is not a mode, it is a QUESTION — several passes (scoring, the generic
// constraint span, the SoA validator) ask "would this bind?" without wanting the answer written
// down. The map comes back either way, because a partially placed call still has diagnostics to
// give about the arguments that DID land.
class AnalyzerSyntheticCallReporter {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans) {
        diagnosticsValue = diagnostics
        spansValue = spans
    }

    func TryBindAndReport(functionType: FunctionTypeInfo, functionName: string, call: CallExpression, out parameterIndexByArgument: int[], parameterStartIndex: int, reportErrors: bool): bool {
        binding := AnalyzerSyntheticCallFacts.BindFunctionArguments(functionType, functionName, call, parameterStartIndex)
        parameterIndexByArgument = binding.ParameterIndexByArgument
        if !reportErrors {
            return binding.Success
        }

        index := 0
        while index < binding.Failures.Count {
            failure := binding.Failures[index]
            if failure.ArgumentIndex >= 0 {
                ReportArgumentBindingError(functionType, functionName, call.Arguments[failure.ArgumentIndex], failure.Message, parameterStartIndex)
            } else {
                ReportMissingArgumentBindingError(functionType, functionName, call, failure.Message, parameterStartIndex)
            }

            index = index + 1
        }

        return binding.Success
    }

    // A parameter that never received an argument anchors on the CALL, because there is no written
    // argument to point at.
    func ReportMissingArgumentBindingError(functionType: FunctionTypeInfo, functionName: string, call: CallExpression, message: string, parameterStartIndex: int) {
        span := spansValue.GetCallDiagnosticSpan(call, functionName)
        signature := AnalyzerOverloadFacts.FormatSyntheticFunctionSignature(functionType, functionName, parameterStartIndex)
        diagnosticsValue.Report(ErrorCode.NoMatchingOverload, message, span.Line, span.Column, "Use " + signature + ".", span.Length)
    }

    // A written argument that reached no parameter anchors on that ARGUMENT.
    func ReportArgumentBindingError(functionType: FunctionTypeInfo, functionName: string, argument: Argument, message: string, parameterStartIndex: int) {
        span := spansValue.GetExpressionDiagnosticSpan(argument.Value)
        signature := AnalyzerOverloadFacts.FormatSyntheticFunctionSignature(functionType, functionName, parameterStartIndex)
        diagnosticsValue.Report(ErrorCode.NoMatchingOverload, message, span.Line, span.Column, "Use " + signature + ", or remove the argument name.", span.Length)
    }
}
