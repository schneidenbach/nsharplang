namespace NSharpLang.CensusLiftedOperators.Tests

test "the three-valued `&` table: an absent operand does not win over a false one" {
    // row order: (true, false, null) x (true, false, null)
    assert AndCode(true, true) == 1
    assert AndCode(true, false) == 0
    assert AndCode(true, null) == -1
    assert AndCode(false, true) == 0
    assert AndCode(false, false) == 0
    assert AndCode(false, null) == 0
    assert AndCode(null, true) == -1
    assert AndCode(null, false) == 0
    assert AndCode(null, null) == -1
}

test "the three-valued `|` table: an absent operand does not win over a true one" {
    assert OrCode(true, true) == 1
    assert OrCode(true, false) == 1
    assert OrCode(true, null) == 1
    assert OrCode(false, true) == 1
    assert OrCode(false, false) == 0
    assert OrCode(false, null) == -1
    assert OrCode(null, true) == 1
    assert OrCode(null, false) == -1
    assert OrCode(null, null) == -1
}

test "`^` over booleans is the ORDINARY lift — no value decides it alone" {
    assert XorCode(true, true) == 0
    assert XorCode(true, false) == 1
    assert XorCode(false, true) == 1
    assert XorCode(false, false) == 0
    assert XorCode(true, null) == -1
    assert XorCode(null, false) == -1
    assert XorCode(null, null) == -1
}

test "the three-valued operators read the same way through their `bool?` results" {
    assert AndBooleans(false, null) == false
    assert AndBooleans(true, null) == null
    assert OrBooleans(true, null) == true
    assert OrBooleans(false, null) == null
    assert XorBooleans(true, false) == true
    assert XorBooleans(true, null) == null
}

test "a plain boolean operand joins the three-valued table in either position" {
    assert AndBooleanAndValue(null, false) == false
    assert AndBooleanAndValue(null, true) == null
    assert AndBooleanAndValue(true, true) == true
    assert OrValueAndBoolean(true, null) == true
    assert OrValueAndBoolean(false, null) == null
    assert OrValueAndBoolean(false, true) == true
}
