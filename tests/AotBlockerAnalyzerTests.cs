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
    public void Reflection_GetType_IsMetadataRequired()
    {
        var blockers = Analyze("""
            func Describe(value: object): void {
                let t := value.GetType()
            }
            """);

        var blocker = Assert.Single(blockers);
        Assert.Equal(AotSafetyKind.MetadataRequired, blocker.Kind);
        Assert.Equal(ErrorCode.AotReflectionUse, blocker.DiagnosticCode);
        Assert.Equal("GetType", blocker.Construct);
        Assert.Equal("Describe", blocker.EnclosingDeclaration);
    }

    [Fact]
    public void Reflection_GetMethod_IsMetadataRequired()
    {
        var blockers = Analyze("""
            func Find(t: object): void {
                let m := t.GetMethod("ToString")
            }
            """);

        Assert.Equal(AotSafetyKind.MetadataRequired, Assert.Single(blockers).Kind);
    }

    [Fact]
    public void Activator_CreateInstance_IsDynamicCode()
    {
        var blockers = Analyze("""
            func Make(t: object): object {
                return Activator.CreateInstance(t)
            }
            """);

        var blocker = Assert.Single(blockers);
        Assert.Equal(AotSafetyKind.DynamicCodeRequired, blocker.Kind);
        Assert.Equal(ErrorCode.AotDynamicCode, blocker.DiagnosticCode);
        Assert.Equal("Activator.CreateInstance", blocker.Construct);
    }

    [Fact]
    public void MakeGenericType_IsRuntimeGenericInstantiation()
    {
        var blockers = Analyze("""
            func Build(t: object): void {
                let g := t.MakeGenericType(t)
            }
            """);

        var blocker = Assert.Single(blockers);
        Assert.Equal(AotSafetyKind.DynamicCodeRequired, blocker.Kind);
        Assert.Equal(ErrorCode.AotMakeGenericType, blocker.DiagnosticCode);
    }

    [Fact]
    public void ExpressionFactory_IsExpressionTree()
    {
        var blockers = Analyze("""
            func Build(): void {
                let e := Expression.Constant(42)
            }
            """);

        var blocker = Assert.Single(blockers);
        Assert.Equal(AotSafetyKind.ExpressionTreeRequired, blocker.Kind);
        Assert.Equal(ErrorCode.AotExpressionTree, blocker.DiagnosticCode);
        Assert.Equal("Expression.Constant", blocker.Construct);
    }

    [Fact]
    public void Compile_IsExpressionTree()
    {
        var blockers = Analyze("""
            func Run(e: object): void {
                let f := e.Compile()
            }
            """);

        Assert.Equal(AotSafetyKind.ExpressionTreeRequired, Assert.Single(blockers).Kind);
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

    [Fact]
    public void PublicFunction_BlockerIsOnPublicSurface()
    {
        var blocker = Assert.Single(Analyze("""
            func PublicApi(value: object): void {
                let t := value.GetType()
            }
            """));

        Assert.Equal(AbiBoundary.ClrPublic, blocker.EnclosingBoundary);
        Assert.True(blocker.IsOnPublicSurface);
    }

    [Fact]
    public void CamelCaseFunction_BlockerIsNotOnPublicSurface()
    {
        var blocker = Assert.Single(Analyze("""
            func helper(value: object): void {
                let t := value.GetType()
            }
            """));

        Assert.NotEqual(AbiBoundary.ClrPublic, blocker.EnclosingBoundary);
        Assert.False(blocker.IsOnPublicSurface);
    }

    [Fact]
    public void Analyze_RecordsPerformanceFacts()
    {
        var unit = Parse("""
            func Describe(value: object): void {
                let t := value.GetType()
            }
            """);
        var abi = new AbiClassifier("test.nl").Classify(unit);
        var store = new PerformanceFactStore();

        var blocker = Assert.Single(new AotBlockerAnalyzer("test.nl", abi).Analyze(unit, store).Blockers);

        var facts = store.Lookup("test.nl", blocker.Line, blocker.Column);
        Assert.NotNull(facts);
        Assert.Equal(AotSafetyKind.MetadataRequired, facts!.AotSafety);
        Assert.Equal(EscapeKind.ReflectionBoundary, facts.Escape);
    }

    private static CallExpression FindSingleInitializerCall(CompilationUnit unit)
    {
        var function = Assert.IsType<FunctionDeclaration>(Assert.Single(unit.Declarations));
        Assert.NotNull(function.Body);
        var body = function.Body!;
        var statement = Assert.IsType<VariableDeclarationStatement>(Assert.Single(body.Statements));
        return Assert.IsType<CallExpression>(statement.Initializer);
    }

    [Fact]
    public void BlockerInsideClassMethod_AttributedToMethod()
    {
        var blocker = Assert.Single(Analyze("""
            class Widget {
                func Inspect(value: object): void {
                    let t := value.GetType()
                }
            }
            """));

        // Type members are keyed by their type-qualified name so the IL emitter can stamp the
        // correct method even when simple names collide across types/overloads.
        Assert.Equal("Widget.Inspect", blocker.EnclosingDeclaration);
        Assert.Equal(AbiBoundary.ClrPublic, blocker.EnclosingBoundary);
    }

    // ── Diagnostics (Elm-quality) ───────────────────────────────────────

    [Fact]
    public void Diagnostic_AsError_BlocksBuildWithGuidance()
    {
        var blocker = Assert.Single(Analyze("""
            func PublicApi(value: object): void {
                let t := value.GetType()
            }
            """));

        var diagnostic = AotDiagnostics.ToDiagnostic(blocker, "    let t := value.GetType()", asError: true);

        Assert.Equal(ErrorSeverity.Error, diagnostic.Severity);
        Assert.Equal("NL960", diagnostic.DiagnosticId);
        Assert.Contains("reflection", diagnostic.Message);
        Assert.Contains("--aot", diagnostic.HumanExplanation);
        Assert.False(string.IsNullOrWhiteSpace(diagnostic.ContextualHint));
        Assert.False(string.IsNullOrWhiteSpace(diagnostic.Suggestion));
        Assert.Equal("https://docs.n-sharp.dev/errors/NL960", diagnostic.DocsUrl);
    }

    [Fact]
    public void Diagnostic_NotAsError_IsAdvisoryWarning()
    {
        var blocker = Assert.Single(Analyze("""
            func PublicApi(value: object): void {
                let t := value.GetType()
            }
            """));

        var diagnostic = AotDiagnostics.ToDiagnostic(blocker, null, asError: false);

        Assert.Equal(ErrorSeverity.Warning, diagnostic.Severity);
    }

    // ── Requirements mapping (attribute emission inputs) ────────────────

    [Fact]
    public void Requirements_PublicReflection_RequiresUnreferencedCode()
    {
        var requirements = AotRequirements.FromBlockers(Analyze("""
            func PublicApi(value: object): void {
                let t := value.GetType()
            }
            """));

        Assert.True(requirements.TryGet("PublicApi", out var annotation));
        Assert.True(annotation.RequiresUnreferencedCode);
        Assert.False(annotation.RequiresDynamicCode);
    }

    [Fact]
    public void Requirements_PublicDynamicCode_RequiresDynamicCode()
    {
        var requirements = AotRequirements.FromBlockers(Analyze("""
            func PublicApi(t: object): object {
                return Activator.CreateInstance(t)
            }
            """));

        Assert.True(requirements.TryGet("PublicApi", out var annotation));
        Assert.True(annotation.RequiresDynamicCode);
    }

    [Fact]
    public void Requirements_PrivateBlocker_ProducesNoAnnotation()
    {
        var requirements = AotRequirements.FromBlockers(Analyze("""
            func helper(value: object): void {
                let t := value.GetType()
            }
            """));

        Assert.True(requirements.IsEmpty);
    }
}
