namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast

class OperatorFacts {
    static func GetUnaryText(op: UnaryOperator): string {
        if op == UnaryOperator.Negate {
            return "-"
        }
        if op == UnaryOperator.Not {
            return "!"
        }
        if op == UnaryOperator.BitwiseNot {
            return "~"
        }
        if op == UnaryOperator.PreIncrement {
            return "++"
        }
        if op == UnaryOperator.PreDecrement {
            return "--"
        }
        if op == UnaryOperator.PostIncrement {
            return "++"
        }
        if op == UnaryOperator.PostDecrement {
            return "--"
        }
        if op == UnaryOperator.IndexFromEnd {
            return "^"
        }

        return "operator"
    }

    static func GetBinaryText(op: BinaryOperator): string {
        if op == BinaryOperator.Add {
            return "+"
        }
        if op == BinaryOperator.Subtract {
            return "-"
        }
        if op == BinaryOperator.Multiply {
            return "*"
        }
        if op == BinaryOperator.Divide {
            return "/"
        }
        if op == BinaryOperator.Modulo {
            return "%"
        }
        if op == BinaryOperator.Equal {
            return "=="
        }
        if op == BinaryOperator.NotEqual {
            return "!="
        }
        if op == BinaryOperator.Less {
            return "<"
        }
        if op == BinaryOperator.LessOrEqual {
            return "<="
        }
        if op == BinaryOperator.Greater {
            return ">"
        }
        if op == BinaryOperator.GreaterOrEqual {
            return ">="
        }
        if op == BinaryOperator.And {
            return "&&"
        }
        if op == BinaryOperator.Or {
            return "||"
        }
        if op == BinaryOperator.BitwiseAnd {
            return "&"
        }
        if op == BinaryOperator.BitwiseOr {
            return "|"
        }
        if op == BinaryOperator.BitwiseXor {
            return "^"
        }
        if op == BinaryOperator.LeftShift {
            return "<<"
        }
        if op == BinaryOperator.RightShift {
            return ">>"
        }
        if op == BinaryOperator.NullCoalesce {
            return "??"
        }
        if op == BinaryOperator.Range {
            return ".."
        }

        return "operator"
    }

    static func GetAssignmentText(op: AssignmentOperator): string {
        if op == AssignmentOperator.Assign {
            return "="
        }
        if op == AssignmentOperator.AddAssign {
            return "+="
        }
        if op == AssignmentOperator.SubtractAssign {
            return "-="
        }
        if op == AssignmentOperator.MultiplyAssign {
            return "*="
        }
        if op == AssignmentOperator.DivideAssign {
            return "/="
        }
        if op == AssignmentOperator.NullCoalesceAssign {
            return "??="
        }

        return "operator"
    }

    static func GetRequiredBinaryText(op: BinaryOperator): string {
        text := GetBinaryText(op)
        if text != "operator" {
            return text
        }

        throw new InvalidOperationException("Formatter does not handle binary operator.")
    }

    static func GetRequiredUnaryText(op: UnaryOperator): string {
        text := GetUnaryText(op)
        if text != "operator" {
            return text
        }

        throw new InvalidOperationException("Formatter does not handle unary operator.")
    }

    static func GetRequiredAssignmentText(op: AssignmentOperator): string {
        text := GetAssignmentText(op)
        if text != "operator" {
            return text
        }

        throw new InvalidOperationException("Formatter does not handle assignment operator.")
    }

    static func GetBinaryClrName(op: BinaryOperator): string? {
        if op == BinaryOperator.Add {
            return "op_Addition"
        }
        if op == BinaryOperator.Subtract {
            return "op_Subtraction"
        }
        if op == BinaryOperator.Multiply {
            return "op_Multiply"
        }
        if op == BinaryOperator.Divide {
            return "op_Division"
        }
        if op == BinaryOperator.Modulo {
            return "op_Modulus"
        }
        if op == BinaryOperator.Equal {
            return "op_Equality"
        }
        if op == BinaryOperator.NotEqual {
            return "op_Inequality"
        }
        if op == BinaryOperator.BitwiseAnd {
            return "op_BitwiseAnd"
        }
        if op == BinaryOperator.BitwiseOr {
            return "op_BitwiseOr"
        }
        if op == BinaryOperator.BitwiseXor {
            return "op_ExclusiveOr"
        }
        if op == BinaryOperator.LeftShift {
            return "op_LeftShift"
        }
        if op == BinaryOperator.RightShift {
            return "op_RightShift"
        }
        if op == BinaryOperator.Less {
            return "op_LessThan"
        }
        if op == BinaryOperator.Greater {
            return "op_GreaterThan"
        }
        if op == BinaryOperator.LessOrEqual {
            return "op_LessThanOrEqual"
        }
        if op == BinaryOperator.GreaterOrEqual {
            return "op_GreaterThanOrEqual"
        }

        return null
    }

    static func GetBinarySymbol(op: BinaryOperator): string? {
        if op == BinaryOperator.Add {
            return "+"
        }
        if op == BinaryOperator.Subtract {
            return "-"
        }
        if op == BinaryOperator.Multiply {
            return "*"
        }
        if op == BinaryOperator.Divide {
            return "/"
        }
        if op == BinaryOperator.Modulo {
            return "%"
        }
        if op == BinaryOperator.Equal {
            return "=="
        }
        if op == BinaryOperator.NotEqual {
            return "!="
        }
        if op == BinaryOperator.BitwiseAnd {
            return "&"
        }
        if op == BinaryOperator.BitwiseOr {
            return "|"
        }
        if op == BinaryOperator.BitwiseXor {
            return "^"
        }
        if op == BinaryOperator.LeftShift {
            return "<<"
        }
        if op == BinaryOperator.RightShift {
            return ">>"
        }
        if op == BinaryOperator.Less {
            return "<"
        }
        if op == BinaryOperator.Greater {
            return ">"
        }
        if op == BinaryOperator.LessOrEqual {
            return "<="
        }
        if op == BinaryOperator.GreaterOrEqual {
            return ">="
        }

        return null
    }

    static func GetUnaryClrName(op: UnaryOperator): string? {
        if op == UnaryOperator.Negate {
            return "op_UnaryNegation"
        }
        if op == UnaryOperator.Not {
            return "op_LogicalNot"
        }
        if op == UnaryOperator.BitwiseNot {
            return "op_OnesComplement"
        }
        if op == UnaryOperator.PreIncrement {
            return "op_Increment"
        }
        if op == UnaryOperator.PostIncrement {
            return "op_Increment"
        }
        if op == UnaryOperator.PreDecrement {
            return "op_Decrement"
        }
        if op == UnaryOperator.PostDecrement {
            return "op_Decrement"
        }

        return null
    }

    static func GetUnarySymbol(op: UnaryOperator): string? {
        if op == UnaryOperator.Negate {
            return "-"
        }
        if op == UnaryOperator.Not {
            return "!"
        }
        if op == UnaryOperator.BitwiseNot {
            return "~"
        }
        if op == UnaryOperator.PreIncrement {
            return "++"
        }
        if op == UnaryOperator.PostIncrement {
            return "++"
        }
        if op == UnaryOperator.PreDecrement {
            return "--"
        }
        if op == UnaryOperator.PostDecrement {
            return "--"
        }

        return null
    }

    static func IsSupportedExpressionTreeBinaryOperator(op: BinaryOperator): bool {
        if op == BinaryOperator.Add {
            return true
        }
        if op == BinaryOperator.Subtract {
            return true
        }
        if op == BinaryOperator.Multiply {
            return true
        }
        if op == BinaryOperator.Divide {
            return true
        }
        if op == BinaryOperator.Modulo {
            return true
        }
        if op == BinaryOperator.Equal {
            return true
        }
        if op == BinaryOperator.NotEqual {
            return true
        }
        if op == BinaryOperator.Less {
            return true
        }
        if op == BinaryOperator.LessOrEqual {
            return true
        }
        if op == BinaryOperator.Greater {
            return true
        }
        if op == BinaryOperator.GreaterOrEqual {
            return true
        }
        if op == BinaryOperator.And {
            return true
        }
        if op == BinaryOperator.Or {
            return true
        }
        if op == BinaryOperator.BitwiseAnd {
            return true
        }
        if op == BinaryOperator.BitwiseOr {
            return true
        }
        if op == BinaryOperator.BitwiseXor {
            return true
        }
        if op == BinaryOperator.LeftShift {
            return true
        }
        if op == BinaryOperator.RightShift {
            return true
        }

        return false
    }

    static func IsSupportedExpressionTreeUnaryOperator(op: UnaryOperator): bool {
        if op == UnaryOperator.Not {
            return true
        }
        if op == UnaryOperator.Negate {
            return true
        }

        return false
    }

    static func TryGetCompoundAssignmentBinaryOperator(op: AssignmentOperator, out binaryOperator: BinaryOperator): bool {
        if op == AssignmentOperator.AddAssign {
            binaryOperator = BinaryOperator.Add
            return true
        }

        if op == AssignmentOperator.SubtractAssign {
            binaryOperator = BinaryOperator.Subtract
            return true
        }

        if op == AssignmentOperator.MultiplyAssign {
            binaryOperator = BinaryOperator.Multiply
            return true
        }

        if op == AssignmentOperator.DivideAssign {
            binaryOperator = BinaryOperator.Divide
            return true
        }

        binaryOperator = BinaryOperator.Add
        return false
    }
}
