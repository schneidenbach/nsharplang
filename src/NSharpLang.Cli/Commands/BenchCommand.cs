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

        var projectConfig = ProjectFileParser.ParseFromDirectory(projectRoot);
        var backend = !string.IsNullOrWhiteSpace(backendOption)
            ? CompilationBackendExtensions.Parse(backendOption)
            : projectConfig?.EffectiveBackend ?? CompilationBackend.Transpile;

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
        return backend == CompilationBackend.Il
            ? RunBenchmarksWithIl(benchFiles, projectRoot, projectConfig, filter, export, jsonOutput, benchmarkJobAttribute)
            : RunBenchmarks(benchFiles, projectRoot, projectConfig, filter, export, jsonOutput, benchmarkJobAttribute);
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

    static int RunBenchmarks(
        string[] benchFiles,
        string projectRoot,
        ProjectConfig? projectConfig,
        string? filter,
        string? export,
        bool jsonOutput,
        string? benchmarkJobAttribute)
    {
        if (!jsonOutput)
        {
            Console.WriteLine($"Running benchmarks in {projectRoot}...");
            Console.WriteLine($"Found {benchFiles.Length} benchmark file{(benchFiles.Length == 1 ? "" : "s")}");
            Console.WriteLine();
        }

        var targetFramework = projectConfig?.TargetFramework ?? "net9.0";

        // Transpile each bench file to C#
        var tempDir = Path.Combine(Path.GetTempPath(), $"nlc-bench-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            var benchClassFiles = new List<(string ClassName, string CSharpPath)>();

            foreach (var benchFile in benchFiles)
            {
                var relativePath = Path.GetRelativePath(projectRoot, benchFile);
                var className = GetBenchmarkClassName(relativePath);

                if (!jsonOutput)
                    Console.WriteLine($"  Transpiling {relativePath}...");

                var source = File.ReadAllText(benchFile);
                string csharpCode;

                try
                {
                    csharpCode = TranspileWithBenchmarkAttributes(source, benchFile, projectConfig, className, benchmarkJobAttribute);
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine($"Transpilation failed for {relativePath}: {ex.Message}");
                    return 1;
                }

                var destPath = Path.Combine(tempDir, $"{className}.cs");
                File.WriteAllText(destPath, csharpCode);
                benchClassFiles.Add((className, destPath));
            }

            // Generate BenchmarkDotNet entrypoint
            var entrypointCs = GenerateBenchmarkEntrypoint(benchClassFiles.Select(b => b.ClassName).ToList());
            File.WriteAllText(Path.Combine(tempDir, "Program.cs"), entrypointCs);

            // Generate .csproj referencing BenchmarkDotNet
            var benchCsproj = GenerateBenchmarkCsProj(targetFramework, projectConfig);
            var csprojPath = Path.Combine(tempDir, "Benchmarks.csproj");
            File.WriteAllText(csprojPath, benchCsproj);

            if (!jsonOutput)
                Console.WriteLine("Running BenchmarkDotNet...");

            // Build args for dotnet run
            var runArgs = new List<string> { "run", "--project", $"\"{csprojPath}\"", "-c", "Release", "--" };
            if (!string.IsNullOrEmpty(filter))
                runArgs.AddRange(new[] { "--filter", $"\"{NormalizeBenchmarkFilter(filter)}\"" });

            if (!string.IsNullOrEmpty(export))
            {
                switch (export.ToLowerInvariant())
                {
                    case "json":
                        runArgs.Add("--exporters json");
                        break;
                    case "csv":
                        runArgs.Add("--exporters csv");
                        break;
                    case "markdown":
                        runArgs.Add("--exporters markdown");
                        break;
                    default:
                        Console.Error.WriteLine($"Unknown export format: {export}. Supported: json, csv, markdown");
                        return 1;
                }
            }

            if (jsonOutput)
            {
                var runResult = DotnetRunner.Run(string.Join(" ", runArgs), workingDirectory: tempDir, timeout: TimeSpan.FromMinutes(10));
                if (runResult.ExitCode != 0)
                {
                    Console.Error.WriteLine("Benchmark run failed.");
                    var detail = (runResult.Stderr + runResult.Stdout).Trim();
                    if (!string.IsNullOrWhiteSpace(detail))
                    {
                        Console.Error.WriteLine(detail);
                    }
                    return 1;
                }
            }
            else
            {
                var exitCode = DotnetRunner.RunPassthrough(string.Join(" ", runArgs), workingDirectory: tempDir);
                if (exitCode != 0)
                {
                    Console.Error.WriteLine("Benchmark run failed.");
                    return 1;
                }
            }

            if (jsonOutput)
            {
                WriteJson(writer =>
                {
                    writer.WriteNumber("schemaVersion", 1);
                    writer.WriteString("command", "bench");
                    writer.WriteBoolean("ok", true);
                    writer.WriteString("projectRoot", projectRoot);
                    writer.WriteNumber("benchmarkCount", benchClassFiles.Count);
                    writer.WriteStartArray("benchmarks");
                    foreach (var b in benchClassFiles)
                    {
                        writer.WriteStartObject();
                        writer.WriteString("class", b.ClassName);
                        writer.WriteEndObject();
                    }
                    writer.WriteEndArray();
                });
            }

            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Benchmark failed: {ex.Message}");
            return 1;
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { /* ignore cleanup errors */ }
        }
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

    // ── Code generation ──────────────────────────────────────────────────────

    /// <summary>
    /// Transpile N# source to C#, injecting [Benchmark] on bench-prefixed functions.
    /// </summary>
    static string TranspileWithBenchmarkAttributes(
        string source,
        string filePath,
        ProjectConfig? config,
        string className,
        string? benchmarkJobAttribute)
    {
        var lexer = new Lexer(source, filePath);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, filePath, source);
        var parseResult = parser.ParseCompilationUnit();

        if (parseResult.CompilationUnit == null)
        {
            var errors = parseResult.Errors;
            throw new Exception($"Parse failed: {string.Join("; ", errors.Select(e => e.Message))}");
        }

        var transpiler = new Transpiler(parseResult.CompilationUnit, config, sourceFilePath: Path.GetFullPath(filePath));
        var csharp = transpiler.Transpile();

        // Inject using BenchmarkDotNet.Attributes and wrap in a proper benchmark class.
        // The Transpiler emits a top-level program; we need to restructure it.
        return WrapAsBenchmarkClass(csharp, className, source, benchmarkJobAttribute);
    }

    /// <summary>
    /// Wrap transpiled C# into a BenchmarkDotNet-compatible class, adding [Benchmark]
    /// to any method whose name starts with "Bench" (the N# transpiler capitalizes).
    /// </summary>
    static string WrapAsBenchmarkClass(string transpiledCsharp, string className, string originalSource, string? benchmarkJobAttribute)
    {
        var sb = new StringBuilder();
        sb.AppendLine("using BenchmarkDotNet.Attributes;");
        sb.AppendLine("using System;");
        sb.AppendLine("using System.Linq;");
        sb.AppendLine("using System.Collections.Generic;");
        sb.AppendLine();
        if (!string.IsNullOrWhiteSpace(benchmarkJobAttribute))
            sb.AppendLine($"[{benchmarkJobAttribute}]");
        sb.AppendLine($"public class {className}");
        sb.AppendLine("{");

        // Extract function bodies from the transpiled C# and add [Benchmark] to bench functions
        // We parse line-by-line, injecting the attribute before matching method signatures
        var lines = transpiledCsharp.Split('\n');
        var inBenchMethod = false;
        var depth = 0;

        foreach (var rawLine in lines)
        {
            var line = rawLine.TrimEnd();

            // Skip top-level using statements and namespace declarations (already handled above)
            if (line.TrimStart().StartsWith("using ", StringComparison.Ordinal) && !line.Contains("("))
                continue;
            if (line.TrimStart().StartsWith("namespace ", StringComparison.Ordinal))
                continue;
            if (line.TrimStart() == "{" && depth == 0 && !inBenchMethod)
                continue; // namespace opening brace
            if (depth == 0 && line.TrimStart() == "}" && !inBenchMethod)
                continue; // namespace closing brace

            // Detect method declarations (generated C# uses 'static' for top-level funcs)
            // Pattern: "static <returnType> <Name>(<params>)"
            var trimmed = line.TrimStart();
            if (IsBenchMethodSignature(trimmed))
            {
                sb.AppendLine("    [Benchmark]");
                inBenchMethod = true;
            }

            sb.AppendLine("    " + line);

            // Track brace depth
            depth += line.Count(c => c == '{') - line.Count(c => c == '}');
            if (depth <= 0)
            {
                depth = 0;
                inBenchMethod = false;
            }
        }

        sb.AppendLine("}");
        return sb.ToString();
    }

    static bool IsBenchMethodSignature(string line)
    {
        // Match: "static <type> Bench<Name>(" or "public static <type> Bench<Name>("
        var stripped = line
            .Replace("public ", "")
            .Replace("private ", "")
            .Replace("protected ", "")
            .Replace("internal ", "")
            .Replace("static ", "")
            .TrimStart();

        // After stripping modifiers, check if the remaining looks like: "Type Bench<X>(...)"
        var parenIdx = stripped.IndexOf('(');
        if (parenIdx < 0) return false;

        var beforeParen = stripped[..parenIdx].Trim();
        var spaceIdx = beforeParen.LastIndexOf(' ');
        if (spaceIdx < 0) return false;

        var methodName = beforeParen[(spaceIdx + 1)..];
        return methodName.StartsWith("Bench", StringComparison.OrdinalIgnoreCase);
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

    static string GenerateBenchmarkCsProj(string targetFramework, ProjectConfig? config)
    {
        var sb = new StringBuilder();
        sb.AppendLine("<Project Sdk=\"Microsoft.NET.Sdk\">");
        sb.AppendLine("  <PropertyGroup>");
        sb.AppendLine($"    <OutputType>Exe</OutputType>");
        sb.AppendLine($"    <TargetFramework>{targetFramework}</TargetFramework>");
        sb.AppendLine("    <LangVersion>latest</LangVersion>");
        sb.AppendLine("    <Nullable>enable</Nullable>");
        sb.AppendLine("    <Optimize>true</Optimize>");
        sb.AppendLine("    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>");
        sb.AppendLine("  </PropertyGroup>");
        sb.AppendLine("  <ItemGroup>");
        sb.AppendLine("    <PackageReference Include=\"BenchmarkDotNet\" Version=\"0.14.0\" />");

        // Forward project's own NuGet dependencies into the benchmark project
        if (config != null)
        {
            foreach (var dep in config.Dependencies)
            {
                if (dep.Type == ReferenceType.NuGet && dep.Nuget != null)
                {
                    var ver = string.IsNullOrEmpty(dep.Version) ? "*" : dep.Version;
                    sb.AppendLine($"    <PackageReference Include=\"{dep.Nuget}\" Version=\"{ver}\" />");
                }
            }
        }

        sb.AppendLine("  </ItemGroup>");
        sb.AppendLine("</Project>");
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
  --backend <mode>      Compilation backend: transpile (default) or il
  --filter <pattern>    Run only benchmarks whose name matches the pattern
  --export <format>     Export results: json, csv, markdown
  --job <kind>          Benchmark job: default, dry, short, medium, long
  --project <dir>       Project root directory (default: current directory)
  --list                List discovered benchmarks without running them
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
