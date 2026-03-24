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
using LspLocation = OmniSharp.Extensions.LanguageServer.Protocol.Models.Location;

namespace NSharpLang.Tests;

/// <summary>
/// Shared fixture for Language Server tests - creates expensive resources once
/// CRITICAL: Use truly lazy initialization - xUnit creates fixtures during test discovery!
/// </summary>
public class LanguageServerFixture : IDisposable
{
    private XmlDocReader? _xmlDocReader;
    private TypeResolver? _typeResolver;
    private readonly object _initLock = new();

    // CRITICAL FIX: Lazy properties, NOT eager constructor initialization
    // xUnit instantiates collection fixtures during test DISCOVERY, not execution
    // Any work in the constructor blocks test discovery
    public XmlDocReader XmlDocReader
    {
        get
        {
            if (_xmlDocReader == null)
            {
                lock (_initLock)
                {
                    if (_xmlDocReader == null)
                    {
                        _xmlDocReader = new XmlDocReader(NullLogger<XmlDocReader>.Instance);
                    }
                }
            }
            return _xmlDocReader;
        }
    }

    public TypeResolver TypeResolver
    {
        get
        {
            if (_typeResolver == null)
            {
                lock (_initLock)
                {
                    if (_typeResolver == null)
                    {
                        _typeResolver = new TypeResolver(NullLogger<TypeResolver>.Instance, XmlDocReader);
                    }
                }
            }
            return _typeResolver;
        }
    }

    public LanguageServerFixture()
    {
        // CRITICAL: Keep constructor EMPTY
        // xUnit calls this during test discovery, not execution
        // Any initialization here will block/hang test discovery
    }

    public void Dispose()
    {
        // Cleanup if needed
    }
}

/// <summary>
/// Collection definition for Language Server tests
/// CRITICAL: DisableParallelization prevents deadlocks during fixture cleanup
/// </summary>
[CollectionDefinition("LanguageServer", DisableParallelization = true)]
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

    private static LspLocation ExtractSingleDefinitionLocation(LocationOrLocationLinks value)
    {
        static IEnumerable<System.Reflection.FieldInfo> GetAllFields(Type t)
        {
            while (t != null)
            {
                foreach (var field in t.GetFields(System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.DeclaredOnly))
                {
                    yield return field;
                }
                t = t.BaseType;
            }
        }

        static System.Reflection.FieldInfo? GetField(Type t, string name)
        {
            while (t != null)
            {
                var field = t.GetField(name, System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.DeclaredOnly);
                if (field != null) return field;
                t = t.BaseType;
            }

            return null;
        }

        static LspLocation? ToLocation(LocationLink link) => new LspLocation
        {
            Uri = link.TargetUri,
            Range = link.TargetRange
        };

        static LspLocation? TryExtractLocationOrLink(object obj)
        {
            if (obj is LspLocation loc) return loc;
            if (obj is LocationLink link) return ToLocation(link);

            var type = obj.GetType();

            foreach (var prop in type.GetProperties(System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic))
            {
                object? propValue;
                try
                {
                    propValue = prop.GetValue(obj);
                }
                catch
                {
                    continue;
                }

                if (propValue is LspLocation propLoc) return propLoc;
                if (propValue is LocationLink propLink) return ToLocation(propLink);
            }

            foreach (var field in GetAllFields(type))
            {
                object? fieldValue;
                try
                {
                    fieldValue = field.GetValue(obj);
                }
                catch
                {
                    continue;
                }

                if (fieldValue is LspLocation fieldLoc) return fieldLoc;
                if (fieldValue is LocationLink fieldLink) return ToLocation(fieldLink);
            }

            return null;
        }

        var boxed = (object)value;

        var type = boxed.GetType();

        // OmniSharp's LocationOrLocationLinks is an internal wrapper around IEnumerable<LocationOrLocationLink>.
        var itemsField = GetField(type, "_items");
        if (itemsField?.GetValue(boxed) is System.Collections.IEnumerable items)
        {
            foreach (var item in items)
            {
                if (item == null) continue;
                var extracted = TryExtractLocationOrLink(item);
                if (extracted != null) return extracted;
            }
        }

        // Fallback: scan the wrapper itself for a direct Location/LocationLink.
        foreach (var field in GetAllFields(type))
        {
            var fieldValue = field.GetValue(boxed);
            if (fieldValue == null) continue;
            var extracted = TryExtractLocationOrLink(fieldValue);
            if (extracted != null) return extracted;
        }

        var props = string.Join(", ", type.GetProperties(System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic)
            .Select(p => $"{p.Name}:{p.PropertyType.FullName}"));
        var fields = string.Join(", ", GetAllFields(type).Select(f => $"{f.Name}:{f.FieldType.FullName}"));
        throw new InvalidOperationException($"Unsupported {type.FullName} shape for definition response (properties: {props}; fields: {fields})");
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
        public DefinitionHandler DefinitionHandler { get; }

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

            DefinitionHandler = new DefinitionHandler(
                DocumentManager,
                NullLogger<DefinitionHandler>.Instance
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

        public async Task<LocationOrLocationLinks?> GetDefinitionAsync(string uri, int line, int character)
        {
            var request = new DefinitionParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Position = new Position(line, character)
            };

            return await DefinitionHandler.Handle(request, CancellationToken.None);
        }
    }

    #region Completion Tests

    [Fact]
    public async Task Completion_KeywordsAsync()
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
    public async Task Completion_PrimitiveTypesAsync()
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
    public async Task Completion_CommonDotNetTypesAsync()
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
    public async Task Completion_LocalFunctionsAsync()
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
    public async Task Completion_MemberAccess_ConsoleAsync()
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
    public async Task Completion_MemberAccess_StringAsync()
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
    public async Task Hover_KeywordAsync()
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
    public async Task Hover_PrimitiveTypeAsync()
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
    public async Task Hover_LocalVariableAsync()
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
    public async Task Hover_FunctionNameAsync()
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
    public async Task Hover_MemberAccess_PropertyAsync()
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
    public async Task Hover_MemberAccess_MethodAsync()
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
    public async Task Hover_MemberAccess_MethodWithParametersAsync()
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
    public async Task Hover_ChainedMemberAccessAsync()
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
    public async Task Hover_ConsoleWriteLineAsync()
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
    public async Task Hover_VariableWithSystemTypeAsync()
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
    public async Task SignatureHelp_ConsoleWriteLineAsync()
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
    public async Task SignatureHelp_StringFormatAsync()
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

    #region Definition Tests

    [Fact]
    public async Task Definition_TopLevelFunctionAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    Foo()

func Foo(): void
    return";

        harness.OpenDocument(uri, source);

        var definition = await harness.GetDefinitionAsync(uri, 2, 6);
        Assert.NotNull(definition);

        var location = ExtractSingleDefinitionLocation(definition!);
        Assert.Equal(4, location.Range.Start.Line);
        Assert.Equal(5, location.Range.Start.Character);
    }

    [Fact]
    public async Task Definition_LocalVariableAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let x := 1
    print(x)";

        harness.OpenDocument(uri, source);

        var definition = await harness.GetDefinitionAsync(uri, 3, 10);
        Assert.NotNull(definition);

        var location = ExtractSingleDefinitionLocation(definition!);
        Assert.Equal(2, location.Range.Start.Line);
        Assert.Equal(8, location.Range.Start.Character);
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
        var diagnostics = doc!.Diagnostics;
        Assert.NotEmpty(diagnostics);
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
        var diagnostics = doc!.Diagnostics;
        // Should have no errors (might have warnings from linter)
        Assert.DoesNotContain(diagnostics, d => d.Severity == NSharpLang.Compiler.ErrorSeverity.Error);
    }

    #endregion

    #region Document Update Tests

    [Fact]
    public async Task DocumentUpdate_CompletionsReflectChangesAsync()
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
    public async Task Completion_EmptyDocumentAsync()
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
    public async Task Hover_InvalidPositionAsync()
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
    public async Task Completion_AfterDot_NoIdentifierAsync()
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
    public async Task Completion_ChainedMemberAccessAsync()
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
    public async Task Completion_NestedFunctionsAsync()
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

    #region Rename / FindAllReferences Tests

    [Fact]
    public void FindAllReferences_FindsIdentifierInsideStringInterpolation()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/interpolation.nl";
        var source = @"func Main() {
    name := ""Spencer""
    greeting := $""Hello, {name}!""
    print name
}";
        harness.OpenDocument(uri, source);

        var refs = harness.DocumentManager.FindAllReferences(uri, "name");

        // Should find 3 references: declaration, interpolation, and print
        Assert.Equal(3, refs.Count);

        // Line 1: name := "Spencer"
        Assert.True(refs.Any(r => r.Line == 1 && r.Column == 4), "Should find 'name' in declaration on line 1");
        // Line 2: $"Hello, {name}!" — inside interpolation, should NOT be skipped
        Assert.True(refs.Any(r => r.Line == 2 && r.Column > 20), "Should find 'name' inside string interpolation on line 2");
        // Line 3: print name
        Assert.True(refs.Any(r => r.Line == 3), "Should find 'name' in print statement on line 3");
    }

    [Fact]
    public void FindAllReferences_DoesNotFindIdentifierInsideRegularString()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/regularstring.nl";
        var source = @"func Main() {
    name := ""Spencer""
    greeting := ""Hello, name!""
    print name
}";
        harness.OpenDocument(uri, source);

        var refs = harness.DocumentManager.FindAllReferences(uri, "name");

        // Should find only 2 references: declaration and print (NOT inside regular string)
        Assert.Equal(2, refs.Count);
        Assert.True(refs.Any(r => r.Line == 1 && r.Column == 4), "Should find 'name' in declaration");
        Assert.True(refs.Any(r => r.Line == 3), "Should find 'name' in print statement");
    }

    #endregion

    #region Member Completion Tests

    [Fact]
    public async Task Completion_MemberAccess_StringVariableAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/string-members.nl";

        var source = @"
func main(): void
    let message = ""hello""
    message.";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 3, 12);

        Assert.NotEmpty(completions.Items);
        // String should have Length, ToUpper, Contains, etc.
        Assert.Contains(completions.Items, c => c.Label == "Length");
        Assert.Contains(completions.Items, c => c.Label == "ToUpper");
    }

    [Fact]
    public async Task Completion_MemberAccess_StaticType_ConsoleAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/console-static.nl";

        var source = @"
func main(): void
    Console.";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 2, 12);

        Assert.NotEmpty(completions.Items);
        Assert.Contains(completions.Items, c => c.Label == "WriteLine");
        Assert.Contains(completions.Items, c => c.Label == "Write");
    }

    [Fact]
    public async Task Completion_MemberAccess_NSharpClassAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/nsharp-class.nl";

        var source = @"
class Person {
    Name: string
    Age: int

    func Greet(): string {
        return ""Hello""
    }
}

func main(): void
    let p = new Person()
    p.";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 12, 6);

        Assert.NotEmpty(completions.Items);
        // Should show N# class members from SymbolsInfo
        Assert.Contains(completions.Items, c => c.Label == "Name");
        Assert.Contains(completions.Items, c => c.Label == "Age");
        Assert.Contains(completions.Items, c => c.Label == "Greet");
    }

    [Fact]
    public async Task Completion_Namespace_SystemAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/namespace.nl";

        var source = @"
func main(): void
    System.";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 2, 11);

        Assert.NotEmpty(completions.Items);
        // System namespace should contain types from CoreLib (Array, Math, String, etc.)
        Assert.Contains(completions.Items, c => c.Label == "Array");
        Assert.Contains(completions.Items, c => c.Label == "Math");
        // Should also show sub-namespaces like Collections, Threading
        Assert.Contains(completions.Items, c => c.Label == "Collections" || c.Label == "Threading");
    }

    #endregion
}
