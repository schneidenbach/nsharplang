using System;
using System.Collections.Generic;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

public class ParserTokenFactsTests
{
    [Fact]
    public void ParserTokenFacts_CanStartExpressionOwnsStatementOperandStarts()
    {
        AssertTokenSet(
            ParserTokenFacts.CanStartExpression,
            TokenType.Identifier,
            TokenType.IntLiteral,
            TokenType.FloatLiteral,
            TokenType.CharLiteral,
            TokenType.StringLiteral,
            TokenType.InterpolatedRawStringLiteral,
            TokenType.True,
            TokenType.False,
            TokenType.Null,
            TokenType.New,
            TokenType.Alloc,
            TokenType.Stackalloc,
            TokenType.Match,
            TokenType.This,
            TokenType.Base,
            TokenType.LeftParen,
            TokenType.LeftBracket,
            TokenType.Immutable,
            TokenType.DotDotDot,
            TokenType.Plus,
            TokenType.Minus,
            TokenType.Not,
            TokenType.BitwiseNot,
            TokenType.Increment,
            TokenType.Decrement,
            TokenType.Must,
            TokenType.Await,
            TokenType.Throw,
            TokenType.Checked,
            TokenType.Unchecked,
            TokenType.Typeof,
            TokenType.Nameof,
            TokenType.Sizeof,
            TokenType.Default);
    }

    [Fact]
    public void ParserTokenFacts_IsExpressionStartOwnsCastOperandStarts()
    {
        AssertTokenSet(
            ParserTokenFacts.IsExpressionStart,
            TokenType.Identifier,
            TokenType.IntLiteral,
            TokenType.FloatLiteral,
            TokenType.CharLiteral,
            TokenType.StringLiteral,
            TokenType.TripleQuoteStringLiteral,
            TokenType.InterpolatedRawStringLiteral,
            TokenType.True,
            TokenType.False,
            TokenType.Null,
            TokenType.Default,
            TokenType.New,
            TokenType.Alloc,
            TokenType.Stackalloc,
            TokenType.This,
            TokenType.Base,
            TokenType.LeftParen,
            TokenType.LeftBracket,
            TokenType.Immutable,
            TokenType.Plus,
            TokenType.Minus,
            TokenType.Not,
            TokenType.BitwiseNot,
            TokenType.Increment,
            TokenType.Decrement,
            TokenType.Must,
            TokenType.Await,
            TokenType.Throw,
            TokenType.Match,
            TokenType.Typeof,
            TokenType.Nameof,
            TokenType.Sizeof,
            TokenType.Checked,
            TokenType.Unchecked);
    }

    [Fact]
    public void ParserTokenFacts_CastOperandStartExcludesCollectionLiteralAmbiguity()
    {
        Assert.False(ParserTokenFacts.IsCastOperandStart(TokenType.LeftBracket));
        Assert.True(ParserTokenFacts.IsCastOperandStart(TokenType.Identifier));
        Assert.True(ParserTokenFacts.IsCastOperandStart(TokenType.TripleQuoteStringLiteral));
        Assert.False(ParserTokenFacts.IsCastOperandStart(TokenType.RightParen));
    }

    [Fact]
    public void ParserTokenFacts_OwnsParserRecoveryTokenSets()
    {
        AssertTokenSet(
            ParserTokenFacts.IsTypeDeclarationKeyword,
            TokenType.Class,
            TokenType.Struct,
            TokenType.Record,
            TokenType.Interface,
            TokenType.Union,
            TokenType.Enum,
            TokenType.Type);

        AssertTokenSet(
            ParserTokenFacts.IsDeclarationKeyword,
            TokenType.Func,
            TokenType.Class,
            TokenType.Struct,
            TokenType.Record,
            TokenType.Interface,
            TokenType.Union,
            TokenType.Enum,
            TokenType.Type,
            TokenType.Test,
            TokenType.Implicit,
            TokenType.Explicit,
            TokenType.Duck,
            TokenType.Ref);

        AssertTokenSet(
            ParserTokenFacts.IsModifierKeyword,
            TokenType.Static,
            TokenType.Internal,
            TokenType.Protected,
            TokenType.Virtual,
            TokenType.Override,
            TokenType.Abstract,
            TokenType.Sealed,
            TokenType.Readonly,
            TokenType.Partial,
            TokenType.Async,
            TokenType.File);

        AssertTokenSet(
            ParserTokenFacts.IsStatementStartKeyword,
            TokenType.Let,
            TokenType.Const,
            TokenType.Readonly,
            TokenType.If,
            TokenType.For,
            TokenType.Foreach,
            TokenType.While,
            TokenType.Return,
            TokenType.Yield,
            TokenType.Break,
            TokenType.Continue,
            TokenType.Throw,
            TokenType.Try,
            TokenType.Using,
            TokenType.Lock,
            TokenType.Switch,
            TokenType.Print,
            TokenType.Assert,
            TokenType.Unsafe,
            TokenType.Allow,
            TokenType.Func,
            TokenType.Semicolon,
            TokenType.LeftBrace);
    }

    [Fact]
    public void ParserTokenFacts_OwnsOperatorAndTerminatorTokenSets()
    {
        AssertTokenSet(
            ParserTokenFacts.IsAssignmentOperator,
            TokenType.Assign,
            TokenType.PlusAssign,
            TokenType.MinusAssign,
            TokenType.StarAssign,
            TokenType.SlashAssign,
            TokenType.QuestionQuestionAssign);

        AssertTokenSet(
            ParserTokenFacts.IsExpressionTerminator,
            TokenType.RightBrace,
            TokenType.RightParen,
            TokenType.RightBracket,
            TokenType.Comma,
            TokenType.Semicolon,
            TokenType.Eof);

        AssertTokenSet(
            ParserTokenFacts.IsTypeReferenceStart,
            TokenType.Identifier,
            TokenType.LeftParen,
            TokenType.BitwiseAnd);
    }

    private static void AssertTokenSet(Func<TokenType, bool> predicate, params TokenType[] expected)
    {
        var expectedSet = new HashSet<TokenType>(expected);
        foreach (TokenType tokenType in Enum.GetValues<TokenType>())
        {
            Assert.Equal(expectedSet.Contains(tokenType), predicate(tokenType));
        }
    }
}
