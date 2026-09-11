namespace NSharpLang.RuntimeAcceptance.Parity

import System
import NSharpLang.Runtime

// THE C# SIDE OF THE UNION TRANSLATION. Every assertion here has a twin in `Union.tests.nl`, made on
// the same inputs against the N# translation; together they are the claim that the two types behave
// identically. The file lives in its own namespace and imports `NSharpLang.Runtime` because that is
// the only spelling that reaches the C# `Union`: a source declaration is always the nearer one, so
// inside `NSharpLang.RuntimeAcceptance` the bare name is the translation, and the qualified
// `new NSharpLang.Runtime.Union<int, string>(5)` does not compile yet (website/docs/types.md,
// "Current limits").
func IntArm(): Union<int, string> {
    return new Union<int, string>(5)
}

func TextArm(): Union<int, string> {
    return new Union<int, string>("five")
}

func NullTextArm(): Union<string, int> {
    slots := new string[](1)
    return new Union<string, int>(slots[0])
}

func IntText(value: int): string {
    return "int:" + value.ToString()
}

func TextText(value: string): string {
    return "text:" + (value ?? "")
}

func SeenSet(slots: string[], value: string) {
    slots[0] = value
}

test "C# union: each constructor records its own arm" {
    assert IntArm().Index == 0
    assert TextArm().Index == 1
}

test "C# union: the implicit conversions are the constructors" {
    fromInt: Union<int, string> = 5
    fromText: Union<int, string> = "five"

    assert fromInt.Index == 0
    assert fromText.Index == 1
    assert fromInt == IntArm()
    assert fromText == TextArm()
}

test "C# union: an uninitialized union has no arm" {
    uninitialized: Union<int, string> = default
    assert uninitialized.Index == -1
}

test "C# union: Value hands back the payload of whichever arm is live" {
    intPayload := IntArm().Value
    textPayload := TextArm().Value
    assert intPayload != null
    assert textPayload != null
    if intPayload != null {
        assert intPayload.ToString() == "5"
    }

    if textPayload != null {
        assert textPayload.ToString() == "five"
    }
}

test "C# union: Value on an uninitialized union throws the exact message" {
    uninitialized: Union<int, string> = default
    message := ""
    try {
        reached := uninitialized.Value
        message = "no throw"
        print reached
    } catch ex: InvalidOperationException {
        message = ex.Message
    }

    assert message == "The union value was not initialized with either arm."
}

test "C# union: Is answers for the live arm's type and its bases" {
    intArm := IntArm()
    textArm := TextArm()

    assert intArm.Is<int>()
    assert !intArm.Is<string>()
    assert intArm.Is<object>()
    assert textArm.Is<string>()
    assert !textArm.Is<int>()
    assert textArm.Is<object>()
}

test "C# union: Is on an uninitialized union throws the exact message" {
    uninitialized: Union<int, string> = default
    message := ""
    try {
        reached := uninitialized.Is<int>()
        message = "no throw: " + reached.ToString()
    } catch ex: InvalidOperationException {
        message = ex.Message
    }

    assert message == "The union value was not initialized with either arm."
}

test "C# union: TryGet writes only when the arm matches" {
    intArm := IntArm()
    textArm := TextArm()

    value := -1
    assert intArm.TryGet<int>(out value)
    assert value == 5

    missed := -1
    assert !textArm.TryGet<int>(out missed)
    assert missed == 0

    text := "seed"
    assert textArm.TryGet<string>(out text)
    assert text == "five"

    missedText := "seed"
    assert !intArm.TryGet<string>(out missedText)
    assert missedText == null
}

test "C# union: TryGet answers true for a null payload on a reference arm" {
    nullArm := NullTextArm()
    text := "seed"
    assert nullArm.TryGet<string>(out text)
    assert text == null
}

test "C# union: As hands back the payload when the arm matches" {
    intArm := IntArm()
    textArm := TextArm()

    assert intArm.As<int>() == 5
    assert textArm.As<string>() == "five"
    assert intArm.As<object>() != null
}

test "C# union: As throws the exact cast message when the arm does not match" {
    intArm := IntArm()
    message := ""
    try {
        reached := intArm.As<string>()
        message = "no throw: " + (reached ?? "")
    } catch ex: InvalidCastException {
        message = ex.Message
    }

    assert message == "Union value at index 0 cannot be read as 'System.String'."
}

test "C# union: As names the index of the arm that IS live" {
    textArm := TextArm()
    message := ""
    try {
        reached := textArm.As<int>()
        message = "no throw: " + reached.ToString()
    } catch ex: InvalidCastException {
        message = ex.Message
    }

    assert message == "Union value at index 1 cannot be read as 'System.Int32'."
}

test "C# union: Match runs the live arm" {
    intArm := IntArm()
    textArm := TextArm()

    assert intArm.Match<string>(v => IntText(v), t => TextText(t)) == "int:5"
    assert textArm.Match<string>(v => IntText(v), t => TextText(t)) == "text:five"
}

test "C# union: Match on an uninitialized union throws the exact message" {
    uninitialized: Union<int, string> = default
    message := ""
    try {
        message = uninitialized.Match<string>(v => IntText(v), t => TextText(t))
    } catch ex: InvalidOperationException {
        message = ex.Message
    }

    assert message == "The union value was not initialized with either arm."
}

test "C# union: Match rejects a null arm" {
    arms := new Func<int, string>[](1)
    intArm := IntArm()

    assert throws ArgumentNullException {
        reached := intArm.Match<string>(arms[0], t => TextText(t))
        print reached
    }
}

test "C# union: Switch runs the live arm and nothing else" {
    seen := new string[](1)
    intArm := IntArm()
    textArm := TextArm()

    intArm.Switch(v => SeenSet(seen, "int:" + v.ToString()), t => SeenSet(seen, "text:" + (t ?? "")))
    assert seen[0] == "int:5"

    textArm.Switch(v => SeenSet(seen, "no"), t => SeenSet(seen, "text:" + (t ?? "")))
    assert seen[0] == "text:five"
}

test "C# union: Switch on an uninitialized union throws the exact message" {
    uninitialized: Union<int, string> = default
    seen := new string[](1)
    message := ""
    try {
        uninitialized.Switch(v => SeenSet(seen, "no"), t => SeenSet(seen, "no"))
        message = "no throw"
    } catch ex: InvalidOperationException {
        message = ex.Message
    }

    assert message == "The union value was not initialized with either arm."
}

test "C# union: Switch rejects a null arm" {
    arms := new Action<int>[](1)
    seen := new string[](1)
    intArm := IntArm()

    assert throws ArgumentNullException {
        intArm.Switch(arms[0], t => SeenSet(seen, "no"))
    }
}

test "C# union: equality, hashing and text" {
    uninitialized: Union<int, string> = default
    left: Union<int, string> = default
    boxedSame: object = new Union<int, string>(5)

    assert IntArm().Equals(new Union<int, string>(5))
    assert !IntArm().Equals(new Union<int, string>(6))
    assert !IntArm().Equals(TextArm())
    assert left.Equals(uninitialized)
    assert IntArm().Equals(boxedSame)
    assert IntArm() == new Union<int, string>(5)
    assert IntArm() != TextArm()
    assert IntArm().GetHashCode() == new Union<int, string>(5).GetHashCode()
    assert IntArm().ToString() == "5"
    assert TextArm().ToString() == "five"
    assert uninitialized.ToString() == ""
    assert NullTextArm().ToString() == ""
}

test "C# union: the emitted metadata is the shape the translation matches" {
    assert typeof(Union<int, string>).get_IsValueType()
    assert typeof(Union<int, string>).GetGenericTypeDefinition().get_Name() == "Union`2"
    assert typeof(Union<int, string>).GetConstructors().Length == 2
}
