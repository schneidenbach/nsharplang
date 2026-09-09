namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit


// These conversions are assignable, but they are neither CLR reference conversions nor
// implicit numeric conversions. Keep their score at the analyzer's assignable tier so an exact
// overload wins and a competing object/reference overload remains an ambiguity.
enum ColumnarDirectCallConstructedConversionKind {
    None = 0,
    ArrayToSpan = 1,
    ArrayToReadOnlySpan = 2,
    AnonymousUnionArm0 = 3,
    AnonymousUnionArm1 = 4,
    SpanToReadOnlySpan = 5
}

// Immutable-by-convention selection facts keep overload classification separate from plan
// mutation. Exactly one handle is present: array and union conversions use an exact closed
// constructor, while Span<T> -> ReadOnlySpan<T> uses the exact closed op_Implicit method.
// TryAppend revalidates those facts before placing the handle in the persisted pool.
class ColumnarDirectCallConstructedConversionSelection {
    Kind: ColumnarDirectCallConstructedConversionKind
    Score: int
    ExpectedType: Type
    ActualType: Type
    ConstructorHandle: ConstructorInfo?
    MethodHandle: MethodInfo?

    constructor(kind: ColumnarDirectCallConstructedConversionKind, score: int, expectedType: Type, actualType: Type, constructorHandle: ConstructorInfo?, methodHandle: MethodInfo?) {
        hasConstructor := constructorHandle != null
        hasMethod := methodHandle != null
        if kind == ColumnarDirectCallConstructedConversionKind.None || score != 4 || expectedType == null || actualType == null || hasConstructor == hasMethod {
            throw new InvalidOperationException("Constructed direct-call conversion facts must be complete.")
        }

        Kind = kind
        Score = score
        ExpectedType = expectedType
        ActualType = actualType
        ConstructorHandle = constructorHandle
        MethodHandle = methodHandle
    }
}

class ColumnarDirectCallConstructedConversions {
    static func ArgumentFlowScore(expectedType: Type, actualType: Type): int {
        selection: ColumnarDirectCallConstructedConversionSelection? = null
        return TryClassify(expectedType, actualType, out selection) ? 4 : -1
    }

    static func CanConvert(expectedType: Type, actualType: Type): bool {
        return ArgumentFlowScore(expectedType, actualType) == 4
    }

    static func TryClassify(expectedType: Type, actualType: Type, out selection: ColumnarDirectCallConstructedConversionSelection?): bool {
        if expectedType == null || actualType == null {
            throw new InvalidOperationException("Constructed direct-call conversion types cannot be null.")
        }

        selection = null
        kind := ClassifyShape(expectedType, actualType)
        if kind == ColumnarDirectCallConstructedConversionKind.None {
            return false
        }

        if kind == ColumnarDirectCallConstructedConversionKind.SpanToReadOnlySpan {
            methodHandle: MethodInfo? = null
            if !TryResolveSpanToReadOnlySpanMethod(expectedType, actualType, out methodHandle) || methodHandle == null {
                return false
            }

            selection = new ColumnarDirectCallConstructedConversionSelection(kind, 4, expectedType, actualType, null, methodHandle)
        } else {
            constructorHandle: ConstructorInfo? = null
            if !TryResolveConstructor(expectedType, actualType, kind, out constructorHandle) || constructorHandle == null {
                return false
            }

            selection = new ColumnarDirectCallConstructedConversionSelection(kind, 4, expectedType, actualType, constructorHandle, null)
        }

        return true
    }

    // Appends only the conversion row. The caller owns the already-emitted argument value and
    // the surrounding fragment. Unsupported or corrupt selection facts leave the plan untouched;
    // any exceptional plan mutation rolls back the member pool and operation row together.
    static func TryAppend(plan: ColumnarCodePlan, expectedType: Type, actualType: Type): bool {
        if plan == null {
            throw new InvalidOperationException("Constructed direct-call conversion plan cannot be null.")
        }

        selection: ColumnarDirectCallConstructedConversionSelection? = null
        if !TryClassify(expectedType, actualType, out selection) || selection == null {
            return false
        }

        return TryAppend(plan, selection)
    }

    static func TryAppend(plan: ColumnarCodePlan, selection: ColumnarDirectCallConstructedConversionSelection): bool {
        if plan == null {
            throw new InvalidOperationException("Constructed direct-call conversion plan cannot be null.")
        }

        if selection == null || !SelectionIsExact(selection) {
            return false
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            parameterTypes := new Type[](1)
            parameterTypes[0] = selection.ActualType
            if selection.Kind == ColumnarDirectCallConstructedConversionKind.SpanToReadOnlySpan {
                methodHandle := selection.MethodHandle
                if methodHandle == null {
                    return false
                }

                declaringType := methodHandle.get_DeclaringType()
                if declaringType == null {
                    return false
                }

                methodIndex := plan.AddMethodWithSignature(methodHandle, declaringType, parameterTypes, selection.ExpectedType, true, false)
                plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
            } else {
                constructorHandle := selection.ConstructorHandle
                if constructorHandle == null {
                    return false
                }

                constructorIndex := plan.AddConstructorWithSignature(constructorHandle, selection.ExpectedType, parameterTypes)
                plan.AppendConstructorInstruction(ColumnarCodePlanContract.Newobj(), constructorIndex)
            }

            return true
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    static func ClassifyShape(expectedType: Type, actualType: Type): ColumnarDirectCallConstructedConversionKind {
        if expectedType.get_IsByRef() || actualType.get_IsByRef() || actualType.FullName == "System.Void" {
            return ColumnarDirectCallConstructedConversionKind.None
        }

        if IsExactClosedGeneric(actualType, typeof(Span<int>).GetGenericTypeDefinition()) && IsExactClosedGeneric(expectedType, typeof(ReadOnlySpan<int>).GetGenericTypeDefinition()) {
            actualArguments := actualType.GetGenericArguments()
            expectedArguments := expectedType.GetGenericArguments()
            if actualArguments.Length == 1 && expectedArguments.Length == 1 && ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(actualArguments[0], expectedArguments[0]) {
                return ColumnarDirectCallConstructedConversionKind.SpanToReadOnlySpan
            }
        }

        if actualType.get_IsSZArray() && expectedType.get_IsGenericType() && !expectedType.get_IsGenericTypeDefinition() {
            actualElement := actualType.GetElementType()
            expectedArguments := expectedType.GetGenericArguments()
            if actualElement != null && expectedArguments.Length == 1 && ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(expectedArguments[0], actualElement) {
                definition := expectedType.GetGenericTypeDefinition()
                if definition == typeof(Span<int>).GetGenericTypeDefinition() {
                    return ColumnarDirectCallConstructedConversionKind.ArrayToSpan
                }

                if definition == typeof(ReadOnlySpan<int>).GetGenericTypeDefinition() {
                    return ColumnarDirectCallConstructedConversionKind.ArrayToReadOnlySpan
                }
            }
        }

        if !expectedType.get_IsGenericType() || expectedType.get_IsGenericTypeDefinition() {
            return ColumnarDirectCallConstructedConversionKind.None
        }

        unionDefinition := expectedType.GetGenericTypeDefinition()
        if !IsAnonymousUnionDefinition(unionDefinition) {
            return ColumnarDirectCallConstructedConversionKind.None
        }

        arms := expectedType.GetGenericArguments()
        if arms.Length != 2 {
            return ColumnarDirectCallConstructedConversionKind.None
        }

        matchesArm0 := ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(arms[0], actualType)

        matchesArm1 := ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(arms[1], actualType)

        if matchesArm0 == matchesArm1 {
            return ColumnarDirectCallConstructedConversionKind.None
        }

        return matchesArm0 ? ColumnarDirectCallConstructedConversionKind.AnonymousUnionArm0 : ColumnarDirectCallConstructedConversionKind.AnonymousUnionArm1
    }

    static func IsExactClosedGeneric(candidate: Type, expectedDefinition: Type): bool {
        return candidate != null && expectedDefinition != null && candidate.get_IsGenericType() && !candidate.get_IsGenericTypeDefinition() && candidate.GetGenericTypeDefinition() == expectedDefinition
    }

    static func IsAnonymousUnionDefinition(candidate: Type): bool {
        if candidate == null || !candidate.get_IsValueType() || !candidate.get_IsGenericTypeDefinition() || candidate.FullName != "NSharpLang.Runtime.Union`2" {
            return false
        }

        assemblyIdentity := candidate.get_Assembly().GetName().get_FullName()
        if assemblyIdentity == null || (!String.Equals(assemblyIdentity, "NSharpLang.Runtime", StringComparison.Ordinal) && !assemblyIdentity.StartsWith("NSharpLang.Runtime,", StringComparison.Ordinal)) {
            return false
        }

        arguments := candidate.GetGenericArguments()
        if arguments.Length != 2 || !arguments[0].get_IsGenericParameter() || arguments[0].get_GenericParameterPosition() != 0 || !arguments[1].get_IsGenericParameter() || arguments[1].get_GenericParameterPosition() != 1 {
            return false
        }

        hasFirstArm := false
        hasSecondArm := false
        constructors := candidate.GetConstructors()
        if constructors.Length != 2 {
            return false
        }

        index := 0
        while index < constructors.Length {
            parameters := constructors[index].GetParameters()
            if parameters.Length == 1 {
                parameterType := parameters[0].get_ParameterType()
                if parameterType.get_IsGenericParameter() {
                    position := parameterType.get_GenericParameterPosition()
                    if position == 0 {
                        hasFirstArm = true
                    } else if position == 1 {
                        hasSecondArm = true
                    }
                }
            }

            index += 1
        }

        return hasFirstArm && hasSecondArm
    }

    static func TryResolveConstructor(expectedType: Type, actualType: Type, kind: ColumnarDirectCallConstructedConversionKind, out constructorHandle: ConstructorInfo?): bool {
        constructorHandle = null
        parameterTypes := new Type[](1)
        parameterTypes[0] = actualType

        if kind == ColumnarDirectCallConstructedConversionKind.ArrayToSpan || kind == ColumnarDirectCallConstructedConversionKind.ArrayToReadOnlySpan {
            try {
                constructorHandle = expectedType.GetConstructor(parameterTypes)
                return constructorHandle != null
            } catch ex: NotSupportedException {
                return false
            } catch ex: NotImplementedException {
                return false
            }
        }

        if kind != ColumnarDirectCallConstructedConversionKind.AnonymousUnionArm0 && kind != ColumnarDirectCallConstructedConversionKind.AnonymousUnionArm1 {
            return false
        }

        if !ContainsBuilderBoundType(expectedType) {
            try {
                constructorHandle = expectedType.GetConstructor(parameterTypes)
                return constructorHandle != null
            } catch ex: NotSupportedException {
                return false
            } catch ex: NotImplementedException {
                return false
            }
        }

        armPosition := kind == ColumnarDirectCallConstructedConversionKind.AnonymousUnionArm0 ? 0 : 1

        definition := expectedType.GetGenericTypeDefinition()
        constructors := definition.GetConstructors()

        index := 0
        while index < constructors.Length {
            candidate := constructors[index]
            parameters := candidate.GetParameters()
            if parameters.Length == 1 {
                parameterType := parameters[0].get_ParameterType()
                if parameterType.get_IsGenericParameter() && parameterType.get_GenericParameterPosition() == armPosition {
                    constructorHandle = TypeBuilder.GetConstructor(expectedType, candidate)

                    return constructorHandle != null
                }
            }

            index += 1
        }

        return false
    }

    static func TryResolveSpanToReadOnlySpanMethod(expectedType: Type, actualType: Type, out methodHandle: MethodInfo?): bool {
        methodHandle = null
        if ClassifyShape(expectedType, actualType) != ColumnarDirectCallConstructedConversionKind.SpanToReadOnlySpan {
            return false
        }

        owners := new Type[](2)
        owners[0] = actualType
        owners[1] = expectedType
        ownerIndex := 0
        while ownerIndex < owners.Length {
            methods := new MethodInfo[](0)
            try {
                methods = owners[ownerIndex].GetMethods()
            } catch ex: NotSupportedException {
                return false
            } catch ex: NotImplementedException {
                return false
            }

            methodIndex := 0
            while methodIndex < methods.Length {
                candidate := methods[methodIndex]
                if IsExactSpanToReadOnlySpanMethod(candidate, owners[ownerIndex], expectedType, actualType) {
                    if methodHandle != null {
                        return false
                    }

                    methodHandle = candidate
                }

                methodIndex += 1
            }

            ownerIndex += 1
        }

        return methodHandle != null
    }

    static func IsExactSpanToReadOnlySpanMethod(method: MethodInfo, declaringType: Type, expectedType: Type, actualType: Type): bool {
        if method == null || declaringType == null {
            return false
        }

        ownerIsActual := ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(declaringType, actualType)
        ownerIsExpected := ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(declaringType, expectedType)
        if !ownerIsActual && !ownerIsExpected || method.get_Name() != "op_Implicit" || !method.get_IsPublic() || !method.get_IsStatic() || method.get_IsAbstract() || method.get_IsGenericMethod() || method.get_IsGenericMethodDefinition() || method.get_DeclaringType() != declaringType || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(method.get_ReturnType(), expectedType) {
            return false
        }

        parameters := method.GetParameters()
        return parameters.Length == 1 && ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(parameters[0].get_ParameterType(), actualType)
    }

    static func SelectionIsExact(selection: ColumnarDirectCallConstructedConversionSelection): bool {
        if selection.Score != 4 || selection.Kind != ClassifyShape(selection.ExpectedType, selection.ActualType) {
            return false
        }

        if selection.Kind == ColumnarDirectCallConstructedConversionKind.SpanToReadOnlySpan {
            if selection.ConstructorHandle != null {
                return false
            }

            methodHandle := selection.MethodHandle
            if methodHandle == null {
                return false
            }

            expectedMethod: MethodInfo? = null
            if !TryResolveSpanToReadOnlySpanMethod(selection.ExpectedType, selection.ActualType, out expectedMethod) || expectedMethod == null {
                return false
            }

            declaringType := methodHandle.get_DeclaringType()
            return declaringType != null && IsExactSpanToReadOnlySpanMethod(methodHandle, declaringType, selection.ExpectedType, selection.ActualType) && Object.ReferenceEquals(methodHandle, expectedMethod)
        }

        if selection.MethodHandle != null {
            return false
        }

        constructorHandle := selection.ConstructorHandle
        if constructorHandle == null {
            return false
        }

        expectedConstructor: ConstructorInfo? = null
        if !TryResolveConstructor(selection.ExpectedType, selection.ActualType, selection.Kind, out expectedConstructor) || expectedConstructor == null {
            return false
        }

        declaringType := constructorHandle.get_DeclaringType()
        if declaringType == null || !ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(declaringType, selection.ExpectedType) {
            return false
        }

        parameters := constructorHandle.GetParameters()
        if parameters.Length != 1 {
            return false
        }

        parameterType := parameters[0].get_ParameterType()
        if !ContainsBuilderBoundType(selection.ExpectedType) {
            return ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(parameterType, selection.ActualType)
        }

        expectedPosition := selection.Kind == ColumnarDirectCallConstructedConversionKind.AnonymousUnionArm0 ? 0 : 1

        if ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(parameterType, selection.ActualType) {
            return true
        }

        return parameterType.get_IsGenericParameter() && parameterType.get_GenericParameterPosition() == expectedPosition
    }

    static func ContainsBuilderBoundType(valueType: Type): bool {
        if valueType is TypeBuilder || valueType.get_IsGenericParameter() {
            return true
        }

        if valueType.get_HasElementType() {
            element := valueType.GetElementType()
            return element != null && ContainsBuilderBoundType(element)
        }

        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }

        arguments := valueType.GetGenericArguments()
        index := 0
        while index < arguments.Length {
            if ContainsBuilderBoundType(arguments[index]) {
                return true
            }

            index += 1
        }

        return false
    }
}
