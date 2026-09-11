namespace NSharpLang.RuntimeParity

import System
import NSharpLang.Runtime

// THE TWO RESULTS, SIDE BY SIDE, ON THE SAME INPUTS — the same claim `UnionParity.tests.nl` makes,
// for `src/NSharpLang.Runtime/Result.cs` and its translation in `Result.nl`.
//
// THE NAMESPACE IS LOAD-BEARING for the same reason it is there: from inside
// `NSharpLang.RuntimeAcceptance`, or any child of it, the bare `Result` is the TRANSLATION however
// the file imports, so a comparison written there compares the translation with itself. Here the
// bare `Result` is the imported C# type and the translation is spelled in full, and the first test
// proves that from the emitted metadata.
//
// `Result.tests.nl` reaches the C# type from inside the translation's own namespace by spelling
// `NSharpLang.Runtime.Result<...>` at every use, and keeps every row it can say that way. This file
// carries the rows that need the C# type by SIMPLE name — an `out` parameter's receiver — plus the
// identity proof neither file could make before.
//
// WHAT THIS FILE CANNOT YET SAY. `Match<TResult>(...)` is asserted against the translation in
// `Result.tests.nl` and has no row here: a GENERIC INSTANCE METHOD of an external constructed
// generic does not bind yet (`r.Match<string>(...)` declines with "generic call 'r.Match' with 2
// argument(s) could not be resolved"), and neither does a generic STATIC method of an external
// type, which is what keeps `ResultFactory.Ok<int, string>(42)` out of this file. Both are compiler
// gaps, recorded in `website/docs/types.md` under "Current limits", and neither is a claim that the
// two types differ.
func RuntimeOk(): Result<int, string> {
    return Result<int, string>.Ok(42)
}

func RuntimeErr(): Result<int, string> {
    return Result<int, string>.Err("failure")
}

func TranslationOk(): NSharpLang.RuntimeAcceptance.Result<int, string> {
    return NSharpLang.RuntimeAcceptance.Result<int, string>.Ok(42)
}

func TranslationErr(): NSharpLang.RuntimeAcceptance.Result<int, string> {
    return NSharpLang.RuntimeAcceptance.Result<int, string>.Err("failure")
}

test "the two spellings are two DIFFERENT types, which is what makes every row below a comparison" {
    runtimeOk := RuntimeOk()
    translationOk := TranslationOk()
    runtimeBoxed: object = runtimeOk
    translationBoxed: object = translationOk

    runtimeDefinition := runtimeBoxed.GetType().GetGenericTypeDefinition()
    translationDefinition := translationBoxed.GetType().GetGenericTypeDefinition()

    assert runtimeDefinition.FullName == "NSharpLang.Runtime.Result`2"
    assert translationDefinition.FullName == "NSharpLang.RuntimeAcceptance.Result`2"
    assert runtimeDefinition.get_Assembly().get_FullName() != translationDefinition.get_Assembly().get_FullName()
}

test "the factories and the arm questions agree on both types" {
    runtimeOk := RuntimeOk()
    runtimeErr := RuntimeErr()
    translationOk := TranslationOk()
    translationErr := TranslationErr()
    runtimeUninitialized: Result<int, string> = default
    translationUninitialized: NSharpLang.RuntimeAcceptance.Result<int, string> = default

    assert runtimeOk.IsOk == translationOk.IsOk
    assert runtimeOk.IsErr == translationOk.IsErr
    assert runtimeErr.IsOk == translationErr.IsOk
    assert runtimeErr.IsErr == translationErr.IsErr
    assert runtimeUninitialized.IsOk == translationUninitialized.IsOk
    assert runtimeUninitialized.IsErr == translationUninitialized.IsErr

    assert runtimeOk.IsOk
    assert !runtimeOk.IsErr
    assert runtimeErr.IsErr
    assert !runtimeErr.IsOk
    assert !runtimeUninitialized.IsOk
    assert !runtimeUninitialized.IsErr
}

test "the payload readers agree on both types" {
    runtimeOk := RuntimeOk()
    runtimeErr := RuntimeErr()
    translationOk := TranslationOk()
    translationErr := TranslationErr()

    assert runtimeOk.OkValue == translationOk.OkValue
    assert runtimeErr.ErrValue == translationErr.ErrValue
    assert runtimeOk.OkValueUnchecked == translationOk.OkValueUnchecked
    assert runtimeErr.ErrValueUnchecked == translationErr.ErrValueUnchecked

    assert runtimeOk.OkValue == 42
    assert runtimeErr.ErrValue == "failure"
}

test "reading the WRONG arm throws the same exception with the same message, on both types" {
    runtimeOk := RuntimeOk()
    translationOk := TranslationOk()

    runtimeMessage := "no throw"
    try {
        reached := runtimeOk.ErrValue
        print reached
    } catch ex: InvalidOperationException {
        runtimeMessage = ex.Message
    }

    translationMessage := "no throw"
    try {
        reached := translationOk.ErrValue
        print reached
    } catch ex: InvalidOperationException {
        translationMessage = ex.Message
    }

    assert runtimeMessage == translationMessage
    assert runtimeMessage == "Result does not contain an Err value."
}

// An uninitialized result is neither arm, so the ARM guard fires before the uninitialized one does —
// `OkValue` says "not an Ok value" rather than "not initialized", on both types.
test "reading either arm of an UNINITIALIZED result throws the same message, on both types" {
    runtimeUninitialized: Result<int, string> = default
    translationUninitialized: NSharpLang.RuntimeAcceptance.Result<int, string> = default

    runtimeMessage := "no throw"
    try {
        reached := runtimeUninitialized.OkValue
        print reached
    } catch ex: InvalidOperationException {
        runtimeMessage = ex.Message
    }

    translationMessage := "no throw"
    try {
        reached := translationUninitialized.OkValue
        print reached
    } catch ex: InvalidOperationException {
        translationMessage = ex.Message
    }

    assert runtimeMessage == translationMessage
    assert runtimeMessage == "Result does not contain an Ok value."
}

test "TryGetOk answers the same and writes the same, on both types" {
    runtimeOk := RuntimeOk()
    runtimeErr := RuntimeErr()
    translationOk := TranslationOk()
    translationErr := TranslationErr()

    runtimeValue := -1
    translationValue := -1
    assert runtimeOk.TryGetOk(out runtimeValue) == translationOk.TryGetOk(out translationValue)
    assert runtimeValue == translationValue
    assert runtimeValue == 42

    runtimeMiss := -1
    translationMiss := -1
    assert runtimeErr.TryGetOk(out runtimeMiss) == translationErr.TryGetOk(out translationMiss)
    assert runtimeMiss == translationMiss
    assert runtimeMiss == 0
}

test "TryGetErr answers the same and writes the same, on both types" {
    runtimeOk := RuntimeOk()
    runtimeErr := RuntimeErr()
    translationOk := TranslationOk()
    translationErr := TranslationErr()

    runtimeError := "seed"
    translationError := "seed"
    assert runtimeErr.TryGetErr(out runtimeError) == translationErr.TryGetErr(out translationError)
    assert runtimeError == translationError
    assert runtimeError == "failure"

    runtimeMiss := "seed"
    translationMiss := "seed"
    assert runtimeOk.TryGetErr(out runtimeMiss) == translationOk.TryGetErr(out translationMiss)
    assert runtimeMiss == translationMiss
    assert runtimeMiss == null
}

test "an UNINITIALIZED result answers false from both Try reads and writes the zero, on both types" {
    runtimeUninitialized: Result<int, string> = default
    translationUninitialized: NSharpLang.RuntimeAcceptance.Result<int, string> = default

    runtimeValue := -1
    translationValue := -1
    assert runtimeUninitialized.TryGetOk(out runtimeValue) == translationUninitialized.TryGetOk(out translationValue)
    assert runtimeValue == translationValue
    assert runtimeValue == 0

    runtimeError := "seed"
    translationError := "seed"
    assert runtimeUninitialized.TryGetErr(out runtimeError) == translationUninitialized.TryGetErr(out translationError)
    assert runtimeError == translationError
    assert runtimeError == null
}

test "a NULL ok payload is a value both types accept and read back" {
    runtimeNullOk := Result<string, string>.Ok(null)
    translationNullOk := NSharpLang.RuntimeAcceptance.Result<string, string>.Ok(null)

    runtimeValue := "seed"
    translationValue := "seed"
    assert runtimeNullOk.TryGetOk(out runtimeValue) == translationNullOk.TryGetOk(out translationValue)
    assert runtimeValue == translationValue
    assert runtimeValue == null
    assert runtimeNullOk.IsOk == translationNullOk.IsOk
    assert runtimeNullOk.IsOk
}

test "Equals, ==, GetHashCode and ToString agree on both types" {
    runtimeOk := RuntimeOk()
    runtimeErr := RuntimeErr()
    translationOk := TranslationOk()
    translationErr := TranslationErr()
    runtimeUninitialized: Result<int, string> = default
    translationUninitialized: NSharpLang.RuntimeAcceptance.Result<int, string> = default

    assert runtimeOk.Equals(Result<int, string>.Ok(42)) == translationOk.Equals(NSharpLang.RuntimeAcceptance.Result<int, string>.Ok(42))
    assert runtimeOk.Equals(Result<int, string>.Ok(7)) == translationOk.Equals(NSharpLang.RuntimeAcceptance.Result<int, string>.Ok(7))
    assert runtimeOk.Equals(runtimeErr) == translationOk.Equals(translationErr)
    assert runtimeUninitialized.Equals(Result<int, string>.Ok(0)) == translationUninitialized.Equals(NSharpLang.RuntimeAcceptance.Result<int, string>.Ok(0))

    assert (runtimeOk == Result<int, string>.Ok(42)) == (translationOk == NSharpLang.RuntimeAcceptance.Result<int, string>.Ok(42))
    assert (runtimeOk != runtimeErr) == (translationOk != translationErr)

    assert runtimeOk.GetHashCode() == translationOk.GetHashCode()
    assert runtimeErr.GetHashCode() == translationErr.GetHashCode()
    assert runtimeUninitialized.GetHashCode() == translationUninitialized.GetHashCode()

    assert runtimeOk.ToString() == translationOk.ToString()
    assert runtimeErr.ToString() == translationErr.ToString()
    assert runtimeUninitialized.ToString() == translationUninitialized.ToString()

    assert runtimeOk.Equals(Result<int, string>.Ok(42))
    assert runtimeOk == Result<int, string>.Ok(42)
    assert runtimeOk != runtimeErr
    assert runtimeOk.ToString() == "42"
    assert runtimeErr.ToString() == "failure"
}

test "a BOXED result of the other type is equal to neither, which is what a self-comparison would miss" {
    runtimeBoxed: object = Result<int, string>.Ok(42)
    translationBoxed: object = NSharpLang.RuntimeAcceptance.Result<int, string>.Ok(42)
    runtimeOk := RuntimeOk()
    translationOk := TranslationOk()

    assert runtimeOk.Equals(runtimeBoxed) == translationOk.Equals(translationBoxed)
    assert runtimeOk.Equals(runtimeBoxed)
    assert !runtimeOk.Equals(translationBoxed)
    assert !translationOk.Equals(runtimeBoxed)
}

test "the emitted metadata is the same shape on both types" {
    runtimeType := typeof(Result<int, string>)
    translationType := typeof(NSharpLang.RuntimeAcceptance.Result<int, string>)
    runtimeDefinition := runtimeType.GetGenericTypeDefinition()
    translationDefinition := translationType.GetGenericTypeDefinition()

    assert runtimeType.get_IsValueType() == translationType.get_IsValueType()
    assert runtimeDefinition.get_Name() == translationDefinition.get_Name()
    assert runtimeDefinition.GetGenericArguments().Length == translationDefinition.GetGenericArguments().Length

    assert runtimeType.get_IsValueType()
    assert runtimeDefinition.get_Name() == "Result`2"
}
