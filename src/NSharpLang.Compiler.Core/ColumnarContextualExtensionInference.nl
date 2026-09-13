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

    constructor(candidate: ColumnarExtensionMethodCandidate, typeParameters: Type[], inferred: Type[], argumentCount: int) {
        Candidate = candidate
        TypeParameters = typeParameters
        Inferred = inferred
        ArgumentCount = argumentCount
    }

    // The DECLARED type of explicit argument `index`, still open. Position zero is the receiver, so
    // an explicit argument is always one slot further along.
    func OpenArgumentType(index: int): Type {
        return Candidate.ParameterTypes[index + 1]
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

        typeParameters := new Type[](0)
        if method.get_IsGenericMethodDefinition() {
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

        binding = new ColumnarContextualExtensionBinding(candidate, typeParameters, inferred, argumentCount)
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

        if !openReturn.get_ContainsGenericParameters() {
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

        if !openReturn.get_ContainsGenericParameters() {
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

        index := 0
        while index < binding.Inferred.Length {
            if binding.Inferred[index] == null {
                return false
            }

            index = index + 1
        }

        return true
    }

    // THE CLOSED CANDIDATE, or a decline. The definition is closed over the inference and the
    // runtime is asked to build the handle: a violated constraint throws there and is a non-binding,
    // never an emitted call the CLR would refuse to verify. A builder-bound type argument stays with
    // later owners, exactly as it does in the non-contextual resolver.
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

        index := 0
        while index < binding.Inferred.Length {
            if ColumnarRuntimeInstanceMemberResolver.ContainsBuilderBoundType(binding.Inferred[index]) {
                return false
            }

            index = index + 1
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

        closedParameters := closedMethod.GetParameters()
        if closedParameters == null || closedParameters.Length != candidate.ParameterTypes.Length {
            return false
        }

        closedParameterTypes := ColumnarExtensionMethodResolver.ParameterTypesOrNull(closedParameters)
        if closedParameterTypes == null {
            return false
        }

        closedReturnType := closedMethod.get_ReturnType()
        if closedReturnType == null || closedReturnType.get_ContainsGenericParameters() {
            return false
        }

        closed = new ColumnarExtensionMethodCandidate(closedMethod, candidate.DeclaringType, closedParameterTypes, closedReturnType)
        return true
    }

    // An expression-tree target names its delegate one level in. Everything else IS its delegate.
    static func DelegateTargetType(parameterType: Type): Type {
        if !parameterType.get_IsGenericType() {
            return parameterType
        }

        definition := parameterType.GetGenericTypeDefinition()
        if definition.get_FullName() != "System.Linq.Expressions.Expression`1" {
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

        if delegateType.get_IsGenericType() {
            definition := delegateType.GetGenericTypeDefinition()
            definitionName := definition.get_FullName()
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

        invokeParameters := invoke.GetParameters()
        if invokeParameters == null {
            return false
        }

        declared := new Type[](invokeParameters.Length)
        index := 0
        while index < invokeParameters.Length {
            declared[index] = invokeParameters[index].get_ParameterType()
            index = index + 1
        }

        parameterTypes = declared
        returnType = invoke.get_ReturnType()
        return true
    }

    // A delegate as METADATA sees it: the base chain reaches one of the two roots. The runtime
    // identity check the rest of the emitter uses cannot answer for an instantiation over method
    // type parameters, and this question is asked of exactly those.
    static func IsDelegateShapedType(candidate: Type): bool {
        current: Type? = candidate.get_BaseType()
        depth := 0
        while current != null && depth < 32 {
            fullName := current.get_FullName()
            if fullName == "System.MulticastDelegate" || fullName == "System.Delegate" {
                return true
            }

            current = current.get_BaseType()
            depth = depth + 1
        }

        return false
    }

    // THE RECEIVER SLOT, WIDENED. The declared receiver is matched against the receiver's own type
    // first; when the two name different generic definitions the receiver's INTERFACES and then its
    // base chain are searched for the one the declaration names, and the match is made against that.
    // `List<string>` therefore satisfies `IEnumerable<TSource>` and fixes `TSource` to `string`.
    static func TryUnifyReceiver(parameterType: Type, receiverType: Type, typeParameters: Type[], inferred: Type[]): bool {
        if TryUnifySlot(parameterType, receiverType, typeParameters, inferred) {
            return true
        }

        if !parameterType.get_IsGenericType() {
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
        if candidate.get_IsGenericType() && candidate.GetGenericTypeDefinition() == openDefinition {
            return candidate
        }

        interfaces := new Type[](0)
        try {
            interfaces = candidate.GetInterfaces()
        } catch {
            interfaces = new Type[](0)
        }

        if interfaces != null {
            index := 0
            while index < interfaces.Length {
                implemented := interfaces[index]
                if implemented.get_IsGenericType() && implemented.GetGenericTypeDefinition() == openDefinition {
                    return implemented
                }

                index = index + 1
            }
        }

        current: Type? = candidate.get_BaseType()
        depth := 0
        while current != null && depth < 64 {
            if current.get_IsGenericType() && current.GetGenericTypeDefinition() == openDefinition {
                return current
            }

            if !openDefinition.get_IsGenericType() && current == openDefinition {
                return current
            }

            current = current.get_BaseType()
            depth = depth + 1
        }

        return null
    }

    // Structural unification of ONE declared slot against one actual type. A slot with nothing open
    // in it carries no inference; a naked type parameter binds its position once and must agree with
    // itself afterwards; an array unifies its element; a constructed shape must name the SAME
    // definition and unifies pairwise.
    static func TryUnifySlot(parameterType: Type, actualType: Type, typeParameters: Type[], inferred: Type[]): bool {
        if parameterType == null || actualType == null {
            return false
        }

        if !parameterType.get_ContainsGenericParameters() {
            return true
        }

        if parameterType.get_IsGenericParameter() {
            position := ColumnarExtensionMethodResolver.MethodTypeParameterOrdinal(parameterType, typeParameters)
            if position < 0 {
                return false
            }

            existing := inferred[position]
            if existing == null {
                inferred[position] = actualType
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

        if !parameterType.get_IsGenericType() {
            return false
        }

        // THE ACTUAL TYPE IS READ THROUGH ITS OWN IMPLEMENTATIONS whenever it does not already name
        // the declaration's definition — including when it is not generic at all. `char[]` is an
        // `IEnumerable<char>`, which is the only way `SelectMany(x => x.ToCharArray())` can fix
        // `TResult`, and a user sequence class is its interface the same way.
        comparison := actualType
        if !actualType.get_IsGenericType() || parameterType.GetGenericTypeDefinition() != actualType.GetGenericTypeDefinition() {
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

        if !openType.get_ContainsGenericParameters() {
            return openType
        }

        if openType.get_IsGenericParameter() {
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

        if !openType.get_IsGenericType() {
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
