using System.Linq;
using Microsoft.Extensions.Logging.Abstractions;
using NSharpLang.Compiler;
using NSharpLang.LanguageServer.Services;
using Xunit;

namespace NSharpLang.Tests;

public class LanguageServerDiagnosticsTests
{
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
            d => d.Code == ErrorCode.DefiniteAssignmentError && d.Message.Contains("name"));

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
                or ErrorCode.ReferenceLoadFailure
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
