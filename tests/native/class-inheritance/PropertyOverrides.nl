namespace NSharpLang.ClassInheritance.Tests

import System

// VIRTUAL, OVERRIDE AND SEALED OVERRIDE ON WRITTEN PROPERTIES (website/docs/types.md "Properties").
//
// A property written with accessors — `Text: string => …` or `{ get … set … }` — is a pair of methods,
// so the inheritance words mean on it what they mean on a `func`. They used to be accepted and then
// dropped: `virtual` emitted an ordinary getter, and `override Message: string => …` on an exception
// compiled while a caller holding an `Exception` read the base text. Every type below is called
// through its base in the tests, which is the only way a missing slot shows.

interface IDisplayText {
    Text: string
}

class Label: IDisplayText {
    virtual Text: string => "plain"

    func Render(): string => "[" + Text + "]"
}

class LoudLabel: Label {
    override Text: string => "LOUD"
}

class FinalLabel: LoudLabel {
    sealed override Text: string => "final"
}

// The getter/setter pair, overridden as a pair, with the subclass DECLARED BEFORE ITS BASE: the
// override's slot is proved from the base's own accessors, whatever order the source writes them in.
class ClampedCounter: Counter {
    limited: int

    override Count: int {
        get { return limited }
        set {
            if value > 10 {
                limited = 10
            } else {
                limited = value
            }
        }
    }
}

class Counter {
    stored: int

    virtual Count: int {
        get { return stored }
        set { stored = value }
    }

    func Bump() {
        Count = Count + 1
    }
}

// An exception's message is `public virtual string Message { get; }` — get-only, so it is overridden
// with a getter alone.
class ParseError: Exception {
    readonly line: int

    constructor(line: int) {
        this.line = line
    }

    override Message: string => "parse error at line " + line.ToString()
}

// ---- written and bare members override each other -------------------------------------------------

// A bare `virtual` member is a get/set auto-property. A written override may replace both accessors…
class Gauge {
    virtual Reading: int = 5
    protected virtual Weight: int = 1

    func Report(): string => "reading " + Reading.ToString()

    func WeightValue(): int => Weight
}

class DoubledGauge: Gauge {
    doubled: int

    override Reading: int {
        get { return doubled }
        set { doubled = value * 2 }
    }
}

// …or the getter alone, inheriting the base's setter as C#'s `override int Reading => 42` does. An
// override with no accessibility word takes the slot's, so `Weight` stays protected.
class FixedGauge: Gauge {
    override Reading: int => 42
    override Weight: int => 9
}

// A bare `override` member over a written `virtual` property, declared before its base.
class Subtitled: Titled {
    override Title: string = "subtitled"
}

class Titled {
    title: string = "titled"

    virtual Title: string {
        get { return title }
        set { title = value }
    }

    func Heading(): string => "# " + Title
}

// A bare `abstract` member is a get/set slot; a written override fills both halves of it.
abstract class Badge {
    abstract Caption: string

    func Show(): string => "badge " + Caption
}

class StarBadge: Badge {
    caption: string = "star"

    override Caption: string {
        get { return caption }
        set { caption = value.ToUpper() }
    }
}

// A generic base's slot, overridden by a subclass that closes it.
class Holder<T> {
    stored: T

    virtual Value: T => stored

    func Read(): T => Value
}

class FortyTwo: Holder<int> {
    override Value: int => 42
}
