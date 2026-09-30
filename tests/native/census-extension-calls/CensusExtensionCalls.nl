namespace NSharpLang.CensusExtensionCalls.Tests

import System
import System.Collections
import System.Collections.Generic
import System.Text.Json


// THE EXTENSION-CALL SHAPES THE 2026-09-12 CONVERTER CENSUS FOUND, AS RUNNING CODE.
//
// Every converted project is LINQ-dense, and an extension call is one relation applied twice: the
// receiver's static type is converted to the `this` parameter's type by the ordinary assignability
// relation, and method type inference fixes the type parameters from whatever the receiver and the
// arguments fixed. The census found the relation stopping short of the RECEIVERS the programs
// actually wrote — most of all a sequence whose ELEMENT is a type this very compilation is writing,
// where `List<Query>` is a builder-bound instantiation whose interface list reflection refuses to
// report at all.
//
// Everything here EXECUTES. The declared type of a LINQ result proves nothing on its own; the
// runtime value and the runtime type it answers with are what prove the right method was selected
// and the right IL was written for it.
class Query {
    Name: string
    Weight: int

    constructor(name: string, weight: int) {
        Name = name
        Weight = weight
    }

    func Describe(prefix: string): string {
        return prefix + Name
    }
}

struct Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        X = x
        Y = y
    }
}

func Queries(): List<Query> {
    values := new List<Query>()
    values.Add(new Query("alpha", 3))
    values.Add(new Query("be", 1))
    values.Add(new Query("gamma", 2))
    return values
}

func Words(): List<string> {
    values := new List<string>()
    values.Add("alpha")
    values.Add("be")
    values.Add("gamma")
    return values
}

func Points(): List<Point> {
    values := new List<Point>()
    values.Add(new Point(1, 2))
    values.Add(new Point(3, 4))
    return values
}

func WordArray(): string[] {
    return ["alpha", "be", "gamma"]
}

func QueryArray(): Query[] {
    return [new Query("alpha", 3), new Query("be", 1)]
}

func WeightsByName(): Dictionary<string, int> {
    map := new Dictionary<string, int>()
    map["alpha"] = 3
    map["be"] = 1
    return map
}

func RuntimeTypeOf(value: object): Type {
    return value.GetType()
}

func MixedValues(): ArrayList {
    values := new ArrayList()
    values.Add("alpha")
    values.Add(7)
    values.Add("gamma")
    return values
}

func NoOptions(): JsonSerializerOptions? {
    return null
}

class Holder {
    Transform: Func<int, int>?
}

func MakeWeight(): int {
    return 9
}

func IsShort(value: string): bool {
    return value.Length < 3
}

// A delegate FIELD assigned from a constructor. The right-hand side of an assignment is an argument
// position, so the field's declared type is what shapes the lambda written there.
class Box {
    handler: Func<int, bool>
    scale: Func<int, int>

    public constructor(factor: int) {
        this.handler = value => value > 2
        scale = value => value * factor
    }

    func Run(value: int): bool {
        return handler(value)
    }

    func Scale(value: int): int {
        return scale(value)
    }
}

// A TYPE PARAMETER constrained to an interface. The receiver's static type is `T`, which has no
// members of its own: its CONSTRAINT is what the extension's receiver slot is matched against.
func CountOf<T>(items: T): int where T: IEnumerable<string> {
    return items.Count()
}

func FirstOf<T>(items: T): string where T: IEnumerable<string> {
    return items.First()
}
