namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// CONTRACTS FOR WHICH NULL CHECK IS POINTLESS (task 019 slice 9). These came out of `Linter.cs`
// with `CheckUnnecessaryNullCheck` (NL003) and `CheckRedundantNullCheckOnNewOrLiteral` (NL016) —
// two methods that read the same shape and split what they said about it.
//
// THE DISJOINTNESS WAS PROSE AND IS NOW A CONTRACT. NL016's comment claimed scalar literals were
// "handled by NL003 instead, so we deliberately exclude them here to avoid double-reporting", and
// nothing anywhere could observe it. The last section asks both rules about the same operand list
// and asserts that no operand makes both speak — which is what "avoid double-reporting" actually
// means, and which would have failed silently if either list had gained a shared kind.
//
// THE GATES ARE ASYMMETRIC AND THAT ASYMMETRY IS INHERITED. NL016 is silent unless its code is
// PRESENT in the configuration's severity table; NL003 has no such gate. Both are asserted.
func LncpConfig(): LinterConfig {
    return LinterConfig.Default()
}

// A configuration with NL016 and NL020 REMOVED from the severity table — the shape a project that
// has never configured them has, and the shape their presence gate is about.
func LncpConfigWithout(ruleCode: string): LinterConfig {
    config := LinterConfig.Default()
    removed: object = 0
    config.RuleSeverities.Remove(ruleCode, out removed)
    return config
}

func LncpInt(): Expression {
    return new IntLiteralExpression("1", 3, 7)
}

func LncpFloat(): Expression {
    return new FloatLiteralExpression("1.5", 3, 7)
}

func LncpChar(): Expression {
    return new CharLiteralExpression("c", 3, 7)
}

func LncpBool(): Expression {
    return new BoolLiteralExpression(true, 3, 7)
}

func LncpNull(): Expression {
    return new NullLiteralExpression(3, 7)
}

func LncpIdentifier(): Expression {
    return new IdentifierExpression("value", 3, 7)
}

func LncpString(): Expression {
    return new StringLiteralExpression("\"s\"", 3, 7)
}

func LncpNew(): Expression {
    arguments := new List<Argument>()
    created := new NewExpression(new SimpleTypeReference("Widget", 3, 7), arguments, null, 3, 7)
    return created
}

func LncpArray(): Expression {
    elements := new List<Expression>()
    literal := new ArrayLiteralExpression(elements, false, 3, 7)
    return literal
}

func LncpBinary(left: Expression, op: BinaryOperator, right: Expression): Expression {
    return new BinaryExpression(left, op, right, 1, 1)
}

func LncpNotEqualNull(operand: Expression): Expression {
    return LncpBinary(operand, BinaryOperator.NotEqual, LncpNull())
}

func LncpEqualNull(operand: Expression): Expression {
    return LncpBinary(operand, BinaryOperator.Equal, LncpNull())
}

// Every operand kind the two rules are ever asked about, plus the kinds neither claims.
func LncpAllOperands(): List<Expression> {
    operands := new List<Expression>()
    operands.Add(LncpInt())
    operands.Add(LncpFloat())
    operands.Add(LncpChar())
    operands.Add(LncpBool())
    operands.Add(LncpNew())
    operands.Add(LncpArray())
    operands.Add(LncpIdentifier())
    operands.Add(LncpString())
    operands.Add(LncpNull())
    return operands
}

// ── the shape both rules read ────────────────────────────────────────────────────────────────

test "the checked operand is the one that is NOT the null literal, in either order" {
    left := LncpInt()
    assert LinterNullCheckPolicy.CheckedOperand(LncpBinary(left, BinaryOperator.NotEqual, LncpNull())) == left

    right := LncpInt()
    assert LinterNullCheckPolicy.CheckedOperand(LncpBinary(LncpNull(), BinaryOperator.Equal, right)) == right
}

test "only equality and inequality are null CHECKS" {
    assert LinterNullCheckPolicy.CheckedOperand(LncpBinary(LncpInt(), BinaryOperator.NotEqual, LncpNull())) != null
    assert LinterNullCheckPolicy.CheckedOperand(LncpBinary(LncpInt(), BinaryOperator.Equal, LncpNull())) != null
    assert LinterNullCheckPolicy.CheckedOperand(LncpBinary(LncpInt(), BinaryOperator.Add, LncpNull())) == null
    assert LinterNullCheckPolicy.CheckedOperand(LncpBinary(LncpInt(), BinaryOperator.Less, LncpNull())) == null
    assert LinterNullCheckPolicy.CheckedOperand(LncpBinary(LncpInt(), BinaryOperator.And, LncpNull())) == null
}

test "a comparison with no null on either side is not a null check" {
    assert LinterNullCheckPolicy.CheckedOperand(LncpBinary(LncpInt(), BinaryOperator.NotEqual, LncpIdentifier())) == null
}

test "something that is not a binary expression at all is not a null check" {
    assert LinterNullCheckPolicy.CheckedOperand(LncpIdentifier()) == null
    assert LinterNullCheckPolicy.CheckedOperand(LncpNull()) == null
}

test "null == null answers with the LEFT operand, and both rules then stay silent" {
    // The right-hand side is tested first, so `null == null` yields the left — itself a null
    // literal, which is neither a scalar literal nor freshly created. Pre-existing behaviour,
    // recorded because it is the one case where the answer is a null literal.
    condition := LncpBinary(LncpNull(), BinaryOperator.Equal, LncpNull())
    assert LinterNullCheckPolicy.CheckedOperand(condition) != null
    assert LinterNullCheckPolicy.UnnecessaryNullCheck(condition, LncpConfig()) == null
    assert LinterNullCheckPolicy.RedundantNullCheck(condition, LncpConfig()) == null
}

// ── NL003 ────────────────────────────────────────────────────────────────────────────────────

test "the four scalar literal kinds each name their own type" {
    assert LinterNullCheckPolicy.ValueTypeLiteralName(LncpInt()) == "int"
    assert LinterNullCheckPolicy.ValueTypeLiteralName(LncpFloat()) == "float"
    assert LinterNullCheckPolicy.ValueTypeLiteralName(LncpChar()) == "char"
    assert LinterNullCheckPolicy.ValueTypeLiteralName(LncpBool()) == "bool"
}

test "the four are ALL of them — the list is closed, and nothing else names a value type" {
    assert LinterNullCheckPolicy.ValueTypeLiteralName(LncpIdentifier()) == null
    assert LinterNullCheckPolicy.ValueTypeLiteralName(LncpString()) == null
    assert LinterNullCheckPolicy.ValueTypeLiteralName(LncpNull()) == null
    assert LinterNullCheckPolicy.ValueTypeLiteralName(LncpNew()) == null
    assert LinterNullCheckPolicy.ValueTypeLiteralName(LncpArray()) == null
}

test "NL003 reports the operand's position, not the condition's" {
    // The operand is built at 3:7 and the binary at 1:1. Underlining the whole condition rather
    // than the value-type operand is the mistake this asserts against.
    finding := LinterNullCheckPolicy.UnnecessaryNullCheck(LncpNotEqualNull(LncpInt()), LncpConfig())
    assert finding != null
    assert finding.Line == 3
    assert finding.Column == 7
}

test "NL003's message names the type, and its code and suggestion are fixed" {
    finding := LinterNullCheckPolicy.UnnecessaryNullCheck(LncpNotEqualNull(LncpChar()), LncpConfig())
    assert finding != null
    assert finding.Code == "NL003"
    assert finding.Message == "This null check is unnecessary — 'char' is a value type and can never be null"
    assert finding.Suggestion == "You can safely remove this null check"
}

test "NL003 speaks for both operators and for either operand order" {
    assert LinterNullCheckPolicy.UnnecessaryNullCheck(LncpNotEqualNull(LncpInt()), LncpConfig()) != null
    assert LinterNullCheckPolicy.UnnecessaryNullCheck(LncpEqualNull(LncpInt()), LncpConfig()) != null
    assert LinterNullCheckPolicy.UnnecessaryNullCheck(LncpBinary(LncpNull(), BinaryOperator.NotEqual, LncpInt()), LncpConfig()) != null
}

test "NL003 has NO presence gate — it speaks even with its code out of the severity table" {
    // The asymmetry with NL016 below is the point. Removing NL003 from the table does not silence
    // the rule; only the linter's ordinary enabled-rule check does.
    assert LinterNullCheckPolicy.UnnecessaryNullCheck(LncpNotEqualNull(LncpInt()), LncpConfigWithout("NL003")) != null
}

// ── NL016 ────────────────────────────────────────────────────────────────────────────────────

test "a new expression and an array literal are freshly created; nothing else is" {
    assert LinterNullCheckPolicy.IsFreshlyCreated(LncpNew())
    assert LinterNullCheckPolicy.IsFreshlyCreated(LncpArray())
    assert !LinterNullCheckPolicy.IsFreshlyCreated(LncpInt())
    assert !LinterNullCheckPolicy.IsFreshlyCreated(LncpString())
    assert !LinterNullCheckPolicy.IsFreshlyCreated(LncpIdentifier())
    assert !LinterNullCheckPolicy.IsFreshlyCreated(LncpNull())
}

test "NL016's verb follows the OPERATOR, which is the opposite way round for the two" {
    notEqual := LinterNullCheckPolicy.RedundantNullCheck(LncpNotEqualNull(LncpNew()), LncpConfig())
    assert notEqual != null
    assert notEqual.Message == "This null check is redundant — the expression was just created and can never be null (this is always true)"

    equal := LinterNullCheckPolicy.RedundantNullCheck(LncpEqualNull(LncpNew()), LncpConfig())
    assert equal != null
    assert equal.Message == "This null check is redundant — the expression was just created and can never be null (this is always false)"
}

test "NL016's code, suggestion and position" {
    finding := LinterNullCheckPolicy.RedundantNullCheck(LncpNotEqualNull(LncpArray()), LncpConfig())
    assert finding != null
    assert finding.Code == "NL016"
    assert finding.Suggestion == "Remove the null check — the value cannot be null"
    assert finding.Line == 3
    assert finding.Column == 7
}

test "NL016 IS gated on presence — take its code out of the table and it says nothing at all" {
    assert LinterNullCheckPolicy.RedundantNullCheck(LncpNotEqualNull(LncpNew()), LncpConfig()) != null
    assert LinterNullCheckPolicy.RedundantNullCheck(LncpNotEqualNull(LncpNew()), LncpConfigWithout("NL016")) == null
}

test "the gate is checked BEFORE the shape, so a gated-off NL016 is silent about everything" {
    gated := LncpConfigWithout("NL016")
    operands := LncpAllOperands()
    index := 0
    while index < operands.Count {
        assert LinterNullCheckPolicy.RedundantNullCheck(LncpNotEqualNull(operands[index]), gated) == null
        index = index + 1
    }
}

// ── the two rules PARTITION the question ─────────────────────────────────────────────────────

test "no operand makes both rules speak, and the ones that make neither speak are named" {
    config := LncpConfig()
    operands := LncpAllOperands()

    both := 0
    onlyNl003 := 0
    onlyNl016 := 0
    neither := 0

    index := 0
    while index < operands.Count {
        condition := LncpNotEqualNull(operands[index])
        saysNl003 := LinterNullCheckPolicy.UnnecessaryNullCheck(condition, config) != null
        saysNl016 := LinterNullCheckPolicy.RedundantNullCheck(condition, config) != null

        if saysNl003 && saysNl016 {
            both = both + 1
        } else if saysNl003 {
            onlyNl003 = onlyNl003 + 1
        } else if saysNl016 {
            onlyNl016 = onlyNl016 + 1
        } else {
            neither = neither + 1
        }

        index = index + 1
    }

    // The disjointness, which is what "avoid double-reporting" means.
    assert both == 0

    // Non-vacuous in both directions: four scalar literals, two freshly-created shapes, and three
    // operands neither rule claims (an identifier, a string literal and a null literal).
    assert onlyNl003 == 4
    assert onlyNl016 == 2
    assert neither == 3
    assert both + onlyNl003 + onlyNl016 + neither == operands.Count
}

test "the two rules agree about the SHAPE even where they disagree about the operand" {
    // Both go through the same `CheckedOperand`, so a condition that is not a null check silences
    // both — for every operator and every operand.
    config := LncpConfig()
    operands := LncpAllOperands()
    index := 0
    while index < operands.Count {
        notACheck := LncpBinary(operands[index], BinaryOperator.Add, LncpNull())
        assert LinterNullCheckPolicy.UnnecessaryNullCheck(notACheck, config) == null
        assert LinterNullCheckPolicy.RedundantNullCheck(notACheck, config) == null
        index = index + 1
    }
}
