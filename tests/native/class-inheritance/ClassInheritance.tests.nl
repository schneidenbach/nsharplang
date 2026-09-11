namespace NSharpLang.ClassInheritance.Tests

import System
import System.Reflection


// THE RUNTIME HALF OF THE PROOF.
//
// `ClassInheritance.nl` compiling at all is the first half: `abstract func` used to fail to parse and
// `override` of a source-declared member used to fail to find a target. These tests are the second
// half. Two things could still be wrong in a program that builds: the override could have taken a NEW
// vtable slot (so a call through the base type would answer the BASE's implementation), and the
// metadata bits could be missing (so the type would load but `newobj` on an abstract class would be
// allowed and no other language could override the member). The behavioural tests below call
// everything through the statically declared base type; the metadata tests read the bits directly.

// Reflection answers `MethodInfo?` for a lookup by name, and every lookup below is for a member this
// project declares itself: a null here means the emitter did not write the member at all, which is a
// failure worth its own sentence rather than a null-dereference further down.
func DeclaredMethod(owner: Type, name: string): MethodInfo {
    method := owner.GetMethod(name)
    if method == null {
        throw new InvalidOperationException("'" + owner.Name + "' declares no method named '" + name + "'.")
    }
    return method
}

test "an override answers through the base type" {
    square := new Square(4)
    assert Dispatch.AreaOf(square) == 16
    assert Dispatch.DescribeOf(square) == "square"
    assert Dispatch.NameOf(square) == "square"
}

test "an abstract member has no base implementation to fall back to" {
    circle := new Circle(2)
    assert Dispatch.AreaOf(circle) == 12
}

test "a middle class's override is inherited by its own subclass" {
    circle := new Circle(2)
    // `Circle` overrides only `Area`. `Describe` must resolve to `Rounded`'s override, not to
    // `Shape`'s virtual implementation.
    assert Dispatch.DescribeOf(circle) == "rounded"
    assert Dispatch.NameOf(circle) == "rounded"
}

test "a class declared before its base still overrides it" {
    // `Circle` is written above `Rounded` in the source. If the declaration pass walked source order,
    // `Rounded` would not yet have declared `Describe` when `Circle` asked to override `Area`.
    circle := new Circle(3)
    assert circle.Radius == 3
    assert Dispatch.AreaOf(circle) == 27
}

test "a generic subclass of a non-generic base overrides it" {
    tagged := new Tagged<int>(7)
    assert tagged.Tag == 7
    assert Dispatch.AreaOf(tagged) == 0
    assert Dispatch.DescribeOf(tagged) == "tagged"
}

test "a subclass closing a generic base overrides both its members" {
    box := new StringBox("v")
    assert Dispatch.RenderOf(box) == "string-box-render"
    assert Dispatch.KindOf(box) == "string-box"
}

test "a generic subclass of a generic base overrides its abstract member" {
    pair := new PairBox<int>(1, 2)
    assert pair.Other == 2
    assert pair.Render() == "pair"
}

// ---- CLR metadata ----------------------------------------------------------------------------

test "an abstract class carries TypeAttributes.Abstract" {
    shape := typeof(Shape)
    assert shape.get_IsAbstract()
    assert !shape.get_IsSealed()
    // `abstract` is what the CLR consults for `newobj`, and it is also what every other .NET language
    // reads to know the type may not be constructed.
    assert (shape.get_Attributes() & TypeAttributes.Abstract) == TypeAttributes.Abstract
}

test "an abstract class in the middle of a chain is abstract too" {
    assert typeof(Rounded).get_IsAbstract()
    assert typeof(Box<string>).get_IsAbstract()
}

test "a concrete subclass is not abstract" {
    assert !typeof(Square).get_IsAbstract()
    assert !typeof(Circle).get_IsAbstract()
    assert !typeof(StringBox).get_IsAbstract()
}

test "the emitted base type is the declared one" {
    assert typeof(Square).get_BaseType() == typeof(Shape)
    assert typeof(Rounded).get_BaseType() == typeof(Shape)
    assert typeof(Circle).get_BaseType() == typeof(Rounded)
    assert typeof(StringBox).get_BaseType() == typeof(Box<string>)
}

test "an abstract member is virtual and abstract with no body" {
    area := DeclaredMethod(typeof(Shape), "Area")
    assert area.get_IsVirtual()
    assert area.get_IsAbstract()
    assert !area.get_IsFinal()
    // An abstract method has no IL at all: no RVA, so no method body to read.
    assert area.GetMethodBody() == null
}

test "a virtual member is virtual but not abstract" {
    describe := DeclaredMethod(typeof(Shape), "Describe")
    assert describe.get_IsVirtual()
    assert !describe.get_IsAbstract()
    assert !describe.get_IsFinal()
    assert describe.GetMethodBody() != null
}

test "an override is virtual and reuses the base slot" {
    area := DeclaredMethod(typeof(Square), "Area")
    assert area.get_IsVirtual()
    assert !area.get_IsAbstract()
    // REUSING THE SLOT IS THE WHOLE POINT. `GetBaseDefinition` walks back to the member that opened
    // the slot; if the override had taken a new one it would answer itself.
    assert area.GetBaseDefinition() == DeclaredMethod(typeof(Shape), "Area")
    assert area.GetBaseDefinition().get_DeclaringType() == typeof(Shape)
}

test "a sealed override is final" {
    describe := DeclaredMethod(typeof(Square), "Describe")
    assert describe.get_IsVirtual()
    assert describe.get_IsFinal()
    assert describe.GetBaseDefinition() == DeclaredMethod(typeof(Shape), "Describe")
}

test "an override that is not sealed is not final" {
    describe := DeclaredMethod(typeof(Rounded), "Describe")
    assert !describe.get_IsFinal()
}

test "a generic subclass's override reuses the non-generic base's slot" {
    area := DeclaredMethod(typeof(Tagged<int>), "Area")
    assert area.get_IsVirtual()
    assert area.GetBaseDefinition().get_DeclaringType() == typeof(Shape)
}

test "an override of a generic base's abstract member reuses its slot" {
    render := DeclaredMethod(typeof(StringBox), "Render")
    assert render.get_IsVirtual()
    assert !render.get_IsAbstract()
    assert render.GetBaseDefinition().get_DeclaringType() == typeof(Box<string>)
}

// ---- base member access ----------------------------------------------------------------------

// THE NON-VIRTUAL DISPATCH IS WHAT THIS ASSERTS. Each level's `Render` wraps its base's, so the one
// string names all three exactly once. A `callvirt` on `base.Render()` would re-enter the most
// derived override and never return.
test "base.Method() reaches the implementation the override replaced, through three levels" {
    assert LayerDispatch.RenderOf(new MiddleLayer()) == "middle(root)"
    assert LayerDispatch.RenderOf(new LeafLayer()) == "leaf(middle(root))"
}

test "a base call passes its own arguments after the receiver" {
    assert LayerDispatch.WrapOf(new MiddleLayer(), "x") == "m[x]"
}

test "base.Property reads the base's property, including one the direct base inherited" {
    middle := new MiddleLayer()
    assert middle.BaseLabel() == "layer"
    assert middle.BaseDepth() == 1

    leaf := new LeafLayer()
    assert leaf.BaseLabelFromLeaf() == "layer"
}

test "base. reaches a closed generic base's own implementation" {
    loud := new LoudBox("v")
    assert loud.Kind() == "string-box!"
    assert Dispatch.KindOf(loud) == "string-box!"
    // `Render` is inherited untouched from `StringBox`, so the base call did not disturb the slot.
    assert Dispatch.RenderOf(loud) == "string-box-render"
}

test "base. reaches System.Object when no base is written" {
    rooted := new RootedOnObject(5)
    // `System.Object.ToString` answers the runtime type's full name, so the string proves WHICH
    // implementation ran as well as that it ran at all.
    assert rooted.BaseText() == "NSharpLang.ClassInheritance.Tests.RootedOnObject"
    assert rooted.BaseHash() == rooted.BaseHash()
}
