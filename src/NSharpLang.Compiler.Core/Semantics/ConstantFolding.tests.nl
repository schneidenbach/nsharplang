namespace NSharpLang.Compiler

func FoldLit(kind: int, spelling: string): ConstantTerm {
    return ConstantTerm.Literal(kind, spelling)
}

func FoldInt(spelling: string): ConstantTerm {
    return ConstantTerm.Literal(1, spelling)
}

func FoldValue(term: ConstantTerm): ConstantValue {
    folded := ConstantFolder.Fold(term)
    assert folded.Value != null, "did not fold: " + folded.Problem
    return folded.Value
}

func AssertFolds(term: ConstantTerm, typeName: string, expected: object) {
    value := FoldValue(term)
    assert value.TypeName == typeName, "folded as " + value.TypeName + ", not " + typeName
    assert value.Value.Equals(expected), "folded to " + (value.Value.ToString() ?? "") + ", not " + (expected.ToString() ?? "")
}

func AssertProblem(term: ConstantTerm, problem: string) {
    folded := ConstantFolder.Fold(term)
    assert folded.Value == null, "should not fold"
    assert folded.Problem == problem, "the problem was: " + folded.Problem
}

test "an integer literal takes the first of int, uint, long and ulong that holds it" {
    AssertFolds(FoldInt("7"), "System.Int32", 7)
    AssertFolds(FoldInt("2147483648"), "System.UInt32", 2147483648u)
    AssertFolds(FoldInt("4294967296"), "System.Int64", 4294967296L)
    AssertFolds(FoldInt("9223372036854775808"), "System.UInt64", 9223372036854775808UL)
    AssertFolds(FoldInt("7L"), "System.Int64", 7L)
    AssertFolds(FoldInt("7u"), "System.UInt32", 7u)
    AssertFolds(FoldInt("7UL"), "System.UInt64", 7UL)
    AssertFolds(FoldInt("0xFF"), "System.Int32", 255)
    assert FoldValue(FoldInt("7")).IsAdoptableLiteral
    assert !FoldValue(FoldInt("7L")).IsAdoptableLiteral
}

test "the two literals that exist only negated stay in the signed type" {
    AssertFolds(ConstantTerm.Unary("-", FoldInt("2147483648")), "System.Int32", -2147483648)
    AssertFolds(ConstantTerm.Unary("-", FoldInt("9223372036854775808")), "System.Int64", -9223372036854775807L - 1L)
    AssertFolds(ConstantTerm.Unary("-", FoldInt("9223372036854775808L")), "System.Int64", -9223372036854775807L - 1L)
    assert FoldValue(ConstantTerm.Unary("-", FoldInt("5"))).IsAdoptableLiteral
}

test "floating, decimal, character, string and bool literals keep their own types" {
    AssertFolds(FoldLit(2, "2.5"), "System.Double", 2.5)
    AssertFolds(FoldLit(2, "1.5f"), "System.Single", 1.5f)
    AssertFolds(FoldLit(1, "3d"), "System.Double", 3.0)
    AssertFolds(FoldLit(2, "1.25m"), "System.Decimal", 1.25m)
    AssertFolds(FoldLit(1, "5m"), "System.Decimal", 5m)
    AssertFolds(FoldLit(3, "'z'"), "System.Char", 'z')
    AssertFolds(FoldLit(4, "\"a\\tb\""), "System.String", "a\tb")
    AssertFolds(FoldLit(44, "true"), "System.Boolean", true)
}

test "integer arithmetic is checked in the promoted type" {
    AssertFolds(ConstantTerm.Binary("*", FoldInt("2"), FoldInt("3")), "System.Int32", 6)
    AssertFolds(ConstantTerm.Binary("-", FoldInt("2"), FoldInt("3")), "System.Int32", -1)
    AssertFolds(ConstantTerm.Binary("/", ConstantTerm.Unary("-", FoldInt("7")), FoldInt("2")), "System.Int32", -3)
    AssertFolds(ConstantTerm.Binary("%", ConstantTerm.Unary("-", FoldInt("7")), FoldInt("2")), "System.Int32", -1)
    AssertFolds(ConstantTerm.Binary("+", FoldInt("2147483647"), FoldInt("1L")), "System.Int64", 2147483648L)
    AssertFolds(ConstantTerm.Binary("+", FoldLit(3, "'a'"), FoldInt("1")), "System.Int32", 98)
    AssertProblem(ConstantTerm.Binary("+", FoldInt("2147483647"), FoldInt("1")), "adding them overflows 'int'")
    AssertProblem(ConstantTerm.Binary("*", FoldInt("9223372036854775807L"), FoldInt("9223372036854775807L")), "multiplying them overflows 'long'")
    AssertProblem(ConstantTerm.Binary("/", FoldInt("7"), FoldInt("0")), "it divides by zero")
    AssertProblem(ConstantTerm.Binary("/", ConstantTerm.Unary("-", FoldInt("2147483648")), ConstantTerm.Unary("-", FoldInt("1"))), "dividing them overflows 'int'")
    assert ConstantFolder.Fold(ConstantTerm.Binary("+", FoldInt("2147483647"), FoldInt("1"))).Hint != null
}

test "a uint beside a negative int widens to long, and a ulong beside one has no operator" {
    AssertFolds(ConstantTerm.Binary("+", FoldInt("5u"), FoldInt("1")), "System.UInt32", 6u)
    AssertFolds(ConstantTerm.Binary("+", FoldInt("5u"), ConstantTerm.Unary("-", FoldInt("1"))), "System.Int64", 4L)
    AssertFolds(ConstantTerm.Binary("+", FoldInt("5UL"), FoldInt("1")), "System.UInt64", 6UL)
    AssertProblem(ConstantTerm.Binary("+", FoldInt("5UL"), ConstantTerm.Unary("-", FoldInt("1"))), "'+' cannot be applied to constants of type 'ulong' and 'int'")
    AssertFolds(ConstantTerm.Unary("-", FoldInt("1u")), "System.Int64", -1L)
    AssertProblem(ConstantTerm.Unary("-", FoldInt("1UL")), "'-' cannot be applied to a constant 'ulong'")
}

test "shifts take the left operand's type and mask the count" {
    AssertFolds(ConstantTerm.Binary("<<", FoldInt("1L"), FoldInt("40")), "System.Int64", 1099511627776L)
    AssertFolds(ConstantTerm.Binary("<<", FoldInt("1"), FoldInt("33")), "System.Int32", 2)
    AssertFolds(ConstantTerm.Binary(">>", ConstantTerm.Unary("-", FoldInt("8")), FoldInt("1")), "System.Int32", -4)
    AssertFolds(ConstantTerm.Binary("<<", FoldInt("1"), FoldInt("31")), "System.Int32", -2147483648)
    AssertProblem(ConstantTerm.Binary("<<", FoldInt("1"), FoldInt("2L")), "'<<' cannot be applied to constants of type 'int' and 'long'")
}

test "bitwise operators, complement and comparisons fold" {
    AssertFolds(ConstantTerm.Binary("|", FoldInt("0xF0"), FoldInt("0x0F")), "System.Int32", 255)
    AssertFolds(ConstantTerm.Binary("^", FoldInt("0xFFu"), FoldInt("0x0Fu")), "System.UInt32", 240u)
    AssertFolds(ConstantTerm.Unary("~", FoldInt("0")), "System.Int32", -1)
    AssertFolds(ConstantTerm.Unary("~", FoldInt("0u")), "System.UInt32", 4294967295u)
    AssertFolds(ConstantTerm.Binary("<", FoldInt("1"), FoldLit(2, "1.5")), "System.Boolean", true)
    AssertFolds(ConstantTerm.Binary("&&", FoldLit(44, "true"), ConstantTerm.Unary("!", FoldLit(45, "false"))), "System.Boolean", true)
}

test "floating and decimal arithmetic fold in their own types" {
    AssertFolds(ConstantTerm.Binary("/", FoldLit(2, "1.0"), FoldInt("4")), "System.Double", 0.25)
    AssertFolds(ConstantTerm.Binary("*", FoldLit(2, "1.5f"), FoldInt("2")), "System.Single", 3.0f)
    AssertFolds(ConstantTerm.Binary("*", FoldLit(1, "10m"), FoldLit(2, "1.5m")), "System.Decimal", 15.0m)
    AssertProblem(ConstantTerm.Binary("+", FoldLit(2, "1.5m"), FoldLit(2, "1.5")), "'+' cannot be applied to constants of type 'decimal' and 'double'")
    AssertProblem(ConstantTerm.Binary("/", FoldLit(2, "1.5m"), FoldInt("0")), "it divides by zero")
}

test "strings concatenate and nothing else does" {
    AssertFolds(ConstantTerm.Binary("+", FoldLit(4, "\"a\""), FoldLit(4, "\"b\"")), "System.String", "ab")
    AssertProblem(ConstantTerm.Binary("+", FoldLit(4, "\"a\""), FoldInt("1")), "'+' cannot be applied to constants of type 'string' and 'int'")
}

test "an enum combines bitwise with members of its own enum, and with nothing else" {
    a := ConstantTerm.EnumMember("Options", 1)
    c := ConstantTerm.EnumMember("Options", 4)
    combined := FoldValue(ConstantTerm.Binary("|", a, c))
    assert combined.EnumIdentity == "Options"
    assert combined.Value.Equals(5)
    masked := FoldValue(ConstantTerm.Binary("&", ConstantTerm.Unary("~", a), c))
    assert masked.Value.Equals(4)
    AssertProblem(ConstantTerm.Binary("+", a, c), "'+' cannot be applied to constants of type 'Options' and 'Options'")
    AssertProblem(ConstantTerm.Binary("|", a, FoldInt("2")), "'|' cannot be applied to constants of type 'Options' and 'int'")
    AssertProblem(ConstantTerm.Binary("|", a, ConstantTerm.EnumMember("Mode", 2)), "'|' cannot be applied to constants of type 'Options' and 'Mode'")
}

test "a literal the compiler cannot read is a problem, not a value" {
    AssertProblem(FoldInt("12abc"), "'12abc' is not a literal the compiler can read")
}
