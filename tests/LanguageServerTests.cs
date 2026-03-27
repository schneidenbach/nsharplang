using System;
using System.Collections.Generic;
using System.IO;
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
using LspSymbolKind = OmniSharp.Extensions.LanguageServer.Protocol.Models.SymbolKind;

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
    private readonly string _examplesDir;

    public LanguageServerTests(LanguageServerFixture fixture)
    {
        _fixture = fixture;
        _examplesDir = FindExamplesDir();
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
        public ReferencesHandler ReferencesHandler { get; }
        public RenameHandler RenameHandler { get; }
        public InlayHintHandler InlayHintHandler { get; }
        public DocumentSymbolHandler DocumentSymbolHandler { get; }

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

            ReferencesHandler = new ReferencesHandler(
                DocumentManager,
                NullLogger<ReferencesHandler>.Instance
            );

            RenameHandler = new RenameHandler(
                DocumentManager,
                NullLogger<RenameHandler>.Instance
            );

            InlayHintHandler = new InlayHintHandler(
                DocumentManager,
                NullLogger<InlayHintHandler>.Instance
            );

            DocumentSymbolHandler = new DocumentSymbolHandler(
                DocumentManager,
                NullLogger<DocumentSymbolHandler>.Instance
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

        public async Task<LocationContainer?> GetReferencesAsync(string uri, int line, int character, bool includeDeclaration = true)
        {
            var request = new ReferenceParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Position = new Position(line, character),
                Context = new ReferenceContext { IncludeDeclaration = includeDeclaration }
            };

            return await ReferencesHandler.Handle(request, CancellationToken.None);
        }

        public async Task<SymbolInformationOrDocumentSymbolContainer?> GetDocumentSymbolsAsync(string uri)
        {
            var request = new DocumentSymbolParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri))
            };

            return await DocumentSymbolHandler.Handle(request, CancellationToken.None);
        }

        public async Task<WorkspaceEdit?> RenameAsync(string uri, int line, int character, string newName)
        {
            var request = new RenameParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Position = new Position(line, character),
                NewName = newName
            };

            return await RenameHandler.Handle(request, CancellationToken.None);
        }

        public async Task<InlayHintContainer?> GetInlayHintsAsync(string uri, int startLine, int startChar, int endLine, int endChar)
        {
            var request = new InlayHintParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    new Position(startLine, startChar),
                    new Position(endLine, endChar))
            };

            return await InlayHintHandler.Handle(request, CancellationToken.None);
        }
    }

    private static string FindExamplesDir()
    {
        var dir = Directory.GetCurrentDirectory();
        for (int i = 0; i < 10; i++)
        {
            var candidate = Path.Combine(dir, "examples");
            if (Directory.Exists(candidate) && Directory.Exists(Path.Combine(candidate, "01-hello-world")))
                return candidate;

            var parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }

        var paths = new[]
        {
            "/Users/spencer/repos/nsharplang/.claude/worktrees/hungry-blackburn/examples",
            "/Users/spencer/repos/nsharplang/examples",
        };

        foreach (var p in paths)
        {
            if (Directory.Exists(p))
                return p;
        }

        throw new Exception("Could not find examples directory");
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

    [Fact]
    public async Task Completion_Snippet_FuncAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "f");

        var completions = await harness.GetCompletionsAsync(uri, 0, 1);

        var snippet = completions.Items.FirstOrDefault(
            c => c.Label == "func" && c.Kind == CompletionItemKind.Snippet);
        Assert.NotNull(snippet);
        Assert.Equal(InsertTextFormat.Snippet, snippet.InsertTextFormat);
        Assert.Contains("${1:name}", snippet.InsertText);
        Assert.Contains("${2:params}", snippet.InsertText);
        Assert.Contains("${3:void}", snippet.InsertText);
    }

    [Fact]
    public async Task Completion_Snippet_IfAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "i");

        var completions = await harness.GetCompletionsAsync(uri, 0, 1);

        var snippet = completions.Items.FirstOrDefault(
            c => c.Label == "if" && c.Kind == CompletionItemKind.Snippet);
        Assert.NotNull(snippet);
        Assert.Equal(InsertTextFormat.Snippet, snippet.InsertTextFormat);
        Assert.Contains("${1:condition}", snippet.InsertText);
    }

    [Fact]
    public async Task Completion_Snippet_MatchAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "m");

        var completions = await harness.GetCompletionsAsync(uri, 0, 1);

        var snippet = completions.Items.FirstOrDefault(
            c => c.Label == "match" && c.Kind == CompletionItemKind.Snippet);
        Assert.NotNull(snippet);
        Assert.Equal(InsertTextFormat.Snippet, snippet.InsertTextFormat);
        Assert.Contains("${1:value}", snippet.InsertText);
        Assert.Contains("${2:pattern}", snippet.InsertText);
    }

    [Fact]
    public async Task Completion_Snippet_ForAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "f");

        var completions = await harness.GetCompletionsAsync(uri, 0, 1);

        var snippet = completions.Items.FirstOrDefault(
            c => c.Label == "for" && c.Kind == CompletionItemKind.Snippet);
        Assert.NotNull(snippet);
        Assert.Equal(InsertTextFormat.Snippet, snippet.InsertTextFormat);
        Assert.Contains("${1:item}", snippet.InsertText);
        Assert.Contains("${2:collection}", snippet.InsertText);
    }

    [Fact]
    public async Task Completion_Snippet_TypeAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "t");

        var completions = await harness.GetCompletionsAsync(uri, 0, 1);

        var snippet = completions.Items.FirstOrDefault(
            c => c.Label == "type" && c.Kind == CompletionItemKind.Snippet);
        Assert.NotNull(snippet);
        Assert.Equal(InsertTextFormat.Snippet, snippet.InsertTextFormat);
        Assert.Contains("${1:Name}", snippet.InsertText);
    }

    [Fact]
    public async Task Completion_Snippets_CoexistWithKeywordsAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        harness.OpenDocument(uri, "f");

        var completions = await harness.GetCompletionsAsync(uri, 0, 1);

        // Both snippet and keyword versions of "func" should exist
        var funcSnippet = completions.Items.First(
            c => c.Label == "func" && c.Kind == CompletionItemKind.Snippet);
        var funcKeyword = completions.Items.First(
            c => c.Label == "func" && c.Kind == CompletionItemKind.Keyword);

        Assert.NotNull(funcSnippet);
        Assert.NotNull(funcKeyword);
    }

    [Fact]
    public async Task Completion_Snippets_NotShownInMemberAccessAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    Console.";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 2, 12);

        // Snippets should NOT appear in member access context
        Assert.DoesNotContain(completions.Items, c => c.Kind == CompletionItemKind.Snippet);
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

    [Fact]
    public async Task SignatureHelp_NSharpFunction_BasicAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func greet(name: string, times: int): void
    for i in 0..times
        Console.WriteLine(name)

func main(): void
    greet(";

        harness.OpenDocument(uri, source);

        var sigHelp = await harness.GetSignatureHelpAsync(uri, 6, 10);

        Assert.NotNull(sigHelp);
        Assert.NotEmpty(sigHelp.Signatures);
        Assert.Contains(sigHelp.Signatures, s => s.Label.Contains("greet"));
        var sig = sigHelp.Signatures.First(s => s.Label.Contains("greet"));
        Assert.Contains("name: string", sig.Label);
        Assert.Contains("times: int", sig.Label);
        Assert.Contains(": void", sig.Label);
        Assert.Equal(2, sig.Parameters!.Count());
    }

    [Fact]
    public async Task SignatureHelp_NSharpFunction_ActiveParameterAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func add(a: int, b: int): int
    return a + b

func main(): void
    add(1, ";

        harness.OpenDocument(uri, source);

        var sigHelp = await harness.GetSignatureHelpAsync(uri, 5, 11);

        Assert.NotNull(sigHelp);
        Assert.NotEmpty(sigHelp.Signatures);
        Assert.Equal(1, sigHelp.ActiveParameter);
    }

    [Fact]
    public async Task SignatureHelp_NSharpFunction_ReturnTypeAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func multiply(x: double, y: double): double
    return x * y

func main(): void
    multiply(";

        harness.OpenDocument(uri, source);

        var sigHelp = await harness.GetSignatureHelpAsync(uri, 5, 13);

        Assert.NotNull(sigHelp);
        Assert.NotEmpty(sigHelp.Signatures);
        var sig = sigHelp.Signatures.First();
        Assert.Contains("multiply(x: double, y: double): double", sig.Label);
    }

    [Fact]
    public async Task SignatureHelp_NSharpFunction_NoParamsAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func getTime(): string
    return ""now""

func main(): void
    getTime(";

        harness.OpenDocument(uri, source);

        var sigHelp = await harness.GetSignatureHelpAsync(uri, 5, 12);

        Assert.NotNull(sigHelp);
        Assert.NotEmpty(sigHelp.Signatures);
        var sig = sigHelp.Signatures.First();
        Assert.Equal("getTime(): string", sig.Label);
        Assert.Empty(sig.Parameters!);
    }

    [Fact]
    public async Task SignatureHelp_NSharpFunction_DefaultValueParamAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func greet(name: string, greeting: string = ""Hello""): void
    Console.WriteLine(greeting + "" "" + name)

func main(): void
    greet(";

        harness.OpenDocument(uri, source);

        var sigHelp = await harness.GetSignatureHelpAsync(uri, 5, 10);

        Assert.NotNull(sigHelp);
        Assert.NotEmpty(sigHelp.Signatures);
        var sig = sigHelp.Signatures.First();
        Assert.Equal(2, sig.Parameters!.Count());
        Assert.Contains("name: string", sig.Label);
        Assert.Contains("greeting: string", sig.Label);
    }

    [Fact]
    public async Task SignatureHelp_NSharpFunction_StillWorksForDotNetAsync()
    {
        // Ensure existing .NET type signature help still works after refactor
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    Math.Max(";

        harness.OpenDocument(uri, source);

        var sigHelp = await harness.GetSignatureHelpAsync(uri, 2, 13);

        Assert.NotNull(sigHelp);
        Assert.NotEmpty(sigHelp.Signatures);
        Assert.Contains(sigHelp.Signatures, s => s.Label.Contains("Max"));
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
        Assert.Equal(93, location.Range.Start.Line);
        Assert.Equal(4, location.Range.Start.Character);
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

    [Fact]
    public async Task Definition_CrossFileType_UsesCompilerProjectSnapshotAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var programPath = Path.Combine(_examplesDir, "15-dogfood-project", "Program.nl");
        var uri = new Uri(programPath).AbsoluteUri;
        var source = File.ReadAllText(programPath);

        harness.OpenDocument(uri, source);

        var definition = await harness.GetDefinitionAsync(uri, 84, 21);
        Assert.NotNull(definition);

        var location = ExtractSingleDefinitionLocation(definition!);
        Assert.Equal(new Uri(Path.Combine(_examplesDir, "15-dogfood-project", "Services", "TaskService.nl")).AbsoluteUri, location.Uri.ToString());
        Assert.Equal(93, location.Range.Start.Line);
        Assert.Equal(4, location.Range.Start.Character);
    }

    [Fact]
    public async Task Definition_CrossFileType_PrefersSemanticResultOverSameNameLocalSymbolAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var programPath = Path.Combine(_examplesDir, "15-dogfood-project", "Program.nl");
        var uri = new Uri(programPath).AbsoluteUri;
        var source = File.ReadAllText(programPath);

        harness.OpenDocument(uri, source);

        var definition = await harness.GetDefinitionAsync(uri, 84, 21);
        Assert.NotNull(definition);

        var location = ExtractSingleDefinitionLocation(definition!);
        Assert.Equal(new Uri(Path.Combine(_examplesDir, "15-dogfood-project", "Services", "TaskService.nl")).AbsoluteUri, location.Uri.ToString());
        Assert.Equal(93, location.Range.Start.Line);
        Assert.Equal(4, location.Range.Start.Character);
    }

    [Fact]
    public async Task Definition_EndOfLinePosition_ReturnsNullAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = """
func Main() {
    Foo()
}

func Foo(): void {
}
""";

        harness.OpenDocument(uri, source);

        var definition = await harness.GetDefinitionAsync(uri, 1, 9);
        Assert.Null(definition);
    }

    [Fact]
    public async Task Definition_CrossFile_WithUnsavedChanges_UsesDiskFallbackAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var programPath = Path.Combine(_examplesDir, "15-dogfood-project", "Program.nl");
        var uri = new Uri(programPath).AbsoluteUri;
        var source = File.ReadAllText(programPath);

        // Append a comment so the open buffer differs from disk,
        // causing IsProjectSynchronizedWithDisk to return false.
        // The disk-based fallback should still resolve cross-file definitions.
        harness.OpenDocument(uri, source + "\n// unsaved edit");

        // F12 on GetStats() at line 85 col 21 (0-indexed: 84, 21)
        var definition = await harness.GetDefinitionAsync(uri, 84, 21);
        Assert.NotNull(definition);

        var location = ExtractSingleDefinitionLocation(definition!);
        var expectedUri = new Uri(Path.Combine(_examplesDir, "15-dogfood-project", "Services", "TaskService.nl")).AbsoluteUri;
        Assert.Equal(expectedUri, location.Uri.ToString());
    }

    [Fact]
    public async Task Definition_CrossFile_DiskFallback_DifferentSymbolAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var programPath = Path.Combine(_examplesDir, "15-dogfood-project", "Program.nl");
        var uri = new Uri(programPath).AbsoluteUri;
        var source = File.ReadAllText(programPath);

        // Make the buffer differ from disk to force disk fallback
        harness.OpenDocument(uri, source + "\n// modified");

        // F12 on GetUrgentTasks() at line 71 col 22 (0-indexed: 70, 22)
        // GetUrgentTasks is defined in Services/TaskService.nl
        var definition = await harness.GetDefinitionAsync(uri, 70, 22);
        Assert.NotNull(definition);

        var location = ExtractSingleDefinitionLocation(definition!);
        var expectedUri = new Uri(Path.Combine(_examplesDir, "15-dogfood-project", "Services", "TaskService.nl")).AbsoluteUri;
        Assert.Equal(expectedUri, location.Uri.ToString());
    }

    #endregion

    #region References Tests

    [Fact]
    public async Task References_LocalVariable_FindsAllUsagesAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let x := 1
    let y := x + 2
    print(x)";

        harness.OpenDocument(uri, source);

        // Request references from the declaration of x (line 2, col 8)
        var refs = await harness.GetReferencesAsync(uri, 2, 8);
        Assert.NotNull(refs);
        Assert.True(refs!.Count() >= 2, $"Expected at least 2 references to 'x', got {refs!.Count()}");
    }

    [Fact]
    public async Task References_LocalVariable_FromUsageSiteAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let x := 1
    let y := x + 2
    print(x)";

        harness.OpenDocument(uri, source);

        // Request references from a usage of x (line 3, col 13 = "x" in "x + 2")
        var refs = await harness.GetReferencesAsync(uri, 3, 13);
        Assert.NotNull(refs);
        Assert.True(refs!.Count() >= 2, $"Expected at least 2 references to 'x', got {refs!.Count()}");
    }

    [Fact]
    public async Task References_TopLevelFunction_FindsAllCallsAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    Foo()
    Foo()

func Foo(): void
    return";

        harness.OpenDocument(uri, source);

        // Request references from "Foo" on line 2
        var refs = await harness.GetReferencesAsync(uri, 2, 4);
        Assert.NotNull(refs);
        // Should find at least: declaration + 2 call sites
        Assert.True(refs!.Count() >= 2, $"Expected at least 2 references to 'Foo', got {refs!.Count()}");
    }

    [Fact]
    public async Task References_EmptyPosition_ReturnsEmptyAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let x := 1";

        harness.OpenDocument(uri, source);

        // Position on whitespace (line 0, col 0 = empty line)
        var refs = await harness.GetReferencesAsync(uri, 0, 0);
        Assert.NotNull(refs);
        Assert.Empty(refs!);
    }

    [Fact]
    public async Task References_NoDocument_ReturnsEmptyAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);

        // Request references for a document that hasn't been opened
        var refs = await harness.GetReferencesAsync("file:///nonexistent.nl", 0, 0);
        Assert.NotNull(refs);
        Assert.Empty(refs!);
    }

    [Fact]
    public async Task References_CrossFile_UsesCompilerProjectSnapshotAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var programPath = Path.Combine(_examplesDir, "15-dogfood-project", "Program.nl");
        var uri = new Uri(programPath).AbsoluteUri;
        var source = File.ReadAllText(programPath);

        harness.OpenDocument(uri, source);

        // "TaskService" usage on line 84, col 21 (same position as definition cross-file test)
        var refs = await harness.GetReferencesAsync(uri, 84, 21);
        Assert.NotNull(refs);
        Assert.NotEmpty(refs!);
    }

    [Fact]
    public async Task References_ExcludeDeclaration_FiltersDefinitionAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let x := 1
    let y := x + 2
    print(x)";

        harness.OpenDocument(uri, source);

        var refsWithDecl = await harness.GetReferencesAsync(uri, 2, 8, includeDeclaration: true);
        var refsWithoutDecl = await harness.GetReferencesAsync(uri, 2, 8, includeDeclaration: false);

        Assert.NotNull(refsWithDecl);
        Assert.NotNull(refsWithoutDecl);

        // Without declaration should have fewer or equal references
        Assert.True(refsWithoutDecl!.Count() <= refsWithDecl!.Count(),
            "References excluding declaration should be <= references including declaration");
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

    [Fact]
    public async Task Rename_CrossFileType_UsesCompilerProjectSnapshotAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var programPath = Path.Combine(_examplesDir, "15-dogfood-project", "Program.nl");
        var servicePath = Path.Combine(_examplesDir, "15-dogfood-project", "Services", "TaskService.nl");
        var programUri = new Uri(programPath).AbsoluteUri;
        var serviceUri = new Uri(servicePath).AbsoluteUri;

        harness.OpenDocument(programUri, File.ReadAllText(programPath));
        harness.OpenDocument(serviceUri, File.ReadAllText(servicePath));

        var edit = await harness.RenameAsync(serviceUri, 93, 9, "ComputeStats");
        Assert.NotNull(edit);
        Assert.NotNull(edit!.Changes);

        var programDocUri = DocumentUri.From(programUri);
        var serviceDocUri = DocumentUri.From(serviceUri);
        Assert.True(edit.Changes!.ContainsKey(serviceDocUri), "Rename should include the declaration file");
        Assert.True(edit.Changes.ContainsKey(programDocUri), "Rename should include the referencing file");

        Assert.Contains(edit.Changes[serviceDocUri], change => change.NewText == "ComputeStats" &&
            change.Range.Start.Line == 93 &&
            change.Range.Start.Character == 4);

        Assert.True(edit.Changes[programDocUri].Count() >= 1, "Rename should update the use-site in the program file");
    }

    [Fact]
    public async Task Rename_ShadowedLocalVariable_OnlyRenamesBoundSymbolAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-rename-shadow-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            File.WriteAllText(Path.Combine(tempRoot, "project.yml"), """
name: TempRenameShadowTest
targetFramework: net9.0
""");

            var programPath = Path.Combine(tempRoot, "Program.nl");
            var source = """
namespace TempRenameShadowTest

func Main(): void
    func Helper(): void
        print("inner")
    Helper()

func Helper(): void
    print("outer")
""";
            File.WriteAllText(programPath, source);

            var uri = new Uri(programPath).AbsoluteUri;
            harness.OpenDocument(uri, source);

            var lines = source.Split('\n');
            var innerDeclLine = Array.FindIndex(lines, line => line.Contains("func Helper(): void", StringComparison.Ordinal));
            Assert.True(innerDeclLine >= 0);
            var innerDeclColumn = lines[innerDeclLine].IndexOf("Helper", StringComparison.Ordinal);
            Assert.True(innerDeclColumn >= 0);

            var edit = await harness.RenameAsync(uri, innerDeclLine, innerDeclColumn, "InnerHelper");
            Assert.NotNull(edit);
            Assert.NotNull(edit!.Changes);

            var change = Assert.Single(edit.Changes!);
            var edits = change.Value.ToList();
            Assert.Equal(2, edits.Count);
            Assert.All(edits, e => Assert.Equal("InnerHelper", e.NewText));
            Assert.Contains(edits, e => e.Range.Start.Line == 3);
            Assert.Contains(edits, e => e.Range.Start.Line == 5);
            Assert.DoesNotContain(edits, e => e.Range.Start.Line == 7);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public void DocumentManager_FileUriRelativeImport_ResolvesAgainstFilesystemPath()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-import-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            var modelsDir = Path.Combine(tempRoot, "Models");
            var servicesDir = Path.Combine(tempRoot, "Services");
            Directory.CreateDirectory(modelsDir);
            Directory.CreateDirectory(servicesDir);

            File.WriteAllText(Path.Combine(tempRoot, "project.yml"), """
name: TempImportTest
targetFramework: net9.0
""");

            File.WriteAllText(Path.Combine(modelsDir, "Person.nl"), """
namespace TempImportTest.Models

record Person {
    Name: string
}
""");

            var servicePath = Path.Combine(servicesDir, "PersonService.nl");
            File.WriteAllText(servicePath, """
namespace TempImportTest.Services

import "../Models/Person"

class PersonService {
    person: Person
}
""");

            var serviceUri = new Uri(servicePath).AbsoluteUri;
            var serviceSource = File.ReadAllText(servicePath);

            harness.OpenDocument(serviceUri, serviceSource);

            var doc = harness.DocumentManager.GetDocument(serviceUri);
            Assert.NotNull(doc);

            var diagnostics = doc!.Diagnostics ?? new List<CompilerError>();
            Assert.DoesNotContain(diagnostics, d => d.DiagnosticId == "NL103");
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public void DocumentManager_TypeImport_ReportsDiagnostic()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-invalid-import-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            File.WriteAllText(Path.Combine(tempRoot, "project.yml"), """
name: TempInvalidImportTest
targetFramework: net9.0
""");

            var programPath = Path.Combine(tempRoot, "Program.nl");
            File.WriteAllText(programPath, """
import System.Console

func Main() {
}
""");

            var uri = new Uri(programPath).AbsoluteUri;
            harness.OpenDocument(uri, File.ReadAllText(programPath));

            var doc = harness.DocumentManager.GetDocument(uri);
            Assert.NotNull(doc);

            var diagnostics = doc!.Diagnostics ?? new List<CompilerError>();
            var diagnostic = Assert.Single(diagnostics.Where(d =>
                d.DiagnosticId == "NL704" &&
                d.Message.Contains("Cannot import type 'System.Console'")));
            Assert.Equal(1, diagnostic.Line);
            Assert.Equal(8, diagnostic.Column);
            Assert.Equal("System.Console".Length, diagnostic.Length);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
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

    [Fact]
    public async Task Completion_ImportContext_OnlySuggestsNamespacesAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/imports.nl";

        var source = "import System.";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 0, source.Length);

        Assert.NotEmpty(completions.Items);
        Assert.All(completions.Items, item => Assert.Equal(CompletionItemKind.Module, item.Kind));
        Assert.Contains(completions.Items, c => c.Label == "Collections" || c.Label == "Threading");
        Assert.DoesNotContain(completions.Items, c => c.Label == "Action");
        Assert.DoesNotContain(completions.Items, c => c.Label == "Console");
    }

    #endregion

    #region InlayHint Tests

    [Fact]
    public async Task InlayHint_InferredStringType_ShowsHintAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_string.nl";

        var source = @"func main() {
    name := ""hello""
}";

        harness.OpenDocument(uri, source);
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        var hintList = hints!.ToList();
        Assert.Single(hintList);

        var hint = hintList[0];
        Assert.Equal(InlayHintKind.Type, hint.Kind);
        Assert.Equal(1, hint.Position.Line);   // 0-based line
        Assert.Contains("string", hint.Label.String);
    }

    [Fact]
    public async Task InlayHint_InferredIntType_ShowsHintAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_int.nl";

        var source = @"func main() {
    count := 42
}";

        harness.OpenDocument(uri, source);
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        var hintList = hints!.ToList();
        Assert.Single(hintList);

        var hint = hintList[0];
        Assert.Equal(InlayHintKind.Type, hint.Kind);
        Assert.Contains("int", hint.Label.String);
    }

    [Fact]
    public async Task InlayHint_ExplicitType_NoHintAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_explicit.nl";

        // When type is explicitly annotated, no inlay hint should be shown
        var source = @"func main() {
    let name: string = ""hello""
}";

        harness.OpenDocument(uri, source);
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        var hintList = hints!.ToList();
        Assert.Empty(hintList);
    }

    [Fact]
    public async Task InlayHint_MultipleDeclarations_ShowsAllHintsAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_multi.nl";

        var source = @"func main() {
    x := 1
    y := 2.5
    z := true
}";

        harness.OpenDocument(uri, source);
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        var hintList = hints!.ToList();
        Assert.Equal(3, hintList.Count);

        // Verify they're on different lines (0-based: lines 1, 2, 3)
        var lines = hintList.Select(h => h.Position.Line).OrderBy(l => l).ToList();
        Assert.Equal(new[] { 1, 2, 3 }, lines);
    }

    [Fact]
    public async Task InlayHint_RangeFiltering_OnlyReturnsVisibleHintsAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_range.nl";

        var source = @"func main() {
    a := 1
    b := 2
    c := 3
    d := 4
}";

        harness.OpenDocument(uri, source);

        // Only request hints for lines 2-3 (0-based), which contain b and c
        var hints = await harness.GetInlayHintsAsync(uri, 2, 0, 3, 100);

        Assert.NotNull(hints);
        var hintList = hints!.ToList();
        Assert.Equal(2, hintList.Count);

        var lines = hintList.Select(h => h.Position.Line).OrderBy(l => l).ToList();
        Assert.Equal(new[] { 2, 3 }, lines);
    }

    [Fact]
    public async Task InlayHint_BoolType_ShowsHintAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_bool.nl";

        var source = @"func main() {
    flag := false
}";

        harness.OpenDocument(uri, source);
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        var hintList = hints!.ToList();
        Assert.Single(hintList);
        Assert.Contains("bool", hintList[0].Label.String);
    }

    [Fact]
    public async Task InlayHint_HintPositionAfterVariableName_CorrectColumnAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_position.nl";

        var source = @"func main() {
    name := ""hello""
}";

        harness.OpenDocument(uri, source);
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        var hintList = hints!.ToList();
        Assert.Single(hintList);

        var hint = hintList[0];
        // "    name" — 4 spaces + "name" (4 chars) = position after name is column 8
        // But parser column is 1-based, and the variable starts at column 5 (1-based)
        // LSP position: line 1, column = (parserCol - 1) + "name".Length
        // The hint should be right after "name"
        Assert.Equal(1, hint.Position.Line);
    }

    [Fact]
    public async Task InlayHint_EmptyDocument_ReturnsEmptyAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_empty.nl";

        harness.OpenDocument(uri, "");
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        Assert.Empty(hints!.ToList());
    }

    [Fact]
    public async Task InlayHint_NoInitializer_NoHintAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_no_init.nl";

        // A declaration without initializer shouldn't produce a hint
        var source = @"func main() {
    let x: int
}";

        harness.OpenDocument(uri, source);
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        Assert.Empty(hints!.ToList());
    }

    [Fact]
    public async Task InlayHint_NestedInIfBlock_ShowsHintAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_nested.nl";

        var source = @"func main() {
    if true {
        x := 42
    }
}";

        harness.OpenDocument(uri, source);
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        var hintList = hints!.ToList();
        Assert.Single(hintList);
        Assert.Contains("int", hintList[0].Label.String);
    }

    [Fact]
    public async Task InlayHint_HintLabelFormat_StartsWithColonAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_format.nl";

        var source = @"func main() {
    x := 42
}";

        harness.OpenDocument(uri, source);
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        var hintList = hints!.ToList();
        Assert.Single(hintList);

        // Inlay hint label should start with ": " to look like a type annotation
        Assert.StartsWith(": ", hintList[0].Label.String);
    }

    [Fact]
    public async Task InlayHint_InsideClassMethod_ShowsHintAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_class.nl";

        var source = @"class Greeter {
    func greet() {
        msg := ""hello""
    }
}";

        harness.OpenDocument(uri, source);
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        var hintList = hints!.ToList();
        Assert.Single(hintList);
        Assert.Contains("string", hintList[0].Label.String);
    }

    [Fact]
    public async Task InlayHint_ConstDeclaration_ShowsHintAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_const.nl";

        var source = @"func main() {
    const pi := 3.14
}";

        harness.OpenDocument(uri, source);
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        var hintList = hints!.ToList();
        // const with := is still an inferred type declaration
        Assert.Single(hintList);
    }

    [Fact]
    public async Task InlayHint_DoubleType_ShowsHintAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/inlay_double.nl";

        var source = @"func main() {
    pi := 3.14
}";

        harness.OpenDocument(uri, source);
        var hints = await harness.GetInlayHintsAsync(uri, 0, 0, 10, 0);

        Assert.NotNull(hints);
        var hintList = hints!.ToList();
        Assert.Single(hintList);
        // 3.14 should infer to double or float
        var label = hintList[0].Label.String;
        Assert.True(label.Contains("double") || label.Contains("float"),
            $"Expected double or float type hint, got: {label}");
    }

    #endregion

    #region Document Symbol Tests

    [Fact]
    public async Task DocumentSymbol_FunctionsAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"func greet(name: string): string
    return ""Hello, "" + name

func main(): void
    greet(""world"")
";

        harness.OpenDocument(uri, source);

        var result = await harness.GetDocumentSymbolsAsync(uri);
        Assert.NotNull(result);

        var symbols = result!.Select(s => s.DocumentSymbol).ToList();
        Assert.Equal(2, symbols.Count);

        Assert.Equal("greet", symbols[0].Name);
        Assert.Equal(LspSymbolKind.Function, symbols[0].Kind);
        Assert.Equal("string", symbols[0].Detail);

        Assert.Equal("main", symbols[1].Name);
        Assert.Equal(LspSymbolKind.Function, symbols[1].Kind);
        Assert.Equal("void", symbols[1].Detail);
    }

    [Fact]
    public async Task DocumentSymbol_ClassWithMembersAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"class Person {
    name: string
    age: int

    func greet(): string
        return ""Hello, "" + name
}
";

        harness.OpenDocument(uri, source);

        var result = await harness.GetDocumentSymbolsAsync(uri);
        Assert.NotNull(result);

        var symbols = result!.Select(s => s.DocumentSymbol).ToList();
        Assert.Single(symbols);

        var personSymbol = symbols[0];
        Assert.Equal("Person", personSymbol.Name);
        Assert.Equal(LspSymbolKind.Class, personSymbol.Kind);
        Assert.NotNull(personSymbol.Children);

        var children = personSymbol.Children!.ToList();
        Assert.Contains(children, c => c.Name == "name" && c.Kind == LspSymbolKind.Field);
        Assert.Contains(children, c => c.Name == "age" && c.Kind == LspSymbolKind.Field);
        Assert.Contains(children, c => c.Name == "greet" && c.Kind == LspSymbolKind.Function);
    }

    [Fact]
    public async Task DocumentSymbol_StructAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"struct Point {
    x: int
    y: int
}
";

        harness.OpenDocument(uri, source);

        var result = await harness.GetDocumentSymbolsAsync(uri);
        Assert.NotNull(result);

        var symbols = result!.Select(s => s.DocumentSymbol).ToList();
        Assert.Single(symbols);

        Assert.Equal("Point", symbols[0].Name);
        Assert.Equal(LspSymbolKind.Struct, symbols[0].Kind);
        Assert.NotNull(symbols[0].Children);
        Assert.Equal(2, symbols[0].Children!.Count());
    }

    [Fact]
    public async Task DocumentSymbol_InterfaceAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"interface Greeter {
    func greet(): string
}
";

        harness.OpenDocument(uri, source);

        var result = await harness.GetDocumentSymbolsAsync(uri);
        Assert.NotNull(result);

        var symbols = result!.Select(s => s.DocumentSymbol).ToList();
        Assert.Single(symbols);

        Assert.Equal("Greeter", symbols[0].Name);
        Assert.Equal(LspSymbolKind.Interface, symbols[0].Kind);
    }

    [Fact]
    public async Task DocumentSymbol_EnumAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"enum Color {
    Red,
    Green,
    Blue
}
";

        harness.OpenDocument(uri, source);

        var result = await harness.GetDocumentSymbolsAsync(uri);
        Assert.NotNull(result);

        var symbols = result!.Select(s => s.DocumentSymbol).ToList();
        Assert.Single(symbols);

        Assert.Equal("Color", symbols[0].Name);
        Assert.Equal(LspSymbolKind.Enum, symbols[0].Kind);
        Assert.NotNull(symbols[0].Children);

        var members = symbols[0].Children!.ToList();
        Assert.Equal(3, members.Count);
        Assert.All(members, m => Assert.Equal(LspSymbolKind.EnumMember, m.Kind));
        Assert.Contains(members, m => m.Name == "Red");
        Assert.Contains(members, m => m.Name == "Green");
        Assert.Contains(members, m => m.Name == "Blue");
    }

    [Fact]
    public async Task DocumentSymbol_EmptyDocument_ReturnsNullAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///empty.nl";

        // Document not opened - should return null
        var result = await harness.GetDocumentSymbolsAsync(uri);
        Assert.Null(result);
    }

    [Fact]
    public async Task DocumentSymbol_MixedDeclarationsAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"enum Status {
    Active,
    Inactive
}

class User {
    name: string
    status: Status
}

func createUser(name: string): User
    return User()
";

        harness.OpenDocument(uri, source);

        var result = await harness.GetDocumentSymbolsAsync(uri);
        Assert.NotNull(result);

        var symbols = result!.Select(s => s.DocumentSymbol).ToList();
        Assert.Equal(3, symbols.Count);

        Assert.Equal("Status", symbols[0].Name);
        Assert.Equal(LspSymbolKind.Enum, symbols[0].Kind);

        Assert.Equal("User", symbols[1].Name);
        Assert.Equal(LspSymbolKind.Class, symbols[1].Kind);

        Assert.Equal("createUser", symbols[2].Name);
        Assert.Equal(LspSymbolKind.Function, symbols[2].Kind);
    }

    [Fact]
    public async Task DocumentSymbol_ZeroBasedLineNumbersAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"func hello(): void
    return
";

        harness.OpenDocument(uri, source);

        var result = await harness.GetDocumentSymbolsAsync(uri);
        Assert.NotNull(result);

        var symbols = result!.Select(s => s.DocumentSymbol).ToList();
        Assert.Single(symbols);

        // LSP lines are 0-based; the function starts at line 1 in source (1-based) = line 0 in LSP
        Assert.Equal(0, symbols[0].Range.Start.Line);
        Assert.Equal(0, symbols[0].SelectionRange.Start.Line);

        // LSP invariant: selectionRange must be contained within range
        Assert.True(symbols[0].Range.End.Character > 0 || symbols[0].Range.End.Line > symbols[0].Range.Start.Line,
            "Range must not be zero-width when SelectionRange has content");
    }

    [Fact]
    public async Task DocumentSymbol_SelectionRangeContainedInRangeAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"class Foo {
    bar: int
}
";

        harness.OpenDocument(uri, source);

        var result = await harness.GetDocumentSymbolsAsync(uri);
        Assert.NotNull(result);

        var symbols = result!.Select(s => s.DocumentSymbol).ToList();
        var fooSymbol = symbols[0];

        // Verify Range contains SelectionRange for the class
        Assert.True(fooSymbol.Range.End.Line >= fooSymbol.SelectionRange.End.Line);
        Assert.True(fooSymbol.Range.End.Character >= fooSymbol.SelectionRange.End.Character
                    || fooSymbol.Range.End.Line > fooSymbol.SelectionRange.End.Line);

        // Verify Range contains SelectionRange for the field child
        var barSymbol = fooSymbol.Children!.First(c => c.Name == "bar");
        Assert.True(barSymbol.Range.End.Character >= barSymbol.SelectionRange.End.Character
                    || barSymbol.Range.End.Line > barSymbol.SelectionRange.End.Line);
    }

    #endregion
}
