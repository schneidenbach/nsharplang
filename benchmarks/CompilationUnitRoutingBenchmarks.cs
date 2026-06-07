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

    // Pooled buffers for the NSharpFrontEnd_ColumnarParseOnly_Pooled variant: allocated once in Setup and
    // reused across every function and every iteration, so the per-function whole-file-sized table allocation
    // (the dominant cost of the naive orchestrator) is removed. This isolates the columnar front-end's true
    // steady-state cost from the table-allocation artifact.
    private int[] _pRawKinds = Array.Empty<int>();
    private int[] _pRawStarts = Array.Empty<int>();
    private int[] _pRawValueLengths = Array.Empty<int>();
    private int[] _pRawLines = Array.Empty<int>();
    private int[] _pRawColumns = Array.Empty<int>();
    private int[] _pCk = Array.Empty<int>();
    private int[] _pCs = Array.Empty<int>();
    private int[] _pCv = Array.Empty<int>();
    private int[] _pDeclKinds = Array.Empty<int>();
    private int[] _pNsStarts = Array.Empty<int>();
    private int[] _pNsLengths = Array.Empty<int>();
    private int[] _pAliasStarts = Array.Empty<int>();
    private int[] _pAliasLengths = Array.Empty<int>();
    private readonly int[] _pPackageResult = new int[2];
    private int[] _pSk = Array.Empty<int>(); private int[] _pSns = Array.Empty<int>(); private int[] _pSnl = Array.Empty<int>();
    private int[] _pScs = Array.Empty<int>(); private int[] _pScc = Array.Empty<int>(); private int[] _pSci = Array.Empty<int>();
    private int[] _pSss = Array.Empty<int>(); private int[] _pSsl = Array.Empty<int>();
    private int[] _pPNameStart = Array.Empty<int>(); private int[] _pPNameLen = Array.Empty<int>(); private int[] _pPTypeRoot = Array.Empty<int>();
    private readonly int[] _pSres = new int[5];
    private int[] _pBk = Array.Empty<int>(); private int[] _pBvs = Array.Empty<int>(); private int[] _pBvl = Array.Empty<int>();
    private int[] _pBcs = Array.Empty<int>(); private int[] _pBcc = Array.Empty<int>(); private int[] _pBci = Array.Empty<int>();
    private int[] _pBss = Array.Empty<int>(); private int[] _pBsl = Array.Empty<int>();
    private readonly int[] _pBres = new int[2];

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

        // Pooled buffers sized to the whole corpus (>= any single function's needs).
        var poolCap = 3 * (_source.Length + 1) + 8;
        _pRawKinds = new int[poolCap]; _pRawStarts = new int[poolCap]; _pRawValueLengths = new int[poolCap];
        _pRawLines = new int[poolCap]; _pRawColumns = new int[poolCap];
        _pCk = new int[poolCap]; _pCs = new int[poolCap]; _pCv = new int[poolCap];
        _pDeclKinds = new int[poolCap]; _pNsStarts = new int[poolCap]; _pNsLengths = new int[poolCap];
        _pAliasStarts = new int[poolCap]; _pAliasLengths = new int[poolCap];
        _pSk = new int[poolCap]; _pSns = new int[poolCap]; _pSnl = new int[poolCap];
        _pScs = new int[poolCap]; _pScc = new int[poolCap]; _pSci = new int[poolCap];
        _pSss = new int[poolCap]; _pSsl = new int[poolCap];
        _pPNameStart = new int[poolCap]; _pPNameLen = new int[poolCap]; _pPTypeRoot = new int[poolCap];
        _pBk = new int[poolCap]; _pBvs = new int[poolCap]; _pBvl = new int[poolCap];
        _pBcs = new int[poolCap]; _pBcc = new int[poolCap]; _pBci = new int[poolCap];
        _pBss = new int[poolCap]; _pBsl = new int[poolCap];

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

    // Same end-to-end parse as NSharpRouting_SourceToCompilationUnit -- identical tokenizer, declarations,
    // signature, and statement kernels, identical per-function int[] table allocation, identical delegate
    // boundary crossings -- but it STOPS at the columnar node tables and does NOT materialize the C# AST
    // (no ColumnarAstMaterializer, no FunctionDeclaration/Parameter/Expression records). The only difference
    // from the materializing benchmark is the materialization step, so:
    //   (this vs NSharpRouting_SourceToCompilationUnit) = the cost of materializing the C# object-graph AST,
    //   (this vs CSharpParser_SourceToCompilationUnit)   = the columnar front-end's true potential.
    // This answers "is the routing regression a marshaling/boundary problem, or a materialization problem?".
    [Benchmark]
    public int NSharpFrontEnd_ColumnarParseOnly()
    {
        return ParseColumnarOnly(_source);
    }

    // Same as NSharpFrontEnd_ColumnarParseOnly but with the int[] tables POOLED (reused across functions and
    // iterations) instead of freshly allocated per function. This removes the whole-file-sized-per-function
    // table allocation -- a fixable orchestrator artifact -- and reveals the columnar front-end's true
    // steady-state cost (tokenize + kernels + the kernels' own internal allocations). The gap between this and
    // NSharpFrontEnd_ColumnarParseOnly is the table-allocation tax; this vs CSharpParser is the realistic
    // ceiling of a columnar pipeline that never materializes the C# AST.
    [Benchmark]
    public int NSharpFrontEnd_ColumnarParseOnly_Pooled()
    {
        return ParseColumnarOnlyPooled(_source);
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

    // Identical parse work to RouteCompilationUnit (same kernels, same per-function int[] table allocation,
    // same delegate crossings) but WITHOUT materializing the C# AST. Returns the total columnar node count.
    private int ParseColumnarOnly(string source)
    {
        var capacity = 3 * (source.Length + 1) + 8;
        var rawKinds = new int[capacity];
        var rawStarts = new int[capacity];
        var rawValueLengths = new int[capacity];
        var rawLines = new int[capacity];
        var rawColumns = new int[capacity];
        var rawCount = _tokenize(source, rawKinds, rawStarts, rawValueLengths, rawLines, rawColumns);
        if (rawCount < 0 || rawCount > capacity)
            return -1;

        var declKinds = new int[rawCount + 1];
        var declCount = _declKinds(rawKinds, rawCount, declKinds);
        if (declCount < 0)
            return -1;
        for (var i = 0; i < declCount; i++)
        {
            if (declKinds[i] != 7)
                return -1;
        }

        var packageResult = new int[2];
        if (_packageSpan(rawKinds, rawStarts, rawValueLengths, rawCount, packageResult) == 1)
            return -1;

        var nsStarts = new int[rawCount + 1];
        var nsLengths = new int[rawCount + 1];
        var aliasStarts = new int[rawCount + 1];
        var aliasLengths = new int[rawCount + 1];
        var importCount = _importSpans(rawKinds, rawStarts, rawValueLengths, rawCount, nsStarts, nsLengths, aliasStarts, aliasLengths);
        if (importCount < 0)
            return -1;

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
            return -1;

        var totalNodes = 0;
        var cap = n + 1;
        foreach (var funcIndex in funcIndices)
        {
            var sk = new int[cap]; var sns = new int[cap]; var snl = new int[cap]; var scs = new int[cap];
            var scc = new int[cap]; var sci = new int[cap]; var sss = new int[cap]; var ssl = new int[cap];
            var pNameStart = new int[cap]; var pNameLen = new int[cap]; var pTypeRoot = new int[cap];
            var sres = new int[5];
            var paramCount = _parseSig(ck, cs, cv, n, funcIndex, sk, sns, snl, scs, scc, sci, sss, ssl, pNameStart, pNameLen, pTypeRoot, sres);
            if (paramCount < 0 || sres[3] < 0)
                return -1;
            totalNodes += sres[2];

            var bodyBrace = -1;
            for (var t = funcIndex + 1; t < n; t++)
            {
                if (ck[t] == 129) { bodyBrace = t; break; }
            }
            if (bodyBrace < 0)
                return -1;

            var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
            var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
            var bres = new int[2];
            var bodyNodeCount = _parseStmt(ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
            if (bodyNodeCount <= 0)
                return -1;
            totalNodes += bodyNodeCount;
        }

        return totalNodes;
    }

    // Pooled-buffer twin of ParseColumnarOnly: reuses the instance buffers for every function, so the only
    // per-iteration allocations are the kernels' own internal scratch (st / argStack). Returns total nodes.
    private int ParseColumnarOnlyPooled(string source)
    {
        var rawCount = _tokenize(source, _pRawKinds, _pRawStarts, _pRawValueLengths, _pRawLines, _pRawColumns);
        if (rawCount < 0 || rawCount > _pRawKinds.Length)
            return -1;

        var declCount = _declKinds(_pRawKinds, rawCount, _pDeclKinds);
        if (declCount < 0)
            return -1;
        for (var i = 0; i < declCount; i++)
        {
            if (_pDeclKinds[i] != 7)
                return -1;
        }

        if (_packageSpan(_pRawKinds, _pRawStarts, _pRawValueLengths, rawCount, _pPackageResult) == 1)
            return -1;

        if (_importSpans(_pRawKinds, _pRawStarts, _pRawValueLengths, rawCount, _pNsStarts, _pNsLengths, _pAliasStarts, _pAliasLengths) < 0)
            return -1;

        var n = 0;
        for (var i = 0; i < rawCount; i++)
        {
            if (_pRawKinds[i] == 136)
                continue;
            _pCk[n] = _pRawKinds[i];
            _pCs[n] = _pRawStarts[i];
            _pCv[n] = _pRawValueLengths[i];
            n++;
        }

        var funcIndices = TopLevelFuncIndices(_pCk, n);
        if (funcIndices.Count != declCount)
            return -1;

        var totalNodes = 0;
        foreach (var funcIndex in funcIndices)
        {
            var paramCount = _parseSig(_pCk, _pCs, _pCv, n, funcIndex, _pSk, _pSns, _pSnl, _pScs, _pScc, _pSci, _pSss, _pSsl, _pPNameStart, _pPNameLen, _pPTypeRoot, _pSres);
            if (paramCount < 0 || _pSres[3] < 0)
                return -1;
            totalNodes += _pSres[2];

            var bodyBrace = -1;
            for (var t = funcIndex + 1; t < n; t++)
            {
                if (_pCk[t] == 129) { bodyBrace = t; break; }
            }
            if (bodyBrace < 0)
                return -1;

            var bodyNodeCount = _parseStmt(_pCk, _pCs, _pCv, n, bodyBrace, _pBk, _pBvs, _pBvl, _pBcs, _pBcc, _pBci, _pBss, _pBsl, _pBres);
            if (bodyNodeCount <= 0)
                return -1;
            totalNodes += bodyNodeCount;
        }

        return totalNodes;
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
