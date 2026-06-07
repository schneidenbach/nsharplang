using System;
using System.Collections.Generic;
using System.Text;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Benchmarks;

/// <summary>
/// END-TO-END whole-file parse: source string -> production <see cref="CompilationUnit"/>, comparing the C#
/// <see cref="Parser"/> (Lexer.Tokenize + ParseCompilationUnit) against the N#-native routing path
/// (NSharpCompilerDogfoodAdapter.TryParseCompilationUnit: dogfood tokenizer + declarations/signature/statement
/// kernels + <see cref="ColumnarAstMaterializer"/>). This is the never-slower gate for flipping the parser
/// front-end routing default on.
///
/// The routed path is replicated here from bound kernels (the benchmark project compiles the .nl sources
/// rather than loading the deployed dogfood assembly), but it executes the SAME logic and the SAME public
/// ColumnarAstMaterializer as production, so the measured cost -- including materialization to the C# AST
/// records the rest of the compiler consumes -- is faithful. Correctness parity is covered by
/// CompilerDogfoodProjectTests.Router_CompilationUnit_MatchesProductionParserAst; this measures speed/alloc.
///
/// KEY QUESTION: the statement kernel alone parses ~5-6x faster than the C# parser (see
/// CompilerServiceParserBenchmarks), but it writes compact int[] tables. Materializing those tables back into
/// the C# object-graph AST re-introduces exactly the allocation the C# parser does. This benchmark measures
/// whether the kernel's speed survives materialization end-to-end.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilationUnitRoutingBenchmarks
{
    private TokenizeMetadataDelegate _tokenize = (_, _, _, _, _, _) => throw new InvalidOperationException("not initialized");
    private TopLevelDeclarationKindsDelegate _declKinds = (_, _, _) => throw new InvalidOperationException("not initialized");
    private NamespaceImportSpansDelegate _importSpans = (_, _, _, _, _, _, _, _) => throw new InvalidOperationException("not initialized");
    private PackageNameSpanDelegate _packageSpan = (_, _, _, _, _) => throw new InvalidOperationException("not initialized");
    private ParseFunctionSignatureDelegate _parseSig = (_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("not initialized");
    private ParseStatementNodesIntoDelegate _parseStmt = (_, _, _, _, _, _, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("not initialized");

    private string _source = string.Empty;

    [Params(RoutingCorpus.Representative, RoutingCorpus.LargeGenerated)]
    public RoutingCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var kernelSource = DogfoodCompilerSources.ParserFrontEndFull;
        _tokenize = NSharpCompiledMethod.Bind<TokenizeMetadataDelegate>(kernelSource, "TokenizeMetadataWithIndentationInto");
        _declKinds = NSharpCompiledMethod.Bind<TopLevelDeclarationKindsDelegate>(kernelSource, "TopLevelDeclarationKindsInto");
        _importSpans = NSharpCompiledMethod.Bind<NamespaceImportSpansDelegate>(kernelSource, "NamespaceImportSpansInto");
        _packageSpan = NSharpCompiledMethod.Bind<PackageNameSpanDelegate>(kernelSource, "PackageNameSpanInto");
        _parseSig = NSharpCompiledMethod.Bind<ParseFunctionSignatureDelegate>(kernelSource, "ParseFunctionSignatureInto");
        _parseStmt = NSharpCompiledMethod.Bind<ParseStatementNodesIntoDelegate>(kernelSource, "ParseStatementNodesInto");

        _source = RoutingCorpusSources.Build(Corpus);

        // Sanity: both paths must succeed on the corpus (parity is covered by the test suite).
        var csharp = new Parser(new Lexer(_source, "bench.nl").Tokenize(), "bench.nl", _source).ParseCompilationUnit().CompilationUnit;
        if (csharp == null)
            throw new InvalidOperationException("C# parser failed on the routing corpus.");
        var routed = RouteCompilationUnit(_source);
        if (routed == null)
            throw new InvalidOperationException("N# routing path declined the routing corpus (expected fully-supported).");
        if (routed.Declarations.Count != csharp.Declarations.Count)
            throw new InvalidOperationException($"Routing produced {routed.Declarations.Count} decls, C# produced {csharp.Declarations.Count}.");
    }

    [Benchmark(Baseline = true)]
    public int CSharpParser_SourceToCompilationUnit()
    {
        var unit = new Parser(new Lexer(_source, "bench.nl").Tokenize(), "bench.nl", _source).ParseCompilationUnit().CompilationUnit;
        return unit?.Declarations.Count ?? 0;
    }

    [Benchmark]
    public int NSharpRouting_SourceToCompilationUnit()
    {
        var unit = RouteCompilationUnit(_source);
        return unit?.Declarations.Count ?? 0;
    }

    // Mirrors NSharpCompilerDogfoodAdapter.TryParseCompilationUnit (see that method for the rationale of each
    // step / guard). Returns null when any form is unsupported (never reached for the supported corpora here).
    private CompilationUnit? RouteCompilationUnit(string source)
    {
        var capacity = 3 * (source.Length + 1) + 8;
        var rawKinds = new int[capacity];
        var rawStarts = new int[capacity];
        var rawValueLengths = new int[capacity];
        var rawLines = new int[capacity];
        var rawColumns = new int[capacity];
        var rawCount = _tokenize(source, rawKinds, rawStarts, rawValueLengths, rawLines, rawColumns);
        if (rawCount < 0 || rawCount > capacity)
            return null;

        var declKinds = new int[rawCount + 1];
        var declCount = _declKinds(rawKinds, rawCount, declKinds);
        if (declCount < 0)
            return null;
        for (var i = 0; i < declCount; i++)
        {
            if (declKinds[i] != 7)
                return null;
        }

        var packageResult = new int[2];
        if (_packageSpan(rawKinds, rawStarts, rawValueLengths, rawCount, packageResult) == 1)
            return null;

        var nsStarts = new int[rawCount + 1];
        var nsLengths = new int[rawCount + 1];
        var aliasStarts = new int[rawCount + 1];
        var aliasLengths = new int[rawCount + 1];
        var importCount = _importSpans(rawKinds, rawStarts, rawValueLengths, rawCount, nsStarts, nsLengths, aliasStarts, aliasLengths);
        if (importCount < 0)
            return null;
        var imports = new List<ImportDirective>(importCount);
        for (var i = 0; i < importCount; i++)
        {
            if (nsStarts[i] < 0)
                return null;
            var ns = source.Substring(nsStarts[i], nsLengths[i]);
            var alias = aliasStarts[i] < 0 ? null : source.Substring(aliasStarts[i], aliasLengths[i]);
            imports.Add(new ImportDirective(ns, alias, 0, 0));
        }

        var ck = new int[rawCount];
        var cs = new int[rawCount];
        var cv = new int[rawCount];
        var n = 0;
        for (var i = 0; i < rawCount; i++)
        {
            if (rawKinds[i] == 136)
                continue;
            ck[n] = rawKinds[i];
            cs[n] = rawStarts[i];
            cv[n] = rawValueLengths[i];
            n++;
        }

        var funcIndices = TopLevelFuncIndices(ck, n);
        if (funcIndices.Count != declCount)
            return null;

        var declarations = new List<Declaration>(funcIndices.Count);
        var cap = n + 1;
        foreach (var funcIndex in funcIndices)
        {
            var sk = new int[cap]; var sns = new int[cap]; var snl = new int[cap]; var scs = new int[cap];
            var scc = new int[cap]; var sci = new int[cap]; var sss = new int[cap]; var ssl = new int[cap];
            var pNameStart = new int[cap]; var pNameLen = new int[cap]; var pTypeRoot = new int[cap];
            var sres = new int[5];
            var paramCount = _parseSig(ck, cs, cv, n, funcIndex, sk, sns, snl, scs, scc, sci, sss, ssl, pNameStart, pNameLen, pTypeRoot, sres);
            if (paramCount < 0 || sres[3] < 0)
                return null;

            var name = source.Substring(sres[3], sres[4]);
            var sigMaterializer = new ColumnarAstMaterializer(sk, sns, snl, scs, scc, sci, sss, source);
            var parameters = new List<Parameter>(paramCount);
            for (var p = 0; p < paramCount; p++)
            {
                parameters.Add(new Parameter(
                    source.Substring(pNameStart[p], pNameLen[p]),
                    sigMaterializer.MaterializeTypeReference(pTypeRoot[p]),
                    null,
                    false));
            }

            TypeReference? returnType = sres[1] >= 0 ? sigMaterializer.MaterializeTypeReference(sres[1]) : null;

            var bodyBrace = -1;
            for (var t = funcIndex + 1; t < n; t++)
            {
                if (ck[t] == 129) { bodyBrace = t; break; }
            }
            if (bodyBrace < 0)
                return null;

            var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
            var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
            var bres = new int[2];
            var bodyNodeCount = _parseStmt(ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
            if (bodyNodeCount <= 0)
                return null;

            var body = new ColumnarAstMaterializer(bk, bvs, bvl, bcs, bcc, bci, bss, source)
                .MaterializeStatement(bres[0]) as BlockStatement;
            if (body == null)
                return null;

            declarations.Add(new FunctionDeclaration(
                name, parameters, returnType, body,
                ExpressionBody: null, TypeParameters: null, Constraints: null,
                Modifiers.None, new List<AttributeNode>(),
                IsOperatorOverload: false, OperatorSymbol: null,
                IsConversionOperator: false, IsImplicitConversion: false,
                Line: 0, Column: 0));
        }

        return new CompilationUnit(Namespace: null, imports, new List<Statement>(), Package: null, declarations, 0, 0);
    }

    private static List<int> TopLevelFuncIndices(int[] kinds, int count)
    {
        var result = new List<int>();
        var brace = 0;
        var bracket = 0;
        var paren = 0;
        for (var i = 0; i < count; i++)
        {
            switch (kinds[i])
            {
                case 129: brace++; break;
                case 130: if (brace > 0) brace--; break;
                case 131: bracket++; break;
                case 132: if (bracket > 0) bracket--; break;
                case 127: paren++; break;
                case 128: if (paren > 0) paren--; break;
                case 7:
                    if (brace == 0 && bracket == 0 && paren == 0) result.Add(i);
                    break;
            }
        }

        return result;
    }
}

internal delegate int TokenizeMetadataDelegate(
    string source, int[] kinds, int[] starts, int[] valueLengths, int[] lines, int[] columns);

internal delegate int TopLevelDeclarationKindsDelegate(int[] tokenKinds, int count, int[] outKinds);

internal delegate int NamespaceImportSpansDelegate(
    int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count,
    int[] outNsStarts, int[] outNsLengths, int[] outAliasStarts, int[] outAliasLengths);

internal delegate int PackageNameSpanDelegate(
    int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int[] outResult);

internal delegate int ParseFunctionSignatureDelegate(
    int[] tokenKinds, int[] tokenStarts, int[] tokenValueLengths, int count, int funcIndex,
    int[] outNodeKinds, int[] outNameStarts, int[] outNameLengths, int[] outChildStart, int[] outChildCount,
    int[] outChildIndices, int[] outSpanStarts, int[] outSpanLengths,
    int[] outParamNameStarts, int[] outParamNameLengths, int[] outParamTypeRoots, int[] outResult);

public enum RoutingCorpus
{
    Representative,
    LargeGenerated,
}

internal static class RoutingCorpusSources
{
    public static string Build(RoutingCorpus corpus) => corpus switch
    {
        RoutingCorpus.Representative => Representative(),
        RoutingCorpus.LargeGenerated => Large(40),
        _ => throw new ArgumentOutOfRangeException(nameof(corpus)),
    };

    // A small, realistic supported-form file: an import + a handful of functions exercising :=, while, if/else,
    // index/member access, calls, arithmetic/logical operators, and a hard cast.
    private static string Representative() =>
        "import System\n\n" +
        "func scan(data: int[], count: int, threshold: int): int {\n" +
        "    total := 0\n" +
        "    i := 0\n" +
        "    while i < count {\n" +
        "        x := data[i]\n" +
        "        if x > threshold && x < count {\n" +
        "            total = total + x * 2 - data[i + 1] % 3\n" +
        "        } else {\n" +
        "            total = total - x\n" +
        "        }\n" +
        "        i = i + 1\n" +
        "    }\n" +
        "    return total\n" +
        "}\n\n" +
        "func toCode(ch: char): int {\n" +
        "    return (int)ch\n" +
        "}\n";

    // Many functions, each with a supported-form body, to measure steady-state whole-file throughput.
    private static string Large(int funcs)
    {
        var sb = new StringBuilder();
        sb.Append("import System\n\n");
        for (var f = 0; f < funcs; f++)
        {
            sb.Append("func f").Append(f).Append("(data: int[], count: int, limit: int): int {\n");
            sb.Append("    acc := 0\n");
            sb.Append("    i := 0\n");
            sb.Append("    while i < count {\n");
            sb.Append("        v := data[i] + acc * 2\n");
            sb.Append("        if v > 0 && v < limit {\n");
            sb.Append("            acc = acc + v * 3 - 1\n");
            sb.Append("        } else {\n");
            sb.Append("            acc = acc - v\n");
            sb.Append("        }\n");
            sb.Append("        i = i + 1\n");
            sb.Append("    }\n");
            sb.Append("    return acc\n");
            sb.Append("}\n\n");
        }

        return sb.ToString();
    }
}
