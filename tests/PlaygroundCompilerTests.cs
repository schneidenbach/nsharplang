using System;
using System.Linq;
using NSharpLang.Playground;
using Xunit;

namespace NSharpLang.Tests;

public sealed class PlaygroundCompilerTests
{
    [Fact]
    public void Catalog_StatesBrowserCapabilitiesAndExamples()
    {
        var catalog = new PlaygroundCompiler().GetCatalog();

        Assert.Equal(2, catalog.SchemaVersion);
        Assert.True(catalog.Capabilities.RunsInBrowser);
        Assert.True(catalog.Capabilities.SupportsDiagnostics);
        Assert.True(catalog.Capabilities.SupportsFormatting);
        Assert.True(catalog.Capabilities.SupportsCompletions);
        Assert.True(catalog.Capabilities.SupportsHover);
        Assert.True(catalog.Capabilities.SupportsSyntaxHighlighting);
        Assert.True(catalog.Capabilities.SupportsExecution);
        Assert.Contains(catalog.Examples, example => example.Id == "05-duck-typing");
        Assert.Contains(catalog.Examples, example => example.ExpectedOutput != null);
        Assert.NotEmpty(catalog.Tutorial);
        Assert.True(catalog.EstimatedMinutes >= 15);
    }

    [Fact]
    public void Catalog_TutorialReferencesKnownExamplesAndExerciseValidation()
    {
        var catalog = new PlaygroundCompiler().GetCatalog();
        var exampleIds = catalog.Examples.Select(example => example.Id).ToHashSet();

        Assert.Contains(catalog.Tutorial, step => step.Kind == "info" && step.Validation == null);
        Assert.Contains(catalog.Tutorial, step => step.Kind == "exercise" && step.Validation != null);
        Assert.All(catalog.Tutorial.Where(step => step.ExampleId != null), step =>
            Assert.Contains(step.ExampleId!, exampleIds));
        Assert.All(catalog.Tutorial.Where(step => step.Kind == "exercise"), step =>
        {
            Assert.NotNull(step.Validation);
            Assert.Equal("output", step.Validation!.Type);
            Assert.False(string.IsNullOrWhiteSpace(step.Validation.ExpectedOutput));
            Assert.False(string.IsNullOrWhiteSpace(step.Validation.SuccessMessage));
        });
    }

    [Fact]
    public void Catalog_ExamplesAreCompilerClean()
    {
        var compiler = new PlaygroundCompiler();

        foreach (var example in PlaygroundExamples.All)
        {
            var result = compiler.CheckProject(
                [
                    new PlaygroundFile("Program.nl", example.Code),
                    new PlaygroundFile("Program.tests.nl", example.TestsCode ?? string.Empty)
                ],
                "Program.nl");

            Assert.True(
                result.Ok,
                $"{example.Id}: {string.Join("; ", result.Diagnostics.Select(diagnostic => $"{diagnostic.Code} {diagnostic.Message}"))}");
        }
    }

    [Fact]
    public void Check_ValidProgram_HasNoErrors()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                message := "Hello"
                print message
            }
            """);

        Assert.True(result.Ok);
        Assert.Equal(0, result.Summary.Errors);
        Assert.Equal(2, result.SchemaVersion);
    }

    [Fact]
    public void Check_InvalidProgram_ReturnsCompilerDiagnostic()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                total := 42
                print totla
            }
            """);

        Assert.False(result.Ok);
        Assert.Contains(result.Diagnostics, diagnostic =>
            diagnostic.Code == "NL301" &&
            diagnostic.Severity == "error" &&
            diagnostic.Message.Contains("totla"));
    }

    [Fact]
    public void Check_SemanticDiagnostics_PreserveExpectedMarkerSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func TakesInt(value: int) {}

            func main() {
                maybeCustomerName: string? = "Ada"
                print maybeCustomerName.Length
                TakesInt("oops")
                TakesInt()
            }
            """);

        Assert.False(result.Ok);

        var nullAccess = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL905");
        Assert.Equal(7, nullAccess.Line);
        Assert.Equal(11, nullAccess.Column);
        Assert.Equal("maybeCustomerName".Length, nullAccess.Length);

        var wrongArgument = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Message.Contains("Cannot pass"));
        Assert.Equal(8, wrongArgument.Line);
        Assert.Equal(14, wrongArgument.Column);
        Assert.Equal("\"oops\"".Length, wrongArgument.Length);

        var wrongCount = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL401");
        Assert.Equal(9, wrongCount.Line);
        Assert.Equal(5, wrongCount.Column);
        Assert.Equal("TakesInt".Length, wrongCount.Length);
    }

    [Fact]
    public void Check_NSharpNoMatchingOverload_PreservesCallableNameSpan()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            class Processor {
                func Process(x: int): int { return x }
                func Process(x: string): string { return x }
            }

            func main() {
                p := new Processor()
                p.Process(true)
            }
            """);

        Assert.False(result.Ok);
        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL402" &&
                          diagnostic.Message.Contains("Process"));
        AssertPlaygroundSpan(diagnostic, line: 10, column: 7, length: "Process".Length);
        Assert.Contains("Process(x: int): int", diagnostic.Hint);
        Assert.Contains("Process(x: string): string", diagnostic.Hint);
    }

    [Fact]
    public void Check_TypeMismatchDiagnostics_PreserveOffendingExpressionSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func TakesVoid(): void {
            }

            func ExpressionBodyMismatch(): int => "bad"

            func ExpressionBodyRequiresReturnType() => "bad"

            func main(): int {
                declared: int = "hi"
                inferred := TakesVoid()
                if "yes" {
                    return "bad"
                }
            }
            """);

        Assert.False(result.Ok);

        var expressionBodyMismatch = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Message.Contains("ExpressionBodyMismatch"));
        AssertPlaygroundSpan(expressionBodyMismatch, line: 6, column: 39, length: "\"bad\"".Length);

        var expressionBodyRequiresReturnType = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Message.Contains("ExpressionBodyRequiresReturnType"));
        AssertPlaygroundSpan(expressionBodyRequiresReturnType, line: 8, column: 44, length: "\"bad\"".Length);

        var localInitializer = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Line == 11 &&
                          diagnostic.Message == "Type mismatch");
        AssertPlaygroundSpan(localInitializer, line: 11, column: 21, length: "\"hi\"".Length);

        var voidAssignment = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Message.Contains("void"));
        AssertPlaygroundSpan(voidAssignment, line: 12, column: 17, length: "TakesVoid".Length);

        var ifCondition = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Line == 13 &&
                          diagnostic.Message == "Type mismatch");
        AssertPlaygroundSpan(ifCondition, line: 13, column: 8, length: "\"yes\"".Length);

        var returnValue = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Message.Contains("main") &&
                          diagnostic.Message.Contains("returns string"));
        AssertPlaygroundSpan(returnValue, line: 14, column: 16, length: "\"bad\"".Length);
    }

    [Fact]
    public void Check_EnumMemberInitializerTypeMismatches_PreserveInitializerValueSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            enum HttpCode: int {
                Ok = "ok"
            }

            enum Label: string {
                Ready = 1
            }
            """);

        Assert.False(result.Ok);

        var numericValue = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Message.Contains("'Ok'"));
        AssertPlaygroundSpan(numericValue, line: 4, column: 10, length: "\"ok\"".Length);

        var stringValue = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Message.Contains("'Ready'"));
        AssertPlaygroundSpan(stringValue, line: 8, column: 13, length: "1".Length);
    }

    [Fact]
    public void Check_ControlFlowAndCollectionTypeMismatches_PreserveOffendingExpressionSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                while "loop" {
                }

                for i := 0; "loop"; i++ {
                }

                value := 1
                answer := "maybe" ? 1 : 2
                numbers := [1, "two"]
                label := match value {
                    n when "guard" => "positive",
                    _ => 12345
                }
                print label
            }
            """);

        Assert.False(result.Ok);

        var whileCondition = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Message.Contains("'while'"));
        AssertPlaygroundSpan(whileCondition, line: 4, column: 11, length: "\"loop\"".Length);

        var forCondition = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Message.Contains("'for'"));
        AssertPlaygroundSpan(forCondition, line: 7, column: 17, length: "\"loop\"".Length);

        var ternaryCondition = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Message.Contains("ternary expression"));
        AssertPlaygroundSpan(ternaryCondition, line: 11, column: 15, length: "\"maybe\"".Length);

        var arrayElement = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Message.Contains("All elements in an array"));
        AssertPlaygroundSpan(arrayElement, line: 12, column: 20, length: "\"two\"".Length);

        var matchGuard = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL505");
        AssertPlaygroundSpan(matchGuard, line: 14, column: 16, length: "\"guard\"".Length);

        var matchArm = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Message.Contains("All match arms"));
        AssertPlaygroundSpan(matchArm, line: 15, column: 14, length: "12345".Length);
    }

    [Fact]
    public void Check_LoopControlOutsideLoop_PreservesFullKeywordSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                break
                continue
            }
            """);

        Assert.False(result.Ok);

        var breakDiagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL103" &&
                          diagnostic.Message.Contains("'break'"));
        AssertPlaygroundSpan(breakDiagnostic, line: 4, column: 5, length: "break".Length);

        var continueDiagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL103" &&
                          diagnostic.Message.Contains("'continue'"));
        AssertPlaygroundSpan(continueDiagnostic, line: 5, column: 5, length: "continue".Length);
    }

    [Fact]
    public void Check_ReturnOutsideFunctionAndTargetlessDefault_PreserveFullKeywordSpans()
    {
        var result = new PlaygroundCompiler().CheckProject(
            [
                new PlaygroundFile("Program.tests.nl", """
                    func main() {
                        value := default
                    }

                    test "does not return" {
                        return
                    }
                    """)
            ],
            "Program.tests.nl");

        Assert.False(result.Ok);

        var targetlessDefault = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL203" &&
                          diagnostic.Message.Contains("'default'"));
        AssertPlaygroundSpan(targetlessDefault, line: 2, column: 14, length: "default".Length);

        var returnOutsideFunction = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL103" &&
                          diagnostic.Message.Contains("'return' can only"));
        AssertPlaygroundSpan(returnOutsideFunction, line: 6, column: 5, length: "return".Length);
    }

    [Fact]
    public void Check_ReadonlyAssignment_PreservesAssignedFieldNameSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            class Account {
                readonly id: string = "initial"

                func Change() {
                    id = "next"
                    this.id = "again"
                }
            }
            """);

        Assert.False(result.Ok);

        var directAssignment = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL309" &&
                          diagnostic.Line == 7);
        AssertPlaygroundSpan(directAssignment, line: 7, column: 9, length: "id".Length);

        var memberAssignment = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL309" &&
                          diagnostic.Line == 8);
        AssertPlaygroundSpan(memberAssignment, line: 8, column: 14, length: "id".Length);
    }

    [Fact]
    public void Check_UnreachableStatement_PreservesUnreachableKeywordSpan()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                return
                print "after"
            }
            """);

        Assert.False(result.Ok);

        var unreachableDiagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL312");
        AssertPlaygroundSpan(unreachableDiagnostic, line: 5, column: 5, length: "print".Length);
    }

    [Fact]
    public void Check_InvalidVariableDeclarations_PreserveFullNameSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                const answer: int
                let value
            }
            """);

        Assert.False(result.Ok);

        var constWithoutInitializer = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL103" &&
                          diagnostic.Message.Contains("'const'"));
        AssertPlaygroundSpan(constWithoutInitializer, line: 4, column: 11, length: "answer".Length);

        var unknownVariableType = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL103" &&
                          diagnostic.Message.Contains("determine the type"));
        AssertPlaygroundSpan(unknownVariableType, line: 5, column: 9, length: "value".Length);
    }

    [Fact]
    public void Check_InvalidGenericConstraints_PreserveOffendingConstraintSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func BadClassStruct<T>(value: T): T where T : class, struct {
                return value
            }

            func BadStructNew<T>(value: T): T where T : struct, new() {
                return value
            }
            """);

        Assert.False(result.Ok);

        var classStructConflict = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL103" &&
                          diagnostic.Message.Contains("both 'class' and 'struct'"));
        AssertPlaygroundSpan(classStructConflict, line: 3, column: 54, length: "struct".Length);

        var structNewConflict = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL103" &&
                          diagnostic.Message.Contains("Cannot combine 'struct' and 'new()'"));
        AssertPlaygroundSpan(structNewConflict, line: 7, column: 53, length: "new()".Length);
    }

    [Fact]
    public void Check_AssignmentAndOperatorTypeMismatches_PreserveSpecificExpressionSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                x := 0
                x = "text"

                oneBad := 1 - "two"
                bothBad := "one" - "two"
                logicalRight := true && 1
                logicalBoth := 1 && 2

                print x
            }
            """);

        Assert.False(result.Ok);

        var assignmentValue = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Line == 5 &&
                          diagnostic.Message == "Type mismatch");
        AssertPlaygroundSpan(assignmentValue, line: 5, column: 9, length: "\"text\"".Length);

        var arithmeticRightOperand = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Line == 7 &&
                          diagnostic.Message.Contains("right side"));
        AssertPlaygroundSpan(arithmeticRightOperand, line: 7, column: 19, length: "\"two\"".Length);

        var arithmeticOperator = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Line == 8 &&
                          diagnostic.Message.Contains("I found 'string' and 'string'"));
        AssertPlaygroundSpan(arithmeticOperator, line: 8, column: 22, length: "-".Length);

        var logicalRightOperand = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Line == 9 &&
                          diagnostic.Message.Contains("right side"));
        AssertPlaygroundSpan(logicalRightOperand, line: 9, column: 29, length: "1".Length);

        var logicalOperator = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL202" &&
                          diagnostic.Line == 10 &&
                          diagnostic.Message.Contains("I found 'int' and 'int'"));
        AssertPlaygroundSpan(logicalOperator, line: 10, column: 22, length: "&&".Length);
    }

    [Fact]
    public void Check_PatternErrors_PreserveSpecificPatternSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            union Result {
                Success { value: int }
                Failure { message: string }
            }

            record User {
                Name: string
            }

            func main() {
                r := new Result.Success { value: 42 }
                x := match r {
                    Result.Unknown => 0,
                    Result.Success { missing: value } => value,
                    Result.Failure { message } => 0
                }

                user := new User { Name: "Ada" }
                y := match user {
                    { Missing: value } => value,
                    _ => "unknown"
                }

                n := 1
                z := match n {
                    [first, ..] => first,
                    _ => 0
                }
            }
            """);

        var missingCase = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL503" &&
                          diagnostic.Line == 15 &&
                          diagnostic.Message.Contains("'Result.Unknown'"));
        AssertPlaygroundSpan(missingCase, line: 15, column: 9, length: "Result.Unknown".Length);

        var missingUnionProperty = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL503" &&
                          diagnostic.Line == 16 &&
                          diagnostic.Message.Contains("'missing'"));
        AssertPlaygroundSpan(missingUnionProperty, line: 16, column: 26, length: "missing".Length);

        var missingObjectProperty = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL503" &&
                          diagnostic.Line == 22 &&
                          diagnostic.Message.Contains("'Missing'"));
        AssertPlaygroundSpan(missingObjectProperty, line: 22, column: 11, length: "Missing".Length);

        var listPatternMismatch = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL504");
        AssertPlaygroundSpan(listPatternMismatch, line: 28, column: 9, length: "[first, ..]".Length);
    }

    [Fact]
    public void Check_DeclarationErrors_PreserveDeclarationNameSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func Duplicate(value: int): int { return value }

            func Duplicate(value: int): int { return value }

            class Thing {}
            class Thing {}

            enum Status {
                Pending,
                Pending
            }

            union Result {
                Success
                Success
            }

            func BadParams(params rest: int[], tail: int) {}

            func BadOrdering(first: int = 1, second: int) {}

            func BadDefault(value: int = makeValue()) {}

            func main() {
                value := 1
                value := 2
            }
            """);

        var duplicateFunction = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL306" &&
                          diagnostic.Line == 5 &&
                          diagnostic.Message.Contains("'Duplicate'"));
        AssertPlaygroundSpan(duplicateFunction, line: 5, column: 6, length: "Duplicate".Length);

        var duplicateType = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL306" &&
                          diagnostic.Line == 8 &&
                          diagnostic.Message.Contains("Thing"));
        AssertPlaygroundSpan(duplicateType, line: 8, column: 7, length: "Thing".Length);

        var duplicateEnumMember = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL306" &&
                          diagnostic.Line == 12 &&
                          diagnostic.Message.Contains("enum member"));
        AssertPlaygroundSpan(duplicateEnumMember, line: 12, column: 5, length: "Pending".Length);

        var duplicateUnionCase = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL306" &&
                          diagnostic.Line == 17 &&
                          diagnostic.Message.Contains("union case"));
        AssertPlaygroundSpan(duplicateUnionCase, line: 17, column: 5, length: "Success".Length);

        var paramsNotLast = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL407");
        AssertPlaygroundSpan(paramsNotLast, line: 20, column: 23, length: "rest".Length);

        var requiredAfterOptional = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL409");
        AssertPlaygroundSpan(requiredAfterOptional, line: 22, column: 34, length: "second".Length);

        var invalidDefault = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL410");
        AssertPlaygroundSpan(invalidDefault, line: 24, column: 30, length: "makeValue".Length);

        var duplicateLocal = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL306" &&
                          diagnostic.Line == 28 &&
                          diagnostic.Message.Contains("'value'"));
        AssertPlaygroundSpan(duplicateLocal, line: 28, column: 5, length: "value".Length);
    }

    [Fact]
    public void Check_OperatorOverloadErrors_PreserveOperatorKeywordAndSymbolSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            class Vector {
                X: int

                func operator %(a: Vector, b: Vector, c: Vector): Vector {
                    return a
                }

                static func operator true(a: Vector, b: Vector): bool {
                    return true
                }
            }
            """);

        var missingStatic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL601");
        AssertPlaygroundSpan(missingStatic, line: 6, column: 10, length: "operator".Length);

        var moduloArity = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL602" &&
                          diagnostic.Message.Contains("'%'"));
        AssertPlaygroundSpan(moduloArity, line: 6, column: 19, length: "%".Length);

        var trueArity = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL602" &&
                          diagnostic.Message.Contains("'true'"));
        AssertPlaygroundSpan(trueArity, line: 10, column: 26, length: "true".Length);
    }

    [Fact]
    public void Check_DuplicateTestLifecycleBlocks_PreserveFullKeywordSpans()
    {
        var result = new PlaygroundCompiler().CheckProject(
            [
                new PlaygroundFile("Program.tests.nl", """
                    setup {
                        first := 1
                    }

                    setup {
                        second := 2
                    }

                    teardown {
                        Cleanup()
                    }

                    teardown {
                        CleanupAgain()
                    }

                    func Cleanup() {}
                    func CleanupAgain() {}

                    test "works" {
                        assert true
                    }
                    """)
            ],
            "Program.tests.nl");

        var duplicateSetup = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL306" &&
                          diagnostic.Message.Contains("setup block"));
        AssertPlaygroundSpan(duplicateSetup, line: 5, column: 1, length: "setup".Length);

        var duplicateTeardown = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL306" &&
                          diagnostic.Message.Contains("teardown block"));
        AssertPlaygroundSpan(duplicateTeardown, line: 13, column: 1, length: "teardown".Length);
    }

    [Fact]
    public void Check_LinterDiagnostic_PreservesFullSpanForMarkers()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                Message := "hi"
                print Message
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL008" &&
                          diagnostic.Message.Contains("Message"));

        Assert.True(result.Ok);
        Assert.Equal("info", diagnostic.Severity);
        Assert.Equal(4, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("Message".Length, diagnostic.Length);
    }

    [Fact]
    public void Check_UnusedShorthandVariable_PreservesVariableNameSpan()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                asdf := "meow"
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL001" &&
                          diagnostic.Message.Contains("asdf"));

        Assert.False(result.Ok);
        Assert.Equal("error", diagnostic.Severity);
        Assert.Equal(4, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("asdf".Length, diagnostic.Length);
    }

    private static void AssertPlaygroundSpan(PlaygroundDiagnostic diagnostic, int line, int column, int length)
    {
        Assert.Equal(line, diagnostic.Line);
        Assert.Equal(column, diagnostic.Column);
        Assert.Equal(length, diagnostic.Length);
    }

    [Fact]
    public void Check_ObjectInitializerEquals_PreservesOneCharacterSpanForMarkers()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            class User {
                Name: string
            }

            func main() {
                user := new User { Name = "Ada" }
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL103" &&
                          diagnostic.Message.Contains("Object initializer member 'Name' uses '='"));

        Assert.Equal(8, diagnostic.Line);
        Assert.Equal(29, diagnostic.Column);
        Assert.Equal(1, diagnostic.Length);
        Assert.Contains("colon", diagnostic.Explanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Name: value", diagnostic.Hint, StringComparison.Ordinal);
    }

    [Fact]
    public void Check_IncompleteMemberAccess_PointsAtTrailingDot()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                name := "Ada"
                name.
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL102" &&
                          diagnostic.Message.Contains("Expected member name"));

        Assert.Equal(5, diagnostic.Line);
        Assert.Equal(9, diagnostic.Column);
        Assert.Equal(1, diagnostic.Length);
        Assert.Contains("dot", diagnostic.Explanation, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL313" ||
                          diagnostic.Message.Contains("<error>", StringComparison.Ordinal));
    }

    [Fact]
    public void Check_IncompleteMemberAccessBeforeCall_PreservesDotSpan()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                name := "Ada"
                name.()
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL102" &&
                          diagnostic.Message.Contains("Expected member name"));

        AssertPlaygroundSpan(diagnostic, line: 5, column: 9, length: 1);
        Assert.Contains("dot (.)", diagnostic.Explanation, StringComparison.Ordinal);
        Assert.DoesNotContain(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL313" ||
                          diagnostic.Message.Contains("<error>", StringComparison.Ordinal));
    }

    [Fact]
    public void Check_UnterminatedStringLiteral_PreservesSpanForMarkers()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                name := "Ada
                print name
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL105" &&
                          diagnostic.Message.Contains("Unterminated string literal"));

        Assert.Equal(4, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(4, diagnostic.Length);
        Assert.Equal("    name := \"Ada", diagnostic.SourceSnippet);
        Assert.Contains("closing quote", diagnostic.Explanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("triple-quoted string", diagnostic.Hint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Check_UnterminatedStringLiteral_WithEscapedQuote_PreservesSpanForMarkers()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                name := "Ada\"
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL105" &&
                          diagnostic.Message.Contains("Unterminated string literal"));

        Assert.Equal(4, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(6, diagnostic.Length);
        Assert.Equal("    name := \"Ada\\\"", diagnostic.SourceSnippet);
        Assert.Contains("closing quote", diagnostic.Explanation, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Check_UnterminatedCharacterLiteral_PreservesSpanForMarkers()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                letter := 'a
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL105" &&
                          diagnostic.Message.Contains("Unterminated character literal"));

        Assert.Equal(4, diagnostic.Line);
        Assert.Equal(15, diagnostic.Column);
        Assert.Equal(2, diagnostic.Length);
        Assert.Equal("    letter := 'a", diagnostic.SourceSnippet);
        Assert.Contains("closing quote", diagnostic.Explanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("single character", diagnostic.Hint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Check_UnterminatedTripleQuoteStringLiteral_PreservesOpeningDelimiterSpanForMarkers()
    {
        var result = new PlaygroundCompiler().Check("package Playground\n\nfunc main() {\n    text := \"\"\"hello\nworld\n}\n");

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL105" &&
                          diagnostic.Message.Contains("Unterminated triple-quoted string literal"));

        Assert.Equal(4, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(3, diagnostic.Length);
        Assert.Equal("    text := \"\"\"hello", diagnostic.SourceSnippet);
        Assert.Contains("closing triple quote", diagnostic.Explanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("closing triple quote", diagnostic.Hint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Check_UnterminatedInterpolatedRawStringLiteral_PreservesOpeningDelimiterSpanForMarkers()
    {
        var result = new PlaygroundCompiler().Check("package Playground\n\nfunc main() {\n    text := $\"\"\"hello {name}\n}\n");

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL105" &&
                          diagnostic.Message.Contains("Unterminated interpolated raw string literal"));

        Assert.Equal(4, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(4, diagnostic.Length);
        Assert.Equal("    text := $\"\"\"hello {name}", diagnostic.SourceSnippet);
        Assert.Contains("closing triple quote", diagnostic.Explanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("closing triple quote", diagnostic.Hint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Check_MissingClosingParen_PreservesCallOwnerSpanForMarkers()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                print("hello"
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL107" &&
                          diagnostic.Message.Contains("Missing closing ')'"));

        Assert.Equal(4, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("print".Length, diagnostic.Length);
        Assert.Equal("    print(\"hello\"", diagnostic.SourceSnippet);
        Assert.Contains("closing ')'", diagnostic.Explanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("matching closing parenthesis", diagnostic.Hint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Check_UnclosedEmptyCallArgumentList_PreservesCallOwnerSpanForMarkers()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                print(
                greeting.CompareTo("ter")
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL107" &&
                          diagnostic.Message.Contains("Missing closing ')'"));

        Assert.Equal(4, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("print".Length, diagnostic.Length);
        Assert.Equal("    print(", diagnostic.SourceSnippet);
        Assert.Contains("closing ')'", diagnostic.Explanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("matching closing parenthesis", diagnostic.Hint, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL101");
    }

    [Fact]
    public void Check_UnclosedEmptyFunctionParameterList_PreservesFunctionNameSpanForMarkers()
    {
        var result = new PlaygroundCompiler().Check("package Playground\n\nfunc main(\n");

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL107" &&
                          diagnostic.Message.Contains("Missing closing ')'"));

        Assert.Equal(3, diagnostic.Line);
        Assert.Equal(6, diagnostic.Column);
        Assert.Equal("main".Length, diagnostic.Length);
        Assert.Equal("func main(", diagnostic.SourceSnippet);
        Assert.Contains("closing ')'", diagnostic.Explanation, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("matching closing parenthesis", diagnostic.Hint, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Check_MissingParameterColon_PreservesParameterNameSpan()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func greet(name string): string {
                return name
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL102" &&
                          diagnostic.Message.Contains("Expected ':' after parameter name"));

        AssertPlaygroundSpan(diagnostic, line: 3, column: 12, length: "name".Length);
        Assert.Equal("func greet(name string): string {", diagnostic.SourceSnippet);
        Assert.Contains("name: Type", diagnostic.Hint, StringComparison.Ordinal);
    }

    [Fact]
    public void Check_MissingFieldColon_PreservesFieldNameSpan()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            class User {
                Name string
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL102" &&
                          diagnostic.Message.Contains("Expected ':' or ':=' after field name"));

        AssertPlaygroundSpan(diagnostic, line: 4, column: 5, length: "Name".Length);
        Assert.Equal("    Name string", diagnostic.SourceSnippet);
        Assert.Contains("Name: Type", diagnostic.Hint, StringComparison.Ordinal);
    }

    [Fact]
    public void Check_MissingFunctionReturnColon_PreservesFunctionNameSpan()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func answer() int {
                return 1
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL102" &&
                          diagnostic.Message.Contains("Expected ':' before return type"));

        AssertPlaygroundSpan(diagnostic, line: 3, column: 6, length: "answer".Length);
        Assert.Equal("func answer() int {", diagnostic.SourceSnippet);
        Assert.Contains("func name(...): Type", diagnostic.Hint, StringComparison.Ordinal);
    }

    [Fact]
    public void Check_DefaultParserSpan_PreservesVisibleTokenSpan()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            enum Status: decimal {
                Open
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL101" &&
                          diagnostic.Message.Contains("Unsupported enum backing type"));

        AssertPlaygroundSpan(diagnostic, line: 3, column: 14, length: "decimal".Length);
        Assert.Equal("enum Status: decimal {", diagnostic.SourceSnippet);
    }

    [Fact]
    public void Check_DefaultSemanticSpan_PreservesVisibleTokenSpan()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main(): int {
                let value: var = 42
                return value
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL103" &&
                          diagnostic.Message.Contains("'var' is not a type"));

        AssertPlaygroundSpan(diagnostic, line: 4, column: 16, length: "var".Length);
        Assert.Equal("    let value: var = 42", diagnostic.SourceSnippet);
    }

    [Fact]
    public void Check_MissingFileImport_PreservesQuotedPathSpan()
    {
        var result = new PlaygroundCompiler().Check("""
            import "./Missing"

            func main() {
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL701");

        AssertPlaygroundSpan(diagnostic, line: 1, column: 8, length: "\"./Missing\"".Length);
        Assert.Equal("import \"./Missing\"", diagnostic.SourceSnippet);
    }

    [Fact]
    public void CheckProject_FileImportCollision_PreservesDuplicateQuotedPathSpan()
    {
        var result = new PlaygroundCompiler().CheckProject(
            [
                new PlaygroundFile("Program.nl", """
                    import "./A"
                    import "./B"

                    func main() {
                    }
                    """),
                new PlaygroundFile("A.nl", """
                    class Shared {
                    }
                    """),
                new PlaygroundFile("B.nl", """
                    class Shared {
                    }
                    """)
            ],
            "Program.nl");

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL702" &&
                          diagnostic.Message.Contains("Shared", StringComparison.Ordinal));

        AssertPlaygroundSpan(diagnostic, line: 2, column: 8, length: "\"./B\"".Length);
        Assert.Equal("import \"./B\"", diagnostic.SourceSnippet);
        Assert.NotNull(diagnostic.Suggestion);
        Assert.NotNull(diagnostic.Hint);
        Assert.Contains("alias", diagnostic.Suggestion);
        Assert.Contains("\"./A\"", diagnostic.Hint);
        Assert.Contains("\"./B\"", diagnostic.Hint);
    }

    [Fact]
    public void Check_MissingInitializer_PreservesVisibleAnchorSpanForMarkers()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                name :=
                    greeting := "hi"
                print greeting
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL102" &&
                          diagnostic.Message.Contains("Expected an initializer expression after ':='"));

        Assert.Equal(4, diagnostic.Line);
        Assert.Equal(10, diagnostic.Column);
        Assert.Equal(":=".Length, diagnostic.Length);
        Assert.Equal("    name :=", diagnostic.SourceSnippet);
        Assert.Contains("initializer expression", diagnostic.Explanation, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL101");
        Assert.DoesNotContain(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL301" && diagnostic.Message.Contains("greeting"));
        Assert.DoesNotContain(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL001" && diagnostic.Message.Contains("name"));
    }

    [Fact]
    public void Check_MissingKeywordsAndKeywordExpressions_PreserveVisibleKeywordSpans()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                foreach item items {
                    print item
                }

                if {
                    print "missing condition"
                }

                print
                    value := 1
            }
            """);

        var missingIn = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL102" &&
                          diagnostic.Message.Contains("Expected 'in' between the loop variable and collection"));
        AssertPlaygroundSpan(missingIn, line: 4, column: 5, length: "foreach".Length);

        var missingIfCondition = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL102" &&
                          diagnostic.Message.Contains("Expected a condition expression after 'if'"));
        AssertPlaygroundSpan(missingIfCondition, line: 8, column: 5, length: "if".Length);

        var missingPrintExpression = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL102" &&
                          diagnostic.Message.Contains("Expected an expression to print after 'print'"));
        AssertPlaygroundSpan(missingPrintExpression, line: 12, column: 5, length: "print".Length);
    }

    [Fact]
    public void Check_ThrowMissingExpression_DoesNotMarkFollowingStatementUnreachable()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                throw
                    greeting := "hi"
            }
            """);

        var diagnostic = Assert.Single(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL102" &&
                          diagnostic.Message.Contains("Expected an exception expression after 'throw'"));

        Assert.Equal(4, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("throw".Length, diagnostic.Length);
        Assert.Equal("    throw", diagnostic.SourceSnippet);
        Assert.DoesNotContain(result.Diagnostics,
            diagnostic => diagnostic.Code == "NL312");
    }

    [Fact]
    public void Format_ValidProgram_ReturnsFormattedCode()
    {
        var result = new PlaygroundCompiler().Format("func main(){print 5}");

        Assert.True(result.Ok);
        Assert.Equal("""
            func main() {
                print 5
            }

            """.Replace("\r\n", "\n"), result.FormattedCode);
        Assert.Equal(0, result.Summary.Errors);
    }

    [Fact]
    public void Check_OversizedProgram_ReturnsBoundedError()
    {
        var result = new PlaygroundCompiler().Check(new string('x', PlaygroundCompiler.MaxSourceLength + 1));

        Assert.False(result.Ok);
        Assert.Contains(result.Diagnostics, diagnostic => diagnostic.Code == "PG001");
    }

    [Fact]
    public void Diagnostics_AreDeduplicated()
    {
        var result = new PlaygroundCompiler().Check("""
            public func main() {
                print missing
            }
            """);

        var duplicates = result.Diagnostics
            .GroupBy(diagnostic => new { diagnostic.Code, diagnostic.Line, diagnostic.Column, diagnostic.Message })
            .Where(group => group.Count() > 1)
            .ToArray();

        Assert.Empty(duplicates);
    }

    [Fact]
    public void Complete_ReturnsKeywordAndSemanticCompletions()
    {
        var result = new PlaygroundCompiler().Complete(
            [new PlaygroundFile("Program.nl", """
                package Playground

                func Add(a: int, b: int): int {
                    return a + b
                }

                func main() {
                    value := Add(1, 2)
                    pri
                }
                """)],
            "Program.nl",
            9,
            7);

        Assert.Contains(result.Items, item => item.Label == "print");
        Assert.Contains(result.Items, item => item.Label == "Add");
    }

    [Fact]
    public void Complete_MemberAccess_ReturnsSourceDefinedMethodsAndProperties()
    {
        const string source = """
            package Playground

            record Todo {
                Id: int
                Title: string
                Done: bool
            }

            class TodoFormatter(prefix: string) {
                func Format(todo: Todo): string {
                    return $"{prefix} #{todo.Id}: {todo.Title}"
                }
            }

            func main() {
                todo := new Todo { Id: 1, Title: "Try N#", Done: false }
                formatter := new TodoFormatter("task")
                print formatter.Format(todo)
                print todo.Id
            }
            """;

        var formatterLine = LineNumberContaining(source, "formatter.Format");
        var formatterResult = new PlaygroundCompiler().Complete(
            [new PlaygroundFile("Program.nl", source)],
            "Program.nl",
            formatterLine,
            ColumnAfter(source, formatterLine, "formatter."));

        var format = Assert.Single(formatterResult.Items.Where(item => item.Label == "Format"));
        Assert.Equal("method", format.Kind);
        Assert.Contains("Todo", format.Detail);
        Assert.Contains("string", format.Detail);

        var todoLine = LineNumberContaining(source, "todo.Id");
        var todoResult = new PlaygroundCompiler().Complete(
            [new PlaygroundFile("Program.nl", source)],
            "Program.nl",
            todoLine,
            ColumnAfter(source, todoLine, "todo."));

        AssertCompletion(todoResult, "Id", "int");
        AssertCompletion(todoResult, "Title", "string");
        AssertCompletion(todoResult, "Done", "bool");
    }

    [Fact]
    public void Complete_MemberAccess_WorksAfterJustTypedDot()
    {
        const string source = """
            package Playground

            class TodoFormatter {
                func Format(): string {
                    return "ok"
                }
            }

            func main() {
                formatter := new TodoFormatter()
                formatter.
            }
            """;

        var line = LineNumberContaining(source, "formatter.");
        var result = new PlaygroundCompiler().Complete(
            [new PlaygroundFile("Program.nl", source)],
            "Program.nl",
            line,
            ColumnAfter(source, line, "formatter."));

        Assert.Contains(result.Items, item => item.Label == "Format" && item.Kind == "method");
    }

    [Fact]
    public void Complete_MemberAccess_ReturnsStringMembersForInterpolatedStringLiteral()
    {
        const string source = """
            $"this is a string".
            """;

        var result = new PlaygroundCompiler().Complete(
            [new PlaygroundFile("Program.nl", source)],
            "Program.nl",
            1,
            ColumnAfter(source, 1, "$\"this is a string\"."));

        Assert.Equal("MemberAccess", result.Context);
        Assert.Equal("System.String", result.ReceiverType);
        Assert.Contains(result.Items, item => item.Label == "Length" && item.Kind == "property");
        Assert.Contains(result.Items, item => item.Label == "ToUpper" && item.Kind == "method");
    }

    [Fact]
    public void Check_StringLiteralUnknownMember_ReturnsUndefinedMemberDiagnostic()
    {
        var result = new PlaygroundCompiler().Check("""
            package Playground

            func main() {
                print "asdfasdfasdf".ToUp()
            }
            """);

        Assert.False(result.Ok);
        var diagnostic = Assert.Single(result.Diagnostics, diagnostic =>
            diagnostic.Code == "NL303"
            && diagnostic.Message.Contains("ToUp")
            && diagnostic.Message.Contains("string"));
        AssertPlaygroundSpan(diagnostic, line: 4, column: 26, length: "ToUp".Length);
    }

    [Fact]
    public void Complete_MemberAccess_ReturnsClrStaticInstanceAndChainedMembers()
    {
        const string source = """
            import System

            package Playground

            func main() {
                message := "hello"
                Console.WriteLine(message)
                print Math.Max(1, 2)
                print message.ToUpper().ToLower()
            }
            """;

        var compiler = new PlaygroundCompiler();
        var files = new[] { new PlaygroundFile("Program.nl", source) };

        var messageLine = LineNumberContaining(source, "message.ToUpper");
        var messageResult = compiler.Complete(files, "Program.nl", messageLine, ColumnAfter(source, messageLine, "message."));
        Assert.Contains(messageResult.Items, item => item.Label == "ToUpper" && item.Kind == "method");
        Assert.Contains(messageResult.Items, item => item.Label == "Contains" && item.Kind == "method");

        var consoleLine = LineNumberContaining(source, "Console.WriteLine");
        var consoleResult = compiler.Complete(files, "Program.nl", consoleLine, ColumnAfter(source, consoleLine, "Console."));
        Assert.Contains(consoleResult.Items, item => item.Label == "WriteLine" && item.Kind == "method");

        var mathLine = LineNumberContaining(source, "Math.Max");
        var mathResult = compiler.Complete(files, "Program.nl", mathLine, ColumnAfter(source, mathLine, "Math."));
        Assert.Contains(mathResult.Items, item => item.Label == "Max" && item.Kind == "method");

        var chainedResult = compiler.Complete(files, "Program.nl", messageLine, ColumnAfter(source, messageLine, "ToUpper()."));
        Assert.Contains(chainedResult.Items, item => item.Label == "ToLower" && item.Kind == "method");
        Assert.Contains(chainedResult.Items, item => item.Label == "Length");
    }

    [Fact]
    public void RunProject_ValidProgram_ProducesStdout()
    {
        var example = PlaygroundExamples.All.First(example => example.Id == "01-hello-world");
        var result = new PlaygroundCompiler().RunProject(
            [new PlaygroundFile("Program.nl", example.Code)],
            "Program.nl");

        Assert.True(result.Ok);
        Assert.Equal(0, result.ExitCode);
        Assert.Equal(example.ExpectedOutput, result.Stdout);
        Assert.Equal(2, result.SchemaVersion);
        Assert.Null(result.UnsupportedReason);
    }

    [Fact]
    public void RunProject_InvalidProgram_SkipsExecution()
    {
        var result = new PlaygroundCompiler().RunProject(
            [new PlaygroundFile("Program.nl", """
                package Playground

                func main() {
                    print missing
                }
                """)],
            "Program.nl");

        Assert.False(result.Ok);
        Assert.Equal(1, result.ExitCode);
        Assert.Contains(result.Diagnostics, diagnostic => diagnostic.Code == "NL301");
        Assert.Contains("compiler errors", result.Stderr);
    }

    [Fact]
    public void RunProject_UnsupportedConstruct_ReturnsPG2xxDiagnostic()
    {
        var result = new PlaygroundCompiler().RunProject(
            [new PlaygroundFile("Program.nl", """
                package Playground

                func main() {
                    while false {
                        print "not reached"
                    }
                }
                """)],
            "Program.nl");

        Assert.False(result.Ok);
        Assert.Equal(2, result.ExitCode);
        Assert.NotNull(result.UnsupportedReason);
        Assert.Contains(result.Diagnostics, diagnostic => diagnostic.Code.StartsWith("PG2"));
    }

    [Fact]
    public void Hover_ReturnsInformationForPrimitiveKeywordFallback()
    {
        var result = new PlaygroundCompiler().Hover(
            [new PlaygroundFile("Program.nl", """
                package Playground

                func main() {
                    name: string = "N#"
                    print name
                }
                """)],
            "Program.nl",
            4,
            11);

        Assert.True(result.Ok);
        Assert.NotNull(result.Hover);
        Assert.Contains("string", result.Hover!.Signature);
    }

    [Fact]
    public void CheckProject_AcceptsTutorialProgramAndTestsFiles()
    {
        var lesson = PlaygroundExamples.All.First(example => example.HasTests);
        var result = new PlaygroundCompiler().CheckProject(
            [
                new PlaygroundFile("Program.nl", lesson.Code),
                new PlaygroundFile("Program.tests.nl", lesson.TestsCode!)
            ],
            "Program.nl");

        Assert.Equal(2, result.SchemaVersion);
        Assert.DoesNotContain(result.Diagnostics, diagnostic => diagnostic.Code == "PG900");
    }

    private static int LineNumberContaining(string source, string text)
    {
        var lines = source.Split('\n');
        for (var index = 0; index < lines.Length; index++)
        {
            if (lines[index].Contains(text))
            {
                return index + 1;
            }
        }

        throw new Xunit.Sdk.XunitException($"Could not find line containing '{text}'.");
    }

    private static int ColumnAfter(string source, int line, string text)
    {
        var lineText = source.Split('\n')[line - 1];
        var index = lineText.IndexOf(text, StringComparison.Ordinal);
        if (index < 0)
        {
            throw new Xunit.Sdk.XunitException($"Could not find '{text}' on line {line}.");
        }

        return index + text.Length;
    }

    private static void AssertCompletion(PlaygroundCompletionResponse result, string label, string detail)
    {
        var completion = Assert.Single(result.Items.Where(item => item.Label == label));
        Assert.Contains(detail, completion.Detail);
    }
}
