namespace NSharpLang.CensusSourceAttributes

import System
import System.Runtime.CompilerServices

// THE SUBJECT: attributes this program declares for itself, applied to declarations in the same
// program. Every shape here is asserted against the EMITTED metadata in `SourceAttributes.tests.nl`
// by reflecting over the assembly the compiler produced for this file.
enum Level {
    Low = 1,
    High = 4
}

// A NO-ARGUMENT ATTRIBUTE and the two spellings that name it.
class MarkAttribute: Attribute {
    Tag: string
    Count: int

    constructor() {
        Tag = ""
        Count = 0
    }

    constructor(tag: string) {
        Tag = tag
        Count = 0
    }

    constructor(tag: string, count: int) {
        Tag = tag
        Count = count
    }
}

// EVERY PRIMITIVE WIDTH A BLOB CAN CARRY, in one constructor, so a wrong width is a wrong value
// rather than a silent truncation nobody notices.
class WidthsAttribute: Attribute {
    Flag: bool
    Letter: char
    Small: sbyte
    Unsigned: byte
    Short: short
    UnsignedShort: ushort
    Whole: int
    UnsignedWhole: uint
    Wide: long
    UnsignedWide: ulong
    Single: float
    Wide64: double

    constructor(flag: bool, letter: char, small: sbyte, unsigned: byte, shortValue: short, unsignedShort: ushort, whole: int, unsignedWhole: uint, wide: long, unsignedWide: ulong, singleValue: float, wide64: double) {
        Flag = flag
        Letter = letter
        Small = small
        Unsigned = unsigned
        Short = shortValue
        UnsignedShort = unsignedShort
        Whole = whole
        UnsignedWhole = unsignedWhole
        Wide = wide
        UnsignedWide = unsignedWide
        Single = singleValue
        Wide64 = wide64
    }
}

// `typeof`, an ARRAY of strings, and a `null` where a reference is expected.
class TypedAttribute: Attribute {
    Subject: Type
    Names: string[]
    Note: string?

    constructor(subject: Type, names: string[], note: string?) {
        Subject = subject
        Names = names
        Note = note
    }
}

// A SOURCE enum, an EXTERNAL enum, and an `object` parameter that carries the value's own type.
class LevelledAttribute: Attribute {
    Level: Level
    Targets: AttributeTargets
    Payload: object?

    constructor(level: Level, targets: AttributeTargets, payload: object?) {
        Level = level
        Targets = targets
        Payload = payload
    }
}

// A FULL PROPERTY as a named argument: the blob writes a property row (0x54), not a field row.
class NotedAttribute: Attribute {
    note: string
    Note: string {
        get {
            return note
        }
        set {
            note = value
        }
    }

    constructor() {
        note = ""
    }
}

// A SOURCE attribute deriving from ANOTHER SOURCE attribute. The named argument is declared by the
// base, so binding it means walking the declaration's base chain.
class DerivedMarkAttribute: MarkAttribute {
    Extra: string

    constructor(tag: string): base(tag) {
        Extra = ""
    }
}

// A SOURCE attribute deriving from an EXTERNAL attribute base in a referenced assembly.
class ExternallyBasedAttribute: DiscardableAttribute {
    Reason: string

    constructor(reason: string) {
        Reason = reason
    }
}

// `[AttributeUsage]` ON THE DECLARATION IS HONORED, and it is read from the source: the type does not
// exist as metadata while the program that declares it is being compiled. `AllowMultiple = true` is
// what makes the two applications below legal, and it survives into the emitted attribute type so a
// consumer of this assembly reads the same answer.
[AttributeUsage(AttributeTargets.Method, AllowMultiple = true)]
class TagAttribute: Attribute {
    Name: string

    constructor(name: string) {
        Name = name
    }
}

[Mark("on the class", 7)]
class Target {
    [Tag("first")]
    [Tag("second")]
    func Tagged() {
    }

    [Mark]
    func Bare() {
    }

    [MarkAttribute("full spelling")]
    func FullSpelling() {
    }

    [Mark("named", Count = 42)]
    func NamedField() {
    }

    [Noted(Note = "through a setter")]
    func NamedProperty() {
    }

    [Widths(true, 'x', -8, 250, -3000, 60000, -123456, 4000000000, -9000000000000, 18000000000000000000, 1.5f, 2.25)]
    func Widths() {
    }

    [Typed(typeof(Target), ["a", "b"], null)]
    func TypedArguments() {
    }

    [Typed(typeof(int), ["only"], "kept")]
    func BuiltInTypeArgument() {
    }

    [Levelled(Level.High, AttributeTargets.Method | AttributeTargets.Class, 17)]
    func Levelled() {
    }

    [Levelled(Level.Low, AttributeTargets.All, "boxed string")]
    func BoxedString() {
    }

    [DerivedMark("derived", Count = 3, Extra = "own")]
    func Derived() {
    }

    [ExternallyBased("because")]
    func ExternallyBased() {
    }

    func WithParameter([Mark("on the parameter")] value: int): int {
        return value
    }

    [Obsolete("gone", true)]
    func ExternalTwoArguments() {
    }

    [Obsolete(DiagnosticId = "NL9999")]
    func ExternalNamedOnly() {
    }
}

// OPTIONAL CONSTRUCTOR PARAMETERS. A custom-attribute blob has no notion of an omitted argument, so
// `[Defaulted]` writes the DECLARED DEFAULT of every parameter it leaves off — which is what the C#
// compiler writes for the same declaration, and what every reader of this assembly reads back.
class DefaultedAttribute: Attribute {
    Level: int
    Note: string
    Flag: bool
    Ranking: Level

    constructor(level: int = 7, note: string = "unsaid", flag: bool = true, ranking: Level = Level.High) {
        Level = level
        Note = note
        Flag = flag
        Ranking = ranking
    }
}

// AN ARRAY ARGUMENT CONVERTS PER ELEMENT. `[1, 2]` is an `int[]` and there is no conversion from
// `int[]` to `byte[]`, but each element is an integer constant a `byte` holds and the blob writes
// each element against the ELEMENT type.
class BytesAttribute: Attribute {
    Values: byte[]
    Widths: long[]

    constructor(values: byte[]) {
        Values = values
        Widths = []
    }

    constructor(values: byte[], widths: long[]) {
        Values = values
        Widths = widths
    }
}

// AN ATTRIBUTE WHOSE EXTERNAL BASE TAKES AN ARGUMENT. The base lives in a referenced assembly, so the
// constructor this chains to is a reflected `ConstructorInfo` rather than one this compilation is
// building — and it is selected and called the same way a source base's is.
class RelaxedAttribute: CompilationRelaxationsAttribute {
    constructor(level: int): base(level) {
    }
}

class DefaultCarrier {
    [Defaulted]
    func AllOmitted() {
    }

    [Defaulted(3)]
    func FirstWritten() {
    }

    [Defaulted(3, "said")]
    func TwoWritten() {
    }

    [Defaulted(3, "said", false, Level.Low)]
    func AllWritten() {
    }

    [Defaulted(Note = "named only")]
    func NamedOnly() {
    }

    [Bytes([1, 2, 250])]
    func NarrowedElements() {
    }

    [Bytes([1], [2, 3])]
    func TwoArrays() {
    }

    [Relaxed(8)]
    func Relaxed() {
    }
}

// A FIELD'S ATTRIBUTES, on every field shape a declaration can carry one on: an instance field, a
// static field, a `const` field whose value is metadata rather than code, a field whose attribute
// comes from a referenced assembly, and a field of a VALUE type. A field declares its attributes at
// its own member position, which the member scan records, so the same backward scan that finds a
// method's finds a field's.
class FieldCarrier {
    [Mark("on the instance field")]
    Value: int

    [Mark("on the static field")]
    static Shared: int = 3

    [Obsolete("field went away")]
    Legacy: string = ""

    [Mark("on the const")]
    const Limit: int = 10

    [Levelled(Level.High, AttributeTargets.Field, "field payload")]
    Described: string = ""

    Plain: int

    constructor() {
        Value = 1
        Plain = 0
    }
}

struct FieldPoint {
    [Mark("on the struct field")]
    X: int
    Y: int
}

// A PROPERTY'S AND A CONSTRUCTOR'S ATTRIBUTES. A property's go on the PROPERTY row, which is where
// every framework that reads them looks; a constructor's go on the constructor.
class Carrier {
    [Mark("on the property")]
    Described: int => 1

    [Mark("on the constructor")]
    constructor() {
    }
}

// `inherit: true` FINDS AN ATTRIBUTE ON THE OVERRIDDEN METHOD. The attribute is written once, on the
// virtual member, and the override carries none of its own.
class BaseCarrier {
    [Mark("inherited")]
    virtual func Describe(): string {
        return "base"
    }
}

class DerivedCarrier: BaseCarrier {
    override func Describe(): string {
        return "derived"
    }
}
