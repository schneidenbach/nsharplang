namespace NSharpLang.CensusEmitShapes.Tests


// EVERY TYPE INHERITS `System.Object`'S OWN INSTANCE MEMBERS, INCLUDING THE ONES THIS COMPILATION
// IS STILL BUILDING.
//
// `GetType`, `ToString`, `GetHashCode` and `Equals(object)` are members of every receiver there is.
// A source receiver is a `TypeBuilder`, which answers no member query, and its implicit
// `System.Object` base was reported as no inherited surface at all — so `thing.GetType().Name`
// declined while `(thing as object).GetType().Name` emitted: the same call, through a cast that
// changes nothing about which method runs.
class Thing {
    Name: string

    // The same question asked from INSIDE the type, through a binding and through `this`. A source
    // class with no `:` clause still HAS a base, and it is `System.Object`: the inherited-external
    // walk reported the implicit base as no answer, so `this.GetType()` was claimed and rejected
    // before any member resolution ran while `(this as object).GetType()` emitted.
    func Describe(other: Thing): string {
        return other.GetType().Name + ":" + other.Name
    }

    func OwnTypeName(): string {
        return this.GetType().Name
    }

    func OwnHash(): int {
        return this.GetHashCode()
    }

    func IsSelf(other: object): bool {
        return this.Equals(other)
    }
}

class Named: Thing {
}

struct Extent {
    Width: int
    Height: int
}

func TypeNameOf(thing: Thing): string {
    return thing.GetType().Name
}

func TypeNameOfStruct(extent: Extent): string {
    return extent.GetType().Name
}

// `GetType` IS NOT VIRTUAL, so the receiver's RUNTIME type answers — a derived instance through a
// base-typed binding names the derived type, exactly as the CLR defines it.
func BoxedTypeNameOf(thing: Thing): string {
    return (thing as object).GetType().Name
}

func HashesAgree(thing: Thing): bool {
    return thing.GetHashCode() == (thing as object).GetHashCode()
}

func StructuralToString(extent: Extent): string {
    return extent.ToString() ?? ""
}
