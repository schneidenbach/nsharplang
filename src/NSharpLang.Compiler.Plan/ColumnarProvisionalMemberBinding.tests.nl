namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Collections.ObjectModel
import System.Reflection.Emit

func CollisionSiblingFacts(): ColumnarSiblingCallFacts {
    method := typeof(string).GetMethod("IsNullOrEmpty", [typeof(string)])
    return new ColumnarSiblingCallFacts(must method, [typeof(string)], [0], typeof(bool), 0)
}

test "a member anywhere on the source chain keeps the planner's provisional member binding" {
    baseDefinition := BindingSourceDefinition("MemberBinding.Base", "MemberBinding.Base")
    derivedDefinition := BindingSourceDefinition("MemberBinding.Derived", "MemberBinding.Derived")
    derivedDefinition.BaseDef = baseDefinition
    derivedDefinition.StaticFields["Own"] = ConstructionDefineField(derivedDefinition.Builder, "Own", typeof(int), 22)
    baseDefinition.Fields["Inherited"] = ConstructionDefineField(baseDefinition.Builder, "Inherited", typeof(int), 6)

    assert ColumnarProvisionalMemberBinding.HasEnclosingMember(derivedDefinition, "Own")
    assert ColumnarProvisionalMemberBinding.HasEnclosingMember(derivedDefinition, "Inherited")
    assert !ColumnarProvisionalMemberBinding.HasEnclosingMember(derivedDefinition, "Absent")
    // The BASE does not bind a member declared only by the derived type.
    assert !ColumnarProvisionalMemberBinding.HasEnclosingMember(baseDefinition, "Own")
    // A free function's own body has no enclosing type, and a blank name is no name.
    assert !ColumnarProvisionalMemberBinding.HasEnclosingMember(null, "Own")
    assert !ColumnarProvisionalMemberBinding.HasEnclosingMember(derivedDefinition, "")
}

test "closure displays preserve the enclosing type's provisional member binding" {
    owner := BindingSourceDefinition("MemberBinding.Owner", "MemberBinding.Owner")
    owner.StaticFields["Label"] = ConstructionDefineField(owner.Builder, "Label", typeof(int), 22)
    display := new ColumnarStructDef(
        TypeOfCreateBuilder("MemberBinding.Display", "MemberBinding.Display.Tests", 0),
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        true,
        "<>c__DisplayClass0"
    )
    // A captured local is a display FIELD, and a field of the display is not a member of any type.
    display.Fields["Label"] = ConstructionDefineField(display.Builder, "Label", typeof(int), 6)
    assert !ColumnarProvisionalMemberBinding.HasEnclosingMember(display, "Label")

    // A nested display reaches the declaring type through each enclosing display in turn.
    nested := new ColumnarStructDef(
        TypeOfCreateBuilder("MemberBinding.Nested", "MemberBinding.Nested.Tests", 0),
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        true,
        "<>c__DisplayClass1"
    )
    nested.ClosureEnclosingDef = display
    display.ClosureEnclosingDef = owner
    assert ColumnarProvisionalMemberBinding.HasEnclosingMember(display, "Label")
    assert ColumnarProvisionalMemberBinding.HasEnclosingMember(nested, "Label")
    assert !ColumnarProvisionalMemberBinding.HasEnclosingMember(nested, "Absent")
}

test "external base members keep provisional binding when they are exposed to a derived type" {
    names := BindingSourceDefinition("MemberBinding.Names", "MemberBinding.Names")
    names.ExactBaseType = typeof(List<string>)
    assert ColumnarProvisionalMemberBinding.HasEnclosingMember(names, "Contains")
    assert ColumnarProvisionalMemberBinding.HasEnclosingMember(names, "Count")
    // Inherited from `object` THROUGH the written base, as the analyzer's member resolution reads it.
    assert ColumnarProvisionalMemberBinding.HasEnclosingMember(names, "GetHashCode")
    assert !ColumnarProvisionalMemberBinding.HasEnclosingMember(names, "_items")
    assert !ColumnarProvisionalMemberBinding.HasEnclosingMember(names, "_version")
    assert !ColumnarProvisionalMemberBinding.HasEnclosingMember(names, "Absent")

    collection := BindingSourceDefinition("MemberBinding.Collection", "MemberBinding.Collection")
    collection.ExactBaseType = typeof(Collection<string>)
    assert ColumnarProvisionalMemberBinding.HasEnclosingMember(collection, "Items")
    assert ColumnarProvisionalMemberBinding.HasEnclosingMember(collection, "InsertItem")

    // A source type with no written base inherits no collision from `object`.
    plain := BindingSourceDefinition("MemberBinding.Plain", "MemberBinding.Plain")
    assert !ColumnarProvisionalMemberBinding.HasEnclosingMember(plain, "GetHashCode")
}

test "fragment bindings keep a colliding sibling out of every provisional binding door" {
    owner := BindingSourceDefinition("MemberBinding.Bindings", "MemberBinding.Bindings")
    owner.StaticFields["Label"] = ConstructionDefineField(owner.Builder, "Label", typeof(int), 22)
    emptyNames := BindingEmptyNames()
    bindings := new ColumnarFragmentBindings(
        new Dictionary<string, int>(StringComparer.Ordinal),
        new Dictionary<string, Type>(StringComparer.Ordinal),
        new Dictionary<string, LocalBuilder>(StringComparer.Ordinal),
        new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
        emptyNames,
        emptyNames,
        emptyNames,
        ["Label", "Other"],
        emptyNames
    )
    bindings.SiblingCallables["Label"] = CollisionSiblingFacts()
    bindings.SiblingCallables["Other"] = CollisionSiblingFacts()

    // Outside every type both siblings are what their names mean.
    let facts: ColumnarSiblingCallFacts? = null
    assert bindings.HasSiblingCallable("Label")
    assert bindings.IsCallable("Label")
    assert bindings.TryGetSiblingCallable("Label", out facts) && facts != null

    bindings.SetEnclosingTypeDefinition(owner)
    assert !bindings.HasSiblingCallable("Label")
    assert !bindings.IsCallable("Label")
    assert !bindings.TryGetSiblingCallable("Label", out facts)
    assert facts == null
    assert bindings.HasSiblingCallable("Other")
    assert bindings.IsCallable("Other")
    assert bindings.TryGetSiblingCallable("Other", out facts) && facts != null
}
