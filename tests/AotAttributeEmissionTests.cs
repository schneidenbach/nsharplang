using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.Loader;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Performance;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Verifies the IL emitter stamps the correct AOT-safety attributes onto public methods that
/// contain AOT blockers, and that adding those attributes leaves the assembly loadable
/// (attribute emission is metadata-only, so IL bodies — and verifiability — are unchanged).
/// </summary>
public class AotAttributeEmissionTests
{
    private static CompilationUnit Parse(string source, string file = "aot.nl")
    {
        var lexer = new Lexer(source, file);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, file);
        var result = parser.ParseCompilationUnit();
        Assert.NotNull(result.CompilationUnit);
        return result.CompilationUnit!;
    }

    private static AotRequirements RequirementsFor(CompilationUnit unit, string file = "aot.nl")
    {
        var abi = new AbiClassifier(file).Classify(unit);
        var blockers = new AotBlockerAnalyzer(file, abi).Analyze(unit).Blockers;
        return AotRequirements.FromBlockers(blockers);
    }

    private static T CompileWithRequirements<T>(string source, AotRequirements requirements, Func<Assembly, T> inspect)
    {
        var unit = Parse(source);
        var outputPath = Path.Combine(Path.GetTempPath(), $"AotAttr_{Guid.NewGuid():N}.dll");
        var assemblyName = $"AotAttr_{Guid.NewGuid():N}";
        AssemblyLoadContext? loadContext = null;

        try
        {
            var compiler = new Compiler.ILCompiler.ILCompiler(unit, assemblyName, outputPath, projectConfig: null)
            {
                AotRequirements = requirements,
            };
            compiler.Compile();

            var bytes = File.ReadAllBytes(outputPath);
            loadContext = new AssemblyLoadContext($"AotAttr_{Guid.NewGuid():N}", isCollectible: true);
            using var stream = new MemoryStream(bytes);
            return inspect(loadContext.LoadFromStream(stream));
        }
        finally
        {
            loadContext?.Unload();
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    private static MethodInfo? FindMethod(Assembly assembly, string name)
        => assembly.GetType("Program")?.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);

    [Fact]
    public void PublicReflectionApi_GetsRequiresUnreferencedCode()
    {
        const string source = """
            func InspectType(value: object): void {
                let t := value.GetType()
            }
            """;
        var requirements = RequirementsFor(Parse(source));

        var attributeNames = CompileWithRequirements(source, requirements, assembly =>
        {
            var method = FindMethod(assembly, "InspectType");
            Assert.NotNull(method);
            return method!.CustomAttributes.Select(a => a.AttributeType.FullName).ToArray();
        });

        Assert.Contains("System.Diagnostics.CodeAnalysis.RequiresUnreferencedCodeAttribute", attributeNames);
    }

    [Fact]
    public void PublicDynamicCodeApi_GetsRequiresDynamicCode()
    {
        // A clean-compiling public method; the dynamic-code requirement is attached directly
        // so the test exercises attribute emission without depending on the IL emitter being
        // able to bind a specific reflection BCL overload.
        const string source = """
            func Make(seed: int): int {
                return seed + 1
            }
            """;
        var requirements = AotRequirements.FromBlockers(new[]
        {
            new AotBlocker(
                AotSafetyKind.DynamicCodeRequired,
                "aot.nl", 2, 12, 1,
                "Activator.CreateInstance",
                AbiBoundary.ClrPublic,
                "Make"),
        });

        var attributeNames = CompileWithRequirements(source, requirements, assembly =>
        {
            var method = FindMethod(assembly, "Make");
            Assert.NotNull(method);
            return method!.CustomAttributes.Select(a => a.AttributeType.FullName).ToArray();
        });

        Assert.Contains("System.Diagnostics.CodeAnalysis.RequiresDynamicCodeAttribute", attributeNames);
    }

    [Fact]
    public void CleanApi_GetsNoAotAttributes()
    {
        const string source = """
            func Add(a: int, b: int): int {
                return a + b
            }
            """;
        var requirements = RequirementsFor(Parse(source));
        Assert.True(requirements.IsEmpty);

        var attributeNames = CompileWithRequirements(source, requirements, assembly =>
        {
            var method = FindMethod(assembly, "Add");
            Assert.NotNull(method);
            return method!.CustomAttributes.Select(a => a.AttributeType.FullName).ToArray();
        });

        Assert.DoesNotContain("System.Diagnostics.CodeAnalysis.RequiresUnreferencedCodeAttribute", attributeNames);
        Assert.DoesNotContain("System.Diagnostics.CodeAnalysis.RequiresDynamicCodeAttribute", attributeNames);
    }

    [Fact]
    public void EmptyRequirements_DoNotChangeEmittedMethods()
    {
        // With no requirements (the default for ordinary builds), the assembly must still
        // load — the attribute hook is a no-op that does not perturb the method body.
        const string source = """
            func InspectType(value: object): void {
                let t := value.GetType()
            }
            """;

        var loaded = CompileWithRequirements(source, AotRequirements.Empty, assembly =>
            FindMethod(assembly, "InspectType") != null);

        Assert.True(loaded);
    }
}
