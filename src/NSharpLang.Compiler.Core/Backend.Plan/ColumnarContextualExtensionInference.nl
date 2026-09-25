namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection


// METHOD TYPE INFERENCE FOR AN EXTENSION CALL WHOSE ARGUMENTS INCLUDE LAMBDAS.
//
// `ColumnarExtensionMethodResolver.Resolve` answers when every argument already HAS a type. A lambda
// does not: it has no type until the delegate it is passed to is known, and the delegate is one of
// the things being inferred. That circularity is what C# resolves in two phases, and this owner is
// those two phases for the emission side:
//
//   PHASE ONE fixes what the non-lambda arguments and the RECEIVER can fix. The receiver counts —
//   `values.Count(v => ...)` fixes `TSource` from `List<string>` against `IEnumerable<TSource>`, and
//   everything the predicate needs follows from it.
//   PHASE TWO takes each lambda whose delegate INPUT types are now fixed, analyses its body under
//   those inputs, and folds the body's type into the delegate's RETURN position. That can fix a type
//   parameter a later lambda needs, so it repeats until nothing changes.
//
// A lambda whose inputs are still open when the loop stops is not inferable and the candidate does
// not bind. That is a decline, never a guess: emitting a delegate whose signature was guessed
// produces IL that corrupts memory when it is invoked.
//
// THE RECEIVER SLOT WIDENS AND THE ARGUMENT SLOTS DO NOT — the same asymmetry C# has. An extension's
// receiver parameter is matched against the receiver through its INTERFACES and its base chain
// (`List<string>` is an `IEnumerable<string>`), because that is how every sequence extension in the
// framework is declared. An ordinary argument position unifies structurally.
//
// NOTHING HERE NAMES A METHOD. There is no table of LINQ members, no per-API arity list and no
// element-type special case: the candidates come from the referenced-assembly extension index, the
// positions come from the candidate's own signature, and the delegate shapes come from the delegate
// types' own `Invoke`. A new extension in a referenced assembly works on the day it is referenced.
class ColumnarContextualExtensionBinding {
    Candidate: ColumnarExtensionMethodCandidate
    TypeParameters: Type[]
    Inferred: Type[]
    ArgumentCount: int

    // WHERE THE WRITTEN ARGUMENTS START IN THE DECLARED PARAMETER LIST. An EXTENSION spends its
    // first parameter on the receiver, so its explicit arguments begin at one; an ordinary static or
    // instance method spends none, so they begin at zero. That single number is the whole difference
    // between the three call shapes, which is why there is one inference owner and not three.
    ParameterOffset: int

    // A LAMBDA GIVEN TO A `void` DELEGATE WHOSE BODY HAD A VALUE TO GIVE. `Task.Run(() => 42)`
    // matches both `Run(Action)` and `Run<TResult>(Func<TResult>)`; C# prefers the one that does not
    // throw the body's value away, and this count is how that preference is expressed.
    DiscardedLambdaResults: int

    constructor(candidate: ColumnarExtensionMethodCandidate, typeParameters: Type[], inferred: Type[], argumentCount: int, parameterOffset: int) {
        Candidate = candidate
        TypeParameters = typeParameters
        Inferred = inferred
        ArgumentCount = argumentCount
        ParameterOffset = parameterOffset
        DiscardedLambdaResults = 0
    }

    // The DECLARED type of explicit argument `index`, still open.
    func OpenArgumentType(index: int): Type {
        return Candidate.ParameterTypes[index + ParameterOffset]
    }
}

class ColumnarContextualExtensionInference {

    // Every extension candidate exported under `memberName`, in the index's own order. An absent
    // name is an empty list rather than a null one: "no candidate" is an ordinary answer here.
    static func Candidates(index: ColumnarExtensionMethodIndex?, memberName: string?): List<ColumnarExtensionMethodCandidate> {
        empty := new List<ColumnarExtensionMethodCandidate>()
        if index == null || memberName == null {
            return empty
        }

        bucket := new List<ColumnarExtensionMethodCandidate>()
        if !index.TryGet(memberName, out bucket) || bucket == null {
            return empty
        }

        return bucket
    }

    // PHASE ONE, OPENED: the candidate's arity is checked and its RECEIVER slot is unified. A
    // non-generic candidate has nothing to infer and still opens, because the argument loop that
    // follows is the same walk either way.
    static func TryBegin(candidate: ColumnarExtensionMethodCandidate?, receiverType: Type, argumentCount: int, out binding: ColumnarContextualExtensionBinding?): bool {
        binding = null
        if candidate == null || receiverType == null || argumentCount < 0 {
            return false
        }

        method := candidate.Method
        if candidate.ParameterTypes.Length != argumentCount + 1 {
            return false
        }

        // A VALUE RECEIVER ARRIVES AT THIS TIER ALREADY PUSHED, and whether it was pushed as a value
        // or as a managed pointer was decided by the member-access walk above, which asked the
        // question about an INSTANCE call. A value-type receiver slot is therefore resolved where the
        // receiver's own push is still in this owner's hands — the explicit-type-argument path — and
        // not here.
        if candidate.ReceiverParameterType.IsValueType {
            return false
        }

        typeParameters := new Type[](0)
        if method.IsGenericMethodDefinition {
            declared := method.GetGenericArguments()
            if declared == null || declared.Length == 0 {
                return false
            }

            typeParameters = declared
        }

        inferred := new Type[](typeParameters.Length)
        if !TryUnifyReceiver(candidate.ParameterTypes[0], receiverType, typeParameters, inferred) {
            return false
        }

        binding = new ColumnarContextualExtensionBinding(candidate, typeParameters, inferred, argumentCount, 1)
        return true
    }

    // PHASE ONE, OPENED FOR A CALL THAT SPENDS NO PARAMETER ON ITS RECEIVER — an ordinary static
    // method, or an instance method whose receiver is the object itself. The only difference from
    // the extension form is the offset; everything after this point is identical, which is the
    // point.
    static func TryBeginDirect(method: MethodInfo?, argumentCount: int, out binding: ColumnarContextualExtensionBinding?): bool {
        binding = null
        if method == null || argumentCount < 1 {
            return false
        }

        // A REFERENCED TYPE'S SIGNATURE MAY NOT BE READABLE AT ALL — a parameter whose type lives in
        // an assembly the reference set does not carry throws while it is being materialised — so
        // every read here is guarded and an unreadable candidate is simply not a candidate.
        parameters := ColumnarExtensionMethodResolver.ParametersOrNull(method)
        if parameters == null || parameters.Length != argumentCount {
            return false
        }

        parameterTypes := ColumnarExtensionMethodResolver.ParameterTypesOrNull(parameters)
        if parameterTypes == null {
            return false
        }

        typeParameters := new Type[](0)
        if method.IsGenericMethodDefinition {
            declared := method.GetGenericArguments()
            if declared == null || declared.Length == 0 {
                return false
            }

            typeParameters = declared
        }

        declaringType := method.DeclaringType
        if declaringType == null {
            return false
        }

        returnType := ColumnarExtensionMethodResolver.ReturnTypeOrNull(method)
        if returnType == null {
            return false
        }

        candidate := new ColumnarExtensionMethodCandidate(method, declaringType, parameterTypes, returnType)
        binding = new ColumnarContextualExtensionBinding(candidate, typeParameters, new Type[](typeParameters.Length), argumentCount, 0)
        return true
    }

    // PHASE ONE, ONE ARGUMENT: an argument whose type is already known unifies against its declared
    // slot. A slot with nothing open in it carries no inference and the ordinary argument match
    // validates it later, exactly as it does for a non-generic candidate.
    static func TryUnifyArgument(binding: ColumnarContextualExtensionBinding, index: int, argumentType: Type): bool {
        if binding == null || argumentType == null || index < 0 || index >= binding.ArgumentCount {
            return false
        }

        return TryUnifySlot(binding.OpenArgumentType(index), argumentType, binding.TypeParameters, binding.Inferred)
    }

    // THE INPUT TYPES A LAMBDA IN THIS POSITION WOULD BE ANALYSED UNDER, or a decline while any of
    // them is still open. This is the phase-two readiness test and the phase-two operand at once.
    static func TryGetLambdaInputTypes(binding: ColumnarContextualExtensionBinding, index: int, out inputTypes: Type[]): bool {
        inputTypes = new Type[](0)
        if binding == null || index < 0 || index >= binding.ArgumentCount {
            return false
        }

        openDelegateType := DelegateTargetType(binding.OpenArgumentType(index))
        openParameters := new Type[](0)
        openReturn := typeof(object)
        if !TryReadOpenDelegateSignature(openDelegateType, out openParameters, out openReturn) {
            return false
        }

        closed := new Type[](openParameters.Length)
        position := 0
        while position < openParameters.Length {
            substituted := Substitute(openParameters[position], binding.TypeParameters, binding.Inferred)
            if substituted == null {
                return false
            }

            closed[position] = substituted
            position = position + 1
        }

        inputTypes = closed
        return true
    }

    // PHASE TWO, ONE LAMBDA: the body's type folds into the delegate's RETURN position. A delegate
    // that returns `void` accepts any body and contributes nothing, which is how an `Action` overload
    // stays a candidate.
    static func TryUnifyLambdaReturn(binding: ColumnarContextualExtensionBinding, index: int, lambdaReturnType: Type): bool {
        if binding == null || lambdaReturnType == null || index < 0 || index >= binding.ArgumentCount {
            return false
        }

        openDelegateType := DelegateTargetType(binding.OpenArgumentType(index))
        openParameters := new Type[](0)
        openReturn := typeof(object)
        if !TryReadOpenDelegateSignature(openDelegateType, out openParameters, out openReturn) {
            return false
        }

        if !openReturn.ContainsGenericParameters {
            return true
        }

        return TryUnifySlot(openReturn, lambdaReturnType, binding.TypeParameters, binding.Inferred)
    }

    // The signature a METHOD GROUP argument carries, folded into the same two positions a lambda's
    // is. A method group is a value whose type is a signature, so it fixes both the delegate's
    // inputs and its return; nothing about the fold depends on how the signature was written.
    static func TryUnifyMethodGroup(binding: ColumnarContextualExtensionBinding, index: int, parameterTypes: Type[], returnType: Type): bool {
        if binding == null || parameterTypes == null || returnType == null || index < 0 || index >= binding.ArgumentCount {
            return false
        }

        openDelegateType := DelegateTargetType(binding.OpenArgumentType(index))
        openParameters := new Type[](0)
        openReturn := typeof(object)
        if !TryReadOpenDelegateSignature(openDelegateType, out openParameters, out openReturn) {
            return false
        }

        if openParameters.Length != parameterTypes.Length {
            return false
        }

        position := 0
        while position < openParameters.Length {
            if !TryUnifySlot(openParameters[position], parameterTypes[position], binding.TypeParameters, binding.Inferred) {
                return false
            }

            position = position + 1
        }

        if !openReturn.ContainsGenericParameters {
            return true
        }

        return TryUnifySlot(openReturn, returnType, binding.TypeParameters, binding.Inferred)
    }

    // THE DELEGATE'S RETURN POSITION, CLOSED — or a decline while it is still open. A position that
    // is already closed is not an inference site: the lambda's body must MATCH it, which is what
    // separates `Sum(x => x.Length)`'s `Func<TSource, int>` from its `Func<TSource, double>` sibling.
    static func TryGetClosedDelegateReturn(binding: ColumnarContextualExtensionBinding, index: int, out returnType: Type): bool {
        returnType = typeof(object)
        if binding == null || index < 0 || index >= binding.ArgumentCount {
            return false
        }

        openParameters := new Type[](0)
        openReturn := typeof(object)
        if !TryReadOpenDelegateSignature(DelegateTargetType(binding.OpenArgumentType(index)), out openParameters, out openReturn) {
            return false
        }

        closed := Substitute(openReturn, binding.TypeParameters, binding.Inferred)
        if closed == null {
            return false
        }

        returnType = closed
        return true
    }

    // Whether this argument position wants a DELEGATE at all — the question that decides whether a
    // lambda or a method group written there is even a candidate.
    static func IsDelegatePosition(binding: ColumnarContextualExtensionBinding, index: int): bool {
        if binding == null || index < 0 || index >= binding.ArgumentCount {
            return false
        }

        openParameters := new Type[](0)
        openReturn := typeof(object)
        return TryReadOpenDelegateSignature(DelegateTargetType(binding.OpenArgumentType(index)), out openParameters, out openReturn)
    }

    // Whether every type parameter has an answer. The loop that drives the phases stops on this.
    static func IsFullyInferred(binding: ColumnarContextualExtensionBinding): bool {
        if binding == null {
            return false
        }

        for inferredItem2 in binding.Inferred {
            if inferredItem2 == null {
                return false
            }
        }

        return true
    }

    // THE CLOSED CANDIDATE, or a decline. The definition is closed over the inference and the
    // runtime is asked to build the handle: a violated constraint throws there and is a non-binding,
    // never an emitted call the CLR would refuse to verify.
    //
    // A TYPE ARGUMENT THE COMPILATION IS ITSELF WRITING closes here as readily as a runtime one.
    // `items.First()` over a `List<Query>` fixes `TSource` to the `TypeBuilder` for the source class
    // `Query`, and `MakeGenericMethod` answers that with a `MethodBuilderInstantiation` — the same
    // shape `ColumnarRuntimeGenericMethodResolver` already emits for `JsonSerializer.Deserialize<Request>`.
    // The one thing that shape CANNOT do is report its own signature: its `GetParameters` reports the
    // DEFINITION's `TSource`, so the closed signature is SUBSTITUTED from the declaration rather than
    // read back off the handle. For a runtime instantiation the two are the same answer, which is why
    // this is one path and not two.
    static func TryClose(binding: ColumnarContextualExtensionBinding, out closed: ColumnarExtensionMethodCandidate?): bool {
        closed = null
        if binding == null {
            return false
        }

        candidate := binding.Candidate
        if binding.TypeParameters.Length == 0 {
            closed = candidate
            return true
        }

        if !IsFullyInferred(binding) {
            return false
        }

        for inferredItem2 in binding.Inferred {
            if ColumnarRuntimeGenericMethodResolver.IsUnbindableInferredType(inferredItem2) {
                return false
            }
        }

        closedMethod: MethodInfo? = null
        try {
            closedMethod = candidate.Method.MakeGenericMethod(binding.Inferred)
        } catch {
            return false
        }

        if closedMethod == null {
            return false
        }

        closedParameterTypes := new Type[](candidate.ParameterTypes.Length)
        parameterIndex := 0
        while parameterIndex < candidate.ParameterTypes.Length {
            substituted := Substitute(candidate.ParameterTypes[parameterIndex], binding.TypeParameters, binding.Inferred)
            if substituted == null {
                return false
            }

            closedParameterTypes[parameterIndex] = substituted
            parameterIndex = parameterIndex + 1
        }

        closedReturnType := Substitute(candidate.ReturnType, binding.TypeParameters, binding.Inferred)
        if closedReturnType == null || closedReturnType.ContainsGenericParameters {
            return false
        }

        closed = new ColumnarExtensionMethodCandidate(closedMethod, candidate.DeclaringType, closedParameterTypes, closedReturnType)
        return true
    }

    // An expression-tree target names its delegate one level in. Everything else IS its delegate.
    static func DelegateTargetType(parameterType: Type): Type {
        if !parameterType.IsGenericType {
            return parameterType
        }

        definition := parameterType.GetGenericTypeDefinition()
        if definition.FullName != "System.Linq.Expressions.Expression`1" {
            return parameterType
        }

        arguments := parameterType.GetGenericArguments()
        if arguments.Length != 1 {
            return parameterType
        }

        return arguments[0]
    }

    // A DELEGATE'S POSITIONS, READ WHILE IT IS STILL OPEN. `Func` and `Action` answer from their own
    // type arguments because an instantiation over method type parameters is not always reflectable
    // through `Invoke`; every other delegate answers from `Invoke`, which is where a delegate's
    // signature actually lives. A type that is not a delegate at all declines.
    static func TryReadOpenDelegateSignature(delegateType: Type, out parameterTypes: Type[], out returnType: Type): bool {
        parameterTypes = new Type[](0)
        returnType = typeof(object)
        if delegateType == null || !IsDelegateShapedType(delegateType) {
            return false
        }

        if delegateType.IsGenericType {
            definition := delegateType.GetGenericTypeDefinition()
            definitionName := definition.FullName
            arguments := delegateType.GetGenericArguments()
            if NSharpLang.Compiler.AnalyzerFunctionTypeFactory.IsActionDefinitionName(definitionName) {
                parameterTypes = arguments
                returnType = ColumnarTypeOfPlanner.RequiredVoidType()
                return true
            }

            if NSharpLang.Compiler.AnalyzerFunctionTypeFactory.IsFuncDefinitionName(definitionName) && arguments.Length > 0 {
                leading := new Type[](arguments.Length - 1)
                index := 0
                while index < leading.Length {
                    leading[index] = arguments[index]
                    index = index + 1
                }

                parameterTypes = leading
                returnType = arguments[arguments.Length - 1]
                return true
            }
        }

        invoke: MethodInfo? = null
        try {
            invoke = delegateType.GetMethod("Invoke")
        } catch {
            return false
        }

        if invoke == null {
            return false
        }

        declared := ColumnarExtensionMethodResolver.ParameterTypesOrNull(ColumnarExtensionMethodResolver.ParametersOrNull(invoke) ?? new ParameterInfo[](0))
        if declared == null {
            return false
        }

        invokeReturnType := ColumnarExtensionMethodResolver.ReturnTypeOrNull(invoke)
        if invokeReturnType == null {
            return false
        }

        parameterTypes = declared
        returnType = invokeReturnType
        return true
    }

    // A delegate as METADATA sees it: the base chain reaches one of the two roots. The runtime
    // identity check the rest of the emitter uses cannot answer for an instantiation over method
    // type parameters, and this question is asked of exactly those.
    static func IsDelegateShapedType(candidate: Type): bool {
        current: Type? = BaseTypeOrNull(candidate)
        depth := 0
        while current != null && depth < 32 {
            fullName := current.FullName
            if fullName == "System.MulticastDelegate" || fullName == "System.Delegate" {
                return true
            }

            current = BaseTypeOrNull(current)
            depth = depth + 1
        }

        return false
    }

    // A base-type read that answers null rather than throwing, for the same reason every other read
    // over a referenced type does.
    static func BaseTypeOrNull(candidate: Type): Type? {
        try {
            return candidate.BaseType
        } catch {
            return null
        }
    }

    // THE RECEIVER SLOT, WIDENED. The declared receiver is matched against the receiver's own type
    // first; when the two name different generic definitions the receiver's INTERFACES and then its
    // base chain are searched for the one the declaration names, and the match is made against that.
    // `List<string>` therefore satisfies `IEnumerable<TSource>` and fixes `TSource` to `string`.
    static func TryUnifyReceiver(parameterType: Type, receiverType: Type, typeParameters: Type[], inferred: Type[]): bool {
        if TryUnifySlot(parameterType, receiverType, typeParameters, inferred) {
            return true
        }

        if !parameterType.IsGenericType {
            return false
        }

        implementation := FindClosedImplementation(receiverType, parameterType.GetGenericTypeDefinition())
        if implementation == null {
            return false
        }

        return TryUnifySlot(parameterType, implementation, typeParameters, inferred)
    }

    // The constructed form of `openDefinition` that `candidate` actually has — an interface it
    // implements or a base class it derives from. Interfaces are searched first, matching the CLR's
    // own resolution order, and an exact definition match on the type itself wins over both.
    static func FindClosedImplementation(candidate: Type, openDefinition: Type): Type? {
        if candidate.IsGenericType && candidate.GetGenericTypeDefinition() == openDefinition {
            return candidate
        }

        interfaces := new Type[](0)
        try {
            interfaces = candidate.GetInterfaces()
        } catch {
            interfaces = new Type[](0)
        }

        if interfaces != null {
            for implemented in interfaces {
                if InterfaceMatchesDefinition(implemented, openDefinition) {
                    return implemented
                }
            }
        }

        current: Type? = BaseTypeOrNull(candidate)
        depth := 0
        while current != null && depth < 64 {
            if current.IsGenericType && current.GetGenericTypeDefinition() == openDefinition {
                return current
            }

            if !openDefinition.IsGenericType && current == openDefinition {
                return current
            }

            current = BaseTypeOrNull(current)
            depth = depth + 1
        }

        arrayImplementation := FindClosedArrayImplementation(candidate, openDefinition)
        if arrayImplementation != null {
            return arrayImplementation
        }

        return FindClosedImplementationThroughDefinition(candidate, openDefinition)
    }

    // AN ARRAY IS A SEQUENCE OF ITS ELEMENT, AND THE CLR SAYS SO. A vector `E[]` implements the
    // one-parameter generic interfaces `object[]` implements — `IList<T>` and `IReadOnlyList<T>` and
    // everything those inherit — closed over `E`. `string[].GetInterfaces()` reports exactly that
    // list and the loop above already reads it; an array whose ELEMENT is a type this compilation is
    // writing (`Query[]`) cannot be asked, so the list is read off the CLR's own `object[]` instead
    // of written down here. Nothing names an interface, so a framework that adds one to the vector
    // contract needs no change.
    static func FindClosedArrayImplementation(candidate: Type, openDefinition: Type): Type? {
        if !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(candidate) {
            return null
        }

        // THE NON-GENERIC HALF OF THE SAME VECTOR CONTRACT. `E[]` also implements `IEnumerable`,
        // `ICollection` and `IList`, and those carry no element at all — the shape a `Query[]`
        // receiver has IS the interface, with nothing to substitute. `OfType<T>` and `Cast<T>`
        // declare exactly this slot, so leaving it out made a source-element array the one vector
        // they could not be called on. The list is still read off the CLR's own `object[]`.
        if !openDefinition.IsGenericType {
            if SzArrayImplementsDefinition(openDefinition) {
                return openDefinition
            }

            return null
        }

        elementType := candidate.GetElementType()
        if elementType == null || openDefinition.GetGenericArguments().Length != 1 {
            return null
        }

        if !SzArrayImplementsDefinition(openDefinition) {
            return null
        }

        try {
            return openDefinition.MakeGenericType([elementType])
        } catch {
            return null
        }
    }

    // The generic interface definitions every vector implements, read off the CLR's own `object[]`.
    static func SzArrayImplementsDefinition(openDefinition: Type): bool {
        vectorInterfaces := new Type[](0)
        try {
            vectorInterfaces = typeof(object[]).GetInterfaces()
        } catch {
            return false
        }

        for vectorInterface in vectorInterfaces {
            if InterfaceMatchesDefinition(vectorInterface, openDefinition) {
                return true
            }
        }

        return false
    }

    // A CONSTRUCTED TYPE CLOSED OVER A TYPE THIS COMPILATION IS WRITING CANNOT BE ASKED DIRECTLY.
    // `List<Query>` for a source class `Query` is a `TypeBuilderInstantiation`: its `GetInterfaces`
    // throws and its base chain is not reflectable, so the loops above answer nothing and
    // `items.First()` declined for every element type the program itself declared.
    //
    // The DEFINITION answers instead. `List<T>`'s interface list and base chain are complete
    // reflected shapes spelled in `T`, and this instantiation supplies `T`: substituting gives the
    // real closed shapes the receiver has. Nothing here consults a name, so `List`, `Dictionary`, a
    // referenced assembly's own collection and a source generic all answer the same way — and for a
    // runtime instantiation the substituted answer is the same one `GetInterfaces` already gave,
    // which is why this is a fallback and not a second policy.
    static func FindClosedImplementationThroughDefinition(candidate: Type, openDefinition: Type): Type? {
        if !candidate.IsGenericType || candidate.IsGenericTypeDefinition {
            return null
        }

        definition := candidate.GetGenericTypeDefinition()
        if definition == null || definition == candidate {
            return null
        }

        arguments := candidate.GetGenericArguments()
        if arguments == null || definition.GetGenericArguments().Length != arguments.Length {
            return null
        }

        definitionInterfaces := new Type[](0)
        try {
            definitionInterfaces = definition.GetInterfaces()
        } catch {
            definitionInterfaces = new Type[](0)
        }

        if definitionInterfaces != null {
            for implemented in definitionInterfaces {
                if InterfaceMatchesDefinition(implemented, openDefinition) {
                    return ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(implemented, arguments)
                }
            }
        }

        current: Type? = BaseTypeOrNull(definition)
        depth := 0
        while current != null && depth < 64 {
            if current.IsGenericType && current.GetGenericTypeDefinition() == openDefinition {
                return ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(current, arguments)
            }

            if !openDefinition.IsGenericType && current == openDefinition {
                return current
            }

            current = BaseTypeOrNull(current)
            depth = depth + 1
        }

        return null
    }

    // A declared interface against the definition a receiver slot names. A generic declaration is
    // matched by its DEFINITION; a non-generic one (`IEnumerable`, which is what `Cast<T>` and
    // `OfType<T>` declare) is matched by identity.
    static func InterfaceMatchesDefinition(implemented: Type, openDefinition: Type): bool {
        if openDefinition.IsGenericType {
            return implemented.IsGenericType && implemented.GetGenericTypeDefinition() == openDefinition
        }

        return implemented == openDefinition
    }

    // Structural unification of ONE declared slot against one actual type. A slot with nothing open
    // in it carries no inference; a naked type parameter binds its position once and must agree with
    // itself afterwards; an array unifies its element; a constructed shape must name the SAME
    // definition and unifies pairwise.
    static func TryUnifySlot(parameterType: Type, actualType: Type, typeParameters: Type[], inferred: Type[]): bool {
        if parameterType == null || actualType == null {
            return false
        }

        if !parameterType.ContainsGenericParameters {
            return true
        }

        if parameterType.IsGenericParameter {
            position := ColumnarExtensionMethodResolver.MethodTypeParameterOrdinal(parameterType, typeParameters)
            if position < 0 {
                return false
            }

            existing := inferred[position]
            if existing == null {
                inferred[position] = actualType
                return true
            }

            // `X` AND `X?` ARE ONE BOUND, AND IT IS `X?` — the same rule the direct-call resolver and
            // the analyzer state, because a type parameter met by both is fixed to the bound the other
            // converts to.
            if ColumnarTypeEquivalenceFacts.IsNullableLiftOf(actualType, existing) {
                inferred[position] = actualType
                return true
            }

            if ColumnarTypeEquivalenceFacts.IsNullableLiftOf(existing, actualType) {
                return true
            }

            return ColumnarTypeEquivalenceFacts.TypesEquivalent(existing, actualType)
        }

        if ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(parameterType) {
            if !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(actualType) {
                return false
            }

            parameterElement := parameterType.GetElementType()
            actualElement := actualType.GetElementType()
            if parameterElement == null || actualElement == null {
                return false
            }

            return TryUnifySlot(parameterElement, actualElement, typeParameters, inferred)
        }

        if !parameterType.IsGenericType {
            return false
        }

        // THE ACTUAL TYPE IS READ THROUGH ITS OWN IMPLEMENTATIONS whenever it does not already name
        // the declaration's definition — including when it is not generic at all. `char[]` is an
        // `IEnumerable<char>`, which is the only way `SelectMany(x => x.ToCharArray())` can fix
        // `TResult`, and a user sequence class is its interface the same way.
        comparison := actualType
        if !actualType.IsGenericType || parameterType.GetGenericTypeDefinition() != actualType.GetGenericTypeDefinition() {
            widened := FindClosedImplementation(actualType, parameterType.GetGenericTypeDefinition())
            if widened == null {
                return false
            }

            comparison = widened
        }

        parameterArguments := parameterType.GetGenericArguments()
        actualArguments := comparison.GetGenericArguments()
        if parameterArguments.Length != actualArguments.Length {
            return false
        }

        pairIndex := 0
        while pairIndex < parameterArguments.Length {
            if !TryUnifySlot(parameterArguments[pairIndex], actualArguments[pairIndex], typeParameters, inferred) {
                return false
            }

            pairIndex = pairIndex + 1
        }

        return true
    }

    // The closed form of an open type under the inference so far, or `null` while any position it
    // mentions is still open. A type that mentions no type parameter is already closed.
    static func Substitute(openType: Type, typeParameters: Type[], inferred: Type[]): Type? {
        if openType == null {
            return null
        }

        if !openType.ContainsGenericParameters {
            return openType
        }

        if openType.IsGenericParameter {
            position := ColumnarExtensionMethodResolver.MethodTypeParameterOrdinal(openType, typeParameters)
            if position < 0 {
                return null
            }

            return inferred[position]
        }

        if ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(openType) {
            element := openType.GetElementType()
            if element == null {
                return null
            }

            closedElement := Substitute(element, typeParameters, inferred)
            if closedElement == null {
                return null
            }

            return closedElement.MakeArrayType()
        }

        if !openType.IsGenericType {
            return null
        }

        arguments := openType.GetGenericArguments()
        closedArguments := new Type[](arguments.Length)
        index := 0
        while index < arguments.Length {
            closedArgument := Substitute(arguments[index], typeParameters, inferred)
            if closedArgument == null {
                return null
            }

            closedArguments[index] = closedArgument
            index = index + 1
        }

        try {
            return openType.GetGenericTypeDefinition().MakeGenericType(closedArguments)
        } catch {
            return null
        }
    }
}
