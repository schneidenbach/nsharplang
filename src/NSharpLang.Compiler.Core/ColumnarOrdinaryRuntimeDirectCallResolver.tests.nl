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

func OrdinaryRuntimeArgumentTypes4(first: Type, second: Type, third: Type, fourth: Type): Type[] {
    values := new Type[](4)
    values[0] = first
    values[1] = second
    values[2] = third
    values[3] = fourth
    return values
}

func OrdinaryRuntimeArgumentTypes6(first: Type, second: Type, third: Type, fourth: Type, fifth: Type, sixth: Type): Type[] {
    arguments := new Type[](6)
    arguments[0] = first
    arguments[1] = second
    arguments[2] = third
    arguments[3] = fourth
    arguments[4] = fifth
    arguments[5] = sixth
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

test "ordinary runtime direct calls select fixed byref and exclude generic params and optional expansion owners" {
    genericCall := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(typeof(Array), "Empty", new Type[](0), true)
    assert genericCall.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Excluded
    assert genericCall.IsExcluded
    assert genericCall.Method == null

    // A `params` TAIL IS A CALL-SITE SHAPE AT THIS DOOR NOW, AND THIS ROW STATES BOTH HALVES OF IT.
    //
    // It used to be an excluded shape whatever the site wrote, which is why `string.Join(sep, a, b,
    // c)` was "not modeled". The NORMAL form binds first: `Activator.CreateInstance(Type,
    // object[])` supplies the array itself, converts by identity, and selects the DECLARED
    // signature — no packing, nothing expanded.
    activatorType := RequiredOrdinaryRuntimeType("System.Activator")
    paramsCall := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(activatorType, "CreateInstance", OrdinaryRuntimeArgumentTypes2(typeof(Type), typeof(object[])), true)
    assert paramsCall.IsSelected, "Activator.CreateInstance(Type, object[]) status was " + paramsCall.Status.ToString()
    assert paramsCall.Method != null
    assert !paramsCall.IsExpanded, "expanded element was " + (paramsCall.ExpandedElementType == null ? "<null>" : (must paramsCall.ExpandedElementType).ToString())
    assert paramsCall.ExpandedElementType == null
    assert paramsCall.ParameterTypes.Length == 2, "parameter count was " + paramsCall.ParameterTypes.Length.ToString()
    assert paramsCall.ParameterTypes[1] == typeof(object[]), "second parameter was " + paramsCall.ParameterTypes[1].ToString()

    // The EXPANDED form is the same declaration read at a site that wrote the elements instead: the
    // per-argument list is as long as the arguments, the declared signature is kept beside it, and
    // the element type and the slot the packing starts at are what the two writers need.
    expandedCall := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(typeof(string), "Join", OrdinaryRuntimeArgumentTypes4(typeof(string), typeof(string), typeof(string), typeof(string)), true)
    assert expandedCall.IsSelected, "string.Join(4 strings) status was " + expandedCall.Status.ToString()
    assert expandedCall.IsExpanded
    assert expandedCall.ExpandedElementType == typeof(string), "element was " + (expandedCall.ExpandedElementType == null ? "<null>" : (must expandedCall.ExpandedElementType).ToString())
    assert expandedCall.FixedArgumentCount == 1, "fixed count was " + expandedCall.FixedArgumentCount.ToString()
    assert expandedCall.ParameterTypes.Length == 4
    assert expandedCall.ParameterTypes[0] == typeof(string)
    assert expandedCall.ParameterTypes[3] == typeof(string)
    assert expandedCall.DeclaredParameterTypes.Length == 2
    assert expandedCall.DeclaredParameterTypes[1] == typeof(string[])

    // A BY-REF PARAMETER IS NO LONGER AN UNREPRESENTABLE SHAPE. `int.TryParse(string, out int)` binds
    // when the argument is WRITTEN `out` (the contract below), so an argument that is not written
    // `out` is an overload that does not bind — REJECTED — rather than a shape with no owner.
    byRefCall := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(typeof(int), "TryParse", OrdinaryRuntimeArgumentTypes2(typeof(string), typeof(int)), true)
    assert byRefCall.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Rejected
    assert byRefCall.IsOwnedRejected
    assert byRefCall.Method == null

    // …and an `out`-written argument whose storage is the WRONG type is a rejection too: `long` storage
    // cannot alias an `int` parameter.
    incompatibleFacts := ColumnarDirectCallArgumentFacts.Empty(2)
    incompatibleFacts.IsByRefArgument[1] = true
    incompatibleByRef := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveWithFacts(typeof(int), "TryParse", OrdinaryRuntimeArgumentTypes2(typeof(string), typeof(long)), incompatibleFacts, true)
    assert incompatibleByRef.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Rejected
    assert incompatibleByRef.IsOwnedRejected
    assert incompatibleByRef.Method == null

    optionalExpansion := ColumnarOrdinaryRuntimeDirectCallResolver.Resolve(typeof(string), "Split", OrdinaryRuntimeArgumentTypes1(typeof(char)), false)
    assert optionalExpansion.Status == ColumnarOrdinaryRuntimeDirectCallStatus.Excluded
    assert optionalExpansion.IsExcluded
    assert optionalExpansion.Method == null
}

// The other half of the rule above: WRITTEN `out`, the same overload binds, and its parameter list
// carries the by-ref spelling the call site has to honour.
test "ordinary runtime direct calls select a by-reference overload when the argument is written by-ref" {
    facts := ColumnarDirectCallArgumentFacts.Empty(2)
    facts.IsByRefArgument[1] = true

    selection := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveWithFacts(typeof(int), "TryParse", OrdinaryRuntimeArgumentTypes2(typeof(string), typeof(int)), facts, true)
    assert selection.IsSelected
    assert selection.Method != null
    assert selection.ParameterTypes.Length == 2
    assert selection.ParameterTypes[0] == typeof(string)
    assert selection.ParameterTypes[1] == typeof(int).MakeByRefType()
    assert selection.ReturnType == typeof(bool)
    assert selection.IsStatic
}

// A SIX-ARGUMENT STATIC CALL WITH A TRAILING `out`, on a real kernel this compiler's own facade calls.
// Arity, ordinary parameter identity and the by-ref spelling of the final parameter all have to
// survive together, which is what the facade's completion-prefix call depends on.
test "ordinary runtime direct calls select external six-argument out calls" {
    kernel := RequiredOrdinaryRuntimeType("NSharpLang.Compiler.CodeIntelligence.CodeIntelligenceSourceTextKernels, NSharpLang.Compiler.Core")
    facts := ColumnarDirectCallArgumentFacts.Empty(6)
    facts.IsByRefArgument[5] = true
    arguments := OrdinaryRuntimeArgumentTypes6(typeof(object), typeof(string), typeof(string), typeof(int), typeof(int), typeof(string))
    selection := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveWithFacts(kernel, "TryExtractCompletionPrefix", arguments, facts, true)

    assert selection.IsSelected
    assert selection.Method != null
    assert selection.LookupType == kernel
    assert selection.DeclaringType == kernel
    assert selection.ParameterTypes.Length == 6
    assert selection.ParameterTypes[0] == typeof(object)
    assert selection.ParameterTypes[1] == typeof(string)
    assert selection.ParameterTypes[2] == typeof(string)
    assert selection.ParameterTypes[3] == typeof(int)
    assert selection.ParameterTypes[4] == typeof(int)
    assert selection.ParameterTypes[5] == typeof(string).MakeByRefType()
    assert selection.ReturnType == typeof(bool)
    assert selection.Kind == ColumnarExternalCallKind.Call
    assert selection.IsStatic
    assert !selection.ReceiverIsReference
    assert !selection.UsesCallVirtual
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
    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(selection.DeclaringType, listType)
    assert selection.ParameterTypes.Length == 1
    assert selection.ParameterTypes[0] == elementType
    assert selection.ReturnType == RequiredOrdinaryRuntimeType("System.Void")
    assert method.get_Name() == "Add"
    methodDeclaringType := method.get_DeclaringType()
    if methodDeclaringType == null {
        throw new InvalidOperationException("The rebound builder-bound runtime method lost its declaring type.")
    }

    assert RuntimeTypeShapeFacts.ExactTypeShapeMatches(methodDeclaringType, listType)
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

// ─── THE UNIQUENESS TIER: A SITE WHOSE ARGUMENTS CANNOT BE TYPED YET ──────────────────────────────
//
// A LAMBDA ARGUMENT HAS NO TYPE UNTIL IT IS BOUND to the parameter it is passed to, so a call like
// `u.Switch(a => …, b => …)` cannot be scored. Scoring is the ONLY thing this tier gives up:
// candidate admission, the excluded shapes and the dispatch rule are the resolver's own.

test "the uniqueness tier selects the one declaration of a name at an arity" {
    forEach := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(typeof(System.Collections.Generic.List<int>), "ForEach", 1, false)

    assert forEach.IsSelected
    assert forEach.ParameterTypes.Length == 1
    assert forEach.ParameterTypes[0] == typeof(Action<int>)
    assert forEach.UsesCallVirtual
    assert !forEach.IsStatic
}

// THE SIGNATURE IS THE RECEIVER'S, not the definition's: `List<int>.Find` takes `Predicate<int>` and
// answers `int`.
test "the selected signature is substituted by the receiver's own type arguments" {
    find := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(typeof(System.Collections.Generic.List<int>), "Find", 1, false)

    assert find.IsSelected
    assert find.ParameterTypes[0] == typeof(Predicate<int>)
    assert find.ReturnType == typeof(int)
}

// A STATIC member of a CONSTRUCTED owner is chosen on the closed type, which is what makes
// `Comparison<int>` — rather than an open `Comparison<T>` — the parameter a lambda takes its shape
// from.
test "a static member of a constructed generic owner is selected on the CLOSED type" {
    create := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(typeof(System.Collections.Generic.Comparer<int>), "Create", 1, true)

    assert create.IsSelected
    assert create.ParameterTypes[0] == typeof(Comparison<int>)
    assert create.ReturnType == typeof(System.Collections.Generic.Comparer<int>)
    assert create.IsStatic
    assert !create.UsesCallVirtual
}

// MORE THAN ONE CANDIDATE IS REFUSED RATHER THAN GUESSED, because the argument types are exactly what
// would have chosen between them.
test "a name with several declarations at the arity is refused" {
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(typeof(System.Text.StringBuilder), "Append", 1, false).IsSelected
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(typeof(Console), "WriteLine", 1, true).IsSelected
}

// The tier's exclusions are the resolver's own: a GENERIC declaration belongs to the generic tiers,
// a wrong arity is not a candidate, and staticness must match.
test "the uniqueness tier keeps the resolver's own exclusions" {
    // Generic: `ConvertAll<TOutput>` is the explicit/inference tiers' shape, not this one.
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(typeof(System.Collections.Generic.List<int>), "ConvertAll", 1, false).IsSelected

    // Arity: `ForEach` takes one argument and nothing else.
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(typeof(System.Collections.Generic.List<int>), "ForEach", 2, false).IsSelected

    // Staticness: `ForEach` is an instance method.
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(typeof(System.Collections.Generic.List<int>), "ForEach", 1, true).IsSelected

    // A name nothing declares.
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(typeof(System.Collections.Generic.List<int>), "NoSuchMember", 0, false).IsSelected
}

// An OPEN owner has no reachable member table, so it keeps the exact resolver's answer.
test "an open generic owner selects nothing" {
    listDefinition := typeof(System.Collections.Generic.List<int>).GetGenericTypeDefinition()

    assert !ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(listDefinition, "ForEach", 1, false).IsSelected
}

// A SOURCE OWNER IS NEVER AN ORDINARY RUNTIME RECEIVER. An instantiation of a source generic hands out
// reflection objects whose parameters cannot even be asked about their custom attributes (the base
// `ParameterInfo` answers "not implemented"), so the resolver must refuse the owner before it reads a
// single candidate; the exact source resolver owns those members. This is the shape that crashed the
// compiler's own test estate once instance calls started reaching the ordinary runtime tier.
test "ordinary runtime resolution refuses an instantiation of a source generic without reading its candidates" {
    builderDefinition := TypeOfCreateBuilder(
        "OrdinaryRuntimeSourceOwner",
        "ColumnarOrdinaryRuntime.SourceOwner",
        1
    )
    builderDefinitionType: Type = builderDefinition
    builderParameter := builderDefinition.GetGenericArguments()[0]
    builderDefinition.DefineMethod(
        "Pick",
        (MethodAttributes)22,
        builderParameter,
        OrdinaryRuntimeArgumentTypes2(builderParameter, typeof(bool))
    )
    builderClosed := builderDefinitionType.MakeGenericType(OrdinaryRuntimeArgumentTypes1(typeof(int)))
    assert RuntimeTypeShapeFacts.ContainsBuilderBoundType(builderClosed)

    selection := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(builderClosed, "Pick", 2, false)
    assert !selection.IsSelected
    assert selection.Status == ColumnarOrdinaryRuntimeDirectCallStatus.NotFound

    // The open definition itself and the bare builder are refused the same way.
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(builderDefinitionType, "Pick", 2, false).IsSelected
}

// ── THE ADMITTED SET, WHICH IS WHAT "UNIQUE AT ARITY" IS THE ONE-ELEMENT CASE OF ────────────────
//
// `ResolveUniqueAtArity` is `CandidatesAtArity` plus the sentence "exactly one, or nothing", and the
// two now share ONE admission rule rather than two copies of it. The list matters for a caller whose
// ARGUMENTS still carry the information that would choose — a collection expression has no type until
// a parameter names its element type, so it can only be asked "which of these can you be emitted at".
test "candidates at arity are the admitted set the unique tier reduces" {
    // `Encoding.GetString` declares `byte[]` and `ReadOnlySpan<byte>` at arity 1, which is exactly the
    // tie that used to end in a per-API table.
    getString := ColumnarOrdinaryRuntimeDirectCallResolver.CandidatesAtArity(typeof(System.Text.Encoding), "GetString", 1, false)
    assert getString.Count >= 2
    sawByteArray := false
    index := 0
    while index < getString.Count {
        candidate := getString[index]
        assert candidate.IsSelected
        assert candidate.Method != null
        assert candidate.Method.get_Name() == "GetString"
        assert candidate.ParameterTypes.Length == 1
        if candidate.ParameterTypes[0] == typeof(byte[]) {
            sawByteArray = true
        }

        index = index + 1
    }
    assert sawByteArray
    assert !ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(typeof(System.Text.Encoding), "GetString", 1, false).IsSelected

    // Where the set has exactly one member the two answers are the same member.
    preamble := ColumnarOrdinaryRuntimeDirectCallResolver.CandidatesAtArity(typeof(System.Text.Encoding), "GetPreamble", 0, false)
    assert preamble.Count == 1
    unique := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveUniqueAtArity(typeof(System.Text.Encoding), "GetPreamble", 0, false)
    assert unique.IsSelected
    assert unique.Method == preamble[0].Method

    // A name nothing declares, an open owner and a source owner answer with an EMPTY set rather than
    // a candidate, which is the same refusal the unique tier makes for them.
    assert ColumnarOrdinaryRuntimeDirectCallResolver.CandidatesAtArity(typeof(System.Text.Encoding), "NoSuchMember", 0, false).Count == 0
    assert ColumnarOrdinaryRuntimeDirectCallResolver.CandidatesAtArity(typeof(System.Collections.Generic.List<int>).GetGenericTypeDefinition(), "ForEach", 1, false).Count == 0

    // A STATIC name is not in the instance set and an instance name is not in the static one.
    assert ColumnarOrdinaryRuntimeDirectCallResolver.CandidatesAtArity(typeof(System.Text.Encoding), "GetString", 1, true).Count == 0
    assert ColumnarOrdinaryRuntimeDirectCallResolver.CandidatesAtArity(typeof(string), "Join", 2, true).Count > 0
}
