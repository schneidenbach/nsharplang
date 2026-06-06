using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

/// <summary>
/// First parser-front-end benchmark for the N#-emitted recursive-descent statement kernel
/// (ParseStatementNodesInto, which composes the type + expression + new kernels over one columnar node
/// table) versus the production C# <see cref="Parser"/>.
///
/// Both parse the SAME function body (supported-form statements: := declarations, while, if/else,
/// assignments, arithmetic/comparison/logical operators, index/member access, calls, new int[](...)). The
/// C# side parses the whole `func ... { body }` compilation unit into an allocating object AST; the N# side
/// parses the body block into a pre-allocated columnar node table (near-zero allocation). Tokenization is
/// done once in <see cref="Setup"/> for both sides, so this measures the PARSE phase only. The N# kernel's
/// output is parity-verified against the C# parser by the test
/// CompilerDogfoodProjectTests.Parser_RealCorpusFunctionBodies_MatchProductionParser; this benchmark
/// measures speed and allocation, not correctness.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceParserBenchmarks
{
    private Func<string, int[], int[], int[], int[], int[], int> _nsharpTokenize =
        (_, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");
    private ParseStatementNodesIntoDelegate _nsharpParseStatement =
        (_, _, _, _, _, _, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string _source = string.Empty;
    private List<Token> _csharpTokens = new();
    private int _count;
    private int _bodyStart;
    private int[] _kinds = Array.Empty<int>();
    private int[] _starts = Array.Empty<int>();
    private int[] _valueLengths = Array.Empty<int>();

    // Reusable output node table (caller-owned; the kernel writes from index 0 on each call).
    private int[] _outNodeKinds = Array.Empty<int>();
    private int[] _outValueStarts = Array.Empty<int>();
    private int[] _outValueLengths = Array.Empty<int>();
    private int[] _outChildStart = Array.Empty<int>();
    private int[] _outChildCount = Array.Empty<int>();
    private int[] _outChildIndices = Array.Empty<int>();
    private int[] _outSpanStarts = Array.Empty<int>();
    private int[] _outSpanLengths = Array.Empty<int>();
    private int[] _outResult = new int[2];

    [Params(ParserCorpus.Representative, ParserCorpus.LargeGenerated)]
    public ParserCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var source = DogfoodCompilerSources.ParserFrontEnd;
        _nsharpTokenize = NSharpCompiledMethod.Bind<Func<string, int[], int[], int[], int[], int[], int>>(
            source, "TokenizeMetadataWithIndentationInto");
        _nsharpParseStatement = NSharpCompiledMethod.Bind<ParseStatementNodesIntoDelegate>(
            source, "ParseStatementNodesInto");

        _source = ParserCorpusSources.Build(Corpus);

        // Tokenize via the N# lexer kernel, then compact Newline tokens (136) -- the parser operates on the
        // newline-free stream the C# Parser uses.
        var capacity = 3 * (_source.Length + 1) + 8;
        var rawKinds = new int[capacity];
        var rawStarts = new int[capacity];
        var rawValueLengths = new int[capacity];
        var rawLines = new int[capacity];
        var rawColumns = new int[capacity];
        var rawCount = _nsharpTokenize(_source, rawKinds, rawStarts, rawValueLengths, rawLines, rawColumns);

        _kinds = new int[rawCount];
        _starts = new int[rawCount];
        _valueLengths = new int[rawCount];
        var n = 0;
        for (var i = 0; i < rawCount; i++)
        {
            if (rawKinds[i] == 136) continue;
            _kinds[n] = rawKinds[i];
            _starts[n] = rawStarts[i];
            _valueLengths[n] = rawValueLengths[i];
            n++;
        }
        _count = n;

        // The benchmark function's body opens at the first `{` (LeftBrace 129).
        _bodyStart = -1;
        for (var i = 0; i < _count; i++)
        {
            if (_kinds[i] == 129) { _bodyStart = i; break; }
        }
        if (_bodyStart < 0) throw new InvalidOperationException("Benchmark corpus has no function body brace.");

        var cap = _count + 1;
        _outNodeKinds = new int[cap];
        _outValueStarts = new int[cap];
        _outValueLengths = new int[cap];
        _outChildStart = new int[cap];
        _outChildCount = new int[cap];
        _outChildIndices = new int[cap];
        _outSpanStarts = new int[cap];
        _outSpanLengths = new int[cap];
        _outResult = new int[2];

        _csharpTokens = new Lexer(_source, $"{Corpus}.nl").Tokenize();

        // Sanity: both parse the corpus successfully (correctness parity is covered by the test suite).
        var nodeCount = _nsharpParseStatement(
            _kinds, _starts, _valueLengths, _count, _bodyStart,
            _outNodeKinds, _outValueStarts, _outValueLengths, _outChildStart, _outChildCount, _outChildIndices,
            _outSpanStarts, _outSpanLengths, _outResult);
        if (nodeCount <= 0)
        {
            throw new InvalidOperationException($"N# statement kernel failed to parse the {Corpus} corpus (returned {nodeCount}).");
        }

        var unit = new Parser(_csharpTokens, $"{Corpus}.nl").ParseCompilationUnit().CompilationUnit;
        if (unit == null)
        {
            throw new InvalidOperationException($"C# parser failed to parse the {Corpus} corpus.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpParser_ParseBody()
    {
        var unit = new Parser(_csharpTokens, "bench.nl").ParseCompilationUnit().CompilationUnit;
        return unit?.Declarations.Count ?? 0;
    }

    [Benchmark]
    public int NSharpStatementKernel_ParseBody()
    {
        return _nsharpParseStatement(
            _kinds, _starts, _valueLengths, _count, _bodyStart,
            _outNodeKinds, _outValueStarts, _outValueLengths, _outChildStart, _outChildCount, _outChildIndices,
            _outSpanStarts, _outSpanLengths, _outResult);
    }
}

internal delegate int ParseStatementNodesIntoDelegate(
    int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int start,
    int[] outNodeKinds, int[] outValueStarts, int[] outValueLengths, int[] outChildStart,
    int[] outChildCount, int[] outChildIndices, int[] outSpanStarts, int[] outSpanLengths, int[] outResult);

public enum ParserCorpus
{
    Representative,
    LargeGenerated,
}

internal static class ParserCorpusSources
{
    public static string Build(ParserCorpus corpus) => corpus switch
    {
        ParserCorpus.Representative => Wrap(RepresentativeBody()),
        ParserCorpus.LargeGenerated => Wrap(LargeBody(40)),
        _ => throw new ArgumentOutOfRangeException(nameof(corpus)),
    };

    private static string Wrap(string body) => "func benchBody() {\n" + body + "}\n";

    // A realistic supported-form body: declaration, counted loop, nested if/else with logical + relational
    // operators, indexing, arithmetic, an array allocation, and a return.
    private static string RepresentativeBody() =>
        "    total := 0\n" +
        "    i := 0\n" +
        "    while i < count {\n" +
        "        x := data[i]\n" +
        "        if x > threshold && x < limit {\n" +
        "            total = total + x * 2 - data[i + 1] % 3\n" +
        "            count = count + 1\n" +
        "        } else {\n" +
        "            total = total - x\n" +
        "        }\n" +
        "        i = i + 1\n" +
        "    }\n" +
        "    buffer := new int[](total)\n" +
        "    return total\n";

    // Many sequential supported-form statements, to amortize the func-wrapper overhead on the C# side and
    // measure steady-state parse throughput.
    private static string LargeBody(int blocks)
    {
        var sb = new StringBuilder();
        sb.Append("    acc := 0\n");
        for (var b = 0; b < blocks; b++)
        {
            sb.Append("    v").Append(b).Append(" := data[").Append(b).Append("] + acc * 2\n");
            sb.Append("    if v").Append(b).Append(" > 0 && v").Append(b).Append(" < limit {\n");
            sb.Append("        acc = acc + v").Append(b).Append(" * 3 - 1\n");
            sb.Append("    } else {\n");
            sb.Append("        acc = acc - v").Append(b).Append("\n");
            sb.Append("    }\n");
            sb.Append("    while acc > threshold {\n");
            sb.Append("        acc = acc - step(v").Append(b).Append(", acc)\n");
            sb.Append("    }\n");
        }
        sb.Append("    return acc\n");
        return sb.ToString();
    }
}
