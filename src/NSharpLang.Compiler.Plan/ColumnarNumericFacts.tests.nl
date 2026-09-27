namespace NSharpLang.Compiler.Columnar

import System


// THE CANONICAL CONTRACTS FOR `ColumnarNumericFacts`, IN N#.
//
// These replace the two table families of `tests/ColumnarNumericFactsTests.cs` (101 lines; 9 + 14
// `[InlineData]` rows). The kernel answers the two numeric questions the columnar emitter asks
// constantly: which CLR types the arithmetic family PROMOTES TO `int`, and which scalars an
// explicit `(T)` cast may target. Five N# production owners consult it
// (`ColumnarPrimitiveBinaryPlanner`, `ColumnarNullableArgumentLowering`, `ColumnarRangeIndexPlanner`,
// `ColumnarCodePlanExecutor`, `ColumnarSourceDirectCallResolver`) plus the C# `ColumnarIlEmitter`.
// The two emit cases of the deleted file live in `tests/native/columnar-emit-facts`, where the
// shapes are compiled by the product build rather than reflected into.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. The recorded block was "`typeof` rows PLUS
// driving `ColumnarCompiler.TryEmitProgram` PLUS reflection over the emitted assembly". The first
// third is an `NL310` TABLE verdict that does not apply to an estate `test` declaration; the other
// two thirds belong to the emit cases, which moved to the native project.
//
// THE FOUR THINGS THAT ARE EASY TO GET WRONG:
//
// (1) THE PROMOTION SET IS THE NARROW TYPES PLUS `int` AND `char`, AND NOTHING WIDER. `long`,
// `ulong` and `uint` are NOT int-promotable — promoting them to `int` would silently truncate — so
// the two rows that look like oversights (`long`, `uint`) are the entire point of the gate.
//
// (2) `char` IS ON BOTH LISTS, AND IT IS NOT A MISTAKE. The CLR carries `char` as an unsigned
// 16-bit integer, so `'a' + 1` really is `int` arithmetic.
//
// (3) THE CAST SET IS STRICTLY WIDER THAN THE PROMOTION SET AND INCLUDES `decimal`, WHICH IS NOT AN
// IL-PRIMITIVE AT ALL. Every promotable type is castable; six castable types are not promotable.
// The deleted C# stated both lists but never crossed them, so nothing anywhere said the inclusion
// held in one direction only.
//
// (4) `IsBitwiseEnum` IS THE THIRD ENTRY POINT AND THE DELETED C# NEVER TOUCHED IT. It is the rule
// that lets `Public | Instance` stay a `BindingFlags` instead of collapsing to `int`, and it is
// written defensively — it swallows `NotSupportedException` and `NotImplementedException` from BOTH
// `IsEnum` and `GetEnumUnderlyingType`, because a builder-backed type under construction can answer
// neither. Its admitted underlying set is the promotable set PLUS `long`, `ulong` and `uint`, which
// is exactly the set the bitwise opcodes already run over as plain operands.

// `typeof` does not name every runtime type on the columnar surface, so the enums this kernel is
// asked about are seeded by name — finding 99.1's shape, made non-null.
func NamedNumericType(name: string): Type {
    found := Type.GetType(name)
    if found == null {
        throw new InvalidOperationException("The runtime type was not resolvable: " + name)
    }

    return found
}

// Successor to IsIntPromotable_ClassifiesColumnarPromotionSet — all nine of its rows.
test "columnar numeric facts classify the int promotion set" {
    assert ColumnarNumericFacts.IsIntPromotable(typeof(int))
    assert ColumnarNumericFacts.IsIntPromotable(typeof(char))
    assert ColumnarNumericFacts.IsIntPromotable(typeof(byte))
    assert ColumnarNumericFacts.IsIntPromotable(typeof(sbyte))
    assert ColumnarNumericFacts.IsIntPromotable(typeof(short))
    assert ColumnarNumericFacts.IsIntPromotable(typeof(ushort))
    assert !ColumnarNumericFacts.IsIntPromotable(typeof(long))
    assert !ColumnarNumericFacts.IsIntPromotable(typeof(uint))
    assert !ColumnarNumericFacts.IsIntPromotable(typeof(bool))
}

// The four refusals the deleted rows did not reach. `ulong` matters most: it is the one 64-bit type
// the relational-pattern set DOES admit, so a reader who learned the sets from `ColumnarPatternFacts`
// would guess wrong here.
test "the int promotion set refuses every type wider than int" {
    assert !ColumnarNumericFacts.IsIntPromotable(typeof(ulong))
    assert !ColumnarNumericFacts.IsIntPromotable(typeof(float))
    assert !ColumnarNumericFacts.IsIntPromotable(typeof(double))
    assert !ColumnarNumericFacts.IsIntPromotable(typeof(decimal))
    assert !ColumnarNumericFacts.IsIntPromotable(typeof(string))
    assert !ColumnarNumericFacts.IsIntPromotable(typeof(object))
}

// Successor to IsCastableScalar_ClassifiesColumnarExplicitCastSet — all fourteen of its rows.
test "columnar numeric facts classify the explicit cast scalar set" {
    assert ColumnarNumericFacts.IsCastableScalar(typeof(int))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(long))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(char))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(double))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(float))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(byte))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(sbyte))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(short))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(ushort))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(uint))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(ulong))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(decimal))
    assert !ColumnarNumericFacts.IsCastableScalar(typeof(bool))
    assert !ColumnarNumericFacts.IsCastableScalar(typeof(string))
}

test "the explicit cast scalar set refuses non-numeric types" {
    assert !ColumnarNumericFacts.IsCastableScalar(typeof(object))
    assert !ColumnarNumericFacts.IsCastableScalar(NamedNumericType("System.DateTime"))
    assert !ColumnarNumericFacts.IsCastableScalar(NamedNumericType("System.IntPtr"))
}

// The containment the deleted C# stated twice and never crossed once: promotion implies castable,
// and six types show the converse fails.
test "every int promotable type is castable and six castable types are not promotable" {
    assert ColumnarNumericFacts.IsIntPromotable(typeof(int)) && ColumnarNumericFacts.IsCastableScalar(typeof(int))
    assert ColumnarNumericFacts.IsIntPromotable(typeof(char)) && ColumnarNumericFacts.IsCastableScalar(typeof(char))
    assert ColumnarNumericFacts.IsIntPromotable(typeof(byte)) && ColumnarNumericFacts.IsCastableScalar(typeof(byte))
    assert ColumnarNumericFacts.IsIntPromotable(typeof(sbyte)) && ColumnarNumericFacts.IsCastableScalar(typeof(sbyte))
    assert ColumnarNumericFacts.IsIntPromotable(typeof(short)) && ColumnarNumericFacts.IsCastableScalar(typeof(short))
    assert ColumnarNumericFacts.IsIntPromotable(typeof(ushort)) && ColumnarNumericFacts.IsCastableScalar(typeof(ushort))

    assert ColumnarNumericFacts.IsCastableScalar(typeof(long)) && !ColumnarNumericFacts.IsIntPromotable(typeof(long))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(ulong)) && !ColumnarNumericFacts.IsIntPromotable(typeof(ulong))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(uint)) && !ColumnarNumericFacts.IsIntPromotable(typeof(uint))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(float)) && !ColumnarNumericFacts.IsIntPromotable(typeof(float))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(double)) && !ColumnarNumericFacts.IsIntPromotable(typeof(double))
    assert ColumnarNumericFacts.IsCastableScalar(typeof(decimal)) && !ColumnarNumericFacts.IsIntPromotable(typeof(decimal))
}

// `IsBitwiseEnum` — the third entry point. The deleted C# never touched it, but it is NOT
// unasserted: `ColumnarPrimitiveBinaryPlanner.tests.nl:1687-1701` already states the enum /
// non-enum split and the underlying set, from the planner's side. These rows state the same rule
// from the KERNEL's side, where its two neighbours are stated, so the three sets can be compared in
// one place. Measured, not assumed — a mutation that drops `long` from the underlying set fails the
// planner's two contracts as well as this one.
test "the bitwise enum gate admits an enum over an admitted underlying type" {
    assert ColumnarNumericFacts.IsBitwiseEnum(NamedNumericType("System.AttributeTargets"))
    assert ColumnarNumericFacts.IsBitwiseEnum(NamedNumericType("System.DayOfWeek"))
    assert ColumnarNumericFacts.IsBitwiseEnum(NamedNumericType("System.StringComparison"))
}

// An N#-SOURCE-declared enum is admitted on the same terms as a BCL one — the gate reads the CLR
// shape, not the declaring language. `ColumnarDirectCallOwnership` is this assembly's own.
test "the bitwise enum gate admits an n-sharp source enum" {
    assert ColumnarNumericFacts.IsBitwiseEnum(typeof(ColumnarDirectCallOwnership))
    assert typeof(ColumnarDirectCallOwnership).GetEnumUnderlyingType().Name == "Int32"
}

// The underlying set is the promotable set PLUS the three 64/32-bit unsigned-or-wide rows, which is
// wider than `IsIntPromotable` alone would admit. A `long`-backed enum proves the widening arm.
test "the bitwise enum gate admits a long-backed enum that is not int promotable" {
    longBackedEnum := NamedNumericType("System.Diagnostics.Tracing.EventKeywords")
    assert longBackedEnum.GetEnumUnderlyingType().Name == "Int64"
    assert !ColumnarNumericFacts.IsIntPromotable(longBackedEnum.GetEnumUnderlyingType())
    assert ColumnarNumericFacts.IsBitwiseEnum(longBackedEnum)
}

// A non-enum is refused however numeric it is — the gate is about the RESULT type staying an enum,
// not about the operand fitting an opcode.
test "the bitwise enum gate refuses every type that is not a clr enum" {
    assert !ColumnarNumericFacts.IsBitwiseEnum(typeof(int))
    assert !ColumnarNumericFacts.IsBitwiseEnum(typeof(long))
    assert !ColumnarNumericFacts.IsBitwiseEnum(typeof(byte))
    assert !ColumnarNumericFacts.IsBitwiseEnum(typeof(bool))
    assert !ColumnarNumericFacts.IsBitwiseEnum(typeof(string))
    assert !ColumnarNumericFacts.IsBitwiseEnum(typeof(object))
}
