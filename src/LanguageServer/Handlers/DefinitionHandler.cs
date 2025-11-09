using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;

namespace LanguageServer.Handlers;

/// <summary>
/// Handles go-to-definition requests (F12 in VS Code)
/// </summary>
public class DefinitionHandler : DefinitionHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<DefinitionHandler> _logger;

    public DefinitionHandler(DocumentManager documentManager, ILogger<DefinitionHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<LocationOrLocationLinks?> Handle(DefinitionParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<LocationOrLocationLinks?>(null);
        }

        try
        {
            // Get the word at the cursor position
            var word = GetWordAtPosition(doc.Text, request.Position.Line, request.Position.Character);
            if (string.IsNullOrWhiteSpace(word))
            {
                return Task.FromResult<LocationOrLocationLinks?>(null);
            }

            _logger.LogDebug("Go to definition for: {Word}", word);

            // Look for the symbol in the current document
            if (doc.SymbolsInfo != null && doc.SymbolsInfo.TryGetValue(word, out var symbolInfo))
            {
                // For now, we don't have location information stored
                // This would require enhancing the DocumentManager to track declaration locations
                _logger.LogDebug("Found symbol {Word} but location tracking not implemented yet", word);
            }

            // TODO: Implement cross-file definition lookup
            // TODO: Implement external assembly metadata view

            return Task.FromResult<LocationOrLocationLinks?>(null);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling go to definition");
            return Task.FromResult<LocationOrLocationLinks?>(null);
        }
    }

    protected override DefinitionRegistrationOptions CreateRegistrationOptions(
        DefinitionCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DefinitionRegistrationOptions();
    }

    private string GetWordAtPosition(string text, int line, int character)
    {
        var lines = text.Split('\n');
        if (line >= lines.Length) return string.Empty;

        var lineText = lines[line];
        if (character >= lineText.Length) return string.Empty;

        // Find word boundaries
        int start = character;
        while (start > 0 && IsIdentifierChar(lineText[start - 1]))
        {
            start--;
        }

        int end = character;
        while (end < lineText.Length && IsIdentifierChar(lineText[end]))
        {
            end++;
        }

        return lineText.Substring(start, end - start);
    }

    private bool IsIdentifierChar(char c)
    {
        return char.IsLetterOrDigit(c) || c == '_';
    }
}
