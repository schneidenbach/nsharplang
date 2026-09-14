namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Text

test "a source override's non-null annotation is what the receiver's type answers" {
    value := MakeLabelled("ada")
    assert FormatSource(value) == "ada"
    assert SourceEquals(value, MakeLabelled("ada"))
    assert !SourceEquals(value, MakeLabelled("grace"))
    assert SourceHash(value) == 3
}

test "a type that INHERITS the override reaches it too" {
    // `Marked` declares no `ToString` of its own; what its static type reaches is `Labelled`'s override,
    // which is non-null — not `object`'s `string?`.
    assert FormatInherited(MakeMarked("ada", 7)) == "ada"
}

test "the BCL's own overrides answer the same way" {
    builder := new StringBuilder()
    builder.Append("hi")
    assert FormatBuilder(builder) == "hi"
    assert FormatException(new InvalidOperationException("boom")).Contains("boom")
    assert FormatVersion(new Version(1, 2, 3)) == "1.2.3"
    assert FormatInt(42) == "42"
    assert FormatString("a") == "a"
}

test "the override really is the most-derived one in the emitted metadata" {
    // A slot that did NOT override would answer `object`'s method here, which is what an owner that
    // reads the base declaration's annotation is effectively doing.
    method := typeof(Labelled).GetMethod("ToString", Type.EmptyTypes)
    assert method != null
    assert method.DeclaringType == typeof(Labelled)

    inherited := typeof(Marked).GetMethod("ToString", Type.EmptyTypes)
    assert inherited != null
    assert inherited.DeclaringType == typeof(Labelled)

    // And the runtime dispatch agrees with the static answer.
    held: object = MakeMarked("ada", 7)
    assert held.ToString() == "ada"
}
