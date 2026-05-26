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
}
