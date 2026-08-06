namespace NSharpLang.CharClassification.Tests

// char.IsLower joined the columnar System.Char catalog for the naming-convention walk
// (NL903 decides visibility by the first character's case). Every approximation the wall
// analysis tried changes the answer on some Unicode category: `IsLetter && !IsUpper`
// accepts title-case letters, `ToUpperInvariant(c) != c` refuses the eszett, an ASCII
// range refuses accented lowercase. These contracts pin the real predicate's answers on
// exactly those discriminating categories, through the packaged pipeline.

public static func ClassifyLower(c: char): bool {
    return char.IsLower(c)
}

test "an ASCII lowercase letter is lower" {
    assert ClassifyLower('a')
}

test "an ASCII uppercase letter is not lower" {
    assert !ClassifyLower('A')
}

test "an accented lowercase letter is lower" {
    assert ClassifyLower('é')
}

test "the eszett is lower even though uppercasing leaves it unchanged" {
    assert ClassifyLower('ß')
}

test "a title-case letter is not lower" {
    assert !ClassifyLower('ǅ')
}

test "a digit is not lower" {
    assert !ClassifyLower('7')
}

test "the predicate agrees with the published siblings on the boundary" {
    assert char.IsLetter('ß')
    assert !char.IsUpper('ß')
    assert char.IsLower('ß')
}
