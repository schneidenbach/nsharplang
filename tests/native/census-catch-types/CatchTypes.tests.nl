namespace NSharpLang.CensusCatchTypes.Tests

import System.Collections.Generic

test "a catch clause naming a System.Net.Primitives exception runs and binds the thrown instance" {
    assert CatchTypes.SocketFailure(10061) == "ConnectionRefused"
    assert CatchTypes.SocketFailure(10054) == "ConnectionReset"
}

test "a catch clause naming a System.Text.Json exception catches what the framework throws" {
    assert CatchTypes.ParseFailureMessageLength("{") > 0
}

test "a catch clause naming an exception this compilation declares runs and binds it" {
    assert CatchTypes.SourceErrorCode(7) == 7
    assert CatchTypes.SourceErrorCode(0) == 0
}

test "clauses across three assemblies take the first match in declaration order" {
    assert CatchTypes.ClassifyThrown(0) == "socket:ConnectionRefused"
    assert CatchTypes.ClassifyThrown(1) == "json:bad json"
    assert CatchTypes.ClassifyThrown(2) == "source:7"
    assert CatchTypes.ClassifyThrown(3) == "base:other"
}

test "a base clause written first wins over a derived clause written after it" {
    assert CatchTypes.BaseBeforeDerived() == "base:3"
}

test "a derived clause written first claims only the derived value" {
    assert CatchTypes.DerivedBeforeBase(true) == "derived:4"
    assert CatchTypes.DerivedBeforeBase(false) == "base:5"
}

test "a non-corelib clause that does not match leaves the region for an outer handler" {
    assert CatchTypes.UnmatchedFallsThrough() == "outer:inner"
}

test "a bare catch still catches a non-corelib exception" {
    assert CatchTypes.BareCatchAll() == "bare"
}

test "a finally runs after a non-corelib typed clause returns" {
    log := new List<string>()
    assert CatchTypes.FinallyRunsAfterExternalCatch(log) == "caught:x"
    assert log.Count == 2
    assert log[0] == "catch"
    assert log[1] == "finally"
}

test "the bound variable carries the clause's own type" {
    assert CatchTypes.BoundVariableIsTheClauseType() == "timed-out"
}
