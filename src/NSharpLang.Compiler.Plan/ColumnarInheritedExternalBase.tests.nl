namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Collections.ObjectModel
import System.Reflection
import System.Reflection.Emit


// THE STATIC SURFACE OF AN EXTERNAL BASE CLOSED OVER A TYPE THIS COMPILATION IS WRITING.
//
// The bindings ask `TryResolveStaticMember` about EVERY bare name inside a derived type, and for
// `class Tags: List<Tag>` the base is a builder instantiation whose every member query throws — so
// that one question took down any bare call in the type (`Add(tag)` declined as an internal error).
// The fixture is `ColumnarExternalBaseConstructors.tests.nl`'s: a real generic definition closed over
// a `TypeBuilder`, which is exactly the shape emission sees.
func InheritedStaticBuilderBound(openDefinition: Type, name: string): Type {
    sourceType: Type = ExternalBaseCtorSourceTypeBuilder(name)
    return openDefinition.MakeGenericType([sourceType])
}

test "a static property the definition declares is rebound onto the builder instantiation" {
    builderBound := InheritedStaticBuilderBound(typeof(Comparer<int>).GetGenericTypeDefinition(), "InheritedStaticDefault")

    // Asking the instantiation itself still throws, so reading the definition is necessary.
    threw := false
    try {
        builderBound.GetProperty("Default", BindingFlags.Public | BindingFlags.Static)
    } catch {
        threw = true
    }
    assert threw

    field: FieldInfo? = null
    getter: MethodInfo? = null
    memberType: Type? = null
    assert ColumnarInheritedExternalBase.TryResolveBuilderBoundStaticMember(builderBound, "Default", out field, out getter, out memberType)
    assert field == null
    assert getter != null
    assert memberType != null

    // The handle belongs to the INSTANTIATION, and the type names the source argument, not `T`.
    assert getter.get_DeclaringType() == builderBound
    assert memberType.get_IsGenericType()
    assert memberType.GetGenericTypeDefinition() == typeof(Comparer<int>).GetGenericTypeDefinition()
    assert memberType.GetGenericArguments()[0] is TypeBuilder
}

test "a name that is not a public static member of the definition answers nothing" {
    builderBound := InheritedStaticBuilderBound(typeof(Collection<int>).GetGenericTypeDefinition(), "InheritedStaticMissing")

    field: FieldInfo? = null
    getter: MethodInfo? = null
    memberType: Type? = null

    // `Count` is an INSTANCE property, and `Nope` is nothing at all; neither may throw.
    assert !ColumnarInheritedExternalBase.TryResolveBuilderBoundStaticMember(builderBound, "Count", out field, out getter, out memberType)
    assert !ColumnarInheritedExternalBase.TryResolveBuilderBoundStaticMember(builderBound, "Nope", out field, out getter, out memberType)
    assert getter == null
    assert memberType == null
}
