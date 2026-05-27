using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.LanguageServer.Services;
using MediatR;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using OmniSharp.Extensions.LanguageServer.Protocol.Server;
using LspDiagnostic = OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles text document synchronization (open, change, close)
/// </summary>
public class TextDocumentHandler : TextDocumentSyncHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILanguageServerFacade _languageServer;
    private readonly ILogger<TextDocumentHandler> _logger;

    public TextDocumentHandler(
        DocumentManager documentManager,
        ILanguageServerFacade languageServer,
        ILogger<TextDocumentHandler> logger)
    {
        _documentManager = documentManager;
        _languageServer = languageServer;
        _logger = logger;
    }

    public override TextDocumentAttributes GetTextDocumentAttributes(DocumentUri uri)
    {
        return new TextDocumentAttributes(uri, "nsharp");
    }

    public override Task<Unit> Handle(DidOpenTextDocumentParams request, CancellationToken token)
    {
        var uri = request.TextDocument.Uri.ToString();
        var text = request.TextDocument.Text;
        var version = request.TextDocument.Version ?? 0;

        _logger.LogInformation("Document opened: {Uri}", uri);

        _documentManager.MarkEditorOpen(uri);
        _documentManager.UpdateDocument(uri, text, version);
        PublishDiagnostics(uri);

        return Unit.Task;
    }

    public override Task<Unit> Handle(DidChangeTextDocumentParams request, CancellationToken token)
    {
        var uri = request.TextDocument.Uri.ToString();

        // Full document sync - we receive the entire document content
        if (request.ContentChanges.Any())
        {
            var text = request.ContentChanges.First().Text;
            var version = request.TextDocument.Version ?? 0;

            _documentManager.UpdateDocument(uri, text, version);
            PublishDiagnostics(uri);
        }

        return Unit.Task;
    }

    public override Task<Unit> Handle(DidSaveTextDocumentParams request, CancellationToken token)
    {
        // Re-analyze on save to ensure diagnostics are up-to-date
        var uri = request.TextDocument.Uri.ToString();
        _logger.LogInformation("Document saved: {Uri}", uri);

        var doc = _documentManager.GetDocument(uri);
        if (doc != null)
        {
            PublishDiagnostics(uri);
        }

        return Unit.Task;
    }

    public override Task<Unit> Handle(DidCloseTextDocumentParams request, CancellationToken token)
    {
        var uri = request.TextDocument.Uri.ToString();
        _logger.LogInformation("Document closed: {Uri}", uri);

        var reloadedUri = _documentManager.HandleEditorClose(uri);

        if (reloadedUri != null)
        {
            // File was reloaded from disk — republish workspace diagnostics
            PublishDiagnostics(reloadedUri);
        }
        else
        {
            // File was fully removed — clear diagnostics
            _languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams
            {
                Uri = request.TextDocument.Uri,
                Diagnostics = new Container<LspDiagnostic>()
            });
        }

        return Unit.Task;
    }

    protected override TextDocumentSyncRegistrationOptions CreateRegistrationOptions(
        TextSynchronizationCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new TextDocumentSyncRegistrationOptions
        {
            // Default configuration - full sync
        };
    }

    private void PublishDiagnostics(string uri)
    {
        var publications = _documentManager.GetDiagnosticsToPublish(uri);
        foreach (var publication in publications)
        {
            var allDiagnostics = new List<LspDiagnostic>();

            allDiagnostics.AddRange(publication.CompilerDiagnostics.Select(ConvertCompilerErrorToDiagnostic));
            allDiagnostics.AddRange(publication.LinterDiagnostics.Select(LspDiagnosticConverter.FromLinterDiagnostic));

            _languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams
            {
                Uri = DocumentUri.From(publication.Uri),
                Diagnostics = new Container<LspDiagnostic>(allDiagnostics)
            });

            _logger.LogInformation("Published {Count} diagnostics for {Uri}", allDiagnostics.Count, publication.Uri);
        }
    }

    private static LspDiagnostic ConvertCompilerErrorToDiagnostic(CompilerError error)
        => LspDiagnosticConverter.FromCompilerError(error);
}
