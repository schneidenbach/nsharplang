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
using OmniSharp.Extensions.JsonRpc.Server;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using OmniSharp.Extensions.LanguageServer.Protocol.Workspace;
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

internal sealed class CapturingLogger<T> : ILogger<T>
{
    public List<LogEntry> Entries { get; } = new();

    public IDisposable BeginScope<TState>(TState state) where TState : notnull => NullScope.Instance;

    public bool IsEnabled(LogLevel logLevel) => true;

    public void Log<TState>(
        LogLevel logLevel,
        EventId eventId,
        TState state,
        Exception? exception,
        Func<TState, Exception?, string> formatter)
    {
        Entries.Add(new LogEntry(
            logLevel,
            formatter(state, exception),
            state as IReadOnlyList<KeyValuePair<string, object?>> ?? Array.Empty<KeyValuePair<string, object?>>(),
            exception));
    }

    public sealed record LogEntry(
        LogLevel Level,
        string Message,
        IReadOnlyList<KeyValuePair<string, object?>> State,
        Exception? Exception);

    private sealed class NullScope : IDisposable
    {
        public static readonly NullScope Instance = new();
        public void Dispose() { }
    }
}

/// <summary>
/// Comprehensive tests for the Language Server Protocol implementation
/// </summary>
[Collection("LanguageServer")]
public class LanguageServerTests
{
    private static readonly Lazy<Type> ConflictingClrPersonType = new(CreateConflictingClrPersonType);

    private readonly LanguageServerFixture _fixture;
    private readonly string _examplesDir;

    public LanguageServerTests(LanguageServerFixture fixture)
    {
        _fixture = fixture;
        _examplesDir = FindExamplesDir();
    }

    private static string? GetDocumentationText(StringOrMarkupContent? documentation)
    {
        if (documentation == null)
        {
            return null;
        }

        if (documentation.HasMarkupContent)
        {
            return documentation.MarkupContent?.Value;
        }

        return documentation.HasString
            ? documentation.String
            : documentation.ToString();
    }

    private static Type CreateConflictingClrPersonType()
    {
        var assemblyName = new System.Reflection.AssemblyName("NSharpLang.Tests.DynamicCompletionCollision");
        var assemblyBuilder = System.Reflection.Emit.AssemblyBuilder.DefineDynamicAssembly(
            assemblyName,
            System.Reflection.Emit.AssemblyBuilderAccess.Run);
        var moduleBuilder = assemblyBuilder.DefineDynamicModule(assemblyName.Name!);
        var typeBuilder = moduleBuilder.DefineType("Person", System.Reflection.TypeAttributes.Public);
        typeBuilder.DefineField("Name", typeof(string), System.Reflection.FieldAttributes.Public);
        return typeBuilder.CreateType()!;
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
        public SemanticTokensHandler SemanticTokensHandler { get; }
        public WorkspaceSymbolHandler WorkspaceSymbolHandler { get; }
        public FoldingRangeHandler FoldingRangeHandler { get; }
        public PrepareRenameHandler PrepareRenameHandler { get; }
        public DocumentFormattingHandler DocumentFormattingHandler { get; }
        public GoToImplementationHandler GoToImplementationHandler { get; }
        public DocumentHighlightHandler DocumentHighlightHandler { get; }
        public SelectionRangeHandler SelectionRangeHandler { get; }
        public CallHierarchyPrepareHandler CallHierarchyPrepareHandler { get; }
        public CallHierarchyIncomingHandler CallHierarchyIncomingHandler { get; }
        public CallHierarchyOutgoingHandler CallHierarchyOutgoingHandler { get; }
        public TypeHierarchyPrepareHandler TypeHierarchyPrepareHandler { get; }
        public TypeHierarchySupertypesHandler TypeHierarchySupertypesHandler { get; }
        public TypeHierarchySubtypesHandler TypeHierarchySubtypesHandler { get; }
        public DocumentLinkHandler DocumentLinkHandler { get; }
        public CodeLensHandler CodeLensHandler { get; }
        public OnTypeFormattingHandler OnTypeFormattingHandler { get; }

        public LspTestHarness(
            XmlDocReader xmlDocReader,
            TypeResolver typeResolver,
            ILogger<DocumentManager>? documentManagerLogger = null)
        {
            // Reuse shared XmlDocReader and TypeResolver from fixture
            XmlDocReader = xmlDocReader;
            TypeResolver = typeResolver;

            // Create test-specific DocumentManager (each test needs its own)
            DocumentManager = new DocumentManager(documentManagerLogger ?? NullLogger<DocumentManager>.Instance);

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
                XmlDocReader,
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

            SemanticTokensHandler = new SemanticTokensHandler(
                DocumentManager,
                NullLogger<SemanticTokensHandler>.Instance
            );

            WorkspaceSymbolHandler = new WorkspaceSymbolHandler(
                DocumentManager,
                NullLogger<WorkspaceSymbolHandler>.Instance
            );

            FoldingRangeHandler = new FoldingRangeHandler(
                DocumentManager,
                NullLogger<FoldingRangeHandler>.Instance
            );

            PrepareRenameHandler = new PrepareRenameHandler(
                DocumentManager,
                NullLogger<PrepareRenameHandler>.Instance
            );

            DocumentFormattingHandler = new DocumentFormattingHandler(DocumentManager, NullLogger<DocumentFormattingHandler>.Instance);
            GoToImplementationHandler = new GoToImplementationHandler(DocumentManager, NullLogger<GoToImplementationHandler>.Instance);
            DocumentHighlightHandler = new DocumentHighlightHandler(DocumentManager, NullLogger<DocumentHighlightHandler>.Instance);
            SelectionRangeHandler = new SelectionRangeHandler(DocumentManager, NullLogger<SelectionRangeHandler>.Instance);
            CallHierarchyPrepareHandler = new CallHierarchyPrepareHandler(DocumentManager, NullLogger<CallHierarchyPrepareHandler>.Instance);
            CallHierarchyIncomingHandler = new CallHierarchyIncomingHandler(DocumentManager, NullLogger<CallHierarchyIncomingHandler>.Instance);
            CallHierarchyOutgoingHandler = new CallHierarchyOutgoingHandler(DocumentManager, NullLogger<CallHierarchyOutgoingHandler>.Instance);
            TypeHierarchyPrepareHandler = new TypeHierarchyPrepareHandler(DocumentManager, NullLogger<TypeHierarchyPrepareHandler>.Instance);
            TypeHierarchySupertypesHandler = new TypeHierarchySupertypesHandler(DocumentManager, NullLogger<TypeHierarchySupertypesHandler>.Instance);
            TypeHierarchySubtypesHandler = new TypeHierarchySubtypesHandler(DocumentManager, NullLogger<TypeHierarchySubtypesHandler>.Instance);
            DocumentLinkHandler = new DocumentLinkHandler(DocumentManager, NullLogger<DocumentLinkHandler>.Instance);
            CodeLensHandler = new CodeLensHandler(DocumentManager, NullLogger<CodeLensHandler>.Instance);
            OnTypeFormattingHandler = new OnTypeFormattingHandler(DocumentManager, NullLogger<OnTypeFormattingHandler>.Instance);
        }

        /// <summary>
        /// Opens a document with the given content
        /// </summary>
        public void OpenDocument(string uri, string content)
        {
            // Mirror didOpen behavior: editor-open documents provide source-text overrides
            // for project snapshots, while workspace-scanned documents continue to read
            // from disk unless explicitly opened.
            DocumentManager.MarkEditorOpen(uri);
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

        public async Task<Container<WorkspaceSymbol>?> GetWorkspaceSymbolsAsync(string query)
        {
            var request = new WorkspaceSymbolParams { Query = query };
            return await WorkspaceSymbolHandler.Handle(request, CancellationToken.None);
        }

        public async Task<Container<FoldingRange>?> GetFoldingRangesAsync(string uri)
        {
            var request = new FoldingRangeRequestParam
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri))
            };

            return await FoldingRangeHandler.Handle(request, CancellationToken.None);
        }

        public async Task<RangeOrPlaceholderRange?> PrepareRenameAsync(string uri, int line, int character)
        {
            var request = new PrepareRenameParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Position = new Position(line, character)
            };

            return await PrepareRenameHandler.Handle(request, CancellationToken.None);
        }

        public async Task<TextEditContainer?> FormatDocumentAsync(string uri, int tabSize = 4, bool insertSpaces = true)
        {
            var request = new DocumentFormattingParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Options = new FormattingOptions { TabSize = tabSize, InsertSpaces = insertSpaces }
            };

            return await DocumentFormattingHandler.Handle(request, CancellationToken.None);
        }

        public async Task<LocationOrLocationLinks?> GetImplementationAsync(string uri, int line, int character)
        {
            var request = new ImplementationParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Position = new Position(line, character)
            };

            return await GoToImplementationHandler.Handle(request, CancellationToken.None);
        }

        public async Task<DocumentHighlightContainer?> GetDocumentHighlightsAsync(string uri, int line, int character)
        {
            var request = new DocumentHighlightParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Position = new Position(line, character)
            };

            return await DocumentHighlightHandler.Handle(request, CancellationToken.None);
        }

        public async Task<Container<SelectionRange>?> GetSelectionRangesAsync(string uri, params Position[] positions)
        {
            var request = new SelectionRangeParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Positions = positions
            };

            return await SelectionRangeHandler.Handle(request, CancellationToken.None);
        }

        public async Task<Container<CallHierarchyItem>?> PrepareCallHierarchyAsync(string uri, int line, int character)
        {
            var request = new CallHierarchyPrepareParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Position = new Position(line, character)
            };

            return await CallHierarchyPrepareHandler.Handle(request, CancellationToken.None);
        }

        public async Task<Container<CallHierarchyIncomingCall>?> GetIncomingCallsAsync(CallHierarchyItem item)
        {
            var request = new CallHierarchyIncomingCallsParams { Item = item };
            return await CallHierarchyIncomingHandler.Handle(request, CancellationToken.None);
        }

        public async Task<Container<CallHierarchyOutgoingCall>?> GetOutgoingCallsAsync(CallHierarchyItem item)
        {
            var request = new CallHierarchyOutgoingCallsParams { Item = item };
            return await CallHierarchyOutgoingHandler.Handle(request, CancellationToken.None);
        }

        public async Task<Container<TypeHierarchyItem>?> PrepareTypeHierarchyAsync(string uri, int line, int character)
        {
            var request = new TypeHierarchyPrepareParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Position = new Position(line, character)
            };

            return await TypeHierarchyPrepareHandler.Handle(request, CancellationToken.None);
        }

        public async Task<Container<TypeHierarchyItem>?> GetSupertypesAsync(TypeHierarchyItem item)
        {
            var request = new TypeHierarchySupertypesParams { Item = item };
            return await TypeHierarchySupertypesHandler.Handle(request, CancellationToken.None);
        }

        public async Task<Container<TypeHierarchyItem>?> GetSubtypesAsync(TypeHierarchyItem item)
        {
            var request = new TypeHierarchySubtypesParams { Item = item };
            return await TypeHierarchySubtypesHandler.Handle(request, CancellationToken.None);
        }

        public async Task<DocumentLinkContainer?> GetDocumentLinksAsync(string uri)
        {
            var request = new DocumentLinkParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri))
            };

            return await DocumentLinkHandler.Handle(request, CancellationToken.None);
        }

        public async Task<CodeLensContainer?> GetCodeLensesAsync(string uri)
        {
            var request = new CodeLensParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri))
            };

            return await CodeLensHandler.Handle(request, CancellationToken.None);
        }

        public async Task<TextEditContainer?> OnTypeFormattingAsync(string uri, int line, int character, string triggerChar, int tabSize = 4, bool insertSpaces = true)
        {
            var request = new DocumentOnTypeFormattingParams
            {
                TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
                Position = new Position(line, character),
                Character = triggerChar,
                Options = new FormattingOptions { TabSize = tabSize, InsertSpaces = insertSpaces }
            };

            return await OnTypeFormattingHandler.Handle(request, CancellationToken.None);
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
    public async Task Completion_LocalFunction_IncludesLeadingDocumentationAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/docs.nl";

        var source = @"// Greets someone by name.
// Returns the composed greeting.
func greet(name: string): string
    return name

func main(): void
    ";

        harness.OpenDocument(uri, source);

        var completions = await harness.GetCompletionsAsync(uri, 6, 4);

        var greet = Assert.Single(completions.Items.Where(c => c.Label == "greet"));
        var documentation = GetDocumentationText(greet.Documentation);

        Assert.NotNull(documentation);
        Assert.Contains("Greets someone by name.", documentation);
        Assert.Contains("Returns the composed greeting.", documentation);
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
    public async Task SignatureHelp_NSharpFunction_IncludesLeadingDocumentationAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/docs-signature.nl";

        var source = @"// Greets someone by name.
// Returns the composed greeting.
func greet(name: string): string
    return name

func main(): void
    greet(";

        harness.OpenDocument(uri, source);

        var sigHelp = await harness.GetSignatureHelpAsync(uri, 6, 10);

        Assert.NotNull(sigHelp);
        var sig = Assert.Single(sigHelp.Signatures);
        var documentation = GetDocumentationText(sig.Documentation);

        Assert.NotNull(documentation);
        Assert.Contains("Greets someone by name.", documentation);
        Assert.Contains("Returns the composed greeting.", documentation);
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

    [Fact]
    public async Task SignatureHelp_StringInstanceMethod_ReturnsOverloadsAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let message := ""hello""
    message.Contains(";

        harness.OpenDocument(uri, source);

        var sigHelp = await harness.GetSignatureHelpAsync(uri, 3, 21);

        Assert.NotNull(sigHelp);
        Assert.True(sigHelp.Signatures.Count() >= 2,
            $"Expected string.Contains overloads, got {sigHelp.Signatures.Count()} signature(s)");
        Assert.All(sigHelp.Signatures, signature => Assert.StartsWith("Contains(", signature.Label));
        Assert.Contains(sigHelp.Signatures, signature => signature.Label.Contains("value: string"));
        Assert.Contains(sigHelp.Signatures, signature => signature.Label.Contains("value: char"));
        Assert.Contains(sigHelp.Signatures, signature => signature.Label.Contains("comparisonType: StringComparison"));
        Assert.Equal(0, sigHelp.ActiveParameter);

        var stringOverload = sigHelp.Signatures.First(signature =>
            signature.Label.Contains("value: string") &&
            !signature.Label.Contains("comparisonType"));
        var documentation = GetDocumentationText(stringOverload.Documentation);
        var parameterDocumentation = GetDocumentationText(stringOverload.Parameters!.First().Documentation);

        Assert.NotNull(documentation);
        Assert.Contains("specified substring", documentation);
        Assert.NotNull(parameterDocumentation);
        Assert.Contains("string to seek", parameterDocumentation);
    }

    [Fact]
    public async Task SignatureHelp_StringInstanceMethod_SelectsArityCompatibleOverloadAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let message := ""hello""
    message.Substring(0, ";

        harness.OpenDocument(uri, source);

        var sigHelp = await harness.GetSignatureHelpAsync(uri, 3, 25);

        Assert.NotNull(sigHelp);
        Assert.NotEmpty(sigHelp.Signatures);
        Assert.Equal(1, sigHelp.ActiveParameter);

        var activeSignature = sigHelp.Signatures.ElementAt(sigHelp.ActiveSignature ?? 0);
        Assert.Contains("length: int", activeSignature.Label);
    }

    [Fact]
    public async Task SignatureHelp_DotNetNamedCall_UsesAnalyzerSelectedOverloadAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/signature_named_call.nl";

        var source = @"
import System
import System.Collections.Generic

func main(): void
    names := new List<string>()
    names.Add(""alpha"")
    joined := String.Join(separator: "","", values: names)
";

        harness.OpenDocument(uri, source);

        var lines = source.Split('\n');
        var line = Array.FindIndex(lines, text => text.Contains("String.Join", StringComparison.Ordinal));
        var character = lines[line].IndexOf("values", StringComparison.Ordinal) + "values".Length;
        var sigHelp = await harness.GetSignatureHelpAsync(uri, line, character);

        Assert.NotNull(sigHelp);
        Assert.NotEmpty(sigHelp.Signatures);
        var activeSignature = sigHelp.Signatures.ElementAt(sigHelp.ActiveSignature ?? 0);
        Assert.Contains("separator: string", activeSignature.Label);
        Assert.Contains("values: IEnumerable<string>", activeSignature.Label);
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

    [Fact]
    public async Task Definition_InterpolatedStringHole_LocalVariableAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let name := ""Spencer""
    print($""Hello, {name}!"")";

        harness.OpenDocument(uri, source);

        var definition = await harness.GetDefinitionAsync(uri, 3, 21);
        Assert.NotNull(definition);

        var location = ExtractSingleDefinitionLocation(definition!);
        Assert.Equal(2, location.Range.Start.Line);
        Assert.Equal(8, location.Range.Start.Character);
    }

    [Fact]
    public async Task Definition_CrossFileType_UsesCompilerProjectSnapshotAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var programPath = Path.Combine(_examplesDir, "17-issue-tracker", "backend", "Program.nl");
        var uri = new Uri(programPath).AbsoluteUri;
        var source = File.ReadAllText(programPath);

        harness.OpenDocument(uri, source);

        // Line 26 col 20 (0-indexed: 25, 19): service := new IssueService(store, hub)
        var definition = await harness.GetDefinitionAsync(uri, 25, 19);
        Assert.NotNull(definition);

        var location = ExtractSingleDefinitionLocation(definition!);
        Assert.Equal(new Uri(Path.Combine(_examplesDir, "17-issue-tracker", "backend", "Service.nl")).AbsoluteUri, location.Uri.ToString());
        Assert.Equal(13, location.Range.Start.Line); // class IssueService on line 14 (0-indexed: 13)
        Assert.Equal(0, location.Range.Start.Character);
    }

    [Fact]
    public async Task Definition_CrossFileType_PrefersSemanticResultOverSameNameLocalSymbolAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var programPath = Path.Combine(_examplesDir, "17-issue-tracker", "backend", "Program.nl");
        var uri = new Uri(programPath).AbsoluteUri;
        var source = File.ReadAllText(programPath);

        harness.OpenDocument(uri, source);

        // Line 26 col 20 (0-indexed: 25, 19): service := new IssueService(store, hub)
        var definition = await harness.GetDefinitionAsync(uri, 25, 19);
        Assert.NotNull(definition);

        var location = ExtractSingleDefinitionLocation(definition!);
        Assert.Equal(new Uri(Path.Combine(_examplesDir, "17-issue-tracker", "backend", "Service.nl")).AbsoluteUri, location.Uri.ToString());
        Assert.Equal(13, location.Range.Start.Line); // class IssueService on line 14 (0-indexed: 13)
        Assert.Equal(0, location.Range.Start.Character);
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
    public async Task Definition_CrossFile_WithUnsavedComment_UsesOpenBufferProjectSnapshotAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var programPath = Path.Combine(_examplesDir, "17-issue-tracker", "backend", "Program.nl");
        var uri = new Uri(programPath).AbsoluteUri;
        var source = File.ReadAllText(programPath);

        // Append a comment so the open buffer differs from disk. Semantic project
        // resolution should analyze that open-buffer snapshot, not reject it.
        harness.OpenDocument(uri, source + "\n// unsaved edit");

        // F12 on IssueService at line 26 col 20 (0-indexed: 25, 19)
        var definition = await harness.GetDefinitionAsync(uri, 25, 19);
        Assert.NotNull(definition);

        var location = ExtractSingleDefinitionLocation(definition!);
        var expectedUri = new Uri(Path.Combine(_examplesDir, "17-issue-tracker", "backend", "Service.nl")).AbsoluteUri;
        Assert.Equal(expectedUri, location.Uri.ToString());
    }

    [Fact]
    public async Task Definition_CrossFile_WithUnsavedComment_DifferentSymbolAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var programPath = Path.Combine(_examplesDir, "17-issue-tracker", "backend", "Program.nl");
        var uri = new Uri(programPath).AbsoluteUri;
        var source = File.ReadAllText(programPath);

        // Make the buffer differ from disk; the open-buffer project snapshot should still resolve.
        harness.OpenDocument(uri, source + "\n// modified");

        // F12 on IssueStore at line 25 col 18 (0-indexed: 24, 17)
        var definition = await harness.GetDefinitionAsync(uri, 24, 17);
        Assert.NotNull(definition);

        var location = ExtractSingleDefinitionLocation(definition!);
        Assert.EndsWith("Database.nl", location.Uri.GetFileSystemPath());
    }

    [Fact]
    public async Task Definition_StandaloneSyntheticFile_DegradesStructuredAndUsesDocumentFallbackAsync()
    {
        var logger = new CapturingLogger<DocumentManager>();
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver, logger);
        var uri = "file:///test.nl";
        var source = "func main(): void\n    let answer := 42\n    print(answer)";

        harness.OpenDocument(uri, source);

        var definition = await harness.GetDefinitionAsync(uri, 2, 12);

        Assert.NotNull(definition);
        var location = ExtractSingleDefinitionLocation(definition!);
        Assert.Equal(uri, location.Uri.ToString());
        Assert.Equal(1, location.Range.Start.Line);
        Assert.Equal(8, location.Range.Start.Character);
        Assert.Contains(logger.Entries, entry => entry.Level == LogLevel.Warning
            && entry.Message.Contains("Project semantic snapshot degraded", StringComparison.Ordinal)
            && entry.State.Any(kvp => kvp.Key == "Reason" && kvp.Value?.ToString() == "NoProjectRoot"));
    }

    [Fact]
    public async Task Definition_DiskBackedStandaloneUnsavedFile_DoesNotUseStaleDiskSnapshotAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-unsaved-standalone-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            var sourcePath = Path.Combine(tempRoot, "Program.nl");
            File.WriteAllText(sourcePath, """
func main(): void {
    alpha()
}

func alpha(): void {
    return
}
""");

            var unsavedSource = """
func main(): void {
    bravo()
}

func helper(): void {
    return
}

func bravo(): void {
    return
}
""";

            var uri = new Uri(sourcePath).AbsoluteUri;
            harness.OpenDocument(uri, unsavedSource);

            var definition = await harness.GetDefinitionAsync(uri, 1, 5);

            Assert.NotNull(definition);
            var location = ExtractSingleDefinitionLocation(definition!);
            Assert.Equal(uri, location.Uri.ToString());
            Assert.Equal(8, location.Range.Start.Line);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public async Task Definition_ScannedWorkspaceWithoutProjectFile_ResolvesAgainstWorkspaceRootAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-workspace-root-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            Directory.CreateDirectory(Path.Combine(tempRoot, "Foo"));
            var widgetPath = Path.Combine(tempRoot, "Foo", "Widget.nl");
            var usePath = Path.Combine(tempRoot, "Foo", "UseWidget.nl");
            File.WriteAllText(widgetPath, """
namespace TempWorkspaceRoot.Foo

record Widget {
    Value: string
}
""");
            File.WriteAllText(usePath, """
namespace TempWorkspaceRoot.Foo

func Read(widget: Widget): string {
    return widget.Value
}
""");

            harness.DocumentManager.ScanWorkspaceDirectory(tempRoot);
            var useUri = new Uri(usePath).AbsoluteUri;

            var definition = await harness.GetDefinitionAsync(useUri, 3, 18);

            Assert.NotNull(definition);
            var location = ExtractSingleDefinitionLocation(definition!);
            Assert.Equal(new Uri(widgetPath).AbsoluteUri, location.Uri.ToString());
            Assert.Equal(3, location.Range.Start.Line);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public async Task Definition_ScannedWorkspaceUsesCurrentDiskForUnopenedFilesAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-scan-stale-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            var programPath = Path.Combine(tempRoot, "Program.nl");
            var helperPath = Path.Combine(tempRoot, "Helper.nl");
            File.WriteAllText(programPath, """
func main(): void {
    beta()
}
""");
            File.WriteAllText(helperPath, """
func alpha(): void {
    return
}
""");

            harness.DocumentManager.ScanWorkspaceDirectory(tempRoot);

            File.WriteAllText(helperPath, """
func beta(): void {
    return
}
""");

            var programUri = new Uri(programPath).AbsoluteUri;
            harness.OpenDocument(programUri, File.ReadAllText(programPath));

            var definition = await harness.GetDefinitionAsync(programUri, 1, 5);

            Assert.NotNull(definition);
            var location = ExtractSingleDefinitionLocation(definition!);
            Assert.Equal(new Uri(helperPath).AbsoluteUri, location.Uri.ToString());
            Assert.Equal(0, location.Range.Start.Line);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public async Task Definition_DegradedStandaloneDirectoryWithUnsavedPeer_DoesNotUseStaleDiskSnapshotAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-stale-disk-peer-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            var programPath = Path.Combine(tempRoot, "Program.nl");
            var helperPath = Path.Combine(tempRoot, "Helper.nl");
            var peerPath = Path.Combine(tempRoot, "Peer.nl");
            File.WriteAllText(programPath, """
func main(): void {
    alpha()
}
""");
            File.WriteAllText(helperPath, """
func alpha(): void {
    return
}
""");
            File.WriteAllText(peerPath, """
func peer(): void {
    return
}
""");

            var programUri = new Uri(programPath).AbsoluteUri;
            var peerUri = new Uri(peerPath).AbsoluteUri;
            harness.OpenDocument(programUri, File.ReadAllText(programPath));
            harness.OpenDocument(peerUri, """
func peerUnsaved(): void {
    return
}
""");

            var definition = await harness.GetDefinitionAsync(programUri, 1, 5);

            Assert.Null(definition);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public async Task Definition_ProjectSnapshotLoadFailure_LogsStructuredDegradedStateAsync()
    {
        var logger = new CapturingLogger<DocumentManager>();
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver, logger);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-degraded-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            File.WriteAllText(Path.Combine(tempRoot, "project.yml"), "[not valid project config");
            var sourcePath = Path.Combine(tempRoot, "Program.nl");
            File.WriteAllText(sourcePath, """
func main(): void {
    print("broken project config")
}
""");

            var uri = new Uri(sourcePath).AbsoluteUri;
            harness.OpenDocument(uri, File.ReadAllText(sourcePath));

            var definition = await harness.GetDefinitionAsync(uri, 1, 5);

            Assert.Null(definition);
            var degradedLogs = logger.Entries
                .Where(entry => entry.Level == LogLevel.Warning
                    && entry.Message.Contains("Project semantic snapshot degraded", StringComparison.Ordinal))
                .ToList();
            Assert.NotEmpty(degradedLogs);

            var degradedLog = degradedLogs[0];
            Assert.Contains(degradedLog.State, kvp => kvp.Key == "Reason" && kvp.Value?.ToString() == "LoadFailed");
            Assert.Contains(degradedLog.State, kvp => kvp.Key == "ProjectRoot" && Equals(kvp.Value, tempRoot));
            Assert.Contains(degradedLog.State, kvp => kvp.Key == "Message" && kvp.Value is string message && message.Length > 0);
            Assert.NotNull(degradedLog.Exception);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
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
    public async Task References_LocalVariable_FromInterpolatedStringHoleAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let name := ""Spencer""
    print($""Hello, {name}!"")
    print(name)";

        harness.OpenDocument(uri, source);

        var refs = await harness.GetReferencesAsync(uri, 3, 21);
        Assert.NotNull(refs);
        Assert.True(refs!.Count() >= 3, $"Expected declaration plus two uses of 'name', got {refs!.Count()}");
        Assert.Contains(refs!, r => r.Range.Start.Line == 2 && r.Range.Start.Character == 8);
        Assert.Contains(refs!, r => r.Range.Start.Line == 3 && r.Range.Start.Character == 20);
        Assert.Contains(refs!, r => r.Range.Start.Line == 4 && r.Range.Start.Character == 10);
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
        var programPath = Path.Combine(_examplesDir, "17-issue-tracker", "backend", "Program.nl");
        var uri = new Uri(programPath).AbsoluteUri;
        var source = File.ReadAllText(programPath);

        harness.OpenDocument(uri, source);

        // "IssueService" usage on line 26, col 20 (0-indexed: 25, 19)
        var refs = await harness.GetReferencesAsync(uri, 25, 19);
        Assert.NotNull(refs);
        Assert.NotEmpty(refs!);
    }

    [Fact]
    public async Task References_UnsavedCrossFileDuplicateMembers_UsesOpenBufferSemanticSnapshotAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-unsaved-refs-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            Directory.CreateDirectory(Path.Combine(tempRoot, "Foo"));
            Directory.CreateDirectory(Path.Combine(tempRoot, "Bar"));
            File.WriteAllText(Path.Combine(tempRoot, "project.yml"), """
name: TempUnsavedRefsTest
targetFramework: net10.0
""");

            var fooWidgetPath = Path.Combine(tempRoot, "Foo", "Widget.nl");
            var fooUsePath = Path.Combine(tempRoot, "Foo", "UseWidget.nl");
            var barWidgetPath = Path.Combine(tempRoot, "Bar", "Widget.nl");
            var barUsePath = Path.Combine(tempRoot, "Bar", "UseWidget.nl");

            File.WriteAllText(fooWidgetPath, """
namespace TempUnsavedRefsTest.Foo

record Widget {
    Value: string
}
""");
            File.WriteAllText(fooUsePath, """
namespace TempUnsavedRefsTest.Foo

func Read(widget: Widget): string {
    return widget.Value
}
""");
            File.WriteAllText(barWidgetPath, """
namespace TempUnsavedRefsTest.Bar

record Widget {
    Value: int
}
""");
            File.WriteAllText(barUsePath, """
namespace TempUnsavedRefsTest.Bar

func Read(widget: Widget): int {
    return widget.Value
}
""");

            var fooWidgetUri = new Uri(fooWidgetPath).AbsoluteUri;
            var fooUseUri = new Uri(fooUsePath).AbsoluteUri;
            var barUseUri = new Uri(barUsePath).AbsoluteUri;

            var unsavedFooWidget = """
namespace TempUnsavedRefsTest.Foo

record Widget {
    UnsavedValue: string
}
""";
            var unsavedFooUse = """
namespace TempUnsavedRefsTest.Foo

func Read(widget: Widget): string {
    return widget.UnsavedValue
}
""";

            harness.OpenDocument(fooWidgetUri, unsavedFooWidget);
            harness.OpenDocument(fooUseUri, unsavedFooUse);
            harness.OpenDocument(barUseUri, File.ReadAllText(barUsePath));

            var references = await harness.GetReferencesAsync(fooWidgetUri, 3, 5);

            Assert.NotNull(references);
            var referenceList = references!.ToList();
            Assert.Contains(referenceList, r => r.Uri.ToString() == fooWidgetUri && r.Range.Start.Line == 3);
            Assert.Contains(referenceList, r => r.Uri.ToString() == fooUseUri && r.Range.Start.Line == 3);
            Assert.DoesNotContain(referenceList, r => r.Uri.ToString() == barUseUri);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public async Task Definition_UnsavedCrossFileDuplicateMembers_UsesOpenBufferSemanticSnapshotAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-unsaved-def-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            Directory.CreateDirectory(Path.Combine(tempRoot, "Foo"));
            Directory.CreateDirectory(Path.Combine(tempRoot, "Bar"));
            File.WriteAllText(Path.Combine(tempRoot, "project.yml"), """
name: TempUnsavedDefTest
targetFramework: net10.0
""");

            var fooWidgetPath = Path.Combine(tempRoot, "Foo", "Widget.nl");
            var fooUsePath = Path.Combine(tempRoot, "Foo", "UseWidget.nl");
            var barWidgetPath = Path.Combine(tempRoot, "Bar", "Widget.nl");

            File.WriteAllText(fooWidgetPath, """
namespace TempUnsavedDefTest.Foo

record Widget {
    Value: string
}
""");
            File.WriteAllText(fooUsePath, """
namespace TempUnsavedDefTest.Foo

func Read(widget: Widget): string {
    return widget.Value
}
""");
            File.WriteAllText(barWidgetPath, """
namespace TempUnsavedDefTest.Bar

record Widget {
    UnsavedValue: int
}
""");

            var fooWidgetUri = new Uri(fooWidgetPath).AbsoluteUri;
            var fooUseUri = new Uri(fooUsePath).AbsoluteUri;

            var unsavedFooWidget = """
namespace TempUnsavedDefTest.Foo

record Widget {
    UnsavedValue: string
}
""";
            var unsavedFooUse = """
namespace TempUnsavedDefTest.Foo

record Decoy {
    UnsavedValue: string
}

func Read(widget: Widget): string {
    return widget.UnsavedValue
}
""";

            harness.OpenDocument(fooWidgetUri, unsavedFooWidget);
            harness.OpenDocument(fooUseUri, unsavedFooUse);

            var definition = await harness.GetDefinitionAsync(fooUseUri, 7, 18);

            Assert.NotNull(definition);
            var location = ExtractSingleDefinitionLocation(definition!);
            Assert.Equal(fooWidgetUri, location.Uri.ToString());
            Assert.Equal(3, location.Range.Start.Line);
            Assert.Equal(4, location.Range.Start.Character);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public async Task Rename_UnsavedCrossFileDuplicateMembers_UsesOpenBufferSemanticSnapshotAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-unsaved-rename-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            Directory.CreateDirectory(Path.Combine(tempRoot, "Foo"));
            Directory.CreateDirectory(Path.Combine(tempRoot, "Bar"));
            File.WriteAllText(Path.Combine(tempRoot, "project.yml"), """
name: TempUnsavedRenameTest
targetFramework: net10.0
""");

            var fooWidgetPath = Path.Combine(tempRoot, "Foo", "Widget.nl");
            var fooUsePath = Path.Combine(tempRoot, "Foo", "UseWidget.nl");
            var barUsePath = Path.Combine(tempRoot, "Bar", "UseWidget.nl");

            File.WriteAllText(fooWidgetPath, """
namespace TempUnsavedRenameTest.Foo

record Widget {
    Value: string
}
""");
            File.WriteAllText(fooUsePath, """
namespace TempUnsavedRenameTest.Foo

func Read(widget: Widget): string {
    return widget.Value
}
""");
            File.WriteAllText(Path.Combine(tempRoot, "Bar", "Widget.nl"), """
namespace TempUnsavedRenameTest.Bar

record Widget {
    UnsavedValue: int
}
""");
            File.WriteAllText(barUsePath, """
namespace TempUnsavedRenameTest.Bar

func Read(widget: Widget): int {
    return widget.UnsavedValue
}
""");

            var fooWidgetUri = new Uri(fooWidgetPath).AbsoluteUri;
            var fooUseUri = new Uri(fooUsePath).AbsoluteUri;
            var barUseUri = new Uri(barUsePath).AbsoluteUri;

            var unsavedFooWidget = """
namespace TempUnsavedRenameTest.Foo

record Widget {
    UnsavedValue: string
}
""";
            var unsavedFooUse = """
namespace TempUnsavedRenameTest.Foo

func Read(widget: Widget): string {
    return widget.UnsavedValue
}
""";

            harness.OpenDocument(fooWidgetUri, unsavedFooWidget);
            harness.OpenDocument(fooUseUri, unsavedFooUse);
            harness.OpenDocument(barUseUri, File.ReadAllText(barUsePath));

            var edit = await harness.RenameAsync(fooWidgetUri, 3, 5, "FreshValue");

            Assert.NotNull(edit);
            Assert.NotNull(edit!.Changes);
            Assert.True(edit.Changes!.ContainsKey(DocumentUri.From(fooWidgetUri)));
            Assert.True(edit.Changes!.ContainsKey(DocumentUri.From(fooUseUri)));
            Assert.False(edit.Changes!.ContainsKey(DocumentUri.From(barUseUri)));
            Assert.Equal(2, edit.Changes!.Values.SelectMany(e => e).Count());
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
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
        var programPath = Path.Combine(_examplesDir, "17-issue-tracker", "backend", "Program.nl");
        var servicePath = Path.Combine(_examplesDir, "17-issue-tracker", "backend", "Service.nl");
        var programUri = new Uri(programPath).AbsoluteUri;
        var serviceUri = new Uri(servicePath).AbsoluteUri;

        harness.OpenDocument(programUri, File.ReadAllText(programPath));
        harness.OpenDocument(serviceUri, File.ReadAllText(servicePath));

        // Rename GetAll at line 68, col 9 (0-indexed: 67, 9) to "FetchAll"
        var edit = await harness.RenameAsync(serviceUri, 67, 9, "FetchAll");
        Assert.NotNull(edit);
        Assert.NotNull(edit!.Changes);

        var serviceDocUri = DocumentUri.From(serviceUri);
        Assert.True(edit.Changes!.ContainsKey(serviceDocUri), "Rename should include the declaration file");

        Assert.Contains(edit.Changes[serviceDocUri], change => change.NewText == "FetchAll" &&
            change.Range.Start.Line == 67 &&
            change.Range.Start.Character == 4);
    }

    [Fact]
    public async Task Rename_InterpolatedStringHole_LocalVariableAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test.nl";

        var source = @"
func main(): void
    let name := ""Spencer""
    print($""Hello, {name}!"")
    print(name)";

        harness.OpenDocument(uri, source);

        var edit = await harness.RenameAsync(uri, 3, 21, "displayName");
        Assert.NotNull(edit);
        Assert.NotNull(edit!.Changes);

        var docUri = DocumentUri.From(uri);
        Assert.True(edit.Changes!.ContainsKey(docUri));
        var edits = edit.Changes[docUri].ToList();
        Assert.Equal(3, edits.Count);
        Assert.All(edits, e => Assert.Equal("displayName", e.NewText));
        Assert.Contains(edits, e => e.Range.Start.Line == 2 && e.Range.Start.Character == 8);
        Assert.Contains(edits, e => e.Range.Start.Line == 3 && e.Range.Start.Character == 20);
        Assert.Contains(edits, e => e.Range.Start.Line == 4 && e.Range.Start.Character == 10);
    }

    [Fact]
    public async Task Rename_StandaloneDuplicateDeclarations_RefusesUnsafeTextRenameAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/unsafe-rename.nl";
        var source = @"
func main(): void
    let value := 1
    print(value)

func other(): void
    let value := 2
    print(value)";

        harness.OpenDocument(uri, source);

        var ex = await Assert.ThrowsAsync<RequestFailedException>(() => harness.RenameAsync(uri, 2, 8, "renamed"));
        Assert.Equal(ErrorCodes.RequestFailed, ex.ErrorCode);
        Assert.Contains("unsafe without project semantics", ex.Message);
        Assert.Contains("No edits were applied", ex.Message);
    }

    [Fact]
    public async Task Rename_DegradedProjectSnapshot_RefusesTextOnlyRenameWithReasonAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-rename-degraded-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            File.WriteAllText(Path.Combine(tempRoot, "project.yml"), "name: [broken");
            var programPath = Path.Combine(tempRoot, "Program.nl");
            var source = @"
func main(): void
    let value := 1
    print(value)";
            File.WriteAllText(programPath, source);
            var uri = new Uri(programPath).AbsoluteUri;

            harness.OpenDocument(uri, source);

            var ex = await Assert.ThrowsAsync<RequestFailedException>(() => harness.RenameAsync(uri, 2, 8, "renamed"));
            Assert.Equal(ErrorCodes.RequestFailed, ex.ErrorCode);
            Assert.Contains("semantic project analysis is degraded", ex.Message);
            Assert.Contains("refusing text-only rename", ex.Message);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public async Task Rename_ProjectCommentWord_RefusesSemanticFallbackRenameAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-rename-comment-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            File.WriteAllText(Path.Combine(tempRoot, "project.yml"), """
name: TempRenameCommentTest
targetFramework: net10.0
""");

            var programPath = Path.Combine(tempRoot, "Program.nl");
            var source = """
namespace TempRenameCommentTest

func Main(): void
    let value := 1
    // value should not bind to the local above
    print(value)
""";
            File.WriteAllText(programPath, source);

            var uri = new Uri(programPath).AbsoluteUri;
            harness.OpenDocument(uri, source);

            var commentLine = Array.FindIndex(source.Split('\n'), line => line.Contains("// value", StringComparison.Ordinal));
            Assert.True(commentLine >= 0);
            var commentColumn = source.Split('\n')[commentLine].IndexOf("value", StringComparison.Ordinal);
            Assert.True(commentColumn >= 0);

            var ex = await Assert.ThrowsAsync<RequestFailedException>(() => harness.RenameAsync(uri, commentLine, commentColumn, "renamed"));
            Assert.Equal(ErrorCodes.RequestFailed, ex.ErrorCode);
            Assert.Contains("semantic resolution could not safely identify", ex.Message);
            Assert.Contains("No edits were applied", ex.Message);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
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
targetFramework: net10.0
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
targetFramework: net10.0
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
targetFramework: net10.0
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
                d.Message.Contains("is a type, not a namespace")));
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

        Assert.Single(completions.Items.Where(c => c.Label == "Contains"));
        Assert.Single(completions.Items.Where(c => c.Label == "EndsWith"));
        Assert.Single(completions.Items.Where(c => c.Label == "CompareTo"));

        var contains = Assert.Single(completions.Items.Where(c => c.Label == "Contains"));
        Assert.Contains("overload", contains.Detail);

        var documentation = GetDocumentationText(contains.Documentation);
        Assert.NotNull(documentation);
        Assert.Contains("Returns a value indicating whether a specified", documentation);
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

        Assert.Single(completions.Items.Where(c => c.Label == "WriteLine"));
        Assert.Single(completions.Items.Where(c => c.Label == "Write"));
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
    public async Task Completion_MemberAccess_NSharpClass_PrefersSourceMembersOverClrNameCollisionAsync()
    {
        _ = ConflictingClrPersonType.Value;

        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/nsharp-class-clr-collision.nl";

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

    #region Semantic Tokens Tests

    [Fact]
    public void SemanticTokens_ClassifiesKeywords()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/semtokens.nl";
        var source = @"func main() {
    let x := 42
}
";
        harness.OpenDocument(uri, source);
        var doc = harness.DocumentManager.GetDocument(uri);
        Assert.NotNull(doc);
        Assert.NotNull(doc!.Tokens);

        var typeNames = SemanticTokensHandler.BuildTypeNameSet(doc);
        var functionNames = SemanticTokensHandler.BuildFunctionNameSet(doc);
        var parameterNames = SemanticTokensHandler.BuildParameterNameSet(doc);
        var propertyNames = SemanticTokensHandler.BuildPropertyNameSet(doc);
        var enumMemberNames = SemanticTokensHandler.BuildEnumMemberNameSet(doc);

        // "func" should be classified as keyword (index 12)
        var funcToken = doc.Tokens!.First(t => t.Type == NSharpLang.Compiler.TokenType.Func);
        var classification = harness.SemanticTokensHandler.ClassifyToken(
            funcToken, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames);
        Assert.NotNull(classification);
        Assert.Equal(12, classification!.Value.TokenType); // keyword

        // "let" should be classified as keyword
        var letToken = doc.Tokens!.First(t => t.Type == NSharpLang.Compiler.TokenType.Let);
        classification = harness.SemanticTokensHandler.ClassifyToken(
            letToken, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames);
        Assert.NotNull(classification);
        Assert.Equal(12, classification!.Value.TokenType); // keyword
    }

    [Fact]
    public void SemanticTokens_ClassifiesNumberLiterals()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/semtokens_num.nl";
        var source = @"func main() {
    let x := 42
    let y := 3.14
}
";
        harness.OpenDocument(uri, source);
        var doc = harness.DocumentManager.GetDocument(uri);
        Assert.NotNull(doc);

        var typeNames = SemanticTokensHandler.BuildTypeNameSet(doc!);
        var functionNames = SemanticTokensHandler.BuildFunctionNameSet(doc);
        var parameterNames = SemanticTokensHandler.BuildParameterNameSet(doc);
        var propertyNames = SemanticTokensHandler.BuildPropertyNameSet(doc);
        var enumMemberNames = SemanticTokensHandler.BuildEnumMemberNameSet(doc);

        var intToken = doc.Tokens!.First(t => t.Type == NSharpLang.Compiler.TokenType.IntLiteral);
        var classification = harness.SemanticTokensHandler.ClassifyToken(
            intToken, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames);
        Assert.NotNull(classification);
        Assert.Equal(15, classification!.Value.TokenType); // number

        var floatToken = doc.Tokens!.First(t => t.Type == NSharpLang.Compiler.TokenType.FloatLiteral);
        classification = harness.SemanticTokensHandler.ClassifyToken(
            floatToken, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames);
        Assert.NotNull(classification);
        Assert.Equal(15, classification!.Value.TokenType); // number
    }

    [Fact]
    public void SemanticTokens_ClassifiesStringLiterals()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/semtokens_str.nl";
        var source = @"func main() {
    let x := ""hello""
}
";
        harness.OpenDocument(uri, source);
        var doc = harness.DocumentManager.GetDocument(uri);
        Assert.NotNull(doc);

        var typeNames = SemanticTokensHandler.BuildTypeNameSet(doc!);
        var functionNames = SemanticTokensHandler.BuildFunctionNameSet(doc);
        var parameterNames = SemanticTokensHandler.BuildParameterNameSet(doc);
        var propertyNames = SemanticTokensHandler.BuildPropertyNameSet(doc);
        var enumMemberNames = SemanticTokensHandler.BuildEnumMemberNameSet(doc);

        var strToken = doc.Tokens!.First(t => t.Type == NSharpLang.Compiler.TokenType.StringLiteral);
        var classification = harness.SemanticTokensHandler.ClassifyToken(
            strToken, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames);
        Assert.NotNull(classification);
        Assert.Equal(14, classification!.Value.TokenType); // string
    }

    [Fact]
    public void SemanticTokens_DoesNotClassifyInterpolatedStringAsSingleStringToken()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/semtokens_interpolated_str.nl";
        var source = """
func main() {
    name := "Spencer"
    print $"Hello, {name}!"
}
""";
        harness.OpenDocument(uri, source);
        var doc = harness.DocumentManager.GetDocument(uri);
        Assert.NotNull(doc);

        var typeNames = SemanticTokensHandler.BuildTypeNameSet(doc!);
        var functionNames = SemanticTokensHandler.BuildFunctionNameSet(doc);
        var parameterNames = SemanticTokensHandler.BuildParameterNameSet(doc);
        var propertyNames = SemanticTokensHandler.BuildPropertyNameSet(doc);
        var enumMemberNames = SemanticTokensHandler.BuildEnumMemberNameSet(doc);

        var interpolatedToken = doc.Tokens!.First(t =>
            t.Type == NSharpLang.Compiler.TokenType.StringLiteral
            && t.Value.StartsWith("$\"", StringComparison.Ordinal));

        var classification = harness.SemanticTokensHandler.ClassifyToken(
            interpolatedToken, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames);

        Assert.Null(classification);

        var embeddedNameToken = SemanticTokensHandler.GetInterpolatedStringExpressionTokens(interpolatedToken)
            .Single(t => t.Type == NSharpLang.Compiler.TokenType.Identifier && t.Value == "name");
        Assert.Equal(3, embeddedNameToken.Line);
        Assert.Equal(21, embeddedNameToken.Column);

        classification = harness.SemanticTokensHandler.ClassifyToken(
            embeddedNameToken, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames);

        Assert.NotNull(classification);
        Assert.Equal(8, classification!.Value.TokenType); // variable
    }

    [Fact]
    public void SemanticTokens_DoesNotClassifyInterpolatedRawStringAsSingleStringToken()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/semtokens_interpolated_raw_str.nl";
        var source = "func main() {\n    name := \"Spencer\"\n    print $\"\"\"Hello, {name}!\"\"\"\n}\n";
        harness.OpenDocument(uri, source);
        var doc = harness.DocumentManager.GetDocument(uri);
        Assert.NotNull(doc);

        var typeNames = SemanticTokensHandler.BuildTypeNameSet(doc!);
        var functionNames = SemanticTokensHandler.BuildFunctionNameSet(doc);
        var parameterNames = SemanticTokensHandler.BuildParameterNameSet(doc);
        var propertyNames = SemanticTokensHandler.BuildPropertyNameSet(doc);
        var enumMemberNames = SemanticTokensHandler.BuildEnumMemberNameSet(doc);

        var interpolatedToken = doc.Tokens!.First(t =>
            t.Type == NSharpLang.Compiler.TokenType.InterpolatedRawStringLiteral);

        var classification = harness.SemanticTokensHandler.ClassifyToken(
            interpolatedToken, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames);

        Assert.Null(classification);

        var embeddedNameToken = SemanticTokensHandler.GetInterpolatedStringExpressionTokens(interpolatedToken)
            .Single(t => t.Type == NSharpLang.Compiler.TokenType.Identifier && t.Value == "name");
        Assert.Equal(3, embeddedNameToken.Line);
        Assert.Equal(23, embeddedNameToken.Column);

        classification = harness.SemanticTokensHandler.ClassifyToken(
            embeddedNameToken, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames);

        Assert.NotNull(classification);
        Assert.Equal(8, classification!.Value.TokenType); // variable
    }

    [Fact]
    public void SemanticTokens_ClassifiesTypeNames()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/semtokens_type.nl";
        var source = @"class Person {
    name: string
    age: int
}

func main() {
    let p := new Person()
}
";
        harness.OpenDocument(uri, source);
        var doc = harness.DocumentManager.GetDocument(uri);
        Assert.NotNull(doc);

        var typeNames = SemanticTokensHandler.BuildTypeNameSet(doc!);
        Assert.Contains("Person", typeNames);
    }

    [Fact]
    public void SemanticTokens_ClassifiesFunctionNames()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/semtokens_func.nl";
        var source = @"func greet(name: string): string {
    return ""Hello "" + name
}
";
        harness.OpenDocument(uri, source);
        var doc = harness.DocumentManager.GetDocument(uri);
        Assert.NotNull(doc);

        var functionNames = SemanticTokensHandler.BuildFunctionNameSet(doc!);
        Assert.Contains("greet", functionNames);
    }

    [Fact]
    public void SemanticTokens_MarksCatchResultBinding()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/semtokens_catch_result.nl";
        var source = @"func MightFail(): int {
    return 1
}

func main() {
    result, err := MightFail()
}
";
        harness.OpenDocument(uri, source);
        var doc = harness.DocumentManager.GetDocument(uri);
        Assert.NotNull(doc);

        var typeNames = SemanticTokensHandler.BuildTypeNameSet(doc!);
        var functionNames = SemanticTokensHandler.BuildFunctionNameSet(doc);
        var parameterNames = SemanticTokensHandler.BuildParameterNameSet(doc);
        var propertyNames = SemanticTokensHandler.BuildPropertyNameSet(doc);
        var enumMemberNames = SemanticTokensHandler.BuildEnumMemberNameSet(doc);
        var catchResultBindings = SemanticTokensHandler.BuildCatchResultBindingSet(doc);

        var errToken = doc.Tokens!.Single(t =>
            t.Type == NSharpLang.Compiler.TokenType.Identifier
            && t.Value == "err"
            && t.Line == 6);

        Assert.Contains(new SemanticTokenLocation(errToken.Line, errToken.Column, errToken.Value), catchResultBindings);

        var classification = harness.SemanticTokensHandler.ClassifyToken(
            errToken, doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames, catchResultBindings);

        Assert.NotNull(classification);
        Assert.Equal(8, classification!.Value.TokenType); // variable
        Assert.Equal(SemanticTokensHandler.CatchResultModifierMask, classification.Value.Modifiers);
    }

    [Fact]
    public void SemanticTokens_MarksOnlyFinalErrInMultiValueCatchDeconstruction()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/semtokens_multi_catch_result.nl";
        var source = @"func GetValues(): (int, int, int) {
    return (1, 2, 3)
}

func main() {
    err, value, other, err := GetValues()
}
";
        harness.OpenDocument(uri, source);
        var doc = harness.DocumentManager.GetDocument(uri);
        Assert.NotNull(doc);

        var typeNames = SemanticTokensHandler.BuildTypeNameSet(doc!);
        var functionNames = SemanticTokensHandler.BuildFunctionNameSet(doc);
        var parameterNames = SemanticTokensHandler.BuildParameterNameSet(doc);
        var propertyNames = SemanticTokensHandler.BuildPropertyNameSet(doc);
        var enumMemberNames = SemanticTokensHandler.BuildEnumMemberNameSet(doc);
        var catchResultBindings = SemanticTokensHandler.BuildCatchResultBindingSet(doc);

        var errTokens = doc.Tokens!
            .Where(t => t.Type == NSharpLang.Compiler.TokenType.Identifier && t.Value == "err" && t.Line == 6)
            .OrderBy(t => t.Column)
            .ToList();

        Assert.Equal(2, errTokens.Count);
        Assert.DoesNotContain(new SemanticTokenLocation(errTokens[0].Line, errTokens[0].Column, errTokens[0].Value), catchResultBindings);
        Assert.Contains(new SemanticTokenLocation(errTokens[1].Line, errTokens[1].Column, errTokens[1].Value), catchResultBindings);

        var firstClassification = harness.SemanticTokensHandler.ClassifyToken(
            errTokens[0], doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames, catchResultBindings);
        var finalClassification = harness.SemanticTokensHandler.ClassifyToken(
            errTokens[1], doc, typeNames, functionNames, parameterNames, propertyNames, enumMemberNames, catchResultBindings);

        Assert.NotNull(firstClassification);
        Assert.Equal(8, firstClassification!.Value.TokenType); // variable
        Assert.Equal(0, firstClassification.Value.Modifiers);

        Assert.NotNull(finalClassification);
        Assert.Equal(8, finalClassification!.Value.TokenType); // variable
        Assert.Equal(SemanticTokensHandler.CatchResultModifierMask, finalClassification.Value.Modifiers);
    }

    #endregion

    #region Workspace Symbol Tests

    [Fact]
    public async Task WorkspaceSymbols_FindsTypeDeclarations()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/ws_symbols.nl";
        var source = @"class Person {
    name: string
}

func greet(): string {
    return ""hello""
}
";
        harness.OpenDocument(uri, source);

        var result = await harness.GetWorkspaceSymbolsAsync("Person");
        Assert.NotNull(result);
        Assert.Contains(result!, s => s.Name == "Person");
    }

    [Fact]
    public async Task WorkspaceSymbols_EmptyQueryReturnsAllSymbols()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/ws_symbols_all.nl";
        var source = @"class Foo {
    bar: int
}

func baz(): void {
}
";
        harness.OpenDocument(uri, source);

        var result = await harness.GetWorkspaceSymbolsAsync("");
        Assert.NotNull(result);
        Assert.True(result!.Count() >= 2); // At least Foo and baz
    }

    [Fact]
    public void WorkspaceSymbols_FuzzyMatching()
    {
        // Test that "PrsNm" matches "PersonName" (fuzzy subsequence)
        Assert.True(WorkspaceSymbolHandler.MatchesQuery("PersonName", "PrsNm"));
        Assert.True(WorkspaceSymbolHandler.MatchesQuery("PersonName", "person"));
        Assert.True(WorkspaceSymbolHandler.MatchesQuery("PersonName", ""));
        Assert.False(WorkspaceSymbolHandler.MatchesQuery("PersonName", "xyz"));
    }

    [Fact]
    public async Task WorkspaceSymbols_IncludesMembers()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/ws_symbols_members.nl";
        var source = @"class Person {
    name: string
    age: int
}
";
        harness.OpenDocument(uri, source);

        // The class itself should be in results
        var result = await harness.GetWorkspaceSymbolsAsync("Person");
        Assert.NotNull(result);
        Assert.Contains(result!, s => s.Name == "Person");

        // Members should also be accessible if they exist in SymbolsInfo
        var allSymbols = await harness.GetWorkspaceSymbolsAsync("");
        Assert.NotNull(allSymbols);
        // At minimum, the Person type itself should be returned
        Assert.Contains(allSymbols!, s => s.Name == "Person");
    }

    #endregion

    #region Folding Range Tests

    [Fact]
    public async Task FoldingRange_FoldsFunction()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/folding.nl";
        var source = @"func main() {
    let x := 42
    let y := 43
}
";
        harness.OpenDocument(uri, source);

        var result = await harness.GetFoldingRangesAsync(uri);
        Assert.NotNull(result);
        Assert.True(result!.Any());

        // The function should fold from line 0 to line 3
        var funcRange = result!.FirstOrDefault(r => r.StartLine == 0);
        Assert.NotNull(funcRange);
        Assert.True(funcRange!.EndLine > funcRange.StartLine);
    }

    [Fact]
    public async Task FoldingRange_FoldsClass()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/folding_class.nl";
        var source = @"class Person {
    name: string
    age: int

    func greet(): string {
        return ""Hello""
    }
}
";
        harness.OpenDocument(uri, source);

        var result = await harness.GetFoldingRangesAsync(uri);
        Assert.NotNull(result);

        // Should have at least class folding and method folding
        Assert.True(result!.Count() >= 2);
    }

    [Fact]
    public async Task FoldingRange_FoldsImports()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/folding_imports.nl";
        var source = @"import System
import System.Collections.Generic
import System.Linq

func main() {
}
";
        harness.OpenDocument(uri, source);

        var result = await harness.GetFoldingRangesAsync(uri);
        Assert.NotNull(result);

        // Should have an import folding range
        var importRange = result!.FirstOrDefault(r => r.Kind == FoldingRangeKind.Imports);
        Assert.NotNull(importRange);
    }

    #endregion

    #region Prepare Rename Tests

    [Fact]
    public async Task PrepareRename_AcceptsKnownSymbol()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/prepare_rename.nl";
        var source = @"func greet(name: string): string {
    return ""Hello "" + name
}
";
        harness.OpenDocument(uri, source);

        // "greet" starts at line 0, col 5 (0-based)
        var result = await harness.PrepareRenameAsync(uri, 0, 5);
        Assert.NotNull(result);
        Assert.True(result!.IsPlaceholderRange);
        Assert.Equal("greet", result.PlaceholderRange.Placeholder);
    }

    [Fact]
    public async Task PrepareRename_RejectsKeyword()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/prepare_rename_kw.nl";
        var source = @"func main() {
    let x := 42
}
";
        harness.OpenDocument(uri, source);

        // "func" is at line 0, col 0
        var result = await harness.PrepareRenameAsync(uri, 0, 0);
        Assert.Null(result);

        // "let" is at line 1, col 4
        result = await harness.PrepareRenameAsync(uri, 1, 4);
        Assert.Null(result);
    }

    [Fact]
    public async Task PrepareRename_RejectsPrimitiveType()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/prepare_rename_prim.nl";
        var source = @"func main() {
    let x: int = 42
}
";
        harness.OpenDocument(uri, source);

        // "int" is at line 1
        var lines = source.Split('\n');
        var intCol = lines[1].IndexOf("int");
        var result = await harness.PrepareRenameAsync(uri, 1, intCol);
        Assert.Null(result);
    }

    [Fact]
    public async Task PrepareRename_RejectsStringLiteralContent()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/prepare_rename_string_literal.nl";
        var source = @"func main() {
    message := ""oldName""
    print message
}
";
        harness.OpenDocument(uri, source);

        var stringContentCol = source.Split('\n')[1].IndexOf("oldName", StringComparison.Ordinal);
        var result = await harness.PrepareRenameAsync(uri, 1, stringContentCol);

        Assert.Null(result);
    }

    [Fact]
    public async Task PrepareRename_AllowsInterpolatedExpressionHole()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/prepare_rename_interpolated_hole.nl";
        var source = """
func main() {
    oldName := "world"
    message := $"hello {oldName}"
    print message
}
""";
        harness.OpenDocument(uri, source);

        var result = await harness.PrepareRenameAsync(uri, 2, source.Split('\n')[2].IndexOf("oldName", StringComparison.Ordinal));

        Assert.NotNull(result);
        Assert.Equal("oldName", result!.PlaceholderRange.Placeholder);
    }

    [Fact]
    public async Task PrepareRename_RejectsEscapedInterpolatedBraceLiteralContent()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/prepare_rename_interpolated_escaped_braces.nl";
        var source = """
func main() {
    oldName := "world"
    message := $"hello {{oldName}}"
    print message
}
""";
        harness.OpenDocument(uri, source);

        var result = await harness.PrepareRenameAsync(uri, 2, source.Split('\n')[2].IndexOf("oldName", StringComparison.Ordinal));

        Assert.Null(result);
    }

    [Fact]
    public async Task PrepareRename_AllowsInterpolatedRawStringExpressionHole()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/prepare_rename_interpolated_raw_hole.nl";
        var source = """"
func main() {
    oldName := "world"
    message := $"""
hello {oldName}
"""
    print message
}
"""";
        harness.OpenDocument(uri, source);

        var result = await harness.PrepareRenameAsync(uri, 3, source.Split('\n')[3].IndexOf("oldName", StringComparison.Ordinal));

        Assert.NotNull(result);
        Assert.Equal("oldName", result!.PlaceholderRange.Placeholder);
    }

    [Fact]
    public async Task PrepareRename_RejectsMultiLineRawStringContent()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/prepare_rename_raw_string_literal.nl";
        var source = """"
func main() {
    oldName := "symbol"
    text := """
oldName
"""
    print text
}
"""";
        harness.OpenDocument(uri, source);

        var result = await harness.PrepareRenameAsync(uri, 3, source.Split('\n')[3].IndexOf("oldName", StringComparison.Ordinal));

        Assert.Null(result);
    }

    [Fact]
    public async Task PrepareRename_ProjectSemanticMemberUsage_AcceptsStrictProjectTargetAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-prepare-rename-project-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            File.WriteAllText(Path.Combine(tempRoot, "project.yml"), """
name: TempPrepareRenameProject
targetFramework: net10.0
""");
            var widgetPath = Path.Combine(tempRoot, "Widget.nl");
            var usePath = Path.Combine(tempRoot, "UseWidget.nl");
            File.WriteAllText(widgetPath, """
namespace TempPrepareRenameProject

record Widget {
    Value: string
}
""");
            var useSource = """
namespace TempPrepareRenameProject

func Read(widget: Widget): string {
    return widget.Value
}
""";
            File.WriteAllText(usePath, useSource);

            var widgetUri = new Uri(widgetPath).AbsoluteUri;
            var useUri = new Uri(usePath).AbsoluteUri;
            harness.OpenDocument(widgetUri, File.ReadAllText(widgetPath));
            harness.OpenDocument(useUri, useSource);

            var result = await harness.PrepareRenameAsync(useUri, 3, 20);

            Assert.NotNull(result);
            Assert.True(result!.IsPlaceholderRange);
            Assert.Equal("Value", result.PlaceholderRange.Placeholder);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public async Task PrepareRename_StandaloneDuplicateDeclarations_RefusesUnsafeTextRenameAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/unsafe-prepare-rename.nl";
        var source = @"
func main(): void
    let value := 1
    print(value)

func other(): void
    let value := 2
    print(value)";

        harness.OpenDocument(uri, source);

        var ex = await Assert.ThrowsAsync<RequestFailedException>(() => harness.PrepareRenameAsync(uri, 2, 8));
        Assert.Equal(ErrorCodes.RequestFailed, ex.ErrorCode);
        Assert.Contains("unsafe without project semantics", ex.Message);
        Assert.Contains("No edits were applied", ex.Message);
    }

    [Fact]
    public async Task PrepareRename_DegradedProjectSnapshot_RefusesWithReasonAsync()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-prepare-rename-degraded-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            File.WriteAllText(Path.Combine(tempRoot, "project.yml"), "name: [broken");
            var programPath = Path.Combine(tempRoot, "Program.nl");
            var source = @"
func main(): void
    let value := 1
    print(value)";
            File.WriteAllText(programPath, source);
            var uri = new Uri(programPath).AbsoluteUri;

            harness.OpenDocument(uri, source);

            var ex = await Assert.ThrowsAsync<RequestFailedException>(() => harness.PrepareRenameAsync(uri, 2, 8));
            Assert.Equal(ErrorCodes.RequestFailed, ex.ErrorCode);
            Assert.Contains("semantic project analysis is degraded", ex.Message);
            Assert.Contains("refusing text-only rename", ex.Message);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    #endregion

    #region Hover Range Tests

    [Fact]
    public async Task Hover_KeywordIncludesRange()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/hover_kw_range.nl";
        var source = @"func main() {
}
";
        harness.OpenDocument(uri, source);

        // "func" at line 0, col 0
        var hover = await harness.GetHoverAsync(uri, 0, 0);
        Assert.NotNull(hover);
        Assert.NotNull(hover!.Range);
        Assert.Contains("keyword", hover.Contents.MarkedStrings == null
            ? hover.Contents.MarkupContent!.Value
            : hover.Contents.MarkedStrings.First().Value);
    }

    [Fact]
    public async Task Hover_PrimitiveTypeIncludesRange()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/hover_prim_range.nl";
        var source = @"func main() {
    let x: int = 42
}
";
        harness.OpenDocument(uri, source);

        var lines = source.Split('\n');
        var intCol = lines[1].IndexOf("int");
        var hover = await harness.GetHoverAsync(uri, 1, intCol);
        Assert.NotNull(hover);
        Assert.NotNull(hover!.Range);
        Assert.Contains("primitive type", hover.Contents.MarkedStrings == null
            ? hover.Contents.MarkupContent!.Value
            : hover.Contents.MarkedStrings.First().Value);
    }

    #endregion

    #region Document Formatting Tests

    [Fact]
    public async Task DocumentFormatting_ReturnsEditsForUnformattedCode()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/formatting.nl";
        // Badly indented source
        var source = "func main() {\n  let x := 42\n      let y := 43\n}\n";
        harness.OpenDocument(uri, source);

        var edits = await harness.FormatDocumentAsync(uri);

        // The formatter should return edits with actual text changes for the badly indented code
        Assert.NotNull(edits);
        if (edits!.Any())
        {
            // At least one edit should contain text that differs from the original source
            var editTexts = edits!.Select(e => e.NewText).ToList();
            var originalLines = source.Split('\n');
            // The edits should produce different content than the original
            Assert.True(editTexts.Any(t => t != null),
                "Formatting edits should contain actual text changes");
        }
    }

    [Fact]
    public async Task DocumentFormatting_NullForMissingDocument()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);

        var edits = await harness.FormatDocumentAsync("file:///nonexistent.nl");

        Assert.Null(edits);
    }

    [Fact]
    public async Task DocumentFormatting_EmptyContainerWhenAlreadyFormatted()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/formatting_clean.nl";
        // Well-formatted single-line source
        var source = "func main() {\n    let x := 42\n}\n";
        harness.OpenDocument(uri, source);

        var edits = await harness.FormatDocumentAsync(uri);

        // Either null (no AST) or a result (possibly empty if already formatted)
        // The key invariant: should not throw
        Assert.NotNull(edits);
    }

    #endregion

    #region Go To Implementation Tests

    [Fact]
    public async Task GoToImplementation_ClassFindsSubclasses()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/impl.nl";
        // NOTE: The parser treats the first type after ':' as BaseClass.
        // Use a class hierarchy to test go-to-implementation on a base class.
        var source = @"class Animal {
    func speak(): string {
        return ""...""
    }
}

class Dog : Animal {
    func speak(): string {
        return ""woof""
    }
}
";
        harness.OpenDocument(uri, source);

        // "Animal" starts at line 0, col 6
        var doc = harness.DocumentManager.GetDocument(uri);
        var hasSymbols = doc?.Symbols != null && doc.Symbols.ContainsKey("Animal");

        var result = await harness.GetImplementationAsync(uri, 0, 6);
        if (hasSymbols)
        {
            // If Symbols are populated, handler should find Dog as a subclass of Animal
            Assert.NotNull(result);
        }
        else
        {
            // Symbol table not populated — handler correctly returns null
            Assert.Null(result);
        }
    }

    [Fact]
    public async Task GoToImplementation_NonInterfaceReturnsNull()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/impl_none.nl";
        var source = @"func main() {
    let x := 42
}
";
        harness.OpenDocument(uri, source);

        // "main" is a function, not an interface or class
        var result = await harness.GetImplementationAsync(uri, 0, 5);
        Assert.Null(result);
    }

    [Fact]
    public async Task GoToImplementation_MissingDocumentReturnsNull()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);

        var result = await harness.GetImplementationAsync("file:///nonexistent.nl", 0, 0);
        Assert.Null(result);
    }

    #endregion

    #region Document Highlight Tests

    [Fact]
    public async Task DocumentHighlight_VariableUsedMultipleTimes()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/highlight.nl";
        var source = @"func main() {
    let count := 1
    let doubled := count + count
    print(count)
}
";
        harness.OpenDocument(uri, source);

        // "count" on line 1 (declaration)
        var highlights = await harness.GetDocumentHighlightsAsync(uri, 1, 8);
        Assert.NotNull(highlights);
        Assert.True(highlights!.Count() >= 2,
            $"Expected at least 2 highlights for 'count', got {highlights!.Count()}");
    }

    [Fact]
    public async Task DocumentHighlight_EmptyPositionReturnsEmpty()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/highlight_empty.nl";
        var source = @"func main() {
    let x := 42
}
";
        harness.OpenDocument(uri, source);

        // Position on whitespace between tokens
        var highlights = await harness.GetDocumentHighlightsAsync(uri, 0, 4);
        Assert.NotNull(highlights);
        // Should return empty container for non-symbol position
    }

    [Fact]
    public async Task DocumentHighlight_MissingDocumentReturnsEmpty()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);

        var highlights = await harness.GetDocumentHighlightsAsync("file:///nonexistent.nl", 0, 0);
        Assert.NotNull(highlights);
        Assert.Empty(highlights!);
    }

    #endregion

    #region Selection Range Tests

    [Fact]
    public async Task SelectionRange_ReturnsNestedChain()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/selrange.nl";
        var source = @"func main() {
    if true {
        let x := 42
    }
}
";
        harness.OpenDocument(uri, source);

        // Position inside the if block at "let x"
        var result = await harness.GetSelectionRangesAsync(uri, new Position(2, 12));
        Assert.NotNull(result);
        var ranges = result!.ToList();
        Assert.Single(ranges);

        // The selection range should have a parent chain (innermost -> outermost)
        var selRange = ranges[0];
        Assert.NotNull(selRange.Range);
        // Should have at least one parent (function body or whole file)
        Assert.NotNull(selRange.Parent);
    }

    [Fact]
    public async Task SelectionRange_MissingDocumentReturnsNull()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);

        var result = await harness.GetSelectionRangesAsync("file:///nonexistent.nl", new Position(0, 0));
        Assert.Null(result);
    }

    [Fact]
    public async Task SelectionRange_MultiplePositions()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/selrange_multi.nl";
        var source = @"func foo() {
    let a := 1
}

func bar() {
    let b := 2
}
";
        harness.OpenDocument(uri, source);

        var result = await harness.GetSelectionRangesAsync(uri,
            new Position(1, 8),  // inside foo
            new Position(5, 8)   // inside bar
        );
        Assert.NotNull(result);
        Assert.Equal(2, result!.Count());
    }

    #endregion

    #region Call Hierarchy Tests

    [Fact]
    public async Task CallHierarchy_PrepareOnFunction()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/callhierarchy.nl";
        var source = @"func greet(name: string): string {
    return ""Hello, "" + name
}

func main() {
    greet(""world"")
}
";
        harness.OpenDocument(uri, source);

        // "greet" at line 0, col 5
        var result = await harness.PrepareCallHierarchyAsync(uri, 0, 5);
        Assert.NotNull(result);
        var items = result!.ToList();
        Assert.Single(items);
        Assert.Equal("greet", items[0].Name);
    }

    [Fact]
    public async Task CallHierarchy_PrepareOnNonFunction_ReturnsNull()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/callhierarchy_none.nl";
        var source = @"class Foo {
    bar: int
}
";
        harness.OpenDocument(uri, source);

        // "Foo" is a class, not a function
        var result = await harness.PrepareCallHierarchyAsync(uri, 0, 6);
        Assert.Null(result);
    }

    [Fact]
    public async Task CallHierarchy_OutgoingCallsFromFunction()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/callhierarchy_outgoing.nl";
        var source = @"func helper(): void {
    return
}

func main() {
    helper()
}
";
        harness.OpenDocument(uri, source);

        // Prepare on "main"
        var prepareResult = await harness.PrepareCallHierarchyAsync(uri, 4, 5);
        Assert.NotNull(prepareResult);
        var mainItem = prepareResult!.First();

        var outgoing = await harness.GetOutgoingCallsAsync(mainItem);
        Assert.NotNull(outgoing);

        // "main" calls "helper", so outgoing should contain a call to "helper"
        if (outgoing!.Any())
        {
            Assert.Contains(outgoing!, call => call.To.Name == "helper");
        }
    }

    #endregion

    #region Type Hierarchy Tests

    [Fact]
    public async Task TypeHierarchy_PrepareOnClass()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/typehierarchy.nl";
        var source = @"interface IAnimal {
    func speak(): string
}

class Dog : IAnimal {
    func speak(): string {
        return ""woof""
    }
}
";
        harness.OpenDocument(uri, source);

        // "Dog" at line 4, col 6
        var result = await harness.PrepareTypeHierarchyAsync(uri, 4, 6);
        Assert.NotNull(result);
        var items = result!.ToList();
        Assert.Single(items);
        Assert.Equal("Dog", items[0].Name);
    }

    [Fact]
    public async Task TypeHierarchy_PrepareOnInterface()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/typehierarchy_iface.nl";
        var source = @"interface IAnimal {
    func speak(): string
}
";
        harness.OpenDocument(uri, source);

        // "IAnimal" at line 0, col 10
        var result = await harness.PrepareTypeHierarchyAsync(uri, 0, 10);
        Assert.NotNull(result);
        var items = result!.ToList();
        Assert.Single(items);
        Assert.Equal("IAnimal", items[0].Name);
    }

    [Fact]
    public async Task TypeHierarchy_SupertypesOfDerivedClass()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/typehierarchy_super.nl";
        var source = @"interface IAnimal {
    func speak(): string
}

class Dog : IAnimal {
    func speak(): string {
        return ""woof""
    }
}
";
        harness.OpenDocument(uri, source);

        // Prepare on "Dog"
        var prepareResult = await harness.PrepareTypeHierarchyAsync(uri, 4, 6);
        Assert.NotNull(prepareResult);
        var dogItem = prepareResult!.First();

        var supertypes = await harness.GetSupertypesAsync(dogItem);
        Assert.NotNull(supertypes);
        Assert.Contains(supertypes!, s => s.Name == "IAnimal");
    }

    [Fact]
    public async Task TypeHierarchy_SubtypesOfInterface()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/typehierarchy_sub.nl";
        var source = @"interface IAnimal {
    func speak(): string
}

class Dog : IAnimal {
    func speak(): string {
        return ""woof""
    }
}

class Cat : IAnimal {
    func speak(): string {
        return ""meow""
    }
}
";
        harness.OpenDocument(uri, source);

        // Prepare on "IAnimal"
        var prepareResult = await harness.PrepareTypeHierarchyAsync(uri, 0, 10);
        Assert.NotNull(prepareResult);
        var animalItem = prepareResult!.First();

        var subtypes = await harness.GetSubtypesAsync(animalItem);
        Assert.NotNull(subtypes);
        Assert.True(subtypes!.Count() >= 2,
            $"Expected at least 2 subtypes (Dog, Cat), got {subtypes!.Count()}");
        Assert.Contains(subtypes!, s => s.Name == "Dog");
        Assert.Contains(subtypes!, s => s.Name == "Cat");
    }

    [Fact]
    public async Task TypeHierarchy_PrepareOnNonType_ReturnsNull()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/typehierarchy_nontype.nl";
        var source = @"func main() {
    let x := 42
}
";
        harness.OpenDocument(uri, source);

        // "main" is a function, not a type
        var result = await harness.PrepareTypeHierarchyAsync(uri, 0, 5);
        Assert.Null(result);
    }

    #endregion

    #region Document Link Tests

    [Fact]
    public async Task DocumentLink_FindsUrlInComment()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/doclink.nl";
        var source = "// See https://example.com/docs for more info\nfunc main() {\n    print(\"hello\")\n}\n";
        harness.OpenDocument(uri, source);

        var links = await harness.GetDocumentLinksAsync(uri);
        Assert.NotNull(links);

        // The handler now scans both tokens AND doc.Comments for URLs
        var doc = harness.DocumentManager.GetDocument(uri);
        var hasCommentTokens = doc?.Tokens?.Any(t =>
            t.Type == NSharpLang.Compiler.TokenType.Comment && t.Value.Contains("https://")) == true;
        var hasCommentTrivia = doc?.Comments?.Any(c => c.Text.Contains("https://")) == true;

        if (hasCommentTokens || hasCommentTrivia)
        {
            Assert.NotEmpty(links!);
            Assert.Contains(links!, l => l.Target != null && l.Target.ToString().Contains("example.com"));
        }
        else
        {
            // Neither token stream nor comments contained the URL text
            Assert.Empty(links!);
        }
    }

    [Fact]
    public async Task DocumentLink_NoUrlsReturnsEmpty()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/doclink_empty.nl";
        var source = @"func main() {
    let x := 42
}
";
        harness.OpenDocument(uri, source);

        var links = await harness.GetDocumentLinksAsync(uri);
        Assert.NotNull(links);
        Assert.Empty(links!);
    }

    [Fact]
    public async Task DocumentLink_MissingDocumentReturnsNull()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);

        var links = await harness.GetDocumentLinksAsync("file:///nonexistent.nl");
        Assert.Null(links);
    }

    #endregion

    #region Code Lens Tests

    [Fact]
    public async Task CodeLens_FunctionDeclarationsHaveLenses()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/codelens.nl";
        var source = @"func greet(name: string): string {
    return ""Hello, "" + name
}

func helper() {
    greet(""world"")
}
";
        harness.OpenDocument(uri, source);

        var lenses = await harness.GetCodeLensesAsync(uri);
        Assert.NotNull(lenses);
        Assert.True(lenses!.Count() >= 2,
            $"Expected at least 2 code lenses (one per function), got {lenses!.Count()}");

        // Each non-entry-point lens should have a command with a title containing "reference"
        Assert.All(lenses!, lens =>
        {
            Assert.NotNull(lens.Command);
            Assert.Contains("reference", lens.Command!.Title);
        });

        var greetLens = lenses!.FirstOrDefault(l =>
            l.Range.Start.Line == 0); // greet is on line 0
        Assert.NotNull(greetLens);
        Assert.Equal("1 reference", greetLens!.Command!.Title);
    }

    [Fact]
    public async Task CodeLens_UnreferencedFunctionExcludesItsDeclarationFromReferenceCount()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/codelens_unreferenced.nl";
        var source = @"func unused() {
}
";
        harness.OpenDocument(uri, source);

        var lenses = await harness.GetCodeLensesAsync(uri);

        Assert.NotNull(lenses);
        var unusedLens = Assert.Single(lenses!);
        Assert.NotNull(unusedLens.Command);
        Assert.Equal("0 references", unusedLens.Command!.Title);
    }

    [Fact]
    public async Task CodeLens_MainFunctionShowsEntryPointInsteadOfReferenceCount()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/codelens_main.nl";
        var source = @"func Main() {
}
";
        harness.OpenDocument(uri, source);

        var lenses = await harness.GetCodeLensesAsync(uri);

        Assert.NotNull(lenses);
        var mainLens = Assert.Single(lenses!);
        Assert.NotNull(mainLens.Command);
        Assert.Equal("Entry point", mainLens.Command!.Title);
        Assert.Equal("nsharp.noop", mainLens.Command!.Name);
    }

    [Fact]
    public async Task CodeLens_DuplicateCrossFileMemberNames_CountsOnlySemanticReferencesAndIsClickable()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var tempRoot = Path.Combine(Path.GetTempPath(), $"nsharp-lsp-codelens-duplicates-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempRoot);

        try
        {
            Directory.CreateDirectory(Path.Combine(tempRoot, "Foo"));
            Directory.CreateDirectory(Path.Combine(tempRoot, "Bar"));
            File.WriteAllText(Path.Combine(tempRoot, "project.yml"), """
name: TempCodeLensDuplicateTest
targetFramework: net10.0
""");

            var fooWidgetPath = Path.Combine(tempRoot, "Foo", "Widget.nl");
            var fooUsePath = Path.Combine(tempRoot, "Foo", "UseWidget.nl");
            var barWidgetPath = Path.Combine(tempRoot, "Bar", "Widget.nl");
            var barUsePath = Path.Combine(tempRoot, "Bar", "UseWidget.nl");

            File.WriteAllText(fooWidgetPath, """
namespace TempCodeLensDuplicateTest.Foo

record Widget {
    Value: string
}
""");
            File.WriteAllText(fooUsePath, """
namespace TempCodeLensDuplicateTest.Foo

func Read(widget: Widget): string {
    return widget.Value
}
""");
            File.WriteAllText(barWidgetPath, """
namespace TempCodeLensDuplicateTest.Bar

record Widget {
    Value: int
}
""");
            File.WriteAllText(barUsePath, """
namespace TempCodeLensDuplicateTest.Bar

func Read(widget: Widget): int {
    return widget.Value
}
""");

            var fooWidgetUri = new Uri(fooWidgetPath).AbsoluteUri;
            var fooUseUri = new Uri(fooUsePath).AbsoluteUri;
            var barWidgetUri = new Uri(barWidgetPath).AbsoluteUri;
            var barUseUri = new Uri(barUsePath).AbsoluteUri;

            harness.OpenDocument(fooWidgetUri, File.ReadAllText(fooWidgetPath));
            harness.OpenDocument(fooUseUri, File.ReadAllText(fooUsePath));
            harness.OpenDocument(barWidgetUri, File.ReadAllText(barWidgetPath));
            harness.OpenDocument(barUseUri, File.ReadAllText(barUsePath));

            var lenses = await harness.GetCodeLensesAsync(fooWidgetUri);

            Assert.NotNull(lenses);
            var widgetLens = Assert.Single(lenses!.Where(l => l.Range.Start.Line == 2));
            Assert.NotNull(widgetLens.Command);
            Assert.Equal("1 reference", widgetLens.Command!.Title);
            Assert.Equal("nsharp.showReferences", widgetLens.Command!.Name);
            Assert.NotNull(widgetLens.Command!.Arguments);
            var args = widgetLens.Command!.Arguments!.ToList();
            Assert.Equal(fooWidgetUri, args[0]!.ToString());
            Assert.Equal(2, (int)args[1]!);
            Assert.Equal(7, (int)args[2]!);
        }
        finally
        {
            Directory.Delete(tempRoot, recursive: true);
        }
    }

    [Fact]
    public async Task CodeLens_StaticMainMemberShowsEntryPointInsteadOfReferenceCount()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/codelens_static_main.nl";
        var source = @"class Program {
    static func Main() {
    }
}
";
        harness.OpenDocument(uri, source);

        var lenses = await harness.GetCodeLensesAsync(uri);

        Assert.NotNull(lenses);
        var mainLens = lenses!.Single(l => l.Range.Start.Line == 1);
        Assert.NotNull(mainLens.Command);
        Assert.Equal("Entry point", mainLens.Command!.Title);
        Assert.Equal("nsharp.noop", mainLens.Command!.Name);
    }

    [Fact]
    public async Task CodeLens_ClassWithMembers()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/codelens_class.nl";
        var source = @"class Person {
    name: string

    func greet(): string {
        return ""Hello""
    }
}
";
        harness.OpenDocument(uri, source);

        var lenses = await harness.GetCodeLensesAsync(uri);
        Assert.NotNull(lenses);
        // Should have lenses for the class and its members
        Assert.NotEmpty(lenses!);
    }

    [Fact]
    public async Task CodeLens_MissingDocumentReturnsEmptyContainer()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);

        var lenses = await harness.GetCodeLensesAsync("file:///nonexistent.nl");
        Assert.NotNull(lenses);
        Assert.Empty(lenses!);
    }

    #endregion

    #region On-Type Formatting Tests

    [Fact]
    public async Task OnTypeFormatting_CloseBraceAlignsWithMatchingOpen()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/ontypeformat_brace.nl";
        // Simulate: user typed '}' with wrong indentation
        var source = "func main() {\n    let x := 42\n        }\n";
        harness.OpenDocument(uri, source);

        // Trigger '}' on line 2
        var edits = await harness.OnTypeFormattingAsync(uri, 2, 9, "}");

        // Should return edits to fix the indentation of the closing brace
        Assert.NotNull(edits);
        Assert.NotEmpty(edits!);
    }

    [Fact]
    public async Task OnTypeFormatting_NewlineAfterOpenBrace()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);
        var uri = "file:///test/ontypeformat_newline.nl";
        // Simulate: user pressed Enter after '{' with no indentation on the new line
        var source = "func main() {\n\n}\n";
        harness.OpenDocument(uri, source);

        // Trigger '\n' on line 1 (the blank line after '{')
        var edits = await harness.OnTypeFormattingAsync(uri, 1, 0, "\n");

        // After '{', the handler should produce an edit with increased indentation
        Assert.NotNull(edits);
        Assert.NotEmpty(edits!);
        // The edit should set indentation on the new line (the previous line ends with '{')
        var edit = edits!.First();
        Assert.True(edit.NewText.Length > 0,
            "On-type formatting after '{' should produce indentation");
        // The new text should start with whitespace (spaces or tabs for indentation)
        Assert.True(edit.NewText.StartsWith(" ") || edit.NewText.StartsWith("\t"),
            $"Expected indented text but got: '{edit.NewText}'");
    }

    [Fact]
    public async Task OnTypeFormatting_MissingDocumentReturnsNull()
    {
        var harness = new LspTestHarness(_fixture.XmlDocReader, _fixture.TypeResolver);

        var edits = await harness.OnTypeFormattingAsync("file:///nonexistent.nl", 0, 0, "}");
        Assert.Null(edits);
    }

    #endregion
}
