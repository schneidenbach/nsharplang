namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
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

    // Interface/variance widening is outside this owner: a List receiver does not unify against an
    // IEnumerable<TSource> receiver slot even though the runtime conversion exists.
    listReceiver := ColumnarExtensionMethodResolver.Resolve(index, typeof(List<int>), "Take", ExtensionOneType(typeof(int)), oneArgumentFacts)
    assert !listReceiver.IsSelected, "List<int>.Take(int) stays with later owners until interface-receiver inference lands."
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

    // `string.Concat(params string[])` is the params shape the excluded-shape test has to see.
    concat := typeof(string).GetMethod("Concat", ConcatParamsSignature())
    assert concat != null
    assert ColumnarExtensionMethodResolver.HasExcludedParameterShape(concat.GetParameters())
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
