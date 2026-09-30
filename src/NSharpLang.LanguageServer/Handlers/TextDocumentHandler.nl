namespace NSharpLang.LanguageServer.Handlers

import System.Collections.Generic
import System.Linq
import System.Threading
import System.Threading.Tasks
import MediatR
import Microsoft.Extensions.Logging
import NSharpLang.Compiler
import NSharpLang.LanguageServer.Services
import OmniSharp.Extensions.LanguageServer.Protocol
import OmniSharp.Extensions.LanguageServer.Protocol.Client.Capabilities
import OmniSharp.Extensions.LanguageServer.Protocol.Document
import OmniSharp.Extensions.LanguageServer.Protocol.Models
import OmniSharp.Extensions.LanguageServer.Protocol.Server

// Handles text document synchronization (open, change, close)
class TextDocumentHandler: TextDocumentSyncHandlerBase {
    readonly documentManager: DocumentManager
    readonly languageServer: ILanguageServerFacade
    readonly logger: ILogger<TextDocumentHandler>

    constructor(
        documentManager: DocumentManager,
        languageServer: ILanguageServerFacade,
        logger: ILogger<TextDocumentHandler>
    ) {
        this.documentManager = documentManager
        this.languageServer = languageServer
        this.logger = logger
    }

    override func GetTextDocumentAttributes(uri: DocumentUri): TextDocumentAttributes {
        return new TextDocumentAttributes(uri, "nsharp")
    }

    override func Handle(request: DidOpenTextDocumentParams, token: CancellationToken): Task<Unit> {
        uri := request.TextDocument.Uri.ToString()
        text := request.TextDocument.Text
        version := request.TextDocument.Version ?? 0

        logger.LogInformation("Document opened: {Uri}", uri)

        documentManager.MarkEditorOpen(uri)
        documentManager.UpdateDocument(uri, text, version)
        publishDiagnostics(uri)

        return Unit.Task
    }

    override func Handle(request: DidChangeTextDocumentParams, token: CancellationToken): Task<Unit> {
        uri := request.TextDocument.Uri.ToString()

        // Full document sync - we receive the entire document content
        if request.ContentChanges.Any() {
            text := request.ContentChanges.First().Text
            version := request.TextDocument.Version ?? 0

            documentManager.UpdateDocument(uri, text, version)
            publishDiagnostics(uri)
        }

        return Unit.Task
    }

    override func Handle(request: DidSaveTextDocumentParams, token: CancellationToken): Task<Unit> {
        // Re-analyze on save to ensure diagnostics are up-to-date
        uri := request.TextDocument.Uri.ToString()
        logger.LogInformation("Document saved: {Uri}", uri)

        doc := documentManager.GetDocument(uri)
        if doc != null {
            publishDiagnostics(uri)
        }

        return Unit.Task
    }

    override func Handle(request: DidCloseTextDocumentParams, token: CancellationToken): Task<Unit> {
        uri := request.TextDocument.Uri.ToString()
        logger.LogInformation("Document closed: {Uri}", uri)

        reloadedUri := documentManager.HandleEditorClose(uri)

        if reloadedUri != null {
            // File was reloaded from disk — republish workspace diagnostics
            publishDiagnostics(reloadedUri)
        } else {
            // File was fully removed — clear diagnostics
            languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams {
                Uri: request.TextDocument.Uri,
                Diagnostics: new Container<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>()
            })
        }

        return Unit.Task
    }

    protected override func CreateRegistrationOptions(
        capability: TextSynchronizationCapability,
        clientCapabilities: ClientCapabilities
    ): TextDocumentSyncRegistrationOptions {
        // Default configuration - full sync
        return new TextDocumentSyncRegistrationOptions()
    }

    func publishDiagnostics(uri: string) {
        publications := documentManager.GetDiagnosticsToPublish(uri)
        for publication in publications {
            allDiagnostics := new List<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>()

            for error in publication.CompilerDiagnostics {
                allDiagnostics.Add(LspDiagnosticConverter.FromCompilerError(error))
            }

            for diagnostic in publication.LinterDiagnostics {
                allDiagnostics.Add(LspDiagnosticConverter.FromLinterDiagnostic(diagnostic))
            }

            languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams {
                Uri: DocumentUri.From(publication.Uri),
                Diagnostics: new Container<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>(allDiagnostics)
            })

            logger.LogInformation("Published {Count} diagnostics for {Uri}", allDiagnostics.Count, publication.Uri)
        }
    }
}
