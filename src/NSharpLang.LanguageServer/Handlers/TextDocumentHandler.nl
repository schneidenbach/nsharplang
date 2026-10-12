namespace NSharpLang.LanguageServer.Handlers

import System
import System.Collections.Generic
import System.Linq
import System.Threading
import System.Threading.Tasks
import MediatR
import Microsoft.Extensions.Logging
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
    readonly pendingChangesLock: object
    readonly pendingChanges: Dictionary<string, CancellationTokenSource>

    constructor(
        documentManager: DocumentManager,
        languageServer: ILanguageServerFacade,
        logger: ILogger<TextDocumentHandler>
    ) {
        this.documentManager = documentManager
        this.languageServer = languageServer
        this.logger = logger
        pendingChangesLock = new Object()
        pendingChanges = new Dictionary<string, CancellationTokenSource>(StringComparer.Ordinal)
    }

    override func GetTextDocumentAttributes(uri: DocumentUri): TextDocumentAttributes {
        return new TextDocumentAttributes(uri, "nsharp")
    }

    override func Handle(request: DidOpenTextDocumentParams, _token: CancellationToken): Task<Unit> {
        uri := request.TextDocument.Uri.ToString()
        text := request.TextDocument.Text
        version := request.TextDocument.Version ?? 0

        logger.LogInformation("Document opened: {Uri}", uri)

        documentManager.MarkEditorOpen(uri)
        reused := documentManager.UpdateDocumentForOpen(uri, text, version)
        if reused && tryPublishCachedDiagnostics(uri) {
            return Unit.Task
        }

        publishDiagnostics(uri)

        return Unit.Task
    }

    override func Handle(request: DidChangeTextDocumentParams, _token: CancellationToken): Task<Unit> {
        uri := request.TextDocument.Uri.ToString()

        // Full document sync - we receive the entire document content
        if request.ContentChanges.Any() {
            text := request.ContentChanges.First().Text
            version := request.TextDocument.Version ?? 0

            documentManager.UpdateDocumentForChange(uri, text, version)
            projectBatchKey := documentManager.GetProjectRootForUri(uri)
            cancellation := new CancellationTokenSource()
            lock pendingChangesLock {
                previous: CancellationTokenSource? = null
                if pendingChanges.TryGetValue(projectBatchKey, out previous) && previous != null {
                    previous.Cancel()
                }
                pendingChanges[projectBatchKey] = cancellation
            }
            return publishChangedDocumentDiagnostics(uri, version, projectBatchKey, cancellation)
        }

        return Unit.Task
    }

    // A WorkspaceEdit is delivered as one didChange per document. Debounce by project so the
    // language server analyzes the complete editor buffer set once the edit batch has arrived,
    // instead of publishing diagnostics from a partially applied multi-file edit.
    private async func publishChangedDocumentDiagnostics(uri: string, version: int, projectBatchKey: string, cancellation: CancellationTokenSource): Task<Unit> {
        try {
            await Task.Delay(75, cancellation.Token)
            if cancellation.IsCancellationRequested {
                return Unit.Value
            }

            doc := documentManager.GetDocument(uri)
            if doc == null || doc.Version != version {
                return Unit.Value
            }

            publishDiagnostics(uri, cancellation.Token)
        } catch cancelled: TaskCanceledException {
            if !cancellation.IsCancellationRequested {
                throw cancelled
            }
        } finally {
            lock pendingChangesLock {
                current: CancellationTokenSource? = null
                if pendingChanges.TryGetValue(projectBatchKey, out current) && current != null && Object.ReferenceEquals(current, cancellation) {
                    pendingChanges.Remove(projectBatchKey)
                }
            }
            cancellation.Dispose()
        }

        return Unit.Value
    }

    override func Handle(request: DidSaveTextDocumentParams, token: CancellationToken): Task<Unit> {
        // Re-analyze on save to ensure diagnostics are up-to-date
        uri := request.TextDocument.Uri.ToString()
        logger.LogInformation("Document saved: {Uri}", uri)

        doc := documentManager.GetDocument(uri)
        if doc != null {
            publishDiagnostics(uri, token)
        }

        return Unit.Task
    }

    override func Handle(request: DidCloseTextDocumentParams, _token: CancellationToken): Task<Unit> {
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
        _capability: TextSynchronizationCapability,
        _clientCapabilities: ClientCapabilities
    ): TextDocumentSyncRegistrationOptions {
        // Default configuration - full sync
        return new TextDocumentSyncRegistrationOptions()
    }

    func publishDiagnostics(uri: string) {
        publishDiagnostics(uri, CancellationToken.None)
    }

    func publishDiagnostics(uri: string, token: CancellationToken) {
        publications := documentManager.GetDiagnosticsToPublish(uri)
        publishDiagnosticsList(publications, token)
    }

    private func tryPublishCachedDiagnostics(uri: string): bool {
        publication := documentManager.GetCachedDiagnosticsForOpen(uri)
        if publication == null {
            return false
        }

        publishDiagnosticPublication(publication ?? throw new InvalidOperationException("Cached diagnostics disappeared."), CancellationToken.None)
        return true
    }

    private func publishDiagnosticsList(publications: IReadOnlyList<DocumentDiagnosticsPublication>, token: CancellationToken): void {
        for publication in publications {
            if token.IsCancellationRequested {
                return
            }

            publishDiagnosticPublication(publication, token)
        }
    }

    private func publishDiagnosticPublication(publication: DocumentDiagnosticsPublication, token: CancellationToken): void {
        if token.IsCancellationRequested {
            return
        }

        allDiagnostics := new List<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>()
        for error in publication.CompilerDiagnostics {
            allDiagnostics.Add(LspDiagnosticConverter.FromCompilerError(error))
        }
        for diagnostic in publication.LinterDiagnostics {
            allDiagnostics.Add(LspDiagnosticConverter.FromLinterDiagnostic(diagnostic))
        }

        document := documentManager.GetDocument(publication.Uri)
        publishedVersion: int? = null
        if document != null {
            publishedVersion = document.Version
        }
        languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams {
            Uri: DocumentUri.From(publication.Uri),
            Version: publishedVersion,
            Diagnostics: new Container<OmniSharp.Extensions.LanguageServer.Protocol.Models.Diagnostic>(allDiagnostics)
        })
        logger.LogInformation("Published {Count} diagnostics for {Uri}", allDiagnostics.Count, publication.Uri)
    }
}
