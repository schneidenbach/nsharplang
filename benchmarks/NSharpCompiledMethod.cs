using System;
using System.IO;
using System.Reflection;
using NSharpLang.Compiler;

namespace NSharpLang.Benchmarks;

/// <summary>
/// Compiles an N# source program through the real compiler pipeline (lexer → parser →
/// <see cref="NSharpLang.Compiler.ILCompiler.ILCompiler"/>) and binds a named static method on the
/// emitted <c>Program</c> type to a strongly-typed delegate. Benchmarks call the delegate directly,
/// so the per-iteration cost is the N#-emitted IL, not reflection.
///
/// The matched C# baseline in each benchmark is hand-written to the same algorithm. The point of
/// the corpus is the SHAPE comparison: the deterministic IL-shape ratchet
/// (tests/PerfEvidence/IlShapeRegressionTests.cs) proves the N# side has no enumerator/boxing/throw
/// overhead, and these wall-clock numbers show the shape translates into runtime parity.
/// </summary>
public static class NSharpCompiledMethod
{
    /// <summary>
    /// Compiles <paramref name="source"/> and returns a delegate of type <typeparamref name="TDelegate"/>
    /// bound to the static method <paramref name="methodName"/> on the emitted <c>Program</c> type.
    /// </summary>
    public static TDelegate Bind<TDelegate>(string source, string methodName)
        where TDelegate : Delegate
    {
        var method = Compile(source, methodName);
        return (TDelegate)Delegate.CreateDelegate(typeof(TDelegate), method);
    }

    private static MethodInfo Compile(string source, string methodName)
    {
        var outputPath = Path.Combine(Path.GetTempPath(), $"NSharpBenchmark_{Guid.NewGuid():N}.dll");
        var assemblyName = $"NSharpBenchmark_{Guid.NewGuid():N}";

        try
        {
            var lexer = new Lexer(source, "benchmark.nl");
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, "benchmark.nl");
            var parseResult = parser.ParseCompilationUnit();
            if (parseResult.CompilationUnit is null)
            {
                throw new InvalidOperationException("N# benchmark source failed to parse.");
            }

            var compiler = new Compiler.ILCompiler.ILCompiler(parseResult.CompilationUnit, assemblyName, outputPath);
            compiler.Compile();

            // Load into the default context (not collectible): benchmark methods stay alive for the
            // whole process, and the JIT is free to optimize the bound delegate's target.
            var assembly = Assembly.Load(File.ReadAllBytes(outputPath));
            var programType = assembly.GetType("Program")
                ?? throw new InvalidOperationException("Emitted assembly has no Program type.");

            return programType.GetMethod(
                    methodName,
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException($"Program type has no static method '{methodName}'.");
        }
        finally
        {
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }
}
