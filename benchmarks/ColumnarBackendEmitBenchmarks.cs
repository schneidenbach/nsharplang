using System;
using System.IO;
using BenchmarkDotNet.Attributes;
using BenchmarkDotNet.Order;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

/// <summary>
/// PHASE C never-slower gate: end-to-end production compile (parse → analyze → emit → save) of a systems-subset
/// program BOTH ways through the SAME production entry point (<see cref="MultiFileCompiler.CompileToIlAssembly"/>),
/// toggling only the backend via <c>NSHARP_COLUMNAR_BACKEND</c>. Because the parse + analyze stages are byte-for-byte
/// identical between the two runs, the measured end-to-end delta IS the backend difference (C# <c>ILCompiler</c>
/// emit vs the standalone columnar emit). Enabling the flag is "never-slower" iff Columnar=true is ≤ Columnar=false.
///
/// The corpora (<see cref="RoutingCorpusSources"/>) are within the systems subset the columnar backend models, so
/// the flag actually re-routes the backend (verified in Setup: the two backends emit DIFFERENT IL). This is the
/// gate the roadmap requires before flipping the flag default-on.
/// </summary>
[MemoryDiagnoser]
[Orderer(SummaryOrderPolicy.FastestToSlowest)]
public class ColumnarBackendEmitBenchmarks
{
    private string _projectRoot = string.Empty;
    private string _programPath = string.Empty;
    private string _outputPath = string.Empty;
    private ProjectConfig _config = null!;

    [Params(RoutingCorpus.Representative, RoutingCorpus.LargeGenerated)]
    public RoutingCorpus Corpus { get; set; }

    // false = C# ILCompiler backend; true = standalone columnar backend (with C# fallback on decline).
    [Params(false, true)]
    public bool Columnar { get; set; }

    [GlobalSetup]
    public void Setup()
    {
        _projectRoot = Path.Combine(Path.GetTempPath(), $"nsharp-colbench-{Guid.NewGuid():N}");
        Directory.CreateDirectory(_projectRoot);
        _programPath = Path.Combine(_projectRoot, "Program.nl");
        _outputPath = Path.Combine(_projectRoot, "bin", "Bench.dll");
        File.WriteAllText(_programPath, RoutingCorpusSources.Build(Corpus));

        _config = ProjectFileParser.CreateDefault("Bench");
        _config.OutputType = "library";
        _config.TargetFramework = "net10.0";

        // Verify the flag genuinely re-routes the backend for this corpus (otherwise Columnar=true would silently
        // measure the C# path): the columnar-emitted assembly must differ from the C# one, yet both must succeed.
        var csharp = CompileOnce(columnar: false);
        var columnar = CompileOnce(columnar: true);
        if (csharp == null || columnar == null)
            throw new InvalidOperationException("A backend failed to compile the benchmark corpus.");
        if (Convert.ToBase64String(csharp) == Convert.ToBase64String(columnar))
            throw new InvalidOperationException("The columnar flag did not re-route the backend (assemblies identical).");
    }

    [GlobalCleanup]
    public void Cleanup()
    {
        Environment.SetEnvironmentVariable("NSHARP_COLUMNAR_BACKEND", null);
        if (Directory.Exists(_projectRoot))
            Directory.Delete(_projectRoot, recursive: true);
    }

    [IterationSetup]
    public void IterationSetup()
        => Environment.SetEnvironmentVariable("NSHARP_COLUMNAR_BACKEND", Columnar ? "1" : null);

    [Benchmark]
    public void CompileToIlAssembly()
    {
        var compiler = new MultiFileCompiler(new[] { _programPath }, _projectRoot, _config);
        var result = compiler.CompileToIlAssembly("Bench", _outputPath);
        if (!result.Success)
            throw new InvalidOperationException("Benchmark compile failed.");
    }

    // Helper for Setup's re-routing check: compile once with the given backend and return the emitted bytes.
    private byte[]? CompileOnce(bool columnar)
    {
        var previous = Environment.GetEnvironmentVariable("NSHARP_COLUMNAR_BACKEND");
        try
        {
            Environment.SetEnvironmentVariable("NSHARP_COLUMNAR_BACKEND", columnar ? "1" : null);
            var result = new MultiFileCompiler(new[] { _programPath }, _projectRoot, _config)
                .CompileToIlAssembly("Bench", _outputPath);
            return result.Success && result.OutputAssemblyPath != null ? File.ReadAllBytes(result.OutputAssemblyPath) : null;
        }
        finally
        {
            Environment.SetEnvironmentVariable("NSHARP_COLUMNAR_BACKEND", previous);
        }
    }
}
