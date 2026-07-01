using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests;

public class OperatorFactsTests
{
    [Fact]
    public void OperatorFacts_ReturnsUnaryOperatorText()
    {
        Assert.Equal("-", OperatorFacts.GetUnaryText(UnaryOperator.Negate));
        Assert.Equal("!", OperatorFacts.GetUnaryText(UnaryOperator.Not));
        Assert.Equal("~", OperatorFacts.GetUnaryText(UnaryOperator.BitwiseNot));
        Assert.Equal("++", OperatorFacts.GetUnaryText(UnaryOperator.PreIncrement));
        Assert.Equal("--", OperatorFacts.GetUnaryText(UnaryOperator.PreDecrement));
        Assert.Equal("++", OperatorFacts.GetUnaryText(UnaryOperator.PostIncrement));
        Assert.Equal("--", OperatorFacts.GetUnaryText(UnaryOperator.PostDecrement));
        Assert.Equal("^", OperatorFacts.GetUnaryText(UnaryOperator.IndexFromEnd));
    }

    [Fact]
    public void OperatorFacts_ReturnsBinaryOperatorText()
    {
        Assert.Equal("+", OperatorFacts.GetBinaryText(BinaryOperator.Add));
        Assert.Equal("-", OperatorFacts.GetBinaryText(BinaryOperator.Subtract));
        Assert.Equal("*", OperatorFacts.GetBinaryText(BinaryOperator.Multiply));
        Assert.Equal("/", OperatorFacts.GetBinaryText(BinaryOperator.Divide));
        Assert.Equal("%", OperatorFacts.GetBinaryText(BinaryOperator.Modulo));
        Assert.Equal("==", OperatorFacts.GetBinaryText(BinaryOperator.Equal));
        Assert.Equal("!=", OperatorFacts.GetBinaryText(BinaryOperator.NotEqual));
        Assert.Equal("<", OperatorFacts.GetBinaryText(BinaryOperator.Less));
        Assert.Equal("<=", OperatorFacts.GetBinaryText(BinaryOperator.LessOrEqual));
        Assert.Equal(">", OperatorFacts.GetBinaryText(BinaryOperator.Greater));
        Assert.Equal(">=", OperatorFacts.GetBinaryText(BinaryOperator.GreaterOrEqual));
        Assert.Equal("&&", OperatorFacts.GetBinaryText(BinaryOperator.And));
        Assert.Equal("||", OperatorFacts.GetBinaryText(BinaryOperator.Or));
        Assert.Equal("&", OperatorFacts.GetBinaryText(BinaryOperator.BitwiseAnd));
        Assert.Equal("|", OperatorFacts.GetBinaryText(BinaryOperator.BitwiseOr));
        Assert.Equal("^", OperatorFacts.GetBinaryText(BinaryOperator.BitwiseXor));
        Assert.Equal("<<", OperatorFacts.GetBinaryText(BinaryOperator.LeftShift));
        Assert.Equal(">>", OperatorFacts.GetBinaryText(BinaryOperator.RightShift));
        Assert.Equal("??", OperatorFacts.GetBinaryText(BinaryOperator.NullCoalesce));
        Assert.Equal("..", OperatorFacts.GetBinaryText(BinaryOperator.Range));
    }

    [Fact]
    public void OperatorFacts_ReturnsAssignmentOperatorText()
    {
        Assert.Equal("=", OperatorFacts.GetAssignmentText(AssignmentOperator.Assign));
        Assert.Equal("+=", OperatorFacts.GetAssignmentText(AssignmentOperator.AddAssign));
        Assert.Equal("-=", OperatorFacts.GetAssignmentText(AssignmentOperator.SubtractAssign));
        Assert.Equal("*=", OperatorFacts.GetAssignmentText(AssignmentOperator.MultiplyAssign));
        Assert.Equal("/=", OperatorFacts.GetAssignmentText(AssignmentOperator.DivideAssign));
        Assert.Equal("??=", OperatorFacts.GetAssignmentText(AssignmentOperator.NullCoalesceAssign));
    }

    [Fact]
    public void OperatorFacts_ReturnsBinaryOperatorOverloadMetadata()
    {
        Assert.Equal("op_Addition", OperatorFacts.GetBinaryClrName(BinaryOperator.Add));
        Assert.Equal("+", OperatorFacts.GetBinarySymbol(BinaryOperator.Add));
        Assert.Equal("op_LessThanOrEqual", OperatorFacts.GetBinaryClrName(BinaryOperator.LessOrEqual));
        Assert.Equal("<=", OperatorFacts.GetBinarySymbol(BinaryOperator.LessOrEqual));

        Assert.Null(OperatorFacts.GetBinaryClrName(BinaryOperator.NullCoalesce));
        Assert.Null(OperatorFacts.GetBinarySymbol(BinaryOperator.NullCoalesce));
        Assert.Null(OperatorFacts.GetBinaryClrName(BinaryOperator.Range));
        Assert.Null(OperatorFacts.GetBinarySymbol(BinaryOperator.Range));
    }

    [Fact]
    public void OperatorFacts_ReturnsUnaryOperatorOverloadMetadata()
    {
        Assert.Equal("op_UnaryNegation", OperatorFacts.GetUnaryClrName(UnaryOperator.Negate));
        Assert.Equal("-", OperatorFacts.GetUnarySymbol(UnaryOperator.Negate));
        Assert.Equal("op_Increment", OperatorFacts.GetUnaryClrName(UnaryOperator.PostIncrement));
        Assert.Equal("++", OperatorFacts.GetUnarySymbol(UnaryOperator.PostIncrement));

        Assert.Null(OperatorFacts.GetUnaryClrName(UnaryOperator.IndexFromEnd));
        Assert.Null(OperatorFacts.GetUnarySymbol(UnaryOperator.IndexFromEnd));
    }

    [Fact]
    public void OperatorFacts_IdentifiesExpressionTreeSupportedOperators()
    {
        Assert.True(OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.Add));
        Assert.True(OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.And));
        Assert.True(OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.RightShift));
        Assert.False(OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.NullCoalesce));
        Assert.False(OperatorFacts.IsSupportedExpressionTreeBinaryOperator(BinaryOperator.Range));

        Assert.True(OperatorFacts.IsSupportedExpressionTreeUnaryOperator(UnaryOperator.Negate));
        Assert.True(OperatorFacts.IsSupportedExpressionTreeUnaryOperator(UnaryOperator.Not));
        Assert.False(OperatorFacts.IsSupportedExpressionTreeUnaryOperator(UnaryOperator.BitwiseNot));
        Assert.False(OperatorFacts.IsSupportedExpressionTreeUnaryOperator(UnaryOperator.IndexFromEnd));
    }
}
