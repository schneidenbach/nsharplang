namespace NSharpLang.Compiler.Columnar

import System
import System.IO
import System.Reflection
import System.Runtime.InteropServices
import NSharpLang.Compiler.Ast


// 023/1e — THE TWO CONSTANT CONVERSIONS, AND THE THREE CAPS THAT ARE NOT THE SPEC'S.
//
// These contracts pin the OWNER. The per-position contracts live in
// `tests/native/columnar-emit-facts/ConstantConversionEmitFacts.tests.nl`, because what a rule costs is
// only visible where it is USED; what is pinned here is the decision itself, including the three places
// the decision is deliberately narrower than ECMA-334 §10.2.11.
func ConstantFactsEnumType(): Type {
    // ASSEMBLY-QUALIFIED ON PURPOSE. `AssemblyFlags` lives in `System.Reflection.Metadata.dll`, not in
    // CoreLib, so a bare metadata name resolves to nothing -- the wall STATUS 2.1 records for
    // `Type.GetType` of a non-core type, met here in a test rather than in production.
    resolved := Type.GetType("System.Reflection.AssemblyFlags, System.Reflection.Metadata")
    if resolved == null {
        throw new InvalidOperationException("AssemblyFlags runtime type was not found.")
    }

    return resolved
}

test "the literal zero converts, in every integer literal form, and nothing else does" {
    // ECMA-334 §10.2.4: a constant expression of ANY integer type with the value zero. The suffix is
    // not the test and the magnitude is.
    assert ConstantConversionFacts.IsLiteralZero("0", false)
    assert ConstantConversionFacts.IsLiteralZero("0L", false)
    assert ConstantConversionFacts.IsLiteralZero("0UL", false)
    assert ConstantConversionFacts.IsLiteralZero("0x0", false)

    // ONE is not zero. This is the whole reason the rule is not "any in-range literal": a laxer rule
    // would accept `AssemblyFlags = 7` for a flag combination that names nothing.
    assert !ConstantConversionFacts.IsLiteralZero("1", false)
    assert !ConstantConversionFacts.IsLiteralZero("7", false)

    // A negated zero is not a zero LITERAL, and a non-literal has no text to read.
    assert !ConstantConversionFacts.IsLiteralZero("0", true)
    assert !ConstantConversionFacts.IsLiteralZero("", false)
    assert !ConstantConversionFacts.IsLiteralZero(null, false)
}

test "an in-range integer constant converts to the narrower integral target" {
    value := 0L

    // ECMA-334 §10.2.11 over each narrowing target.
    assert ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(byte), "65", false, out value)
    assert value == 65L
    assert ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(byte), "255", false, out value)
    assert value == 255L
    assert ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(short), "32767", false, out value)
    assert value == 32767L
    assert ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(ushort), "65535", false, out value)
    assert value == 65535L
    assert ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(sbyte), "127", false, out value)
    assert value == 127L

    // Out of range for the target.
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(byte), "256", false, out value)
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(sbyte), "128", false, out value)
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(ushort), "65536", false, out value)

    // A SUFFIXED literal carries its own fixed type and never adopts a target.
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(byte), "65L", false, out value)
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(byte), "65UL", false, out value)

    // A target that is not an integral narrowing target at all.
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(string), "65", false, out value)
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(double), "65", false, out value)
}

test "a negative constant reaches the signed targets and no unsigned one" {
    value := 0L
    assert ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(sbyte), "127", true, out value)
    assert value == -127L
    assert ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(short), "300", true, out value)
    assert value == -300L

    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(byte), "1", true, out value)
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(ushort), "1", true, out value)
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(uint), "1", true, out value)
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(ulong), "1", true, out value)
}

// ── THE THREE CAPS THAT ARE TIGHTER THAN §10.2.11 ────────────────────────────────────────────────
// They are NOT the spec's, they are the legacy pipeline's, and 023/1e carried them VERBATIM out of
// `ColumnarIlEmitter.TryEmitIntLiteralAsType` because moving the decision must not move the answer.
// A decline the two owners disagree about is a claim the N# door makes and the host then refuses --
// the failure `ColumnarMethodBodyPlanner` exists to prevent. FILED, not fixed: now that the decision
// lives in one place, they are correctable in one place.
test "the caps are the pipeline's, not the spec's, and they are pinned so a fix is a deliberate act" {
    value := 0L

    // #12 — `uint` caps at int.MaxValue, not uint.MaxValue. C# accepts `uint u = 4000000000;`.
    assert ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(uint), "2147483647", false, out value)
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(uint), "2147483648", false, out value)
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(uint), "4000000000", false, out value)

    // #13 — positive `long`/`ulong` magnitudes ALSO cap at int.MaxValue.
    assert ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(long), "2147483647", false, out value)
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(long), "5000000000", false, out value)
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(ulong), "5000000000", false, out value)

    // #14 — negatives cap at the target's MAXVALUE magnitude, so the exact MinValues are refused.
    // C# accepts `sbyte v = -128;` and `short w = -32768;`.
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(sbyte), "128", true, out value)
    assert !ConstantConversionFacts.TryGetInRangeIntegralConstant(typeof(short), "32768", true, out value)
}

test "the int64 constant targets are the two that take ldc.i8" {
    assert ConstantConversionFacts.IsInt64ConstantTarget(typeof(long))
    assert ConstantConversionFacts.IsInt64ConstantTarget(typeof(ulong))
    assert !ConstantConversionFacts.IsInt64ConstantTarget(typeof(int))
    assert !ConstantConversionFacts.IsInt64ConstantTarget(typeof(byte))
    assert !ConstantConversionFacts.IsInt64ConstantTarget(ConstantFactsEnumType())
}

test "the constant operand facts read a literal, a negated literal, and nothing else" {
    none := ConstantOperandFacts.None()
    assert !none.HasIntegerLiteral

    literal := ConstantOperandFacts.FromExpression(new IntLiteralExpression("65", 1, 1))
    assert literal.HasIntegerLiteral
    assert literal.LiteralText == "65"
    assert !literal.IsNegative

    negated := ConstantOperandFacts.FromExpression(new UnaryExpression(UnaryOperator.Negate, new IntLiteralExpression("128", 1, 2), 1, 1))
    assert negated.HasIntegerLiteral
    assert negated.LiteralText == "128"
    assert negated.IsNegative

    // A non-literal expression carries no constant, so its position falls back to the ordinary answer.
    assert !ConstantOperandFacts.FromExpression(new IdentifierExpression("n", 1, 1)).HasIntegerLiteral
    assert !ConstantOperandFacts.FromExpression(new StringLiteralExpression("\"x\"", 1, 1)).HasIntegerLiteral
    assert !ConstantOperandFacts.FromExpression(null).HasIntegerLiteral

    // `!x` is a unary that is NOT a negation, so it is not a negated constant.
    assert !ConstantOperandFacts.FromExpression(new UnaryExpression(UnaryOperator.Not, new IntLiteralExpression("1", 1, 2), 1, 1)).HasIntegerLiteral
}

// ── §CONV/3 — THE PAIR, ASKED OF A CLR TYPE ──────────────────────────────────────────────────────
// `AcceptsIntegerConstant` is the one question every position with a target and a literal asks: the
// assignability owner for `b: byte = 0`, the reflection binder for `roots.TryAdd(root, 0)`. Its two
// arms are the two rules above, and the guards are what keeps a constant out of method type
// inference and away from a position that is written through.
// The METHOD type parameter of an open generic declaration — the shape a reflected parameter has
// before inference binds it.
func ConstantFactsOpenTypeParameter(): Type {
    definition := typeof(Nullable<int>).GetGenericTypeDefinition()
    return definition.GetGenericArguments()[0]
}

test "both constant conversions are one question when a CLR target is in hand" {
    // §10.2.11 — an in-range integral target.
    assert ConstantConversionFacts.AcceptsIntegerConstant(typeof(byte), "0", false)
    assert ConstantConversionFacts.AcceptsIntegerConstant(typeof(byte), "255", false)
    assert !ConstantConversionFacts.AcceptsIntegerConstant(typeof(byte), "256", false)
    assert !ConstantConversionFacts.AcceptsIntegerConstant(typeof(byte), "1", true)
    assert ConstantConversionFacts.AcceptsIntegerConstant(typeof(short), "1", true)

    // §10.2.4 — an enum takes the literal zero and nothing else.
    assert ConstantConversionFacts.AcceptsIntegerConstant(ConstantFactsEnumType(), "0", false)
    assert !ConstantConversionFacts.AcceptsIntegerConstant(ConstantFactsEnumType(), "7", false)

    // A target the rule does not name at all.
    assert !ConstantConversionFacts.AcceptsIntegerConstant(typeof(string), "0", false)
    assert !ConstantConversionFacts.AcceptsIntegerConstant(typeof(int), "0", false)

    // No target, no literal.
    assert !ConstantConversionFacts.AcceptsIntegerConstant(null, "0", false)
    assert !ConstantConversionFacts.AcceptsIntegerConstant(typeof(byte), null, false)

    // AN OPEN TYPE IS REFUSED: a constant conversion drives no method type inference, so a parameter
    // still mentioning a type parameter must be bound by the standard rules or not at all.
    assert !ConstantConversionFacts.AcceptsIntegerConstant(ConstantFactsOpenTypeParameter(), "0", false)

    // A BY-REF position names storage, and a constant is not a variable.
    assert !ConstantConversionFacts.AcceptsIntegerConstant(typeof(byte).MakeByRefType(), "0", false)
}

// THE TARGET IS IDENTIFIED BY NAME, NOT BY INSTANCE, and that is the whole reason the reflection
// binder can ask at all: its parameter types come from a MetadataLoadContext, so `target ==
// typeof(byte)` — reference equality over `Type` — was false for the CLR's own `System.Byte`.
test "a primitive target is recognised through a load context that did not produce typeof(byte)" {
    resolver := new PathAssemblyResolver(Directory.GetFiles(RuntimeEnvironment.GetRuntimeDirectory(), "*.dll"))
    loadContext := new MetadataLoadContext(resolver, "System.Private.CoreLib")
    try {
        core := loadContext.get_CoreAssembly()
        assert core != null
        loadedByte := must core.GetType("System.Byte")

        // The two are the same type by NAME and a different instance, which is exactly the state the
        // old `==` test could not see through.
        assert !Object.ReferenceEquals(loadedByte, typeof(byte))
        assert loadedByte.FullName == typeof(byte).FullName

        assert ConstantConversionFacts.AcceptsIntegerConstant(loadedByte, "200", false)
        assert !ConstantConversionFacts.AcceptsIntegerConstant(loadedByte, "256", false)

        loadedLong := must core.GetType("System.Int64")
        assert ConstantConversionFacts.IsInt64ConstantTarget(loadedLong)
    } finally {
        loadContext.Dispose()
    }
}
