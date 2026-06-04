using System;
using System.Linq;
using System.Text;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for diagnostic severity summaries emitted by diagnostics/check/lint JSON.
///
/// The C# baseline models the current formatter shape: three LINQ count passes over the diagnostic
/// severities. The N# candidate counts error/warning/info severities in one compiled hot loop and
/// writes the stable summary counts into caller-owned storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceDiagnosticSummaryBenchmarks
{
    private const int LargeDiagnosticCount = 8192;
    private const int RepresentativeDiagnosticCount = 1024;

    private Func<string[], int, int[], int> _nsharpDiagnosticSeveritySummaryChecksumInto =
        (_, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private int _diagnosticCount;
    private int[] _nsharpCounts = Array.Empty<int>();
    private string[] _severities = Array.Empty<string>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _diagnosticCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDiagnosticCount
            : LargeDiagnosticCount;
        _nsharpDiagnosticSeveritySummaryChecksumInto =
            NSharpCompiledMethod.Bind<Func<string[], int, int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticClusters,
                "DiagnosticSeveritySummaryChecksumInto");

        _severities = new string[_diagnosticCount];
        _nsharpCounts = new int[3];
        BuildSeverities();

        var expectedChecksum = CSharpDiagnosticSeveritySummary_QueryBatch();
        var actualChecksum = NSharpDiagnosticSeveritySummary_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# diagnostic severity summary checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDiagnosticSeveritySummary_QueryBatch()
    {
        var errors = _severities.Count(static severity => severity == "error");
        var warnings = _severities.Count(static severity => severity == "warning");
        var info = _severities.Count(static severity => severity == "info");

        return _diagnosticCount + errors * 31 + warnings * 17 + info * 13;
    }

    [Benchmark]
    public int NSharpDiagnosticSeveritySummary_QueryBatch() =>
        _nsharpDiagnosticSeveritySummaryChecksumInto(_severities, _diagnosticCount, _nsharpCounts);

    private void BuildSeverities()
    {
        for (var i = 0; i < _diagnosticCount; i++)
        {
            _severities[i] = (i % 11) switch
            {
                0 or 1 or 2 or 3 or 4 => "error",
                5 or 6 or 7 => "warning",
                8 or 9 => "info",
                _ => "hint"
            };
        }
    }
}

/// <summary>
/// Dogfood benchmark for the diagnostic cluster grouping kernel used before clustered diagnostic
/// JSON/text materialization.
///
/// The C# baseline mirrors the current formatter shape: LINQ <c>GroupBy</c> over string cluster
/// fields, per-group root selection, and final cluster ordering. The N# candidate consumes
/// preclassified integer dimensions, uses a caller-owned open-addressed grouping table, and writes
/// ordered root indices/counts into caller-owned storage. Public id, next-command, examples, and
/// related-diagnostic strings remain separate materialization boundaries.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceDiagnosticClusterGroupBenchmarks
{
    private const int LargeDiagnosticCount = 8192;
    private const int RepresentativeDiagnosticCount = 1024;

    private Func<int[], int[], int[], int[], int[], int[], int[], string[], int[], int[], int[], int[], int[], int[], int> _nsharpDiagnosticClusterGroupChecksumInto =
        (_, _, _, _, _, _, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _categories = Array.Empty<string>();
    private int[] _categoryIds = Array.Empty<int>();
    private int _diagnosticCount;
    private string[] _codes = Array.Empty<string>();
    private int[] _codeIds = Array.Empty<int>();
    private int[] _columns = Array.Empty<int>();
    private int[] _csharpCounts = Array.Empty<int>();
    private int[] _csharpRootIndices = Array.Empty<int>();
    private string[] _files = Array.Empty<string>();
    private int[] _lines = Array.Empty<int>();
    private int[] _messagePatternIds = Array.Empty<int>();
    private string[] _messagePatterns = Array.Empty<string>();
    private int[] _nsharpCounts = Array.Empty<int>();
    private int[] _nsharpGroupKeyIndices = Array.Empty<int>();
    private int[] _nsharpRootIndices = Array.Empty<int>();
    private int[] _nsharpSlotGroups = Array.Empty<int>();
    private int[] _recipeIds = Array.Empty<int>();
    private string[] _recipes = Array.Empty<string>();
    private int[] _riskIds = Array.Empty<int>();
    private string[] _risks = Array.Empty<string>();
    private int[] _severityIds = Array.Empty<int>();
    private string[] _severities = Array.Empty<string>();
    private int[] _sourceConstructIds = Array.Empty<int>();
    private string[] _sourceConstructs = Array.Empty<string>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _diagnosticCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeDiagnosticCount
            : LargeDiagnosticCount;
        _nsharpDiagnosticClusterGroupChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int[], int[], int[], int[], int[], int[], string[], int[], int[], int[], int[], int[], int[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticClusters,
                "DiagnosticClusterCompactGroupChecksumInto");

        _codes = new string[_diagnosticCount];
        _codeIds = new int[_diagnosticCount];
        _severities = new string[_diagnosticCount];
        _severityIds = new int[_diagnosticCount];
        _categories = new string[_diagnosticCount];
        _categoryIds = new int[_diagnosticCount];
        _sourceConstructs = new string[_diagnosticCount];
        _sourceConstructIds = new int[_diagnosticCount];
        _recipes = new string[_diagnosticCount];
        _recipeIds = new int[_diagnosticCount];
        _risks = new string[_diagnosticCount];
        _riskIds = new int[_diagnosticCount];
        _messagePatterns = new string[_diagnosticCount];
        _messagePatternIds = new int[_diagnosticCount];
        _files = new string[_diagnosticCount];
        _lines = new int[_diagnosticCount];
        _columns = new int[_diagnosticCount];
        _csharpRootIndices = new int[_diagnosticCount];
        _csharpCounts = new int[_diagnosticCount];
        _nsharpSlotGroups = new int[_diagnosticCount * 2 + 1];
        _nsharpGroupKeyIndices = new int[_diagnosticCount];
        _nsharpRootIndices = new int[_diagnosticCount];
        _nsharpCounts = new int[_diagnosticCount];

        BuildDiagnosticClusterFields();

        var expectedChecksum = CSharpDiagnosticClusterGroups_QueryBatch();
        var actualChecksum = NSharpDiagnosticClusterGroups_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# diagnostic cluster grouping checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        var expectedGroupCount = CountGroups(_csharpCounts);
        var actualGroupCount = CountGroups(_nsharpCounts);
        if (expectedGroupCount != actualGroupCount)
        {
            throw new InvalidOperationException(
                $"N# diagnostic cluster grouping count mismatch for {Corpus}: expected {expectedGroupCount}, got {actualGroupCount}.");
        }

        for (var i = 0; i < expectedGroupCount; i++)
        {
            if (_csharpRootIndices[i] != _nsharpRootIndices[i] || _csharpCounts[i] != _nsharpCounts[i])
            {
                throw new InvalidOperationException(
                    $"N# diagnostic cluster grouping mismatch for {Corpus} at group {i}: " +
                    $"expected root/count {_csharpRootIndices[i]}/{_csharpCounts[i]}, " +
                    $"got {_nsharpRootIndices[i]}/{_nsharpCounts[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDiagnosticClusterGroups_QueryBatch()
    {
        Array.Clear(_csharpRootIndices);
        Array.Clear(_csharpCounts);

        var groups = Enumerable.Range(0, _diagnosticCount)
            .GroupBy(i => new
            {
                Severity = _severities[i],
                Code = _codes[i],
                Category = _categories[i],
                SourceConstruct = _sourceConstructs[i],
                Recipe = _recipes[i],
                Risk = _risks[i],
                MessagePattern = _messagePatterns[i]
            })
            .Select(group =>
            {
                var rootIndex = group
                    .OrderBy(i => _lines[i])
                    .ThenBy(i => _columns[i])
                    .ThenBy(i => _files[i], StringComparer.OrdinalIgnoreCase)
                    .First();
                return new
                {
                    RootIndex = rootIndex,
                    Count = group.Count()
                };
            })
            .OrderByDescending(group => group.Count)
            .ThenBy(group => _files[group.RootIndex], StringComparer.OrdinalIgnoreCase)
            .ThenBy(group => _lines[group.RootIndex])
            .ThenBy(group => _columns[group.RootIndex])
            .ToArray();

        var checksum = groups.Length;
        for (var i = 0; i < groups.Length; i++)
        {
            _csharpRootIndices[i] = groups[i].RootIndex;
            _csharpCounts[i] = groups[i].Count;
            checksum += (groups[i].RootIndex + 1) * 31 + groups[i].Count * 17;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpDiagnosticClusterGroups_QueryBatch() =>
        _nsharpDiagnosticClusterGroupChecksumInto(
            _codeIds,
            _severityIds,
            _categoryIds,
            _sourceConstructIds,
            _recipeIds,
            _riskIds,
            _messagePatternIds,
            _files,
            _lines,
            _columns,
            _nsharpSlotGroups,
            _nsharpGroupKeyIndices,
            _nsharpRootIndices,
            _nsharpCounts);

    private void BuildDiagnosticClusterFields()
    {
        for (var i = 0; i < _diagnosticCount; i++)
        {
            var shape = i % 8;
            _codes[i] = shape switch
            {
                0 or 1 => "NL102",
                2 => "NL703",
                3 => "NL301",
                4 => "NL201",
                5 => "NL202",
                6 => "NL303",
                _ => "NL999"
            };
            _codeIds[i] = shape switch
            {
                0 or 1 => 102,
                2 => 703,
                3 => 301,
                4 => 201,
                5 => 202,
                6 => 303,
                _ => 999
            };
            _severities[i] = shape switch
            {
                0 or 1 or 2 or 5 => "error",
                3 or 6 => "warning",
                4 => "info",
                _ => "hint"
            };
            _severityIds[i] = shape switch
            {
                0 or 1 or 2 or 5 => 1,
                3 or 6 => 2,
                4 => 3,
                _ => 4
            };
            _categories[i] = shape switch
            {
                0 => "syntax-missing-delimiter",
                1 => "syntax-missing-terminator",
                2 => "import-cycle",
                3 => "identifier-resolution",
                4 => "type-resolution",
                5 => "type-mismatch",
                6 => "member-resolution",
                _ => "diagnostic-message-shape"
            };
            _categoryIds[i] = shape + 1;
            _sourceConstructs[i] = shape switch
            {
                0 => "function-declaration",
                1 => "variable-declaration",
                2 => "import",
                3 => "variable-declaration",
                4 => "class-declaration",
                5 => "return-statement",
                6 => "call-or-construction",
                _ => "unknown-construct"
            };
            _sourceConstructIds[i] = shape switch
            {
                0 => 1,
                1 or 3 => 2,
                2 => 3,
                4 => 4,
                5 => 5,
                6 => 6,
                _ => 7
            };
            _recipes[i] = shape switch
            {
                0 => "syntax:delimiter-balancing",
                1 => "syntax:statement-boundary",
                2 => "architecture:extract-shared-module-or-invert-dependency",
                3 => "symbols:missing-import-or-qualification",
                4 => "types:resolve-type-or-import",
                5 => "refactor:signature-or-expression-shape",
                6 => "members:api-rename-or-extension-import",
                _ => "manual-triage:inspect-root-diagnostic"
            };
            _recipeIds[i] = shape + 1;
            _risks[i] = shape switch
            {
                0 or 1 or 2 => "high",
                3 or 4 or 5 or 6 => "medium",
                _ => "low"
            };
            _riskIds[i] = shape switch
            {
                0 or 1 or 2 => 1,
                3 or 4 or 5 or 6 => 2,
                _ => 3
            };
            _messagePatterns[i] = $"Expected diagnostic shape {i % 64} while preserving cluster grouping";
            _messagePatternIds[i] = i % 64;
            _files[i] = (i % 11) switch
            {
                0 => $"/repo/src/Program{i % 17}.nl",
                1 => $"/repo/src/generated/File-{i % 19}.nl",
                2 => $"/repo/src/with space/File {i % 13}.nl",
                3 => $@"C:\repo\module\File{i % 23}.nl",
                4 => $"/repo/src/quoted\"File{i % 29}.nl",
                5 => "/repo/src/Main.nl",
                6 => $"/repo/src/café/Module{i % 7}.nl",
                _ => $"/repo/src/[weird]/File{i % 31}.nl"
            };
            _lines[i] = (i * 37 % 400) + 1;
            _columns[i] = (i * 17 % 80) + 1;
        }
    }

    private static int CountGroups(int[] counts)
    {
        var count = 0;
        while (count < counts.Length && counts[count] > 0)
        {
            count++;
        }

        return count;
    }
}

/// <summary>
/// Dogfood benchmark for diagnostic cluster id creation used by clustered diagnostics JSON.
///
/// The C# baseline mirrors the current formatter shape: build one composite key string, hash the
/// key characters, then materialize the public <c>diag-{hex}</c> id. The N# candidate hashes each
/// stable cluster field directly and writes ids into caller-owned storage, avoiding the temporary
/// composite key allocation.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceDiagnosticClusterIdBenchmarks
{
    private const int LargeClusterCount = 8192;
    private const int RepresentativeClusterCount = 1024;

    private Func<string[], string[], string[], string[], string[], string[], string[], int> _nsharpDiagnosticClusterIdChecksumInto =
        (_, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _categories = Array.Empty<string>();
    private string[] _codes = Array.Empty<string>();
    private int _clusterCount;
    private string[] _csharpIds = Array.Empty<string>();
    private string[] _messagePatterns = Array.Empty<string>();
    private string[] _nsharpIds = Array.Empty<string>();
    private string[] _recipes = Array.Empty<string>();
    private string[] _severities = Array.Empty<string>();
    private string[] _sourceConstructs = Array.Empty<string>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _clusterCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeClusterCount
            : LargeClusterCount;
        _nsharpDiagnosticClusterIdChecksumInto =
            NSharpCompiledMethod.Bind<Func<string[], string[], string[], string[], string[], string[], string[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticClusters,
                "DiagnosticClusterIdChecksumInto");

        _codes = new string[_clusterCount];
        _severities = new string[_clusterCount];
        _categories = new string[_clusterCount];
        _sourceConstructs = new string[_clusterCount];
        _recipes = new string[_clusterCount];
        _messagePatterns = new string[_clusterCount];
        _csharpIds = new string[_clusterCount];
        _nsharpIds = new string[_clusterCount];

        BuildClusterFields();

        var expectedChecksum = CSharpDiagnosticClusterIds_QueryBatch();
        var actualChecksum = NSharpDiagnosticClusterIds_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# diagnostic cluster id checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpIds.SequenceEqual(_nsharpIds))
        {
            var mismatch = FirstMismatch();
            throw new InvalidOperationException(
                $"N# diagnostic cluster id mismatch for {Corpus} at cluster {mismatch}: " +
                $"expected {_csharpIds[mismatch]}, got {_nsharpIds[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDiagnosticClusterIds_QueryBatch()
    {
        var checksum = _clusterCount;
        for (var i = 0; i < _clusterCount; i++)
        {
            var id = CreateClusterId(
                _codes[i],
                _severities[i],
                _categories[i],
                _sourceConstructs[i],
                _recipes[i],
                _messagePatterns[i]);
            _csharpIds[i] = id;
            checksum += id.Length * 31;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpDiagnosticClusterIds_QueryBatch() =>
        _nsharpDiagnosticClusterIdChecksumInto(
            _codes,
            _severities,
            _categories,
            _sourceConstructs,
            _recipes,
            _messagePatterns,
            _nsharpIds);

    private void BuildClusterFields()
    {
        for (var i = 0; i < _clusterCount; i++)
        {
            var shape = i % 8;
            _codes[i] = shape switch
            {
                0 => "NL102",
                1 => "NL102",
                2 => "NL703",
                3 => "NL301",
                4 => "NL201",
                5 => "NL202",
                6 => "NL303",
                _ => "NL900"
            };
            _severities[i] = i % 13 == 0 ? "warning" : "error";
            _categories[i] = shape switch
            {
                0 => "syntax-missing-delimiter",
                1 => "syntax-missing-terminator",
                2 => "import-cycle",
                3 => "identifier-resolution",
                4 => "type-resolution",
                5 => "type-mismatch",
                6 => "member-resolution",
                _ => "diagnostic-message-shape"
            };
            _sourceConstructs[i] = shape switch
            {
                0 => "function-declaration",
                1 => "variable-declaration",
                2 => "import",
                3 => "variable-declaration",
                4 => "class-declaration",
                5 => "return-statement",
                6 => "call-or-construction",
                _ => "unknown-construct"
            };
            _recipes[i] = shape switch
            {
                0 => "syntax:delimiter-balancing",
                1 => "syntax:statement-boundary",
                2 => "architecture:extract-shared-module-or-invert-dependency",
                3 => "symbols:missing-import-or-qualification",
                4 => "types:resolve-type-or-import",
                5 => "refactor:signature-or-expression-shape",
                6 => "members:api-rename-or-extension-import",
                _ => "manual-triage:inspect-root-diagnostic"
            };
            _messagePatterns[i] =
                $"Expected diagnostic shape # while processing generated module {i % 97} " +
                $"and preserving cluster grouping for workspace shard {i % 31}";
        }
    }

    private static string CreateClusterId(
        string code,
        string severity,
        string category,
        string sourceConstruct,
        string recipe,
        string messagePattern)
    {
        var key = $"{code}|{severity}|{category}|{sourceConstruct}|{recipe}|{messagePattern}";
        var hash = 17;
        foreach (var c in key)
        {
            hash = (hash * 31) + c;
        }

        return $"diag-{Math.Abs(hash):x}";
    }

    private int FirstMismatch()
    {
        for (var i = 0; i < _csharpIds.Length; i++)
        {
            if (_csharpIds[i] != _nsharpIds[i])
            {
                return i;
            }
        }

        return _csharpIds.Length;
    }
}

/// <summary>
/// Dogfood benchmark for diagnostic cluster next-command construction used by clustered diagnostic
/// JSON and text output.
///
/// The C# baseline mirrors the current formatter helper: escape the root file path with a LINQ
/// safety scan and replacement-based quoting, then materialize <c>nlc query inspect</c>. The N#
/// candidate performs the safety scan directly and writes commands into caller-owned storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceCodeIntelligenceDiagnosticClusterNextCommandBenchmarks
{
    private const int LargeClusterCount = 8192;
    private const int RepresentativeClusterCount = 1024;

    private Func<string[], int[], int[], string[], int> _nsharpDiagnosticClusterNextCommandChecksumInto =
        (_, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private string[] _csharpCommands = Array.Empty<string>();
    private int _clusterCount;
    private int[] _columns = Array.Empty<int>();
    private string[] _files = Array.Empty<string>();
    private int[] _lines = Array.Empty<int>();
    private string[] _nsharpCommands = Array.Empty<string>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _clusterCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeClusterCount
            : LargeClusterCount;
        _nsharpDiagnosticClusterNextCommandChecksumInto =
            NSharpCompiledMethod.Bind<Func<string[], int[], int[], string[], int>>(
                DogfoodCompilerSources.CodeIntelligenceDiagnosticClusters,
                "DiagnosticClusterNextCommandChecksumInto");

        _files = new string[_clusterCount];
        _lines = new int[_clusterCount];
        _columns = new int[_clusterCount];
        _csharpCommands = new string[_clusterCount];
        _nsharpCommands = new string[_clusterCount];

        BuildRootLocations();

        var expectedChecksum = CSharpDiagnosticClusterNextCommands_QueryBatch();
        var actualChecksum = NSharpDiagnosticClusterNextCommands_QueryBatch();
        if (expectedChecksum != actualChecksum)
        {
            throw new InvalidOperationException(
                $"N# diagnostic cluster next-command checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualChecksum}.");
        }

        if (!_csharpCommands.SequenceEqual(_nsharpCommands))
        {
            var mismatch = FirstMismatch();
            throw new InvalidOperationException(
                $"N# diagnostic cluster next-command mismatch for {Corpus} at cluster {mismatch}: " +
                $"expected {_csharpCommands[mismatch]}, got {_nsharpCommands[mismatch]}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpDiagnosticClusterNextCommands_QueryBatch()
    {
        var checksum = _clusterCount;
        for (var i = 0; i < _clusterCount; i++)
        {
            var command = BuildDiagnosticClusterNextCommand(_files[i], _lines[i], _columns[i]);
            _csharpCommands[i] = command;
            checksum += command.Length * 31;
        }

        return checksum;
    }

    [Benchmark]
    public int NSharpDiagnosticClusterNextCommands_QueryBatch() =>
        _nsharpDiagnosticClusterNextCommandChecksumInto(
            _files,
            _lines,
            _columns,
            _nsharpCommands);

    private void BuildRootLocations()
    {
        for (var i = 0; i < _clusterCount; i++)
        {
            _files[i] = (i % 8) switch
            {
                0 => $"/repo/src/Program{i % 97}.nl",
                1 => $"/repo/src/generated/File-{i % 193}.nl",
                2 => $"/repo/src/with space/File {i % 89}.nl",
                3 => $@"C:\repo\module\File{i % 157}.nl",
                4 => $"/repo/src/quoted\"File{i % 71}.nl",
                5 => "   ",
                6 => $"/repo/src/café/Module{i % 67}.nl",
                _ => $"/repo/src/[weird]/File{i % 101}.nl"
            };
            _lines[i] = i % 400 + 1;
            _columns[i] = i % 80 + 1;
        }
    }

    private static string BuildDiagnosticClusterNextCommand(string file, int line, int column)
    {
        file = EscapeCommandArgument(file);
        return $"nlc query inspect --file {file} --pos {line}:{column}";
    }

    private static string EscapeCommandArgument(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "\"\"";
        }

        if (value.All(c => char.IsLetterOrDigit(c) || c is '/' or '.' or '_' or '-'))
        {
            return value;
        }

        return $"\"{value.Replace("\\", "\\\\").Replace("\"", "\\\"")}\"";
    }

    private int FirstMismatch()
    {
        for (var i = 0; i < _csharpCommands.Length; i++)
        {
            if (_csharpCommands[i] != _nsharpCommands[i])
            {
                return i;
            }
        }

        return _csharpCommands.Length;
    }
}

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
