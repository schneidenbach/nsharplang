namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler

// One exact runtime extension-method candidate: a public static method that carries
// [System.Runtime.CompilerServices.ExtensionAttribute] and whose first parameter is the extension
// receiver. ParameterTypes is the FULL declared list, so ParameterTypes[0] is the receiver slot and
// an ordinary `StaticClass.Method(receiver, args...)` call row reproduces the extension invocation.
// Generic methods are indexed as OPEN definitions; selection closes them by receiver/argument
// inference so the selected candidate always carries an exact closed handle and signature.
class ColumnarExtensionMethodCandidate {
    Method: MethodInfo
    DeclaringType: Type
    ParameterTypes: Type[]
    ReturnType: Type

    ReceiverParameterType: Type => ParameterTypes[0]

    constructor(method: MethodInfo, declaringType: Type, parameterTypes: Type[], returnType: Type) {
        if method == null || declaringType == null || parameterTypes == null || returnType == null || parameterTypes.Length < 1 {
            throw new InvalidOperationException("Extension-method candidate facts cannot be null.")
        }

        Method = method
        DeclaringType = declaringType
        ParameterTypes = parameterTypes
        ReturnType = returnType
    }
}

// A name-keyed index of the extension methods exported by the referenced-assembly scan. Built once
// per compilation and cached on the external-type catalog: later member-call resolution consults it
// without re-opening the scan or extending a per-feature whitelist.
class ColumnarExtensionMethodIndex {
    byName: Dictionary<string, List<ColumnarExtensionMethodCandidate>>

    constructor() {
        byName = new Dictionary<string, List<ColumnarExtensionMethodCandidate>>(StringComparer.Ordinal)
    }

    func Add(name: string, candidate: ColumnarExtensionMethodCandidate) {
        bucket := new List<ColumnarExtensionMethodCandidate>()
        if !byName.TryGetValue(name, out bucket) || bucket == null {
            bucket = new List<ColumnarExtensionMethodCandidate>()
            byName[name] = bucket
        }

        bucket.Add(candidate)
    }

    func TryGet(name: string, out candidates: List<ColumnarExtensionMethodCandidate>): bool {
        candidates = new List<ColumnarExtensionMethodCandidate>()
        return byName.TryGetValue(name, out candidates) && candidates != null
    }
}

// A selected extension binding for emission. ParameterTypes is the full declared list including the
// receiver at [0]; ExplicitArgumentCount is the number of supplied call arguments (never the
// receiver). Parameters beyond `1 + ExplicitArgumentCount` are filled from their metadata defaults.
class ColumnarExtensionMethodSelection {
    IsSelected: bool
    Method: MethodInfo?
    DeclaringType: Type
    ParameterTypes: Type[]
    ReturnType: Type
    ExplicitArgumentCount: int

    constructor(isSelected: bool, method: MethodInfo?, declaringType: Type, parameterTypes: Type[], returnType: Type, explicitArgumentCount: int) {
        if declaringType == null || parameterTypes == null || returnType == null {
            throw new InvalidOperationException("Extension-method selection facts cannot be null.")
        }

        if isSelected && (method == null || parameterTypes.Length < 1 || explicitArgumentCount < 0 || explicitArgumentCount > parameterTypes.Length - 1) {
            throw new InvalidOperationException("A selected extension method requires an exact static handle and a valid explicit-argument count.")
        }

        IsSelected = isSelected
        Method = method
        DeclaringType = declaringType
        ParameterTypes = parameterTypes
        ReturnType = returnType
        ExplicitArgumentCount = explicitArgumentCount
    }

    static func None(): ColumnarExtensionMethodSelection {
        return new ColumnarExtensionMethodSelection(false, null, typeof(object), new Type[](0), typeof(object), 0)
    }
}

// Extension-method binding for member-style calls whose receiver type declares no matching instance
// method. Candidate discovery is metadata-exact ([ExtensionAttribute] on a public static method of a
// static class) over the referenced-assembly runtime scan; selection reuses the shared direct-call
// argument scoring so an extension and an ordinary call never disagree about conversion preference.
//
// This owner is intentionally narrow: reference-type receivers only, exact fixed arity or a
// trailing run of optional parameters whose metadata default is null. Generic candidates close by
// EXACT structural inference from the receiver and explicit argument types (`IEnumerable<int>`
// receiver -> Enumerable.Take<int>); partial inference, builder-bound type arguments,
// interface/variance receiver widening (`List<int>` against `IEnumerable<TSource>`), and
// trailing-optional filling on generic candidates all decline. Anything outside the admitted
// surface leaves the call to its later owner.
class ColumnarExtensionMethodResolver {
    static func ExtensionAttributeType(): Type? {
        return Type.GetType("System.Runtime.CompilerServices.ExtensionAttribute")
    }

    static func ParamArrayAttributeType(): Type? {
        return Type.GetType("System.ParamArrayAttribute")
    }

    static func BuildIndex(scan: ExternalAssemblyScanResult): ColumnarExtensionMethodIndex {
        index := new ColumnarExtensionMethodIndex()
        if scan == null || scan.Entries == null {
            return index
        }

        extensionAttribute := ExtensionAttributeType()
        paramArrayAttribute := ParamArrayAttributeType()
        if extensionAttribute == null || paramArrayAttribute == null {
            return index
        }

        entryIndex := 0
        while entryIndex < scan.Entries.Length {
            entry := scan.Entries[entryIndex]
            if entry != null && entry.RuntimeAssembly != null {
                AddAssembly(index, entry.RuntimeAssembly, extensionAttribute, paramArrayAttribute)
            }

            entryIndex = entryIndex + 1
        }

        return index
    }

    static func AddAssembly(index: ColumnarExtensionMethodIndex, assembly: Assembly, extensionAttribute: Type, paramArrayAttribute: Type) {
        types := ExportedTypesOrEmpty(assembly)
        typeIndex := 0
        while typeIndex < types.Length {
            candidateType := types[typeIndex]
            if IsStaticExtensionHost(candidateType, extensionAttribute) {
                AddType(index, candidateType, extensionAttribute, paramArrayAttribute)
            }

            typeIndex = typeIndex + 1
        }
    }

    static func AddType(index: ColumnarExtensionMethodIndex, hostType: Type, extensionAttribute: Type, paramArrayAttribute: Type) {
        methods := MethodsOrEmpty(hostType)
        methodIndex := 0
        while methodIndex < methods.Length {
            method := methods[methodIndex]
            if IsExtensionMethodCandidate(method, extensionAttribute) {
                parameters := method.GetParameters()
                if parameters != null && parameters.Length >= 1 && !HasExcludedParameterShape(parameters, paramArrayAttribute) {
                    parameterTypes := ParameterTypesOrNull(parameters)
                    returnType := method.get_ReturnType()
                    if parameterTypes != null && returnType != null && IsSupportedReceiverParameter(parameterTypes[0]) {
                        index.Add(method.get_Name(), new ColumnarExtensionMethodCandidate(method, hostType, parameterTypes, returnType))
                    }
                }
            }

            methodIndex = methodIndex + 1
        }
    }

    static func IsStaticExtensionHost(candidateType: Type, extensionAttribute: Type): bool {
        return candidateType != null
            && candidateType.get_IsClass()
            && candidateType.get_IsSealed()
            && candidateType.get_IsAbstract()
            && !candidateType.get_IsGenericType()
            && SafeIsDefined(candidateType, extensionAttribute)
    }

    static func IsExtensionMethodCandidate(method: MethodInfo, extensionAttribute: Type): bool {
        if method == null || !method.get_IsStatic() || !method.get_IsPublic() {
            return false
        }

        // Generic extension methods are indexed only as OPEN definitions; resolution closes them by
        // receiver/argument inference. A partially constructed generic method is never a candidate.
        if method.get_IsGenericMethod() && !method.get_IsGenericMethodDefinition() {
            return false
        }

        return SafeIsDefined(method, extensionAttribute)
    }

    static func HasExcludedParameterShape(parameters: ParameterInfo[], paramArrayAttribute: Type): bool {
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter == null {
                return true
            }

            parameterType := parameter.get_ParameterType()
            if parameterType == null || parameterType.get_IsByRef() || parameterType.get_IsPointer() {
                return true
            }

            if SafeIsDefined(parameter, paramArrayAttribute) {
                return true
            }

            index = index + 1
        }

        return false
    }

    static func IsSupportedReceiverParameter(receiverParameterType: Type): bool {
        return receiverParameterType != null
            && !receiverParameterType.get_IsValueType()
            && !receiverParameterType.get_IsByRef()
            && !receiverParameterType.get_IsPointer()
            && !receiverParameterType.get_IsGenericParameter()
    }

    static func ParameterTypesOrNull(parameters: ParameterInfo[]): Type[]? {
        result := new Type[](parameters.Length)
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter == null {
                return null
            }

            parameterType := parameter.get_ParameterType()
            if parameterType == null {
                return null
            }

            result[index] = parameterType
            index = index + 1
        }

        return result
    }

    static func ExportedTypesOrEmpty(assembly: Assembly): Type[] {
        try {
            result := assembly.GetExportedTypes()
            if result == null {
                return new Type[](0)
            }

            return result
        } catch {
            // A referenced assembly whose exported surface cannot be enumerated (missing transitive
            // dependency, unreadable image) contributes no extension methods.
            return new Type[](0)
        }
    }

    static func MethodsOrEmpty(hostType: Type): MethodInfo[] {
        try {
            result := hostType.GetMethods()
            if result == null {
                return new MethodInfo[](0)
            }

            return result
        } catch {
            return new MethodInfo[](0)
        }
    }

    static func SafeIsDefined(candidateType: Type, attributeType: Type): bool {
        try {
            return candidateType.IsDefined(attributeType, false)
        } catch {
            return false
        }
    }

    static func SafeIsDefined(method: MethodInfo, attributeType: Type): bool {
        try {
            return method.IsDefined(attributeType, false)
        } catch {
            return false
        }
    }

    static func SafeIsDefined(parameter: ParameterInfo, attributeType: Type): bool {
        try {
            return parameter.IsDefined(attributeType, false)
        } catch {
            return false
        }
    }

    // Select the single best extension method for `receiver.memberName(args...)`. Ranking mirrors the
    // ordinary call resolver: exact conversion beats a weaker one, among equal-conversion matches the
    // fewest total parameters (least optional filling) wins, and at a full tie a non-generic candidate
    // beats an inference-closed generic one (the CLR's less-generic-is-better rule). Any remaining tie
    // declines.
    static func Resolve(index: ColumnarExtensionMethodIndex, receiverType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): ColumnarExtensionMethodSelection {
        if index == null || receiverType == null || memberName == null || argumentTypes == null || argumentFacts == null {
            return ColumnarExtensionMethodSelection.None()
        }

        if receiverType.get_IsValueType() || receiverType.get_IsByRef() || receiverType.get_IsPointer() || receiverType.get_IsGenericParameter() {
            return ColumnarExtensionMethodSelection.None()
        }

        candidates := new List<ColumnarExtensionMethodCandidate>()
        if !index.TryGet(memberName, out candidates) {
            return ColumnarExtensionMethodSelection.None()
        }

        explicitCount := argumentTypes.Length
        bestScore := -1
        bestParameterCount := 0
        bestIsGeneric := false
        bestCount := 0
        selected: ColumnarExtensionMethodCandidate? = null
        candidateIndex := 0
        while candidateIndex < candidates.Count {
            indexed := candidates[candidateIndex]
            candidate: ColumnarExtensionMethodCandidate? = null
            if indexed != null {
                candidate = ResolveCandidateShape(indexed, receiverType, argumentTypes, explicitCount)
            }

            if candidate != null && CandidateAppliesToReceiver(candidate, receiverType) {
                parameterTypes := candidate.ParameterTypes
                if parameterTypes.Length - 1 >= explicitCount && TrailingDefaultsFillable(candidate.Method, parameterTypes, 1 + explicitCount) {
                    leading := ExplicitParameterTypes(parameterTypes, explicitCount)
                    score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(leading, argumentTypes, argumentFacts)
                    if score >= 0 {
                        parameterCount := parameterTypes.Length
                        candidateIsGeneric := candidate.Method.get_IsGenericMethod()
                        if score > bestScore
                            || (score == bestScore && parameterCount < bestParameterCount)
                            || (score == bestScore && parameterCount == bestParameterCount && bestIsGeneric && !candidateIsGeneric) {
                            bestScore = score
                            bestParameterCount = parameterCount
                            bestIsGeneric = candidateIsGeneric
                            bestCount = 1
                            selected = candidate
                        } else if score == bestScore && parameterCount == bestParameterCount && bestIsGeneric == candidateIsGeneric {
                            bestCount = bestCount + 1
                        }
                    }
                }
            }

            candidateIndex = candidateIndex + 1
        }

        if bestCount != 1 || selected == null {
            return ColumnarExtensionMethodSelection.None()
        }

        return new ColumnarExtensionMethodSelection(true, selected.Method, selected.DeclaringType, selected.ParameterTypes, selected.ReturnType, explicitCount)
    }

    // A non-generic candidate resolves as itself. A generic method DEFINITION resolves by inferring
    // EVERY method type argument from the receiver and explicit argument types, then closing the
    // definition into an exact runtime handle. The generic surface is deliberately exact: the arity
    // must match with no optional filling, inference is structural unification only, and a closure
    // the runtime rejects (a violated constraint) is not a candidate.
    static func ResolveCandidateShape(candidate: ColumnarExtensionMethodCandidate, receiverType: Type, argumentTypes: Type[], explicitCount: int): ColumnarExtensionMethodCandidate? {
        method := candidate.Method
        if !method.get_IsGenericMethodDefinition() {
            return candidate
        }

        if candidate.ParameterTypes.Length - 1 != explicitCount {
            return null
        }

        typeParameters := method.GetGenericArguments()
        if typeParameters == null || typeParameters.Length == 0 {
            return null
        }

        inferred := new Type[](typeParameters.Length)
        if !TryUnifyCandidateSlot(candidate.ParameterTypes[0], receiverType, typeParameters, inferred) {
            return null
        }

        argumentIndex := 0
        while argumentIndex < explicitCount {
            if !TryUnifyCandidateSlot(candidate.ParameterTypes[argumentIndex + 1], argumentTypes[argumentIndex], typeParameters, inferred) {
                return null
            }

            argumentIndex = argumentIndex + 1
        }

        // Partial inference never closes, and a builder-bound type argument stays with later owners:
        // MakeGenericMethod over Reflection.Emit builders is outside this exact-handle surface.
        inferredIndex := 0
        while inferredIndex < inferred.Length {
            inferredArgument := inferred[inferredIndex]
            if inferredArgument == null || ColumnarRuntimeInstanceMemberResolver.ContainsBuilderBoundType(inferredArgument) {
                return null
            }

            inferredIndex = inferredIndex + 1
        }

        closedMethod: MethodInfo? = null
        try {
            closedMethod = method.MakeGenericMethod(inferred)
        } catch {
            return null
        }

        if closedMethod == null {
            return null
        }

        closedParameters := closedMethod.GetParameters()
        if closedParameters == null || closedParameters.Length != candidate.ParameterTypes.Length {
            return null
        }

        closedParameterTypes := ParameterTypesOrNull(closedParameters)
        if closedParameterTypes == null {
            return null
        }

        closedReturnType := closedMethod.get_ReturnType()
        if closedReturnType == null || closedReturnType.get_ContainsGenericParameters() {
            return null
        }

        return new ColumnarExtensionMethodCandidate(closedMethod, candidate.DeclaringType, closedParameterTypes, closedReturnType)
    }

    // Structural unification of one declared slot against one actual type. A slot without open
    // generic parameters carries no inference (ordinary scoring validates it); a naked method type
    // parameter binds its position exactly once; constructed shapes must carry the SAME generic
    // definition (or both be SZ arrays) and unify their arguments pairwise. Interface and variance
    // widening (`List<int>` against `IEnumerable<TSource>`) is deliberately outside this owner.
    static func TryUnifyCandidateSlot(parameterType: Type, actualType: Type, typeParameters: Type[], inferred: Type[]): bool {
        if parameterType == null || actualType == null {
            return false
        }

        if !parameterType.get_ContainsGenericParameters() {
            return true
        }

        if parameterType.get_IsGenericParameter() {
            position := MethodTypeParameterOrdinal(parameterType, typeParameters)
            if position < 0 {
                return false
            }

            existing := inferred[position]
            if existing == null {
                inferred[position] = actualType
                return true
            }

            return existing == actualType
        }

        if parameterType.get_IsSZArray() {
            if !actualType.get_IsSZArray() {
                return false
            }

            parameterElement := parameterType.GetElementType()
            actualElement := actualType.GetElementType()
            if parameterElement == null || actualElement == null {
                return false
            }

            return TryUnifyCandidateSlot(parameterElement, actualElement, typeParameters, inferred)
        }

        if !parameterType.get_IsGenericType() || !actualType.get_IsGenericType() {
            return false
        }

        if parameterType.GetGenericTypeDefinition() != actualType.GetGenericTypeDefinition() {
            return false
        }

        parameterArguments := parameterType.GetGenericArguments()
        actualArguments := actualType.GetGenericArguments()
        if parameterArguments.Length != actualArguments.Length {
            return false
        }

        pairIndex := 0
        while pairIndex < parameterArguments.Length {
            if !TryUnifyCandidateSlot(parameterArguments[pairIndex], actualArguments[pairIndex], typeParameters, inferred) {
                return false
            }

            pairIndex = pairIndex + 1
        }

        return true
    }

    // The definition's own generic arguments are the identity anchors for inference positions.
    static func MethodTypeParameterOrdinal(parameterType: Type, typeParameters: Type[]): int {
        ordinal := 0
        while ordinal < typeParameters.Length {
            if typeParameters[ordinal] == parameterType {
                return ordinal
            }

            ordinal = ordinal + 1
        }

        return -1
    }

    static func CandidateAppliesToReceiver(candidate: ColumnarExtensionMethodCandidate, receiverType: Type): bool {
        receiverParameterType := candidate.ReceiverParameterType
        return !receiverParameterType.get_IsValueType()
            && ReferenceAssignableFrom(receiverParameterType, receiverType)
    }

    // Explicit call arguments occupy the extension parameters after the receiver slot.
    static func ExplicitParameterTypes(parameterTypes: Type[], explicitCount: int): Type[] {
        result := new Type[](explicitCount)
        index := 0
        while index < explicitCount {
            result[index] = parameterTypes[index + 1]
            index = index + 1
        }

        return result
    }

    static func TrailingDefaultsFillable(method: MethodInfo, parameterTypes: Type[], startIndex: int): bool {
        parameters := method.GetParameters()
        if parameters == null || parameters.Length != parameterTypes.Length {
            return false
        }

        index := startIndex
        while index < parameterTypes.Length {
            if !CanFillOptional(parameters[index], parameterTypes[index]) {
                return false
            }

            index = index + 1
        }

        return true
    }

    // A trailing parameter is fillable only when it is optional, has a reference-type shape, and its
    // metadata default is the null reference. This is the exact form the Web API template needs
    // (`setupAction = null`, `url = null`); a value-type default or a non-null constant declines.
    static func CanFillOptional(parameter: ParameterInfo, resolvedType: Type): bool {
        if parameter == null || resolvedType == null || !parameter.get_IsOptional() {
            return false
        }

        if resolvedType.get_IsValueType() || resolvedType.get_IsByRef() || resolvedType.get_IsPointer() || resolvedType.get_IsGenericParameter() {
            return false
        }

        return DefaultIsNullReference(parameter)
    }

    static func DefaultIsNullReference(parameter: ParameterInfo): bool {
        try {
            return parameter.get_DefaultValue() == null
        } catch {
            // A parameter whose default value cannot be read is not a fillable null default.
            return false
        }
    }

    // Emit the null metadata default for a trailing optional parameter as `ldnull`. The executor
    // validates the resulting null-reference stack value against the exact reference parameter type.
    static func TryAppendOptionalDefault(plan: ColumnarCodePlan, parameter: ParameterInfo, resolvedType: Type): bool {
        if plan == null || !CanFillOptional(parameter, resolvedType) {
            return false
        }

        plan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ldnull())
        return true
    }

    static func ReferenceAssignableFrom(expectedType: Type, actualType: Type): bool {
        if expectedType == null || actualType == null {
            return false
        }

        if ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(expectedType, actualType) {
            return true
        }

        try {
            return expectedType.IsAssignableFrom(actualType)
        } catch {
            return false
        }
    }
}
