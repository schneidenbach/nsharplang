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
        Assert.Contains(diagnostics, diagnostic => diagnostic.Code == ErrorCode.InvalidExpressionStatement);
        Assert.Contains(diagnostics, diagnostic => diagnostic.Code == ErrorCode.NoMatchingOverload);
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
        AssertDiagnosticSpan(expressionBodyRequiresReturnType, line: 6, column: 44, length: "\"bad\"".Length);
        AssertLspRange(expressionBodyRequiresReturnType, line0: 5, startCharacter: 43, endCharacter: 48);

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
        Assert.Contains("return 42", message);
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
            diagnostic.Length == 1 &&
            diagnostic.Message.Contains("Expected expression after '+'"));
        Assert.Contains(diagnostics, diagnostic =>
            diagnostic.Code == ErrorCode.InvalidSyntax &&
            diagnostic.Line == 8 &&
            diagnostic.Length == 1 &&
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
    public void LspCompilerDiagnostic_UsesExactCompilerSpan()
    {
        var error = CompilerError.WithSnippet(
            ErrorCode.InvalidSyntax,
            "Object initializer member 'Name' uses '='; N# uses ':'",
            "Program.nl",
            line: 8,
            column: 29,
            sourceSnippet: "    user := new User { Name = \"Ada\" }",
            length: 1);

        var diagnostic = LspDiagnosticConverter.FromCompilerError(error);

        Assert.Equal(7, (int)diagnostic.Range.Start.Line);
        Assert.Equal(28, (int)diagnostic.Range.Start.Character);
        Assert.Equal(7, (int)diagnostic.Range.End.Line);
        Assert.Equal(29, (int)diagnostic.Range.End.Character);
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
    public void Diagnostics_IncompleteMemberAccess_PointsAtTrailingDot()
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
        Assert.Equal(9, diagnostic.Column);
        Assert.Equal(1, diagnostic.Length);
        Assert.Contains("dot", diagnostic.HumanExplanation, System.StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.InvalidExpressionStatement ||
                 d.Message.Contains("<error>", System.StringComparison.Ordinal));

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(2, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(8, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(9, (int)lspDiagnostic.Range.End.Character);
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
    public void Diagnostics_MissingClosingParen_PointsAtInsertionPosition()
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
        Assert.Equal(18, diagnostic.Column);
        Assert.Equal(1, diagnostic.Length);
        Assert.Contains("closing ')'", diagnostic.HumanExplanation, System.StringComparison.OrdinalIgnoreCase);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(17, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(18, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnclosedEmptyCallArgumentList_PointsAtInsertionPosition()
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
        Assert.Equal(11, diagnostic.Column);
        Assert.Equal(1, diagnostic.Length);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UnexpectedToken);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(10, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(11, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_UnclosedEmptyFunctionParameterList_PointsAtInsertionPosition()
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
        Assert.Equal(11, diagnostic.Column);
        Assert.Equal(1, diagnostic.Length);

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(0, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(10, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(11, (int)lspDiagnostic.Range.End.Character);
    }

    [Fact]
    public void Diagnostics_MissingInitializer_PointsAtInsertionPosition()
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
        Assert.Equal(12, diagnostic.Column);
        Assert.Equal(1, diagnostic.Length);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UnexpectedToken);
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UndefinedVariable && d.Message.Contains("greeting"));
        Assert.DoesNotContain(document!.Diagnostics ?? Enumerable.Empty<CompilerError>(),
            d => d.Code == ErrorCode.UnusedVariable && d.Message.Contains("name"));

        var lspDiagnostic = LspDiagnosticConverter.FromCompilerError(diagnostic);
        Assert.Equal(1, (int)lspDiagnostic.Range.Start.Line);
        Assert.Equal(11, (int)lspDiagnostic.Range.Start.Character);
        Assert.Equal(12, (int)lspDiagnostic.Range.End.Character);
    }
}
