namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// EXTERNAL GENERIC METHODS, CLOSED BY INFERENCE FROM THE ARGUMENTS.
//
// The ordinary runtime call resolver owns fixed-arity, NON-generic declarations; a generic method
// definition is an excluded shape there because its signature still mentions its own type parameters
// and cannot be scored or emitted as written. This owner is the tier that closes them:
// `Vector.Sum(block)` binds `T` to `int` from `Vector<int>`, `Vector.Min(a, b)` and
// `Vector.ConditionalSelect(mask, a, b)` bind it from the same shape, and `HashCode.Combine(state, ok)`
// binds one parameter per argument.
//
// IT ANSWERS THE SAME SELECTION TYPE AS THE ORDINARY RESOLVER ON PURPOSE. A closed generic method is
// an ordinary MethodInfo with an ordinary signature, so the planner's existing append path emits it
// with no new arm: the whole difference between the two tiers is how the handle was obtained.
//
// INFERENCE IS ARGUMENT-DRIVEN UNIFICATION (ECMA-334 §12.6.3's first phase). Each parameter is walked
// against its argument: a method type parameter binds to the argument type it meets, an array or
// by-ref shell recurses into its element, and a constructed generic parameter is matched against the
// same definition found anywhere in the argument's own hierarchy -- so `IEnumerable<T>` against
// `List<int>` binds `T` to `int`. A position that carries no information contributes none, and a type
// parameter that two positions bind DIFFERENTLY is refused rather than guessed.
//
// NOTHING IS ACCEPTED ON THE STRENGTH OF INFERENCE ALONE. The inferred type arguments are handed to
// `MakeGenericMethod`, which enforces the declared constraints, and the resulting CLOSED signature is
// then scored by the same argument-flow scorer every other call selection uses. A candidate whose
// closed parameters do not accept the arguments loses exactly as a non-generic one would.
class ColumnarRuntimeGenericMethodResolver {
    static func Resolve(lookupType: Type, memberName: string, argumentTypes: Type[], expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return ResolveWithFacts(lookupType, memberName, argumentTypes, ColumnarDirectCallArgumentFacts.Empty(argumentTypes.Length), expectedStatic)
    }

    static func ResolveWithFacts(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        if lookupType == null || memberName == null || argumentTypes == null {
            throw new InvalidOperationException("Runtime generic method resolution inputs cannot be null.")
        }
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)

        // A builder-bound owner's members are only reachable through its open definition, where a
        // generic method's own parameters and the TYPE's parameters would both need closing at once.
        // That pairing has no call site yet and is left to the tier that grows one.
        if ColumnarRuntimeInstanceMemberResolver.ContainsBuilderBoundType(lookupType) || lookupType.get_IsGenericTypeDefinition() || lookupType.get_IsGenericParameter() {
            return Unselected(lookupType, expectedStatic)
        }

        candidates := new List<MethodInfo>()
        candidateParameters := new List<Type[]>()
        AppendClosedCandidates(lookupType, memberName, argumentTypes, candidates, candidateParameters, expectedStatic)
        if candidates.Count == 0 {
            return Unselected(lookupType, expectedStatic)
        }

        selectedIndex := ColumnarConstructionPlanner.BestSourceConstructorIndex(candidateParameters, argumentTypes, argumentFacts)
        if selectedIndex < 0 {
            return Unselected(lookupType, expectedStatic)
        }

        selected := candidates[selectedIndex]
        declaringType := selected.get_DeclaringType()
        if declaringType == null {
            return Unselected(lookupType, expectedStatic)
        }

        receiverIsReference := !expectedStatic && !lookupType.get_IsValueType()
        kind := expectedStatic ? ColumnarExternalCallKind.Call : (receiverIsReference ? ColumnarExternalCallKind.CallVirtual : ColumnarExternalCallKind.Call)
        return new ColumnarOrdinaryRuntimeDirectCallSelection(
            ColumnarOrdinaryRuntimeDirectCallStatus.Selected,
            selected,
            lookupType,
            declaringType,
            candidateParameters[selectedIndex],
            selected.get_ReturnType(),
            kind,
            expectedStatic,
            receiverIsReference,
            selected.get_IsAbstract()
        )
    }

    static func AppendClosedCandidates(lookupType: Type, memberName: string, argumentTypes: Type[], candidates: List<MethodInfo>, candidateParameters: List<Type[]>, expectedStatic: bool) {
        declared := MethodsOrEmpty(lookupType)
        index := 0
        while index < declared.Length {
            candidate := declared[index]
            if IsInferableCandidate(candidate, lookupType, memberName, argumentTypes.Length, expectedStatic) {
                closed := TryCloseCandidate(candidate, argumentTypes)
                if closed != null {
                    closedParameters := ClosedParameterTypesOrNull(closed)
                    if closedParameters != null {
                        candidates.Add(closed)
                        candidateParameters.Add(closedParameters)
                    }
                }
            }

            index = index + 1
        }
    }

    static func MethodsOrEmpty(lookupType: Type): MethodInfo[] {
        try {
            methods := lookupType.GetMethods()
            if methods == null {
                return new MethodInfo[](0)
            }
            return methods
        } catch ex: NotSupportedException {
            return new MethodInfo[](0)
        } catch ex: NotImplementedException {
            return new MethodInfo[](0)
        }
    }

    static func IsInferableCandidate(candidate: MethodInfo, lookupType: Type, memberName: string, argumentCount: int, expectedStatic: bool): bool {
        if candidate == null || !candidate.get_IsPublic() || candidate.get_Name() != memberName || candidate.get_IsStatic() != expectedStatic {
            return false
        }
        if !candidate.get_IsGenericMethodDefinition() {
            return false
        }
        if ColumnarSourceOperatorResolver.IsVarArgs(candidate) {
            return false
        }
        declaringType := candidate.get_DeclaringType()
        if declaringType == null {
            return false
        }
        if !ColumnarConstructionPlanner.SameObject(declaringType, lookupType) {
            if declaringType.get_IsValueType() || lookupType.get_IsValueType() || !RuntimeAssignableFrom(declaringType, lookupType) {
                return false
            }
        }

        parameters := candidate.GetParameters()
        if parameters == null || parameters.Length != argumentCount {
            return false
        }
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter == null || parameter.get_ParameterType() == null || ColumnarExtensionMethodResolver.IsParamsParameter(parameter) {
                return false
            }
            index = index + 1
        }
        return true
    }

    static func RuntimeAssignableFrom(declaringType: Type, lookupType: Type): bool {
        try {
            return declaringType.IsAssignableFrom(lookupType)
        } catch ex: NotSupportedException {
            return false
        } catch ex: NotImplementedException {
            return false
        }
    }

    // The candidate closed over the type arguments its parameters infer, or null when a type parameter
    // stays unbound, two positions disagree, or the constraints refuse the instantiation.
    static func TryCloseCandidate(candidate: MethodInfo, argumentTypes: Type[]): MethodInfo? {
        genericParameters := candidate.GetGenericArguments()
        bindings := new Dictionary<int, Type>()
        parameters := candidate.GetParameters()
        index := 0
        while index < parameters.Length {
            if !Unify(parameters[index].get_ParameterType(), argumentTypes[index], bindings) {
                return null
            }
            index = index + 1
        }

        typeArguments := new Type[](genericParameters.Length)
        position := 0
        while position < genericParameters.Length {
            bound := typeof(object)
            if !bindings.TryGetValue(position, out bound) || bound == null {
                return null
            }
            typeArguments[position] = bound
            position = position + 1
        }

        try {
            return candidate.MakeGenericMethod(typeArguments)
        } catch ex: ArgumentException {
            return null
        } catch ex: NotSupportedException {
            return null
        } catch ex: InvalidOperationException {
            return null
        }
    }

    static func Unify(parameterType: Type, argumentType: Type, bindings: Dictionary<int, Type>): bool {
        if parameterType == null || argumentType == null {
            return false
        }
        if parameterType.get_IsByRef() {
            element := parameterType.GetElementType()
            if element == null {
                return false
            }
            return Unify(element, StripByRef(argumentType), bindings)
        }

        if parameterType.get_IsGenericParameter() {
            // A type parameter of the DECLARING type is already fixed by the owner; only a METHOD type
            // parameter is inferred here.
            if parameterType.get_DeclaringMethod() == null {
                return true
            }
            if IsUnbindableInferredType(argumentType) {
                return false
            }
            position := parameterType.get_GenericParameterPosition()
            existing := typeof(object)
            if bindings.TryGetValue(position, out existing) {
                return existing != null && ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(existing, argumentType)
            }
            bindings[position] = argumentType
            return true
        }

        if parameterType.get_IsArray() {
            if !argumentType.get_IsArray() {
                return true
            }
            parameterElement := parameterType.GetElementType()
            argumentElement := argumentType.GetElementType()
            if parameterElement == null || argumentElement == null {
                return true
            }
            return Unify(parameterElement, argumentElement, bindings)
        }

        if !parameterType.get_IsGenericType() || !parameterType.get_ContainsGenericParameters() {
            return true
        }

        matched := FindMatchingInstantiation(parameterType.GetGenericTypeDefinition(), argumentType)
        if matched == null {
            return true
        }

        parameterArguments := parameterType.GetGenericArguments()
        matchedArguments := matched.GetGenericArguments()
        if parameterArguments.Length != matchedArguments.Length {
            return true
        }

        position := 0
        while position < parameterArguments.Length {
            if !Unify(parameterArguments[position], matchedArguments[position], bindings) {
                return false
            }
            position = position + 1
        }
        return true
    }

    // The instantiation of `definition` reachable from the argument type: the type itself, one of its
    // base classes, or one of its interfaces. This is what lets `IEnumerable<T>` infer `T` from a
    // `List<int>` argument.
    static func FindMatchingInstantiation(definition: Type, argumentType: Type): Type? {
        current: Type? = argumentType
        while current != null {
            if IsInstantiationOf(definition, current) {
                return current
            }
            current = BaseTypeOrNull(current)
        }

        interfaces := InterfacesOrEmpty(argumentType)
        index := 0
        while index < interfaces.Length {
            if IsInstantiationOf(definition, interfaces[index]) {
                return interfaces[index]
            }
            index = index + 1
        }
        return null
    }

    static func IsInstantiationOf(definition: Type, candidate: Type): bool {
        if !candidate.get_IsGenericType() || candidate.get_IsGenericTypeDefinition() {
            return false
        }
        return ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(candidate.GetGenericTypeDefinition(), definition)
    }

    static func InterfacesOrEmpty(argumentType: Type): Type[] {
        try {
            found := argumentType.GetInterfaces()
            if found == null {
                return new Type[](0)
            }
            return found
        } catch ex: NotSupportedException {
            return new Type[](0)
        } catch ex: NotImplementedException {
            return new Type[](0)
        }
    }

    static func BaseTypeOrNull(current: Type): Type? {
        try {
            return current.get_BaseType()
        } catch ex: NotSupportedException {
            return null
        } catch ex: NotImplementedException {
            return null
        }
    }

    static func StripByRef(candidate: Type): Type {
        if !candidate.get_IsByRef() {
            return candidate
        }
        element := candidate.GetElementType()
        if element == null {
            return candidate
        }
        return element
    }

    // A type argument the CLR cannot close a method over. `void` and a still-open shape are the two
    // that reach here; a builder-bound argument would produce a handle the emitter cannot call.
    static func IsUnbindableInferredType(argumentType: Type): bool {
        if argumentType.FullName == "System.Void" || argumentType.get_IsByRef() || argumentType.get_IsPointer() {
            return true
        }
        if argumentType.get_ContainsGenericParameters() {
            return true
        }
        return ColumnarRuntimeInstanceMemberResolver.ContainsBuilderBoundType(argumentType)
    }

    static func ClosedParameterTypesOrNull(closed: MethodInfo): Type[]? {
        parameters := closed.GetParameters()
        result := new Type[](parameters.Length)
        index := 0
        while index < parameters.Length {
            parameterType := parameters[index].get_ParameterType()
            if parameterType == null || ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedSignatureType(parameterType) {
                return null
            }
            result[index] = parameterType
            index = index + 1
        }

        returnType := closed.get_ReturnType()
        if returnType == null || returnType.get_IsByRef() || returnType.get_IsPointer() || returnType.get_ContainsGenericParameters() {
            return null
        }
        return result
    }

    static func Unselected(lookupType: Type, expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
        return new ColumnarOrdinaryRuntimeDirectCallSelection(
            ColumnarOrdinaryRuntimeDirectCallStatus.NotFound,
            null,
            lookupType,
            lookupType,
            new Type[](0),
            typeof(object),
            ColumnarExternalCallKind.None,
            expectedStatic,
            !expectedStatic && !lookupType.get_IsValueType(),
            false
        )
    }
}
