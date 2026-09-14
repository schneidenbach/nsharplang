namespace NSharpLang.CensusFlowRules.Tests

import System


// RUNTIME contracts for the flow state a PROPERTY PATH carries.
//
// Every function in `PropertyPathState.nl` reported NL905 on the line after its proof before this
// rule, so the file COMPILING is half of each contract. These assertions are the other half: the
// narrowed path is dereferenced for real, so a rule that proved the WRONG path throws here instead
// of quietly disagreeing, and the invalidation contracts are run with a null replacement so a stale
// fact becomes a NullReferenceException rather than a passing test.
func PathResponse(message: string): DaemonResponse {
    return new DaemonResponse("2.0", new ResponseError(-32601, message))
}

func EmptyResponse(): DaemonResponse {
    return new DaemonResponse("2.0", null)
}

// ── `must` proves the path ─────────────────────────────────────────────────────────────────────

test "an unwrapped member path is proved for every read after it" {
    assert ErrorCodeThenMessage(PathResponse("Unknown method: daemon/nope")) == "-32601:Unknown method: daemon/nope"
}

test "a BOUND unwrap proves the path as surely as a dereferenced one" {
    assert BoundErrorThenMessage(PathResponse("nope")) == "-32601:nope"
}

test "the same rule with a one-segment path is the plain local case" {
    assert UnwrappedTextLength("beta") == 8
}

test "a two-hop path is proved at the path the unwrap named" {
    assert DeepPathMessageLength(PathResponse("abcde")) == 10
}

test "an unwrap of a null path still throws — the proof is a check, not a claim" {
    assert throws InvalidOperationException {
        ErrorCodeThenMessage(EmptyResponse())
    }
}

// ── a `[NotNull]` postcondition on an argument EXPRESSION ──────────────────────────────────────

test "a source-declared [NotNull] member proves the PATH it was handed" {
    assert AssertedErrorMessage(PathResponse("asserted")) == "asserted"
}

test "the same attribute travels on an INSTANCE member" {
    assert AssertedErrorMessageViaInstance(PathResponse("instance"), new Check()) == "instance"
}

test "the BCL's own [NotNull] signature proves the same path the source one does" {
    assert ReflectedAssertedErrorMessage(PathResponse("reflected")) == "reflected"
}

test "the asserted path really is checked: a null path raises the declared failure" {
    assert throws InvalidOperationException {
        AssertedErrorMessage(EmptyResponse())
    }
}

test "the reflected assertion raises the BCL's own failure" {
    assert throws ArgumentNullException {
        ReflectedAssertedErrorMessage(EmptyResponse())
    }
}

// ── what takes the fact away ───────────────────────────────────────────────────────────────────

test "writing the path drops the fact, and the re-check is what the program relies on" {
    assert MessageAfterReset(PathResponse("first"), null) == "first|gone"
    assert MessageAfterReset(PathResponse("first"), new ResponseError(1, "second")) == "first|second"
}

test "writing a PREFIX drops everything under it" {
    assert MessageAfterPrefixAssignment(PathResponse("first"), EmptyResponse()) == "first|gone"
    assert MessageAfterPrefixAssignment(PathResponse("first"), PathResponse("second")) == "first|second"
}

test "an `out` argument on a PREFIX is an assignment and drops the fact" {
    assert MessageAfterOutRefill(PathResponse("first"), EmptyResponse()) == "first|gone"
    assert MessageAfterOutRefill(PathResponse("first"), PathResponse("second")) == "first|second"
}

test "a method call on the RECEIVER keeps the fact — the optimistic rule, running" {
    assert MessageAcrossReceiverCall(PathResponse("kept")) == "kept"
    assert MessageAcrossReceiverCall(EmptyResponse()) == "none"
}

// ── the back edge ──────────────────────────────────────────────────────────────────────────────

test "a guard written INSIDE a while body narrows the turn it is written on" {
    assert MessagesWhileResetting(PathResponse("once"), null, 3) == "once"
    assert MessagesWhileResetting(PathResponse("a"), new ResponseError(2, "b"), 3) == "abb"
}

test "the `for` form behaves the same, update clause and all" {
    assert MessagesForResetting(PathResponse("once"), null, 3) == "once"
    assert MessagesForResetting(PathResponse("a"), new ResponseError(2, "b"), 3) == "abb"
}

test "the `foreach` form behaves the same" {
    turns: int[] = [1, 2, 3]

    assert MessagesForEachResetting(PathResponse("once"), null, turns) == "once1"
    assert MessagesForEachResetting(PathResponse("a"), new ResponseError(2, "b"), turns) == "a1b2b3"
}

test "a loop that writes nothing keeps the fact it was given" {
    assert MessagesWithoutResetting(PathResponse("x"), 3) == "xxx"
    assert MessagesWithoutResetting(EmptyResponse(), 3) == ""
}

// ── a narrowed property path is a narrowed nullable ─────────────────────────────────────────────

func PathSample(slot: int?): Sample {
    return new Sample(slot, new DateTime(2027, 4, 5))
}

test "a narrowed property path answers `.Value` as the unwrap, not as a member of the element" {
    assert SlotValueOrMinusOne(PathSample(7)) == 7
    assert SlotValueOrMinusOne(PathSample(null)) == -1

    assert SlotDoubledOrMinusOne(PathSample(7)) == 14
    assert SlotDoubledOrMinusOne(PathSample(null)) == -1

    assert SlotAfterMust(PathSample(6)) == 12
}

test "`Nullable<T>`'s own surface answers through a narrowed path too" {
    assert SlotOrDefaultThroughPath(PathSample(9)) == 9
    assert SlotOrDefaultThroughPath(PathSample(null)) == -1

    assert MomentYearThroughPath(PathSample(1)) == 2027
}

test "writing the path still drops its state, and the unwrap after the write is the declared one" {
    // The second read goes through `GetValueOrDefault`, which is legal whatever the state is — so
    // what this pins is that the WRITE is what the second read sees.
    assert SlotAfterOverwrite(PathSample(4), 10) == 14
    assert SlotAfterOverwrite(PathSample(4), null) == 4
}
