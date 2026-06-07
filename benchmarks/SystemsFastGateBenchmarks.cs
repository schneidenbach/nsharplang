using System;
using BenchmarkDotNet.Attributes;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Fast Systems N# gate for the full test suite. Each benchmark row aggregates the detailed
/// subcases from one Systems benchmark family so CI gets BenchmarkDotNet allocation and
/// throughput evidence without paying for every parameterized matrix row by default.
/// </summary>
[MemoryDiagnoser]
public class SystemsFastGateBenchmarks
{
    private const int InnerOperations = 32;

    private SystemsHotPathBenchmarks _hot64 = null!;
    private SystemsHotPathBenchmarks _hot4096 = null!;
    private SystemsSpanHandoffBenchmarks _span64 = null!;
    private SystemsSpanHandoffBenchmarks _span4096 = null!;
    private SystemsCallerBufferBenchmarks _caller64 = null!;
    private SystemsCallerBufferBenchmarks _caller4096 = null!;
    private SystemsResultBenchmarks _result64 = null!;
    private SystemsResultBenchmarks _result4096 = null!;
    private SystemsPooledBoundaryBenchmarks _pooled64 = null!;
    private SystemsPooledBoundaryBenchmarks _pooled4096 = null!;
    private SystemsCombinationBenchmarks _combination64 = null!;
    private SystemsCombinationBenchmarks _combination4096 = null!;

    public enum GateScenario
    {
        HotLoops,
        SpanHandoff,
        CallerBuffers,
        ResultAbi,
        PooledBoundary,
        HotResultCombinations,
    }

    [Params(
        GateScenario.HotLoops,
        GateScenario.SpanHandoff,
        GateScenario.CallerBuffers,
        GateScenario.ResultAbi,
        GateScenario.PooledBoundary,
        GateScenario.HotResultCombinations)]
    public GateScenario Scenario { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        switch (Scenario)
        {
            case GateScenario.HotLoops:
                _hot64 = SetupHot(64);
                _hot4096 = SetupHot(4096);
                break;
            case GateScenario.SpanHandoff:
                _span64 = SetupSpan(64);
                _span4096 = SetupSpan(4096);
                break;
            case GateScenario.CallerBuffers:
                _caller64 = SetupCaller(64);
                _caller4096 = SetupCaller(4096);
                break;
            case GateScenario.ResultAbi:
                _result64 = SetupResult(64);
                _result4096 = SetupResult(4096);
                break;
            case GateScenario.PooledBoundary:
                _pooled64 = SetupPooled(64);
                _pooled4096 = SetupPooled(4096);
                break;
            case GateScenario.HotResultCombinations:
                _combination64 = SetupCombination(64);
                _combination4096 = SetupCombination(4096);
                break;
            default:
                throw new InvalidOperationException($"Unknown Systems fast gate scenario '{Scenario}'.");
        }
    }

    [Benchmark(Baseline = true, OperationsPerInvoke = InnerOperations)]
    public int CSharp()
    {
        var total = 0;
        for (var operation = 0; operation < InnerOperations; operation++)
        {
            total += Scenario switch
            {
                GateScenario.HotLoops => RunHot(_hot64, useNSharp: false) + RunHot(_hot4096, useNSharp: false),
                GateScenario.SpanHandoff => RunSpan(_span64, useNSharp: false) + RunSpan(_span4096, useNSharp: false),
                GateScenario.CallerBuffers => RunCaller(_caller64, useNSharp: false) + RunCaller(_caller4096, useNSharp: false),
                GateScenario.ResultAbi => RunResult(_result64, useNSharp: false) + RunResult(_result4096, useNSharp: false),
                GateScenario.PooledBoundary => RunPooled(_pooled64, useNSharp: false) + RunPooled(_pooled4096, useNSharp: false),
                GateScenario.HotResultCombinations => RunCombination(_combination64, useNSharp: false) + RunCombination(_combination4096, useNSharp: false),
                _ => throw new InvalidOperationException()
            };
        }

        return total;
    }

    [Benchmark(OperationsPerInvoke = InnerOperations)]
    public int NSharp()
    {
        var total = 0;
        for (var operation = 0; operation < InnerOperations; operation++)
        {
            total += Scenario switch
            {
                GateScenario.HotLoops => RunHot(_hot64, useNSharp: true) + RunHot(_hot4096, useNSharp: true),
                GateScenario.SpanHandoff => RunSpan(_span64, useNSharp: true) + RunSpan(_span4096, useNSharp: true),
                GateScenario.CallerBuffers => RunCaller(_caller64, useNSharp: true) + RunCaller(_caller4096, useNSharp: true),
                GateScenario.ResultAbi => RunResult(_result64, useNSharp: true) + RunResult(_result4096, useNSharp: true),
                GateScenario.PooledBoundary => RunPooled(_pooled64, useNSharp: true) + RunPooled(_pooled4096, useNSharp: true),
                GateScenario.HotResultCombinations => RunCombination(_combination64, useNSharp: true) + RunCombination(_combination4096, useNSharp: true),
                _ => throw new InvalidOperationException()
            };
        }

        return total;
    }

    private static SystemsHotPathBenchmarks SetupHot(int size)
    {
        var benchmark = new SystemsHotPathBenchmarks { Size = size };
        benchmark.Setup();
        return benchmark;
    }

    private static SystemsSpanHandoffBenchmarks SetupSpan(int size)
    {
        var benchmark = new SystemsSpanHandoffBenchmarks { Size = size };
        benchmark.Setup();
        return benchmark;
    }

    private static SystemsCallerBufferBenchmarks SetupCaller(int size)
    {
        var benchmark = new SystemsCallerBufferBenchmarks { Size = size };
        benchmark.Setup();
        return benchmark;
    }

    private static SystemsResultBenchmarks SetupResult(int size)
    {
        var benchmark = new SystemsResultBenchmarks { Size = size };
        benchmark.Setup();
        return benchmark;
    }

    private static SystemsPooledBoundaryBenchmarks SetupPooled(int size)
    {
        var benchmark = new SystemsPooledBoundaryBenchmarks { Size = size };
        benchmark.Setup();
        return benchmark;
    }

    private static SystemsCombinationBenchmarks SetupCombination(int size)
    {
        var benchmark = new SystemsCombinationBenchmarks { Size = size };
        benchmark.Setup();
        return benchmark;
    }

    // Workload value arrays cached once (Enum.GetValues allocates per call; the gate enforces zero
    // per-invoke allocation, so caching keeps the hot loop allocation-free).
    private static readonly SystemsHotPathBenchmarks.HotPathWorkload[] HotWorkloads =
        Enum.GetValues<SystemsHotPathBenchmarks.HotPathWorkload>();
    private static readonly SystemsSpanHandoffBenchmarks.SpanHandoffWorkload[] SpanWorkloads =
        Enum.GetValues<SystemsSpanHandoffBenchmarks.SpanHandoffWorkload>();
    private static readonly SystemsCallerBufferBenchmarks.CallerBufferWorkload[] CallerWorkloads =
        Enum.GetValues<SystemsCallerBufferBenchmarks.CallerBufferWorkload>();
    private static readonly SystemsResultBenchmarks.ResultWorkload[] ResultWorkloads =
        Enum.GetValues<SystemsResultBenchmarks.ResultWorkload>();
    private static readonly SystemsPooledBoundaryBenchmarks.PooledBoundaryWorkload[] PooledWorkloads =
        Enum.GetValues<SystemsPooledBoundaryBenchmarks.PooledBoundaryWorkload>();
    private static readonly SystemsCombinationBenchmarks.CombinationWorkload[] CombinationWorkloads =
        Enum.GetValues<SystemsCombinationBenchmarks.CombinationWorkload>();

    // Apples-to-apples (H8): both sides run the SAME set of distinct per-workload functions, so the
    // gate measures N# vs C# CODEGEN, not loop fusion. (The fused NSharpAll()/CSharpAll() helpers
    // fuse the workloads asymmetrically — N# into a few loops, C# into separate full passes — so the
    // gate used to partly measure that structural difference rather than codegen quality.)
    private static int RunHot(SystemsHotPathBenchmarks benchmark, bool useNSharp)
    {
        var total = 0;
        foreach (var workload in HotWorkloads)
        {
            benchmark.Workload = workload;
            total += useNSharp ? benchmark.NSharp() : benchmark.CSharp();
        }

        return total;
    }

    private static int RunSpan(SystemsSpanHandoffBenchmarks benchmark, bool useNSharp)
    {
        var total = 0;
        foreach (var workload in SpanWorkloads)
        {
            benchmark.Workload = workload;
            total += useNSharp ? benchmark.NSharp() : benchmark.CSharp();
        }

        return total;
    }

    private static int RunCaller(SystemsCallerBufferBenchmarks benchmark, bool useNSharp)
    {
        var total = 0;
        foreach (var workload in CallerWorkloads)
        {
            benchmark.Workload = workload;
            total += useNSharp ? benchmark.NSharp() : benchmark.CSharp();
        }

        return total;
    }

    private static int RunResult(SystemsResultBenchmarks benchmark, bool useNSharp)
    {
        var total = 0;
        foreach (var workload in ResultWorkloads)
        {
            benchmark.Workload = workload;
            total += useNSharp ? benchmark.RuntimeResult() : benchmark.CSharpTaggedStruct();
        }

        return total;
    }

    private static int RunPooled(SystemsPooledBoundaryBenchmarks benchmark, bool useNSharp)
    {
        var total = 0;
        foreach (var workload in PooledWorkloads)
        {
            benchmark.Workload = workload;
            total += useNSharp ? benchmark.NSharp() : benchmark.CSharp();
        }

        return total;
    }

    private static int RunCombination(SystemsCombinationBenchmarks benchmark, bool useNSharp)
    {
        var total = 0;
        foreach (var workload in CombinationWorkloads)
        {
            benchmark.Workload = workload;
            total += useNSharp ? benchmark.NSharp() : benchmark.CSharp();
        }

        return total;
    }
}
