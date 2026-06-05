using System;
using System.Collections.Generic;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for NL010 namespace-import usage analysis. The current C# path checks each
/// import by repeatedly scanning known type/member names and probing the identifiers collected by
/// the linter. The N# candidate consumes dense namespace ranks, marks used namespaces once, then
/// scans imports linearly.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceLinterUnusedKnownNamespaceImportBenchmarks
{
    private static readonly (string Namespace, string[] Types, string[] Members)[] s_knownNamespaces =
    [
        ("System",
        [
            "DateTime", "DateTimeOffset", "TimeSpan", "Guid", "Uri", "Tuple", "Lazy",
            "Action", "Func", "Console", "Math", "Char", "Exception", "ArgumentException",
            "ArgumentNullException", "ArgumentOutOfRangeException", "InvalidOperationException",
            "NotSupportedException", "NotImplementedException", "FormatException", "OverflowException",
            "Random", "Convert", "Array", "Type", "Attribute", "Environment", "Int32", "String",
            "IDisposable", "IComparable", "IEquatable", "EventHandler", "Nullable", "Span",
            "Memory", "ReadOnlySpan", "ReadOnlyMemory"
        ],
        []),
        ("System.Collections.Generic",
        [
            "List", "Dictionary", "HashSet", "Queue", "Stack", "LinkedList", "SortedList",
            "SortedDictionary", "IEnumerable", "ICollection", "IList", "IDictionary", "ISet",
            "IReadOnlyList", "IReadOnlyCollection", "IReadOnlyDictionary", "IAsyncEnumerable",
            "IEnumerator", "IComparer", "IEqualityComparer"
        ],
        []),
        ("System.Text",
        [
            "StringBuilder", "Encoding"
        ],
        []),
        ("System.Text.RegularExpressions",
        [
            "Regex", "Match", "MatchCollection"
        ],
        []),
        ("System.IO",
        [
            "File", "Directory", "Path", "Stream", "StreamReader", "StreamWriter", "FileStream",
            "MemoryStream", "BinaryReader", "BinaryWriter", "FileInfo", "DirectoryInfo",
            "TextReader", "TextWriter"
        ],
        []),
        ("System.Net.Http",
        [
            "HttpClient", "HttpResponseMessage", "HttpRequestMessage", "HttpContent", "StringContent"
        ],
        []),
        ("System.Text.Json",
        [
            "JsonSerializer", "JsonSerializerOptions", "JsonNamingPolicy", "JsonElement",
            "JsonDocument", "JsonNode"
        ],
        []),
        ("System.Threading.Tasks",
        [
            "Task", "ValueTask", "TaskCompletionSource"
        ],
        []),
        ("System.Threading",
        [
            "CancellationToken", "CancellationTokenSource", "SemaphoreSlim", "Mutex", "Timer", "Thread"
        ],
        []),
        ("System.Linq",
        [
            "Enumerable", "Queryable", "IQueryable", "IOrderedEnumerable", "IGrouping", "ILookup", "Lookup"
        ],
        [
            "Select", "SelectMany", "Where", "OrderBy", "OrderByDescending", "ThenBy", "ThenByDescending",
            "GroupBy", "GroupJoin", "Join", "Distinct", "DistinctBy", "Union", "UnionBy", "Intersect",
            "IntersectBy", "Except", "ExceptBy", "Skip", "SkipWhile", "Take", "TakeWhile", "First",
            "FirstOrDefault", "Last", "LastOrDefault", "Single", "SingleOrDefault", "ElementAt",
            "ElementAtOrDefault", "Count", "LongCount", "Sum", "Min", "MinBy", "Max", "MaxBy",
            "Average", "Aggregate", "Any", "All", "Contains", "ToList", "ToArray", "ToDictionary",
            "ToHashSet", "ToLookup", "Zip", "Concat", "Append", "Prepend", "Reverse", "SequenceEqual",
            "DefaultIfEmpty", "OfType", "Cast", "AsEnumerable", "Chunk", "SkipLast", "TakeLast",
            "TryGetNonEnumeratedCount", "CountBy", "AggregateBy", "Index", "Order", "OrderDescending"
        ])
    ];

    private Func<int[], int, int[], int, int[], int, int, int[], int[], int[], int> _nsharpChecksumInto =
        (_, _, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private Func<int[], int, int[], int, int[], int, int, int[], int[], int[], int> _nsharpIndicesInto =
        (_, _, _, _, _, _, _, _, _, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private HashSet<string> _allCodeIdentifiers = new(StringComparer.Ordinal);
    private HashSet<string> _allMemberAccessNames = new(StringComparer.Ordinal);
    private int _csharpResultCount;
    private int[] _csharpResultIndices = Array.Empty<int>();
    private int _importCount;
    private int[] _importNamespaceRanks = Array.Empty<int>();
    private string[] _importNamespaces = Array.Empty<string>();
    private Dictionary<string, int> _memberNamespaceRanksByName = new(StringComparer.Ordinal);
    private Dictionary<string, HashSet<string>> _namespaceMembers = new(StringComparer.Ordinal);
    private Dictionary<string, HashSet<string>> _namespaceTypes = new(StringComparer.Ordinal);
    private int _namespaceRankCount;
    private int[] _nsharpResultIndices = Array.Empty<int>();
    private int[] _precomputedMemberNamespaceRanks = Array.Empty<int>();
    private int _precomputedMemberRankCount;
    private int[] _precomputedTypeNamespaceRanks = Array.Empty<int>();
    private int _precomputedTypeRankCount;
    private int[] _projectedMemberNamespaceRanks = Array.Empty<int>();
    private int[] _projectedTypeNamespaceRanks = Array.Empty<int>();
    private int[] _touchedNamespaceRanks = Array.Empty<int>();
    private Dictionary<string, int> _typeNamespaceRanksByName = new(StringComparer.Ordinal);
    private int[] _usedNamespaceFlags = Array.Empty<int>();

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpChecksumInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int, int[], int, int, int[], int[], int[], int>>(
                DogfoodCompilerSources.LinterImports,
                "LinterUnusedKnownNamespaceImportChecksumInto");
        _nsharpIndicesInto =
            NSharpCompiledMethod.Bind<Func<int[], int, int[], int, int[], int, int, int[], int[], int[], int>>(
                DogfoodCompilerSources.LinterImports,
                "LinterUnusedKnownNamespaceImportIndicesInto");

        BuildKnownNamespaceMaps();
        BuildCorpus();
        PrecomputeUsedNamespaceRanks();

        var expectedChecksum = CSharpUnusedKnownNamespaceImports_CurrentScan();
        var actualCoreChecksum = NSharpUnusedKnownNamespaceImports_RankedCore();
        if (expectedChecksum != actualCoreChecksum)
        {
            throw new InvalidOperationException(
                $"N# linter unused-import ranked checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualCoreChecksum}.");
        }

        var actualProjectedChecksum = NSharpUnusedKnownNamespaceImports_WithProjection();
        if (expectedChecksum != actualProjectedChecksum)
        {
            throw new InvalidOperationException(
                $"N# linter unused-import projected checksum mismatch for {Corpus}: expected {expectedChecksum}, got {actualProjectedChecksum}.");
        }

        var actualCount = _nsharpIndicesInto(
            _importNamespaceRanks,
            _importCount,
            _precomputedTypeNamespaceRanks,
            _precomputedTypeRankCount,
            _precomputedMemberNamespaceRanks,
            _precomputedMemberRankCount,
            _namespaceRankCount,
            _usedNamespaceFlags,
            _touchedNamespaceRanks,
            _nsharpResultIndices);
        if (actualCount != _csharpResultCount)
        {
            throw new InvalidOperationException(
                $"N# linter unused-import count mismatch for {Corpus}: expected {_csharpResultCount}, got {actualCount}.");
        }

        for (var i = 0; i < _csharpResultCount; i++)
        {
            if (_csharpResultIndices[i] != _nsharpResultIndices[i])
            {
                throw new InvalidOperationException(
                    $"N# linter unused-import mismatch for {Corpus} at result {i}: " +
                    $"expected index {_csharpResultIndices[i]}, got {_nsharpResultIndices[i]}.");
            }
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpUnusedKnownNamespaceImports_CurrentScan()
    {
        _csharpResultCount = 0;
        var checksum = 0;
        for (var i = 0; i < _importCount; i++)
        {
            var ns = _importNamespaces[i];
            var hasKnownTypes = _namespaceTypes.TryGetValue(ns, out var knownTypes);
            var hasKnownMembers = _namespaceMembers.TryGetValue(ns, out var knownMembers);
            var used = true;

            if (hasKnownTypes || hasKnownMembers)
            {
                used = false;
                if (hasKnownTypes)
                    used = knownTypes!.Any(typeName => _allCodeIdentifiers.Contains(typeName));
                if (!used && hasKnownMembers)
                    used = knownMembers!.Any(memberName => _allMemberAccessNames.Contains(memberName));
            }

            if (!used)
            {
                _csharpResultIndices[_csharpResultCount] = i;
                _csharpResultCount++;
                checksum += (i + 1) * 31;
            }
        }

        return checksum + _csharpResultCount;
    }

    [Benchmark]
    public int NSharpUnusedKnownNamespaceImports_RankedCore() =>
        _nsharpChecksumInto(
            _importNamespaceRanks,
            _importCount,
            _precomputedTypeNamespaceRanks,
            _precomputedTypeRankCount,
            _precomputedMemberNamespaceRanks,
            _precomputedMemberRankCount,
            _namespaceRankCount,
            _usedNamespaceFlags,
            _touchedNamespaceRanks,
            _nsharpResultIndices);

    [Benchmark]
    public int NSharpUnusedKnownNamespaceImports_WithProjection()
    {
        var typeRankCount = 0;
        foreach (var identifier in _allCodeIdentifiers)
        {
            if (_typeNamespaceRanksByName.TryGetValue(identifier, out var rank))
            {
                _projectedTypeNamespaceRanks[typeRankCount] = rank;
                typeRankCount++;
            }
        }

        var memberRankCount = 0;
        foreach (var memberName in _allMemberAccessNames)
        {
            if (_memberNamespaceRanksByName.TryGetValue(memberName, out var rank))
            {
                _projectedMemberNamespaceRanks[memberRankCount] = rank;
                memberRankCount++;
            }
        }

        return _nsharpChecksumInto(
            _importNamespaceRanks,
            _importCount,
            _projectedTypeNamespaceRanks,
            typeRankCount,
            _projectedMemberNamespaceRanks,
            memberRankCount,
            _namespaceRankCount,
            _usedNamespaceFlags,
            _touchedNamespaceRanks,
            _nsharpResultIndices);
    }

    private void BuildKnownNamespaceMaps()
    {
        _namespaceTypes = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        _namespaceMembers = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        _typeNamespaceRanksByName = new Dictionary<string, int>(StringComparer.Ordinal);
        _memberNamespaceRanksByName = new Dictionary<string, int>(StringComparer.Ordinal);

        for (var i = 0; i < s_knownNamespaces.Length; i++)
        {
            var rank = i + 1;
            var (ns, types, members) = s_knownNamespaces[i];
            if (types.Length > 0)
            {
                _namespaceTypes[ns] = new HashSet<string>(types, StringComparer.Ordinal);
                foreach (var typeName in types)
                {
                    _typeNamespaceRanksByName[typeName] = rank;
                }
            }

            if (members.Length > 0)
            {
                _namespaceMembers[ns] = new HashSet<string>(members, StringComparer.Ordinal);
                foreach (var memberName in members)
                {
                    _memberNamespaceRanksByName[memberName] = rank;
                }
            }
        }

        _namespaceRankCount = s_knownNamespaces.Length;
    }

    private void BuildCorpus()
    {
        _importCount = Corpus == CompilerLexerCorpus.Representative ? 384 : 8192;
        var identifierNoiseCount = Corpus == CompilerLexerCorpus.Representative ? 256 : 4096;
        var memberNoiseCount = Corpus == CompilerLexerCorpus.Representative ? 192 : 2048;

        _importNamespaces = new string[_importCount];
        _importNamespaceRanks = new int[_importCount];
        _csharpResultIndices = new int[_importCount];
        _nsharpResultIndices = new int[_importCount];
        _precomputedTypeNamespaceRanks = new int[identifierNoiseCount + s_knownNamespaces.Length];
        _precomputedMemberNamespaceRanks = new int[memberNoiseCount + s_knownNamespaces.Length];
        _projectedTypeNamespaceRanks = new int[identifierNoiseCount + s_knownNamespaces.Length];
        _projectedMemberNamespaceRanks = new int[memberNoiseCount + s_knownNamespaces.Length];
        _touchedNamespaceRanks = new int[_namespaceRankCount + 1];
        _usedNamespaceFlags = new int[_namespaceRankCount + 1];

        _allCodeIdentifiers = new HashSet<string>(StringComparer.Ordinal);
        _allMemberAccessNames = new HashSet<string>(StringComparer.Ordinal);

        for (var i = 0; i < _importCount; i++)
        {
            if (i % 11 == 0)
            {
                _importNamespaces[i] = $"Vendor.Package{i % 17}";
                _importNamespaceRanks[i] = 0;
                continue;
            }

            var knownIndex = (i * 7 + i / 5) % s_knownNamespaces.Length;
            var known = s_knownNamespaces[knownIndex];
            _importNamespaces[i] = known.Namespace;
            _importNamespaceRanks[i] = knownIndex + 1;
        }

        for (var i = 0; i < identifierNoiseCount; i++)
        {
            _allCodeIdentifiers.Add($"LocalSymbol{i}");
            _allCodeIdentifiers.Add($"GeneratedType_{i % 97}_{i}");
        }

        for (var i = 0; i < memberNoiseCount; i++)
        {
            _allMemberAccessNames.Add($"LocalMember{i}");
            _allMemberAccessNames.Add($"GeneratedMember_{i % 73}_{i}");
        }

        AddUsedTypeFromNamespace("System", "ReadOnlyMemory");
        AddUsedTypeFromNamespace("System.Collections.Generic", "IEqualityComparer");
        AddUsedTypeFromNamespace("System.Text", "Encoding");
        AddUsedTypeFromNamespace("System.IO", "TextWriter");
        AddUsedTypeFromNamespace("System.Threading.Tasks", "TaskCompletionSource");
        AddUsedTypeFromNamespace("System.Threading", "Thread");
        AddUsedMemberFromNamespace("System.Linq", "OrderDescending");
    }

    private void PrecomputeUsedNamespaceRanks()
    {
        _precomputedTypeRankCount = 0;
        foreach (var identifier in _allCodeIdentifiers)
        {
            if (_typeNamespaceRanksByName.TryGetValue(identifier, out var rank))
            {
                _precomputedTypeNamespaceRanks[_precomputedTypeRankCount] = rank;
                _precomputedTypeRankCount++;
            }
        }

        _precomputedMemberRankCount = 0;
        foreach (var memberName in _allMemberAccessNames)
        {
            if (_memberNamespaceRanksByName.TryGetValue(memberName, out var rank))
            {
                _precomputedMemberNamespaceRanks[_precomputedMemberRankCount] = rank;
                _precomputedMemberRankCount++;
            }
        }
    }

    private void AddUsedTypeFromNamespace(string ns, string typeName)
    {
        if (!_namespaceTypes.TryGetValue(ns, out var knownTypes) || !knownTypes.Contains(typeName))
        {
            throw new InvalidOperationException($"Unknown benchmark type '{ns}.{typeName}'.");
        }

        _allCodeIdentifiers.Add(typeName);
    }

    private void AddUsedMemberFromNamespace(string ns, string memberName)
    {
        if (!_namespaceMembers.TryGetValue(ns, out var knownMembers) || !knownMembers.Contains(memberName))
        {
            throw new InvalidOperationException($"Unknown benchmark member '{ns}.{memberName}'.");
        }

        _allMemberAccessNames.Add(memberName);
    }
}
