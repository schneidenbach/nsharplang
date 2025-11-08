using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NewCLILang.Compiler;
using LanguageServer.Services;
using MediatR;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using OmniSharp.Extensions.LanguageServer.Protocol.Server;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace LanguageServer.Handlers;

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

        _documentManager.CloseDocument(uri);

        // Clear diagnostics for closed document
        _languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams
        {
            Uri = request.TextDocument.Uri,
            Diagnostics = new Container<Diagnostic>()
        });

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
        var doc = _documentManager.GetDocument(uri);
        if (doc?.Diagnostics == null) return;

        var diagnostics = doc.Diagnostics.Select(ConvertToDiagnostic).ToArray();

        _languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams
        {
            Uri = DocumentUri.From(uri),
            Diagnostics = new Container<Diagnostic>(diagnostics)
        });

        _logger.LogInformation("Published {Count} diagnostics for {Uri}", diagnostics.Length, uri);
    }

    private Diagnostic ConvertToDiagnostic(CompilerError error)
    {
        // Convert compiler error to LSP diagnostic
        var line = Math.Max(0, error.Line - 1); // LSP is 0-indexed
        var column = Math.Max(0, error.Column - 1);

        return new Diagnostic
        {
            Range = new LspRange(line, column, line, column + 10), // Approximate range
            Severity = error.Severity == ErrorSeverity.Warning ? DiagnosticSeverity.Warning : DiagnosticSeverity.Error,
            Code = $"NL{(int)error.Code:D3}",
            Source = "N#",
            Message = error.Message
        };
    }
}
