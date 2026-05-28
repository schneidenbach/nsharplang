using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.Loader;
using System.Text;
using System.Text.Json;
using NSharpLang.Compiler;

namespace NSharpLang.Cli.Commands;

public static partial class BenchCommand
{
    private sealed record ResolvedBenchmarkInfo(
        BenchmarkInfo Benchmark,
        string ReturnTypeName,
        string DeclaringTypeName,
        string MethodName,
        IlShapeSummary? IlShape);

    /// <summary>
    /// A coarse, allocation/dispatch-focused summary of a method's IL body.
    /// Used by <c>nlc bench --explain</c> to surface the kinds of operations that
    /// dominate N# performance (heap allocations, boxing, virtual dispatch, and
    /// delegate construction) without a full disassembler.
    /// </summary>
    internal sealed record IlShapeSummary(
        int IlBytes,
        int Newobj,
        int Box,
        int Callvirt,
        int Call,
        int DelegateCtors);

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
        string? benchmarkJobAttribute,
        bool explain)
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

        var outputAssemblyPath = Program.BuildProjectWithIlBackendForCommand(
            projectRoot,
            projectConfig,
            "Release",
            outputDir: null,
            includeTests: false);
        if (outputAssemblyPath == null)
        {
            Console.Error.WriteLine("Benchmark build failed.");
            return 1;
        }

        if (!File.Exists(outputAssemblyPath))
        {
            Console.Error.WriteLine($"Built benchmark target not found: {outputAssemblyPath}");
            return 1;
        }

        var discovered = DiscoverBenchmarkFunctions(benchFiles, projectRoot);
        List<ResolvedBenchmarkInfo> resolvedBenchmarks;
        try
        {
            resolvedBenchmarks = ResolveBenchmarksFromAssembly(outputAssemblyPath, discovered, explain);
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

                var wrapperSource = GenerateIlBenchmarkClass(className, group.ToList(), benchmarkJobAttribute, outputAssemblyPath);
                File.WriteAllText(Path.Combine(tempDir, $"{className}.cs"), wrapperSource);
            }

            File.WriteAllText(Path.Combine(tempDir, "Program.cs"), GenerateBenchmarkEntrypoint(wrapperClasses));
            var benchmarkProjectPath = Path.Combine(tempDir, "Benchmarks.csproj");
            File.WriteAllText(
                benchmarkProjectPath,
                GenerateIlBenchmarkCsProj(projectConfig.TargetFramework, outputAssemblyPath));

            if (explain && !jsonOutput)
            {
                WriteIlShapeText(resolvedBenchmarks);
            }

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
                var benchmarksByClass = resolvedBenchmarks
                    .GroupBy(b => GetBenchmarkClassName(b.Benchmark.RelativePath), StringComparer.OrdinalIgnoreCase)
                    .ToDictionary(g => g.Key, g => g.ToList(), StringComparer.OrdinalIgnoreCase);

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
                        if (explain && benchmarksByClass.TryGetValue(className, out var methods))
                        {
                            writer.WriteStartArray("methods");
                            foreach (var benchmark in methods)
                            {
                                WriteBenchmarkIlShape(writer, benchmark);
                            }
                            writer.WriteEndArray();
                        }
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
        IReadOnlyList<BenchmarkInfo> discovered,
        bool explain = false)
    {
        var assemblyDirectory = Path.GetDirectoryName(outputAssemblyPath)
            ?? throw new InvalidOperationException($"Could not determine the assembly directory for '{outputAssemblyPath}'.");
        var loadContext = new BenchmarkReflectionLoadContext(assemblyDirectory);

        try
        {
            var assembly = loadContext.LoadFromAssemblyPath(outputAssemblyPath);
            var methods = assembly.GetTypes()
                .SelectMany(type => type.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static))
                .Where(method => !method.IsSpecialName)
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

                resolved.Add(new ResolvedBenchmarkInfo(
                    benchmark,
                    GetCSharpTypeName(method.ReturnType),
                    method.DeclaringType?.FullName ?? throw new InvalidOperationException($"Benchmark method '{benchmark.FunctionName}' is missing a declaring type."),
                    method.Name,
                    explain ? ComputeIlShape(method) : null));
            }

            return resolved;
        }
        finally
        {
            loadContext.Unload();
        }
    }

    // Lookup tables mapping IL opcode values to their <see cref="OpCode"/> definitions.
    // Single-byte opcodes are indexed directly; two-byte opcodes share the 0xFE prefix
    // and are indexed by their second byte.
    private static readonly OpCode?[] SingleByteOpCodes = BuildOpCodeTable(twoByte: false);
    private static readonly OpCode?[] TwoByteOpCodes = BuildOpCodeTable(twoByte: true);

    private static OpCode?[] BuildOpCodeTable(bool twoByte)
    {
        var table = new OpCode?[256];
        foreach (var field in typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static))
        {
            if (field.GetValue(null) is not OpCode opCode)
            {
                continue;
            }

            var value = (ushort)opCode.Value;
            var isTwoByte = (value & 0xFF00) == 0xFE00;
            if (isTwoByte == twoByte)
            {
                table[value & 0xFF] = opCode;
            }
        }

        return table;
    }

    /// <summary>
    /// Decodes a benchmark method's IL body and tallies the operations that most
    /// influence N# runtime performance. Resolution of metadata tokens (to detect
    /// delegate construction) must happen while the declaring module is still loaded.
    /// </summary>
    internal static IlShapeSummary? ComputeIlShape(MethodInfo method)
    {
        byte[]? il;
        try
        {
            il = method.GetMethodBody()?.GetILAsByteArray();
        }
        catch
        {
            // Abstract/extern/runtime-provided methods have no managed IL body.
            il = null;
        }

        if (il == null)
        {
            return null;
        }

        var module = method.Module;
        var genericTypeArgs = method.DeclaringType?.IsGenericType == true
            ? method.DeclaringType.GetGenericArguments()
            : null;
        var genericMethodArgs = method.IsGenericMethod ? method.GetGenericArguments() : null;

        int newobj = 0, box = 0, callvirt = 0, call = 0, delegateCtors = 0;
        var pos = 0;
        while (pos < il.Length)
        {
            var opCode = ReadOpCode(il, ref pos);
            if (opCode == null)
            {
                break;
            }

            var op = opCode.Value;
            int operandToken = 0;
            var hasInlineToken = op.OperandType is OperandType.InlineMethod
                or OperandType.InlineField
                or OperandType.InlineType
                or OperandType.InlineTok
                or OperandType.InlineString
                or OperandType.InlineSig;

            if (hasInlineToken && pos + 4 <= il.Length)
            {
                operandToken = BitConverter.ToInt32(il, pos);
            }

            if (op == OpCodes.Newobj)
            {
                newobj++;
                if (IsDelegateConstructor(module, operandToken, genericTypeArgs, genericMethodArgs))
                {
                    delegateCtors++;
                }
            }
            else if (op == OpCodes.Box)
            {
                box++;
            }
            else if (op == OpCodes.Callvirt)
            {
                callvirt++;
            }
            else if (op == OpCodes.Call)
            {
                call++;
            }

            pos += OperandSize(op.OperandType, il, pos);
        }

        return new IlShapeSummary(il.Length, newobj, box, callvirt, call, delegateCtors);
    }

    private static OpCode? ReadOpCode(byte[] il, ref int pos)
    {
        var first = il[pos++];
        if (first == 0xFE)
        {
            if (pos >= il.Length)
            {
                return null;
            }

            return TwoByteOpCodes[il[pos++]];
        }

        return SingleByteOpCodes[first];
    }

    private static int OperandSize(OperandType operandType, byte[] il, int pos)
    {
        switch (operandType)
        {
            case OperandType.InlineNone:
                return 0;
            case OperandType.ShortInlineBrTarget:
            case OperandType.ShortInlineI:
            case OperandType.ShortInlineVar:
                return 1;
            case OperandType.InlineVar:
                return 2;
            case OperandType.InlineBrTarget:
            case OperandType.InlineField:
            case OperandType.InlineI:
            case OperandType.InlineMethod:
            case OperandType.InlineSig:
            case OperandType.InlineString:
            case OperandType.InlineTok:
            case OperandType.InlineType:
            case OperandType.ShortInlineR:
                return 4;
            case OperandType.InlineI8:
            case OperandType.InlineR:
                return 8;
            case OperandType.InlineSwitch:
                // A 4-byte count N followed by N 4-byte branch targets.
                if (pos + 4 > il.Length)
                {
                    return il.Length - pos;
                }

                var count = BitConverter.ToInt32(il, pos);
                return 4 + (count * 4);
            default:
                return 0;
        }
    }

    private static bool IsDelegateConstructor(
        Module module,
        int token,
        Type[]? genericTypeArgs,
        Type[]? genericMethodArgs)
    {
        if (token == 0)
        {
            return false;
        }

        try
        {
            var resolved = module.ResolveMethod(token, genericTypeArgs, genericMethodArgs);
            if (resolved is not ConstructorInfo ctor)
            {
                return false;
            }

            return typeof(Delegate).IsAssignableFrom(ctor.DeclaringType);
        }
        catch
        {
            // Tokens that cannot be resolved (e.g. across closed generics) are simply
            // not counted as delegate constructions.
            return false;
        }
    }

    private static void WriteBenchmarkIlShape(Utf8JsonWriter writer, ResolvedBenchmarkInfo benchmark)
    {
        writer.WriteStartObject();
        writer.WriteString("name", benchmark.Benchmark.FunctionName);
        var shape = benchmark.IlShape;
        if (shape == null)
        {
            writer.WriteNull("ilShape");
        }
        else
        {
            writer.WriteStartObject("ilShape");
            writer.WriteNumber("ilBytes", shape.IlBytes);
            writer.WriteNumber("newobj", shape.Newobj);
            writer.WriteNumber("box", shape.Box);
            writer.WriteNumber("callvirt", shape.Callvirt);
            writer.WriteNumber("call", shape.Call);
            writer.WriteNumber("delegateCtors", shape.DelegateCtors);
            writer.WriteEndObject();
        }
        writer.WriteEndObject();
    }

    private static void WriteIlShapeText(IReadOnlyList<ResolvedBenchmarkInfo> benchmarks)
    {
        Console.WriteLine("IL-shape summary (--explain):");
        Console.WriteLine();
        foreach (var benchmark in benchmarks)
        {
            var shape = benchmark.IlShape;
            if (shape == null)
            {
                Console.WriteLine($"  {benchmark.Benchmark.FunctionName}: <no managed IL body>");
                continue;
            }

            Console.WriteLine(
                $"  {benchmark.Benchmark.FunctionName}: " +
                $"il={shape.IlBytes}B, newobj={shape.Newobj}, box={shape.Box}, " +
                $"callvirt={shape.Callvirt}, call={shape.Call}, delegateCtors={shape.DelegateCtors}");
        }
        Console.WriteLine();
    }

    private static string GenerateIlBenchmarkClass(
        string className,
        IReadOnlyList<ResolvedBenchmarkInfo> benchmarks,
        string? benchmarkJobAttribute,
        string outputAssemblyPath)
    {
        var escapedAssemblyPath = EscapeCSharpStringLiteral(outputAssemblyPath);
        var sb = new StringBuilder();
        sb.AppendLine("using BenchmarkDotNet.Attributes;");
        sb.AppendLine();
        if (!string.IsNullOrWhiteSpace(benchmarkJobAttribute))
        {
            sb.AppendLine($"[{benchmarkJobAttribute}]");
        }
        sb.AppendLine($"public class {className}");
        sb.AppendLine("{");
        sb.AppendLine($"    private static readonly string __benchmarkAssemblyPath = \"{escapedAssemblyPath}\";");
        sb.AppendLine("    private static readonly global::System.Reflection.Assembly __benchmarkAssembly = global::System.Reflection.Assembly.LoadFrom(__benchmarkAssemblyPath);");
        sb.AppendLine();
        sb.AppendLine("    private static global::System.Reflection.MethodInfo ResolveMethod(string typeName, string methodName)");
        sb.AppendLine("    {");
        sb.AppendLine("        var type = __benchmarkAssembly.GetType(typeName, throwOnError: true)");
        sb.AppendLine("            ?? throw new global::System.InvalidOperationException($\"Benchmark type '{typeName}' was not found.\");");
        sb.AppendLine("        return type.GetMethod(methodName, global::System.Reflection.BindingFlags.Public | global::System.Reflection.BindingFlags.NonPublic | global::System.Reflection.BindingFlags.Static)");
        sb.AppendLine("            ?? throw new global::System.InvalidOperationException($\"Benchmark method '{typeName}.{methodName}' was not found.\");");
        sb.AppendLine("    }");
        sb.AppendLine();
        sb.AppendLine("    private static global::System.Action CreateAction(string typeName, string methodName)");
        sb.AppendLine("        => (global::System.Action)ResolveMethod(typeName, methodName).CreateDelegate(typeof(global::System.Action));");
        sb.AppendLine();
        sb.AppendLine("    private static global::System.Func<T> CreateFunc<T>(string typeName, string methodName)");
        sb.AppendLine("        => (global::System.Func<T>)ResolveMethod(typeName, methodName).CreateDelegate(typeof(global::System.Func<T>));");
        sb.AppendLine();

        foreach (var benchmark in benchmarks)
        {
            var delegateFieldName = $"__{SanitizeClassName(benchmark.Benchmark.FunctionName)}Delegate";
            var escapedTypeName = EscapeCSharpStringLiteral(benchmark.DeclaringTypeName);
            var escapedMethodName = EscapeCSharpStringLiteral(benchmark.MethodName);

            if (benchmark.ReturnTypeName == "void")
            {
                sb.AppendLine($"    private static readonly global::System.Action {delegateFieldName} = CreateAction(\"{escapedTypeName}\", \"{escapedMethodName}\");");
            }
            else
            {
                sb.AppendLine($"    private static readonly global::System.Func<{benchmark.ReturnTypeName}> {delegateFieldName} = CreateFunc<{benchmark.ReturnTypeName}>(\"{escapedTypeName}\", \"{escapedMethodName}\");");
            }

            sb.AppendLine();
            sb.AppendLine("    [Benchmark]");
            if (benchmark.ReturnTypeName == "void")
            {
                sb.AppendLine($"    public void {benchmark.Benchmark.FunctionName}()");
                sb.AppendLine("    {");
                sb.AppendLine($"        {delegateFieldName}();");
                sb.AppendLine("    }");
            }
            else
            {
                sb.AppendLine($"    public {benchmark.ReturnTypeName} {benchmark.Benchmark.FunctionName}()");
                sb.AppendLine("    {");
                sb.AppendLine($"        return {delegateFieldName}();");
                sb.AppendLine("    }");
            }

            sb.AppendLine();
        }

        sb.AppendLine("}");
        return sb.ToString();
    }

    private static string EscapeCSharpStringLiteral(string value)
    {
        return value
            .Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal);
    }

    private static string GenerateIlBenchmarkCsProj(string targetFramework, string outputAssemblyPath)
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
        sb.AppendLine($"    <Reference Include=\"{EscapeXml(Path.GetFileNameWithoutExtension(outputAssemblyPath))}\">");
        sb.AppendLine($"      <HintPath>{EscapeXml(outputAssemblyPath)}</HintPath>");
        sb.AppendLine("    </Reference>");
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
