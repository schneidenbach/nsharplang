namespace NSharpLang.RuntimeParity

import System
import NSharpLang.Runtime

// THE TWO UNIONS, SIDE BY SIDE, ON THE SAME INPUTS.
//
// `Union.nl` is an N# translation of `src/NSharpLang.Runtime/Union.cs` and `Union.tests.nl` says
// what the translation does. This file is the claim that the two types AGREE, and for that claim to
// mean anything the two spellings here have to denote two different types.
//
// THE NAMESPACE IS THE WHOLE REASON THIS FILE IS SHAPED THIS WAY. A source declaration is always
// the nearer name, and an ENCLOSING namespace counts as near: from `NSharpLang.RuntimeAcceptance`
// — and from any child of it — the bare `Union` is the translation, and `import NSharpLang.Runtime`
// does not change that. A file that lives under the translation's namespace and writes
// `Union<int, string>` on both sides of an `assert` is therefore comparing the translation with
// ITSELF, no matter what it imports. This namespace is NOT under `NSharpLang.RuntimeAcceptance`, so
// the bare `Union` here is the imported C# type and the translation is reached by its full name.
// The first test proves that from the emitted metadata rather than from this note.
//
// WHAT THIS FILE CANNOT YET SAY. `Is<T>()`, `TryGet<T>(out value)`, `As<T>()`, `Match<TResult>(...)`
// and `Switch(...)` are asserted against the TRANSLATION in `Union.tests.nl` and have no row here,
// because a GENERIC INSTANCE METHOD of an external constructed generic does not bind yet —
// `u.Is<int>()` on the runtime union declines with "generic call 'u.Is' with 0 argument(s) could not
// be resolved". That is a compiler gap, recorded in `website/docs/types.md` under "Current limits",
// and not a claim that the two types differ.
func TranslationIntArm(): NSharpLang.RuntimeAcceptance.Union<int, string> {
    return new NSharpLang.RuntimeAcceptance.Union<int, string>(5)
}

func TranslationTextArm(): NSharpLang.RuntimeAcceptance.Union<int, string> {
    return new NSharpLang.RuntimeAcceptance.Union<int, string>("five")
}

func RuntimeIntArm(): Union<int, string> {
    return new Union<int, string>(5)
}

func RuntimeTextArm(): Union<int, string> {
    return new Union<int, string>("five")
}

// The conversion in an ARGUMENT position, on each type.
func RuntimeArmOf(value: Union<int, string>): int {
    return value.Index
}

func TranslationArmOf(value: NSharpLang.RuntimeAcceptance.Union<int, string>): int {
    return value.Index
}

// The conversion in a RETURN position, on each type.
func RuntimeConvertedInt(): Union<int, string> {
    return 5
}

func TranslationConvertedInt(): NSharpLang.RuntimeAcceptance.Union<int, string> {
    return 5
}

func RuntimeConvertedText(): Union<int, string> {
    return "five"
}

func TranslationConvertedText(): NSharpLang.RuntimeAcceptance.Union<int, string> {
    return "five"
}

// A NULL PAYLOAD the type system still sees as the arm's type: a default array element is a `string`
// value that is null at runtime.
func NullText(): string {
    slots := new string[](1)
    return slots[0]
}

test "the two spellings are two DIFFERENT types, which is what makes every row below a comparison" {
    runtimeArm := RuntimeIntArm()
    translationArm := TranslationIntArm()
    runtimeBoxed: object = runtimeArm
    translationBoxed: object = translationArm

    runtimeDefinition := runtimeBoxed.GetType().GetGenericTypeDefinition()
    translationDefinition := translationBoxed.GetType().GetGenericTypeDefinition()

    assert runtimeDefinition.FullName == "NSharpLang.Runtime.Union`2"
    assert translationDefinition.FullName == "NSharpLang.RuntimeAcceptance.Union`2"

    // And the C# one really is the referenced assembly's, not a same-named source declaration.
    assert runtimeDefinition.get_Assembly().get_FullName() != translationDefinition.get_Assembly().get_FullName()
}

test "each constructor records the same arm on both types" {
    runtimeInt := RuntimeIntArm()
    translationInt := TranslationIntArm()
    runtimeText := RuntimeTextArm()
    translationText := TranslationTextArm()

    assert runtimeInt.Index == translationInt.Index
    assert runtimeText.Index == translationText.Index
    assert runtimeInt.Index == 0
    assert runtimeText.Index == 1
}

test "the IMPLICIT CONVERSIONS are the constructors, on both types" {
    // This is the row the analyzer could not compile at all against the C# type: the conversion is
    // declared by an EXTERNAL constructed generic, and the user-defined conversion search only read
    // source declarations.
    runtimeFromInt: Union<int, string> = 5
    runtimeFromText: Union<int, string> = "five"
    translationFromInt: NSharpLang.RuntimeAcceptance.Union<int, string> = 5
    translationFromText: NSharpLang.RuntimeAcceptance.Union<int, string> = "five"

    assert runtimeFromInt.Index == translationFromInt.Index
    assert runtimeFromText.Index == translationFromText.Index
    assert runtimeFromInt == RuntimeIntArm()
    assert translationFromInt == TranslationIntArm()
    assert runtimeFromText == RuntimeTextArm()
    assert translationFromText == TranslationTextArm()
}

test "a written CAST reaches the same conversion on both types" {
    runtimeCast := (Union<int, string>)5
    translationCast := (NSharpLang.RuntimeAcceptance.Union<int, string>)5

    assert runtimeCast.Index == translationCast.Index
    assert runtimeCast == RuntimeIntArm()
    assert translationCast == TranslationIntArm()
}

test "the conversion reaches an ARGUMENT and a RETURN position on both types" {
    assert RuntimeArmOf(5) == TranslationArmOf(5)
    assert RuntimeArmOf("five") == TranslationArmOf("five")
    assert RuntimeArmOf(5) == 0
    assert RuntimeArmOf("five") == 1

    runtimeReturnedInt := RuntimeConvertedInt()
    translationReturnedInt := TranslationConvertedInt()
    runtimeReturnedText := RuntimeConvertedText()
    translationReturnedText := TranslationConvertedText()

    assert runtimeReturnedInt.Index == translationReturnedInt.Index
    assert runtimeReturnedText.Index == translationReturnedText.Index
    assert runtimeReturnedInt.Index == 0
    assert runtimeReturnedText.Index == 1
}

test "an uninitialized union has no arm, on both types" {
    runtimeUninitialized: Union<int, string> = default
    translationUninitialized: NSharpLang.RuntimeAcceptance.Union<int, string> = default

    assert runtimeUninitialized.Index == translationUninitialized.Index
    assert runtimeUninitialized.Index == -1
}

test "Value hands back the payload of whichever arm is live, on both types" {
    runtimeIntArm := RuntimeIntArm()
    translationIntArm := TranslationIntArm()
    runtimeTextArm := RuntimeTextArm()
    translationTextArm := TranslationTextArm()

    runtimeInt := runtimeIntArm.Value
    translationInt := translationIntArm.Value
    runtimeText := runtimeTextArm.Value
    translationText := translationTextArm.Value

    assert runtimeInt != null
    assert translationInt != null
    assert runtimeText != null
    assert translationText != null

    if runtimeInt != null && translationInt != null {
        assert runtimeInt.ToString() == translationInt.ToString()
        assert runtimeInt.ToString() == "5"
    }

    if runtimeText != null && translationText != null {
        assert runtimeText.ToString() == translationText.ToString()
        assert runtimeText.ToString() == "five"
    }
}

test "Value on an uninitialized union throws the SAME exception with the SAME message" {
    runtimeUninitialized: Union<int, string> = default
    translationUninitialized: NSharpLang.RuntimeAcceptance.Union<int, string> = default

    runtimeMessage := "no throw"
    try {
        reached := runtimeUninitialized.Value
        print reached
    } catch ex: InvalidOperationException {
        runtimeMessage = ex.Message
    }

    translationMessage := "no throw"
    try {
        reached := translationUninitialized.Value
        print reached
    } catch ex: InvalidOperationException {
        translationMessage = ex.Message
    }

    assert runtimeMessage == translationMessage
    assert runtimeMessage == "The union value was not initialized with either arm."
}

test "Equals agrees on every pair, on both types" {
    runtimeUninitialized: Union<int, string> = default
    translationUninitialized: NSharpLang.RuntimeAcceptance.Union<int, string> = default
    runtimeIntArm := RuntimeIntArm()
    translationIntArm := TranslationIntArm()

    assert runtimeIntArm.Equals(new Union<int, string>(5)) == translationIntArm.Equals(new NSharpLang.RuntimeAcceptance.Union<int, string>(5))
    assert runtimeIntArm.Equals(new Union<int, string>(6)) == translationIntArm.Equals(new NSharpLang.RuntimeAcceptance.Union<int, string>(6))
    assert runtimeIntArm.Equals(RuntimeTextArm()) == translationIntArm.Equals(TranslationTextArm())
    assert runtimeUninitialized.Equals(new Union<int, string>(0)) == translationUninitialized.Equals(new NSharpLang.RuntimeAcceptance.Union<int, string>(0))

    assert runtimeIntArm.Equals(new Union<int, string>(5))
    assert !runtimeIntArm.Equals(new Union<int, string>(6))
    assert !runtimeIntArm.Equals(RuntimeTextArm())
    assert !runtimeUninitialized.Equals(new Union<int, string>(0))
}

test "a NULL payload on a reference arm compares equal to itself, on both types" {
    runtimeNull: Union<string, int> = NullText()
    runtimeOtherNull: Union<string, int> = NullText()
    translationNull: NSharpLang.RuntimeAcceptance.Union<string, int> = NullText()
    translationOtherNull: NSharpLang.RuntimeAcceptance.Union<string, int> = NullText()

    assert runtimeNull.Equals(runtimeOtherNull) == translationNull.Equals(translationOtherNull)
    assert runtimeNull.Equals(runtimeOtherNull)
    assert runtimeNull.Index == translationNull.Index
    assert runtimeNull.Index == 0
}

test "the BOXED comparison answers the same on both types" {
    runtimeBoxed: object = new Union<int, string>(5)
    translationBoxed: object = new NSharpLang.RuntimeAcceptance.Union<int, string>(5)
    runtimeIntArm := RuntimeIntArm()
    translationIntArm := TranslationIntArm()

    assert runtimeIntArm.Equals(runtimeBoxed) == translationIntArm.Equals(translationBoxed)
    assert runtimeIntArm.Equals(runtimeBoxed)

    // A box of the OTHER type is equal to neither, which is the check that would catch a file that
    // had accidentally compared one type with itself.
    assert !runtimeIntArm.Equals(translationBoxed)
    assert !translationIntArm.Equals(runtimeBoxed)
}

test "== and != agree on both types" {
    runtimeIntArm := RuntimeIntArm()
    translationIntArm := TranslationIntArm()

    assert (runtimeIntArm == new Union<int, string>(5)) == (translationIntArm == new NSharpLang.RuntimeAcceptance.Union<int, string>(5))
    assert (runtimeIntArm != RuntimeTextArm()) == (translationIntArm != TranslationTextArm())
    assert runtimeIntArm == new Union<int, string>(5)
    assert runtimeIntArm != RuntimeTextArm()
}

test "GetHashCode agrees value for value, on both types" {
    runtimeUninitialized: Union<int, string> = default
    translationUninitialized: NSharpLang.RuntimeAcceptance.Union<int, string> = default
    runtimeIntArm := RuntimeIntArm()
    translationIntArm := TranslationIntArm()
    runtimeTextArm := RuntimeTextArm()
    translationTextArm := TranslationTextArm()

    assert runtimeIntArm.GetHashCode() == translationIntArm.GetHashCode()
    assert runtimeTextArm.GetHashCode() == translationTextArm.GetHashCode()
    assert runtimeUninitialized.GetHashCode() == translationUninitialized.GetHashCode()

    // And equal values still hash equally within each type.
    assert runtimeIntArm.GetHashCode() == new Union<int, string>(5).GetHashCode()
    assert translationIntArm.GetHashCode() == new NSharpLang.RuntimeAcceptance.Union<int, string>(5).GetHashCode()
}

test "ToString renders the same text, on both types" {
    runtimeUninitialized: Union<int, string> = default
    translationUninitialized: NSharpLang.RuntimeAcceptance.Union<int, string> = default
    runtimeNull: Union<string, int> = NullText()
    translationNull: NSharpLang.RuntimeAcceptance.Union<string, int> = NullText()
    runtimeIntArm := RuntimeIntArm()
    translationIntArm := TranslationIntArm()
    runtimeTextArm := RuntimeTextArm()
    translationTextArm := TranslationTextArm()

    assert runtimeIntArm.ToString() == translationIntArm.ToString()
    assert runtimeTextArm.ToString() == translationTextArm.ToString()
    assert runtimeUninitialized.ToString() == translationUninitialized.ToString()
    assert runtimeNull.ToString() == translationNull.ToString()

    assert runtimeIntArm.ToString() == "5"
    assert runtimeTextArm.ToString() == "five"
    assert runtimeUninitialized.ToString() == ""
    assert runtimeNull.ToString() == ""
}

test "the emitted metadata is the same shape on both types" {
    runtimeType := typeof(Union<int, string>)
    translationType := typeof(NSharpLang.RuntimeAcceptance.Union<int, string>)
    runtimeDefinition := runtimeType.GetGenericTypeDefinition()
    translationDefinition := translationType.GetGenericTypeDefinition()

    assert runtimeType.get_IsValueType() == translationType.get_IsValueType()
    assert runtimeDefinition.get_Name() == translationDefinition.get_Name()
    assert runtimeType.GetConstructors().Length == translationType.GetConstructors().Length

    assert runtimeType.get_IsValueType()
    assert runtimeDefinition.get_Name() == "Union`2"
    assert runtimeType.GetConstructors().Length == 2
}
