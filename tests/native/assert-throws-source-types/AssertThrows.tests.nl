namespace NSharpLang.AssertThrowsSourceTypes.Tests

import System
import System.Text.Json
import NSharpLang.AssertThrowsSourceTypes
import NSharpLang.AssertThrowsSourceTypes.Other

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

test "assert throws accepts an exception type imported from another namespace of the project" {
    assert throws OtherNamespaceException {
        ThrowOther()
    }
}

test "assert throws accepts an exception type from a referenced assembly" {
    assert throws JsonException {
        JsonDocument.Parse("{")
    }
}

test "a non-matching exception keeps the stack trace of the frame that threw it" {
    trace := ""
    try {
        WrongThrow()
    } catch ex: BoomException {
        trace = ex.StackTrace ?? ""
    }
    assert trace.Contains("Boom"), trace
}
