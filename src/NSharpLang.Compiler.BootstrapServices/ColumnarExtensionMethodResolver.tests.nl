namespace NSharpLang.Compiler.Columnar

import System
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
}

test "extension resolution declines generic-only, missing, and value-type receiver cases" {
    index := BuildLinqExtensionIndex()
    facts := ColumnarDirectCallArgumentFacts.Empty(0)

    // Enumerable.Select/Where are generic-only; the index build excludes generic methods, so no
    // non-generic candidate exists and resolution declines rather than binding a generic method.
    genericOnly := ColumnarExtensionMethodResolver.Resolve(index, typeof(int[]), "Select", new Type[](0), facts)
    assert !genericOnly.IsSelected, "A generic-only extension name must not bind."

    missing := ColumnarExtensionMethodResolver.Resolve(index, typeof(int[]), "TotallyMissingExtensionXyz", new Type[](0), facts)
    assert !missing.IsSelected, "An unknown extension name must decline."

    valueReceiver := ColumnarExtensionMethodResolver.Resolve(index, typeof(int), "Sum", new Type[](0), facts)
    assert !valueReceiver.IsSelected, "A value-type receiver is outside this extension-call surface."
}

test "extension resolution prefers exact arity over trailing-optional and rejects ambiguity" {
    facts := ColumnarDirectCallArgumentFacts.Empty(0)

    preference := new ColumnarExtensionMethodIndex()
    exactCandidate := MakeExtensionFixtureCandidate(
        RequiredExtensionStaticMethod(typeof(string), "IsNullOrEmpty", ExtensionOneType(typeof(string))))
    optionalCandidate := MakeExtensionFixtureCandidate(
        RequiredExtensionStaticMethod(RequiredExtensionFixtureType("System.ArgumentException"), "ThrowIfNullOrEmpty", ExtensionTwoTypes(typeof(string), typeof(string))))
    preference.Add("Combine", exactCandidate)
    preference.Add("Combine", optionalCandidate)

    selection := ColumnarExtensionMethodResolver.Resolve(preference, typeof(string), "Combine", new Type[](0), facts)
    assert selection.IsSelected, "An exact-arity extension must win over a trailing-optional overload."
    assert selection.ParameterTypes.Length == 1
    assert selection.ExplicitArgumentCount == 0

    ambiguous := new ColumnarExtensionMethodIndex()
    ambiguous.Add("Ambiguous", MakeExtensionFixtureCandidate(
        RequiredExtensionStaticMethod(typeof(string), "IsNullOrEmpty", ExtensionOneType(typeof(string)))))
    ambiguous.Add("Ambiguous", MakeExtensionFixtureCandidate(
        RequiredExtensionStaticMethod(typeof(string), "IsNullOrWhiteSpace", ExtensionOneType(typeof(string)))))

    ambiguousSelection := ColumnarExtensionMethodResolver.Resolve(ambiguous, typeof(string), "Ambiguous", new Type[](0), facts)
    assert !ambiguousSelection.IsSelected, "Two equally-ranked extensions across static classes must decline."
}

test "extension resolution fills a trailing optional null-default parameter" {
    facts := ColumnarDirectCallArgumentFacts.Empty(0)

    index := new ColumnarExtensionMethodIndex()
    // ArgumentNullException.ThrowIfNull(object value, string? paramName = null): the receiver slot is
    // `value` and `paramName` is a trailing optional with a null metadata default.
    optionalCandidate := MakeExtensionFixtureCandidate(
        RequiredExtensionStaticMethod(RequiredExtensionFixtureType("System.ArgumentNullException"), "ThrowIfNull", ExtensionTwoTypes(typeof(object), typeof(string))))
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
