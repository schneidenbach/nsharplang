using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging.Abstractions;
using NSharpLang.LanguageServer.Handlers;
using NSharpLang.LanguageServer.Services;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using Xunit;
using LspTextEdit = OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit;

namespace NSharpLang.Tests;

public class LanguageServerAutoImportTests
{
    private sealed class Harness
    {
        private readonly object _lock = new();
        private XmlDocReader? _xmlDocReader;
        private TypeResolver? _typeResolver;
        private DocumentManager? _documentManager;
        private CompletionHandler? _completionHandler;

        public XmlDocReader XmlDocReader
        {
            get
            {
                if (_xmlDocReader == null)
                {
                    lock (_lock)
                    {
                        _xmlDocReader ??= new XmlDocReader(NullLogger<XmlDocReader>.Instance);
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
                    lock (_lock)
                    {
                        _typeResolver ??= new TypeResolver(NullLogger<TypeResolver>.Instance, XmlDocReader);
                    }
                }

                return _typeResolver;
            }
        }

        public DocumentManager DocumentManager
        {
            get
            {
                if (_documentManager == null)
                {
                    lock (_lock)
                    {
                        _documentManager ??= new DocumentManager(NullLogger<DocumentManager>.Instance);
                    }
                }

                return _documentManager;
            }
        }

        public CompletionHandler CompletionHandler
        {
            get
            {
                if (_completionHandler == null)
                {
                    lock (_lock)
                    {
                        _completionHandler ??= new CompletionHandler(
                            DocumentManager,
                            TypeResolver,
                            NullLogger<CompletionHandler>.Instance);
                    }
                }

                return _completionHandler;
            }
        }
    }

    [Fact]
    public async Task Completion_ListAddsImportEdit_AfterNamespaceDeclarationAsync()
    {
        var harness = new Harness();
        var source = """
namespace Demo

func main() {
    Lis
}
""";

        var (uri, line, character) = CreateDocument(harness.DocumentManager, source, "Lis");

        var completion = await GetCompletionAsync(harness.CompletionHandler, uri, line, character);
        var item = Assert.Single(completion.Items.Where(i => i.Label == "List"));

        var edits = GetAdditionalTextEdits(item);
        Assert.Single(edits);

        var edit = edits[0];
        Assert.Equal(1, (int)edit.Range.Start.Line);
        Assert.Equal(0, (int)edit.Range.Start.Character);
        Assert.Equal("import System.Collections.Generic\n", edit.NewText);
    }

    [Fact]
    public async Task Completion_ListSkipsImportEdit_WhenNamespaceAlreadyImportedAsync()
    {
        var harness = new Harness();
        var source = """
import System.Collections.Generic

func main() {
    Lis
}
""";

        var (uri, line, character) = CreateDocument(harness.DocumentManager, source, "Lis");

        var completion = await GetCompletionAsync(harness.CompletionHandler, uri, line, character);
        var item = Assert.Single(completion.Items.Where(i => i.Label == "List"));

        var edits = GetAdditionalTextEdits(item);
        Assert.Empty(edits);
    }

    [Fact]
    public async Task Completion_ConsoleAddsImportSystem_WhenNotImportedAsync()
    {
        var harness = new Harness();
        var source = """
func main() {
    Cons
}
""";

        var (uri, line, character) = CreateDocument(harness.DocumentManager, source, "Cons");

        var completion = await GetCompletionAsync(harness.CompletionHandler, uri, line, character);
        var item = Assert.Single(completion.Items.Where(i => i.Label == "Console"));

        var edits = GetAdditionalTextEdits(item);
        Assert.Single(edits);

        var edit = edits[0];
        Assert.Equal(0, (int)edit.Range.Start.Line);
        Assert.Equal(0, (int)edit.Range.Start.Character);
        Assert.Equal("import System\n", edit.NewText);
    }

    [Fact]
    public async Task Completion_ConsoleSkipsImport_WhenSystemAlreadyImportedAsync()
    {
        var harness = new Harness();
        var source = """
import System

func main() {
    Cons
}
""";

        var (uri, line, character) = CreateDocument(harness.DocumentManager, source, "Cons");

        var completion = await GetCompletionAsync(harness.CompletionHandler, uri, line, character);
        var item = Assert.Single(completion.Items.Where(i => i.Label == "Console"));

        var edits = GetAdditionalTextEdits(item);
        Assert.Empty(edits);
    }

    [Fact]
    public async Task MemberCompletion_ConsoleDot_AddsImportSystem_WhenNotImportedAsync()
    {
        var harness = new Harness();
        var source = """
func main() {
    Console.
}
""";

        var (uri, line, character) = CreateDocumentAtDot(harness.DocumentManager, source);

        var completion = await GetMemberCompletionAsync(harness.CompletionHandler, uri, line, character);
        Assert.NotEmpty(completion.Items);

        // All member items should carry the auto-import edit
        var writeLineItem = completion.Items.FirstOrDefault(i => i.Label == "WriteLine");
        Assert.NotNull(writeLineItem);

        var edits = GetAdditionalTextEdits(writeLineItem!);
        Assert.Single(edits);

        var edit = edits[0];
        Assert.Equal(0, (int)edit.Range.Start.Line);
        Assert.Equal(0, (int)edit.Range.Start.Character);
        Assert.Equal("import System\n", edit.NewText);
    }

    [Fact]
    public async Task MemberCompletion_ConsoleDot_SkipsImport_WhenSystemAlreadyImportedAsync()
    {
        var harness = new Harness();
        var source = """
import System

func main() {
    Console.
}
""";

        var (uri, line, character) = CreateDocumentAtDot(harness.DocumentManager, source);

        var completion = await GetMemberCompletionAsync(harness.CompletionHandler, uri, line, character);
        Assert.NotEmpty(completion.Items);

        var writeLineItem = completion.Items.FirstOrDefault(i => i.Label == "WriteLine");
        Assert.NotNull(writeLineItem);

        var edits = GetAdditionalTextEdits(writeLineItem!);
        Assert.Empty(edits);
    }

    [Fact]
    public async Task MemberCompletion_ImportInsertedAfterExistingImportsAsync()
    {
        var harness = new Harness();
        var source = """
import System.Collections.Generic

func main() {
    Console.
}
""";

        var (uri, line, character) = CreateDocumentAtDot(harness.DocumentManager, source);

        var completion = await GetMemberCompletionAsync(harness.CompletionHandler, uri, line, character);
        Assert.NotEmpty(completion.Items);

        var writeLineItem = completion.Items.FirstOrDefault(i => i.Label == "WriteLine");
        Assert.NotNull(writeLineItem);

        var edits = GetAdditionalTextEdits(writeLineItem!);
        Assert.Single(edits);

        // Should be inserted after the existing import (line 1, 0-indexed)
        var edit = edits[0];
        Assert.Equal(1, (int)edit.Range.Start.Line);
        Assert.Equal(0, (int)edit.Range.Start.Character);
        Assert.Equal("import System\n", edit.NewText);
    }

    private static (string Uri, int Line, int Character) CreateDocument(
        DocumentManager documentManager, string source, string target)
    {
        var filePath = Path.Combine(Path.GetTempPath(), $"nsharp-auto-import-{Guid.NewGuid():N}.nl");
        var uri = DocumentUri.From(new Uri(filePath).AbsoluteUri).ToString();
        documentManager.UpdateDocument(uri, source, 1);

        var lines = source.Split('\n');
        var targetLine = Array.FindIndex(lines, line => line.Contains(target, StringComparison.Ordinal));
        Assert.True(targetLine >= 0, $"Test source must contain the completion target text '{target}'.");

        var character = lines[targetLine].IndexOf(target, StringComparison.Ordinal) + target.Length;
        return (uri, targetLine, character);
    }

    private static (string Uri, int Line, int Character) CreateDocumentAtDot(
        DocumentManager documentManager, string source)
    {
        var filePath = Path.Combine(Path.GetTempPath(), $"nsharp-auto-import-{Guid.NewGuid():N}.nl");
        var uri = DocumentUri.From(new Uri(filePath).AbsoluteUri).ToString();
        documentManager.UpdateDocument(uri, source, 1);

        var lines = source.Split('\n');
        var targetLine = Array.FindIndex(lines, line => line.Contains(".", StringComparison.Ordinal)
            && !line.TrimStart().StartsWith("import", StringComparison.Ordinal));
        Assert.True(targetLine >= 0, "Test source must contain a dot for member completion.");

        var dotIndex = lines[targetLine].IndexOf('.', StringComparison.Ordinal);
        // Position after the dot
        var character = dotIndex + 1;
        return (uri, targetLine, character);
    }

    private static async Task<CompletionList> GetCompletionAsync(
        CompletionHandler completionHandler,
        string uri,
        int line,
        int character)
    {
        var request = new CompletionParams
        {
            TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
            Position = new Position(line, character)
        };

        var response = await completionHandler.Handle(request, CancellationToken.None);
        Assert.NotNull(response);
        return response;
    }

    private static async Task<CompletionList> GetMemberCompletionAsync(
        CompletionHandler completionHandler,
        string uri,
        int line,
        int character)
    {
        var request = new CompletionParams
        {
            TextDocument = new TextDocumentIdentifier(DocumentUri.From(uri)),
            Position = new Position(line, character),
            Context = new CompletionContext
            {
                TriggerKind = CompletionTriggerKind.TriggerCharacter,
                TriggerCharacter = "."
            }
        };

        var response = await completionHandler.Handle(request, CancellationToken.None);
        Assert.NotNull(response);
        return response;
    }

    private static IReadOnlyList<LspTextEdit> GetAdditionalTextEdits(CompletionItem item)
    {
        return item.AdditionalTextEdits is { } additionalTextEdits
            ? additionalTextEdits.ToList()
            : Array.Empty<LspTextEdit>();
    }
}
