using System;
using System.Collections.Generic;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Benchmarks;

/// <summary>
/// The "does the win compound past the parser?" spike. Slice 26 proved the N# parser front-end is ~2.4x
/// faster than C# when it is NOT materialized into the C# AST. This measures the NEXT stage: given an
/// already-parsed representation, run the SAME downstream semantic pass two ways and compare.
///
/// The pass is identifier collection -- "the distinct set of identifier names referenced in every function
/// body" -- a full traversal that does representative per-node work (a string add to a set), standing in for
/// the per-node work a binder/analyzer does. The C# side recursively walks the object-graph AST
/// (virtual dispatch + pointer chasing + the AST already allocated). The columnar side linearly scans the
/// flat int[] node tables (sequential, cache-friendly, no AST). Parsing is done in Setup, so this isolates
/// the PASS cost. Both produce the same identifier set (asserted in Setup).
///
/// This is the core thesis of the columnar self-host pipeline: every downstream pass that would walk the
/// 600KB+ object-graph AST instead scans tiny int[] tables. If the per-pass advantage holds here, it compounds
/// across bind/analyze/codegen -- and the whole pipeline never allocates the C# AST at all.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class ColumnarSemanticPassBenchmarks
{
    private TokenizeMetadataDelegate _tokenize = (_, _, _, _, _, _) => throw new InvalidOperationException("not initialized");
    private TopLevelDeclarationKindsDelegate _declKinds = (_, _, _) => throw new InvalidOperationException("not initialized");
    private ParseStatementNodesIntoDelegate _parseStmt = (_, _, _, _, _, _, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("not initialized");

    private string _source = string.Empty;

    // Pre-parsed representations (built once in Setup) -- the pass benchmarks operate on these.
    private readonly List<BlockStatement> _astBodies = new();
    private readonly List<ColumnarBody> _columnarBodies = new();

    [Params(RoutingCorpus.Representative, RoutingCorpus.LargeGenerated)]
    public RoutingCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        var kernelSource = DogfoodCompilerSources.ParserFrontEndFull;
        _tokenize = NSharpCompiledMethod.Bind<TokenizeMetadataDelegate>(kernelSource, "TokenizeMetadataWithIndentationInto");
        _declKinds = NSharpCompiledMethod.Bind<TopLevelDeclarationKindsDelegate>(kernelSource, "TopLevelDeclarationKindsInto");
        _parseStmt = NSharpCompiledMethod.Bind<ParseStatementNodesIntoDelegate>(kernelSource, "ParseStatementNodesInto");

        _source = RoutingCorpusSources.Build(Corpus);

        // C# AST bodies.
        var unit = new Parser(new Lexer(_source, "bench.nl").Tokenize(), "bench.nl", _source).ParseCompilationUnit().CompilationUnit
            ?? throw new InvalidOperationException("C# parser failed on the corpus.");
        foreach (var decl in unit.Declarations)
        {
            if (decl is FunctionDeclaration { Body: { } body })
                _astBodies.Add(body);
        }

        // Columnar body tables (one per function), parsed once via the statement kernel.
        var capacity = 3 * (_source.Length + 1) + 8;
        var rawKinds = new int[capacity]; var rawStarts = new int[capacity]; var rawValueLengths = new int[capacity];
        var rawLines = new int[capacity]; var rawColumns = new int[capacity];
        var rawCount = _tokenize(_source, rawKinds, rawStarts, rawValueLengths, rawLines, rawColumns);

        var ck = new int[rawCount]; var cs = new int[rawCount]; var cv = new int[rawCount];
        var n = 0;
        for (var i = 0; i < rawCount; i++)
        {
            if (rawKinds[i] == 136) continue;
            ck[n] = rawKinds[i]; cs[n] = rawStarts[i]; cv[n] = rawValueLengths[i]; n++;
        }

        var funcIndices = new List<int>();
        int brace = 0, bracket = 0, paren = 0;
        for (var i = 0; i < n; i++)
        {
            switch (ck[i])
            {
                case 129: brace++; break;
                case 130: if (brace > 0) brace--; break;
                case 131: bracket++; break;
                case 132: if (bracket > 0) bracket--; break;
                case 127: paren++; break;
                case 128: if (paren > 0) paren--; break;
                case 7: if (brace == 0 && bracket == 0 && paren == 0) funcIndices.Add(i); break;
            }
        }

        var cap = n + 1;
        foreach (var funcIndex in funcIndices)
        {
            var bodyBrace = -1;
            for (var t = funcIndex + 1; t < n; t++) { if (ck[t] == 129) { bodyBrace = t; break; } }
            if (bodyBrace < 0) continue;

            var bk = new int[cap]; var bvs = new int[cap]; var bvl = new int[cap]; var bcs = new int[cap];
            var bcc = new int[cap]; var bci = new int[cap]; var bss = new int[cap]; var bsl = new int[cap];
            var bres = new int[2];
            var nodeCount = _parseStmt(ck, cs, cv, n, bodyBrace, bk, bvs, bvl, bcs, bcc, bci, bss, bsl, bres);
            if (nodeCount <= 0) throw new InvalidOperationException("statement kernel declined a corpus body.");
            // Trim the columnar tables to the actual node count so the scan touches only real nodes.
            var kinds = new int[nodeCount]; var vstarts = new int[nodeCount]; var vlens = new int[nodeCount];
            Array.Copy(bk, kinds, nodeCount); Array.Copy(bvs, vstarts, nodeCount); Array.Copy(bvl, vlens, nodeCount);
            _columnarBodies.Add(new ColumnarBody(kinds, vstarts, vlens));
        }

        // Parity: both passes must produce the same identifier set.
        var astSet = CSharpPass_CollectIdentifiers();
        var columnarSet = ColumnarPass_CollectIdentifiers();
        if (astSet.Count != columnarSet.Count || !astSet.SetEquals(columnarSet))
            throw new InvalidOperationException($"Identifier-set mismatch: AST={astSet.Count}, columnar={columnarSet.Count}.");
    }

    [Benchmark(Baseline = true)]
    public HashSet<string> CSharpPass_CollectIdentifiers()
    {
        var set = new HashSet<string>(StringComparer.Ordinal);
        foreach (var body in _astBodies)
            CollectFromStatement(body, set);
        return set;
    }

    [Benchmark]
    public HashSet<string> ColumnarPass_CollectIdentifiers()
    {
        var set = new HashSet<string>(StringComparer.Ordinal);
        foreach (var body in _columnarBodies)
        {
            var kinds = body.Kinds;
            for (var i = 0; i < kinds.Length; i++)
            {
                if (kinds[i] == 6) // IdentifierExpression
                    set.Add(_source.Substring(body.ValueStarts[i], body.ValueLengths[i]));
            }
        }

        return set;
    }

    // The columnar pass done RIGHT: intern each distinct name once via a span-keyed lookup (no Substring per
    // occurrence). This is how a real columnar pipeline handles names (intern / symbol IDs) -- each distinct
    // name allocates exactly once across the whole pass, instead of once per reference. Expected to beat the
    // C# AST pass on BOTH time and allocation.
    [Benchmark]
    public HashSet<string> ColumnarPass_CollectIdentifiers_Interned()
    {
        var intern = new Dictionary<string, string>(StringComparer.Ordinal);
        var bySpan = intern.GetAlternateLookup<ReadOnlySpan<char>>();
        var set = new HashSet<string>(StringComparer.Ordinal);
        var src = _source.AsSpan();
        foreach (var body in _columnarBodies)
        {
            var kinds = body.Kinds;
            for (var i = 0; i < kinds.Length; i++)
            {
                if (kinds[i] != 6) continue; // IdentifierExpression
                var span = src.Slice(body.ValueStarts[i], body.ValueLengths[i]);
                if (!bySpan.TryGetValue(span, out var name))
                {
                    name = span.ToString();
                    intern[name] = name;
                }

                set.Add(name);
            }
        }

        return set;
    }

    // Recursive C# AST walker covering the node forms the supported corpora use.
    private static void CollectFromStatement(Statement statement, HashSet<string> set)
    {
        switch (statement)
        {
            case BlockStatement b:
                foreach (var s in b.Statements) CollectFromStatement(s, set);
                break;
            case WhileStatement w:
                CollectFromExpression(w.Condition, set);
                CollectFromStatement(w.Body, set);
                break;
            case IfStatement i:
                CollectFromExpression(i.Condition, set);
                CollectFromStatement(i.ThenStatement, set);
                if (i.ElseStatement != null) CollectFromStatement(i.ElseStatement, set);
                break;
            case ReturnStatement r:
                if (r.Value != null) CollectFromExpression(r.Value, set);
                break;
            case ExpressionStatement e:
                CollectFromExpression(e.Expression, set);
                break;
            case VariableDeclarationStatement v:
                if (v.Initializer != null) CollectFromExpression(v.Initializer, set);
                break;
        }
    }

    private static void CollectFromExpression(Expression expression, HashSet<string> set)
    {
        switch (expression)
        {
            case IdentifierExpression id:
                set.Add(id.Name);
                break;
            case BinaryExpression b:
                CollectFromExpression(b.Left, set);
                CollectFromExpression(b.Right, set);
                break;
            case UnaryExpression u:
                CollectFromExpression(u.Operand, set);
                break;
            case ParenthesizedExpression p:
                CollectFromExpression(p.Inner, set);
                break;
            case CastExpression c:
                CollectFromExpression(c.Expression, set);
                break;
            case TernaryExpression t:
                CollectFromExpression(t.Condition, set);
                CollectFromExpression(t.ThenExpression, set);
                CollectFromExpression(t.ElseExpression, set);
                break;
            case AssignmentExpression a:
                CollectFromExpression(a.Target, set);
                CollectFromExpression(a.Value, set);
                break;
            case IndexAccessExpression ix:
                CollectFromExpression(ix.Object, set);
                CollectFromExpression(ix.Index, set);
                break;
            case MemberAccessExpression m:
                CollectFromExpression(m.Object, set);
                break;
            case CallExpression call:
                CollectFromExpression(call.Callee, set);
                foreach (var arg in call.Arguments) CollectFromExpression(arg.Value, set);
                break;
            case NewExpression nw:
                foreach (var arg in nw.ConstructorArguments) CollectFromExpression(arg.Value, set);
                break;
            // literals: nothing to collect.
        }
    }

    private readonly struct ColumnarBody
    {
        public ColumnarBody(int[] kinds, int[] valueStarts, int[] valueLengths)
        {
            Kinds = kinds;
            ValueStarts = valueStarts;
            ValueLengths = valueLengths;
        }

        public int[] Kinds { get; }
        public int[] ValueStarts { get; }
        public int[] ValueLengths { get; }
    }
}
