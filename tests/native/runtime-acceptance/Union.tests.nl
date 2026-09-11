namespace NSharpLang.RuntimeAcceptance

import System
import System.Collections.Generic
import System.Reflection

// `Union.nl` IS THE N# TRANSLATION OF `src/NSharpLang.Runtime/Union.cs`, AND THIS IS WHAT IT DOES.
// The same assertions are made against the C# type in `UnionParity.tests.nl`, which reaches it by
// importing `NSharpLang.Runtime` from a namespace that does not declare a `Union` of its own — the
// only spelling that resolves, since a source declaration is always the nearer one and a qualified
// `new NSharpLang.Runtime.Union<int, string>(5)` does not compile yet (website/docs/types.md,
// "Current limits").
func IntArm(): Union<int, string> {
    return new Union<int, string>(5)
}

func TextArm(): Union<int, string> {
    return new Union<int, string>("five")
}

// A NULL PAYLOAD that the type system still sees as the arm's type: a default array element is a
// `string` value that is null at runtime, which is the case `TryGet`'s second arm exists for.
func NullTextArm(): Union<string, int> {
    slots := new string[](1)
    return new Union<string, int>(slots[0])
}

// ---- CONSTRUCTION AND THE ARM ------------------------------------------------------------------

test "each constructor records its own arm" {
    assert IntArm().Index == 0
    assert TextArm().Index == 1
}

test "the implicit conversions are the constructors" {
    fromInt: Union<int, string> = 5
    fromText: Union<int, string> = "five"

    assert fromInt.Index == 0
    assert fromText.Index == 1
    assert fromInt == IntArm()
    assert fromText == TextArm()
}

test "an uninitialized union has no arm" {
    uninitialized: Union<int, string> = default
    assert uninitialized.Index == -1
}

// ---- THE PAYLOAD -------------------------------------------------------------------------------

test "Value hands back the payload of whichever arm is live" {
    assert IntArm().Value != null
    assert TextArm().Value != null
    intPayload := IntArm().Value
    textPayload := TextArm().Value
    if intPayload != null {
        assert intPayload.ToString() == "5"
    }

    if textPayload != null {
        assert textPayload.ToString() == "five"
    }
}

test "Value on an uninitialized union throws the exact message" {
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

// ---- THE TYPE QUESTIONS ------------------------------------------------------------------------

test "Is answers for the live arm's type and its bases" {
    intArm := IntArm()
    textArm := TextArm()

    assert intArm.Is<int>()
    assert !intArm.Is<string>()
    assert intArm.Is<object>()

    assert textArm.Is<string>()
    assert !textArm.Is<int>()
    assert textArm.Is<object>()
}

test "Is on an uninitialized union throws the exact message" {
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

test "TryGet writes only when the arm matches" {
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

test "TryGet answers true for a null payload on a reference arm" {
    // `_value is T typed` is false for a null, so the C# type has a second arm for exactly this:
    // the arm matches, the payload is null, and null IS a value of that type.
    nullArm := NullTextArm()
    text := "seed"
    assert nullArm.TryGet<string>(out text)
    assert text == null
}

test "As hands back the payload when the arm matches" {
    // The receiver is bound to a local first: a generic method called directly on a CALL RESULT
    // (`IntArm().As<int>()`) does not resolve yet — recorded in website/docs/types.md's
    // "Current limits" — while the same call on a named value does.
    intArm := IntArm()
    textArm := TextArm()

    assert intArm.As<int>() == 5
    assert textArm.As<string>() == "five"
    assert intArm.As<object>() != null
}

test "As throws the exact cast message when the arm does not match" {
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

test "As names the index of the arm that IS live" {
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

// ---- MATCH AND SWITCH --------------------------------------------------------------------------

func IntText(value: int): string {
    return "int:" + value.ToString()
}

func TextText(value: string): string {
    return "text:" + (value ?? "")
}

test "Match runs the live arm" {
    intArm := IntArm()
    textArm := TextArm()

    assert intArm.Match<string>(v => IntText(v), t => TextText(t)) == "int:5"
    assert textArm.Match<string>(v => IntText(v), t => TextText(t)) == "text:five"
}

test "Match on an uninitialized union throws the exact message" {
    uninitialized: Union<int, string> = default
    message := ""
    try {
        message = uninitialized.Match<string>(v => IntText(v), t => TextText(t))
    } catch ex: InvalidOperationException {
        message = ex.Message
    }

    assert message == "The union value was not initialized with either arm."
}

test "Match rejects a null arm" {
    arms := new Func<int, string>[](1)
    intArm := IntArm()

    assert throws ArgumentNullException {
        reached := intArm.Match<string>(arms[0], t => TextText(t))
        print reached
    }
}

test "Switch runs the live arm and nothing else" {
    seen := new string[](1)
    IntArm().Switch(v => SeenSet(seen, "int:" + v.ToString()), t => SeenSet(seen, "text:" + (t ?? "")))
    assert seen[0] == "int:5"

    IntArm().Switch(v => SeenSet(seen, "again:" + v.ToString()), t => SeenSet(seen, "no"))
    assert seen[0] == "again:5"

    TextArm().Switch(v => SeenSet(seen, "no"), t => SeenSet(seen, "text:" + (t ?? "")))
    assert seen[0] == "text:five"
}

func SeenSet(slots: string[], value: string) {
    slots[0] = value
}

test "Switch on an uninitialized union throws the exact message" {
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

test "Switch rejects a null arm" {
    arms := new Action<int>[](1)
    seen := new string[](1)
    intArm := IntArm()

    assert throws ArgumentNullException {
        intArm.Switch(arms[0], t => SeenSet(seen, "no"))
    }
}

// ---- EQUALITY, HASHING AND TEXT ----------------------------------------------------------------

test "two unions are equal when the arm and the payload are" {
    assert IntArm().Equals(new Union<int, string>(5))
    assert !IntArm().Equals(new Union<int, string>(6))
    assert !IntArm().Equals(TextArm())
    assert TextArm().Equals(new Union<int, string>("five"))
    assert !TextArm().Equals(new Union<int, string>("six"))
}

test "two uninitialized unions are equal" {
    left: Union<int, string> = default
    right: Union<int, string> = default
    assert left.Equals(right)
    assert !left.Equals(IntArm())
}

test "the object overload answers only for the same constructed type" {
    boxedSame: object = new Union<int, string>(5)
    boxedOther: object = new Union<string, int>("5")

    assert IntArm().Equals(boxedSame)
    assert !IntArm().Equals(boxedOther)
    // `Equals(5)` and `Equals(null)` are written through `object` locals: a bare `5` is convertible
    // BOTH to `object` and, through this type's own implicit operator, to `Union<int, string>`, so the
    // call is ambiguous — which is the union's own doing, not the overloads'.
    nothing: object? = null
    boxedInt: object = 5
    assert !IntArm().Equals(nothing)
    assert !IntArm().Equals(boxedInt)
}

test "the equality operators are the Equals they delegate to" {
    assert IntArm() == new Union<int, string>(5)
    assert !(IntArm() != new Union<int, string>(5))
    assert IntArm() != new Union<int, string>(6)
    assert IntArm() != TextArm()
}

test "equal unions hash equally, and the arm is part of the hash" {
    assert IntArm().GetHashCode() == new Union<int, string>(5).GetHashCode()
    assert TextArm().GetHashCode() == new Union<int, string>("five").GetHashCode()
}

test "ToString is the payload's text, and empty when there is no arm" {
    uninitialized: Union<int, string> = default
    assert IntArm().ToString() == "5"
    assert TextArm().ToString() == "five"
    assert uninitialized.ToString() == ""
    assert NullTextArm().ToString() == ""
}

// ---- THE EMITTED METADATA ----------------------------------------------------------------------

func UnionCarriesAttributeNamed(candidate: Type, attributeName: string): bool {
    for attribute in candidate.GetCustomAttributes(false) {
        if attribute.GetType().Name == attributeName {
            return true
        }
    }

    return false
}

func UnionImplementsInterface(candidate: Type, wanted: Type): bool {
    for implemented in candidate.GetInterfaces() {
        if implemented == wanted {
            return true
        }
    }

    return false
}

// INTERFACE DISPATCH THROUGH THE BASE LIST, asked the way the BCL asks it: `EqualityComparer<T>` picks
// `IEquatable<T>`'s implementation when the type has one, so a comparer over the constructed
// translation reaches the declared `Equals(Union<T0, T1>)` rather than the object overload. The
// comparer is used in place rather than bound to a name — a LOCAL typed by an external generic over a
// complete source type still declines at `emit.local.unsupported-type`, which is a separate slice.
test "the declared IEquatable implementation is what BCL dispatch reaches" {
    intArm := IntArm()
    sameIntArm := new Union<int, string>(5)
    otherIntArm := new Union<int, string>(6)
    uninitialized: Union<int, string> = default
    alsoUninitialized: Union<int, string> = default

    assert EqualityComparer<Union<int, string>>.Default.Equals(intArm, sameIntArm)
    assert !EqualityComparer<Union<int, string>>.Default.Equals(intArm, otherIntArm)
    assert !EqualityComparer<Union<int, string>>.Default.Equals(intArm, TextArm())
    assert EqualityComparer<Union<int, string>>.Default.Equals(uninitialized, alsoUninitialized)
    assert EqualityComparer<Union<int, string>>.Default.GetHashCode(intArm) == intArm.GetHashCode()
}

test "the union is a readonly value type named for its arity" {
    assert typeof(Union<int, string>).get_IsValueType()
    assert typeof(Union<int, string>).GetGenericTypeDefinition().get_Name() == "Union`2"
    assert UnionCarriesAttributeNamed(typeof(Union<int, string>).GetGenericTypeDefinition(), "IsReadOnlyAttribute")
    assert UnionImplementsInterface(typeof(Union<int, string>), typeof(IEquatable<Union<int, string>>))
}

test "both constructors are public and take one argument each" {
    constructors := typeof(Union<int, string>).GetConstructors()
    assert constructors.Length == 2
    assert constructors[0].GetParameters().Length == 1
    assert constructors[1].GetParameters().Length == 1
}

test "the implicit conversions reach CLR metadata as op_Implicit" {
    definition := typeof(Union<int, string>).GetGenericTypeDefinition()
    conversions := 0
    for method in definition.GetMethods(BindingFlags.Public | BindingFlags.Static) {
        if method.get_Name() == "op_Implicit" {
            conversions = conversions + 1
            assert method.GetParameters().Length == 1
        }
    }

    assert conversions == 2
}

test "the generic members are real CLR generic methods" {
    isMethod := typeof(Union<int, string>).GetMethod("Is")
    tryGetMethod := typeof(Union<int, string>).GetMethod("TryGet")
    asMethod := typeof(Union<int, string>).GetMethod("As")

    assert isMethod != null
    assert tryGetMethod != null
    assert asMethod != null
    if isMethod != null && tryGetMethod != null && asMethod != null {
        assert isMethod.GetGenericArguments().Length == 1
        assert tryGetMethod.GetGenericArguments().Length == 1
        assert asMethod.GetGenericArguments().Length == 1
        assert tryGetMethod.GetParameters()[0].get_ParameterType().get_IsByRef()
        assert tryGetMethod.GetParameters()[0].get_IsOut()
    }
}
