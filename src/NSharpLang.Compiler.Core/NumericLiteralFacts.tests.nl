namespace NSharpLang.Compiler

import System


// THE CANONICAL CONTRACTS FOR `NumericLiteralFacts`, IN N#.
//
// These replace `tests/NumericLiteralFactsTests.cs` (80 lines, 6 `[Fact]`/`[Theory]` declarations,
// 30 cases). The kernel is the compiler's answer to "what type is this number, and how big is it
// allowed to be" — six N# production owners consult it (`AnalyzerLiteralExpressions`,
// `AnalyzerOperatorExpressions`, `AnalyzerAttributeValidator`, `AnalyzerSyntheticCallValidator`,
// `ColumnarRangeIndexPlanner`, `ColumnarUnaryLiteralPlanner`, `SystemsStackallocPolicy`) and no C#
// owner reaches it at all, so the deleted file was a pure canonical assertion layer.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. The recorded block was "9 `typeof` rows (NL310)
// + `out` params + `ulong` bounds". `NL310` is a TABLE rule and there is no table here; `out`
// parameters are ordinary in this estate; and the `ulong` bounds are written exactly as the deleted
// `[InlineData]` rows wrote them, with the `UL` suffix. That suffix is load-bearing: an UNSUFFIXED
// integer literal always types as `int` and never widens by magnitude, so `2147483648` declines at
// `emit.typed-local.initializer` while `2147483648UL` emits — a standing product defect recorded
// in the closeout ledger, and one this kernel's own source already routes around.
//
// THE SIX THINGS THAT ARE EASY TO GET WRONG:
//
// (1) THE FLOAT SUFFIX IS CASE-INSENSITIVE AND THE DEFAULT IS `double`. `m`/`M` is decimal, `f`/`F`
// is float, everything else — including no suffix at all, and including a `d`/`D` that is matched by
// nothing and simply falls through — is `double`.
//
// (2) THE FAILURE VALUE OF `TryGetIntegerLiteralTypeInfo` IS NOT NULL AND NOT UNKNOWN — IT IS
// `int`. A caller that ignores the `bool` gets a plausible wrong answer rather than a crash, which
// is why the false arm's OUT VALUE is asserted and not merely its result.
//
// (3) THE TWO BOUND TABLES ARE KEYED BY N# TYPE NAME, NOT BY CLR TYPE. They take `"sbyte"`, not
// `typeof(sbyte)` — a different vocabulary from the entry point directly above them in the same
// class, and the reason `"Int32"` and `"System.Int32"` are both misses.
//
// (4) THE TWO BOUND TABLES HAVE DIFFERENT DOMAINS, AND THE DIFFERENCE IS THE WHOLE POINT.
// A negative literal's magnitude is defined only for the four SIGNED types (`-128` fits `sbyte`
// because the magnitude bound is 128, one more than `sbyte.MaxValue`); the unsigned max-value table
// covers eight types including `ulong` and `char`. `uint` is in the second and NOT the first.
//
// (5) `char` AND `ushort` SHARE A ROW. Both bound at 65535, from one arm.
//
// (6) `ParseUnsignedIntegerMagnitude` STRIPS SUFFIXES AND UNDERSCORES AND UNDERSTANDS THREE RADIX
// PREFIXES, AND ITS `Try` WRAPPER SWALLOWS EXACTLY THREE EXCEPTION TYPES. The deleted file touched
// neither, nor `GetIntegerSuffix`. The two parse functions are reached from the consumer side by
// `ColumnarParserKernels.tests.nl` and `ColumnarUnaryLiteralPlanner.tests.nl`; **`GetIntegerSuffix`
// had no assertion layer anywhere**, which is why the suffix vocabulary the lexer depends on is
// stated below in full.

// ---- the float suffix family ----------------------------------------------------------------------

// A `TypeInfo` renders through `object.ToString()`; the direct call is the user-class gotcha.
func FloatLiteralTypeName(text: string): string {
    boxed := NumericLiteralFacts.GetFloatLiteralTypeInfo(text) as object
    return boxed.ToString() ?? ""
}

// Successor to NumericLiteralFacts_ClassifiesFloatLiteralSuffixes — all six of its rows.
test "numeric literal facts classify the float literal suffixes" {
    assert FloatLiteralTypeName("1.0") == "double"
    assert FloatLiteralTypeName("1.0d") == "double"
    assert FloatLiteralTypeName("1.0f") == "float"
    assert FloatLiteralTypeName("1.0F") == "float"
    assert FloatLiteralTypeName("1.0m") == "decimal"
    assert FloatLiteralTypeName("1.0M") == "decimal"
}

// The three facts the deleted rows implied without stating: `D` is as unmatched as `d`, the text is
// trimmed before it is read, and anything unsuffixed is `double`.
test "the float literal default is double and the text is trimmed first" {
    assert FloatLiteralTypeName("1.0D") == "double"
    assert FloatLiteralTypeName("  1.0f  ") == "float"
    assert FloatLiteralTypeName("  1.0m") == "decimal"
    assert FloatLiteralTypeName("0") == "double"
    assert FloatLiteralTypeName("") == "double"
}

// ---- the CLR integer literal type map ---------------------------------------------------------------

// Successor to NumericLiteralFacts_MapsClrIntegerLiteralTypes — all nine of its rows.
test "numeric literal facts map every clr integer type to its n-sharp type info" {
    mapped: SimpleTypeInfo = BuiltInTypes.Int

    assert NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(byte), out mapped)
    assert mapped.Name == "byte"
    assert NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(sbyte), out mapped)
    assert mapped.Name == "sbyte"
    assert NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(short), out mapped)
    assert mapped.Name == "short"
    assert NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(ushort), out mapped)
    assert mapped.Name == "ushort"
    assert NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(int), out mapped)
    assert mapped.Name == "int"
    assert NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(uint), out mapped)
    assert mapped.Name == "uint"
    assert NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(long), out mapped)
    assert mapped.Name == "long"
    assert NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(ulong), out mapped)
    assert mapped.Name == "ulong"
    assert NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(char), out mapped)
    assert mapped.Name == "char"
}

// Successor to NumericLiteralFacts_RejectsNonIntegerClrTypes — both of its assertions, plus the
// three non-integer types it did not try.
test "an unmapped clr type is refused and leaves int in the out slot" {
    unmapped: SimpleTypeInfo = BuiltInTypes.Long

    assert !NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(string), out unmapped)
    assert BuiltInTypes.Is(unmapped, BuiltInTypes.Int)

    assert !NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(bool), out unmapped)
    assert BuiltInTypes.Is(unmapped, BuiltInTypes.Int)

    assert !NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(double), out unmapped)
    assert BuiltInTypes.Is(unmapped, BuiltInTypes.Int)

    assert !NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(decimal), out unmapped)
    assert BuiltInTypes.Is(unmapped, BuiltInTypes.Int)

    assert !NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(typeof(object), out unmapped)
    assert BuiltInTypes.Is(unmapped, BuiltInTypes.Int)
}

// ---- the negative-literal magnitude table ------------------------------------------------------------

// Successor to NumericLiteralFacts_ProvidesNegativeIntegerLiteralMaxMagnitude — all four of its rows.
test "the negative integer literal magnitude is one past max value for the four signed types" {
    magnitude: ulong = 0UL

    assert NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("sbyte", out magnitude)
    assert magnitude == 128UL
    assert NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("short", out magnitude)
    assert magnitude == 32768UL
    assert NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("int", out magnitude)
    assert magnitude == 2147483648UL
    assert NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("long", out magnitude)
    assert magnitude == 9223372036854775808UL
}

// The arithmetic identity behind those four numbers, stated so a wrong row cannot look plausible:
// each magnitude is exactly the type's own `MaxValue` plus one.
test "each negative literal magnitude is exactly the signed max value plus one" {
    magnitude: ulong = 0UL
    one: ulong = 1UL

    assert NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("sbyte", out magnitude)
    assert magnitude == (ulong)sbyte.MaxValue + one
    assert NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("short", out magnitude)
    assert magnitude == (ulong)short.MaxValue + one
    assert NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("int", out magnitude)
    assert magnitude == (ulong)int.MaxValue + one
    assert magnitude.ToString() == "2147483648"
    assert NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("long", out magnitude)
    assert magnitude == (ulong)long.MaxValue + one
    assert magnitude.ToString() == "9223372036854775808"
}

// The domain of the table is exactly those four names. `uint` — which the OTHER table does carry —
// is the row that shows the two domains differ.
test "the negative literal magnitude table covers only the four signed types" {
    magnitude: ulong = 7UL

    assert !NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("uint", out magnitude)
    assert magnitude == 0UL
    assert !NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("byte", out magnitude)
    assert magnitude == 0UL
    assert !NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("ushort", out magnitude)
    assert magnitude == 0UL
    assert !NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("ulong", out magnitude)
    assert magnitude == 0UL
    assert !NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("char", out magnitude)
    assert magnitude == 0UL
}

// ---- the unsigned max-value table ---------------------------------------------------------------------

// Successor to NumericLiteralFacts_ProvidesUnsignedIntegerLiteralMaxValue — all nine of its rows.
test "the unsigned integer literal max value covers eight n-sharp type names" {
    bound: ulong = 0UL

    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("byte", out bound)
    assert bound == 255UL
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("sbyte", out bound)
    assert bound == 127UL
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("short", out bound)
    assert bound == 32767UL
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("ushort", out bound)
    assert bound == 65535UL
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("char", out bound)
    assert bound == 65535UL
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("int", out bound)
    assert bound == 2147483647UL
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("uint", out bound)
    assert bound == 4294967295UL
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("long", out bound)
    assert bound == 9223372036854775807UL
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("ulong", out bound)
    assert bound == ulong.MaxValue
}

// The same nine bounds as the CLR's own `MaxValue` constants, so a transposed digit cannot pass.
test "each unsigned literal bound is exactly the clr max value of its type" {
    bound: ulong = 0UL

    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("byte", out bound)
    assert bound == (ulong)byte.MaxValue
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("sbyte", out bound)
    assert bound == (ulong)sbyte.MaxValue
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("short", out bound)
    assert bound == (ulong)short.MaxValue
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("ushort", out bound)
    assert bound == (ulong)ushort.MaxValue
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("char", out bound)
    assert bound == (ulong)ushort.MaxValue
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("int", out bound)
    assert bound == (ulong)int.MaxValue
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("uint", out bound)
    assert bound == (ulong)uint.MaxValue
    assert bound.ToString() == "4294967295"
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("long", out bound)
    assert bound == (ulong)long.MaxValue
    assert NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("ulong", out bound)
    assert bound.ToString() == "18446744073709551615"
}

// Successor to NumericLiteralFacts_RejectsUnsupportedIntegerLiteralBounds — both of its pairs, plus
// the CLR-vocabulary misses that prove the tables are keyed by N# type NAME.
test "an unknown type name is refused by both bound tables and leaves zero behind" {
    magnitude: ulong = 9UL
    bound: ulong = 9UL

    assert !NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("uint", out magnitude)
    assert magnitude == 0UL
    assert !NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("string", out bound)
    assert bound == 0UL

    assert !NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("Int32", out bound)
    assert bound == 0UL
    assert !NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("System.Int32", out bound)
    assert bound == 0UL
    assert !NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("INT", out bound)
    assert bound == 0UL
    assert !NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue("", out bound)
    assert bound == 0UL
    assert !NumericLiteralFacts.TryGetNegativeIntegerLiteralMaxMagnitude("", out magnitude)
    assert magnitude == 0UL
}

// ---- the parse and suffix families the deleted file never reached ---------------------------------------

// `ParseUnsignedIntegerMagnitude` strips trailing `u`/`U`/`l`/`L` in any order and any count,
// removes digit-group underscores, and reads three radix prefixes case-insensitively.
test "parsing an unsigned magnitude strips suffixes underscores and reads three radix prefixes" {
    assert NumericLiteralFacts.ParseUnsignedIntegerMagnitude("42") == 42UL
    assert NumericLiteralFacts.ParseUnsignedIntegerMagnitude("42u") == 42UL
    assert NumericLiteralFacts.ParseUnsignedIntegerMagnitude("42UL") == 42UL
    assert NumericLiteralFacts.ParseUnsignedIntegerMagnitude("42lu") == 42UL
    assert NumericLiteralFacts.ParseUnsignedIntegerMagnitude("1_000_000") == 1000000UL
    assert NumericLiteralFacts.ParseUnsignedIntegerMagnitude("0xFF") == 255UL
    assert NumericLiteralFacts.ParseUnsignedIntegerMagnitude("0Xff") == 255UL
    assert NumericLiteralFacts.ParseUnsignedIntegerMagnitude("0b1010") == 10UL
    assert NumericLiteralFacts.ParseUnsignedIntegerMagnitude("0o17") == 15UL
    assert NumericLiteralFacts.ParseUnsignedIntegerMagnitude("18446744073709551615") == ulong.MaxValue
}

// The `Try` wrapper turns each of the three parse failures into `false` plus a zeroed out slot,
// rather than letting the exception reach the analyser.
test "the try parse wrapper answers false and zero for malformed and overflowing text" {
    value: ulong = 5UL

    assert NumericLiteralFacts.TryParseUnsignedIntegerMagnitude("42", out value)
    assert value == 42UL

    assert !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude("abc", out value)
    assert value == 0UL

    assert !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude("", out value)
    assert value == 0UL

    assert !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude("18446744073709551616", out value)
    assert value == 0UL

    assert !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude("0xZZ", out value)
    assert value == 0UL
}

// `GetIntegerSuffix` reports the two flags independently, in either order and in either case, and
// answers both-false for an unsuffixed literal.
test "the integer suffix reports unsigned and long independently in any order or case" {
    plain := NumericLiteralFacts.GetIntegerSuffix("42")
    assert !plain.HasUnsigned
    assert !plain.HasLong

    unsigned := NumericLiteralFacts.GetIntegerSuffix("42u")
    assert unsigned.HasUnsigned
    assert !unsigned.HasLong

    wide := NumericLiteralFacts.GetIntegerSuffix("42L")
    assert !wide.HasUnsigned
    assert wide.HasLong

    both := NumericLiteralFacts.GetIntegerSuffix("42UL")
    assert both.HasUnsigned
    assert both.HasLong

    reversed := NumericLiteralFacts.GetIntegerSuffix("42lu")
    assert reversed.HasUnsigned
    assert reversed.HasLong
}
