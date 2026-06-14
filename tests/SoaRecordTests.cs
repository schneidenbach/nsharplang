using System;
using System.Linq;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class SoaRecordTests : ILCompilerTestBase
{
    private const string ExperimentalSoaEnvironmentVariable = "NSHARP_EXPERIMENTAL_SOA";

    [Fact]
    public void Analyzer_SoaRecordWithoutFlag_IsFeatureGated()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, null);

        var result = Analyze("""
            soa record NodeTable {
                kind: int
                valueStart: int
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("soa record 'NodeTable'", error.Message);
        Assert.Contains(ExperimentalSoaEnvironmentVariable, error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void Analyzer_SoaRecordWithFlag_TypesTableMembersAndRowProjection()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
                start: int
            }

            func probe(): int {
                nodes := new NodeTable(4)
                row := nodes.add()
                nodes[row].kind = 7
                nodes.kind[row] = nodes[row].kind + nodes.capacity + nodes.length
                return nodes.kind[row]
            }
            """);

        Assert.False(
            result.HasErrors,
            $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeIntoLocal()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                row := nodes[0]
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be stored in a variable", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeIntoCallArgument()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func consume(value: object) {
            }

            func bad(nodes: NodeTable): int {
                consume(nodes[0])
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be passed as an argument", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughReturn()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): object {
                return nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be returned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeIntoArrayLiteral()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                values := [nodes[0]]
                return values.Length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be stored in an array", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughArrayInitializer()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): int {
                values := new object[] { nodes[0] }
                return values.Length
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be stored in an initializer", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeIntoConstructorArgument()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                constructor(value: object) {
                }
            }

            func bad(nodes: NodeTable): int {
                holder := new Holder(nodes[0])
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be passed as a constructor argument", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBePrinted()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable) {
                print nodes[0]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be printed", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotBeFormattedInInterpolatedString()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            func bad(nodes: NodeTable): string {
                return $"{nodes[0]}"
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be formatted in an interpolated string", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughAssignment()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Value: object
            }

            func bad(nodes: NodeTable): int {
                holder := new Holder()
                holder.Value = nodes[0]
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be assigned", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void Analyzer_SoaRowViewCannotEscapeThroughObjectInitializer()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var result = Analyze("""
            soa record NodeTable {
                kind: int
            }

            class Holder {
                Value: object
            }

            func bad(nodes: NodeTable): int {
                holder := new Holder { Value: nodes[0] }
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("SoA row views cannot be stored in an object initializer", error.Message);
        Assert.Contains("table[index].column", error.Suggestion);
    }

    [Fact]
    public void ILCompiler_SoaRecordNewAddAndRowProjection_LowersToColumns()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func main(): int {
                nodes := new NodeTable(1)
                first := nodes.add()
                nodes[first].kind = 10
                nodes[first].start = 20
                second := nodes.add()
                nodes[second].kind = nodes[first].kind + 1
                nodes[second].kind += nodes[first].kind
                nodes[second].start = nodes[first].start + 2
                return nodes.length * 1000 + nodes.capacity * 100 + nodes[second].kind * 10 + nodes[second].start
            }
            """;

        Assert.Equal(2632, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordWrap_IsZeroCopyAndValidatesLength()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func main(): int {
                kinds := new int[](2)
                starts := new int[](2)
                kinds[0] = 3
                starts[0] = 4
                nodes := NodeTable.wrap(kinds, starts, 1)
                nodes[0].kind = 8
                nodes[0].start += 5
                return kinds[0] + starts[0] * 10 + nodes.capacity * 100 + nodes.length * 1000
            }
            """;

        Assert.Equal(1298, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordCopyRowAndClear_UpdateLengthWithoutRowObjects()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
                start: int
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 5
                nodes[row].start = 7
                nodes.copyRow(0, 3)
                before := nodes.length * 100 + nodes.capacity * 10 + nodes[3].kind + nodes[3].start
                nodes.clear()
                return before * 10 + nodes.length
            }
            """;

        Assert.Equal(4520, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordNullCoalesceAssignOnRowColumn_StoresOnlyWhenNull()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                text: string
            }

            func main(): string {
                nodes := new NodeTable(2)
                first := nodes.add()
                second := nodes.add()
                nodes[first].text ??= "fallback"
                nodes[first].text ??= "other"
                nodes[second].text = "ready"
                nodes[second].text ??= "ignored"
                return nodes[first].text + ":" + nodes[second].text
            }
            """;

        Assert.Equal("fallback:ready", Assert.IsType<string>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_SoaRecordRowColumnIncrementAndDecrement_PreservesPostfixSemantics()
    {
        using var _ = SetEnvironmentVariable(ExperimentalSoaEnvironmentVariable, "1");

        var source = """
            soa record NodeTable {
                kind: int
            }

            func main(): int {
                nodes := new NodeTable(1)
                row := nodes.add()
                nodes[row].kind = 10
                oldUp := nodes[row].kind++
                oldDown := nodes[row].kind--
                nodes[row].kind++
                nodes[row].kind++
                return oldUp * 1000 + oldDown * 100 + nodes[row].kind
            }
            """;

        Assert.Equal(11112, Assert.IsType<int>(CompileAndInvoke(source)));
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
        return new RestoreEnvironmentVariable(name, previousValue);
    }

    private sealed class RestoreEnvironmentVariable(string name, string? previousValue) : IDisposable
    {
        public void Dispose()
        {
            Environment.SetEnvironmentVariable(name, previousValue);
        }
    }
}
