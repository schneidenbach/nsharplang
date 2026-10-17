namespace NSharpLang.AssertThrowsSourceTypes.Tests

import System
import NSharpLang.AssertThrowsSourceTypes

class LocalBoomException: Exception {
    constructor(m: string): base(m) {}
}

func throwLocal() {
    throw new LocalBoomException("local")
}

test "assert throws accepts an exception type declared in another source file" {
    assert throws BoomException {
        Boom()
    }
}

test "assert throws accepts an exception type declared in the test file" {
    assert throws LocalBoomException {
        throwLocal()
    }
}

test "assert throws a base project exception passes when a derived one is thrown" {
    assert throws BoomException {
        BoomDerived()
    }
}

test "assert throws a derived project exception passes when exactly it is thrown" {
    assert throws DerivedBoomException {
        BoomDerived()
    }
}

test "assert throws a BCL base type still accepts a project exception deriving from it" {
    assert throws Exception {
        Boom()
    }
}

test "assert throws a project type fails with a message naming the type when nothing is thrown" {
    message := "none"
    try {
        MissedThrow()
    } catch ex: InvalidOperationException {
        message = ex.Message
    }
    assert message == "Expected exception of type BoomException was not thrown"
}

test "assert throws a project type does not swallow a different exception" {
    escaped := "none"
    try {
        WrongThrow()
    } catch ex: BoomException {
        escaped = ex.Message
    }
    assert escaped == "x"
}
