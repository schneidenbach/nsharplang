using System.Linq;
using Microsoft.Extensions.Logging.Abstractions;
using NSharpLang.Compiler;
using NSharpLang.LanguageServer.Services;
using Xunit;

namespace NSharpLang.Tests;

public class LanguageServerDiagnosticsTests
{
    [Fact]
    public void Diagnostics_InvalidMemberStatementAndBadCall()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///test.nl";

        var source = @"
func main() {
    greeting := ""hello""
    greeting.CompareTo
    greeting.CompareTo()
}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = document!.Diagnostics ?? Enumerable.Empty<CompilerError>();
        Assert.Contains(diagnostics, diagnostic => diagnostic.Code == ErrorCode.MethodGroupUsedAsValue);
        Assert.Contains(diagnostics, diagnostic => diagnostic.Code == ErrorCode.NoMatchingOverload);
    }

    [Fact]
    public void Diagnostics_NSharpNoMatchingOverload_UsesCallableNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///nsharp-overload-spans.nl";

        var source = """
class Processor {
    func Process(x: int): int { return x }
    func Process(x: string): string { return x }
}

func main() {
    p := new Processor()
    p.Process(true)
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.NoMatchingOverload &&
                          diagnostic.Message.Contains("Process"));

        AssertDiagnosticSpan(diagnostic, line: 8, column: 7, length: "Process".Length);
        AssertLspRange(diagnostic, line0: 7, startCharacter: 6, endCharacter: 13);
        Assert.Contains("Process(x: int): int", diagnostic.ContextualHint);
        Assert.Contains("Process(x: string): string", diagnostic.ContextualHint);
    }

    [Fact]
    public void Diagnostics_ErrorTupleResultUseRequiresNullErrorProof()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///error-tuple-result.nl";

        var source = """
func Hi(): int {
    return 1
}

func Main() {
    i, err := Hi()
    if err != null {
        print err
    }

    print i
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.UnverifiedErrorResult);

        Assert.Equal("NL314", diagnostic.DiagnosticId);
        Assert.Contains("'i'", diagnostic.Message);
        Assert.Contains("'err'", diagnostic.Message);
        AssertDiagnosticSpan(diagnostic, line: 11, column: 11, length: "i".Length);
        AssertLspRange(diagnostic, line0: 10, startCharacter: 10, endCharacter: 11);
    }

    [Fact]
    public void Diagnostics_DiscardedMustUseResult_UnderlinesCalleeName()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///discarded-must-use.nl";

        var source = """
[MustUse]
func Compute(): int {
    return 42
}

func Main() {
    Compute()
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.DiscardedMustUseResult);

        Assert.Equal("NL315", diagnostic.DiagnosticId);
        Assert.Contains("'Compute'", diagnostic.Message);
        AssertDiagnosticSpan(diagnostic, line: 7, column: 5, length: "Compute".Length);
        AssertLspRange(diagnostic, line0: 6, startCharacter: 4, endCharacter: 11);
    }

    [Fact]
    public void Diagnostics_UndefinedBareCall_ReportsFunctionNotVariable()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///undefined-bare-call.nl";

        var source = """
func Main() {
    i := Hi()
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);
        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.UndefinedFunction);

        Assert.Equal("Function 'Hi' not found", diagnostic.Message);
        Assert.Contains("function named `Hi`", diagnostic.HumanExplanation);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.UndefinedVariable &&
                          diagnostic.Message.Contains("Hi"));
        AssertDiagnosticSpan(diagnostic, line: 2, column: 10, length: "Hi".Length);
        AssertLspRange(diagnostic, line0: 1, startCharacter: 9, endCharacter: 11);
    }

    [Fact]
    public void Diagnostics_FunctionCallErrors_UnderlineCalleeNameWithExactRanges()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///function-call-spans.nl";

        var source = """
func TakesInt(value: int) {}

func main() {
    TakesInt()
    Unknown()
    TakesInt
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        // NL401: span underlines the callee name; message pluralizes "argument".
        var wrongCount = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.WrongArgumentCount);
        Assert.Equal("Function 'TakesInt' expects 1 argument but got 0", wrongCount.Message);
        AssertDiagnosticSpan(wrongCount, line: 4, column: 5, length: "TakesInt".Length);
        AssertLspRange(wrongCount, line0: 3, startCharacter: 4, endCharacter: 12);

        // NL412: span underlines the bare call name, reported as a function.
        var undefinedFunction = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.UndefinedFunction);
        Assert.Equal("Function 'Unknown' not found", undefinedFunction.Message);
        AssertDiagnosticSpan(undefinedFunction, line: 5, column: 5, length: "Unknown".Length);
        AssertLspRange(undefinedFunction, line0: 4, startCharacter: 4, endCharacter: 11);

        // NL411: span underlines the method name used as a value.
        var methodGroup = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.MethodGroupUsedAsValue);
        Assert.Equal("Method 'TakesInt' must be called or passed to a delegate", methodGroup.Message);
        AssertDiagnosticSpan(methodGroup, line: 6, column: 5, length: "TakesInt".Length);
        AssertLspRange(methodGroup, line0: 5, startCharacter: 4, endCharacter: 12);
    }

    [Fact]
    public void Diagnostics_NoMatchingOverload_PluralizesArgumentCount()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///overload-plural.nl";

        var source = """
class Processor {
    func Process(x: int): int { return x }
    func Process(x: string): string { return x }
}

func main() {
    p := new Processor()
    p.Process(true)
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.NoMatchingOverload);

        Assert.Equal("No overload of 'Process' accepts 1 argument with these types", diagnostic.Message);
        AssertDiagnosticSpan(diagnostic, line: 8, column: 7, length: "Process".Length);
        AssertLspRange(diagnostic, line0: 7, startCharacter: 6, endCharacter: 13);
    }

    [Fact]
    public void Diagnostics_ShadowedLocal_UnderlinesInnerName()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///shadowing.nl";

        var source = """
func Main() {
    count := 1
    if count > 0 {
        count := 2
        print $"{count}"
    }
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);
        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.ShadowedDeclaration);

        Assert.Equal("NL316", diagnostic.DiagnosticId);
        Assert.Contains("'count'", diagnostic.Message);
        // Inner `count := 2` is on line 4 at column 9 (8 spaces of indent + 1).
        AssertDiagnosticSpan(diagnostic, line: 4, column: 9, length: "count".Length);
        AssertLspRange(diagnostic, line0: 3, startCharacter: 8, endCharacter: 13);
    }

    [Fact]
    public void Diagnostics_ShadowedParameter_UnderlinesInnerLocalName()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///shadow-param.nl";

        var source = """
func Greet(name: string) {
    name := "override"
    print name
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);
        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.ShadowedDeclaration);

        // `name := "override"` is on line 2 at column 5 (4 spaces of indent + 1).
        AssertDiagnosticSpan(diagnostic, line: 2, column: 5, length: "name".Length);
        AssertLspRange(diagnostic, line0: 1, startCharacter: 4, endCharacter: 8);
    }

    [Fact]
    public void Diagnostics_ReadBeforeDefiniteAssignment_UnderlinesTheRead()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///definite-assignment.nl";

        var source = """
func Cond(): bool {
    return true
}

func Main() {
    let total: int
    if Cond() {
        total = 5
    }
    print total
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);
        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.DefiniteAssignmentError);

        Assert.Equal("NL304", diagnostic.DiagnosticId);
        Assert.Contains("'total'", diagnostic.Message);
        // `print total` is on line 10; `total` starts at column 11 (4 indent + "print " = 10).
        AssertDiagnosticSpan(diagnostic, line: 10, column: 11, length: "total".Length);
        AssertLspRange(diagnostic, line0: 9, startCharacter: 10, endCharacter: 15);
    }

    [Fact]
    public void Diagnostics_PossibleNullDereference_UsesStableCompilerCode()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///nullable.nl";

        var source = @"
func main() {
    x: string? = ""hello""
    len := x.Length
}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = document!.Diagnostics ?? Enumerable.Empty<CompilerError>();
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.PossibleNullAccess &&
            diagnostic.DiagnosticId == "NL905" &&
            diagnostic.Severity == ErrorSeverity.Error &&
            diagnostic.Suggestion != null &&
            diagnostic.Suggestion.Contains("?.", System.StringComparison.Ordinal));
    }

    [Fact]
    public void Diagnostics_PossibleNullDereference_SquiggleCoversReceiverToken()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///nullable-span.nl";

        var source = "func main() {\n    x: string? = \"hello\"\n    len := x.Length\n}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.PossibleNullAccess && d.DiagnosticId == "NL905");

        // `len := x.Length` — the squiggle must land on the receiver `x`, not the dot or member.
        AssertDiagnosticSpan(diagnostic, line: 3, column: 12, length: "x".Length);
        AssertLspRange(diagnostic, line0: 2, startCharacter: 11, endCharacter: 12);
    }

    [Fact]
    public void Diagnostics_PossibleNullDereference_UnderlinesReceiverExpression()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///null-receiver-span.nl";

        // Receiver `customer` starts at column 12 (1-based) on line 3; the squiggle
        // must cover the whole receiver token, not the '.' or the member name.
        var source = "func main() {\n    customer: string? = \"Ada\"\n    len := customer.Length\n}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();
        var nullAccess = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.PossibleNullAccess);

        Assert.Equal(ErrorSeverity.Error, nullAccess.Severity);
        AssertDiagnosticSpan(nullAccess, line: 3, column: 12, length: "customer".Length);
        AssertLspRange(nullAccess, line0: 2, startCharacter: 11, endCharacter: 11 + "customer".Length);
    }

    [Fact]
    public void Diagnostics_NullableValueAccess_SquiggleCoversValueToken()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///nullable-value-span.nl";

        var source = "func Main(input: int?): int {\n    return input.Value\n}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.NullabilityWarning && d.Message.Contains(".Value"));

        Assert.Equal(ErrorSeverity.Error, diagnostic.Severity);
        // `return input.Value` — the squiggle must cover the `Value` member token.
        AssertDiagnosticSpan(diagnostic, line: 2, column: 18, length: "Value".Length);
        AssertLspRange(diagnostic, line0: 1, startCharacter: 17, endCharacter: 22);
    }

    [Fact]
    public void Diagnostics_PossibleNullIndex_UnderlinesReceiverExpression()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///null-index-span.nl";

        var source = "func first(items: int[]?): int {\n    return items[0]\n}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();
        var nullAccess = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.PossibleNullAccess);

        Assert.Equal(ErrorSeverity.Error, nullAccess.Severity);
        // `items` starts at column 12 (1-based) on line 2.
        AssertDiagnosticSpan(nullAccess, line: 2, column: 12, length: "items".Length);
        AssertLspRange(nullAccess, line0: 1, startCharacter: 11, endCharacter: 11 + "items".Length);
    }

    [Fact]
    public void Diagnostics_RedundantMustUnwrap_SquiggleCoversMustKeyword()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///redundant-must-span.nl";

        var source = "func Main(input: int?): int {\n    if input.HasValue {\n        return must input\n    }\n    return 0\n}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.NullabilityWarning && d.Message.Contains("redundant"));

        Assert.Equal(ErrorSeverity.Error, diagnostic.Severity);
        // `        return must input` — the squiggle must cover the `must` keyword (4 chars).
        AssertDiagnosticSpan(diagnostic, line: 3, column: 16, length: "must".Length);
        AssertLspRange(diagnostic, line0: 2, startCharacter: 15, endCharacter: 19);
    }

    [Fact]
    public void Diagnostics_SemanticErrors_UseExpectedTokenSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///semantic-spans.nl";

        var source = """
func TakesInt(value: int) {}
func main() {
    maybeCustomerName: string? = "Ada"
    print maybeCustomerName.Length
    TakesInt("oops")
    TakesInt()
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var nullAccess = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.PossibleNullAccess);
        Assert.Equal(4, nullAccess.Line);
        Assert.Equal(11, nullAccess.Column);
        Assert.Equal("maybeCustomerName".Length, nullAccess.Length);

        var wrongArgument = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("Cannot pass"));
        Assert.Equal(5, wrongArgument.Line);
        Assert.Equal(14, wrongArgument.Column);
        Assert.Equal("\"oops\"".Length, wrongArgument.Length);

        var wrongCount = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.WrongArgumentCount);
        Assert.Equal(6, wrongCount.Line);
        Assert.Equal(5, wrongCount.Column);
        Assert.Equal("TakesInt".Length, wrongCount.Length);

        var nullAccessLsp = LspDiagnosticConverter.FromCompilerError(nullAccess);
        Assert.Equal(3, (int)nullAccessLsp.Range.Start.Line);
        Assert.Equal(10, (int)nullAccessLsp.Range.Start.Character);
        Assert.Equal(27, (int)nullAccessLsp.Range.End.Character);

        var wrongArgumentLsp = LspDiagnosticConverter.FromCompilerError(wrongArgument);
        Assert.Equal(4, (int)wrongArgumentLsp.Range.Start.Line);
        Assert.Equal(13, (int)wrongArgumentLsp.Range.Start.Character);
        Assert.Equal(19, (int)wrongArgumentLsp.Range.End.Character);

        var wrongCountLsp = LspDiagnosticConverter.FromCompilerError(wrongCount);
        Assert.Equal(5, (int)wrongCountLsp.Range.Start.Line);
        Assert.Equal(4, (int)wrongCountLsp.Range.Start.Character);
        Assert.Equal(12, (int)wrongCountLsp.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_TypeMismatches_UseOffendingExpressionSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///type-mismatch-spans.nl";

        var source = """
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
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var expressionBodyMismatch = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("ExpressionBodyMismatch"));
        AssertDiagnosticSpan(expressionBodyMismatch, line: 4, column: 39, length: "\"bad\"".Length);
        AssertLspRange(expressionBodyMismatch, line0: 3, startCharacter: 38, endCharacter: 43);

        var expressionBodyRequiresReturnType = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("ExpressionBodyRequiresReturnType"));
        AssertDiagnosticSpan(expressionBodyRequiresReturnType, line: 6, column: 6, length: "ExpressionBodyRequiresReturnType".Length);
        AssertLspRange(expressionBodyRequiresReturnType, line0: 5, startCharacter: 5, endCharacter: 37);

        var localInitializer = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 9 &&
                          diagnostic.Message == "Type mismatch");
        AssertDiagnosticSpan(localInitializer, line: 9, column: 21, length: "\"hi\"".Length);
        AssertLspRange(localInitializer, line0: 8, startCharacter: 20, endCharacter: 24);

        var voidAssignment = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("void"));
        AssertDiagnosticSpan(voidAssignment, line: 10, column: 17, length: "TakesVoid".Length);
        AssertLspRange(voidAssignment, line0: 9, startCharacter: 16, endCharacter: 25);

        var ifCondition = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 11 &&
                          diagnostic.Message == "Type mismatch");
        AssertDiagnosticSpan(ifCondition, line: 11, column: 8, length: "\"yes\"".Length);
        AssertLspRange(ifCondition, line0: 10, startCharacter: 7, endCharacter: 12);

        var returnValue = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("main") &&
                          diagnostic.Message.Contains("returns string"));
        AssertDiagnosticSpan(returnValue, line: 12, column: 16, length: "\"bad\"".Length);
        AssertLspRange(returnValue, line0: 11, startCharacter: 15, endCharacter: 20);
    }

    [Fact]
    public void Diagnostics_EnumMemberInitializerTypeMismatches_UseInitializerValueSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///enum-value-spans.nl";

        var source = """
enum HttpCode: int {
    Ok = "ok"
}

enum Label: string {
    Ready = 1
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var numericValue = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("'Ok'"));
        AssertDiagnosticSpan(numericValue, line: 2, column: 10, length: "\"ok\"".Length);
        AssertLspRange(numericValue, line0: 1, startCharacter: 9, endCharacter: 13);

        var stringValue = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("'Ready'"));
        AssertDiagnosticSpan(stringValue, line: 6, column: 13, length: "1".Length);
        AssertLspRange(stringValue, line0: 5, startCharacter: 12, endCharacter: 13);
    }

    [Fact]
    public void Diagnostics_ControlFlowAndCollectionTypeMismatches_UseOffendingExpressionSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///control-flow-type-mismatch-spans.nl";

        var source = """
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
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var whileCondition = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("'while'"));
        AssertDiagnosticSpan(whileCondition, line: 2, column: 11, length: "\"loop\"".Length);
        AssertLspRange(whileCondition, line0: 1, startCharacter: 10, endCharacter: 16);

        var forCondition = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("'for'"));
        AssertDiagnosticSpan(forCondition, line: 5, column: 17, length: "\"loop\"".Length);
        AssertLspRange(forCondition, line0: 4, startCharacter: 16, endCharacter: 22);

        var ternaryCondition = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("ternary expression"));
        AssertDiagnosticSpan(ternaryCondition, line: 9, column: 15, length: "\"maybe\"".Length);
        AssertLspRange(ternaryCondition, line0: 8, startCharacter: 14, endCharacter: 21);

        var arrayElement = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("All elements in an array"));
        AssertDiagnosticSpan(arrayElement, line: 10, column: 20, length: "\"two\"".Length);
        AssertLspRange(arrayElement, line0: 9, startCharacter: 19, endCharacter: 24);

        var matchGuard = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.GuardNotBoolean);
        AssertDiagnosticSpan(matchGuard, line: 12, column: 16, length: "\"guard\"".Length);
        AssertLspRange(matchGuard, line0: 11, startCharacter: 15, endCharacter: 22);

        var matchArm = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("All match arms"));
        AssertDiagnosticSpan(matchArm, line: 13, column: 14, length: "12345".Length);
        AssertLspRange(matchArm, line0: 12, startCharacter: 13, endCharacter: 18);
    }

    [Fact]
    public void Diagnostics_LoopControlOutsideLoop_UseFullKeywordSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///loop-control-spans.nl";

        var source = """
func main() {
    break
    continue
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var breakDiagnostic = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("'break'"));
        AssertDiagnosticSpan(breakDiagnostic, line: 2, column: 5, length: "break".Length);
        AssertLspRange(breakDiagnostic, line0: 1, startCharacter: 4, endCharacter: 9);

        var continueDiagnostic = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("'continue'"));
        AssertDiagnosticSpan(continueDiagnostic, line: 3, column: 5, length: "continue".Length);
        AssertLspRange(continueDiagnostic, line0: 2, startCharacter: 4, endCharacter: 12);
    }

    [Fact]
    public void Diagnostics_ReturnOutsideFunctionAndTargetlessDefault_UseFullKeywordSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///keyword-semantic-spans.tests.nl";

        var source = """
func main() {
    value := default
}

test "does not return" {
    return
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var targetlessDefault = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.CannotInferType &&
                          diagnostic.Message.Contains("'default'"));
        AssertDiagnosticSpan(targetlessDefault, line: 2, column: 14, length: "default".Length);
        AssertLspRange(targetlessDefault, line0: 1, startCharacter: 13, endCharacter: 20);

        var returnOutsideFunction = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("'return' can only"));
        AssertDiagnosticSpan(returnOutsideFunction, line: 6, column: 5, length: "return".Length);
        AssertLspRange(returnOutsideFunction, line0: 5, startCharacter: 4, endCharacter: 10);
    }

    [Fact]
    public void Diagnostics_ReadonlyAssignment_UsesAssignedFieldNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///readonly-assignment-spans.nl";

        var source = """
class Account {
    readonly id: string = "initial"

    func Change() {
        id = "next"
        this.id = "again"
    }
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var directAssignment = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ReadonlyAssignment &&
                          diagnostic.Line == 5);
        AssertDiagnosticSpan(directAssignment, line: 5, column: 9, length: "id".Length);
        AssertLspRange(directAssignment, line0: 4, startCharacter: 8, endCharacter: 10);

        var memberAssignment = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ReadonlyAssignment &&
                          diagnostic.Line == 6);
        AssertDiagnosticSpan(memberAssignment, line: 6, column: 14, length: "id".Length);
        AssertLspRange(memberAssignment, line0: 5, startCharacter: 13, endCharacter: 15);
    }

    [Fact]
    public void Diagnostics_UndefinedMember_UsesMemberNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///undefined-member-spans.nl";

        var source = """
func main() {
    print "asdf".ToUp()
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.UndefinedMember &&
                          diagnostic.Message.Contains("ToUp"));

        AssertDiagnosticSpan(diagnostic, line: 2, column: 18, length: "ToUp".Length);
        AssertLspRange(diagnostic, line0: 1, startCharacter: 17, endCharacter: 21);
    }

    [Fact]
    public void Diagnostics_FileImportAliasMissingSymbol_UsesRequestedSymbolSpan()
    {
        var tempRoot = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"nsharp-lsp-alias-symbol-span-{System.Guid.NewGuid():N}");
        System.IO.Directory.CreateDirectory(tempRoot);

        try
        {
            System.IO.File.WriteAllText(System.IO.Path.Combine(tempRoot, "project.yml"), """
name: AliasSymbolSpan
version: 1.0.0
targetFramework: net10.0
outputType: exe
entry: Program.nl
""");

            System.IO.File.WriteAllText(System.IO.Path.Combine(tempRoot, "Helpers.nl"), """
func PresentThing(): int {
    return 1
}
""");

            var programPath = System.IO.Path.Combine(tempRoot, "Program.nl");
            var source = """
import "./Helpers" as Lib

func main() {
    Lib.MissingThing()
}
""";
            System.IO.File.WriteAllText(programPath, source);

            var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
            documentManager.UpdateDocument(new System.Uri(programPath).AbsoluteUri, source, version: 1);

            var document = documentManager.GetDocument(new System.Uri(programPath).AbsoluteUri);
            Assert.NotNull(document);

            var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
                diagnostic => diagnostic.Code == ErrorCode.UndefinedMember &&
                              diagnostic.Message.Contains("MissingThing"));

            AssertDiagnosticSpan(diagnostic, line: 4, column: 9, length: "MissingThing".Length);
            AssertLspRange(diagnostic, line0: 3, startCharacter: 8, endCharacter: 20);
        }
        finally
        {
            if (System.IO.Directory.Exists(tempRoot))
            {
                System.IO.Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    [Fact]
    public void Diagnostics_MissingFileImport_UsesQuotedPathSpan()
    {
        var tempRoot = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"nsharp-lsp-missing-import-span-{System.Guid.NewGuid():N}");
        System.IO.Directory.CreateDirectory(tempRoot);

        try
        {
            System.IO.File.WriteAllText(System.IO.Path.Combine(tempRoot, "project.yml"), """
name: MissingImportSpan
version: 1.0.0
targetFramework: net10.0
outputType: exe
entry: Program.nl
""");

            var programPath = System.IO.Path.Combine(tempRoot, "Program.nl");
            var source = """
import "./Missing"

func main() {
}
""";
            System.IO.File.WriteAllText(programPath, source);

            var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
            documentManager.UpdateDocument(new System.Uri(programPath).AbsoluteUri, source, version: 1);

            var document = documentManager.GetDocument(new System.Uri(programPath).AbsoluteUri);
            Assert.NotNull(document);

            var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
                diagnostic => diagnostic.Code == ErrorCode.ImportNotFound);

            AssertDiagnosticSpan(diagnostic, line: 1, column: 8, length: "\"./Missing\"".Length);
            AssertLspRange(diagnostic, line0: 0, startCharacter: 7, endCharacter: 18);
        }
        finally
        {
            if (System.IO.Directory.Exists(tempRoot))
            {
                System.IO.Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    [Fact]
    public void Diagnostics_FileImportCollision_UsesDuplicateQuotedPathSpan()
    {
        var tempRoot = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"nsharp-lsp-import-collision-span-{System.Guid.NewGuid():N}");
        System.IO.Directory.CreateDirectory(tempRoot);

        try
        {
            System.IO.File.WriteAllText(System.IO.Path.Combine(tempRoot, "project.yml"), """
name: ImportCollisionSpan
version: 1.0.0
targetFramework: net10.0
outputType: exe
entry: Program.nl
""");

            System.IO.File.WriteAllText(System.IO.Path.Combine(tempRoot, "A.nl"), """
class Shared {
}
""");

            System.IO.File.WriteAllText(System.IO.Path.Combine(tempRoot, "B.nl"), """
class Shared {
}
""");

            var programPath = System.IO.Path.Combine(tempRoot, "Program.nl");
            var source = """
import "./A"
import "./B"

func main() {
}
""";
            System.IO.File.WriteAllText(programPath, source);

            var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
            documentManager.UpdateDocument(new System.Uri(programPath).AbsoluteUri, source, version: 1);

            var document = documentManager.GetDocument(new System.Uri(programPath).AbsoluteUri);
            Assert.NotNull(document);

            var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
                diagnostic => diagnostic.Code == ErrorCode.ImportCollision &&
                              diagnostic.Message.Contains("Shared"));

            AssertDiagnosticSpan(diagnostic, line: 2, column: 8, length: "\"./B\"".Length);
            AssertLspRange(diagnostic, line0: 1, startCharacter: 7, endCharacter: 12);
            Assert.NotNull(diagnostic.Suggestion);
            Assert.NotNull(diagnostic.ContextualHint);
            Assert.Contains("alias", diagnostic.Suggestion);
            Assert.Contains("\"./A\"", diagnostic.ContextualHint);
            Assert.Contains("\"./B\"", diagnostic.ContextualHint);
        }
        finally
        {
            if (System.IO.Directory.Exists(tempRoot))
            {
                System.IO.Directory.Delete(tempRoot, recursive: true);
            }
        }
    }

    [Fact]
    public void Diagnostics_UnreachableStatement_UsesUnreachableKeywordSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unreachable-statement-spans.nl";

        var source = """
func main() {
    return
    print "after"
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var unreachableDiagnostic = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.UnreachableStatement);
        AssertDiagnosticSpan(unreachableDiagnostic, line: 3, column: 5, length: "print".Length);
        AssertLspRange(unreachableDiagnostic, line0: 2, startCharacter: 4, endCharacter: 9);
    }

    [Fact]
    public void Diagnostics_InvalidVariableDeclarations_UseFullNameSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///variable-declaration-spans.nl";

        var source = """
func main() {
    const answer: int
    let value
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var constWithoutInitializer = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("'const'"));
        AssertDiagnosticSpan(constWithoutInitializer, line: 2, column: 11, length: "answer".Length);
        AssertLspRange(constWithoutInitializer, line0: 1, startCharacter: 10, endCharacter: 16);

        var unknownVariableType = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("determine the type"));
        AssertDiagnosticSpan(unknownVariableType, line: 3, column: 9, length: "value".Length);
        AssertLspRange(unknownVariableType, line0: 2, startCharacter: 8, endCharacter: 13);
    }

    [Fact]
    public void Diagnostics_InvalidGenericConstraints_UseOffendingConstraintSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///generic-constraint-spans.nl";

        var source = """
func BadClassStruct<T>(value: T): T where T : class, struct {
    return value
}

func BadStructNew<T>(value: T): T where T : struct, new() {
    return value
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var classStructConflict = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("both 'class' and 'struct'"));
        AssertDiagnosticSpan(classStructConflict, line: 1, column: 54, length: "struct".Length);
        AssertLspRange(classStructConflict, line0: 0, startCharacter: 53, endCharacter: 59);

        var structNewConflict = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("Cannot combine 'struct' and 'new()'"));
        AssertDiagnosticSpan(structNewConflict, line: 5, column: 53, length: "new()".Length);
        AssertLspRange(structNewConflict, line0: 4, startCharacter: 52, endCharacter: 57);
    }

    [Fact]
    public void Diagnostics_AssignmentAndOperatorTypeMismatches_UseSpecificExpressionSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///assignment-operator-type-mismatch-spans.nl";

        var source = """
func main() {
    x := 0
    x = "text"

    oneBad := 1 - "two"
    bothBad := "one" - "two"
    logicalRight := true && 1
    logicalBoth := 1 && 2

    print x
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var assignmentValue = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 3 &&
                          diagnostic.Message == "Type mismatch");
        AssertDiagnosticSpan(assignmentValue, line: 3, column: 9, length: "\"text\"".Length);
        AssertLspRange(assignmentValue, line0: 2, startCharacter: 8, endCharacter: 14);

        var arithmeticRightOperand = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 5 &&
                          diagnostic.Message.Contains("right side"));
        AssertDiagnosticSpan(arithmeticRightOperand, line: 5, column: 19, length: "\"two\"".Length);
        AssertLspRange(arithmeticRightOperand, line0: 4, startCharacter: 18, endCharacter: 23);

        var arithmeticOperator = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 6 &&
                          diagnostic.Message.Contains("I found 'string' and 'string'"));
        AssertDiagnosticSpan(arithmeticOperator, line: 6, column: 22, length: "-".Length);
        AssertLspRange(arithmeticOperator, line0: 5, startCharacter: 21, endCharacter: 22);

        var logicalRightOperand = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 7 &&
                          diagnostic.Message.Contains("right side"));
        AssertDiagnosticSpan(logicalRightOperand, line: 7, column: 29, length: "1".Length);
        AssertLspRange(logicalRightOperand, line0: 6, startCharacter: 28, endCharacter: 29);

        var logicalOperator = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Line == 8 &&
                          diagnostic.Message.Contains("I found 'int' and 'int'"));
        AssertDiagnosticSpan(logicalOperator, line: 8, column: 22, length: "&&".Length);
        AssertLspRange(logicalOperator, line0: 7, startCharacter: 21, endCharacter: 23);
    }

    [Fact]
    public void Diagnostics_PatternErrors_UseSpecificPatternSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///pattern-error-spans.nl";

        var source = """
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
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var missingCase = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidPattern &&
                          diagnostic.Line == 13 &&
                          diagnostic.Message.Contains("'Result.Unknown'"));
        AssertDiagnosticSpan(missingCase, line: 13, column: 9, length: "Result.Unknown".Length);
        AssertLspRange(missingCase, line0: 12, startCharacter: 8, endCharacter: 22);

        var missingUnionProperty = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidPattern &&
                          diagnostic.Line == 14 &&
                          diagnostic.Message.Contains("'missing'"));
        AssertDiagnosticSpan(missingUnionProperty, line: 14, column: 26, length: "missing".Length);
        AssertLspRange(missingUnionProperty, line0: 13, startCharacter: 25, endCharacter: 32);

        var missingObjectProperty = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidPattern &&
                          diagnostic.Line == 20 &&
                          diagnostic.Message.Contains("'Missing'"));
        AssertDiagnosticSpan(missingObjectProperty, line: 20, column: 11, length: "Missing".Length);
        AssertLspRange(missingObjectProperty, line0: 19, startCharacter: 10, endCharacter: 17);

        var listPatternMismatch = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.PatternTypeMismatch);
        AssertDiagnosticSpan(listPatternMismatch, line: 26, column: 9, length: "[first, ..]".Length);
        AssertLspRange(listPatternMismatch, line0: 25, startCharacter: 8, endCharacter: 19);
    }

    [Fact]
    public void Diagnostics_DeclarationErrors_UseDeclarationNameSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///declaration-spans.nl";

        var source = """
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

func BadParamsType(params count: int) {}

func main() {
    value := 1
    value := 2
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var duplicateFunction = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Line == 3 &&
                          diagnostic.Message.Contains("'Duplicate'"));
        AssertDiagnosticSpan(duplicateFunction, line: 3, column: 6, length: "Duplicate".Length);
        AssertLspRange(duplicateFunction, line0: 2, startCharacter: 5, endCharacter: 14);

        var duplicateType = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Line == 6 &&
                          diagnostic.Message.Contains("Thing"));
        AssertDiagnosticSpan(duplicateType, line: 6, column: 7, length: "Thing".Length);

        var duplicateEnumMember = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Line == 10 &&
                          diagnostic.Message.Contains("enum member"));
        AssertDiagnosticSpan(duplicateEnumMember, line: 10, column: 5, length: "Pending".Length);

        var duplicateUnionCase = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Line == 15 &&
                          diagnostic.Message.Contains("union case"));
        AssertDiagnosticSpan(duplicateUnionCase, line: 15, column: 5, length: "Success".Length);

        var paramsNotLast = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ParamsNotLast);
        AssertDiagnosticSpan(paramsNotLast, line: 18, column: 23, length: "rest".Length);
        AssertLspRange(paramsNotLast, line0: 17, startCharacter: 22, endCharacter: 26);

        var requiredAfterOptional = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.RequiredParameterAfterOptional);
        AssertDiagnosticSpan(requiredAfterOptional, line: 20, column: 34, length: "second".Length);
        AssertLspRange(requiredAfterOptional, line0: 19, startCharacter: 33, endCharacter: 39);

        var invalidDefault = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidDefaultParameterValue);
        AssertDiagnosticSpan(invalidDefault, line: 22, column: 30, length: "makeValue".Length);
        AssertLspRange(invalidDefault, line0: 21, startCharacter: 29, endCharacter: 38);

        var invalidParamsType = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidParameter);
        AssertDiagnosticSpan(invalidParamsType, line: 24, column: 27, length: "count".Length);
        AssertLspRange(invalidParamsType, line0: 23, startCharacter: 26, endCharacter: 31);

        var duplicateLocal = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Line == 28 &&
                          diagnostic.Message.Contains("'value'"));
        AssertDiagnosticSpan(duplicateLocal, line: 28, column: 5, length: "value".Length);
    }

    [Fact]
    public void Diagnostics_OperatorOverloadErrors_UseOperatorKeywordAndSymbolSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///operator-overload-spans.nl";

        var source = """
class Vector {
    X: int

    func operator %(a: Vector, b: Vector, c: Vector): Vector {
        return a
    }

    static func operator true(a: Vector, b: Vector): bool {
        return true
    }
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var missingStatic = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.InvalidOperatorOverload);
        AssertDiagnosticSpan(missingStatic, line: 4, column: 10, length: "operator".Length);
        AssertLspRange(missingStatic, line0: 3, startCharacter: 9, endCharacter: 17);

        var moduloArity = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.OperatorParameterCount &&
                          diagnostic.Message.Contains("'%'"));
        AssertDiagnosticSpan(moduloArity, line: 4, column: 19, length: "%".Length);
        AssertLspRange(moduloArity, line0: 3, startCharacter: 18, endCharacter: 19);

        var trueArity = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.OperatorParameterCount &&
                          diagnostic.Message.Contains("'true'"));
        AssertDiagnosticSpan(trueArity, line: 8, column: 26, length: "true".Length);
        AssertLspRange(trueArity, line0: 7, startCharacter: 25, endCharacter: 29);
    }

    [Fact]
    public void Diagnostics_DuplicateTestLifecycleBlocks_UseFullKeywordSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///duplicate-lifecycle.tests.nl";

        var source = """
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
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var duplicateSetup = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Message.Contains("setup block"));
        AssertDiagnosticSpan(duplicateSetup, line: 5, column: 1, length: "setup".Length);
        AssertLspRange(duplicateSetup, line0: 4, startCharacter: 0, endCharacter: 5);

        var duplicateTeardown = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.DuplicateDeclaration &&
                          diagnostic.Message.Contains("teardown block"));
        AssertDiagnosticSpan(duplicateTeardown, line: 13, column: 1, length: "teardown".Length);
        AssertLspRange(duplicateTeardown, line0: 12, startCharacter: 0, endCharacter: 8);
    }

    [Fact]
    public void Diagnostics_ReturnValueWithoutReturnType_ExplainsImplicitVoid()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///return-value.nl";

        var source = @"
func Hi() {
    return 42
}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.TypeMismatch);

        var message = diagnostic.FormatForTooling(includeCode: true, includeLocation: false);
        Assert.Contains("NL202: Function 'Hi' returns int but has no return type", message);
        Assert.Contains("N# treats it as `void`", message);
        Assert.Contains("Add `: int`", message);
        Assert.Contains("func Hi() {", message);
        AssertDiagnosticSpan(diagnostic, line: 2, column: 6, length: "Hi".Length);
        AssertLspRange(diagnostic, line0: 1, startCharacter: 5, endCharacter: 7);
    }

    private static void AssertDiagnosticSpan(CompilerError diagnostic, int line, int column, int length)
    {
        Assert.Equal(line, diagnostic.Line);
        Assert.Equal(column, diagnostic.Column);
        Assert.Equal(length, diagnostic.Length);
    }

    private static void AssertLspRange(CompilerError diagnostic, int line0, int startCharacter, int endCharacter)
    {
        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(line0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(startCharacter, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(endCharacter, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_InvalidMemberCallsAndReturnType_AreAllPublished()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///invalid-member-calls.nl";

        var source = """
package HelloWorld

func Hi() {
    "asdf".toUp()
    asdf := "asdf"
    asdf.sdd()
    return 42
}
""";

        documentManager.MarkEditorOpen(uri);
        documentManager.UpdateDocument(uri, source, version: 1);

        var publications = documentManager.GetDiagnosticsToPublish(uri);
        var diagnostics = Assert.Single(publications).CompilerDiagnostics.ToList();

        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.UndefinedMember &&
            diagnostic.Message.Contains("toUp") &&
            diagnostic.Line == 4);
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.UndefinedMember &&
            diagnostic.Message.Contains("sdd") &&
            diagnostic.Line == 6);
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.TypeMismatch &&
            diagnostic.Message.Contains("returns int but has no return type") &&
            diagnostic.Line == 3 &&
            diagnostic.Column == 6 &&
            diagnostic.Length == "Hi".Length);
    }

    [Fact]
    public void Diagnostics_MalformedEditingBuffer_PublishesHighSignalProblems()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///malformed.nl";

        var source = """
class User {
    Name: string
}

func main() {
    first := 1 +
    Console.WriteLine(undefinedFromLsp)
    user := new User { Name = "Ada" }
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.ExpectedToken &&
            diagnostic.Line == 6 &&
            diagnostic.Column == 14 &&
            diagnostic.Length == "1 +".Length &&
            diagnostic.Message.Contains("Expected expression after '+'"));
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.InvalidSyntax &&
            diagnostic.Line == 8 &&
            diagnostic.Column == 24 &&
            diagnostic.Length == "Name".Length &&
            diagnostic.Message.Contains("Object initializer member 'Name' uses '='"));
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.UndefinedVariable &&
            diagnostic.Message.Contains("undefinedFromLsp"));
        Assert.DoesNotContain(diagnostics, diagnostic =>
            diagnostic.Message.Contains("<error>", System.StringComparison.Ordinal));
        Assert.True(diagnostics.Count <= 6,
            $"Expected bounded diagnostics, got {diagnostics.Count}: {string.Join("; ", diagnostics.Select(d => $"{d.DiagnosticId} {d.Message}"))}");
    }

    [Fact]
    public void Diagnostics_ObjectInitializerMissingValue_UsesPropertyNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///object-initializer-missing-value.nl";

        var source = """
class User {
    Name: string
}

func main() {
    user := new User { Name: }
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected a value for object initializer member 'Name'"));

        AssertDiagnosticSpan(diagnostic, line: 6, column: 24, length: "Name".Length);
        AssertLspRange(diagnostic, line0: 5, startCharacter: 23, endCharacter: 27);
    }

    [Theory]
    [InlineData("func () {\n}", "Expected function name", "func")]
    [InlineData("class {\n}", "Expected class name", "class")]
    [InlineData("struct {\n}", "Expected struct name", "struct")]
    [InlineData("record {\n}", "Expected record name", "record")]
    [InlineData("interface {\n}", "Expected interface name", "interface")]
    [InlineData("union {\n}", "Expected union name", "union")]
    [InlineData("enum {\n}", "Expected enum name", "enum")]
    [InlineData("type = int", "Expected type alias name", "type")]
    public void Diagnostics_MissingDeclarationName_UsesDeclarationKeywordSpan(
        string declarationSource,
        string message,
        string keyword)
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = $"file:///missing-{keyword}-name.nl";
        var source = $"package Playground\n\n{declarationSource}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains(message));

        AssertDiagnosticSpan(diagnostic, line: 3, column: 1, length: keyword.Length);
        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(2, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(keyword.Length, (int)lspDiagnostic.Range.End.Character);
    }

    [Theory]
    [InlineData("func main(: string) {\n}", "Expected parameter name", 13, "string")]
    [InlineData("func main(name:) {\n}", "Expected type name", 11, "name")]
    [InlineData("func main(name: string, ) {\n}", "Expected parameter name", 11, "name: string,")]
    [InlineData("func main<T,>() {\n}", "Expected type parameter name", 10, "<T,>")]
    [InlineData("class Box<> {\n}", "Expected type parameter name", 10, "<>")]
    public void Diagnostics_MalformedParameterLists_UseVisibleTokenSpans(
        string declarationSource,
        string message,
        int column,
        string highlightedText)
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///malformed-parameters.nl";
        var source = $"package Playground\n\n{declarationSource}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains(message));

        AssertDiagnosticSpan(diagnostic, line: 3, column: column, length: highlightedText.Length);
        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(2, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(column - 1, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(column - 1 + highlightedText.Length, (int)lspDiagnostic.Range.End.Character);
    }

    [Theory]
    [InlineData("class User {\n    Name:\n}", "Expected type name", 4, 5, "Name")]
    [InlineData("class User {\n    Items: List<>\n}", "Expected type name", 4, 12, "List<>")]
    [InlineData("func main() {\n    value := new\n}", "Expected type name", 4, 14, "new")]
    [InlineData("class User {\n    Name: string\n}\nfunc main() {\n    user := new User { Name }\n}", "Expected ':' after object initializer member 'Name'", 7, 24, "Name")]
    public void Diagnostics_AdditionalMalformedConstructs_UseVisibleTokenSpans(
        string sourceBody,
        string message,
        int line,
        int column,
        string highlightedText)
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///additional-malformed-spans.nl";
        var source = $"package Playground\n\n{sourceBody}";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains(message));

        AssertDiagnosticSpan(diagnostic, line: line, column: column, length: highlightedText.Length);
        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(line - 1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(column - 1, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(column - 1 + highlightedText.Length, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingFieldTypeBeforeNextField_UsesBothOwningSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///field-type-before-next-field.nl";
        var source = """
package Playground

class User {
    Name:
    Items: List<>
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();
        var missingNameType = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected type name") &&
                          diagnostic.Line == 4 &&
                          diagnostic.Column == 5);
        AssertDiagnosticSpan(missingNameType, line: 4, column: 5, length: "Name".Length);
        AssertLspRange(missingNameType, line0: 3, startCharacter: 4, endCharacter: 8);

        var emptyGenericArgument = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected type name") &&
                          diagnostic.Line == 5 &&
                          diagnostic.Column == 12);
        AssertDiagnosticSpan(emptyGenericArgument, line: 5, column: 12, length: "List<>".Length);
        AssertLspRange(emptyGenericArgument, line0: 4, startCharacter: 11, endCharacter: 17);
    }

    [Fact]
    public void LspCompilerDiagnostic_UsesExactCompilerSpan()
    {
        var error = CompilerError.WithSnippet(
            ErrorCode.InvalidSyntax,
            "Object initializer member 'Name' uses '='; N# uses ':'",
            "Program.nl",
            line: 8,
            column: 24,
            sourceSnippet: "    user := new User { Name = \"Ada\" }",
            length: "Name".Length);

        var diagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(7, (int)diagnostic.Range.Start.Line);
        Assert.Equal(23, (int)diagnostic.Range.Start.Character);
        Assert.Equal(7, (int)diagnostic.Range.End.Line);
        Assert.Equal(27, (int)diagnostic.Range.End.Character);
    }

    [Fact]
    public void LspLinterDiagnostic_UsesExactLinterSpan()
    {
        var diagnostic = new Diagnostic(
            "NL012",
            "Parameter 'unusedName' in 'greet' is never read — is it needed?",
            new Location(1, 12, "Program.nl"),
            DiagnosticSeverity.Info,
            "Prefix with '_' if this is intentional",
            "unusedName".Length);

        var lspDiagnostic = LspDiagnosticConverter.FromLinterDiagnostic(diagnostic);

        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(11, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(0, (int)lspDiagnostic.Range.End.Line);
        Assert.Equal(21, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_IncompleteMemberAccess_PointsAtReceiver()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///member-dot.nl";

        var source = """
func main() {
    name := "Ada"
    name.
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.ExpectedToken && d.Message.Contains("Expected member name"));

        Assert.Equal(3, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("name".Length, diagnostic.Length);
        Assert.Contains("dot", diagnostic.HumanExplanation, System.StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidExpressionStatement ||
                 d.Message.Contains("<error>", System.StringComparison.Ordinal));

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(2, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(4, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(8, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_IncompleteMemberAccessBeforeCall_PointsAtReceiver()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///member-dot-before-call.nl";

        var source = """
func main() {
    name := "Ada"
    name.()
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.ExpectedToken && d.Message.Contains("Expected member name"));

        Assert.Equal(3, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("name".Length, diagnostic.Length);
        Assert.Contains("dot (.)", diagnostic.HumanExplanation);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidExpressionStatement ||
                 d.Message.Contains("<error>", System.StringComparison.Ordinal));

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(2, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(4, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(8, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnterminatedStringLiteral_PointsAtLiteralToken()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unterminated-string.nl";

        var source = """
func main() {
    name := "Ada
    print name
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidLiteral && d.Message.Contains("Unterminated string literal"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(4, diagnostic.Length);
        Assert.Contains("closing quote", diagnostic.HumanExplanation, System.StringComparison.OrdinalIgnoreCase);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(12, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(16, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnterminatedStringLiteral_WithEscapedQuote_PointsAtLiteralToken()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unterminated-string-escaped-quote.nl";

        var source = """
func main() {
    name := "Ada\"
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidLiteral && d.Message.Contains("Unterminated string literal"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(6, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(12, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(18, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnterminatedTripleQuoteStringLiteral_PointsAtOpeningDelimiter()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unterminated-triple-string.nl";

        var source = "func main() {\n    text := \"\"\"hello\nworld\n}\n";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidLiteral &&
                 d.Message.Contains("Unterminated triple-quoted string literal"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(3, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(12, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(15, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnterminatedInterpolatedRawStringLiteral_PointsAtOpeningDelimiter()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unterminated-raw-string.nl";

        var source = "func main() {\n    text := $\"\"\"hello {name}\n}\n";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidLiteral &&
                 d.Message.Contains("Unterminated interpolated raw string literal"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(13, diagnostic.Column);
        Assert.Equal(4, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(12, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(16, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingClosingParen_PointsAtCallOwner()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-paren.nl";

        var source = """
func main() {
    print("hello"
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.MissingClosingParen && d.Message.Contains("Missing closing ')'"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("print".Length, diagnostic.Length);
        Assert.Contains("closing ')'", diagnostic.HumanExplanation, System.StringComparison.OrdinalIgnoreCase);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(4, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(9, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnclosedEmptyCallArgumentList_PointsAtCallOwner()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-empty-call-paren.nl";

        var source = """
func main() {
    print(
    greeting.CompareTo("ter")
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.MissingClosingParen && d.Message.Contains("Missing closing ')'"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("print".Length, diagnostic.Length);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UnexpectedToken);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(4, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(9, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnclosedEmptyFunctionParameterList_PointsAtFunctionName()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-empty-parameter-paren.nl";

        var source = "func main(\n";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.MissingClosingParen && d.Message.Contains("Missing closing ')'"));

        Assert.Equal(1, diagnostic.Line);
        Assert.Equal(6, diagnostic.Column);
        Assert.Equal("main".Length, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(5, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(9, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingClosingBrace_PointsAtFunctionName()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-brace.nl";

        var source = """
func main() {
    print "hi"
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.MissingClosingBrace && d.Message.Contains("Missing closing '}'"));

        Assert.Equal(1, diagnostic.Line);
        Assert.Equal(6, diagnostic.Column);
        Assert.Equal("main".Length, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(5, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(9, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingClosingBracket_PointsAtAssignedVariable()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-bracket.nl";

        var source = """
func main() {
    nums := [1, 2
    print nums
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.MissingClosingBracket && d.Message.Contains("Missing closing ']'"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("nums".Length, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(4, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(8, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingParameterColon_UsesParameterNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-parameter-colon.nl";

        var source = "func greet(name string): string { return name }";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected ':' after parameter name"));

        AssertDiagnosticSpan(diagnostic, line: 1, column: 12, length: "name".Length);
        AssertLspRange(diagnostic, line0: 0, startCharacter: 11, endCharacter: 15);
        Assert.Contains("name: Type", diagnostic.ContextualHint);
    }

    [Fact]
    public void Diagnostics_MissingFieldColon_UsesFieldNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-field-colon.nl";

        var source = """
class User {
    Name string
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected ':' or ':=' after field name"));

        AssertDiagnosticSpan(diagnostic, line: 2, column: 5, length: "Name".Length);
        AssertLspRange(diagnostic, line0: 1, startCharacter: 4, endCharacter: 8);
        Assert.Contains("Name: Type", diagnostic.ContextualHint);
    }

    [Fact]
    public void Diagnostics_MissingFunctionReturnColon_UsesFunctionNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-function-return-colon.nl";

        var source = "func answer() int { return 1 }";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected ':' before return type"));

        AssertDiagnosticSpan(diagnostic, line: 1, column: 6, length: "answer".Length);
        AssertLspRange(diagnostic, line0: 0, startCharacter: 5, endCharacter: 11);
        Assert.Contains("func name(...): Type", diagnostic.ContextualHint);
    }

    [Fact]
    public void Diagnostics_DefaultParserSpan_UsesVisibleTokenSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unsupported-enum-backing-type.nl";

        var source = "enum Status: decimal { Open }";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.UnexpectedToken &&
                          diagnostic.Message.Contains("Unsupported enum backing type"));

        AssertDiagnosticSpan(diagnostic, line: 1, column: 14, length: "decimal".Length);
        AssertLspRange(diagnostic, line0: 0, startCharacter: 13, endCharacter: 20);
    }

    [Fact]
    public void Diagnostics_DefaultSemanticSpan_UsesVisibleTokenSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///explicit-var-type.nl";

        var source = """
func main(): int {
    let value: var = 42
    return value
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("'var' is not a type"));

        AssertDiagnosticSpan(diagnostic, line: 2, column: 16, length: "var".Length);
        AssertLspRange(diagnostic, line0: 1, startCharacter: 15, endCharacter: 18);
    }

    [Fact]
    public void LinterDiagnostics_UnusedShorthandVariable_UsesVariableNameSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///unused-shorthand-variable.nl";

        var source = """
func main() {
    asdf := "meow"
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.LinterDiagnostics ?? Enumerable.Empty<Diagnostic>(),
            diagnostic => diagnostic.Code == "NL001" &&
                          diagnostic.Message.Contains("asdf"));

        Assert.Equal(2, diagnostic.Location.Line);
        Assert.Equal(5, diagnostic.Location.Column);
        Assert.Equal("asdf".Length, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromLinterDiagnostic(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(4, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(8, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingInitializer_PointsAtVariableName()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-initializer.nl";

        var source = """
func main() {
    name :=
        greeting := "hi"
    print greeting
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.ExpectedToken &&
                 d.Message.Contains("Expected an initializer expression after ':='"));

        Assert.Equal(2, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("name".Length, diagnostic.Length);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UnexpectedToken);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UndefinedVariable && d.Message.Contains("greeting"));
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UnusedVariable && d.Message.Contains("name"));

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(4, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(8, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingAssignmentValue_PointsAtAssignmentTarget()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-assignment-value.nl";

        var source = """
func main() {
    value := 1
    value =
    print value
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.ExpectedToken &&
                 d.Message.Contains("Expected expression after '='"));

        Assert.Equal(3, diagnostic.Line);
        Assert.Equal(5, diagnostic.Column);
        Assert.Equal("value".Length, diagnostic.Length);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UnexpectedToken);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(2, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(4, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(9, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingKeywordsAndKeywordExpressions_UseVisibleKeywordSpans()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///missing-keyword-spans.nl";

        var source = """
func main() {
    foreach item items {
        print item
    }

    if {
        print "missing condition"
    }

    while {
        print "missing condition"
    }

    print
        value := 1
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();

        var missingIn = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected 'in' between the loop variable and collection"));
        AssertDiagnosticSpan(missingIn, line: 2, column: 5, length: "foreach".Length);
        AssertLspRange(missingIn, line0: 1, startCharacter: 4, endCharacter: 11);

        var missingIfCondition = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected a condition expression after 'if'"));
        AssertDiagnosticSpan(missingIfCondition, line: 6, column: 5, length: "if".Length);
        AssertLspRange(missingIfCondition, line0: 5, startCharacter: 4, endCharacter: 6);

        var missingWhileCondition = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected a condition expression after 'while'"));
        AssertDiagnosticSpan(missingWhileCondition, line: 10, column: 5, length: "while".Length);
        AssertLspRange(missingWhileCondition, line0: 9, startCharacter: 4, endCharacter: 9);

        var missingPrintExpression = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.ExpectedToken &&
                          diagnostic.Message.Contains("Expected an expression to print after 'print'"));
        AssertDiagnosticSpan(missingPrintExpression, line: 14, column: 5, length: "print".Length);
        AssertLspRange(missingPrintExpression, line0: 13, startCharacter: 4, endCharacter: 9);

        Assert.DoesNotContain(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.TypeMismatch &&
                          diagnostic.Message.Contains("condition in a 'while' loop", System.StringComparison.Ordinal));
    }

    [Theory]
    [InlineData("""
func main() {
    + 1
}
""", ErrorCode.InvalidSyntax, "Prefix '+'", 2, 5, "+ 1")]
    [InlineData("""
func main() {
    .Name
}
""", ErrorCode.ExpectedToken, "Expected expression before '.'", 2, 5, ".Name")]
    [InlineData("""
func main() {
    if true
}
""", ErrorCode.ExpectedToken, "Expected statement body", 2, 5, "if")]
    [InlineData("""
func main() {
    for item in items
}
""", ErrorCode.ExpectedToken, "Expected statement body", 2, 5, "for")]
    [InlineData("""
func main() {
    value := await
}
""", ErrorCode.ExpectedToken, "Expected an expression to await after 'await'", 2, 14, "await")]
    [InlineData("""
func main() {
    value := must
}
""", ErrorCode.ExpectedToken, "Expected a nullable expression to unwrap after 'must'", 2, 14, "must")]
    [InlineData("""
func main() {
    f := x =>
}
""", ErrorCode.ExpectedToken, "Expected a lambda body expression after '=>'", 2, 10, "x =>")]
    [InlineData("""
func main() {
    result := condition ? 1 :
}
""", ErrorCode.ExpectedToken, "Expected an else expression after ':'", 2, 15, "condition ? 1 :")]
    public void Diagnostics_RecoverySpans_AvoidPunctuationOnlyMarkers(
        string source,
        ErrorCode code,
        string message,
        int line,
        int column,
        string highlightedText)
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///recovery-span.nl";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostics = (document!.Diagnostics ?? Enumerable.Empty<CompilerError>()).ToList();
        var diagnostic = Assert.Single(diagnostics,
            diagnostic => diagnostic.Code == code &&
                          diagnostic.Message.Contains(message));

        AssertDiagnosticSpan(diagnostic, line: line, column: column, length: highlightedText.Length);
        AssertLspRange(diagnostic, line0: line - 1, startCharacter: column - 1, endCharacter: column - 1 + highlightedText.Length);
        Assert.DoesNotContain(diagnostics,
            diagnostic => diagnostic.Code == ErrorCode.UnexpectedToken ||
                          diagnostic.Code == ErrorCode.InvalidExpressionStatement);
    }

    [Fact]
    public void Diagnostics_UsingTupleDeconstruction_UsesTuplePatternSpan()
    {
        var documentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);
        var uri = "file:///using-tuple-deconstruction.nl";

        var source = """
func getPair(): (int, int) {
    return (1, 2)
}

func main() {
    using let (left, right) := getPair() {
        print "ok"
    }
}
""";

        documentManager.UpdateDocument(uri, source, version: 1);

        var document = documentManager.GetDocument(uri);
        Assert.NotNull(document);

        var diagnostic = Assert.Single(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Code == ErrorCode.InvalidSyntax &&
                          diagnostic.Message.Contains("Using statement requires a variable declaration"));

        AssertDiagnosticSpan(diagnostic, line: 6, column: 15, length: "(left, right)".Length);
        AssertLspRange(diagnostic, line0: 5, startCharacter: 14, endCharacter: 27);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            diagnostic => diagnostic.Message.Contains("<error>", System.StringComparison.Ordinal) ||
                          diagnostic.Message.Contains("can't determine the type", System.StringComparison.OrdinalIgnoreCase));
    }

    // ---------------------------------------------------------------------------------------------
    // Converter conversion-invariant coverage (Unit 12).
    //
    // These tests exercise LspDiagnosticConverter directly with hand-constructed CompilerError /
    // Diagnostic values so the 1-based -> 0-based, end-exclusive, length>=1 and clamp invariants are
    // asserted independently of any analyzer raise-site span (which other units own).
    // ---------------------------------------------------------------------------------------------

    [Theory]
    // Column 1, length 1: minimal span at the very start of a line.
    [InlineData(1, 1, 1, 0, 0, 1)]
    // Mid-line span of several columns.
    [InlineData(5, 10, 4, 4, 9, 13)]
    // Length defaults below 1 are forced to a single column.
    [InlineData(3, 3, 0, 2, 2, 3)]
    [InlineData(3, 3, -7, 2, 2, 3)]
    // Negative/zero line and column are clamped to 0 without throwing.
    [InlineData(0, 0, 1, 0, 0, 1)]
    [InlineData(-4, -9, 1, 0, 0, 1)]
    // Large length with no source snippet is left intact (end-exclusive).
    [InlineData(2, 1, 250, 1, 0, 250)]
    public void Converter_CompilerError_AppliesConversionInvariants(
        int line,
        int column,
        int length,
        int expectedLine0,
        int expectedStartCharacter,
        int expectedEndCharacter)
    {
        var error = new CompilerError(ErrorCode.InvalidSyntax, "synthetic", line, column, ErrorSeverity.Error)
        {
            Length = length
        };

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(expectedLine0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(expectedLine0, (int)lspDiagnostic.Range.End.Line);
        Assert.Equal(expectedStartCharacter, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(expectedEndCharacter, (int)lspDiagnostic.Range.End.Character);
        Assert.True(lspDiagnostic.Range.End.Character > lspDiagnostic.Range.Start.Character,
            "End character must stay strictly greater than start (span underlines at least one column).");
    }

    [Fact]
    public void Converter_CompilerError_SpanAtEndOfLine_StaysExclusiveWithinLine()
    {
        // "abc" is 3 chars; a length-1 span on the final char ('c') ends exactly at the line length.
        var error = new CompilerError(ErrorCode.InvalidSyntax, "synthetic", line: 1, column: 3, ErrorSeverity.Error)
        {
            Length = 1,
            SourceSnippet = "abc"
        };

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(2, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(3, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Converter_CompilerError_OverlongSpan_IsClampedToVisibleLineLength()
    {
        // A defective length that would otherwise overflow past the end of the visible line must be
        // clamped to the line length so the squiggle does not bleed into virtual whitespace.
        var error = new CompilerError(ErrorCode.InvalidSyntax, "synthetic", line: 2, column: 5, ErrorSeverity.Error)
        {
            Length = 100,
            SourceSnippet = "    nums := [1, 2"
        };

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(4, (int)lspDiagnostic.Range.Start.Character);
        // "    nums := [1, 2" is 17 characters; the end is clamped to that visible length.
        Assert.Equal("    nums := [1, 2".Length, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Converter_CompilerError_OverlongSpan_NeverCollapsesBelowOneColumn()
    {
        // Even when the start sits at (or past) the visible end of the line, the clamp must keep the
        // range non-empty: end stays strictly greater than start.
        var error = new CompilerError(ErrorCode.InvalidSyntax, "synthetic", line: 1, column: 6, ErrorSeverity.Error)
        {
            Length = 50,
            SourceSnippet = "abcd"
        };

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(5, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(6, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Converter_CompilerError_MultiLineSnippet_ClampsAgainstFirstLineOnly()
    {
        // SourceSnippet may carry more than the starting line; the span is single-line by contract so
        // the clamp considers only the first physical line and never wraps end onto a later line.
        var error = new CompilerError(ErrorCode.InvalidSyntax, "synthetic", line: 1, column: 1, ErrorSeverity.Error)
        {
            Length = 100,
            SourceSnippet = "abc\ndefghijklmnop"
        };

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(0, (int)lspDiagnostic.Range.End.Line);
        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal("abc".Length, (int)lspDiagnostic.Range.End.Character);
    }

    [Theory]
    [InlineData(1, 1, 1, 0, 0, 1)]
    [InlineData(7, 12, 10, 6, 11, 21)]
    [InlineData(3, 3, 0, 2, 2, 3)]
    [InlineData(0, 0, -3, 0, 0, 1)]
    public void Converter_LinterDiagnostic_AppliesConversionInvariants(
        int line,
        int column,
        int length,
        int expectedLine0,
        int expectedStartCharacter,
        int expectedEndCharacter)
    {
        var diagnostic = new Diagnostic(
            "NL012",
            "synthetic",
            new Location(line, column, "Program.nl"),
            DiagnosticSeverity.Info,
            Suggestion: null,
            Length: length);

        var lspDiagnostic = LspDiagnosticConverter.FromLinterDiagnostic(diagnostic);

        Assert.Equal(expectedLine0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(expectedLine0, (int)lspDiagnostic.Range.End.Line);
        Assert.Equal(expectedStartCharacter, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(expectedEndCharacter, (int)lspDiagnostic.Range.End.Character);
        Assert.True(lspDiagnostic.Range.End.Character > lspDiagnostic.Range.Start.Character);
    }

    [Theory]
    [InlineData(DiagnosticSeverity.Error, OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Error)]
    [InlineData(DiagnosticSeverity.Warning, OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Warning)]
    [InlineData(DiagnosticSeverity.Info, OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Information)]
    public void Converter_LinterDiagnostic_MapsSeverity(
        DiagnosticSeverity compilerSeverity,
        OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity expected)
    {
        var diagnostic = new Diagnostic(
            "NL001",
            "synthetic",
            new Location(1, 1, "Program.nl"),
            compilerSeverity,
            Length: 1);

        var lspDiagnostic = LspDiagnosticConverter.FromLinterDiagnostic(diagnostic);

        Assert.Equal(expected, lspDiagnostic.Severity);
    }

    [Theory]
    [InlineData(ErrorSeverity.Error, OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Error)]
    [InlineData(ErrorSeverity.Warning, OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity.Warning)]
    public void Converter_CompilerError_MapsSeverity(
        ErrorSeverity compilerSeverity,
        OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity expected)
    {
        var error = new CompilerError(ErrorCode.TypeMismatch, "synthetic", line: 1, column: 1, compilerSeverity);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(expected, lspDiagnostic.Severity);
    }

    /// <summary>
    /// Coverage sweep: every compiler ErrorCode (NL1xx-NL9xx) and every linter rule (NL0xx) must
    /// produce a deterministic LSP Range obeying the conversion invariants. This guards against a new
    /// diagnostic code being added without the converter being exercised for it.
    /// </summary>
    [Fact]
    public void Converter_EveryDiagnosticCode_ProducesValidLspRange()
    {
        const int line = 4;
        const int column = 7;
        const int length = 5;

        foreach (ErrorCode code in System.Enum.GetValues<ErrorCode>())
        {
            var severity = code is ErrorCode.VisibilityConventionWarning
                or ErrorCode.ObsoleteUsage
                or ErrorCode.UnnecessaryTypeAnnotation
                ? ErrorSeverity.Warning
                : ErrorSeverity.Error;

            var error = new CompilerError(code, $"synthetic {code}", line, column, severity)
            {
                Length = length
            };

            var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(error);

            Assert.Equal($"NL{(int)code:D3}", lspDiagnostic.Code!.Value.String);
            Assert.Equal("N#", lspDiagnostic.Source);
            Assert.Equal(line - 1, (int)lspDiagnostic.Range.Start.Line);
            Assert.Equal(column - 1, (int)lspDiagnostic.Range.Start.Character);
            Assert.Equal(column - 1 + length, (int)lspDiagnostic.Range.End.Character);
        }

        foreach (var descriptor in DiagnosticCatalog.LinterDescriptors)
        {
            var diagnostic = new Diagnostic(
                descriptor.Code,
                $"synthetic {descriptor.Code}",
                new Location(line, column, "Program.nl"),
                descriptor.DefaultSeverity,
                Length: length);

            var lspDiagnostic = LspDiagnosticConverter.FromLinterDiagnostic(diagnostic);

            Assert.Equal(descriptor.Code, lspDiagnostic.Code!.Value.String);
            Assert.Equal("N#", lspDiagnostic.Source);
            Assert.Equal(line - 1, (int)lspDiagnostic.Range.Start.Line);
            Assert.Equal(column - 1, (int)lspDiagnostic.Range.Start.Character);
            Assert.Equal(column - 1 + length, (int)lspDiagnostic.Range.End.Character);
        }
    }
}
