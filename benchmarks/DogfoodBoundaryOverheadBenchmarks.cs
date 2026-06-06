using System;
using System.Runtime.CompilerServices;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Decomposition probe for the dogfood "N# is slower on tiny inputs" rejections (units 4 & 6).
///
/// Hypothesis: the per-call floor that sinks tiny inputs is NOT N# being slow — it is the
/// non-inlinable DELEGATE DISPATCH through which both the benchmark and the production
/// <c>*DogfoodAdapter</c> invoke the kernel (<see cref="NSharpCompiledMethod.Bind"/> returns a
/// <c>Delegate.CreateDelegate</c> open delegate). The C# baseline is inlined; the N# row is a
/// delegate call. To prove the floor is indirection (not language), this probe also routes the
/// IDENTICAL C# scan through a <c>Func&lt;&gt;</c> delegate: if C#-via-delegate ≈ N#-via-delegate,
/// the gap is dispatch, not N#.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class DogfoodDelegateDispatchFloorBenchmarks
{
    private Func<int> _nsharpReturnConst = () => 0;
    private readonly Func<int> _csharpReturnConstDelegate = () => 12345;

    [GlobalSetup]
    public void Setup()
    {
        // Minimal N# body: isolates the bare dispatch cost of a bound N# delegate.
        _nsharpReturnConst = NSharpCompiledMethod.Bind<Func<int>>(
            "func ReturnConst(): int {\n    return 12345\n}\n",
            "ReturnConst");

        if (_nsharpReturnConst() != 12345)
            throw new InvalidOperationException("N# ReturnConst parity failed.");
    }

    // Fully inlinable: the JIT folds this to a constant. This is the C# "production" shape when
    // the callee lives in-assembly and is not hidden behind a delegate.
    [Benchmark(Baseline = true)]
    public int CSharp_Direct() => CSharpReturnConst();

    // Same trivial C# body, but reached through a Func<> — the JIT cannot inline through it.
    [Benchmark]
    public int CSharp_ViaDelegate() => _csharpReturnConstDelegate();

    // The N# kernel, reached through the same kind of bound delegate the adapter uses.
    [Benchmark]
    public int NSharp_ViaDelegate() => _nsharpReturnConst();

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static int CSharpReturnConst() => 12345;
}

/// <summary>
/// Input-size sweep for the declared-type exact-name lookup (unit 6). Finds the crossover point
/// where the N# delegate stops losing to inlined C#. Below the crossover a size-threshold hybrid
/// must fall back to C# to honor "never slower than C#"; above it, route N#.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class DogfoodDeclaredTypeLookupCrossoverBenchmarks
{
    // Func signature of DeclaredTypeExactNameFirstIndex(names, tailHashes, typeName, queryTailHash, count).
    private Func<string[], int[], string, int, int, int> _nsharpExactNameFirstIndex =
        (_, _, _, _, _) => 0;

    private readonly Func<string[], int[], string, int, int, int> _csharpDelegate = CSharpExactNameFirstIndex;

    private string[] _names = Array.Empty<string>();
    private int[] _tailHashes = Array.Empty<int>();
    private string _target = "Match";
    private int _queryTailHash;

    [Params(2, 4, 8, 16, 32, 64, 128, 256)]
    public int Size { get; set; }

    // First  = early match at index 0 → constant ~1-comparison body, isolates the fixed per-call
    //          floor (worst case for N#).
    // None   = target absent → full scan of Size elements, reveals how the fixed floor amortizes
    //          as per-call work grows (parallel slopes => no per-element disadvantage).
    [Params(MatchMode.First, MatchMode.None)]
    public MatchMode Match { get; set; }

    public enum MatchMode { First, None }

    [GlobalSetup]
    public void Setup()
    {
        _nsharpExactNameFirstIndex =
            NSharpCompiledMethod.Bind<Func<string[], int[], string, int, int, int>>(
                DogfoodCompilerSources.TypeLookup, "DeclaredTypeExactNameFirstIndex");

        _names = new string[Size];
        _tailHashes = new int[Size];
        _target = "Match";
        _queryTailHash = TailHash(_target);
        for (var i = 0; i < Size; i++)
            _names[i] = "Other" + i;
        if (Match == MatchMode.First)
            _names[0] = _target; // constant ~1-comparison body; otherwise target is absent (full scan)
        for (var i = 0; i < Size; i++)
            _tailHashes[i] = TailHash(_names[i]);

        var expected = CSharpExactNameFirstIndex(_names, _tailHashes, _target, _queryTailHash, Size);
        var actual = _nsharpExactNameFirstIndex(_names, _tailHashes, _target, _queryTailHash, Size);
        if (expected != actual)
            throw new InvalidOperationException($"Parity failed: C#={expected} N#={actual} (Size={Size}).");
    }

    [Benchmark(Baseline = true)]
    public int CSharp_Direct() =>
        CSharpExactNameFirstIndex(_names, _tailHashes, _target, _queryTailHash, Size);

    [Benchmark]
    public int CSharp_ViaDelegate() =>
        _csharpDelegate(_names, _tailHashes, _target, _queryTailHash, Size);

    [Benchmark]
    public int NSharp_ViaDelegate() =>
        _nsharpExactNameFirstIndex(_names, _tailHashes, _target, _queryTailHash, Size);

    private static int TailHash(string s) => s.Length == 0 ? 0 : s[s.Length - 1];

    // Byte-for-byte the same algorithm as DeclaredTypeExactNameFirstIndex in TypeLookup.nl.
    private static int CSharpExactNameFirstIndex(
        string[] names, int[] tailHashes, string typeName, int queryTailHash, int count)
    {
        if (count < 0 || count > names.Length || count > tailHashes.Length)
            return -2;

        var useTailHash = typeName.Length > 0;
        for (var i = 0; i < count; i++)
        {
            if ((!useTailHash || tailHashes[i] == queryTailHash) && names[i] == typeName)
                return i + 1;
        }

        return 0;
    }
}
