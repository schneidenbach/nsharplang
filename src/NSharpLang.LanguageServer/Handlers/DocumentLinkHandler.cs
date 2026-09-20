using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using NSharpLang.LanguageServer.Services;
using Microsoft.Extensions.Logging;
using OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities;
using OmniSharp.Extensions.LanguageServer.Protocol.Document;
using OmniSharp.Extensions.LanguageServer.Protocol.Models;
using CodeIntel = NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.LanguageServer.Handlers;

/// <summary>
/// Handles textDocument/documentLink requests to detect clickable URLs
/// in comments and string literals.
///
/// WHICH spans are links is N#-owned by <c>EditorDocumentLinkFacts</c>: the token kinds that are
/// searched, the comment trivia that is searched beside them, the order of the two, and the walk
/// that places a URL found on a later line of a block comment. What is left here is the protocol —
/// OmniSharp's DocumentLink, and <c>System.Uri</c>, which canonicalises the target and which the
/// columnar backend cannot construct yet.
/// </summary>
public class DocumentLinkHandler : DocumentLinkHandlerBase
{
    private readonly DocumentManager _documentManager;
    private readonly ILogger<DocumentLinkHandler> _logger;

    public DocumentLinkHandler(DocumentManager documentManager, ILogger<DocumentLinkHandler> logger)
    {
        _documentManager = documentManager;
        _logger = logger;
    }

    public override Task<DocumentLinkContainer?> Handle(DocumentLinkParams request, CancellationToken cancellationToken)
    {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc?.Tokens == null)
        {
            return Task.FromResult<DocumentLinkContainer?>(null);
        }

        var links = new List<DocumentLink>();
        foreach (var row in CodeIntel.EditorDocumentLinkFacts.LinkRows(doc.Tokens, doc.Comments))
        {
            if (!Uri.TryCreate(row.Text, UriKind.Absolute, out var parsedUri))
            {
                continue;
            }

            links.Add(new DocumentLink
            {
                Range = new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    row.StartLine, row.StartCharacter, row.EndLine, row.EndCharacter),
                Target = parsedUri.ToString()
            });
        }

        _logger.LogDebug("Returning {Count} document links for {Uri}", links.Count, uri);
        return Task.FromResult<DocumentLinkContainer?>(new DocumentLinkContainer(links));
    }

    public override Task<DocumentLink> Handle(DocumentLink request, CancellationToken cancellationToken)
    {
        // Links are fully resolved in the initial request; return as-is
        return Task.FromResult(request);
    }

    protected override DocumentLinkRegistrationOptions CreateRegistrationOptions(
        DocumentLinkCapability capability,
        ClientCapabilities clientCapabilities)
    {
        return new DocumentLinkRegistrationOptions();
    }
}
