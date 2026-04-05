using System;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/formatting requests to format N# source files
/// </summary>
public class DocumentFormattingHandler : DocumentFormattingHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<DocumentFormattingHandler> _logger;

    public DocumentFormattingHandler(
        DocumentManager documentManager,
        ILogger<DocumentFormattingHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<TextEditContainer?> Handle(
        DocumentFormattingParams request,
        CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null || doc.CompilationUnit == null)
        {
            _logger.LogDebug("Skipping formatting for {Uri}: document or AST unavailable", uri);
            return Task.FromResult<TextEditContainer?>(null);
        }

        var config = new FormatterConfig
        {
            IndentSize = request.Options.TabSize,
            UseSpaces = request.Options.InsertSpaces
        };

        string formattedText;
        try
        {
            var result = new Formatter(config).FormatSafe(doc.Text, doc.CompilationUnit, doc.Comments, uri);
            foreach (var warning in result.Warnings)
            {
                _logger.LogWarning("Formatter safety warning for {Uri}: {Warning}", uri, warning);
            }
            if (!result.Success)
            {
                _logger.LogWarning("Formatting aborted for {Uri}: safety checks failed", uri);
                return Task.FromResult<TextEditContainer?>(null);
            }
            formattedText = result.Text;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Formatting failed for {Uri}", uri);
            return Task.FromResult<TextEditContainer?>(null);
        }

        if (formattedText == doc.Text)
        {
            _logger.LogDebug("Document {Uri} is already formatted", uri);
            return Task.FromResult<TextEditContainer?>(new TextEditContainer());
        }

        var lines = doc.Text.Split('\n');
        var lastLine = lines.Length - 1;
        var lastLineLength = lines[lastLine].Length;

        var fullDocumentRange = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
            0, 0, lastLine, lastLineLength);

        _logger.LogInformation("Formatted document {Uri}", uri);

        return Task.FromResult<TextEditContainer?>(new TextEditContainer(
            new OmniSharp.Extensions.LanguageServer.Protocol.Models.TextEdit
            {
                Range = fullDocumentRange,
                NewText = formattedText
            }
        ));
    }

    protected override DocumentFormattingRegistrationOptions CreateRegistrationOptions(
        DocumentFormattingCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DocumentFormattingRegistrationOptions();
    }
}
