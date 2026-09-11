namespace NSharpLang.RuntimeAcceptance

import System
import System.Collections.Generic
import System.Reflection

// WHAT THIS PROJECT IS. `Result.nl` and `Union.nl` are N# translations of the two generic types in
// `src/NSharpLang.Runtime`, written member for member. The runtime's own copies stay C# — a separate
// owner holds that assembly — so these are not replacements; they are the language held to a REAL
// public surface somebody already designed, rather than to shapes chosen because they compile.
//
// EVERY BEHAVIOURAL ASSERTION IS MADE TWICE where the language can spell both sides: once against the
// N# translation and once against the C# type it translates, on the same inputs. "Faithful" is a claim
// about behaviour, and two implementations that disagree on one input are two types, not one type in
// two languages.
//
// THE C# TYPE IS SPELLED IN FULL AT EVERY USE, because both types are named `Result` and the source
// one is the nearer declaration. A `type` alias would read better and is what the language documents
// for this; `type R = NSharpLang.Runtime.Result<int, string>` does not compile yet (recorded in
// website/docs/types.md's "Current limits"), and neither does an annotated local or a parameter of
// that type, so the C# values are all bound with `:=` from a factory call.

// ---- CONSTRUCTION AND THE TAG ------------------------------------------------------------------
test "the two factories are the only way in, and they set the arm" {
    ok := Result<int, string>.Ok(42)
    err := Result<int, string>.Err("failure")

    assert ok.IsOk
    assert !ok.IsErr
    assert !err.IsOk
    assert err.IsErr

    runtimeOk := NSharpLang.Runtime.Result<int, string>.Ok(42)
    runtimeErr := NSharpLang.Runtime.Result<int, string>.Err("failure")
    assert ok.IsOk == runtimeOk.IsOk
    assert ok.IsErr == runtimeOk.IsErr
    assert err.IsOk == runtimeErr.IsOk
    assert err.IsErr == runtimeErr.IsErr
}

test "a default value is neither arm" {
    uninitialized: Result<int, string> = default
    runtimeUninitialized: NSharpLang.Runtime.Result<int, string> = default

    assert !uninitialized.IsOk
    assert !uninitialized.IsErr
    assert uninitialized.IsOk == runtimeUninitialized.IsOk
    assert uninitialized.IsErr == runtimeUninitialized.IsErr
}

// ---- PAYLOAD READS, CHECKED AND UNCHECKED ------------------------------------------------------

test "the checked payload reads answer on their own arm" {
    ok := Result<int, string>.Ok(42)
    err := Result<int, string>.Err("failure")
    runtimeOk := NSharpLang.Runtime.Result<int, string>.Ok(42)
    runtimeErr := NSharpLang.Runtime.Result<int, string>.Err("failure")

    assert ok.OkValue == 42
    assert err.ErrValue == "failure"
    assert ok.OkValue == runtimeOk.OkValue
    assert err.ErrValue == runtimeErr.ErrValue
}

test "the checked ok read throws the exact message on the err arm" {
    err := Result<int, string>.Err("failure")
    runtimeErr := NSharpLang.Runtime.Result<int, string>.Err("failure")

    message := ""
    try {
        reached := err.OkValue
        message = "no throw: " + reached.ToString()
    } catch ex: InvalidOperationException {
        message = ex.Message
    }

    runtimeMessage := ""
    try {
        reached := runtimeErr.OkValue
        runtimeMessage = "no throw: " + reached.ToString()
    } catch ex: InvalidOperationException {
        runtimeMessage = ex.Message
    }

    assert message == "Result does not contain an Ok value."
    assert message == runtimeMessage
}

test "the checked err read throws the exact message on the ok arm" {
    ok := Result<int, string>.Ok(42)
    runtimeOk := NSharpLang.Runtime.Result<int, string>.Ok(42)

    message := ""
    try {
        reached := ok.ErrValue
        message = "no throw: " + (reached ?? "")
    } catch ex: InvalidOperationException {
        message = ex.Message
    }

    runtimeMessage := ""
    try {
        reached := runtimeOk.ErrValue
        runtimeMessage = "no throw: " + (reached ?? "")
    } catch ex: InvalidOperationException {
        runtimeMessage = ex.Message
    }

    assert message == "Result does not contain an Err value."
    assert message == runtimeMessage
}

test "an uninitialized value throws from both checked reads" {
    uninitialized: Result<int, string> = default
    runtimeUninitialized: NSharpLang.Runtime.Result<int, string> = default

    okMessage := ""
    try {
        reached := uninitialized.OkValue
        okMessage = "no throw: " + reached.ToString()
    } catch ex: InvalidOperationException {
        okMessage = ex.Message
    }

    errMessage := ""
    try {
        reached := uninitialized.ErrValue
        errMessage = "no throw: " + (reached ?? "")
    } catch ex: InvalidOperationException {
        errMessage = ex.Message
    }

    runtimeOkMessage := ""
    try {
        reached := runtimeUninitialized.OkValue
        runtimeOkMessage = "no throw: " + reached.ToString()
    } catch ex: InvalidOperationException {
        runtimeOkMessage = ex.Message
    }

    assert okMessage == "Result does not contain an Ok value."
    assert errMessage == "Result does not contain an Err value."
    assert okMessage == runtimeOkMessage
}

test "the unchecked reads hand back the slot without asking" {
    ok := Result<int, string>.Ok(42)
    err := Result<int, string>.Err("failure")
    runtimeOk := NSharpLang.Runtime.Result<int, string>.Ok(42)
    runtimeErr := NSharpLang.Runtime.Result<int, string>.Err("failure")

    assert ok.OkValueUnchecked == 42
    assert err.ErrValueUnchecked == "failure"
    // The OTHER slot of a one-armed value is the zero of its type — the documented contract, and what
    // makes these reads free.
    assert err.OkValueUnchecked == 0
    assert ok.ErrValueUnchecked == null

    assert ok.OkValueUnchecked == runtimeOk.OkValueUnchecked
    assert err.ErrValueUnchecked == runtimeErr.ErrValueUnchecked
    assert err.OkValueUnchecked == runtimeErr.OkValueUnchecked
    assert ok.ErrValueUnchecked == runtimeOk.ErrValueUnchecked
}

// ---- TRY-SHAPED READS --------------------------------------------------------------------------

test "TryGetOk answers true and writes only on the ok arm" {
    okValue := -1
    assert Result<int, string>.Ok(42).TryGetOk(out okValue)
    assert okValue == 42

    missValue := -1
    assert !Result<int, string>.Err("failure").TryGetOk(out missValue)
    assert missValue == 0
}
// The C# side is in `ResultParity.tests.nl`: reaching `TryGetOk` on it needs the type IMPORTED
// rather than spelled in full, because an external instance method with an `out` parameter does
// not bind through a fully-qualified receiver expression.

test "TryGetErr answers true and writes only on the err arm" {
    errValue := "seed"
    assert Result<int, string>.Err("failure").TryGetErr(out errValue)
    assert errValue == "failure"

    missValue := "seed"
    assert !Result<int, string>.Ok(42).TryGetErr(out missValue)
    assert missValue == null
}
// The C# side is in `ResultParity.tests.nl`, for the same reason as `TryGetOk` above.

test "an uninitialized value answers false from both Try reads" {
    uninitialized: Result<int, string> = default
    okValue := -1
    errValue := "seed"

    assert !uninitialized.TryGetOk(out okValue)
    assert !uninitialized.TryGetErr(out errValue)
    assert okValue == 0
    assert errValue == null
}

// ---- MATCH -------------------------------------------------------------------------------------

func OkText(value: int): string {
    return "ok:" + value.ToString()
}

func ErrText(error: string): string {
    return "err:" + (error ?? "")
}

test "Match runs the arm the value is on" {
    // The C# side is in `ResultParity.tests.nl`: an external generic method with written type
    // arguments binds through an IMPORTED name, not through a fully-qualified receiver expression.
    ok := Result<int, string>.Ok(42)
    err := Result<int, string>.Err("failure")

    assert ok.Match<string>(v => OkText(v), e => ErrText(e)) == "ok:42"
    assert err.Match<string>(v => OkText(v), e => ErrText(e)) == "err:failure"
    assert ok.Match<int>(v => v + 1, e => (e ?? "").Length) == 43
    assert err.Match<int>(v => v + 1, e => (e ?? "").Length) == 7
}

test "Match on an uninitialized value throws the exact message" {
    uninitialized: Result<int, string> = default
    runtimeUninitialized: NSharpLang.Runtime.Result<int, string> = default

    message := ""
    try {
        message = uninitialized.Match<string>(v => OkText(v), e => ErrText(e))
    } catch ex: InvalidOperationException {
        message = ex.Message
    }

    runtimeMessage := ""
    try {
        runtimeMessage = runtimeUninitialized.Match<string>(v => OkText(v), e => ErrText(e))
    } catch ex: InvalidOperationException {
        runtimeMessage = ex.Message
    }

    assert message == "The result value was not initialized with either arm."
    assert message == runtimeMessage
}

// THE NULL-ARM GUARD, REACHED THE ONLY WAY N# CAN REACH IT. `Match`'s parameters are non-nullable
// delegates and the language will not let a caller pass `null` — the C# type carries
// `ArgumentNullException.ThrowIfNull` because C#'s annotation is advisory, not enforced. The guard is
// still part of the translated surface and still runs, and a default array element is a value of the
// non-nullable delegate type that IS null at runtime, which is exactly the case the guard exists for.
test "Match rejects a null arm before it looks at the value" {
    arms := new Func<int, string>[](1)
    ok := Result<int, string>.Ok(42)

    assert throws ArgumentNullException {
        reached := ok.Match<string>(arms[0], e => ErrText(e))
        print reached
    }
}

// ---- EQUALITY, HASHING AND TEXT ----------------------------------------------------------------

test "two values of the same arm and payload are equal" {
    assert Result<int, string>.Ok(42).Equals(Result<int, string>.Ok(42))
    assert Result<int, string>.Err("failure").Equals(Result<int, string>.Err("failure"))
    assert NSharpLang.Runtime.Result<int, string>.Ok(42).Equals(NSharpLang.Runtime.Result<int, string>.Ok(42))
}

test "arms and payloads both have to match" {
    assert !Result<int, string>.Ok(42).Equals(Result<int, string>.Ok(7))
    assert !Result<int, string>.Ok(42).Equals(Result<int, string>.Err("failure"))
    assert !Result<int, string>.Err("a").Equals(Result<int, string>.Err("b"))
    assert !NSharpLang.Runtime.Result<int, string>.Ok(42).Equals(NSharpLang.Runtime.Result<int, string>.Ok(7))
    assert !NSharpLang.Runtime.Result<int, string>.Ok(42).Equals(NSharpLang.Runtime.Result<int, string>.Err("failure"))
}

test "two uninitialized values are equal to each other and to nothing else" {
    left: Result<int, string> = default
    right: Result<int, string> = default
    assert left.Equals(right)
    assert !left.Equals(Result<int, string>.Ok(0))
    assert !left.Equals(Result<int, string>.Err(""))

    runtimeLeft: NSharpLang.Runtime.Result<int, string> = default
    runtimeRight: NSharpLang.Runtime.Result<int, string> = default
    assert runtimeLeft.Equals(runtimeRight)
    assert !runtimeLeft.Equals(NSharpLang.Runtime.Result<int, string>.Ok(0))
}

test "a null reference payload is a payload, and equals another null" {
    nullOk := Result<string, string>.Ok(null)
    assert nullOk.Equals(Result<string, string>.Ok(null))
    assert !nullOk.Equals(Result<string, string>.Ok("x"))
    assert !Result<string, string>.Ok("x").Equals(nullOk)

    runtimeNullOk := NSharpLang.Runtime.Result<string, string>.Ok(null)
    assert runtimeNullOk.Equals(NSharpLang.Runtime.Result<string, string>.Ok(null))
    assert !runtimeNullOk.Equals(NSharpLang.Runtime.Result<string, string>.Ok("x"))
}

test "the object overload answers only for the same constructed type" {
    ok := Result<int, string>.Ok(42)
    same: object = Result<int, string>.Ok(42)
    other: object = Result<string, string>.Ok("42")

    assert ok.Equals(same)
    assert !ok.Equals(other)
    assert !ok.Equals(null)
    assert !ok.Equals(42)

    runtimeOk := NSharpLang.Runtime.Result<int, string>.Ok(42)
    runtimeSame: object = NSharpLang.Runtime.Result<int, string>.Ok(42)
    assert runtimeOk.Equals(runtimeSame)
    assert !runtimeOk.Equals(null)
}

test "hash codes agree with the C sharp type on every arm" {
    uninitialized: Result<int, string> = default
    runtimeUninitialized: NSharpLang.Runtime.Result<int, string> = default

    assert Result<int, string>.Ok(42).GetHashCode() == NSharpLang.Runtime.Result<int, string>.Ok(42).GetHashCode()
    assert Result<int, string>.Err("failure").GetHashCode() == NSharpLang.Runtime.Result<int, string>.Err("failure").GetHashCode()
    assert uninitialized.GetHashCode() == runtimeUninitialized.GetHashCode()
    assert uninitialized.GetHashCode() == 0
    // Equal values hash equally: the contract every dictionary depends on.
    assert Result<int, string>.Ok(42).GetHashCode() == Result<int, string>.Ok(42).GetHashCode()
}

test "ToString is the payload's own text, and empty when there is none" {
    uninitialized: Result<int, string> = default
    runtimeUninitialized: NSharpLang.Runtime.Result<int, string> = default

    assert Result<int, string>.Ok(42).ToString() == "42"
    assert Result<int, string>.Err("failure").ToString() == "failure"
    assert uninitialized.ToString() == ""
    assert Result<string, string>.Ok(null).ToString() == ""

    assert Result<int, string>.Ok(42).ToString() == NSharpLang.Runtime.Result<int, string>.Ok(42).ToString()
    assert Result<int, string>.Err("failure").ToString() == NSharpLang.Runtime.Result<int, string>.Err("failure").ToString()
    assert uninitialized.ToString() == runtimeUninitialized.ToString()
    assert Result<string, string>.Ok(null).ToString() == NSharpLang.Runtime.Result<string, string>.Ok(null).ToString()
}

test "the equality operators are the Equals they delegate to" {
    assert Result<int, string>.Ok(42) == Result<int, string>.Ok(42)
    assert !(Result<int, string>.Ok(42) != Result<int, string>.Ok(42))
    assert Result<int, string>.Ok(42) != Result<int, string>.Ok(7)
    assert Result<int, string>.Ok(42) != Result<int, string>.Err("failure")
    assert NSharpLang.Runtime.Result<int, string>.Ok(42) == NSharpLang.Runtime.Result<int, string>.Ok(42)
    assert NSharpLang.Runtime.Result<int, string>.Ok(42) != NSharpLang.Runtime.Result<int, string>.Err("failure")
}

// ---- THE FACTORY CLASS -------------------------------------------------------------------------

test "ResultFactory builds the same values the type's own factories do" {
    // The C# `ResultFactory` is compared in `ResultParity.tests.nl`, which reaches it by import.
    assert ResultFactory.Ok<int, string>(42) == Result<int, string>.Ok(42)
    assert ResultFactory.Err<int, string>("failure") == Result<int, string>.Err("failure")
    assert ResultFactory.Ok<int, string>(42).IsOk
    assert ResultFactory.Err<int, string>("failure").IsErr
    assert ResultFactory.Ok<int, string>(42).OkValue == 42
}

// ---- THE EMITTED METADATA ----------------------------------------------------------------------

func CarriesAttributeNamed(candidate: Type, attributeName: string): bool {
    for attribute in candidate.GetCustomAttributes(false) {
        if attribute.GetType().Name == attributeName {
            return true
        }
    }

    return false
}

func ImplementsInterface(candidate: Type, wanted: Type): bool {
    for implemented in candidate.GetInterfaces() {
        if implemented == wanted {
            return true
        }
    }

    return false
}

test "the translation is a readonly value type, exactly as the C sharp one is" {
    assert typeof(Result<int, string>).get_IsValueType()
    assert typeof(Result<int, string>).get_IsValueType() == typeof(NSharpLang.Runtime.Result<int, string>).get_IsValueType()
    assert CarriesAttributeNamed(typeof(Result<int, string>).GetGenericTypeDefinition(), "IsReadOnlyAttribute")
    assert CarriesAttributeNamed(typeof(NSharpLang.Runtime.Result<int, string>).GetGenericTypeDefinition(), "IsReadOnlyAttribute")
}

test "the CLR name carries the arity, and the type parameters are two" {
    assert typeof(Result<int, string>).GetGenericTypeDefinition().get_Name() == "Result`2"
    assert typeof(Result<int, string>).GetGenericTypeDefinition().get_Name() == typeof(NSharpLang.Runtime.Result<int, string>).GetGenericTypeDefinition().get_Name()
    assert typeof(Result<int, string>).GetGenericArguments().Length == 2
    assert typeof(Result<int, string>).GetGenericArguments()[0] == typeof(int)
    assert typeof(Result<int, string>).GetGenericArguments()[1] == typeof(string)
}

// INTERFACE DISPATCH THROUGH THE BASE LIST, ASKED THE WAY THE BCL ASKS IT. `EqualityComparer<T>` picks
// `IEquatable<T>`'s implementation when the type has one, so a comparer over the CONSTRUCTED
// translation reaches `Equals(Result<int, string>)` — the declared implementation — rather than the
// object overload. That is the whole observable meaning of the base list, and it is asserted here
// because the direct spelling cannot be: a local typed by an external generic over a COMPLETE source
// type (`e: IEquatable<Result<int, string>> = r`) still declines at
// `emit.typed-local.unsupported-type`, which is a separate stream's slice.
test "the declared IEquatable implementation is what BCL dispatch reaches" {
    ok := Result<int, string>.Ok(42)
    sameOk := Result<int, string>.Ok(42)
    otherOk := Result<int, string>.Ok(7)
    err := Result<int, string>.Err("failure")
    uninitialized: Result<int, string> = default
    alsoUninitialized: Result<int, string> = default

    // The comparer is used in place rather than bound to a name: a LOCAL typed by an external generic
    // over a complete source type is the same decline as the `IEquatable<...>` local above.
    assert EqualityComparer<Result<int, string>>.Default.Equals(ok, sameOk)
    assert !EqualityComparer<Result<int, string>>.Default.Equals(ok, otherOk)
    assert !EqualityComparer<Result<int, string>>.Default.Equals(ok, err)
    assert EqualityComparer<Result<int, string>>.Default.Equals(uninitialized, alsoUninitialized)
    assert EqualityComparer<Result<int, string>>.Default.GetHashCode(ok) == ok.GetHashCode()

    runtimeOk := NSharpLang.Runtime.Result<int, string>.Ok(42)
    runtimeSame := NSharpLang.Runtime.Result<int, string>.Ok(42)
    runtimeErr := NSharpLang.Runtime.Result<int, string>.Err("failure")
    assert EqualityComparer<NSharpLang.Runtime.Result<int, string>>.Default.Equals(runtimeOk, runtimeSame)
    assert !EqualityComparer<NSharpLang.Runtime.Result<int, string>>.Default.Equals(runtimeOk, runtimeErr)
}

test "the constructed type implements IEquatable of itself" {
    assert ImplementsInterface(typeof(Result<int, string>), typeof(IEquatable<Result<int, string>>))
    assert ImplementsInterface(typeof(NSharpLang.Runtime.Result<int, string>), typeof(IEquatable<NSharpLang.Runtime.Result<int, string>>))
}

test "the factories are static and the constructor is private" {
    okMethod := typeof(Result<int, string>).GetMethod("Ok")
    assert okMethod != null
    if okMethod != null {
        assert okMethod.get_IsStatic()
        assert okMethod.get_IsPublic()
    }

    assert typeof(NSharpLang.Runtime.Result<int, string>).GetMethod("Ok") != null

    constructors := typeof(Result<int, string>).GetConstructors(BindingFlags.Instance | BindingFlags.NonPublic)
    assert constructors.Length == 1
    assert constructors[0].get_IsPrivate()
    assert typeof(Result<int, string>).GetConstructors().Length == 0
    assert typeof(NSharpLang.Runtime.Result<int, string>).GetConstructors().Length == 0
}

test "Match is a real generic method on both types" {
    matchMethod := typeof(Result<int, string>).GetMethod("Match")
    runtimeMatch := typeof(NSharpLang.Runtime.Result<int, string>).GetMethod("Match")
    assert matchMethod != null
    assert runtimeMatch != null
    if matchMethod != null && runtimeMatch != null {
        assert matchMethod.GetGenericArguments().Length == 1
        assert matchMethod.GetParameters().Length == 2
        assert matchMethod.GetGenericArguments().Length == runtimeMatch.GetGenericArguments().Length
        assert matchMethod.GetParameters().Length == runtimeMatch.GetParameters().Length
    }
}

test "the equality operators reach CLR metadata under their operator names" {
    definition := typeof(Result<int, string>).GetGenericTypeDefinition()
    equality := definition.GetMethod("op_Equality")
    inequality := definition.GetMethod("op_Inequality")
    assert equality != null
    assert inequality != null
    if equality != null {
        assert equality.get_IsStatic()
        assert equality.get_ReturnType() == typeof(bool)
        assert equality.GetParameters().Length == 2
    }
}
