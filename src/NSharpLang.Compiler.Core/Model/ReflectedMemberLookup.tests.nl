namespace NSharpLang.Compiler

import System
import System.Reflection
import System.Reflection.Emit

// THE HIDING RULE FOR A PROPERTY READ BY NAME (GitHub #239).
//
// `class Derived: Base` redeclares `Base`'s `P: object` as `P: string` — what C# spells `new string P`
// and what `DbContextOptionsBuilder<T>.Options` does to its base class's `Options`. The fixture is
// emitted with `Reflection.Emit` so the row needs neither a package nor a C# project. The first row
// proves the fixture is the ambiguous shape: the binder's own `GetProperty` throws on it.
func RmlDefineProperty(owner: TypeBuilder, name: string, propertyType: Type) {
    field := owner.DefineField("_" + name, propertyType, FieldAttributes.Private)
    getter := owner.DefineMethod("get_" + name, MethodAttributes.Public | MethodAttributes.SpecialName | MethodAttributes.HideBySig, propertyType, Type.EmptyTypes)
    il := getter.GetILGenerator()
    il.Emit(OpCodes.Ldarg_0)
    il.Emit(OpCodes.Ldfld, field)
    il.Emit(OpCodes.Ret)
    property := owner.DefineProperty(name, PropertyAttributes.None, propertyType, Type.EmptyTypes)
    property.SetGetMethod(getter)
}

func RmlHidingTypes(): Type[] {
    assembly := AssemblyBuilder.DefineDynamicAssembly(new AssemblyName("ReflectedMemberLookupFixture" + Guid.NewGuid().ToString("N")), AssemblyBuilderAccess.Run)
    module := assembly.DefineDynamicModule("Fixture")
    baseBuilder := module.DefineType("Base", TypeAttributes.Public | TypeAttributes.Class)
    RmlDefineProperty(baseBuilder, "P", typeof(object))
    RmlDefineProperty(baseBuilder, "Q", typeof(int))
    baseType := baseBuilder.CreateType() ?? typeof(object)
    derivedBuilder := module.DefineType("Derived", TypeAttributes.Public | TypeAttributes.Class, baseType)
    RmlDefineProperty(derivedBuilder, "P", typeof(string))
    derivedType := derivedBuilder.CreateType() ?? typeof(object)
    return [baseType, derivedType]
}

test "the fixture is the shape the binder refuses" {
    types := RmlHidingTypes()
    outcome := "no exception"
    try {
        types[1].GetProperty("P", BindingFlags.Public | BindingFlags.Instance)
    } catch ex: AmbiguousMatchException {
        outcome = "ambiguous"
    }
    assert outcome == "ambiguous"
}

test "the most derived declaration of a hidden property is the property" {
    types := RmlHidingTypes()
    found := ReflectedMemberLookup.FindProperty(types[1], "P", BindingFlags.Public | BindingFlags.Instance)
    assert found != null
    assert found.PropertyType == typeof(string)
    assert found.DeclaringType == types[1]
}

test "the default flags find the hidden property the same way" {
    types := RmlHidingTypes()
    found := ReflectedMemberLookup.FindProperty(types[1], "P")
    assert found != null
    assert found.PropertyType == typeof(string)
}

test "the base type still answers with its own declaration" {
    types := RmlHidingTypes()
    found := ReflectedMemberLookup.FindProperty(types[0], "P", BindingFlags.Public | BindingFlags.Instance)
    assert found != null
    assert found.PropertyType == typeof(object)
}

test "an unhidden inherited property and an absent one answer as the binder does" {
    types := RmlHidingTypes()
    inherited := ReflectedMemberLookup.FindProperty(types[1], "Q", BindingFlags.Public | BindingFlags.Instance)
    assert inherited != null
    assert inherited.PropertyType == typeof(int)
    assert ReflectedMemberLookup.FindProperty(types[1], "Missing", BindingFlags.Public | BindingFlags.Instance) == null
}
