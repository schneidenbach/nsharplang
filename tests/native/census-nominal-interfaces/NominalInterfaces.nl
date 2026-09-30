namespace NSharpLang.CensusNominalInterfaces.Tests


// A PLAIN `interface` IS NOMINAL; ONLY A `duck interface` IS STRUCTURAL.
//
// The columnar emitter used to register EVERY source interface structurally: its duck pass walked
// all of them, and the interface input carried no duck flag to tell it otherwise. So an EMPTY plain
// interface — a marker — was written onto every class in the assembly, because every class has all
// zero of its members, and a plain interface with members was written onto every class that happened
// to have matching ones. The analyzer was right all along (a class that does not name a plain
// interface is not assignable to it); the emitted METADATA was not, and metadata is what `is`, `as`,
// a match arm, reflection and every other assembly read. The Compiler.Core split found it: an empty
// marker interface meant to type one property turned up on every class of Compiler.Core, and a
// common-base search found it on every pair.
//
// The types below are read back by reflection and by runtime type tests in the rows beside them.

// An empty plain interface. Satisfied structurally by everything; implemented by what names it.
interface IMarker {
}

// A plain interface with a member.
interface IGreeter {
    func Greet(): string
}

// A plain interface that extends a duck one: naming the duck base does not make it structural.
interface INamedGreeter: IDuckGreeter {
    func Name(): string
}

// The duck twins of the two plain interfaces above.
duck interface IDuckGreeter {
    func Greet(): string
}

duck interface IDuckEmpty {
}

// Has `Greet` and `Name`, and names no interface at all.
class Stranger {
    func Greet(): string {
        return "stranger"
    }

    func Name(): string {
        return "Stranger"
    }
}

// Names both plain interfaces.
class Member: IGreeter, IMarker {
    func Greet(): string {
        return "member"
    }
}

// Has nothing but a field.
class Bare {
    Value: int = 0
}

// A value type with the duck member: a matching struct is boxed into the duck interface.
struct Point {
    X: int

    func Greet(): string {
        return "point"
    }
}

func GreetThroughDuck(greeter: IDuckGreeter): string {
    return greeter.Greet()
}

func GreetThroughPlain(greeter: IGreeter): string {
    return greeter.Greet()
}
