namespace NSharpLang.ClassInheritance.Tests

import System
import System.Collections.Generic
import System.Collections.ObjectModel
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

// AN EXTERNAL BASE'S CONSTRUCTOR, CALLED WITH ARGUMENTS. Each of these declined the whole assembly
// before the base chain could reach a constructor that is not a `ConstructorBuilder`. The proof is
// that the base's own state is what the base constructor was given.
test "a class chains to an external base constructor with one argument" {
    sized := new SizedList(9)
    assert sized.Capacity == 9
    assert sized.Count == 0
}

test "an external base constructor taking a sequence receives it" {
    source: string[] = ["a", "b"]
    seeded := new SeededList(source)
    assert seeded.Count == 2
    assert seeded[0] == "a"
    assert seeded[1] == "b"
}

test "two external base constructors are told apart by their arguments" {
    inner := new LayerError("inner")
    assert inner.Message == "inner"
    assert inner.InnerException == null

    outer := new LayerError("outer", inner)
    assert outer.Message == "outer"
    assert (must outer.InnerException).Message == "inner"
}

test "an external base with several same-arity overloads selects by argument type" {
    compared := new ComparedMap(StringComparer.OrdinalIgnoreCase)
    compared["Alpha"] = 1
    assert compared.ContainsKey("alpha")

    sizedAndCompared := new ComparedMap(8, StringComparer.Ordinal)
    sizedAndCompared["Alpha"] = 1
    assert !sizedAndCompared.ContainsKey("alpha")
}

// AN INHERITED EXTERNAL MEMBER, THROUGH THE DERIVED TYPE. Each of these reported NL402 or declined
// the assembly before the base chain was walked past its last source link; the assertions are on the
// VALUES, because a call that binds the wrong member still compiles.
test "a property of an external base is read through the derived type" {
    names := new Names()
    names.Add("alpha")
    names.Add("beta")

    assert names.Count == 2
    assert names.ExplicitCount() == 2
    assert names.BaseCount() == 2
    assert names.Summary() == "2 names"
}

test "a method of an external base binds its substituted parameter" {
    names := new Names()
    names.Add("alpha")
    names.Add("beta")
    names.Add("alpha")

    assert names.Contains("alpha")
    assert !names.Contains("gamma")
    assert names.IndexOf("alpha") == 0
    assert names.IndexOf("alpha", 1) == 2
    assert names.Remove("beta")
    assert names.Count == 2
}

test "an external base's indexer is read and written through the derived type" {
    names := new Names()
    names.Add("alpha")
    names.Add("beta")

    assert names[1] == "beta"
    names[1] = "gamma"
    assert names[1] == "gamma"
}

test "a method of an external base takes a lambda argument" {
    names := new Names()
    names.Add("alpha")
    names.Add("be")

    assert names.Exists(name => name.Length == 2)
    assert !names.Exists(name => name.Length == 7)
    assert names.Find(name => name.Length == 2) == "be"
}

test "a generic method of an external base takes its written type argument" {
    names := new Names()
    names.Add("alpha")
    names.Add("be")

    lengths := names.ConvertAll<int>(name => name.Length)
    assert lengths.Count == 2
    assert lengths[0] == 5
    assert lengths[1] == 2
}

test "a base two source links up still answers through the external base" {
    deeper := new DeeperNames()
    deeper.Add("alpha")

    assert deeper.Count == 1
    assert deeper[0] == "alpha"
    assert deeper.Summary() == "1 names"
    assert deeper.IndexOf("alpha") == 0
}

test "each argument of a two-argument external base substitutes by position" {
    counts := new Counts()
    counts.Add("alpha", 3)
    counts["beta"] = 4

    assert counts.Count == 2
    assert counts["alpha"] == 3
    assert counts.ContainsKey("beta")
    assert !counts.ContainsValue(9)

    seen := 0
    if counts.TryGetValue("beta", out seen) {
        assert seen == 4
    } else {
        assert false
    }
}

// THE INTERFACES THE EXTERNAL BASE IMPLEMENTS ARE THE DERIVED TYPE'S TOO, which is both a conversion
// the compiler must allow and a fact the CLR must agree with at run time.
test "an interface the external base implements is reached through the derived type" {
    names := new Names()
    names.Add("alpha")
    names.Add("be")

    sequence: IEnumerable<string> = names
    total := 0
    for name in sequence {
        total = total + name.Length
    }
    assert total == 7

    list: IList<string> = names
    assert list.Count == 2
    assert list[0] == "alpha"

    assert (names is IReadOnlyList<string>)
}

test "a derived collection is accepted where its external base is expected" {
    names := new Names()
    names.Add("alpha")

    copied := new List<string>()
    copied.AddRange(names)
    assert copied.Count == 1
    assert copied[0] == "alpha"

    deeper := new DeeperNames()
    deeper.AddRange(names)
    assert deeper.Count == 1
}

test "an unqualified inherited member is read inside the type's own override" {
    tagged := new TaggedError("io", "disk full")

    assert tagged.Message == "disk full"
    assert tagged.ToString() == "io:disk full"

    thrown: Exception = tagged
    assert thrown.Message == "disk full"
    assert thrown.ToString() == "io:disk full"
}

// THE METADATA SIDE: the derived type's CLR parent IS the external base, closed over the arguments
// its `:` clause wrote, and the members above are the base's own rather than copies in new slots.
test "the emitted parent of a derived type is the external base it wrote" {
    namesType := typeof(Names)
    assert namesType.BaseType == typeof(List<string>)
    assert typeof(DeeperNames).BaseType == namesType
    assert typeof(Counts).BaseType == typeof(Dictionary<string, int>)
    assert typeof(TaggedError).BaseType == typeof(Exception)

    assert namesType.GetMethod("Add") != null
    assert (must namesType.GetMethod("Add")).DeclaringType == typeof(List<string>)
    assert (must namesType.GetProperty("Count")).DeclaringType == typeof(List<string>)
}

test "a static member of an external base is read through the derived type" {
    shared := SharedRandom.Shared
    assert shared != null

    // It IS the base's one shared instance, not a new one: a static member belongs to the type that
    // declares it, and naming a derived type does not give it a second copy.
    assert Object.ReferenceEquals(shared, Random.Shared)
}

// THE GENERIC EXTERNAL BASE CLOSED OVER A SOURCE TYPE. The build succeeding is the first half of the
// proof — this shape used to crash `nlc check` outright — and these are the second: the type really
// IS that instantiation, its inherited members really run, and the explicit base chain really passed
// its argument to the base constructor it selected.
test "a base closed over a source type is the parent the source wrote" {
    assert typeof(Catalogue).BaseType == typeof(Collection<Catalogued>)
    assert typeof(SeededCatalogue).BaseType == typeof(Collection<Catalogued>)
}

test "an inherited member of a base closed over a source type runs" {
    catalogue := new Catalogue()
    assert catalogue.Size() == 0

    catalogue.Add(new Catalogued("first"))
    catalogue.Add(new Catalogued("second"))
    assert catalogue.Size() == 2
    assert catalogue.Count == 2
    assert catalogue[1].Title == "second"
}

test "an explicit base chain into a base closed over a source type passes its argument" {
    seed := new List<Catalogued>()
    seed.Add(new Catalogued("seeded"))

    catalogue := new SeededCatalogue(seed)
    assert catalogue.Count == 1
    assert catalogue[0].Title == "seeded"
}

// ---- an override's accessibility ---------------------------------------------------------------

// `GetMethod(name)` is public-only, and the whole point here is a PROTECTED slot.
func DeclaredNonPublicMethod(owner: Type, name: string): MethodInfo {
    method := owner.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.DeclaredOnly)
    if method == null {
        throw new InvalidOperationException("'" + owner.Name + "' declares no method named '" + name + "'.")
    }
    return method
}

test "an override that MATCHES its slot's accessibility loads and dispatches" {
    matched: Guarded = new MatchedGuard()
    assert matched.Read() == "matched"

    label := DeclaredNonPublicMethod(typeof(MatchedGuard), "Label")
    assert label.get_IsFamily()
    assert label.get_IsVirtual()
    assert label.GetBaseDefinition() == DeclaredNonPublicMethod(typeof(Guarded), "Label")
}

test "an override that WIDENS its slot's accessibility loads too — only reducing is refused" {
    widened: Guarded = new WidenedGuard()
    assert widened.Read() == "widened"

    label := DeclaredNonPublicMethod(typeof(WidenedGuard), "Label")
    assert label.get_IsPublic()
    assert label.get_IsVirtual()
    // WIDENING STILL REUSES THE SLOT. If it had taken a new one the base receiver above would have
    // answered "guarded", and `GetBaseDefinition` would answer itself.
    assert label.GetBaseDefinition() == DeclaredNonPublicMethod(typeof(Guarded), "Label")
}
