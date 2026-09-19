namespace Census.FreeFunctionIdentity.TypesOnly

import System


// A NAMESPACE THAT DECLARES ONLY TYPES.
//
// Nothing here belongs on a `Program` holder. `Calc` has a constructor, an instance method, a
// non-capturing lambda, a capturing lambda and an anonymous object — every body shape the emitter
// used to hand a holder to "just in case" — and all of them land somewhere else: a lambda written
// inside a type is a method on that type, a display class and an anonymous object type are
// module-level. So this namespace must emit NO `Census.FreeFunctionIdentity.TypesOnly.Program` at
// all, and `FreeFunctionIdentity.tests.nl` pins that.
class Calc {
    Seed: int

    constructor(seed: int) {
        Seed = seed
    }

    func Doubled(): int {
        return Seed * 2
    }

    func PlusOne(value: int): int {
        step: Func<int, int> = x => x + 1
        return step(value)
    }

    func PlusSeed(value: int): int {
        captured := Seed
        step: Func<int, int> = x => x + captured
        return step(value)
    }

    func Described(): object {
        return new { Seed: Seed, Doubled: Doubled() }
    }
}
