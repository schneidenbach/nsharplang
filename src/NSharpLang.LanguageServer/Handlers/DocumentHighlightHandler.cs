using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using LspRange = OmniSharp.Extensions.LanguageServer.Protocol.Models.Range;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles document highlight requests — when a user places the cursor on a symbol,
/// all occurrences of that symbol in the current file are highlighted.
///
/// WHICH occurrences are highlighted and WHICH of them is the declaration are N#-owned by
/// <c>EditorDocumentHighlightFacts</c>: the binding map answers for a whole project, and the
/// one-file filter, the case-insensitive file comparison and the 0-based arithmetic are that
/// owner's. What is left here is the protocol and the `file://` conversion, which needs a URI.
/// </summary>
public class DocumentHighlightHandler : DocumentHighlightHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<DocumentHighlightHandler> _logger;

    public DocumentHighlightHandler(DocumentManager documentManager, ILogger<DocumentHighlightHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<DocumentHighlightContainer?> Handle(DocumentHighlightParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Text == null)
        {
            return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer());
        }

        try
        {
            var line = request.Position.Line;
            var character = request.Position.Character;

            // Tier 1: Semantic highlights via BindingMap
            if (doc.Bindings != null)
            {
                var highlights = new List<DocumentHighlight>();
                foreach (var row in EditorDocumentHighlightFacts.HighlightRows(
                    doc.Bindings, ExtractFilePath(uri), line, character))
                {
                    highlights.Add(new DocumentHighlight
                    {
                        Kind = row.IsWrite ? DocumentHighlightKind.Write : DocumentHighlightKind.Read,
                        Range = new LspRange(row.Line, row.StartCharacter, row.Line, row.EndCharacter)
                    });
                }

                if (highlights.Count > 0)
                {
                    return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer(highlights));
                }
            }

            return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer());
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error handling document highlight");
            return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer());
        }
    }

    private static string? ExtractFilePath(string uri)
    {
        try
        {
            return new Uri(uri).LocalPath;
        }
        catch
        {
            // If URI parsing fails, return the raw URI stripped of the file:// prefix
            if (uri.StartsWith("file:///"))
                return uri.Substring("file:///".Length);
            return uri;
        }
    }

    protected override DocumentHighlightRegistrationOptions CreateRegistrationOptions(
        DocumentHighlightCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DocumentHighlightRegistrationOptions();
    }
}
