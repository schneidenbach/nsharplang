using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.Columnar;

namespace NSharpLang.Tests;

public class AnalyzerTests
{
    private AnalysisResult Analyze(string source)
    {
        var result = ColumnarParserRecovery.ParseFileAst(source, null);
        var analyzer = new Analyzer();

        // Load system assemblies
        analyzer.LoadSystemAssemblies();

        return analyzer.Analyze(result.CompilationUnit!);
    }

    private void AssertNoErrors(string source)
    {
        var result = Analyze(source);
        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void Analyzer_SourceSnippet_PreservesCrLfSplitBehavior()
    {
        var source = string.Join("\r\n", new[]
        {
            "func main() {",
            "    let value: var = 42",
            "}"
        });

        var result = AnalyzeWithSource(source);

        var diagnostic = Assert.Single(
            result.Errors,
            error => error.Message.Contains("'var' is not a type", StringComparison.Ordinal));
        Assert.Equal("    let value: var = 42\r", diagnostic.SourceSnippet);
    }

    /// <summary>
    /// Analyze source code with full source context so the rich error path (ErrorMessageBuilder) is taken,
    /// populating ContextualHint with conversion suggestions.
    /// </summary>
    private AnalysisResult AnalyzeWithSource(string source)
    {
        var result = ColumnarParserRecovery.ParseFileAst(source, null);
        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        return analyzer.Analyze(result.CompilationUnit!, "test.nl", null, source);
    }

    [Fact]
    public void BuiltInMemberTypo_WithoutSystemAssemblies_ReportsUndefinedMember()
    {
        const string source = """
func Main() {
    print "asdf".ToUpper()
    print "asdf".Length
    print "asdf".ToUp()
}
""";

        var parseResult = ColumnarParserRecovery.ParseFileAst(source, "Program.nl");
        using var analyzer = new Analyzer();

        var result = analyzer.Analyze(parseResult.CompilationUnit!, "/tmp/Program.nl", projectRoot: null, source);

        var diagnostic = Assert.Single(result.Errors,
            error => error.Code == ErrorCode.UndefinedMember &&
                     error.Message.Contains("ToUp"));
        Assert.Equal(4, diagnostic.Line);
        Assert.Equal(18, diagnostic.Column);
        Assert.Equal("ToUp".Length, diagnostic.Length);
    }

    [Fact]
    public void Write_SettableSourcePropertyTarget_Valid()
    {
        var result = AnalyzeWithSource("""
            class Box {
                backing: int

                Value: int {
                    get {
                        return backing
                    }
                    set {
                        backing = value
                    }
                }

                constructor() {
                    backing = 0
                }

                func Mutate(other: Box) {
                    Value = 1
                    other.Value += 2
                    other.Value++
                }
            }
        """);

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void BitwiseAndShift_BuiltInOperands_RecordPromotedTypes()
    {
        var result = AnalyzeWithSource(@"
func getByte(): byte { return 1 as byte }
func getUInt(): uint { return 1 as uint }

func Main() {
    intBits := 1 & 2
    smallBits := getByte() | getByte()
    mixedUnsigned := getUInt() ^ 1
    shiftedInt := 1 << 3
    shiftedSmall := getByte() << 1
    boolBits := true & false
}
");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("intBits")?.ToString());
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("smallBits")?.ToString());
        Assert.Equal("long", result.SemanticModel.LookupIdentifier("mixedUnsigned")?.ToString());
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("shiftedInt")?.ToString());
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("shiftedSmall")?.ToString());
        Assert.Equal("bool", result.SemanticModel.LookupIdentifier("boolBits")?.ToString());
    }

    [Fact]
    public void UnaryNumericOperators_RecordPromotedTypes()
    {
        var result = AnalyzeWithSource(@"
func getByte(): byte { return 1 as byte }
func getUInt(): uint { return 1 as uint }
func getLong(): long { return 1L }

func Main() {
    negSmall := -getByte()
    negUInt := -getUInt()
    invSmall := ~getByte()
    invUInt := ~getUInt()
    invLong := ~getLong()
}
");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("negSmall")?.ToString());
        Assert.Equal("long", result.SemanticModel.LookupIdentifier("negUInt")?.ToString());
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("invSmall")?.ToString());
        Assert.Equal("uint", result.SemanticModel.LookupIdentifier("invUInt")?.ToString());
        Assert.Equal("long", result.SemanticModel.LookupIdentifier("invLong")?.ToString());
    }

    [Fact]
    public void Lambda_Simple()
    {
        // Lambda test - just check that lambdas don't crash the analyzer
        // Full type inference for lambdas is complex and deferred
        var source = @"
            func Main() {
                f := x => 42
            }
        ";
        var result = Analyze(source);
        // Just ensure it doesn't crash - type errors are expected for now
        Assert.NotNull(result);
    }

    [Fact]
    public void TupleDeconstruction_InferredElementTypes_Valid()
    {
        var result = AnalyzeWithSource("""
            func Main() {
                count, text := (3, "abc")
                total := count + text.Length
            }
        """);

        Assert.Empty(result.Errors);
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("count")?.ToString());
        Assert.Equal("string", result.SemanticModel.LookupIdentifier("text")?.ToString());
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("total")?.ToString());
    }

    [Fact]
    public void TupleDeconstruction_CallResultElementTypes_Valid()
    {
        var result = AnalyzeWithSource("""
            func pair(): (left: int, right: string) {
                return (left: 2, right: "ab")
            }

            func Main() {
                number, label := pair()
                total := number + label.Length
            }
        """);

        Assert.Empty(result.Errors);
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("number")?.ToString());
        Assert.Equal("string", result.SemanticModel.LookupIdentifier("label")?.ToString());
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("total")?.ToString());
    }

    [Fact]
    public void ForeachLoop_SpanCollection_Valid()
    {
        var result = AnalyzeWithSource("""
            import System

            func Sum(numbers: ReadOnlySpan<int>): int {
                total := 0
                foreach value in numbers {
                    total += value
                }

                return total
            }
            """);

        Assert.Empty(result.Errors);
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("value")?.ToString());
    }

    [Fact]
    public void AwaitForeachLoop_AsyncEnumerableCollection_Valid()
    {
        var result = AnalyzeWithSource("""
            import System.Collections.Generic
            import System.Threading.Tasks

            async func Sum(numbers: IAsyncEnumerable<int>): Task<int> {
                total := 0
                await foreach value in numbers {
                    total += value
                }

                return total
            }
            """);

        Assert.Empty(result.Errors);
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("value")?.ToString());
    }

    [Fact]
    public void AwaitForeachLoop_AsyncGeneratorCall_Valid()
    {
        var result = AnalyzeWithSource("""
            import System.Collections.Generic

            async func* Numbers(): IAsyncEnumerable<int> {
                yield 1
            }

            async func Sum() {
                total := 0
                await foreach value in Numbers() {
                    total += value
                }
            }
            """);

        Assert.Empty(result.Errors);
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("value")?.ToString());
    }

    // Extension Method Resolution Tests

    [Fact]
    public void ImplicitConversion_ClassToClass()
    {
        var result = AnalyzeWithSource("""
            class Celsius {
                Value: double

                implicit operator Fahrenheit(c: Celsius) {
                    return new Fahrenheit { Value: c.Value * 9.0 / 5.0 + 32.0 }
                }
            }

            class Fahrenheit {
                Value: double
            }

            func Main() {
                let c: Celsius = new Celsius { Value: 20.0 }
                let f: Fahrenheit = c  // Implicit conversion should work
            }
        """);

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void ImplicitConversion_BidirectionalConversions()
    {
        var result = AnalyzeWithSource("""
            class Meters {
                Value: double

                implicit operator Centimeters(m: Meters) {
                    return new Centimeters { Value: m.Value * 100.0 }
                }
            }

            class Centimeters {
                Value: double

                implicit operator Meters(cm: Centimeters) {
                    return new Meters { Value: cm.Value / 100.0 }
                }
            }

            func Main() {
                let m: Meters = new Meters { Value: 5.0 }
                let cm: Centimeters = m  // Meters -> Centimeters
                let m2: Meters = cm      // Centimeters -> Meters
            }
        """);

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void Assignment_UserDefinedImplicitConversion_Allowed()
    {
        var result = AnalyzeWithSource("""
            class Celsius {
                Value: double

                implicit operator Fahrenheit(c: Celsius) {
                    return new Fahrenheit { Value: c.Value }
                }
            }

            class Fahrenheit {
                Value: double
            }

            func Main() {
                celsius := new Celsius { Value: 20.0 }
                fahrenheit: Fahrenheit = celsius
            }
        """);

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void TestDefaultParametersWithLiterals()
    {
        // Valid: default parameters with literal values
        var result = Analyze(@"
            func Greet(name: string, greeting: string = ""Hello"", times: int = 1) {
                print greeting
            }

            func Main() {
                Greet(""Alice"")
                Greet(""Bob"", ""Hi"")
                Greet(""Charlie"", ""Hey"", 3)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersWithNullLiteral()
    {
        // Valid: nullable type with null default
        var result = Analyze(@"
            func Process(data: string?) {
                if (data != null) {
                    print data
                }
            }

            func Main() {
                Process(null)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersWithNumericExpressions()
    {
        // Valid: numeric literal expressions as defaults
        var result = Analyze(@"
            func Calculate(x: int = 2 + 3, y: int = -5, z: float = 3.14) {
                print x
            }

            func Main() {
                Calculate()
                Calculate(10)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersWithBooleanLiterals()
    {
        // Valid: boolean literals as defaults
        var result = Analyze(@"
            func Configure(enabled: bool = true, verbose: bool = false) {
                print enabled
                print verbose
            }

            func Main() {
                Configure()
                Configure(false)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersAllOptional()
    {
        // Valid: all parameters are optional
        var result = Analyze(@"
            func AllOptional(a: int = 1, b: int = 2, c: int = 3) {
                print a + b + c
            }

            func Main() {
                AllOptional()
                AllOptional(10)
                AllOptional(10, 20)
                AllOptional(10, 20, 30)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersInMethods()
    {
        // Valid: default parameters in class methods
        var result = Analyze(@"
            class Calculator {
                func Add(a: int, b: int = 0): int {
                    return a + b
                }
            }

            func Main() {
                calc := new Calculator()
                result1 := calc.Add(5)
                result2 := calc.Add(5, 3)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersInConstructors()
    {
        // Valid: default parameters in constructors
        var result = Analyze(@"
            class Person {
                Name: string
                Age: int

                constructor(name: string, age: int = 0) {
                    Name = name
                    Age = age
                }
            }

            func Main() {
                p1 := new Person(""Alice"")
                p2 := new Person(""Bob"", 30)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersParamsStaysLast()
    {
        // Valid: params parameter is still last, default parameters before it
        var result = Analyze(@"
            func Format(prefix: string = """", params values: int[]) {
                print prefix
            }

            func Main() {
                Format(""Numbers:"", 1, 2, 3)
                Format()
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersExtensionMethods()
    {
        // Valid: default parameters in extension methods
        var result = Analyze(@"
            func IsLongerThan(this s: string, minLength: int = 0): bool {
                return s.Length > minLength
            }

            func Main() {
                result1 := ""hello"".IsLongerThan()
                result2 := ""hello"".IsLongerThan(3)
            }
        ");

        Assert.Empty(result.Errors);
    }

    // ==================== Assembly Resolution Tests (Phase 1) ====================

    [Fact]
    public void AwaitExpression_TaskResult_InfersResultType()
    {
        var result = AnalyzeWithSource("""
            import System.Threading.Tasks

            async func GetCount(): Task<int> {
                return 3
            }

            async func Main(): Task<int> {
                count := await GetCount()
                total := count + 1
                return total
            }
            """);

        Assert.Empty(result.Errors);
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("count")?.ToString());
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("total")?.ToString());
    }

    [Fact]
    public void AwaitExpression_ValueTaskResult_InfersResultType()
    {
        var result = AnalyzeWithSource("""
            import System.Threading.Tasks

            async func GetLabel(): ValueTask<string> {
                return "abc"
            }

            async func Main(): Task<int> {
                label := await GetLabel()
                length := label.Length
                return length
            }
            """);

        Assert.Empty(result.Errors);
        Assert.Equal("string", result.SemanticModel.LookupIdentifier("label")?.ToString());
        Assert.Equal("int", result.SemanticModel.LookupIdentifier("length")?.ToString());
    }

    // ==================== ASP.NET Core Integration Tests (Task 034) ====================

    [Fact]
    public void MethodGroupToClrDelegate_RejectsRefParameterMismatch()
    {
        var result = Analyze(@"
            import System

            func Use(action: Action<int>) {
            }

            func Bump(ref value: int) {
                value = value + 1
            }

            func Main() {
                Use(Bump)
            }
        ");

        Assert.True(result.HasErrors, "Expected method group binding to reject ref/by-value parameter mismatch.");
        Assert.Contains(result.Errors, error => error.Message.Contains("Bump"));
    }

    // ── Lambda Contextual Type Inference for N# Functions ──

    [Fact]
    public void Lambda_NSharpFunction_InfersParameterType_FuncIntInt()
    {
        AssertNoErrors(@"
            func Apply(f: Func<int, int>): int {
                return f(42)
            }

            func Main() {
                result := Apply(x => x * 2)
            }
        ");
    }

    [Fact]
    public void Lambda_NSharpFunction_InfersParameterType_FuncStringInt()
    {
        AssertNoErrors(@"
            func Transform(items: List<string>, f: Func<string, int>): int {
                return f(items[0])
            }

            func Main() {
                items := [""hello"", ""world""]
                result := Transform(items, x => x.Length)
            }
        ");
    }

    [Fact]
    public void Lambda_NSharpFunction_InfersMultipleParams_FuncIntIntInt()
    {
        AssertNoErrors(@"
            func Process(f: Func<int, int, int>): int {
                return f(1, 2)
            }

            func Main() {
                result := Process((x, y) => x + y)
            }
        ");
    }

    [Fact]
    public void Lambda_NSharpFunction_BlockBody_InfersParameterType()
    {
        AssertNoErrors(@"
            func Apply(f: Func<int, int>): int {
                return f(42)
            }

            func Main() {
                result := Apply(x => { return x * 2 })
            }
        ");
    }

    [Fact]
    public void Lambda_NSharpFunction_Action_InfersParameterType()
    {
        AssertNoErrors(@"
            func DoWith(value: int, action: Action<int>) {
                action(value)
            }

            func Main() {
                DoWith(42, x => x + 1)
            }
        ");
    }

    // ── Lambda Contextual Type Inference from Variable/Field/Return/Assignment ──

    [Fact]
    public void Lambda_VarDecl_FuncIntInt_InfersParamType()
    {
        AssertNoErrors(@"
            func Main() {
                let handler: Func<int, int> = x => x * 2
            }
        ");
    }

    [Fact]
    public void Lambda_VarDecl_ActionString_InfersParamType()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                let action: Action<string> = s => Console.WriteLine(s)
            }
        ");
    }

    // An untyped lambda parameter with NO inference source must be a compile-time error: the Unknown
    // type used to flow into emit and produce a delegate whose invocation CORRUPTED MEMORY at runtime
    // (AccessViolationException — probe-proven on `f := (x) => x + 1` + `f(5)`).

    [Fact]
    public void Lambda_UntypedParams_NoInferenceSource_SingleErrorPerLambda()
    {
        var result = Analyze(@"
            func Main() {
                f := (x, y) => x + y
                result := f(1, 2)
            }
        ");
        Assert.Equal(1, result.Errors.Count(e =>
            e.Message.Contains("can't figure out the type of lambda parameter")));
    }

    [Fact]
    public void Lambda_ZeroParam_NoInferenceSource_NoError()
    {
        // Nothing to infer — `zero := () => 99` is legal and runs.
        AssertNoErrors(@"
            func Main() {
                zero := () => 99
                result := zero()
            }
        ");
    }

    [Fact]
    public void Lambda_VarDecl_MultiParam_InfersParamTypes()
    {
        AssertNoErrors(@"
            func Main() {
                let combine: Func<int, int, int> = (x, y) => x + y
            }
        ");
    }

    [Fact]
    public void Lambda_VarDecl_BlockBody_InfersParamType()
    {
        AssertNoErrors(@"
            func Main() {
                let handler: Func<int, int> = x => { return x * 2 }
            }
        ");
    }

    [Fact]
    public void Lambda_Assignment_InfersParamType()
    {
        AssertNoErrors(@"
            func Apply(f: Func<int, int>): int {
                return f(42)
            }

            func Main() {
                let handler: Func<int, int> = x => x
                handler = x => x * 2
            }
        ");
    }

    [Fact]
    public void Lambda_ReturnStatement_InfersParamType()
    {
        AssertNoErrors(@"
            func GetHandler(): Func<int, int> {
                return x => x * 2
            }
        ");
    }

    [Fact]
    public void Lambda_FieldInitializer_InfersParamType()
    {
        AssertNoErrors(@"
            class Calculator {
                Doubler: Func<int, int> = x => x * 2
            }
        ");
    }

    // ── Extension Methods on Literals ──

    [Fact]
    public void ExtensionMethod_OnIntLiteral_NoError()
    {
        AssertNoErrors(@"
            func Double(this n: int): int {
                return n * 2
            }

            func Main() {
                let result: int = 5.Double()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_OnStringLiteral_NoError()
    {
        AssertNoErrors(@"
            func IsEmpty(this s: string): bool {
                return s.Length == 0
            }

            func Main() {
                let result: bool = ""hello"".IsEmpty()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_OnDoubleLiteral_NoError()
    {
        AssertNoErrors(@"
            func Negate(this d: double): double {
                return 0.0 - d
            }

            func Main() {
                let result: double = 3.14.Negate()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_IntLiteral_InstanceMethod_NoError()
    {
        // Instance methods on built-in types should also work on literals
        AssertNoErrors(@"
            func Main() {
                s := 5.ToString()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_StringLiteral_InstanceProperty_NoError()
    {
        AssertNoErrors(@"
            func Main() {
                len := ""hello"".Length
            }
        ");
    }

    // Circular import detection tests

    [Fact]
    public void CircularImport_TwoFiles_ReportsError()
    {
        // Create temp directory with two files that import each other
        var tempDir = Path.Combine(Path.GetTempPath(), "nsharp_test_circular_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);

        try
        {
            var fileA = Path.Combine(tempDir, "A.nl");
            var fileB = Path.Combine(tempDir, "B.nl");

            File.WriteAllText(fileA, @"import ""./B""

func Hello(): string {
    return ""hello""
}
");
            File.WriteAllText(fileB, @"import ""./A""

func World(): string {
    return ""world""
}
");

            // Parse and analyze file A
            var sourceA = File.ReadAllText(fileA);
            var parseResult = ColumnarParserRecovery.ParseFileAst(sourceA, fileA);
            var analyzer = new Analyzer();
            analyzer.LoadSystemAssemblies();

            var result = analyzer.Analyze(parseResult.CompilationUnit!, fileA, tempDir, sourceA);

            Assert.True(result.HasErrors, "Expected circular import error but got none");
            Assert.Contains(result.Errors, e => e.Code == ErrorCode.CircularImport);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CircularImport_SelfImport_ReportsError()
    {
        // Create temp directory with a file that imports itself
        var tempDir = Path.Combine(Path.GetTempPath(), "nsharp_test_self_import_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);

        try
        {
            var file = Path.Combine(tempDir, "Self.nl");
            File.WriteAllText(file, @"import ""./Self""

func Hello(): string {
    return ""hello""
}
");

            var source = File.ReadAllText(file);
            var parseResult = ColumnarParserRecovery.ParseFileAst(source, file);
            var analyzer = new Analyzer();
            analyzer.LoadSystemAssemblies();

            var result = analyzer.Analyze(parseResult.CompilationUnit!, file, tempDir, source);

            Assert.True(result.HasErrors, "Expected circular import error but got none");
            Assert.Contains(result.Errors, e => e.Code == ErrorCode.CircularImport);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void NonCircularImport_NoError()
    {
        // Create temp directory with two files where only one imports the other (no cycle)
        var tempDir = Path.Combine(Path.GetTempPath(), "nsharp_test_no_circular_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempDir);

        try
        {
            var fileA = Path.Combine(tempDir, "A.nl");
            var fileB = Path.Combine(tempDir, "B.nl");

            File.WriteAllText(fileA, @"import ""./B""

func Hello(): string {
    return ""hello""
}
");
            File.WriteAllText(fileB, @"func World(): string {
    return ""world""
}
");

            var sourceA = File.ReadAllText(fileA);
            var parseResult = ColumnarParserRecovery.ParseFileAst(sourceA, fileA);
            var analyzer = new Analyzer();
            analyzer.LoadSystemAssemblies();

            var result = analyzer.Analyze(parseResult.CompilationUnit!, fileA, tempDir, sourceA);

            Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.CircularImport);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    // ================================================================
    // N#-declared method overload resolution
    // ================================================================

    [Fact]
    public void OverloadResolution_ClassMethod_IntOverload()
    {
        AssertNoErrors(@"
            class Processor {
                func Process(x: int): int {
                    return x
                }
                func Process(x: string): string {
                    return x
                }
            }
            func Main() {
                p := new Processor()
                result := p.Process(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ClassMethod_StringOverload()
    {
        AssertNoErrors(@"
            class Processor {
                func Process(x: int): int {
                    return x
                }
                func Process(x: string): string {
                    return x
                }
            }
            func Main() {
                p := new Processor()
                result := p.Process(""hello"")
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ClassMethod_MultipleParams()
    {
        AssertNoErrors(@"
            class Math {
                func Add(a: int, b: int): int {
                    return a
                }
                func Add(a: string, b: string): string {
                    return a
                }
            }
            func Main() {
                m := new Math()
                r1 := m.Add(1, 2)
                r2 := m.Add(""a"", ""b"")
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ClassMethod_DifferentArity()
    {
        AssertNoErrors(@"
            class Logger {
                func Log(msg: string) {
                }
                func Log(msg: string, level: int) {
                }
            }
            func Main() {
                l := new Logger()
                l.Log(""hello"")
                l.Log(""hello"", 3)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_StructMethod()
    {
        AssertNoErrors(@"
            struct Point {
                x: int
                y: int
                func Scale(factor: int): int {
                    return factor
                }
                func Scale(factor: double): double {
                    return factor
                }
            }
            func Main() {
                p := new Point()
                r := p.Scale(2)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_TopLevelFunctions()
    {
        AssertNoErrors(@"
            func Greet(name: string): string {
                return name
            }
            func Greet(name: string, greeting: string): string {
                return greeting
            }
            func Main() {
                r1 := Greet(""Alice"")
                r2 := Greet(""Alice"", ""Hi"")
            }
        ");
    }

    // ================================================================
    // Generic type inference for N#-declared functions
    // ================================================================

    [Fact]
    public void GenericInference_Identity_Int()
    {
        AssertNoErrors(@"
            func Identity<T>(x: T): T {
                return x
            }
            func Main() {
                result := Identity(42)
            }
        ");
    }

    [Fact]
    public void GenericInference_Identity_String()
    {
        AssertNoErrors(@"
            func Identity<T>(x: T): T {
                return x
            }
            func Main() {
                result := Identity(""hello"")
            }
        ");
    }

    [Fact]
    public void GenericInference_ExplicitTypeArg()
    {
        AssertNoErrors(@"
            func Identity<T>(x: T): T {
                return x
            }
            func Main() {
                result := Identity<int>(42)
            }
        ");
    }

    [Fact]
    public void GenericInference_TwoTypeParams()
    {
        AssertNoErrors(@"
            func Pair<A, B>(a: A, b: B): A {
                return a
            }
            func Main() {
                result := Pair(1, ""two"")
            }
        ");
    }

    [Fact]
    public void GenericInference_ClassMethod()
    {
        AssertNoErrors(@"
            class Container {
                func Wrap<T>(value: T): T {
                    return value
                }
            }
            func Main() {
                c := new Container()
                r := c.Wrap(42)
            }
        ");
    }

    [Fact]
    public void GenericInference_ClassMethodOverload_WithGeneric()
    {
        // Non-generic overload should be preferred over generic when both match
        AssertNoErrors(@"
            class Converter {
                func Convert(x: int): string {
                    return ""int""
                }
                func Convert<T>(x: T): T {
                    return x
                }
            }
            func Main() {
                c := new Converter()
                r1 := c.Convert(42)
            }
        ");
    }

    [Fact]
    public void GenericInference_ReturnsGenericType()
    {
        // Inference should work when return type uses the inferred type parameter
        AssertNoErrors(@"
            func MakeList<T>(x: T): List<T> {
                items := new List<T>()
                items.Add(x)
                return items
            }
            func Main() {
                result := MakeList(42)
            }
        ");
    }

    [Fact]
    public void GenericInference_FromNestedGenericArg()
    {
        // T should be inferred from List<T> argument
        AssertNoErrors(@"
            func First<T>(items: List<T>): T {
                return items[0]
            }
            func Main() {
                list := new List<int>()
                list.Add(1)
                result := First(list)
            }
        ");
    }

    [Fact]
    public void GenericInference_FromArrayArg()
    {
        // T should be inferred from T[] argument
        AssertNoErrors(@"
            func First<T>(items: T[]): T {
                return items[0]
            }
            func Main() {
                arr := [1, 2, 3]
                result := First(arr)
            }
        ");
    }

    [Fact]
    public void GenericInference_SameTypeParamMultipleArgs()
    {
        // T is constrained by both arguments; they must agree
        AssertNoErrors(@"
            func Max<T>(a: T, b: T): T {
                return a
            }
            func Main() {
                result := Max(1, 2)
            }
        ");
    }

    [Fact]
    public void GenericInference_NumericWidening()
    {
        // When T appears for both int and double args, LUB should pick double
        AssertNoErrors(@"
            func Max<T>(a: T, b: T): T {
                return a
            }
            func Main() {
                result := Max(1, 2.5)
            }
        ");
    }

    [Fact]
    public void GenericInference_ThreeTypeParams()
    {
        // Triple type parameter inference
        AssertNoErrors(@"
            func Triple<A, B, C>(a: A, b: B, c: C): A {
                return a
            }
            func Main() {
                result := Triple(1, ""hello"", true)
            }
        ");
    }

    [Fact]
    public void GenericInference_WithConstraint_Satisfied()
    {
        // Inference + constraint validation
        AssertNoErrors(@"
            interface IComparable {
                func CompareTo(other: object): int
            }
            class MyNum : IComparable {
                func CompareTo(other: object): int {
                    return 0
                }
            }
            func Max<T>(a: T, b: T): T where T : IComparable {
                return a
            }
            func Main() {
                result := Max(new MyNum(), new MyNum())
            }
        ");
    }

    [Fact]
    public void GenericInference_ExtensionMethod()
    {
        // Inference on extension method (first param is this)
        AssertNoErrors(@"
            func Identity<T>(this x: T): T {
                return x
            }
            func Main() {
                result := 42.Identity()
            }
        ");
    }

    [Fact]
    public void GenericInference_ExtensionMethod_ReturnType()
    {
        // Extension method inference should correctly bind return type via receiver
        AssertNoErrors(@"
            func Double<T>(this x: T): T {
                return x
            }
            func Process(x: int): int {
                return x
            }
            func Main() {
                result := Process(42.Double())
            }
        ");
    }

    [Fact]
    public void GenericInference_NullableParam()
    {
        // Infer T from non-nullable parameter when T? is also present
        AssertNoErrors(@"
            func ValueOrDefault<T>(fallback: T, x: T?): T {
                return fallback
            }
            func Main() {
                result := ValueOrDefault(42, null)
            }
        ");
    }

    [Fact]
    public void GenericInference_ParamsCollection()
    {
        // Inference with params collection (non-array) parameter
        AssertNoErrors(@"
            func Enumerate<T>(params items: List<T>): int {
                return 0
            }
            func Main() {
                result := Enumerate(1, 2, 3)
            }
        ");
    }

    [Fact]
    public void GenericInference_ParamsArray()
    {
        // Inference with params parameter
        AssertNoErrors(@"
            func CreateList<T>(params items: T[]): int {
                return 0
            }
            func Main() {
                result := CreateList(1, 2, 3)
            }
        ");
    }

    [Fact]
    public void GenericInference_ExplicitArrayTypeArgument_ParamsArray()
    {
        AssertNoErrors(@"
            func Sum(params numbers: int[]): int {
                return 0
            }

            func CreateList<T>(params items: T[]): int {
                return 0
            }

            func Main() {
                direct := Sum([1, 2, 3])
                arrays := CreateList<int[]>([1, 2], [3, 4], [5, 6])
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ParamsOverload()
    {
        AssertNoErrors(@"
            class Formatter {
                func Format(msg: string): string {
                    return msg
                }
                func Format(msg: string, params args: int[]): string {
                    return msg
                }
            }
            func Main() {
                f := new Formatter()
                f.Format(""hello"")
                f.Format(""hello"", 1, 2, 3)
            }
        ");
    }

    // ================================================================
    // Type-based overload resolution — same arity, different types
    // ================================================================

    [Fact]
    public void OverloadResolution_SameArity_IntVsString_SelectsInt()
    {
        AssertNoErrors(@"
            func Process(x: int): int { return x }
            func Process(x: string): string { return x }
            func Main() {
                r := Process(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_SameArity_IntVsString_SelectsString()
    {
        AssertNoErrors(@"
            func Process(x: int): int { return x }
            func Process(x: string): string { return x }
            func Main() {
                r := Process(""hello"")
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ImplicitNumeric_IntToLong()
    {
        AssertNoErrors(@"
            func Handle(x: long): long { return x }
            func Handle(x: string): string { return x }
            func Main() {
                r := Handle(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ImplicitNumeric_IntToDouble()
    {
        AssertNoErrors(@"
            func Calc(x: double): double { return x }
            func Calc(x: string): string { return x }
            func Main() {
                r := Calc(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_PreferExactOverImplicit()
    {
        // When both int and long overloads exist, int literal should prefer int
        AssertNoErrors(@"
            func Handle(x: int): int { return x }
            func Handle(x: long): long { return x }
            func Main() {
                r := Handle(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ExtensionOverload_SameThis_DifferentParams()
    {
        AssertNoErrors(@"
            func Format(this x: int, prefix: string): string { return prefix }
            func Format(this x: int, decimals: int): int { return decimals }
            func Main() {
                r1 := 5.Format(""pre"")
                r2 := 5.Format(3)
            }
        ");
    }

    // ================================================================
    // Extension methods on literal receivers — type safety
    // ================================================================

    [Fact]
    public void Extension_LiteralReceiver_InExpression()
    {
        // Extension return used in binary expression
        AssertNoErrors(@"
            func Double(this n: int): int { return n * 2 }
            func Main() {
                r := 5.Double() + 3
            }
        ");
    }

    [Fact]
    public void Extension_ChainedOnLiteral()
    {
        // 5.ToString().Length should work (CLR methods)
        AssertNoErrors(@"
            func Main() {
                r := 5.ToString().Length
            }
        ");
    }

    [Fact]
    public void Extension_DoubleLiteral_Receiver()
    {
        AssertNoErrors(@"
            func Negate(this d: double): double { return 0.0 - d }
            func Main() {
                r := 3.14.Negate()
            }
        ");
    }

    // ================================================================
    // .NET BCL interop — overloaded static methods
    // ================================================================

    [Fact]
    public void BCL_ConsoleWrite_IntOverload()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Console.Write(42)
            }
        ");
    }

    [Fact]
    public void BCL_ConsoleWrite_StringOverload()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Console.Write(""hello"")
            }
        ");
    }

    [Fact]
    public void BCL_ConsoleWrite_BoolOverload()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Console.Write(true)
            }
        ");
    }

    [Fact]
    public void BCL_MathMax_IntOverload()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                r := Math.Max(1, 2)
            }
        ");
    }

    [Fact]
    public void BCL_StaticParamsArray_AllowsExpandedArguments()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks

            func Main() {
                task := Task.CompletedTask
                Task.WaitAll(task, task, task)
            }
        ");
    }

    [Fact]
    public void BCL_IntegerParse()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                n := Int32.Parse(""42"")
            }
        ");
    }

    [Fact]
    public void NestedClass_ResolvesThroughOwnerTypeInfo()
    {
        AssertNoErrors(@"
            class Outer {
                class Inner {
                    Value: int

                    constructor(value: int) {
                        Value = value
                    }
                }
            }

            func MakeInner(): Outer.Inner {
                return new Outer.Inner(42)
            }

            func Main() {
                item := MakeInner()
                value := item.Value
            }
        ");
    }

    [Fact]
    public void SingleFunctionMemberCall_ResolvesThroughTypeInfoDeclaredMembers()
    {
        AssertNoErrors(@"
            class Greeter {
                func Join(left: string, right: string): string {
                    return left + right
                }
            }

            func Main() {
                greeter := new Greeter()
                message := greeter.Join(right: ""world"", left: ""hello "")
            }
        ");
    }

    [Fact]
    public void DefaultedFunctionMemberCall_ResolvesThroughTypeInfoDeclaredMembers()
    {
        AssertNoErrors(@"
            class Greeter {
                func Join(left: string, right: string = ""world""): string {
                    return left + right
                }
            }

            func Main() {
                greeter := new Greeter()
                message := greeter.Join(left: ""hello "")
            }
        ");
    }

    [Fact]
    public void ParamsFunctionMemberCall_ResolvesThroughTypeInfoDeclaredMembers()
    {
        AssertNoErrors(@"
            class Accumulator {
                func Sum(params values: int[]): int {
                    return 0
                }
            }

            func Main() {
                accumulator := new Accumulator()
                none := accumulator.Sum()
                expanded := accumulator.Sum(1, 2, 3)
                direct := accumulator.Sum([1, 2, 3])
            }
        ");
    }

    [Fact]
    public void OverloadedFunctionMemberCall_ResolvesThroughTypeInfoDeclaredMembers()
    {
        AssertNoErrors(@"
            class Formatter {
                func Format(value: int): string {
                    return ""int""
                }

                func Format(value: string): string {
                    return value
                }
            }

            func Main() {
                formatter := new Formatter()
                number := formatter.Format(1)
                text := formatter.Format(""one"")
            }
        ");
    }

    [Fact]
    public void GenericFunctionMemberCall_ResolvesThroughTypeInfoDeclaredMembers()
    {
        AssertNoErrors(@"
            class Box {
                func Identity<T>(value: T): T {
                    return value
                }

                func RequireClass<T>(value: T): T where T : class {
                    return value
                }
            }

            func Main() {
                box := new Box()
                number: int = box.Identity(1)
                text: string = box.Identity<string>(""one"")
                constrained: string = box.RequireClass(""value"")
            }
        ");
    }

    [Fact]
    public void BCL_MethodCall_WithNamedOptionalAndParamsArguments_NoErrors()
    {
        var result = AnalyzeWithSource(@"
            import System
            import System.Collections.Generic
            import System.Text.Json

            class Payload {
                Name: string
            }

            func Main() {
                payload := JsonSerializer.Deserialize<Payload>(json: ""{}"")
                names := new List<string>()
                names.Add(""alpha"")
                names.Add(""beta"")
                joined := String.Join(separator: "","", values: names)
                formatted := String.Format(format: ""{0}-{1}"", arg0: ""left"", arg1: ""right"")
            }
        ");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdas_InferReturnType()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [1, 2, 3]
                query := source.AsQueryable()
                filtered := query.Where(x => x > 1).Select(x => x.ToString())
            }
        ");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");

        var queryType = result.SemanticModel.LookupIdentifier("query");
        Assert.Equal("IQueryable<int>", queryType?.ToString());

        var filteredType = result.SemanticModel.LookupIdentifier("filtered");
        Assert.Equal("IQueryable<string>", filteredType?.ToString());
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaUnaryNegation_IsSupported()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [1, 2, 3]
                query := source.AsQueryable()
                filtered := query.Where(x => -x < -1)
            }
        ");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaHardCast_IsSupported()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [1, 2, 3]
                query := source.AsQueryable()
                filtered := query.Where(x => (double)x > 1.5)
            }
        ");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaSafeCast_IsSupported()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [""a"", ""b""]
                query := source.AsQueryable()
                filtered := query.Where(x => (x as object) != null)
            }
        ");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaBitwiseOperators_AreSupported()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [1, 2, 3]
                query := source.AsQueryable()
                filtered := query.Where(x => ((x & 1) == 1) || ((x | 1) == 3) || ((x ^ 3) == 0))
            }
        ");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaShiftOperators_AreSupported()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [1, 2, 3]
                query := source.AsQueryable()
                filtered := query.Where(x => ((x << 1) == 2) || ((x >> 1) == 1))
            }
        ");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaStaticMethodCall_IsSupported()
    {
        var result = AnalyzeWithSource(@"
            import System
            import System.Linq

            func Main() {
                source := [""a"", """", ""bb""]
                query := source.AsQueryable()
                filtered := query.Where(x => !String.IsNullOrEmpty(x))
            }
        ");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaConditional_IsSupported()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [1, 2, 3]
                query := source.AsQueryable()
                mapped := query.Select(x => x > 1 ? x : 0L)
            }
        ");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");

        var mappedType = result.SemanticModel.LookupIdentifier("mapped");
        Assert.Equal("IQueryable<long>", mappedType?.ToString());
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaDefault_IsSupported()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [1, 2, 3]
                query := source.AsQueryable()
                mapped: IQueryable<long> = Queryable.Select<int, long>(query, x => default)
            }
        ");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaMetadataConstants_AreSupported()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [1, 2, 3]
                query := source.AsQueryable()
                names := query.Select(x => nameof(x))
                typeNames := query.Select(x => typeof(int).Name)
            }
        ");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");

        Assert.Equal("IQueryable<string>", result.SemanticModel.LookupIdentifier("names")?.ToString());
        Assert.Equal("IQueryable<string>", result.SemanticModel.LookupIdentifier("typeNames")?.ToString());
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaIndexAccess_IsSupported()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [""ab"", ""cd""]
                query := source.AsQueryable()
                chars := query.Select(x => x[0])
            }
        ");

        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");

        Assert.Equal("IQueryable<char>", result.SemanticModel.LookupIdentifier("chars")?.ToString());
    }

    // ===================================================================
    // Type System Hardening Tests
    // ===================================================================

    [Fact]
    public void ReflectionGenericReceiver_ToArrayPreservesNonNullableElementType()
    {
        var result = Analyze(@"
            import System.Collections.Generic

            func Accept(tags: string[]): void {
            }

            func Main() {
                tags := new List<string>()
                array := tags.ToArray()
                Accept(array)
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.Equal("string[]", result.SemanticModel.LookupIdentifier("array")?.ToString());
    }

    [Fact]
    public void ReflectionGenericReceiver_ToArrayPreservesNullableElementType()
    {
        var result = Analyze(@"
            import System.Collections.Generic

            func Main() {
                tags := new List<string?>()
                array := tags.ToArray()
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.Equal("string?[]", result.SemanticModel.LookupIdentifier("array")?.ToString());
    }

    [Fact]
    public void ReflectionGenericReceiver_UsesBoundTypeParameterAssignabilityForArguments()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                values := new List<object>()
                values.Add(42)
                values.Add(""hello"")
            }
        ");
    }

    // ════════════════════════════════════════════════════════════════════
    //  Compiler audit regression tests
    // ════════════════════════════════════════════════════════════════════

    [Fact]
    public void NullAssignableToString()
    {
        // null should be assignable to string (reference type)
        AssertNoErrors(@"
            func Main() {
                name: string = null
            }
        ");
    }

    [Fact]
    public void NullAssignableToNullableInt()
    {
        // null should be assignable to int? (nullable value type)
        AssertNoErrors(@"
            func Main() {
                x: int? = null
            }
        ");
    }

    [Fact]
    public void NullAssignableToClassType()
    {
        // null should be assignable to a class type
        AssertNoErrors(@"
            class Person
                Name: string

            func Main() {
                p: Person = null
            }
        ");
    }

    [Fact]
    public void GenericTypeParameter_VisibleInFunctionBody()
    {
        // Generic type parameters should be usable as types inside function body
        AssertNoErrors(@"
            func Identity<T>(value: T): T {
                return value
            }
        ");
    }

    [Fact]
    public void GenericTypeParameter_VisibleInClassBody()
    {
        // Generic type parameters should be usable inside class members
        AssertNoErrors(@"
            class Container<T> {
                Value: T
            }
        ");
    }

    [Fact]
    public void RecursiveTypeDefinition()
    {
        // Recursive type: Node references itself
        AssertNoErrors(@"
            class Node {
                Value: int
                Next: Node?
            }
        ");
    }

    [Fact]
    public void MutualRecursion_Functions()
    {
        // Mutual recursion between functions
        AssertNoErrors(@"
            func IsEven(n: int): bool {
                if n == 0 { return true }
                return IsOdd(n - 1)
            }
            func IsOdd(n: int): bool {
                if n == 0 { return false }
                return IsEven(n - 1)
            }
        ");
    }

    [Fact]
    public void DefiniteAssignment_IfElse_BothBranchesAssign()
    {
        // Both branches assign — should satisfy definite assignment
        AssertNoErrors(@"
            class Foo {
                Name: string

                constructor() {
                    if true {
                        this.Name = ""hello""
                    } else {
                        this.Name = ""world""
                    }
                }
            }
        ");
    }

    [Fact]
    public void DefiniteAssignment_NestedBlock()
    {
        // Assignment inside a nested block should be detected
        AssertNoErrors(@"
            class Foo {
                Name: string

                constructor() {
                    {
                        this.Name = ""hello""
                    }
                }
            }
        ");
    }

    // ===== Newtype Tests =====

    [Fact]
    public void Newtype_ConstructionWithCorrectType_NoError()
    {
        AssertNoErrors(@"
            type UserId = newtype int

            func Main() {
                id := UserId(42)
            }
        ");
    }

    [Fact]
    public void Newtype_ValueAccess_ReturnsUnderlyingType()
    {
        AssertNoErrors(@"
            type UserId = newtype int

            func Main() {
                id := UserId(42)
                let raw: int = id.Value
            }
        ");
    }

    [Fact]
    public void Newtype_SameNewtypeAssignable()
    {
        AssertNoErrors(@"
            type UserId = newtype int

            func Main() {
                id1 := UserId(1)
                let id2: UserId = id1
            }
        ");
    }

    // ── Bug regression tests ────────────────────────────────────────────

    [Fact]
    public void IntParse_NoUndefinedVariableError()
    {
        // Bug 001: int.Parse() should resolve int as System.Int32, not "Variable 'int' not found"
        AssertNoErrors(@"
func Main() {
    x := int.Parse(""42"")
}
        ");
    }

    [Fact]
    public void StringIsNullOrEmpty_NoUndefinedVariableError()
    {
        // Same fix as int.Parse — all built-in type keywords should support static method access
        AssertNoErrors(@"
func Main() {
    result := string.IsNullOrEmpty(""hello"")
}
        ");
    }

    [Fact]
    public void IntTryParse_WithExistingOutVariable_NoErrors()
    {
        AssertNoErrors(@"
func Main() {
    result := 0
    if int.TryParse(""123"", out result) {
        print result
    }
}
        ");
    }

    [Fact]
    public void OverloadResolution_MultipleArities_SelectsCorrectOverload()
    {
        // Bug 074: 3-arg call should resolve to 3-arg overload, not error
        AssertNoErrors(@"
class Formatter {
    static func Format(a: string): string {
        return a
    }
    static func Format(a: string, b: string): string {
        return a
    }
    static func Format(a: string, b: string, c: string): string {
        return a
    }
}

func Main() {
    Formatter.Format(""a"")
    Formatter.Format(""a"", ""b"")
    Formatter.Format(""a"", ""b"", ""c"")
}
        ");
    }

    [Fact]
    public void OverloadResolution_TopLevelFunctions_MultipleArities()
    {
        // Bug 074: top-level function overloads with different arities
        AssertNoErrors(@"
func Helper(a: int): int {
    return a
}

func Helper(a: int, b: int): int {
    return a + b
}

func Helper(a: int, b: int, c: int): int {
    return a + b + c
}

func Main() {
    Helper(1)
    Helper(1, 2)
    Helper(1, 2, 3)
}
        ");
    }

    [Fact]
    public void ParameterAttributes_DoNotAffectSemanticAnalysis()
    {
        AssertNoErrors(@"
func Identity([CLSCompliant(true)] value: int): int {
    return value
}

func Main() {
    result := Identity(42)
}
        ");
    }

    [Fact]
    public void AttributeArguments_SupportedConstantShapes_AreValid()
    {
        AssertNoErrors("""
            import System

            [System.AttributeUsage(System.AttributeTargets.Class | System.AttributeTargets.Struct)]
            class MarkerAttribute: Attribute {
            }

            [System.Obsolete(nameof(Marked))]
            class Marked {
            }
            """);
    }

    [Fact]
    public void AttributeArguments_SystemsPolicyAttributes_AcceptSymbolicArguments()
    {
        AssertNoErrors("""
            [memory(safe)]
            [allow(trap, owner: "runtime-core", reason: "bounds checked")]
            [trusted(reason: "bounds checked", owner: "runtime-core", review: "SYS-25")]
            [hot]
            func Copy(): int {
                return 0
            }
            """);
    }

    [Fact]
    public void TableDrivenTestCases_SupportedInlineDataConstants_AreValid()
    {
        AssertNoErrors("""
            test "constants" with (a: int, b: int, ratio: double, ch: char, text: string, flag: bool, value: object) [
                (1, -2, (-1.5), 'x', "ok", true, null),
                (-2147483648, 2147483647, -1.5, 'm', "min", false, null)
            ] {
            }
            """);
    }

    [Fact]
    public void AnonymousUnion_AllowsEitherArmAndCommonTargetAssignment()
    {
        AssertNoErrors(@"
func Accept(value: int | string): object {
    return value
}

func Main() {
    a := Accept(42)
    b := Accept(""hello"")
}
        ");
    }

    [Fact]
    public void AnonymousUnion_AllowsUnionToUnionWhenEverySourceArmFitsTargetArm()
    {
        AssertNoErrors(@"
func Identity(value: int | string): int | string {
    return value
}
        ");
    }

    [Fact]
    public void AnonymousUnion_NarrowsElseBranchAfterIsCheck()
    {
        AssertNoErrors(@"
func Describe(value: int | string): int {
    if value is string text {
        return text.Length
    }

    return value + 1
}
        ");
    }

    [Fact]
    public void AnonymousUnion_MatchIsExhaustiveWhenEveryArmIsCovered()
    {
        AssertNoErrors(@"
func Describe(value: int | string): int {
    return match value {
        int number => number,
        string text => text.Length
    }
}
        ");
    }

    [Fact]
    public void ParserErrorPlaceholder_InArrayLength_SuppressesConditionTypeFollowOn()
    {
        var condition = new NewExpression(
            new ArrayTypeReference(new SimpleTypeReference("int")),
            new List<Argument>(),
            Initializer: null,
            Line: 2,
            Column: 8,
            ArrayLengthExpression: new IdentifierExpression("<error>", 2, 16));
        var unit = new CompilationUnit(
            Namespace: null,
            Imports: new List<ImportDirective>(),
            FileImports: new List<Statement>(),
            Package: null,
            Declarations: new List<Declaration>
            {
                new FunctionDeclaration(
                    "Main",
                    new List<Parameter>(),
                    ReturnType: null,
                    Body: new BlockStatement(
                        new List<Statement>
                        {
                            new IfStatement(
                                condition,
                                new BlockStatement(new List<Statement>(), 2, 24),
                                ElseStatement: null,
                                Line: 2,
                                Column: 5)
                        },
                        1,
                        13),
                    ExpressionBody: null,
                    TypeParameters: null,
                    Constraints: null,
                    Modifiers.None,
                    new List<AttributeNode>(),
                    IsOperatorOverload: false,
                    OperatorSymbol: null,
                    IsConversionOperator: false,
                    IsImplicitConversion: false,
                    Line: 1,
                    Column: 1)
            },
            Line: 1,
            Column: 1);

        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        var result = analyzer.Analyze(unit);

        Assert.DoesNotContain(result.Errors, e =>
            e.Code == ErrorCode.TypeMismatch &&
            e.Message.Contains("condition", StringComparison.OrdinalIgnoreCase) &&
            e.Message.Contains("boolean", StringComparison.OrdinalIgnoreCase));
    }

    // ── stackalloc length: full semantic analysis (NL301/NL202) ────────────

    [Fact]
    public void StackAlloc_LengthExpression_RecordedInSemanticModel()
    {
        // Tooling (hover, go-to-definition) needs the length subtree in the semantic model.
        var result = Analyze(@"
func Scratch(count: int): int {
    scratch := stackalloc byte[count]
    return scratch.Length
}");
        Assert.True(
            result.SemanticModel.ExpressionTypes.TryGetValue((3, 32), out var lengthType),
            "Expected the stackalloc length identifier's type to be recorded in the semantic model");
        Assert.Equal("int", lengthType!.ToString());
    }

    [Fact]
    public void GenericTypeParameters_AreNotReportedAsUnresolved()
    {
        AssertNoErrors("func Map<T>(x: T): T {\n    return x\n}\n");
        AssertNoErrors("class Box<T> {\n    Value: T\n}\n");
        // Local functions register their type parameters too (fixed alongside this check).
        AssertNoErrors("func Main() {\n    func inner<T>(x: T): T {\n        return x\n    }\n    y := inner(1)\n}\n");
    }

    [Fact]
    public void CompilerKnownAndImportedTypes_AreNotReportedAsUnresolved()
    {
        // Result<T,E> is compiler-known without imports; StringBuilder resolves via import;
        // duck interfaces and same-file forward references resolve through declarations.
        AssertNoErrors("func make(ok: bool): Result<int, string> {\n    if ok {\n        return Ok(42)\n    }\n    return Err(\"nope\")\n}\n");
        AssertNoErrors("import System.Text\nfunc Main() {\n    sb := new StringBuilder()\n}\n");
        AssertNoErrors("func Use(r: IReader): string {\n    return r.Read()\n}\nduck interface IReader {\n    func Read(): string\n}\n");
    }

    [Fact]
    public void UnionCaseInstantiation_IsNotReportedAsUnresolved()
    {
        AssertNoErrors("union Shape {\n    Circle { radius: double }\n}\nfunc MakeCircle(): Shape {\n    return new Shape.Circle { radius: 1.0 }\n}\n");
    }

    [Fact]
    public void MemberAccess_ThroughByRefStructReceiver_ResolvesFields()
    {
        AssertNoErrors(@"
struct Entry {
    Key: int
    Used: bool
}

struct FixedMap {
    entries: Entry[]
}

func Contains(map: &FixedMap, key: int): bool {
    for i := 0; i < map.entries.Length; i++ {
        if !map.entries[i].Used || map.entries[i].Key == key {
            return true
        }
    }
    return false
}
");
    }
}
