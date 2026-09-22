namespace NSharpLang.LanguageServer.Handlers

import System
import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles go-to-implementation requests (Ctrl+F12 in VS Code).
// Finds all types that implement an interface or extend a base/abstract class.
//
// WHETHER the caret is on something that has implementations, WHICH declarations count as one, and
// the semantic check that keeps a same-spelled name in an unrelated file out, are all N#-owned by
// `EditorImplementationFacts`. What is left here is the protocol — the word under the caret, the
// walk over the open buffers with its cancellation check, and OmniSharp's Location.
class GoToImplementationHandler: ImplementationHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<GoToImplementationHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<GoToImplementationHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: ImplementationParams, cancellationToken: CancellationToken): Task<LocationOrLocationLinks?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null {
            return Task.FromResult<LocationOrLocationLinks?>(null)
        }

        line := request.Position.Line
        character := request.Position.Character

        try {
            word := EditorUtilities.GetWordAtPosition(doc.Text, line, character)
            if string.IsNullOrWhiteSpace(word) {
                return Task.FromResult<LocationOrLocationLinks?>(null)
            }

            logger.LogDebug("Go to implementation for: {Word}", word)

            targetKind := EditorImplementationFacts.TargetKind(doc.Symbols, word)
            if targetKind == EditorImplementationTarget.None {
                logger.LogDebug("Symbol '{Word}' is not an interface or class — skipping implementation search", word)
                return Task.FromResult<LocationOrLocationLinks?>(null)
            }

            rows := new List<EditorImplementorRow>()
            for candidate in documentManager.GetAllDocuments() {
                if cancellationToken.IsCancellationRequested {
                    break
                }

                EditorImplementationFacts.AppendImplementorRows(
                    candidate.CompilationUnit,
                    candidate.Symbols,
                    candidate.Uri,
                    word,
                    targetKind,
                    rows
                )
            }

            if rows.Count == 0 {
                return Task.FromResult<LocationOrLocationLinks?>(null)
            }

            locations := new List<LocationOrLocationLink>()
            for row in rows {
                range := new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                    row.Line,
                    row.StartCharacter,
                    row.Line,
                    row.EndCharacter
                )
                location := new OmniSharp.Extensions.LanguageServer.Protocol.Models.Location {
                    Uri: DocumentUri.From(row.Uri),
                    Range: range
                }
                locations.Add(new LocationOrLocationLink(location))
            }

            return Task.FromResult<LocationOrLocationLinks?>(new LocationOrLocationLinks(locations))
        } catch failure: Exception {
            logger.LogError(failure, "Error handling go to implementation")
            return Task.FromResult<LocationOrLocationLinks?>(null)
        }
    }

    protected override func CreateRegistrationOptions(
        capability: ImplementationCapability,
        clientCapabilities: ClientCapabilities
    ): ImplementationRegistrationOptions {
        return new ImplementationRegistrationOptions()
    }
}
