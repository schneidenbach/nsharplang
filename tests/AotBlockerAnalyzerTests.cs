using System.Linq;
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
    public void SemanticMode_FlagsResolvedObjectGetType()
    {
        var unit = Parse("""
            func Describe(value: object): void {
                let t := value.GetType()
            }
            """);
        var call = FindSingleInitializerCall(unit);
        var semanticModel = new SemanticModel();
        semanticModel.RecordReflectionCallTarget(
            call.Line,
            call.Column,
            typeof(object).GetMethod(nameof(object.GetType))!);
        var abi = new AbiClassifier("test.nl").Classify(unit);

        var blocker = Assert.Single(new AotBlockerAnalyzer("test.nl", abi, semanticModel)
            .Analyze(unit)
            .Blockers);

        Assert.Equal(AotSafetyKind.MetadataRequired, blocker.Kind);
        Assert.Equal("GetType", blocker.Construct);
    }

    [Fact]
    public void SemanticMode_UsesAnalyzerRecordedClrCallTargets()
    {
        var source = """
            func Describe(value: object): void {
                let t := value.GetType()
            }
            """;
        var unit = Parse(source);
        var call = FindSingleInitializerCall(unit);
        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        var analysis = analyzer.Analyze(unit, "test.nl", projectRoot: null, source);
        var abi = new AbiClassifier("test.nl").Classify(unit);

        Assert.NotNull(analysis.SemanticModel.LookupReflectionCallTarget(call.Line, call.Column));
        var blocker = Assert.Single(new AotBlockerAnalyzer("test.nl", abi, analysis.SemanticModel)
            .Analyze(unit)
            .Blockers);

        Assert.Equal(AotSafetyKind.MetadataRequired, blocker.Kind);
        Assert.Equal("GetType", blocker.Construct);
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

    private static CallExpression FindSingleInitializerCall(CompilationUnit unit)
    {
        var function = Assert.IsType<FunctionDeclaration>(Assert.Single(unit.Declarations));
        Assert.NotNull(function.Body);
        var body = function.Body!;
        var statement = Assert.IsType<VariableDeclarationStatement>(Assert.Single(body.Statements));
        return Assert.IsType<CallExpression>(statement.Initializer);
    }

}
