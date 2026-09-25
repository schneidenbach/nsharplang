namespace NSharpLang.CensusIterators.Tests

import System
import System.Collections.Generic


// EXECUTED PROOFS THAT AN INSTANCE GENERATOR NAMES ITS TYPE'S FIELDS EXACTLY AS AN ORDINARY MEMBER
// BODY DOES: every visibility is reachable, and a binding of the same spelling hides a field only
// while that binding is in scope.
func CensusMemberJoin(values: IEnumerable<string>): string {
    return String.Join(",", values)
}

func CensusMemberJoinInts(values: IEnumerable<int>): string {
    parts := new List<string>()
    for value in values {
        parts.Add(value.ToString())
    }
    return String.Join(",", parts)
}

test "an instance generator reads its type's public, camelCase and private fields" {
    assert CensusMemberJoin(new CensusLedger().Visibilities()) == "title,note,secret,note,secret"
}

test "an instance generator's state machine is nested in its declaring type" {
    sequence: object = new CensusLedger().Visibilities()
    machine := sequence.GetType()
    assert machine.IsNested
    assert machine.DeclaringType == typeof(CensusLedger)
}

test "a generator parameter hides a field of its name and this.name still reads the field" {
    assert CensusMemberJoin(new CensusLedger().ParameterHides("argument")) == "argument,secret"
}

test "a generator local hides a field from its next statement to the end of its block" {
    assert CensusMemberJoin(new CensusLedger().LocalHides(true)) == "note,note-local,note,inner,secret"
    assert CensusMemberJoin(new CensusLedger().LocalHides(false)) == "note,note-local,note,secret"
}

test "a generator loop variable hides a field for its loop body alone" {
    assert CensusMemberJoin(new CensusLedger().LoopVariablesHide()) == "a,b,note,0,secret"
}

test "a generator catch variable hides a field for its handler alone" {
    assert CensusMemberJoin(new CensusLedger().CatchVariableHides()) == "caught,note"
}

test "a lambda in a generator sees fields as the place it was written sees them" {
    assert CensusMemberJoin(new CensusLedger().LambdasSee()) == "argument!,notesecret,local/note"
}

test "a per-iteration lambda in a generator reaches private fields and this.name through its display" {
    assert CensusMemberJoin(new CensusLedger().PerIterationLambdas()) == "n1:secret:note,n2:secret:note"
}

test "a generator writes the field or the local a name means where it is written" {
    ledger := new CensusLedger()
    assert CensusMemberJoinInts(ledger.Writes()) == "1,10,101,2,111"
    assert ledger.Tally() == 111
}

test "a generator hiding a field leaves the field itself untouched" {
    ledger := new CensusLedger()
    assert CensusMemberJoin(ledger.LocalHides(true)).Length > 0
    assert ledger.Note() == "note"
}

test "an instance generator reads and writes its source base's public and camelCase fields" {
    derived := new CensusDerivedLedger()
    assert CensusMemberJoin(derived.Inherited()) == "shared,inherited,own,rewritten"
    assert derived.inherited == "rewritten"
}
