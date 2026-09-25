namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast


// WHICH NULL CHECK IS POINTLESS — BOTH RULES, IN ONE PLACE, BECAUSE THEY PARTITION ONE QUESTION.
//
// NL003 and NL016 read the SAME shape: a `==`/`!=` comparison with `null` on one side. They differ
// only in what they say about the other side. NL003 answers for a scalar value-type literal, which
// cannot be null because of its TYPE; NL016 answers for a `new` expression or an array literal,
// which cannot be null because of what it just DID. The two sets are disjoint and the C# comment on
// NL016 said so in prose — "handled by NL003 instead, so we deliberately exclude them here to avoid
// double-reporting" — while nothing in the code or its tests could observe it. Here the shared
// half is written once as `CheckedOperand`, and the disjointness is a contract.
//
// THE GATES ARE NOT THE SAME AND THAT IS PRESERVED EXACTLY. NL016 refuses to speak unless its code
// is PRESENT in the configuration's severity table; NL003 has no such gate and relies on the
// linter's ordinary enabled-rule check. That asymmetry is inherited behaviour, not a tidy design:
// NL016 is the newer rule and was given an explicit opt-in. Both are stated below rather than
// smoothed over, because smoothing either one changes what a real project sees.
//
// WHERE THE SQUIGGLE GOES IS ALSO THE RULE'S DECISION: both point at the OPERAND, not at the whole
// condition, so `if (count != null)` underlines `count` and not `count != null`.
class LinterNullCheckPolicy {

    // The shape both rules read. Answers with the operand that is NOT the null literal, or nothing
    // when this is not a null comparison at all.
    //
    // `null == null` answers with the LEFT operand — which is itself a null literal, and therefore
    // neither a scalar literal nor a `new`, so both rules stay silent. That is the pre-existing
    // behaviour of the right-first test and it is kept.
    static func CheckedOperand(condition: Expression): Expression? {
        binary := condition as BinaryExpression
        if binary == null {
            return null
        }

        if binary.Operator != BinaryOperator.NotEqual && binary.Operator != BinaryOperator.Equal {
            return null
        }

        if binary.Right is NullLiteralExpression {
            return binary.Left
        }

        if binary.Left is NullLiteralExpression {
            return binary.Right
        }

        return null
    }

    // NL003's half: the name of the scalar value type a literal operand has, or nothing.
    //
    // The list itself lives on `NullComparisonFacts`, because the ANALYZER reads the same list to
    // decide when to stand down — its own rule covers every non-literal operand, and two copies of
    // this list would eventually drift into a double report on one line.
    static func ValueTypeLiteralName(operand: Expression): string? {
        return NullComparisonFacts.ValueTypeLiteralName(operand)
    }

    // NL016's half: an expression that was JUST created and therefore cannot be null.
    static func IsFreshlyCreated(operand: Expression): bool {
        if operand is NewExpression {
            return true
        }

        return operand is ArrayLiteralExpression
    }

    // NL003. No configuration gate beyond the severity lookup.
    static func UnnecessaryNullCheck(condition: Expression, config: LinterConfig): LinterRuleFinding? {
        operand := CheckedOperand(condition)
        if operand == null {
            return null
        }

        typeName := ValueTypeLiteralName(operand)
        if typeName == null {
            return null
        }

        return new LinterRuleFinding("NL003", "This null check is unnecessary — '" + typeName + "' is a value type and can never be null", "You can safely remove this null check", config.GetSeverity("NL003"), operand.Line, operand.Column)
    }

    // NL016. Silent unless the rule's code is present in the configuration's severity table.
    static func RedundantNullCheck(condition: Expression, config: LinterConfig): LinterRuleFinding? {
        if !config.RuleSeverities.ContainsKey("NL016") {
            return null
        }

        operand := CheckedOperand(condition)
        if operand == null {
            return null
        }

        if !IsFreshlyCreated(operand) {
            return null
        }

        // The verb names what the comparison ALWAYS evaluates to, which is the opposite way round
        // for the two operators: a `!= null` on something that cannot be null is always true.
        binary := condition as BinaryExpression
        verb := "always false"
        if binary != null && binary.Operator == BinaryOperator.NotEqual {
            verb = "always true"
        }

        return new LinterRuleFinding("NL016", "This null check is redundant — the expression was just created and can never be null (this is " + verb + ")", "Remove the null check — the value cannot be null", config.GetSeverity("NL016"), operand.Line, operand.Column)
    }
}
