namespace NSharpLang.CensusLiftedOperators.Tests


// EQUALITY OVER AN OPEN TYPE PARAMETER, WHICH C# REFUSES OUTRIGHT.
//
// `a == b` under `where T : struct` is CS0019 in C#, and so is the `T?` form the converter census
// caught: a generic helper that compares two optional values has to be written as
// `EqualityComparer<T>.Default.Equals(...)` by hand, and the `?` form has to open-code the presence
// test as well. N# admits both, because the CLR has one comparison for a value whose kind is not
// known until the instantiation is chosen and that comparison is well defined for every T.
//
// THE `?` FORM IS THE LIFT, NOT A SECOND RULE. Two absent values are EQUAL, an absent one differs
// from every present one, and the answer is a plain `bool` — the same contract every closed lifted
// equality in this project pins, asked of an element the emitter cannot name.
func Same<T>(a: T?, b: T?): bool where T: struct => a == b

func Different<T>(a: T?, b: T?): bool where T: struct => a != b

func SameValue<T>(a: T, b: T): bool where T: struct => a == b

func DifferentValue<T>(a: T, b: T): bool where T: struct => a != b

// ONE LIFTED SIDE IS ENOUGH: the plain operand converts to `T?` and the presence test is asked of
// the lifted side alone.
func SameLiftedLeft<T>(a: T?, b: T): bool where T: struct => a == b

func SameLiftedRight<T>(a: T, b: T?): bool where T: struct => a == b

// AN UNCONSTRAINED PARAMETER TAKES THE SAME RULE. Its `?` is an annotation on one CLR type rather
// than a `Nullable<T>` construction, so the comparison is the bare parameter's — and it is still
// `EqualityComparer<T>.Default`, which is reference identity for a class that does not override
// `Equals` and the override's answer for one that does.
func SameAny<T>(a: T, b: T): bool => a == b

func SameAnnotated<T>(a: T?, b: T?): bool => a == b

// A TYPE PARAMETER OF THE ENCLOSING TYPE, not of the function — and the enclosing type may be of ANY
// kind. The question is asked of the SCOPE, which records a declaration's parameters whatever the
// declaration is, so a generic `struct` and `record` answer exactly as a `class` does.
class Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    func Holds(candidate: T): bool => Value == candidate
}

struct Cell<T> where T: struct {
    Value: T?

    constructor(value: T?) {
        Value = value
    }

    func Holds(candidate: T?): bool => Value == candidate
}

record Pair<T> where T: struct {
    Left: T?
    Right: T?

    func Balanced(): bool => Left == Right
}

// A SOURCE STRUCT THAT OVERRIDES `Equals` proves the comparison DISPATCHES rather than comparing
// bits: `Sloppy` calls two values equal whenever their `X` matches, so a `Y` that differs must not
// change the answer.
struct Sloppy {
    X: int
    Y: int

    constructor(x: int, y: int) {
        X = x
        Y = y
    }

    override func Equals(other: object?): bool {
        if other is Sloppy value {
            return value.X == X
        }

        return false
    }

    override func GetHashCode(): int => X
}

func MakeSloppy(x: int, y: int): Sloppy => new Sloppy(x, y)

func MakeBox(value: int): Box<int> => new Box<int>(value)

func MakeCell(value: int?): Cell<int> => new Cell<int>(value)

func MakePair(left: int?, right: int?): Pair<int> => new Pair<int> { Left: left, Right: right }

func LiftSloppy(value: Sloppy): Sloppy? => value

func AbsentSloppy(): Sloppy? => null
