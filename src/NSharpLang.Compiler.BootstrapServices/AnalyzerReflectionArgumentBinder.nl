namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast

// THE REFLECTION BINDER'S ARGUMENT MODEL.
//
// A reflected candidate is bound in TWO passes and this is the value that carries the first pass's
// answer into the second. `TryBindReflectionArguments` decides WHICH argument (or default, or
// params tail) each parameter position takes and scores the candidate; the analyzer's finalising
// walk later re-reads exactly the same decisions to convert, validate and report. The two passes
// must agree, so the decisions are recorded rather than recomputed.
//
// THE OPEN PARAMETER TYPE IS THE FIELD THAT MATTERS. Every bound argument records the type it was
// matched AGAINST, with the by-ref shell already stripped, and for an EXPANDED params tail that is
// the ELEMENT type rather than the declared array. That difference is the only evidence a later
// pass has that the tail was expanded (`AnalyzerOverloadFacts.IsExpandedReflectionParamsArgument`
// asks exactly this question), which is why the field is on the base rather than on one arm.
public class ReflectionBoundArgument {

    parameterIndexValue: int
    openParameterTypeValue: Type

    ParameterIndex: int => parameterIndexValue
    OpenParameterType: Type => openParameterTypeValue

    constructor(parameterIndex: int, openParameterType: Type) {
        parameterIndexValue = parameterIndex
        openParameterTypeValue = openParameterType
    }
}

// A position filled by a written argument. `ArgumentIndex` indexes the CALL's argument list, not
// the parameter list — named arguments and an expanded params tail both break that correspondence.
public class SuppliedReflectionBoundArgument: ReflectionBoundArgument {

    argumentValue: Argument
    argumentIndexValue: int

    Argument: Argument => argumentValue
    ArgumentIndex: int => argumentIndexValue

    constructor(
        parameterIndex: int,
        openParameterType: Type,
        argument: Argument,
        argumentIndex: int): base(parameterIndex, openParameterType) {
        argumentValue = argument
        argumentIndexValue = argumentIndex
    }
}

// A position filled by the declaration's own default. The `ParameterInfo` is kept because the
// default's TYPE is read from the parameter, not from any argument.
public class DefaultReflectionBoundArgument: ReflectionBoundArgument {

    parameterValue: ParameterInfo

    Parameter: ParameterInfo => parameterValue

    constructor(
        parameterIndex: int,
        openParameterType: Type,
        parameter: ParameterInfo): base(parameterIndex, openParameterType) {
        parameterValue = parameter
    }
}

// An EXPANDED params tail: one parameter position, zero or more arguments. The elements are
// MATERIALIZED here, each already carrying the element type as its own open parameter type, so
// every later pass reads one shape instead of re-expanding the tail itself.
public class ParamsReflectionBoundArgument: ReflectionBoundArgument {

    openElementTypeValue: Type
    argumentsValue: List<SuppliedReflectionBoundArgument>

    OpenElementType: Type => openElementTypeValue
    Arguments: List<SuppliedReflectionBoundArgument> => argumentsValue

    constructor(
        parameterIndex: int,
        openParameterType: Type,
        openElementType: Type,
        arguments: List<SuppliedReflectionBoundArgument>): base(parameterIndex, openParameterType) {
        openElementTypeValue = openElementType
        argumentsValue = arguments
    }
}

// THE REFLECTION BINDER'S PURE INTERIOR.
//
// This owner answers the question "does this reflected candidate accept this call, and how well?"
// and NOTHING ELSE. It reports no diagnostic and records nothing in the semantic model: a candidate
// either binds with a score or does not bind, and the analyzer's reporting walk decides what to say
// about a call for which no candidate bound.
//
// THE BINDING WALK IS THREE ORDERED PHASES and they cannot be merged. First every written argument
// is PLACED — named arguments by name (a name that does not match, or that lands on a position
// already taken, fails the candidate outright), then positionals into the next free non-params
// position, then the remainder into the params tail. Only then are unfilled positions FILLED from
// their declared defaults, because a named argument may legally fill a position after one that
// defaults. Only then is each placement SCORED, because scoring binds generic parameters and the
// bindings accumulated by an earlier position must be visible to a later one.
//
// THE BINDINGS DICTIONARIES ARE THE INFERENCE, NOT A CACHE. `bindings` maps a method's open type
// parameters to CLR types and `typeInfoBindings` maps them to N# `TypeInfo`s; both accumulate as
// the walk proceeds, and both are the caller's — a failed candidate leaves them dirty, which is why
// the analyzer hands each candidate its own pair.
//
// THE PARAMS TAIL IS TWO DIFFERENT BINDINGS. A single trailing argument that already IS the array
// (or a compatible sequence) is passed DIRECTLY and binds as an ordinary supplied argument against
// the array type; anything else EXPANDS, and each element binds against the element type. The
// choice is `ShouldPassReflectionParamsArgumentDirectly`, and it deliberately answers on a TRIAL
// copy of the bindings so a rejected direct pass leaves no inference behind.
//
// A METHOD GROUP IS NOT AN ARGUMENT TYPE. When a parameter is a delegate, a source function or
// method group argument is resolved to ONE overload here, ambiguity is a non-binding, and the
// selection is recorded for the finalising walk — the analyzer cannot re-derive it, because the
// choice depended on the delegate's bound signature.
//
// Do not reintroduce any of this in C#.
public class AnalyzerReflectionArgumentBinder {

    clrTypeConversion: AnalyzerClrTypeConversion
    assignability: AnalyzerAssignability
    assignabilityFacts: AnalyzerAssignabilityFacts
    overloadScoring: AnalyzerOverloadScoring

    constructor(
        conversion: AnalyzerClrTypeConversion,
        assignabilityOwner: AnalyzerAssignability,
        facts: AnalyzerAssignabilityFacts,
        scoring: AnalyzerOverloadScoring) {
        clrTypeConversion = conversion
        assignability = assignabilityOwner
        assignabilityFacts = facts
        overloadScoring = scoring
    }

    // Phase one and two: PLACE every written argument, then FILL the rest from defaults. Phase
    // three scores. A false answer means this candidate does not accept this call at all.
    public func TryBindReflectionArguments(
        parameters: ParameterInfo[],
        parameterOffset: int,
        call: CallExpression,
        bindings: Dictionary<Type, Type>,
        typeInfoBindings: Dictionary<Type, TypeInfo>,
        methodGroupArguments: Dictionary<int, FunctionTypeInfo>,
        analyzedNonLambdaArguments: TypeInfo?[],
        out boundArguments: List<ReflectionBoundArgument>,
        out score: int,
        out usesParams: bool,
        out defaultsUsed: int): bool {
        boundArguments = new List<ReflectionBoundArgument>()
        score = 0
        defaultsUsed = 0

        bound := new ReflectionBoundArgument?[](parameters.Length)
        usesParams = parameters.Length > parameterOffset
            && AnalyzerOverloadFacts.IsParamsParameter(parameters[parameters.Length - 1])
        paramsParameterIndex := -1
        if usesParams {
            paramsParameterIndex = parameters.Length - 1
        }

        nextPositionalParameter := parameterOffset
        paramsArguments := new List<Argument>()
        paramsArgumentIndexes := new List<int>()

        argumentIndex := 0
        while argumentIndex < call.Arguments.Count {
            argument := call.Arguments[argumentIndex]
            if argument.Name != null {
                namedIndex := FindNamedParameterIndex(
                    parameters, parameterOffset, argument.Name)
                if namedIndex < parameterOffset || namedIndex >= parameters.Length
                    || bound[namedIndex] != null {
                    return false
                }

                namedParameterType := parameters[namedIndex].get_ParameterType()
                namedOpenType := AnalyzerOverloadFacts.GetByRefElementType(namedParameterType)
                namedBinding: ReflectionBoundArgument? = new SuppliedReflectionBoundArgument(
                    namedIndex, namedOpenType, argument, argumentIndex)
                bound[namedIndex] = namedBinding
                argumentIndex = argumentIndex + 1
                continue
            }

            while nextPositionalParameter < parameters.Length
                && nextPositionalParameter != paramsParameterIndex
                && bound[nextPositionalParameter] != null {
                nextPositionalParameter = nextPositionalParameter + 1
            }

            if nextPositionalParameter < parameters.Length
                && nextPositionalParameter != paramsParameterIndex {
                positionalParameterType := parameters[nextPositionalParameter].get_ParameterType()
                positionalOpenType := AnalyzerOverloadFacts.GetByRefElementType(
                    positionalParameterType)
                positionalBinding: ReflectionBoundArgument? = new SuppliedReflectionBoundArgument(
                    nextPositionalParameter, positionalOpenType, argument, argumentIndex)
                bound[nextPositionalParameter] = positionalBinding
                nextPositionalParameter = nextPositionalParameter + 1
                argumentIndex = argumentIndex + 1
                continue
            }

            if !usesParams {
                return false
            }

            paramsArguments.Add(argument)
            paramsArgumentIndexes.Add(argumentIndex)
            argumentIndex = argumentIndex + 1
        }

        regularParameterEnd := parameters.Length
        if usesParams {
            regularParameterEnd = paramsParameterIndex
        }

        parameterIndex := parameterOffset
        while parameterIndex < regularParameterEnd {
            if bound[parameterIndex] == null {
                if !parameters[parameterIndex].get_IsOptional() {
                    return false
                }

                defaultParameter := parameters[parameterIndex]
                defaultParameterType := defaultParameter.get_ParameterType()
                defaultOpenType := AnalyzerOverloadFacts.GetByRefElementType(defaultParameterType)
                defaultBinding: ReflectionBoundArgument? = new DefaultReflectionBoundArgument(
                    parameterIndex, defaultOpenType, defaultParameter)
                bound[parameterIndex] = defaultBinding
                defaultsUsed = defaultsUsed + 1
            }

            parameterIndex = parameterIndex + 1
        }

        if usesParams {
            if bound[paramsParameterIndex] != null && paramsArguments.Count > 0 {
                return false
            }

            if bound[paramsParameterIndex] == null {
                declaredParamsType := parameters[paramsParameterIndex].get_ParameterType()
                paramsParameterType := AnalyzerOverloadFacts.GetByRefElementType(
                    declaredParamsType)
                elementType: Type = typeof(object)
                if !AnalyzerOverloadFacts.TryGetReflectionParamsElementType(
                        paramsParameterType, out elementType) {
                    return false
                }

                if paramsArguments.Count == 1
                    && ShouldPassReflectionParamsArgumentDirectly(
                        paramsArguments[0],
                        paramsArgumentIndexes[0],
                        paramsParameterType,
                        bindings,
                        analyzedNonLambdaArguments) {
                    directBinding: ReflectionBoundArgument? = new SuppliedReflectionBoundArgument(
                        paramsParameterIndex,
                        paramsParameterType,
                        paramsArguments[0],
                        paramsArgumentIndexes[0])
                    bound[paramsParameterIndex] = directBinding
                } else {
                    elements := new List<SuppliedReflectionBoundArgument>()
                    elementIndex := 0
                    while elementIndex < paramsArguments.Count {
                        element := new SuppliedReflectionBoundArgument(
                            paramsParameterIndex,
                            elementType,
                            paramsArguments[elementIndex],
                            paramsArgumentIndexes[elementIndex])
                        elements.Add(element)
                        elementIndex = elementIndex + 1
                    }

                    expandedBinding: ReflectionBoundArgument? = new ParamsReflectionBoundArgument(
                        paramsParameterIndex,
                        paramsParameterType,
                        elementType,
                        elements)
                    bound[paramsParameterIndex] = expandedBinding
                }
            }
        }

        materialized := new List<ReflectionBoundArgument>()
        scoredIndex := parameterOffset
        while scoredIndex < parameters.Length {
            boundArgument := bound[scoredIndex]
            if boundArgument != null {
                supplied := boundArgument as SuppliedReflectionBoundArgument
                paramsBound := boundArgument as ParamsReflectionBoundArgument
                if supplied != null {
                    suppliedScore := 0
                    if !TryScoreReflectionSuppliedArgument(
                            supplied,
                            parameters[supplied.ParameterIndex],
                            bindings,
                            typeInfoBindings,
                            methodGroupArguments,
                            analyzedNonLambdaArguments,
                            false,
                            out suppliedScore) {
                        return false
                    }

                    score = score + suppliedScore
                } else if paramsBound != null {
                    elements := paramsBound.Arguments
                    elementIndex := 0
                    while elementIndex < elements.Count {
                        elementScore := 0
                        if !TryScoreReflectionSuppliedArgument(
                                elements[elementIndex],
                                parameters[paramsBound.ParameterIndex],
                                bindings,
                                typeInfoBindings,
                                methodGroupArguments,
                                analyzedNonLambdaArguments,
                                true,
                                out elementScore) {
                            return false
                        }

                        score = score + elementScore
                        elementIndex = elementIndex + 1
                    }
                }

                materialized.Add(boundArgument)
            }

            scoredIndex = scoredIndex + 1
        }

        boundArguments = materialized
        return true
    }

    // The per-argument score, and the point at which generic inference actually happens.
    //
    // THE LADDER IS ORDERED BY HOW MUCH THE COMPILER HAD TO ASSUME. An explicit `default` scores 8
    // because it fits any parameter exactly. A lambda against a KNOWN delegate signature scores
    // 2 + arity, and against a broad `System.Delegate` only 1 + arity, so a concrete delegate
    // parameter always beats `Delegate` for the same lambda. A resolved method group scores 4 plus
    // its own signature match. A CLR-representable argument scores on the reflection ladder. An
    // argument that has no CLR form at all falls back to the assignability question and scores 1.
    //
    // BY-REF DIRECTION IS AN EQUALITY, NOT AN IMPLICATION: a `ref`/`out` argument for a by-value
    // parameter and a by-value argument for a by-ref parameter are BOTH non-bindings. A params
    // ELEMENT is exempt, because the element of a by-ref params array is not itself by-ref.
    public func TryScoreReflectionSuppliedArgument(
        supplied: SuppliedReflectionBoundArgument,
        parameter: ParameterInfo,
        bindings: Dictionary<Type, Type>,
        typeInfoBindings: Dictionary<Type, TypeInfo>,
        methodGroupArguments: Dictionary<int, FunctionTypeInfo>,
        analyzedNonLambdaArguments: TypeInfo?[],
        expectsParamsElement: bool,
        out score: int): bool {
        score = 0

        expectsByRef := !expectsParamsElement && parameter.get_ParameterType().get_IsByRef()
        argumentModifier := supplied.Argument.Modifier
        suppliedByRef := argumentModifier == ArgumentModifier.Ref
            || argumentModifier == ArgumentModifier.Out
        if expectsByRef != suppliedByRef {
            return false
        }

        openParameterType := supplied.OpenParameterType
        argumentValue := supplied.Argument.Value

        if argumentValue is DefaultExpression {
            score = 8
            return true
        }

        lambda := argumentValue as LambdaExpression
        if lambda != null {
            expectedSignature := CreateDelegateSignatureFromOpenType(
                openParameterType,
                typeInfoBindings,
                bindings)

            if expectedSignature == null || expectedSignature.ParameterTypes == null {
                if !overloadScoring.CanInferBroadDelegateLambda(
                        openParameterType, bindings, lambda) {
                    return false
                }

                score = 1 + lambda.Parameters.Count
                return true
            }

            expectedParameterTypes := expectedSignature.ParameterTypes
            if expectedParameterTypes == null
                || expectedParameterTypes.Count != lambda.Parameters.Count {
                return false
            }

            score = 2 + expectedParameterTypes.Count
            return true
        }

        argumentType := analyzedNonLambdaArguments[supplied.ArgumentIndex]
        if argumentType == null {
            return false
        }

        selectedMethodGroup: FunctionTypeInfo? = null
        methodGroupScore := 0
        if TryBindMethodGroupToReflectionDelegate(
                openParameterType,
                argumentType,
                bindings,
                out selectedMethodGroup,
                out methodGroupScore) {
            if selectedMethodGroup == null
                || !TryPopulateReflectionBindingsFromMethodGroupDelegate(
                    openParameterType,
                    selectedMethodGroup,
                    bindings,
                    typeInfoBindings) {
                return false
            }

            methodGroupArguments[supplied.ArgumentIndex] = selectedMethodGroup
            score = methodGroupScore
            return true
        }

        argumentClrType := clrTypeConversion.TryConvertTypeInfoToClrType(argumentType)
        if argumentClrType == null {
            argumentClrType = clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(argumentType)
        }

        if argumentClrType != null {
            if !AnalyzerOverloadFacts.TryMatchReflectionParameter(
                    openParameterType, argumentClrType, bindings) {
                return false
            }

            PopulateTypeInfoBindingsFromType(openParameterType, argumentType, typeInfoBindings)

            score = AnalyzerOverloadFacts.GetReflectionMatchScore(
                AnalyzerReflectionTypeConversion.ApplyReflectionBindings(
                    openParameterType, bindings),
                argumentClrType)
            return true
        }

        boundParameterType := AnalyzerReflectionTypeConversion.ApplyReflectionBindings(
            openParameterType, bindings)
        expectedType := AnalyzerReflectionTypeConversion.ConvertReflectionType(boundParameterType)
        if !assignability.IsAssignable(expectedType, argumentType) {
            return false
        }

        score = 1
        return true
    }

    // Whether ONE trailing argument is the params ARRAY itself rather than its first element.
    //
    // A SPREAD is never direct — spreading is the expansion — and a lambda never is, because a
    // lambda has no type until a delegate context exists. An explicit `default` always is: it
    // denotes the null array. Everything else is a type question, asked on a TRIAL COPY of the
    // bindings so that a refused direct pass leaves no generic inference behind for the expansion
    // that follows it.
    public func ShouldPassReflectionParamsArgumentDirectly(
        argument: Argument,
        argumentIndex: int,
        paramsParameterType: Type,
        bindings: Dictionary<Type, Type>,
        analyzedNonLambdaArguments: TypeInfo?[]): bool {
        argumentValue := argument.Value
        if argumentValue is SpreadExpression {
            return false
        }

        if argumentValue is DefaultExpression {
            return true
        }

        if argumentValue is LambdaExpression {
            return false
        }

        argumentType := analyzedNonLambdaArguments[argumentIndex]
        if argumentType == null || BuiltInTypes.IsUnknown(argumentType) {
            return false
        }

        argumentClrType := clrTypeConversion.TryConvertTypeInfoToClrType(argumentType)
        if argumentClrType == null {
            argumentClrType = clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(argumentType)
        }

        if argumentClrType != null {
            trialBindings := CopyBindings(bindings)
            return AnalyzerOverloadFacts.TryMatchReflectionParameter(
                paramsParameterType, argumentClrType, trialBindings)
        }

        expectedType := AnalyzerReflectionTypeConversion.ConvertReflectionType(
            AnalyzerReflectionTypeConversion.ApplyReflectionBindings(
                paramsParameterType, bindings))
        return assignability.IsAssignable(expectedType, argumentType)
    }

    // Resolving a source function or method group against a DELEGATE parameter.
    //
    // The parameter's bindings are applied first, so an unbound `Func<T, TResult>` is not a
    // delegate yet and no method group binds to it. A single function must carry SOURCE identity —
    // a reflected delegate value is not a method group — and a method group picks its BEST
    // overload, with a tie being a non-binding rather than an arbitrary choice. The +4 is the
    // method-group conversion itself, so a resolved group outranks a plain assignable argument.
    public func TryBindMethodGroupToReflectionDelegate(
        parameterType: Type,
        argumentType: TypeInfo,
        bindings: Dictionary<Type, Type>,
        out selectedMethodGroup: FunctionTypeInfo?,
        out score: int): bool {
        selectedMethodGroup = null
        score = 0

        delegateType := AnalyzerReflectionTypeConversion.ApplyReflectionBindings(
            parameterType, bindings)
        if !assignabilityFacts.IsDelegateType(delegateType) {
            return false
        }

        expectedSignature := AnalyzerFunctionTypeFactory.CreateFromRuntimeDelegate(delegateType)
        if expectedSignature.ParameterTypes == null {
            return false
        }

        functionType := argumentType as FunctionTypeInfo
        if functionType != null {
            candidateScore := 0
            if !TryGetMethodGroupMatchScore(functionType, expectedSignature, out candidateScore) {
                return false
            }

            selectedMethodGroup = functionType
            score = 4 + candidateScore
            return true
        }

        methodGroup := argumentType as NSharpMethodGroupInfo
        if methodGroup != null {
            bestScore := -1
            ambiguous := false
            bestFunctionType: FunctionTypeInfo? = null
            candidates := NSharpMethodGroupInfoFactory.GetFunctions(methodGroup)
            candidateIndex := 0
            while candidateIndex < candidates.Count {
                candidateType := candidates[candidateIndex]
                candidateScore := 0
                if TryGetMethodGroupMatchScore(
                        candidateType, expectedSignature, out candidateScore) {
                    scoreWithConversion := 4 + candidateScore
                    if scoreWithConversion > bestScore {
                        bestScore = scoreWithConversion
                        bestFunctionType = candidateType
                        ambiguous = false
                    } else if scoreWithConversion == bestScore {
                        ambiguous = true
                    }
                }

                candidateIndex = candidateIndex + 1
            }

            if bestFunctionType == null || bestScore < 0 || ambiguous {
                return false
            }

            selectedMethodGroup = bestFunctionType
            score = bestScore
            return true
        }

        return false
    }

    // A candidate binds to a delegate only when it is a SOURCE function; a reflected delegate value
    // has no method group to select from.
    func TryGetMethodGroupMatchScore(
        functionType: FunctionTypeInfo,
        expectedSignature: FunctionTypeInfo,
        out candidateScore: int): bool {
        candidateScore = 0
        if !AnalyzerCallableReferenceFacts.HasSourceFunctionIdentity(functionType) {
            return false
        }

        return assignability.TryGetRuntimeDelegateMethodGroupMatchScore(
            functionType, expectedSignature, out candidateScore)
    }

    // Every supplied argument the binding produced, with an expanded params tail flattened into its
    // elements. The elements were materialized when the tail was bound, so this is a read.
    public func EnumerateSuppliedReflectionArguments(
        boundArguments: List<ReflectionBoundArgument>): List<SuppliedReflectionBoundArgument> {
        flattened := new List<SuppliedReflectionBoundArgument>()
        index := 0
        while index < boundArguments.Count {
            boundArgument := boundArguments[index]
            supplied := boundArgument as SuppliedReflectionBoundArgument
            paramsBound := boundArgument as ParamsReflectionBoundArgument
            if supplied != null {
                flattened.Add(supplied)
            } else if paramsBound != null {
                elements := paramsBound.Arguments
                elementIndex := 0
                while elementIndex < elements.Count {
                    flattened.Add(elements[elementIndex])
                    elementIndex = elementIndex + 1
                }
            }

            index = index + 1
        }

        return flattened
    }

    // The signature a lambda must match, read off an OPEN delegate parameter.
    //
    // The CLR bindings are applied first so a partially inferred `Func<T, TResult>` becomes as
    // concrete as inference has made it, and an expression tree unwraps to the delegate it carries.
    // `Action`/`Func` are read structurally from their type ARGUMENTS rather than through `Invoke`,
    // because the open form's `Invoke` would lose the N# TypeInfo overrides; every other delegate
    // goes through `Invoke`, whose parameters carry their own nullability metadata.
    //
    // A NULL answer means "not a delegate at all". A delegate with no `Invoke` answers with an
    // unknown-returning signature instead, so a caller can tell "no signature" from "not callable".
    public func CreateDelegateSignatureFromOpenType(
        openDelegateType: Type,
        typeInfoOverrides: Dictionary<Type, TypeInfo>,
        clrBindings: Dictionary<Type, Type>): FunctionTypeInfo? {
        effectiveOpenType := openDelegateType
        resolvedType := AnalyzerReflectionTypeConversion.ApplyReflectionBindings(
            openDelegateType, clrBindings)
        expressionDelegateType: Type = typeof(object)
        if AnalyzerFunctionTypeFactory.TryGetExpressionTreeDelegateType(
                resolvedType, out expressionDelegateType) {
            resolvedType = expressionDelegateType
            effectiveOpenType = AnalyzerOverloadFacts.GetDelegateParameterTypeForLambdaTarget(
                openDelegateType)
        }

        if !assignabilityFacts.IsDelegateType(resolvedType) {
            return null
        }

        if resolvedType.get_IsGenericType() {
            definition := resolvedType.GetGenericTypeDefinition()
            definitionName := definition.get_FullName()

            openTypeArguments := resolvedType.GetGenericArguments()
            if effectiveOpenType.get_IsGenericType() {
                openTypeArguments = effectiveOpenType.GetGenericArguments()
            }

            typeArguments := new List<TypeInfo>()
            argumentIndex := 0
            while argumentIndex < openTypeArguments.Length {
                typeArguments.Add(
                    AnalyzerReflectionTypeConversion.ConvertReflectionTypeWithOverrides(
                        openTypeArguments[argumentIndex], typeInfoOverrides, clrBindings))
                argumentIndex = argumentIndex + 1
            }

            if AnalyzerFunctionTypeFactory.IsActionDefinitionName(definitionName) {
                action := new FunctionTypeInfo()
                action.ParameterTypes = typeArguments
                action.ParameterModifiers = AnalyzerFunctionTypeFactory.RepeatNoModifier(
                    typeArguments.Count)
                action.ReturnType = BuiltInTypes.Void
                return action
            }

            if AnalyzerFunctionTypeFactory.IsFuncDefinitionName(definitionName) {
                parameterCount := typeArguments.Count - 1
                parameterTypes := new List<TypeInfo>()
                parameterIndex := 0
                while parameterIndex < parameterCount {
                    parameterTypes.Add(typeArguments[parameterIndex])
                    parameterIndex = parameterIndex + 1
                }

                modifierCount := parameterCount
                if modifierCount < 0 {
                    modifierCount = 0
                }

                function := new FunctionTypeInfo()
                function.ParameterTypes = parameterTypes
                function.ParameterModifiers = AnalyzerFunctionTypeFactory.RepeatNoModifier(
                    modifierCount)
                function.ReturnType = typeArguments[typeArguments.Count - 1]
                return function
            }
        }

        invokeMethod := resolvedType.GetMethod("Invoke")
        if invokeMethod == null {
            unknown := new FunctionTypeInfo()
            unknown.ReturnType = BuiltInTypes.Unknown
            return unknown
        }

        invokeParameters := invokeMethod.GetParameters()
        parameterTypeList := new List<TypeInfo>()
        parameterModifierList := new List<ParameterModifier>()
        invokeIndex := 0
        while invokeIndex < invokeParameters.Length {
            invokeParameter := invokeParameters[invokeIndex]
            parameterTypeList.Add(
                AnalyzerReflectionTypeConversion.ConvertParameterWithOverrides(
                    invokeParameter, typeInfoOverrides, clrBindings))
            parameterModifierList.Add(
                AnalyzerFunctionTypeFactory.GetReflectionParameterModifier(invokeParameter))
            invokeIndex = invokeIndex + 1
        }

        signature := new FunctionTypeInfo()
        signature.ParameterTypes = parameterTypeList
        signature.ParameterModifiers = parameterModifierList
        signature.ReturnType = AnalyzerReflectionTypeConversion.ConvertReturnWithOverrides(
            invokeMethod, typeInfoOverrides, clrBindings)
        return signature
    }

    // The RECEIVER's contribution to generic inference, for a call on a generic type. A declaring
    // type that mentions no type parameter contributes nothing and is not a failure.
    public func TryPopulateReceiverGenericTypeBindings(
        declaringType: Type?,
        receiverClrType: Type,
        receiverTypeInfo: TypeInfo,
        bindings: Dictionary<Type, Type>,
        typeInfoBindings: Dictionary<Type, TypeInfo>): bool {
        if declaringType == null
            || !declaringType.get_IsGenericType()
            || !declaringType.get_ContainsGenericParameters() {
            return true
        }

        receiverSignatureType := declaringType
        if !declaringType.get_IsGenericTypeDefinition() {
            receiverSignatureType = declaringType.GetGenericTypeDefinition()
        }

        if !AnalyzerOverloadFacts.TryMatchReflectionParameter(
                receiverSignatureType, receiverClrType, bindings) {
            return false
        }

        PopulateTypeInfoBindingsFromType(
            receiverSignatureType, receiverTypeInfo, typeInfoBindings)
        return true
    }

    // The N# half of generic inference: which `TypeInfo` a method's open type parameter took.
    //
    // This runs ALONGSIDE the CLR binding walk rather than instead of it, because a source type has
    // no CLR form to bind and the finalising walk needs the source spelling back — that is what
    // keeps `int` printed as `int` and an N# record printed as itself in a reflected signature.
    //
    // FIRST BINDING WINS, matching the CLR walk, so a repeated type parameter is decided by its
    // leftmost occurrence. An ARRAY argument against any read-only sequence parameter contributes
    // its ELEMENT type, and a generic argument that does not match the parameter's own definition
    // is traced through the CLR hierarchy — `List<int>` against `IEnumerable<T>` binds `T` to `int`
    // by mapping the interface's type arguments back to the argument definition's own.
    public func PopulateTypeInfoBindingsFromType(
        openParameterType: Type,
        argumentTypeInfo: TypeInfo,
        typeInfoBindings: Dictionary<Type, TypeInfo>) {
        if openParameterType.get_IsGenericParameter() {
            if !typeInfoBindings.ContainsKey(openParameterType) {
                typeInfoBindings[openParameterType] = argumentTypeInfo
            }

            return
        }

        arrayTypeInfo := argumentTypeInfo as ArrayTypeInfo
        if arrayTypeInfo != null {
            enumerableElementParameter := TryGetReflectionEnumerableElementParameter(
                openParameterType)
            if enumerableElementParameter != null {
                PopulateTypeInfoBindingsFromType(
                    enumerableElementParameter, arrayTypeInfo.ElementType, typeInfoBindings)
                return
            }
        }

        argGeneric := argumentTypeInfo as GenericTypeInfo
        if !openParameterType.get_IsGenericType() || argGeneric == null {
            return
        }

        openParamGenDef := openParameterType.GetGenericTypeDefinition()
        openParamArgs := openParameterType.GetGenericArguments()
        paramName := StripGenericArity(openParamGenDef.get_Name())

        if argGeneric.Name == paramName && openParamArgs.Length == argGeneric.TypeArguments.Count {
            directIndex := 0
            while directIndex < openParamArgs.Length {
                PopulateTypeInfoBindingsFromType(
                    openParamArgs[directIndex],
                    argGeneric.TypeArguments[directIndex],
                    typeInfoBindings)
                directIndex = directIndex + 1
            }

            return
        }

        argClrType := clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(argumentTypeInfo)
        if argClrType == null || !argClrType.get_IsGenericType() {
            return
        }

        argGenDef := argClrType.GetGenericTypeDefinition()
        openImpl := FindOpenImplementation(argGenDef, openParamGenDef)
        if openImpl == null {
            return
        }

        implArgs := openImpl.GetGenericArguments()
        argDefGenArgs := argGenDef.GetGenericArguments()

        implIndex := 0
        while implIndex < openParamArgs.Length && implIndex < implArgs.Length {
            if implArgs[implIndex].get_IsGenericParameter() {
                definitionIndex := 0
                while definitionIndex < argDefGenArgs.Length {
                    if implArgs[implIndex] == argDefGenArgs[definitionIndex]
                        && definitionIndex < argGeneric.TypeArguments.Count {
                        PopulateTypeInfoBindingsFromType(
                            openParamArgs[implIndex],
                            argGeneric.TypeArguments[definitionIndex],
                            typeInfoBindings)
                        definitionIndex = argDefGenArgs.Length
                    } else {
                        definitionIndex = definitionIndex + 1
                    }
                }
            }

            implIndex = implIndex + 1
        }
    }

    // Both halves of inference, driven from a SOURCE signature rather than from a CLR argument. This
    // is how a selected method group's own parameter and return types flow back into the reflected
    // method's type parameters.
    public func PopulateReflectionBindingsFromTypeInfo(
        openType: Type,
        sourceType: TypeInfo,
        bindings: Dictionary<Type, Type>,
        typeInfoBindings: Dictionary<Type, TypeInfo>) {
        effectiveOpenType := openType
        if openType.get_IsByRef() {
            element := openType.GetElementType()
            if element != null {
                effectiveOpenType = element
            }
        }

        if effectiveOpenType.get_IsGenericParameter() {
            if !typeInfoBindings.ContainsKey(effectiveOpenType) {
                typeInfoBindings[effectiveOpenType] = sourceType
            }

            if !bindings.ContainsKey(effectiveOpenType) {
                clrType := clrTypeConversion.TryConvertTypeInfoToClrType(sourceType)
                if clrType == null {
                    clrType = clrTypeConversion.TryConvertTypeInfoToClrTypeForBinding(sourceType)
                }

                if clrType != null {
                    bindings[effectiveOpenType] = clrType
                }
            }

            return
        }

        if effectiveOpenType.get_IsArray() {
            sourceArray := sourceType as ArrayTypeInfo
            if sourceArray != null {
                elementType := effectiveOpenType.GetElementType()
                if elementType != null {
                    PopulateReflectionBindingsFromTypeInfo(
                        elementType, sourceArray.ElementType, bindings, typeInfoBindings)
                }
            }

            return
        }

        if !effectiveOpenType.get_IsGenericType() {
            return
        }

        PopulateTypeInfoBindingsFromType(effectiveOpenType, sourceType, typeInfoBindings)

        sourceGeneric := sourceType as GenericTypeInfo
        if sourceGeneric == null {
            return
        }

        openName := StripGenericArity(effectiveOpenType.get_Name())
        openArguments := effectiveOpenType.GetGenericArguments()
        if AnalyzerOverloadFacts.GenericNamesMatch(openName, sourceGeneric.Name)
            && openArguments.Length == sourceGeneric.TypeArguments.Count {
            index := 0
            while index < openArguments.Length {
                PopulateReflectionBindingsFromTypeInfo(
                    openArguments[index],
                    sourceGeneric.TypeArguments[index],
                    bindings,
                    typeInfoBindings)
                index = index + 1
            }
        }
    }

    // A selected method group's SIGNATURE, matched position by position against the delegate's own
    // `Invoke`. An arity disagreement is a non-binding; a `void` return contributes nothing.
    public func TryPopulateReflectionBindingsFromMethodGroupDelegate(
        openDelegateType: Type,
        sourceFunctionType: FunctionTypeInfo,
        bindings: Dictionary<Type, Type>,
        typeInfoBindings: Dictionary<Type, TypeInfo>): bool {
        invokeMethod := openDelegateType.GetMethod("Invoke")
        if invokeMethod == null {
            return false
        }

        invokeParameters := invokeMethod.GetParameters()
        sourceParameterTypes := sourceFunctionType.ParameterTypes
        if sourceParameterTypes == null {
            sourceParameterTypes = new List<TypeInfo>()
        }

        if invokeParameters.Length != sourceParameterTypes.Count {
            return false
        }

        index := 0
        while index < invokeParameters.Length {
            PopulateReflectionBindingsFromTypeInfo(
                invokeParameters[index].get_ParameterType(),
                sourceParameterTypes[index],
                bindings,
                typeInfoBindings)
            index = index + 1
        }

        returnType := sourceFunctionType.ReturnType
        if invokeMethod.get_ReturnType() != LiveVoidType() && returnType != null {
            PopulateReflectionBindingsFromTypeInfo(
                invokeMethod.get_ReturnType(),
                returnType,
                bindings,
                typeInfoBindings)
        }

        return true
    }

    // The read-only SEQUENCE parameters an array argument may contribute its element type to. The
    // set is deliberately closed: it is the shapes an N# array literal binds to without conversion.
    // A null answer means this parameter is not one of them.
    func TryGetReflectionEnumerableElementParameter(openParameterType: Type): Type? {
        effectiveType := AnalyzerOverloadFacts.GetByRefElementType(openParameterType)
        if effectiveType.get_IsArray() {
            return effectiveType.GetElementType()
        }

        if !effectiveType.get_IsGenericType() {
            return null
        }

        definitionName := effectiveType.GetGenericTypeDefinition().get_FullName()
        if definitionName == "System.Collections.Generic.IEnumerable`1"
            || definitionName == "System.Collections.Generic.IReadOnlyList`1"
            || definitionName == "System.Collections.Generic.IReadOnlyCollection`1"
            || definitionName == "System.Collections.Generic.ICollection`1"
            || definitionName == "System.Collections.Generic.IList`1" {
            return effectiveType.GetGenericArguments()[0]
        }

        return null
    }

    // The interface or base position on `definition` that instantiates `openDefinition`. Interfaces
    // are searched before the base chain, matching the CLR's own resolution order.
    static func FindOpenImplementation(definition: Type, openDefinition: Type): Type? {
        interfaces := definition.GetInterfaces()
        index := 0
        while index < interfaces.Length {
            candidate := interfaces[index]
            if candidate.get_IsGenericType()
                && candidate.GetGenericTypeDefinition() == openDefinition {
                return candidate
            }

            index = index + 1
        }

        baseType := definition.get_BaseType()
        while baseType != null {
            if baseType.get_IsGenericType()
                && baseType.GetGenericTypeDefinition() == openDefinition {
                return baseType
            }

            baseType = baseType.get_BaseType()
        }

        return null
    }

    // A reflected generic name carries its arity (`List`1`); the N# spelling does not.
    static func StripGenericArity(name: string?): string {
        if name == null {
            return ""
        }

        tick := name.IndexOf("`", StringComparison.Ordinal)
        if tick < 0 {
            return name
        }

        return name.Substring(0, tick)
    }

    // The LIVE `System.Void`, resolved through the core library because `typeof(void)` is off the
    // columnar surface.
    //
    // It is deliberately the LIVE one, and the difference is observable: a delegate read through a
    // MetadataLoadContext answers with the CONTEXT'S `System.Void`, a distinct type identity, so
    // this comparison does not recognise it as void. That is exactly the comparison the analyzer has
    // always made here, and it is reproduced rather than corrected — a correction would change which
    // return positions contribute to inference.
    static func LiveVoidType(): Type {
        coreLibrary := typeof(object).get_Assembly()
        voidType := coreLibrary.GetType("System.Void")
        if voidType == null {
            throw new InvalidOperationException("The core library does not define 'System.Void'.")
        }

        return voidType
    }

    // A TRIAL copy of the accumulated CLR bindings. The point is not the copy but the ISOLATION: a
    // refused direct params pass must leave no generic inference behind for the expansion that
    // follows it.
    static func CopyBindings(bindings: Dictionary<Type, Type>): Dictionary<Type, Type> {
        copy := new Dictionary<Type, Type>()
        foreach entry in bindings {
            copy[entry.Key] = entry.Value
        }

        return copy
    }

    // The named-argument lookup, over the SUPPLIABLE positions only: a receiver position is never
    // addressable by name.
    static func FindNamedParameterIndex(
        parameters: ParameterInfo[],
        parameterOffset: int,
        name: string): int {
        index := parameterOffset
        while index < parameters.Length {
            if String.Equals(parameters[index].get_Name(), name, StringComparison.Ordinal) {
                return index
            }

            index = index + 1
        }

        return -1
    }
}
