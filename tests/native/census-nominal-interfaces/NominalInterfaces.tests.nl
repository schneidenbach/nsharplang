namespace NSharpLang.CensusNominalInterfaces.Tests

import System


// The interfaces a type's EMITTED METADATA lists, this project's own only, sorted — the answer
// `is`, `as`, a match arm and every other assembly read.
func DeclaredInterfaceNames(type: Type): string {
    interfaces := type.GetInterfaces()
    names := new string[](interfaces.Length)
    count := 0
    for index := 0; index < interfaces.Length; index++ {
        candidate := interfaces[index]
        if candidate.Namespace == "NSharpLang.CensusNominalInterfaces.Tests" {
            names[count] = candidate.Name
            count = count + 1
        }
    }
    kept := new string[](count)
    Array.Copy(names, kept, count)
    Array.Sort(kept, StringComparer.Ordinal)
    return string.Join(",", kept)
}

test "an empty plain interface is implemented by the class that names it and by no other type" {
    assert DeclaredInterfaceNames(typeof(Member)).Contains("IMarker")
    assert !DeclaredInterfaceNames(typeof(Stranger)).Contains("IMarker")
    assert !DeclaredInterfaceNames(typeof(Bare)).Contains("IMarker")
    assert !DeclaredInterfaceNames(typeof(Point)).Contains("IMarker")

    member: object = new Member()
    stranger: object = new Stranger()
    bare: object = new Bare()
    assert member is IMarker
    assert !(stranger is IMarker)
    assert !(bare is IMarker)
}

test "a plain interface with members is not implemented by a class that merely has matching members" {
    assert DeclaredInterfaceNames(typeof(Stranger)) == "IDuckEmpty,IDuckGreeter"
    assert DeclaredInterfaceNames(typeof(Member)) == "IDuckEmpty,IDuckGreeter,IGreeter,IMarker"

    stranger: object = new Stranger()
    assert !(stranger is IGreeter)
    assert (stranger as IGreeter) == null
    assert !typeof(IGreeter).IsAssignableFrom(typeof(Stranger))
    assert GreetThroughPlain(new Member()) == "member"
}

test "a plain interface that extends a duck interface is still nominal" {
    // `Stranger` has both `Greet` and `Name`, so it satisfies `INamedGreeter`'s whole closure; it
    // carries the DUCK base structurally and not the plain interface built on it.
    assert !typeof(INamedGreeter).IsAssignableFrom(typeof(Stranger))
    assert typeof(IDuckGreeter).IsAssignableFrom(typeof(Stranger))
}

test "a duck interface is still written onto every type that satisfies it, and dispatches through it" {
    // Unchanged duck behaviour: the match is structural, recorded in metadata, and a struct is
    // boxed into it.
    assert DeclaredInterfaceNames(typeof(Bare)) == "IDuckEmpty"
    assert DeclaredInterfaceNames(typeof(Point)) == "IDuckEmpty,IDuckGreeter"
    assert typeof(IDuckEmpty).IsAssignableFrom(typeof(Bare))
    assert typeof(IDuckGreeter).IsAssignableFrom(typeof(Member))
    assert GreetThroughDuck(new Stranger()) == "stranger"
    assert GreetThroughDuck(new Member()) == "member"
    point := new Point { X: 3 }
    assert GreetThroughDuck(point) == "point"

    stranger: object = new Stranger()
    assert stranger is IDuckGreeter
    assert stranger is IDuckEmpty
}

test "the emitted interfaces keep their written kind: both are interfaces, neither is a class" {
    assert typeof(IMarker).IsInterface
    assert typeof(IGreeter).IsInterface
    assert typeof(IDuckGreeter).IsInterface
    assert typeof(IDuckEmpty).IsInterface
    assert typeof(IMarker).GetInterfaces().Length == 0
    assert DeclaredInterfaceNames(typeof(INamedGreeter)) == "IDuckGreeter"
}
