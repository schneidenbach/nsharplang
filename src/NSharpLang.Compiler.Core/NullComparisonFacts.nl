namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast


// THE ONE PLACE THAT SAYS WHICH SIDE OF THE NULL-COMPARISON RULE OWNS A SHAPE.
//
// A comparison against `null` whose other side can never be null is reported by TWO owners, and they
// partition the shape rather than overlapping:
//
//   - the LINTER (NL003) claims the operand whose LITERAL KIND settles it — `3 == null` is wrong on
//     sight, with no types needed, which is why a purely syntactic rule can and should say so;
//   - the ANALYZER (NL202, `AnalyzerOperatorExpressions.TryReportNullComparisonWithValueType`) claims
//     everything else, because deciding that `count != null` is pointless needs `count`'s TYPE and
//     the linter has none.
//
// The partition is stated here, once, and both owners read it — the linter to choose its operand and
// the analyzer to stand down. That is what stops the two from double-reporting the same line, which
// is what a second copy of this list would eventually do.
class NullComparisonFacts {

    // The name of the scalar value type a LITERAL operand has, or nothing.
    //
    // A TOTAL four-way function over the literal kinds N# has, written that way on purpose: the C#
    // this replaced carried a fifth `_ => "value type"` arm the enclosing type test made unreachable,
    // a default that could never fire and whose presence suggested the list was open when it is
    // closed. A string literal is not here, because `"s" == null` is a legal, meaningful comparison.
    static func ValueTypeLiteralName(operand: Expression): string? {
        if operand is IntLiteralExpression {
            return "int"
        }

        if operand is FloatLiteralExpression {
            return "float"
        }

        if operand is CharLiteralExpression {
            return "char"
        }

        if operand is BoolLiteralExpression {
            return "bool"
        }

        return null
    }

    // Whether the linter's NL003 owns this operand, which is the analyzer's cue to stay silent.
    static func LinterOwnsOperand(operand: Expression): bool {
        return ValueTypeLiteralName(operand) != null
    }
}
