using System;
using System.IO;
using System.Linq;

namespace NSharpLang.Cli.Commands;

public static class BenchCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var projectRoot = Directory.GetCurrentDirectory();
        var benchFiles = Directory.Exists(projectRoot)
            ? Directory.GetFiles(projectRoot, "*.bench.nl", SearchOption.AllDirectories)
            : Array.Empty<string>();

        if (benchFiles.Length > 0)
        {
            Console.WriteLine($"Found {benchFiles.Length} benchmark file{(benchFiles.Length == 1 ? "" : "s")}:");
            foreach (var f in benchFiles)
                Console.WriteLine($"  {Path.GetRelativePath(projectRoot, f)}");
            Console.WriteLine();
        }

        Console.WriteLine("Benchmarking support is coming soon.");
        Console.WriteLine();
        Console.WriteLine("Planned: *.bench.nl files with BenchmarkDotNet integration.");
        Console.WriteLine("Track progress: https://github.com/nsharp-lang/nsharp/issues");

        return 0;
    }

    static int ShowHelp()
    {
        Console.WriteLine(@"N# Benchmarks

Usage: nlc bench [options]

Run benchmarks defined in *.bench.nl files using BenchmarkDotNet.

This feature is under development. Benchmark files use the .bench.nl
extension and will support BenchmarkDotNet attributes via N# syntax.

Planned options:
  --filter <pattern>    Run only matching benchmarks
  --export <format>     Export results (json, csv, markdown)
  --project <dir>       Project root directory
  --help, -h            Show this help text

Example benchmark file (planned syntax):
  bench addNumbers() {
      let list = [1, 2, 3, 4, 5]
      let sum = list.Sum()
  }

Exit codes:
  0  Benchmarks completed successfully
  1  Benchmark run failed");

        return 0;
    }
}
