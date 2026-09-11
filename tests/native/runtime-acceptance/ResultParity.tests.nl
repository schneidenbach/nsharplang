namespace NSharpLang.RuntimeAcceptance.Parity

import System
import NSharpLang.Runtime

// THE C# SIDE OF THE RESULT TRANSLATION, for the members `Result.tests.nl` could not compare in place.
// That file spells the C# type in full at every use, which reaches its properties, its factories, its
// equality and its metadata — but not `TryGetOk`/`TryGetErr` (an external instance method with an
// `out` parameter) or `Match<TResult>` (an external generic method with written type arguments),
// neither of which binds yet. Imported into a namespace that declares no `Result` of its own, both do,
// and the assertions below are the same ones the translation answers.
func ResultOkText(value: int): string {
    return "ok:" + value.ToString()
}

func ResultErrText(error: string): string {
    return "err:" + (error ?? "")
}

test "C# result: TryGetOk answers true and writes only on the ok arm" {
    ok := Result<int, string>.Ok(42)
    err := Result<int, string>.Err("failure")

    okValue := -1
    assert ok.TryGetOk(out okValue)
    assert okValue == 42

    missValue := -1
    assert !err.TryGetOk(out missValue)
    assert missValue == 0
}

test "C# result: TryGetErr answers true and writes only on the err arm" {
    ok := Result<int, string>.Ok(42)
    err := Result<int, string>.Err("failure")

    errValue := "seed"
    assert err.TryGetErr(out errValue)
    assert errValue == "failure"

    missValue := "seed"
    assert !ok.TryGetErr(out missValue)
    assert missValue == null
}

test "C# result: an uninitialized value answers false from both Try reads" {
    uninitialized: Result<int, string> = default
    okValue := -1
    errValue := "seed"

    assert !uninitialized.TryGetOk(out okValue)
    assert !uninitialized.TryGetErr(out errValue)
    assert okValue == 0
    assert errValue == null
}

test "C# result: Match runs the arm the value is on" {
    ok := Result<int, string>.Ok(42)
    err := Result<int, string>.Err("failure")

    assert ok.Match<string>(v => ResultOkText(v), e => ResultErrText(e)) == "ok:42"
    assert err.Match<string>(v => ResultErrText(err.ErrValue), e => ResultErrText(e)) == "err:failure"
    assert ok.Match<int>(v => v + 1, e => (e ?? "").Length) == 43
    assert err.Match<int>(v => v + 1, e => (e ?? "").Length) == 7
}

test "C# result: Match on an uninitialized value throws the exact message" {
    uninitialized: Result<int, string> = default
    message := ""
    try {
        message = uninitialized.Match<string>(v => ResultOkText(v), e => ResultErrText(e))
    } catch ex: InvalidOperationException {
        message = ex.Message
    }

    assert message == "The result value was not initialized with either arm."
}

test "C# result: Match rejects a null arm" {
    arms := new Func<int, string>[](1)
    ok := Result<int, string>.Ok(42)

    assert throws ArgumentNullException {
        reached := ok.Match<string>(arms[0], e => ResultErrText(e))
        print reached
    }
}

test "C# result: ResultFactory builds the same values the type's own factories do" {
    assert ResultFactory.Ok<int, string>(42) == Result<int, string>.Ok(42)
    assert ResultFactory.Err<int, string>("failure") == Result<int, string>.Err("failure")
    assert ResultFactory.Ok<int, string>(42).IsOk
    assert ResultFactory.Err<int, string>("failure").IsErr
    assert ResultFactory.Ok<int, string>(42).OkValue == 42
}
