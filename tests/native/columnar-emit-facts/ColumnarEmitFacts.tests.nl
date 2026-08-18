namespace NSharpLang.ColumnarEmitFacts.Tests


// THE FIVE EMIT CASES OF THE COLUMNAR FACT KERNELS, COMPILED BY THE PRODUCT BUILD ITSELF.
//
// These replace the five `[Fact]`s that drove `ColumnarCompiler.TryEmitProgram` by reflection:
//   tests/ColumnarPatternFactsTests.cs      ColumnarCompiler_MatchPatterns_UseNSharpPatternFacts
//   tests/ColumnarNumericFactsTests.cs      ColumnarCompiler_IntPromotableArithmetic_UsesNSharpNumericFacts
//   tests/ColumnarNumericFactsTests.cs      ColumnarCompiler_ExplicitNumericCasts_UseNSharpNumericFacts
//   tests/ColumnarTypeCanonicalizerTests.cs ColumnarCompiler_NamedTupleLocal_UsesNSharpCanonicalizer
//   tests/ColumnarTypeCanonicalizerTests.cs ColumnarCompiler_NamespacedStructShortName_UsesNSharpCanonicalizer
//
// Each of those five built a source STRING, handed it to the internal
// `ColumnarCompiler.TryEmitProgram`, loaded the returned bytes into a collectible context, found the
// method by reflection and invoked it. Here the same source shape is written DIRECTLY in this file
// and called directly, because a `tests/native` project is compiled by the columnar backend under
// test: `nlc test` routes this file through `ColumnarProgramInputBuilder` and `ColumnarIlEmitter` —
// the same two components the 25-line `TryEmitProgram` wrapper calls, and nothing else.
//
// THIS ROUTE IS STRICTLY STRONGER THAN THE REFLECTION ONE, IN THREE WAYS.
//   (a) IT INCLUDES THE ANALYSER. `TryEmitProgram` is an emit-only entry that bypasses analysis
//       entirely, so a shape that emits but does not ANALYSE passed the deleted tests. Here the
//       whole product build runs, so a shape has to survive both.
//   (b) A DECLINE IS A BUILD FAILURE RATHER THAN ONE FALSE `Assert.True`. The deleted cases each
//       asserted `TryEmitProgram(...) == true` once; here a decline stops the project compiling and
//       the runner reports it with its decline SITE.
//   (c) EVERY ARM IS EXERCISED. The deleted match case invoked three inputs; the deleted cast case
//       invoked one value per direction. These contracts state every arm of every shape, including
//       the boundary between the two relational arms and the truncation direction of `(int)`.
//
// WHY IT IS NOT A REFLECTION HARNESS. It was measured: reaching the internal wrapper needs
// `Type.GetMethod(name, BindingFlags)`, and that overload declines at
// `emit.call.instance-member-unmodeled` ("instance call 'Type.GetMethod' with 2 argument(s) is not
// modeled"). The catalog row that would model it is not added, because it would buy a strictly
// weaker route than this one.
//
// ONE SPELLING NOTE. A tuple-typed local needs `let`: `pair: (x: int, y: int) = (1, 2)` parses as an
// assignment to an undeclared `pair` and reports NL301 + NL103.

struct Point {
    X: int
}

// ---- ColumnarPatternFacts: match lowering ------------------------------------------------------

// The deleted case's exact program. `0` is a literal pattern (kind 0..4), `< 5` is a relational
// pattern over `int` — which `IsOrderedMatchType` admits — and `_` is the catch-all.
func MatchedValue(x: int): int {
    return match x {
        0 => 10,
        < 5 => 20,
        _ => 30
    }
}

test "the columnar match lowering routes literal relational and discard arms" {
    assert MatchedValue(0) == 10
    assert MatchedValue(3) == 20
    assert MatchedValue(7) == 30
}

// The two boundaries the deleted case's three inputs did not pin: the literal arm wins over the
// relational arm that also matches `0`, and the relational arm is strictly less-than.
test "the literal arm precedes the relational arm and the relational bound is exclusive" {
    assert MatchedValue(1) == 20
    assert MatchedValue(4) == 20
    assert MatchedValue(5) == 30
    assert MatchedValue(-1) == 20
    assert MatchedValue(int.MaxValue) == 30
    assert MatchedValue(int.MinValue) == 20
}

// ---- ColumnarNumericFacts: int-promotable arithmetic --------------------------------------------

// The deleted case's exact program: a `byte` and a `short` are both int-promotable, so `a + b` is
// `int` arithmetic and the function's declared `int` return needs no conversion.
func PromotedSum(): int {
    a: byte = 1
    b: short = 2
    return a + b
}

test "adding a byte and a short promotes to int" {
    assert PromotedSum() == 3
}

// The other four members of the promotion set, each paired with `int` — none of which the deleted
// case reached, and each of which is a separate opcode path.
func PromotedFromSByte(value: sbyte): int {
    return value + 1
}

func PromotedFromUShort(value: ushort): int {
    return value + 1
}

func PromotedFromChar(value: char): int {
    return value + 1
}

func PromotedFromByte(value: byte): int {
    return value + 1
}

test "every int promotable operand promotes to int arithmetic" {
    assert PromotedFromSByte(-1) == 0
    assert PromotedFromUShort(65535) == 65536
    assert PromotedFromChar('a') == 98
    assert PromotedFromByte(255) == 256
}

// ---- ColumnarNumericFacts: explicit numeric casts ------------------------------------------------

// The deleted case's exact two programs.
func Narrowed(value: double): int {
    return (int)value
}

func Widened(value: int): long {
    return (long)value
}

test "an explicit cast narrows a double to an int and widens an int to a long" {
    assert Narrowed(3.75) == 3
    assert Widened(42) == 42
}

// Narrowing TRUNCATES toward zero rather than rounding — the fact a single `3.75 -> 3` case cannot
// distinguish from rounding, because both answer 3.
test "narrowing a double truncates toward zero rather than rounding" {
    assert Narrowed(3.25) == 3
    assert Narrowed(3.99) == 3
    assert Narrowed(-3.75) == -3
    assert Narrowed(-3.25) == -3
    assert Narrowed(0.0) == 0
}

// Widening is sign-preserving, and the widened value is genuinely 64-bit.
func WidenedSum(value: int): long {
    return (long)value + 2147483647L
}

test "widening an int to a long preserves sign and reaches beyond int range" {
    assert Widened(-42) == -42
    assert Widened(0) == 0
    assert WidenedSum(1) == 2147483648L
    assert WidenedSum(2147483647) == 4294967294L
}

// ---- ColumnarTypeCanonicalizer: named tuple locals -----------------------------------------------

// The deleted case's exact program: the declared type carries element NAMES, which the canonicalizer
// strips before the registry looks the tuple up, and the member access uses one of them.
func NamedTupleFirst(): int {
    let pair: (x: int, y: int) = (1, 2)
    return pair.x
}

test "a named tuple local resolves its first element by name" {
    assert NamedTupleFirst() == 1
}

// The second element and the positional spelling of the same shape — neither reached by the deleted
// case, and together they show the names are metadata rather than a different type.
func NamedTupleSecond(): int {
    let pair: (x: int, y: int) = (1, 2)
    return pair.y
}

// A POSITIONAL local of the same structural shape, so the names are shown to be metadata over one
// tuple type rather than a different type: both reach element two the same way.
//
// A NESTED named tuple is NOT reachable here and the wall is recorded rather than routed around:
// `let nested: (a: int, b: (c: int, d: int)) = (1, (2, 3))` declines at `emit.return.expression`
// whether the inner element is read as a chain (`nested.b.d`) or through an intermediate local.
func PositionalTupleSecond(): int {
    let pair: (int, int) = (1, 2)
    return pair.Item2
}

test "a named tuple local resolves every element and matches its positional spelling" {
    assert NamedTupleSecond() == 2
    assert PositionalTupleSecond() == 2
}

// ---- ColumnarTypeCanonicalizer: a namespaced struct by short name ---------------------------------

// The deleted case's exact program: the struct is declared inside a namespace, so its canonical name
// is qualified, and the construction names it by its SHORT name — which only resolves because
// `UnqualifiedTypeName` strips the prefix before the registry lookup.
func StructValue(): int {
    p := new Point { X: 7 }
    return p.X
}

test "a namespaced struct is constructed by its short name" {
    assert StructValue() == 7
}

// The short name resolves in every position the registry is asked about, not only construction.
func StructRoundTrip(seed: int): Point {
    return new Point { X: seed }
}

func StructFieldOf(value: Point): int {
    return value.X
}

test "the short name resolves in return and parameter position as well as construction" {
    assert StructFieldOf(StructRoundTrip(11)) == 11
    assert StructRoundTrip(0).X == 0
}
