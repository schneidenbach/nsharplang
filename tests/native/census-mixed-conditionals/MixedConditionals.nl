namespace NSharpLang.CensusMixedConditionals.Tests

import System


// CONDITIONALS WHOSE TWO BRANCHES HAVE TWO DIFFERENT TYPES, each one compiled through the product path.
//
// Every shape here passed analysis and then declined in the backend (NL103) before the backend learned
// to write a conditional arm by arm as a TARGET type. Each member returns something that shows the
// STATIC type the conditional was given, not only its value: an overload chosen by that type, or the
// CLR type of the boxed result.
class Animal {
    func Speak(): string => "animal"
}

class Dog: Animal {
    func Fetch(): string => "fetch"
}

class Cat: Animal {}

class Kinds {
    // Chosen by the STATIC type of the argument: a conditional typed `Animal` picks the first even when
    // the value it produced at run time is a `Dog`.
    static func Of(_value: Animal): string => "Animal"
    static func Of(_value: Dog): string => "Dog"

    // A group in which only `object` fits both `int` and `string`.
    static func Show(_value: int): string => "int"
    static func Show(_value: object): string => "object"
}

class MixedConditionals {
    // ── no target: the natural type ─────────────────────────────────────────────────────────────

    // `Dog` converts to `Animal` and not back, so the conditional is an `Animal`.
    static func NaturalReference(flag: bool): string {
        pet := flag ? new Dog() : new Animal()
        return Kinds.Of(pet) + ":" + pet.GetType().Name + ":" + pet.Speak()
    }

    // `int` widens to `double`, so the conditional is a `double` on both paths.
    static func NaturalNumeric(flag: bool): string {
        ratio := flag ? 1 : 2.5
        boxed: object = ratio
        return boxed.GetType().Name + ":" + ratio.ToString(System.Globalization.CultureInfo.InvariantCulture)
    }

    // Neither `byte` nor `short` widens to the other; both promote to `int`.
    static func NaturalPromoted(flag: bool): string {
        small: byte = 3
        wider: short = 4
        value := flag ? small : wider
        boxed: object = value
        return boxed.GetType().Name + ":" + value.ToString()
    }

    // The unannotated `let` spelling is the same inferred local.
    static func LetInferred(flag: bool): string {
        let count = 5
        let label := "pets"
        let pet = flag ? new Dog() : new Animal()
        return count.ToString() + ":" + label + ":" + Kinds.Of(pet)
    }

    // ── a target: each arm converts to it ───────────────────────────────────────────────────────

    // A declared local.
    static func TypedLocal(flag: bool): string {
        boxed: object = flag ? 1 : "x"
        either: Animal = flag ? new Dog() : new Cat()
        return boxed.GetType().Name + ":" + boxed.ToString() + ":" + Kinds.Of(either) + ":" + either.GetType().Name
    }

    // A local being assigned.
    static func Assigned(flag: bool): string {
        boxed: object = "start"
        boxed = flag ? 7 : "seven"
        return boxed.ToString() ?? ""
    }

    // A declared return type.
    static func Returned(flag: bool): object => flag ? 1 : "x"

    // A parameter of a source function.
    static func Described(value: object): string => value.GetType().Name + ":" + value.ToString()

    static func PassedToSource(flag: bool): string => Described(flag ? 2 : "two")

    // A parameter of a referenced method.
    static func PassedToFramework(flag: bool): string => String.Concat("a", flag ? 1 : "x")

    // An overload group: only `object` fits both branches, and a same-typed conditional keeps `int`.
    static func Overloaded(flag: bool): string => Kinds.Show(flag ? 1 : "x") + ":" + Kinds.Show(flag ? 1 : 2)

    // A mixed conditional nested inside a target-typed one, under the outer target.
    static func Nested(outer: bool, inner: bool): object => outer ? (inner ? 1 : "inner") : null
}
