using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Cli.Commands;

public static partial class BenchCommand
{
    public static int Execute(string[] args)
    {
        if (args.Contains("--help") || args.Contains("-h") || (args.Length > 0 && args[0] == "help"))
            return ShowHelp();

        var projectRoot = Path.GetFullPath(GetOptionValue(args, "--project") ?? Directory.GetCurrentDirectory());
        var backendOption = GetOptionValue(args, "--backend");
        var filter = GetOptionValue(args, "--filter");
        var export = GetOptionValue(args, "--export");
        var jobOption = GetOptionValue(args, "--job");
        var listOnly = args.Contains("--list");
        var jsonOutput = args.Contains("--json");
        var explain = args.Contains("--explain");

        if (!Directory.Exists(projectRoot))
        {
            Console.Error.WriteLine($"Project directory not found: {projectRoot}");
            return 1;
        }

        // Discover *.bench.nl files
        var benchFiles = Directory.GetFiles(projectRoot, "*.bench.nl", SearchOption.AllDirectories);

        if (benchFiles.Length == 0)
        {
            if (jsonOutput)
            {
                WriteJson(writer =>
                {
                    writer.WriteNumber("schemaVersion", 1);
                    writer.WriteString("command", "bench");
                    writer.WriteBoolean("ok", true);
                    writer.WriteString("projectRoot", projectRoot);
                    writer.WriteNumber("benchmarkCount", 0);
                    writer.WriteStartArray("benchmarks");
                    writer.WriteEndArray();
                });
            }
            else
            {
                Console.WriteLine("No benchmark files (*.bench.nl) found in this project.");
                Console.WriteLine();
                Console.WriteLine("To add benchmarks, create a file named *.bench.nl with functions");
                Console.WriteLine("prefixed with 'bench' (e.g., benchAddNumbers).");
            }
            return 0;
        }

        // List mode: discover benchmark functions without running
        if (listOnly)
        {
            return ListBenchmarks(benchFiles, projectRoot, jsonOutput);
        }

        ProjectConfig? projectConfig;
        try
        {
            projectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);
            _ = !string.IsNullOrWhiteSpace(backendOption)
                ? CompilationBackendExtensions.Parse(backendOption)
                : projectConfig?.EffectiveBackend ?? CompilationBackend.Il;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.Message);
            return 1;
        }

        string? benchmarkJobAttribute;
        try
        {
            benchmarkJobAttribute = GetBenchmarkJobAttribute(jobOption);
        }
        catch (InvalidOperationException ex)
        {
            Console.Error.WriteLine(ex.Message);
            return 1;
        }

        // Run benchmarks
        return RunBenchmarksWithIl(benchFiles, projectRoot, projectConfig, filter, export, jsonOutput, benchmarkJobAttribute, explain);
    }

    static int ListBenchmarks(string[] benchFiles, string projectRoot, bool jsonOutput)
    {
        var discovered = DiscoverBenchmarkFunctions(benchFiles, projectRoot);

        if (jsonOutput)
        {
            WriteJson(writer =>
            {
                writer.WriteNumber("schemaVersion", 1);
                writer.WriteString("command", "bench");
                writer.WriteBoolean("ok", true);
                writer.WriteString("projectRoot", projectRoot);
                writer.WriteNumber("benchmarkCount", discovered.Count);
                writer.WriteStartArray("benchmarks");
                foreach (var b in discovered)
                {
                    writer.WriteStartObject();
                    writer.WriteString("name", b.FunctionName);
                    writer.WriteString("file", b.RelativePath);
                    writer.WriteEndObject();
                }
                writer.WriteEndArray();
            });
        }
        else
        {
            Console.WriteLine($"Discovered {discovered.Count} benchmark{(discovered.Count == 1 ? "" : "s")} in {benchFiles.Length} file{(benchFiles.Length == 1 ? "" : "s")}:");
            Console.WriteLine();
            foreach (var b in discovered)
                Console.WriteLine($"  {b.FunctionName} ({b.RelativePath})");
        }

        return 0;
    }

    // ── Discovery ────────────────────────────────────────────────────────────

    record BenchmarkInfo(string FunctionName, string RelativePath);

    static List<BenchmarkInfo> DiscoverBenchmarkFunctions(string[] benchFiles, string projectRoot)
    {
        var results = new List<BenchmarkInfo>();

        foreach (var file in benchFiles)
        {
            var relativePath = Path.GetRelativePath(projectRoot, file);
            try
            {
                var source = File.ReadAllText(file);
                // Find function declarations whose names start with "bench" (case-insensitive)
                foreach (var name in FindBenchFunctionNames(source))
                    results.Add(new BenchmarkInfo(name, relativePath));
            }
            catch
            {
                // Best-effort discovery; skip unreadable files
            }
        }

        return results;
    }

    /// <summary>
    /// Extract function names that start with "bench" from N# source code.
    /// Uses the N# lexer/parser for accurate extraction.
    /// </summary>
    static List<string> FindBenchFunctionNames(string source)
    {
        var names = new List<string>();

        try
        {
            var lexer = new Lexer(source, "bench.nl");
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, "bench.nl", source);
            var result = parser.ParseCompilationUnit();

            if (result.CompilationUnit == null)
                return names;

            foreach (var decl in result.CompilationUnit.Declarations)
            {
                if (decl is FunctionDeclaration fn &&
                    fn.Name.StartsWith("bench", StringComparison.OrdinalIgnoreCase))
                {
                    names.Add(fn.Name);
                }
            }
        }
        catch
        {
            // Fall back to line-based heuristic
            foreach (var line in source.Split('\n'))
            {
                var trimmed = line.TrimStart();
                if (trimmed.StartsWith("func bench", StringComparison.OrdinalIgnoreCase))
                {
                    var start = trimmed.IndexOf(' ') + 1;
                    var end = trimmed.IndexOf('(');
                    if (end > start)
                        names.Add(trimmed[start..end].Trim());
                }
            }
        }

        return names;
    }

    static string GenerateBenchmarkEntrypoint(List<string> classNames)
    {
        var sb = new StringBuilder();
        sb.AppendLine("using BenchmarkDotNet.Running;");
        sb.AppendLine();
        sb.AppendLine("// N# Benchmark Runner - generated by nlc bench");
        sb.AppendLine("internal static class NSharpBenchmarkHost");
        sb.AppendLine("{");
        sb.AppendLine("    public static void Main(string[] args)");
        sb.AppendLine("    {");

        if (classNames.Count == 1)
        {
            sb.AppendLine($"        BenchmarkRunner.Run<{classNames[0]}>(args: args);");
        }
        else
        {
            sb.AppendLine("        var switcher = BenchmarkSwitcher.FromTypes(new[]");
            sb.AppendLine("        {");
            foreach (var name in classNames)
                sb.AppendLine($"            typeof({name}),");
            sb.AppendLine("        });");
            sb.AppendLine("        switcher.Run(args);");
        }

        sb.AppendLine("    }");
        sb.AppendLine("}");

        return sb.ToString();
    }

    static string NormalizeBenchmarkFilter(string filter)
    {
        if (string.IsNullOrWhiteSpace(filter))
        {
            return filter;
        }

        return filter.IndexOfAny(['*', '?']) >= 0
            ? filter
            : $"*{filter}*";
    }

    static string? GetBenchmarkJobAttribute(string? jobOption)
    {
        if (string.IsNullOrWhiteSpace(jobOption))
        {
            return null;
        }

        return jobOption.Trim().ToLowerInvariant() switch
        {
            "default" => null,
            "dry" => "DryJob",
            "short" => "ShortRunJob",
            "medium" => "MediumRunJob",
            "long" => "LongRunJob",
            _ => throw new InvalidOperationException(
                $"Unknown benchmark job '{jobOption}'. Supported values: default, dry, short, medium, long.")
        };
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    static string SanitizeClassName(string name)
    {
        var sb = new StringBuilder();
        var capitalizeNext = true;

        foreach (var ch in name)
        {
            if (ch == '.' || ch == '-' || ch == '_' || ch == ' ')
            {
                capitalizeNext = true;
                continue;
            }

            sb.Append(capitalizeNext ? char.ToUpperInvariant(ch) : ch);
            capitalizeNext = false;
        }

        return sb.Length == 0 ? "Bench" : sb.ToString();
    }

    static string GetBenchmarkClassName(string relativePath)
    {
        var withoutExtension = relativePath.EndsWith(".bench.nl", StringComparison.OrdinalIgnoreCase)
            ? relativePath[..^".bench.nl".Length]
            : Path.GetFileNameWithoutExtension(relativePath);
        return SanitizeClassName(withoutExtension) + "Benchmarks";
    }

    static string? GetOptionValue(string[] args, string flag)
    {
        for (var i = 0; i < args.Length - 1; i++)
            if (args[i] == flag)
                return args[i + 1];
        return null;
    }

    static void WriteJson(Action<Utf8JsonWriter> write)
    {
        using var stream = new MemoryStream();
        using var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true });
        writer.WriteStartObject();
        write(writer);
        writer.WriteEndObject();
        writer.Flush();
        Console.WriteLine(System.Text.Encoding.UTF8.GetString(stream.ToArray()));
    }

    static int ShowHelp()
    {
        Console.WriteLine(@"N# Benchmarks

Usage: nlc bench [options]

Run benchmarks defined in *.bench.nl files using BenchmarkDotNet.

Benchmark files use the .bench.nl extension. Any function whose name starts
with 'bench' is automatically wrapped with [Benchmark] and run.

Options:
  --backend <mode>      Compilation backend: il
  --filter <pattern>    Run only benchmarks whose name matches the pattern
  --export <format>     Export results: json, csv, markdown
  --job <kind>          Benchmark job: default, dry, short, medium, long
  --project <dir>       Project root directory (default: current directory)
  --list                List discovered benchmarks without running them
  --explain             Attach an IL-shape summary (newobj/box/callvirt/call/
                        delegate-ctor counts) to each benchmark's output
  --json                Output structured JSON (schemaVersion 1 envelope)
  --help, -h            Show this help text

Example benchmark file (hello.bench.nl):
  func benchAddNumbers() {
      let list = [1, 2, 3, 4, 5]
      let sum = list.Sum()
  }

Examples:
  nlc bench
  nlc bench --backend il
  nlc bench --list
  nlc bench --explain
  nlc bench --filter benchAdd
  nlc bench --job dry
  nlc bench --export json
  nlc bench --project examples/my-lib
  nlc bench --json

Exit codes:
  0  Benchmarks completed successfully (or no benchmark files found)
  1  Benchmark run failed");

        return 0;
    }
}
