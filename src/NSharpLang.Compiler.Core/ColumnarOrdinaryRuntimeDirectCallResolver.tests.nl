namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

func OrdinaryRuntimeArgumentTypes1(first: Type): Type[] {
    arguments := new Type[](1)
    arguments[0] = first
    return arguments
}

func OrdinaryRuntimeArgumentTypes2(first: Type, second: Type): Type[] {
    arguments := new Type[](2)
    arguments[0] = first
    arguments[1] = second
    return arguments
}

func RequiredOrdinaryRuntimeType(fullName: string): Type {
    runtimeType := Type.GetType(fullName)
    if runtimeType == null {
        throw new InvalidOperationException("The ordinary runtime direct-call fixture type could not be resolved: " + fullName)
    }

    return runtimeType
}

func RequiredOrdinaryRuntimeSelection(lookupType: Type, memberName: string, argumentTypes: Type[], expectedStatic: bool): ColumnarOrdinaryRuntimeDirectCallSelection {
    selection := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(lookupType, memberName, argumentTypes, expectedStatic)
    if !selection.IsSelected || selection.Method == null {
        throw new InvalidOperationException("The ordinary runtime direct-call fixture was not selected.")
    }

    return selection
}

func OrdinaryRuntimeBuilderBoundList(elementType: Type): Type {
    arguments := new Type[](1)
    arguments[0] = elementType
    return typeof(List<int>).GetGenericTypeDefinition().MakeGenericType(arguments)
}

func RequiredOrdinaryRuntimeOpenMethod(genericDefinition: Type, memberName: string, parameterCount: int, genericMethod: bool): MethodInfo {
    methods := genericDefinition.GetMethods()
    selected: MethodInfo? = null
    count := 0
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        if candidate != null && candidate.get_Name() == memberName && candidate.get_IsGenericMethod() == genericMethod {
            parameters := candidate.GetParameters()
            if parameters.Length == parameterCount {
                selected = candidate
                count += 1
            }
        }

        index += 1
    }

    if selected == null || count != 1 {
        throw new InvalidOperationException("The ordinary runtime open-method fixture was not unique: " + memberName)
    }

    return selected
}

test "ordinary runtime direct calls select exact static reference and value dispatch" {
    staticSelection := RequiredOrdinaryRuntimeSelection(typeof(Type), "GetType", OrdinaryRuntimeArgumentTypes1(typeof(string)), true)
    assert staticSelection.Method != null
    assert staticSelection.LookupType == typeof(Type)
    assert staticSelection.DeclaringType == typeof(Type)
    assert staticSelection.ParameterTypes.Length == 1
    assert staticSelection.ParameterTypes[0] == typeof(string)
    assert staticSelection.ReturnType == typeof(Type)
    assert staticSelection.Kind == ColumnarExternalCallKind.Call
    assert staticSelection.IsStatic
    assert !staticSelection.ReceiverIsReference
    assert !staticSelection.IsAbstract
    assert !staticSelection.UsesCallVirtual

    referenceSelection := RequiredOrdinaryRuntimeSelection(typeof(object), "ToString", new Type[](0), false)
    assert referenceSelection.Method != null
    assert referenceSelection.DeclaringType == typeof(object)
    assert referenceSelection.ParameterTypes.Length == 0
    assert referenceSelection.ReturnType == typeof(string)
    assert referenceSelection.Kind == ColumnarExternalCallKind.CallVirtual
    assert !referenceSelection.IsStatic
    assert referenceSelection.ReceiverIsReference
    assert !referenceSelection.IsAbstract
    assert referenceSelection.UsesCallVirtual

    valueSelection := RequiredOrdinaryRuntimeSelection(typeof(Index), "GetOffset", OrdinaryRuntimeArgumentTypes1(typeof(int)), false)
    assert valueSelection.Method != null
    assert valueSelection.DeclaringType == typeof(Index)
    assert valueSelection.ParameterTypes[0] == typeof(int)
    assert valueSelection.ReturnType == typeof(int)
    assert valueSelection.Kind == ColumnarExternalCallKind.Call
    assert !valueSelection.IsStatic
    assert !valueSelection.ReceiverIsReference
    assert !valueSelection.IsAbstract
    assert !valueSelection.UsesCallVirtual
}

test "ordinary runtime direct calls preserve inherited and abstract interface facts" {
    stringWriterType := RequiredOrdinaryRuntimeType("System.IO.StringWriter")
    textWriterType := RequiredOrdinaryRuntimeType("System.IO.TextWriter")
    inherited := RequiredOrdinaryRuntimeSelection(stringWriterType, "WriteLine", OrdinaryRuntimeArgumentTypes1(typeof(string)), false)
    assert inherited.Method != null
    assert inherited.LookupType == stringWriterType
    assert inherited.DeclaringType == textWriterType
    assert inherited.ParameterTypes[0] == typeof(string)
    assert inherited.ReturnType.FullName == "System.Void"
    assert inherited.ReceiverIsReference
    assert inherited.UsesCallVirtual

    disposableType := RequiredOrdinaryRuntimeType("System.IDisposable")
    abstractInterface := RequiredOrdinaryRuntimeSelection(disposableType, "Dispose", new Type[](0), false)
    assert abstractInterface.Method != null
    assert abstractInterface.LookupType == disposableType
    assert abstractInterface.DeclaringType == disposableType
    assert abstractInterface.ReturnType.FullName == "System.Void"
    assert abstractInterface.IsAbstract
    assert abstractInterface.ReceiverIsReference
    assert abstractInterface.UsesCallVirtual
}

test "ordinary runtime direct calls rank exact reference overloads above boxing" {
    selection := RequiredOrdinaryRuntimeSelection(typeof(string), "Equals", OrdinaryRuntimeArgumentTypes1(typeof(string)), false)
    assert selection.Method != null
    assert selection.ParameterTypes.Length == 1
    assert selection.ParameterTypes[0] == typeof(string)
    assert selection.ReturnType == typeof(bool)
    assert selection.UsesCallVirtual
}

test "ordinary runtime direct calls retain target-typed null facts during overload selection" {
    arguments := OrdinaryRuntimeArgumentTypes1(typeof(object))
    facts := ColumnarDirectCallArgumentFacts.Empty(1)
    facts.IsNullLiteral[0] = true

    selection := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveWithFacts(typeof(string), "StartsWith", arguments, facts, false)

    assert selection.IsSelected
    assert selection.Method != null
    assert selection.ParameterTypes.Length == 1
    assert selection.ParameterTypes[0] == typeof(string)
    assert selection.ReturnType == typeof(bool)
    assert selection.UsesCallVirtual
}

test "ordinary runtime direct calls reject incompatible and equal-score ambiguous fixed arity" {
    incompatible := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(typeof(string), "IndexOf", OrdinaryRuntimeArgumentTypes1(typeof(DateTime)), false)
    assert incompatible.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Rejected
    assert incompatible.IsOwnedRejected
    assert incompatible.Method == null

    // char has the same implicit-numeric score for several Math.Abs overloads. The resolver
    // must reject that tie independent of reflection's method enumeration order.
    mathType := RequiredOrdinaryRuntimeType("System.Math")
    ambiguous := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(mathType, "Abs", OrdinaryRuntimeArgumentTypes1(typeof(char)), true)
    assert ambiguous.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Rejected
    assert ambiguous.IsOwnedRejected
    assert ambiguous.Method == null
}

test "ordinary runtime direct calls exclude generic params byref and optional expansion owners" {
    genericCall := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(typeof(Array), "Empty", new Type[](0), true)
    assert genericCall.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Excluded
    assert genericCall.IsExcluded
    assert genericCall.Method == null

    activatorType := RequiredOrdinaryRuntimeType("System.Activator")
    paramsCall := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(activatorType, "CreateInstance", OrdinaryRuntimeArgumentTypes2(typeof(Type), typeof(object[])), true)
    assert paramsCall.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Excluded
    assert paramsCall.IsExcluded
    assert paramsCall.Method == null

    byRefCall := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(typeof(int), "TryParse", OrdinaryRuntimeArgumentTypes2(typeof(string), typeof(int)), true)
    assert byRefCall.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Excluded
    assert byRefCall.IsExcluded
    assert byRefCall.Method == null

    optionalExpansion := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(typeof(string), "Split", OrdinaryRuntimeArgumentTypes1(typeof(char)), false)
    assert optionalExpansion.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Excluded
    assert optionalExpansion.IsExcluded
    assert optionalExpansion.Method == null
}

test "ordinary runtime direct calls select optional parameters when every argument is explicit" {
    splitOptionsType := RequiredOrdinaryRuntimeType("System.StringSplitOptions")
    explicitArguments := OrdinaryRuntimeArgumentTypes2(typeof(char), splitOptionsType)
    selection := RequiredOrdinaryRuntimeSelection(typeof(string), "Split", explicitArguments, false)
    assert selection.Method != null
    assert selection.ParameterTypes.Length == 2
    assert selection.ParameterTypes[0] == typeof(char)
    assert selection.ParameterTypes[1] == splitOptionsType
    assert selection.ReturnType == typeof(string[])
    assert selection.UsesCallVirtual
}

test "ordinary runtime direct calls leave missing names and arities unowned" {
    missingName := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(typeof(object), "DefinitelyMissingRuntimeMethod", new Type[](0), false)
    assert missingName.Status == ColumnarOrdinaryRuntimeDirectCallStatus.NotFound
    assert missingName.IsNotFound
    assert missingName.Method == null

    wrongArity := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(typeof(object), "ToString", OrdinaryRuntimeArgumentTypes1(typeof(int)), false)
    assert wrongArity.Status == ColumnarOrdinaryRuntimeDirectCallStatus.NotFound
    assert wrongArity.IsNotFound
    assert wrongArity.Method == null
}

test "ordinary runtime direct calls select exact builder-bound generic methods" {
    elementType: Type = TypeOfCreateSourceBuilder("OrdinaryRuntimeListElement", false)
    listType := OrdinaryRuntimeBuilderBoundList(elementType)
    arguments := OrdinaryRuntimeArgumentTypes1(elementType)

    selection := RequiredOrdinaryRuntimeSelection(listType, "Add", arguments, false)

    assert selection.Method != null
    method := selection.Method
    if method == null {
        throw new InvalidOperationException("The builder-bound runtime selection lost its exact method.")
    }

    assert selection.LookupType == listType
    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(selection.DeclaringType, listType)
    assert selection.ParameterTypes.Length == 1
    assert selection.ParameterTypes[0] == elementType
    assert selection.ReturnType == RequiredOrdinaryRuntimeType("System.Void")
    assert method.get_Name() == "Add"
    methodDeclaringType := method.get_DeclaringType()
    if methodDeclaringType == null {
        throw new InvalidOperationException("The rebound builder-bound runtime method lost its declaring type.")
    }

    assert ColumnarRuntimeInstanceMemberResolver.ExactTypeShapeMatches(methodDeclaringType, listType)
    assert !selection.IsStatic
    assert selection.ReceiverIsReference
    assert !selection.IsAbstract
    assert selection.Kind == ColumnarExternalCallKind.CallVirtual
    assert selection.UsesCallVirtual

    toArray := RequiredOrdinaryRuntimeSelection(listType, "ToArray", new Type[](0), false)
    assert toArray.Method != null
    assert toArray.ParameterTypes.Length == 0
    assert toArray.ReturnType.get_IsSZArray()
    assert toArray.ReturnType.GetElementType() == elementType
    assert toArray.UsesCallVirtual
}

test "ordinary runtime direct calls classify rejected and excluded builder-bound shapes" {
    elementType: Type = TypeOfCreateSourceBuilder("OrdinaryRuntimeRejectedElement", false)
    listType := OrdinaryRuntimeBuilderBoundList(elementType)

    incompatible := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(listType, "Add", OrdinaryRuntimeArgumentTypes1(typeof(string)), false)
    assert incompatible.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Rejected
    assert incompatible.IsOwnedRejected
    assert incompatible.Method == null

    genericCall := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(listType, "ConvertAll", OrdinaryRuntimeArgumentTypes1(typeof(object)), false)
    assert genericCall.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Excluded
    assert genericCall.IsExcluded
    assert genericCall.Method == null
}

test "ordinary runtime builder-bound candidate seams reject ambiguity and corrupt rebound handles" {
    elementType: Type = TypeOfCreateSourceBuilder("OrdinaryRuntimeCandidateElement", false)
    listType := OrdinaryRuntimeBuilderBoundList(elementType)
    listDefinition := listType.GetGenericTypeDefinition()
    add := RequiredOrdinaryRuntimeOpenMethod(listDefinition, "Add", 1, false)
    arguments := OrdinaryRuntimeArgumentTypes1(elementType)

    duplicate := new MethodInfo[](2)
    duplicate[0] = add
    duplicate[1] = add
    ambiguous := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveFromCandidates(listType, "Add", arguments, false, duplicate)
    assert ambiguous.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Rejected
    assert ambiguous.IsOwnedRejected
    assert ambiguous.Method == null

    rebound := TypeBuilder.GetMethod(listType, add)
    corruptCandidates := new MethodInfo[](1)
    corruptCandidates[0] = rebound
    corrupt := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveFromCandidates(listType, "Add", arguments, false, corruptCandidates)
    assert corrupt.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Excluded
    assert corrupt.IsExcluded
    assert corrupt.Method == null
}

test "ordinary runtime builder-bound selection is independent of open candidate order" {
    elementType: Type = TypeOfCreateSourceBuilder("OrdinaryRuntimeOrderElement", false)
    listType := OrdinaryRuntimeBuilderBoundList(elementType)
    listDefinition := listType.GetGenericTypeDefinition()
    indexOfOne := RequiredOrdinaryRuntimeOpenMethod(listDefinition, "IndexOf", 1, false)
    indexOfTwo := RequiredOrdinaryRuntimeOpenMethod(listDefinition, "IndexOf", 2, false)
    arguments := OrdinaryRuntimeArgumentTypes1(elementType)

    forwardCandidates := new MethodInfo[](2)
    forwardCandidates[0] = indexOfOne
    forwardCandidates[1] = indexOfTwo
    forward := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveFromCandidates(listType, "IndexOf", arguments, false, forwardCandidates)

    reverseCandidates := new MethodInfo[](2)
    reverseCandidates[0] = indexOfTwo
    reverseCandidates[1] = indexOfOne
    reverse := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveFromCandidates(listType, "IndexOf", arguments, false, reverseCandidates)

    assert forward.IsSelected
    assert reverse.IsSelected
    assert forward.Method != null
    assert reverse.Method != null
    assert forward.ParameterTypes.Length == 1
    assert reverse.ParameterTypes.Length == 1
    assert forward.ParameterTypes[0] == elementType
    assert reverse.ParameterTypes[0] == elementType
    assert forward.ReturnType == typeof(int)
    assert reverse.ReturnType == typeof(int)
    assert forward.UsesCallVirtual
    assert reverse.UsesCallVirtual
}
