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
        candidateReturns := new List<Type>()
        AppendClosedCandidates(lookupType, memberName, argumentTypes, argumentFacts, candidates, candidateParameters, candidateReturns, expectedStatic)
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
            candidateReturns[selectedIndex],
            kind,
            expectedStatic,
            receiverIsReference,
            selected.get_IsAbstract()
        )
    }

    static func AppendClosedCandidates(lookupType: Type, memberName: string, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, candidates: List<MethodInfo>, candidateParameters: List<Type[]>, candidateReturns: List<Type>, expectedStatic: bool) {
        declared := MethodsOrEmpty(lookupType)
        index := 0
        while index < declared.Length {
            candidate := declared[index]
            if IsInferableCandidate(candidate, lookupType, memberName, argumentTypes.Length, expectedStatic) {
                inferred := InferTypeArgumentsOrNull(candidate, argumentTypes, argumentFacts)
                if inferred != null {
                    closed := CloseOrNull(candidate, inferred)
                    if closed != null {
                        closedParameters := ClosedParameterTypesOrNull(candidate, inferred)
                        closedReturn := SubstituteMethodTypeArguments(candidate.get_ReturnType(), inferred)
                        if closedParameters != null && closedReturn != null {

                            // The RETURN comes from the same substitution the parameters do, not from
                            // the closed wrapper's own `ReturnType`. A wrapper built over a
                            // builder-bound argument can report the raw `T` it was closed from, and
                            // the plan's declared signature must be the shape the CALL SITE sees.
                            candidates.Add(closed)
                            candidateParameters.Add(closedParameters)
                            candidateReturns.Add(closedReturn)
                        }
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
        if !IsInferableCandidateShape(candidate, lookupType, memberName, expectedStatic) {
            return false
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

    // The half of candidate admission that does not depend on the call site's ARGUMENTS: a public,
    // non-varargs generic method definition of this name and staticness, declared by the lookup type
    // or by something the lookup type derives from. The explicit-type-argument tier asks the same
    // question, so the two tiers cannot disagree about which declarations are reachable.
    static func IsInferableCandidateShape(candidate: MethodInfo?, lookupType: Type, memberName: string, expectedStatic: bool): bool {
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

    // The type arguments the candidate's parameters infer, or null when a type parameter stays
    // unbound or two positions disagree.
    static func InferTypeArgumentsOrNull(candidate: MethodInfo, argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts): Type[]? {
        genericParameters := candidate.GetGenericArguments()
        bindings := new Dictionary<int, Type>()
        parameters := candidate.GetParameters()
        index := 0
        while index < parameters.Length {

            // A `null` LITERAL CARRIES NO TYPE, so it contributes nothing to inference — ECMA-334
            // §12.6.3 says the same, and the recorded `object` placeholder is a stand-in for "unknown"
            // rather than an argument type. Unifying it would bind a parameter to `object` and then
            // refuse the position that knows the real answer, which is exactly what
            // `Interlocked.Exchange(ref remove, null)` did: `T` bound to the field's type from the
            // by-ref position and was then contradicted by the null.
            if argumentFacts.IsNullLiteral[index] {
                index = index + 1
                continue
            }

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

        return typeArguments
    }

    // The candidate closed over those arguments, or null when the declared constraints refuse the
    // instantiation. Closing over a SOURCE TYPE PARAMETER is a supported Reflection.Emit shape: the
    // answer is a `MethodBuilderInstantiation`, which `call` encodes as a MethodSpec over that
    // parameter and the CLR resolves once per constructed type.
    static func CloseOrNull(candidate: MethodInfo, typeArguments: Type[]): MethodInfo? {
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

    // A type argument the CLR cannot close a method over. `void`, a by-ref or pointer shape and a
    // still-open one are what reach here.
    static func IsUnbindableInferredType(argumentType: Type): bool {
        if argumentType.FullName == "System.Void" || argumentType.get_IsByRef() || argumentType.get_IsPointer() {
            return true
        }
        if IsEmittedTypeParameter(argumentType) {
            return false
        }

        // A SHAPE CLOSED OVER THE DECLARATION BEING EMITTED — `Action<THandler>` inside
        // `NSharpEventSubscription<THandler>`. It is "open" only in the sense that its argument is a
        // parameter of the type currently being written; at every instantiation it is a closed type,
        // and `MakeGenericMethod` over it is the same Reflection.Emit shape a bare source type
        // parameter already is. `CloseOrNull` is the arbiter: if Reflection refuses the
        // instantiation, the candidate is dropped there rather than guessed at here.
        if ColumnarRuntimeInstanceMemberResolver.ContainsBuilderBoundType(argumentType) {
            return false
        }

        return argumentType.get_ContainsGenericParameters()
    }

    // A TYPE PARAMETER OF THE DECLARATION BEING EMITTED — `TOk` inside `Result<TOk, TErr>`, or a
    // generic function's own `T`. Reflection.Emit closes a runtime generic method over one, so
    // `HashCode.Combine(state, ok)` inside a generic type is an ordinary MethodSpec rather than a
    // shape with no handle. It is the ONLY open type admitted here: every other unresolved shape
    // would produce a handle with no meaning at the call site.
    static func IsEmittedTypeParameter(candidateType: Type): bool {
        return candidateType != null && candidateType is GenericTypeParameterBuilder
    }

    // THE CLOSED SIGNATURE IS SUBSTITUTED, NOT READ BACK. For a runtime instantiation the two are the
    // same answer, so nothing changes for the tier's existing shapes. For a
    // `MethodBuilderInstantiation` they are not: its `GetParameters` reports the DEFINITION's own
    // `T1, T2`, and scoring a call against those would compare each argument to an unrelated type
    // parameter and select on noise.
    static func ClosedParameterTypesOrNull(definition: MethodInfo, typeArguments: Type[]): Type[]? {
        parameters := definition.GetParameters()
        result := new Type[](parameters.Length)
        index := 0
        while index < parameters.Length {
            parameterType := SubstituteMethodTypeArguments(parameters[index].get_ParameterType(), typeArguments)
            if parameterType == null || IsUnsupportedClosedSignatureType(parameterType) {
                return null
            }
            result[index] = parameterType
            index = index + 1
        }

        returnType := SubstituteMethodTypeArguments(definition.get_ReturnType(), typeArguments)
        if returnType == null || returnType.get_IsByRef() || returnType.get_IsPointer() {
            return null
        }
        // A return that is ITSELF a source type parameter is a value the emitter can hold; one that
        // merely CONTAINS an open parameter (`List<T>`) is left to the tier that grows a call site.
        if !IsEmittedTypeParameter(returnType) && returnType.get_ContainsGenericParameters() {
            return null
        }
        return result
    }

    // A source type parameter is a legal closed signature type — the CLR resolves it per
    // instantiation. Everything else keeps the ordinary tier's answer.
    static func IsUnsupportedClosedSignatureType(signatureType: Type): bool {
        if IsEmittedTypeParameter(signatureType) {
            return false
        }

        // A closed PARAMETER may be `ref`/`out` — `Interlocked.Exchange<T>(ref T, T)` closes to
        // `(ref Action, Action)` and that is the whole shape. The element is asked the ordinary
        // question; a by-ref of a by-ref is not a signature the CLR can spell.
        return ColumnarOrdinaryRuntimeDirectCallResolver.IsUnsupportedParameterType(signatureType, new Type[](0))
    }

    // The definition's signature rewritten under the inferred arguments. Only the METHOD's own type
    // parameters are rewritten: a candidate is read off a CLOSED lookup type, so the declaring type's
    // parameters are already substituted before this walk sees them.
    static func SubstituteMethodTypeArguments(signatureType: Type?, typeArguments: Type[]): Type? {
        if signatureType == null {
            return null
        }

        if signatureType.get_IsGenericParameter() {
            if signatureType.get_DeclaringMethod() == null {
                return signatureType
            }
            position := signatureType.get_GenericParameterPosition()
            if position < 0 || position >= typeArguments.Length {
                return null
            }
            return typeArguments[position]
        }

        if !signatureType.get_ContainsGenericParameters() {
            return signatureType
        }

        if signatureType.get_IsByRef() {
            byRefElement := SubstituteMethodTypeArguments(signatureType.GetElementType(), typeArguments)
            if byRefElement == null {
                return null
            }
            return byRefElement.MakeByRefType()
        }

        if signatureType.get_IsArray() {
            // A multi-dimensional array is left to the tier that grows a call site for one; its rank
            // would have to be reconstructed, and no shape in the corpus asks for it.
            if !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(signatureType) {
                return null
            }
            arrayElement := SubstituteMethodTypeArguments(signatureType.GetElementType(), typeArguments)
            if arrayElement == null {
                return null
            }
            return arrayElement.MakeArrayType()
        }

        if !signatureType.get_IsGenericType() {
            return null
        }

        arguments := signatureType.GetGenericArguments()
        substituted := new Type[](arguments.Length)
        index := 0
        while index < arguments.Length {
            resolved := SubstituteMethodTypeArguments(arguments[index], typeArguments)
            if resolved == null {
                return null
            }
            substituted[index] = resolved
            index = index + 1
        }

        try {
            return signatureType.GetGenericTypeDefinition().MakeGenericType(substituted)
        } catch ex: ArgumentException {
            return null
        } catch ex: NotSupportedException {
            return null
        }
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

// ONE EXTERNAL METHOD SELECTED FOR A CALL SITE THAT WROTE ITS TYPE ARGUMENTS.
//
// `ExplicitArgumentCount` is how many of `ParameterTypes` the site supplies; every parameter from
// there on is a trailing optional filled from its null metadata default, exactly as the ordinary
// resolver's optional-fill tier does for a non-generic declaration.
class ColumnarExplicitGenericCallSelection {
    IsSelected: bool
    Method: MethodInfo?
    LookupType: Type
    ParameterTypes: Type[]
    ReturnType: Type
    ExplicitArgumentCount: int
    IsStatic: bool
    UsesCallVirtual: bool

    constructor(isSelected: bool, method: MethodInfo?, lookupType: Type, parameterTypes: Type[], returnType: Type, explicitArgumentCount: int, isStatic: bool, usesCallVirtual: bool) {
        if lookupType == null || parameterTypes == null || returnType == null {
            throw new InvalidOperationException("Explicit generic call selection facts cannot be null.")
        }
        if isSelected && (method == null || explicitArgumentCount < 0 || explicitArgumentCount > parameterTypes.Length) {
            throw new InvalidOperationException("A selected explicit generic call requires an exact handle and a supplied-argument count within its signature.")
        }
        if !isSelected && (method != null || parameterTypes.Length != 0) {
            throw new InvalidOperationException("An unselected explicit generic call cannot carry executable method facts.")
        }

        IsSelected = isSelected
        Method = method
        LookupType = lookupType
        ParameterTypes = parameterTypes
        ReturnType = returnType
        ExplicitArgumentCount = explicitArgumentCount
        IsStatic = isStatic
        UsesCallVirtual = usesCallVirtual
    }

    static func None(lookupType: Type): ColumnarExplicitGenericCallSelection {
        return new ColumnarExplicitGenericCallSelection(false, null, lookupType, new Type[](0), typeof(object), 0, false, false)
    }
}

// EXTERNAL GENERIC METHODS, CLOSED OVER THE TYPE ARGUMENTS THE CALL SITE WROTE.
//
// This is the explicit twin of the inference tier above, and the ONLY difference between them is
// where the type arguments come from: written by the site instead of unified from the arguments.
// Everything after that is the same answer — `MakeGenericMethod` enforces the declared constraints,
// the closed signature is SUBSTITUTED rather than read back, and the resulting handle is an ordinary
// MethodInfo the call site emits with an ordinary `call`/`callvirt`.
//
// THE WRITTEN COUNT MUST MATCH THE DECLARATION'S ARITY (ECMA-334 §12.6.4.1): a candidate whose own
// arity differs is not a candidate at all, so `Is<int, string>()` on `Is<T>()` never binds and the
// call site reports the ordinary "no overload" arity diagnostic instead of closing something wrong.
class ColumnarExplicitRuntimeGenericMethodResolver {

    // The unique candidate for a site whose ARGUMENT TYPES are not all knowable ahead of emission — a
    // lambda argument has no type until it is bound against the parameter it is passed to. A name
    // that leaves more than one closed candidate at this arity is left to the scored overload below.
    static func Resolve(lookupType: Type, memberName: string, typeArguments: Type[], argumentCount: int, expectedStatic: bool): ColumnarExplicitGenericCallSelection {
        candidates := new List<MethodInfo>()
        candidateParameters := new List<Type[]>()
        candidateReturns := new List<Type>()
        if !TryCollect(lookupType, memberName, typeArguments, argumentCount, expectedStatic, candidates, candidateParameters, candidateReturns) {
            return ColumnarExplicitGenericCallSelection.None(lookupType)
        }

        if candidates.Count != 1 {
            return ColumnarExplicitGenericCallSelection.None(lookupType)
        }

        return Selected(lookupType, candidates[0], candidateParameters[0], candidateReturns[0], argumentCount, expectedStatic)
    }

    // The same candidate set, ranked by the argument-flow scorer every other call selection uses. A
    // site whose arguments all type ahead of emission gets ordinary overload resolution; a tie is
    // refused rather than guessed.
    static func ResolveWithFacts(lookupType: Type, memberName: string, typeArguments: Type[], argumentTypes: Type[], argumentFacts: ColumnarDirectCallArgumentFacts, expectedStatic: bool): ColumnarExplicitGenericCallSelection {
        if argumentTypes == null {
            throw new InvalidOperationException("Explicit generic method resolution inputs cannot be null.")
        }
        ColumnarSourceDirectCallResolver.ValidateArgumentFacts(argumentTypes, argumentFacts)

        candidates := new List<MethodInfo>()
        candidateParameters := new List<Type[]>()
        candidateReturns := new List<Type>()
        if !TryCollect(lookupType, memberName, typeArguments, argumentTypes.Length, expectedStatic, candidates, candidateParameters, candidateReturns) {
            return ColumnarExplicitGenericCallSelection.None(lookupType)
        }

        bestScore := -1
        bestParameterCount := 0
        bestCount := 0
        bestIndex := -1
        index := 0
        while index < candidates.Count {
            parameterTypes := candidateParameters[index]
            leading := LeadingParameterTypes(parameterTypes, argumentTypes.Length)
            score := ColumnarSourceDirectCallResolver.ArgumentsScoreWithFacts(leading, argumentTypes, argumentFacts)
            if score >= 0 {
                parameterCount := parameterTypes.Length
                if score > bestScore || (score == bestScore && parameterCount < bestParameterCount) {
                    bestScore = score
                    bestParameterCount = parameterCount
                    bestCount = 1
                    bestIndex = index
                } else if score == bestScore && parameterCount == bestParameterCount {
                    bestCount = bestCount + 1
                }
            }
            index = index + 1
        }

        if bestCount != 1 || bestIndex < 0 {
            return ColumnarExplicitGenericCallSelection.None(lookupType)
        }

        return Selected(lookupType, candidates[bestIndex], candidateParameters[bestIndex], candidateReturns[bestIndex], argumentTypes.Length, expectedStatic)
    }

    // Every declared generic method of `lookupType` whose name, staticness, own arity and parameter
    // count admit this site, closed over the written type arguments. A candidate that
    // `MakeGenericMethod` refuses (a violated constraint) is dropped here, which is what makes a
    // constraint violation a "no such call" answer rather than an exception at emit.
    static func TryCollect(lookupType: Type, memberName: string, typeArguments: Type[], argumentCount: int, expectedStatic: bool, candidates: List<MethodInfo>, candidateParameters: List<Type[]>, candidateReturns: List<Type>): bool {
        if lookupType == null || memberName == null || typeArguments == null || typeArguments.Length == 0 || argumentCount < 0 {
            throw new InvalidOperationException("Explicit generic method resolution inputs cannot be null.")
        }

        // The same owner boundary the inference tier keeps: a builder-bound or still-open lookup type
        // has no reachable member table, and closing a method on one would need the TYPE's arguments
        // bound at the same time.
        if ColumnarRuntimeInstanceMemberResolver.ContainsBuilderBoundType(lookupType) || lookupType.get_IsGenericTypeDefinition() || lookupType.get_IsGenericParameter() {
            return false
        }

        position := 0
        while position < typeArguments.Length {
            if typeArguments[position] == null {
                return false
            }
            position = position + 1
        }

        declared := ColumnarRuntimeGenericMethodResolver.MethodsOrEmpty(lookupType)
        exactArity := false
        index := 0
        while index < declared.Length {
            candidate := declared[index]
            parameters := AdmittedParameters(candidate, lookupType, memberName, typeArguments.Length, argumentCount, expectedStatic)
            if parameters != null {
                closed := ColumnarRuntimeGenericMethodResolver.CloseOrNull(candidate, typeArguments)
                closedParameters := ColumnarRuntimeGenericMethodResolver.ClosedParameterTypesOrNull(candidate, typeArguments)
                closedReturn := ColumnarRuntimeGenericMethodResolver.SubstituteMethodTypeArguments(candidate.get_ReturnType(), typeArguments)
                if closed != null && closedParameters != null && closedReturn != null && TailFillable(parameters, closedParameters, argumentCount) {
                    candidates.Add(closed)
                    candidateParameters.Add(closedParameters)
                    candidateReturns.Add(closedReturn)
                    if closedParameters.Length == argumentCount {
                        exactArity = true
                    }
                }
            }
            index = index + 1
        }

        // AN EXACTLY-MATCHING ARITY BEATS A FILLED TAIL, which is C#'s rule and the ordinary
        // resolver's: optional-fill is only consulted when nothing takes the arguments as written.
        if exactArity {
            keep := 0
            while keep < candidateParameters.Count {
                if candidateParameters[keep].Length == argumentCount {
                    keep = keep + 1
                } else {
                    candidates.RemoveAt(keep)
                    candidateParameters.RemoveAt(keep)
                    candidateReturns.RemoveAt(keep)
                }
            }
        }

        return candidates.Count > 0
    }

    // The candidate's parameters when its shape admits this site, or null. The exclusions are the
    // inference tier's, plus the written-arity rule.
    static func AdmittedParameters(candidate: MethodInfo?, lookupType: Type, memberName: string, typeArgumentCount: int, argumentCount: int, expectedStatic: bool): ParameterInfo[]? {
        if !ColumnarRuntimeGenericMethodResolver.IsInferableCandidateShape(candidate, lookupType, memberName, expectedStatic) {
            return null
        }
        if candidate.GetGenericArguments().Length != typeArgumentCount {
            return null
        }

        parameters := candidate.GetParameters()
        if parameters == null || parameters.Length < argumentCount {
            return null
        }
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            if parameter == null || parameter.get_ParameterType() == null || ColumnarExtensionMethodResolver.IsParamsParameter(parameter) {
                return null
            }
            index = index + 1
        }
        return parameters
    }

    static func TailFillable(parameters: ParameterInfo[], closedParameters: Type[], argumentCount: int): bool {
        if parameters.Length != closedParameters.Length {
            return false
        }
        index := argumentCount
        while index < closedParameters.Length {
            if !ColumnarExtensionMethodResolver.CanFillOptional(parameters[index], closedParameters[index]) {
                return false
            }
            index = index + 1
        }
        return true
    }

    static func LeadingParameterTypes(parameterTypes: Type[], count: int): Type[] {
        if parameterTypes.Length == count {
            return parameterTypes
        }
        leading := new Type[](count)
        index := 0
        while index < count {
            leading[index] = parameterTypes[index]
            index = index + 1
        }
        return leading
    }

    static func Selected(lookupType: Type, method: MethodInfo, parameterTypes: Type[], returnType: Type, argumentCount: int, expectedStatic: bool): ColumnarExplicitGenericCallSelection {
        usesCallVirtual := !expectedStatic && !lookupType.get_IsValueType()
        return new ColumnarExplicitGenericCallSelection(true, method, lookupType, parameterTypes, returnType, argumentCount, expectedStatic, usesCallVirtual)
    }
}
