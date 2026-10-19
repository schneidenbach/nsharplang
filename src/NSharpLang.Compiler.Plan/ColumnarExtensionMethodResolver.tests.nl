namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Linq
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler

func RequiredExtensionFixtureType(fullName: string): Type {
    runtimeType := Type.GetType(fullName)
    if runtimeType == null {
        throw new InvalidOperationException("The extension-method fixture type could not be resolved: " + fullName)
    }

    return runtimeType
}

func ExtensionOneType(first: Type): Type[] {
    values := new Type[](1)
    values[0] = first
    return values
}

func ExtensionTwoTypes(first: Type, second: Type): Type[] {
    values := new Type[](2)
    values[0] = first
    values[1] = second
    return values
}

func RequiredExtensionStaticMethod(owner: Type, name: string, parameterTypes: Type[]): MethodInfo {
    method := owner.GetMethod(name, parameterTypes)
    if method == null {
        throw new InvalidOperationException("The extension-method fixture static method could not be resolved: " + name)
    }

    return method
}

func MakeExtensionFixtureCandidate(method: MethodInfo): ColumnarExtensionMethodCandidate {
    parameters := method.GetParameters()
    parameterTypes := new Type[](parameters.Length)
    index := 0
    while index < parameters.Length {
        parameterTypes[index] = parameters[index].get_ParameterType()
        index = index + 1
    }

    declaringType := method.get_DeclaringType()
    if declaringType == null {
        throw new InvalidOperationException("The extension-method fixture method has no declaring type.")
    }

    return new ColumnarExtensionMethodCandidate(method, declaringType, parameterTypes, method.get_ReturnType())
}

func BuildReceiverRankedExtensionIndex(expanded: bool, includeGeneric: bool, includeNonGeneric: bool): ColumnarExtensionMethodIndex {
    identity := "ReceiverRankedExtension" + Guid.NewGuid().ToString("N")
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(identity), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule(identity)
    owner := module.DefineType(identity, TypeAttributes.Public | TypeAttributes.Abstract | TypeAttributes.Sealed)

    if includeGeneric {
        generic := owner.DefineMethod("Rank", MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig, CallingConventions.Standard)
        typeParameter := generic.DefineGenericParameters(["T"])[0]
        genericArgument := new Type[](1)
        genericArgument[0] = typeParameter
        receiver := typeof(IEnumerable<int>).GetGenericTypeDefinition().MakeGenericType(genericArgument)
        genericParameters := new Type[](expanded ? 3 : 2)
        genericParameters[0] = receiver
        genericParameters[1] = expanded ? typeof(long) : typeof(int)
        if expanded {
            genericParameters[2] = typeof(int[])
        }
        generic.SetReturnType(typeof(int))
        generic.SetParameters(genericParameters)
        generic.DefineParameter(1, ParameterAttributes.None, "receiver")
        generic.DefineParameter(2, ParameterAttributes.None, "value")
        if expanded {
            paramArrayConstructor := typeof(ParamArrayAttribute).GetConstructor(Type.EmptyTypes)
            if paramArrayConstructor == null {
                throw new InvalidOperationException("ParamArrayAttribute constructor was not found.")
            }
            tail := generic.DefineParameter(3, ParameterAttributes.None, "rest")
            tail.SetCustomAttribute(new CustomAttributeBuilder(paramArrayConstructor, new object[](0)))
        }
        genericBody := generic.GetILGenerator()
        genericBody.Emit(OpCodes.Ldc_I4_1)
        genericBody.Emit(OpCodes.Ret)
    }

    if includeNonGeneric {
        ordinary := owner.DefineMethod("Rank", MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.HideBySig, CallingConventions.Standard)
        ordinaryParameters := new Type[](expanded ? 3 : 2)
        ordinaryParameters[0] = typeof(object)
        ordinaryParameters[1] = typeof(int)
        if expanded {
            ordinaryParameters[2] = typeof(int[])
        }
        ordinary.SetReturnType(typeof(int))
        ordinary.SetParameters(ordinaryParameters)
        ordinary.DefineParameter(1, ParameterAttributes.None, "receiver")
        ordinary.DefineParameter(2, ParameterAttributes.None, "value")
        if expanded {
            paramArrayConstructor := typeof(ParamArrayAttribute).GetConstructor(Type.EmptyTypes)
            if paramArrayConstructor == null {
                throw new InvalidOperationException("ParamArrayAttribute constructor was not found.")
            }
            tail := ordinary.DefineParameter(3, ParameterAttributes.None, "rest")
            tail.SetCustomAttribute(new CustomAttributeBuilder(paramArrayConstructor, new object[](0)))
        }
        ordinaryBody := ordinary.GetILGenerator()
        ordinaryBody.Emit(OpCodes.Ldc_I4_2)
        ordinaryBody.Emit(OpCodes.Ret)
    }

    createdOwner := owner.CreateType()
    if createdOwner == null {
        throw new InvalidOperationException("The receiver-ranked extension fixture type was not created.")
    }

    index := new ColumnarExtensionMethodIndex()
    for method in createdOwner.GetMethods() {
        isGeneric := method.IsGenericMethodDefinition
        if method.Name == "Rank" && ((isGeneric && includeGeneric) || (!isGeneric && includeNonGeneric)) {
            index.Add("Rank", MakeExtensionFixtureCandidate(method))
        }
    }
    return index
}

func InvokeExtensionRank(selection: ColumnarExtensionMethodSelection, arguments: object?[]): int {
    method := selection.Method
    if !selection.IsSelected || method == null {
        throw new InvalidOperationException("A selected extension ranking probe must carry its method.")
    }
    return Convert.ToInt32(method.Invoke(null, arguments))
}

func BuildLinqExtensionIndex(): ColumnarExtensionMethodIndex {
    linqAssembly := RequiredExtensionFixtureType("System.Linq.Enumerable, System.Linq").get_Assembly()
    entry := new ExternalAssemblyCatalogEntry(null, "linq", "", linqAssembly, true)
    entries := new ExternalAssemblyCatalogEntry[](1)
    entries[0] = entry
    scan := new ExternalAssemblyScanResult(entries, null)
    return ColumnarExtensionMethodResolver.BuildIndex(scan)
}

test "extension index build binds non-generic Linq extensions on interface and array receivers" {
    index := BuildLinqExtensionIndex()
    enumerableType := RequiredExtensionFixtureType("System.Linq.Enumerable, System.Linq")
    facts := ColumnarDirectCallArgumentFacts.Empty(0)

    arraySum := ColumnarExtensionMethodResolver.Resolve(index, typeof(int[]), "Sum", new Type[](0), facts)
    assert arraySum.IsSelected, "int[].Sum() must bind the non-generic Enumerable.Sum(IEnumerable<int>) extension."
    assert arraySum.Method != null
    assert arraySum.DeclaringType == enumerableType
    assert arraySum.ExplicitArgumentCount == 0
    assert arraySum.ParameterTypes.Length == 1
    assert arraySum.ReturnType == typeof(int)

    interfaceSum := ColumnarExtensionMethodResolver.Resolve(index, typeof(IEnumerable<int>), "Sum", new Type[](0), facts)
    assert interfaceSum.IsSelected, "An interface-typed receiver must resolve the same non-generic extension by identity."
    assert interfaceSum.ReturnType == typeof(int)

    arrayMax := ColumnarExtensionMethodResolver.Resolve(index, typeof(int[]), "Max", new Type[](0), facts)
    assert arrayMax.IsSelected
    assert arrayMax.ReturnType == typeof(int)

    // Min()/Max() over an int-sequence receiver bind the non-generic Enumerable.Min/Max(IEnumerable<int>)
    // overload by receiver identity. This owner replaces the retired C# int-aggregate emitter arm, so
    // both the concrete-array and the interface-typed receiver must select the same non-generic handle.
    arrayMin := ColumnarExtensionMethodResolver.Resolve(index, typeof(int[]), "Min", new Type[](0), facts)
    assert arrayMin.IsSelected, "int[].Min() must bind the non-generic Enumerable.Min(IEnumerable<int>) extension."
    assert arrayMin.Method != null
    assert !arrayMin.Method.get_IsGenericMethod(), "The non-generic Min(IEnumerable<int>) declaration must be the selected handle."
    assert arrayMin.ReturnType == typeof(int)

    interfaceMin := ColumnarExtensionMethodResolver.Resolve(index, typeof(IEnumerable<int>), "Min", new Type[](0), facts)
    assert interfaceMin.IsSelected, "An interface-typed int receiver must resolve the same non-generic Min extension by identity."
    assert interfaceMin.Method != null
    assert !interfaceMin.Method.get_IsGenericMethod(), "The interface receiver must also select the non-generic Min(IEnumerable<int>) handle."
    assert interfaceMin.ReturnType == typeof(int)
}

test "extension resolution declines generic arity mismatch, missing, and value-type receiver cases" {
    index := BuildLinqExtensionIndex()
    facts := ColumnarDirectCallArgumentFacts.Empty(0)

    // Every Enumerable.Select overload takes a selector argument; generic candidates require exact
    // arity with no optional filling, so a zero-argument call declines rather than binding.
    genericOnly := ColumnarExtensionMethodResolver.Resolve(index, typeof(int[]), "Select", new Type[](0), facts)
    assert !genericOnly.IsSelected, "A generic extension at the wrong arity must not bind."

    missing := ColumnarExtensionMethodResolver.Resolve(index, typeof(int[]), "TotallyMissingExtensionXyz", new Type[](0), facts)
    assert !missing.IsSelected, "An unknown extension name must decline."

    valueReceiver := ColumnarExtensionMethodResolver.Resolve(index, typeof(int), "Sum", new Type[](0), facts)
    assert !valueReceiver.IsSelected, "A value-type receiver is outside this extension-call surface."
}

test "generic extension inference closes Take and ToList from an exact interface receiver" {
    index := BuildLinqExtensionIndex()
    takeFacts := ColumnarDirectCallArgumentFacts.Empty(1)

    take := ColumnarExtensionMethodResolver.Resolve(index, typeof(IEnumerable<int>), "Take", ExtensionOneType(typeof(int)), takeFacts)
    assert take.IsSelected, "IEnumerable<int>.Take(int) must close Enumerable.Take<int> by receiver inference."
    assert take.Method != null
    assert take.Method.get_IsGenericMethod(), "The selected Take handle must be the closed generic instantiation."
    assert !take.Method.get_IsGenericMethodDefinition(), "The selected Take handle must not stay an open definition."
    assert take.ExplicitArgumentCount == 1
    assert take.ParameterTypes.Length == 2
    assert take.ParameterTypes[0] == typeof(IEnumerable<int>)
    assert take.ParameterTypes[1] == typeof(int)
    assert take.ReturnType == typeof(IEnumerable<int>)

    toListFacts := ColumnarDirectCallArgumentFacts.Empty(0)
    toList := ColumnarExtensionMethodResolver.Resolve(index, typeof(IEnumerable<int>), "ToList", new Type[](0), toListFacts)
    assert toList.IsSelected, "IEnumerable<int>.ToList() must close Enumerable.ToList<int>."
    assert toList.ReturnType == typeof(List<int>)
}

test "generic extension inference unifies delegate arguments and rejects conflicts and widening" {
    index := BuildLinqExtensionIndex()
    oneArgumentFacts := ColumnarDirectCallArgumentFacts.Empty(1)

    // Func<int, bool> unifies against Func<TSource, bool> with TSource already pinned by the
    // receiver; the indexed Func<TSource, int, bool> overload differs in generic definition arity
    // and is filtered, so exactly one candidate survives.
    whereSelection := ColumnarExtensionMethodResolver.Resolve(index, typeof(IEnumerable<int>), "Where", ExtensionOneType(typeof(Func<int, bool>)), oneArgumentFacts)
    assert whereSelection.IsSelected, "A delegate-typed argument must unify against the generic selector slot."
    assert whereSelection.ReturnType == typeof(IEnumerable<int>)

    matched := ColumnarExtensionMethodResolver.Resolve(index, typeof(IEnumerable<int>), "SequenceEqual", ExtensionOneType(typeof(IEnumerable<int>)), oneArgumentFacts)
    assert matched.IsSelected, "Consistent inference across receiver and argument slots must close."
    assert matched.ReturnType == typeof(bool)

    conflicted := ColumnarExtensionMethodResolver.Resolve(index, typeof(IEnumerable<int>), "SequenceEqual", ExtensionOneType(typeof(IEnumerable<string>)), oneArgumentFacts)
    assert !conflicted.IsSelected, "A type parameter bound to two different types must decline."

    // A constructed interface in the receiver's base/interface closure supplies the inference bound.
    listReceiver := ColumnarExtensionMethodResolver.Resolve(index, typeof(List<int>), "Take", ExtensionOneType(typeof(int)), oneArgumentFacts)
    assert listReceiver.IsSelected, "List<int> must infer Take<TSource> through its IEnumerable<int> interface."
    assert listReceiver.ParameterTypes[0] == typeof(IEnumerable<int>)
}

test "a non-generic extension outranks an equally scored inference-closed generic" {
    index := BuildLinqExtensionIndex()
    facts := ColumnarDirectCallArgumentFacts.Empty(0)

    // Enumerable carries both the non-generic Max(IEnumerable<int>) and the generic
    // Max<TSource>(IEnumerable<TSource>); both close to the identical signature here, and the
    // non-generic declaration must win instead of declining as ambiguous.
    interfaceMax := ColumnarExtensionMethodResolver.Resolve(index, typeof(IEnumerable<int>), "Max", new Type[](0), facts)
    assert interfaceMax.IsSelected, "Equal-signature generic and non-generic candidates must prefer the non-generic."
    assert interfaceMax.Method != null
    assert !interfaceMax.Method.get_IsGenericMethod(), "The non-generic Max(IEnumerable<int>) declaration must be the selected handle."
    assert interfaceMax.ReturnType == typeof(int)
}

func ExtensionReceiverComparisonCandidates(): List<ColumnarExtensionMethodCandidate> {
    identity := "ExtensionReceiverComparison" + Guid.NewGuid().ToString("N")
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(identity), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule(identity)
    owner := module.DefineType(identity, TypeAttributes.Public | TypeAttributes.Abstract | TypeAttributes.Sealed)

    genericMethodBuilder := owner.DefineMethod("Pick", MethodAttributes.Public | MethodAttributes.Static, CallingConventions.Standard)
    typeParameter := genericMethodBuilder.DefineGenericParameters(["T"])[0]
    enumerableType := typeof(IEnumerable<int>).GetGenericTypeDefinition().MakeGenericType(ExtensionOneType(typeParameter))
    genericMethodBuilder.SetReturnType(typeof(int))
    genericMethodBuilder.SetParameters(ExtensionThreeTypes(enumerableType, typeof(string), typeof(int[])))
    genericMethodBuilder.DefineParameter(1, ParameterAttributes.None, "values")
    genericMethodBuilder.DefineParameter(2, ParameterAttributes.None, "label")
    genericPackedParameter := genericMethodBuilder.DefineParameter(3, ParameterAttributes.None, "rest")
    paramArrayConstructor := typeof(ParamArrayAttribute).GetConstructor(Type.EmptyTypes)
    if paramArrayConstructor == null {
        throw new InvalidOperationException("ParamArrayAttribute constructor not found")
    }
    genericPackedParameter.SetCustomAttribute(new CustomAttributeBuilder(paramArrayConstructor, new object[](0)))
    genericIl := genericMethodBuilder.GetILGenerator()
    genericIl.Emit(OpCodes.Ldc_I4_1)
    genericIl.Emit(OpCodes.Ret)

    objectMethodBuilder := owner.DefineMethod("Pick", MethodAttributes.Public | MethodAttributes.Static, CallingConventions.Standard)
    objectMethodBuilder.SetReturnType(typeof(int))
    objectMethodBuilder.SetParameters(ExtensionThreeTypes(typeof(object), typeof(string), typeof(int[])))
    objectMethodBuilder.DefineParameter(1, ParameterAttributes.None, "value")
    objectMethodBuilder.DefineParameter(2, ParameterAttributes.None, "label")
    objectPackedParameter := objectMethodBuilder.DefineParameter(3, ParameterAttributes.None, "rest")
    objectPackedParameter.SetCustomAttribute(new CustomAttributeBuilder(paramArrayConstructor, new object[](0)))
    objectIl := objectMethodBuilder.GetILGenerator()
    objectIl.Emit(OpCodes.Ldc_I4_2)
    objectIl.Emit(OpCodes.Ret)

    createdOwner := owner.CreateType()
    candidates := new List<ColumnarExtensionMethodCandidate>()
    for method in createdOwner.GetMethods(BindingFlags.Public | BindingFlags.Static) {
        if method.Name == "Pick" {
            candidates.Add(MakeExtensionFixtureCandidate(method))
        }
    }
    return candidates
}

func ExtensionThreeTypes(first: Type, second: Type, third: Type): Type[] {
    values := new Type[](3)
    values[0] = first
    values[1] = second
    values[2] = third
    return values
}

test "expanded extension overload comparison includes receiver conversions" {
    index := new ColumnarExtensionMethodIndex()
    for candidate in ExtensionReceiverComparisonCandidates() {
        index.Add("Pick", candidate)
    }

    explicitTypes := ExtensionOneType(typeof(string))
    facts := ColumnarDirectCallArgumentFacts.Empty(1)
    list := new List<string>()
    list.Add("value")
    selected := ColumnarExtensionMethodResolver.Resolve(index, typeof(List<string>), "Pick", explicitTypes, facts)
    assert selected.IsSelected, "the generic IEnumerable<T> extension should beat the object receiver"
    assert selected.Method != null && selected.Method.IsGenericMethod
    listArguments := new object?[](3)
    listArguments[0] = list
    listArguments[1] = "x"
    listArguments[2] = new int[](0)
    listResult := selected.Method.Invoke(null, listArguments)
    assert Convert.ToInt32(listResult) == 1

    objectReceiver := new object()
    objectSelection := ColumnarExtensionMethodResolver.Resolve(index, typeof(object), "Pick", explicitTypes, facts)
    assert objectSelection.IsSelected && objectSelection.Method != null
    assert !objectSelection.Method.IsGenericMethod, "an object receiver cannot use the IEnumerable<T> overload"
    objectArguments := new object?[](3)
    objectArguments[0] = objectReceiver
    objectArguments[1] = "x"
    objectArguments[2] = new int[](0)
    objectResult := objectSelection.Method.Invoke(null, objectArguments)
    assert Convert.ToInt32(objectResult) == 2
}

test "extension resolution prefers exact arity over trailing-optional and rejects ambiguity" {
    facts := ColumnarDirectCallArgumentFacts.Empty(0)

    preference := new ColumnarExtensionMethodIndex()
    exactCandidate := MakeExtensionFixtureCandidate(
        RequiredExtensionStaticMethod(typeof(string), "IsNullOrEmpty", ExtensionOneType(typeof(string)))
    )
    optionalCandidate := MakeExtensionFixtureCandidate(
        RequiredExtensionStaticMethod(RequiredExtensionFixtureType("System.ArgumentException"), "ThrowIfNullOrEmpty", ExtensionTwoTypes(typeof(string), typeof(string)))
    )
    preference.Add("Combine", exactCandidate)
    preference.Add("Combine", optionalCandidate)

    selection := ColumnarExtensionMethodResolver.Resolve(preference, typeof(string), "Combine", new Type[](0), facts)
    assert selection.IsSelected, "An exact-arity extension must win over a trailing-optional overload."
    assert selection.ParameterTypes.Length == 1
    assert selection.ExplicitArgumentCount == 0

    ambiguous := new ColumnarExtensionMethodIndex()
    ambiguous.Add("Ambiguous", MakeExtensionFixtureCandidate(
        RequiredExtensionStaticMethod(typeof(string), "IsNullOrEmpty", ExtensionOneType(typeof(string)))
    ))
    ambiguous.Add("Ambiguous", MakeExtensionFixtureCandidate(
        RequiredExtensionStaticMethod(typeof(string), "IsNullOrWhiteSpace", ExtensionOneType(typeof(string)))
    ))

    ambiguousSelection := ColumnarExtensionMethodResolver.Resolve(ambiguous, typeof(string), "Ambiguous", new Type[](0), facts)
    assert !ambiguousSelection.IsSelected, "Two equally-ranked extensions across static classes must decline."
}

test "extension resolution fills a trailing optional null-default parameter" {
    facts := ColumnarDirectCallArgumentFacts.Empty(0)

    index := new ColumnarExtensionMethodIndex()
    // ArgumentNullException.ThrowIfNull(object value, string? paramName = null): the receiver slot is
    // `value` and `paramName` is a trailing optional with a null metadata default.
    optionalCandidate := MakeExtensionFixtureCandidate(
        RequiredExtensionStaticMethod(RequiredExtensionFixtureType("System.ArgumentNullException"), "ThrowIfNull", ExtensionTwoTypes(typeof(object), typeof(string)))
    )
    index.Add("Guard", optionalCandidate)

    selection := ColumnarExtensionMethodResolver.Resolve(index, typeof(string), "Guard", new Type[](0), facts)
    assert selection.IsSelected, "A string receiver must bind the object-receiver extension and fill the trailing optional."
    assert selection.ParameterTypes.Length == 2
    assert selection.ExplicitArgumentCount == 0
}

test "optional default admits null reference parameters and rejects required receivers" {
    method := RequiredExtensionStaticMethod(RequiredExtensionFixtureType("System.ArgumentNullException"), "ThrowIfNull", ExtensionTwoTypes(typeof(object), typeof(string)))
    parameters := method.GetParameters()

    assert ColumnarExtensionMethodResolver.CanFillOptional(parameters[1], typeof(string)), "A null-default reference optional is fillable."
    assert !ColumnarExtensionMethodResolver.CanFillOptional(parameters[0], typeof(object)), "A required receiver parameter is not a fillable optional."
}

test "runtime optional-fill selection binds a single trailing optional and ignores exact arity" {
    facts := ColumnarDirectCallArgumentFacts.Empty(0)

    // Directory.CreateTempSubdirectory(string? prefix = null) is a static method with one trailing
    // optional; the fallback selects it at arity zero and records zero explicit arguments.
    directoryType := RequiredExtensionFixtureType("System.IO.Directory")
    optionalFill := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveOptionalFill(directoryType, "CreateTempSubdirectory", new Type[](0), facts, true)
    assert optionalFill.IsSelected, "A trailing-optional static must be selected by the optional-fill fallback."
    assert optionalFill.Method != null
    assert optionalFill.ExplicitArgumentCount == 0
    assert optionalFill.ParameterTypes.Length == 1
    assert optionalFill.ParameterTypes[0] == typeof(string)
    assert optionalFill.IsStatic
    assert !optionalFill.UsesCallVirtual

    // A method whose arity already matches the supplied arguments is owned by the exact-arity
    // resolver, never by the optional-fill fallback.
    exactArity := ColumnarOrdinaryRuntimeDirectCallResolver.ResolveOptionalFill(typeof(object), "ToString", new Type[](0), facts, false)
    assert !exactArity.IsSelected, "An exact-arity call must not be claimed by the optional-fill fallback."
}

// THE ATTRIBUTE TESTS MUST NOT DEPEND ON TYPE IDENTITY. `IsDefined(attributeType, ...)` compares the
// attribute's type OBJECT, which is refused outright over a `MetadataLoadContext` and would have been
// swallowed by the `catch`es these owners used to carry -- producing an empty extension index in
// silence rather than an error. These blocks pin the full-name reading on both receivers.
test "the extension-host test reads the attribute by full name, not by type identity" {
    hostType := RequiredExtensionFixtureType("System.Linq.Enumerable, System.Linq")
    assert ColumnarExtensionMethodResolver.HasExtensionAttribute(hostType)
    assert ColumnarExtensionMethodResolver.IsStaticExtensionHost(hostType)

    // A sealed non-static class carries no ExtensionAttribute and is not a host.
    assert !ColumnarExtensionMethodResolver.HasExtensionAttribute(typeof(string))
    assert !ColumnarExtensionMethodResolver.IsStaticExtensionHost(typeof(string))
}

test "an extension method and a params tail are both recognised by full name" {
    hostType := RequiredExtensionFixtureType("System.Linq.Enumerable, System.Linq")
    methods := hostType.GetMethods()
    sawExtension := false
    index := 0
    while index < methods.Length {
        candidate := methods[index]
        if candidate.get_Name() == "Count" && ColumnarExtensionMethodResolver.IsExtensionMethodCandidate(candidate) {
            sawExtension = true
        }

        index = index + 1
    }

    assert sawExtension

    // `string.Concat(params string[])` is the params shape the attribute read has to see. The
    // FULL-NAME reading is what this row exists for and it is unchanged; what the tail MEANS has
    // changed, because a `params` tail in its declared last position is now a call-site shape
    // `ColumnarParamsExpansion` answers for rather than an exclusion that hid the whole declaration.
    concat := typeof(string).GetMethod("Concat", ConcatParamsSignature())
    assert concat != null
    assert ColumnarExtensionMethodResolver.IsParamsParameter(concat.GetParameters()[0]), "The params tail must still be recognised by full name."
    assert !ColumnarExtensionMethodResolver.HasExcludedParameterShape(concat.GetParameters()), "A params tail in its last position is an admitted shape."

    // The exclusions the rule still keeps: a by-ref or pointer slot has no call shape here.
    tryParse := typeof(int).GetMethod("TryParse", TryParseByRefSignature())
    assert tryParse != null
    assert ColumnarExtensionMethodResolver.HasExcludedParameterShape(tryParse.GetParameters())
}

func TryParseByRefSignature(): Type[] {
    signature := new Type[](2)
    signature[0] = typeof(string)
    signature[1] = typeof(int).MakeByRefType()
    return signature
}

func ConcatParamsSignature(): Type[] {
    signature := new Type[](1)
    signature[0] = typeof(string[])
    return signature
}

// ── a site that WROTE its type arguments ──────────────────────────────────────────────────────
test "explicit type arguments skip inference and close the candidate of that written arity" {
    index := BuildLinqExtensionIndex()
    facts := ColumnarDirectCallArgumentFacts.Empty(0)

    // `Cast<TResult>` declares a NON-GENERIC `IEnumerable` receiver and a type argument nothing in the
    // call could infer, which is exactly why the site writes it.
    cast := ColumnarExtensionMethodResolver.ResolveExplicit(index, typeof(List<object>), "Cast", ExtensionOneType(typeof(string)), new Type[](0), facts)
    assert cast.IsSelected, "IEnumerable.Cast<string>() must close Enumerable.Cast<string>."
    assert cast.Method != null
    assert cast.Method.get_IsGenericMethod()
    assert !cast.Method.get_IsGenericMethodDefinition()
    assert cast.ParameterTypes.Length == 1
    assert cast.ReturnType == typeof(IEnumerable<string>)

    ofType := ColumnarExtensionMethodResolver.ResolveExplicitUnique(index, typeof(string[]), "OfType", ExtensionOneType(typeof(string)), 0)
    assert ofType.IsSelected, "An array receiver reaches the same non-generic IEnumerable slot."
    assert ofType.ReturnType == typeof(IEnumerable<string>)
}

test "a written type-argument count that the declaration does not have EXCLUDES the candidate" {
    index := BuildLinqExtensionIndex()
    facts := ColumnarDirectCallArgumentFacts.Empty(0)

    // `Enumerable.Cast<TResult>` declares ONE type parameter. Writing two is not an error here: the
    // candidate is excluded and the site is left with none, which is C#'s own rule (§12.6.4.1).
    wrongArity := ColumnarExtensionMethodResolver.ResolveExplicit(index, typeof(List<object>), "Cast", ExtensionTwoTypes(typeof(string), typeof(int)), new Type[](0), facts)
    assert !wrongArity.IsSelected, "A written type-argument count the declaration does not have must not bind."

    // `Enumerable.ToList<TSource>` declares ONE, so writing one BINDS and writing two does not.
    matchingArity := ColumnarExtensionMethodResolver.ResolveExplicit(index, typeof(IEnumerable<int>), "ToList", ExtensionOneType(typeof(int)), new Type[](0), facts)
    assert matchingArity.IsSelected, "A written type-argument count the declaration DOES have must bind."
    assert matchingArity.ReturnType == typeof(List<int>)

    tooMany := ColumnarExtensionMethodResolver.ResolveExplicit(index, typeof(IEnumerable<int>), "ToList", ExtensionTwoTypes(typeof(int), typeof(int)), new Type[](0), facts)
    assert !tooMany.IsSelected, "A written type-argument count the declaration does not have must not bind."

    missing := ColumnarExtensionMethodResolver.ResolveExplicitUnique(index, typeof(string[]), "TotallyMissingExtensionXyz", ExtensionOneType(typeof(string)), 0)
    assert !missing.IsSelected, "An unknown extension name declines however its type arguments were written."
}

test "a receiver the closed candidate cannot accept declines rather than binding" {
    index := BuildLinqExtensionIndex()
    facts := ColumnarDirectCallArgumentFacts.Empty(0)

    // `Select<TSource, TResult>` closes over the written pair, and the closed receiver slot is then
    // `IEnumerable<int>` — a `string[]` is not one.
    wrongReceiver := ColumnarExtensionMethodResolver.ResolveExplicit(index, typeof(string[]), "Select", ExtensionTwoTypes(typeof(int), typeof(int)), new Type[](0), facts)
    assert !wrongReceiver.IsSelected, "A closed receiver slot the receiver does not satisfy must not bind."
}

// `Expression.Lambda<TDelegate>` is the BCL's generic `params` shape with a receiver-shaped first
// slot: `(Expression body, params ParameterExpression[])`, its `(Expression, bool, params ...)` sibling
// and `IEnumerable<ParameterExpression>` overloads. Indexed as extension candidates, it stands in for
// `UseMiddleware<TMiddleware>(this IApplicationBuilder, params object?[] args)`, which lives in the
// ASP.NET shared framework the estate does not reference.
func BuildGenericParamsExtensionIndex(): ColumnarExtensionMethodIndex {
    index := new ColumnarExtensionMethodIndex()
    for method in typeof(System.Linq.Expressions.Expression).GetMethods() {
        if method.get_Name() == "Lambda" && method.get_IsGenericMethodDefinition() && method.GetParameters().Length >= 2 && method.GetParameters()[0].get_ParameterType() == typeof(System.Linq.Expressions.Expression) {
            index.Add("Lambda", MakeExtensionFixtureCandidate(method))
        }
    }

    return index
}

test "an explicit generic site packs a params tail it supplies no arguments for" {
    index := BuildGenericParamsExtensionIndex()
    receiver := typeof(System.Linq.Expressions.ConstantExpression)
    delegateType := ExtensionOneType(typeof(Func<int>))

    // `body.Lambda<Func<int>>()` — the `UseMiddleware<Stamp>()` shape: zero arguments, so only the
    // expanded form applies, and it closes over what the site wrote with nothing to infer.
    empty := ColumnarExtensionMethodResolver.ResolveExplicit(index, receiver, "Lambda", delegateType, new Type[](0), ColumnarDirectCallArgumentFacts.Empty(0))
    assert empty.IsSelected, "A zero-argument explicit site must bind the params-only overload in expanded form."
    assert empty.ParamsElementType == typeof(System.Linq.Expressions.ParameterExpression)
    assert empty.ExplicitArgumentCount == 0
    assert empty.ParameterTypes.Length == 2
    assert empty.ReturnType == typeof(System.Linq.Expressions.Expression<Func<int>>)

    unique := ColumnarExtensionMethodResolver.ResolveExplicitUnique(index, receiver, "Lambda", delegateType, 0)
    assert unique.IsSelected, "The untyped tier reaches the same expanded candidate."
    assert unique.ParamsElementType == typeof(System.Linq.Expressions.ParameterExpression)
}

test "an explicit generic site scores fixed and packed arguments in the expanded form" {
    index := BuildGenericParamsExtensionIndex()
    receiver := typeof(System.Linq.Expressions.ConstantExpression)
    delegateType := ExtensionOneType(typeof(Func<int, int>))

    // A `bool` is no `ParameterExpression`, so it is the FIXED slot of `(Expression, bool, params ...)`.
    tailCall := ColumnarExtensionMethodResolver.ResolveExplicit(index, receiver, "Lambda", delegateType, ExtensionOneType(typeof(bool)), ColumnarDirectCallArgumentFacts.Empty(1))
    assert tailCall.IsSelected, "A fixed bool argument must select the bool-taking params overload."
    assert tailCall.ParameterTypes.Length == 3
    assert tailCall.ParameterTypes[1] == typeof(bool)
    assert tailCall.ParamsElementType == typeof(System.Linq.Expressions.ParameterExpression)

    // Two elements pack into the one params slot.
    packed := ColumnarExtensionMethodResolver.ResolveExplicit(index, receiver, "Lambda", delegateType, ExtensionTwoTypes(typeof(System.Linq.Expressions.ParameterExpression), typeof(System.Linq.Expressions.ParameterExpression)), ColumnarDirectCallArgumentFacts.Empty(2))
    assert packed.IsSelected, "Two parameter expressions must pack into the params tail."
    assert packed.ParameterTypes.Length == 2
    assert packed.ExplicitArgumentCount == 2
    assert packed.ParamsElementType == typeof(System.Linq.Expressions.ParameterExpression)

    // An already-built array binds in NORMAL form, which C# prefers over packing it again.
    normal := ColumnarExtensionMethodResolver.ResolveExplicit(index, receiver, "Lambda", delegateType, ExtensionOneType(typeof(System.Linq.Expressions.ParameterExpression[])), ColumnarDirectCallArgumentFacts.Empty(1))
    assert normal.IsSelected, "An array argument for the params slot must bind in normal form."
    assert normal.ParamsElementType == null
    assert normal.ParameterTypes[1] == typeof(System.Linq.Expressions.ParameterExpression[])

    // Nothing converts a string to either a fixed slot or the element type.
    rejected := ColumnarExtensionMethodResolver.ResolveExplicit(index, receiver, "Lambda", delegateType, ExtensionOneType(typeof(string)), ColumnarDirectCallArgumentFacts.Empty(1))
    assert !rejected.IsSelected, "An argument neither form accepts must not bind."
}

test "a value-type receiver slot is indexed, because an extension's receiver is its first argument" {
    // `IsSupportedReceiverParameter` admits a struct slot: `JsonSerializer.Deserialize<TValue>` is
    // declared on `JsonElement`. A by-ref, pointer or BARE type-parameter slot stays excluded.
    assert ColumnarExtensionMethodResolver.IsSupportedReceiverParameter(typeof(int))
    assert ColumnarExtensionMethodResolver.IsSupportedReceiverParameter(typeof(string))
    assert !ColumnarExtensionMethodResolver.IsSupportedReceiverParameter(typeof(int).MakeByRefType())
    assert !ColumnarExtensionMethodResolver.IsSupportedReceiverParameter(typeof(List<int>).GetGenericTypeDefinition().GetGenericArguments()[0])
}

test "the shape a receiver is searched for is the SLOT ITSELF when nothing in it is open" {
    // The receiver relation is answered by `FindClosedImplementation`, and what it searches for is a
    // DEFINITION. A constructed slot searches by its definition, because the receiver has a different
    // instantiation of it. A slot with nothing open in it — `System.Collections.IEnumerable`, which
    // `Cast<T>` and `OfType<T>` declare — is already the shape to look for; gating the walk on a
    // CONSTRUCTED slot left those two with no relation at all over a builder-bound receiver.
    assert ColumnarExtensionMethodResolver.ExpectedSlotDefinitionOrNull(typeof(IEnumerable)) == typeof(IEnumerable)
    assert ColumnarExtensionMethodResolver.ExpectedSlotDefinitionOrNull(typeof(string)) == typeof(string)
    assert ColumnarExtensionMethodResolver.ExpectedSlotDefinitionOrNull(typeof(IEnumerable<string>)) == typeof(IEnumerable<int>).GetGenericTypeDefinition()
}

test "a slot that is still OPEN names no shape a receiver can be said to have" {
    openDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
    assert ColumnarExtensionMethodResolver.ExpectedSlotDefinitionOrNull(openDefinition) == null
    assert ColumnarExtensionMethodResolver.ExpectedSlotDefinitionOrNull(openDefinition.GetGenericArguments()[0]) == null
    assert ColumnarExtensionMethodResolver.ExpectedSlotDefinitionOrNull(openDefinition.GetGenericArguments()[0].MakeArrayType()) == null
}

// ── an owner that cannot answer for its members, and the index build that broke on one ─────────
//
// `AnalyzerReflectionMemberProbe.tests.nl` pins the analyzer's guarded reads over the same fixture;
// these rows pin the extension-method resolver's, whose INDEX walk -- every extension method of every
// referenced assembly -- is the one that actually ended a check on a signature it could not read.
// Their fixture is their own: Core's estate helpers are not visible from Compiler.Plan's assembly.

// An uncreated `TypeBuilder`: its members cannot be enumerated until it is baked.
func ExtensionProbeUncreatedOwner(): Type {
    assemblyName := "NSharpTests.ExtensionMethodProbe"
    dynamicAssembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName(assemblyName), AssemblyBuilderAccess.Run)
    dynamicModule := dynamicAssembly.DefineDynamicModule(assemblyName)
    return dynamicModule.DefineType("NSharpTests.ExtensionMethodProbe.Owner", TypeAttributes.Public | TypeAttributes.Abstract | TypeAttributes.Sealed)
}

func ExtensionProbeDefineAbstractMethod(owner: Type, name: string): MethodInfo {
    builder := owner as TypeBuilder
    if builder == null {
        throw new InvalidOperationException("The extension probe owner is not a TypeBuilder.")
    }
    return builder.DefineMethod(name, MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.Abstract, typeof(int), new Type[](0))
}

// The raw reads the guards wrap, asserted to FAIL on the fixture. A fixture that stopped failing
// would make every contract here vacuous, and these are what would say so.
func ExtensionProbeRawMethodsThrow(owner: Type): bool {
    try {
        ignored := owner.GetMethods(BindingFlags.Public | BindingFlags.Static)
        return ignored == null
    } catch {
        return true
    }
}

func ExtensionProbeRawParametersThrow(method: MethodInfo): bool {
    try {
        ignored := method.GetParameters()
        return ignored == null
    } catch {
        return true
    }
}

// A `MethodBuilder` is a method handle whose parameters cannot be read either, which is the
// per-METHOD half of the same rule: the owner enumerated, one member did not answer.
test "a method whose parameters cannot be read contributes no signature" {
    owner := ExtensionProbeUncreatedOwner()
    builderMethod := ExtensionProbeDefineAbstractMethod(owner, "Unreadable")

    assert ExtensionProbeRawParametersThrow(builderMethod)
    assert ColumnarExtensionMethodResolver.ParametersOrNull(builderMethod) == null
    assert AnalyzerReflectionMemberProbe.ParameterTypesOrNull(builderMethod) == null
    assert ColumnarExtensionMethodResolver.ParameterTypesOrNull(new ParameterInfo[](0)) != null
}

test "the extension index skips a host it cannot read and indexes everything it can" {
    index := new ColumnarExtensionMethodIndex()
    owner := ExtensionProbeUncreatedOwner()

    // The host DOES declare a method, and the walk that would read it throws — so "indexes nothing"
    // is the guard answering rather than an empty type.
    ExtensionProbeDefineAbstractMethod(owner, "Unreadable")
    assert ExtensionProbeRawMethodsThrow(owner)

    // A host whose attribute list cannot be read is not a static extension host, and adding it
    // indexes nothing. Neither call throws, which is the whole claim.
    assert !ColumnarExtensionMethodResolver.IsStaticExtensionHost(owner)
    ColumnarExtensionMethodResolver.AddType(index, owner)

    unreadable := new List<ColumnarExtensionMethodCandidate>()
    assert !index.TryGet("Unreadable", out unreadable)

    // The readable half still works: `System.Linq.Enumerable` indexes its own extensions.
    ColumnarExtensionMethodResolver.AddType(index, typeof(Enumerable))
    selected := new List<ColumnarExtensionMethodCandidate>()
    assert index.TryGet("Count", out selected)
    assert selected.Count > 0
}

test "normal extension overload ranking compares the receiver with explicit arguments" {
    index := BuildReceiverRankedExtensionIndex(false, true, true)
    values := new List<string>()
    values.Add("receiver")
    argumentTypes := new Type[](1)
    argumentTypes[0] = typeof(int)
    facts := ColumnarDirectCallArgumentFacts.Empty(1)

    selected := ColumnarExtensionMethodResolver.Resolve(index, typeof(List<string>), "Rank", argumentTypes, facts)
    assert selected.IsSelected
    assert selected.Method != null && selected.Method.IsGenericMethod
    arguments := new object?[](2)
    arguments[0] = values
    arguments[1] = 9
    assert InvokeExtensionRank(selected, arguments) == 1

    // With only the object receiver candidate, that same call shape remains applicable and reaches
    // its runtime body. This controls both the negative candidate filter and invocation setup.
    objectIndex := BuildReceiverRankedExtensionIndex(false, false, true)
    objectSelected := ColumnarExtensionMethodResolver.Resolve(objectIndex, typeof(object), "Rank", argumentTypes, facts)
    assert objectSelected.IsSelected
    assert objectSelected.Method != null && !objectSelected.Method.IsGenericMethod
    objectArguments := new object?[](2)
    objectArguments[0] = new object()
    objectArguments[1] = 9
    assert InvokeExtensionRank(objectSelected, objectArguments) == 2
}

test "expanded extension overload ranking preserves incomparable receiver and argument conversions" {
    index := BuildReceiverRankedExtensionIndex(true, true, true)
    argumentTypes := new Type[](1)
    argumentTypes[0] = typeof(int)
    facts := ColumnarDirectCallArgumentFacts.Empty(1)

    // The generic candidate converts the receiver better (IEnumerable<string> over object), while
    // the non-generic candidate converts the explicit int better (identity over int-to-long).
    // C# leaves this call ambiguous; scoring explicit arguments first must not choose either one.
    ambiguous := ColumnarExtensionMethodResolver.Resolve(index, typeof(List<string>), "Rank", argumentTypes, facts)
    assert !ambiguous.IsSelected

    // Each shape remains callable in isolation and returns its own marker when invoked.
    genericIndex := BuildReceiverRankedExtensionIndex(true, true, false)
    values := new List<string>()
    values.Add("receiver")
    longArgumentTypes := new Type[](1)
    longArgumentTypes[0] = typeof(long)
    genericSelected := ColumnarExtensionMethodResolver.Resolve(genericIndex, typeof(List<string>), "Rank", longArgumentTypes, facts)
    assert genericSelected.IsSelected
    assert genericSelected.ParamsElementType == typeof(int)
    genericArguments := new object?[](3)
    genericArguments[0] = values
    genericArguments[1] = 9L
    genericArguments[2] = new int[](0)
    assert InvokeExtensionRank(genericSelected, genericArguments) == 1

    objectIndex := BuildReceiverRankedExtensionIndex(true, false, true)
    objectSelected := ColumnarExtensionMethodResolver.Resolve(objectIndex, typeof(object), "Rank", argumentTypes, facts)
    assert objectSelected.IsSelected
    objectArguments := new object?[](3)
    objectArguments[0] = new object()
    objectArguments[1] = 9
    objectArguments[2] = new int[](0)
    assert InvokeExtensionRank(objectSelected, objectArguments) == 2
}
