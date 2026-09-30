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

// Handles document highlight requests — when a user places the cursor on a symbol, all occurrences
// of that symbol in the current file are highlighted.
//
// WHICH occurrences are highlighted and WHICH of them is the declaration are N#-owned by
// `EditorDocumentHighlightFacts`: the binding map answers for a whole project, and the one-file
// filter, the case-insensitive file comparison and the 0-based arithmetic are that owner's. What is
// left here is the protocol and the `file://` conversion, which needs a URI.
class DocumentHighlightHandler: DocumentHighlightHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<DocumentHighlightHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<DocumentHighlightHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: DocumentHighlightParams, cancellationToken: CancellationToken): Task<DocumentHighlightContainer?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null {
            return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer())
        }

        try {
            line := request.Position.Line
            character := request.Position.Character

            // Tier 1: Semantic highlights via BindingMap
            bindings := doc.Bindings
            if bindings != null {
                highlights := new List<DocumentHighlight>()
                for row in EditorDocumentHighlightFacts.HighlightRows(bindings, extractFilePath(uri), line, character) {
                    kind := DocumentHighlightKind.Read
                    if row.IsWrite {
                        kind = DocumentHighlightKind.Write
                    }

                    highlights.Add(new DocumentHighlight {
                        Kind: kind,
                        Range: new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                            row.Line,
                            row.StartCharacter,
                            row.Line,
                            row.EndCharacter
                        )
                    })
                }

                if highlights.Count > 0 {
                    return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer(highlights))
                }
            }

            return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer())
        } catch failure: Exception {
            logger.LogError(failure, "Error handling document highlight")
            return Task.FromResult<DocumentHighlightContainer?>(new DocumentHighlightContainer())
        }
    }

    static func extractFilePath(uri: string): string? {
        try {
            return new Uri(uri).LocalPath
        } catch parseFailure: Exception {
            // If URI parsing fails, return the raw URI stripped of the file:// prefix
            if uri.StartsWith("file:///") {
                return uri.Substring("file:///".Length)
            }

            return uri
        }
    }

    protected override func CreateRegistrationOptions(
        capability: DocumentHighlightCapability,
        clientCapabilities: ClientCapabilities
    ): DocumentHighlightRegistrationOptions {
        return new DocumentHighlightRegistrationOptions()
    }
}
