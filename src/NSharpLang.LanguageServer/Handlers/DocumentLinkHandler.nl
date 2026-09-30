namespace NSharpLang.LanguageServer.Handlers

import System
import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles textDocument/documentLink requests to detect clickable URLs in comments and string
// literals.
//
// WHICH spans are links is N#-owned by `EditorDocumentLinkFacts`: the token kinds that are
// searched, the comment trivia that is searched beside them, the order of the two, and the walk
// that places a URL found on a later line of a block comment. What is left here is the protocol —
// OmniSharp's DocumentLink, and `System.Uri`, which canonicalises the target.
class DocumentLinkHandler: DocumentLinkHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<DocumentLinkHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<DocumentLinkHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: DocumentLinkParams, cancellationToken: CancellationToken): Task<DocumentLinkContainer?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null || doc.Tokens == null {
            return Task.FromResult<DocumentLinkContainer?>(null)
        }

        links := new List<DocumentLink>()
        for row in EditorDocumentLinkFacts.LinkRows(doc.Tokens, doc.Comments) {
            parsedUri: Uri? = null
            if !Uri.TryCreate(row.Text, UriKind.Absolute, out parsedUri) {
                continue
            }

            target := parsedUri.ToString()
            links.Add(new DocumentLink {
                Range: new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    row.StartLine,
                    row.StartCharacter,
                    row.EndLine,
                    row.EndCharacter
                ),
                Target: target
            })
        }

        logger.LogDebug("Returning {Count} document links for {Uri}", links.Count, uri)
        return Task.FromResult<DocumentLinkContainer?>(new DocumentLinkContainer(links))
    }

    override func Handle(request: DocumentLink, cancellationToken: CancellationToken): Task<DocumentLink> {
        // Links are fully resolved in the initial request; return as-is
        return Task.FromResult(request)
    }

    protected override func CreateRegistrationOptions(
        capability: DocumentLinkCapability,
        clientCapabilities: ClientCapabilities
    ): DocumentLinkRegistrationOptions {
        return new DocumentLinkRegistrationOptions()
    }
}
