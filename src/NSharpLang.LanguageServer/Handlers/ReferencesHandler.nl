namespace NSharpLang.LanguageServer.Handlers

import System
import System.Collections.Generic
import System.Threading
import System.Threading.Tasks
import Microsoft.Extensions.Logging
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.JsonRpc.Server
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models

// Handles find-all-references requests (Shift+F12 in VS Code)
class ReferencesHandler: ReferencesHandlerBase {
    readonly documentManager: DocumentManager
    readonly logger: ILogger<ReferencesHandler>

    constructor(documentManager: DocumentManager, logger: ILogger<ReferencesHandler>) {
        this.documentManager = documentManager
        this.logger = logger
    }

    override func Handle(request: ReferenceParams, cancellationToken: CancellationToken): Task<LocationContainer?> {
        uri := request.TextDocument.Uri.ToString()
        doc := documentManager.GetDocument(uri)

        if doc == null {
            return Task.FromResult<LocationContainer?>(new LocationContainer())
        }

        line := request.Position.Line
        character := request.Position.Character

        try {
            word := EditorUtilities.GetWordAtPosition(doc.Text, line, character)
            if string.IsNullOrWhiteSpace(word) {
                return Task.FromResult<LocationContainer?>(new LocationContainer())
            }

            logger.LogDebug("Find references for: {Word}", word)

            // Try semantic cross-file resolution via CodeIntelligenceService
            projectReferences := documentManager.FindProjectReferences(uri, line, character)
            if projectReferences != null {
                projectRoot := documentManager.GetProjectRootForUri(uri)
                includeDeclaration := request.Context?.IncludeDeclaration ?? true

                locations := new List<OmniSharp.Extensions.LanguageServer.Protocol.Models.Location>()
                for reference in projectReferences {
                    if !includeDeclaration && reference.IsDefinition {
                        continue
                    }

                    filePath := documentManager.ResolveProjectFilePath(projectRoot, reference.File)
                    absoluteUri := new Uri(filePath).AbsoluteUri
                    range := new OmniSharp.Extensions.LanguageServer.Protocol.Models.Range(
                        reference.Line - 1,
                        reference.Column - 1,
                        reference.Line - 1,
                        reference.Column - 1 + Math.Max(1, reference.Length)
                    )
                    locations.Add(new OmniSharp.Extensions.LanguageServer.Protocol.Models.Location {
                        Uri: DocumentUri.From(absoluteUri),
                        Range: range
                    })
                }

                return Task.FromResult<LocationContainer?>(new LocationContainer(locations))
            }

            // A synchronized project snapshot is authoritative for references; do
            // not degrade to text search when the binding map has no precise target.
            if documentManager.HasSynchronizedProjectSnapshot(uri) {
                return Task.FromResult<LocationContainer?>(new LocationContainer())
            }

            if documentManager.HasSemanticProjectContext(uri) {
                throw referencesUnavailable(EditorRenameGuardFacts.ReferencesDegradedMessage(word))
            }

            return Task.FromResult<LocationContainer?>(new LocationContainer())
        } catch refused: RequestFailedException {
            throw refused
        } catch failure: Exception {
            logger.LogError(failure, "Error handling find references")
            return Task.FromResult<LocationContainer?>(new LocationContainer())
        }
    }

    protected override func CreateRegistrationOptions(
        capability: ReferenceCapability,
        clientCapabilities: ClientCapabilities
    ): ReferenceRegistrationOptions {
        return new ReferenceRegistrationOptions()
    }

    static func referencesUnavailable(message: string): RequestFailedException {
        return new RequestFailedException(
            ErrorCodes.RequestFailed,
            message,
            RequestFailedException.UnknownRequestId,
            null
        )
    }
}
