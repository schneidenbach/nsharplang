using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Xunit;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.LanguageServer.Handlers;
using NSharpLang.LanguageServer.Services;
using NSharpLang.LanguageServer.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;

namespace NSharpLang.Tests;

/// <summary>
/// Shared fixture for Language Server tests - creates expensive resources once
/// CRITICAL: Do NOT use Lazy - causes test hangs during discovery/initialization
/// </summary>
public class LanguageServerFixture : IDisposable
{
    // CRITICAL FIX: Direct field initialization instead of Lazy
    // Lazy initialization was causing deadlocks during xUnit test discovery
    public XmlDocReader XmlDocReader { get; }
    public TypeResolver TypeResolver { get; }

    public LanguageServerFixture()
    {
        // Direct initialization - fast enough, no hangs
        XmlDocReader = new XmlDocReader(NullLogger<XmlDocReader>.Instance);
        TypeResolver = new TypeResolver(NullLogger<TypeResolver>.Instance, XmlDocReader);
    }

    public void Dispose()
    {
        // Cleanup if needed
    }
}

/// <summary>
/// Collection definition for Language Server tests
/// </summary>
[CollectionDefinition("LanguageServer")]
public class LanguageServerCollection : ICollectionFixture<LanguageServerFixture>
{
    // This class has no code, and is never created. Its purpose is simply
    // to be the place to apply [CollectionDefinition] and all the
    // ICollectionFixture<> interfaces.
}

/// <summary>
/// Comprehensive tests for the Language Server Protocol implementation
/// </summary>
[Collection("LanguageServer")]
public class LanguageServerTests
{
    private readonly LanguageServerFixture _fixture;

    public LanguageServerTests(LanguageServerFixture fixture)
    {
        _fixture = fixture;
    }

    /// <summary>
    /// Test harness for LSP features - makes testing easier
    /// </summary>
    private class LspTestHarness
    {
        public DocumentManager DocumentManager { get; }
        public XmlDocReader XmlDocReader { get; }
        public TypeResolver TypeResolver { get; }
        public CompletionHandler CompletionHandler { get; }
        public HoverHandler HoverHandler { get; }
        public SignatureHelpHandler SignatureHelpHandler { get; }

        public LspTestHarness(XmlDocReader xmlDocReader, TypeResolver typeResolver)
        {
            // Reuse shared XmlDocReader and TypeResolver from fixture
            XmlDocReader = xmlDocReader;
            TypeResolver = typeResolver;

            // Create test-specific DocumentManager (each test needs its own)
            DocumentManager = new DocumentManager(NullLogger<DocumentManager>.Instance);

            // Create handlers with shared services
            CompletionHandler = new CompletionHandler(
                DocumentManager,
                TypeResolver,
                NullLogger<CompletionHandler>.Instance
            );

            HoverHandler = new HoverHandler(
                DocumentManager,
                TypeResolver,
                NullLogger<HoverHandler>.Instance
            );

            SignatureHelpHandler = new SignatureHelpHandler(
                DocumentManager,
                TypeResolver,
                NullLogger<SignatureHelpHandler>.Instance
            );
        }

        /// <summary>
        /// Opens a document with the given content
        /// </summary>
        public void OpenDocument(string uri, string content)
        {
            // DocumentManager.UpdateDocument does all the parsing and analyzing
            DocumentManager.UpdateDocument(uri, content, 1);
        }

        /// <summary>
        /// Updates document content
        /// </summary>
        public void UpdateDocument(string uri, string content)
        {
            var doc = DocumentManager.GetDocument(uri);
            var version = doc?.Version + 1 ?? 1;

            // DocumentManager.UpdateDocument handles everything
            DocumentManager.UpdateDocument(uri, content, version);
        }

        /// <summary>
        /// Get completions at a position
        /// </summary>
        public async Task<CompletionList> GetCompletionsAsync(string uri, int line, int character)
        {
            var request = new CompletionParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Position = new Position(line, character)
            };

            return await CompletionHandler.Handle(request, CancellationToken.None);
        }

        /// <summary>
        /// Get hover info at a position
        /// </summary>
        public async Task<Hover?> GetHoverAsync(string uri, int line, int character)
        {
            var request = new HoverParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Position = new Position(line, character)
            };

            return await HoverHandler.Handle(request, CancellationToken.None);
        }

        /// <summary>
        /// Get signature help at a position
        /// </summary>
        public async Task<SignatureHelp?> GetSignatureHelpAsync(string uri, int line, int character)
        {
            var request = new SignatureHelpParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Position = new Position(line, character)
            };

            return await SignatureHelpHandler.Handle(request, CancellationToken.None);
        }
    }

    #region Completion Tests

    [Fact]
    public async Task Completion_Keywords()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "f");

        var completions = await harness.GetCompletionsAsync(uri, 0, 1);

        Assert.NotEmpty(completions.Items);
        Assert.Contains(completions.Items, c => c.Label == "func");
        Assert.Contains(completions.Items, c => c.Label == "for");
        Assert.Contains(completions.Items, c => c.Label == "foreach");
    }

    [Fact]
    public async Task Completion_PrimitiveTypes()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "i");

        var completions = await harness.GetCompletionsAsync(uri, 0, 1);

        Assert.Contains(completions.Items, c => c.Label == "int");
        Assert.Contains(completions.Items, c => c.Label == "string");
        Assert.Contains(completions.Items, c => c.Label == "bool");
    }

    [Fact]
    public async Task Completion_CommonDotNetTypes()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "C");

        var completions = await harness.GetCompletionsAsync(uri, 0, 1);

        Assert.Contains(completions.Items, c => c.Label == "Console");
        Assert.Contains(completions.Items, c => c.Label == "List");
        Assert.Contains(completions.Items, c => c.Label == "Dictionary");
    }

    [Fact]
    public async Task Completion_LocalFunctions()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func greet(name: string): string
    return ""Hello, "" + name

func main(): void
    ";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 5, 4);

        Assert.Contains(completions.Items, c => c.Label == "greet");
        Assert.Contains(completions.Items, c => c.Label == "main");
    }

    [Fact]
    public async Task Completion_MemberAccess_Console()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    Console.";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 2, 12);

        Assert.NotEmpty(completions.Items);
        Assert.Contains(completions.Items, c => c.Label == "WriteLine");
        Assert.Contains(completions.Items, c => c.Label == "Write");
        Assert.Contains(completions.Items, c => c.Label == "ReadLine");
    }

    [Fact]
    public async Task Completion_MemberAccess_String()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let message = ""hello""
    message.";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 3, 12);

        Assert.NotEmpty(completions.Items);
        Assert.Contains(completions.Items, c => c.Label == "Length");
        Assert.Contains(completions.Items, c => c.Label == "ToUpper");
        Assert.Contains(completions.Items, c => c.Label == "ToLower");
        Assert.Contains(completions.Items, c => c.Label == "Substring");
    }

    #endregion

    #region Hover Tests

    [Fact]
    public async Task Hover_Keyword()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "func main(): void");

        var hover = await harness.GetHoverAsync(uri, 0, 2);

        Assert.NotNull(hover);
        var content = hover.Contents.MarkupContent;
        Assert.NotNull(content);
        Assert.Contains("func", content.Value);
        Assert.Contains("keyword", content.Value);
    }

    [Fact]
    public async Task Hover_PrimitiveType()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "func test(): int");

        var hover = await harness.GetHoverAsync(uri, 0, 14);

        Assert.NotNull(hover);
        var content = hover.Contents.MarkupContent;
        Assert.NotNull(content);
        Assert.Contains("int", content.Value);
        Assert.Contains("primitive type", content.Value);
    }

    [Fact]
    public async Task Hover_LocalVariable()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let count = 42
    print(count)";

        harness.OpenDocument(uri, source);

        var hover = await harness.GetHoverAsync(uri, 3, 11);

        Assert.NotNull(hover);
        var content = hover.Contents.MarkupContent;
        Assert.NotNull(content);
        Assert.Contains("count", content.Value);
        // Should show the type information
    }

    [Fact]
    public async Task Hover_FunctionName()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func greet(name: string): string
    return ""Hello, "" + name";

        harness.OpenDocument(uri, source);

        var hover = await harness.GetHoverAsync(uri, 1, 6);

        Assert.NotNull(hover);
        var content = hover.Contents.MarkupContent;
        Assert.NotNull(content);
        Assert.Contains("greet", content.Value);
    }

    [Fact]
    public async Task Hover_MemberAccess_Property()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let message = ""hello""
    let len = message.Length";

        harness.OpenDocument(uri, source);

        // Hover over "Length" in "message.Length"
        var hover = await harness.GetHoverAsync(uri, 3, 24);

        Assert.NotNull(hover);
        var content = hover.Contents.MarkupContent;
        Assert.NotNull(content);
        Assert.Contains("Length", content.Value);
        Assert.Contains("property", content.Value.ToLower());
    }

    [Fact]
    public async Task Hover_MemberAccess_Method()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let message = ""hello""
    let upper = message.ToUpper()";

        harness.OpenDocument(uri, source);

        // Hover over "ToUpper" in "message.ToUpper()"
        var hover = await harness.GetHoverAsync(uri, 3, 26);

        Assert.NotNull(hover);
        var content = hover.Contents.MarkupContent;
        Assert.NotNull(content);
        Assert.Contains("ToUpper", content.Value);
        Assert.Contains("method", content.Value.ToLower());
    }

    [Fact]
    public async Task Hover_MemberAccess_MethodWithParameters()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let message = ""hello world""
    let sub = message.Substring(0, 5)";

        harness.OpenDocument(uri, source);

        // Hover over "Substring"
        var hover = await harness.GetHoverAsync(uri, 3, 24);

        Assert.NotNull(hover);
        var content = hover.Contents.MarkupContent;
        Assert.NotNull(content);
        Assert.Contains("Substring", content.Value);
        // Should show method signature with parameters
        Assert.Contains("int", content.Value);
    }

    [Fact(Skip = "TODO: Same as Completion_ChainedMemberAccess - needs expression type resolution")]
    public async Task Hover_ChainedMemberAccess()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let message = ""hello""
    let len = message.ToUpper().Length";

        harness.OpenDocument(uri, source);

        // Hover over "Length" in the chained call
        var hover = await harness.GetHoverAsync(uri, 3, 34);

        Assert.NotNull(hover);
        var content = hover.Contents.MarkupContent;
        Assert.NotNull(content);
        Assert.Contains("Length", content.Value);
    }

    [Fact]
    public async Task Hover_ConsoleWriteLine()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    Console.WriteLine(""test"")";

        harness.OpenDocument(uri, source);

        // Hover over "WriteLine"
        var hover = await harness.GetHoverAsync(uri, 2, 15);

        Assert.NotNull(hover);
        var content = hover.Contents.MarkupContent;
        Assert.NotNull(content);
        Assert.Contains("WriteLine", content.Value);
        // Should show it has overloads
        Assert.Contains("method", content.Value.ToLower());
    }

    [Fact]
    public async Task Hover_VariableWithSystemType()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let numbers = [1, 2, 3]
    print(numbers)";

        harness.OpenDocument(uri, source);

        // Hover over "numbers" variable
        var hover = await harness.GetHoverAsync(uri, 3, 12);

        Assert.NotNull(hover);
        var content = hover.Contents.MarkupContent;
        Assert.NotNull(content);
        Assert.Contains("numbers", content.Value);
        // Should show type information
    }

    #endregion

    #region Signature Help Tests

    [Fact]
    public async Task SignatureHelp_ConsoleWriteLine()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    Console.WriteLine(";

        harness.OpenDocument(uri, source);

        var sigHelp = await harness.GetSignatureHelpAsync(uri, 2, 22);

        Assert.NotNull(sigHelp);
        Assert.NotEmpty(sigHelp.Signatures);
        Assert.Contains(sigHelp.Signatures, s => s.Label.Contains("WriteLine"));
    }

    [Fact]
    public async Task SignatureHelp_StringFormat()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    String.Format(";

        harness.OpenDocument(uri, source);

        var sigHelp = await harness.GetSignatureHelpAsync(uri, 2, 18);

        Assert.NotNull(sigHelp);
        Assert.NotEmpty(sigHelp.Signatures);
        Assert.Contains(sigHelp.Signatures, s => s.Label.Contains("Format"));
    }

    #endregion

    #region Diagnostics Tests

    [Fact]
    public void Diagnostics_SyntaxError()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(: void";

        harness.OpenDocument(uri, source);

        var doc = harness.DocumentManager.GetDocument(uri);
        Assert.NotNull(doc);
        Assert.NotEmpty(doc.Diagnostics);
    }

    [Fact]
    public void Diagnostics_ValidCode_NoDiagnostics()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    print(""Hello, World!"")";

        harness.OpenDocument(uri, source);

        var doc = harness.DocumentManager.GetDocument(uri);
        Assert.NotNull(doc);
        // Should have no errors (might have warnings from linter)
        Assert.DoesNotContain(doc.Diagnostics, d => d.Severity == NSharpLang.Compiler.ErrorSeverity.Error);
    }

    #endregion

    #region Document Update Tests

    [Fact]
    public async Task DocumentUpdate_CompletionsReflectChanges()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        // Initial document
        harness.OpenDocument(uri, "func foo(): void");

        var completions1 = await harness.GetCompletionsAsync(uri, 0, 0);
        Assert.Contains(completions1.Items, c => c.Label == "foo");

        // Update document with new function
        harness.UpdateDocument(uri, "func bar(): void");

        var completions2 = await harness.GetCompletionsAsync(uri, 0, 0);
        Assert.Contains(completions2.Items, c => c.Label == "bar");
    }

    #endregion

    #region Edge Cases

    [Fact]
    public async Task Completion_EmptyDocument()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "");

        var completions = await harness.GetCompletionsAsync(uri, 0, 0);

        // Should still return keywords and common types
        Assert.NotEmpty(completions.Items);
        Assert.Contains(completions.Items, c => c.Label == "func");
    }

    [Fact]
    public async Task Hover_InvalidPosition()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "func main(): void");

        // Position beyond document length
        var hover = await harness.GetHoverAsync(uri, 10, 50);

        // Should return null or handle gracefully
        Assert.Null(hover);
    }

    [Fact]
    public async Task Completion_AfterDot_NoIdentifier()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    .";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 2, 5);

        // Should handle gracefully (return general completions or empty)
        Assert.NotNull(completions);
    }

    #endregion

    #region Complex Scenarios

    [Fact(Skip = "TODO: Implement proper expression type resolution for chained method calls")]
    public async Task Completion_ChainedMemberAccess()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let message = ""hello""
    let upper = message.ToUpper().";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 3, 38);

        // Should show string members (result of ToUpper())
        Assert.NotEmpty(completions.Items);
        Assert.Contains(completions.Items, c => c.Label == "Length");
        Assert.Contains(completions.Items, c => c.Label == "ToLower");
    }

    [Fact]
    public async Task Completion_NestedFunctions()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func outer(): void
    func inner(): void
        print(""nested"")
    ";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 4, 4);

        // Should see both outer and inner functions
        Assert.Contains(completions.Items, c => c.Label == "outer");
        Assert.Contains(completions.Items, c => c.Label == "inner");
    }

    #endregion
}
