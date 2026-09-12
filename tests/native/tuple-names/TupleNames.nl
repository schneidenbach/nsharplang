namespace NSharpLang.TupleNames.Tests

import System.Collections.Generic


// THE DECLARED SHAPES THE METADATA ROWS READ BACK.
//
// Every named tuple below is written the way a user writes one; the tests beside this file read the
// `TupleElementNamesAttribute` the compiler put on the matching signature position and compare it
// against what the C# compiler writes for the same shape. Nothing here is a fixture in the sense of
// "arranged to make a test pass" -- these are the ordinary spellings, and the point is that ordinary
// spellings carry their names across the assembly boundary.
class TupleShapes {
    static func Simple(): (Min: int, Max: int) {
        return (3, 9)
    }

    static func Unnamed(): (int, int) {
        return (3, 9)
    }

    static func Nested(): (A: int, D: (B: int, C: int)) {
        return (1, (2, 3))
    }

    static func NestedFirst(): (D: (B: int, C: int), A: int) {
        return ((2, 3), 1)
    }

    static func InnerUnnamed(): (X: (int, int), Y: int) {
        return ((2, 3), 1)
    }

    static func Generic(): List<(Min: int, Max: int)> {
        return new List<(Min: int, Max: int)>()
    }

    static func GenericInsideTuple(): (M: List<(L1: int, L2: int)>, N: int) {
        return (new List<(L1: int, L2: int)>(), 7)
    }

    static func Parameterised(pair: (P: int, Q: int)): int {
        return pair.P + pair.Q
    }

    func Instance(): (Left: int, Right: int) {
        return (4, 5)
    }

    func InstanceParameterised(pair: (P: int, Q: int)): int {
        return pair.P * pair.Q
    }
}

// A constructor parameter is a signature position like any other.
class PairHolder {
    Sum: int

    constructor(pair: (P: int, Q: int)) {
        Sum = pair.P + pair.Q
    }
}

func FreeSimple(): (Min: int, Max: int) {
    return (3, 9)
}

func FreeUnnamed(): (int, int) {
    return (3, 9)
}

func FreeParameterised(pair: (P: int, Q: int)): int {
    return pair.P - pair.Q
}
