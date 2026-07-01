using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

public class ParserLiteralFactsTests
{
    [Theory]
    [InlineData("\"Ada\"", true)]
    [InlineData("\"Ada", false)]
    [InlineData("\"Ada\\\"", false)]
    [InlineData("\"Ada\\\\\"", true)]
    [InlineData("$\"{name}\"", true)]
    [InlineData("$\"{name}", false)]
    [InlineData("identifier", true)]
    public void ParserLiteralFacts_ClassifiesCompleteStringLiterals(string value, bool expected)
    {
        Assert.Equal(expected, ParserLiteralFacts.IsCompleteStringLiteral(value));
    }

    [Theory]
    [InlineData("'a'", true)]
    [InlineData("'\\n'", true)]
    [InlineData("''", false)]
    [InlineData("'ab'", false)]
    [InlineData("'a", false)]
    [InlineData("a'", false)]
    public void ParserLiteralFacts_ClassifiesCompleteCharLiterals(string value, bool expected)
    {
        Assert.Equal(expected, ParserLiteralFacts.IsCompleteCharLiteral(value));
    }

    [Theory]
    [InlineData("value:N2", 5)]
    [InlineData("value ?? fallback:N2", 17)]
    [InlineData("ok ? yes : no", -1)]
    [InlineData("ok ? yes : no:N2", 13)]
    [InlineData("Format(value: 1):N2", 16)]
    [InlineData("items[0:1]:N2", 10)]
    [InlineData("new { A: 1 }:N2", 12)]
    [InlineData("\"{not:format}\":N2", 14)]
    [InlineData("value?.Name:N2", 11)]
    public void ParserLiteralFacts_FindsOnlyTopLevelFormatSpecifierColon(string expression, int expected)
    {
        Assert.Equal(expected, ParserLiteralFacts.FindFormatSpecifierColon(expression));
    }
}
