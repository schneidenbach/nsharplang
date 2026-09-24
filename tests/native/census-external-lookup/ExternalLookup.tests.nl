namespace Census.Lookup.Consumer

import System


// A NAMESPACE'S MEMBERS ARE ITS TYPES, WHICHEVER ASSEMBLY COMPILED THEM.
//
// `Census.Lookup` is this project's ENCLOSING namespace and its types live in a referenced assembly
// (tests/fixtures/census-external-lookup-library). `SimpleNamePrecedence` rules 1 and 2 put them ahead
// of every import, exactly as they put a source declaration there — so `TypeInfo` in `Consumer.nl`
// binds `Census.Lookup.TypeInfo`, not the `System.Reflection.TypeInfo` or the source
// `Census.Lookup.Rival.TypeInfo` its two imports supply, and `Ast.Node` is read relative to the chain.
// Each row executes a binding and reads it back out of the emitted metadata, so a walk that bound the
// wrong type — or bound nothing and declined — fails here.
func LookupLibraryName(): string {
    return "NSharpLang.CensusExternalLookup.Library"
}

func ParameterTypeName(methodName: string): string {
    method := typeof(Consumers).GetMethod(methodName)
    assert method != null
    return method.GetParameters()[0].ParameterType.FullName ?? ""
}

func ReturnTypeName(methodName: string): string {
    method := typeof(Consumers).GetMethod(methodName)
    assert method != null
    return method.ReturnType.FullName ?? ""
}

test "a bare name binds the enclosing namespace's referenced-assembly type over two imports" {
    assert ParameterTypeName("Describe") == "Census.Lookup.TypeInfo"
    assert typeof(TypeInfo).FullName == "Census.Lookup.TypeInfo"
    assert typeof(TypeInfo).Assembly.GetName().Name == LookupLibraryName()
    assert Consumers.Describe(new TypeInfo()) == "lookup"
}

test "the rivals the imports supply are still reachable in full" {
    assert new Census.Lookup.Rival.TypeInfo().Side() == "rival"
    reflectionType: Type = typeof(System.Reflection.TypeInfo)
    assert reflectionType.FullName == "System.Reflection.TypeInfo"
}

test "a static receiver, a construction and a type argument bind the same enclosing type" {
    assert ReturnTypeName("Make") == "Census.Lookup.TypeInfo"
    assert Consumers.Make().Side() == "lookup"
    assert ReturnTypeName("Fresh") == "Census.Lookup.TypeInfo"
    assert Consumers.Fresh().Side() == "lookup"

    items := Consumers.Collect()
    assert items.Count == 1
    assert items[0].Side() == "lookup"
    assert ReturnTypeName("Collect").StartsWith("System.Collections.Generic.List`1[[Census.Lookup.TypeInfo,", StringComparison.Ordinal)
}

test "a type test binds the enclosing type, not an imported rival" {
    assert Consumers.IsLookup(new TypeInfo())
    assert !Consumers.IsLookup(new Census.Lookup.Rival.TypeInfo())
}

test "a qualifier is read through the enclosing chain into a referenced assembly" {
    assert ParameterTypeName("NodeKind") == "Census.Lookup.Ast.Node"
    assert ReturnTypeName("FreshNode") == "Census.Lookup.Ast.Node"
    assert Consumers.NodeKind(Consumers.FreshNode()) == "node"

    assert ParameterTypeName("LeftWho") == "Census.Lookup.Left.Widget"
    assert Consumers.LeftWho(new Left.Widget()) == "left"
    assert Consumers.RightWho() == "right"
}

test "a base class named by its bare name comes from the enclosing namespace's assembly" {
    baseType := typeof(Derived).BaseType
    assert baseType != null
    assert (baseType?.FullName ?? "") == "Census.Lookup.Base"
    assert new Derived().Twice() == "basebase"
}
