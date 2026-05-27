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
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;
using LspDiagnostic = OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic;
using LspDiagnosticSeverity = OmniSharp.Extensions.LanguageServer.Protocol.Models.DiagnosticSeverity;
using CompilerDiagnostic = NSharpLang.Compiler.Diagnostic;
using DiagnosticSeverity = NSharpLang.Compiler.DiagnosticSeverity;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles text document synchronization (open, change, close)
/// </summary>
public class TextDocumentHandler : TextDocumentSyncHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILanguageServerFacade _languageServer;
    private readonly ILogger<TextDocumentHandler> _logger;
    private string? _currentDiagnosticUri; // Set during PublishDiagnostics for token length lookup

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
            _currentDiagnosticUri = publication.Uri;

            var allDiagnostics = new List<LspDiagnostic>();

            allDiagnostics.AddRange(publication.CompilerDiagnostics.Select(ConvertCompilerErrorToDiagnostic));
            allDiagnostics.AddRange(publication.LinterDiagnostics.Select(ConvertLinterDiagnosticToDiagnostic));

            _languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams
            {
                Uri = DocumentUri.From(publication.Uri),
                Diagnostics = new Container<LspDiagnostic>(allDiagnostics)
            });

            _logger.LogInformation("Published {Count} diagnostics for {Uri}", allDiagnostics.Count, publication.Uri);
        }
    }

    private LspDiagnostic ConvertCompilerErrorToDiagnostic(CompilerError error)
    {
        // Convert compiler error to LSP diagnostic
        var line = Math.Max(0, error.Line - 1); // LSP is 0-indexed
        var column = Math.Max(0, error.Column - 1);

        var length = GetTokenLengthAtPosition(error, line, column);

        return new LspDiagnostic
        {
            Range = new LspRange(line, column, line, column + length),
            Severity = error.Severity == ErrorSeverity.Warning ? LspDiagnosticSeverity.Warning : LspDiagnosticSeverity.Error,
            Code = error.DiagnosticId,
            Source = "N#",
            Message = error.FormatForTooling(includeCode: true, includeLocation: false)
        };
    }

    private int GetTokenLengthAtPosition(CompilerError error, int line0, int column0)
    {
        var length = Math.Max(1, error.Length);

        var uri = _currentDiagnosticUri;
        if (uri != null)
        {
            var doc = _documentManager.GetDocument(uri);
            if (doc?.Text != null)
            {
                var lines = doc.Text.Split('\n');
                if (line0 < lines.Length)
                {
                    var lineText = lines[line0];
                    if (column0 < lineText.Length)
                    {
                        // Find the end of the current token (identifier or keyword)
                        int end = column0;
                        while (end < lineText.Length && (char.IsLetterOrDigit(lineText[end]) || lineText[end] == '_'))
                            end++;
                        if (end > column0)
                            length = Math.Max(length, end - column0);
                    }
                }
            }
        }

        return length;
    }

    private LspDiagnostic ConvertLinterDiagnosticToDiagnostic(CompilerDiagnostic diagnostic)
    {
        // Convert linter diagnostic to LSP diagnostic
        var line = Math.Max(0, diagnostic.Location.Line - 1); // LSP is 0-indexed
        var column = Math.Max(0, diagnostic.Location.Column - 1); // LSP columns are also 0-indexed

        var severity = diagnostic.Severity switch
        {
            DiagnosticSeverity.Error => LspDiagnosticSeverity.Error,
            DiagnosticSeverity.Warning => LspDiagnosticSeverity.Warning,
            DiagnosticSeverity.Info => LspDiagnosticSeverity.Information,
            _ => LspDiagnosticSeverity.Warning
        };

        var length = 1;
        if (_currentDiagnosticUri != null)
        {
            var doc = _documentManager.GetDocument(_currentDiagnosticUri);
            if (doc?.Text != null)
            {
                var lines = doc.Text.Split('\n');
                if (line < lines.Length && column < lines[line].Length)
                {
                    int end = column;
                    while (end < lines[line].Length && (char.IsLetterOrDigit(lines[line][end]) || lines[line][end] == '_'))
                        end++;
                    if (end > column) length = end - column;
                }
            }
        }

        return new LspDiagnostic
        {
            Range = new LspRange(line, column, line, column + length),
            Severity = severity,
            Code = diagnostic.Code,
            Source = "N#",
            Message = diagnostic.Message
        };
    }
}
