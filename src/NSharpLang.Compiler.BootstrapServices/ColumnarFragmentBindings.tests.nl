namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func BindingNames(first: string): List<string> {
    names := new List<string>()
    names.Add(first)
    return names
}

func BindingEmptyNames(): string[] {
    return new string[](0)
}

func BindingRawTypeParameters(typeParameters: Dictionary<string, Type>): ColumnarFragmentBindings {
    emptyNames := BindingEmptyNames()
    return ColumnarFragmentBindings.FromRawFacts(
        new Dictionary<string, int>(StringComparer.Ordinal),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        new Dictionary<string, LocalBuilder>(StringComparer.Ordinal),
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        new Dictionary<string, (Box: LocalBuilder, ValueType: Type)>(StringComparer.Ordinal),
        null,
        null,
        new ColumnarStructDef[](0),
        new ColumnarUnionDef[](0),
        new Dictionary<string, string[]>(StringComparer.Ordinal),
        emptyNames,
        emptyNames,
        emptyNames,
        typeParameters)
}

func BindingSourceDefinition(runtimeName: string, declaredName: string, genericParameterCount: int = 0): ColumnarStructDef {
    builder := TypeOfCreateBuilder(
        runtimeName,
        runtimeName + ".Bindings.Tests",
        genericParameterCount)
    return new ColumnarStructDef(
        builder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        declaredName)
}

func BindingEmpty(): ColumnarFragmentBindings {
    return new ColumnarFragmentBindings(
        new Dictionary<string, int>(StringComparer.Ordinal),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        new Dictionary<string, LocalBuilder>(StringComparer.Ordinal),
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        BindingEmptyNames(),
        BindingEmptyNames(),
        BindingEmptyNames(),
        BindingEmptyNames(),
        BindingEmptyNames())
}

func BindingMakeGenericMethod(method: MethodBuilder, parameterName: string) {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string[])
    defineParameters := ExecutorRequiredMethod(
        typeof(MethodBuilder),
        "DefineGenericParameters",
        parameterTypes)
    names := new string[](1)
    names[0] = parameterName
    arguments := new object[](1)
    ExecutorSetObject(arguments, 0, names)
    TypeOfRequiredInvocation(defineParameters, method, arguments)
}

test "fragment bindings preserve raw maps and blocked-name precedence" {
    parameterOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    parameterOrdinals["parameter"] = 0
    parameterTypes := new Dictionary<string, Type>(StringComparer.Ordinal)
    parameterTypes["parameter"] = typeof(int)
    locals := new Dictionary<string, LocalBuilder>(StringComparer.Ordinal)
    enums := new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal)

    visibleCallables := BindingNames("visibleCallable")
    bindings := new ColumnarFragmentBindings(
        parameterOrdinals,
        parameterTypes,
        locals,
        enums,
        BindingNames("lifted"),
        BindingNames("boxed"),
        BindingNames("enclosing"),
        BindingNames("callable"),
        visibleCallables)

    assert bindings.ParameterOrdinals["parameter"] == 0
    assert bindings.ParameterTypes["parameter"] == typeof(int)
    assert bindings.IsValueBinding("parameter")
    assert bindings.IsBlocked("lifted")
    assert bindings.IsBlocked("boxed")
    assert bindings.IsBlocked("enclosing")
    assert !bindings.IsBlocked("parameter")
    assert bindings.IsCallable("callable")
    assert bindings.IsCallable("visibleCallable")
    assert !bindings.IsCallable("parameter")
}

test "fragment bindings observe live shadow and textual-callable sources" {
    parameterOrdinals := new Dictionary<string, int>(StringComparer.Ordinal)
    parameterTypes := new Dictionary<string, Type>(StringComparer.Ordinal)
    locals := new Dictionary<string, LocalBuilder>(StringComparer.Ordinal)
    enums := new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal)
    lifted := new HashSet<string>(StringComparer.Ordinal)
    boxed := new HashSet<string>(StringComparer.Ordinal)
    enclosing := new HashSet<string>(StringComparer.Ordinal)
    declaredCallables := new HashSet<string>(StringComparer.Ordinal)
    visibleCallables := new HashSet<string>(StringComparer.Ordinal)

    bindings := new ColumnarFragmentBindings(
        parameterOrdinals,
        parameterTypes,
        locals,
        enums,
        lifted,
        boxed,
        enclosing,
        declaredCallables,
        visibleCallables)

    assert !bindings.IsBlocked("laterLifted")
    assert !bindings.IsBlocked("laterBoxed")
    assert !bindings.IsBlocked("laterEnclosing")
    assert !bindings.IsCallable("laterDeclared")
    assert !bindings.IsCallable("laterVisible")

    lifted.Add("laterLifted")
    boxed.Add("laterBoxed")
    enclosing.Add("laterEnclosing")
    declaredCallables.Add("laterDeclared")
    visibleCallables.Add("laterVisible")

    assert bindings.IsBlocked("laterLifted")
    assert bindings.IsBlocked("laterBoxed")
    assert bindings.IsBlocked("laterEnclosing")
    assert bindings.IsCallable("laterDeclared")
    assert bindings.IsCallable("laterVisible")

    parameterOrdinals["laterParameter"] = 2
    parameterTypes["laterParameter"] = typeof(Index)
    assert bindings.IsValueBinding("laterParameter")
}

test "fragment bindings merge live method and enclosing type parameter handles by lexical precedence" {
    methodOwner := BindingSourceDefinition(
        "GenericBindingMethodOwner", "GenericBindingMethodOwner", 0)
    noParameters := new Type[](0)
    methodDefinition := SourceCallPublicStatic(
        methodOwner,
        "GenericBindingMethod",
        noParameters,
        typeof(int))
    BindingMakeGenericMethod(methodDefinition.Builder, "T0")
    methodArguments := methodDefinition.Builder.GetGenericArguments()
    methodParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    methodParameters["T0"] = methodArguments[0]
    bindings := BindingRawTypeParameters(methodParameters)

    owner := BindingSourceDefinition("GenericBindingOwner", "GenericBindingOwner", 2)
    ownerArguments := owner.Builder.GetGenericArguments()
    ownerParameters := new Dictionary<string, Type>(StringComparer.Ordinal)
    ownerParameters["T0"] = ownerArguments[0]
    ownerParameters["T1"] = ownerArguments[1]
    owner.GenericParameters = ownerParameters
    bindings.SetEnclosingTypeDefinition(owner)

    resolved := typeof(object)
    assert bindings.TryGetTypeParameter("T0", out resolved)
    assert ColumnarConstructionPlanner.SameObject(
        resolved, methodArguments[0])
    assert bindings.TryGetTypeParameter("T1", out resolved)
    assert ColumnarConstructionPlanner.SameObject(
        resolved, ownerArguments[1])
    assert !bindings.TryGetTypeParameter("Missing", out resolved)
    assert bindings.EnclosingTypeDefinition == owner
}

test "fragment bindings reject malformed raw type parameter facts" {
    invalid := new Dictionary<string, Type>(StringComparer.Ordinal)
    invalid[""] = typeof(int)
    assert throws InvalidOperationException {
        BindingRawTypeParameters(invalid)
    }
}

test "selected source type resolution prefers exact identity and deduplicates registry aliases" {
    alpha := BindingSourceDefinition("Alpha.Widget", "Alpha.Widget", 0)
    beta := BindingSourceDefinition("Beta.Widget", "Beta.Widget", 0)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(alpha)
    definitions.Add(alpha)
    definitions.Add(beta)

    bindings := BindingEmpty()
    bindings.SourceTypeDefinitions = definitions
    resolved := typeof(object)
    assert bindings.TryResolveSelectedSourceType("Alpha.Widget", "Widget", out resolved)
    assert ColumnarConstructionPlanner.SameObject(
        resolved, alpha.Builder)
}

test "selected source type declaration bridge requires one distinct candidate" {
    selected := BindingSourceDefinition(
        "SelectedRuntimeWidget", "Widget", 0)
    uniqueDefinitions := new List<ColumnarStructDef>()
    uniqueDefinitions.Add(selected)
    unique := BindingEmpty()
    unique.SourceTypeDefinitions = uniqueDefinitions

    resolved := typeof(object)
    assert unique.TryResolveSelectedSourceType("Selected.Widget", "Widget", out resolved)
    assert ColumnarConstructionPlanner.SameObject(
        resolved, selected.Builder)

    first := BindingSourceDefinition("FirstRuntimeWidget", "Widget", 0)
    second := BindingSourceDefinition("SecondRuntimeWidget", "Widget", 0)
    ambiguousDefinitions := new List<ColumnarStructDef>()
    ambiguousDefinitions.Add(first)
    ambiguousDefinitions.Add(second)
    ambiguous := BindingEmpty()
    ambiguous.SourceTypeDefinitions = ambiguousDefinitions
    assert !ambiguous.TryResolveSelectedSourceType("Selected.Widget", "Widget", out resolved)
}

test "selected source type resolution inspects enum and union definitions without alias ambiguity" {
    enumDefinition := new ColumnarEnumDef(
        typeof(int),
        new Dictionary<string, int>(StringComparer.Ordinal),
        null,
        "Palette.Color")
    fallbackDefinition := new ColumnarEnumDef(
        typeof(long),
        new Dictionary<string, int>(StringComparer.Ordinal),
        null,
        "Other.Color")
    enumBindings := BindingEmpty()
    enumBindings.Enums["Color"] = enumDefinition
    enumBindings.Enums["LegacyColor"] = enumDefinition
    enumBindings.Enums["Palette.Color"] = fallbackDefinition

    resolved := typeof(object)
    assert enumBindings.TryResolveSelectedSourceType("Palette.Color", "Color", out resolved)
    assert resolved == typeof(int)

    unionSource := BindingSourceDefinition(
        "Results.Outcome", "Results.Outcome", 0)
    unionDefinition := new ColumnarUnionDef(unionSource.Builder, 0, "Results.Outcome")
    unions := new List<ColumnarUnionDef>()
    unions.Add(unionDefinition)
    unions.Add(unionDefinition)
    unionBindings := BindingEmpty()
    unionBindings.SourceUnionDefinitions = unions
    assert unionBindings.TryResolveSelectedSourceType("Results.Outcome", "Outcome", out resolved)
    assert ColumnarConstructionPlanner.SameObject(
        resolved, unionSource.Builder)
}
