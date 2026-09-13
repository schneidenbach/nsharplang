namespace NSharpLang.CensusParseShapes.Tests

import System
import System.Reflection
import System.Runtime.InteropServices


// A TYPE'S MEMBERS MAY BE WRITTEN IN ANY ORDER.
//
// The columnar member scan used to read a type's body in ONE pass with a section boundary in it: the
// field scan stopped at the first `func`, conversion operator or constructor, and the member scan
// behind it refused anything that was not one of those. So `field, func, field` — an entirely
// ordinary way to group a type's members around the method that uses them — declined the WHOLE
// declaration at `parse.struct` (NL103), reported at the class header with nothing said about which
// member caused it. An `event` written after a method hit the same rule, and so did a property whose
// type was composed.
//
// The body is read twice now, once for storage members and once for methods and constructors, so
// nothing about where a member is written changes what it means. These types are compiled by the real
// columnar pipeline, so their existence is half the proof; the tests below are the other half —
// declaration ORDER still decides field layout, initializers still run, and a member declared after a
// method is the same member it would be declared before one.
[StructLayout(LayoutKind.Sequential)]
struct OrderedPoint {
    X: int

    func Sum(): int {
        return X + Y
    }

    Y: int
}

class OrderedCounter {
    Seed: int = 3

    func Bump(): int {
        Steps = Steps + 1

        return Seed + Steps
    }

    // A field with an INSTANCE INITIALIZER, after a method. Whether a type needs a synthesized
    // constructor at all is decided by this initializer, and the synthesized constructor has to be
    // recorded before any written one — which is why the body is read twice rather than once.
    Steps: int = 0

    // A property, after a method, whose type is composed rather than a single token.
    Names: Collections.Generic.List<string> = new Collections.Generic.List<string>()

    Label: string => "counter"

    static Total: int = 10

    func Described(): string {
        return Label + ":" + Total.ToString()
    }
}

class OrderedSignals {
    func Arm(): int {
        Armed = Armed + 1

        return Armed
    }

    // A field-like EVENT after a method — the shape stream EVENTS2 met.
    event Changed: Action

    Armed: int = 0

    func Raise() {
        handler := Changed
        if handler != null {
            handler.Invoke()
        }
    }
}

class OrderedByConstructor {
    constructor(seed: int) {
        Held = seed
    }

    func Doubled(): int {
        return Held * 2
    }

    // Declared after BOTH a constructor and a method.
    Held: int
}

test "declaration order still decides a sequential struct's field layout" {
    point := new OrderedPoint { X: 4, Y: 5 }
    assert point.Sum() == 9

    fields := typeof(OrderedPoint).GetFields(BindingFlags.Public | BindingFlags.Instance)
    assert fields.Length == 2
    assert fields[0].Name == "X"
    assert fields[1].Name == "Y"
}

test "a field declared after a method carries its initializer" {
    counter := new OrderedCounter()

    assert counter.Bump() == 4
    assert counter.Bump() == 5
    assert counter.Seed == 3
    assert counter.Names.Count == 0

    counter.Names.Add("first")
    assert counter.Names.Count == 1
}

test "a property and a static field declared after a method are ordinary members" {
    counter := new OrderedCounter()

    assert counter.Label == "counter"
    assert counter.Described() == "counter:10"
    assert OrderedCounter.Total == 10

    assert typeof(OrderedCounter).GetProperty("Label") != null
    assert (must typeof(OrderedCounter).GetField("Total", BindingFlags.Public | BindingFlags.Static)).IsStatic
}

test "an event declared after a method is still an event" {
    signals := new OrderedSignals()
    assert signals.Arm() == 1

    raised := 0
    on signals.Changed () => {
        raised = raised + 1
    }

    signals.Raise()
    assert raised == 1

    assert typeof(OrderedSignals).GetEvent("Changed") != null
}

test "a field declared after a constructor is the storage that constructor writes" {
    held := new OrderedByConstructor(7)

    assert held.Held == 7
    assert held.Doubled() == 14
}
