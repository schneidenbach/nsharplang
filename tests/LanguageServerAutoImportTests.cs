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
        private TypeResolver? _typeResolver;
        private DocumentManager? _documentManager;
        private CompletionHandler? _completionHandler;

        public TypeResolver TypeResolver
        {
            get
            {
                if (_typeResolver == null)
                {
                    lock (_lock)
                    {
                        _typeResolver ??= new TypeResolver(NullLogger<TypeResolver>.Instance);
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

    private static (string Uri, int Line, int Character) OpenDocumentAtPath(
        DocumentManager documentManager,
        string filePath,
        string source,
        string target)
    {
        var uri = OpenDocumentAtPath(documentManager, filePath, source);
        var lines = source.Split('\n');
        var targetLine = Array.FindIndex(lines, line => line.Contains(target, StringComparison.Ordinal));
        Assert.True(targetLine >= 0, $"Test source must contain the completion target text '{target}'.");

        var character = lines[targetLine].IndexOf(target, StringComparison.Ordinal) + target.Length;
        return (uri, targetLine, character);
    }

    private static string OpenDocumentAtPath(DocumentManager documentManager, string filePath, string source)
    {
        var uri = DocumentUri.From(new Uri(filePath).AbsoluteUri).ToString();
        documentManager.MarkEditorOpen(uri);
        documentManager.UpdateDocument(uri, source, 1);
        return uri;
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

    private static IReadOnlyList<LspTextEdit> GetAdditionalTextEdits(CompletionItem item)
    {
        return item.AdditionalTextEdits is { } additionalTextEdits
            ? additionalTextEdits.ToList()
            : Array.Empty<LspTextEdit>();
    }
}
