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
            Diagnostics = new Container<LspDiagnostic>()
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
        if (doc == null) return;

        _currentDiagnosticUri = uri;
        var allDiagnostics = new List<LspDiagnostic>();

        // Add compiler diagnostics
        if (doc.Diagnostics != null)
        {
            allDiagnostics.AddRange(doc.Diagnostics.Select(ConvertCompilerErrorToDiagnostic));
        }

        // Add linter diagnostics
        if (doc.LinterDiagnostics != null)
        {
            allDiagnostics.AddRange(doc.LinterDiagnostics.Select(ConvertLinterDiagnosticToDiagnostic));
        }

        _languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams
        {
            Uri = DocumentUri.From(uri),
            Diagnostics = new Container<LspDiagnostic>(allDiagnostics)
        });

        _logger.LogInformation("Published {Count} diagnostics for {Uri}", allDiagnostics.Count, uri);
    }

    private LspDiagnostic ConvertCompilerErrorToDiagnostic(CompilerError error)
    {
        // Convert compiler error to LSP diagnostic
        var line = Math.Max(0, error.Line - 1); // LSP is 0-indexed
        var column = Math.Max(0, error.Column - 1);

        // Try to determine the actual token length at the error position
        int length = GetTokenLengthAtPosition(error, line, column);

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
        var fallbackLength = Math.Max(1, error.Length);

        // Try to extract a symbol name from the error message (e.g., "'name'", "identifier 'foo'")
        var quoteMatch = System.Text.RegularExpressions.Regex.Match(error.Message, @"'([^']+)'");
        if (quoteMatch.Success)
        {
            return Math.Max(fallbackLength, quoteMatch.Groups[1].Value.Length);
        }

        // Try to find the token in the source text at the error position
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
                            return Math.Max(fallbackLength, end - column0);
                    }
                }
            }
        }

        return fallbackLength;
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

        // Extract symbol name from message and find its actual position in source
        // Linter column positions can be inaccurate, so we search the source line
        int length = 1;
        var quoteMatch = System.Text.RegularExpressions.Regex.Match(diagnostic.Message, @"'([^']+)'");
        string? symbolName = quoteMatch.Success ? quoteMatch.Groups[1].Value : null;

        if (symbolName != null && _currentDiagnosticUri != null)
        {
            length = symbolName.Length;
            // Find the actual column of the symbol in the source line
            var doc = _documentManager.GetDocument(_currentDiagnosticUri);
            if (doc?.Text != null)
            {
                var lines = doc.Text.Split('\n');
                if (line < lines.Length)
                {
                    var idx = lines[line].IndexOf(symbolName, StringComparison.Ordinal);
                    if (idx >= 0)
                    {
                        column = idx; // Use the actual position, not the linter's
                    }
                }
            }
        }
        else if (_currentDiagnosticUri != null)
        {
            // No symbol in message — find the token at the reported position
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
