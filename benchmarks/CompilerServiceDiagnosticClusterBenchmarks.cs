using System;
using System.Linq;
using System.Text;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for diagnostic cluster trait classification used by CLI/query diagnostic
/// grouping.
///
/// The C# baseline models the previous production shape in <c>OutputFormatter</c>: each diagnostic
/// lowercases its message and source snippet, classifies into a full trait record, and allocates the
/// suggested-action array. The N# candidate classifies a batch into compact caller-owned category
/// and source-construct buffers; the formatter still materializes public JSON message patterns
/// after this hot trait pass.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceDiagnosticClusterTraitBenchmarks
{
    private const int LargeDiagnosticCount = 8192;
    private const int RepresentativeDiagnosticCount = 1024;

    private Func<string[], string[], string[], int[], int[], int> _nsharpDiagnosticClusterTraitChecksumInto =
        (_, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int[] _csharpCategories = Array.Empty<int>();
    private int[] _csharpSourceConstructs = Array.Empty<int>();
    private string[] _codes = Array.Empty<string>();
    private BenchmarkDiagnostic[] _diagnostics = Array.Empty<BenchmarkDiagnostic>();
    private int _diagnosticCount;
    private string[] _messages = Array.Empty<string>();
    private int[] _nsharpCategories = Array.Empty<int>();
    private int[] _nsharpSourceConstructs = Array.Empty<int>();
    private string[] _snippets = Array.Empty<string>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _diagnosticCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDiagnosticCount
            : LargeDiagnosticCount;
        _nsharpDiagnosticClusterTraitChecksumInto =
            NSharpCompiledMethod.Bind<Func<string[], string[], string[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticClusters,
                "DiagnosticClusterTraitChecksumInto");

        _diagnostics = new BenchmarkDiagnostic[_diagnosticCount];
        _codes = new string[_diagnosticCount];
        _messages = new string[_diagnosticCount];
        _snippets = new string[_diagnosticCount];
        _csharpCategories = new int[_diagnosticCount];
        _csharpSourceConstructs = new int[_diagnosticCount];
        _nsharpCategories = new int[_diagnosticCount];
        _nsharpSourceConstructs = new int[_diagnosticCount];

        BuildDiagnostics();

        var expectedChecksum = CSharpDiagnosticClusterTraits_QueryBatch();
        var actualChecksum = NSharpDiagnosticClusterTraits_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# diagnostic cluster trait checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpCategories.SequenceEqual(_nsharpCategories)
            || !_csharpSourceConstructs.SequenceEqual(_nsharpSourceConstructs))
        {
            var mismatch = FirstMismatch();
            throw new InvalidOperationException(
                $"N# diagnostic cluster trait mismatch for {Corpus} at diagnostic {mismatch}: " +
                $"expected {_csharpCategories[mismatch]}/{_csharpSourceConstructs[mismatch]}, " +
                $"got {_nsharpCategories[mismatch]}/{_nsharpSourceConstructs[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDiagnosticClusterTraits_QueryBatch()
    {
        var checksum = _diagnosticCount;
        for (var i = 0; i < _diagnostics.Length; i++)
        {
            var traits = ClassifyDiagnostic(_diagnostics[i]);
            var category = DiagnosticCategoryIndex(traits.Category);
            var sourceConstruct = DiagnosticSourceConstructIndex(traits.SourceConstruct);

            _csharpCategories[i] = category;
            _csharpSourceConstructs[i] = sourceConstruct;

            checksum += category * 31 + sourceConstruct * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpDiagnosticClusterTraits_QueryBatch() =>
        _nsharpDiagnosticClusterTraitChecksumInto(
            _codes,
            _messages,
            _snippets,
            _nsharpCategories,
            _nsharpSourceConstructs);

    private void BuildDiagnostics()
    {
        for (var i = 0; i < _diagnosticCount; i++)
        {
            var diagnostic = BuildDiagnostic(i);
            _diagnostics[i] = diagnostic;
            _codes[i] = diagnostic.Code;
            _messages[i] = diagnostic.Message;
            _snippets[i] = diagnostic.SourceSnippet;
        }
    }

    private static BenchmarkDiagnostic BuildDiagnostic(int index)
    {
        var suffix =
            $" while compiling generated module {index % 97} after incremental query invalidation and semantic recovery pass {index}. " +
            $"The diagnostic renderer preserved enough context for CLI clustering, editor grouping, and LLM query triage in workspace shard {index % 31}.";

        var shape = index % 16;
        if (shape == 15)
        {
            return new BenchmarkDiagnostic(
                "NL900",
                $"Analyzer AB{index} reported unusual pattern {index}{suffix}",
                $"    ??? {index}");
        }

        shape = shape % 7;
        return shape switch
        {
            0 => new BenchmarkDiagnostic(
                "NL102",
                $"Expected token ')' at line {index + 10} column {index % 41 + 1}{suffix}",
                $"public func Compute{index}(value: int {{"),
            1 => new BenchmarkDiagnostic(
                "NL102",
                $"Missing semicolon after 'foo{index}' in generated statement {index}{suffix}",
                $"    result{index} := Compute{index}()"),
            2 => new BenchmarkDiagnostic(
                "NL703",
                $"Circular import detected between Module{index} and Shared{index % 13}{suffix}",
                $"import Shared.Module{index % 13}"),
            3 => new BenchmarkDiagnostic(
                "NL301",
                $"Undefined variable 'customer{index}' in expression {index}{suffix}",
                $"    customer{index} := lookup()"),
            4 => new BenchmarkDiagnostic(
                "NL201",
                $"Type not found 'Invoice{index}' in declaration {index}{suffix}",
                $"class InvoiceController{index} : MissingBase {{"),
            5 => new BenchmarkDiagnostic(
                "NL202",
                $"Type mismatch: expected Int32 but found String at assignment {index}{suffix}",
                $"return payload{index}"),
            6 => new BenchmarkDiagnostic(
                "NL303",
                $"Member 'LengthEx{index}' does not exist on type Customer{index}{suffix}",
                $"    print customer.LengthEx{index}()"),
            _ => throw new InvalidOperationException($"Unexpected diagnostic benchmark shape {shape}.")
        };
    }

    private static DiagnosticClusterTraits ClassifyDiagnostic(BenchmarkDiagnostic diagnostic)
    {
        var message = diagnostic.Message ?? string.Empty;
        var snippet = diagnostic.SourceSnippet ?? string.Empty;
        var code = diagnostic.Code ?? string.Empty;
        var messageLower = message.ToLowerInvariant();
        var snippetLower = snippet.ToLowerInvariant();

        if (code == "NL102" || messageLower.Contains("expected token") || messageLower.Contains("missing"))
        {
            var construct = InferSourceConstruct(snippetLower);
            var shape = messageLower.Contains(";", StringComparison.Ordinal) || messageLower.Contains("semicolon", StringComparison.Ordinal)
                ? "syntax-missing-terminator"
                : "syntax-missing-delimiter";
            var recipe = shape == "syntax-missing-terminator"
                ? "syntax:statement-boundary"
                : "syntax:delimiter-balancing";
            return new DiagnosticClusterTraits(
                shape,
                construct,
                recipe,
                "high",
                NormalizeMessagePattern(message),
                new[]
                {
                    "Fix the earliest statement-boundary parse error first; later syntax diagnostics are often cascades.",
                    "Inspect the refactor or code-generation path that emitted this construct and add a delimiter/terminator regression test."
                });
        }

        if (code == "NL703" || messageLower.Contains("circular import"))
        {
            return new DiagnosticClusterTraits(
                "import-cycle",
                "import",
                "architecture:extract-shared-module-or-invert-dependency",
                "high",
                NormalizeMessagePattern(message),
                new[]
                {
                    "Break the cycle at the reported import path by moving shared declarations into a third file/package or inverting one dependency.",
                    "Rerun `nlc check` after removing the cycle; unused-import warnings in the same files may be cascades."
                });
        }

        if (code == "NL301" || code == "NL412" || messageLower.Contains("undefined variable") || messageLower.Contains("undefined symbol"))
        {
            return new DiagnosticClusterTraits(
                "identifier-resolution",
                InferSourceConstruct(snippetLower),
                "symbols:missing-import-or-qualification",
                "medium",
                NormalizeMessagePattern(message),
                new[]
                {
                    "Resolve the first missing identifier by adding the import/qualification or correcting the declaration name.",
                    "Rerun diagnostics after the root symbol is resolved; dependent member/type errors may disappear."
                });
        }

        if (code == "NL201" || code == "NL302" || messageLower.Contains("type not found") || messageLower.Contains("undefined type") || messageLower.Contains("cannot resolve type"))
        {
            return new DiagnosticClusterTraits(
                "type-resolution",
                InferSourceConstruct(snippetLower),
                "types:resolve-type-or-import",
                "medium",
                NormalizeMessagePattern(message),
                new[]
                {
                    "Resolve the type/import at the earliest root location before chasing downstream uses.",
                    "Check whether the source construct needs full qualification or a project reference."
                });
        }

        if (code == "NL202" || messageLower.Contains("type mismatch"))
        {
            return new DiagnosticClusterTraits(
                "type-mismatch",
                InferSourceConstruct(snippetLower),
                "refactor:signature-or-expression-shape",
                "medium",
                NormalizeMessagePattern(message),
                new[]
                {
                    "Compare the expected and actual types at the root example and update the refactor recipe that changed the expression/signature shape.",
                    "Prefer fixing the producer expression over adding casts to each cascaded consumer."
                });
        }

        if (code == "NL303" || messageLower.Contains("member") || messageLower.Contains("method"))
        {
            return new DiagnosticClusterTraits(
                "member-resolution",
                InferSourceConstruct(snippetLower),
                "members:api-rename-or-extension-import",
                "medium",
                NormalizeMessagePattern(message),
                new[]
                {
                    "Verify the API/member name for the root receiver before fixing repeated call sites.",
                    "Check whether an extension-method import or receiver type conversion was dropped."
                });
        }

        return new DiagnosticClusterTraits(
            "diagnostic-message-shape",
            InferSourceConstruct(snippetLower),
            "manual-triage:inspect-root-diagnostic",
            "low",
            NormalizeMessagePattern(message),
            new[]
            {
                "Start at the root example and decide whether this is a source, refactor, or compiler diagnostic issue.",
                "After fixing the root cause, rerun diagnostics and compare the remaining cluster counts."
            });
    }

    private static string InferSourceConstruct(string sourceSnippetLower)
    {
        var snippet = sourceSnippetLower.TrimStart();
        if (snippet.StartsWith("let ", StringComparison.Ordinal) || snippet.Contains(" := ", StringComparison.Ordinal) || snippet.Contains(":=", StringComparison.Ordinal))
        {
            return "variable-declaration";
        }

        var declarationSnippet = StripLeadingDeclarationModifiers(snippet);
        if (declarationSnippet.StartsWith("func ", StringComparison.Ordinal) || declarationSnippet.StartsWith("func* ", StringComparison.Ordinal))
        {
            return "function-declaration";
        }

        if (snippet.StartsWith("class ", StringComparison.Ordinal))
        {
            return "class-declaration";
        }

        if (snippet.StartsWith("interface ", StringComparison.Ordinal))
        {
            return "interface-declaration";
        }

        if (snippet.StartsWith("import ", StringComparison.Ordinal) || snippet.StartsWith("using ", StringComparison.Ordinal))
        {
            return "import";
        }

        if (snippet.StartsWith("return ", StringComparison.Ordinal))
        {
            return "return-statement";
        }

        if (snippet.StartsWith("if ", StringComparison.Ordinal) || snippet.StartsWith("for ", StringComparison.Ordinal) || snippet.StartsWith("while ", StringComparison.Ordinal) || snippet.StartsWith("match ", StringComparison.Ordinal))
        {
            return "control-flow";
        }

        if (snippet.Contains("(", StringComparison.Ordinal) && snippet.Contains(")", StringComparison.Ordinal))
        {
            return "call-or-construction";
        }

        return "unknown-construct";
    }

    private static string StripLeadingDeclarationModifiers(string snippet)
    {
        while (true)
        {
            var trimmed = snippet.TrimStart();
            if (trimmed.StartsWith("async ", StringComparison.Ordinal))
            {
                snippet = trimmed["async ".Length..];
                continue;
            }

            if (trimmed.StartsWith("static ", StringComparison.Ordinal))
            {
                snippet = trimmed["static ".Length..];
                continue;
            }

            if (trimmed.StartsWith("override ", StringComparison.Ordinal))
            {
                snippet = trimmed["override ".Length..];
                continue;
            }

            if (trimmed.StartsWith("public ", StringComparison.Ordinal))
            {
                snippet = trimmed["public ".Length..];
                continue;
            }

            if (trimmed.StartsWith("private ", StringComparison.Ordinal))
            {
                snippet = trimmed["private ".Length..];
                continue;
            }

            if (trimmed.StartsWith("protected ", StringComparison.Ordinal))
            {
                snippet = trimmed["protected ".Length..];
                continue;
            }

            if (trimmed.StartsWith("internal ", StringComparison.Ordinal))
            {
                snippet = trimmed["internal ".Length..];
                continue;
            }

            return trimmed;
        }
    }

    private static string NormalizeMessagePattern(string message)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            return "unknown-message";
        }

        var builder = new StringBuilder(message.Length);
        var inQuoted = false;
        foreach (var current in message)
        {
            if (current == '\'' || current == '"')
            {
                inQuoted = !inQuoted;
                if (inQuoted)
                {
                    builder.Append("{value}");
                }

                continue;
            }

            if (!inQuoted)
            {
                builder.Append(char.IsDigit(current) ? '#' : current);
            }
        }

        return builder.ToString().Trim();
    }

    private static int DiagnosticCategoryIndex(string category) => category switch
    {
        "syntax-missing-terminator" => 0,
        "syntax-missing-delimiter" => 1,
        "import-cycle" => 2,
        "identifier-resolution" => 3,
        "type-resolution" => 4,
        "type-mismatch" => 5,
        "member-resolution" => 6,
        _ => 7
    };

    private static int DiagnosticSourceConstructIndex(string sourceConstruct) => sourceConstruct switch
    {
        "variable-declaration" => 0,
        "function-declaration" => 1,
        "class-declaration" => 2,
        "interface-declaration" => 3,
        "import" => 4,
        "return-statement" => 5,
        "control-flow" => 6,
        "call-or-construction" => 7,
        _ => 8
    };

    private int FirstMismatch()
    {
        for (var i = 0; i < _csharpCategories.Length; i++)
        {
            if (_csharpCategories[i] != _nsharpCategories[i]
                || _csharpSourceConstructs[i] != _nsharpSourceConstructs[i])
            {
                return i;
            }
        }

        return _csharpCategories.Length;
    }

    private sealed record BenchmarkDiagnostic(string Code, string Message, string SourceSnippet);

    private sealed record DiagnosticClusterTraits(
        string Category,
        string SourceConstruct,
        string Recipe,
        string Risk,
        string MessagePattern,
        string[] SuggestedNextActions);
}
