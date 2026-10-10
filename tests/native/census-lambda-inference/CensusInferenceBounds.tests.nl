namespace NSharpLang.CensusLambdaInference.Tests

import System.Collections.Generic
import Xunit


// ── `X` and `X?` as two bounds for one reflected type parameter ───────────────────────────────
test "a reflected generic method takes the lifted bound when its two arguments are `X` and `X?`" {
    // `Assert.Equal<T>(T, T)` is the census's own shape: xunit is a REFLECTED assembly here, so the
    // two arguments are the only thing that can decide `T`. `Level` and `Level?` fix it to `Level?`.
    present := ReadingWith(Level.High)
    Assert.Equal(Level.High, present.Severity)

    // The same call written the other way round: the lifted bound arrives FIRST and absorbs the
    // plain one, which is the direction that already bound and must keep binding.
    Assert.Equal(present.Severity, Level.High)
}

test "the lifted instantiation is the one that actually runs" {
    // If `T` had been fixed to `Level`, this call could not be written at all — a `Level` position
    // cannot hold `null`. It is written, it runs, and it FAILS, which is what proves the emitted
    // call is `Equal<Level?>` and compares a real `Nullable<Level>` rather than an unwrapped value.
    absent := ReadingWith(null)
    threw := false
    try {
        Assert.Equal(Level.High, absent.Severity)
    } catch {
        threw = true
    }

    assert threw

    // And two DIFFERENT values of the lifted type still disagree, so the lift did not collapse the
    // comparison into "both have a value".
    low := ReadingWith(Level.Low)
    disagreed := false
    try {
        Assert.Equal(Level.High, low.Severity)
    } catch {
        disagreed = true
    }

    assert disagreed
}

test "the lifted bound is found through a reflected member, not only a source one" {
    // `List<int?>.FirstOrDefault()` is reflected end to end; the literal supplies the plain bound.
    values := new List<int?>()
    values.Add(3)
    Assert.Equal(3, FirstBoxedOrNull(values))

    empty := new List<int?>()
    assert FirstBoxedOrNull(empty) == null
}

test "a reference type's annotation lifts the same way" {
    // `string` and `string?` are ONE CLR type, so only the N# spelling changes — the call binds and
    // the comparison is the ordinary string one.
    Assert.Equal("alpha", MaybeName(true))

    threw := false
    try {
        Assert.Equal("alpha", MaybeName(false))
    } catch {
        threw = true
    }

    assert threw
}

test "an argument list that agrees exactly is untouched by the lifting rule" {
    Assert.Equal(Level.High, Level.High)
    Assert.Equal(4, 4)

    both := ReadingWith(Level.Low)
    Assert.Equal(both.Severity, both.Severity)
}
