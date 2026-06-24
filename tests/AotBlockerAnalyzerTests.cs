using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Performance;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Regression tests for the AOT-blocker analysis pass: detection coverage, ABI-surface
/// attribution, perf-fact recording, and the Elm-quality diagnostics it produces.
/// </summary>
public class AotBlockerAnalyzerTests
{
    private static CompilationUnit Parse(string source, string file = "test.nl")
    {
        var lexer = new Lexer(source, file);
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, file);
        var result = parser.ParseCompilationUnit();
        Assert.NotNull(result.CompilationUnit);
        return result.CompilationUnit!;
    }

    private static System.Collections.Generic.IReadOnlyList<AotBlocker> Analyze(string source, string file = "test.nl")
    {
        var unit = Parse(source, file);
        var abi = new AbiClassifier(file).Classify(unit);
        return new AotBlockerAnalyzer(file, abi).Analyze(unit).Blockers;
    }

    [Fact]
    public void CleanCode_HasNoBlockers()
    {
        var blockers = Analyze("""
            func Add(a: int, b: int): int {
                return a + b
            }
            """);

        Assert.Empty(blockers);
    }

    [Fact]
    public void SemanticMode_DoesNotFlagUserMethodNamedCompile()
    {
        var unit = Parse("""
            class Worker {
                func Compile(): int {
                    return 1
                }
            }

            func Run(): int {
                let worker := new Worker()
                return worker.Compile()
            }
            """);
        var abi = new AbiClassifier("test.nl").Classify(unit);
        var semanticModel = new SemanticModel();

        var blockers = new AotBlockerAnalyzer("test.nl", abi, semanticModel)
            .Analyze(unit)
            .Blockers;

        Assert.Empty(blockers);
    }

    [Fact]
    public void NameofIsNotReflection()
    {
        // nameof is compile-time and must never be flagged.
        var blockers = Analyze("""
            func Label(): string {
                return nameof(Label)
            }
            """);

        Assert.Empty(blockers);
    }

}
