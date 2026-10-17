namespace NSharpLang.AssertThrowsSourceTypes

import System

class BoomException: Exception {
    constructor(m: string): base(m) {}
}

class DerivedBoomException: BoomException {
    constructor(m: string): base(m) {}
}

func Boom() {
    throw new BoomException("x")
}

func BoomDerived() {
    throw new DerivedBoomException("derived")
}

func Quiet() {
}

// Asserts that Quiet() throws a BoomException. It does not, so the assert fails.
func MissedThrow() {
    assert throws BoomException {
        Quiet()
    }
}

// Asserts that Boom() throws a DerivedBoomException. It throws the base type, which must escape.
func WrongThrow() {
    assert throws DerivedBoomException {
        Boom()
    }
}
