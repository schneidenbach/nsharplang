using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Linq;
using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Tests;

#nullable disable
public static class CSharpObliviousInteropProbe
{
    public static string Identity(string value) => value;
}
#nullable restore

public static class CSharpNullabilityInteropProbe
{
    public static string NonNull(string value) => value;
    public static string? Maybe(string? value) => value;
    public static List<string?> MaybeList() => new();

    [return: MaybeNull]
    public static string MaybeNullReturn() => null;

    [return: NotNull]
    public static string? NotNullReturn() => "";

    public static bool TryGet([NotNullWhen(true)] out string? value)
    {
        value = "ok";
        return true;
    }
}

public class CSharpInheritedStaticFieldBase
{
    public static int Value;
}

public class CSharpInheritedStaticFieldDerived : CSharpInheritedStaticFieldBase
{
}

public class CSharpStaticPropertyShadowsInheritedField : CSharpInheritedStaticFieldBase
{
    public new static int Value => 0;
}

public class CSharpInheritedInstanceFieldBase
{
    public int Value;
}

public class CSharpInheritedInstanceFieldDerived : CSharpInheritedInstanceFieldBase
{
}

public class CSharpInstancePropertyShadowsInheritedField : CSharpInheritedInstanceFieldBase
{
    public new int Value => 0;
}

public class CSharpReadonlyInstanceFieldBase
{
    public readonly int Value = 1;
}

public class CSharpMutableInstanceFieldShadowsReadonlyBase : CSharpReadonlyInstanceFieldBase
{
    public new int Value;
}

public class CSharpReadonlyStaticFieldBase
{
    public static readonly int Value = 1;
}

public class CSharpMutableStaticFieldShadowsReadonlyBase : CSharpReadonlyStaticFieldBase
{
    public new static int Value;
}

public class AnalyzerTests
{
    // Project config for ASP.NET Core tests
    private static readonly ProjectConfig AspNetCoreConfig = new()
    {
        Sdk = "Microsoft.NET.Sdk.Web",
        TargetFramework = "net10.0",
        // For tests, we'll rely on the Sdk="Web" to trigger loading ASP.NET assemblies
        // The LoadFromProjectConfig method will load these automatically
    };

    private AnalysisResult Analyze(string source, ProjectConfig? config = null)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var result = parser.ParseCompilationUnit();
        var analyzer = new Analyzer();

        // Load system assemblies
        analyzer.LoadSystemAssemblies();

        // Load from project config if provided
        analyzer.LoadFromProjectConfig(config);

        return analyzer.Analyze(result.CompilationUnit!);
    }

    private void AssertNoErrors(string source, ProjectConfig? config = null)
    {
        var result = Analyze(source, config);
        Assert.False(result.HasErrors,
            result.Errors.Count > 0
                ? $"Expected no errors but got: {string.Join(", ", result.Errors.Select(e => e.Message))}"
                : "");
    }

    private void AssertHasError(string source, string expectedMessage)
    {
        var result = Analyze(source);
        Assert.True(result.HasErrors, "Expected errors but got none");
        Assert.Contains(result.Errors, e => e.Message.Contains(expectedMessage));
    }

    [Fact]
    public void UserDefinedOk_IsNotHijackedByResultFactory()
    {
        // C1: a user-declared `Ok`/`Err` must bind to the user's function even in a Result-typed
        // position, instead of being string-matched as the compiler-known Result factory. The
        // two-argument user `Ok` here would trigger a bogus "needs exactly 1 argument" error if
        // the factory hijacked the call.
        AssertNoErrors(@"
func Ok(a: int, b: int): Result<int, string> {
    return Err(""boom"")
}

func make(): Result<int, string> {
    return Ok(1, 2)
}
");
    }

    [Fact]
    public void GenuineOkErr_StillRecognizedAsResultFactory()
    {
        // C1 must not break the real factory: with no user-defined Ok/Err in scope, Ok/Err in a
        // Result-typed position are the compiler-known factory.
        AssertNoErrors(@"
func make(ok: bool): Result<int, string> {
    if ok {
        return Ok(42)
    }
    return Err(""nope"")
}
");
    }

    [Fact]
    public void InstanceMemberResolution_PrefersMemberNamedPathOverImportedType()
    {
        AssertNoErrors(@"
import System.IO

class HttpUrl {
    Path: string = ""/api/items""

    func ToDisplayString(): string {
        pathLength := Path.Length
        return $""{Path}:{pathLength}""
    }
}");
    }

    [Fact]
    public void ReflectionOverloadResolution_BindsDictionaryRemoveOverloads()
    {
        AssertNoErrors(@"
import System.Collections.Generic

func removeKey(): bool {
    headers := new Dictionary<string, string>()
    headers[""Accept""] = ""application/json""
    return headers.Remove(""Accept"")
}

func removeKeyAndValue(): string {
    headers := new Dictionary<string, string>()
    headers[""Accept""] = ""application/json""

    removedValue := """"
    if headers.Remove(""Accept"", out removedValue) {
        return removedValue
    }

    return ""missing""
}");
    }

    [Fact]
    public void ExplicitVarTypeAnnotation_IsRejected()
    {
        AssertHasError(@"
func main(): int {
    let value: var = 42
    return value
}", "'var' is not a type");
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

    private void AssertHasParseError(string source, string expectedMessage)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl", source);
        var result = parser.ParseCompilationUnit();
        Assert.False(result.Success, "Expected parse error but got none");
        Assert.Contains(result.Errors, e => e.Message.Contains(expectedMessage));
    }

    [Fact]
    public void CharLiteral_HasCharType()
    {
        AssertNoErrors(@"
            func Delimiter(): char {
                return '|'
            }
        ");
    }

    [Fact]
    public void TryCatch_AllBranchesReturn_SatisfiesReturnAnalysis()
    {
        AssertNoErrors(@"
            import System

            func ParseId(s: string): int {
                try {
                    return Int32.Parse(s)
                } catch ex: FormatException {
                    return -1
                }
            }
        ");
    }

    [Theory]
    [InlineData("throw 1", "int")]
    [InlineData("throw \"bad\"", "string")]
    [InlineData("value: object = \"bad\"\n                throw value", "object")]
    public void ThrowStatement_NonExceptionOperand_ReportsTypeMismatch(string statement, string operandType)
    {
        var result = AnalyzeWithSource($$"""
            func Main() {
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("Throw expressions must be assignable to System.Exception", error.Message);
        Assert.Contains($"'{operandType}'", error.Message);
        Assert.Contains("Exception-derived", error.Suggestion);
    }

    [Fact]
    public void ThrowStatement_ExceptionOperands_AreValid()
    {
        AssertNoErrors("""
            import System

            class DomainFailure : Exception {
            }

            func ThrowRuntime() {
                throw new InvalidOperationException("boom")
            }

            func ThrowCustom() {
                throw new DomainFailure()
            }

            func ThrowNull() {
                throw null
            }
            """);
    }

    /// <summary>
    /// Analyze source code with full source context so the rich error path (ErrorMessageBuilder) is taken,
    /// populating ContextualHint with conversion suggestions.
    /// </summary>
    private AnalysisResult AnalyzeWithSource(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var result = parser.ParseCompilationUnit();
        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        return analyzer.Analyze(result.CompilationUnit!, "test.nl", null, source);
    }

    /// <summary>
    /// Assert that at least one error has a ContextualHint containing the expected text.
    /// Use this to verify numeric narrowing cast suggestions.
    /// </summary>
    private void AssertHasHint(string source, string expectedHint)
    {
        var result = AnalyzeWithSource(source);
        Assert.True(result.HasErrors, "Expected errors but got none");
        Assert.Contains(result.Errors, e =>
            (e.ContextualHint != null && e.ContextualHint.Contains(expectedHint)));
    }

    [Fact]
    public void SimpleVariableDeclaration_TypeInference()
    {
        AssertNoErrors(@"
            func Main() {
                x := 42
            }
        ");
    }

    [Fact]
    public void VariableDeclaration_WithExplicitType()
    {
        AssertNoErrors(@"
            func Main() {
                let x: int = 42
            }
        ");
    }

    [Fact]
    public void VariableDeclaration_TypeMismatch()
    {
        AssertHasError(@"
            func Main() {
                let x: string = 42
            }
        ", "is typed as");
    }

    [Fact]
    public void ErrorTupleResultUseAfterNonReturningErrorBranch_IsRejected()
    {
        var result = Analyze(@"
            import System

            func Hi(): int {
                throw new Exception(""boom"")
            }

            func Main() {
                i, err := Hi()
                if err != null {
                    print err
                }

                print $""hi returned {i}""
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.UnverifiedErrorResult);
        Assert.Contains("'i'", error.Message);
        Assert.Contains("'err'", error.Message);
    }

    [Fact]
    public void ErrorTupleResultUseInsideErrorBranch_IsRejected()
    {
        var result = Analyze(@"
            import System

            func Hi(): int {
                throw new Exception(""boom"")
            }

            func Main() {
                i, err := Hi()
                if err != null {
                    print i
                }
            }
        ");

        Assert.Contains(result.Errors, e => e.Code == ErrorCode.UnverifiedErrorResult);
    }

    [Fact]
    public void ErrorTupleResultUseAfterReturningErrorBranch_IsAllowed()
    {
        AssertNoErrors(@"
            import System

            func Hi(): int {
                throw new Exception(""boom"")
            }

            func Main() {
                i, err := Hi()
                if err != null {
                    return
                }

                print i
            }
        ");
    }

    [Fact]
    public void ErrorTupleResultUseInsideNullErrorBranch_IsAllowed()
    {
        AssertNoErrors(@"
            import System

            func Hi(): int {
                return 42
            }

            func Main() {
                i, err := Hi()
                if err == null {
                    print i
                } else {
                    print err
                }
            }
        ");
    }

    [Fact]
    public void ErrorTupleResultUseAfterReturningElseBranch_IsAllowed()
    {
        AssertNoErrors(@"
            import System

            func Hi(): int {
                return 42
            }

            func Main() {
                i, err := Hi()
                if err == null {
                    print ""ok""
                } else {
                    return
                }

                print i
            }
        ");
    }

    [Fact]
    public void DiscardedMustUseFunctionResult_IsRejected()
    {
        var result = Analyze(@"
            [MustUse]
            func Compute(): int {
                return 42
            }

            func Main() {
                Compute()
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.DiscardedMustUseResult);
        Assert.Contains("'Compute'", error.Message);
        Assert.Contains("must be used", error.Message);
    }

    [Fact]
    public void DiscardedMustUseMethodResult_IsRejected()
    {
        var result = Analyze(@"
            class Calc {
                [MustUse]
                func Add(a: int, b: int): int {
                    return a + b
                }
            }

            func Main() {
                let c := new Calc()
                c.Add(1, 2)
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.DiscardedMustUseResult);
        Assert.Contains("'Add'", error.Message);
    }

    [Fact]
    public void DiscardedMustUseSelectedOverload_IsRejected()
    {
        var result = Analyze(@"
            [MustUse]
            func Compute(): int {
                return 42
            }

            func Compute(value: int): int {
                return value
            }

            func Main() {
                Compute()
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.DiscardedMustUseResult);
        Assert.Contains("'Compute'", error.Message);
    }

    [Fact]
    public void DiscardedNonMustUseSelectedOverload_IsAllowed()
    {
        AssertNoErrors(@"
            [MustUse]
            func Compute(value: int): int {
                return value
            }

            func Compute(): int {
                return 42
            }

            func Main() {
                Compute()
            }
        ");
    }

    [Fact]
    public void ExplicitDiscardOfMustUseResult_IsAllowed()
    {
        AssertNoErrors(@"
            [MustUse]
            func Compute(): int {
                return 42
            }

            func Main() {
                _ = Compute()
            }
        ");
    }

    [Fact]
    public void UsedMustUseResult_IsAllowed()
    {
        AssertNoErrors(@"
            [MustUse]
            func Compute(): int {
                return 42
            }

            func Main() {
                let x := Compute()
                print $""{x}""
            }
        ");
    }

    [Fact]
    public void DiscardedNonMustUseResult_IsAllowed()
    {
        AssertNoErrors(@"
            func Compute(): int {
                return 42
            }

            func Main() {
                Compute()
            }
        ");
    }

    [Fact]
    public void VoidCallStatement_IsAllowed()
    {
        AssertNoErrors(@"
            func SideEffect() {
                print ""hi""
            }

            func Main() {
                SideEffect()
            }
        ");
    }

    [Fact]
    public void ConstWithoutInitializer_Error()
    {
        AssertHasError(@"
            func Main() {
                const x: int
            }
        ", "must have an initial value");
    }

    [Fact]
    public void UndefinedVariable_Error()
    {
        AssertHasError(@"
            func Main() {
                x := y
            }
        ", "I can't find 'y'");
    }

    [Fact]
    public void UndefinedBareCall_ReportsFunctionError()
    {
        var result = Analyze(@"
            func Main() {
                i := Hi()
            }
        ");

        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.UndefinedFunction &&
            e.Message.Contains("Function 'Hi' not found"));
        Assert.DoesNotContain(result.Errors, e =>
            e.Code == ErrorCode.UndefinedVariable &&
            e.Message.Contains("Hi"));
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

        var lexer = new Lexer(source, "Program.nl");
        var parser = new Parser(lexer.Tokenize(), "Program.nl", source);
        var parseResult = parser.ParseCompilationUnit();
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
    public void FunctionDeclaration_Valid()
    {
        AssertNoErrors(@"
            func Add(x: int, y: int): int {
                return x + y
            }
        ");
    }

    [Fact]
    public void ReturnTypeMismatch_Error()
    {
        AssertHasError(@"
            func GetName(): string {
                return 42
            }
        ", "should return 'string'");
    }

    [Fact]
    public void VoidFunctionReturnValue_Error()
    {
        AssertHasError(@"
            func DoNothing() {
                return 42
            }
        ", "no return type annotation");
    }

    [Fact]
    public void ExplicitVoidFunctionReturnValue_Error()
    {
        AssertHasError(@"
            func DoNothing(): void {
                return 42
            }
        ", "declared to return 'void'");
    }

    [Theory]
    [InlineData("func* Numbers(): IEnumerable<int> { return 1 }")]
    [InlineData("async func* Numbers(): IAsyncEnumerable<int> { return 1 }")]
    public void GeneratorReturnValue_ReportsInvalidSyntax(string declaration)
    {
        var result = AnalyzeWithSource("import System.Collections.Generic\n\n" + declaration);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("Generator functions cannot return a value", error.Message);
        Assert.Contains("yield value", error.Suggestion);
    }

    [Theory]
    [InlineData("yield 1")]
    [InlineData("yield break")]
    public void YieldOutsideGenerator_ReportsInvalidSyntax(string statement)
    {
        var result = AnalyzeWithSource($$"""
            func Main() {
                {{statement}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("'yield' can only be used inside a generator function", error.Message);
        Assert.Contains("func*", error.Suggestion);
    }

    [Fact]
    public void GeneratorSequenceReturnTypes_AreValid()
    {
        AssertNoErrors("""
            import System.Collections.Generic

            func* Numbers(): IEnumerable<int> {
                yield 1
            }

            func* NumberList(): List<int> {
                yield 1
            }

            func* NumberReadOnlyList(): IReadOnlyList<int> {
                yield 1
            }

            async func* AsyncNumbers(): IAsyncEnumerable<int> {
                yield 1
            }
            """);
    }

    [Theory]
    [InlineData("func* Numbers(): int { yield 1 }", "int", "synchronous enumerable", "IEnumerable<T>")]
    [InlineData("func* Numbers(): int[] { yield 1 }", "int[]", "synchronous enumerable", "IEnumerable<T>")]
    [InlineData("func* Numbers(): IEnumerator<int> { yield 1 }", "IEnumerator", "synchronous enumerable", "IEnumerable<T>")]
    [InlineData("func* Numbers(): IAsyncEnumerable<int> { yield 1 }", "IAsyncEnumerable", "synchronous enumerable", "IEnumerable<T>")]
    [InlineData("async func* Numbers(): int { yield 1 }", "int", "async enumerable", "IAsyncEnumerable<T>")]
    [InlineData("async func* Numbers(): IEnumerable<int> { yield 1 }", "IEnumerable", "async enumerable", "IAsyncEnumerable<T>")]
    public void GeneratorNonSequenceReturnType_ReportsTypeMismatch(
        string declaration,
        string returnType,
        string expectedSequenceKind,
        string expectedSuggestion)
    {
        var result = AnalyzeWithSource("import System.Collections.Generic\n\n" + declaration);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains(expectedSequenceKind, error.Message);
        Assert.Contains(returnType, error.Message);
        Assert.Contains(expectedSuggestion, error.Suggestion);
    }

    [Theory]
    [InlineData("func* Numbers(): IEnumerable<string> { yield 1 }", "int", "string")]
    [InlineData("async func* Numbers(): IAsyncEnumerable<int> { yield \"bad\" }", "string", "int")]
    public void GeneratorYieldValueTypeMismatch_ReportsTypeMismatch(
        string declaration,
        string yieldedType,
        string elementType)
    {
        var result = AnalyzeWithSource("import System.Collections.Generic\n\n" + declaration);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains($"yield value is '{yieldedType}'", error.Message);
        Assert.Contains($"sequence element type is '{elementType}'", error.Message);
        Assert.Contains($"assignable to '{elementType}'", error.Suggestion);
    }

    [Fact]
    public void LocalGeneratorNonSequenceReturnType_ReportsTypeMismatch()
    {
        var result = AnalyzeWithSource("""
            func Main() {
                func* Numbers(): int {
                    yield 1
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("synchronous enumerable", error.Message);
        Assert.Contains("returns 'int'", error.Message);
        Assert.Contains("IEnumerable<T>", error.Suggestion);
    }

    [Theory]
    [InlineData("func* Numbers(): IEnumerable<int> => []")]
    [InlineData("async func* Numbers(): IAsyncEnumerable<int> => []")]
    public void GeneratorExpressionBody_ReportsInvalidSyntax(string declaration)
    {
        var result = AnalyzeWithSource("import System.Collections.Generic\n\n" + declaration);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("Generator functions must use a block body", error.Message);
        Assert.Contains("yield value", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
    }

    [Fact]
    public void LocalGeneratorExpressionBody_ReportsInvalidSyntax()
    {
        var result = AnalyzeWithSource("""
            import System.Collections.Generic

            func Main() {
                func* Numbers(): IEnumerable<int> => []
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("Generator functions must use a block body", error.Message);
        Assert.Contains("yield value", error.Suggestion);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ExpressionBodiedFunctionWithoutReturnType_ReturnValue_Error()
    {
        AssertHasError(@"
            func Answer() => 42
        ", "no return type annotation");
    }

    [Fact]
    public void IfConditionMustBeBoolean()
    {
        AssertHasError(@"
            func Main() {
                if 42 {

                }
            }
        ", "must be a boolean");
    }

    [Fact]
    public void WhileConditionMustBeBoolean()
    {
        AssertHasError(@"
            func Main() {
                while 42 {

                }
            }
        ", "must be a boolean");
    }

    [Fact]
    public void ForConditionMustBeBoolean()
    {
        AssertHasError(@"
            func Main() {
                for i := 0; ""test""; i++ {

                }
            }
        ", "must be a boolean");
    }

    [Fact]
    public void ForIteratorMustHaveStatementEffect()
    {
        var result = AnalyzeWithSource("""
            func Main() {
                for i := 0; i < 3; i + 1 {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidExpressionStatement);
        Assert.Contains("for-loop iterator has no effect", error.Message);
        Assert.Contains("for-loop iterators", error.ContextualHint);
    }

    [Fact]
    public void ForIteratorDiscardedMustUseCall_IsRejected()
    {
        var result = Analyze("""
            [MustUse]
            func Next(): int {
                return 1
            }

            func Main() {
                for i := 0; i < 3; Next() {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.DiscardedMustUseResult);
        Assert.Contains("'Next'", error.Message);
    }

    [Fact]
    public void BreakOutsideLoop_Error()
    {
        AssertHasError(@"
            func Main() {
                break
            }
        ", "can only be used inside a loop");
    }

    [Fact]
    public void ContinueOutsideLoop_Error()
    {
        AssertHasError(@"
            func Main() {
                continue
            }
        ", "can only be used inside a loop");
    }

    [Fact]
    public void BreakInsideLoop_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                while true {
                    break
                }
            }
        ");
    }

    [Fact]
    public void ExpressionStatement_BareMemberAccess_MethodGroupUsedAsValue()
    {
        var result = AnalyzeWithSource(@"
            func Main() {
                greeting := ""hello""
                greeting.CompareTo
            }
        ");

        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.MethodGroupUsedAsValue &&
            e.Message.Contains("CompareTo"));
    }

    [Fact]
    public void ExpressionStatement_NonSideEffectingValue_Error()
    {
        var result = AnalyzeWithSource(@"
            func Main() {
                value := 41
                value + 1
            }
        ");

        Assert.Contains(result.Errors, e => e.Code == ErrorCode.InvalidExpressionStatement);
    }

    [Fact]
    public void MethodGroupUsedAsPrintValue_Error()
    {
        var result = AnalyzeWithSource(@"
            func Main() {
                print ""hello"".ToString
            }
        ");

        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.MethodGroupUsedAsValue &&
            e.Message.Contains("ToString") &&
            e.ContextualHint?.Contains("delegate") == true);
    }

    [Fact]
    public void MethodGroupUsedAsInferredVariableValue_Error()
    {
        var result = AnalyzeWithSource(@"
            func Main() {
                value := ""hello"".ToString
            }
        ");

        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.MethodGroupUsedAsValue &&
            e.Message.Contains("ToString"));
    }

    [Fact]
    public void MethodGroupUsedAsExpressionStatement_Error()
    {
        var result = AnalyzeWithSource(@"
            func Main() {
                ""hello"".ToString
            }
        ");

        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.MethodGroupUsedAsValue &&
            e.Message.Contains("ToString"));
    }

    [Fact]
    public void MethodGroupUsedAsObjectArgument_Error()
    {
        var result = AnalyzeWithSource(@"
            func Use(value: object) {
                print value
            }

            func Main() {
                Use(""hello"".ToString)
            }
        ");

        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.MethodGroupUsedAsValue &&
            e.Message.Contains("ToString"));
    }

    [Fact]
    public void GenericListOfNSharpType_CountProperty_IsNotMethodGroup()
    {
        var result = AnalyzeWithSource(@"
            import System.Collections.Generic

            class TaskItem {
                Name: string
            }

            func Main() {
                tasks := new List<TaskItem>()
                total := tasks.Count
                print total
            }
        ");

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.MethodGroupUsedAsValue);
    }

    [Fact]
    public void ExpressionStatement_SideEffectingForms_NoErrors()
    {
        AssertNoErrors(@"
            class Worker {
            }

            func Touch(value: int) {
            }

            func Main() {
                value := 1
                value = 2
                value++
                Touch(value)
                new Worker()
            }
        ");
    }

    [Fact]
    public void Increment_NonIntegralOperand_Error()
    {
        var result = AnalyzeWithSource(@"
            func Main() {
                value := ""hello""
                value++
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'++' operator doesn't work with 'string'", error.Message);
        Assert.Contains("integral numeric value", error.Message);
    }

    [Fact]
    public void Increment_NonAssignableTarget_Error()
    {
        var result = AnalyzeWithSource(@"
            func Main() {
                1++
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("'++' operator needs an assignable target", error.Message);
        Assert.Contains("variable, field, property, or indexed element", error.Suggestion);
    }

    [Theory]
    [InlineData("text.Length = 2", "Length", "=")]
    [InlineData("text.Length += 1", "Length", "+=")]
    [InlineData("text.Length++", "Length", "++")]
    public void Write_ReadOnlyRuntimePropertyTarget_Error(string statement, string propertyName, string op)
    {
        var result = AnalyzeWithSource($$"""
            func Main() {
                text := "abc"
                {{statement}}
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"Property '{propertyName}' is read-only", error.Message);
        Assert.Contains($"'{op}'", error.Message);
        Assert.Contains("settable property", error.Suggestion);
    }

    [Theory]
    [InlineData("other.Value = 2", "Value", "=")]
    [InlineData("other.Value++", "Value", "++")]
    [InlineData("Value = 2", "Value", "=")]
    public void Write_ReadOnlySourcePropertyTarget_Error(string statement, string propertyName, string op)
    {
        var result = AnalyzeWithSource($$"""
            class Box {
                backing: int

                Value: int {
                    get {
                        return backing
                    }
                }

                constructor() {
                    backing = 0
                }

                func Mutate(other: Box) {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"Property '{propertyName}' is read-only", error.Message);
        Assert.Contains($"'{op}'", error.Message);
        Assert.Contains("settable property", error.Suggestion);
    }

    [Fact]
    public void Write_SettableSourcePropertyTarget_Valid()
    {
        AssertNoErrors("""
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
    }

    [Fact]
    public void Write_SettableRuntimePropertyTarget_Valid()
    {
        AssertNoErrors("""
            import System.Collections.Generic

            func Main(items: List<int>) {
                items.Capacity = 4
                items.Capacity += 1
                items.Capacity++
            }
        """);
    }

    [Fact]
    public void Write_ReadOnlyExternalPropertyTarget_Error()
    {
        var result = AnalyzeWithInteropProbe("""
            import NSharpLang.Tests

            func Main(probe: CSharpInstancePropertyShadowsInheritedField) {
                probe.Value = 2
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("Property 'Value' is read-only", error.Message);
        Assert.Contains("'='", error.Message);
        Assert.Contains("settable property", error.Suggestion);
    }

    [Theory]
    [InlineData("(1 + 2) = 3", "=")]
    [InlineData("checked(value) = 2", "=")]
    [InlineData("unchecked(value) += 2", "+=")]
    public void Assignment_NonAssignableTarget_Error(string statement, string op)
    {
        var result = AnalyzeWithSource($$"""
            func Main() {
                value := 1
                {{statement}}
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"'{op}' assignment needs an assignable target", error.Message);
        Assert.Contains("variable, field, property, indexed element", error.Suggestion);
    }

    [Theory]
    [InlineData("box?.Value = 1", "member access", "assigned with '='")]
    [InlineData("box?.Next.Value = 1", "member access", "assigned with '='")]
    [InlineData("box?.Value += 1", "member access", "assigned with '+='")]
    [InlineData("box?.Value++", "member access", "changed with '++'")]
    [InlineData("box?.Next.Value++", "member access", "changed with '++'")]
    [InlineData("items?[0] = 1", "index access", "assigned with '='")]
    [InlineData("matrix?[0][1] = 1", "index access", "assigned with '='")]
    [InlineData("items?[0]++", "index access", "changed with '++'")]
    [InlineData("bump(ref box?.Value)", "member access", "used as the ref argument")]
    [InlineData("bump(ref box?.Next.Value)", "member access", "used as the ref argument")]
    [InlineData("bump(ref items?[0])", "index access", "used as the ref argument")]
    [InlineData("reset(out box?.Value)", "member access", "used as the out argument")]
    public void Write_NullConditionalTarget_Error(string statement, string targetKind, string action)
    {
        var result = AnalyzeWithSource($$"""
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
            }

            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            func Main(box: Box?, items: int[]?, matrix: int[][]?) {
                {{statement}}
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"Null-conditional {targetKind} can't be {action}", error.Message);
        Assert.Contains("guard it for null", error.Suggestion);
    }

    [Theory]
    [InlineData("update(ref checked(value), out copy)", "ref")]
    [InlineData("update(ref value, out unchecked(copy))", "out")]
    public void RefOutArgument_NonAssignableTarget_Error(string statement, string modifier)
    {
        var result = AnalyzeWithSource($$"""
            func update(ref value: int, out copy: int) {
                copy = value
                value += 1
            }

            func Main() {
                value := 1
                copy := 0
                {{statement}}
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"'{modifier}' argument needs an assignable target", error.Message);
        Assert.Contains($"as the {modifier} argument", error.Suggestion);
    }

    [Theory]
    [InlineData("if Int32.TryParse(\"42\", out checked(result)) { }", "out")]
    [InlineData("Int32.TryParse(\"42\", out text.Length)", "out")]
    [InlineData("update(ref items[0])", "ref")]
    public void RefOutArgument_NonAddressableClrTargets_Error(string statement, string modifier)
    {
        var result = AnalyzeWithSource($$"""
            import System
            import System.Collections.Generic

            func update(ref value: int) {
                value += 1
            }

            func Main() {
                result := 0
                text := "abc"
                items := new List<int>()
                {{statement}}
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"'{modifier}' argument needs an assignable target", error.Message);
        Assert.Contains($"as the {modifier} argument", error.Suggestion);
    }

    [Fact]
    public void RefOutArgument_ArrayRangeSlice_Error()
    {
        var result = AnalyzeWithSource("""
            func update(ref values: int[]) {
            }

            func Main() {
                values := [1, 2, 3]
                update(ref values[0..1])
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("Array slices cannot be used as the ref argument", error.Message);
        Assert.Contains("Assign individual elements", error.Suggestion);
    }

    [Fact]
    public void RefOutArgument_ArrayFromEndElement_IsAddressable()
    {
        AssertNoErrors("""
            func update(ref value: int) {
                value += 1
            }

            func Main() {
                values := [1, 2, 3]
                update(ref values[^1])
            }
        """);
    }

    [Fact]
    public void ClassDeclaration_Valid()
    {
        AssertNoErrors(@"
            class Person {
                Name: string
                Age: int
            }
        ");
    }

    [Fact]
    public void DuplicateSymbol_Error()
    {
        AssertHasError(@"
            func Main() {
                x := 1
                x := 2
            }
        ", "already declared");
    }

    [Fact]
    public void ScopeNesting_NestedRedeclarationShadowsOuter_IsError()
    {
        // N# forbids shadowing: a nested block re-declaring an outer local is an
        // error (NL316), not the silently-permitted re-binding of older languages.
        AssertHasErrorCode(@"
            func Main() {
                x := 1
                {
                    x := 2
                    print x
                }
            }
        ", ErrorCode.ShadowedDeclaration);
    }

    [Fact]
    public void ScopeNesting_NestedBlockWithDistinctName_IsValid()
    {
        AssertNoErrors(@"
            func Main() {
                x := 1
                {
                    y := 2
                    print y
                }
                print x
            }
        ");
    }

    [Fact]
    public void BinaryArithmetic_IntOperands()
    {
        AssertNoErrors(@"
            func Main() {
                x := 1 + 2
                y := 3 * 4
                z := 5 - 6
            }
        ");
    }

    [Fact]
    public void BinaryArithmetic_BytePlusByte_ProducesInt()
    {
        // C# binary numeric promotion: byte + byte = int
        // getA/getB return byte, so a+b should be int, not assignable back to byte
        AssertHasError(@"
            func getA(): byte { return 0 as byte }
            func getB(): byte { return 0 as byte }
            func Main() {
                c: byte = getA() + getB()
            }
        ", "is typed as");
    }

    [Fact]
    public void BinaryArithmetic_ShortPlusShort_ProducesInt()
    {
        // C# binary numeric promotion: short + short = int
        AssertHasError(@"
            func getA(): short { return 0 as short }
            func getB(): short { return 0 as short }
            func Main() {
                c: short = getA() + getB()
            }
        ", "is typed as");
    }

    [Fact]
    public void BinaryArithmetic_SmallTypes_AssignableToInt()
    {
        // byte + byte = int, which should be assignable to int
        AssertNoErrors(@"
            func getA(): byte { return 0 as byte }
            func getB(): byte { return 0 as byte }
            func Main() {
                c: int = getA() + getB()
            }
        ");
    }

    [Fact]
    public void BinaryArithmetic_DecimalPlusDouble_Error()
    {
        // ECMA-334 §12.4.7: decimal cannot mix with float/double
        AssertHasError(@"
            func getD(): decimal { return 0 as decimal }
            func getF(): double { return 0.0 }
            func Main() {
                x := getD() + getF()
            }
        ", "doesn't work with");
    }

    [Fact]
    public void BinaryArithmetic_DecimalPlusFloat_Error()
    {
        AssertHasError(@"
            func getD(): decimal { return 0 as decimal }
            func getF(): float { return 0 as float }
            func Main() {
                x := getD() + getF()
            }
        ", "doesn't work with");
    }

    [Fact]
    public void BinaryArithmetic_UlongPlusInt_Error()
    {
        // ECMA-334 §12.4.7: ulong cannot mix with signed types
        AssertHasError(@"
            func getU(): ulong { return 0 as ulong }
            func getI(): int { return 0 }
            func Main() {
                x := getU() + getI()
            }
        ", "doesn't work with");
    }

    [Fact]
    public void BinaryArithmetic_DecimalPlusDecimal_Ok()
    {
        // decimal + decimal is valid
        AssertNoErrors(@"
            func getA(): decimal { return 0 as decimal }
            func getB(): decimal { return 0 as decimal }
            func Main() {
                x := getA() + getB()
            }
        ");
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
    public void LogicalNot_NonBoolOperand_Error()
    {
        var result = AnalyzeWithSource(@"
func bad(value: int): bool {
    return !value
}
");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'!' operator doesn't work with 'int'", error.Message);
        Assert.Contains("boolean value", error.Message);
    }

    [Fact]
    public void NegativeIntegerLiteral_TargetTypedSignedNarrowing_IsPreserved()
    {
        AssertNoErrors(@"
func Main() {
    a: sbyte = -128
    b: short = -32768
    c: int = -2147483648
}
");
    }

    [Fact]
    public void DecimalSuffixLiteral_AssignableToDecimal()
    {
        AssertNoErrors(@"
            func Main() {
                value: decimal = 0m
                other: decimal = 1.25m
            }
        ");
    }

    [Fact]
    public void BinaryArithmetic_InvalidOperands()
    {
        AssertHasError(@"
            func Main() {
                x := ""hello"" - ""world""
            }
        ", "doesn't work with");
    }

    [Fact]
    public void RelationalOperator_InvalidOperands_ReportTypeMismatch()
    {
        var result = AnalyzeWithSource(@"
func BadString(): bool {
    return ""a"" < ""b""
}

func BadObject(value: object): bool {
    return value > 0
}

func BadBool(left: bool, right: bool): bool {
    return left <= right
}

func BadNullable(value: int?): bool {
    return value >= 0
}

func BadMixed(left: ulong, right: long): bool {
    return left < right
}
");

        var errors = result.Errors.Where(e => e.Code == ErrorCode.TypeMismatch).ToList();
        Assert.Equal(5, errors.Count);
        Assert.Contains(errors, e => e.Message.Contains("'<' operator") && e.Message.Contains("'string' and 'string'"));
        Assert.Contains(errors, e => e.Message.Contains("'>' operator") && e.Message.Contains("'object' and 'int'"));
        Assert.Contains(errors, e => e.Message.Contains("'<=' operator") && e.Message.Contains("'bool' and 'bool'"));
        Assert.Contains(errors, e => e.Message.Contains("'>=' operator") && e.Message.Contains("'int?' and 'int'"));
        Assert.Contains(errors, e => e.Message.Contains("'<' operator") && e.Message.Contains("'ulong' and 'long'"));
    }

    [Fact]
    public void RelationalOperator_NumericAndOverloadedOperands_AreValid()
    {
        AssertNoErrors(@"
struct Version {
    Major: int

    static func operator <(left: Version, right: Version): bool {
        return left.Major < right.Major
    }
}

func ComparePrimitives(a: int, b: double, c: char, d: uint, e: long): bool {
    return a < b && c >= 0 && d <= e
}

func CompareDecimals(left: decimal, right: decimal): bool {
    return left > right
}

func CompareVersions(left: Version, right: Version): bool {
    return left < right
}
        ");
    }

    [Fact]
    public void RelationalOperator_ReflectedPrimitiveReturn_IsValid()
    {
        AssertNoErrors(@"
func CompareLower(left: string, right: string): bool {
    leftChar := Char.ToLowerInvariant(left[0])
    rightChar := Char.ToLowerInvariant(right[0])
    return leftChar < rightChar
}
        ");
    }

    [Fact]
    public void EqualityOperator_InvalidOperands_ReportTypeMismatch()
    {
        var result = AnalyzeWithSource(@"
struct Plain {
    Value: int
}

func BadObjectInt(value: object): bool {
    return value == 1
}

func BadPlain(left: Plain, right: Plain): bool {
    return left == right
}

func BadNullable(left: int?, right: int?): bool {
    return left != right
}

func BadMixedDecimal(left: decimal, right: int): bool {
    return left == right
}
");

        var errors = result.Errors.Where(e => e.Code == ErrorCode.TypeMismatch).ToList();
        Assert.Equal(4, errors.Count);
        Assert.Contains(errors, e => e.Message.Contains("'==' operator") && e.Message.Contains("'object' and 'int'"));
        Assert.Contains(errors, e => e.Message.Contains("'==' operator") && e.Message.Contains("'Plain' and 'Plain'"));
        Assert.Contains(errors, e => e.Message.Contains("'!=' operator") && e.Message.Contains("'int?' and 'int?'"));
        Assert.Contains(errors, e => e.Message.Contains("'==' operator") && e.Message.Contains("'decimal' and 'int'"));
    }

    [Fact]
    public void EqualityOperator_SupportedOperands_AreValid()
    {
        AssertNoErrors(@"
record struct Measurement(value: int) {
}

struct Key {
    Value: int

    static func operator ==(left: Key, right: Key): bool {
        return left.Value == right.Value
    }

    static func operator !=(left: Key, right: Key): bool {
        return left.Value != right.Value
    }
}

func ComparePrimitives(a: int, b: double, flag: bool, ch: char): bool {
    return a == b && flag != false && ch == 'x'
}

func CompareDecimals(left: decimal, right: decimal): bool {
    return left == right
}

func CompareReferences(text: string, other: object, values: int[]): bool {
    return text == ""x"" && text != other && values == null && null != other
}

func CompareValueToNull(value: int): bool {
    return value != null
}

func CompareRecordStructs(left: Measurement, right: Measurement): bool {
    return left == right
}

func CompareKeys(left: Key, right: Key): bool {
    return left == right && left != right
}

func CompareReflectedChars(left: string, right: string): bool {
    leftChar := Char.ToLowerInvariant(left[0])
    rightChar := Char.ToLowerInvariant(right[0])
    return leftChar == rightChar
}
        ");
    }

    [Fact]
    public void StringConcatenation_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                x := ""hello"" + "" "" + ""world""
            }
        ");
    }

    [Fact]
    public void LogicalOperators_RequireBoolean()
    {
        AssertHasError(@"
            func Main() {
                x := 1 && 2
            }
        ", "must be booleans");
    }

    [Fact]
    public void TernaryConditionMustBeBoolean()
    {
        AssertHasError(@"
            func Main() {
                x := 42 ? 1 : 2
            }
        ", "must be a boolean");
    }

    [Fact]
    public void ArrayLiteral_UniformTypes()
    {
        AssertNoErrors(@"
            func Main() {
                nums := [1, 2, 3, 4]
            }
        ");
    }

    [Fact]
    public void SizedArrayAllocation_WithConstructorArguments_ReportsSemanticDiagnostic()
    {
        var result = Analyze(@"
            func sideEffect(): int {
                return 1
            }

            func Main() {
                values := new int[4](sideEffect())
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSizedArrayConstructorArguments);
        Assert.Contains("Sized array allocation cannot also pass constructor arguments", error.Message);
        Assert.Contains("new T[n]", error.Suggestion ?? string.Empty);
    }

    [Fact]
    public void SizedArrayAllocation_WithConstructorArguments_StillAnalyzesArgumentExpressions()
    {
        var result = Analyze(@"
            func Main() {
                values := new int[4](missing)
            }
        ");

        Assert.Contains(result.Errors, e => e.Code == ErrorCode.InvalidSizedArrayConstructorArguments);
        Assert.Contains(result.Errors, e => e.Code == ErrorCode.UndefinedVariable && e.Message.Contains("missing"));
    }

    [Fact]
    public void ArrayRangeIndexAccess_ReturnsArrayType()
    {
        AssertNoErrors(@"
            func PrintArray(arr: int[]) {
            }

            func Main() {
                numbers := [1, 2, 3, 4, 5]
                firstTwo := numbers[..2]
                PrintArray(firstTwo)
            }
        ");
    }

    [Fact]
    public void RangeExpression_InvalidEndpointTypes_ReportTypeMismatch()
    {
        var result = AnalyzeWithSource(@"
func BadStart(values: int[]) {
    _ = values[""0""..2]
}

func BadEnd(values: int[]) {
    _ = values[0..""2""]
}

func BadFromEnd(values: int[]) {
    _ = values[0..^""2""]
}

func BadLong(values: int[], count: long) {
    _ = values[0..count]
}
");

        var errors = result.Errors.Where(e => e.Code == ErrorCode.TypeMismatch).ToList();
        Assert.Equal(4, errors.Count);
        Assert.Contains(errors, e => e.Message.Contains("Range bounds must be int or System.Index")
            && e.Message.Contains("'string'"));
        Assert.Contains(errors, e => e.Message.Contains("Range bounds must be int or System.Index")
            && e.Message.Contains("'long'"));
        Assert.Contains(errors, e => e.Message.Contains("'^' operator doesn't work with 'string'"));
    }

    [Fact]
    public void RangeExpression_IntCompatibleEndpoints_AreValid()
    {
        AssertNoErrors(@"
func Main(values: int[], start: byte, end: short, fromEnd: int) {
    first := values[start..end]
    middle := values[..^fromEnd]
    all := values[..]
}
        ");
    }

    [Fact]
    public void ArrayIndexAccess_WithStringIndex_ReportsTypeMismatch()
    {
        var result = Analyze("""
            func Main(): int {
                values := [1, 2, 3]
                return values["0"]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("Array indexes must be int, System.Index, or System.Range", error.Message);
        Assert.Contains("'string'", error.Message);
        Assert.Contains("^n", error.Suggestion);
    }

    [Fact]
    public void ArrayRangeIndexedAssignment_ReportsBeforeEmission()
    {
        var result = Analyze("""
            func Main() {
                values := [1, 2, 3]
                values[0..1] = [4]
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("Array slices cannot be assigned", error.Message);
        Assert.Contains("Assign individual elements", error.Suggestion);
    }

    [Fact]
    public void StringIndexedAssignment_ReportsImmutableString()
    {
        var result = Analyze("""
            func Main() {
                text := "hello"
                text[0] = 'H'
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("String characters and slices cannot be assigned", error.Message);
        Assert.Contains("strings are immutable", error.Suggestion);
    }

    [Fact]
    public void StringRangeIndexAccess_ReturnsStringType()
    {
        AssertNoErrors(@"
            func PrintString(value: string) {
            }

            func Main() {
                text := ""hello""
                firstTwo := text[..2]
                PrintString(firstTwo)
            }
        ");
    }

    [Fact]
    public void FunctionCall_Valid()
    {
        AssertNoErrors(@"
            func Add(x: int, y: int): int {
                return x + y
            }

            func Main() {
                result := Add(1, 2)
            }
        ");
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
    public void EnumDeclaration_Valid()
    {
        AssertNoErrors(@"
            enum Status {
                Pending,
                Active,
                Done
            }
        ");
    }

    [Fact]
    public void EnumMemberAccess_UnknownStaticMember_ReportsUndefinedMember()
    {
        var error = AssertHasErrorCode(@"
            enum Status {
                Pending,
                Active,
                Done
            }

            func Main(): Status {
                return Status.Activ
            }
        ", ErrorCode.UndefinedMember);

        Assert.Contains("Member 'Activ' not found on type 'Status'", error.Message);
        Assert.Contains("Active", error.Suggestion ?? string.Join(",", error.Suggestions ?? new List<string>()));
    }

    [Fact]
    public void EnumValueObjectMemberAccess_Resolves()
    {
        AssertNoErrorCode(@"
            enum Status {
                Pending,
                Active,
                Done
            }

            func Main(): string {
                status := Status.Active
                return status.ToString()
            }
        ", ErrorCode.UndefinedMember);
    }

    [Fact]
    public void EnumValueMemberAccess_EnumMemberName_ReportsUndefinedMember()
    {
        var error = AssertHasErrorCode(@"
            enum Status {
                Pending,
                Active,
                Done
            }

            func Main(): Status {
                status := Status.Active
                return status.Done
            }
        ", ErrorCode.UndefinedMember);

        Assert.Contains("Member 'Done' not found on type 'Status'", error.Message);
    }

    [Fact]
    public void EnumDeclaration_DuplicateMembers()
    {
        AssertHasError(@"
            enum Status {
                Pending,
                Pending
            }
        ", "is already defined");
    }

    [Fact]
    public void UnionDeclaration_Valid()
    {
        AssertNoErrors(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }
        ");
    }

    [Fact]
    public void UnionDeclaration_DuplicateCases()
    {
        AssertHasError(@"
            union Result {
                Success { value: int }
                Success { error: string }
            }
        ", "is already defined");
    }

    [Fact]
    public void GenericUnionDeclaration_TypeParameterResolvesInCaseProperties()
    {
        AssertNoErrors(@"
            union Result<T> {
                Success { value: T }
                Failure { error: string }
            }
        ");
    }

    [Fact]
    public void GenericUnionConstruction_WithExplicitTypeArguments_Valid()
    {
        AssertNoErrors(@"
            union Result<T> {
                Success { value: T }
                Failure { error: string }
            }

            func main(): int {
                r := new Result.Success<int> { value: 42 }
                return 0
            }
        ");
    }

    [Fact]
    public void GenericUnionConstruction_MissingTypeArguments_Error()
    {
        AssertHasError(@"
            union Result<T> {
                Success { value: T }
                Failure { error: string }
            }

            func main(): int {
                r := new Result.Success { value: 42 }
                return 0
            }
        ", "requires 1 type argument");
    }

    [Fact]
    public void GenericUnionConstruction_WrongArity_Error()
    {
        AssertHasError(@"
            union Result<T> {
                Success { value: T }
                Failure { error: string }
            }

            func main(): int {
                r := new Result.Success<int, string> { value: 42 }
                return 0
            }
        ", "takes 1 type argument(s), but 2 were provided");
    }

    [Fact]
    public void GenericUnionConstruction_TargetTyped_InfersFromReturnType()
    {
        AssertNoErrors(@"
            union Option<T> {
                Some { value: T }
                None { }
            }

            func find(): Option<string> {
                return new Option.None
            }
        ");
    }

    [Fact]
    public void GenericUnionAnnotation_WrongArity_Error()
    {
        AssertHasError(@"
            union Result<T> {
                Success { value: T }
                Failure { error: string }
            }

            func handle(r: Result<int, string>): int {
                return 0
            }
        ", "takes 1 type argument(s), but 2 were provided");
    }

    [Fact]
    public void GenericUnionMatch_NonExhaustive_Error()
    {
        AssertHasError(@"
            union Result<T> {
                Success { value: T }
                Failure { error: string }
            }

            func handle(r: Result<int>): int {
                return match r {
                    Result.Success { value } => value
                }
            }
        ", "doesn't cover");
    }

    [Fact]
    public void GenericUnionMatch_BindingSubstitutesTypeArgument()
    {
        // value: T binds as int on a Result<int> scrutinee, so it flows into int math.
        AssertNoErrors(@"
            union Result<T> {
                Success { value: T }
                Failure { error: string }
            }

            func handle(r: Result<int>): int {
                return match r {
                    Result.Success { value } => value + 1,
                    Result.Failure { error } => 0
                }
            }
        ");
    }

    [Fact]
    public void GenericUnionMatch_UnknownCase_Error()
    {
        AssertHasError(@"
            union Result<T> {
                Success { value: T }
                Failure { error: string }
            }

            func handle(r: Result<int>): int {
                return match r {
                    Result.Bogus { value } => value,
                    _ => 0
                }
            }
        ", "is not a case of union");
    }

    [Fact]
    public void ConstructorWithFieldAssignment_Valid()
    {
        AssertNoErrors(@"
            class Person {
                Name: string

                constructor(name: string) {
                    Name = name
                }
            }
        ");
    }

    [Fact]
    public void ConstructorMissingFieldAssignment_Error()
    {
        AssertHasError(@"
            class Person {
                Name: string

                constructor() {
                }
            }
        ", "isn't assigned in this constructor");
    }

    [Fact]
    public void FieldWithInitializer_NoConstructorError()
    {
        AssertNoErrors(@"
            class Person {
                Name: string = ""Unknown""

                constructor() {
                }
            }
        ");
    }

    [Fact]
    public void StaticFieldWithoutInitializer_NoConstructorError()
    {
        // Regression: NL304 demanded a constructor assignment for an uninitialized STATIC field — but a static
        // field is .cctor-initialized (or CLR zero), never an instance constructor's contract. Statics are
        // skipped; the unassigned INSTANCE field in the sibling test above must still fire.
        AssertNoErrors(@"
            class Counter {
                static total: int
                n: int

                constructor(n0: int) {
                    n = n0
                }
            }
        ");
    }

    [Fact]
    public void TryCatchFinally_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                try {

                } catch {

                } finally {

                }
            }
        ");
    }

    [Theory]
    [InlineData("catch ex: int { }", "int")]
    [InlineData("catch ex: string { }", "string")]
    [InlineData("catch ex: object { }", "object")]
    public void CatchClause_NonExceptionType_ReportsTypeMismatch(string catchClause, string catchType)
    {
        var result = AnalyzeWithSource($$"""
            func Main() {
                try {
                } {{catchClause}}
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("Catch type must be assignable to System.Exception", error.Message);
        Assert.Contains($"'{catchType}'", error.Message);
        Assert.Contains("Exception-derived", error.Suggestion);
    }

    [Fact]
    public void CatchClause_UnknownType_ReportsTypeNotFoundOnly()
    {
        var result = AnalyzeWithSource("""
            func Main() {
                try {
                } catch ex: MissingException {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        Assert.Contains("MissingException", error.Message);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
    }

    [Fact]
    public void CatchClause_ExceptionTypes_AreValid()
    {
        AssertNoErrors("""
            import System

            class DomainFailure : Exception {
            }

            func Main() {
                try {
                } catch ex: InvalidOperationException {
                } catch custom: DomainFailure {
                } catch {
                }
            }
            """);
    }

    [Theory]
    [InlineData("int", "int")]
    [InlineData("string", "string")]
    [InlineData("object", "object")]
    public void AssertThrows_NonExceptionType_ReportsTypeMismatch(string assertType, string expectedType)
    {
        var result = AnalyzeWithSource($$"""
            func Main() {
                assert throws {{assertType}} {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("Assert throws type must be assignable to System.Exception", error.Message);
        Assert.Contains($"'{expectedType}'", error.Message);
        Assert.Contains("Exception-derived", error.Suggestion);
    }

    [Fact]
    public void AssertThrows_UnknownType_ReportsTypeNotFoundOnly()
    {
        var result = AnalyzeWithSource("""
            func Main() {
                assert throws MissingException {
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        Assert.Contains("MissingException", error.Message);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
    }

    [Fact]
    public void AssertThrows_ExceptionTypes_AreValid()
    {
        AssertNoErrors("""
            import System

            class DomainFailure : Exception {
            }

            func Main() {
                assert throws InvalidOperationException {
                    throw new InvalidOperationException("boom")
                }

                assert throws DomainFailure {
                    throw new DomainFailure()
                }
            }
            """);
    }

    [Fact]
    public void UsingStatement_Valid()
    {
        AssertNoErrors("""
            class Resource {
                func Dispose(): void {
                }
            }

            func Main() {
                using resource := new Resource() {
                }
            }
        """);
    }

    [Fact]
    public void UsingStatement_RuntimeDisposable_Valid()
    {
        AssertNoErrors("""
            import System.IO

            func Main() {
                using stream := new MemoryStream() {
                }
            }
        """);
    }

    [Theory]
    [InlineData("using value := 1 { }", "int")]
    [InlineData("using let text: string = \"test\" { }", "string")]
    [InlineData("using \"test\" { }", "string")]
    public void UsingStatement_NonDisposableResource_Error(string statement, string typeName)
    {
        var result = AnalyzeWithSource($$"""
            func Main() {
                {{statement}}
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains($"Using resource of type '{typeName}' must implement IDisposable", error.Message);
        Assert.Contains("Dispose(): void", error.Message);
    }

    [Theory]
    [InlineData("func Dispose(value: int): void { }")]
    [InlineData("func Dispose(): int { return 0 }")]
    [InlineData("static func Dispose(): void { }")]
    public void UsingStatement_InvalidDisposePattern_Error(string disposeMember)
    {
        var result = AnalyzeWithSource($$"""
            class Resource {
                {{disposeMember}}
            }

            func Main() {
                using resource := new Resource() {
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("Using resource of type 'Resource' must implement IDisposable", error.Message);
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

    [Theory]
    [InlineData("x, y := 1", "needs a tuple value")]
    [InlineData("x, y, z := (1, 2)", "has 3 target(s), but the initializer has 2 element(s)")]
    [InlineData("x, y := (1, 2, 3)", "has 2 target(s), but the initializer has 3 element(s)")]
    public void TupleDeconstruction_InvalidInitializer_Error(string statement, string message)
    {
        var result = AnalyzeWithSource($$"""
            func Main() {
                {{statement}}
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains(message, error.Message);
    }

    [Fact]
    public void ForeachLoop_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                nums := [1, 2, 3]
                foreach num in nums {

                }
            }
        ");
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

    [Theory]
    [InlineData("foreach value in 1 { }", "foreach collection must be enumerable")]
    [InlineData("await foreach value in [1, 2, 3] { }", "await foreach collection must be async enumerable")]
    public void ForeachLoop_NonEnumerableCollection_Error(string statement, string message)
    {
        var result = AnalyzeWithSource($$"""
            import System.Threading.Tasks

            async func Main(): Task<int> {
                {{statement}}
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains(message, error.Message);
    }

    [Fact]
    public void NestedScopes_AccessOuterVariable()
    {
        AssertNoErrors(@"
            func Main() {
                x := 1
                {
                    y := x + 1
                }
            }
        ");
    }

    [Fact]
    public void ClassMethodAccess_Valid()
    {
        AssertNoErrors(@"
            class Calculator {
                func Add(x: int, y: int): int {
                    return x + y
                }
            }
        ");
    }

    [Fact]
    public void StaticMethod_Valid()
    {
        AssertNoErrors(@"
            class Utils {
                static func DoThing() {

                }
            }
        ");
    }

    [Fact]
    public void MultipleParameters_Valid()
    {
        AssertNoErrors(@"
            func Process(a: int, b: string, c: bool): int {
                return a
            }
        ");
    }

    [Fact]
    public void ReturnStatement_VoidFunction()
    {
        AssertNoErrors(@"
            func DoNothing() {
                return
            }
        ");
    }

    [Fact]
    public void Assignment_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                let x: int
                x = 42
            }
        ");
    }

    [Fact]
    public void CompoundAssignment_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                x := 10
                x += 5
            }
        ");
    }

    [Fact]
    public void CompoundAssignment_BoolOperand_Error()
    {
        var result = AnalyzeWithSource(@"
            func Main() {
                value := true
                value += true
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'+' operator doesn't work with 'bool' and 'bool'", error.Message);
        Assert.Contains("numeric values", error.Message);
    }

    [Fact]
    public void CompoundAssignment_DecimalOperand_NoErrors()
    {
        AssertNoErrors(@"
            func Main() {
                value := 10m
                value += 2.5m
            }
        ");
    }

    [Fact]
    public void CompoundAssignment_PromotedSmallIntegerResult_Error()
    {
        var result = AnalyzeWithSource(@"
            func Main() {
                left: byte = 1 as byte
                right: byte = 2 as byte
                left += right
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("'+=' assignment produces 'int'", error.Message);
        Assert.Contains("can't be stored in 'byte'", error.Message);
    }

    [Fact]
    public void NullCoalesceAssignment_NonNullableValueTarget_Invalid()
    {
        var result = Analyze(@"
            func Main() {
                x := 10
                x ??= 5
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??=' has type 'int'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the target nullable", error.Suggestion);
    }

    [Fact]
    public void NullCoalesce_NonNullableValueLeft_Invalid()
    {
        var result = Analyze(@"
            func Main(): int {
                x := 10
                return x ?? 5
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("left side of '??' has type 'int'", error.Message);
        Assert.Contains("can't be null", error.Message);
        Assert.Contains("make the left side nullable", error.Suggestion);
    }

    [Fact]
    public void NullCoalesce_NullableValueLeft_Valid()
    {
        AssertNoErrors(@"
            func FromParameter(n: int?): int {
                return n ?? 5
            }

            func FromDefinitelyAssignedLocal(): int {
                n: int? = 10
                return n ?? 0
            }
        ");
    }

    [Fact]
    public void NullableType_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                let x: int? = null
            }
        ");
    }

    [Fact]
    public void GenericClass_Valid()
    {
        AssertNoErrors(@"
            class List<T> {
                items: T[]
            }
        ");
    }

    [Fact]
    public void InterfaceDeclaration_Valid()
    {
        AssertNoErrors(@"
            interface IReader {
                func Read(): string
            }
        ");
    }

    [Fact]
    public void RecordDeclaration_Valid()
    {
        AssertNoErrors(@"
            record Person {
                Name: string
                Age: int
            }
        ");
    }

    [Fact]
    public void SoaRecordDeclaration_IsFeatureGated()
    {
        var result = Analyze(@"
            soa record NodeTable {
                kind: int
                valueStart: int
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("soa record 'NodeTable'", error.Message);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void StructDeclaration_Valid()
    {
        AssertNoErrors(@"
            struct Point {
                X: int
                Y: int
            }
        ");
    }

    [Fact]
    public void ExternalType_Console_Valid()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Console.WriteLine(""Hello"")
            }
        ");
    }

    [Fact]
    public void ExternalType_MemberAccess_Valid()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                let msg = ""test""
                Console.WriteLine(msg)
            }
        ");
    }

    [Fact]
    public void Lambda_InferredType_Valid()
    {
        AssertNoErrors(@"
            import System.Linq

            func Main() {
                numbers := [1, 2, 3]
                doubled := numbers.Select(x => x * 2)
            }
        ");
    }

    [Fact]
    public void ExternalType_MethodOverloading_Valid()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Console.WriteLine(42)
                Console.WriteLine(""text"")
                Console.WriteLine(true)
            }
        ");
    }

    [Fact]
    public void ReadonlyField_SetInConstructor_Valid()
    {
        AssertNoErrors(@"
            class MyClass {
                readonly id: string

                constructor() {
                    id = ""123""
                }
            }
        ");
    }

    [Fact]
    public void ReadonlyField_SetOutsideConstructor_Error()
    {
        AssertHasError(@"
            class MyClass {
                readonly id: string

                constructor() {
                    id = ""123""
                }

                func ChangeId() {
                    id = ""456""
                }
            }
        ", "readonly");
    }

    [Theory]
    [InlineData("bump(ref value)", "ref")]
    [InlineData("reset(out this.value)", "out")]
    public void ReadonlyField_RefOutArgumentOutsideConstructor_Error(string statement, string modifier)
    {
        var result = AnalyzeWithSource($$"""
            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            class Counter {
                readonly value: int

                constructor() {
                    value = 1
                }

                func Mutate() {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains($"can't be used as a {modifier} argument", error.Message);
        Assert.Contains("remove `readonly`", error.Suggestion);
    }

    [Fact]
    public void ReadonlyField_QualifiedInstanceAssignmentOutsideConstructor_Error()
    {
        var result = AnalyzeWithSource("""
            class Counter {
                readonly value: int

                constructor() {
                    value = 1
                }

                func Mutate(other: Counter) {
                    other.value = 2
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("Field 'value' is readonly", error.Message);
        Assert.Contains("constructor", error.Message);
        Assert.Contains("remove `readonly`", error.Suggestion);
    }

    [Fact]
    public void ReadonlyField_QualifiedInstanceAssignmentInConstructor_Error()
    {
        var result = AnalyzeWithSource("""
            class Counter {
                readonly value: int

                constructor(other: Counter) {
                    value = 1
                    other.value = 2
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("current instance", error.Message);
        Assert.Contains("current instance field directly", error.Suggestion);
    }

    [Theory]
    [InlineData("bump(ref other.value)", "ref")]
    [InlineData("reset(out other.value)", "out")]
    public void ReadonlyField_QualifiedInstanceRefOutArgument_Error(string statement, string modifier)
    {
        var result = AnalyzeWithSource($$"""
            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            class Counter {
                readonly value: int

                constructor() {
                    value = 1
                }

                func Mutate(other: Counter) {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("Field 'value' is readonly", error.Message);
        Assert.Contains($"can't be used as a {modifier} argument", error.Message);
        Assert.Contains("remove `readonly`", error.Suggestion);
    }

    [Theory]
    [InlineData("value = 2")]
    [InlineData("this.value = 2")]
    public void ReadonlyField_InheritedAssignmentOutsideConstructor_Error(string statement)
    {
        var result = AnalyzeWithSource($$"""
            class Base {
                readonly value: int = 1
            }

            class Derived : Base {
                func Mutate() {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("Field 'value' is readonly", error.Message);
        Assert.Contains("constructor", error.Message);
    }

    [Theory]
    [InlineData("value = 2")]
    [InlineData("this.value = 2")]
    public void ReadonlyField_InheritedAssignmentInDerivedConstructor_Error(string statement)
    {
        var result = AnalyzeWithSource($$"""
            class Base {
                readonly value: int = 1
            }

            class Derived : Base {
                constructor() {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("current instance", error.Message);
        Assert.Contains("current instance field directly", error.Suggestion);
    }

    [Theory]
    [InlineData("bump(ref value)", "ref")]
    [InlineData("reset(out this.value)", "out")]
    public void ReadonlyField_InheritedRefOutArgument_Error(string statement, string modifier)
    {
        var result = AnalyzeWithSource($$"""
            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            class Base {
                readonly value: int = 1
            }

            class Derived : Base {
                func Mutate() {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("Field 'value' is readonly", error.Message);
        Assert.Contains($"can't be used as a {modifier} argument", error.Message);
    }

    [Fact]
    public void ReadonlyField_ExternalInheritedReadonlyShadowedByMutableField_Valid()
    {
        var result = AnalyzeWithInteropProbe("""
            import NSharpLang.Tests

            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            func Mutate(derived: CSharpMutableInstanceFieldShadowsReadonlyBase) {
                derived.Value = 2
                bump(ref derived.Value)
                reset(out derived.Value)
                derived.Value++
            }
        """);

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
    }

    [Theory]
    [InlineData("value++", "++")]
    [InlineData("this.value--", "--")]
    public void ReadonlyField_InheritedIncrement_Error(string statement, string op)
    {
        var result = AnalyzeWithSource($$"""
            class Base {
                readonly value: int = 1
            }

            class Derived : Base {
                func Mutate() {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("Field 'value' is readonly", error.Message);
        Assert.Contains($"'{op}'", error.Message);
    }

    [Theory]
    [InlineData("value++", "++")]
    [InlineData("this.value--", "--")]
    public void ReadonlyField_IncrementOutsideConstructor_Error(string statement, string op)
    {
        var result = AnalyzeWithSource($$"""
            class Counter {
                readonly value: int

                constructor() {
                    value = 1
                }

                func Mutate() {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("Field 'value' is readonly", error.Message);
        Assert.Contains($"'{op}'", error.Message);
        Assert.Contains("remove `readonly`", error.Suggestion);
    }

    [Fact]
    public void ReadonlyField_IncrementCurrentInstanceInConstructor_Valid()
    {
        AssertNoErrors("""
            class Counter {
                readonly value: int

                constructor() {
                    value = 1
                    value++
                    this.value--
                }
            }
        """);
    }

    [Theory]
    [InlineData("other.value++", "++")]
    [InlineData("other.value--", "--")]
    public void ReadonlyField_QualifiedInstanceIncrement_Error(string statement, string op)
    {
        var result = AnalyzeWithSource($$"""
            class Counter {
                readonly value: int

                constructor() {
                    value = 1
                }

                func Mutate(other: Counter) {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("Field 'value' is readonly", error.Message);
        Assert.Contains($"'{op}'", error.Message);
        Assert.Contains("remove `readonly`", error.Suggestion);
    }

    [Theory]
    [InlineData("State.Value++", "++")]
    [InlineData("Value--", "--")]
    public void StaticReadonlyField_Increment_Error(string statement, string op)
    {
        var result = AnalyzeWithSource($$"""
            class State {
                static readonly Value: int = 1

                static func Mutate() {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("static readonly", error.Message);
        Assert.Contains($"'{op}'", error.Message);
        Assert.Contains("declaration", error.Suggestion);
    }

    [Theory]
    [InlineData("bump(ref derived.Value)")]
    [InlineData("reset(out derived.Value)")]
    public void InstanceField_InheritedRefOutArgument_Valid(string statement)
    {
        AssertNoErrors($$"""
            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            class Base {
                Value: int
            }

            class Derived : Base {
            }

            func Mutate(derived: Derived) {
                {{statement}}
            }
        """);
    }

    [Theory]
    [InlineData("bump(ref derived.Value)")]
    [InlineData("reset(out derived.Value)")]
    public void InstanceField_ExternalInheritedRefOutArgument_Valid(string statement)
    {
        var result = AnalyzeWithInteropProbe($$"""
            import NSharpLang.Tests

            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            func Mutate(derived: CSharpInheritedInstanceFieldDerived) {
                {{statement}}
            }
        """);

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
    }

    [Fact]
    public void InstanceField_ExternalShadowedInheritedFieldRefArgument_Error()
    {
        var result = AnalyzeWithInteropProbe("""
            import NSharpLang.Tests

            func bump(ref value: int) {
                value += 1
            }

            func Mutate(derived: CSharpInstancePropertyShadowsInheritedField) {
                bump(ref derived.Value)
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("needs an assignable target", error.Message);
    }

    [Fact]
    public void StaticReadonlyField_InheritedAssignment_Error()
    {
        var result = AnalyzeWithSource("""
            class Base {
                static readonly Value: int = 1
            }

            class Derived : Base {
                static func Mutate() {
                    Derived.Value = 2
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("Field 'Value' is static readonly", error.Message);
        Assert.Contains("field initializer", error.Suggestion);
    }

    [Theory]
    [InlineData("bump(ref Derived.Value)")]
    [InlineData("reset(out Derived.Value)")]
    public void StaticField_InheritedRefOutArgument_Valid(string statement)
    {
        AssertNoErrors($$"""
            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            class Base {
                static Value: int
            }

            class Derived : Base {
                static func Mutate() {
                    {{statement}}
                }
            }
        """);
    }

    [Theory]
    [InlineData("bump(ref CSharpInheritedStaticFieldDerived.Value)")]
    [InlineData("reset(out CSharpInheritedStaticFieldDerived.Value)")]
    public void StaticField_ExternalInheritedRefOutArgument_Valid(string statement)
    {
        var result = AnalyzeWithInteropProbe($$"""
            import NSharpLang.Tests

            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            func Main() {
                {{statement}}
            }
        """);

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
    }

    [Fact]
    public void StaticField_ExternalShadowedInheritedFieldRefArgument_Error()
    {
        var result = AnalyzeWithInteropProbe("""
            import NSharpLang.Tests

            func bump(ref value: int) {
                value += 1
            }

            func Main() {
                bump(ref CSharpStaticPropertyShadowsInheritedField.Value)
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidSyntax);
        Assert.Contains("needs an assignable target", error.Message);
    }

    [Theory]
    [InlineData("bump(ref Derived.Value)", "ref")]
    [InlineData("reset(out Derived.Value)", "out")]
    public void StaticReadonlyField_InheritedRefOutArgument_Error(string statement, string modifier)
    {
        var result = AnalyzeWithSource($$"""
            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            class Base {
                static readonly Value: int = 1
            }

            class Derived : Base {
                static func Mutate() {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("static readonly", error.Message);
        Assert.Contains($"can't be used as a {modifier} argument", error.Message);
        Assert.Contains("declaration", error.Suggestion);
    }

    [Fact]
    public void StaticReadonlyField_InheritedIncrement_Error()
    {
        var result = AnalyzeWithSource("""
            class Base {
                static readonly Value: int = 1
            }

            class Derived : Base {
                static func Mutate() {
                    Derived.Value++
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("static readonly", error.Message);
        Assert.Contains("'++'", error.Message);
        Assert.Contains("declaration", error.Suggestion);
    }

    [Fact]
    public void StaticReadonlyField_ExternalInheritedReadonlyShadowedByMutableField_Valid()
    {
        var result = AnalyzeWithInteropProbe("""
            import NSharpLang.Tests

            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            func Mutate() {
                CSharpMutableStaticFieldShadowsReadonlyBase.Value = 2
                bump(ref CSharpMutableStaticFieldShadowsReadonlyBase.Value)
                reset(out CSharpMutableStaticFieldShadowsReadonlyBase.Value)
                CSharpMutableStaticFieldShadowsReadonlyBase.Value++
            }
        """);

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
    }

    [Theory]
    [InlineData("State.Value = 2", "Value")]
    [InlineData("Value = 2", "Value")]
    public void StaticReadonlyField_SetOutsideDeclaration_Error(string statement, string fieldName)
    {
        var result = AnalyzeWithSource($$"""
            class State {
                static readonly Value: int = 1

                static func Mutate() {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains($"Field '{fieldName}' is static readonly", error.Message);
        Assert.Contains("field initializer", error.Suggestion);
    }

    [Theory]
    [InlineData("bump(ref State.Value)", "ref")]
    [InlineData("reset(out State.Value)", "out")]
    [InlineData("bump(ref Value)", "ref")]
    public void StaticReadonlyField_RefOutArgument_Error(string statement, string modifier)
    {
        var result = AnalyzeWithSource($$"""
            func bump(ref value: int) {
                value += 1
            }

            func reset(out value: int) {
                value = 0
            }

            class State {
                static readonly Value: int = 1

                static func Mutate() {
                    {{statement}}
                }
            }
        """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReadonlyAssignment);
        Assert.Contains("static readonly", error.Message);
        Assert.Contains($"can't be used as a {modifier} argument", error.Message);
        Assert.Contains("declaration", error.Suggestion);
    }

    [Fact]
    public void ReadonlyField_WithInitializer_Valid()
    {
        AssertNoErrors(@"
            class MyClass {
                readonly id: string = ""default""
            }
        ");
    }

    // Duck Interface Tests
    [Fact]
    public void DuckInterface_ClassImplementsInterface_Valid()
    {
        AssertNoErrors(@"
            duck interface IReader {
                func Read(): string
            }

            class FileReader {
                func Read(): string {
                    return ""data""
                }
            }

            func DoWork(r: IReader) {
            }

            func Main() {
                reader := new FileReader()
                DoWork(reader)
            }
        ");
    }

    [Fact]
    public void DuckInterface_StructImplementsInterface_Valid()
    {
        AssertNoErrors(@"
            duck interface ICounter {
                func GetCount(): int
                func Increment()
            }

            struct Counter {
                count: int

                func GetCount(): int {
                    return count
                }

                func Increment() {
                    count = count + 1
                }
            }

            func Process(c: ICounter) {
            }

            func Main() {
                counter := new Counter { count: 0 }
                Process(counter)
            }
        ");
    }

    [Fact]
    public void DuckInterface_RecordImplementsInterface_Valid()
    {
        AssertNoErrors(@"
            duck interface IPrintable {
                func ToString(): string
            }

            record Person {
                Name: string
                Age: int

                func ToString(): string {
                    return Name
                }
            }

            func Print(p: IPrintable) {
            }

            func Main() {
                person := new Person { Name: ""John"", Age: 30 }
                Print(person)
            }
        ");
    }

    [Fact]
    public void DuckInterface_ClassMissingMethod_Error()
    {
        AssertHasError(@"
            duck interface IReader {
                func Read(): string
                func Close()
            }

            class FileReader {
                func Read(): string {
                    return ""data""
                }
                // Missing Close() method
            }

            func DoWork(r: IReader) {
            }

            func Main() {
                reader := new FileReader()
                DoWork(reader)
            }
        ", "but parameter");
    }

    [Fact]
    public void DuckInterface_MethodWrongReturnType_Error()
    {
        AssertHasError(@"
            duck interface IReader {
                func Read(): string
            }

            class FileReader {
                func Read(): int {  // Wrong return type
                    return 42
                }
            }

            func DoWork(r: IReader) {
            }

            func Main() {
                reader := new FileReader()
                DoWork(reader)
            }
        ", "but parameter");
    }

    [Fact]
    public void DuckInterface_MethodWrongParameterCount_Error()
    {
        AssertHasError(@"
            duck interface IWriter {
                func Write(data: string)
            }

            class FileWriter {
                func Write(data: string, append: bool) {  // Wrong parameter count
                }
            }

            func DoWork(w: IWriter) {
            }

            func Main() {
                writer := new FileWriter()
                DoWork(writer)
            }
        ", "but parameter");
    }

    [Fact]
    public void DuckInterface_MethodWrongParameterType_Error()
    {
        AssertHasError(@"
            duck interface IProcessor {
                func Process(value: int): string
            }

            class DataProcessor {
                func Process(value: string): string {  // Wrong parameter type
                    return value
                }
            }

            func DoWork(p: IProcessor) {
            }

            func Main() {
                processor := new DataProcessor()
                DoWork(processor)
            }
        ", "but parameter");
    }

    [Fact]
    public void DuckInterface_MultipleMethodsAllImplemented_Valid()
    {
        AssertNoErrors(@"
            duck interface IDataStore {
                func Save(data: string)
                func Load(): string
                func Delete()
            }

            class MemoryStore {
                data: string

                func Save(d: string) {
                    data = d
                }

                func Load(): string {
                    return data
                }

                func Delete() {
                    data = """"
                }
            }

            func UseStore(store: IDataStore) {
            }

            func Main() {
                store := new MemoryStore { data: """" }
                UseStore(store)
            }
        ");
    }

    [Fact]
    public void DuckInterface_VariableAssignment_Valid()
    {
        AssertNoErrors(@"
            duck interface IReader {
                func Read(): string
            }

            class FileReader {
                func Read(): string {
                    return ""data""
                }
            }

            func Main() {
                let reader: IReader = new FileReader()
            }
        ");
    }

    [Fact]
    public void DuckInterface_ReturnValue_Valid()
    {
        AssertNoErrors(@"
            duck interface IReader {
                func Read(): string
            }

            class FileReader {
                func Read(): string {
                    return ""data""
                }
            }

            func CreateReader(): IReader {
                return new FileReader()
            }
        ");
    }

    // Match expression exhaustiveness tests

    [Fact]
    public void MatchExpression_Exhaustive_AllCasesCovered()
    {
        AssertNoErrors(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value,
                    Result.Failure { error } => 0
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_NonExhaustive_MissingCase()
    {
        AssertHasError(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value
                }
            }
        ", "doesn't cover all");
    }

    [Fact]
    public void MatchExpression_ConstrainedUnionCaseProperty_DoesNotCoverWholeCase()
    {
        AssertHasError(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value: 0 } => 0,
                    Result.Failure { error } => 1
                }
            }
        ", "partially covered: Success");
    }

    [Fact]
    public void MatchExpression_ConstrainedUnionCaseProperty_ReportsMissingAndPartialCases()
    {
        AssertHasError(@"
            union Result {
                Success { value: int }
                Failure { error: string }
                Pending
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value: 0 } => 0
                }
            }
        ", "missing: Failure, Pending; partially covered: Success");
    }

    [Fact]
    public void MatchExpression_NestedConstrainedUnionProperty_DoesNotCoverOuterCase()
    {
        AssertHasError(@"
            union Option {
                Some { value: int }
                None
            }

            union Response {
                Ok { data: Option }
                Error { message: string }
            }

            func Main() {
                r := new Response.Ok { data: new Option.Some { value: 1 } }
                x := match r {
                    Response.Ok { data: Option.Some { value: 0 } } => 0,
                    Response.Error { message } => 1
                }
            }
        ", "Response.Ok { data: Option.None }");
    }

    [Fact]
    public void MatchExpression_NestedUnionPropertyPattern_BindsInnerValue()
    {
        AssertNoErrors(@"
            union Option {
                Some { value: int }
                None
            }

            union Response {
                Ok { data: Option }
                Error { message: string }
            }

            func Main() {
                r := new Response.Ok { data: new Option.Some { value: 1 } }
                x := match r {
                    Response.Ok { data: Option.Some { value } } => value,
                    Response.Ok { data: Option.None } => 0,
                    Response.Error { message } => 0
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_ResultErrorExamplePatterns_AreExhaustive()
    {
        AssertNoErrors(@"
            union Option {
                Some { value: int }
                None
            }

            union Result {
                Success { value: int }
                Failure { error: string, code: int }
            }

            union Response {
                Ok { data: Option }
                Error { message: string }
            }

            func DescribeResult(result: Result): string {
                return match result {
                    Result.Success { value } => $""Success: {value}"",
                    Result.Failure { error, code } => $""Error {code}: {error}""
                }
            }

            func ExtractResponse(response: Response): int {
                return match response {
                    Response.Ok { data: Option.Some { value } } => value,
                    Response.Ok { data: Option.None } => 0,
                    Response.Error { message } => 0
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_NestedUnionPropertyPattern_WrongQualifierDoesNotCoverCase()
    {
        AssertHasError(@"
            union Option {
                Some { value: int }
                None
            }

            union Other {
                Some { value: int }
                None
            }

            union Response {
                Ok { data: Option }
                Error { message: string }
            }

            func Main() {
                r := new Response.Ok { data: new Option.Some { value: 1 } }
                x := match r {
                    Response.Ok { data: Other.Some { value } } => value,
                    Response.Ok { data: Option.None } => 0,
                    Response.Error { message } => 0
                }
            }
        ", "'Other.Some' is not a case of union 'Option'");
    }

    [Fact]
    public void MatchExpression_TopLevelUnionCasePattern_WrongQualifierDoesNotCoverCase()
    {
        AssertHasError(@"
            union Expected {
                Case { value: int }
                Empty
            }

            union Other {
                Case { value: int }
                Empty
            }

            func Main() {
                r := new Expected.Case { value: 1 }
                x := match r {
                    Other.Case { value } => value,
                    Expected.Empty => 0
                }
            }
        ", "'Other.Case' is not a case of union 'Expected'");
    }

    [Fact]
    public void MatchExpression_TopLevelUnionCasePattern_NamespaceLikeWrongQualifierDoesNotCoverCase()
    {
        AssertHasError(@"
            union Expected {
                Case { value: int }
                Empty
            }

            func Main() {
                r := new Expected.Case { value: 1 }
                x := match r {
                    Other.Expected.Case { value } => value,
                    Expected.Empty => 0
                }
            }
        ", "'Other.Expected.Case' is not a case of union 'Expected'");
    }

    [Fact]
    public void MatchExpression_NamespacedUnion_AllowsShortQualifier()
    {
        AssertNoErrors(@"
            namespace Demo.Patterns

            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value,
                    Result.Failure { error } => 0
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_WithWildcard_IsExhaustive()
    {
        AssertNoErrors(@"
            union Result {
                Success { value: int }
                Failure { error: string }
                Pending { message: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value,
                    _ => 0
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_NonExhaustive_MultipleMissingCases()
    {
        AssertHasError(@"
            union Status {
                Pending { id: int }
                Active { id: int }
                Completed { id: int }
                Failed { id: int }
            }

            func Main() {
                s := new Status.Pending { id: 1 }
                x := match s {
                    Status.Pending { id } => 0
                }
            }
        ", "doesn't cover all");
    }

    [Fact]
    public void MatchExpression_PatternBinding_CorrectTypes()
    {
        AssertNoErrors(@"
            union Result {
                Success { value: int }
                Failure { error: string, code: int }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value * 2,
                    Result.Failure { error, code } => code
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_InvalidUnionCase_Error()
    {
        AssertHasError(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value,
                    Result.Unknown => 0
                }
            }
        ", "is not a case of union");
    }

    [Fact]
    public void MatchExpression_InvalidProperty_Error()
    {
        AssertHasError(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value,
                    Result.Failure { invalidProp } => 0
                }
            }
        ", "doesn't have a property named");
    }

    [Fact]
    public void MatchExpression_LiteralPatterns_NoExhaustivenessCheck()
    {
        // For non-union types, we don't check exhaustiveness
        AssertNoErrors(@"
            func Main() {
                x := 5
                result := match x {
                    1 => ""one"",
                    2 => ""two""
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_IdentifierPattern_BindsVariable()
    {
        AssertNoErrors(@"
            func Main() {
                x := 5
                result := match x {
                    n => n * 2
                }
            }
        ");
    }

    [Fact]
    public void ListPattern_IReadOnlyListPattern_Valid()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main(values: IReadOnlyList<int>): int {
                return match values {
                    [first] => first,
                    _ => 0
                }
            }
        ");
    }

    [Fact]
    public void ListPattern_IEnumerablePattern_ReportsPatternTypeMismatch()
    {
        var result = Analyze(@"
            import System.Collections.Generic

            func Main(values: IEnumerable<int>): int {
                return match values {
                    [first] => first,
                    _ => 0
                }
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.PatternTypeMismatch);
        Assert.Contains("arrays or indexable collections", error.Message);
        Assert.Contains("IEnumerable<int>", error.Message);
    }

    [Theory]
    [InlineData("value: string", "< \"m\"", "string", "string")]
    [InlineData("value: string", "== \"m\"", "string", "string")]
    [InlineData("value: object", "== 1", "object", "int")]
    [InlineData("value: int?", "< 1", "int?", "int")]
    [InlineData("value: decimal", "< 1m", "decimal", "decimal")]
    public void RelationalPattern_UnsupportedComparison_ReportsTypeMismatch(
        string declaration,
        string pattern,
        string valueType,
        string patternType)
    {
        var result = Analyze($$"""
            func Main({{declaration}}): int {
                return match value {
                    {{pattern}} => 1,
                    _ => 0
                }
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("Relational pattern", error.Message);
        Assert.Contains($"'{valueType}'", error.Message);
        Assert.Contains($"'{patternType}'", error.Message);
        Assert.Contains("before IL emission", error.Message);
        Assert.Contains("match guard", error.Suggestion);
    }

    [Fact]
    public void RelationalPattern_NumericWidening_IsValid()
    {
        AssertNoErrors("""
            func Main(value: long, ratio: double): int {
                a := match value {
                    < 0 => 1,
                    >= 0 => 2
                }
                b := match ratio {
                    < 1 => 3,
                    >= 1 => 4
                }
                return a + b
            }
            """);
    }

    [Fact]
    public void MatchExpression_IncompatibleCaseTypes_Error()
    {
        AssertHasError(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Success { value } => value,
                    Result.Failure { error } => error
                }
            }
        ", "All match arms must return the same type");
    }

    [Fact]
    public void MatchExpression_WithGuard_Valid()
    {
        AssertNoErrors(@"
            func Main() {
                x := 5
                result := match x {
                    n when n > 0 => ""positive"",
                    n when n < 0 => ""negative"",
                    _ => ""zero""
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_GuardNotBool_Error()
    {
        AssertHasError(@"
            func Main() {
                x := 5
                result := match x {
                    n when ""not a bool"" => ""value""
                }
            }
        ", "A match guard must be a boolean");
    }

    [Fact]
    public void MatchExpression_GuardWithPatternVariable_Valid()
    {
        AssertNoErrors(@"
            union Result {
                Success { value: int }
                Failure { error: string }
            }

            func Main() {
                r := new Result.Success { value: 42 }
                msg := match r {
                    Result.Success { value } when value > 10 => ""big success"",
                    Result.Success { value } => ""small success"",
                    Result.Failure { error } => error
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_WithGuard_AndUnguardedWildcard_IsExhaustive()
    {
        // Guarded arms don't count for coverage, but an unguarded wildcard covers everything
        AssertNoErrors(@"
            union Status {
                Active
                Inactive
                Pending
            }

            func Main() {
                s := new Status.Active { }
                msg := match s {
                    Status.Active when true => ""active"",
                    _ => ""other""
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_WithGuards_MissingCases_ReportsError()
    {
        // Guards on 2 of 3 cases, no wildcard — should report missing unguarded coverage
        AssertHasError(@"
            union Status {
                Active
                Inactive
                Pending
            }

            func Main() {
                s := new Status.Active { }
                msg := match s {
                    Status.Active when true => ""active"",
                    Status.Inactive when true => ""inactive""
                }
            }
        ", "doesn't cover all");
    }

    [Fact]
    public void MatchExpression_WithGuards_AllCasesUnguarded_IsExhaustive()
    {
        // All union cases covered by unguarded arms (some arms also have guards — doesn't matter)
        AssertNoErrors(@"
            union Status {
                Active
                Inactive
                Pending
            }

            func Main() {
                s := new Status.Active { }
                msg := match s {
                    Status.Active when true => ""active special"",
                    Status.Active => ""active"",
                    Status.Inactive => ""inactive"",
                    Status.Pending => ""pending""
                }
            }
        ");
    }

    [Fact]
    public void MatchExpression_AllGuardedNoWildcard_ReportsError()
    {
        // Every arm has a guard and no wildcard — non-exhaustive
        AssertHasError(@"
            union Status {
                Active
                Inactive
                Pending
            }

            func Main() {
                s := new Status.Active { }
                msg := match s {
                    Status.Active when true => ""active"",
                    Status.Inactive when true => ""inactive"",
                    Status.Pending when true => ""pending""
                }
            }
        ", "doesn't cover all");
    }

    [Fact]
    public void MatchExpression_WithGuard_CatchAllBinding_IsExhaustive()
    {
        // An unguarded plain identifier binding (not `_`) is a catch-all and covers all cases
        AssertNoErrors(@"
            union Status {
                Active
                Inactive
                Pending
            }

            func Main() {
                s := new Status.Active { }
                msg := match s {
                    Status.Active when true => ""active special"",
                    other => ""fallback""
                }
            }
        ");
    }

    [Fact]
    public void PrimaryConstructor_ClassParameterAccessibleInMethod()
    {
        AssertNoErrors(@"
            class Logger(name: string) {
                func Log(message: string) {
                    result := name
                }
            }
        ");
    }

    [Fact]
    public void PrimaryConstructor_StructParameterAccessibleInMethod()
    {
        AssertNoErrors(@"
            struct Point(x: double, y: double) {
                func GetDistance(): double {
                    return x * x + y * y
                }
            }
        ");
    }

    [Fact]
    public void PrimaryConstructor_RecordParameterAccessibleInProperty()
    {
        AssertNoErrors(@"
            record Person(name: string, age: int) {
                FullName: string => name
            }
        ");
    }

    [Fact]
    public void PrimaryConstructor_ParameterTypeChecking()
    {
        AssertNoErrors(@"
            class Calculator(value: int) {
                func GetDoubled(): int {
                    return value * 2
                }
            }
        ");
    }

    [Fact]
    public void PrimaryConstructor_MultipleParameters()
    {
        AssertNoErrors(@"
            class Service(logger: string, db: string, cache: string) {
                func DoWork() {
                    a := logger
                    b := db
                    c := cache
                }
            }
        ");
    }

    [Fact]
    public void CollectionExpression_ListAssignment_Valid()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                let numbers: List<int> = [1, 2, 3]
            }
        ");
    }

    [Fact]
    public void CollectionExpression_HashSetAssignment_Valid()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                let unique: HashSet<string> = [""a"", ""b"", ""c""]
            }
        ");
    }

    [Fact]
    public void CollectionExpression_QueueAssignment_Valid()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                let queue: Queue<int> = [1, 2, 3]
            }
        ");
    }

    [Fact]
    public void CollectionExpression_IEnumerableAssignment_Valid()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                let items: IEnumerable<string> = [""a"", ""b""]
            }
        ");
    }

    [Fact]
    public void CollectionExpression_IQueryableAssignment_ReportsFeatureNotImplemented()
    {
        var result = Analyze(@"
            import System.Linq

            func Main() {
                let items: IQueryable<int> = [1, 2, 3]
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("Collection expressions for 'IQueryable<int>'", error.Message);
    }

    [Fact]
    public void CollectionExpression_UnsupportedReflectionSequenceTarget_ReportsFeatureNotImplemented()
    {
        var result = AnalyzeWithInteropProbe(@"
            import NSharpLang.Tests

            func Main() {
                let items: IntEnumerableOnlyBox = [1, 2, 3]
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("Collection expressions for 'IntEnumerableOnlyBox'", error.Message);
        Assert.Contains("not implemented yet", error.Message);
    }

    [Fact]
    public void CollectionExpression_IncompatibleReflectionMutator_ReportsFeatureNotImplemented()
    {
        var result = AnalyzeWithInteropProbe(@"
            import NSharpLang.Tests

            func Main() {
                let items: IntStringAddBag = [1, 2, 3]
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("Collection expressions for 'IntStringAddBag'", error.Message);
        Assert.Contains("not implemented yet", error.Message);
    }

    [Fact]
    public void GenericInterfaceAssignment_ListToICollection_Valid()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            class Item {}

            class Container {
                Items: ICollection<Item> = new List<Item>()
            }
        ");
    }

    [Fact]
    public void CollectionExpression_TypeMismatch_Error()
    {
        AssertHasError(@"
            import System.Collections.Generic

            func Main() {
                let numbers: List<int> = [""not"", ""ints""]
            }
        ", "target collection expects 'int'");
    }

    [Fact]
    public void CollectionExpression_ArrayStillWorks()
    {
        AssertNoErrors(@"
            func Main() {
                let arr: int[] = [1, 2, 3]
            }
        ");
    }

    [Fact]
    public void ParamsParameter_Valid_NoError()
    {
        AssertNoErrors(@"
            func Sum(params numbers: int[]): int {
                return 0
            }
        ");
    }

    [Fact]
    public void ParamsParameter_WithOtherParams_NoError()
    {
        AssertNoErrors(@"
            func Format(format: string, params args: object[]): string {
                return format
            }
        ");
    }

    [Fact]
    public void ParamsParameter_NotLast_Error()
    {
        AssertHasError(@"
            func Invalid(params numbers: int[], other: string) {
            }
        ", "must come last in the parameter list");
    }

    [Fact]
    public void ParamsParameter_NotArray_Error()
    {
        AssertHasError(@"
            func Invalid(params value: int) {
            }
        ", "must be an array or collection type");
    }

    // Extension Method Resolution Tests

    [Fact]
    public void ExtensionMethod_BasicResolution_NoError()
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
    public void ExtensionMethod_DirectCallPassesThisParameter_NoError()
    {
        AssertNoErrors(@"
            func Sum(this arr: int[]): int {
                return arr[0]
            }

            func Average(this arr: int[]): double {
                return (double)Sum(arr) / (double)arr.Length
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_OnVariableType_NoError()
    {
        AssertNoErrors(@"
            func Double(this x: int): int {
                return x * 2
            }

            func Main() {
                let num: int = 5
                let result: int = num.Double()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_WithParameters_NoError()
    {
        AssertNoErrors(@"
            func Repeat(this s: string, count: int): string {
                return s
            }

            func Main() {
                let result: string = ""hello"".Repeat(3)
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_GenericType_NoError()
    {
        AssertNoErrors(@"
            func First(this arr: int[]): int {
                return arr[0]
            }

            func Main() {
                let numbers: int[] = [1, 2, 3]
                let first: int = numbers.First()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_OnCustomType_NoError()
    {
        AssertNoErrors(@"
            class Person {
                Name: string
            }

            func Greet(this p: Person): string {
                return ""Hello""
            }

            func Main() {
                let person: Person = new Person { Name: ""Alice"" }
                let greeting: string = person.Greet()
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_InStaticClass_NoError()
    {
        AssertNoErrors(@"
            static class StringExtensions {
                static func Truncate(this s: string, maxLength: int): string {
                    return s
                }
            }

            func Main() {
                let result: string = ""hello world"".Truncate(5)
            }
        ");
    }

    [Fact]
    public void ExtensionMethod_MultipleExtensions_NoError()
    {
        AssertNoErrors(@"
            func IsEmpty(this s: string): bool {
                return s.Length == 0
            }

            func IsLong(this s: string): bool {
                return s.Length > 10
            }

            func Main() {
                let s: string = ""test""
                let empty: bool = s.IsEmpty()
                let long: bool = s.IsLong()
            }
        ");
    }

    [Fact]
    public void ImplicitConversion_ClassToClass()
    {
        AssertNoErrors(@"
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
        ");
    }

    [Fact]
    public void ExplicitConversion_DoesNotAllowImplicitAssignment()
    {
        AssertHasError(@"
            class Fraction {
                Numerator: int
                Denominator: int

                explicit operator double(f: Fraction) {
                    return f.Numerator / (double)f.Denominator
                }
            }

            func Main() {
                let frac: Fraction = new Fraction { Numerator: 3, Denominator: 4 }
                let value: double = frac  // Should error - explicit conversion required
            }
        ", "is typed as");
    }

    [Fact]
    public void ImplicitConversion_BidirectionalConversions()
    {
        AssertNoErrors(@"
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
        ");
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
    public void TestDefaultParametersRequiredAfterOptional()
    {
        // Invalid: required parameter after optional parameter
        var result = Analyze(@"
            func Invalid(a: int = 1, b: int) {
                print a
            }
        ");

        Assert.NotEmpty(result.Errors);
        var error = result.Errors[0];
        Assert.Equal(ErrorCode.RequiredParameterAfterOptional, error.Code);
        Assert.Contains("'b'", error.Message);
        Assert.Contains("can't come after optional", error.Message);
    }

    [Fact]
    public void TestDefaultParametersMultipleRequiredAfterOptional()
    {
        // Invalid: multiple required parameters after optional ones
        var result = Analyze(@"
            func Invalid(a: int, b: int = 1, c: int, d: string) {
                print a
            }
        ");

        Assert.NotEmpty(result.Errors);
        // Should report error for first required parameter after optional
        var error = result.Errors.FirstOrDefault(e => e.Code == ErrorCode.RequiredParameterAfterOptional);
        Assert.NotNull(error);
        Assert.Contains("'c'", error.Message);
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
    public void TestDefaultParametersInvalidNonConstant()
    {
        // Invalid: non-constant expression as default
        var result = Analyze(@"
            func GetValue(): int {
                return 42
            }

            func Invalid(x: int = GetValue()) {
                print x
            }
        ");

        Assert.NotEmpty(result.Errors);
        var error = result.Errors.FirstOrDefault(e => e.Code == ErrorCode.InvalidDefaultParameterValue);
        Assert.NotNull(error);
        Assert.Contains("default value for", error.Message);
    }

    [Fact]
    public void TestDefaultParametersWithMemberAccess()
    {
        // Valid: member access for constants (C# compiler will validate)
        var result = Analyze(@"
            func SetMax(max: int = int.MaxValue) {
                print max
            }

            func Main() {
                SetMax()
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersWithMemberAccessIdentifier()
    {
        // Valid: member access for constants as default values
        var result = Analyze(@"
            func Resize(size: int = int.MaxValue) {
                print size
            }

            func Main() {
                Resize()
                Resize(200)
            }
        ");

        Assert.Empty(result.Errors);
    }

    [Fact]
    public void TestDefaultParametersWithNewExpression()
    {
        // Valid: new expression with literal arguments
        var result = Analyze(@"
            func Main() {
                // New expressions with literals should be allowed
                print ""test""
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
    public void AssemblyResolution_SystemConsole_Resolved()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Console.WriteLine(""Hello"")
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_TypeImportRejected()
    {
        AssertHasError(@"
            import System.Console

            func Main() {
            }
        ", "is a type, not a namespace");
    }

    [Fact]
    public void AssemblyResolution_SystemLinq_Resolved()
    {
        AssertNoErrors(@"
            import System.Linq

            func Main() {
                numbers := [1, 2, 3, 4, 5]
                evens := numbers.Where(x => x % 2 == 0)
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_SystemCollections_Resolved()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                list := new List<int>()
                list.Add(1)
                list.Add(2)
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_SystemIO_Resolved()
    {
        AssertNoErrors(@"
            import System.IO

            func Main() {
                path := Path.Combine(""folder"", ""file.txt"")
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_SystemThreadingTasks_Resolved()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks

            async func GetDataAsync(): string {
                await Task.Delay(100)
                return ""data""
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_MultiplImports_AllResolved()
    {
        AssertNoErrors(@"
            import System
            import System.Linq
            import System.Collections.Generic

            func Main() {
                Console.WriteLine(""Test"")
                list := new List<int>()
                result := list.Where(x => x > 0)
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_StaticMethodCall_Resolved()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                Math.Max(1, 2)
                Math.Min(3, 4)
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_GenericTypeInstantiation_Resolved()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                dict := new Dictionary<string, int>()
                dict[""key""] = 42
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_ExtensionMethodFromLinq_Resolved()
    {
        AssertNoErrors(@"
            import System.Linq

            func Main() {
                numbers := [1, 2, 3]
                first := numbers.First()
                last := numbers.Last()
                sum := numbers.Sum()
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_NestedTypeAccess_Resolved()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                separator := Environment.NewLine
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_PropertyAccess_Resolved()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            func Main() {
                list := new List<int>()
                list.Add(1)
                count := list.Count
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_GenericPropertyWithNSharpTypeArgument_Resolved()
    {
        AssertNoErrors(@"
            import System.Collections.Generic

            class TaskItem {
                Title: string
            }

            func Main() {
                tasks := new List<TaskItem>()
                count: int = tasks.Count
                if tasks.Count == 0 {
                    print ""No tasks""
                }
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_ChainedMethodCalls_Resolved()
    {
        AssertNoErrors(@"
            import System.Linq

            func Main() {
                numbers := [1, 2, 3, 4, 5]
                result := numbers.Where(x => x > 2).Select(x => x * 2).ToList()
            }
        ");
    }

    [Fact]
    public void GenericMethodReturnType_NSharpTypeArg_ReturnsCorrectType()
    {
        // Bug: JsonSerializer.Deserialize<NSharpType>(body) returned object instead of NSharpType
        AssertNoErrors(@"
            import System.Text.Json

            class MyRequest {
                Name: string
            }

            func DoWork(body: string) {
                request := JsonSerializer.Deserialize<MyRequest>(body)
            }
        ");
    }

    [Fact]
    public void LinqLambda_NSharpElementType_InfersParameterTypes()
    {
        // Bug: .Where(r => r.Name.Contains(q)) on List<NSharpClass> produced NL103
        // because lambda parameter type was 'unknown' instead of the N# class type
        AssertNoErrors(@"
            import System.Linq
            import System.Collections.Generic

            class Recipe {
                Title: string
                Description: string
            }

            func Search(recipes: List<Recipe>, query: string) {
                lower := query.ToLower()
                results := recipes.Where(r => r.Title.ToLower().Contains(lower)).ToList()
            }
        ");
    }

    [Fact]
    public void LinqLambda_SimpleContains_NSharpType()
    {
        // Intermediate test: single Contains without ||
        AssertNoErrors(@"
            import System.Linq
            import System.Collections.Generic

            class Item {
                Name: string
                Tag: string
            }

            func Search(items: List<Item>, q: string) {
                results := items.Where(x => x.Name.Contains(q)).ToList()
            }
        ");
    }

    [Fact]
    public void LinqLambda_BooleanOrInLambda_NSharpType()
    {
        // Bug: || and && failed inside LINQ lambdas with NL103 when used on N# types
        AssertNoErrors(@"
            import System.Linq
            import System.Collections.Generic

            class Item {
                Name: string
                Tag: string
            }

            func Search(items: List<Item>, q: string) {
                results := items.Where(x => x.Name.Contains(q) || x.Tag.Contains(q)).ToList()
            }
        ");
    }

    [Fact]
    public void LinqSelect_NSharpType_InfersLambdaReturnType()
    {
        // Select on a collection of N# types should correctly infer lambda parameter types
        AssertNoErrors(@"
            import System.Linq
            import System.Collections.Generic

            class Person {
                Name: string
                Age: int
            }

            func GetNames(people: List<Person>): List<string> {
                return people.Select(p => p.Name).ToList()
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_SystemText_Resolved()
    {
        AssertNoErrors(@"
            import System.Text

            func Main() {
                sb := new StringBuilder()
                sb.Append(""Hello"")
                sb.Append("" "")
                sb.Append(""World"")
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_DateTime_Resolved()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                now := DateTime.Now
                today := DateTime.Today
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_Guid_Resolved()
    {
        AssertNoErrors(@"
            import System

            func Main() {
                id := Guid.NewGuid()
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_Task_Resolved()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks

            async func DoWork() {
                await Task.Delay(100)
            }
        ");
    }

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

    [Fact]
    public void AwaitExpression_NonAwaitableValue_Error()
    {
        var result = AnalyzeWithSource("""
            import System.Threading.Tasks

            async func Main(): Task<int> {
                value := await 1
                return 0
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.Contains("await expression needs an awaitable value", error.Message);
    }

    [Fact]
    public void AssemblyResolution_FileInfo_Resolved()
    {
        AssertNoErrors(@"
            import System.IO

            func Main() {
                fileInfo := new FileInfo(""test.txt"")
                exists := fileInfo.Exists
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_Regex_Resolved()
    {
        AssertNoErrors(@"
            import System.Text.RegularExpressions

            func Main() {
                pattern := new Regex(""[0-9]+"")
                isMatch := pattern.IsMatch(""123"")
            }
        ");
    }

    [Fact]
    public void GeneratedRegex_StaticPartialFactory_IsValid()
    {
        AssertNoErrors(@"
            import System.Text.RegularExpressions

            partial class Routes {
                [GeneratedRegex(""^(GET|POST) /health$"")]
                static partial func RouteRegex(): Regex
            }
        ");
    }

    [Fact]
    public void GeneratedRegex_InstanceFactory_IsRejected()
    {
        var result = Analyze(@"
            import System.Text.RegularExpressions

            partial class Routes {
                [GeneratedRegex(""^(GET|POST) /health$"")]
                partial func RouteRegex(): Regex
            }
        ");

        Assert.Contains(result.Errors, error =>
            error.Code == ErrorCode.InvalidModifier
            && error.Message.Contains("must be static", StringComparison.Ordinal));
    }

    [Fact]
    public void GeneratedRegex_NonRegexReturn_IsRejected()
    {
        var result = Analyze(@"
            import System.Text.RegularExpressions

            partial class Routes {
                [GeneratedRegex(""^(GET|POST) /health$"")]
                static partial func RouteRegex(): string
            }
        ");

        Assert.Contains(result.Errors, error =>
            error.Code == ErrorCode.TypeMismatch
            && error.Message.Contains("must return System.Text.RegularExpressions.Regex", StringComparison.Ordinal));
    }

    [Fact]
    public void AssemblyResolution_HttpClient_Resolved()
    {
        AssertNoErrors(@"
            import System.Net.Http

            async func GetData(): string {
                client := new HttpClient()
                return await client.GetStringAsync(""https://example.com"")
            }
        ");
    }

    [Fact]
    public void AssemblyResolution_JsonSerializer_Resolved()
    {
        AssertNoErrors(@"
            import System.Text.Json

            func Main() {
                json := JsonSerializer.Serialize(42)
            }
        ");
    }

    // ==================== Override Keyword Tests (Phase 2) ====================

    [Fact]
    public void Override_SimpleOverride_Valid()
    {
        AssertNoErrors(@"
            import System

            class Animal {
                virtual func MakeSound() {
                    Console.WriteLine(""Generic sound"")
                }
            }

            class Dog : Animal {
                override func MakeSound() {
                    Console.WriteLine(""Bark"")
                }
            }
        ");
    }

    [Fact]
    public void Override_WithReturnType_Valid()
    {
        AssertNoErrors(@"
            class Base {
                virtual func GetValue(): int {
                    return 0
                }
            }

            class Derived : Base {
                override func GetValue(): int {
                    return 42
                }
            }
        ");
    }

    [Fact]
    public void Override_WithParameters_Valid()
    {
        AssertNoErrors(@"
            class Base {
                virtual func Process(x: int, y: int): int {
                    return x + y
                }
            }

            class Derived : Base {
                override func Process(x: int, y: int): int {
                    return x * y
                }
            }
        ");
    }

    [Fact]
    public void Override_AsyncMethod_Valid()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks

            class Base {
                virtual async func GetDataAsync(): string {
                    return ""base""
                }
            }

            class Derived : Base {
                override async func GetDataAsync(): string {
                    await Task.Delay(10)
                    return ""derived""
                }
            }
        ");
    }

    [Fact]
    public void Override_MultipleOverrides_Valid()
    {
        AssertNoErrors(@"
            class Base {
                virtual func Method1() { }
                virtual func Method2() { }
                virtual func Method3() { }
            }

            class Derived : Base {
                override func Method1() { }
                override func Method2() { }
                override func Method3() { }
            }
        ");
    }

    [Fact]
    public void Override_InheritanceChain_Valid()
    {
        AssertNoErrors(@"
            class A {
                virtual func DoWork() { }
            }

            class B : A {
                override func DoWork() { }
            }

            class C : B {
                override func DoWork() { }
            }
        ");
    }

    [Fact]
    public void Override_WithBaseCall_Valid()
    {
        AssertNoErrors(@"
            import System

            class Base {
                virtual func Initialize() {
                    Console.WriteLine(""Base init"")
                }
            }

            class Derived : Base {
                override func Initialize() {
                    base.Initialize()
                    Console.WriteLine(""Derived init"")
                }
            }
        ");
    }

    [Fact]
    public void Override_PropertyWithMethods_Valid()
    {
        AssertNoErrors(@"
            class Base {
                virtual func GetName(): string {
                    return ""Base""
                }
            }

            class Derived : Base {
                override func GetName(): string {
                    return ""Derived""
                }
            }
        ");
    }

    [Fact]
    public void Override_GenericMethod_Valid()
    {
        AssertNoErrors(@"
            class Base {
                virtual func Process<T>(item: T): T {
                    return item
                }
            }

            class Derived : Base {
                override func Process<T>(item: T): T {
                    return item
                }
            }
        ");
    }

    [Fact]
    public void Override_AbstractMethod_Valid()
    {
        AssertNoErrors(@"
            import System

            abstract class Base {
                abstract func DoWork(): void
            }

            class Derived : Base {
                override func DoWork(): void {
                    Console.WriteLine(""Working"")
                }
            }
        ");
    }

    // ==================== ASP.NET Core Integration Tests (Task 034) ====================

    [Fact]
    public void AspNetCore_WebApplicationBuilder_Resolves()
    {
        // Gap 1: External Type Resolution from Imports
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                app := builder.Build()
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_IsDevelopment_BooleanInference()
    {
        // Gap 2: Boolean Type Inference from External Methods
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                app := builder.Build()

                if app.Environment.IsDevelopment() {
                    print ""Development mode""
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_NullCoalescing_WithNullableProperties()
    {
        // Gap 3: Null-Coalescing with nullable properties
        AssertNoErrors(@"
            record EmployeeDto {
                Name: string?
                Title: string?
            }

            func ProcessEmployee(dto: EmployeeDto): string {
                name := dto.Name ?? ""Unnamed""
                title := dto.Title ?? ""No title""
                return name
            }
        ");
    }

    [Fact]
    public void AspNetCore_ServicesConfiguration()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                builder.Services.AddControllers()
                app := builder.Build()
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_MiddlewareConfiguration()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                app := builder.Build()

                app.UseHttpsRedirection()
                app.UseAuthorization()
                app.MapControllers()
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_ConditionalMiddleware()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                app := builder.Build()

                if app.Environment.IsDevelopment() {
                    app.UseSwagger()
                    app.UseSwaggerUI()
                }

                app.UseHttpsRedirection()
                app.Run()
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_MinimalApi_MapGet()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                app := builder.Build()

                app.MapGet(""/"", () => ""Hello from N#!"")
                app.Run()
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_MinimalApi_MapGet_InfersRequestDelegateLambda()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder
            import Microsoft.AspNetCore.Http

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                app := builder.Build()

                app.MapGet(""/api/health"", context => context.Response.WriteAsync(""ok""))
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_MinimalApi_MapPost_InfersRequestDelegateBlockLambda()
    {
        AssertNoErrors(@"
            import System.IO
            import Microsoft.AspNetCore.Builder
            import Microsoft.AspNetCore.Http

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                app := builder.Build()

                app.MapPost(""/api/issues"", context => {
                    reader := new StreamReader(context.Request.Body)
                    body := reader.ReadToEndAsync().Result

                    if body == """" {
                        context.Response.StatusCode = 400
                        return context.Response.WriteAsync(""Invalid request body"")
                    }

                    context.Response.StatusCode = 201
                    return context.Response.WriteAsync(body)
                })
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_MinimalApi_MapPost_InfersRequestDelegateBlockLambdaInsideInstanceMethod()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder
            import Microsoft.AspNetCore.Http
            import System.Text.Json

            class Routes {
                jsonOptions: JsonSerializerOptions

                constructor() {
                    jsonOptions = new JsonSerializerOptions()
                }

                func Map(app: WebApplication) {
                    app.MapPost(""/api/issues"", context => {
                        context.Response.StatusCode = 201
                        return context.Response.WriteAsJsonAsync(1, jsonOptions)
                    })
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_WriteAsJsonAsync_SelectsGenericJsonOptionsOverloadForNSharpPayload()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder
            import Microsoft.AspNetCore.Http
            import System.Text.Json

            record IssueResponse {
                Id: int
                Title: string
            }

            class Routes {
                jsonOptions: JsonSerializerOptions

                constructor() {
                    jsonOptions = new JsonSerializerOptions()
                }

                func Map(app: WebApplication) {
                    app.MapPost(""/api/issues"", context => {
                        context.Response.StatusCode = 201
                        response := new IssueResponse { Id: 1, Title: ""ok"" }
                        return context.Response.WriteAsJsonAsync(response, jsonOptions)
                    })
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_MinimalApi_MapGet_InfersRequestDelegateMethodGroup()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks
            import Microsoft.AspNetCore.Builder
            import Microsoft.AspNetCore.Http

            class Routes {
                func Map(app: WebApplication) {
                    app.MapGet(""/api/issues"", HandleList)
                }

                func HandleList(context: HttpContext): Task {
                    return context.Response.WriteAsync(""ok"")
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void MethodGroupToClrDelegate_RejectsNumericParameterConversion()
    {
        var result = Analyze(@"
            import System

            func Use(action: Action<int>) {
            }

            func AcceptLong(value: long) {
            }

            func Main() {
                Use(AcceptLong)
            }
        ");

        Assert.True(result.HasErrors, "Expected method group binding to reject numeric parameter conversion.");
        Assert.Contains(result.Errors, error => error.Message.Contains("AcceptLong"));
    }

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

    [Fact]
    public void MethodGroupToClrDelegate_PrefersExactParameterOverContravariantMatch()
    {
        var config = new ProjectConfig
        {
            Dependencies = [new Reference { Dll = typeof(RuntimeDelegateOverloadHelpers).Assembly.Location }]
        };

        AssertNoErrors(@"
            import System
            import NSharpLang.Tests

            func AcceptObject(value: object) {
            }

            func Main() {
                result: int = RuntimeDelegateOverloadHelpers.UseMethodGroup(AcceptObject)
            }
        ", config);
    }

    [Fact]
    public void MethodGroupToClrDelegate_PreservesSelectedNSharpOverload()
    {
        var config = new ProjectConfig
        {
            Dependencies = [new Reference { Dll = typeof(RuntimeDelegateOverloadHelpers).Assembly.Location }]
        };

        AssertNoErrors(@"
            import System
            import NSharpLang.Tests

            func Handle(value: string) {
            }

            func Handle(value: int) {
            }

            func Main() {
                result: string = RuntimeDelegateOverloadHelpers.UseMethodGroup(Handle)
            }
        ", config);
    }

    [Fact]
    public void MethodGroupToClrDelegate_BindsGenericReturnTypeDuringReflectionInference()
    {
        AssertNoErrors(@"
            import System.Linq

            func Convert(value: int): string {
                return value.ToString()
            }

            func Main() {
                values := [1, 2]
                texts := values.Select(Convert).ToArray()
                first: string = texts[0]
            }
        ");
    }

    [Fact]
    public void MethodGroupToClrDelegate_RejectsSingleFunctionMismatchDuringAnalysis()
    {
        var config = new ProjectConfig
        {
            Dependencies = [new Reference { Dll = typeof(RuntimeDelegateOverloadHelpers).Assembly.Location }]
        };

        var result = Analyze(@"
            import System
            import NSharpLang.Tests

            func AcceptInt(value: int) {
            }

            func Main() {
                RuntimeDelegateOverloadHelpers.UseMethodGroup(AcceptInt)
            }
        ", config);

        Assert.True(result.HasErrors, "Expected incompatible single-function method group to be rejected during analysis.");
        Assert.Contains(result.Errors, error => error.Message.Contains("AcceptInt"));
    }

    [Fact]
    public void MethodGroupToClrDelegate_RejectsMixedNSharpClrReferenceMismatchDuringAnalysis()
    {
        var config = new ProjectConfig
        {
            Dependencies = [new Reference { Dll = typeof(RuntimeDelegateOverloadHelpers).Assembly.Location }]
        };

        var result = Analyze(@"
            import System
            import NSharpLang.Tests

            class Customer {
            }

            func Handle(customer: Customer) {
            }

            func Main() {
                RuntimeDelegateOverloadHelpers.UseMethodGroup(Handle)
            }
        ", config);

        Assert.True(result.HasErrors, "Expected incompatible mixed N#/CLR method group to be rejected during analysis.");
        Assert.Contains(result.Errors, error => error.Message.Contains("Handle") || error.Message.Contains("UseMethodGroup"));
    }

    [Fact]
    public void MethodGroupToClrDelegate_RejectsAmbiguousOverloadTie()
    {
        var config = new ProjectConfig
        {
            Dependencies = [new Reference { Dll = typeof(RuntimeDelegateOverloadHelpers).Assembly.Location }]
        };

        var result = Analyze(@"
            import System
            import NSharpLang.Tests

            func Handle(value: RuntimeDelegateBase) {
            }

            func Handle(value: IRuntimeDelegateFace) {
            }

            func Main() {
                RuntimeDelegateOverloadHelpers.UseDerived(Handle)
            }
        ", config);

        Assert.True(result.HasErrors, "Expected tied method group overloads to be rejected as ambiguous.");
        Assert.Contains(result.Errors, error => error.Message.Contains("UseDerived"));
    }

    [Fact]
    public void AspNetCore_ChainedConfiguration()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder

            func ConfigureServices(builder: WebApplicationBuilder) {
                builder.Services.AddControllers()
                builder.Services.AddEndpointsApiExplorer()
                builder.Services.AddSwaggerGen()
            }

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                ConfigureServices(builder)
                app := builder.Build()
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_EntityFramework_DbContext()
    {
        AssertNoErrors(@"
            import Microsoft.EntityFrameworkCore

            class AppDbContext : DbContext {
                Employees: DbSet<Employee>

                constructor(options: DbContextOptions<AppDbContext>) : base(options) {
                }
            }

            class Employee {
                Id: int
                Name: string
            }
        ");
    }

    [Fact]
    public void AspNetCore_ControllerBase_Inheritance()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Mvc

            class EmployeesController : ControllerBase {
                func GetAll(): IActionResult {
                    return Ok()
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_ActionResult_Generic()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Mvc

            record EmployeeDto {
                Id: int
                Name: string
            }

            class EmployeesController : ControllerBase {
                func GetById(id: int): ActionResult<EmployeeDto> {
                    dto := new EmployeeDto { Id: id, Name: ""Test"" }
                    return Ok(dto)
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_BadRequest_WithAnonymousObject()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Mvc

            class EmployeesController : ControllerBase {
                func Validate(): IActionResult {
                    errors := [""Error 1"", ""Error 2""]
                    return BadRequest(new { errors: errors })
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AspNetCore_DateTime_StaticProperties()
    {
        AssertNoErrors(@"
            import System

            record Employee {
                Id: int
                Name: string
                CreatedAt: DateTime
            }

            func CreateEmployee(): Employee {
                return new Employee {
                    Id: 1,
                    Name: ""Test"",
                    CreatedAt: DateTime.Now
                }
            }
        ");
    }

    [Fact]
    public void AspNetCore_Guid_Generation()
    {
        AssertNoErrors(@"
            import System

            record Employee {
                Id: Guid
                Name: string
            }

            func CreateEmployee(): Employee {
                return new Employee {
                    Id: Guid.NewGuid(),
                    Name: ""Test""
                }
            }
        ");
    }

    [Fact]
    public void AspNetCore_AsyncTask_WithAwait()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks
            import Microsoft.AspNetCore.Mvc

            class EmployeesController : ControllerBase {
                async func GetDataAsync(): Task<IActionResult> {
                    await Task.Delay(100)
                    return Ok()
                }
            }
        ", AspNetCoreConfig);
    }

    [Fact]
    public void AsyncTask_ReturningUnitTask_DoesNotRequireExplicitReturn()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks

            async func DoWork(): Task {
                await Task.Delay(100)
            }
        ");
    }

    [Fact]
    public void AsyncValueTask_ReturningUnitValueTask_DoesNotRequireExplicitReturn()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks

            async func DoWork(): ValueTask {
                await Task.Delay(100)
            }
        ");
    }

    [Fact]
    public void AsyncTaskOfT_ReturnsBareResultValue()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks

            async func GetValue(): Task<int> {
                await Task.Delay(100)
                return 42
            }
        ");
    }

    [Fact]
    public void AsyncTaskOfT_StillRequiresExplicitReturnValue()
    {
        AssertHasError(@"
            import System.Threading.Tasks

            async func GetValue(): Task<int> {
                await Task.Delay(100)
            }
        ", "not all code paths return");
    }

    [Fact]
    public void AsyncValueTaskOfT_ReturnsBareResultValue()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks

            async func GetValue(): ValueTask<int> {
                await Task.Delay(100)
                return 42
            }
        ");
    }

    [Fact]
    public void AsyncValueTaskOfT_StillRequiresExplicitReturnValue()
    {
        AssertHasError(@"
            import System.Threading.Tasks

            async func GetValue(): ValueTask<int> {
                await Task.Delay(100)
            }
        ", "not all code paths return");
    }

    [Fact]
    public void LocalAsyncFunction_UsesAsyncBeforeFuncSyntax()
    {
        AssertNoErrors(@"
            import System.Threading.Tasks

            async func Main(): Task<int> {
                async func getValue(): Task<int> {
                    await Task.Delay(100)
                    return 42
                }

                return await getValue()
            }
        ");
    }

    [Fact]
    public void AspNetCore_ExternalTypeChaining()
    {
        AssertNoErrors(@"
            import Microsoft.AspNetCore.Builder
            import Microsoft.Extensions.DependencyInjection

            func Main(args: string[]) {
                builder := WebApplication.CreateBuilder(args)
                services := builder.Services
                services.AddControllers()
                app := builder.Build()
            }
        ", AspNetCoreConfig);
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
    public void Lambda_UntypedParam_NoInferenceSource_Errors()
    {
        AssertHasError(@"
            func Main() {
                f := (x) => x + 1
                result := f(5)
            }
        ", "can't figure out the type of lambda parameter");
    }

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
            var lexer = new Lexer(sourceA, fileA);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, fileA, sourceA);
            var parseResult = parser.ParseCompilationUnit();
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
            var lexer = new Lexer(source, file);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, file, source);
            var parseResult = parser.ParseCompilationUnit();
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
            var lexer = new Lexer(sourceA, fileA);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, fileA, sourceA);
            var parseResult = parser.ParseCompilationUnit();
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
    public void OverloadResolution_NoMatchingOverload_Error()
    {
        AssertHasError(@"
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
                p.Process(true)
            }
        ", "No overload of 'Process' accepts");
    }

    [Fact]
    public void OverloadResolution_NoMatchingOverload_UsesCallableNameSpanAndRichContext()
    {
        const string source = """
class Processor {
    func Process(x: int): int { return x }
    func Process(x: string): string { return x }
}

func Main() {
    p := new Processor()
    p.Process(true)
}
""";

        var result = AnalyzeWithSource(source);

        var diagnostic = Assert.Single(result.Errors,
            error => error.Code == ErrorCode.NoMatchingOverload);
        Assert.Equal(8, diagnostic.Line);
        Assert.Equal(7, diagnostic.Column);
        Assert.Equal("Process".Length, diagnostic.Length);
        Assert.Equal("    p.Process(true)", diagnostic.SourceSnippet);
        Assert.Contains("I cannot find an overload of `Process`", diagnostic.HumanExplanation);
        Assert.Contains("Process(x: int): int", diagnostic.ContextualHint);
        Assert.Contains("Process(x: string): string", diagnostic.ContextualHint);
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
    public void GenericInference_WithConstraint_Violated()
    {
        // Inference works but constraint should fail
        AssertHasError(@"
            interface IComparable {
                func CompareTo(other: object): int
            }
            class Plain {
            }
            func Max<T>(a: T, b: T): T where T : IComparable {
                return a
            }
            func Main() {
                result := Max(new Plain(), new Plain())
            }
        ", "does not implement");
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
    public void OverloadResolution_AmbiguousCall_Error()
    {
        AssertHasError(@"
            class Processor {
                func Do(x: int, y: int): int {
                    return x
                }
                func Do(a: int, b: int): int {
                    return a
                }
            }
            func Main() {
                p := new Processor()
                p.Do(1, 2)
            }
        ", "Ambiguous call");
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
    public void OverloadResolution_SameArity_BoolVsInt_Error()
    {
        AssertHasError(@"
            func Process(x: int): int { return x }
            func Process(x: string): string { return x }
            func Main() {
                Process(true)
            }
        ", "No overload of 'Process' accepts");
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

    [Fact]
    public void OverloadResolution_ExtensionOverload_NoMatch_Error()
    {
        AssertHasError(@"
            func Format(this x: int, prefix: string): string { return prefix }
            func Format(this x: int, decimals: int): int { return decimals }
            func Main() {
                5.Format(true)
            }
        ", "No overload of 'Format' accepts");
    }

    // ================================================================
    // Extension methods on literal receivers — type safety
    // ================================================================

    [Fact]
    public void Extension_LiteralReceiver_ReturnTypeChecked()
    {
        // Extension returns int; assigning to string must error
        AssertHasError(@"
            func Double(this n: int): int { return n * 2 }
            func Main() {
                let s: string = 5.Double()
            }
        ", "is typed as");
    }

    [Fact]
    public void Extension_VariableReceiver_ReturnTypeChecked()
    {
        AssertHasError(@"
            func Double(this n: int): int { return n * 2 }
            func Main() {
                let x: int = 5
                let s: string = x.Double()
            }
        ", "is typed as");
    }

    [Fact]
    public void Extension_BoolLiteral_ReturnTypeChecked()
    {
        AssertHasError(@"
            func Toggle(this b: bool): bool { return b }
            func Main() {
                let n: int = true.Toggle()
            }
        ", "is typed as");
    }

    [Fact]
    public void Extension_StringLiteral_ReturnTypeChecked()
    {
        AssertHasError(@"
            func Upper(this s: string): string { return s }
            func Main() {
                let n: int = ""hello"".Upper()
            }
        ", "is typed as");
    }

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
    public void Extension_LiteralReceiver_AsArgument()
    {
        // Extension return passed to function expecting different type should error
        AssertHasError(@"
            func Double(this n: int): int { return n * 2 }
            func TakesString(s: string) {}
            func Main() {
                TakesString(5.Double())
            }
        ", "but parameter");
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
    public void BCL_StringMethodCall_WrongArity_ReportsNoMatchingOverload()
    {
        var result = AnalyzeWithSource(@"
            func Main() {
                greeting := ""hello""
                greeting.CompareTo()
            }
        ");

        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.NoMatchingOverload
            && e.Message.Contains("No overload of 'CompareTo' accepts 0 argument"));
    }

    [Fact]
    public void BCL_StringLiteralUnknownMember_ReportsUndefinedMember()
    {
        var result = AnalyzeWithSource(@"
            func Main() {
                value := ""asdfasdfasdf"".ToUp()
            }
        ");

        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.UndefinedMember
            && e.Message.Contains("ToUp")
            && e.Message.Contains("string"));
    }

    [Fact]
    public void RecordPrimaryConstructorMemberAccess_DoesNotReportUndefinedMember()
    {
        var result = AnalyzeWithSource(@"
            record EmailAddress(value: string) {
                IsValid: bool => value.Length > 5
            }

            func Main() {
                email := new EmailAddress(""user@example.com"")
                print email.value
            }
        ");

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
    }

    [Fact]
    public void NestedTypeMemberAccess_DoesNotReportUndefinedMember()
    {
        var result = AnalyzeWithSource(@"
            class BankAccount {
                enum Status {
                    Active,
                    Frozen
                }

                CurrentStatus: BankAccount.Status

                constructor() {
                    CurrentStatus = BankAccount.Status.Active
                }
            }
        ");

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
    }

    [Fact]
    public void RecordObjectMemberAccess_DoesNotReportUndefinedMember()
    {
        var result = AnalyzeWithSource(@"
            record Point {
                X: int
                Y: int
            }

            func Main() {
                p1 := new Point { X: 1, Y: 2 }
                p2 := new Point { X: 1, Y: 2 }
                print p1.Equals(p2)
            }
        ");

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedMember);
    }

    [Fact]
    public void BCL_MethodCall_WithImplicitNumericWidening_NoNoMatchingOverload()
    {
        var result = AnalyzeWithSource(@"
            import System

            func Main() {
                tomorrow := DateTime.Now.AddDays(1)
            }
        ");

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
    }

    [Fact]
    public void BCL_MethodCall_WithExpandedParams_NoNoMatchingOverload()
    {
        var result = AnalyzeWithSource(@"
            import System

            func Main() {
                Console.WriteLine(""{0} {1}"", ""hello"", ""world"")
            }
        ");

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
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

        Assert.Equal("IQueryable<Char>", result.SemanticModel.LookupIdentifier("chars")?.ToString());
    }

    [Fact]
    public void QueryableLinq_BlockExpressionTreeLambda_ReportsFeatureNotImplemented()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [1, 2, 3]
                query := source.AsQueryable()
                filtered := query.Where(x => { return x > 1 })
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("Expression-tree lambdas must use an expression body", error.Message);
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaWithCapturedValue_ReportsFeatureNotImplemented()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [1, 2, 3]
                query := source.AsQueryable()
                threshold := 1
                filtered := query.Where(x => x > threshold)
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("captured or static identifier 'threshold'", error.Message);
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaNullConditionalIndexAccess_ReportsFeatureNotImplemented()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [""ab"", ""cd""]
                query := source.AsQueryable()
                chars := query.Select(x => x?[0])
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("null-conditional index access", error.Message);
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaNamedCallArgument_ReportsFeatureNotImplemented()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [1, 2, 3]
                query := source.AsQueryable()
                filtered := query.Where(x => x.ToString(format: ""D"") == ""2"")
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("named method argument", error.Message);
    }

    [Fact]
    public void QueryableLinq_ExpressionTreeLambdaUnsupportedSizeof_ReportsFeatureNotImplemented()
    {
        var result = AnalyzeWithSource(@"
            import System.Linq

            func Main() {
                source := [1, 2, 3]
                query := source.AsQueryable()
                mapped := query.Select(x => sizeof(int))
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.FeatureNotImplemented);
        Assert.Contains("sizeof expression", error.Message);
    }

    [Fact]
    public void BCL_MethodCall_WithOutArgument_NoNoMatchingOverload()
    {
        var result = AnalyzeWithSource(@"
            import System

            func Main() {
                result := 0
                if Int32.TryParse(""42"", out result) {
                    print result
                }
            }
        ");

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
    }

    [Fact]
    public void NSharpExtensionMethod_OnInstance_PrefersExtensionOverStaticClrMember()
    {
        var result = AnalyzeWithSource(@"
            func IsPositive(this n: int): bool {
                return n > 0
            }

            func Main() {
                value := 42
                print value.IsPositive()
            }
        ");

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.NoMatchingOverload);
    }

    // ===================================================================
    // Type System Hardening Tests
    // ===================================================================

    #region Nominal Subtyping

    [Fact]
    public void NominalSubtyping_ClassInheritance_Assignable()
    {
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func Main() {
                dog := new Dog()
                animal: Animal = dog
            }
        ");
    }

    [Fact]
    public void NominalSubtyping_InterfaceImplementation_Assignable()
    {
        AssertNoErrors(@"
            interface IGreetable {
                func Greet(): string
            }
            class Person : IGreetable {
                func Greet(): string {
                    return ""Hello""
                }
            }
            func Main() {
                p := new Person()
                g: IGreetable = p
            }
        ");
    }

    [Fact]
    public void NominalSubtyping_EverythingAssignableToObject()
    {
        AssertNoErrors(@"
            func Main() {
                x: object = 42
                y: object = ""hello""
                z: object = true
            }
        ");
    }

    #endregion

    #region Numeric Widening — Comprehensive Assignability Matrix

    // ===== byte widening =====
    [Fact]
    public void NumericWidening_ByteToShort()
    {
        AssertNoErrors(@"
            func GetByte(): byte { return 0 as byte }
            func Main() {
                x: byte = GetByte()
                y: short = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ByteToInt()
    {
        AssertNoErrors(@"
            func GetByte(): byte { return 0 as byte }
            func Main() {
                x: byte = GetByte()
                y: int = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ByteToLong()
    {
        AssertNoErrors(@"
            func GetByte(): byte { return 0 as byte }
            func Main() {
                x: byte = GetByte()
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ByteToFloat()
    {
        AssertNoErrors(@"
            func GetByte(): byte { return 0 as byte }
            func Main() {
                x: byte = GetByte()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ByteToDouble()
    {
        AssertNoErrors(@"
            func GetByte(): byte { return 0 as byte }
            func Main() {
                x: byte = GetByte()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ByteToDecimal()
    {
        AssertNoErrors(@"
            func GetByte(): byte { return 0 as byte }
            func Main() {
                x: byte = GetByte()
                y: decimal = x
            }
        ");
    }

    // ===== sbyte widening =====
    [Fact]
    public void NumericWidening_SByteToShort()
    {
        AssertNoErrors(@"
            func GetSByte(): sbyte { return 0 as sbyte }
            func Main() {
                x: sbyte = GetSByte()
                y: short = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_SByteToInt()
    {
        AssertNoErrors(@"
            func GetSByte(): sbyte { return 0 as sbyte }
            func Main() {
                x: sbyte = GetSByte()
                y: int = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_SByteToLong()
    {
        AssertNoErrors(@"
            func GetSByte(): sbyte { return 0 as sbyte }
            func Main() {
                x: sbyte = GetSByte()
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_SByteToFloat()
    {
        AssertNoErrors(@"
            func GetSByte(): sbyte { return 0 as sbyte }
            func Main() {
                x: sbyte = GetSByte()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_SByteToDouble()
    {
        AssertNoErrors(@"
            func GetSByte(): sbyte { return 0 as sbyte }
            func Main() {
                x: sbyte = GetSByte()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_SByteToDecimal()
    {
        AssertNoErrors(@"
            func GetSByte(): sbyte { return 0 as sbyte }
            func Main() {
                x: sbyte = GetSByte()
                y: decimal = x
            }
        ");
    }

    // ===== short widening =====
    [Fact]
    public void NumericWidening_ShortToInt()
    {
        AssertNoErrors(@"
            func GetShort(): short { return 0 as short }
            func Main() {
                x: short = GetShort()
                y: int = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ShortToLong()
    {
        AssertNoErrors(@"
            func GetShort(): short { return 0 as short }
            func Main() {
                x: short = GetShort()
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ShortToFloat()
    {
        AssertNoErrors(@"
            func GetShort(): short { return 0 as short }
            func Main() {
                x: short = GetShort()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ShortToDouble()
    {
        AssertNoErrors(@"
            func GetShort(): short { return 0 as short }
            func Main() {
                x: short = GetShort()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ShortToDecimal()
    {
        AssertNoErrors(@"
            func GetShort(): short { return 0 as short }
            func Main() {
                x: short = GetShort()
                y: decimal = x
            }
        ");
    }

    // ===== ushort widening =====
    [Fact]
    public void NumericWidening_UShortToInt()
    {
        AssertNoErrors(@"
            func GetUShort(): ushort { return 0 as ushort }
            func Main() {
                x: ushort = GetUShort()
                y: int = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UShortToLong()
    {
        AssertNoErrors(@"
            func GetUShort(): ushort { return 0 as ushort }
            func Main() {
                x: ushort = GetUShort()
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UShortToFloat()
    {
        AssertNoErrors(@"
            func GetUShort(): ushort { return 0 as ushort }
            func Main() {
                x: ushort = GetUShort()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UShortToDouble()
    {
        AssertNoErrors(@"
            func GetUShort(): ushort { return 0 as ushort }
            func Main() {
                x: ushort = GetUShort()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UShortToDecimal()
    {
        AssertNoErrors(@"
            func GetUShort(): ushort { return 0 as ushort }
            func Main() {
                x: ushort = GetUShort()
                y: decimal = x
            }
        ");
    }

    // ===== int widening =====
    [Fact]
    public void NumericWidening_IntToLong()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = 42
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_IntToFloat()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = 42
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_IntToDouble()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = 42
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_IntToDecimal()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = 42
                y: decimal = x
            }
        ");
    }

    // ===== uint widening =====
    [Fact]
    public void NumericWidening_UIntToLong()
    {
        AssertNoErrors(@"
            func GetUInt(): uint { return 0 as uint }
            func Main() {
                x: uint = GetUInt()
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UIntToFloat()
    {
        AssertNoErrors(@"
            func GetUInt(): uint { return 0 as uint }
            func Main() {
                x: uint = GetUInt()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UIntToDouble()
    {
        AssertNoErrors(@"
            func GetUInt(): uint { return 0 as uint }
            func Main() {
                x: uint = GetUInt()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_UIntToDecimal()
    {
        AssertNoErrors(@"
            func GetUInt(): uint { return 0 as uint }
            func Main() {
                x: uint = GetUInt()
                y: decimal = x
            }
        ");
    }

    // ===== long widening =====
    [Fact]
    public void NumericWidening_LongToFloat()
    {
        AssertNoErrors(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_LongToDouble()
    {
        AssertNoErrors(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_LongToDecimal()
    {
        AssertNoErrors(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: decimal = x
            }
        ");
    }

    // ===== ulong widening =====
    [Fact]
    public void NumericWidening_ULongToFloat()
    {
        AssertNoErrors(@"
            func GetULong(): ulong { return 0 as ulong }
            func Main() {
                x: ulong = GetULong()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ULongToDouble()
    {
        AssertNoErrors(@"
            func GetULong(): ulong { return 0 as ulong }
            func Main() {
                x: ulong = GetULong()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_ULongToDecimal()
    {
        AssertNoErrors(@"
            func GetULong(): ulong { return 0 as ulong }
            func Main() {
                x: ulong = GetULong()
                y: decimal = x
            }
        ");
    }

    [Fact]
    public void IntegerLiteralTypes_UnsignedSuffixesAndTargetTypes_NoError()
    {
        AssertNoErrors(@"
            import System.Numerics

            func ReturnUlongMax(): ulong {
                return 0xFFFFFFFFFFFFFFFFUL
            }

            func ReturnUintHighBit(): uint {
                return 0x80000000
            }

            func CountMasked(value: ulong): int {
                return BitOperations.PopCount(value & 0xF0F0F0F0F0F0F0F0UL)
            }

            func CountLiteral(): int {
                return BitOperations.PopCount(0xF0F0F0F0F0F0F0F0UL)
            }
        ");
    }

    // ===== char widening =====
    [Fact]
    public void NumericWidening_CharToInt()
    {
        AssertNoErrors(@"
            func GetChar(): char { return 65 as char }
            func Main() {
                x: char = GetChar()
                y: int = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_CharToLong()
    {
        AssertNoErrors(@"
            func GetChar(): char { return 65 as char }
            func Main() {
                x: char = GetChar()
                y: long = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_CharToFloat()
    {
        AssertNoErrors(@"
            func GetChar(): char { return 65 as char }
            func Main() {
                x: char = GetChar()
                y: float = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_CharToDouble()
    {
        AssertNoErrors(@"
            func GetChar(): char { return 65 as char }
            func Main() {
                x: char = GetChar()
                y: double = x
            }
        ");
    }

    [Fact]
    public void NumericWidening_CharToDecimal()
    {
        AssertNoErrors(@"
            func GetChar(): char { return 65 as char }
            func Main() {
                x: char = GetChar()
                y: decimal = x
            }
        ");
    }

    // ===== float widening =====
    [Fact]
    public void NumericWidening_FloatToDouble()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = 42
                y: float = x
                z: double = y
            }
        ");
    }

    // ===== Narrowing conversions — must be REJECTED =====
    [Fact]
    public void NumericNarrowing_IntToByte_Rejected()
    {
        AssertHasError(@"
            func Main() {
                x: int = 42
                y: byte = x
            }
        ", "is typed as");
    }

    [Fact]
    public void NumericNarrowing_ShortToByte_Rejected()
    {
        AssertHasError(@"
            func GetShort(): short { return 0 as short }
            func Main() {
                x: short = GetShort()
                y: byte = x
            }
        ", "is typed as");
    }

    [Fact]
    public void NumericNarrowing_LongToInt_Rejected()
    {
        AssertHasError(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: int = x
            }
        ", "is typed as");
    }

    [Fact]
    public void NumericNarrowing_DoubleToFloat_Rejected()
    {
        AssertHasError(@"
            func Main() {
                x: double = 3.14
                y: float = x
            }
        ", "is typed as");
    }

    [Fact]
    public void NumericNarrowing_DecimalToDouble_Rejected()
    {
        AssertHasError(@"
            func GetDecimal(): decimal { return 0 as decimal }
            func Main() {
                x: decimal = GetDecimal()
                y: double = x
            }
        ", "is typed as");
    }

    [Fact]
    public void NumericNarrowing_IntToShort_Rejected()
    {
        AssertHasError(@"
            func Main() {
                x: int = 42
                y: short = x
            }
        ", "is typed as");
    }

    [Fact]
    public void NumericNarrowing_DoubleToInt_Rejected()
    {
        AssertHasError(@"
            func Main() {
                x: double = 3.14
                y: int = x
            }
        ", "is typed as");
    }

    [Fact]
    public void NumericNarrowing_FloatToInt_Rejected()
    {
        AssertHasError(@"
            func GetFloat(): float { return 0 as float }
            func Main() {
                x: float = GetFloat()
                y: int = x
            }
        ", "is typed as");
    }

    [Fact]
    public void NumericNarrowing_DecimalToInt_Rejected()
    {
        AssertHasError(@"
            func GetDecimal(): decimal { return 0 as decimal }
            func Main() {
                x: decimal = GetDecimal()
                y: int = x
            }
        ", "is typed as");
    }

    [Fact]
    public void NumericNarrowing_LongToShort_Rejected()
    {
        AssertHasError(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: short = x
            }
        ", "is typed as");
    }

    #endregion

    #region C# Nullability Interop

    private AnalysisResult AnalyzeWithInteropProbe(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens);
        var result = parser.ParseCompilationUnit();
        var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        analyzer.LoadReferencedAssembly(typeof(CSharpNullabilityInteropProbe).Assembly.Location);
        return analyzer.Analyze(result.CompilationUnit!);
    }

    [Fact]
    public void CSharpInterop_ImportsNullableMetadata()
    {
        var result = AnalyzeWithInteropProbe(@"
            import NSharpLang.Tests

            func Main() {
                nonNull := CSharpNullabilityInteropProbe.NonNull(""ok"")
                maybe := CSharpNullabilityInteropProbe.Maybe(""ok"")
                maybeList := CSharpNullabilityInteropProbe.MaybeList()
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.Equal("string", result.SemanticModel.LookupIdentifier("nonNull")?.ToString());
        Assert.Equal("string?", result.SemanticModel.LookupIdentifier("maybe")?.ToString());
        Assert.Equal("List<string?>", result.SemanticModel.LookupIdentifier("maybeList")?.ToString());
    }

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

    [Fact]
    public void CSharpInterop_ImportsFlowNullabilityAttributes()
    {
        var result = AnalyzeWithInteropProbe(@"
            import NSharpLang.Tests

            func Main() {
                maybe := CSharpNullabilityInteropProbe.MaybeNullReturn()
                nonNull := CSharpNullabilityInteropProbe.NotNullReturn()
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.Equal("string?", result.SemanticModel.LookupIdentifier("maybe")?.ToString());
        Assert.Equal("string", result.SemanticModel.LookupIdentifier("nonNull")?.ToString());

        var method = typeof(CSharpNullabilityInteropProbe).GetMethod(nameof(CSharpNullabilityInteropProbe.TryGet))!;
        Assert.Contains("[NotNullWhen(true)]", NullabilityMetadata.FormatParameter(method.GetParameters()[0]));
    }

    [Fact]
    public void CSharpInterop_MissingNullableMetadataIsOblivious()
    {
        var result = AnalyzeWithInteropProbe(@"
            import NSharpLang.Tests

            func Main() {
                value := CSharpObliviousInteropProbe.Identity(""ok"")
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.Equal("string!", result.SemanticModel.LookupIdentifier("value")?.ToString());
    }

    #endregion

    #region Nullable Assignability — Comprehensive Matrix

    // T -> T? (widening) — should work
    [Fact]
    public void NullableWidening_IntToNullableInt()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = 42
                y: int? = x
            }
        ");
    }

    [Fact]
    public void NullableWidening_StringToNullableString()
    {
        AssertNoErrors(@"
            func Main() {
                x: string = ""hello""
                y: string? = x
            }
        ");
    }

    // null -> T? (should work)
    [Fact]
    public void NullableAssignment_NullToNullableInt()
    {
        AssertNoErrors(@"
            func Main() {
                x: int? = null
            }
        ");
    }

    [Fact]
    public void NullableAssignment_NullToNullableString()
    {
        AssertNoErrors(@"
            func Main() {
                x: string? = null
            }
        ");
    }

    // null -> reference type (should work — string is a reference type)
    [Fact]
    public void NullAssignment_NullToString()
    {
        AssertNoErrors(@"
            func Main() {
                x: string = null
            }
        ");
    }

    // null -> value type (should fail)
    [Fact]
    public void NullAssignment_NullToInt_Rejected()
    {
        AssertHasError(@"
            func Main() {
                x: int = null
            }
        ", "is typed as");
    }

    // Inner type widening: int? -> long? (should work)
    [Fact]
    public void NullableWidening_NullableIntToNullableLong()
    {
        AssertNoErrors(@"
            func GetNullableInt(): int? { return null }
            func Main() {
                x: int? = GetNullableInt()
                y: long? = x
            }
        ");
    }

    // T? -> object (boxing — should work)
    [Fact]
    public void NullableWidening_NullableIntToObject()
    {
        AssertNoErrors(@"
            func GetNullableInt(): int? { return null }
            func Main() {
                x: int? = GetNullableInt()
                y: object = x
            }
        ");
    }

    // null -> class type (should work — classes are reference types)
    [Fact]
    public void NullAssignment_NullToClassType()
    {
        AssertNoErrors(@"
            class Foo {
                x: int = 0
            }
            func Main() {
                f: Foo = null
            }
        ");
    }

    #endregion

    #region Flow-Sensitive Null Narrowing

    [Fact]
    public void FlowNarrowing_NullCheckNarrowsToNonNullable()
    {
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                if x != null {
                    y: string = x
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_EqualNullNarrowsInElse()
    {
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                if x == null {
                    // x is still string? here
                } else {
                    y: string = x
                }
            }
        ");
    }

    [Fact]
    public void Nullability_PossibleDereferenceReportsStableError()
    {
        var result = Analyze(@"
            func Main() {
                x: string? = ""hello""
                len := x.Length
            }
        ");

        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.PossibleNullAccess &&
            e.DiagnosticId == "NL905" &&
            e.Severity == ErrorSeverity.Error &&
            e.Message.Contains("Possible null dereference"));
    }

    [Fact]
    public void Nullability_GuardClauseNarrowsAfterEarlyReturn()
    {
        var result = Analyze(@"
            func LengthOrZero(x: string?): int {
                if x == null {
                    return 0
                }

                return x.Length
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.PossibleNullAccess);
    }

    [Fact]
    public void Nullability_StrictFlow_MethodCallOnNullableReceiverErrors()
    {
        var result = Analyze(@"
            class Box {
                func Open(): int { return 1 }
            }

            func Use(b: Box?): int {
                return b.Open()
            }
        ");

        // Calling a method on a possibly-null receiver is a hard error and the
        // squiggle must land on the receiver, not the '.' or member name.
        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.PossibleNullAccess);
        Assert.Equal(ErrorSeverity.Error, error.Severity);
        Assert.Equal("b".Length, error.Length);
        Assert.Contains("`b`", error.Message);
    }

    [Fact]
    public void Nullability_StrictFlow_IndexAccessOnNullableReceiverErrors()
    {
        var result = Analyze(@"
            func First(items: int[]?): int {
                return items[0]
            }
        ");

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.PossibleNullAccess);
        Assert.Equal(ErrorSeverity.Error, error.Severity);
        Assert.Contains("Possible null index", error.Message);
        Assert.Equal("items".Length, error.Length);
    }

    [Fact]
    public void Nullability_StrictFlow_CoalesceFallbackNarrowsToNonNull()
    {
        var result = Analyze(@"
            func Length(s: string?): int {
                t := s ?? ""fallback""
                return t.Length
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.PossibleNullAccess);
    }

    [Fact]
    public void Nullability_StrictFlow_ThrowGuardNarrowsAfterEarlyExit()
    {
        var result = Analyze(@"
            func Length(s: string?): int {
                if s == null {
                    throw ""value was null""
                }

                return s.Length
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.PossibleNullAccess);
    }

    [Fact]
    public void Nullability_StrictFlow_IsPatternNarrowsBoundVariable()
    {
        var result = Analyze(@"
            func Length(s: string?): int {
                if s is string str {
                    return str.Length
                }
                return 0
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.PossibleNullAccess);
    }

    [Fact]
    public void Nullability_StrictFlow_MatchNullArmNarrowsOtherArm()
    {
        var result = Analyze(@"
            func Length(s: string?): int {
                return match s {
                    null => 0,
                    other => other.Length
                }
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.PossibleNullAccess);
    }

    [Fact]
    public void Nullability_StrictFlow_NonNullableTypeNeverErrors()
    {
        var result = Analyze(@"
            class Box {
                func Open(): int { return 1 }
            }

            func Use(b: Box): int {
                return b.Open()
            }
        ");

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.PossibleNullAccess);
    }

    [Fact]
    public void Nullability_StrictFlow_ReassignmentToNonNullClearsNullState()
    {
        var result = Analyze(@"
            func Length(): int {
                x: string? = null
                x = ""now not null""
                return x.Length
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.PossibleNullAccess);
    }

    [Fact]
    public void Nullability_StrictFlow_NullConditionalAccessNeverErrors()
    {
        var result = Analyze(@"
            func Length(s: string?): int? {
                return s?.Length
            }
        ");

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.PossibleNullAccess);
    }

    [Fact]
    public void Nullability_AssignmentInvalidatesPriorGuardFact()
    {
        var result = Analyze(@"
            func Main() {
                x: string? = ""hello""
                if x == null {
                    return
                }

                x = null
                len := x.Length
            }
        ");

        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.PossibleNullAccess &&
            e.Severity == ErrorSeverity.Error &&
            e.Message.Contains("`x` is null"));
    }

    [Fact]
    public void Nullability_StableMemberPathGuardNarrowsValueUse()
    {
        var result = Analyze(@"
            record Person {
                Name: string?
            }

            func Read(p: Person): string {
                if p.Name == null {
                    return """"
                }

                name: string = p.Name
                return name
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.PossibleNullAccess);
    }

    [Fact]
    public void Nullability_LoopConditionNarrowsBody()
    {
        var result = Analyze(@"
            func Main() {
                x: string? = ""hello""
                while x != null {
                    len := x.Length
                    x = null
                }
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.PossibleNullAccess);
    }

    [Fact]
    public void MustExpression_UnwrapsNullableToInnerType()
    {
        AssertNoErrors(@"
            func Take(value: int): int { return value }
            func Main(input: int?): int {
                return Take(must input)
            }
        ");
    }

    [Fact]
    public void MustExpression_RedundantAfterHasValueGuard_Errors()
    {
        var result = Analyze(@"
            func Main(input: int?): int {
                if input.HasValue {
                    return must input
                }
                return 0
            }
        ");

        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.NullabilityWarning
            && e.DiagnosticId == "NL907"
            && e.Severity == ErrorSeverity.Error
            && e.Message.Contains("redundant"));
    }

    [Fact]
    public void NullableHasValueGuard_AllowsValueAccessWithoutUnsafeWarning()
    {
        var result = Analyze(@"
            func Main(input: int?): int {
                if input.HasValue {
                    return input.Value
                }
                return 0
            }
        ");

        Assert.False(result.HasErrors, string.Join(", ", result.Errors.Select(e => e.Message)));
        Assert.DoesNotContain(result.Errors, e =>
            e.Code == ErrorCode.NullabilityWarning
            && e.Message.Contains(".Value"));
    }

    [Fact]
    public void NullableValueAccess_UnguardedIsAnError()
    {
        var result = Analyze(@"
            func Main(input: int?): int {
                return input.Value
            }
        ");

        Assert.True(result.HasErrors);
        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.NullabilityWarning
            && e.Severity == ErrorSeverity.Error
            && e.Message.Contains(".Value"));
    }

    [Fact]
    public void NullableMatch_BindsPresentArmAsInnerType()
    {
        AssertNoErrors(@"
            func Main(input: int?): int {
                return match input {
                    null => 0,
                    value => value + 1
                }
            }
        ");
    }

    [Fact]
    public void NullableMatch_MissingNullCoverageErrors()
    {
        var result = Analyze(@"
            func Main(input: int?): int {
                return match input {
                    value => value + 1
                }
            }
        ");

        Assert.True(result.HasErrors, "Expected missing nullable match coverage to be an error");
        Assert.Contains(result.Errors, e =>
            e.Code == ErrorCode.NonExhaustiveMatch
            && e.Message.Contains("null"));
    }

    #endregion

    #region Enum Exhaustiveness

    [Fact]
    public void EnumExhaustiveness_AllCasesCovered_NoError()
    {
        AssertNoErrors(@"
            enum Status {
                Active = 0,
                Inactive = 1
            }
            func Main() {
                s: Status = Status.Active
                result := match s {
                    Status.Active => ""on"",
                    Status.Inactive => ""off""
                }
            }
        ");
    }

    [Fact]
    public void EnumExhaustiveness_WildcardCovers_NoError()
    {
        AssertNoErrors(@"
            enum Status {
                Active = 0,
                Inactive = 1,
                Pending = 2
            }
            func Main() {
                s: Status = Status.Active
                result := match s {
                    Status.Active => ""on"",
                    _ => ""other""
                }
            }
        ");
    }

    [Fact]
    public void EnumExhaustiveness_MissingCase_Error()
    {
        AssertHasError(@"
            enum Status {
                Active = 0,
                Inactive = 1,
                Pending = 2
            }
            func Main() {
                s: Status = Status.Active
                result := match s {
                    Status.Active => ""on"",
                    Status.Inactive => ""off""
                }
            }
        ", "doesn't cover all");
    }

    [Fact]
    public void EnumToInt_ImplicitlyAssignable()
    {
        AssertNoErrors(@"
            enum Priority {
                Low = 0,
                High = 1
            }
            func Main() {
                p := Priority.Low
                n: int = p
            }
        ");
    }

    #endregion

    #region Unknown Type Kinds

    [Fact]
    public void UnknownKind_ErrorRecovery_SuppressesCascading()
    {
        // Using an undefined function should produce ONE error, not cascading errors
        var result = Analyze(@"
            func Main() {
                x := undefinedFunction()
                y: int = x
            }
        ");
        // Should have error for undefined function but NOT for x assignment
        Assert.True(result.HasErrors);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
    }

    #endregion

    // ===================================================================
    // Type System Hardening: Phase 2 — Flow Typing, Structural Delegates,
    // Constraint Validation, Enum Nominality
    // ===================================================================

    #region Flow Narrowing: && Chaining

    [Fact]
    public void FlowNarrowing_AndChain_BothNullChecks()
    {
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                y: int? = 42
                if x != null && y != null {
                    a: string = x
                    b: int = y
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_AndChain_NullCheckWithCondition()
    {
        // x != null narrows x; the second operand doesn't produce narrowings but shouldn't break
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                if x != null && true {
                    a: string = x
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_AndChain_NoElseNarrowing()
    {
        // else of && is !a || !b — can't narrow either variable
        AssertHasError(@"
            func Main() {
                x: string? = ""hello""
                y: int? = 42
                if x != null && y != null {
                    a: string = x
                } else {
                    b: string = x
                }
            }
        ", "is typed as");
    }

    #endregion

    #region Flow Narrowing: Is-Type Patterns

    [Fact]
    public void FlowNarrowing_IsPattern_BindsVariable()
    {
        // if x is Dog d — should declare d with type Dog in then-branch
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func TakeAnimal(a: Animal) {
                if a is Dog d {
                    name: string = d.Name
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_IsPattern_NarrowsWithoutBinding()
    {
        // if x is Dog — should narrow x to Dog in then-branch (no new variable)
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func TakeAnimal(a: Animal) {
                if a is Dog {
                    dog: Dog = a
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_IsPattern_WithAndChain()
    {
        // Combine is-pattern with && null check on separate variables
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func TakeAnimal(a: Animal, x: string?) {
                if a is Dog && x != null {
                    dog: Dog = a
                    s: string = x
                }
            }
        ");
    }

    #endregion

    #region Flow Narrowing: Or-Chain

    [Fact]
    public void FlowNarrowing_OrChain_NarrowsInElseBranch()
    {
        // if x == null || y == null → both non-null in else branch
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                y: int? = 42
                if x == null || y == null {
                    // can't narrow here — one or the other failed
                } else {
                    a: string = x
                    b: int = y
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_OrChain_NoThenNarrowing()
    {
        // then-branch of || cannot narrow (only one side needs to be true)
        AssertHasError(@"
            func Main() {
                x: string? = ""hello""
                y: int? = 42
                if x == null || y == null {
                    a: string = x
                }
            }
        ", "is typed as");
    }

    [Fact]
    public void FlowNarrowing_OrChain_TripleNullCheck()
    {
        // Three null checks combined with || — all narrow in else
        AssertNoErrors(@"
            func Main() {
                x: string? = ""a""
                y: string? = ""b""
                z: string? = ""c""
                if x == null || y == null || z == null {
                    // can't narrow
                } else {
                    a: string = x
                    b: string = y
                    c: string = z
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_OrChain_RhsSeesLeftElseNarrowing()
    {
        // x == null || x.Length > 0 — RHS should see x as non-nullable (short-circuit: left was false → x != null)
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                if x == null || x.Length > 0 {
                    // can narrow x in then body only if both sides hold,
                    // but the important thing is no error on x.Length
                }
            }
        ");
    }

    #endregion

    #region Flow Narrowing: And-Chain RHS Narrowing

    [Fact]
    public void FlowNarrowing_AndChain_RhsSeesLeftNarrowing()
    {
        // x != null && x.Length > 0 — the RHS should see x as non-nullable
        AssertNoErrors(@"
            func Main() {
                x: string? = ""hello""
                if x != null && x.Length > 0 {
                    s: string = x
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_AndChain_RhsSeesIsPatternNarrowing()
    {
        // a is Dog && a.Breed == "poodle" — RHS should see a as Dog (accessing Dog.Breed)
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func TakeAnimal(a: Animal) {
                if a is Dog && a.Breed == ""poodle"" {
                    breed: string = a.Breed
                }
            }
        ");
    }

    #endregion

    #region Flow Narrowing: Same-Symbol Intersection

    [Fact]
    public void FlowNarrowing_SameSymbol_KeepsMostSpecific()
    {
        // if a is Dog && a is Animal → should keep Dog (more specific), not Animal
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func TakeAnimal(a: Animal) {
                if a is Dog && a is Animal {
                    d: Dog = a
                }
            }
        ");
    }

    [Fact]
    public void FlowNarrowing_SameSymbol_ReversedOrder_KeepsMostSpecific()
    {
        // if a is Animal && a is Dog → should still keep Dog (more specific)
        AssertNoErrors(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func TakeAnimal(a: Animal) {
                if a is Animal && a is Dog {
                    d: Dog = a
                }
            }
        ");
    }

    #endregion

    #region Lambda-Delegate Structural Validation

    [Fact]
    public void Lambda_Delegate_CorrectParamCount_NoError()
    {
        AssertNoErrors(@"
            func Apply(f: Func<int, string>, x: int): string {
                return f(x)
            }
            func Main() {
                result := Apply((x) => ""hello"", 42)
            }
        ");
    }

    [Fact]
    public void Lambda_Delegate_WrongParamCount_Error()
    {
        // Lambda with 2 params assigned to Func<int, string> (1 param + return type)
        AssertHasError(@"
            func Main() {
                let f: Func<int, string> = (x, y) => ""hello""
            }
        ", "is typed as");
    }

    [Fact]
    public void Lambda_Delegate_ZeroParams_MatchesFunc()
    {
        AssertNoErrors(@"
            func RunIt(f: Func<int>): int {
                return f()
            }
            func Main() {
                result := RunIt(() => 42)
            }
        ");
    }

    #endregion

    #region Generic Constraint Validation

    [Fact]
    public void GenericConstraint_Satisfied_NoError()
    {
        AssertNoErrors(@"
            interface IComparable {
                func CompareTo(other: object): int
            }
            class MyInt : IComparable {
                func CompareTo(other: object): int {
                    return 0
                }
            }
            func Max<T>(a: T, b: T): T where T : IComparable {
                return a
            }
            func Main() {
                result := Max(new MyInt(), new MyInt())
            }
        ");
    }

    [Fact]
    public void GenericConstraint_Violated_Error()
    {
        AssertHasError(@"
            interface IComparable {
                func CompareTo(other: object): int
            }
            class Plain {
            }
            func Max<T>(a: T, b: T): T where T : IComparable {
                return a
            }
            func Main() {
                result := Max(new Plain(), new Plain())
            }
        ", "does not implement");
    }

    // --- Circular constraint dependencies (mirrors C#'s CS0454): the CLR refuses the metadata at load
    // and the emitter's base-chain walks would spin forever, so the analyzer must reject them. ---

    [Fact]
    public void GenericConstraint_CircularSelf_Errors()
    {
        AssertHasError(@"
            func Identity<T>(value: T): T where T : T {
                return value
            }
        ", "circular constraint dependency");
    }

    [Fact]
    public void GenericConstraint_CircularMutual_Errors()
    {
        AssertHasError(@"
            func Pick<T, U>(a: T, b: U): T where T : U where U : T {
                return a
            }
        ", "circular constraint dependency");
    }

    [Fact]
    public void GenericConstraint_FBounded_NoError()
    {
        // F-bounded (`where T: IComparable<T>`) is NOT circular — only bare type-parameter cycles are.
        AssertNoErrors(@"
            interface IComparable<T> {
                func CompareTo(other: T): int
            }
            func Max<T>(a: T, b: T): T where T : IComparable<T> {
                return a
            }
        ");
    }

    [Fact]
    public void GenericConstraint_TypeParamChain_NoError()
    {
        AssertNoErrors(@"
            func Pick<T, U>(a: T, b: U): T where T : U where U : class {
                return a
            }
        ");
    }

    // --- Special constraint tests ---

    [Fact]
    public void SpecialConstraint_Class_WithStringArg_NoError()
    {
        AssertNoErrors(@"
            func Identity<T>(value: T): T where T : class {
                return value
            }
            func Main() {
                result := Identity(""hello"")
            }
        ");
    }

    [Fact]
    public void SpecialConstraint_Class_WithIntArg_Error()
    {
        AssertHasError(@"
            func Identity<T>(value: T): T where T : class {
                return value
            }
            func Main() {
                result := Identity(42)
            }
        ", "is a value type, but type parameter");
    }

    [Fact]
    public void SpecialConstraint_Struct_WithIntArg_NoError()
    {
        AssertNoErrors(@"
            func Box<T>(value: T): T where T : struct {
                return value
            }
            func Main() {
                result := Box(42)
            }
        ");
    }

    [Fact]
    public void SpecialConstraint_Struct_WithStringArg_Error()
    {
        AssertHasError(@"
            func Box<T>(value: T): T where T : struct {
                return value
            }
            func Main() {
                result := Box(""hello"")
            }
        ", "is not a non-nullable value type");
    }

    [Fact]
    public void SpecialConstraint_New_WithDefaultCtorClass_NoError()
    {
        AssertNoErrors(@"
            class Widget {
            }
            func Create<T>(dummy: T): T where T : new() {
                return dummy
            }
            func Main() {
                w := new Widget()
                result := Create(w)
            }
        ");
    }

    [Fact]
    public void SpecialConstraint_New_WithParameterizedCtorOnly_Error()
    {
        // A record with primary constructor parameters has no parameterless constructor.
        // Use explicit type argument to ensure T is resolved to the record type.
        AssertHasError(@"
            record Point(X: int, Y: int)
            func Create<T>(dummy: T): T where T : new() {
                return dummy
            }
            func Main() {
                p := new Point(1, 2)
                result := Create<Point>(p)
            }
        ", "has no parameterless constructor");
    }

    [Fact]
    public void SpecialConstraint_ClassAndStruct_MutuallyExclusive_ParseError()
    {
        AssertHasParseError(@"
            func Bad<T>(value: T): T where T : class, struct {
                return value
            }
        ", "mutually exclusive");
    }

    [Fact]
    public void SpecialConstraint_Class_WithInterface_WithStringArg_NoError()
    {
        // string satisfies both 'class' and IComparable
        AssertNoErrors(@"
            interface IComparable {
                func CompareTo(other: object): int
            }
            class MyString : IComparable {
                func CompareTo(other: object): int { return 0 }
            }
            func Process<T>(value: T): T where T : class, IComparable {
                return value
            }
            func Main() {
                ms := new MyString()
                result := Process(ms)
            }
        ");
    }

    [Fact]
    public void SpecialConstraint_New_WithStructArg_NoError()
    {
        // Structs always have a parameterless constructor
        AssertNoErrors(@"
            struct Point {
                X: int
                Y: int
            }
            func Create<T>(dummy: T): T where T : new() {
                return dummy
            }
            func Main() {
                p := new Point()
                result := Create(p)
            }
        ");
    }

    [Fact]
    public void SpecialConstraint_Class_WithRecordArg_NoError()
    {
        // Records are reference types and satisfy 'class' constraint
        AssertNoErrors(@"
            record Person(Name: string, Age: int)
            func Process<T>(value: T): T where T : class {
                return value
            }
            func Main() {
                p := new Person(""Alice"", 30)
                result := Process(p)
            }
        ");
    }

    [Fact]
    public void SpecialConstraint_StructAndNew_MutuallyExclusive_ParseError()
    {
        // C# forbids struct + new() because struct already implies new()
        AssertHasParseError(@"
            func Bad<T>(value: T): T where T : struct, new() {
                return value
            }
        ", "struct");
    }

    [Fact]
    public void SpecialConstraint_New_WithPrimaryCtorClass_Error()
    {
        // A class with a primary constructor (suppresses implicit default ctor)
        // should NOT satisfy new()
        AssertHasError(@"
            class RequiresPrimary(X: int) { }
            func Create<T>(dummy: T): T where T : new() {
                return dummy
            }
            func Main() {
                r := new RequiresPrimary(1)
                result := Create<RequiresPrimary>(r)
            }
        ", "has no parameterless constructor");
    }

    [Fact]
    public void SpecialConstraint_New_WithRecordStructArg_NoError()
    {
        // Record structs always have an implicit parameterless constructor
        AssertNoErrors(@"
            record struct Size(Width: int, Height: int)
            func Create<T>(dummy: T): T where T : new() {
                return dummy
            }
            func Main() {
                s := new Size(10, 20)
                result := Create<Size>(s)
            }
        ");
    }

    #endregion

    #region String-to-Enum Rejection

    [Fact]
    public void StringToEnum_Rejected()
    {
        // Assigning a string literal to an enum type should be rejected
        AssertHasError(@"
            enum Color {
                Red = 0,
                Blue = 1
            }
            func Main() {
                c: Color = ""red""
            }
        ", "is typed as");
    }

    [Fact]
    public void IntToEnum_Rejected()
    {
        // Assigning an int literal to an enum type should be rejected
        AssertHasError(@"
            enum Color {
                Red = 0,
                Blue = 1
            }
            func Main() {
                c: Color = 0
            }
        ", "is typed as");
    }

    [Fact]
    public void EnumToString_Allowed()
    {
        // Enum to its underlying type is allowed
        AssertNoErrors(@"
            enum Color {
                Red = 0,
                Blue = 1
            }
            func Main() {
                c := Color.Red
                n: int = c
            }
        ");
    }

    [Fact]
    public void StringEnumToString_Allowed()
    {
        // String enums are inferred from the first member value being a string literal
        AssertNoErrors(@"
            enum Color {
                Red = ""red"",
                Blue = ""blue""
            }
            func Main() {
                c := Color.Red
                s: string = c
            }
        ");
    }

    [Fact]
    public void StringToStringEnum_Rejected()
    {
        AssertHasError(@"
            enum Color {
                Red = ""red"",
                Blue = ""blue""
            }
            func Main() {
                c: Color = ""red""
            }
        ", "is typed as");
    }

    [Fact]
    public void StringEnumAsParameterType_Allowed()
    {
        AssertNoErrors(@"
            enum Status: string {
                Active = ""active"",
                Inactive = ""inactive""
            }
            func Process(s: Status): string {
                return s
            }
        ");
    }

    [Fact]
    public void StringEnumAsReturnType_Allowed()
    {
        AssertNoErrors(@"
            enum Status: string {
                Active = ""active"",
                Inactive = ""inactive""
            }
            func GetDefault(): Status {
                return Status.Active
            }
        ");
    }

    [Fact]
    public void StringEnumAsRecordProperty_Allowed()
    {
        AssertNoErrors(@"
            enum Status: string {
                Active = ""active"",
                Inactive = ""inactive""
            }
            record Item {
                CurrentStatus: Status
            }
        ");
    }

    #endregion

    [Fact]
    public void SetupSymbols_VisibleInTestBodies()
    {
        // Setup variables must be available in test scopes (not unresolved)
        AssertNoErrors(@"
            setup {
                count := 42
            }

            test ""should see setup variable"" {
                assert count == 42
            }
        ");
    }

    #region Overload Resolution — Betterness Rules

    [Fact]
    public void OverloadResolution_IntBeatsLong_WithIntArg()
    {
        // C# spec 12.6.4: Exact match beats implicit conversion
        AssertNoErrors(@"
            func Foo(x: int): int { return x }
            func Foo(x: long): long { return x }
            func Main() {
                r := Foo(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_IntBeatsObject_WithIntArg()
    {
        // More specific type beats less specific
        AssertNoErrors(@"
            func Foo(x: int): int { return x }
            func Foo(x: object) { }
            func Main() {
                Foo(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_TwoParams_FirstExactWins()
    {
        // Foo(int, int) beats Foo(int, long) when both args are int
        AssertNoErrors(@"
            func Foo(x: int, y: int): int { return x }
            func Foo(x: int, y: long): long { return x as long }
            func Main() {
                r := Foo(1, 2)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_NonParamsBeatsParams()
    {
        // Non-params overload wins when both match for single argument
        AssertNoErrors(@"
            func Foo(x: int): int { return x }
            func Foo(params x: int[]): int { return 0 }
            func Main() {
                r := Foo(1)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ImplicitNumeric_IntToLong_Works()
    {
        // When only long overload exists, int should implicitly widen
        AssertNoErrors(@"
            func Process(x: long): long { return x }
            func Main() {
                r := Process(42)
            }
        ");
    }

    [Fact]
    public void OverloadResolution_ImplicitNumeric_IntToDouble_Works()
    {
        // When only double overload exists, int should implicitly widen
        AssertNoErrors(@"
            func Process(x: double): double { return x }
            func Main() {
                r := Process(42)
            }
        ");
    }

    #endregion

    #region Missing Diagnostics — Type System Edge Cases

    [Fact]
    public void VoidUsedAsValue_Rejected()
    {
        // Assigning the result of a void function to a variable should be an error
        AssertHasError(@"
            func DoStuff() { }
            func Main() {
                x := DoStuff()
            }
        ", "void");
    }

    [Fact]
    public void DuplicateParameterNames_Rejected()
    {
        // Two parameters with the same name should be an error
        AssertHasError(@"
            func Dup(x: int, x: string): int {
                return 0
            }
        ", "already declared");
    }

    [Fact]
    public void NullAssignment_NullToInterfaceType()
    {
        // null should be assignable to interface types (reference types)
        AssertNoErrors(@"
            interface IFoo {
                func Bar(): int
            }
            func Main() {
                x: IFoo = null
            }
        ");
    }

    [Fact]
    public void NullAssignment_NullToArrayType()
    {
        // null should be assignable to array types (reference types)
        AssertNoErrors(@"
            func Main() {
                x: int[] = null
            }
        ");
    }

    [Fact]
    public void NullAssignment_NullToBool_Rejected()
    {
        // null should NOT be assignable to value types
        AssertHasError(@"
            func Main() {
                x: bool = null
            }
        ", "is typed as");
    }

    [Fact]
    public void NullAssignment_NullToDouble_Rejected()
    {
        // null should NOT be assignable to numeric value types
        AssertHasError(@"
            func Main() {
                x: double = null
            }
        ", "is typed as");
    }

    [Fact]
    public void NullableWidening_IntNullableToLongNullable()
    {
        // int? -> long? via inner type widening should work
        AssertNoErrors(@"
            func GetNullableInt(): int? { return null }
            func Main() {
                x: int? = GetNullableInt()
                y: long? = x
            }
        ");
    }

    [Fact]
    public void NullableWidening_ByteNullableToIntNullable()
    {
        // byte? -> int? via inner type widening
        AssertNoErrors(@"
            func GetNullableByte(): byte? { return null }
            func Main() {
                x: byte? = GetNullableByte()
                y: int? = x
            }
        ");
    }

    [Fact]
    public void NullableWidening_FloatNullableToDoubleNullable()
    {
        // float? -> double? via inner type widening
        AssertNoErrors(@"
            func GetNullableFloat(): float? { return null }
            func Main() {
                x: float? = GetNullableFloat()
                y: double? = x
            }
        ");
    }

    [Fact]
    public void NullableNarrowing_LongNullableToIntNullable_Rejected()
    {
        // long? -> int? should fail (narrowing)
        AssertHasError(@"
            func GetNullableLong(): long? { return null }
            func Main() {
                x: long? = GetNullableLong()
                y: int? = x
            }
        ", "is typed as");
    }

    [Fact]
    public void NullAssignment_NullToRecordStruct_Rejected()
    {
        // record struct is a value type — null should NOT be assignable
        AssertHasError(@"
            record struct Point {
                x: int = 0
                y: int = 0
            }
            func Main() {
                p: Point = null
            }
        ", "is typed as");
    }

    [Fact]
    public void NullAssignment_NullToRecord_Allowed()
    {
        // record (not struct) is a reference type — null should be assignable
        AssertNoErrors(@"
            record Person {
                name: string = ""unknown""
            }
            func Main() {
                p: Person = null
            }
        ");
    }

    [Fact]
    public void NullAssignment_NullToStruct_Rejected()
    {
        // struct is a value type — null should NOT be assignable
        AssertHasError(@"
            struct Point {
                x: int = 0
                y: int = 0
            }
            func Main() {
                p: Point = null
            }
        ", "is typed as");
    }

    [Fact]
    public void NullAssignment_NullToUnionType()
    {
        // union types are reference types — null should be assignable
        AssertNoErrors(@"
            union Shape {
                Circle { radius: double }
                Rectangle { width: double, height: double }
            }
            func Main() {
                s: Shape = null
            }
        ");
    }

    #endregion

    #region Impossible Pattern Errors

    private void AssertHasStrictError(string source, string expectedMessage)
    {
        var result = Analyze(source);
        Assert.Contains(result.Errors,
            e => e.Severity == NSharpLang.Compiler.ErrorSeverity.Error
              && e.Message.Contains(expectedMessage));
    }

    private void AssertNoWarning(string source, string warningMessage)
    {
        var result = Analyze(source);
        Assert.DoesNotContain(result.Errors,
            e => e.Message.Contains(warningMessage));
    }

    [Fact]
    public void ImpossiblePattern_IntIsString_ProducesError()
    {
        // int is a value type; string is a different reference type — can never match
        AssertHasStrictError(@"
            func Main() {
                x: int = 42
                result := x is string
            }
        ", "is always false");
    }

    [Fact]
    public void ImpossiblePattern_BoolIsInt_ProducesError()
    {
        // bool and int are unrelated value types — can never match
        AssertHasStrictError(@"
            func Main() {
                flag: bool = true
                result := flag is int
            }
        ", "is always false");
    }

    [Fact]
    public void ImpossiblePattern_IntIsInt_NoWarning()
    {
        // Exact same type — trivially possible (always matches)
        AssertNoWarning(@"
            func Main() {
                x: int = 42
                result := x is int
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_ClassIsInterface_NoWarning()
    {
        // Any class could implement an interface — always possible at runtime
        AssertNoWarning(@"
            interface IShape {
                func Area(): double
            }
            class Circle {
                Radius: double
                func Area(): double { return 3.14 * Radius * Radius }
            }
            func Main() {
                c: Circle = new Circle { Radius: 1.0 }
                result := c is IShape
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_BaseClassIsDerived_NoWarning()
    {
        // Downcasting from base to derived is a valid runtime check
        AssertNoWarning(@"
            class Animal {
                Name: string
            }
            class Dog : Animal {
                Breed: string
            }
            func Main() {
                a: Animal = new Dog { Name: ""Rex"", Breed: ""Lab"" }
                result := a is Dog
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_SealedClassUnrelated_ProducesError()
    {
        // A sealed class can never be a subtype of an unrelated class
        AssertHasStrictError(@"
            sealed class Cat {
                Name: string
            }
            class Dog {
                Name: string
            }
            func Main() {
                c: Cat = new Cat { Name: ""Whiskers"" }
                result := c is Dog
            }
        ", "is always false");
    }

    [Fact]
    public void ImpossiblePattern_ObjectIsString_NoWarning()
    {
        // object can be anything — unboxing/downcasting string is valid
        AssertNoWarning(@"
            func Main() {
                obj: object = ""hello""
                result := obj is string
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_UnionTypeIsCase_NoWarning()
    {
        // Pattern matching union cases is always valid
        AssertNoWarning(@"
            union Shape {
                Circle { radius: double }
                Rectangle { width: double, height: double }
            }
            func Main() {
                s: Shape = new Shape.Circle { radius: 1.0 }
                x := match s {
                    Shape.Circle { radius } => radius,
                    _ => 0.0
                }
            }
        ", "will never");
    }

    [Fact]
    public void ImpossiblePattern_IsExpression_IntIsString_ProducesError()
    {
        // if 42 is string s — int can never be string
        AssertHasStrictError(@"
            func Main() {
                n: int = 42
                if n is string s {
                    len: int = s.Length
                }
            }
        ", "is always false");
    }

    [Fact]
    public void ImpossiblePattern_IsExpression_ObjectIsString_NoWarning()
    {
        // obj is string s — object can always be checked at runtime
        AssertNoWarning(@"
            func Main() {
                obj: object = ""hello""
                if obj is string s {
                    len: int = s.Length
                }
            }
        ", "will never succeed");
    }

    [Fact]
    public void ImpossiblePattern_IsExpression_IntIsDouble_Error()
    {
        // The `is` operator is a CLR runtime type-identity test (isinst), NOT a conversion.
        // int is double is always false at runtime, even though int->double is an implicit conversion.
        AssertHasStrictError(@"
            func Main() {
                x: int = 5
                result := x is double
            }
        ", "is always false");
    }

    #endregion

    #region Numeric Narrowing Cast Suggestions

    // These tests verify that when a numeric narrowing error occurs, the error's ContextualHint
    // contains explicit cast syntax (e.g. "(int)value") to help the developer fix the issue.

    [Fact]
    public void NarrowingSuggestion_LongToInt_SuggestsCast()
    {
        // long → int: should suggest explicit (int) cast
        AssertHasHint(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: int = x
            }
        ", "(int)value");
    }

    [Fact]
    public void NarrowingSuggestion_DoubleToFloat_SuggestsCast()
    {
        // double → float: should suggest explicit (float) cast
        AssertHasHint(@"
            func Main() {
                x: double = 3.14
                y: float = x
            }
        ", "(float)value");
    }

    [Fact]
    public void NarrowingSuggestion_FunctionArgument_LongToInt_SuggestsCast()
    {
        // Passing a long argument to a function expecting int should include cast suggestion
        AssertHasHint(@"
            func Foo(x: int) {}
            func GetLong(): long { return 0 as long }
            func Main() {
                v: long = GetLong()
                Foo(v)
            }
        ", "(int)value");
    }

    [Fact]
    public void NarrowingSuggestion_ReturnDoubleFromIntFunc_SuggestsCast()
    {
        // Returning double from a function declared to return int should suggest cast
        AssertHasHint(@"
            func GetDouble(): double { return 0.0 }
            func Compute(): int {
                d: double = GetDouble()
                return d
            }
        ", "(int)value");
    }

    [Fact]
    public void NarrowingSuggestion_IntToByte_LiteralTooLarge_SuggestsCast()
    {
        // Assigning an int literal (300) to byte: int → byte narrowing should suggest cast
        AssertHasHint(@"
            func Main() {
                x: int = 300
                y: byte = x
            }
        ", "(byte)value");
    }

    [Fact]
    public void NarrowingSuggestion_IntToInt_NoError()
    {
        // int to int: valid assignment, no error and no narrowing suggestion needed
        AssertNoErrors(@"
            func Main() {
                x: int = 42
            }
        ");
    }

    [Fact]
    public void NarrowingSuggestion_StringToInt_NotNumericNarrowing()
    {
        // string → int: error, but NOT a numeric narrowing suggestion — should use the
        // string-specific hint (int.Parse / int.TryParse), not a cast suggestion
        var result = AnalyzeWithSource(@"
            func Main() {
                x: string = ""hello""
                y: int = x
            }
        ");
        Assert.True(result.HasErrors, "Expected errors but got none");
        var typeMismatchErrors = result.Errors.Where(e => e.ContextualHint != null).ToList();
        // Should NOT suggest a numeric cast — should suggest int.Parse instead
        Assert.Contains(typeMismatchErrors, e => e.ContextualHint!.Contains("int.Parse"));
        Assert.DoesNotContain(typeMismatchErrors, e => e.ContextualHint!.Contains("(int)value"));
    }

    [Fact]
    public void NarrowingSuggestion_LongToShort_SuggestsCast()
    {
        // long → short: should suggest explicit (short) cast
        AssertHasHint(@"
            func GetLong(): long { return 0 as long }
            func Main() {
                x: long = GetLong()
                y: short = x
            }
        ", "(short)value");
    }

    #endregion

    #region Default Expression

    [Fact]
    public void DefaultExpression_IntVariable_NoErrors()
    {
        AssertNoErrors(@"
            func Main() {
                x: int = default
            }
        ");
    }

    [Fact]
    public void DefaultExpression_StringVariable_NoErrors()
    {
        AssertNoErrors(@"
            func Main() {
                s: string = default
            }
        ");
    }

    [Fact]
    public void DefaultExpression_ReturnFromIntFunction_NoErrors()
    {
        AssertNoErrors(@"
            func Foo(): int {
                return default
            }
        ");
    }


    [Fact]
    public void DefaultExpression_NoTypeContext_ReportsError()
    {
        var result = Analyze("""
            func Main() {
                x := default
            }
            """);

        var diagnostic = Assert.Single(result.Errors,
            error => error.Message.Contains("can't figure out what type 'default' should be"));
        Assert.Equal(ErrorCode.CannotInferType, diagnostic.Code);
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(10, diagnostic.Column);
        Assert.Equal("default".Length, diagnostic.Length);
    }

    [Fact]
    public void TargetTypedNew_NoTypeContext_ReportsError()
    {
        var result = Analyze("""
            func Main() {
                x := new()
            }
            """);

        var diagnostic = Assert.Single(result.Errors,
            error => error.Message.Contains("what type 'new()' should create"));
        Assert.Equal(ErrorCode.CannotInferType, diagnostic.Code);
        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(10, diagnostic.Column);
        Assert.Equal("new".Length, diagnostic.Length);
    }

    [Fact]
    public void TargetTypedNew_ExpressionStatementNoTypeContext_ReportsError()
    {
        var result = Analyze("""
            func Main() {
                new()
            }
            """);

        var diagnostic = Assert.Single(result.Errors,
            error => error.Message.Contains("what type 'new()' should create"));
        Assert.Equal(ErrorCode.CannotInferType, diagnostic.Code);
        Assert.Equal("new".Length, diagnostic.Length);
    }

    [Fact]
    public void AnonymousObjectCreation_NoTypeContext_IsAllowed()
    {
        AssertNoErrors("""
            func Main() {
                value := new { Name: "Ada", Count: 1 }
            }
            """);
    }

    [Fact]
    public void DefaultExpression_FunctionArgument_NoErrors()
    {
        AssertNoErrors(@"
            func Bar(x: int) {}
            func Main() {
                Bar(default)
            }
        ");
    }

    [Fact]
    public void DefaultExpression_NullableIntVariable_NoErrors()
    {
        AssertNoErrors(@"
            func Main() {
                x: int? = default
            }
        ");
    }

    [Fact]
    public void DefaultExpression_BoolVariable_NoErrors()
    {
        AssertNoErrors(@"
            func Main() {
                x: bool = default
            }
        ");
    }

    [Fact]
    public void DefaultExpression_DoubleVariable_NoErrors()
    {
        AssertNoErrors(@"
            func Main() {
                x: double = default
            }
        ");
    }

    [Fact]
    public void DefaultExpression_ReturnFromBoolFunction_NoErrors()
    {
        AssertNoErrors(@"
            func IsReady(): bool {
                return default
            }
        ");
    }

    [Fact]
    public void DefaultExpression_FieldInitializer_NoErrors()
    {
        AssertNoErrors(@"
            class Counter {
                count: int = default
            }
        ");
    }

    #endregion

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
    public void NullNotAssignableToInt()
    {
        // null should NOT be assignable to int (value type)
        AssertHasError(@"
            func Main() {
                x: int = null
            }
        ", "is typed as");
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
    public void Newtype_NotAssignableFromUnderlying()
    {
        AssertHasError(@"
            type UserId = newtype int

            func Main() {
                let id: UserId = 42
            }
        ", "is typed as 'UserId', but the value is 'int'");
    }

    [Fact]
    public void Newtype_NotAssignableToUnderlying()
    {
        AssertHasError(@"
            type UserId = newtype int

            func Main() {
                id := UserId(42)
                let raw: int = id
            }
        ", "is typed as 'int', but the value is 'UserId'");
    }

    [Fact]
    public void Newtype_ConstructionWithWrongType_Error()
    {
        AssertHasError(@"
            type UserId = newtype int

            func Main() {
                id := UserId(""hello"")
            }
        ", "not assignable");
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

    [Fact]
    public void Newtype_DifferentNewtypeNotAssignable()
    {
        AssertHasError(@"
            type UserId = newtype int
            type OrderId = newtype int

            func Main() {
                userId := UserId(1)
                let orderId: OrderId = userId
            }
        ", "is typed as 'OrderId', but the value is 'UserId'");
    }

    [Fact]
    public void DuplicateSetupBlock_ReportsError()
    {
        AssertHasError(@"
setup {
    x := 1
}

setup {
    y := 2
}

test ""should work"" {
    assert true
}
        ", "Only one setup block is allowed per test file");
    }

    [Fact]
    public void DuplicateTeardownBlock_ReportsError()
    {
        AssertHasError(@"
teardown {
    Cleanup()
}

teardown {
    Cleanup2()
}

test ""should work"" {
    assert true
}
        ", "Only one teardown block is allowed per test file");
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

    [Theory]
    [InlineData("[System.Obsolete(BuildMessage())]", "call")]
    [InlineData("[System.Obsolete(\"v\" + \"1\")]", "+")]
    [InlineData("[System.Obsolete(!\"no\")]", "!")]
    public void AttributeArguments_UnsupportedExpressions_ReportConstantRequired(
        string attribute,
        string expectedMessage)
    {
        var result = AnalyzeWithSource($$"""
            import System

            {{attribute}}
            func Bad(): int {
                return 0
            }

            func BuildMessage(): string {
                return "bad"
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ConstantRequired);
        Assert.Contains(expectedMessage, error.Message);
        Assert.Contains("compile-time constants", error.Message);
        Assert.Contains("literal", error.Suggestion);
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
    public void TableDrivenTestCases_UnsupportedExpressions_ReportConstantRequired()
    {
        var result = AnalyzeWithSource("""
            func build(): int {
                return 1
            }

            test "bad table case" with (value: int) [
                (build())
            ] {
            }
            """);

        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.ConstantRequired);
        Assert.Contains("Table-driven test case values must be compile-time constants", error.Message);
        Assert.Contains("call", error.Message);
        Assert.Contains("literal int, float, char, string, bool, or null", error.Suggestion);
    }

    [Fact]
    public void TableDrivenTestCases_TypeMismatches_ReportTypeMismatch()
    {
        var result = AnalyzeWithSource("""
            test "bad table case type" with (value: int, label: string) [
                ("nope", 42)
            ] {
            }
            """);

        Assert.Contains(
            result.Errors,
            e => e.Code == ErrorCode.TypeMismatch
                && e.Message.Contains("value")
                && e.Message.Contains("int")
                && e.Message.Contains("string"));
        Assert.Contains(
            result.Errors,
            e => e.Code == ErrorCode.TypeMismatch
                && e.Message.Contains("label")
                && e.Message.Contains("string")
                && e.Message.Contains("int"));
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
    public void AnonymousUnion_RejectsAssignmentWhenNotEveryArmFitsTarget()
    {
        AssertHasError(@"
func Bad(value: int | string): string {
    return value
}
        ", "should return 'string'");
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
    public void AnonymousUnion_RejectsDuplicateArms()
    {
        AssertHasError(@"
func Bad(value: int | int): void {
}
        ", "repeats arm 'int'");
    }

    [Fact]
    public void AnonymousUnion_RejectsMoreThanTwoArms()
    {
        AssertHasError(@"
func Bad(value: int | string | bool): void {
}
        ", "support exactly two arms in v1");
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
    public void AnonymousUnion_MatchRequiresEveryArm()
    {
        AssertHasError(@"
func Describe(value: int | string): int {
    return match value {
        int number => number,
    }
}
        ", "missing: string");
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

    // ── NL316: shadowing is a hard compiler error ──────────────────────────

    private CompilerError AssertHasErrorCode(string source, ErrorCode code)
    {
        var result = Analyze(source);
        var match = result.Errors.FirstOrDefault(e => e.Code == code && e.Severity == ErrorSeverity.Error);
        Assert.True(match != null,
            $"Expected {code} but got: {string.Join(", ", result.Errors.Select(e => $"{e.DiagnosticId}:{e.Message}"))}");
        return match!;
    }

    private void AssertNoErrorCode(string source, ErrorCode code)
    {
        var result = Analyze(source);
        Assert.DoesNotContain(result.Errors, e => e.Code == code && e.Severity == ErrorSeverity.Error);
    }

    [Fact]
    public void Shadowing_InnerBlockLocalShadowingOuterLocal_IsError()
    {
        var error = AssertHasErrorCode(@"
func Main() {
    count := 1
    if count > 0 {
        count := 2
        print count
    }
}", ErrorCode.ShadowedDeclaration);
        Assert.Equal("NL316", error.DiagnosticId);
        Assert.Contains("'count'", error.Message);
        Assert.Equal(5, error.Length);
    }

    [Fact]
    public void Shadowing_LocalShadowingParameter_IsError()
    {
        AssertHasErrorCode(@"
func Greet(name: string) {
    name := ""override""
    print name
}", ErrorCode.ShadowedDeclaration);
    }

    [Fact]
    public void Shadowing_NestedFunctionBlockShadowingOuter_IsError()
    {
        AssertHasErrorCode(@"
func Outer() {
    sum := 1
    for i := 0; i < 3; i = i + 1 {
        sum := i
        print sum
    }
}", ErrorCode.ShadowedDeclaration);
    }

    [Fact]
    public void Shadowing_SiblingBlocksReusingName_IsAllowed()
    {
        AssertNoErrorCode(@"
func Main() {
    if true {
        temp := 1
        print temp
    }
    if false {
        temp := 2
        print temp
    }
}", ErrorCode.ShadowedDeclaration);
    }

    [Fact]
    public void Shadowing_LocalShadowingClassField_IsAllowed()
    {
        // Fields live in the class scope, not an enclosing local scope, so a method
        // local may reuse a field name (it is accessed via `this.` when needed).
        AssertNoErrorCode(@"
class Counter {
    count: int = 0

    func Increment() {
        count := 1
        print count
    }
}", ErrorCode.ShadowedDeclaration);
    }

    [Fact]
    public void Shadowing_DiscardAndUnderscoreNames_AreAllowed()
    {
        AssertNoErrorCode(@"
func Main() {
    _temp := 1
    if true {
        _temp := 2
        print _temp
    }
    print _temp
}", ErrorCode.ShadowedDeclaration);
    }

    // ── NL304: definite assignment for locals ──────────────────────────────

    [Fact]
    public void DefiniteAssignment_ReadAfterConditionalAssignment_IsError()
    {
        var error = AssertHasErrorCode(@"
func Cond(): bool {
    return true
}

func Main() {
    let total: int
    if Cond() {
        total = 5
    }
    print total
}", ErrorCode.DefiniteAssignmentError);
        Assert.Equal("NL304", error.DiagnosticId);
        Assert.Contains("'total'", error.Message);
        Assert.Equal(5, error.Length);
    }

    [Fact]
    public void DefiniteAssignment_ReadBeforeAnyAssignment_IsError()
    {
        AssertHasErrorCode(@"
func Main() {
    let value: int
    print value
}", ErrorCode.DefiniteAssignmentError);
    }

    [Fact]
    public void DefiniteAssignment_AssignedOnAllBranches_IsAllowed()
    {
        AssertNoErrorCode(@"
func Cond(): bool {
    return true
}

func Main() {
    let total: int
    if Cond() {
        total = 5
    } else {
        total = 0
    }
    print total
}", ErrorCode.DefiniteAssignmentError);
    }

    [Fact]
    public void DefiniteAssignment_AssignedBeforeUse_IsAllowed()
    {
        AssertNoErrorCode(@"
func Main() {
    let total: int
    total = 42
    print total
}", ErrorCode.DefiniteAssignmentError);
    }

    [Fact]
    public void DefiniteAssignment_InitializedAtDeclaration_IsAllowed()
    {
        AssertNoErrorCode(@"
func Main() {
    total := 0
    print total
}", ErrorCode.DefiniteAssignmentError);
    }

    [Fact]
    public void DefiniteAssignment_EarlyReturnGuardsUnassignedPath_IsAllowed()
    {
        AssertNoErrorCode(@"
func Cond(): bool {
    return true
}

func Main() {
    let total: int
    if Cond() {
        total = 5
    } else {
        return
    }
    print total
}", ErrorCode.DefiniteAssignmentError);
    }

    [Fact]
    public void DefiniteAssignment_ArrayLengthUse_ReadBeforeAnyAssignment_IsError()
    {
        // `new int[n]` reads n; the array-length subtree must flow through definite assignment
        // like any other read (it was a skipped child of NewExpression).
        AssertHasErrorCode(@"
func Main() {
    let n: int
    let arr = new int[n]
    print arr.Length
}", ErrorCode.DefiniteAssignmentError);
    }

    [Fact]
    public void DefiniteAssignment_ArrayLengthUse_ConditionallyAssigned_IsError()
    {
        AssertHasErrorCode(@"
func Cond(): bool {
    return true
}

func Main() {
    let n: int
    if Cond() {
        n = 5
    }
    let arr = new int[n]
    print arr.Length
}", ErrorCode.DefiniteAssignmentError);
    }

    [Fact]
    public void DefiniteAssignment_ArrayLengthUse_AssignedOnAllBranches_IsAllowed()
    {
        AssertNoErrorCode(@"
func Cond(): bool {
    return true
}

func Main() {
    let n: int
    if Cond() {
        n = 5
    } else {
        n = 6
    }
    let arr = new int[n]
    print arr.Length
}", ErrorCode.DefiniteAssignmentError);
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
    public void StackAlloc_UndefinedLengthName_ReportsUndefinedVariable()
    {
        // The length subtree gets real name resolution; before, only the systems policy gate
        // (NSYS080) saw it, which [boundary]/audit code downgrades to a warning.
        var error = AssertHasErrorCode(@"
func Scratch(): int {
    scratch := stackalloc byte[undefinedName]
    return scratch.Length
}", ErrorCode.UndefinedVariable);
        Assert.Equal(3, error.Line);
        Assert.Contains("undefinedName", error.Message);
    }

    [Fact]
    public void StackAlloc_StringLength_ReportsTypeMismatch()
    {
        var error = AssertHasErrorCode(@"
func Scratch(name: string): int {
    scratch := stackalloc byte[name]
    return scratch.Length
}", ErrorCode.TypeMismatch);
        Assert.Contains("stackalloc length must be an int", error.Message);
        Assert.Contains("'string'", error.Message);
        Assert.Equal(3, error.Line);
        Assert.Equal(32, error.Column);
    }

    [Fact]
    public void StackAlloc_LongLength_ReportsTypeMismatch()
    {
        var error = AssertHasErrorCode(@"
func Scratch(count: long): int {
    scratch := stackalloc byte[count]
    return scratch.Length
}", ErrorCode.TypeMismatch);
        Assert.Contains("stackalloc length must be an int", error.Message);
        Assert.Contains("'long'", error.Message);
    }

    [Fact]
    public void StackAlloc_SmallIntLengths_Accepted()
    {
        // byte/sbyte/short/ushort/char widen implicitly to int (C#'s element-count rule).
        var result = Analyze(@"
func Scratch(b: byte, s: short, c: char): int {
    s1 := stackalloc byte[b]
    s2 := stackalloc byte[s]
    s3 := stackalloc byte[c]
    return s1.Length + s2.Length + s3.Length
}");
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedVariable);
    }

    [Fact]
    public void StackAlloc_AliasedSmallIntLength_Accepted()
    {
        var result = Analyze(@"
type Count = short

func Scratch(count: Count): int {
    scratch := stackalloc byte[count]
    return scratch.Length
}");
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeMismatch);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.UndefinedVariable);
    }

    [Fact]
    public void StackAlloc_NegativeConstantLength_Rejected()
    {
        var error = AssertHasErrorCode(@"
func Scratch(): int {
    scratch := stackalloc byte[-1]
    return scratch.Length
}", ErrorCode.TypeMismatch);
        Assert.Contains("must not be negative", error.Message);
    }

    [Fact]
    public void StackAlloc_CastedNegativeConstantLength_Rejected()
    {
        var error = AssertHasErrorCode(@"
func Scratch(): int {
    scratch := stackalloc byte[checked((int)-1)]
    return scratch.Length
}", ErrorCode.TypeMismatch);
        Assert.Contains("must not be negative", error.Message);
    }

    [Fact]
    public void StackAlloc_ParenthesizedNegativeConstantOperand_Rejected()
    {
        var error = AssertHasErrorCode(@"
func Scratch(): int {
    scratch := stackalloc byte[unchecked(-(1))]
    return scratch.Length
}", ErrorCode.TypeMismatch);
        Assert.Contains("must not be negative", error.Message);
    }

    [Fact]
    public void StackAlloc_AliasedSignedCastNegativeConstantLength_Rejected()
    {
        var error = AssertHasErrorCode(@"
type Count = short

func Scratch(): int {
    scratch := stackalloc byte[(Count)-1]
    return scratch.Length
}", ErrorCode.TypeMismatch);
        Assert.Contains("must not be negative", error.Message);
    }

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

    // ==================== Operator overloads on non-numeric operands (SIMD / Unit 13) ====================

    [Fact]
    public void ArithmeticOp_OnRuntimeVectorType_ResolvesOperatorOverload_NoTypeMismatch()
    {
        // System.Numerics.Vector<T> defines static op_Addition/op_Multiply/... operators. The
        // analyzer must resolve these so explicit SIMD code type-checks (the IL backend already
        // binds them directly). Previously this produced a spurious NL202 "operator doesn't work".
        AssertNoErrorCode(@"
import System.Numerics

func vadd(a: Vector<int>, b: Vector<int>): Vector<int> {
    return a + b
}

func vop(a: Vector<int>, b: Vector<int>, c: Vector<int>): Vector<int> {
    return a * b - c
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ArithmeticOp_OnFixedSizeVectorType_ResolvesOperatorOverload_NoTypeMismatch()
    {
        AssertNoErrorCode(@"
import System.Numerics

func vadd(a: Vector3, b: Vector3): Vector3 {
    return a + b
}

func vmul(a: Vector4, b: Vector4): Vector4 {
    return a * b
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ArithmeticOp_OnUserDeclaredStructOperator_NoTypeMismatch()
    {
        // A user struct that declares `static func operator +` must let `a + b` type-check.
        AssertNoErrorCode(@"
struct Vec2 {
    X: double
    Y: double

    static func operator +(a: Vec2, b: Vec2): Vec2 {
        return new Vec2 { X: a.X + b.X, Y: a.Y + b.Y }
    }
}

func add(a: Vec2, b: Vec2): Vec2 {
    return a + b
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void BitwiseShiftAndUnaryOps_OnUserDeclaredStructOperators_NoTypeMismatch()
    {
        AssertNoErrorCode(@"
struct Flags {
    Value: int

    static func operator &(a: Flags, b: Flags): Flags {
        return new Flags { Value: a.Value & b.Value }
    }

    static func operator <<(a: Flags, amount: int): Flags {
        return new Flags { Value: a.Value << amount }
    }

    static func operator ~(value: Flags): Flags {
        return new Flags { Value: ~value.Value }
    }
}

func combine(a: Flags, b: Flags): Flags {
    masked := a & b
    shifted := masked << 2
    return ~shifted
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void LogicalNot_OnUserDeclaredStructOperator_NoTypeMismatch()
    {
        AssertNoErrorCode(@"
struct Flag {
    Value: int

    static func operator !(value: Flag): bool {
        return value.Value == 0
    }
}

func check(value: Flag): bool {
    return !value
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ArithmeticOp_OnTypeWithoutOperator_StillReportsTypeMismatch()
    {
        // Conservative guard: a type with NO matching operator overload must still be rejected,
        // so the fix doesn't silently swallow real arithmetic errors.
        AssertHasErrorCode(@"
class Box {
    Value: int
}

func bad(a: Box, b: Box): Box {
    return a + b
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ArithmeticOp_VectorPlusUnrelatedType_StillReportsTypeMismatch()
    {
        // A runtime vector operator must NOT bind when the *other* operand is an unrelated type.
        // `Vector<int>.op_Addition(Vector<int>, Vector<int>)` exists, but `Box` is not assignable to
        // the second parameter, so the analyzer must still report a mismatch (matching the IL
        // backend, which resolves operators against the actual argument types).
        AssertHasErrorCode(@"
import System.Numerics

class Box {
    Value: int
}

func bad(a: Vector<int>, b: Box): Vector<int> {
    return a + b
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ArithmeticOp_DeclaredOperatorWithWrongParameterTypes_StillReportsTypeMismatch()
    {
        // A declared `operator +` whose parameters do NOT accept the operands must not bind. Here
        // the operator takes (int, int); using it for `Vec2 + Vec2` must still be a type mismatch.
        AssertHasErrorCode(@"
struct Vec2 {
    X: double
    Y: double

    static func operator +(a: int, b: int): Vec2 {
        return new Vec2 { X: 0.0, Y: 0.0 }
    }
}

func bad(a: Vec2, b: Vec2): Vec2 {
    return a + b
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void UnresolvedType_InParameterAnnotation_ReportsTypeNotFound()
    {
        AssertHasErrorCode("func Handle(input: MissingExternalType) {\n}\n", ErrorCode.TypeNotFound);
    }

    [Fact]
    public void UnresolvedType_InReturnType_ReportsTypeNotFound()
    {
        AssertHasErrorCode("func Make(): MissingExternalType {\n    return null\n}\n", ErrorCode.TypeNotFound);
    }

    [Fact]
    public void UnresolvedType_InNewExpression_ReportsTypeNotFound()
    {
        AssertHasErrorCode("func Main() {\n    x := new MissingExternalType()\n}\n", ErrorCode.TypeNotFound);
    }

    [Fact]
    public void UnresolvedType_InFieldType_ReportsTypeNotFound()
    {
        AssertHasErrorCode("class Box {\n    Value: MissingExternalType\n}\n", ErrorCode.TypeNotFound);
    }

    [Fact]
    public void UnresolvedType_InGenericTypeArgument_ReportsArgNotTheKnownGeneric()
    {
        // The bogus argument must be reported, but `List` itself is compiler-known/external
        // (CLR open generics carry an arity suffix) and must NOT be flagged.
        var result = Analyze("import System.Collections.Generic\nfunc Handle(items: List<MissingExternalType>) {\n}\n");
        var notFound = result.Errors.Where(e => e.Code == ErrorCode.TypeNotFound).ToList();
        Assert.Single(notFound);
        Assert.Contains("MissingExternalType", notFound[0].Message);
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
    public void UnresolvedType_SuggestsNearestInScopeType()
    {
        var result = Analyze("class Person {\n    Name: string\n}\nfunc Greet(p: Persn) {\n}\n");
        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
        Assert.Contains("Persn", error.Message);
        Assert.Contains("Did you mean 'Person'?", error.Suggestion ?? string.Empty);
    }

    [Fact]
    public void GenericNew_MissingTypeArguments_ReportsInvalidTypeArgument()
    {
        // B2: `new Box(5)` on a generic class previously emitted an open-type token and
        // crashed at runtime with BadImageFormatException. N# requires explicit type
        // arguments (no class-type-argument inference, the C# rule).
        var result = Analyze("class Box<T> {\n    item: T\n\n    constructor(v: T) {\n        item = v\n    }\n}\n\nfunc Use(): int {\n    b := new Box(5)\n    return 0\n}\n");
        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidTypeArgument);
        Assert.Contains("requires 1 type argument", error.Message);
    }

    [Fact]
    public void GenericNew_WrongArity_ReportsInvalidTypeArgument()
    {
        // B13: wrong type-argument count previously emitted an unloadable assembly
        // (TypeLoadException at runtime).
        var result = Analyze("class Box<T> {\n    item: T\n\n    constructor(v: T) {\n        item = v\n    }\n}\n\nfunc Use(): int {\n    b := new Box<int, string>(5)\n    return 0\n}\n");
        var error = Assert.Single(result.Errors, e => e.Code == ErrorCode.InvalidTypeArgument);
        Assert.Contains("takes 1 type argument(s), but 2 were provided", error.Message);
    }

    [Fact]
    public void GenericAnnotation_WrongArity_ReportsInvalidTypeArgument()
    {
        var result = Analyze("class Box<T> {\n    item: T\n}\n\nfunc Handle(input: Box<int, bool>) {\n    _ = input\n}\n");
        Assert.Contains(result.Errors, e => e.Code == ErrorCode.InvalidTypeArgument && e.Message.Contains("takes 1 type argument(s), but 2 were provided"));
    }

    [Fact]
    public void GenericNew_UnknownTypeArgument_ReportsTypeNotFound()
    {
        // B14 pin: `new Box<Nope>(5)` is diagnosed at analysis (NL201 on the type argument)
        // instead of sailing through to IL emission.
        var result = Analyze("class Box<T> {\n    item: T\n\n    constructor(v: T) {\n        item = v\n    }\n}\n\nfunc Use(): int {\n    b := new Box<Nope>(5)\n    return 0\n}\n");
        Assert.Contains(result.Errors, e => e.Code == ErrorCode.TypeNotFound && e.Message.Contains("'Nope'"));
    }

    [Fact]
    public void GenericNew_CorrectArity_HasNoArityDiagnostics()
    {
        var result = Analyze("class Box<T> {\n    item: T\n\n    constructor(v: T) {\n        item = v\n    }\n}\n\nfunc Use(): int {\n    b := new Box<int>(5)\n    return b.item\n}\n");
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.InvalidTypeArgument);
        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.TypeNotFound);
    }

    [Fact]
    public void ReferenceLoadFailure_SurfacedAsWarning_WhenTypeResolutionFails()
    {
        // A reference assembly that failed to load is the classic root cause behind a
        // misleading "name not found" — NL923 must pair the two so the failure is diagnosable.
        // `MissingExternalType.Create()` resolves the receiver via external type lookup and
        // reports UndefinedVariable when it is not found (the analyzer's unresolved-name signal).
        var lexer = new Lexer("func Main() {\n    x := MissingExternalType.Create()\n}\n", "test.nl");
        var parser = new Parser(lexer.Tokenize());
        var unit = parser.ParseCompilationUnit();

        using var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        analyzer.RecordReferenceLoadFailure("/refs/Broken.dll", new IOException("simulated corrupt reference"));

        var result = analyzer.Analyze(unit);

        Assert.Contains(result.Errors, e => e.Severity == ErrorSeverity.Error);
        var warning = Assert.Single(result.Errors, e => e.Code == ErrorCode.ReferenceLoadFailure);
        Assert.Equal(ErrorSeverity.Warning, warning.Severity);
        Assert.Contains("/refs/Broken.dll", warning.Message);
        Assert.Contains("simulated corrupt reference", warning.Message);
    }

    [Fact]
    public void ReferenceLoadFailure_NotSurfaced_WhenAnalysisIsClean()
    {
        // Best-effort probe failures must stay quiet when every type resolved — healthy
        // compilations should not warn about assemblies they never needed.
        var lexer = new Lexer("func Add(a: int, b: int): int {\n    return a + b\n}\n", "test.nl");
        var parser = new Parser(lexer.Tokenize());
        var unit = parser.ParseCompilationUnit();

        using var analyzer = new Analyzer();
        analyzer.LoadSystemAssemblies();
        analyzer.RecordReferenceLoadFailure("/refs/Broken.dll", new IOException("simulated corrupt reference"));

        var result = analyzer.Analyze(unit);

        Assert.DoesNotContain(result.Errors, e => e.Code == ErrorCode.ReferenceLoadFailure);
        Assert.False(result.HasErrors);
    }

    // ── NL319: control cannot leave a finally block ────────────────────────
    // The CS0157 analog. Without it, the IL backend emitted `leave` out of a finally handler —
    // invalid IL (ilverify: LeaveOutOfFinally), InvalidProgramException on every call.

    [Fact]
    public void ReturnInsideFinally_Void_ReportsNL319()
    {
        var error = AssertHasErrorCode(@"
func F(n: int) {
    try {
        n = n + 1
    } finally {
        return
    }
}", ErrorCode.ControlTransferOutOfFinally);
        Assert.Equal("NL319", error.DiagnosticId);
        Assert.Equal("return".Length, error.Length);
    }

    [Fact]
    public void ReturnInsideFinally_Value_WithReturningCatch_ReportsNL319()
    {
        // The returning catch satisfies always-returns (NL305 ignores the finally and needs >=1
        // catch), so without NL319 this shape sailed through to the emitter and crashed at runtime.
        AssertHasErrorCode(@"
func F(n: int): int {
    try {
        return 100 / n
    } catch {
        return 0 - 1
    } finally {
        return 7
    }
}", ErrorCode.ControlTransferOutOfFinally);
    }

    [Fact]
    public void ReturnInsideFinally_Value_NoCatch_ReportsNL319()
    {
        // NL305 also fires for this shape (the always-returns rule ignores the finally); NL319 names
        // the real problem and is reported first, at the return statement itself.
        var result = Analyze(@"
func F(n: int): int {
    try {
        return 100 / n
    } finally {
        return 2
    }
}");
        var codes = result.Errors.Where(e => e.Severity == ErrorSeverity.Error).Select(e => e.Code).ToList();
        Assert.Contains(ErrorCode.ControlTransferOutOfFinally, codes);
        var nl319Index = codes.IndexOf(ErrorCode.ControlTransferOutOfFinally);
        var nl305Index = codes.IndexOf(ErrorCode.MissingReturn);
        Assert.True(nl305Index < 0 || nl319Index < nl305Index,
            "NL319 (the real problem) must be reported before NL305");
    }

    [Fact]
    public void BreakInsideFinally_LoopOutside_ReportsNL319()
    {
        var error = AssertHasErrorCode(@"
func F(n: int): int {
    total := 0
    i := 0
    while i < n {
        i = i + 1
        try {
            total = total + 1
        } finally {
            if i == 2 {
                break
            }
        }
    }
    return total
}", ErrorCode.ControlTransferOutOfFinally);
        Assert.Equal("break".Length, error.Length);
    }

    [Fact]
    public void ContinueInsideFinally_LoopOutside_ReportsNL319()
    {
        AssertHasErrorCode(@"
func F(n: int): int {
    total := 0
    i := 0
    while i < n {
        i = i + 1
        try {
            total = total + 1
        } finally {
            if i == 2 {
                continue
            }
        }
    }
    return total
}", ErrorCode.ControlTransferOutOfFinally);
    }

    [Fact]
    public void BreakAndContinueInsideLoopOpenedInsideFinally_NoDiagnostic()
    {
        // The loop is wholly inside the finally — its own break/continue never leave the handler.
        AssertNoErrorCode(@"
func F(n: int): int {
    total := 0
    try {
        total = total + 1
    } finally {
        i := 0
        while i < n {
            if i == 3 {
                break
            }
            if i == 1 {
                i = i + 2
                continue
            }
            total = total + 1
            i = i + 1
        }
    }
    return total
}", ErrorCode.ControlTransferOutOfFinally);
    }

    [Fact]
    public void ReturnInsideLambdaInsideFinally_NoDiagnostic()
    {
        // The return exits the lambda, not the finally — legal (the NL319 context resets at the
        // nested-body boundary).
        AssertNoErrorCode(@"
func F(): int {
    r := 0
    try {
        r = 1
    } finally {
        let f: Func<int, int> = x => {
            return x + 1
        }
        r = f(r)
    }
    return r
}", ErrorCode.ControlTransferOutOfFinally);
    }

    [Fact]
    public void ReturnInsideLocalFunctionInsideFinally_NoDiagnostic()
    {
        AssertNoErrorCode(@"
func F(): int {
    r := 0
    try {
        r = 1
    } finally {
        func bump(x: int): int {
            return x + 1
        }
        r = bump(r)
    }
    return r
}", ErrorCode.ControlTransferOutOfFinally);
    }

    [Fact]
    public void BreakInsideLambdaInsideFinally_ReportsInvalidSyntaxNotNL319()
    {
        var result = Analyze(@"
func F(): int {
    i := 0
    while i < 1 {
        try {
            i = i + 1
        } finally {
            let f: Func<int> = () => {
                break
                return 1
            }
            i = f()
        }
    }
    return i
}");

        Assert.Contains(result.Errors, error =>
            error.Code == ErrorCode.InvalidSyntax
            && error.Message.Contains("'break' can only be used inside a loop"));
        Assert.DoesNotContain(result.Errors, error => error.Code == ErrorCode.ControlTransferOutOfFinally);
    }

    [Fact]
    public void ContinueInsideLocalFunctionInsideFinally_ReportsInvalidSyntaxNotNL319()
    {
        var result = Analyze(@"
func F(): int {
    i := 0
    while i < 1 {
        try {
            i = i + 1
        } finally {
            func bump(): int {
                continue
                return 1
            }
            i = bump()
        }
    }
    return i
}");

        Assert.Contains(result.Errors, error =>
            error.Code == ErrorCode.InvalidSyntax
            && error.Message.Contains("'continue' can only be used inside a loop"));
        Assert.DoesNotContain(result.Errors, error => error.Code == ErrorCode.ControlTransferOutOfFinally);
    }

    [Fact]
    public void ReturnInsideTryNestedInsideFinally_ReportsNL319()
    {
        // Depth comparison, not immediate-parent: the return still exits the outer finally.
        AssertHasErrorCode(@"
func F(n: int) {
    try {
        n = n + 1
    } finally {
        try {
            return
        } catch {
            n = 0
        }
    }
}", ErrorCode.ControlTransferOutOfFinally);
    }

    [Fact]
    public void ReturnInsideLockNestedInsideFinally_ReportsNL319()
    {
        AssertHasErrorCode(@"
func F(s: string) {
    try {
        print(s)
    } finally {
        lock s {
            return
        }
    }
}", ErrorCode.ControlTransferOutOfFinally);
    }

    [Fact]
    public void ThrowInsideFinally_NoDiagnostic()
    {
        AssertNoErrorCode(@"
func F(n: int): int {
    r := 0
    try {
        r = 1
    } finally {
        if n == 0 {
            throw new InvalidOperationException(""fin"")
        }
    }
    return r
}", ErrorCode.ControlTransferOutOfFinally);
    }

    [Fact]
    public void NestedFinallys_InnerReturnRejected()
    {
        AssertHasErrorCode(@"
func F(n: int) {
    try {
        n = n + 1
    } finally {
        try {
            n = n + 2
        } finally {
            return
        }
    }
}", ErrorCode.ControlTransferOutOfFinally);
    }

    [Fact]
    public void ReturnAfterFinally_NoDiagnostic()
    {
        // The finally context must close when the block ends — a return after it is plain legal.
        AssertNoErrorCode(@"
func F(n: int): int {
    try {
        n = n + 1
    } finally {
        n = n + 2
    }
    return n
}", ErrorCode.ControlTransferOutOfFinally);
    }

    [Fact]
    public void BreakInsideSwitchInsideFinally_NoDiagnostic()
    {
        // The break targets the switch, which was entered inside the finally — legal.
        AssertNoErrorCode(@"
func F(n: int): int {
    total := 0
    i := 0
    while i < n {
        i = i + 1
        try {
            total = total + 1
        } finally {
            switch i {
                case 2:
                    break
                default:
                    total = total + 1
            }
        }
    }
    return total
}", ErrorCode.ControlTransferOutOfFinally);
    }

    // ── NL320: the lock statement requires a reference-typed lockee ────────
    // The CS0185 analog. Without it, EmitLock stored the raw value into an object local —
    // unverifiable IL whose fake reference segfaulted the whole process inside Monitor.Enter.

    [Fact]
    public void Lock_OnIntLocal_ReportsNL320()
    {
        var error = AssertHasErrorCode(@"
func F() {
    n := 5
    lock n {
        print(n)
    }
}", ErrorCode.LockRequiresReferenceType);
        Assert.Equal("NL320", error.DiagnosticId);
        Assert.Contains("'int'", error.Message);
    }

    [Fact]
    public void Lock_OnRecordStructInstance_ReportsNL320()
    {
        AssertHasErrorCode(@"
record struct Point {
    X: int
    Y: int
}

func F() {
    p := new Point { X: 1, Y: 2 }
    lock p {
        print(p.X)
    }
}", ErrorCode.LockRequiresReferenceType);
    }

    [Fact]
    public void Lock_OnEnumValue_ReportsNL320()
    {
        AssertHasErrorCode(@"
enum Color {
    Red
    Green
}

func F() {
    c := Color.Red
    lock c {
        print(1)
    }
}", ErrorCode.LockRequiresReferenceType);
    }

    [Fact]
    public void Lock_OnNullableInt_ReportsNL320()
    {
        // Nullable<int> is itself a struct — still a value lockee.
        AssertHasErrorCode(@"
func F() {
    let n: int? = 5
    lock n {
        print(1)
    }
}", ErrorCode.LockRequiresReferenceType);
    }

    [Fact]
    public void Lock_OnUnconstrainedTypeParameter_ReportsNL320()
    {
        // Stricter than C# by design: Roslyn boxes an unconstrained T into a fresh object per lock
        // (mutual exclusion never happens); N# rejects the trap with a constraint-specific hint.
        var error = AssertHasErrorCode(@"
func LockIt<T>(x: T) {
    lock x {
        print(1)
    }
}", ErrorCode.LockRequiresReferenceType);
        Assert.Contains("where T: class", error.Suggestion);
    }

    [Fact]
    public void Lock_OnStructConstrainedTypeParameter_ReportsNL320()
    {
        AssertHasErrorCode(@"
func LockIt<T>(x: T) where T: struct {
    lock x {
        print(1)
    }
}", ErrorCode.LockRequiresReferenceType);
    }

    [Fact]
    public void Lock_OnClassConstrainedTypeParameter_NoDiagnostic()
    {
        // `where T: class` proves the lockee is a reference; the emitter's `box !!T` lowering is a
        // runtime no-op for reference instantiations.
        AssertNoErrorCode(@"
func LockIt<T>(x: T) where T: class {
    lock x {
        print(1)
    }
}", ErrorCode.LockRequiresReferenceType);
    }

    [Fact]
    public void Lock_OnString_NoDiagnostic()
    {
        AssertNoErrorCode(@"
func F(s: string) {
    lock s {
        print(s.Length)
    }
}", ErrorCode.LockRequiresReferenceType);
    }

    [Fact]
    public void Lock_OnClassInstance_NoDiagnostic()
    {
        AssertNoErrorCode(@"
class Box {
    v: int
}

func F() {
    b := new Box { v: 5 }
    lock b {
        print(b.v)
    }
}", ErrorCode.LockRequiresReferenceType);
    }

    [Fact]
    public void Lock_OnObjectField_NoDiagnostic()
    {
        // The language-tour Counter shape — the recommended dedicated lock object.
        AssertNoErrorCode(@"
class Counter {
    count: int = 0
    syncLock: object = new object()

    func Increment() {
        lock syncLock {
            count++
        }
    }
}", ErrorCode.LockRequiresReferenceType);
    }

    [Fact]
    public void Lock_OnArray_NoDiagnostic()
    {
        AssertNoErrorCode(@"
func F(items: int[]) {
    lock items {
        print(items.Length)
    }
}", ErrorCode.LockRequiresReferenceType);
    }

    [Fact]
    public void Lock_OnInterfaceTypedValue_NoDiagnostic()
    {
        AssertNoErrorCode(@"
interface Greeter {
    func Greet(): string
}

class Hello {
    func Greet(): string {
        return ""hi""
    }
}

func F(g: Greeter) {
    lock g {
        print(g.Greet())
    }
}", ErrorCode.LockRequiresReferenceType);
    }

    [Fact]
    public void Lock_OnExternalReflectionReferenceType_NoFalsePositive()
    {
        // A reflection-resolved BCL reference type must never trip the value-type check.
        AssertNoErrorCode(@"
import System.Text

func F() {
    sb := new StringBuilder()
    lock sb {
        print(1)
    }
}", ErrorCode.LockRequiresReferenceType);
    }

    // ── NL322: a member write through a temporary VALUE COPY (the CS1612 analog) ────────
    // Paired with the EmitAddressableExpression chain fix (oracle defect #22): a value-typed
    // receiver that is not a variable — a List indexer result, a call result, a property result —
    // is a temporary copy; the store would land in the copy and be silently dropped.

    [Fact]
    public void MemberWrite_ThroughListIndexerOfStruct_ReportsNL322()
    {
        var error = AssertHasErrorCode(@"
struct S {
    X: int
}

func F(): int {
    lst := new List<S>()
    lst.Add(new S { X: 1 })
    lst[0].X = 5
    return lst[0].X
}", ErrorCode.MemberWriteThroughValueCopy);
        Assert.Equal("NL322", error.DiagnosticId);
    }

    [Fact]
    public void MemberWrite_ThroughStructCallResult_ReportsNL322()
    {
        AssertHasErrorCode(@"
struct S {
    X: int
}

func Make(): S {
    return new S { X: 1 }
}

func F() {
    Make().X = 5
}", ErrorCode.MemberWriteThroughValueCopy);
    }

    [Fact]
    public void CompoundMemberWrite_ThroughListIndexerOfStruct_ReportsNL322()
    {
        // Compound operators read-modify-write through the same temporary copy.
        AssertHasErrorCode(@"
struct S {
    X: int
}

func F() {
    lst := new List<S>()
    lst.Add(new S { X: 1 })
    lst[0].X += 3
}", ErrorCode.MemberWriteThroughValueCopy);
    }

    [Fact]
    public void MemberWrite_ThroughReferenceReceivers_NoFalsePositive()
    {
        // Reference-typed receivers are storage handles — every shape is assignable through them.
        AssertNoErrorCode(@"
class C {
    X: int
    constructor(v: int) {
        X = v
    }
}

func Pick(items: List<C>): C {
    return items[0]
}

func F(): int {
    lst := new List<C>()
    lst.Add(new C(1))
    lst[0].X = 5
    Pick(lst).X = 6
    return lst[0].X
}", ErrorCode.MemberWriteThroughValueCopy);
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

    [Fact]
    public void MemberWrite_ThroughAddressableValueChains_NoFalsePositive()
    {
        // Field chains rooted at locals/params and ARRAY elements are real variables.
        AssertNoErrorCode(@"
struct Inner {
    X: int
}

struct Outer {
    i: Inner
}

func G(p: Outer): int {
    p.i.X = 7
    return p.i.X
}

func F(): int {
    o := new Outer { i: new Inner { X: 1 } }
    o.i.X = 5
    arr := new int[3]
    arr[0] = 1
    return o.i.X + G(o)
}", ErrorCode.MemberWriteThroughValueCopy);
    }

    // ===== Object-initializer member type checking (defect: unsound List<Rs> -> List<Pt>) =====
    //
    // The C# pipeline used to accept ANY value type in `new T { Member: value }` — the
    // analyzer never compared the value against the declared member type, and the IL
    // backend's coercion silently no-ops for closed generics built over emitted user
    // types. A List<Rs> stored into a List<Pt> field produced type-confused garbage
    // reads at runtime (no InvalidCastException). These tests pin the NL202 gate.

    [Fact]
    public void ObjectInitializer_GenericCollectionElementMismatch_Error()
    {
        // The original unsound repro: compiled and returned garbage at runtime.
        var error = AssertHasErrorCode(@"
record Pt {
    X: int
}

record Rs {
    S: string
}

record H {
    Items: List<Pt>
}

func f(): int {
    l := new List<Rs>()
    l.Add(new Rs { S: ""abc"" })
    h := new H { Items: l }
    return h.Items[0].X
}", ErrorCode.TypeMismatch);
        // Bare-analyzer harness has no source file, so the plain-message path reports
        // (the Elm-style path with ExpectedType/ActualType is pinned by the
        // MultiFileCompiler regression test in CompilationBackendTests).
        Assert.Contains("'Items' is typed as 'List<Pt>', but the value is 'List<Rs>'", error.Message);
    }

    [Fact]
    public void ObjectInitializer_SameShapedElementTypeMismatch_Error()
    {
        // Layout-identical element types must still be rejected — this variant
        // 'worked' at runtime by field-offset luck, which is exactly the trap.
        var error = AssertHasErrorCode(@"
record Pt {
    X: int
}

record Qt {
    X: int
}

record H {
    Items: List<Pt>
}

func f(): int {
    l := new List<Qt>()
    h := new H { Items: l }
    return h.Items[0].X
}", ErrorCode.TypeMismatch);
        Assert.Contains("'Items' is typed as 'List<Pt>', but the value is 'List<Qt>'", error.Message);
    }

    [Fact]
    public void ObjectInitializer_DictionaryValueTypeMismatch_Error()
    {
        var error = AssertHasErrorCode(@"
record Pt {
    X: int
}

record Rs {
    S: string
}

record H {
    Map: Dictionary<string, Pt>
}

func f(): int {
    d := new Dictionary<string, Rs>()
    h := new H { Map: d }
    return h.Map[""k""].X
}", ErrorCode.TypeMismatch);
        Assert.Contains("'Map' is typed as 'Dictionary<string, Pt>', but the value is 'Dictionary<string, Rs>'", error.Message);
    }

    [Fact]
    public void ObjectInitializer_SimpleFieldTypeMismatch_Error()
    {
        // Used to compile and only fail at RUNTIME with InvalidCastException.
        AssertHasErrorCode(@"
record Pt {
    X: int
}

func f(): int {
    p := new Pt { X: ""abc"" }
    return p.X
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ObjectInitializer_GenericUserTypeArgumentMismatch_Error()
    {
        AssertHasErrorCode(@"
record Pt {
    X: int
}

record Rs {
    S: string
}

record Box<T> {
    Item: T
}

record H {
    B: Box<Pt>
}

func f(h: H, b: Box<Rs>): H {
    return new H { B: b }
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ObjectInitializer_ClosedGenericMemberSubstitution_Error()
    {
        // Item: T on Box<Pt> expects Pt — the member type must be resolved under the
        // instantiation's substitution, not skipped as an open type parameter.
        AssertHasErrorCode(@"
record Pt {
    X: int
}

record Rs {
    S: string
}

record Box<T> {
    Item: T
}

func f(): Box<Pt> {
    return new Box<Pt> { Item: new Rs { S: ""abc"" } }
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ObjectInitializer_ArrayElementTypeMismatch_Error()
    {
        // Unrelated element types are never array-assignable (used to die at emit
        // with an internal NL103 instead of a real diagnostic).
        AssertHasErrorCode(@"
record Pt {
    X: int
}

record Rs {
    S: string
}

record H {
    Items: Pt[]
}

func f(arr: Rs[]): H {
    return new H { Items: arr }
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ObjectInitializer_UnionCasePropertyMismatch_Error()
    {
        // Union case construction members are typed under the closed instantiation's
        // substitution: value: T on Result<int> expects int.
        AssertHasErrorCode(@"
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

func f(): Result<int> {
    return new Result.Success<int> { value: ""abc"" }
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ObjectInitializer_MatchingGenericTypes_NoError()
    {
        AssertNoErrorCode(@"
record Pt {
    X: int
}

record Box<T> {
    Item: T
}

record H {
    Items: List<Pt>
    Map: Dictionary<string, Pt>
    B: Box<int>
}

func f(): int {
    l := new List<Pt>()
    l.Add(new Pt { X: 7 })
    d := new Dictionary<string, Pt>()
    h := new H { Items: l, Map: d, B: new Box<int> { Item: 5 } }
    return h.Items[0].X
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ObjectInitializer_WideningAndNullAndSubtype_NoError()
    {
        // Implicit numeric widening, null into a nullable member, a derived instance
        // into a base-typed member, and a target-typed new() must all stay accepted.
        AssertNoErrorCode(@"
class Animal {
}

class Dog : Animal {
}

record Pt {
    X: int
}

record H {
    V: double
    Items: List<Pt>?
    Pet: Animal
    Tags: List<string>
}

func f(): H {
    return new H { V: 3, Items: null, Pet: new Dog(), Tags: new() }
}", ErrorCode.TypeMismatch);
    }

    // ===== Object-initializer member NAME validation (used to be an internal NL103 at emit) =====

    [Fact]
    public void ObjectInitializer_UnknownMemberName_Error()
    {
        var error = AssertHasErrorCode(@"
record H {
    Items: List<int>
}

func f(): H {
    return new H { Itmes: new List<int>() }
}", ErrorCode.UndefinedMember);
        Assert.Contains("'Itmes'", error.Message);
        Assert.Contains("Items", error.Suggestion ?? string.Join(",", error.Suggestions ?? new List<string>()));
    }

    [Fact]
    public void ObjectInitializer_UnknownMemberOnClosedGeneric_Error()
    {
        var error = AssertHasErrorCode(@"
record Box<T> {
    Item: T
}

func f(): Box<int> {
    return new Box<int> { Itm: 5 }
}", ErrorCode.UndefinedMember);
        Assert.Contains("'Itm'", error.Message);
    }

    [Fact]
    public void ObjectInitializer_UnionCasePropertyTypo_Error()
    {
        var error = AssertHasErrorCode(@"
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

func f(): Result<int> {
    return new Result.Success<int> { valu: 42 }
}", ErrorCode.UndefinedMember);
        Assert.Contains("Union case 'Success' doesn't have a property named 'valu'", error.Message);
        Assert.Contains("value", error.Suggestion ?? string.Empty);
    }

    [Fact]
    public void UnionCaseConstruction_UnknownCase_Error()
    {
        var error = AssertHasErrorCode(@"
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

func f(): Result<int> {
    return new Result.Sucess<int> { value: 42 }
}", ErrorCode.UndefinedMember);
        Assert.Contains("'Sucess' is not a case of union 'Result'", error.Message);
        Assert.Contains("Result.Success", error.Suggestion ?? string.Empty);
    }

    [Fact]
    public void ObjectInitializer_InheritedMember_ResolvesAndTypeChecks()
    {
        // Members inherited from a base class must resolve (no false NL303)...
        AssertNoErrorCode(@"
class Base {
    X: int
}

class Derived : Base {
}

func f(): Derived {
    return new Derived { X: 5 }
}", ErrorCode.UndefinedMember);

        // ...and still get the NL202 assignability gate through the base member type.
        AssertHasErrorCode(@"
class Base {
    X: int
}

class Derived : Base {
}

func f(): Derived {
    return new Derived { X: ""abc"" }
}", ErrorCode.TypeMismatch);
    }

    [Fact]
    public void ObjectInitializer_ReflectionMembers_TypeCheckAndNameCheck()
    {
        // BCL receivers: matching member types stay accepted...
        AssertNoErrorCode(@"
import System.Text

func f(): StringBuilder {
    return new StringBuilder { Capacity: 10 }
}", ErrorCode.TypeMismatch);

        // ...a mismatched value reports NL202...
        AssertHasErrorCode(@"
import System.Text

func f(): StringBuilder {
    return new StringBuilder { Capacity: ""abc"" }
}", ErrorCode.TypeMismatch);

        // ...and a typo'd member reports NL303 (reliable BCL member set).
        AssertHasErrorCode(@"
import System.Text

func f(): StringBuilder {
    return new StringBuilder { Capcity: 10 }
}", ErrorCode.UndefinedMember);
    }

    [Fact]
    public void Nameof_UnsupportedTarget_ReportsAnalyzerDiagnostic()
    {
        var error = AssertHasErrorCode("""
func f(): string {
    return nameof(1 + 2)
}
""", ErrorCode.InvalidSyntax);

        Assert.Contains("nameof can only name an identifier or member access", error.Message);
        Assert.Contains("nameof(value)", error.Suggestion ?? string.Empty);
    }
}
