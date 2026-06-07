using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Deterministic unit tests for the conditional-compilation token-stream preprocessor
/// (<c>#if</c>/<c>#elif</c>/<c>#else</c>/<c>#endif</c>). These run the lexer over a source
/// snippet, apply <see cref="Preprocessor.Process"/> with an explicit defined-symbol set,
/// and assert which branch tokens survive — independent of the build configuration.
/// </summary>
public class PreprocessorTests
{
    private static (List<Token> Tokens, List<CompilerError> Errors) Preprocess(string source, params string[] defines)
    {
        var tokens = new Lexer(source, "test.nl").Tokenize();
        var errors = new List<CompilerError>();
        var symbols = new HashSet<string>(defines, System.StringComparer.Ordinal);
        var result = Preprocessor.Process(tokens, symbols, "test.nl", errors);
        return (result, errors);
    }

    private static bool HasIdentifier(IEnumerable<Token> tokens, string name)
        => tokens.Any(t => t.Type == TokenType.Identifier && t.Value == name);

    private const string TwoBranch = """
        #if FEATURE_X
        let value = featureOnValue
        #else
        let value = featureOffValue
        #endif
        """;

    [Fact]
    public void IfBranch_Included_WhenSymbolDefined()
    {
        var (tokens, errors) = Preprocess(TwoBranch, "FEATURE_X");

        Assert.Empty(errors);
        Assert.True(HasIdentifier(tokens, "featureOnValue"));
        Assert.False(HasIdentifier(tokens, "featureOffValue"));
    }

    [Fact]
    public void ElseBranch_Included_WhenSymbolUndefined()
    {
        var (tokens, errors) = Preprocess(TwoBranch); // FEATURE_X not defined

        Assert.Empty(errors);
        Assert.False(HasIdentifier(tokens, "featureOnValue"));
        Assert.True(HasIdentifier(tokens, "featureOffValue"));
    }

    [Fact]
    public void DebugSymbol_IsCaseSensitive()
    {
        const string source = """
            #if DEBUG
            let x = debugBody
            #endif
            """;

        Assert.True(HasIdentifier(Preprocess(source, "DEBUG").Tokens, "debugBody"));
        Assert.False(HasIdentifier(Preprocess(source, "debug").Tokens, "debugBody"));
        Assert.False(HasIdentifier(Preprocess(source).Tokens, "debugBody"));
    }

    [Fact]
    public void ConditionalDirectiveTokens_AreRemoved()
    {
        var (tokens, _) = Preprocess(TwoBranch, "FEATURE_X");

        // #if/#else/#endif are resolved away; none survive as directive tokens.
        Assert.DoesNotContain(tokens, t => t.Type == TokenType.PreprocessorDirective);
    }

    [Fact]
    public void RegionDirectives_ArePassedThrough()
    {
        const string source = """
            #region Helpers
            let x = inRegion
            #endregion
            """;

        var (tokens, errors) = Preprocess(source);

        Assert.Empty(errors);
        Assert.True(HasIdentifier(tokens, "inRegion"));
        var directives = tokens.Where(t => t.Type == TokenType.PreprocessorDirective).Select(t => t.Value).ToList();
        Assert.Contains("#region Helpers", directives);
        Assert.Contains("#endregion", directives);
    }

    [Fact]
    public void RegionInsideExcludedBranch_IsDropped()
    {
        const string source = """
            #if FEATURE_X
            #region OnlyWhenOn
            let x = inRegion
            #endregion
            #endif
            """;

        var (tokens, _) = Preprocess(source); // FEATURE_X undefined

        Assert.DoesNotContain(tokens, t => t.Type == TokenType.PreprocessorDirective);
        Assert.False(HasIdentifier(tokens, "inRegion"));
    }

    [Fact]
    public void Elif_SelectsFirstMatchingBranch_AndIsMutuallyExclusive()
    {
        const string source = """
            #if A
            let v = branchA
            #elif B
            let v = branchB
            #elif C
            let v = branchC
            #else
            let v = branchElse
            #endif
            """;

        // B and C both defined: only the first matching #elif (B) is taken.
        var (tokens, errors) = Preprocess(source, "B", "C");

        Assert.Empty(errors);
        Assert.False(HasIdentifier(tokens, "branchA"));
        Assert.True(HasIdentifier(tokens, "branchB"));
        Assert.False(HasIdentifier(tokens, "branchC"));
        Assert.False(HasIdentifier(tokens, "branchElse"));
    }

    [Fact]
    public void Else_IsTaken_WhenNoBranchMatches()
    {
        const string source = """
            #if A
            let v = branchA
            #elif B
            let v = branchB
            #else
            let v = branchElse
            #endif
            """;

        var (tokens, _) = Preprocess(source); // neither A nor B defined

        Assert.False(HasIdentifier(tokens, "branchA"));
        Assert.False(HasIdentifier(tokens, "branchB"));
        Assert.True(HasIdentifier(tokens, "branchElse"));
    }

    [Theory]
    [InlineData("!A", new string[0], true)]
    [InlineData("!A", new[] { "A" }, false)]
    [InlineData("A && B", new[] { "A", "B" }, true)]
    [InlineData("A && B", new[] { "A" }, false)]
    [InlineData("A || B", new[] { "B" }, true)]
    [InlineData("A || B", new string[0], false)]
    [InlineData("(A || B) && !C", new[] { "A" }, true)]
    [InlineData("(A || B) && !C", new[] { "A", "C" }, false)]
    [InlineData("true", new string[0], true)]
    [InlineData("false", new string[0], false)]
    public void BooleanExpressions_EvaluateCorrectly(string condition, string[] defines, bool expectIncluded)
    {
        var source = $"""
            #if {condition}
            let x = body
            #endif
            """;

        var (tokens, errors) = Preprocess(source, defines);

        Assert.Empty(errors);
        Assert.Equal(expectIncluded, HasIdentifier(tokens, "body"));
    }

    [Fact]
    public void NestedConditional_UnderExcludedOuterBranch_IsExcluded()
    {
        const string source = """
            #if OUTER
            let a = outerBody
            #if INNER
            let b = innerBody
            #endif
            #endif
            """;

        // INNER is defined but OUTER is not — nothing should survive, and the
        // inner condition must still pair correctly so no error is raised.
        var (tokens, errors) = Preprocess(source, "INNER");

        Assert.Empty(errors);
        Assert.False(HasIdentifier(tokens, "outerBody"));
        Assert.False(HasIdentifier(tokens, "innerBody"));
    }

    [Fact]
    public void MalformedCondition_ReportsError_AndExcludesBranch()
    {
        const string source = """
            #if A &&
            let x = body
            #endif
            """;

        var (tokens, errors) = Preprocess(source, "A");

        Assert.False(HasIdentifier(tokens, "body"));
        var error = Assert.Single(errors);
        Assert.Equal(ErrorCode.InvalidPreprocessorDirective, error.Code);
    }

    [Fact]
    public void EndifWithoutIf_ReportsError()
    {
        var (_, errors) = Preprocess("#endif");

        var error = Assert.Single(errors);
        Assert.Equal(ErrorCode.InvalidPreprocessorDirective, error.Code);
    }

    [Fact]
    public void UnterminatedIf_ReportsError()
    {
        const string source = """
            #if A
            let x = body
            """;

        var (_, errors) = Preprocess(source, "A");

        var error = Assert.Single(errors);
        Assert.Equal(ErrorCode.InvalidPreprocessorDirective, error.Code);
    }

    [Fact]
    public void ElifAfterElse_ReportsError()
    {
        const string source = """
            #if A
            let x = a
            #else
            let x = b
            #elif C
            let x = c
            #endif
            """;

        var (_, errors) = Preprocess(source);

        Assert.Contains(errors, e => e.Code == ErrorCode.InvalidPreprocessorDirective);
    }

    [Fact]
    public void TrailingLineComment_OnCondition_IsIgnored()
    {
        const string source = """
            #if FEATURE_X // turn the feature on
            let x = body
            #endif
            """;

        var (tokens, errors) = Preprocess(source, "FEATURE_X");

        Assert.Empty(errors);
        Assert.True(HasIdentifier(tokens, "body"));
    }
}
