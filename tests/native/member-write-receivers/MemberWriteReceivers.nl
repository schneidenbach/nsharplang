namespace NSharpLang.MemberWriteReceivers.Tests

import System.Collections.Generic

// A MEMBER WRITE WHOSE RECEIVER IS NOT A NAME. C#'s rule, which N# keeps: a member write needs
// storage to land in. A REFERENCE-typed receiver — an array element, a call result, an indexer
// result — yields an object, and the object IS the storage, so `roster[0].Name = v` and
// `Pick(d).Name = v` write the shared object. A VALUE-typed ARRAY ELEMENT is storage too: the write
// goes through the element's address and changes the array's own slot. A value-typed call or indexer
// result is a temporary copy with nowhere to write back to, and the analyzer rejects it as NL322.
struct Point {
    X: int
    Y: int
}

struct Segment {
    Start: Point
    End: Point
}

class Dog {
    Name: string = "rex"
    Age: int = 1
    Spot: Point
    nickname: string = "none"

    Nickname: string {
        get {
            return nickname
        }
        set {
            nickname = value
        }
    }
}

// Records the order the parts of a write are evaluated in.
class Trace {
    Steps: List<string> = new List<string>()

    func Pick(dog: Dog): Dog {
        Steps.Add("receiver")
        return dog
    }

    func Index(i: int): int {
        Steps.Add("index")
        return i
    }

    func Value(v: int): int {
        Steps.Add("value")
        return v
    }

    func Text(): string {
        return string.Join(",", Steps)
    }
}

func Pick(dog: Dog): Dog {
    return dog
}

func Bump(ref n: int) {
    n = n + 100
}

func Swap(ref text: string) {
    text = "swapped:" + text
}

// ---- reference-typed receivers ------------------------------------------------------------------

func RenameFirst(roster: Dog[], name: string) {
    roster[0].Name = name
}

func RenameThroughCall(dog: Dog, name: string) {
    Pick(dog).Name = name
}

func RenameThroughList(dogs: List<Dog>, name: string) {
    dogs[0].Name = name
}

func RenameThroughParens(roster: Dog[], name: string) {
    (roster[0]).Name = name
}

func NicknameFirst(roster: Dog[], name: string) {
    roster[0].Nickname = name
}

func NicknameThroughCall(dog: Dog, name: string) {
    Pick(dog).Nickname = name
}

func AgeUpFirst(roster: Dog[], years: int) {
    roster[0].Age += years
}

func BirthdayThroughCall(dog: Dog) {
    Pick(dog).Age++
}

// A value-typed FIELD of a reference-typed receiver is written in place through its address.
func MoveSpotFirst(roster: Dog[], x: int) {
    roster[0].Spot.X = x
}

func MoveSpotThroughCall(dog: Dog, y: int) {
    Pick(dog).Spot.Y = y
}

// ---- value-typed array elements -----------------------------------------------------------------

func SetX(points: Point[], i: int, x: int) {
    points[i].X = x
}

func AddToY(points: Point[], i: int, delta: int) {
    points[i].Y += delta
}

func StepY(points: Point[], i: int) {
    points[i].Y++
}

func SetEndX(segments: Segment[], i: int, x: int) {
    segments[i].End.X = x
}

func BumpX(points: Point[], i: int) {
    Bump(ref points[i].X)
}

func BumpAgeThroughCall(dog: Dog) {
    Bump(ref Pick(dog).Age)
}

// A `ref` to a REFERENCE-typed field passes the field's slot, so the callee's store replaces what
// the field holds.
func SwapName(dog: Dog) {
    Swap(ref dog.Name)
}

func SwapNameFirst(roster: Dog[]) {
    Swap(ref roster[0].Name)
}

func SwapNameThroughCall(dog: Dog) {
    Swap(ref Pick(dog).Name)
}

// ---- evaluation order ---------------------------------------------------------------------------

func TracedElementWrite(trace: Trace, points: Point[], i: int, x: int) {
    points[trace.Index(i)].X = trace.Value(x)
}

func TracedCallWrite(trace: Trace, dog: Dog, age: int) {
    trace.Pick(dog).Age = trace.Value(age)
}

func TracedCallCompound(trace: Trace, dog: Dog, years: int) {
    trace.Pick(dog).Age += trace.Value(years)
}

func TracedNullElementWrite(trace: Trace, roster: Dog[], age: int) {
    roster[0].Age = trace.Value(age)
}

// ---- receivers rooted at the instance's own fields ---------------------------------------------

class Kennel {
    dogs: Dog[] = [new Dog(), new Dog()]
    spots: Point[] = new Point[](2)

    func Rename(i: int, name: string) {
        dogs[i].Name = name
    }

    func RenameExplicit(i: int, name: string) {
        this.dogs[i].Name = name
    }

    func Place(i: int, x: int) {
        spots[i].X = x
        this.spots[i].Y += x
    }

    func First(): Dog {
        return dogs[0]
    }

    func RenameFirstThroughCall(name: string) {
        First().Name = name
    }

    func NameAt(i: int): string {
        return dogs[i].Name
    }

    func SpotAt(i: int): Point {
        return spots[i]
    }
}
