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
// `Is<T>()`, `TryGet<T>(out value)`, `As<T>()`, `Match<TResult>(...)` and `Switch(...)` had no row
// here until generic methods declared by an EXTERNAL type could be called: `u.Is<int>()` on the
// runtime union used to decline with "generic call 'u.Is' with 0 argument(s) could not be resolved".
// They are compared against the C# type below like everything else.
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

// ─── THE GENERIC INSTANCE METHODS ─────────────────────────────────────────────────────────────────

test "Is<T> answers the same arm question on both types" {
    runtimeIntArm := RuntimeIntArm()
    translationIntArm := TranslationIntArm()
    runtimeTextArm := RuntimeTextArm()
    translationTextArm := TranslationTextArm()

    assert runtimeIntArm.Is<int>() == translationIntArm.Is<int>()
    assert runtimeIntArm.Is<string>() == translationIntArm.Is<string>()
    assert runtimeTextArm.Is<string>() == translationTextArm.Is<string>()
    assert runtimeTextArm.Is<int>() == translationTextArm.Is<int>()

    assert runtimeIntArm.Is<int>()
    assert !runtimeIntArm.Is<string>()
    assert runtimeTextArm.Is<string>()
    assert !runtimeTextArm.Is<int>()

    // A BASE of the live arm's type is still the arm's type, on both.
    assert runtimeIntArm.Is<object>() == translationIntArm.Is<object>()
    assert runtimeIntArm.Is<object>()
}

// `Is<T>` asks the ACTIVE ARM a question, and an uninitialized union has no active arm — so it
// throws rather than answering false, on both types.
test "Is<T> on an UNINITIALIZED union throws the same message, on both types" {
    runtimeUninitialized: Union<int, string> = default
    translationUninitialized: NSharpLang.RuntimeAcceptance.Union<int, string> = default

    runtimeMessage := "no throw"
    try {
        reached := runtimeUninitialized.Is<int>()
        print reached
    } catch ex: InvalidOperationException {
        runtimeMessage = ex.Message
    }

    translationMessage := "no throw"
    try {
        reached := translationUninitialized.Is<int>()
        print reached
    } catch ex: InvalidOperationException {
        translationMessage = ex.Message
    }

    assert runtimeMessage == translationMessage
    assert runtimeMessage == "The union value was not initialized with either arm."
}

test "TryGet<T> answers the same and writes the same, on both types" {
    runtimeIntArm := RuntimeIntArm()
    translationIntArm := TranslationIntArm()
    runtimeTextArm := RuntimeTextArm()
    translationTextArm := TranslationTextArm()

    runtimeValue := -1
    translationValue := -1
    assert runtimeIntArm.TryGet<int>(out runtimeValue) == translationIntArm.TryGet<int>(out translationValue)
    assert runtimeValue == translationValue
    assert runtimeValue == 5

    runtimeMiss := -1
    translationMiss := -1
    assert runtimeTextArm.TryGet<int>(out runtimeMiss) == translationTextArm.TryGet<int>(out translationMiss)
    assert runtimeMiss == translationMiss
    assert runtimeMiss == 0

    runtimeText := "seed"
    translationText := "seed"
    assert runtimeTextArm.TryGet<string>(out runtimeText) == translationTextArm.TryGet<string>(out translationText)
    assert runtimeText == translationText
    assert runtimeText == "five"
}

test "As<T> hands back the same payload on both types" {
    runtimeIntArm := RuntimeIntArm()
    translationIntArm := TranslationIntArm()
    runtimeTextArm := RuntimeTextArm()
    translationTextArm := TranslationTextArm()

    assert runtimeIntArm.As<int>() == translationIntArm.As<int>()
    assert runtimeTextArm.As<string>() == translationTextArm.As<string>()
    assert runtimeIntArm.As<int>() == 5
    assert runtimeTextArm.As<string>() == "five"
}

test "As<T> on the WRONG arm throws the SAME exception with the SAME message, on both types" {
    runtimeIntArm := RuntimeIntArm()
    translationIntArm := TranslationIntArm()

    runtimeMessage := "no throw"
    try {
        reached := runtimeIntArm.As<string>()
        print reached
    } catch ex: InvalidCastException {
        runtimeMessage = ex.Message
    }

    translationMessage := "no throw"
    try {
        reached := translationIntArm.As<string>()
        print reached
    } catch ex: InvalidCastException {
        translationMessage = ex.Message
    }

    assert runtimeMessage == translationMessage
    assert runtimeMessage == "Union value at index 0 cannot be read as 'System.String'."
}

test "Match<TResult> runs the live arm and returns the same text, on both types" {
    runtimeIntArm := RuntimeIntArm()
    translationIntArm := TranslationIntArm()
    runtimeTextArm := RuntimeTextArm()
    translationTextArm := TranslationTextArm()

    runtimeFromInt := runtimeIntArm.Match<string>(a => a.ToString(), b => b)
    translationFromInt := translationIntArm.Match<string>(a => a.ToString(), b => b)
    runtimeFromText := runtimeTextArm.Match<string>(a => a.ToString(), b => b)
    translationFromText := translationTextArm.Match<string>(a => a.ToString(), b => b)

    assert runtimeFromInt == translationFromInt
    assert runtimeFromText == translationFromText
    assert runtimeFromInt == "5"
    assert runtimeFromText == "five"
}

test "Match<TResult> on an UNINITIALIZED union throws the same message, on both types" {
    runtimeUninitialized: Union<int, string> = default
    translationUninitialized: NSharpLang.RuntimeAcceptance.Union<int, string> = default

    runtimeMessage := "no throw"
    try {
        reached := runtimeUninitialized.Match<string>(a => a.ToString(), b => b)
        print reached
    } catch ex: InvalidOperationException {
        runtimeMessage = ex.Message
    }

    translationMessage := "no throw"
    try {
        reached := translationUninitialized.Match<string>(a => a.ToString(), b => b)
        print reached
    } catch ex: InvalidOperationException {
        translationMessage = ex.Message
    }

    assert runtimeMessage == translationMessage
    assert runtimeMessage == "The union value was not initialized with either arm."
}

// `Switch` is NOT generic — it takes two `Action<T>` arms — so it is the row that proves the lambda
// side of this on its own: the arms are written as lambdas and bound against the CLOSED delegate
// each parameter denotes.
test "Switch runs the live arm on both types" {
    runtimeIntArm := RuntimeIntArm()
    translationIntArm := TranslationIntArm()
    runtimeTextArm := RuntimeTextArm()
    translationTextArm := TranslationTextArm()

    runtimeSeen := new System.Text.StringBuilder()
    translationSeen := new System.Text.StringBuilder()

    runtimeIntArm.Switch(a => {
        runtimeSeen.Append("int:" + a.ToString())
    }, b => {
        runtimeSeen.Append("text:" + b)
    })
    translationIntArm.Switch(a => {
        translationSeen.Append("int:" + a.ToString())
    }, b => {
        translationSeen.Append("text:" + b)
    })
    runtimeTextArm.Switch(a => {
        runtimeSeen.Append("int:" + a.ToString())
    }, b => {
        runtimeSeen.Append("text:" + b)
    })
    translationTextArm.Switch(a => {
        translationSeen.Append("int:" + a.ToString())
    }, b => {
        translationSeen.Append("text:" + b)
    })

    assert runtimeSeen.ToString() == translationSeen.ToString()
    assert runtimeSeen.ToString() == "int:5text:five"
}

test "Switch on an UNINITIALIZED union throws the same message, on both types" {
    runtimeUninitialized: Union<int, string> = default
    translationUninitialized: NSharpLang.RuntimeAcceptance.Union<int, string> = default

    runtimeMessage := "no throw"
    try {
        runtimeUninitialized.Switch(a => {
            print a
        }, b => {
            print b
        })
    } catch ex: InvalidOperationException {
        runtimeMessage = ex.Message
    }

    translationMessage := "no throw"
    try {
        translationUninitialized.Switch(a => {
            print a
        }, b => {
            print b
        })
    } catch ex: InvalidOperationException {
        translationMessage = ex.Message
    }

    assert runtimeMessage == translationMessage
    assert runtimeMessage == "The union value was not initialized with either arm."
}
