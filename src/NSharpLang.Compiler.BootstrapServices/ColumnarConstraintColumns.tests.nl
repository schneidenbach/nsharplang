namespace NSharpLang.Compiler


// THE FLAT `where` ROWS FOLDED INTO THE TWO COLUMNS THE EMITTER READS.
//
// Both parsers answer one row per constraint ITEM; the emitter wants the transpose, one entry per TYPE
// PARAMETER. The fold lives here so the host builder does not carry it once per declaration keyword —
// and so it can be crossed without a parser.
func CcOwners(a: string, b: string, c: string): string[] {
    owners := new string[](3)
    owners[0] = a
    owners[1] = b
    owners[2] = c
    return owners
}

func CcCodes(a: int, b: int, c: int): int[] {
    codes := new int[](3)
    codes[0] = a
    codes[1] = b
    codes[2] = c
    return codes
}

func CcNames(a: string, b: string): string[] {
    names := new string[](2)
    names[0] = a
    names[1] = b
    return names
}

test "the three sentinels fold into their own parameter's flag word" {
    // `class Map<K, V> where K: class where V: struct, new()`.
    owners := CcOwners("K", "V", "V")
    codes := CcCodes(-2, -3, -4)
    names := CcNames("K", "V")

    specials := ColumnarConstraintColumns.BuildSpecials(owners, codes, names, 3)
    assert specials.Length == 2
    assert specials[0] == 1
    assert specials[1] == 6
}

test "a row whose owner names no declared parameter is DROPPED, not refused" {
    // The parser does not compare source text, so an owner that matches nothing is a source error the
    // analyzer reports WITH a position. Emitting a constraint against a parameter that does not exist
    // would be the worse answer, and refusing here would lose the diagnostic.
    owners := CcOwners("K", "Q", "V")
    codes := CcCodes(-2, -2, -3)
    names := CcNames("K", "V")

    specials := ColumnarConstraintColumns.BuildSpecials(owners, codes, names, 3)
    assert specials[0] == 1
    assert specials[1] == 2
}

test "type constraints transpose per parameter, and a parameter with none gets an EMPTY array" {
    owners := CcOwners("K", "K", "V")
    codes := CcCodes(0, -2, 0)
    types := CcOwners("IKey", "", "IValue")
    names := CcNames("K", "V")

    constraints := ColumnarConstraintColumns.BuildTypeConstraints(owners, codes, types, names, 3)
    assert constraints.Length == 2
    assert constraints[0].Length == 1
    assert constraints[0][0] == "IKey"
    assert constraints[1].Length == 1
    assert constraints[1][0] == "IValue"

    // The special row contributed nothing to the type columns — the two folds are disjoint.
    specials := ColumnarConstraintColumns.BuildSpecials(owners, codes, names, 3)
    assert specials[0] == 1
    assert specials[1] == 0
}

test "two type constraints on ONE parameter keep their written order" {
    owners := CcOwners("T", "T", "T")
    codes := CcCodes(0, 0, -4)
    types := CcOwners("IFirst", "ISecond", "")
    names := new string[](1)
    names[0] = "T"

    constraints := ColumnarConstraintColumns.BuildTypeConstraints(owners, codes, types, names, 3)
    assert constraints[0].Length == 2
    assert constraints[0][0] == "IFirst"
    assert constraints[0][1] == "ISecond"
}

test "an unconstrained declaration gets the same EMPTY shape a function's does, not a null" {
    specials := ColumnarConstraintColumns.SpecialsOrEmpty(null, 2)
    assert specials.Length == 2
    assert specials[0] == 0

    types := ColumnarConstraintColumns.TypesOrEmpty(null, 2)
    assert types.Length == 2
    assert types[0].Length == 0
    assert types[1].Length == 0

    // A supplied set is passed through untouched.
    supplied := new int[](1)
    supplied[0] = 4
    assert ColumnarConstraintColumns.SpecialsOrEmpty(supplied, 1)[0] == 4
}

test "the trim helper copies exactly the count asked for" {
    // Three C# call sites open-coded this loop, once per declaration keyword.
    texts := CcOwners("A", "B", "C")
    assert ColumnarConstraintColumns.TrimTexts(texts, 2).Length == 2
    assert ColumnarConstraintColumns.TrimTexts(texts, 2)[1] == "B"
    assert ColumnarConstraintColumns.TrimTexts(texts, 0).Length == 0
}
