using System;
using System.Linq;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class SoaRecordNullConditionalTests
{
    private const string ExperimentalSoaEnvironmentVariable = "NSHARP_EXPERIMENTAL_SOA";

    [Fact]
    public void Analyzer_SoaRowViewCannotUseNullConditionalIndexing()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return nodes?[0].kind
            }
            """);

        var error = result.Errors.Single(e => e.Code == ErrorCode.InvalidSyntax
            && e.Message.Contains("SoA row views cannot be used with null-conditional indexing"));
        Assert.Contains("SoA row views cannot be used with null-conditional indexing", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowColumnCannotUseNullConditionalMemberAccess()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return nodes[0]?.kind
            }
            """);

        var error = result.Errors.Single(e => e.Code == ErrorCode.InvalidSyntax
            && e.Message.Contains("SoA row views cannot be used with null-conditional member access"));
        Assert.Contains("SoA row views cannot be used with null-conditional member access", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaTableCannotUseNullConditionalMemberAccess()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                return nodes?.length
            }
            """);

        var error = result.Errors.Single(e => e.Code == ErrorCode.InvalidSyntax
            && e.Message.Contains("SoA tables cannot use null-conditional member access"));
        Assert.Contains("SoA tables cannot use null-conditional member access", error.Message);
        Assert.Contains("use direct table.member access", error.Suggestion);
    }

    private static AnalysisResult Analyze(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl", source);
        var parseResult = parser.ParseCompilationUnit();
        Assert.True(parseResult.Success, string.Join(Environment.NewLine, parseResult.Errors.Select(error => error.Message)));

        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        return analyzer.Analyze(parseResult.CompilationUnit!, "test.nl", null, source);
    }

    private static IDisposable SetEnvironmentVariable(string name, string? value)
    {
        var previousValue = Environment.GetEnvironmentVariable(name);
        Environment.SetEnvironmentVariable(name, value);
        return new DisposableAction(() => Environment.SetEnvironmentVariable(name, previousValue));
    }

    private sealed class DisposableAction(Action dispose) : IDisposable
    {
        public void Dispose() => dispose();
    }
}
