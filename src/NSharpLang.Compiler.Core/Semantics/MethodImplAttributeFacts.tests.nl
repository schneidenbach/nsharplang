namespace NSharpLang.Compiler

import System
import System.Reflection
import System.Runtime.CompilerServices
import NSharpLang.Compiler.Ast

// THE RULES FOR `[MethodImpl(...)]`, STATED WHERE NOTHING IS EMITTED.
//
// Three of the options this owner judges CANNOT be exercised through an emitted assembly, because the
// assembly would not load: `InternalCall` and `Unmanaged` on a member with a body, and `Synchronized`
// on a value type's member, are all refused by the type loader — which is the entire reason the rule
// exists. They are measured here instead, against the real `MethodImplAttribute` and its real enums,
// and `tests/native/methodimpl-attributes` measures everything that CAN be emitted.
func MiafOptions(): Type {
    optionsType: Type = typeof(object)
    assert MethodImplAttributeFacts.TryGetOptionsType(typeof(MethodImplAttribute), out optionsType)
    return optionsType
}

func MiafCodeType(): Type {
    codeTypeType: Type = typeof(object)
    assert MethodImplAttributeFacts.TryGetCodeTypeType(typeof(MethodImplAttribute), out codeTypeType)
    return codeTypeType
}

func MiafMember(name: string): Expression {
    return new MemberAccessExpression(new IdentifierExpression("MethodImplOptions", 1, 1), name, false, 1, 1)
}

func MiafEvaluate(expression: Expression): int {
    value := 0
    assert MethodImplAttributeFacts.TryEvaluate(expression, MiafOptions(), out value)
    return value
}

// ── identity ───────────────────────────────────────────────────────────────────────────────────

test "the attribute is recognised by its CLR identity and by nothing else" {
    assert MethodImplAttributeFacts.IsMethodImplAttributeType(typeof(MethodImplAttribute))
    assert !MethodImplAttributeFacts.IsMethodImplAttributeType(typeof(ObsoleteAttribute))
    assert !MethodImplAttributeFacts.IsMethodImplAttributeType(null)
}

// ── the two enums are read off the attribute, never looked up by name ───────────────────────────

test "MethodImplOptions is the attribute's own one-argument enum constructor parameter" {
    assert MiafOptions() == typeof(MethodImplOptions)
}

test "MethodCodeType is the type of the attribute's own named-argument field" {
    assert MiafCodeType() == typeof(MethodCodeType)
}

test "a type that is not the attribute yields neither enum" {
    ignoredOptions: Type = typeof(object)
    assert !MethodImplAttributeFacts.TryGetOptionsType(typeof(ObsoleteAttribute), out ignoredOptions)
    ignoredCodeType: Type = typeof(object)
    assert !MethodImplAttributeFacts.TryGetCodeTypeType(typeof(ObsoleteAttribute), out ignoredCodeType)
}

// ── evaluating an argument ─────────────────────────────────────────────────────────────────────

test "a member access evaluates to the option's own value" {
    assert MiafEvaluate(MiafMember("AggressiveInlining")) == Convert.ToInt32(MethodImplOptions.AggressiveInlining)
    assert MiafEvaluate(MiafMember("NoInlining")) == Convert.ToInt32(MethodImplOptions.NoInlining)
    assert MiafEvaluate(MiafMember("Synchronized")) == Convert.ToInt32(MethodImplOptions.Synchronized)
}

test "a '|' combination evaluates to both bits, at any nesting" {
    combination := new BinaryExpression(MiafMember("AggressiveInlining"), BinaryOperator.BitwiseOr, MiafMember("AggressiveOptimization"), 1, 1)
    assert MiafEvaluate(combination) == Convert.ToInt32(MethodImplOptions.AggressiveInlining | MethodImplOptions.AggressiveOptimization)

    three := new BinaryExpression(combination, BinaryOperator.BitwiseOr, MiafMember("NoInlining"), 1, 1)
    assert MiafEvaluate(three) == 768 + Convert.ToInt32(MethodImplOptions.NoInlining)
}

test "parentheses do not change the value" {
    assert MiafEvaluate(new ParenthesizedExpression(MiafMember("NoOptimization"), 1, 1)) == Convert.ToInt32(MethodImplOptions.NoOptimization)
}

test "an integer literal is taken at face value, undefined bits and all" {
    assert MiafEvaluate(new IntLiteralExpression("1024", 1, 1)) == 1024
    assert MiafEvaluate(new IntLiteralExpression("256", 1, 1)) == Convert.ToInt32(MethodImplOptions.AggressiveInlining)
}

test "a shape that is not a constant answers false rather than guessing" {
    value := 0
    assert !MethodImplAttributeFacts.TryEvaluate(new IdentifierExpression("someLocal", 1, 1), MiafOptions(), out value)
    assert !MethodImplAttributeFacts.TryEvaluate(MiafMember("NotAnOption"), MiafOptions(), out value)

    // `&` is not the combination operator, and admitting it would silently answer a question the
    // developer did not ask.
    conjunction := new BinaryExpression(MiafMember("NoInlining"), BinaryOperator.BitwiseAnd, MiafMember("Synchronized"), 1, 1)
    assert !MethodImplAttributeFacts.TryEvaluate(conjunction, MiafOptions(), out value)
}

// ── which bits the enum defines ────────────────────────────────────────────────────────────────

test "the defined mask is every option the enum declares, or-ed together" {
    mask := MethodImplAttributeFacts.DefinedMask(MiafOptions())
    assert (mask & Convert.ToInt32(MethodImplOptions.PreserveSig)) != 0
    assert (mask & Convert.ToInt32(MethodImplOptions.InternalCall)) != 0
    assert (mask & Convert.ToInt32(MethodImplOptions.AggressiveOptimization)) != 0
    assert (mask & 1024) == 0, "0x400 is not an option this runtime has"
}

test "undefined bits are named in hexadecimal, and a defined value names none" {
    mask := MethodImplAttributeFacts.DefinedMask(MiafOptions())
    assert MethodImplAttributeFacts.DescribeUndefinedBits(1024, mask) == "0x400"
    assert MethodImplAttributeFacts.DescribeUndefinedBits(1024 + 256, mask) == "0x400"
    assert MethodImplAttributeFacts.DescribeUndefinedBits(Convert.ToInt32(MethodImplOptions.AggressiveInlining), mask) == ""
    assert MethodImplAttributeFacts.DescribeUndefinedBits(0, mask) == ""
    assert MethodImplAttributeFacts.DescribeUndefinedBits(mask, mask) == ""
}

// ── what the type loader refuses ───────────────────────────────────────────────────────────────

test "Synchronized is refused on a value type's member and accepted on a reference type's" {
    synchronized := Convert.ToInt32(MethodImplOptions.Synchronized)
    assert MethodImplAttributeFacts.DescribeClrRefusal(synchronized, MiafOptions(), true, true) == "Synchronized"
    assert MethodImplAttributeFacts.DescribeClrRefusal(synchronized, MiafOptions(), false, true) == null
}

test "InternalCall and Unmanaged are refused on a member that has a body" {
    internalCall := Convert.ToInt32(MethodImplOptions.InternalCall)
    assert MethodImplAttributeFacts.DescribeClrRefusal(internalCall, MiafOptions(), false, true) == "InternalCall"
    assert MethodImplAttributeFacts.DescribeClrRefusal(internalCall, MiafOptions(), false, false) == null

    unmanaged := Convert.ToInt32(MethodImplOptions.Unmanaged)
    assert MethodImplAttributeFacts.DescribeClrRefusal(unmanaged, MiafOptions(), false, true) == "Unmanaged"
    assert MethodImplAttributeFacts.DescribeClrRefusal(unmanaged, MiafOptions(), false, false) == null
}

test "the options a member with a body may always carry are refused by nothing" {
    carryable := Convert.ToInt32(MethodImplOptions.AggressiveInlining | MethodImplOptions.AggressiveOptimization | MethodImplOptions.NoInlining | MethodImplOptions.NoOptimization | MethodImplOptions.PreserveSig | MethodImplOptions.ForwardRef)
    assert MethodImplAttributeFacts.DescribeClrRefusal(carryable, MiafOptions(), true, true) == null
    assert MethodImplAttributeFacts.DescribeClrRefusal(0, MiafOptions(), true, true) == null
}

test "the refusal carries its own reason and its own repair" {
    synchronizedReason := MethodImplAttributeFacts.DescribeRefusalReason("Synchronized")
    assert synchronizedReason.Contains("Synchronized Method in Value Type")
    assert MethodImplAttributeFacts.DescribeRefusalRepair("Synchronized").Contains("move it to a class")

    internalCallReason := MethodImplAttributeFacts.DescribeRefusalReason("InternalCall")
    assert internalCallReason.Contains("non-zero RVA")
    assert MethodImplAttributeFacts.DescribeRefusalRepair("InternalCall").Contains("Remove the option")
}
