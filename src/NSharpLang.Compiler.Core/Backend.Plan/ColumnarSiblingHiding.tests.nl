namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Collections.ObjectModel
import System.Reflection.Emit


func HidingSiblingFacts(): ColumnarSiblingCallFacts {
    method := typeof(string).GetMethod("IsNullOrEmpty", [typeof(string)])
    return new ColumnarSiblingCallFacts(must method, [typeof(string)], [0], typeof(bool), 0)
}

test "a member anywhere on the source chain hides a sibling of its name, and nothing else does" {
    baseDefinition := BindingSourceDefinition("Hiding.Base", "Hiding.Base")
    derivedDefinition := BindingSourceDefinition("Hiding.Derived", "Hiding.Derived")
    derivedDefinition.BaseDef = baseDefinition
    derivedDefinition.StaticFields["Own"] = ConstructionDefineField(derivedDefinition.Builder, "Own", typeof(int), 22)
    baseDefinition.Fields["Inherited"] = ConstructionDefineField(baseDefinition.Builder, "Inherited", typeof(int), 6)

    assert ColumnarSiblingHiding.IsHiddenByEnclosingMember(derivedDefinition, "Own")
    assert ColumnarSiblingHiding.IsHiddenByEnclosingMember(derivedDefinition, "Inherited")
    assert !ColumnarSiblingHiding.IsHiddenByEnclosingMember(derivedDefinition, "Absent")
    // The BASE does not see what the derived type declares.
    assert !ColumnarSiblingHiding.IsHiddenByEnclosingMember(baseDefinition, "Own")
    // A free function's own body has no enclosing type, and a blank name is no name.
    assert !ColumnarSiblingHiding.IsHiddenByEnclosingMember(null, "Own")
    assert !ColumnarSiblingHiding.IsHiddenByEnclosingMember(derivedDefinition, "")
}

test "a closure display hides what the type it was written in hides, and a free function's display hides nothing" {
    owner := BindingSourceDefinition("Hiding.Owner", "Hiding.Owner")
    owner.StaticFields["Label"] = ConstructionDefineField(owner.Builder, "Label", typeof(int), 22)
    display := new ColumnarStructDef(
        TypeOfCreateBuilder("Hiding.Display", "Hiding.Display.Tests", 0),
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        true,
        "<>c__DisplayClass0"
    )
    // A captured local is a display FIELD, and a field of the display is not a member of any type.
    display.Fields["Label"] = ConstructionDefineField(display.Builder, "Label", typeof(int), 6)
    assert !ColumnarSiblingHiding.IsHiddenByEnclosingMember(display, "Label")

    // A nested display reaches the declaring type through each enclosing display in turn.
    nested := new ColumnarStructDef(
        TypeOfCreateBuilder("Hiding.Nested", "Hiding.Nested.Tests", 0),
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        true,
        "<>c__DisplayClass1"
    )
    nested.ClosureEnclosingDef = display
    display.ClosureEnclosingDef = owner
    assert ColumnarSiblingHiding.IsHiddenByEnclosingMember(display, "Label")
    assert ColumnarSiblingHiding.IsHiddenByEnclosingMember(nested, "Label")
    assert !ColumnarSiblingHiding.IsHiddenByEnclosingMember(nested, "Absent")
}

test "an external base hides with what it exposes to a derived type: public and protected, never private or internal" {
    names := BindingSourceDefinition("Hiding.Names", "Hiding.Names")
    names.ExactBaseType = typeof(List<string>)
    assert ColumnarSiblingHiding.IsHiddenByEnclosingMember(names, "Contains")
    assert ColumnarSiblingHiding.IsHiddenByEnclosingMember(names, "Count")
    // Inherited from `object` THROUGH the written base, as the analyzer's member resolution reads it.
    assert ColumnarSiblingHiding.IsHiddenByEnclosingMember(names, "GetHashCode")
    assert !ColumnarSiblingHiding.IsHiddenByEnclosingMember(names, "_items")
    assert !ColumnarSiblingHiding.IsHiddenByEnclosingMember(names, "_version")
    assert !ColumnarSiblingHiding.IsHiddenByEnclosingMember(names, "Absent")

    collection := BindingSourceDefinition("Hiding.Collection", "Hiding.Collection")
    collection.ExactBaseType = typeof(Collection<string>)
    assert ColumnarSiblingHiding.IsHiddenByEnclosingMember(collection, "Items")
    assert ColumnarSiblingHiding.IsHiddenByEnclosingMember(collection, "InsertItem")

    // A source type with no written base inherits nothing that hides: `object`'s members do not.
    plain := BindingSourceDefinition("Hiding.Plain", "Hiding.Plain")
    assert !ColumnarSiblingHiding.IsHiddenByEnclosingMember(plain, "GetHashCode")
}

test "fragment bindings stop offering a sibling the enclosing type hides, by every door" {
    owner := BindingSourceDefinition("Hiding.Bindings", "Hiding.Bindings")
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
    bindings.SiblingCallables["Label"] = HidingSiblingFacts()
    bindings.SiblingCallables["Other"] = HidingSiblingFacts()

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
