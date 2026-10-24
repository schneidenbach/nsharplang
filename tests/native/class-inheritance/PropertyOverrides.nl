namespace NSharpLang.ClassInheritance.Tests

import System
import System.Threading.Tasks

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

// ---- a written property's accessibility -------------------------------------------------------------

// The accessors take the property's own word, or its casing when it writes none — the method rule.
// `Total()` reads every one of them from inside the type, through closures and an async body too.
class Ledger {
    stored: int = 3

    Plain: int => 1
    open: int => 2
    public Shown: int => 4
    protected Guarded: int => 8
    internal Inside: int => 16
    private Secret: int => 32
    protected internal Shared: int => 64
    static Count: int => 128
    protected static Seed: int => 256

    private Balance: int {
        get { return stored }
        set { stored = value }
    }

    func Total(): int => Plain + open + Shown + Guarded + Inside + Secret + Shared + Count + Seed + Balance

    func Deposit(amount: int) {
        Balance = Balance + amount
    }

    func SecretReader(): Func<int> => () => Secret + Balance

    async func SecretLater(): Task<int> {
        await Task.Yield()
        return Secret + Guarded
    }
}

class AuditedLedger: Ledger {
    func GuardedReader(): Func<int> => () => Guarded + Seed
}

// A non-public property that fills an interface's value slot names the slot it fills, as a non-public
// `func` filling an interface method does; a bare member does the same.
interface ICaption {
    Caption: string
}

class InternalCaption: ICaption {
    internal Caption: string => "internal"
}

class BareInternalCaption: ICaption {
    internal Caption: string = "bare"
}

// ---- a get-only override inherits the base's setter --------------------------------------------------

class PinnedGauge: Gauge {
    override Reading: int => 99

    func Overwrite(): int {
        Reading = 7
        Reading += 1
        Reading++
        return base.Reading
    }
}

// `Exception.HelpLink` is `virtual { get; set; }`: the override replaces its getter, and a write still
// reaches `Exception`'s setter.
class LinkedError: Exception {
    override HelpLink: string? => "https://example.test/fixed"
}

class PlainError: Exception {
}
