using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using System.Text;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

public static partial class BenchCommand
{
    private sealed record ResolvedBenchmarkInfo(BenchmarkInfo Benchmark, string ReturnTypeName);

    private sealed class BenchmarkReflectionLoadContext(string assemblyDirectory)
        : AssemblyLoadContext(nameof(BenchmarkReflectionLoadContext), isCollectible: true)
    {
        private readonly string _assemblyDirectory = assemblyDirectory;

        protected override Assembly? Load(AssemblyName assemblyName)
        {
            var candidatePath = Path.Combine(_assemblyDirectory, $"{assemblyName.Name}.dll");
            return File.Exists(candidatePath) ? LoadFromAssemblyPath(candidatePath) : null;
        }
    }

    static int RunBenchmarksWithIl(
        string[] benchFiles,
        string projectRoot,
        ProjectConfig? projectConfig,
        string? filter,
        string? export,
        bool jsonOutput,
        string? benchmarkJobAttribute)
    {
        if (projectConfig == null)
        {
            Console.Error.WriteLine("IL-backed benchmarks require a project.yml file.");
            return 1;
        }

        if (!jsonOutput)
        {
            Console.WriteLine($"Running benchmarks in {projectRoot}...");
            Console.WriteLine($"Found {benchFiles.Length} benchmark file{(benchFiles.Length == 1 ? "" : "s")}");
            Console.WriteLine();
        }

        var restoreResult = RestoreCommand.Restore(projectRoot, quiet: true);
        if (restoreResult != 0)
        {
            Console.Error.WriteLine("Failed to restore project configuration.");
            return 1;
        }

        var projectFile = Program.EnsureProjectFiles(projectRoot, projectConfig);
        Program.CleanStaleGeneratedFiles(projectRoot);

        var buildArgs = string.Join(" ", new[]
        {
            "build",
            $"\"{projectFile}\"",
            "-c",
            "Release",
            "-v",
            "q",
            "-p:NSharpExcludeTests=true",
            Program.GetBackendMsBuildProperty(CompilationBackend.Il)
        });

        var buildResult = DotnetRunner.Run(buildArgs, workingDirectory: projectRoot);
        if (buildResult.ExitCode != 0)
        {
            Console.Error.WriteLine("Benchmark build failed.");
            var detail = (buildResult.Stderr + buildResult.Stdout).Trim();
            if (!string.IsNullOrWhiteSpace(detail))
            {
                Console.Error.WriteLine(detail);
            }
            return 1;
        }

        var outputAssemblyPath = Path.Combine(
            projectRoot,
            "bin",
            "Release",
            projectConfig.TargetFramework,
            $"{projectConfig.EffectiveName}.dll");

        if (!File.Exists(outputAssemblyPath))
        {
            Console.Error.WriteLine($"Built benchmark target not found: {outputAssemblyPath}");
            return 1;
        }

        var discovered = DiscoverBenchmarkFunctions(benchFiles, projectRoot);
        List<ResolvedBenchmarkInfo> resolvedBenchmarks;
        try
        {
            resolvedBenchmarks = ResolveBenchmarksFromAssembly(outputAssemblyPath, discovered);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Benchmark discovery failed: {ex.Message}");
            return 1;
        }

        var tempDir = Path.Combine(Path.GetTempPath(), $"nlc-bench-il-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);

        try
        {
            CopySdkResolutionFiles(projectRoot, tempDir);

            var wrapperClasses = new List<string>();
            foreach (var group in resolvedBenchmarks.GroupBy(b => b.Benchmark.RelativePath, StringComparer.OrdinalIgnoreCase))
            {
                var className = GetBenchmarkClassName(group.Key);
                wrapperClasses.Add(className);

                var wrapperSource = GenerateIlBenchmarkClass(className, group.ToList(), benchmarkJobAttribute);
                File.WriteAllText(Path.Combine(tempDir, $"{className}.cs"), wrapperSource);
            }

            File.WriteAllText(Path.Combine(tempDir, "Program.cs"), GenerateBenchmarkEntrypoint(wrapperClasses));
            var benchmarkProjectPath = Path.Combine(tempDir, "Benchmarks.csproj");
            File.WriteAllText(
                benchmarkProjectPath,
                GenerateIlBenchmarkCsProj(projectConfig.TargetFramework, projectFile));

            if (!jsonOutput)
            {
                Console.WriteLine("Running BenchmarkDotNet...");
            }

            var runArgs = new List<string>
            {
                "run",
                "--project",
                $"\"{benchmarkProjectPath}\"",
                "-c",
                "Release",
                Program.GetBackendMsBuildProperty(CompilationBackend.Il),
                "--"
            };

            if (!string.IsNullOrEmpty(filter))
            {
                runArgs.AddRange(new[] { "--filter", $"\"{NormalizeBenchmarkFilter(filter)}\"" });
            }

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
                    writer.WriteNumber("benchmarkCount", wrapperClasses.Count);
                    writer.WriteStartArray("benchmarks");
                    foreach (var className in wrapperClasses)
                    {
                        writer.WriteStartObject();
                        writer.WriteString("class", className);
                        writer.WriteEndObject();
                    }
                    writer.WriteEndArray();
                });
            }

            return 0;
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { }
        }
    }

    private static List<ResolvedBenchmarkInfo> ResolveBenchmarksFromAssembly(
        string outputAssemblyPath,
        IReadOnlyList<BenchmarkInfo> discovered)
    {
        var assemblyDirectory = Path.GetDirectoryName(outputAssemblyPath)
            ?? throw new InvalidOperationException($"Could not determine the assembly directory for '{outputAssemblyPath}'.");
        var loadContext = new BenchmarkReflectionLoadContext(assemblyDirectory);

        try
        {
            var assembly = loadContext.LoadFromAssemblyPath(outputAssemblyPath);
            var programType = assembly.GetType("Program");
            if (programType == null)
            {
                throw new InvalidOperationException("Compiled benchmark assembly does not define the generated Program type.");
            }

            var methods = programType
                .GetMethods(BindingFlags.Public | BindingFlags.Static)
                .ToLookup(method => method.Name, StringComparer.Ordinal);

            var resolved = new List<ResolvedBenchmarkInfo>(discovered.Count);
            foreach (var benchmark in discovered)
            {
                var candidates = methods[benchmark.FunctionName];
                var method = candidates.SingleOrDefault(candidate =>
                    !candidate.IsGenericMethodDefinition &&
                    candidate.GetParameters().Length == 0);

                if (method == null)
                {
                    throw new InvalidOperationException(
                        $"Could not resolve a parameterless top-level benchmark function '{benchmark.FunctionName}' in the compiled project assembly.");
                }

                resolved.Add(new ResolvedBenchmarkInfo(benchmark, GetCSharpTypeName(method.ReturnType)));
            }

            return resolved;
        }
        finally
        {
            loadContext.Unload();
        }
    }

    private static string GenerateIlBenchmarkClass(
        string className,
        IReadOnlyList<ResolvedBenchmarkInfo> benchmarks,
        string? benchmarkJobAttribute)
    {
        var sb = new StringBuilder();
        sb.AppendLine("using BenchmarkDotNet.Attributes;");
        sb.AppendLine();
        if (!string.IsNullOrWhiteSpace(benchmarkJobAttribute))
        {
            sb.AppendLine($"[{benchmarkJobAttribute}]");
        }
        sb.AppendLine($"public class {className}");
        sb.AppendLine("{");

        foreach (var benchmark in benchmarks)
        {
            sb.AppendLine("    [Benchmark]");
            if (benchmark.ReturnTypeName == "void")
            {
                sb.AppendLine($"    public void {benchmark.Benchmark.FunctionName}()");
                sb.AppendLine("    {");
                sb.AppendLine($"        global::Program.{benchmark.Benchmark.FunctionName}();");
                sb.AppendLine("    }");
            }
            else
            {
                sb.AppendLine($"    public {benchmark.ReturnTypeName} {benchmark.Benchmark.FunctionName}()");
                sb.AppendLine("    {");
                sb.AppendLine($"        return global::Program.{benchmark.Benchmark.FunctionName}();");
                sb.AppendLine("    }");
            }

            sb.AppendLine();
        }

        sb.AppendLine("}");
        return sb.ToString();
    }

    private static string GenerateIlBenchmarkCsProj(string targetFramework, string projectFile)
    {
        var sb = new StringBuilder();
        sb.AppendLine("<Project Sdk=\"Microsoft.NET.Sdk\">");
        sb.AppendLine("  <PropertyGroup>");
        sb.AppendLine("    <OutputType>Exe</OutputType>");
        sb.AppendLine($"    <TargetFramework>{targetFramework}</TargetFramework>");
        sb.AppendLine("    <LangVersion>latest</LangVersion>");
        sb.AppendLine("    <Nullable>enable</Nullable>");
        sb.AppendLine("    <Optimize>true</Optimize>");
        sb.AppendLine("  </PropertyGroup>");
        sb.AppendLine("  <ItemGroup>");
        sb.AppendLine($"    <ProjectReference Include=\"{EscapeXml(projectFile)}\" />");
        sb.AppendLine("    <PackageReference Include=\"BenchmarkDotNet\" Version=\"0.14.0\" />");
        sb.AppendLine("  </ItemGroup>");
        sb.AppendLine("</Project>");
        return sb.ToString();
    }

    private static void CopySdkResolutionFiles(string projectRoot, string tempDir)
    {
        foreach (var fileName in new[] { "global.json", "NuGet.config" })
        {
            var sourcePath = Path.Combine(projectRoot, fileName);
            if (File.Exists(sourcePath))
            {
                File.Copy(sourcePath, Path.Combine(tempDir, fileName), overwrite: true);
            }
        }
    }

    private static string GetCSharpTypeName(Type type)
    {
        if (type == typeof(void)) return "void";
        if (type == typeof(bool)) return "bool";
        if (type == typeof(byte)) return "byte";
        if (type == typeof(sbyte)) return "sbyte";
        if (type == typeof(short)) return "short";
        if (type == typeof(ushort)) return "ushort";
        if (type == typeof(int)) return "int";
        if (type == typeof(uint)) return "uint";
        if (type == typeof(long)) return "long";
        if (type == typeof(ulong)) return "ulong";
        if (type == typeof(float)) return "float";
        if (type == typeof(double)) return "double";
        if (type == typeof(decimal)) return "decimal";
        if (type == typeof(string)) return "string";
        if (type == typeof(char)) return "char";
        if (type == typeof(object)) return "object";

        if (type.IsByRef)
        {
            return $"{GetCSharpTypeName(type.GetElementType()!)}&";
        }

        if (type.IsArray)
        {
            return $"{GetCSharpTypeName(type.GetElementType()!)}[]";
        }

        var nullableType = Nullable.GetUnderlyingType(type);
        if (nullableType != null)
        {
            return $"{GetCSharpTypeName(nullableType)}?";
        }

        if (type.IsGenericType)
        {
            var genericTypeDefinition = type.GetGenericTypeDefinition();
            var genericTypeName = genericTypeDefinition.FullName ?? genericTypeDefinition.Name;
            var tickIndex = genericTypeName.IndexOf('`');
            if (tickIndex >= 0)
            {
                genericTypeName = genericTypeName[..tickIndex];
            }

            genericTypeName = genericTypeName.Replace('+', '.');
            var genericArguments = string.Join(", ", type.GetGenericArguments().Select(GetCSharpTypeName));
            return $"global::{genericTypeName}<{genericArguments}>";
        }

        var typeName = type.FullName ?? type.Name;
        return $"global::{typeName.Replace('+', '.')}";
    }

    private static string EscapeXml(string value)
    {
        return value
            .Replace("&", "&amp;", StringComparison.Ordinal)
            .Replace("\"", "&quot;", StringComparison.Ordinal)
            .Replace("<", "&lt;", StringComparison.Ordinal)
            .Replace(">", "&gt;", StringComparison.Ordinal);
    }
}
