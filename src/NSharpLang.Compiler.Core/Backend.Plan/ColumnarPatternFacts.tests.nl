namespace NSharpLang.Compiler.Columnar

import System


// THE CANONICAL CONTRACTS FOR `ColumnarPatternFacts`, IN N#.
//
// These replace the two table families of `tests/ColumnarPatternFactsTests.cs` (66 lines; 7 + 8
// `[InlineData]` rows). The kernel decides two things for the columnar `match` lowering: which
// pattern node kinds are LITERAL patterns, and which CLR types a RELATIONAL pattern (`< 5`, `>= x`)
// may compare with. Its only production referrer is the C# `ColumnarIlEmitter`, which asks both
// questions while lowering a match arm; the third case of the deleted file — that a real `match`
// program emits and runs — is `tests/native/columnar-emit-facts`, where the shape is compiled by
// the product build rather than reflected into.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. The recorded block was "`typeof` rows PLUS
// driving `ColumnarCompiler.TryEmitProgram` PLUS reflection over the emitted assembly". The first
// third of that is a `NL310` TABLE verdict and does not apply to an estate `test` declaration; the
// other two thirds belong to the emit case, which moved to the native project.
//
// THE THREE THINGS THAT ARE EASY TO GET WRONG:
//
// (1) THE LITERAL-KIND RANGE IS A CLOSED INTERVAL OVER NODE KINDS, AND BOTH ENDS MATTER. `0`
// through `4` are literal patterns; `-1` and `5` are not. A node kind is an ordinal, so an inserted
// kind silently shifts the interval — which is why every admitted value is stated individually
// rather than only the two boundaries.
//
// (2) THE RELATIONAL TYPE SET IS NOT THE ARITHMETIC ONE, AND THE DIFFERENCE IS SURPRISING. It
// admits `int`, `long`, `ulong`, `char`, `double` and `float` — but NOT `byte`, `short`, `ushort`,
// `uint` or `decimal`, all of which `ColumnarNumericFacts.IsCastableScalar` DOES admit. The two
// kernels sit next to each other in the same emitter, so the asymmetry is stated here explicitly
// and cross-checked below rather than left to be inferred.
//
// (3) `bool` AND `string` ARE REFUSED FOR DIFFERENT REASONS AND BOTH MUST STAY REFUSED. `bool` has
// no ordering; `string` has one, but not one the CLR comparison opcodes implement. A relational
// pattern over either would emit an opcode against an operand it cannot compare.

// Successor to IsLiteralPatternKind_ClassifiesColumnarLiteralNodes — all seven of its rows.
test "columnar pattern facts classify the literal pattern node kinds" {
    assert !ColumnarPatternFacts.IsLiteralPatternKind(-1)
    assert ColumnarPatternFacts.IsLiteralPatternKind(0)
    assert ColumnarPatternFacts.IsLiteralPatternKind(1)
    assert ColumnarPatternFacts.IsLiteralPatternKind(2)
    assert ColumnarPatternFacts.IsLiteralPatternKind(3)
    assert ColumnarPatternFacts.IsLiteralPatternKind(4)
    assert !ColumnarPatternFacts.IsLiteralPatternKind(5)
}

// The interval is closed at both ends far beyond the two neighbours the deleted rows checked.
test "the literal pattern kind interval is closed at both ends" {
    assert !ColumnarPatternFacts.IsLiteralPatternKind(-2)
    assert !ColumnarPatternFacts.IsLiteralPatternKind(6)
    assert !ColumnarPatternFacts.IsLiteralPatternKind(100)
    assert !ColumnarPatternFacts.IsLiteralPatternKind(int.MaxValue)
    assert !ColumnarPatternFacts.IsLiteralPatternKind(int.MinValue)
}

// Successor to IsOrderedMatchType_ClassifiesRelationalPatternSet — all eight of its rows.
test "columnar pattern facts classify the relational pattern type set" {
    assert ColumnarPatternFacts.IsOrderedMatchType(typeof(int))
    assert ColumnarPatternFacts.IsOrderedMatchType(typeof(long))
    assert ColumnarPatternFacts.IsOrderedMatchType(typeof(ulong))
    assert ColumnarPatternFacts.IsOrderedMatchType(typeof(char))
    assert ColumnarPatternFacts.IsOrderedMatchType(typeof(double))
    assert ColumnarPatternFacts.IsOrderedMatchType(typeof(float))
    assert !ColumnarPatternFacts.IsOrderedMatchType(typeof(bool))
    assert !ColumnarPatternFacts.IsOrderedMatchType(typeof(string))
}

// The five numeric types the relational set refuses. Never stated anywhere before this contract.
test "the relational pattern type set refuses the narrow and decimal numerics" {
    assert !ColumnarPatternFacts.IsOrderedMatchType(typeof(byte))
    assert !ColumnarPatternFacts.IsOrderedMatchType(typeof(sbyte))
    assert !ColumnarPatternFacts.IsOrderedMatchType(typeof(short))
    assert !ColumnarPatternFacts.IsOrderedMatchType(typeof(ushort))
    assert !ColumnarPatternFacts.IsOrderedMatchType(typeof(uint))
    assert !ColumnarPatternFacts.IsOrderedMatchType(typeof(decimal))
    assert !ColumnarPatternFacts.IsOrderedMatchType(typeof(object))
}

// The asymmetry between the two neighbouring kernels, stated where both can be seen at once: every
// relational type is castable, but five castable types are NOT relational.
test "every relational match type is castable but the converse fails for five types" {
    assert ColumnarNumericFacts.IsCastableScalar(typeof(int))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(long))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(ulong))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(char))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(double))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(float))

    assert ColumnarNumericFacts.IsCastableScalar(typeof(byte)) && !ColumnarPatternFacts.IsOrderedMatchType(typeof(byte))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(sbyte)) && !ColumnarPatternFacts.IsOrderedMatchType(typeof(sbyte))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(short)) && !ColumnarPatternFacts.IsOrderedMatchType(typeof(short))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(ushort)) && !ColumnarPatternFacts.IsOrderedMatchType(typeof(ushort))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(uint)) && !ColumnarPatternFacts.IsOrderedMatchType(typeof(uint))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(decimal)) && !ColumnarPatternFacts.IsOrderedMatchType(typeof(decimal))
}
