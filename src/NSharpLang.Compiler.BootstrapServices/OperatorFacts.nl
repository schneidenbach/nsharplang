namespace NSharpLang.Compiler

import NSharpLang.Compiler.Ast

public class OperatorFacts {
    public static func GetUnaryText(op: UnaryOperator): string {
        if op == UnaryOperator.Negate { return "-" }
        if op == UnaryOperator.Not { return "!" }
        if op == UnaryOperator.BitwiseNot { return "~" }
        if op == UnaryOperator.PreIncrement { return "++" }
        if op == UnaryOperator.PreDecrement { return "--" }
        if op == UnaryOperator.PostIncrement { return "++" }
        if op == UnaryOperator.PostDecrement { return "--" }
        if op == UnaryOperator.IndexFromEnd { return "^" }

        return "operator"
    }

    public static func GetBinaryText(op: BinaryOperator): string {
        if op == BinaryOperator.Add { return "+" }
        if op == BinaryOperator.Subtract { return "-" }
        if op == BinaryOperator.Multiply { return "*" }
        if op == BinaryOperator.Divide { return "/" }
        if op == BinaryOperator.Modulo { return "%" }
        if op == BinaryOperator.Equal { return "==" }
        if op == BinaryOperator.NotEqual { return "!=" }
        if op == BinaryOperator.Less { return "<" }
        if op == BinaryOperator.LessOrEqual { return "<=" }
        if op == BinaryOperator.Greater { return ">" }
        if op == BinaryOperator.GreaterOrEqual { return ">=" }
        if op == BinaryOperator.And { return "&&" }
        if op == BinaryOperator.Or { return "||" }
        if op == BinaryOperator.BitwiseAnd { return "&" }
        if op == BinaryOperator.BitwiseOr { return "|" }
        if op == BinaryOperator.BitwiseXor { return "^" }
        if op == BinaryOperator.LeftShift { return "<<" }
        if op == BinaryOperator.RightShift { return ">>" }
        if op == BinaryOperator.NullCoalesce { return "??" }
        if op == BinaryOperator.Range { return ".." }

        return "operator"
    }

    public static func GetAssignmentText(op: AssignmentOperator): string {
        if op == AssignmentOperator.Assign { return "=" }
        if op == AssignmentOperator.AddAssign { return "+=" }
        if op == AssignmentOperator.SubtractAssign { return "-=" }
        if op == AssignmentOperator.MultiplyAssign { return "*=" }
        if op == AssignmentOperator.DivideAssign { return "/=" }
        if op == AssignmentOperator.NullCoalesceAssign { return "??=" }

        return "operator"
    }
}
