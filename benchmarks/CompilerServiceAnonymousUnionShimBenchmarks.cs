using System;
using System.Linq;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Dogfood benchmark for the anonymous-union shim eligibility gate in the IL compiler under
/// shim-emission pressure. The C# baseline mirrors the previous compiler-core shape: filter union
/// parameters with LINQ, materialize the union-parameter list, then verify every union parameter is
/// shim-safe. The N# candidate runs over compact parameter flags in caller-owned storage.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class CompilerServiceAnonymousUnionShimBenchmarks
{
    private const int LargeParameterCount = 8192;
    private const int RepresentativeParameterCount = 1024;

    private Func<int[], int, int> _nsharpDeclaresPublicShim =
        (_, _) => throw new InvalidOperationException("Benchmark not initialized.");

    private BenchmarkAnonymousUnionParameter[] _parameters = Array.Empty<BenchmarkAnonymousUnionParameter>();
    private int[] _parameterFlags = Array.Empty<int>();
    private int _parameterCount;
    private int _unionParameterCount;

    [Params(CompilerLexerCorpus.Representative, CompilerLexerCorpus.LargeGenerated)]
    public CompilerLexerCorpus Corpus { get; set; }

    [Params(
        AnonymousUnionParameterShape.DenseAllEligible,
        AnonymousUnionParameterShape.DenseLastUnionDisallowed,
        AnonymousUnionParameterShape.SparseAllEligible,
        AnonymousUnionParameterShape.SparseLastUnionDisallowed)]
    public AnonymousUnionParameterShape Shape { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _parameterCount = Corpus == CompilerLexerCorpus.Representative
            ? RepresentativeParameterCount
            : LargeParameterCount;
        _nsharpDeclaresPublicShim =
            NSharpCompiledMethod.Bind<Func<int[], int, int>>(
                DogfoodCompilerSources.AnonymousUnionShims,
                "AnonymousUnionDeclaresPublicShim");

        _parameters = BuildParameters(_parameterCount, Shape);
        _parameterFlags = new int[_parameterCount];
        _unionParameterCount = BuildParameterFlags();

        var expected = CSharpAnonymousUnion_DeclaresPublicShim();
        var actual = NSharpAnonymousUnion_DeclaresPublicShim();
        if (expected != actual)
        {
            throw new InvalidOperationException(
                $"N# anonymous-union shim eligibility mismatch for {Corpus}/{Shape}: " +
                $"expected {expected}, got {actual}.");
        }
    }

    [Benchmark(Baseline = true)]
    public int CSharpAnonymousUnion_DeclaresPublicShim()
    {
        var unionParameters = _parameters
            .Where(parameter => parameter.IsTwoArmUnion)
            .ToList();

        if (unionParameters.Count == 0)
            return 0;

        return unionParameters.All(parameter => !parameter.IsDisallowedModifier)
            ? 1
            : 0;
    }

    [Benchmark]
    public int NSharpAnonymousUnion_DeclaresPublicShim() =>
        _nsharpDeclaresPublicShim(_parameterFlags, _unionParameterCount);

    private int BuildParameterFlags()
    {
        var unionParameterCount = 0;
        for (var i = 0; i < _parameters.Length; i++)
        {
            var parameter = _parameters[i];
            if (!parameter.IsTwoArmUnion)
                continue;

            _parameterFlags[unionParameterCount] = parameter.IsDisallowedModifier ? 2 : 1;
            unionParameterCount++;
        }

        return unionParameterCount;
    }

    private static BenchmarkAnonymousUnionParameter[] BuildParameters(
        int count,
        AnonymousUnionParameterShape shape)
    {
        var parameters = new BenchmarkAnonymousUnionParameter[count];
        var lastUnionIndex = -1;
        var dense = shape is AnonymousUnionParameterShape.DenseAllEligible
            or AnonymousUnionParameterShape.DenseLastUnionDisallowed;
        for (var i = 0; i < count; i++)
        {
            var isTwoArmUnion = dense || i % 5 == 1;
            if (isTwoArmUnion)
                lastUnionIndex = i;

            parameters[i] = new BenchmarkAnonymousUnionParameter(
                i,
                isTwoArmUnion,
                IsDisallowedModifier: false);
        }

        if (shape is AnonymousUnionParameterShape.DenseLastUnionDisallowed
                or AnonymousUnionParameterShape.SparseLastUnionDisallowed
            && lastUnionIndex >= 0)
        {
            parameters[lastUnionIndex] = parameters[lastUnionIndex] with { IsDisallowedModifier = true };
        }

        return parameters;
    }
}

public enum AnonymousUnionParameterShape
{
    DenseAllEligible,
    DenseLastUnionDisallowed,
    SparseAllEligible,
    SparseLastUnionDisallowed
}

public readonly record struct BenchmarkAnonymousUnionParameter(
    int Index,
    bool IsTwoArmUnion,
    bool IsDisallowedModifier);
